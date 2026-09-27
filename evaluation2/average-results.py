#!/usr/bin/env python3
"""Average the per-round measurements of run-checkers.sh per benchmark and checker.

Reads a CSV as written by ./run-checkers.sh (bench, checker, round, wall_s,
user_s, sys_s, max_rss_kb, exit_code, verdict) and writes one row per
(bench, checker) pair to results/averages.csv.

    ./average-results.py [CSV] [-o OUT]

Besides the two requested means the output carries `rounds`, `wall_s_std` and
`verdict`: a mean is not interpretable without the sample count it came from,
and averaging rounds that disagree on the verdict would be meaningless. A pair
whose rounds produced different verdicts is written as "A|B" and reported on
stderr, because that is a checker behaving non-deterministically rather than a
number to put in a table.
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

COLUMNS = [
    "bench",
    "checker",
    "round",
    "wall_s",
    "user_s",
    "sys_s",
    "max_rss_kb",
    "exit_code",
    "verdict",
]


def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "csv",
        nargs="?",
        type=Path,
        default=here / "results" / "raw.csv",
        help="input CSV (default: results/raw.csv)",
    )
    parser.add_argument(
        "-o",
        "--out",
        type=Path,
        default=here / "results" / "averages.csv",
        help="output CSV (default: results/averages.csv)",
    )
    args = parser.parse_args()

    if not args.csv.is_file():
        sys.exit(f"error: no such CSV: {args.csv}")

    df = pd.read_csv(args.csv)

    missing = [c for c in COLUMNS if c not in df.columns]
    if missing:
        sys.exit(
            f"error: {args.csv} is missing column(s): {', '.join(missing)}\n"
            f"       expected a CSV written by run-checkers.sh"
        )
    if df.empty:
        sys.exit(f"error: {args.csv} holds no measurements")

    grouped = df.groupby(["bench", "checker"], sort=True)

    out = grouped.agg(
        rounds=("round", "count"),
        wall_s_mean=("wall_s", "mean"),
        wall_s_std=("wall_s", "std"),  # NaN for a single round, left empty
        max_rss_kb_mean=("max_rss_kb", "mean"),
    )
    # A single verdict when the rounds agree, "A|B" when they do not.
    out["verdict"] = grouped["verdict"].agg(lambda s: "|".join(sorted(set(s))))
    out = out.reset_index()

    out["wall_s_mean"] = out["wall_s_mean"].round(4)
    out["wall_s_std"] = out["wall_s_std"].round(4)
    out["max_rss_kb_mean"] = out["max_rss_kb_mean"].round(1)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.out, index=False)

    print(out.to_string(index=False))
    print(
        f"\n{len(out)} (bench, checker) pair(s) from {len(df)} run(s) -> {args.out}"
    )

    inconsistent = out[out["verdict"].str.contains("|", regex=False)]
    if not inconsistent.empty:
        print(
            f"\nwarning: {len(inconsistent)} pair(s) disagree across rounds; "
            "their averages mix different outcomes:",
            file=sys.stderr,
        )
        for row in inconsistent.itertuples():
            print(
                f"  {row.bench} / {row.checker}: {row.verdict}",
                file=sys.stderr,
            )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
