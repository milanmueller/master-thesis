#!/usr/bin/env bash
# Build both phase-reporting checkers, run them over every benchmark listed in
# ../main/instances/benchmark-include, collect their reports in
# results/phases-sml.csv and results/phases-llvm.csv, average them per benchmark
# into results/phases-sml-averages.csv and results/phases-llvm-averages.csv, and
# render results/phases-plot.pdf and results/phases-table.tex from the two.
#
# Dependencies: python3, with pandas for the averaging and matplotlib for the
# figure; on NixOS the ../flake.nix devshell provides them, along with the
# compilers ./collect-checkers.sh needs.
#
#   ./run-phases.sh [options]
#
# The instances and the include list are the ones ../main/run-benchmarks.sh
# uses, so that a phase breakdown covers exactly the benchmarks of the wall
# clock and peak RSS comparison. The include file holds one benchmark stem per
# line; blank lines are skipped and `#` starts a comment.
#
# Unlike ../main/run-benchmarks.sh this script needs no GNU time: both drivers
# time themselves and report their own peak RSS, and that self-measurement is
# the point of the sweep. It also writes two CSVs rather than one, because the
# two drivers measure different things - MLton splits every timer into a GC and
# a non-GC part, the instrumented LLVM binary breaks the verified checker itself
# into phases. See ./parse-stats-sml.py and ./parse-stats-llvm.py.
#
# Options:
#   -r, --rounds N       runs per checker per benchmark (default 1)
#   -t, --timeout SECS   per-run timeout; off by default
#   -c, --checkers LIST  comma-separated subset (default both)
#   -i, --include FILE   include list (default ../main/instances/benchmark-include)
#   -I, --instances DIR  instance directory (default ../main/instances)
#       --sml-csv FILE   SML output (default results/phases-sml.csv)
#       --llvm-csv FILE  LLVM output (default results/phases-llvm.csv)
#       --tier N         instrumentation tier to build, 0-2 (default 1)
#       --time-alloc     build the LLVM driver with -DPST_TIME_ALLOC
#   -n, --no-build       skip ./collect-checkers.sh and use ./checkers as it is
#       --append         add to existing CSVs instead of starting new ones
#       --sml-averages FILE   averaged SML CSV (default: <--sml-csv>-averages.csv)
#       --llvm-averages FILE  averaged LLVM CSV (default: <--llvm-csv>-averages.csv)
#       --no-average     stop after the raw CSVs, do not average them
#   -P, --plot FILE      figure (default: results/phases-plot.pdf)
#       --no-plot        do not run ./render-phases-plot.py
#   -T, --table FILE     LaTeX table (default: results/phases-table.tex)
#       --no-table       do not run ./render-phases-table.py
#
# Set RUN_PREFIX to pin runs to one core: RUN_PREFIX="taskset -c 2".
# Set PHASES_PLOT_ARGS to pass options through to ./render-phases-plot.py:
# PHASES_PLOT_ARGS="--panels". It is deliberately not the PLOT_ARGS that
# ../main/run-benchmarks.sh reads: the two renderers take different options, and
# one exported variable meant for the other script would fail this one.
# PHASES_TABLE_ARGS does the same for ./render-phases-table.py.
#
# The figure normalises every bar to its own run, so that benchmarks of any
# duration share one axis: over all ten the totals span a factor of 700, which
# no single linear axis of time can show. The total in seconds stays on the cap
# of each bar. It covers the two families that come in several sizes, btor and
# sparrc, as one block each, and inside a block it puts each checker's three
# instances in one run, so that the progression with the instance size is read
# along a run rather than across alternating bars. Setting PHASES_PLOT_ARGS
# replaces all of that. The table has no such limit and covers every benchmark.
#
# Every run's output is kept under results/logs/, because a phase report that
# the parser rejects is only diagnosable from the text it was rejected from.
#
# Only one sweep may write a given results directory at a time, enforced with a
# lock file. Two concurrent sweeps would append to the same CSVs and overwrite
# each other's logs, which does not fail - it silently produces duplicate
# (bench, round) rows carrying different measurements.
#
# Without --append an existing CSV is moved aside to <name>-<timestamp>.csv
# rather than appended to, so that a rerun cannot silently mix reports taken
# from binaries built at different tiers.
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$EVAL_DIR/checkers"

ALL_CHECKERS=(pasteque-sml pasteque-llvm-stats)

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '%s\n' "$*"; }
die()  { red "error: $*"; exit 1; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '$d'; }

# --- arguments -------------------------------------------------------------

rounds=5
timeout_s=
checkers=()
instances="$EVAL_DIR/../main/instances"
include=
sml_csv="$EVAL_DIR/results/phases-sml.csv"
llvm_csv="$EVAL_DIR/results/phases-llvm.csv"
logs="$EVAL_DIR/results/logs"
sml_averages=
llvm_averages=
average=true
plot_file=
plot=true
table_file=
table=true
tier=1
time_alloc=false
build=true
append=false

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage; exit 0 ;;
    -r|--rounds)    rounds="${2:?--rounds needs a value}"; shift 2 ;;
    -t|--timeout)   timeout_s="${2:?--timeout needs a value}"; shift 2 ;;
    -c|--checkers)  IFS=, read -r -a checkers <<< "${2:?--checkers needs a value}"; shift 2 ;;
    -i|--include)   include="${2:?--include needs a value}"; shift 2 ;;
    -I|--instances) instances="${2:?--instances needs a value}"; shift 2 ;;
    --sml-csv)      sml_csv="${2:?--sml-csv needs a value}"; shift 2 ;;
    --llvm-csv)     llvm_csv="${2:?--llvm-csv needs a value}"; shift 2 ;;
    --sml-averages)  sml_averages="${2:?--sml-averages needs a value}"; shift 2 ;;
    --llvm-averages) llvm_averages="${2:?--llvm-averages needs a value}"; shift 2 ;;
    --no-average)    average=false; shift ;;
    -P|--plot)       plot_file="${2:?--plot needs a value}"; shift 2 ;;
    --no-plot)       plot=false; shift ;;
    -T|--table)      table_file="${2:?--table needs a value}"; shift 2 ;;
    --no-table)      table=false; shift ;;
    --tier)         tier="${2:?--tier needs a value}"; shift 2 ;;
    --time-alloc)   time_alloc=true; shift ;;
    -n|--no-build)  build=false; shift ;;
    --append)       append=true; shift ;;
    *)              die "unknown argument '$1' (try --help)" ;;
  esac
done

# Follow --instances, so that pointing the sweep at another instance tree does
# not keep reading the include list of the default one.
[ -n "$include" ] || include="$instances/benchmark-include"

# Keep each averaged CSV next to the raw one it summarises, so that redirecting
# the raw output does not leave its average behind in results/.
[ -n "$sml_averages" ] || sml_averages="${sml_csv%.csv}-averages.csv"
[ -n "$llvm_averages" ] || llvm_averages="${llvm_csv%.csv}-averages.csv"
[ -n "$plot_file" ] || plot_file="$EVAL_DIR/results/phases-plot.pdf"
[ -n "$table_file" ] || table_file="$EVAL_DIR/results/phases-table.tex"

# See the header: normalised bars, and one block per instance family.
plot_args=(--relative --order family --group-checkers --match '^(btor|sparrc)-')
[ -n "${PHASES_PLOT_ARGS:-}" ] && read -r -a plot_args <<< "$PHASES_PLOT_ARGS"
table_args=()
[ -n "${PHASES_TABLE_ARGS:-}" ] && read -r -a table_args <<< "$PHASES_TABLE_ARGS"

[ "$rounds" -ge 1 ] 2>/dev/null || die "--rounds must be a positive integer, got '$rounds'"
[ ${#checkers[@]} -eq 0 ] && checkers=("${ALL_CHECKERS[@]}")
for c in "${checkers[@]}"; do
  printf '%s\n' "${ALL_CHECKERS[@]}" | grep -qxF "$c" \
    || die "unknown checker '$c'; known: ${ALL_CHECKERS[*]}"
done

[ -d "$instances" ] || die "instance directory missing: $instances"
[ -f "$include" ] || die "include list missing: $include
       It holds one benchmark stem per line; '#' starts a comment."

# The parsers are the only reason this script needs python3; check them before
# the build rather than after the sweep, whose reports would then be stranded in
# results/logs/.
wants() { printf '%s\n' "${checkers[@]}" | grep -qxF "$1"; }
wants pasteque-sml        && parser_sml="$EVAL_DIR/parse-stats-sml.py"
wants pasteque-llvm-stats && parser_llvm="$EVAL_DIR/parse-stats-llvm.py"
for p in "${parser_sml:-}" "${parser_llvm:-}"; do
  [ -z "$p" ] || [ -x "$p" ] || die "missing or not executable: $p"
done
command -v python3 >/dev/null 2>&1 \
  || die "python3 not found on PATH. Run: nix develop .. -c ./run-phases.sh $*"

# Check the averaging before the sweep, not after it: the raw CSVs would survive
# a late failure, but finding out that pandas is missing at the end of an hour
# of measuring would not be excusable.
if $average; then
  wants pasteque-sml        && averager_sml="$EVAL_DIR/average-phases-sml.py"
  wants pasteque-llvm-stats && averager_llvm="$EVAL_DIR/average-phases-llvm.py"
  for p in "${averager_sml:-}" "${averager_llvm:-}"; do
    [ -z "$p" ] || [ -x "$p" ] || die "missing or not executable: $p"
  done
  python3 -c 'import pandas' 2>/dev/null \
    || die "python3 has no pandas; run inside the devshell or pass --no-average"
  if $plot; then
    [ -x "$EVAL_DIR/render-phases-plot.py" ] \
      || die "missing or not executable: $EVAL_DIR/render-phases-plot.py"
    python3 -c 'import matplotlib' 2>/dev/null \
      || die "python3 has no matplotlib; run inside the devshell or pass --no-plot"
  fi
  $table && { [ -x "$EVAL_DIR/render-phases-table.py" ] \
    || die "missing or not executable: $EVAL_DIR/render-phases-table.py"; }
fi

prefix=()
[ -n "${RUN_PREFIX:-}" ] && read -r -a prefix <<< "$RUN_PREFIX"
limit=()
[ -n "$timeout_s" ] && limit=(timeout --foreground "$timeout_s")

# --- benchmark list --------------------------------------------------------

# Strip comments and surrounding whitespace, drop what is left empty. The
# `|| [ -n "$line" ]` keeps a last line that has no trailing newline.
benchmarks=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] || continue
  benchmarks+=("$line")
done < "$include"

[ ${#benchmarks[@]} -gt 0 ] || die "no benchmarks listed in $include"

# Check every stem up front: a typo should not surface an hour into a sweep.
missing=()
for b in "${benchmarks[@]}"; do
  for ext in polys proof spec; do
    [ -f "$instances/$b.$ext" ] || missing+=("$b.$ext")
  done
done
if [ ${#missing[@]} -gt 0 ]; then
  die "${#missing[@]} instance file(s) listed in $include but missing from $instances:
       $(printf '%s ' "${missing[@]}")"
fi

# --- build -----------------------------------------------------------------

if $build; then
  bold "==> building checkers"
  build_args=(--tier "$tier")
  $time_alloc && build_args+=(--time-alloc)
  "$EVAL_DIR/collect-checkers.sh" "${build_args[@]}" "${checkers[@]}"
else
  info "skipping build (--no-build)"
fi

for c in "${checkers[@]}"; do
  [ -x "$BIN/$c" ] || die "$BIN/$c missing. Build it with: ./collect-checkers.sh $c"
done

# --- run -------------------------------------------------------------------

mkdir -p "$logs"

# One writer per results directory (see the header). flock releases the
# descriptor when this process dies, so a killed sweep leaves no stale lock.
lock="$(dirname "$logs")/.sweep.lock"
exec 9>"$lock"
flock -n 9 || die "another sweep is already writing $(dirname "$logs")
       (lock: $lock). Wait for it to finish, or point this one elsewhere with
       --sml-csv/--llvm-csv."

for c in "${checkers[@]}"; do
  case "$c" in
    pasteque-sml)        csv="$sml_csv" ;;
    pasteque-llvm-stats) csv="$llvm_csv" ;;
  esac
  mkdir -p "$(dirname "$csv")"
  if [ -f "$csv" ] && ! $append; then
    backup="${csv%.csv}-$(date +%Y%m%d-%H%M%S).csv"
    mv "$csv" "$backup"
    info "moved existing CSV aside to $backup"
  fi
done

bold "==> running ${#benchmarks[@]} benchmark(s), $rounds round(s) of ${checkers[*]}"
start=$SECONDS
failed=()
i=0
for b in "${benchmarks[@]}"; do
  i=$((i + 1))
  bold "[$i/${#benchmarks[@]}] $b"
  for c in "${checkers[@]}"; do
    case "$c" in
      pasteque-sml)        csv="$sml_csv"; parser="$parser_sml" ;;
      pasteque-llvm-stats) csv="$llvm_csv"; parser="$parser_llvm" ;;
    esac
    for r in $(seq 1 "$rounds"); do
      # A stem may contain directories, which must not become directories under
      # results/logs/.
      log="$logs/${b//\//_}-$c-$r.log"
      # Both reports are captured together: pasteque.sml prints its stats on
      # stdout, stats.c prints its report on stderr, and each parser reads only
      # the lines of its own driver. A non-zero exit is a normal outcome -
      # pasteque-llvm-stats exits 1 unless the target was derived - so do not
      # let set -e abort on it.
      # The up-front check cannot speak for a sweep that takes hours: an
      # instance renamed while it runs would otherwise surface as a report the
      # parser cannot read, rather than as the missing file it is.
      gone=()
      for ext in polys proof spec; do
        [ -f "$instances/$b.$ext" ] || gone+=("$b.$ext")
      done
      if [ ${#gone[@]} -gt 0 ]; then
        red "  $c round $r: instance file(s) no longer in $instances: ${gone[*]}"
        failed+=("$b/$c/$r")
        continue
      fi

      rc=0
      "${prefix[@]}" "${limit[@]}" "$BIN/$c" \
        "$instances/$b.polys" "$instances/$b.proof" "$instances/$b.spec" \
        > "$log" 2>&1 || rc=$?

      if [ "$rc" = 124 ]; then
        red "  $c round $r: timed out after ${timeout_s}s, no report to parse"
        failed+=("$b/$c/$r")
        continue
      fi
      # The parser reports what it wrote, or explains what the log is missing.
      # Its own exit status is what decides success: a run that exits non-zero
      # but prints a complete report is a measurement, and a run that exits 0
      # without one is not.
      "$parser" "$log" --bench "$b" --round "$r" --csv "$csv" \
        || failed+=("$b/$c/$r")
    done
  done
done

bold "==> ran ${#benchmarks[@]} benchmark(s) in $((SECONDS - start))s"
wants pasteque-sml        && info "SML phase reports:  $sml_csv"
wants pasteque-llvm-stats && info "LLVM phase reports: $llvm_csv"
info "run logs:           $logs"

status=0
if [ ${#failed[@]} -gt 0 ]; then
  red "${#failed[@]} run(s) produced no usable report: ${failed[*]}"
  status=1
fi

# Average whatever was measured, even after a partial sweep: a benchmark that
# failed is simply absent from the CSV, and the rows that are there are still
# worth summarising. A non-zero exit from an averager means the rounds of some
# benchmark disagreed on the verdict, which it has already detailed on stderr.
if ! $average; then
  info "skipping averaging (--no-average)"
else
  for c in "${checkers[@]}"; do
    case "$c" in
      pasteque-sml)        csv="$sml_csv";  out="$sml_averages";  avg="$averager_sml" ;;
      pasteque-llvm-stats) csv="$llvm_csv"; out="$llvm_averages"; avg="$averager_llvm" ;;
    esac
    if [ ! -s "$csv" ]; then
      red "skipping $c: $csv holds no measurements"
      status=1
      continue
    fi
    bold "==> averaging $c"
    "$avg" "$csv" --out "$out" || status=1
  done
fi

# The figure puts the two checkers side by side, so it needs both averaged CSVs.
# A sweep of one checker produces half of that, which is not this figure.
if ! $plot; then
  info "skipping plot (--no-plot)"
elif ! $average; then
  info "skipping plot (it renders the averages, and --no-average was given)"
elif [ ${#checkers[@]} -lt ${#ALL_CHECKERS[@]} ]; then
  info "skipping plot (it draws both checkers, and only ${checkers[*]} was run)"
elif [ ! -f "$sml_averages" ] || [ ! -f "$llvm_averages" ]; then
  red "skipping plot: $sml_averages or $llvm_averages was not written"
  status=1
else
  bold "==> rendering plot"
  "$EVAL_DIR/render-phases-plot.py" --sml "$sml_averages" --llvm "$llvm_averages" \
    --out "$plot_file" "${plot_args[@]}" || status=1
fi

# The table puts the two checkers side by side as well, so it needs both CSVs.
if ! $table; then
  info "skipping table (--no-table)"
elif ! $average; then
  info "skipping table (it renders the averages, and --no-average was given)"
elif [ ${#checkers[@]} -lt ${#ALL_CHECKERS[@]} ]; then
  info "skipping table (it draws both checkers, and only ${checkers[*]} was run)"
elif [ ! -f "$sml_averages" ] || [ ! -f "$llvm_averages" ]; then
  red "skipping table: $sml_averages or $llvm_averages was not written"
  status=1
else
  bold "==> rendering table"
  "$EVAL_DIR/render-phases-table.py" --sml "$sml_averages" --llvm "$llvm_averages" \
    --out "$table_file" "${table_args[@]}" || status=1
fi

exit $status
