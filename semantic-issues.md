# Semantic issues: thesis text vs. Pastèque/LLVM implementation

Checked against `isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/` (submodule commit `7a1a638d`).
Line numbers refer to the `.tex` sources as of thesis commit `262b4a7` plus working-tree changes.

Legend: 
  **[W]** wrong claim, 
  **[N]** name in the thesis differs from the identifier in the sources, 
  **[R]** listing line range points at the wrong code.

---

## `sections/multiprecision.tex`

### §Relating integers and ASCII encoded strings

**[W] `chars_of_nat` base case (line 160).** The thesis writes `[n]` for `n < 10`; `n` is a `nat`
and the result is a `string`, so this must be `[char_of (n + 48)]` (consistent with the recursive
case on the next line).

**[W] `is_ascii_unum_str :: string → nat` (line 121)** must be `string → bool`.

**[W] `chars_of_int :: int → nat` (line 165)** must be `int → string`.

**[W] `abs :: int → nat` (line 173)** — Isabelle's `abs` on `int` has type `int → int`; the
conversion to `nat` needs `nat ∘ abs` (and `chars_of_nat` expects a `nat`).

**[W] Missing argument (line 127).** `… ∧ is_ascii_unum_str` should be
`… ∧ is_ascii_unum_str cs`.

**[W] `int_ascii_str_rel :: (int, string) :: set` (lines 152 and 174)** — the second `\dbcolon`
should be `\app`, i.e. the type is `(int × string) set`.

**[W] "A given string is continuously divided by 10" (line 181)** — a *number* is divided by 10,
not a string.

---

## `sections/datatypes.tex`

### §Interleaving fold — `dec` type (line 173)

**[W]** "a function $\iexp{dec} \dbcolon \tv{a} \rightarrow \tv{b} \rightarrow \iexp{direction}$".
`LLVM_Interleaving_Fold.thy:16–18` fixes `dec :: 'b ⇒ 'c ⇒ direction` — it inspects the two *list
elements*, not the accumulator. The following sentences correctly use `dec b c`, so only the type
annotation is wrong.

### §Interleaving fold — listing range (line 159)

~~`linerange=11-29` on `PAC_Polynomials_Operations.thy` omits the `fun` keyword on line 10.~~
**Withdrawn.** Every listing taken from `isabelle-code/Lists.thy` starts one line after its
`fun`/`definition` keyword the same way (`algo:llvm-sum` 45-47 after `fun` on 44, `algo:llvm-fold`
51-56 after `definition` on 50, `algo:sum-alt` 59-60 after `definition` on 58), so dropping the
keyword line is the established style here, not a mistake.

### §Lists / assertion names

**[N] `ls_assn` vs. `cl_assn`.** The thesis calls the linked-list refinement assertion `ls_assn`
throughout (introduced at line 84). In the sources it is `cl_assn` / `cl_assn'`
(`LLVM_DS_Copying_List.thy:75–76`), built on `olseg` (line 72) rather than directly on `lseg` and
`list_aux`. The thesis's `list_aux` is the AFP/Isabelle-LLVM `list_assn` (already footnoted), but
`ls_assn` has no counterpart under that name.
Same for the tail-pointer variant: thesis `lst_assn` (line 275) is `clt_assn`
(`LLVM_DS_Copying_List.thy:1199–1205`).

**[N] `str_assn`.** Used at `datatypes.tex:525` and `multiprecision.tex:191`; the sources use
`strl_assn'` (e.g. `PAC_Polynomials_Assn.thy:11`, `LLVM_DS_String.thy:39`).

### §A refinement assertion for lists — `lseg` recursion (lines 68–79)

**[W] The recursive case never binds its own variables.** The thesis writes

```
lseg xs p s = … | ∃q. p ↦ (Node x q) ∗ lseg xs q s  (otherwise)
```

`x` is unbound and the recursive call passes the *whole* list `xs` instead of its tail, so the
equation is not well founded. It must destructure `xs = x # xs'` and recurse on `xs'`. The bullet
list underneath (line 79, "for the tail of the list it must hold that $\iexp{lseg}\,xs\,q\,s$")
repeats the same slip.

### §Non-destructive list access using `foldl`

**[W] `64 word cl_list = 64 word ptr` (line 102).** A list is a pointer to a *node*, as stated at
line 45. `LLVM_DS_Copying_List.thy` uses `'a cl_list = 'a node ptr`, so the equation should read
`64 word cl_list = 64 word node ptr`.

**[W] `sum'` is applied to three arguments (line 146).** `isabelle-code/Lists.thy:58–60` defines

```isabelle
definition sum' :: \<open>nat list \<Rightarrow> nat\<close> where \<open>sum' = foldl (+) 0\<close>
```

so the refinement lemma must use `sum' xs`, not `sum' (+) 0 xs` (twice in the same display).
`fundamentals.tex:317` also writes `sum' xs`, so the two uses disagree.

**[W/R] The listed `ll_foldl` had its arguments swapped (`algo:llvm-fold`, line 124).**
**Fixed.** `isabelle-code/Lists.thy:51–56` read

```isabelle
ll_foldl :: \<open>('a \<Rightarrow> 'b \<Rightarrow> 'a llM) \<Rightarrow> 'a \<Rightarrow> 'b node ptr \<Rightarrow> 'a llM\<close>
  \<open>ll_foldl f a p \<equiv> … ll_foldl f (node.next n) a\<close>
```

where the recursive call passed the next-pointer as the accumulator and the accumulator as the
pointer. The call is now `ll_fold f a (node.next n)`, and the function was renamed
`ll_foldl` → `ll_fold` to match the thesis text.
Note that the demo theory's `ll_fold` is still a separate illustration: the function actually used
in Pastèque is `cl_fold` in `LLVM_DS_Copying_List.thy`, which the footnote at `datatypes.tex:128`
points at.

### §A generic merge sort implementation for lists

**[N] `linord_assn`.** Used at `datatypes.tex:23, 239`; the locale in the sources is
`linorder_assn` (interpreted e.g. at `PAC_Polynomials_Assn.thy:20`).

### §Partial maps — requirement 3 (lines 304–306)

**[W] Inverted wording.** "This would result in a runtime error, but the state where a slot is
inhabited must still be representable." The requirement being motivated is that *empty*
(uninhabited) slots be representable — an inhabited slot is trivially representable.

### §High-level refinement of partial map by list of optionals

**[W] `opt_list_update` drops the `Some` (line 342).** The thesis writes
`(ol @ None^(k + 1 - length m))[k := v]`. `LLVM_DS_Partial_Map.thy:65`:

```isabelle
definition \<open>opt_list_update k v m \<equiv> (m @ replicate (k + 1 - length m) None)[k:=Some v]\<close>
```

The list has element type `'a option`, so the update must insert `Some v`.
(The bound variable is also inconsistent: the definition binds `ol` but the body says `length m`.)

**[W] Missing result types in the operation signatures (lines 331, 340).**
`opt_list_lookup :: nat → 'a option list` must be `nat → 'a option list → 'a option`, and
`opt_list_update :: nat → 'a → 'a option list` must be
`nat → 'a → 'a option list → 'a option list` (cf. `LLVM_DS_Partial_Map.thy:65, 69`).

**[W] `opt_list_α` result type (line 318).** Stated as
`'a option list → nat → 'a`; it yields a partial map, i.e. `'a option list → nat → 'a option`
(the definition's own `None` branch shows this). The surrounding prose likewise calls the abstract
type "a partial map `nat → 'a`" where it is `nat ⇀ 'a`.

### §Partial maps — `llist_polynomial` coefficient type

**[W] `nat` instead of `int`.** `datatypes.tex:160` states
`llist_polynomial = (string list × nat) list` and line 181 states that `monomial` abbreviates
`(string list × nat)`. `PAC_Polynomials_Term.thy:40–41`:

```isabelle
type_synonym term_poly_list = \<open>string list\<close>
type_synonym llist_polynomial = \<open>(term_poly_list \<times> int) list\<close>
```

Coefficients are `int`. This also contradicts `fundamentals.tex:382` (`monomial = term × int`),
and the whole point of §Signed Arbitrary Precision Integers is that coefficients are signed.

### §Low-level refinement of lists of optionals — listing range (line 410)

**[R]** `linerange=346-358` on `LLVM_DS_Partial_Map.thy` points at `lemma pmap_len_hnr`, not at the
update function. `pmap_update` is defined at lines **379–392**. The caption
("Implementation of the update function on partial maps at llM level (actual Isabelle source
code)") therefore does not match the rendered listing.

### §Low-level refinement of lists of optionals — `pmap_update` precondition (line 419)

**[W] Off-by-one bound.** The thesis Hoare-triple carries `↑(k + 1 < 2^63 - 1)`.
`LLVM_DS_Partial_Map.thy:450–454` has

```isabelle
\<up>\<^sub>d(k + 1 < max_snat 64)
```

and `max_snat 64 = 2^63`, so the precondition is `k + 1 < 2^63`.

**[W] Variable clash in the same triple.** The precondition reads
`snat64_assn k ki ∗ A a ai pmap_assn xs ai`: `ai` denotes both the refined value and the refined
array, a `∗` is missing between `A a ai` and `pmap_assn xs ai`, and the program term is
`pmap_update ki vi ai` — so the value's concrete name should be `vi` (and the abstract one `v`,
not `a`). Line 424 repeats the clash ("$ai \dbcolon \tv{b}$ refines $a$ … and $ai \dbcolon 64\,
word \times \dots$").

**[W] Missing function in the walk-through (lines 412–415).** The paragraph names `arl_len`,
`arl_nth` and `arl_upd` as the reused Isabelle-LLVM functions but the growing branch actually
calls `iarl_resize` (`LLVM_DS_Partial_Map.thy:389`), which is the thesis's own extension and is the
one operation that needs the extra `init` information carried by `iarl_assn`.

### §High-level set refinement by nested lists

**[W] `lshs_resize` initial counter (line 472).** The thesis writes

```
lshs_resize := λ n (xs, l). fold lshs_insert (concat xs) (replicate n [], n)
```

`LLVM_DS_Hash_Set.thy:164, 168`:

```isabelle
definition \<open>lshs_op_set_empty n \<equiv> (replicate n ([] :: 'a list), 0::nat)\<close>
definition \<open>lshs_op_set_resize \<equiv> \<lambda>n (xs, l::nat).
  fold lshs_op_set_insert (concat xs) (lshs_op_set_empty n)\<close>
```

The counter of the fresh hashset is `0`, not `n` — with `n` the element count would be wrong by
the number of buckets after every resize.

**[W] `bucket_of` signature and missing `unat` (line 453).** The thesis defines
`bucket_of x n := ahash x mod n`. `LLVM_DS_Hash_Set.thy:157`:

```isabelle
definition \<open>lshs_bucket_of n a \<equiv> unat (ahash a) mod n\<close>
```

The bucket count comes first, and `unat` is required because `ahash` yields a `64 word`
(see the `ahash` item above). The thesis's own hashmap counterpart
(`datatypes.tex:536`) does write `unat (ahash k) mod n` with the arguments in the source order,
so the two subsections contradict each other.

**[N] Inconsistent names within the subsection.** Line 450 defines `hs_invar`, line 461 uses
`lshs_invar`; lines 459–462 define `lshs_rel`, lines 465–476 use `hs_rel`. The source names are
`lshs_invar`, `lshs_α`, `lshs_rel`, `lshs_op_set_insert`, `lshs_op_set_member`,
`lshs_op_set_resize` (`LLVM_DS_Hash_Set.thy:157–168`) — the thesis drops the `op_set_` infix
(`lshs_insert`, `lshs_member`, `lshs_resize`).

**[W] `lshs_α` ignores its own binder (line 459).** `λ(xs,l). {a. ∃b ∈ set xs. a ∈ set b}` is
written with the bound variable named `xs` but the accompanying prose calls the outer list `xss`
elsewhere in the same subsection; harmless, but it reads as a different object.

### §Low-level hashset implementation

**[W] Claimed cap on the number of buckets (line 500).** "the number of buckets is always capped
to $2^{63}-1$". `ht_grow` (`LLVM_DS_Hash_Set.thy:113`) is
`if n < 2^62 then 2*n else n`, so doubling stops once `n ≥ 2^62` and the reachable bucket count is
bounded by `2^63 - 2` (from `n = 2^62 - 1`). Either give the actual bound or phrase it in terms of
`ht_grow`.

**[N] `hs_assn'` refinement target (line 502).** The thesis writes
`64 word × 'b ptr ptr × 64 word`; `LLVM_DS_Hash_Set.thy:266` has
`type_synonym 'bi hs_conc = 64 word × 'bi node ptr ptr × 64 word` — the `node` is missing.

### §Hashmaps (intro, line 519)

**[W] Copy-paste slip.** "The hash*set* implementation combines concepts from the partial map
implementation … and the hashset implementation" — the sentence is about the hash*map*
implementation.

### §High-level refinement of partial maps by nested lists

**[W] Buckets do not store hashes (line 527).** "the inner tuples of type `k × 'v` … store not
only a given string, but also its corresponding hash." The entries are `('k × 'v)` — key and
value (`LLVM_DS_Hash_Map.thy:83, 86–96`); the hash is recomputed by `lshm_bucket_of` whenever a bucket
index is needed and is never stored. The genuine difference to the hashset is that hashmap buckets
carry key/value *pairs* (and the invariant requires `distinct (map fst …)`), not that they carry
hashes.

**[W] Direction of the refined type (line 526).** "The abstract partial map $\tv{v} \rightharpoonup
\iexp{k}$" — keys are strings and values are numbers, so it is `'k ⇀ 'v`. The same reversal
appears in the `hm_rel` type at line 549 (`(… × 'k ⇀ v) set`).

**[W] `\iexp{k}` / `\iexp{v}` used where type variables are meant.** Lines 526, 536, 539, 549,
566 typeset `k` and `v` as constants (`\iexp`) instead of type variables (`\tv`), e.g.
`(\iexp{k} \times \tv{v}) \app \iexp{list} \app \iexp{list}`.

**[W] `lshm_α` binds the wrong variable (line 539).**

```
lshsm_α := λ (xss,l) m. map_of (xss ! lshm_bucket_of (length xss) k) k
```

The second parameter must be the key `k`, not `m` (`k` is otherwise unbound), and the name is
misspelled `lshsm_α` (extra `s`). Source, `LLVM_DS_Hash_Map.thy:77–78`:

```isabelle
definition lshm_\<alpha> :: \<open>('k, 'v) hashmap \<Rightarrow> 'k \<Rightarrow> 'v option\<close> where
  \<open>lshm_\<alpha> \<equiv> \<lambda>(xs,l) k. map_of (xs ! lshm_bucket_of (length xs) k) k\<close>
```

**[W] `lshm_bucket_of :: 'v → nat` (line 536)** must be `nat → 'k → nat`.

**[W] `lshm_update` correctness lemma is missing an argument (line 557).**
`(lshm_update k v, s(k ↦ v)) ∈ hm_rel` — the hashmap argument `h` is missing:
`(lshm_op_map_update k v h, s(k ↦ v)) ∈ hm_rel`.

**[W] Wrong assumption on `A` (lines 524–525).** "I assume $A \dbcolon \tv{v} \rightarrow \tv{b}
\rightarrow \iexp{assn}$ … instantiates `hashable_assn` and `copyable_assn`. In Pastèque, hashmaps
are only used for strings, i.e., $A = \iexp{str\_assn}$." The hashmap locale separates keys from
values: `khash` is fixed for keys only (`LLVM_DS_Hash_Map.thy:69`), and §Low-level hashmap
implementation correctly introduces `K` (hashable) and `V` (copyable). So the hashable assumption
belongs to the *key* assertion `K = strl_assn'`, while values (`nat`) only need copying.

**[N] Type and operation names.** Thesis `hm_abs`, `lshm_update`, `lshm_contains_key`,
`lshm_lookup`; sources: `('k, 'v) hashmap`, `lshm_op_map_update`, `lshm_op_map_contains_key`,
`lshm_op_map_lookup` (`LLVM_DS_Hash_Map.thy:70, 92, 114, 120`). The hash on keys is `khash`, not
`ahash`.

### §Low-level hashmap implementation

**[N] `entry_assn` (line 577).** The source abbreviation is
`boxed_bucket_assn ≡ K ×⇩a (λv. vopt_assn (Some v))` (`LLVM_DS_Hash_Map.thy:48`); the thesis name
`entry_assn` does not occur.

**[W] `hm_assn` footnote is slightly off (line 583).** The footnote says the actual assertion is
`hm_assn''` composed with `hm_opt_rel`. In the sources `hm_assn''`
(`LLVM_DS_Hash_Map.thy:735–736`) *already* contains that composition (it is `hm_assn'` `hr_comp`'d
with `hm_opt_rel`, paired with the counter assertion); the assertion composed with `lshm_rel` on
top is the abbreviation `hm_assn` (`LLVM_DS_Hash_Map.thy:1334`). Naming the three levels explicitly
(`hm_assn'` → `hm_assn''` → `hm_assn`) would avoid the ambiguity.

---

## `sections/evaluation.tex`

**[W/verify] Claimed bold-face convention (line 15).** "Between the LLVM backend and the Standard
ML backend, the variant with either lower wall clock execution time and memory usage is written in
bold" — "either … and" is contradictory, and it needs checking against
`evaluation/main/results/table.tex` whether both columns are emboldened independently.

**Note (benchmark validity).** The stored note on AMulet2 commit `cff5957` corrupting
`-certify` proofs applies here: line 7 states "I use the current version of the AMulet tool by
Kaufmann" — confirm which AMulet commit produced the certificates behind
`evaluation/main/results/table.tex` before the numbers go into the final text.

---

## Cross-cutting

- **`\ref` vs. `\refsec`.** Many cross references to sections use bare `\ref{sec:…}` instead of
  `\refsec{…}`, so they render as a bare number without the `§`:
  `fundamentals.tex:248, 386, 389, 396, 441, 443`; `multiprecision.tex:194`;
  `datatypes.tex:2, 91, 154, 181, 191, 194, 235, 263, 268, 314, 463`.
- **Label mismatch.** `sec:methodology_high-level-representation-of-polynomials` labels the
  §Pastèque subsection; the label name no longer describes the content.
- **Duplicate/near-duplicate labels.** `sec:lists-with-tail-pointers` (subsection, line 33) vs.
  `lists-with-tail-pointers` (subsubsection, line 266) differ only by the `sec:` prefix, and
  `datatypes.tex:405` cites `sec:lists-with-tail-pointers` where the intended target is
  `sec:refinement-assertion-for-lists` (that is where `list_aux` is defined).
- **`monomial` defined twice, differently.** `fundamentals.tex:382` (`term × int`) and
  `datatypes.tex:181` (`string list × nat`). Pick one and cross-reference it.
- **Open `\todo`s referenced in this review's sections:** `fundamentals.tex:135, 212, 216, 224`;
  `multiprecision.tex:3, 212`; `fundamentals.tex:434` ("How can we cite Mihai?").
