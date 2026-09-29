#!/usr/bin/env python3
"""Render an averages CSV as a LaTeX table: one row per benchmark, one column
pair (wct, rss) per checker.

    ./render-table.py [CSV] [-o OUT] [--label LABEL] [--caption TEXT]

Reads the output of ./average-results.py and writes results/table.tex. The
table needs booktabs, which setup.tex already loads.

Numbers are preformatted here with a fixed number of decimals and set in plain
`r` columns rather than siunitx `S` columns: with a fixed decimal count right
alignment already aligns the decimal points, and it keeps \\textbf working
without depending on siunitx's font-detection settings.

The faster and smaller of the two Pasteque backends is set in bold. Pacheck is
excluded from that comparison: it is the unverified baseline and always wins, so
marking it would carry no information.
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

# Column order, and the headings they are given in the table.
CHECKERS = [
    ("pacheck", "Pacheck"),
    ("pasteque-llvm", "Pastèque LLVM"),
    ("pasteque-sml", "Pastèque SML"),
]
COMPARED = ("pasteque-llvm", "pasteque-sml")

REQUIRED = ["bench", "checker", "wall_s_mean", "max_rss_kb_mean", "verdict"]

# Verdicts whose timings are not a completed measurement and must not be
# printed as though they were.
NOT_MEASURED = {"TIMEOUT", "ERROR"}

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
        default=here / "results" / "averages.csv",
        help="input CSV (default: results/averages.csv)",
    )
    parser.add_argument(
        "-o",
        "--out",
        type=Path,
        default=here / "results" / "table.tex",
        help="output .tex file (default: results/table.tex)",
    )
    parser.add_argument(
        "--label", default="tab:checker-comparison", help="\\label of the table"
    )
    parser.add_argument("--caption", default=None, help="override the caption")
    parser.add_argument(
        "--rss-kib",
        action="store_true",
        help="report peak RSS in KiB as measured, instead of MiB",
    )
    args = parser.parse_args()

    if not args.csv.is_file():
        sys.exit(f"error: no such CSV: {args.csv}")

    df = pd.read_csv(args.csv)
    missing = [c for c in REQUIRED if c not in df.columns]
    if missing:
        sys.exit(
            f"error: {args.csv} is missing column(s): {', '.join(missing)}\n"
            f"       expected a CSV written by average-results.py"
        )
    if df.empty:
        sys.exit(f"error: {args.csv} holds no rows")

    unknown = sorted(set(df["checker"]) - {c for c, _ in CHECKERS})
    if unknown:
        print(
            f"warning: ignoring unknown checker(s): {', '.join(unknown)}",
            file=sys.stderr,
        )

    # Keep the CSV's benchmark order so a hand-sorted file is respected.
    benches = list(dict.fromkeys(df["bench"]))
    present = [(c, h) for c, h in CHECKERS if c in set(df["checker"])]
    if not present:
        sys.exit(f"error: {args.csv} holds none of the known checkers")

    by_pair = {(r.bench, r.checker): r for r in df.itertuples()}

    rss_divisor = 1.0 if args.rss_kib else 1024.0
    rss_unit = "KiB" if args.rss_kib else "MiB"

    def cell(row, field, decimals):
        """A formatted number, or a marker when nothing was measured.

        The comparison value is rounded to the printed precision, so that the
        bold mark never claims a difference the table does not show: two cells
        printed as 0.00 are either both bold or neither."""
        if row is None:
            return None, "--"
        if str(row.verdict) in NOT_MEASURED:
            return None, "TO" if row.verdict == "TIMEOUT" else "err"
        value = row.wall_s_mean if field == "wct" else row.max_rss_kb_mean / rss_divisor
        return round(float(value), decimals), f"{value:.{decimals}f}"

    rows = []
    inconsistent = []
    for bench in benches:
        values, texts = {}, {}
        for checker, _ in present:
            row = by_pair.get((bench, checker))
            if row is not None and "|" in str(row.verdict):
                inconsistent.append((bench, checker, row.verdict))
            values[checker, "wct"], texts[checker, "wct"] = cell(row, "wct", 2)
            values[checker, "rss"], texts[checker, "rss"] = cell(row, "rss", 1)

        # Bold the winner of LLVM vs SML per metric, only when both are numbers.
        for metric in ("wct", "rss"):
            pair = [values.get((c, metric)) for c in COMPARED if (c, metric) in values]
            if len(pair) == 2 and all(v is not None for v in pair):
                best = min(pair)
                for checker in COMPARED:
                    if values[checker, metric] == best:
                        texts[checker, metric] = f"\\textbf{{{texts[checker, metric]}}}"

        cells = [texts[c, m] for c, _ in present for m in ("wct", "rss")]
        rows.append(f"    {latex_escape(bench)} & " + " & ".join(cells) + r" \\")

    # Cross-checker disagreement is a correctness problem, not a formatting one.
    for bench in benches:
        seen = {
            str(by_pair[bench, c].verdict)
            for c, _ in present
            if (bench, c) in by_pair
            and str(by_pair[bench, c].verdict) not in NOT_MEASURED
        }
        if len(seen) > 1:
            print(
                f"warning: checkers disagree on {bench}: {', '.join(sorted(seen))}",
                file=sys.stderr,
            )

    if inconsistent:
        print(
            f"warning: {len(inconsistent)} pair(s) averaged across differing "
            "verdicts; their numbers describe a mix of outcomes:",
            file=sys.stderr,
        )
        for bench, checker, verdict in inconsistent:
            print(f"  {bench} / {checker}: {verdict}", file=sys.stderr)

    if args.caption is not None:
        caption = args.caption
    else:
        rounds = sorted(set(df["rounds"])) if "rounds" in df.columns else []
        over = (
            f"the mean over {rounds[0]} rounds"
            if len(rounds) == 1
            else "the mean over the recorded rounds"
        )
        caption = (
            f"Wall clock time (\\emph{{wct}}, in seconds) and peak resident set "
            f"size (\\emph{{rss}}, in {rss_unit}) of the three PAC proof "
            f"checkers. Each value is {over}. For each benchmark the lower of "
            f"the two Pastèque backends is set in bold."
        )

    align = "l" + " rr" * len(present)
    group_heads = " & ".join(
        f"\\multicolumn{{2}}{{c}}{{{h}}}" for _, h in present
    )
    cmidrules = " ".join(
        f"\\cmidrule(lr){{{2 + 2 * i}-{3 + 2 * i}}}" for i in range(len(present))
    )
    sub_heads = " & ".join("wct & rss" for _ in present)

    lines = [
        f"% Generated by render-table.py from {args.csv.name}.",
        "% Regenerate rather than edit; needs booktabs.",
        r"\begin{table}[htbp]",
        r"  \centering",
        f"  \\caption{{{caption}}}",
        f"  \\label{{{args.label}}}",
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
    print(f"{len(rows)} row(s) x {len(present)} checker(s) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
