#!/usr/bin/env bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Always build from the slides directory, regardless of the caller's cwd
cd "$(dirname "$0")"

# Unset SOURCE_DATE_EPOCH to use current date in LaTeX
unset SOURCE_DATE_EPOCH

echo -e "${GREEN}Starting slides watch mode with Tectonic...${NC}"
echo -e "${GREEN}Watching for changes to .tex, .bib, .sty and image files...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

build() {
    tectonic --print main.tex 2>&1 | grep -v "note:"
    tectonic --print main-notes.tex 2>&1 | grep -v "note:"
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
        echo -e "${GREEN}Build successful at $(date +%H:%M:%S)${NC}"
    else
        echo -e "${RED}Build failed at $(date +%H:%M:%S)${NC}"
    fi
}

# Initial build
build

# Watch loop using find + sleep
LAST_HASH=""
while true; do
    # Calculate hash of all relevant files (excluding the generated main.pdf)
    CURRENT_HASH=$(find . \( -name "*.tex" -o -name "*.bib" -o -name "*.sty" \
        -o -name "*.png" -o -name "*.jpg" -o -name "*.pdf" \) ! -path "./main.pdf" \
        -print0 | xargs -0 md5sum 2>/dev/null | md5sum)

    if [ "$LAST_HASH" != "$CURRENT_HASH" ] && [ -n "$LAST_HASH" ]; then
        echo -e "\n${YELLOW}Change detected, rebuilding...${NC}"
        build
    fi

    LAST_HASH=$CURRENT_HASH
    sleep 1
done
