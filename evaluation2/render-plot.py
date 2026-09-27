#!/usr/bin/env python3
"""Plot an averages CSV: wall clock time and peak RSS of every checker over the
benchmarks, ordered by how long pasteque-llvm took.

    ./render-plot.py [CSV] [-o OUT] [--log] [--panels]

Reads the output of ./average-results.py and writes results/plot.pdf.

Encoding: colour identifies the checker and never moves between them, line
style identifies the measure (solid wall clock on the left axis, dashed peak
RSS on the right). Identity is therefore never carried by colour alone, which
matters both for colour-vision deficiency and for a greyscale print of the
thesis.

The default layout puts the two measures on two y-scales, as specified. Their
alignment is arbitrary, so where the lines cross carries no meaning; read each
measure against its own axis and compare checkers within one measure, never a
wall-clock line against an RSS line. --panels draws the same data as two
stacked panels sharing the x-axis, which removes that hazard.

Colours are slots 1-3 of the skill's default categorical palette, which pass
the all-pairs colour-vision checks as a set. Aqua sits below 3:1 against the
surface; the relief for that is the companion table from ./render-table.py.
"""

import argparse
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display in the devshell or on a build machine
import matplotlib.pyplot as plt
import pandas as pd

# Colour follows the checker, assigned in this fixed order and never cycled.
CHECKERS = [
    ("pacheck", "Pacheck", "#2a78d6"),
    ("pasteque-llvm", "Pastèque LLVM", "#eb6834"),
    ("pasteque-sml", "Pastèque SML", "#1baf7a"),
]
ORDER_BY = "pasteque-llvm"

REQUIRED = ["bench", "checker", "wall_s_mean", "max_rss_kb_mean", "verdict"]

# Verdicts whose timings are not a completed measurement: plotted as gaps
# rather than as points, so a timeout cannot read as a fast run.
NOT_MEASURED = {"TIMEOUT", "ERROR"}

SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_MUTED = "#52514e"
GRID = "#dcdcd8"


def style_axes(ax):
    ax.set_facecolor(SURFACE)
    # The top spine is never data; on a twinned axis it is drawn a second time
    # and reads as a rule across the figure.
    ax.spines["top"].set_visible(False)
    for side in ("left", "right", "bottom"):
        if ax.spines[side].get_visible():
            ax.spines[side].set_color(GRID)
    ax.tick_params(colors=INK_MUTED, labelsize=9)
    ax.xaxis.label.set_color(INK)
    ax.yaxis.label.set_color(INK)


def series(df, bench_order, checker, column, divisor=1.0):
    """One checker's values in benchmark order, with gaps where nothing was
    measured so that the line breaks instead of interpolating over a timeout."""
    rows = df[df["checker"] == checker].set_index("bench")
    out = []
    for bench in bench_order:
        if bench not in rows.index:
            out.append(float("nan"))
            continue
        row = rows.loc[bench]
        if str(row["verdict"]) in NOT_MEASURED:
            out.append(float("nan"))
        else:
            out.append(float(row[column]) / divisor)
    return out


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
        default=here / "results" / "plot.pdf",
        help="output figure; extension picks the format (default: results/plot.pdf)",
    )
    parser.add_argument(
        "--log", action="store_true", help="log scale on both value axes"
    )
    parser.add_argument(
        "--panels",
        action="store_true",
        help="two stacked panels sharing the x-axis instead of two y-scales",
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

    present = [c for c in CHECKERS if c[0] in set(df["checker"])]
    if not present:
        sys.exit(f"error: {args.csv} holds none of the known checkers")

    # Order the x-axis by the reference checker's wall clock time. Benchmarks it
    # did not complete have no position on that scale, so they go last.
    ref = df[(df["checker"] == ORDER_BY) & (~df["verdict"].isin(NOT_MEASURED))]
    key = dict(zip(ref["bench"], ref["wall_s_mean"]))
    if not key:
        print(
            f"warning: {ORDER_BY} completed no benchmark; ordering the x-axis by name",
            file=sys.stderr,
        )
    bench_order = sorted(
        dict.fromkeys(df["bench"]), key=lambda b: (key.get(b, float("inf")), str(b))
    )
    unordered = [b for b in bench_order if b not in key]
    if unordered and key:
        print(
            f"note: {len(unordered)} benchmark(s) without a {ORDER_BY} time "
            f"placed last: {', '.join(map(str, unordered))}",
            file=sys.stderr,
        )

    # A log axis cannot place a zero, so such points vanish without trace.
    # Measurements below GNU time's 10 ms resolution read as exactly 0.00.
    if args.log:
        measured = df[~df["verdict"].isin(NOT_MEASURED)]
        dropped = int(
            (measured["wall_s_mean"] <= 0).sum()
            + (measured["max_rss_kb_mean"] <= 0).sum()
        )
        if dropped:
            print(
                f"warning: {dropped} value(s) are zero and cannot be drawn on a "
                "log axis; they are missing from the figure",
                file=sys.stderr,
            )

    x = range(len(bench_order))
    width = max(7.0, 1.1 * len(bench_order) + 3.0)

    if args.panels:
        fig, (ax_w, ax_r) = plt.subplots(
            2, 1, figsize=(width, 6.4), sharex=True, height_ratios=[1, 1]
        )
        fig.patch.set_facecolor(SURFACE)
        axes = [(ax_w, "wall_s_mean", 1.0, "-", "o"), (ax_r, "max_rss_kb_mean", 1024.0, "--", "s")]
        ax_w.set_ylabel("wall clock time [s]", fontsize=10)
        ax_r.set_ylabel("peak RSS [MiB]", fontsize=10)
        bottom, legend_ax = ax_r, ax_w
    else:
        fig, ax_w = plt.subplots(figsize=(width, 5.2))
        fig.patch.set_facecolor(SURFACE)
        ax_r = ax_w.twinx()
        axes = [(ax_w, "wall_s_mean", 1.0, "-", "o"), (ax_r, "max_rss_kb_mean", 1024.0, "--", "s")]
        ax_w.set_ylabel("wall clock time [s]  (solid)", fontsize=10)
        ax_r.set_ylabel("peak RSS [MiB]  (dashed)", fontsize=10)
        bottom, legend_ax = ax_w, ax_w

    for ax, column, divisor, linestyle, marker in axes:
        for checker, _, colour in present:
            ax.plot(
                x,
                series(df, bench_order, checker, column, divisor),
                linestyle=linestyle,
                marker=marker,
                color=colour,
                linewidth=2.0,
                markersize=6.0,
                markeredgecolor=SURFACE,
                markeredgewidth=1.0,
                zorder=3,
            )
        if args.log:
            ax.set_yscale("log")
        style_axes(ax)
        ax.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
        ax.set_axisbelow(True)

    if not args.panels:
        # Only the left axis draws the horizontal grid, or the two scales' lines
        # interleave into a mesh that belongs to neither.
        ax_r.grid(False)

    bottom.set_xticks(list(x))
    bottom.set_xticklabels(
        [str(b) for b in bench_order], rotation=30, ha="right", fontsize=9
    )
    bottom.set_xlabel(
        f"benchmark, ordered by {dict((c, n) for c, n, _ in CHECKERS)[ORDER_BY]} "
        "wall clock time",
        fontsize=10,
    )

    # Two small legends rather than six combined entries: one says which colour
    # is which checker, the other which line style is which measure.
    checker_handles = [
        plt.Line2D([], [], color=colour, linewidth=2.0, label=name)
        for _, name, colour in present
    ]
    measure_handles = [
        plt.Line2D([], [], color=INK_MUTED, linewidth=2.0, linestyle="-",
                   marker="o", markersize=6.0, label="wall clock time"),
        plt.Line2D([], [], color=INK_MUTED, linewidth=2.0, linestyle="--",
                   marker="s", markersize=6.0, label="peak RSS"),
    ]
    def titled(legend):
        legend.get_title().set_fontsize(9)
        legend.get_title().set_color(INK_MUTED)
        return legend

    first = titled(legend_ax.legend(
        handles=checker_handles, loc="upper left", frameon=False,
        fontsize=9, labelcolor=INK, title="Checker", alignment="left",
    ))
    # In the panel layout each panel's y-axis already names its measure, so a
    # second legend would only add ink -- and collide with the first, since the
    # panel is half the height the single-axis layout has.
    if not args.panels:
        legend_ax.add_artist(first)
        titled(legend_ax.legend(
            handles=measure_handles, loc="upper left", bbox_to_anchor=(0.0, 0.76),
            frameon=False, fontsize=9, labelcolor=INK, title="Measure",
            alignment="left",
        ))

    fig.tight_layout()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, dpi=200, facecolor=SURFACE)
    plt.close(fig)

    print(f"{len(bench_order)} benchmark(s) x {len(present)} checker(s) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
