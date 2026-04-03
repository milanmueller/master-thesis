# Isabelle Theories for the Thesis
This folder contains all contributed Isabelle theories. It is organized as follows:
- `./IsaFoL` - The original [IsaFol repository](https://github.com/IsaFoL/IsaFoL) including Mathias Fleury's Pastèque with Standard ML backend for performance comparisons.
- `./isabelle_llvm` - Peter Lammich's [Isabelle-LLVM](https://github.com/lammich/isabelle_llvm) for generating verified LLVM code from Isabelle.
- `./mirror-afp-2025-1` - The 2025-1 version of the (github mirror of) the Isabelle [Archive of Formal Proofs](https://www.isa-afp.org/).
- `./IsabelleBigInteger` - A fork of Mihai Spinei and Peter Lammich's [IsabelleBigInteger](https://github.com/mspinei/IsabelleBigInteger) project, extending it with change of basis (**main contribution of this thesis**).
- `./IsaFoL-Pasteque-LLVM` - A fork of the original [IsaFol repository](https://github.com/IsaFoL/IsaFoL) where we port Pastèque to LLVM using the IsabelleBigInteger implementation.
- `./isabelle-emacs` - Mathias Fleury's [Emacs setup](https://github.com/m-fleury/isabelle-emacs) for writing Isabelle theories in Emacs.

ToDo:
- Fork IsaFoL (or maybe just Pastèque?) to migrate it to LLVM with custom c parser.
