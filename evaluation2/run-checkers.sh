#!/usr/bin/env bash
# Time the PAC checkers on one instance and append the measurements to a CSV.
#
# Dependencies: GNU time; on NixOS the ./flake.nix devshell provides it.
# Build the binaries first with ./collect-checkers.sh.
#
#   ./run-checkers.sh [options] <bench>
#
# <bench> is an instance stem below instances/, so that the three files
# instances/<bench>.input, .proof and .target exist. A stem may contain
# directories: ./run-checkers.sh KaufmannFleuryBiereKauers-JKU/.../foo
#
# Options:
#   -r, --rounds N       runs per checker (default 3)
#   -o, --csv FILE       CSV to append to (default results.csv)
#   -c, --checkers LIST  comma-separated subset (default all three)
#   -t, --timeout SECS   per-run timeout; off by default
#
# Set RUN_PREFIX to pin runs to one core: RUN_PREFIX="taskset -c 2".
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$EVAL_DIR/checkers"
INSTANCES="$EVAL_DIR/instances"

ALL_CHECKERS=(pacheck pasteque-sml pasteque-llvm)

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
die()  { red "error: $*"; exit 1; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '$d'; }

# --- arguments -------------------------------------------------------------

rounds=3
csv="$EVAL_DIR/results.csv"
timeout_s=
checkers=()
bench=

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    -r|--rounds)   rounds="${2:?--rounds needs a value}"; shift 2 ;;
    -o|--csv)      csv="${2:?--csv needs a value}"; shift 2 ;;
    -t|--timeout)  timeout_s="${2:?--timeout needs a value}"; shift 2 ;;
    -c|--checkers) IFS=, read -r -a checkers <<< "${2:?--checkers needs a value}"; shift 2 ;;
    -*)            die "unknown option '$1' (try --help)" ;;
    *)             [ -n "$bench" ] && die "more than one benchmark given: '$bench', '$1'"
                   bench="$1"; shift ;;
  esac
done

[ -n "$bench" ] || die "no benchmark given (try --help)"
[ "$rounds" -ge 1 ] 2>/dev/null || die "--rounds must be a positive integer, got '$rounds'"
[ ${#checkers[@]} -eq 0 ] && checkers=("${ALL_CHECKERS[@]}")

for c in "${checkers[@]}"; do
  printf '%s\n' "${ALL_CHECKERS[@]}" | grep -qxF "$c" \
    || die "unknown checker '$c'; known: ${ALL_CHECKERS[*]}"
  [ -x "$BIN/$c" ] || die "$BIN/$c missing. Build it with: ./collect-checkers.sh $c"
done

input="$INSTANCES/$bench.polys"
proof="$INSTANCES/$bench.proof"
target="$INSTANCES/$bench.spec"
for f in "$input" "$proof" "$target"; do
  [ -f "$f" ] || die "instance file missing: $f"
done

# bash's `time` is a keyword, so command -v would resolve to it; -P searches
# PATH for the executable only.
GNU_TIME="${GNU_TIME:-$(type -P time || true)}"
[ -n "$GNU_TIME" ] || die "GNU time not found on PATH. Run: nix develop -c ./run-checkers.sh $*"

prefix=()
[ -n "${RUN_PREFIX:-}" ] && read -r -a prefix <<< "$RUN_PREFIX"
limit=()
[ -n "$timeout_s" ] && limit=(timeout --foreground "$timeout_s")

# --- verdict ---------------------------------------------------------------

# Normalise the three checkers' incompatible reporting onto one vocabulary.
# Exit codes alone will not do: pasteque-sml always exits 0, and pasteque-llvm
# exits 0 only when the target was derived.
verdict_of() {
  local checker="$1" out="$2" err="$3" rc="$4"
  [ "$rc" = 124 ] && { echo TIMEOUT; return; }
  case "$checker" in
    pacheck)
      # Messages carry a "[pck2] " prefix, and the no-target line extends the
      # inferences-checked one, so test the more specific patterns first.
      if   grep -qF 'c TARGET CHECKED' "$out" "$err"; then echo TARGET
      elif grep -qF 'TARGET IS NOT INFERRED' "$out" "$err"; then echo NO_TARGET
      elif grep -qF 'c INFERENCES CHECKED' "$out" "$err"; then echo CHECKED
      elif [ "$rc" != 0 ]; then echo INVALID
      else echo UNKNOWN
      fi ;;
    pasteque-sml)
      if   grep -qF 's SUCCESSFULL' "$out" "$err"; then echo TARGET
      elif grep -qF 's FAILED, but correct PAC' "$out" "$err"; then echo NO_TARGET
      elif grep -qF 's PAC FAILED' "$out" "$err"; then echo INVALID
      else echo UNKNOWN
      fi ;;
    pasteque-llvm)
      # The driver prints the verified checker's status on stdout: 1 FOUND,
      # 0 SUCCESS (steps check, target not derived), 2 FAILED. A missing status
      # line means it exited earlier with a usage or IO error.
      case "$(grep -m1 -oE '^[0-2]$' "$out" || true)" in
        1) echo TARGET ;;
        0) echo NO_TARGET ;;
        2) echo INVALID ;;
        *) echo ERROR ;;
      esac ;;
  esac
}

# --- run -------------------------------------------------------------------

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$(dirname "$csv")"
[ -f "$csv" ] || echo 'bench,checker,round,wall_s,user_s,sys_s,max_rss_kb,exit_code,verdict' > "$csv"

printf '%s: %d round(s) of %s\n' "$bench" "$rounds" "${checkers[*]}"

for c in "${checkers[@]}"; do
  for r in $(seq 1 "$rounds"); do
    # A non-zero exit is a normal outcome here (see verdict_of), so do not let
    # set -e abort on it; %x carries the command's own status either way.
    "$GNU_TIME" --quiet -f '%e,%U,%S,%M,%x' -o "$tmp/time" \
      "${prefix[@]}" "${limit[@]}" "$BIN/$c" "$input" "$proof" "$target" \
      > "$tmp/stdout" 2> "$tmp/stderr" || true

    IFS=, read -r wall usr sys rss exit_code < "$tmp/time" \
      || die "GNU time wrote no measurement for $c round $r"

    v="$(verdict_of "$c" "$tmp/stdout" "$tmp/stderr" "$exit_code")"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$bench" "$c" "$r" "$wall" "$usr" "$sys" "$rss" "$exit_code" "$v" >> "$csv"
    printf '  %-14s round %-3s %8s s  %8s kB  exit %-4s %s\n' \
      "$c" "$r" "$wall" "$rss" "$exit_code" "$v"
  done
done

printf 'appended %d row(s) to %s\n' "$((${#checkers[@]} * rounds))" "$csv"
