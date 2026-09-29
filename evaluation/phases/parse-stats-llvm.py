#!/usr/bin/env python3
"""Turn the stats block printed by pasteque-llvm-stats into CSV rows.

Reads the output of a pasteque-llvm-stats run (stdin by default, or a saved log)
and appends one row per reported phase to results/phases-llvm.csv.

    ./checkers/pasteque-llvm-stats a.polys a.proof a.spec 2>&1 | \
        ./parse-stats-llvm.py -b a
    ./parse-stats-llvm.py run.log -b a -r 2

The instrumented driver (stats.c) reports a phase table whose length depends on
the tier the binary was injected at: 9 phases at tier 1, 16 at tier 2 (see the
phase table in stats.h). A row per phase therefore keeps the schema fixed when
the tier changes, which a column per phase would not. The phase columns are

    phase, depth, incl_s, self_s, self_pct, calls, allocs, alloc_mib

with `depth` taken from the indentation of the label, i.e. the nesting of the
phase in the call tree, and `(unattributed)` kept as a phase with no `incl_s`:
it is the time inside the verified checker that no wrapped phase accounts for
and is what shows that the table is complete.

The run-level measurements - the three input parsing timers, the driver timers,
peak RSS, the allocator counters and the verdict - are repeated on every row of
the run. They describe the run, not the phase, so this is redundant; it is also
what lets one row be read without joining a second table, and grouping by
(bench, checker, round) recovers them.

The columns differ from the ones the SML counterpart writes, because the two
drivers measure different things: MLton splits every timer into a GC and a
non-GC part, the LLVM checker has no garbage collector but breaks the verified
code itself apart. See ./parse-stats-sml.py.

Anything the log does not contain is an error rather than an empty field. In
particular a binary built from an uninstrumented pasteque.ll prints the phase
section as a single "no phase was entered" line, which this script rejects
instead of writing rows with no phases in them.
"""

import argparse
import csv
import re
import sys
from pathlib import Path

# --- the lines stats.c writes ----------------------------------------------

# `c %-38s %9.3f %9.3f %6.1f%% %12llu %12llu %10.1f`. The label field keeps its
# leading indent, which is where `depth` comes from.
PHASE_RE = re.compile(
    r"^c (?P<indent> *)(?P<label>\S.*?) {2,}"
    r"(?P<incl_s>\d+\.\d+) +(?P<self_s>\d+\.\d+) +(?P<self_pct>\d+\.\d+)% +"
    r"(?P<calls>\d+) +(?P<allocs>\d+) +(?P<alloc_mib>\d+\.\d+)$"
)
# The same line for `(unattributed)`, which has no inclusive time, no call count
# and no allocation columns.
UNATTRIBUTED_RE = re.compile(
    r"^c \((?P<label>unattributed)\) +(?P<self_s>\d+\.\d+) +(?P<self_pct>\d+\.\d+)%$"
)

# Run-level scalars: column -> (prefix, regex over the rest of the line).
SCALARS = {
    "polys_parse_s": ("c parsing polys file:", r"(?P<v>\d+\.\d+) s"),
    "pac_parse_s": ("c parsing pac file:", r"(?P<v>\d+\.\d+) s"),
    "spec_parse_s": ("c parsing spec file:", r"(?P<v>\d+\.\d+) s"),
    "init_s": ("c full init (lexing and parsing):", r"(?P<v>\d+\.\d+) s"),
    "solve_s": ("c time solving:", r"(?P<v>\d+\.\d+) s"),
    "teardown_s": ("c teardown (allocator):", r"(?P<v>\d+\.\d+) s"),
    "peak_rss_mib": ("c peak RSS:", r"(?P<v>\d+\.\d+) MiB"),
    "calloc_calls": ("c isabelle_llvm_calloc:", r"(?P<v>\d+) calls,"),
    "calloc_mib": ("c isabelle_llvm_calloc:", r"\d+ calls, (?P<v>\d+\.\d+) MiB"),
    "free_calls": ("c isabelle_llvm_free:", r"(?P<v>\d+) calls"),
}
# getrusage() may fail, in which case peak RSS and the usr/sys split of the
# total are not printed at all. Everything else above is unconditional.
OPTIONAL_SCALARS = {"peak_rss_mib"}

# `c Overall: %.3f s` with an optional ` = %.3f s (usr) %.3f s (sys)`.
OVERALL_RE = re.compile(
    r"^c Overall: (?P<overall_s>\d+\.\d+) s"
    r"(?: = (?P<overall_usr_s>\d+\.\d+) s \(usr\) (?P<overall_sys_s>\d+\.\d+) s \(sys\))?$"
)
# Only printed when the driver was built with -DPST_TIME_ALLOC; the other
# branch prints "not measured", which leaves the column empty.
ALLOC_TIME_RE = re.compile(
    r"^c time in allocator: (?P<alloc_s>\d+\.\d+) s = (?P<alloc_pct>\d+\.\d+)% of the checker$"
)

# The status tag of status_assn, mapped onto the vocabulary run-checkers.sh uses
# for all checkers. stats.c prints the tag on stdout and spells it out on
# stderr; the spelled-out line is the one that survives a `2>&1 | tee`.
VERDICTS = [
    ("run_checker: FOUND", "TARGET"),
    ("run_checker: SUCCESS", "NO_TARGET"),
    ("run_checker: FAILED", "INVALID"),
]

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
    "overall_usr_s",
    "overall_sys_s",
    "peak_rss_mib",
    "calloc_calls",
    "calloc_mib",
    "free_calls",
    "alloc_s",
    "alloc_pct",
    "verdict",
]
PHASE_COLUMNS = [
    "phase",
    "depth",
    "incl_s",
    "self_s",
    "self_pct",
    "calls",
    "allocs",
    "alloc_mib",
]
COLUMNS = RUN_COLUMNS + PHASE_COLUMNS


def parse_phases(lines: list[str], source: str) -> list[dict[str, str]]:
    if any(line.startswith("c no phase was entered") for line in lines):
        sys.exit(
            f"error: {source} reports no phases: the binary was linked against an\n"
            "       uninstrumented pasteque.ll. Rebuild it with:\n"
            "         ./collect-checkers.sh pasteque-llvm-stats"
        )

    phases: list[dict[str, str]] = []
    for line in lines:
        m = PHASE_RE.match(line)
        if m:
            phases.append(
                {
                    "phase": m["label"],
                    "depth": str(len(m["indent"]) // 2),
                    "incl_s": m["incl_s"],
                    "self_s": m["self_s"],
                    "self_pct": m["self_pct"],
                    "calls": m["calls"],
                    "allocs": m["allocs"],
                    "alloc_mib": m["alloc_mib"],
                }
            )
            continue
        m = UNATTRIBUTED_RE.match(line)
        if m:
            phases.append(
                {
                    "phase": f"({m['label']})",
                    "depth": "1",
                    "incl_s": "",
                    "self_s": m["self_s"],
                    "self_pct": m["self_pct"],
                    "calls": "",
                    "allocs": "",
                    "alloc_mib": "",
                }
            )

    if not phases:
        sys.exit(
            f"error: {source} has no phase table. Expected the output of\n"
            "       pasteque-llvm-stats, which prints its report on stderr, so a\n"
            "       log has to be captured with 2>&1 or 2>."
        )
    return phases


def parse_run(lines: list[str], source: str) -> dict[str, str]:
    run: dict[str, str] = {}
    missing = []

    for column, (prefix, pattern) in SCALARS.items():
        rest = None
        for line in reversed(lines):
            if line.startswith(prefix):
                rest = line[len(prefix):].strip()
                break
        if rest is None:
            if column not in OPTIONAL_SCALARS:
                missing.append(prefix)
            run[column] = ""
            continue
        m = re.match(pattern, rest)
        if not m:
            sys.exit(f"error: {source}: cannot parse '{prefix}' value: {rest!r}")
        run[column] = m["v"]

    for line in lines:
        m = OVERALL_RE.match(line)
        if m:
            run.update({k: (v or "") for k, v in m.groupdict().items()})
            break
    else:
        missing.append("c Overall:")

    run["alloc_s"] = ""
    run["alloc_pct"] = ""
    for line in lines:
        m = ALLOC_TIME_RE.match(line)
        if m:
            run.update(m.groupdict())
            break

    if missing:
        sys.exit(
            f"error: {source} has no complete stats block; missing line(s):\n"
            + "".join(f"       {p}\n" for p in sorted(set(missing)))
            + "       Expected the output of pasteque-llvm-stats, which prints its\n"
            "       report on stderr, so a log has to be captured with 2>&1 or 2>."
        )

    run["verdict"] = "UNKNOWN"
    for needle, verdict in VERDICTS:
        if any(line.startswith(needle) for line in lines):
            run["verdict"] = verdict
            break
    return run


def default_tier(here: Path) -> str:
    """The tier of the last pasteque-llvm-stats record in checkers/build-info.txt.

    The tier is not in the checker's output but decides which phases it can
    attribute at all, so a table of these rows is not interpretable without it.
    """
    info = here / "checkers" / "build-info.txt"
    if not info.is_file():
        return ""
    tier = ""
    in_record = False
    for line in info.read_text(errors="replace").splitlines():
        if line.startswith("["):
            in_record = line.strip() == "[pasteque-llvm-stats]"
        elif in_record and line.strip().startswith("tier:"):
            tier = line.split(":", 1)[1].strip()
    return tier


def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        epilog="\n".join(__doc__.splitlines()[1:]),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "log",
        nargs="?",
        default="-",
        help="log to read (default: - for stdin)",
    )
    parser.add_argument(
        "-o",
        "--csv",
        type=Path,
        default=here / "results" / "phases-llvm.csv",
        help="CSV to append to (default: results/phases-llvm.csv)",
    )
    parser.add_argument(
        "-b",
        "--bench",
        help="benchmark name for the rows (default: the log's file name stem)",
    )
    parser.add_argument("-r", "--round", default="1", help="round number (default: 1)")
    parser.add_argument(
        "-c",
        "--checker",
        default="pasteque-llvm-stats",
        help="checker name for the rows (default: pasteque-llvm-stats)",
    )
    parser.add_argument(
        "-t",
        "--tier",
        help="instrumentation tier of the binary "
        "(default: the last pasteque-llvm-stats record in checkers/build-info.txt)",
    )
    parser.add_argument(
        "-w",
        "--overwrite",
        action="store_true",
        help="truncate the CSV first instead of appending to it",
    )
    args = parser.parse_args()

    if args.log == "-":
        source = "<stdin>"
        text = sys.stdin.read()
    else:
        path = Path(args.log)
        if not path.is_file():
            sys.exit(f"error: no such log: {path}")
        source = str(path)
        text = path.read_text(errors="replace")

    bench = args.bench
    if bench is None:
        bench = Path(args.log).stem if args.log != "-" else "unknown"

    lines = [line.rstrip("\n") for line in text.splitlines()]
    phases = parse_phases(lines, source)
    run = parse_run(lines, source)
    run["bench"] = bench
    run["checker"] = args.checker
    run["round"] = args.round
    run["tier"] = args.tier if args.tier is not None else default_tier(here)

    # The injector and the driver share the phase table in stats.h, so unbalanced
    # hooks mean the .ll the binary was linked against is not the one stats.h
    # describes, and the phase columns of such a report are not attributable.
    # The rows are still written - discarding a measurement is the caller's
    # decision - but the exit status and the message on stderr say so.
    warning = next((l for l in lines if l.startswith("c WARNING:")), None)

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    write_header = args.overwrite or not args.csv.exists() or args.csv.stat().st_size == 0
    with args.csv.open("w" if args.overwrite else "a", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNS)
        if write_header:
            writer.writeheader()
        for phase in phases:
            writer.writerow({**run, **phase})

    print(
        f"{bench} / {args.checker} round {args.round} (tier "
        f"{run['tier'] or '?'}): {len(phases)} phase row(s), "
        f"init {run['init_s']} s, solve {run['solve_s']} s, "
        f"overall {run['overall_s']} s, {run['verdict']} -> {args.csv}"
    )
    if warning:
        print(f"warning: {source}: {warning[2:]}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
