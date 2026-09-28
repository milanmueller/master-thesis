#!/usr/bin/env bash
# Build the three PAC proof checkers on the host and collect the binaries in
# Dependencies: mlton, g++, clang, gmp
# on NixOS, the ./flake.nix provides a devshell with all requirements
#
#   nix develop -c ./collect-checkers.sh   # or: direnv allow, then run directly
#
# Nothing here runs Isabelle. Both Pasteque backends are compiled from code
# Isabelle has already exported; see the preflight messages below for how to
# (re)generate it.
#
#   pacheck         evaluation/pacheck2 (submodule), C++20 + GMP
#   pasteque-sml    IsaFoL/PAC_Checker2/code, Imperative-HOL/MLton, shared
#                   variables ("Efficient"); code/no_sharing is not built
#   pasteque-llvm   IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/code, Isabelle-LLVM,
#                   `make pasteque`: trusted parser (parser.c) linked against
#                   the exported term.ll and pasteque.ll
#
# All three take the same three positional arguments: <input> <proof> <target>.
#
# Usage:
#   ./collect-checkers.sh                       # build all three
#   ./collect-checkers.sh pacheck pasteque-sml  # build a subset
#   ./collect-checkers.sh --clean               # remove build/ and checkers/
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$EVAL_DIR/.." && pwd)"

# Source trees. Override any of these from the environment if the layout moves.
PACHECK_SRC="${PACHECK_SRC:-$REPO_ROOT/evaluation/pacheck2}"
SML_SRC="${SML_SRC:-$REPO_ROOT/isabelle/IsaFoL/PAC_Checker2/code}"
LLVM_SRC="${LLVM_SRC:-$REPO_ROOT/isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/code}"

BUILD="$EVAL_DIR/build"
OUT="$EVAL_DIR/checkers"

# Everything `make pasteque` in the LLVM code directory needs: the two drivers
# (parser.c, main.c), Isabelle-LLVM's support library, the
# hand-written/generated headers and the two Isabelle-LLVM exports.
LLVM_FILES=(Makefile parser.c main.c lib_isabelle_llvm.c parser.h pasteque.h
            term.h pasteque.ll term.ll)

ALL_CHECKERS=(pacheck pasteque-sml pasteque-llvm)

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
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --clean)   clean=true ;;
    -*)        die "unknown option '$arg' (try --help)" ;;
    *)
      found=false
      for c in "${ALL_CHECKERS[@]}"; do
        [ "$arg" = "$c" ] && found=true
      done
      $found || die "unknown checker '$arg'; known: ${ALL_CHECKERS[*]}"
      selected+=("$arg")
      ;;
  esac
done

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

CXX="${CXX:-g++}"
CLANG="${CLANG:-clang}"

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die \
    "$1 not found on PATH. The toolchain is in the dev shell of
       $EVAL_DIR/flake.nix. Run:
         cd $EVAL_DIR && nix develop -c ./collect-checkers.sh"
}

wants pacheck       && need_tool "$CXX"
wants pacheck       && need_tool make
wants pasteque-sml  && need_tool mlton
wants pasteque-llvm && need_tool "$CLANG"
wants pasteque-llvm && need_tool make

# --- preflight: sources ----------------------------------------------------

if wants pacheck; then
  [ -f "$PACHECK_SRC/configure.sh" ] || die \
    "pacheck2 sources missing at $PACHECK_SRC. Fetch them with:
         git -C $REPO_ROOT submodule update --init evaluation/pacheck2"
fi

if wants pasteque-sml; then
  [ -f "$SML_SRC/checker.ML" ] || die \
    "$SML_SRC/checker.ML missing. It is the Isabelle-exported ML code of the
       shared-variables checker and is normally committed. Regenerate it with:
         cd $REPO_ROOT/isabelle && mk build_pasteque_sml"
fi

if wants pasteque-llvm; then
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

# Everything is compiled in build/ from copied sources, so that the source
# trees (two of them submodules) stay clean and each build starts from scratch.
mkdir -p "$OUT"

build_pacheck() {
  bold "==> pacheck"
  local dir="$BUILD/pacheck"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -r "$PACHECK_SRC/src" "$dir/src"
  cp "$PACHECK_SRC/configure.sh" "$PACHECK_SRC/makefile.in" "$dir/"
  chmod +x "$dir/configure.sh"
  # configure.sh probes for getrusage/getc_unlocked, creates build/ and writes
  # the makefile; it must run from the source directory. Defaults are -O3
  # -DNDEBUG.
  ( cd "$dir" && CC="$CXX" ./configure.sh && make )
  cp "$dir/pacheck" "$OUT/pacheck"
}

build_pasteque_sml() {
  bold "==> pasteque-sml"
  local dir="$BUILD/pasteque-sml"
  rm -rf "$dir"; mkdir -p "$dir"
  # pasteque.mlb references its sources by relative path, so all four files
  # have to sit next to each other.
  cp "$SML_SRC/checker.ML" "$SML_SRC/parser.sml" "$SML_SRC/pasteque.sml" \
     "$SML_SRC/pasteque.mlb" "$dir/"
  # Same flags as isabelle/Makefile target build_pasteque_sml.
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

build_pasteque_llvm() {
  bold "==> pasteque-llvm"
  local dir="$BUILD/pasteque-llvm"
  rm -rf "$dir"; mkdir -p "$dir"
  for f in "${LLVM_FILES[@]}"; do cp "$LLVM_SRC/$f" "$dir/"; done
  # The exported IR needs no external library: lib_isabelle_llvm.c defines the
  # runtime hooks it declares (isabelle_llvm_calloc / isabelle_llvm_free /
  # isabelle_llvm_abort). The Makefile first rewrites term.ll and pasteque.ll
  # to *_int.ll (hiding the clashing auxiliary definitions) and then compiles
  # parser.c, main.c and the support library together with both in one clang
  # invocation so that LTO optimises the trusted parser together with the
  # verified checker.
  ( cd "$dir" && make CLANG="$CLANG" pasteque )
  cp "$dir/pasteque" "$OUT/pasteque-llvm"
}

for c in "${selected[@]}"; do
  case "$c" in
    pacheck)       build_pacheck ;;
    pasteque-sml)  build_pasteque_sml ;;
    pasteque-llvm) build_pasteque_llvm ;;
  esac
done

# --- provenance ------------------------------------------------------------

# One record per checker built, appended rather than rewritten, so that a
# subset build does not restate provenance for binaries left untouched. The
# report can qualify its numbers with the last record of each checker.
git_head() { git -C "$1" rev-parse --short HEAD 2>/dev/null || echo unknown; }
tool_version() { "$@" 2>/dev/null | head -1 || true; }

{
  for c in "${selected[@]}"; do
    printf '%s\n' "[$c]"
    printf '  built:    %s\n' "$(date -Is)"
    case "$c" in
      pacheck)
        printf '  source:   %s @ %s\n' "$PACHECK_SRC" "$(git_head "$PACHECK_SRC")"
        printf '  compiler: %s\n' "$(tool_version "$CXX" --version)"
        ;;
      pasteque-sml)
        printf '  source:   %s @ %s\n' "$SML_SRC" \
          "$(git_head "$REPO_ROOT/isabelle/IsaFoL")"
        printf '  compiler: %s\n' "$(tool_version mlton)"
        ;;
      pasteque-llvm)
        printf '  source:   %s @ %s\n' "$LLVM_SRC" \
          "$(git_head "$REPO_ROOT/isabelle/IsaFoL-Pasteque-LLVM")"
        printf '  compiler: %s\n' "$(tool_version "$CLANG" --version)"
        ;;
    esac
  done
} >> "$OUT/build-info.txt"

bold "==> done"
ls -l "$OUT"
