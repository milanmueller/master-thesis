#!/bin/bash
set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting LaTeX compilation workflow...${NC}"

# Step 1: Check titlepage
echo -e "${YELLOW}Step 1: Checking titlepage...${NC}"
if [ ! -f "titlepage/Thesis_Titlepage.pdf" ]; then
    echo -e "${RED}Error: titlepage/Thesis_Titlepage.pdf not found${NC}"
    echo -e "${RED}The titlepage PDF must be pre-built and committed to the repository${NC}"
    exit 1
fi
echo -e "${GREEN}Titlepage PDF found${NC}"

# Step 2: Compile main document
echo -e "${YELLOW}Step 2: Compiling main document...${NC}"
pdflatex -interaction=nonstopmode main.tex || {
    echo -e "${RED}Failed to compile main document (first pass)${NC}"
    exit 1
}

# Run biber for bibliography if .bcf file exists
if [ -f main.bcf ]; then
    echo -e "${YELLOW}Running biber for bibliography...${NC}"
    biber main || echo -e "${YELLOW}Biber failed or no citations found${NC}"
fi

# Run makeglossaries if glossary is used
if [ -f main.glo ]; then
    echo -e "${YELLOW}Running makeglossaries...${NC}"
    makeglossaries main || echo -e "${YELLOW}Makeglossaries failed or not needed${NC}"
fi

# Second pass for references
echo -e "${YELLOW}Running second pass...${NC}"
pdflatex -interaction=nonstopmode main.tex

# Third pass to ensure everything is resolved
echo -e "${YELLOW}Running third pass...${NC}"
pdflatex -interaction=nonstopmode main.tex

echo -e "${GREEN}Compilation completed successfully!${NC}"
echo -e "${GREEN}Output: main.pdf${NC}"

# Optional: Clean auxiliary files
if [ "$1" == "--clean" ]; then
    echo -e "${YELLOW}Cleaning auxiliary files...${NC}"
    ./clean.sh
fi
