#!/usr/bin/env bash
# Build the two Pasteque checkers that report a per-phase breakdown and collect
# the binaries in ./checkers.
# Dependencies: mlton, clang, make, python3
# The devshell of ../flake.nix provides all requirements, and ../.envrc covers
# this directory too, so with direnv the scripts run directly.
#
#   nix develop .. -c ./collect-checkers.sh   # or: direnv allow in ..
#
# Nothing here runs Isabelle. Both Pasteque backends are compiled from code
# Isabelle has already exported; see the preflight messages below for how to
# (re)generate it.
#
#   pasteque-sml         IsaFoL/PAC_Checker2/code, Imperative-HOL/MLton, shared
#                        variables ("Efficient"); the same binary ../main
#                        builds. Its driver (pasteque.sml) already times
#                        parsing, initialization and proof checking, and reports
#                        each phase with and without garbage collection.
#   pasteque-llvm-stats  IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/code,
#                        Isabelle-LLVM, `make pasteque_stats`: the instrumented
#                        driver (stats.c) linked against term.ll and an injected
#                        pasteque.ll. inject_stats.py wraps every phase of the
#                        phase table in stats.h so that the verified checker,
#                        which reaches the driver as a single call, reports
#                        inclusive and self time, call counts and allocations per
#                        phase. This is NOT the production binary: a wrapped
#                        function can no longer be inlined and blocks
#                        interprocedural optimization across the call, so
#                        ../main builds the uninstrumented `pasteque` for the
#                        wall clock and peak RSS comparison.
#
# Both take the same three positional arguments as the uninstrumented checkers,
# <input> <proof> <target>, and print their breakdown to stderr.
#
# Usage:
#   ./collect-checkers.sh                        # build both
#   ./collect-checkers.sh pasteque-sml           # build a subset
#   ./collect-checkers.sh --tier 2               # instrument deeper (default 1)
#   ./collect-checkers.sh --time-alloc           # also time the allocator
#   ./collect-checkers.sh --clean                # remove build/ and checkers/
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$EVAL_DIR/../.." && pwd)"

# Source trees. Override any of these from the environment if the layout moves.
SML_SRC="${SML_SRC:-$REPO_ROOT/isabelle/IsaFoL/PAC_Checker2/code}"
LLVM_SRC="${LLVM_SRC:-$REPO_ROOT/isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/code}"

BUILD="$EVAL_DIR/build"
OUT="$EVAL_DIR/checkers"

# Everything `make pasteque_stats` in the LLVM code directory needs: the trusted
# parser and the instrumented driver (parser.c, stats.c), the injector and the
# phase table it shares with the driver (inject_stats.py, stats.h), the
# hand-written/generated headers and the two Isabelle-LLVM exports. main.c and
# lib_isabelle_llvm.c are not in the list: stats.c replaces the driver and
# brings its own runtime hooks, which is how it counts the allocations.
LLVM_FILES=(Makefile parser.c stats.c inject_stats.py parser.h pasteque.h
            term.h stats.h pasteque.ll term.ll)

ALL_CHECKERS=(pasteque-sml pasteque-llvm-stats)

# How deep inject_stats.py instruments; see the phase table in stats.h. Tier 1
# stops before the phases that run per polynomial operation, which are called
# millions of times and perturb the measurement they report.
STATS_TIER="${STATS_TIER:-1}"

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '%s\n' "$*"; }
die()  { red "error: $*"; exit 1; }

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '$d'
}

# --- argument parsing ------------------------------------------------------

selected=()
clean=false
time_alloc=false
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage; exit 0 ;;
    --clean)     clean=true ;;
    --time-alloc) time_alloc=true ;;
    --tier)      [ $# -ge 2 ] || die "--tier needs an argument"
                 STATS_TIER="$2"; shift ;;
    --tier=*)    STATS_TIER="${1#--tier=}" ;;
    -*)          die "unknown option '$1' (try --help)" ;;
    *)
      found=false
      for c in "${ALL_CHECKERS[@]}"; do
        [ "$1" = "$c" ] && found=true
      done
      $found || die "unknown checker '$1'; known: ${ALL_CHECKERS[*]}"
      selected+=("$1")
      ;;
  esac
  shift
done

case "$STATS_TIER" in
  0|1|2) ;;
  *) die "--tier must be 0, 1 or 2 (got '$STATS_TIER'); see the phase table in
       $LLVM_SRC/stats.h" ;;
esac

if $clean; then
  rm -rf "$BUILD" "$OUT"
  info "removed $BUILD and $OUT"
  [ ${#selected[@]} -eq 0 ] && exit 0
fi

[ ${#selected[@]} -eq 0 ] && selected=("${ALL_CHECKERS[@]}")

wants() {
  for c in "${selected[@]}"; do
    [ "$c" = "$1" ] && return 0
  done
  return 1
}

# --- preflight: toolchain --------------------------------------------------

CLANG="${CLANG:-clang}"

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die \
    "$1 not found on PATH. The toolchain is in the dev shell of
       $EVAL_DIR/../flake.nix, which ../.envrc loads for this directory too.
       Run:
         cd $EVAL_DIR && nix develop .. -c ./collect-checkers.sh"
}

wants pasteque-sml        && need_tool mlton
wants pasteque-llvm-stats && need_tool "$CLANG"
wants pasteque-llvm-stats && need_tool make
wants pasteque-llvm-stats && need_tool python3

# --- preflight: sources ----------------------------------------------------

if wants pasteque-sml; then
  [ -f "$SML_SRC/checker.ML" ] || die \
    "$SML_SRC/checker.ML missing. It is the Isabelle-exported ML code of the
       shared-variables checker and is normally committed. Regenerate it with:
         cd $REPO_ROOT/isabelle && mk build_pasteque_sml"
fi

if wants pasteque-llvm-stats; then
  missing=()
  for f in "${LLVM_FILES[@]}"; do
    [ -f "$LLVM_SRC/$f" ] || missing+=("$f")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    die "missing in $LLVM_SRC: ${missing[*]}
       The .ll files are gitignored (working tree only). Regenerate them with:
         cd $REPO_ROOT/isabelle && mk build_pasteque_llvm"
  fi
fi

# --- build -----------------------------------------------------------------

# Everything is compiled in build/ from copied sources, so that the source trees
# (both submodules) stay clean and each build starts from scratch. That matters
# more here than in ../main: the stats build generates pasteque_stats.ll next to
# the sources it reads.
mkdir -p "$OUT"

build_pasteque_sml() {
  bold "==> pasteque-sml"
  local dir="$BUILD/pasteque-sml"
  rm -rf "$dir"; mkdir -p "$dir"
  # pasteque.mlb references its sources by relative path, so all four files
  # have to sit next to each other.
  cp "$SML_SRC/checker.ML" "$SML_SRC/parser.sml" "$SML_SRC/pasteque.sml" \
     "$SML_SRC/pasteque.mlb" "$dir/"
  # Same flags as isabelle/Makefile target build_pasteque_sml, and as ../main:
  # the phase breakdown has to come from the binary that produced the wall clock
  # numbers, so this build is deliberately not specialized for measurement.
  ( cd "$dir" && mlton \
      -output "$OUT/pasteque-sml" \
      -const 'MLton.safe false' \
      -verbose 1 \
      -default-type int64 \
      -codegen native \
      -inline 700 \
      -cc-opt -O3 \
      pasteque.mlb )
}

build_pasteque_llvm_stats() {
  bold "==> pasteque-llvm-stats (tier $STATS_TIER)"
  local dir="$BUILD/pasteque-llvm-stats"
  rm -rf "$dir"; mkdir -p "$dir"
  for f in "${LLVM_FILES[@]}"; do cp "$LLVM_SRC/$f" "$dir/"; done
  chmod +x "$dir/inject_stats.py"
  # The Makefile runs inject_stats.py over pasteque.ll, internalizes every
  # definition not declared in a header in both the injected export and term.ll,
  # and compiles parser.c and stats.c together with them in one clang
  # invocation. inject_stats.py fails if a phase regex does not match exactly
  # one definition, which is what catches a stale .ll after a re-export.
  local cppflags="${CPPFLAGS:-}"
  $time_alloc && cppflags="$cppflags -DPST_TIME_ALLOC"
  ( cd "$dir" && make CLANG="$CLANG" STATS_TIER="$STATS_TIER" \
      CPPFLAGS="$cppflags" pasteque_stats )
  cp "$dir/pasteque_stats" "$OUT/pasteque-llvm-stats"
}

for c in "${selected[@]}"; do
  case "$c" in
    pasteque-sml)        build_pasteque_sml ;;
    pasteque-llvm-stats) build_pasteque_llvm_stats ;;
  esac
done

# --- provenance ------------------------------------------------------------

# One record per checker built, appended rather than rewritten, so that a subset
# build does not restate provenance for binaries left untouched. The report can
# qualify its numbers with the last record of each checker; for
# pasteque-llvm-stats the instrumentation tier belongs to that qualification,
# because it decides which phases the binary can attribute at all.
git_head() { git -C "$1" rev-parse --short HEAD 2>/dev/null || echo unknown; }
tool_version() { "$@" 2>/dev/null | head -1 || true; }

{
  for c in "${selected[@]}"; do
    printf '%s\n' "[$c]"
    printf '  built:    %s\n' "$(date -Is)"
    case "$c" in
      pasteque-sml)
        printf '  source:   %s @ %s\n' "$SML_SRC" \
          "$(git_head "$REPO_ROOT/isabelle/IsaFoL")"
        printf '  compiler: %s\n' "$(tool_version mlton)"
        ;;
      pasteque-llvm-stats)
        printf '  source:   %s @ %s\n' "$LLVM_SRC" \
          "$(git_head "$REPO_ROOT/isabelle/IsaFoL-Pasteque-LLVM")"
        printf '  compiler: %s\n' "$(tool_version "$CLANG" --version)"
        printf '  tier:     %s\n' "$STATS_TIER"
        printf '  alloc:    %s\n' \
          "$($time_alloc && echo 'timed (-DPST_TIME_ALLOC)' || echo 'counted only')"
        ;;
    esac
  done
} >> "$OUT/build-info.txt"

bold "==> done"
ls -l "$OUT"
