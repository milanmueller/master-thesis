#!/usr/bin/env python3
"""Turn a results CSV into results/summary.md (and plots, if matplotlib is there).

Usable both as a library (run_bench.py calls generate()) and standalone:
    python3 report.py results/results-20260727-201500.csv
"""

import csv
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def read_rows(csv_path):
    with open(csv_path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    for r in rows:
        r["wall_s"] = float(r["wall_s"])
        r["max_rss_kb"] = int(r["max_rss_kb"])
        r["rss_floor_kb"] = int(r.get("rss_floor_kb") or 0)
        r["rep"] = int(r["rep"])
    return rows


def aggregate(rows):
    """(instance, checker) -> {median/min wall, max rss, verdict, status}."""
    buckets = defaultdict(list)
    for r in rows:
        buckets[(r["instance"], r["checker"])].append(r)
    agg = {}
    for key, rs in buckets.items():
        walls = [r["wall_s"] for r in rs]
        agg[key] = {
            "median_s": statistics.median(walls),
            "min_s": min(walls),
            "max_rss_kb": max(r["max_rss_kb"] for r in rs),
            # Below the floor the driver cannot resolve the child's own usage.
            "rss_at_floor": all(r["max_rss_kb"] <= r["rss_floor_kb"] for r in rs),
            "rss_floor_kb": max(r["rss_floor_kb"] for r in rs),
            "verdict": "/".join(sorted({r["verdict"] for r in rs})),
            "status": "/".join(sorted({r["status"] for r in rs})),
            "reps": len(rs),
        }
    return agg


def md_table(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join("---" for _ in headers) + "|"]
    for row in rows:
        out.append("| " + " | ".join(str(c) for c in row) + " |")
    return "\n".join(out)


def make_plots(rows, out_dir):
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return []

    plots_dir = out_dir / "plots"
    plots_dir.mkdir(parents=True, exist_ok=True)
    agg = aggregate(rows)
    instances = sorted({i for i, _ in agg})
    checkers = sorted({c for _, c in agg})
    written = []

    # Runtime per instance, one bar group per instance.
    fig, ax = plt.subplots(figsize=(max(6, 1.6 * len(instances) * len(checkers)), 4))
    width = 0.8 / len(checkers)
    for k, checker in enumerate(checkers):
        xs = [i + k * width for i in range(len(instances))]
        ys = [agg.get((inst, checker), {}).get("median_s", 0.0) for inst in instances]
        ax.bar(xs, ys, width=width, label=checker)
    ax.set_xticks([i + 0.4 - width / 2 for i in range(len(instances))])
    ax.set_xticklabels(instances, rotation=20, ha="right")
    ax.set_ylabel("median wall-clock time [s]")
    ax.set_title("PAC checker runtime")
    ax.legend()
    fig.tight_layout()
    path = plots_dir / "runtime.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    written.append(path)

    # Peak memory, same layout.
    fig, ax = plt.subplots(figsize=(max(6, 1.6 * len(instances) * len(checkers)), 4))
    for k, checker in enumerate(checkers):
        xs = [i + k * width for i in range(len(instances))]
        ys = [agg.get((inst, checker), {}).get("max_rss_kb", 0) / 1024 for inst in instances]
        ax.bar(xs, ys, width=width, label=checker)
    ax.set_xticks([i + 0.4 - width / 2 for i in range(len(instances))])
    ax.set_xticklabels(instances, rotation=20, ha="right")
    ax.set_ylabel("peak RSS [MiB]")
    ax.set_title("PAC checker memory")
    ax.legend()
    fig.tight_layout()
    path = plots_dir / "memory.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    written.append(path)

    # Cactus plot: instances solved within a time budget. Only informative once
    # the benchmark set is larger than a handful of instances.
    if len(instances) >= 5:
        fig, ax = plt.subplots(figsize=(6, 4))
        for checker in checkers:
            times = sorted(
                agg[(inst, checker)]["median_s"]
                for inst in instances
                if (inst, checker) in agg and agg[(inst, checker)]["status"] == "ok"
            )
            ax.plot(range(1, len(times) + 1), times, marker=".", label=checker)
        ax.set_xlabel("instances solved")
        ax.set_ylabel("wall-clock time [s]")
        ax.set_yscale("log")
        ax.set_title("Cactus plot")
        ax.legend()
        fig.tight_layout()
        path = plots_dir / "cactus.png"
        fig.savefig(path, dpi=150)
        plt.close(fig)
        written.append(path)

    return written


def generate(csv_path, out_dir, build_info=None, disagreements=None):
    out_dir = Path(out_dir)
    rows = read_rows(csv_path)
    agg = aggregate(rows)
    instances = sorted({i for i, _ in agg})
    checkers = sorted({c for _, c in agg})
    build_info = build_info or {}
    disagreements = disagreements or []

    parts = [f"# PAC checker evaluation\n", f"Source: `{Path(csv_path).name}`\n"]

    if build_info:
        parts.append("## Build provenance\n")
        parts.append(
            md_table(
                ["key", "value"],
                [[k, f"`{v}`"] for k, v in build_info.items()],
            )
            + "\n"
        )
    if build_info.get("llvm_variant_mismatch"):
        parts.append(
            "> **Warning:** an LLVM export does not reference the checker implementation it\n"
            "> should (`full_checker_l3_impl` for `pasteque-llvm`, `full_checker_l_s3_impl`\n"
            "> for `pasteque-llvm-shared`). The shared/non-shared comparison below may be a\n"
            "> self-comparison; re-run the Isabelle export.\n"
        )

    parts.append("## Runtime — median wall-clock seconds\n")
    parts.append(
        md_table(
            ["instance"] + checkers,
            [
                [inst]
                + [
                    f"{agg[(inst, c)]['median_s']:.3f}" if (inst, c) in agg else "—"
                    for c in checkers
                ]
                for inst in instances
            ],
        )
        + "\n"
    )

    def rss_cell(inst, c):
        if (inst, c) not in agg:
            return "—"
        a = agg[(inst, c)]
        mib = a["max_rss_kb"] / 1024
        return f"< {mib:.1f}" if a["rss_at_floor"] else f"{mib:.1f}"

    parts.append("## Memory — peak RSS (MiB)\n")
    parts.append(
        md_table(
            ["instance"] + checkers,
            [[inst] + [rss_cell(inst, c) for c in checkers] for inst in instances],
        )
        + "\n"
    )
    if any(agg[k]["rss_at_floor"] for k in agg):
        parts.append(
            "`<` marks runs whose peak RSS stayed under the floor the child inherits from\n"
            "the driver process — the checker used at most that much, but how much less is\n"
            "not observable this way. Only relevant for tiny instances.\n"
        )

    parts.append("## Verdicts\n")
    parts.append(
        md_table(
            ["instance"] + checkers + ["agreement"],
            [
                [inst]
                + [agg[(inst, c)]["verdict"] if (inst, c) in agg else "—" for c in checkers]
                + [
                    "yes"
                    if len({agg[(inst, c)]["verdict"] for c in checkers if (inst, c) in agg}) == 1
                    else "**NO**"
                ]
                for inst in instances
            ],
        )
        + "\n"
    )

    non_ok = [r for r in rows if r["status"] != "ok"]
    if non_ok:
        parts.append("## Non-ok runs\n")
        parts.append(
            md_table(
                ["instance", "checker", "rep", "status", "exit_code"],
                [[r["instance"], r["checker"], r["rep"], r["status"], r["exit_code"]] for r in non_ok],
            )
            + "\n"
        )

    if disagreements:
        parts.append("## Disagreements\n")
        parts.extend(f"- {d}\n" for d in disagreements)

    plots = make_plots(rows, out_dir)
    if plots:
        parts.append("## Plots\n")
        parts.extend(f"- `{p.relative_to(out_dir)}`\n" for p in plots)
    else:
        parts.append("_matplotlib not available — no plots generated._\n")

    summary = out_dir / "summary.md"
    summary.write_text("\n".join(parts))
    print(f"wrote {summary}")
    return summary


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: report.py <results.csv>")
    csv_path = Path(sys.argv[1])
    out_dir = csv_path.parent
    info_path = out_dir / "build-info.json"
    info = json.loads(info_path.read_text()) if info_path.exists() else {}
    generate(csv_path, out_dir, info)
