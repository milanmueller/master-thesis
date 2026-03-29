#!/bin/bash

# Clean auxiliary files from LaTeX compilation
# Note: Tectonic manages its own build directory and cleans up automatically.
# This script is mainly for cleaning up any legacy files from old pdflatex builds.

echo "Cleaning auxiliary files..."

# Main directory - remove legacy pdflatex artifacts
rm -f *.aux *.log *.out *.toc *.lof *.lot *.bbl *.blg *.bcf *.run.xml *.fls *.fdb_latexmk *.synctex.gz *.idx *.ilg *.ind *.glo *.gls *.glg *.acn *.acr *.alg *.ist

# Titlepage directory
rm -f titlepage/*.aux titlepage/*.log titlepage/*.out titlepage/*.synctex.gz

# Sections directory
rm -f sections/*.aux

# Remove Tectonic build directory if requested
if [ "$1" == "--all" ]; then
    echo "Removing Tectonic build directory..."
    rm -rf build/
fi

echo "Cleanup complete!"
