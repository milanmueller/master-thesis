# Isabelle Theories for the Thesis
This folder contains all contributed Isabelle theories. It is organized as follows:
- `./IsaFoL` - The original [IsaFol repository](https://github.com/IsaFoL/IsaFoL) including Mathias Fleury's Pastèque with Standard ML backend for performance comparisons.
- `./isabelle_llvm` - Peter Lammich's [Isabelle-LLVM](https://github.com/lammich/isabelle_llvm) for generating verified LLVM code from Isabelle.
- `./mirror-afp-2025-1` - The 2025-1 version of the (github mirror of) the Isabelle [Archive of Formal Proofs](https://www.isa-afp.org/).
- `./IsabelleBigInteger` - A fork of Mihai Spinei and Peter Lammich's [IsabelleBigInteger](https://github.com/mspinei/IsabelleBigInteger) project, extending it with change of basis (**main contribution of this thesis**).
- `./IsaFoL-Pasteque-LLVM` - A fork of the original [IsaFol repository](https://github.com/IsaFoL/IsaFoL) where we port Pastèque to LLVM using the IsabelleBigInteger implementation.
- `./isabelle-emacs` - Mathias Fleury's [Emacs setup](https://github.com/m-fleury/isabelle-emacs) for writing Isabelle theories in Emacs.

ToDo:
- [x] LLVM Makefile should have `-flto` flag enabled!
- [ ] Reimplement `cl_length` using `cl_fold'`, should be a lot cleaner and we could even give it
      a nice capped version, c.f. LLVM_String.thy
- Simplify manual `cl_fold_rule` proof chains via the new `cl_fold_hfref` registration lemma
  (`PAC_Checker_LLVM/IICF_Copying_List.thy`). Each site becomes a one-line `lemmas` composition;
  the step/walk auxiliary lemmas get deleted.
  - Tier 1 — works with `cl_fold_hfref` as is (body `.refine` matches `R^d *a A^k -->a R`):
    - [ ] `union_vars_monom_impl_hnr` (`PAC_Checker_Synthesis.thy:163`) + delete `insert'_step_rule` (156)
    - [ ] `union_vars_poly_impl_hnr` (`PAC_Checker_Synthesis.thy:199`) + delete `union_vars_poly_inner_step_rule` (192)
    - [ ] prerequisite for both: `cl_fold_hfref_swap` corollary (registered rules are list-first,
          `cl_fold_hfref` concludes accumulator-first)
  - Tier 2 — needs pure-accumulator mode weakening (`^k` -> `^d` is free for pure assertions,
    or just re-annotate the inner synthesis with `^d`):
    - [ ] `fnv1a_of_strl_hnr` (`LLVM_String.thy:81`) + delete `fnv1a_of_strl_inner_rule` (53),
          `fnv1a_of_strl_inner_rule'` (66), `fnv1a_of_strl_walk_rule` (74) incl. the ad-hoc
          pure-`R` trick
  - Tier 3 — needs the parameterized (`Q^k`, captured-argument) variant of `cl_fold_hfref`
    (derive from the already-proven Phi-generalized `cl_fold_rule'` + a `k1_d1_k1` bridge in
    `Assn_Env.thy`):
    - [ ] `vars_of_monom_in_impl_hnr` (`PAC_Checker_Synthesis.thy:79`) + delete `fold_inner_step_rule` (60),
          `vars_of_monom_walk_rule` (70)
    - [ ] `vars_of_poly_in_impl_hnr` (`PAC_Checker_Synthesis.thy:130`) + delete
          `vars_of_poly_in_inner_step_rule` (108), `vars_of_poly_walk_rule` (118)
    - Note: the planned `mult_poly_raw` loops (inner row-builder capturing `pm`, outer loop
      capturing `q`) are also Tier-3 instances — the `Q^k` variant pays for four sites at once.
  - Not a candidate: `sort_all_coeffs` (`PAC_Polynomials_Operations.thy:839`) — body is a genuine
    `SPEC`, outside the pure-`foldl` fragment; would need an `hn_refine`-level combinator.
- Migrate `BigInt_String.thy` onto the canonical ASCII semantics in `LLVM_ASCII_String.thy`
  (goal: one semantic stack, and the parse/print round-trip pair at the same assertion:
  `(str_sval_impl, RETURN o id) : str_int_assn^d ->a sbi_assn` and
  `(print_sbi_ascii_impl, RETURN o id) : sbi_assn^d ->a str_int_assn`).
  - [ ] Import direction: `BigInt_String` imports `LLVM_ASCII_String`; delete `BigInt_String`'s
        duplicate high-level layer and replace uses by the canonical constants. Renaming map
        (old -> new): `char_val` -> `char_uval`, `is_ascii_num` -> `is_ascii_unum`,
        `is_ascii_num_str` -> `is_ascii_unum_str`, `str_val` -> `str_uval`,
        `int_of_str` -> `str_sval`, `is_ascii_int` -> `is_ascii_snum_str`, plus the clashing
        `ascii_str_nat_rel`/`ascii_str_int_rel`/`ascii_hyphen` (old `ascii_hyphen` is a nat
        abbreviation, new one is a `char` definition with an hnr producer for `0x2D`).
  - [ ] Rebase the `str_val`-based proofs from the positional (`zip`/`exps`) formulation onto the
        Horner `str_uval`. `dec_val` is already Horner-shaped (`foldl (\acc d. acc*10 + unat d)`),
        so `str_val_ascii_of_digits` / `is_ascii_num_str_ascii_of_digits` should get *simpler*;
        alternatively prove `str_val = str_uval` once (accumulator-generalized induction, cf.
        `foldl_dec_shift`) and keep the old proofs unchanged.
  - [ ] Restate `print_bi_ascii_correct'` / `print_sbi_ascii_correct'` against the canonical
        relations; redefine `ascii_ws_nat_rel`/`ascii_ws_int_rel` as
        `<char_rel>list_rel O ascii_str_{nat,int}_rel` over the canonical string relations.
  - [ ] Finish the commented-out `print_sbi_ascii_hnr` stub: fref from `print_sbi_ascii_correct'`
        (`[\_. True]_f signed_big_int_rel -> <ascii_ws_int_rel>nres_rel`) + FCOMP with
        `fcomp_norm_unfold = sbi_assn_def[symmetric]` gives
        `sbi_assn^d ->a hr_comp ascii_strl_assn ascii_ws_int_rel`.
  - [ ] The one genuinely new lemma — `cl_assn'` parametricity for pure element assertions:
        `hr_comp (cl_assn' (word_assn' TYPE(8))) <char_rel>list_rel = cl_assn' char_assn`
        (induction over cl segments, two-stage pure/AC discipline). With `hr_comp_assoc` this
        collapses the print rule's result assertion to `str_int_assn` — round trip complete.
  - [ ] Cleanup on the way: drop `word_char_rel`/`char_word_rel` (duplicates of `Char_Assn.char_rel`
        modulo direction), drop the commented-out `print_bi_ascii_refine` block, unify the hyphen
        constants (`word_hyphen`/`char_hyphen` vs `ascii_hyphen`).
  - [ ] Wire `LLVM_ASCII_String` -> `BigInt_String` into the `PAC_Checker_LLVM` ROOT and extend
        the `PAC_LASCII` scratch session to target `BigInt_String` for the migration loop.
  - Optional follow-up (independent): generalize the base-10 digit extraction to a bounded base
    (`bi_div_by_w64` and `divmod2by1` are already base-generic; parameterize `dec_val` +
    `dec_of_big_int` by `1 < beta`, keep the ASCII layer pinned to 10).
- Runtime overflow check for polynomial ids (prerequisite for porting
  `remap_polys_l4`/`full_checker_l3` to `PAC_Checker_LLVM` and getting a runnable checker).
  The LLVM port caps ids where Imperative-HOL/MLton allowed arbitrary precision; decision: check
  at runtime in the *verified* checker (new error message), not only via parser typing.
  Uniform bound: `id <= 2^63 - 3` — remap needs `upper_bound_on_dom < max_snat 64 - 1`
  (i.e. `max_id + 1 < 2^63 - 1`), tighter than `step_id_bounded`'s `id + 1 < max_snat 64`; use
  the tighter bound everywhere. Key point: compare against the *literal* `2^63 - 3` (snat-representable,
  no arithmetic) — the naive `id + 1 < 2^63` form is not synthesizable (constant `2^63` exceeds
  `max_snat 64`, and the `id + 1` snat addition has a circular overflow side condition).
  - [ ] C parser (`IsaFoL-Pasteque-LLVM/PAC_Checker2/code/parser.c`): parse ids as *signed*
        `int64_t` (`strtoll`), rejecting negatives AND `ERANGE` (never accept the clamped
        `INT64_MAX`). This guarantees every id entering the importer is a valid snat, so ids can
        cross the import boundary at `si64_assn` and the verified bound check is a plain snat
        comparison (no unat entry / MSB gymnastics needed). Trusted, but the parser is trusted
        for faithful representation anyway.
  - [ ] Input polynomial ids: check lives in the ported `remap_polys_l4`
        (`PAC_Checker_LLVM/LPAC_Checker_Synthesis.thy`), as a second error case beside the
        existing duplicate-id branch. Absorbed by `remap_polys_l`'s nondeterministic
        `failed <- SPEC(\_. True)` branch (`PAC_Checker.thy:445`), so it refines under plain
        `\<Down>Id` — no abstract definition or spec changes.
  - [ ] Step ids: replace the `ASSERT (list_all step_id_bounded st)` threading in
        `full_checker_l2`/`l3` by an upfront runtime check over the step list returning a new
        error message. This no longer refines `full_checker_l2` under `Id`; compose two-case at
        the specification level instead (`PAC_checker_specification` guards everything with
        `\<not>is_failed b`, so the error branch is vacuous; the bounded branch reuses the
        existing chain).
  - [ ] New error message constant in `PAC_Checker_LLVM/PAC_Checker_Error.thy` (semantically
        free: messages are `SPEC(\_. True)`/capped, only the `CFAILED` tag enters the theorem).
