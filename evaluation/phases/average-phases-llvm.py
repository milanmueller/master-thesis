#!/usr/bin/env python3
"""Average the per-round phase measurements of pasteque-llvm-stats per benchmark.

Reads a CSV as written by ./parse-stats-llvm.py and writes one row per benchmark
to results/phases-llvm-averages.csv.

    ./average-phases-llvm.py [CSV] [-o OUT]

The three phases are the ones section 5 of the thesis names for the LLVM
backend:

    parse_s   parsing the three input files (the driver's lexing and parsing)
    init_s    initialization of the input polynomials, sorting and normalization
              (the `import input polynomials` phase, remap_polys)
    check_s   checking the proof steps (the `proof step loop` phase)

Two further columns make the row add up to the whole run, so that a share is a
share of something real rather than of the three phases alone:

    teardown_s  releasing the checker's memory after it returned; the Standard
                ML backend has no counterpart, it exits without freeing
    other_s     the rest of the run: the glue in run_checker around the verified
                entry point, and the entry point's own time outside the two
                phases above. It is small (1-3% of the checker) and is kept as
                its own column rather than folded into a phase.
    ------------------------------------------------------------------
                parse_s + init_s + check_s + teardown_s + other_s = overall_s

All figures are wall clock (CLOCK_MONOTONIC). On the measurements taken so far
the process is CPU bound to within 1% (user + system is 99.2-100% of wall), so
they are comparable with the Standard ML driver's CPU times - but they are not
the same quantity, and the comparison should say so.

Two caveats that belong to the binary rather than to the aggregation:

  * `init_s` and `check_s` are inclusive times: they cover everything the phase
    calls. They are disjoint from each other, and together they are 98.7-100% of
    the verified checker. The remaining phases of the tier-1 report are NOT
    disjoint from them - `normalize polynomial` runs partly inside
    `prepare sources` inside `proof step loop` - which is why this script uses
    only these two and leaves the finer breakdown to the raw CSV.
  * The instrumented binary is not the production one: wrapping a phase blocks
    inlining across the call. At tier 1 the cost is about 2% of the total; at
    tier 2 it is far larger. Take absolute totals from ../main/results and the
    composition from here.
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

# Run-level columns, repeated on every phase row of a run.
RUN_COLUMNS = [
    "bench",
    "checker",
    "round",
    "tier",
    "polys_parse_s",
    "pac_parse_s",
    "spec_parse_s",
    "init_s",
    "solve_s",
    "teardown_s",
    "overall_s",
    "peak_rss_mib",
    "verdict",
]
PHASE_COLUMNS = ["phase", "incl_s"]

# The two phases the thesis names, by the label stats.c prints for them. Both are
# tier 0, so they are present in a report of any tier.
PHASE_INIT = "import input polynomials"
PHASE_CHECK = "proof step loop"

OUT_COLUMNS = [
    "bench",
    "checker",
    "rounds",
    "tier",
    "parse_s",
    "parse_polys_s",
    "parse_proof_s",
    "parse_spec_s",
    "init_s",
    "check_s",
    "teardown_s",
    "other_s",
    "overall_s",
    "overall_s_std",
    "parse_pct",
    "init_pct",
    "check_pct",
    "teardown_pct",
    "other_pct",
    "peak_rss_mib",
    "verdict",
]


def phase_per_run(df: pd.DataFrame, label: str, csv: Path) -> pd.DataFrame:
    """The inclusive time of one phase, one row per (bench, checker, round)."""
    sel = df[df["phase"] == label]
    if sel.empty:
        sys.exit(
            f"error: {csv} has no '{label}' row.\n"
            f"       It is a tier-0 phase and should be in every report; a CSV\n"
            f"       without it did not come from parse-stats-llvm.py."
        )
    dup = sel.duplicated(["bench", "checker", "round"])
    if dup.any():
        sys.exit(
            f"error: {csv} has {dup.sum()} duplicate '{label}' row(s) for the same\n"
            f"       (bench, checker, round). Two sweeps wrote the same CSV; rerun\n"
            f"       them one at a time (run-phases.sh takes a lock to prevent it)."
        )
    return sel[["bench", "checker", "round", "incl_s"]]


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
        default=here / "results" / "phases-llvm.csv",
        help="input CSV (default: results/phases-llvm.csv)",
    )
    parser.add_argument(
        "-o",
        "--out",
        type=Path,
        default=here / "results" / "phases-llvm-averages.csv",
        help="output CSV (default: results/phases-llvm-averages.csv)",
    )
    args = parser.parse_args()

    if not args.csv.is_file():
        sys.exit(f"error: no such CSV: {args.csv}")

    df = pd.read_csv(args.csv)
    missing = [c for c in RUN_COLUMNS + PHASE_COLUMNS if c not in df.columns]
    if missing:
        sys.exit(
            f"error: {args.csv} is missing column(s): {', '.join(missing)}\n"
            f"       expected a CSV written by parse-stats-llvm.py"
        )
    if df.empty:
        sys.exit(f"error: {args.csv} holds no measurements")

    # Absolute times from binaries injected at different tiers are not
    # comparable, so refuse to average across them rather than produce a mean of
    # two different things.
    tiers = sorted(set(df["tier"].dropna().astype(str)))
    if len(tiers) > 1:
        sys.exit(
            f"error: {args.csv} mixes instrumentation tiers ({', '.join(tiers)}).\n"
            f"       A tier-2 binary is several times slower than a tier-1 one, so\n"
            f"       averaging across tiers is meaningless. Split the CSV, or\n"
            f"       rerun the sweep at one tier."
        )

    # One row per run: the run-level columns repeat on every phase row.
    runs = df.drop_duplicates(["bench", "checker", "round"])[RUN_COLUMNS].copy()
    init = phase_per_run(df, PHASE_INIT, args.csv).rename(columns={"incl_s": "init_incl_s"})
    check = phase_per_run(df, PHASE_CHECK, args.csv).rename(columns={"incl_s": "check_incl_s"})
    runs = runs.merge(init, on=["bench", "checker", "round"], how="left")
    runs = runs.merge(check, on=["bench", "checker", "round"], how="left")

    orphan = runs[runs["init_incl_s"].isna() | runs["check_incl_s"].isna()]
    if not orphan.empty:
        sys.exit(
            f"error: {len(orphan)} run(s) in {args.csv} have no '{PHASE_INIT}' or\n"
            f"       '{PHASE_CHECK}' row: "
            + ", ".join(f"{r.bench}/{r.round}" for r in orphan.itertuples())
        )

    # The driver's own timers give parsing, the checker interval and teardown;
    # the two phases split the checker interval, and what they do not cover is
    # reported as other_s so the columns sum to the total.
    runs["parse_s"] = runs["init_s"]
    runs["init_phase_s"] = runs["init_incl_s"]
    runs["check_phase_s"] = runs["check_incl_s"]
    runs["other_s"] = runs["solve_s"] - runs["init_incl_s"] - runs["check_incl_s"]
    drift = (
        runs["parse_s"] + runs["init_phase_s"] + runs["check_phase_s"]
        + runs["teardown_s"] + runs["other_s"] - runs["overall_s"]
    ).abs()
    if (drift > 0.01).any():
        bad = runs.loc[drift > 0.01, ["bench", "round"]]
        print(
            f"warning: the phases differ from the total by more than 10 ms in "
            f"{len(bad)} run(s):",
            file=sys.stderr,
        )
        for row in bad.itertuples():
            print(f"  {row.bench} round {row.round}", file=sys.stderr)

    grouped = runs.groupby(["bench", "checker"], sort=True)
    out = grouped.agg(
        rounds=("round", "count"),
        parse_s=("parse_s", "mean"),
        parse_polys_s=("polys_parse_s", "mean"),
        parse_proof_s=("pac_parse_s", "mean"),
        parse_spec_s=("spec_parse_s", "mean"),
        init_s=("init_phase_s", "mean"),
        check_s=("check_phase_s", "mean"),
        teardown_s=("teardown_s", "mean"),
        other_s=("other_s", "mean"),
        overall_s=("overall_s", "mean"),
        overall_s_std=("overall_s", "std"),  # NaN for a single round, left empty
        peak_rss_mib=("peak_rss_mib", "mean"),
    )
    out["tier"] = grouped["tier"].agg(lambda s: sorted(set(s.astype(str)))[0])
    out["verdict"] = grouped["verdict"].agg(lambda s: "|".join(sorted(set(s))))
    out = out.reset_index()

    for phase in ("parse", "init", "check", "teardown", "other"):
        out[f"{phase}_pct"] = (100.0 * out[f"{phase}_s"] / out["overall_s"]).round(1)
    for c in out.columns:
        if c.endswith("_s") or c.endswith("_s_std"):
            out[c] = out[c].round(3)
    out["peak_rss_mib"] = out["peak_rss_mib"].round(1)

    out = out[OUT_COLUMNS]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.out, index=False)

    show = ["bench", "rounds", "parse_s", "init_s", "check_s", "teardown_s",
            "other_s", "overall_s", "parse_pct", "init_pct", "check_pct", "verdict"]
    print(out[show].to_string(index=False))
    print(f"\n{len(out)} benchmark(s) from {len(runs)} run(s), tier {tiers[0]} -> {args.out}")

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
