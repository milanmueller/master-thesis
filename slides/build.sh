#!/usr/bin/env bash
set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Always build from the slides directory, regardless of the caller's cwd
cd "$(dirname "$0")"

# Unset SOURCE_DATE_EPOCH to use current date in LaTeX
unset SOURCE_DATE_EPOCH

echo -e "${GREEN}Starting slides compilation with Tectonic...${NC}"

if [ "$1" == "--keep-intermediates" ]; then
    echo -e "${YELLOW}Keeping intermediate files for debugging...${NC}"
    tectonic -X compile --keep-intermediates --print main.tex
    tectonic -X compile --keep-intermediates --print main-notes.tex
else
    tectonic -X compile --print main.tex
    tectonic -X compile --print main-notes.tex
fi

echo -e "${GREEN}Compilation completed successfully!${NC}"
echo -e "${GREEN}Output: slides/main.pdf (audience), slides/main-notes.pdf (pympress)${NC}"
