#!/usr/bin/env python3
"""Average the per-round phase measurements of pasteque-sml per benchmark.

Reads a CSV as written by ./parse-stats-sml.py and writes one row per benchmark
to results/phases-sml-averages.csv.

    ./average-phases-sml.py [CSV] [-o OUT]

The three phases are the ones section 5 of the thesis names for the Standard ML
backend, and they partition the run exactly:

    parse_s   parsing the three input files, excluding garbage collection
    check_s   the verified checker, excluding garbage collection
    gc_s      garbage collection, over the whole run
    ---------------------------------------------------------------
              parse_s + check_s + gc_s = overall_s

`parse_s` is the driver's "full init" timer and `check_s` its "time solving"
timer, both of which MLton reports without GC; `gc_s` is the GC part of the
whole-run timer. All are CPU time (user + system).

Two things this CSV cannot say, both of them properties of the driver rather
than of the aggregation:

  * There is no initialization phase. The Standard ML driver calls
    full_checker_l_s2_impl as one opaque operation, so sorting and normalizing
    the input polynomials happens inside `check_s` and cannot be separated from
    proof checking. The LLVM counterpart reports it, which is why
    ./average-phases-llvm.py has an `init_s` column and this script has none:
    an empty column here would invite reading it as zero.
  * GC is attributed to the interval it occurred in, not to the work that
    caused it. `gc_parse_s` and `gc_check_s` split it by interval - the driver
    prints GC only for the checker and for the whole run, so the parse share is
    recovered as the difference - but neither is "GC caused by this phase".

Use `overall_s` (which includes GC) when comparing against the LLVM backend:
that backend has no garbage collector but pays for memory management inline, so
its figures already carry the equivalent cost.
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

COLUMNS = [
    "bench",
    "checker",
    "round",
    "polys_parse_s",
    "pac_parse_s",
    "init_s",
    "solve_s",
    "solve_gc_s",
    "overall_gc_s",
    "overall_full_s",
    "verdict",
]

OUT_COLUMNS = [
    "bench",
    "checker",
    "rounds",
    "parse_s",
    "parse_polys_s",
    "parse_proof_s",
    "parse_spec_s",
    "check_s",
    "gc_s",
    "gc_parse_s",
    "gc_check_s",
    "overall_s",
    "overall_s_std",
    "parse_pct",
    "check_pct",
    "gc_pct",
    "verdict",
]


def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        epilog="\n".join(__doc__.splitlines()[1:]),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "csv",
        nargs="?",
        type=Path,
        default=here / "results" / "phases-sml.csv",
        help="input CSV (default: results/phases-sml.csv)",
    )
    parser.add_argument(
        "-o",
        "--out",
        type=Path,
        default=here / "results" / "phases-sml-averages.csv",
        help="output CSV (default: results/phases-sml-averages.csv)",
    )
    args = parser.parse_args()

    if not args.csv.is_file():
        sys.exit(f"error: no such CSV: {args.csv}")

    df = pd.read_csv(args.csv)
    missing = [c for c in COLUMNS if c not in df.columns]
    if missing:
        sys.exit(
            f"error: {args.csv} is missing column(s): {', '.join(missing)}\n"
            f"       expected a CSV written by parse-stats-sml.py"
        )
    if df.empty:
        sys.exit(f"error: {args.csv} holds no measurements")

    # Per round first, so that every mean is taken over the same quantity.
    df = df.copy()
    df["parse_s"] = df["init_s"]
    df["check_s"] = df["solve_s"]
    df["gc_s"] = df["overall_gc_s"]
    df["gc_check_s"] = df["solve_gc_s"]
    # The driver prints GC for the checker and for the whole run only; the whole
    # run is parsing plus checking, so the parse share is the difference.
    df["gc_parse_s"] = df["overall_gc_s"] - df["solve_gc_s"]
    df["overall_s"] = df["overall_full_s"]
    # "full init" covers all three files but only the first two are timed
    # individually, so the spec parse is what is left of it.
    df["parse_spec_s"] = df["init_s"] - df["polys_parse_s"] - df["pac_parse_s"]

    # The three phases must account for the run. A mismatch means the input rows
    # did not all come from one run of the driver.
    drift = (df["parse_s"] + df["check_s"] + df["gc_s"] - df["overall_s"]).abs()
    if (drift > 0.01).any():
        bad = df.loc[drift > 0.01, ["bench", "round"]]
        print(
            f"warning: parse + check + gc differs from the total by more than "
            f"10 ms in {len(bad)} row(s):",
            file=sys.stderr,
        )
        for row in bad.itertuples():
            print(f"  {row.bench} round {row.round}", file=sys.stderr)

    grouped = df.groupby(["bench", "checker"], sort=True)
    out = grouped.agg(
        rounds=("round", "count"),
        parse_s=("parse_s", "mean"),
        parse_polys_s=("polys_parse_s", "mean"),
        parse_proof_s=("pac_parse_s", "mean"),
        parse_spec_s=("parse_spec_s", "mean"),
        check_s=("check_s", "mean"),
        gc_s=("gc_s", "mean"),
        gc_parse_s=("gc_parse_s", "mean"),
        gc_check_s=("gc_check_s", "mean"),
        overall_s=("overall_s", "mean"),
        overall_s_std=("overall_s", "std"),  # NaN for a single round, left empty
    )
    out["verdict"] = grouped["verdict"].agg(lambda s: "|".join(sorted(set(s))))
    out = out.reset_index()

    for phase in ("parse", "check", "gc"):
        out[f"{phase}_pct"] = (100.0 * out[f"{phase}_s"] / out["overall_s"]).round(1)
    for c in out.columns:
        if c.endswith("_s") or c.endswith("_s_std"):
            out[c] = out[c].round(3)

    out = out[OUT_COLUMNS]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.out, index=False)

    show = ["bench", "rounds", "parse_s", "check_s", "gc_s", "overall_s",
            "parse_pct", "check_pct", "gc_pct", "verdict"]
    print(out[show].to_string(index=False))
    print(f"\n{len(out)} benchmark(s) from {len(df)} run(s) -> {args.out}")
    print(
        "note: check_s also contains the initialization of the input polynomials;\n"
        "      the Standard ML driver cannot separate the two (see --help).",
        file=sys.stderr,
    )

    inconsistent = out[out["verdict"].str.contains("|", regex=False)]
    if not inconsistent.empty:
        print(
            f"\nwarning: {len(inconsistent)} benchmark(s) disagree across rounds; "
            "their averages mix different outcomes:",
            file=sys.stderr,
        )
        for row in inconsistent.itertuples():
            print(f"  {row.bench}: {row.verdict}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
