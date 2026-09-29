#!/usr/bin/env bash
# Build the checkers, run them over every benchmark listed in
# instances/benchmark-include, collect the measurements in results/raw.csv,
# average them into results/averages.csv and render results/table.tex and
# results/plot.pdf.
#
# Dependencies: GNU time and python3 with pandas and matplotlib; on NixOS the
# ../flake.nix devshell provides them.
#
#   ./run-benchmarks.sh [options]
#
# The include file holds one benchmark stem per line, in the form
# ./run-checkers.sh takes. Blank lines are skipped, and `#` starts a comment
# that runs to the end of the line.
#
# Options:
#   -r, --rounds N       runs per checker per benchmark (default 3)
#   -t, --timeout SECS   per-run timeout; off by default
#   -o, --csv FILE       raw output CSV (default results/raw.csv)
#   -a, --averages FILE  averaged CSV (default averages.csv beside --csv)
#   -T, --table FILE     LaTeX table (default table.tex beside --csv)
#   -P, --plot FILE      figure (default plot.pdf beside --csv)
#   -i, --include FILE   include list (default instances/benchmark-include)
#   -n, --no-build       skip ./collect-checkers.sh and use ./checkers as it is
#       --no-average     stop after the raw CSV, do not run ./average-results.py
#       --no-table       do not run ./render-table.py
#       --no-plot        do not run ./render-plot.py
#       --append         add to an existing CSV instead of starting a new one
#
# Set RUN_PREFIX to pin runs to one core: RUN_PREFIX="taskset -c 2".
# Set PLOT_ARGS to pass options through to ./render-plot.py: PLOT_ARGS="--log".
#
# Without --append an existing CSV is moved aside to <name>-<timestamp>.csv
# rather than appended to, so that a rerun cannot silently mix measurements
# taken with different binaries.
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES="$EVAL_DIR/instances"

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '%s\n' "$*"; }
die()  { red "error: $*"; exit 1; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '$d'; }

# --- arguments -------------------------------------------------------------

rounds=10
timeout_s=
csv="$EVAL_DIR/results/raw.csv"
averages=
table=
plot_file=
include="$INSTANCES/benchmark-include"
build=true
average=true
render=true
plot=true
append=false

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage; exit 0 ;;
    -r|--rounds)    rounds="${2:?--rounds needs a value}"; shift 2 ;;
    -t|--timeout)   timeout_s="${2:?--timeout needs a value}"; shift 2 ;;
    -o|--csv)       csv="${2:?--csv needs a value}"; shift 2 ;;
    -a|--averages)  averages="${2:?--averages needs a value}"; shift 2 ;;
    -T|--table)     table="${2:?--table needs a value}"; shift 2 ;;
    -P|--plot)      plot_file="${2:?--plot needs a value}"; shift 2 ;;
    -i|--include)   include="${2:?--include needs a value}"; shift 2 ;;
    -n|--no-build)  build=false; shift ;;
    --no-average)   average=false; shift ;;
    --no-table)     render=false; shift ;;
    --no-plot)      plot=false; shift ;;
    --append)       append=true; shift ;;
    *)              die "unknown argument '$1' (try --help)" ;;
  esac
done

# Keep the outputs together when --csv moved the raw one elsewhere.
[ -n "$averages" ] || averages="$(dirname "$csv")/averages.csv"
[ -n "$table" ] || table="$(dirname "$csv")/table.tex"
[ -n "$plot_file" ] || plot_file="$(dirname "$csv")/plot.pdf"

plot_args=()
[ -n "${PLOT_ARGS:-}" ] && read -r -a plot_args <<< "$PLOT_ARGS"

[ -f "$include" ] || die "include list missing: $include
       It holds one benchmark stem per line; '#' starts a comment."

# Check the aggregation's dependencies before the build, not after the sweep:
# the raw CSV would survive a late failure, but an hour of waiting to find out
# that pandas is missing would not be excusable.
if $average; then
  [ -x "$EVAL_DIR/average-results.py" ] || die "missing $EVAL_DIR/average-results.py"
  $render && { [ -x "$EVAL_DIR/render-table.py" ] || die "missing $EVAL_DIR/render-table.py"; }
  $plot && { [ -x "$EVAL_DIR/render-plot.py" ] || die "missing $EVAL_DIR/render-plot.py"; }
  command -v python3 >/dev/null 2>&1 \
    || die "python3 not found on PATH; run inside the devshell or pass --no-average"
  python3 -c 'import pandas' 2>/dev/null \
    || die "python3 has no pandas; run inside the devshell or pass --no-average"
  $plot && { python3 -c 'import matplotlib' 2>/dev/null \
    || die "python3 has no matplotlib; run inside the devshell or pass --no-plot"; }
fi

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
    [ -f "$INSTANCES/$b.$ext" ] || missing+=("$b.$ext")
  done
done
if [ ${#missing[@]} -gt 0 ]; then
  die "${#missing[@]} instance file(s) listed in $include but missing from $INSTANCES:
       $(printf '%s ' "${missing[@]}")"
fi

# --- build -----------------------------------------------------------------

if $build; then
  bold "==> building checkers"
  "$EVAL_DIR/collect-checkers.sh"
else
  info "skipping build (--no-build)"
fi

# --- run -------------------------------------------------------------------

mkdir -p "$(dirname "$csv")"
if [ -f "$csv" ] && ! $append; then
  backup="${csv%.csv}-$(date +%Y%m%d-%H%M%S).csv"
  mv "$csv" "$backup"
  info "moved existing CSV aside to $backup"
fi

run_args=(--rounds "$rounds" --csv "$csv")
[ -n "$timeout_s" ] && run_args+=(--timeout "$timeout_s")

bold "==> running ${#benchmarks[@]} benchmark(s), $rounds round(s) each"
start=$SECONDS
failed=()
i=0
for b in "${benchmarks[@]}"; do
  i=$((i + 1))
  bold "[$i/${#benchmarks[@]}] $b"
  "$EVAL_DIR/run-checkers.sh" "${run_args[@]}" "$b" || failed+=("$b")
done

bold "==> ran ${#benchmarks[@]} benchmark(s) in $((SECONDS - start))s"
info "raw measurements: $csv"

status=0
if [ ${#failed[@]} -gt 0 ]; then
  red "${#failed[@]} benchmark(s) failed: ${failed[*]}"
  status=1
fi

# Aggregate whatever was measured, even after a partial sweep. A non-zero exit
# here means the rounds of some pair disagreed, which average-results.py has
# already detailed on stderr.
if $average; then
  bold "==> averaging"
  "$EVAL_DIR/average-results.py" "$csv" --out "$averages" || status=1
else
  info "skipping aggregation (--no-average)"
fi

# The table and the plot are both rendered from the averages, so they have
# nothing to work on when the aggregation was skipped. A failed aggregation
# still writes the file, and rendering it is worth doing: the table and the
# plot are where the problematic rows become visible.
if ! $render; then
  info "skipping table (--no-table)"
elif ! $average; then
  info "skipping table (it renders the averages, and --no-average was given)"
elif [ ! -f "$averages" ]; then
  red "skipping table: $averages was not written"
  status=1
else
  bold "==> rendering table"
  "$EVAL_DIR/render-table.py" "$averages" --out "$table" || status=1
fi

if ! $plot; then
  info "skipping plot (--no-plot)"
elif ! $average; then
  info "skipping plot (it renders the averages, and --no-average was given)"
elif [ ! -f "$averages" ]; then
  red "skipping plot: $averages was not written"
  status=1
else
  bold "==> rendering plot"
  "$EVAL_DIR/render-plot.py" "$averages" --out "$plot_file" "${plot_args[@]}" \
    || status=1
fi

exit $status
