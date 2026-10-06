#!/usr/bin/env bash
# Build the parse-only variants of both Pasteque backends and collect the
# binaries in ./parsers.
# Dependencies: mlton, clang, make. The devshell of ./flake.nix provides them:
#
#   nix develop -c ./collect-parsers.sh
#
#   parse-sml    parser.sml and checker.ML of IsaFoL/PAC_Checker2/code with the
#                driver ./parse-sml.sml instead of pasteque.sml.
#   parse-llvm   parser.c, term.ll and pasteque.ll of
#                IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/code with the driver
#                ./parse-llvm.c instead of main.c.
#
# Both are compiled exactly like the full checkers in ../main (same sources,
# same flags); only the driver differs. They take <polys> <proof> <spec> and
# print `key value` lines with the wall clock time per file; see the drivers.
#
# Usage:
#   ./collect-parsers.sh              # build both
#   ./collect-parsers.sh parse-sml    # build a subset
#   ./collect-parsers.sh --clean      # remove build/ and parsers/
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$EVAL_DIR/../.." && pwd)"

SML_SRC="${SML_SRC:-$REPO_ROOT/isabelle/IsaFoL/PAC_Checker2/code}"
LLVM_SRC="${LLVM_SRC:-$REPO_ROOT/isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/code}"
CLANG="${CLANG:-clang}"

BUILD="$EVAL_DIR/build"
OUT="$EVAL_DIR/parsers"

# What `make pasteque` in the LLVM code directory needs, without main.c.
LLVM_FILES=(Makefile parser.c lib_isabelle_llvm.c parser.h pasteque.h term.h
            pasteque.ll term.ll)

ALL=(parse-sml parse-llvm)

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

selected=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '$d'
               exit 0 ;;
    --clean)   rm -rf "$BUILD" "$OUT"; echo "removed $BUILD and $OUT"; exit 0 ;;
    parse-sml|parse-llvm) selected+=("$arg") ;;
    *)         die "unknown argument '$arg'; known: ${ALL[*]}, --clean" ;;
  esac
done
[ ${#selected[@]} -eq 0 ] && selected=("${ALL[@]}")

mkdir -p "$OUT"

build_parse_sml() {
  bold "==> parse-sml"
  command -v mlton >/dev/null || die "mlton not found (nix develop -c $0)"
  local dir="$BUILD/parse-sml"
  rm -rf "$dir"; mkdir -p "$dir"
  cp "$SML_SRC/checker.ML" "$SML_SRC/parser.sml" \
     "$EVAL_DIR/parse-sml.sml" "$EVAL_DIR/parse-sml.mlb" "$dir/"
  # Same flags as ../main/collect-checkers.sh (isabelle/Makefile target
  # build_pasteque_sml).
  ( cd "$dir" && mlton \
      -output "$OUT/parse-sml" \
      -const 'MLton.safe false' \
      -verbose 1 \
      -default-type int64 \
      -codegen native \
      -inline 700 \
      -cc-opt -O3 \
      parse-sml.mlb )
}

build_parse_llvm() {
  bold "==> parse-llvm"
  local dir="$BUILD/parse-llvm"
  rm -rf "$dir"; mkdir -p "$dir"
  for f in "${LLVM_FILES[@]}"; do
    [ -f "$LLVM_SRC/$f" ] || die "missing $LLVM_SRC/$f"
    cp "$LLVM_SRC/$f" "$dir/"
  done
  # The driver takes the place of main.c, so that the unmodified `pasteque`
  # rule of the upstream Makefile builds it with the flags of the full checker.
  cp "$EVAL_DIR/parse-llvm.c" "$dir/main.c"
  ( cd "$dir" && make CLANG="$CLANG" pasteque )
  cp "$dir/pasteque" "$OUT/parse-llvm"
}

for c in "${selected[@]}"; do
  case "$c" in
    parse-sml)  build_parse_sml ;;
    parse-llvm) build_parse_llvm ;;
  esac
done

bold "==> done"
ls -l "$OUT"
