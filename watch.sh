#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting LaTeX watch mode with Tectonic...${NC}"

# Step 1: Check titlepage
echo -e "${YELLOW}Step 1: Checking titlepage...${NC}"
if [ ! -f "titlepage/Thesis_Titlepage.pdf" ]; then
    echo -e "${RED}Error: titlepage/Thesis_Titlepage.pdf not found${NC}"
    echo -e "${RED}The titlepage PDF must be pre-built and committed to the repository${NC}"
    exit 1
fi
echo -e "${GREEN}Titlepage PDF found${NC}"

# Step 2: Start watch mode
echo -e "${YELLOW}Step 2: Starting watch mode...${NC}"
echo -e "${GREEN}Watching for changes to .tex and .bib files...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Initial build
tectonic --print main.tex 2>&1 | grep -v "note:"

# Watch loop using find + sleep
LAST_HASH=""
while true; do
    # Calculate hash of all relevant files
    CURRENT_HASH=$(find . -name "*.tex" -o -name "*.bib" | grep -v "./build/" | xargs md5sum 2>/dev/null | md5sum)

    if [ "$LAST_HASH" != "$CURRENT_HASH" ] && [ -n "$LAST_HASH" ]; then
        echo -e "\n${YELLOW}Change detected, rebuilding...${NC}"
        if tectonic --print main.tex 2>&1 | grep -v "note:"; then
            echo -e "${GREEN}Build successful at $(date +%H:%M:%S)${NC}"
        else
            echo -e "${RED}Build failed at $(date +%H:%M:%S)${NC}"
        fi
    fi

    LAST_HASH=$CURRENT_HASH
    sleep 1
done
