#!/usr/bin/env python3
"""Plot a sweep CSV: one graph per fuzzer parameter, with the parameter on the
x-axis and the average parsing time of both backends on the y-axis.

    ./render-graph.py [CSV] [-o DIR] [--metric KEY] [--fix p=100 ...] [--log]

Reads the output of ./run-sweep.sh (default results/sweep.csv) and writes
<DIR>/<csv name>-<param>.pdf for every parameter of p, l, c, v, s that takes
more than one value in the CSV.

A graph shows how the time depends on ONE parameter, so the others have to be
held fixed. When the CSV is a grid, there are several such slices. For each
graph the script takes the slice with the most points on the x-axis (on a tie
the one with the smallest values of the other parameters) and names the fixed
values below the plot. --fix pins a parameter to a value of your choice in all
graphs where it is not the x-axis.

--metric selects the timer: total_s (default), polys_s, proof_s or spec_s. For
total_s the error bars show the standard deviation over the rounds.

Colour identifies the backend and is the one ../main/render-plot.py uses for
it; the marker shape repeats the identity, so that it survives a greyscale
print of the thesis.
"""

import argparse
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display in the devshell or on a build machine
import matplotlib.pyplot as plt
import pandas as pd

# (CSV prefix, legend name, colour, marker) - same colours as ../main.
PARSERS = [
    ("llvm", "Pastèque LLVM", "#eb6834", "o"),
    ("sml", "Pastèque SML", "#1baf7a", "s"),
]

PARAMS = {
    "p": "number of input polynomials (p)",
    "l": "number of linear combination steps (l)",
    "c": "digits per coefficient (c)",
    "v": "number of variables (v)",
    "s": "summands per linear combination (s)",
}

METRICS = {
    "total_s": "parsing time [s]",
    "polys_s": "parsing time, input polynomials [s]",
    "proof_s": "parsing time, proof [s]",
    "spec_s": "parsing time, spec [s]",
}

SURFACE = "#ffffff"
INK = "#0b0b0b"
INK_MUTED = "#52514e"
GRID = "#dcdcd8"
FONT = 12  # pt, for every label, tick and legend entry


def pick_slice(df, param, fixed):
    """The rows of one slice along `param`: all other parameters constant."""
    others = [q for q in PARAMS if q != param]
    for q in others:
        if q in fixed:
            df = df[df[q] == fixed[q]]
    if df.empty:
        return df, {}
    best = None
    for key, grp in df.groupby(others):
        rank = (-grp[param].nunique(), key)
        if best is None or rank < best[0]:
            best = (rank, key, grp)
    _, key, grp = best
    return grp.sort_values(param), dict(zip(others, key))


def render(df, param, held, metric, log, out):
    fig, ax = plt.subplots(figsize=(6.4, 4.2))
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=INK_MUTED, labelsize=FONT)
    ax.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)

    for prefix, name, colour, marker in PARSERS:
        std = df.get(f"{prefix}_{metric}_std")
        ax.errorbar(
            df[param], df[f"{prefix}_{metric}"], yerr=std,
            color=colour, linewidth=2.0, marker=marker, markersize=6,
            markeredgecolor=SURFACE, markeredgewidth=1.0,
            elinewidth=1.0, capsize=2.5, label=name, zorder=3,
        )

    ax.set_xlabel(PARAMS[param], fontsize=FONT, color=INK)
    ax.set_ylabel(METRICS[metric], fontsize=FONT, color=INK)
    if log:
        ax.set_yscale("log")
    else:
        ax.set_ylim(bottom=0)
    # The parameters are integers; a few values get one tick each.
    xs = sorted(df[param].unique())
    if len(xs) <= 12:
        ax.set_xticks(xs)
    # Above the plot area, where no line can run into it.
    ax.legend(frameon=False, fontsize=FONT, labelcolor=INK, ncol=len(PARSERS),
              loc="lower left", bbox_to_anchor=(0, 1.0), borderaxespad=0.2)

    note = ", ".join(f"{q} = {val}" for q, val in held.items())
    fig.text(0.5, -0.02, f"fixed: {note}", ha="center", va="top",
             fontsize=FONT - 2, color=INK_MUTED)

    fig.savefig(out, dpi=200, facecolor=SURFACE, bbox_inches="tight")
    plt.close(fig)


def main():
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("csv", nargs="?", type=Path, default=here / "results" / "sweep.csv")
    ap.add_argument("-o", "--out-dir", type=Path,
                    help="output directory (default: next to the CSV)")
    ap.add_argument("--metric", choices=METRICS, default="total_s")
    ap.add_argument("--fix", action="append", default=[], metavar="PARAM=VALUE",
                    help="hold a parameter at this value (repeatable)")
    ap.add_argument("--log", action="store_true", help="logarithmic time axis")
    a = ap.parse_args()

    fixed = {}
    for item in a.fix:
        q, _, val = item.partition("=")
        if q not in PARAMS or not val.isdigit():
            ap.error(f"--fix '{item}' is not PARAM=VALUE with PARAM in {', '.join(PARAMS)}")
        fixed[q] = int(val)

    if not a.csv.is_file():
        sys.exit(f"error: {a.csv} not found; run ./run-sweep.sh first")
    df = pd.read_csv(a.csv)
    needed = list(PARAMS) + [f"{prefix}_{a.metric}" for prefix, *_ in PARSERS]
    missing = [col for col in needed if col not in df.columns]
    if missing:
        sys.exit(f"error: {a.csv} lacks the columns {', '.join(missing)}")

    out_dir = a.out_dir or a.csv.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    varying = [q for q in PARAMS if df[q].nunique() > 1]
    if not varying:
        sys.exit(f"error: no parameter varies in {a.csv}; nothing to plot")
    for param in varying:
        if param in fixed:
            continue
        rows, held = pick_slice(df, param, fixed)
        if rows.empty or rows[param].nunique() < 2:
            print(f"{param}: fewer than two points with {fixed}; skipped", file=sys.stderr)
            continue
        # A slice may hold several rows per x (appended reruns): average them.
        rows = rows.groupby(param, as_index=False).mean(numeric_only=True)
        out = out_dir / f"{a.csv.stem}-{param}.pdf"
        render(rows, param, held, a.metric, a.log, out)
        print(f"{out}  ({len(rows)} points; fixed: {held})")


if __name__ == "__main__":
    main()
