#!/bin/bash

# Clean auxiliary files from LaTeX compilation

echo "Cleaning auxiliary files..."

# Main directory
rm -f *.aux *.log *.out *.toc *.lof *.lot *.bbl *.blg *.bcf *.run.xml *.fls *.fdb_latexmk *.synctex.gz *.idx *.ilg *.ind *.glo *.gls *.glg *.acn *.acr *.alg *.ist

# Titlepage directory
rm -f titlepage/*.aux titlepage/*.log titlepage/*.out titlepage/*.synctex.gz

# Sections directory
rm -f sections/*.aux

echo "Cleanup complete!"
