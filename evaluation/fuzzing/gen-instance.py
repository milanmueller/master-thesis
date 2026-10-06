#!/usr/bin/env python3
"""Generate a synthetic PAC instance (<stem>.polys, <stem>.proof, <stem>.spec).

The instance is syntactically valid but NOT a valid proof: every polynomial has
random coefficients, so a checker rejects the first step. It is meant for
benchmarking the parsers (and, later, the computation of linear combinations),
where only the shape of the input matters.

Everything is uniform, so that the size of an instance is a closed formula of
its parameters:

  * There are V variables, named x0 .. x<V-1> and zero-padded to one width.
  * Every polynomial is dense: it has one monomial for each of the 2^V subsets
    of the variables (the empty subset is the constant monomial). All
    polynomials list their monomials in the same order, the variables inside a
    monomial by descending index and the constant last, as the real instances
    do.
  * Every coefficient is written out (also a 1) and has exactly C decimal
    digits without a leading zero, with a random sign.
  * The input file holds P polynomials with the ids 1 .. P.
  * The proof holds L linear combination steps with the ids P+1 .. P+L and no
    deletion or extension steps. Every step has S summands `id *(poly)`, whose
    id is drawn from the inputs and the earlier steps, and a claimed result.
  * The spec is one more polynomial.

Hence the instance contains (P + L*(S+1) + 1) polynomials of 2^V monomials each.

  ./gen-instance.py -p 100 -l 1000 -c 20 -v 4 -o instances/p100-l1000-c20-v4
"""

import argparse
import os
import random
import sys

# Coefficients can exceed Python's default limit of 4300 digits for int -> str.
sys.set_int_max_str_digits(0)


def monomial_terms(v):
    """The 2^v terms in output order, each as the text following the
    coefficient: '*x2*x0' for a proper term, '' for the constant."""
    width = len(str(v - 1)) if v > 0 else 1
    names = [f"x{i:0{width}d}" for i in range(v)]
    terms = []
    for mask in range((1 << v) - 1, -1, -1):
        vs = [names[i] for i in range(v - 1, -1, -1) if mask >> i & 1]
        terms.append("".join("*" + n for n in vs))
    return terms


class Gen:
    def __init__(self, rng, terms, digits):
        self.rng = rng
        self.terms = terms
        self.lo = 10 ** (digits - 1)
        self.hi = 10**digits

    def poly(self):
        rng, lo, hi = self.rng, self.lo, self.hi
        parts = []
        for k, t in enumerate(self.terms):
            if rng.getrandbits(1):
                parts.append("-")
            elif k > 0:
                parts.append("+")
            parts.append(str(rng.randrange(lo, hi)))
            parts.append(t)
        return "".join(parts)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("-p", "--polys", type=int, required=True,
                    help="number of input polynomials")
    ap.add_argument("-l", "--steps", type=int, required=True,
                    help="number of linear combination steps")
    ap.add_argument("-c", "--digits", type=int, required=True,
                    help="number of decimal digits of every coefficient")
    ap.add_argument("-v", "--vars", type=int, required=True,
                    help="number of variables; every polynomial has 2^v monomials")
    ap.add_argument("-s", "--summands", type=int, default=2,
                    help="summands per linear combination (default 2)")
    ap.add_argument("--seed", type=int, default=0,
                    help="seed of the random number generator (default 0)")
    ap.add_argument("-o", "--output", required=True, metavar="STEM",
                    help="write STEM.polys, STEM.proof and STEM.spec")
    a = ap.parse_args()

    if a.polys < 1:
        ap.error("--polys must be at least 1 (the steps need a source)")
    if a.steps < 0 or a.digits < 1 or a.vars < 0 or a.summands < 1:
        ap.error("--steps >= 0, --digits >= 1, --vars >= 0, --summands >= 1 required")

    g = Gen(random.Random(a.seed), monomial_terms(a.vars), a.digits)
    rng = g.rng

    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)

    with open(a.output + ".polys", "w") as f:
        for i in range(1, a.polys + 1):
            f.write(f"{i} {g.poly()};\n")

    with open(a.output + ".proof", "w") as f:
        for i in range(a.polys + 1, a.polys + a.steps + 1):
            srcs = " + ".join(
                f"{rng.randrange(1, i)} *({g.poly()})" for _ in range(a.summands)
            )
            f.write(f"{i} % {srcs}, {g.poly()};\n")

    with open(a.output + ".spec", "w") as f:
        f.write(f"{g.poly()};\n")

    npolys = a.polys + a.steps * (a.summands + 1) + 1
    size = sum(os.path.getsize(a.output + e) for e in (".polys", ".proof", ".spec"))
    print(
        f"{a.output}: {npolys} polynomials, {npolys << a.vars} monomials, "
        f"{size / 1e6:.2f} MB",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
