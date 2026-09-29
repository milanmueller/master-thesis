#!/usr/bin/env python3
"""Plot the phase breakdown of both checkers: one stacked bar per checker and
benchmark, the two checkers side by side.

    ./render-phases-plot.py [--sml CSV] [--llvm CSV] [-o OUT] [--relative] [--panels]

Reads the outputs of ./average-phases-sml.py and ./average-phases-llvm.py and
writes results/phases-plot.pdf. The x-axis is the benchmarks, ordered as in
../main/results/plot.pdf by how long the LLVM backend took; the y-axis is time
in seconds; each bar is stacked out of the three phases section 5 of the thesis
names for that checker:

    Pastèque SML   parsing, checking proof steps, garbage collection
    Pastèque LLVM  parsing, initialization of input polynomials, checking

Encoding: colour identifies the phase and never moves between phases, so the two
phases both checkers report - parsing and checking - carry the same colour in
both bars, which is what makes a pair comparable at a glance. Position
identifies the checker: the left bar of every pair is Standard ML, the right one
LLVM. A hatch pattern repeats the phase, so identity survives a greyscale print
of the thesis; the total above each bar gives the relief the aqua fill needs,
its contrast against the surface being below 3:1.

The SML bars are the full run: parsing + checking + GC is the whole measured
time. The LLVM bars are NOT, by default: the thesis names three phases for that
backend, and the run also contains teardown and a little glue around the
verified checker (3-10% together). --remainder adds those as one grey segment,
which makes a pair's heights comparable as totals rather than as phases.

Garbage collection is drawn as a phase of its own because that is how the
Standard ML driver reports it, but it is not a stage of the run: MLton
accumulates it over whichever interval it happens in. The LLVM backend has no
collector and pays for memory management inside its other phases, so a bar-to-bar
reading of the aqua segment has no counterpart on the right.

The benchmarks span three orders of magnitude, so on one linear axis of time the
32-bit instances are a few pixels tall. A logarithmic axis is not the way out:
stacking puts a segment's top at log(cumulative), so its drawn height is
log(c_i / c_{i-1}) rather than the value, and the same second is drawn about
seventeen times taller at the bottom of a stack than at the top.

--relative is the way out that keeps every benchmark on one axis: each bar is
normalised to its own run, so all of them are the same height and the figure
compares composition rather than duration. The absolute scale is not lost - the
total in seconds stays on the cap of each bar, and the x-axis is still ordered
by the total time of the LLVM backend, which would otherwise be invisible. The
alternatives are to plot benchmarks of one magnitude (--bench or --match) or to
split them over panels with their own scales (--panels).
"""

import argparse
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display in the devshell or on a build machine
import matplotlib.pyplot as plt
import pandas as pd

# Colour follows the phase, assigned here and never cycled. Slots 1, 7, 2 and 3
# of the data-viz skill's default categorical palette; every adjacent pair that
# occurs in either stack passes the CVD and normal-vision separation checks.
# The hatch repeats the phase for greyscale.
PHASES_SML = [
    ("parse_s", "parsing", "#2a78d6", ""),
    ("check_s", "checking proof steps", "#eb6834", "//"),
    ("gc_s", "garbage collection", "#1baf7a", ".."),
]
PHASES_LLVM = [
    ("parse_s", "parsing", "#2a78d6", ""),
    ("init_s", "initialization of input polynomials", "#4a3aa7", "\\\\"),
    ("check_s", "checking proof steps", "#eb6834", "//"),
]
# Teardown, with the 1-2% of glue around the verified checker folded in: the
# allocator consolidating the free lists left by the run's ~1e9 allocations,
# charged to the first allocation after the checker returns. The Standard ML
# backend does the corresponding work during the run and reports it as garbage
# collection, so the two are counterparts rather than an omission.
TEARDOWN = ("remainder_s", "teardown (allocator)", "#9a9a94", "xx")
PHASES_LLVM = PHASES_LLVM + [TEARDOWN]

CHECKERS = [("sml", "Pastèque SML"), ("llvm", "Pastèque LLVM")]

SURFACE = "#ffffff"
INK = "#0b0b0b"
INK_MUTED = "#52514e"
GRID = "#dcdcd8"
FONT = 12  # pt, as in ../main/render-plot.py

BAR_W = 0.38  # two bars plus a gap inside one unit of x
FAMILY_GAP = 1.8  # extra x between two families, with --order family
CHECKER_GAP = 0.5  # extra x between the two checkers, with --group-checkers
RUN_BAR_W = 0.8  # one bar per position, when the checkers are not paired
GAP_LW = 1.5  # surface-coloured edge: the 2px gap between adjacent fills


def style_axes(ax):
    ax.set_facecolor(SURFACE)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=INK_MUTED, labelsize=FONT)
    ax.xaxis.label.set_color(INK)
    ax.yaxis.label.set_color(INK)


def load(path: Path, required: list[str], produced_by: str) -> pd.DataFrame:
    if not path.is_file():
        sys.exit(
            f"error: no such CSV: {path}\n"
            f"       write it with {produced_by}"
        )
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


def by_family_split(args) -> bool:
    return args.order == "family"


def family_of(bench) -> str:
    """The leading letters of a stem: btor-256 and btor-512 are one family."""
    m = re.match(r"[A-Za-z]+", str(bench))
    return m.group(0) if m else str(bench)


def layout(bench_order, by_family: bool, by_checker: bool):
    """Where every bar goes.

    Returns the bars as (bench, checker, x), the x of each tick, and the x of
    the rules that separate the blocks.

    Two arrangements. Paired (the default) puts a benchmark's two checkers next
    to each other, which compares the checkers on one instance. Grouped by
    checker (--group-checkers) puts a checker's whole family in one run, which
    compares the instances of a family with each other: the progression with the
    instance size is then read along a run of bars of one checker rather than
    across alternating ones.
    """
    bars, ticks, rules = [], [], []
    x = 0.0
    if not by_checker:
        for i, bench in enumerate(bench_order):
            if by_family and i > 0 and family_of(bench) != family_of(bench_order[i - 1]):
                rules.append(x - 0.5 + FAMILY_GAP / 2.0)
                x += FAMILY_GAP
            for key, _ in CHECKERS:
                bars.append((bench, key, x + (-BAR_W / 2 if key == "sml" else BAR_W / 2)))
            ticks.append((bench, x))
            x += 1.0
        return bars, ticks, rules, BAR_W

    families = list(dict.fromkeys(family_of(b) for b in bench_order))
    for fi, family in enumerate(families):
        members = [b for b in bench_order if family_of(b) == family]
        if fi > 0:
            rules.append(x - 0.5 + FAMILY_GAP / 2.0)
            x += FAMILY_GAP
        for ci, (key, _) in enumerate(CHECKERS):
            if ci > 0:
                x += CHECKER_GAP
            for bench in members:
                bars.append((bench, key, x))
                ticks.append((bench, x))
                x += 1.0
    return bars, ticks, rules, RUN_BAR_W


def draw(ax, bars, data, phases_by_checker, relative, width):
    """A stacked bar at every position the layout gave."""
    for key, _ in CHECKERS:
        df = data[key]
        phases = phases_by_checker[key]
        mine = [(b, x) for b, k, x in bars if k == key]
        if not mine:
            continue
        xs = [x for _, x in mine]
        bottom = [0.0] * len(mine)
        for column, _, colour, hatch in phases:
            values = []
            for bench, _ in mine:
                if bench not in df.index:
                    values.append(0.0)
                    continue
                v = float(df.loc[bench, column])
                if relative:
                    # Against the whole run, which the phases now cover for both
                    # checkers, so that every bar reaches exactly 100%.
                    total = float(df.loc[bench, "overall_s"])
                    v = 100.0 * v / total if total > 0 else 0.0
                values.append(v)
            ax.bar(
                xs, values, width, bottom=bottom, color=colour, hatch=hatch,
                edgecolor=SURFACE, linewidth=GAP_LW, zorder=3,
            )
            bottom = [b + v for b, v in zip(bottom, values)]
        for (bench, x), top in zip(mine, bottom):
            if top <= 0:
                continue
            # With every bar the same height the ordering by total time would
            # otherwise be invisible, so the cap carries the total in seconds.
            total = (
                float(df.loc[bench, "overall_s"]) if bench in df.index else 0.0
            )
            ax.annotate(
                f"{total:.3g}" if relative else f"{top:.3g}",
                (x, top),
                textcoords="offset points",
                xytext=(0, 3),
                ha="center",
                va="bottom",
                fontsize=FONT - 3,
                color=INK_MUTED,
                rotation=90,
            )


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
        default=here / "results" / "phases-plot.pdf",
        help="output figure; extension picks the format "
        "(default: results/phases-plot.pdf)",
    )
    parser.add_argument(
        "--relative",
        action="store_true",
        help="normalise every bar to its own total and show composition in "
        "percent instead of time",
    )
    parser.add_argument(
        "--panels",
        action="store_true",
        help="split the benchmarks over two panels with their own y-scales, so "
        "that the small instances stay readable",
    )
    parser.add_argument(
        "--group-checkers",
        action="store_true",
        help="put each checker's bars in one run per family instead of pairing "
        "them per benchmark, so that the progression with the instance size is "
        "read along a run of one checker's bars",
    )
    parser.add_argument(
        "--bench",
        help="comma-separated benchmarks to draw, in place of all of them",
    )
    parser.add_argument(
        "--match",
        help="draw only the benchmarks whose name matches this regular "
        "expression, e.g. '-256$' for the 256-bit instances",
    )
    parser.add_argument(
        "--order",
        choices=("llvm", "name", "family"),
        default="llvm",
        help="x-axis order: by the LLVM total as in ../main/results/plot.pdf "
        "(default), by benchmark name, or by family and then by the LLVM total "
        "(\'family\'), which puts each instance family in its own block so that "
        "the progression with the instance size can be read along it",
    )
    args = parser.parse_args()

    sml = load(
        args.sml,
        ["bench", "parse_s", "check_s", "gc_s", "overall_s"],
        "average-phases-sml.py",
    )
    llvm = load(
        args.llvm,
        ["bench", "parse_s", "init_s", "check_s", "teardown_s", "other_s",
         "overall_s"],
        "average-phases-llvm.py",
    )
    llvm = llvm.copy()
    llvm["remainder_s"] = llvm["teardown_s"] + llvm["other_s"]

    phases_by_checker = {"sml": list(PHASES_SML), "llvm": list(PHASES_LLVM)}
    data = {"sml": sml, "llvm": llvm}

    both = [b for b in llvm.index if b in sml.index]
    only_sml = [b for b in sml.index if b not in llvm.index]
    only_llvm = [b for b in llvm.index if b not in sml.index]
    if not both:
        sys.exit(
            f"error: {args.sml} and {args.llvm} have no benchmark in common"
        )
    for names, where in ((only_sml, args.llvm), (only_llvm, args.sml)):
        if names:
            print(
                f"note: {len(names)} benchmark(s) missing from {where.name} are "
                f"drawn with one bar only: {', '.join(map(str, names))}",
                file=sys.stderr,
            )

    bench_order = sorted(dict.fromkeys(list(sml.index) + list(llvm.index)))

    # Selecting benchmarks of one magnitude is what makes a single linear axis
    # readable, so an empty selection is an error rather than an empty figure.
    if args.bench:
        wanted = [b.strip() for b in args.bench.split(",") if b.strip()]
        unknown = [b for b in wanted if b not in bench_order]
        if unknown:
            sys.exit(
                f"error: --bench names {len(unknown)} benchmark(s) that are in "
                f"neither CSV: {', '.join(unknown)}"
            )
        bench_order = [b for b in bench_order if b in set(wanted)]
    if args.match:
        try:
            pattern = re.compile(args.match)
        except re.error as exc:
            sys.exit(f"error: --match is not a valid regular expression: {exc}")
        bench_order = [b for b in bench_order if pattern.search(str(b))]
        if not bench_order:
            sys.exit(
                f"error: --match {args.match!r} selected no benchmark; the CSVs "
                f"hold: {', '.join(map(str, sorted(dict.fromkeys(list(sml.index) + list(llvm.index)))))}"
            )

    key = llvm["overall_s"].to_dict()
    if args.order == "llvm":
        bench_order = sorted(
            bench_order, key=lambda b: (key.get(b, float("inf")), str(b))
        )
    elif args.order == "family":
        # Families in the order of their smallest instance, and inside a family
        # by size, so that each block reads left to right as the instance grows.
        first = {}
        for b in bench_order:
            f = family_of(b)
            first[f] = min(first.get(f, float("inf")), key.get(b, float("inf")))
        bench_order = sorted(
            bench_order,
            key=lambda b: (first[family_of(b)], family_of(b),
                           key.get(b, float("inf")), str(b)),
        )

    if not args.relative:
        totals = [
            float(llvm.loc[b, "overall_s"]) for b in bench_order if b in llvm.index
        ]
        if totals and min(totals) > 0 and max(totals) / min(totals) > 20:
            print(
                f"note: the totals span a factor of {max(totals) / min(totals):.0f}; "
                "on one linear axis the smallest bars are only a few pixels tall. "
                "--panels or --relative make them readable.",
                file=sys.stderr,
            )

    # Split by total so that each panel holds one order of magnitude, rather
    # than by name, which would put a 0.1 s and an 80 s bar on one scale again.
    if args.panels and by_family_split(args) and len(bench_order) > 1:
        # One panel per family, so a block is never cut across panels.
        fams = list(dict.fromkeys(family_of(b) for b in bench_order))
        groups = [[b for b in bench_order if family_of(b) == f] for f in fams]
    elif args.panels and len(bench_order) > 1:
        key = llvm["overall_s"].to_dict()
        by_size = sorted(bench_order, key=lambda b: key.get(b, float("inf")))
        half = (len(by_size) + 1) // 2
        small, large = set(by_size[:half]), set(by_size[half:])
        groups = [
            [b for b in bench_order if b in small],
            [b for b in bench_order if b in large],
        ]
    else:
        groups = [bench_order]

    width = max(5.25, 0.825 * len(max(groups, key=len)) + 2.25)
    height = 0.62 * width * len(groups)
    fig, axes = plt.subplots(len(groups), 1, figsize=(width, height))
    axes = [axes] if len(groups) == 1 else list(axes)
    fig.patch.set_facecolor(SURFACE)

    unit = None if args.relative else "time [s]"
    by_family = args.order == "family"
    for ax, group in zip(axes, groups):
        bars, ticks, rules, width = layout(group, by_family, args.group_checkers)
        draw(ax, bars, data, phases_by_checker, args.relative, width)
        style_axes(ax)
        ax.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
        ax.set_axisbelow(True)
        if unit is not None:
            ax.set_ylabel(unit, fontsize=FONT)
        # A rule in the gap between two families, so that the blocks read as
        # blocks rather than as one run of bars that happens to be spaced oddly.
        for rx in rules:
            ax.axvline(rx, color=GRID, linewidth=1.0, zorder=1)
        ax.set_xticks([x for _, x in ticks])
        ax.set_xticklabels(
            [str(b) for b, _ in ticks], rotation=60, ha="right", fontsize=FONT
        )
        xs_all = [x for _, _, x in bars]
        ax.set_xlim(min(xs_all) - 0.7, max(xs_all) + 0.7)
        # Room for the rotated totals on the caps.
        top = ax.get_ylim()[1]
        ax.set_ylim(0, top * (1.10 if args.relative else 1.20))

    # Two legends: one says which colour is which phase, the other which side of
    # a pair is which checker. Identity is therefore never colour alone, and the
    # position encoding is stated rather than left to be inferred.
    # In execution order, not in the order the two checkers happen to be walked:
    # the legend reads as the run does, and a phase only one checker reports
    # sits where it would occur.
    legend_order = [
        PHASES_LLVM[0],   # parsing, reported by both
        PHASES_LLVM[1],   # initialization, LLVM only
        PHASES_LLVM[2],   # checking, reported by both
        PHASES_SML[2],    # garbage collection, SML only
        TEARDOWN,         # teardown, LLVM only
    ]
    drawn = {label for key, _ in CHECKERS
             for _, label, _, _ in phases_by_checker[key]}
    phase_handles = [
        plt.Rectangle((0, 0), 1, 1, facecolor=colour, hatch=hatch,
                      edgecolor=SURFACE, linewidth=GAP_LW, label=label)
        for _, label, colour, hatch in legend_order if label in drawn
    ]
    sides = ("left run of a block", "right run of a block") if args.group_checkers \
        else ("left bar", "right bar")
    side_handles = [
        plt.Rectangle((0, 0), 1, 1, facecolor="#dedede", edgecolor=GRID,
                      label=f"{side}: {name}")
        for (key, name), side in zip(CHECKERS, sides)
    ]

    legend_ax = axes[0]
    legends = []

    def above(handles, offset_pt, ncol):
        transform = matplotlib.transforms.offset_copy(
            legend_ax.transAxes, fig, x=0.0, y=offset_pt, units="points"
        )
        legend = legend_ax.legend(
            handles=handles, loc="lower left", bbox_to_anchor=(0.0, 1.0),
            bbox_transform=transform, ncol=ncol, frameon=False, fontsize=FONT,
            labelcolor=INK, handlelength=1.8, columnspacing=1.5,
            borderaxespad=0.0,
        )
        legend_ax.add_artist(legend)
        legends.append(legend)
        return legend

    side_legend = above(side_handles, 4.0, len(side_handles))
    fig.canvas.draw()
    row_pt = side_legend.get_window_extent().height / fig.dpi * 72.0
    above(phase_handles, 4.0 + row_pt + 2.0, 2)

    fig.tight_layout()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(
        args.out, dpi=200, facecolor=SURFACE, bbox_inches="tight",
        bbox_extra_artists=legends,
    )
    plt.close(fig)

    print(
        f"{len(bench_order)} benchmark(s) x {len(CHECKERS)} checker(s) "
        f"-> {args.out}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
