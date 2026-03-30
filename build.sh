#!/bin/bash
set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting LaTeX compilation with Tectonic...${NC}"

# Step 1: Check titlepage
echo -e "${YELLOW}Step 1: Checking titlepage...${NC}"
if [ ! -f "titlepage/Thesis_Titlepage.pdf" ]; then
    echo -e "${RED}Error: titlepage/Thesis_Titlepage.pdf not found${NC}"
    echo -e "${RED}The titlepage PDF must be pre-built and committed to the repository${NC}"
    exit 1
fi
echo -e "${GREEN}Titlepage PDF found${NC}"

# Step 2: Build with Tectonic (V1 mode for compatibility)
echo -e "${YELLOW}Step 2: Building document with Tectonic...${NC}"

# Check if user wants to keep intermediate files for debugging
if [ "$1" == "--keep-intermediates" ]; then
    echo -e "${YELLOW}Keeping intermediate files for debugging...${NC}"
    tectonic -X compile --keep-intermediates --print main.tex
else
    tectonic -X compile --print main.tex
fi

echo -e "${GREEN}Compilation completed successfully!${NC}"
echo -e "${GREEN}Output: main.pdf${NC}"

# Optional: Clean auxiliary files
if [ "$1" == "--clean" ]; then
    echo -e "${YELLOW}Cleaning auxiliary files...${NC}"
    ./clean.sh
fi
