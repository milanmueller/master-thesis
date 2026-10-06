#!/usr/bin/env bash
# Sweep the parse-only drivers over fuzzed instances, one parameter at a time,
# and plot the result.
#
# For every parameter configuration this script generates one instance with
# ./gen-instance.py, runs ./parsers/parse-llvm and ./parsers/parse-sml on it
# ROUNDS times each, and appends one row with the configuration and the
# averaged timers to a CSV. Afterwards ./render-graph.py draws one graph per
# parameter that varies. Build the parsers first with ./collect-parsers.sh.
#
# Dependencies: python3 for the generator, and matplotlib and pandas for the
# graphs; the devshell of ./flake.nix provides them.
#
#   ./run-sweep.sh -p RANGE -l RANGE -c RANGE -v RANGE [options]
#
# Every fuzzer parameter takes either a single fixed value N or a range with a
# default, MIN:MAX:STEP@DEFAULT (MAX inclusive). The script does one sweep per
# parameter that has a range: that parameter runs through its range while all
# others stay at their fixed value or their DEFAULT. It does not measure the
# cartesian product of the ranges. DEFAULT does not have to lie in the range;
# a configuration that belongs to several sweeps runs once. Without any range
# the script measures the single configuration of the fixed values.
#
#   ./run-sweep.sh -p 100 -l 1000:10000:1000@1000 -c 20 -v 4
#   ./run-sweep.sh -p 100 -l 1000 -c 1:101:10@21 -v 2:6:1@4 -r 5 -o results/c-v.csv
#
# The second call measures 11 + 5 - 1 = 15 configurations: c = 1..101 at
# v = 4, and v = 2..6 at c = 21; c = 21, v = 4 belongs to both sweeps.
#
# Options:
#   -p, --polys RANGE     number of input polynomials
#   -l, --steps RANGE     number of linear combination steps
#   -c, --digits RANGE    digits per coefficient
#   -v, --vars RANGE      number of variables (2^v monomials per polynomial)
#   -s, --summands RANGE  summands per linear combination (default: fixed 2)
#       --seed N          seed passed to the generator (default 0)
#   -r, --rounds N        runs per parser per configuration (default 3)
#   -o, --output FILE     CSV file (default results/sweep.csv)
#       --append          append to an existing CSV instead of refusing it
#   -f, --overwrite       replace an existing CSV instead of refusing it
#       --keep            keep the generated instances in ./instances; without
#                         it the script removes every instance it generates,
#                         also when a parser fails or the sweep is interrupted
#       --no-plot         do not run ./render-graph.py
#
# CSV columns:
#   p, l, c, v, s, seed       the configuration (see ./gen-instance.py)
#   size_bytes                total size of the three files
#   rounds                    runs averaged per parser
#   llvm_<key>, sml_<key>     mean of each timer the driver reports, in
#                             seconds: polys_s, proof_s, spec_s, total_s, and
#                             lex_s (LLVM only) or gc_s (SML only)
#   llvm_total_s_std,         sample standard deviation of total_s over the
#   sml_total_s_std           rounds (0 for a single round)
#
# The two parsers alternate within a round, so that drift of the machine
# affects both alike. A row is written as soon as its configuration is done; an
# interrupted sweep keeps what it measured.
#
# Set RUN_PREFIX to pin the runs to one core: RUN_PREFIX="taskset -c 2".
# Set GRAPH_ARGS to pass options through to ./render-graph.py:
# GRAPH_ARGS="--log --fix c=20".
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$EVAL_DIR/parsers"
INST="$EVAL_DIR/instances"

PARSERS=(llvm sml)
# The timers each driver reports, in CSV order.
LLVM_KEYS="polys_s proof_s spec_s total_s lex_s"
SML_KEYS="polys_s proof_s spec_s total_s gc_s"

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info() { printf '%s\n' "$*" >&2; }
die()  { red "error: $*"; exit 1; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '$d'; }

# --- arguments -------------------------------------------------------------

polys= steps= digits= vars= summands=2
seed=0
rounds=3
output="$EVAL_DIR/results/sweep.csv"
append=false
overwrite=false
keep=false
plot=true

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    -p|--polys)    polys="${2:?--polys needs a value}"; shift 2 ;;
    -l|--steps)    steps="${2:?--steps needs a value}"; shift 2 ;;
    -c|--digits)   digits="${2:?--digits needs a value}"; shift 2 ;;
    -v|--vars)     vars="${2:?--vars needs a value}"; shift 2 ;;
    -s|--summands) summands="${2:?--summands needs a value}"; shift 2 ;;
    --seed)        seed="${2:?--seed needs a value}"; shift 2 ;;
    -r|--rounds)   rounds="${2:?--rounds needs a value}"; shift 2 ;;
    -o|--output)   output="${2:?--output needs a value}"; shift 2 ;;
    --append)      append=true; shift ;;
    -f|--overwrite) overwrite=true; shift ;;
    --keep)        keep=true; shift ;;
    --no-plot)     plot=false; shift ;;
    *)             die "unknown argument '$1' (try --help)" ;;
  esac
done

# parse NAME TEXT VALUES DEFAULT: 'N' or 'MIN:MAX:STEP@DEFAULT' -> the array
# VALUES of swept values (MAX inclusive; empty for a fixed N) and the value
# DEFAULT that the parameter keeps during the sweeps of the others.
parse() {
  local name="$1" text="$2"
  local -n values="$3" default="$4"
  [ -n "$text" ] || die "--$name is required (try --help)"
  if [[ "$text" =~ ^[0-9]+$ ]]; then
    values=()
    default="$text"
  elif [[ "$text" =~ ^([0-9]+):([0-9]+):([0-9]+)@([0-9]+)$ ]]; then
    local lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[2]}" step="${BASH_REMATCH[3]}"
    default="${BASH_REMATCH[4]}"
    [ "$step" -ge 1 ] && [ "$hi" -ge "$lo" ] \
      || die "--$name '$text' needs STEP >= 1 and MAX >= MIN"
    mapfile -t values < <(seq "$lo" "$step" "$hi")
  elif [[ "$text" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    die "--$name '$text' is a range without a default; write $text@DEFAULT"
  else
    die "--$name '$text' is not N or MIN:MAX:STEP@DEFAULT"
  fi
}

parse polys "$polys" ps p_def;       parse steps "$steps" ls l_def
parse digits "$digits" cs c_def;     parse vars "$vars" vs v_def
parse summands "$summands" ss s_def

[[ "$rounds" =~ ^[0-9]+$ ]] && [ "$rounds" -ge 1 ] || die "--rounds must be at least 1"
[[ "$seed" =~ ^[0-9]+$ ]] || die "--seed must be a number"

for name in "${PARSERS[@]}"; do
  [ -x "$BIN/parse-$name" ] || die "$BIN/parse-$name not found; run ./collect-parsers.sh first"
done
read -r -a prefix <<< "${RUN_PREFIX:-}"

exists=false
[ -e "$output" ] && exists=true
$append && $overwrite && die "--append and --overwrite exclude each other"
if $exists && $overwrite; then
  rm -f "$output"
  exists=false
elif $exists && ! $append; then
  die "$output exists; pass --append, --overwrite or choose another -o"
fi
mkdir -p "$(dirname "$output")" "$INST"

tmp="$(mktemp -d)"
# The instance of the configuration that is running. The trap removes it when
# the script exits early, so that a failed or interrupted sweep leaves nothing
# behind.
files=()
cleanup() {
  rm -rf "$tmp"
  $keep || [ ${#files[@]} -eq 0 ] || rm -f "${files[@]}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- sweep -----------------------------------------------------------------

if ! $exists; then
  {
    printf 'p,l,c,v,s,seed,size_bytes,rounds'
    for k in $LLVM_KEYS; do printf ',llvm_%s' "$k"; done
    for k in $SML_KEYS;  do printf ',sml_%s' "$k"; done
    printf ',llvm_total_s_std,sml_total_s_std\n'
  } > "$output"
fi

# Mean of every key in $2 over the reports collected in file $1, as
# ",mean,mean,...". MLton prints negative numbers with '~'.
means() {
  tr '~' '-' < "$1" | awk -v keys="$2" '
    { sum[$1] += $2; cnt[$1]++ }
    END {
      n = split(keys, k, " ")
      for (i = 1; i <= n; i++) {
        if (!cnt[k[i]]) { print "missing key " k[i] > "/dev/stderr"; exit 1 }
        printf ",%.6f", sum[k[i]] / cnt[k[i]]
      }
    }'
}

# Sample standard deviation of total_s over the reports in file $1.
total_std() {
  awk '$1 == "total_s" { n++; s += $2; q += $2 * $2 }
       END { d = (n > 1) ? (q - s * s / n) / (n - 1) : 0
             printf "%.6f", (d > 0) ? sqrt(d) : 0 }' "$1"
}

total_mean() { awk '$1 == "total_s" { n++; s += $2 } END { printf "%.3f", s / n }' "$1"; }

# One sweep per parameter with a range: it takes each of its values while the
# others stay at their default. A configuration that several sweeps share is
# queued only once.
configs=()
declare -A queued=()
queue() {
  [ -n "${queued[$*]:-}" ] && return 0
  queued[$*]=1
  configs+=("$*")
}
for p in "${ps[@]}"; do queue "$p" "$l_def" "$c_def" "$v_def" "$s_def"; done
for l in "${ls[@]}"; do queue "$p_def" "$l" "$c_def" "$v_def" "$s_def"; done
for c in "${cs[@]}"; do queue "$p_def" "$l_def" "$c" "$v_def" "$s_def"; done
for v in "${vs[@]}"; do queue "$p_def" "$l_def" "$c_def" "$v" "$s_def"; done
for s in "${ss[@]}"; do queue "$p_def" "$l_def" "$c_def" "$v_def" "$s"; done
# No range at all: measure the one configuration of the fixed values.
[ ${#configs[@]} -gt 0 ] || queue "$p_def" "$l_def" "$c_def" "$v_def" "$s_def"

total=${#configs[@]}
info "$total configurations, $rounds rounds each -> $output"

n=0
for config in "${configs[@]}"; do
  read -r p l c v s <<< "$config"
  n=$((n + 1))
  stem="$INST/p$p-l$l-c$c-v$v-s$s"
  files=("$stem.polys" "$stem.proof" "$stem.spec")
  "$EVAL_DIR/gen-instance.py" -p "$p" -l "$l" -c "$c" -v "$v" -s "$s" \
    --seed "$seed" -o "$stem" 2>"$tmp/gen" \
    || { cat "$tmp/gen" >&2; die "gen-instance.py failed on $stem"; }
  size=$(cat "${files[@]}" | wc -c)

  for name in "${PARSERS[@]}"; do : > "$tmp/$name"; done
  for _ in $(seq "$rounds"); do
    for name in "${PARSERS[@]}"; do
      "${prefix[@]}" "$BIN/parse-$name" "${files[@]}" >> "$tmp/$name" \
        || die "parse-$name failed on $stem (rerun with --keep to keep the instance)"
    done
  done
  $keep || rm -f "${files[@]}"

  {
    printf '%s,%s,%s,%s,%s,%s,%s,%s' "$p" "$l" "$c" "$v" "$s" "$seed" "$size" "$rounds"
    means "$tmp/llvm" "$LLVM_KEYS"
    means "$tmp/sml" "$SML_KEYS"
    printf ',%s,%s\n' "$(total_std "$tmp/llvm")" "$(total_std "$tmp/sml")"
  } >> "$output"

  info "[$n/$total] p=$p l=$l c=$c v=$v s=$s ($((size / 1000)) kB):" \
       "llvm $(total_mean "$tmp/llvm") s, sml $(total_mean "$tmp/sml") s"
done

# --- graphs ----------------------------------------------------------------

if $plot; then
  graph_args=()
  [ -n "${GRAPH_ARGS:-}" ] && read -r -a graph_args <<< "$GRAPH_ARGS"
  "$EVAL_DIR/render-graph.py" "$output" "${graph_args[@]}" \
    || red "render-graph.py failed (matplotlib and pandas come with: nix develop);" \
           "the CSV is complete, rerun ./render-graph.py $output"
fi
