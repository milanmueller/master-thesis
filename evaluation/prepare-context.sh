#!/usr/bin/env bash
# Stage the sources of all three PAC checkers into a small Docker build context.
#
# We deliberately do not use the repository root as build context: it contains
# isabelle/.isabelle (~10 GB of heaps and components) and the Isabelle/AFP
# submodules. Everything the image needs is a handful of small files.
#
# Nothing here runs Isabelle. The generated code (checker.ML, *.ll) must already
# exist in the working tree; see README.md for how to (re)generate it.
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$EVAL_DIR/.." && pwd)"

PACHECK2_SRC="$EVAL_DIR/pacheck2"
SML_SRC="$REPO_ROOT/isabelle/IsaFoL/PAC_Checker2/code"
LLVM_SRC="$REPO_ROOT/isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker2/code"

CTX="$EVAL_DIR/.ctx"
INSTANCES="$EVAL_DIR/instances"

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

die() { red "error: $*"; exit 1; }

# --- preflight -------------------------------------------------------------

[ -f "$PACHECK2_SRC/configure.sh" ] || die \
  "pacheck2 sources missing at $PACHECK2_SRC. Run: git submodule update --init evaluation/pacheck2"

[ -f "$SML_SRC/checker.ML" ] || die \
  "$SML_SRC/checker.ML missing. It is the Isabelle-exported ML code for the shared
       (Efficient) checker and is normally committed. Regenerate it from the repo root with:
         cd $REPO_ROOT/isabelle && mk build_pasteque_sml"

missing=()
for f in Makefile parser.c parser.h pasteque.h pasteque_shared.h pasteque.ll pasteque_shared.ll; do
  [ -f "$LLVM_SRC/$f" ] || missing+=("$f")
done
if [ ${#missing[@]} -gt 0 ]; then
  die "missing in $LLVM_SRC: ${missing[*]}
       The .ll/.h files are gitignored (working tree only). Regenerate them with:
         cd $REPO_ROOT/isabelle && isabelle build \\
           -d mirror-afp-2025-1/thys -d isabelle_llvm/thys -d IsabelleBigInteger \\
           -d IsaFoL-Pasteque-LLVM PAC_Checker2_LLVM"
fi

# Sanity-check that the two LLVM exports really are the two different checkers.
# The exported IR is generated from one theory by two export_llvm invocations,
# and the entry points differ only in name, so a stale or mis-targeted export
# would silently turn the comparison into a self-comparison.
llvm_variant_mismatch=false
check_variant() {
  local file="$1" want="$2" label="$3"
  if ! grep -q "@$want" "$LLVM_SRC/$file"; then
    llvm_variant_mismatch=true
    warn "WARNING: $file does not reference $want."
    warn "         The $label LLVM checker is not what will be benchmarked."
    warn "         Re-run the PAC_Checker2_LLVM export (see README.md), then re-run this script."
  fi
}
check_variant pasteque.ll LPAC_Checker_Synthesis_full_checker_l3_impl "non-shared"
check_variant pasteque_shared.ll LPAC_Efficient_Checker_Synthesis_full_checker_l_s3_impl "shared-variables"

# --- stage -----------------------------------------------------------------

rm -rf "$CTX"
mkdir -p "$CTX/pacheck2" "$CTX/sml" "$CTX/llvm" "$CTX/bench"

# pacheck2: sources only. Anything configure.sh/make produced on the host
# (makefile, build/, pacheck) is left behind so the image builds from scratch.
cp -r "$PACHECK2_SRC/src" "$CTX/pacheck2/src"
cp "$PACHECK2_SRC/configure.sh" "$PACHECK2_SRC/makefile.in" "$CTX/pacheck2/"
chmod +x "$CTX/pacheck2/configure.sh"

# pasteque, SML backend: the shared/"Efficient" variant lives directly in code/
# (code/no_sharing/ has no checker.ML and is out of scope).
cp "$SML_SRC/checker.ML" "$SML_SRC/parser.sml" "$SML_SRC/pasteque.sml" \
   "$SML_SRC/pasteque.mlb" "$CTX/sml/"

# pasteque, LLVM backend: both variants share parser.c; the .ll files carry the
# verified checker.
cp "$LLVM_SRC/Makefile" "$LLVM_SRC/parser.c" "$LLVM_SRC/parser.h" \
   "$LLVM_SRC/pasteque.h" "$LLVM_SRC/pasteque_shared.h" \
   "$LLVM_SRC/pasteque.ll" "$LLVM_SRC/pasteque_shared.ll" "$CTX/llvm/"

cp "$EVAL_DIR/checkers.json" "$CTX/checkers.json"
cp "$EVAL_DIR/bench/run_bench.py" "$EVAL_DIR/bench/report.py" "$CTX/bench/"

# Provenance of everything we just staged, so the report can qualify the numbers.
git_describe() {
  git -C "$1" rev-parse --short HEAD 2>/dev/null || echo unknown
}
cat > "$CTX/build-info.json" <<EOF
{
  "pacheck2_commit": "$(git_describe "$PACHECK2_SRC")",
  "isafol_commit": "$(git_describe "$REPO_ROOT/isabelle/IsaFoL")",
  "isafol_llvm_commit": "$(git_describe "$REPO_ROOT/isabelle/IsaFoL-Pasteque-LLVM")",
  "llvm_variant_mismatch": $llvm_variant_mismatch
}
EOF

# --- instances -------------------------------------------------------------

mkdir -p "$INSTANCES"
if [ -z "$(ls -A "$INSTANCES" 2>/dev/null)" ]; then
  cp "$PACHECK2_SRC"/example/example.input \
     "$PACHECK2_SRC"/example/example.proof \
     "$PACHECK2_SRC"/example/example.target "$INSTANCES/"
  info "seeded $INSTANCES from pacheck2/example"
fi

info "build context ready: $CTX"
