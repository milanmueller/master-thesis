#!/usr/bin/env python3
"""Render how each phase grows with the bit-width as a LaTeX table: one row per
phase, one column per bit-width of each benchmark family.

    ./render-phases-scaling-table.py [--sml CSV] [--llvm CSV] [-o OUT]

Reads the same averaged CSVs as ./render-phases-table.py and writes
results/phases-scaling-table.tex. The table needs booktabs, which setup.tex
already loads.

Each cell is the mean time of that phase divided by the mean time of the same
phase on the smallest instance of the family, so the first column of every
family is 1.0 by construction. The phases and the meaning of `teardown` (the
teardown plus the code around the verified checker) are those of
./render-phases-table.py.
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

# (column in the averaged CSV, row label). Order is the order of the rows.
PHASES_LLVM = [
    ("parse_s", "parsing"),
    ("init_s", "initialization"),
    ("check_s", "checking"),
    ("teardown_total_s", "teardown"),
]
PHASES_SML = [
    ("parse_s", "parsing"),
    ("check_s", "checking"),
    ("gc_s", "garbage collection"),
]

# Row order follows the request for this table, LLVM first; it is the backend
# whose progression the table is there to show.
CHECKERS = [
    ("llvm", "Pastèque LLVM", PHASES_LLVM),
    ("sml", "Pastèque SML", PHASES_SML),
]

# The families that come in several bit-widths, and the widths in ascending
# order. The first width is the base every other one is divided by.
FAMILIES = ["btor", "sparrc"]
WIDTHS = [128, 256, 512]

DECIMALS = 1


def load(path: Path, required: list[str], produced_by: str) -> pd.DataFrame:
    if not path.is_file():
        sys.exit(f"error: no such CSV: {path}\n       write it with {produced_by}")
    df = pd.read_csv(path)
    missing = [c for c in required if c not in df.columns]
    if missing:
        sys.exit(
            f"error: {path} is missing column(s): {', '.join(missing)}\n"
            f"       expected a CSV written by {produced_by}"
        )
    return df.set_index("bench")


def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        epilog="\n".join(__doc__.splitlines()[1:]),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--sml",
        type=Path,
        default=here / "results" / "phases-sml-averages.csv",
        help="averaged SML CSV (default: results/phases-sml-averages.csv)",
    )
    parser.add_argument(
        "--llvm",
        type=Path,
        default=here / "results" / "phases-llvm-averages.csv",
        help="averaged LLVM CSV (default: results/phases-llvm-averages.csv)",
    )
    parser.add_argument(
        "-o",
        "--out",
        type=Path,
        default=here / "results" / "phases-scaling-table.tex",
        help="output .tex file (default: results/phases-scaling-table.tex)",
    )
    parser.add_argument(
        "--label", default="tab:phase-scaling", help="\\label of the table"
    )
    parser.add_argument("--caption", default=None, help="override the caption")
    args = parser.parse_args()

    data = {
        "sml": load(
            args.sml, ["bench", "parse_s", "check_s", "gc_s"], "average-phases-sml.py"
        ),
        "llvm": load(
            args.llvm,
            ["bench", "parse_s", "init_s", "check_s", "teardown_s", "other_s"],
            "average-phases-llvm.py",
        ),
    }
    data["llvm"] = data["llvm"].copy()
    data["llvm"]["teardown_total_s"] = (
        data["llvm"]["teardown_s"] + data["llvm"]["other_s"]
    )

    def cell(df: pd.DataFrame, column: str, family: str, width: int) -> str:
        bench, base = f"{family}-{width}", f"{family}-{WIDTHS[0]}"
        if bench not in df.index or base not in df.index:
            return "--"
        base_seconds = float(df.loc[base, column])
        if base_seconds <= 0:
            return "--"
        return f"{float(df.loc[bench, column]) / base_seconds:.{DECIMALS}f}"

    columns = len(FAMILIES) * len(WIDTHS)
    body = []
    for i, (key, name, phases) in enumerate(CHECKERS):
        if i:
            body.append(r"    \addlinespace")
        body.append(f"    \\multicolumn{{{columns + 1}}}{{l}}{{\\emph{{{name}}}}} \\\\")
        for column, label in phases:
            cells = [
                cell(data[key], column, family, width)
                for family in FAMILIES
                for width in WIDTHS
            ]
            body.append(f"    \\quad {label} & " + " & ".join(cells) + r" \\")

    caption = args.caption or (
        "Time spent on the individual phases relative to the time spent on the "
        f"same phase for the {WIDTHS[0]}-bit instance of the same benchmark."
    )

    align = "l" + "".join(" " + "r" * len(WIDTHS) for _ in FAMILIES)
    group_heads = " & ".join(
        f"\\multicolumn{{{len(WIDTHS)}}}{{c}}{{{family}}}" for family in FAMILIES
    )
    cmidrules = " ".join(
        f"\\cmidrule(lr){{{2 + i * len(WIDTHS)}-{1 + (i + 1) * len(WIDTHS)}}}"
        for i in range(len(FAMILIES))
    )
    sub_heads = " & ".join(str(width) for _ in FAMILIES for width in WIDTHS)

    lines = [
        f"% Generated by render-phases-scaling-table.py from {args.sml.name} and "
        f"{args.llvm.name}.",
        "% Regenerate rather than edit; needs booktabs.",
        r"\begin{table}[htbp]",
        r"  \centering",
        f"  \\caption{{{caption}}}",
        f"  \\label{{{args.label}}}",
        f"  \\begin{{tabular}}{{{align}}}",
        r"    \toprule",
        f"    & {group_heads} \\\\",
        f"    {cmidrules}",
        f"    Phase & {sub_heads} \\\\",
        r"    \midrule",
        *body,
        r"    \bottomrule",
        r"  \end{tabular}",
        r"\end{table}",
    ]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(body) - len(CHECKERS)} row(s) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
