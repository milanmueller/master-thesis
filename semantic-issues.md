# Semantic issues: thesis text vs. Pastèque/LLVM implementation

Open issues only. Re-checked 2026-10-10 (ninth pass) against
`isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/` (submodule commit `aa574964`),
`isabelle/IsabelleBigInteger/` (`e4e421f`), the Isabelle-LLVM sources in `isabelle/isabelle_llvm/`,
the listing sources in `isabelle-code/`, and `evaluation/main/results/table.tex`. Line numbers refer
to the `.tex` working tree on top of thesis commit `f8bf4e5`. Resolved entries from earlier passes
were removed.

Legend:
  **[W]** wrong claim,
  **[N]** name in the thesis differs from the identifier in the sources,
  **[verify]** could not be checked from the repository.

---

## `sections/multiprecision.tex`

- **Line 200:** open `\todo`.
- Verified fixed: `big_int_rel_size_leq` is closed in `IsabelleBigInteger` commit `e4e421f` and the
  submodule pointer matches, so the `sorry` claim on lines 49–50 holds for the referenced revision
  (the only remaining `sorry` is the deliberate `op_ASSUME_sorry_bind` mechanism).

---

## `sections/datatypes.tex`

No open issues.

- Verified fixed: `\iexp{polynomial}` in the partial-map synonym (line 321).

---

## `sections/fundamentals.tex`

No open issues.

---

## `sections/motivation.tex`

**Vague claim (line 28).** "similar, if not stronger correctness guarantees due to the wide adoption
… and extensive testing and partial verification of the LLVM compiler tools": what is compared is
the trust placed in the compiler toolchain (LLVM vs. MLton), not a correctness guarantee of the
generated code; "similar, if not stronger" is not quantified.

**Scope of the evaluation (line 34).** "evaluate the migrated version against the original Standard
ML version" omits Pacheck, which the evaluation and the abstract (line 7) include.

- Line 14: missing space before `\cite` ("hardware adders\cite{…}"; use `~\cite`).
- Verified fixed: GRAT/`cake_lpr` in the 2026 competition (line 10, confirmed by author); adders
  claim now cited (line 14); "Spinei … with contributions by Lammich" (line 33); "depends on"
  (line 9).

---

## `sections/finalization.tex`

No open issues.

---

## `sections/evaluation.tex`

**Note (benchmark validity).** `checkers/build-info.txt` records the checker commits
(`pasteque-llvm @ 017d6bd4`, `pasteque-sml @ 4abada6b`, `pacheck @ 46001db`) but not the AMulet
commit that produced the certificates (raw data from 2026-10-04). The stored note on AMulet commit
`cff5957` corrupting `-certify` proofs still needs to be ruled out for line 13.

---

## `sections/discussion.tex`

**Line 25: "failing to proof correct even simple fundamental operations".** "proof" is the noun,
"prove" the verb; the infinitive after "failing to" needs the verb ("failing to prove correct …").

---

## `sections/appendix.tex`

**[W] `LPAC_Efficient_Checker_Correctness` is in `ROOT` now.** The session `ROOT` lists it
(line 63, uncommented), but the table omits it and the trailing comment (lines 93–94) says
"commented out in ROOT". The row for `PAC_Checker_Synthesis` ("correctness theorem commented out",
line 84) is still accurate: `PAC_full_correctness` is commented out at
`PAC_Checker_Synthesis.thy:1143`.

**Inconsistent "not in ROOT" marking.** `LPAC_Step_Assn_Array` is marked "Not listed in ROOT;
imported" (line 72), but `PAC_Polynomials_Assn_Array` (line 60) is also absent from `ROOT` and is
not marked.

---

## `sections/abstract.tex`

- Line 5: "to a newer LLVM code" (missing "backend").
- Line 9: open `\todo`.

---

## `sections/acknowledgements.tex`

- Line 4: "this this thesis" (doubled word).

---

## Cross-cutting

- **Label mismatch.** `sec:methodology_high-level-representation-of-polynomials` still labels
  §Pastèque (`fundamentals.tex:384`).
- **Near-duplicate labels.** `sec:lists-with-tail-pointers` (`datatypes.tex:38`, subsection) vs.
  `lists-with-tail-pointers` (`datatypes.tex:271`, subsubsection).
- **Open `\todo`s:** `multiprecision.tex:200`, `abstract.tex:9`.
