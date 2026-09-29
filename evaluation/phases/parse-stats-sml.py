#!/usr/bin/env python3
"""Turn the stats block printed by pasteque-sml into one CSV row.

Reads the output of a pasteque-sml run (stdin by default, or a saved log) and
appends one row per run to results/phases-sml.csv.

    ./checkers/pasteque-sml a.polys a.proof a.spec | ./parse-stats-sml.py -b a
    ./parse-stats-sml.py run.log -b a -r 2

The driver (pasteque.sml, print_stat) reports five CPU timers, each split by
MLton into a non-GC and a GC part:

    polys_parse  parsing the input polynomials
    pac_parse    parsing the proof
    init         all three input files (polys_parse + pac_parse + the spec)
    solve        the verified checker
    overall      init + solve

For every timer print_stat prints the non-GC part as `usr + sys = usr (usr)
sys (sys)`; for `solve` and `overall` it also prints the GC part the same way
and the sum of both as `(full)`. This script keeps all of it: the columns are
named after the timers above with the suffixes `_s`, `_usr_s`, `_sys_s` for the
non-GC part, `_gc_s`/`_gc_usr_s`/`_gc_sys_s` for the GC part and `_full_s` for
the sum. The GC parts of the three init timers are not printed and are
therefore absent rather than zero.

One row per run, because the timers are run-level scalars. The LLVM
counterpart writes one row per phase and thus a different schema; see
./parse-stats-llvm.py.

Anything the log does not contain is an error rather than an empty field: a
truncated stats block means the run died mid-report, and a row of silent blanks
would be averaged into the results later.
"""

import argparse
import csv
import re
import sys
from pathlib import Path

# The exact prefixes print_stat writes, in report order. Matching them literally
# rather than with one generic pattern keeps `c time GC:` from also matching the
# non-GC lines, whose label ends in " (nonGC)".
NONGC_TIMERS = [
    ("polys_parse", "c parsing polys file init (nonGC): "),
    ("pac_parse", "c parsing pac file init (nonGC): "),
    ("init", "c full init (nonGC): "),
    ("solve", "c time solving (nonGC): "),
    ("overall", "c Overall (nonGC): "),
]
GC_TIMERS = [
    ("solve_gc", "c time GC: "),
    ("overall_gc", "c overall GC: "),
]
FULL_TIMERS = [
    ("solve_full", "c time solving(full): "),
    ("overall_full", "c Overall(full): "),
]

# `<total> s = <usr> s (usr) <sys> s (sys)`; SML's Time.toString has no sign and
# a fixed number of decimals, but accept the general shape.
SPLIT_RE = re.compile(
    r"^(?P<total>\d+\.\d+) s = (?P<usr>\d+\.\d+) s \(usr\) (?P<sys>\d+\.\d+) s \(sys\)$"
)
TOTAL_RE = re.compile(r"^(?P<total>\d+\.\d+) s$")

# The three outcomes pasteque.sml can print, mapped onto the vocabulary
# run-checkers.sh already uses for all checkers.
VERDICTS = [
    ("s SUCCESSFULL", "TARGET"),
    ("s FAILED, but correct PAC", "NO_TARGET"),
    ("s PAC FAILED", "INVALID"),
]

COLUMNS = (
    ["bench", "checker", "round"]
    + [f"{name}{suffix}" for name, _ in NONGC_TIMERS for suffix in ("_s", "_usr_s", "_sys_s")]
    + [f"{name}{suffix}" for name, _ in GC_TIMERS for suffix in ("_s", "_usr_s", "_sys_s")]
    + [f"{name}_s" for name, _ in FULL_TIMERS]
    + ["verdict"]
)


def parse(lines: list[str], source: str) -> dict[str, str]:
    row: dict[str, str] = {}
    missing = []

    def find(prefix: str) -> str | None:
        # The last occurrence: --iloop runs print_stat once per iteration, and
        # the final report is the one that covers the whole run.
        for line in reversed(lines):
            if line.startswith(prefix):
                return line[len(prefix):]
        return None

    for name, prefix in NONGC_TIMERS + GC_TIMERS:
        rest = find(prefix)
        if rest is None:
            missing.append(prefix.rstrip())
            continue
        m = SPLIT_RE.match(rest)
        if not m:
            sys.exit(f"error: {source}: cannot parse '{prefix.rstrip()}' value: {rest!r}")
        row[f"{name}_s"] = m["total"]
        row[f"{name}_usr_s"] = m["usr"]
        row[f"{name}_sys_s"] = m["sys"]

    for name, prefix in FULL_TIMERS:
        rest = find(prefix)
        if rest is None:
            missing.append(prefix.rstrip())
            continue
        m = TOTAL_RE.match(rest)
        if not m:
            sys.exit(f"error: {source}: cannot parse '{prefix.rstrip()}' value: {rest!r}")
        row[f"{name}_s"] = m["total"]

    if missing:
        sys.exit(
            f"error: {source} has no complete stats block; missing line(s):\n"
            + "".join(f"       {p}\n" for p in missing)
            + "       Expected the output of pasteque-sml. Note that the driver\n"
            "       prints its stats on stdout, so a log captured with 2> only\n"
            "       will not contain them."
        )

    # The verdict is printed before the stats block, so a log that got this far
    # has it; treat its absence as UNKNOWN rather than as a parse failure.
    row["verdict"] = "UNKNOWN"
    for needle, verdict in VERDICTS:
        if any(line.startswith(needle) for line in lines):
            row["verdict"] = verdict
            break
    return row


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
        default=here / "results" / "phases-sml.csv",
        help="CSV to append to (default: results/phases-sml.csv)",
    )
    parser.add_argument(
        "-b",
        "--bench",
        help="benchmark name for the row (default: the log's file name stem)",
    )
    parser.add_argument("-r", "--round", default="1", help="round number (default: 1)")
    parser.add_argument(
        "-c",
        "--checker",
        default="pasteque-sml",
        help="checker name for the row (default: pasteque-sml)",
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
    row = parse(lines, source)
    row["bench"] = bench
    row["checker"] = args.checker
    row["round"] = args.round

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    write_header = args.overwrite or not args.csv.exists() or args.csv.stat().st_size == 0
    with args.csv.open("w" if args.overwrite else "a", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNS)
        if write_header:
            writer.writeheader()
        writer.writerow(row)

    print(
        f"{bench} / {args.checker} round {args.round}: "
        f"init {row['init_s']} s, solve {row['solve_s']} s "
        f"(+{row['solve_gc_s']} s GC), overall {row['overall_full_s']} s, "
        f"{row['verdict']} -> {args.csv}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
