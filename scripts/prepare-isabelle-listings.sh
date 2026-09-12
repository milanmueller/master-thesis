#!/bin/bash
# Generates rendering-only copies of the Isabelle theory files used by
# \isabellecodeextern, with the "\<comment>" marker rewritten to the classic
# Isar "--" comment marker. The original theory files are left untouched.
#
# This exists because the `listings` package cannot recognize a genuine
# multi-byte Unicode character (e.g. an em dash) as a comment delimiter, and
# it cannot use `literate` to substitute the display text of a string that is
# itself a comment delimiter.
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/build/isabelle-listings"

FILES=(
  "isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/IICF_PartialMap.thy"
)

while IFS= read -r -d '' thy; do
  FILES+=("${thy#"$REPO_ROOT/"}")
done < <(find "$REPO_ROOT/isabelle-code" -name '*.thy' -print0 | sort -z)

for rel in "${FILES[@]}"; do
  src="$REPO_ROOT/$rel"
  dst="$OUT_DIR/$rel"
  if [ ! -f "$src" ]; then
    echo "warning: $rel not found, skipping (submodule not checked out?)" >&2
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  perl -pe 's/\Q\<comment>\E/--/g' "$src" > "$dst"
done
