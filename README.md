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

# Unofficial Uni Freiburg Thesis-Template

This is a minimal template for a [german or english bachelor's or master's thesis](output/main.pdf).

It uses the Corporate Design of the University of Freiburg and fulfills the requirements for the technical faculty (e.g. the supervisor is only mentioned in the acknowledgments not in the [sections/information.tex](sections/information.tex)).

**I wish you all the best and let me know about any issues!**

## Prerequisites

This [Video-Explanation](https://www.youtube.com/watch?v=vIImoKpKWIo) gives an overview of the used programs:

### Visual Studio Code (VSC)

[Visual Studio Code (VSC)](https://code.visualstudio.com/)

### TeX Live and LaTeX-Formatter

[TeX Live](https://www.tug.org/texlive/) and the optional [LaTeX-Formatter](https://github.com/cmhughes/latexindent.pl)

install on Linux Mint:

```bash
sudo apt update && sudo apt install texlive-full texlive-extra-utils
```

### VSC Extension LaTeX-Workshop

[VSC Extension LaTeX-Workshop](https://github.com/James-Yu/LaTeX-Workshop)

VSC should ask you to install it.
If not, go to Extensions by pressing CTRL + SHIFT + X and search @recommended.

## Building the Document

### Automated Build Script

This repository includes an automated build script that compiles both the titlepage and main document:

```bash
# Run the build script
bash build.sh

# Clean auxiliary files after building
bash clean.sh
```

The build script:
1. Compiles the titlepage separately from `titlepage/Thesis_Titlepage.tex`
2. Compiles the main document with all references, glossaries, and bibliography
3. Includes the titlepage PDF in the final output
4. Runs multiple passes to resolve all references

### GitHub Actions

The repository is configured with GitHub Actions to automatically build the PDF on every commit to `main` or `develop` branches. The compiled PDF is available as a downloadable artifact in the Actions tab for 90 days.

### Manual Compilation with VSC

You can also compile the document manually using Visual Studio Code with the LaTeX Workshop extension (see Prerequisites section below).

## Usage

### Cover

#### Get Cover

The official template for the cover is from the Corporate Design of the University of Freiburg:

<https://cd.uni-freiburg.de/buerovorlagen/#latex-vorlagen>

1. Download it.
2. Extract it.
3. Open it in VSC.
4. Delete the german or english directory that you don't want to use.
5. Compile it.

If you have any issues, make it one single file:
Open the .tex-file that is not `setup.tex`, replace

```TeX
\input{setup}
```

with the content of `setup.tex` and delete `setup.tex`.

#### Insert Cover

1. Rename the compiled PDF to `cover.pdf`.
2. Copy it into the `assets` directory.
3. Compile the thesis.
4. Check the cover in the PDF.

### Hints

More hints and examples are given in the file [sections/conclusion.tex](sections/conclusion.tex).

There is also a Guide written by the Github Copilot, checked by hand:
[GUIDE_AI_Generated.md](GUIDE_AI_Generated.md)
Everything else in this archive is not written by AI.

### Known Issues

#### No PDF

Sometimes there is no PDF generated, especially when you open the project for the first time.
Just wait a few seconds, recompile and if it still doesn't work, restart VSC or your computer.

#### Generated Files Not In Output-Folder Or Glossaries Do Not Work

The `.vscode`-folder must be directly inside the folder you opened in VSC.

E.g. if you open the folder `thesis` which contains `latex` which contains `.vscode`
you should move or copy the `.vscode` directly into `thesis`
or open the `latex`-folder directly to compile the PDF.

The best way is to open the folder you cloned/downloaded from here always separately in VSC.

#### ChkTeX-Errors

If `\LaTeX` or similar commands without parenthesis produce the following error:

```
1: Command terminated with space.
```

You can add the command to the `.chktexrc`-file. The file provides more infos.

You can also handle other errors in there.
