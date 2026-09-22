# Isabelle Theories for the Thesis
This folder contains all contributed Isabelle theories. It is organized as follows:
- `./IsaFoL` - The original [IsaFol repository](https://github.com/IsaFoL/IsaFoL) including Mathias Fleury's Pastèque with Standard ML backend for performance comparisons.
- `./isabelle_llvm` - Peter Lammich's [Isabelle-LLVM](https://github.com/lammich/isabelle_llvm) for generating verified LLVM code from Isabelle.
- `./mirror-afp-2025-1` - The 2025-1 version of the (github mirror of) the Isabelle [Archive of Formal Proofs](https://www.isa-afp.org/).
- `./IsabelleBigInteger` - A fork of Mihai Spinei and Peter Lammich's [IsabelleBigInteger](https://github.com/mspinei/IsabelleBigInteger) project, extending it with change of basis (**main contribution of this thesis**).
- `./IsaFoL-Pasteque-LLVM` - A fork of the original [IsaFol repository](https://github.com/IsaFoL/IsaFoL) where we port Pastèque to LLVM using the IsabelleBigInteger implementation.
- `./isabelle-emacs` - Mathias Fleury's [Emacs setup](https://github.com/m-fleury/isabelle-emacs) for writing Isabelle theories in Emacs.

ToDo:
- [ ] Parser should build Isabelle lists directly to avoid import functions in CodeExport theory (verified string -> big int could still be used)
- [x] Implement resizing for the hashmap and hashset. Load gets quite bad with fixed size
- [ ] Migrate strings to larray_assn - should make equality check much faster and is relatively simple (just have to implement copy free, equality (where one can use length) and lt)
- [ ] Use `signed_big_int_mult_limb_aux` for string -> big int parsing. Right now, 10 is directly represented by bigint which is bad.
