#!/usr/bin/env python3
"""Render the two averaged phase CSVs as a LaTeX table: one row per benchmark,
three columns per checker.

    ./render-phases-table.py [--sml CSV] [--llvm CSV] [-o OUT]

Reads the outputs of ./average-phases-sml.py and ./average-phases-llvm.py and
writes results/phases-table.tex. The table needs booktabs, which setup.tex
already loads.

Each cell is the mean time in seconds followed by that phase's share of the
checker's whole run in brackets. The share is taken against the run rather than
against the three phases shown, so that the two checkers are read on the same
base: the Standard ML columns therefore add up to 100%, while the LLVM columns
fall short of it by the teardown and the code around the verified checker, which
the thesis does not count as a phase.

The three columns per checker are the phases section 5 names for it:

    Pastèque SML   parsing, checking proof steps, garbage collection
    Pastèque LLVM  parsing, initialization of input polynomials, checking

Parsing and checking are the two phases both checkers report, and the lower of
the two is set in bold, as in the table of ../main/render-table.py. Garbage
collection and initialization have no counterpart in the other backend and are
never marked: the Standard ML backend has a collector and the LLVM backend does
not, and the LLVM backend reports an initialization phase the Standard ML driver
cannot separate from its checking.

Numbers are preformatted here with a fixed number of decimals and set in plain
`r` columns rather than siunitx `S` columns, for the reasons given in
../main/render-table.py.
"""

import argparse
import re
import sys
from pathlib import Path

import pandas as pd

# (column in the averaged CSV, heading). Order is the order of the columns.
PHASES_SML = [("parse_s", "parse"), ("check_s", "check"), ("gc_s", "gc")]
# `tdown` is teardown plus the code around the verified checker, which is 1-2%
# of the run; keeping them apart would cost a column for a rounding difference.
# Without it the LLVM shares would fall short of the run by up to a fifth.
PHASES_LLVM = [
    ("parse_s", "parse"),
    ("init_s", "init"),
    ("check_s", "check"),
    ("teardown_total_s", "tdown"),
]

# Column order follows ./render-phases-plot.py, whose left bar is the Standard
# ML backend, so that a reader moving between the figure and the table finds the
# two checkers on the same side.
CHECKERS = [
    ("sml", "Pastèque SML", PHASES_SML),
    ("llvm", "Pastèque LLVM", PHASES_LLVM),
]
# The phases both checkers report, and which column of each holds them.
COMPARABLE = {"parse": ("parse_s", "parse_s"), "check": ("check_s", "check_s")}

DECIMALS = 2

LATEX_SPECIALS = {
    "\\": r"\textbackslash{}",
    "&": r"\&",
    "%": r"\%",
    "$": r"\$",
    "#": r"\#",
    "_": r"\_",
    "{": r"\{",
    "}": r"\}",
    "~": r"\textasciitilde{}",
    "^": r"\textasciicircum{}",
}


def latex_escape(text: str) -> str:
    """Escape LaTeX specials. A benchmark stem is a file name and may carry
    underscores, which would otherwise break the build."""
    return "".join(LATEX_SPECIALS.get(c, c) for c in str(text))


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
    if df.empty:
        sys.exit(f"error: {path} holds no rows")
    dup = df["bench"].duplicated()
    if dup.any():
        sys.exit(
            f"error: {path} has more than one row for "
            f"{', '.join(map(str, df.loc[dup, 'bench']))}; it should hold one row "
            f"per benchmark"
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
        default=here / "results" / "phases-table.tex",
        help="output .tex file (default: results/phases-table.tex)",
    )
    parser.add_argument(
        "--label", default="tab:phase-comparison", help="\\label of the table"
    )
    parser.add_argument("--caption", default=None, help="override the caption")
    parser.add_argument(
        "--bench", help="comma-separated benchmarks to include, in place of all"
    )
    parser.add_argument(
        "--match",
        help="include only the benchmarks whose name matches this regular "
        "expression, e.g. '-256$' for the 256-bit instances",
    )
    parser.add_argument(
        "--no-bold",
        action="store_true",
        help="do not set the lower of the two backends in bold",
    )
    args = parser.parse_args()

    data = {
        "sml": load(
            args.sml,
            ["bench", "parse_s", "check_s", "gc_s", "overall_s", "rounds"],
            "average-phases-sml.py",
        ),
        "llvm": load(
            args.llvm,
            [
                "bench",
                "parse_s",
                "init_s",
                "check_s",
                "teardown_s",
                "other_s",
                "overall_s",
                "rounds",
            ],
            "average-phases-llvm.py",
        ),
    }
    data["llvm"] = data["llvm"].copy()
    data["llvm"]["teardown_total_s"] = (
        data["llvm"]["teardown_s"] + data["llvm"]["other_s"]
    )

    benches = list(dict.fromkeys(list(data["sml"].index) + list(data["llvm"].index)))
    if args.bench:
        wanted = [b.strip() for b in args.bench.split(",") if b.strip()]
        unknown = [b for b in wanted if b not in benches]
        if unknown:
            sys.exit(
                f"error: --bench names {len(unknown)} benchmark(s) that are in "
                f"neither CSV: {', '.join(unknown)}"
            )
        benches = [b for b in benches if b in set(wanted)]
    if args.match:
        try:
            pattern = re.compile(args.match)
        except re.error as exc:
            sys.exit(f"error: --match is not a valid regular expression: {exc}")
        benches = [b for b in benches if pattern.search(str(b))]
        if not benches:
            sys.exit(f"error: --match {args.match!r} selected no benchmark")

    missing_side = [
        b for b in benches if b not in data["sml"].index or b not in data["llvm"].index
    ]
    if missing_side:
        print(
            f"warning: {len(missing_side)} benchmark(s) are in only one CSV and "
            f"get '--' for the other: {', '.join(map(str, missing_side))}",
            file=sys.stderr,
        )

    rows = []
    for bench in benches:
        values, texts = {}, {}
        for key, _, phases in CHECKERS:
            df = data[key]
            for column, head in phases:
                if bench not in df.index:
                    values[key, head], texts[key, head] = None, "--"
                    continue
                seconds = float(df.loc[bench, column])
                total = float(df.loc[bench, "overall_s"])
                share = 100.0 * seconds / total if total > 0 else 0.0
                values[key, head] = round(seconds, DECIMALS)
                # The percent sign is left out of the cells and stated in the
                # caption instead: on seventy cells it is redundant ink, and it
                # is what pushes the table past the text width.
                texts[key, head] = f"{seconds:.{DECIMALS}f} ({share:.0f})"

        # Bold the lower of the two backends, for the two phases both report.
        # The comparison uses the rounded value, so the mark never claims a
        # difference the printed numbers do not show.
        if not args.no_bold:
            for head in COMPARABLE:
                pair = [values.get(("sml", head)), values.get(("llvm", head))]
                if all(v is not None for v in pair):
                    best = min(pair)
                    for key in ("sml", "llvm"):
                        if values[key, head] == best:
                            texts[key, head] = f"\\textbf{{{texts[key, head]}}}"

        cells = [texts[key, head] for key, _, phases in CHECKERS for _, head in phases]
        rows.append(f"    {latex_escape(bench)} & " + " & ".join(cells) + r" \\")

    if args.caption is not None:
        caption = args.caption
    else:
        rounds = sorted(set(data["sml"]["rounds"]) | set(data["llvm"]["rounds"]))
        if len(rounds) != 1:
            over = "the mean over the recorded rounds"
        elif rounds[0] == 1:
            over = "a single round"
        else:
            over = f"the mean over {rounds[0]} rounds"
        caption = (
            "Time in seconds spent on the individual phases for both backend, "
            "relative time (in percentages) is written in brackets."
        )

    align = "l" + "".join(" " + "r" * len(phases) for _, _, phases in CHECKERS)
    group_heads = " & ".join(
        f"\\multicolumn{{{len(phases)}}}{{c}}{{{name}}}" for _, name, phases in CHECKERS
    )
    starts, col = [], 2
    for _, _, phases in CHECKERS:
        starts.append((col, col + len(phases) - 1))
        col += len(phases)
    cmidrules = " ".join(f"\\cmidrule(lr){{{a}-{b}}}" for a, b in starts)
    sub_heads = " & ".join(
        " & ".join(head for _, head in phases) for _, _, phases in CHECKERS
    )

    lines = [
        f"% Generated by render-phases-table.py from {args.sml.name} and "
        f"{args.llvm.name}.",
        "% Regenerate rather than edit; needs booktabs.",
        r"\begin{table}[htbp]",
        r"  \centering",
        f"  \\caption{{{caption}}}",
        f"  \\label{{{args.label}}}",
        # Seven columns of "value (share)" are wider than the text block at the
        # document's normal size; both settings are local to the table.
        r"  \small",
        r"  \setlength{\tabcolsep}{3pt}",
        f"  \\begin{{tabular}}{{{align}}}",
        r"    \toprule",
        f"    & {group_heads} \\\\",
        f"    {cmidrules}",
        f"    Benchmark & {sub_heads} \\\\",
        r"    \midrule",
        *rows,
        r"    \bottomrule",
        r"  \end{tabular}",
        r"\end{table}",
    ]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(rows)} row(s) x {len(CHECKERS)} checker(s) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
