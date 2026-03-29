# Repository for my Master Thesis
Based on the [Fachschaft's template for Theses](https://github.com/leanderbuerkin/latex-template-uni-freiburg?tab=readme-ov-file).

# Project Description
TODO

# Milestones
- [ ] Implementation in Isabelle:
  - [ ] Support for integers - previous implementation only supports natural numbers so far
  - [ ] Base exchange between arbitrary bases - first we start with a naive, fast version
  - [ ] Conversion to string, i.e. printing (using conversion to base 10)
- [ ] Port Pastèque to Isabelle-LLVM
  - [ ] Rewrite parser in c, to eliminate SML dependence
  - [ ] (optional) Add support for integer sharing
- [ ] Experiment/Evaluation - compare the performance of
  - [ ] Pastèque using the SML backend
  - [ ] Pastèque using the LLVM backend
  - [ ] (optional) Pastèque using LLVM with GMP bindings
- [ ] Write Thesis

# Building the Document

## Automated Build Script

This repository includes an automated build script that compiles both the titlepage and main document:

```bash
# Run the build script
bash build.sh

# Clean auxiliary files after building
bash clean.sh
```

The build script:
1. Compiles the main document with all references, glossaries, and bibliography
2. Includes the (precompiled) titlepage PDF in the final output
3. Runs multiple passes to resolve all references

Note that the titlepage is only included as a rendered pdf. The latex code for the template of the titlepage can be accessed [here](https://cd.uni-freiburg.de/buerovorlagen/#latex-vorlagen) for members and students of the university Freiburg.

## GitHub Actions

The repository is configured with GitHub Actions to automatically build the PDF on every commit to `main`.
The latest version of the thesis PDF is automatically published via GitHub Pages and is permanently available at:

**https://milanmueller.github.io/master-thesis/main.pdf**

This URL always points to the most recent build from the `main` branch.
