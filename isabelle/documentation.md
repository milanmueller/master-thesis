# Internal Documentation
Collection of important files, definitions etc. that need to be modified.

## Signed Integers
We will need to support signed numbers in the BigInteger library. This is probably the first thing we will have to do.
Notable definitions:
- `src/BigInt.thy` - line 7 - `big_int`
  - Implement custom signed int datatype
  - Reimplement addition (and subtraction) and multiplication for the new datatype

## Native Integers  -> `BigInteger` in Pastèque
We need to replace all usages of native integers in Pastèque refinement with the `BigInteger` type.
Notable definitions:
- `/PAC_Checker/PAC_Checker_Relation.thy` - line 99 - `monom_assn` (**in afp!**)
  - `list_assn string_assn`, (i.e. `["x", "xy", "y"]` maybe?)
- `/PAC_Checker/PAC_Checker_Relation.thy` - line 104 - `monomial_assn` (**in afp!**)
  - `monom_assn \times int_assn`, (i.e. `["x", "xy", "y"] \times 42` maybe)
  - We want to use signed `BigInteger` here instead of `int_assn`
