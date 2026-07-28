#!/usr/bin/env python3
"""Benchmark driver for the PAC checker comparison.

Runs every checker described in checkers.json on every instance found in the
data directory, N times each, and records wall-clock time, peak resident set
size and the normalised verdict into a CSV. Standard library only.

An instance is a triple of files sharing a stem: <stem>.input/.proof/.target
(the pacheck2 convention) or <stem>.polys/.pac/.spec (the pasteque convention).
All four checkers take the three files as positional arguments in that order.
"""

import argparse
import csv
import json
import os
import re
import selectors
import shutil
import signal
import sys
import time
from collections import defaultdict
from pathlib import Path

EXT_GROUPS = [
    ("input", "proof", "target"),
    ("polys", "pac", "spec"),
]

VERDICTS = ("TARGET", "NO_TARGET", "INVALID", "ERROR", "UNKNOWN")


class Instance:
    def __init__(self, name, input_f, proof_f, target_f):
        self.name = name
        self.files = {"input": input_f, "proof": proof_f, "target": target_f}

    def __repr__(self):
        return f"<Instance {self.name}>"


def discover_instances(data_dir):
    """Group files by stem; return complete triples and a list of complaints."""
    by_stem = defaultdict(dict)
    for path in sorted(Path(data_dir).rglob("*")):
        if not path.is_file():
            continue
        ext = path.suffix.lstrip(".")
        for group in EXT_GROUPS:
            if ext in group:
                key = str(path.parent / path.stem)
                by_stem[key][group.index(ext)] = path
                break

    instances, skipped = [], []
    for stem in sorted(by_stem):
        parts = by_stem[stem]
        if len(parts) != 3:
            have = ", ".join(p.name for _, p in sorted(parts.items()))
            skipped.append(f"{stem}: incomplete instance (have {have})")
            continue
        name = Path(stem).name
        instances.append(Instance(name, parts[0], parts[1], parts[2]))
    return instances, skipped


def classify(spec, exit_code, stdout, stderr, timed_out):
    """Map a checker's output onto a normalised verdict."""
    if timed_out:
        return "UNKNOWN"

    mapped = spec.get("exit_codes", {}).get(str(exit_code))
    if mapped:
        return mapped

    streams = {"stdout": stdout, "stderr": stderr}
    for rule in spec.get("rules", []):
        text = streams.get(rule.get("stream", "stdout"), "")
        needle = rule.get("contains")
        if needle is not None and needle in text:
            return rule["verdict"]
        pattern = rule.get("matches")
        if pattern is not None and re.search(pattern, text, re.MULTILINE):
            return rule["verdict"]

    if exit_code != 0 and "on_nonzero_exit" in spec:
        return spec["on_nonzero_exit"]
    return spec.get("default", "UNKNOWN")


def reset_own_peak_rss():
    """Reset this process's VmHWM so children do not inherit a stale peak.

    Linux seeds a child's high-water RSS from its parent's and does not clear it
    on exec, so without this every measurement would be floored by the driver's
    largest-ever footprint. `5` is CLEAR_REFS_MM_HIWATER_RSS.
    """
    try:
        with open("/proc/self/clear_refs", "w") as fh:
            fh.write("5\n")
    except OSError:
        pass


def measure_floor():
    """The RSS floor children inherit from this process, in KiB.

    Anything a checker reports at or below this is 'smaller than we can see'.
    """
    reset_own_peak_rss()
    pid = os.posix_spawn("/bin/true", ["/bin/true"], os.environ)
    return os.wait4(pid, 0)[2].ru_maxrss


def run_once(argv, timeout, log_path):
    """Run argv once; return (wall_s, max_rss_kb, exit_code, stdout, stderr, status).

    Peak RSS is the child's own wait4() high-water mark, but see measure_floor():
    it can never be reported as lower than what the child inherits from us.
    """
    reset_own_peak_rss()
    out_r, out_w = os.pipe()
    err_r, err_w = os.pipe()
    start = time.perf_counter()
    pid = os.posix_spawn(
        argv[0],
        argv,
        os.environ,
        file_actions=[
            (os.POSIX_SPAWN_CLOSE, out_r),
            (os.POSIX_SPAWN_CLOSE, err_r),
            (os.POSIX_SPAWN_DUP2, out_w, 1),
            (os.POSIX_SPAWN_DUP2, err_w, 2),
        ],
    )
    os.close(out_w)
    os.close(err_w)

    # Drain both pipes while waiting so a chatty checker cannot deadlock on a
    # full pipe buffer (pasteque prints a stats block on every run).
    chunks = {out_r: [], err_r: []}
    sel = selectors.DefaultSelector()
    for fd in (out_r, err_r):
        os.set_blocking(fd, False)
        sel.register(fd, selectors.EVENT_READ)

    status = "ok"
    open_fds = 2
    while open_fds:
        remaining = None
        if timeout is not None:
            remaining = timeout - (time.perf_counter() - start)
            if remaining <= 0:
                status = "timeout"
                break
        for key, _ in sel.select(remaining if remaining else 0.5):
            data = os.read(key.fd, 65536)
            if not data:
                sel.unregister(key.fd)
                open_fds -= 1
            else:
                chunks[key.fd].append(data)

    if status == "timeout":
        os.kill(pid, signal.SIGKILL)

    _, wait_status, usage = os.wait4(pid, 0)
    wall = time.perf_counter() - start

    for fd in (out_r, err_r):
        try:
            sel.unregister(fd)
        except KeyError:
            pass
        try:
            while True:
                data = os.read(fd, 65536)
                if not data:
                    break
                chunks[fd].append(data)
        except (BlockingIOError, OSError):
            pass
        os.close(fd)
    sel.close()

    stdout = b"".join(chunks[out_r]).decode("utf-8", "replace")
    stderr = b"".join(chunks[err_r]).decode("utf-8", "replace")

    if os.WIFSIGNALED(wait_status):
        exit_code = -os.WTERMSIG(wait_status)
        if status == "ok":
            status = "crash"
    else:
        exit_code = os.WEXITSTATUS(wait_status)

    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        f"$ {' '.join(argv)}\n"
        f"exit={exit_code} status={status} wall={wall:.6f}s "
        f"maxrss={usage.ru_maxrss}KiB\n"
        f"--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}\n"
    )
    return wall, usage.ru_maxrss, exit_code, stdout, stderr, status


def main():
    ap = argparse.ArgumentParser(
        description="Benchmark PAC proof checkers on a set of instances.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--data", default="/data", help="directory holding the instances")
    ap.add_argument("--out", default="/results", help="directory for CSV, logs and report")
    ap.add_argument("--config", default="/opt/bench/checkers.json")
    ap.add_argument("--bin-dir", default="/opt/checkers/bin")
    ap.add_argument("--build-info", default="/opt/bench/build-info.json")
    ap.add_argument("--reps", type=int, default=3, help="measured repetitions per run")
    ap.add_argument("--warmup", action="store_true",
                    help="do one unrecorded run per (checker, instance) first")
    ap.add_argument("--timeout", type=float, default=None,
                    help="per-run timeout in seconds (default: none)")
    ap.add_argument("--checkers", default=None,
                    help="comma-separated subset of checker ids to run")
    ap.add_argument("--no-report", action="store_true", help="skip generating summary.md")
    args = ap.parse_args()

    config = json.loads(Path(args.config).read_text())
    checkers = config["checkers"]
    if args.checkers:
        wanted = {c.strip() for c in args.checkers.split(",")}
        unknown = wanted - {c["id"] for c in checkers}
        if unknown:
            sys.exit(f"unknown checker id(s): {', '.join(sorted(unknown))}")
        checkers = [c for c in checkers if c["id"] in wanted]

    for c in checkers:
        path = Path(args.bin_dir) / c["binary"]
        if not path.exists():
            sys.exit(f"missing binary for {c['id']}: {path}")
        c["path"] = str(path)

    instances, skipped = discover_instances(args.data)
    for note in skipped:
        print(f"skipping {note}", file=sys.stderr)
    if not instances:
        sys.exit(f"no complete instances found in {args.data}")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    csv_path = out_dir / f"results-{stamp}.csv"

    build_info = {}
    if Path(args.build_info).exists():
        build_info = json.loads(Path(args.build_info).read_text())
        shutil.copyfile(args.build_info, out_dir / "build-info.json")
        if build_info.get("llvm_variant_mismatch"):
            print(
                "WARNING: an LLVM export does not reference the checker implementation it\n"
                "         should (see prepare-context.sh). The shared/non-shared comparison\n"
                "         may be a self-comparison.",
                file=sys.stderr,
            )

    print(f"{len(instances)} instance(s) x {len(checkers)} checker(s) x {args.reps} rep(s)")

    verdicts = defaultdict(dict)  # instance -> checker -> set of verdicts
    rows = []
    for inst in instances:
        for c in checkers:
            argv = [c["path"]] + [
                a.format(**{k: str(v) for k, v in inst.files.items()}) for a in c["argv"]
            ]
            if args.warmup:
                run_once(argv, args.timeout, out_dir / "logs" / f"{inst.name}.{c['id']}.warmup.log")
            for rep in range(1, args.reps + 1):
                log = out_dir / "logs" / f"{inst.name}.{c['id']}.{rep}.log"
                floor = measure_floor()
                wall, rss, code, stdout, stderr, status = run_once(argv, args.timeout, log)
                verdict = classify(c["verdict"], code, stdout, stderr, status == "timeout")
                if status == "ok" and verdict == "ERROR":
                    status = "error"
                verdicts[inst.name].setdefault(c["id"], set()).add(verdict)
                rows.append(
                    {
                        "instance": inst.name,
                        "checker": c["id"],
                        "rep": rep,
                        "wall_s": f"{wall:.6f}",
                        "max_rss_kb": rss,
                        "rss_floor_kb": floor,
                        "exit_code": code,
                        "verdict": verdict,
                        "status": status,
                    }
                )
                below = "<" if rss <= floor else " "
                print(
                    f"  {inst.name:<24} {c['id']:<22} rep {rep}/{args.reps}  "
                    f"{wall:8.3f}s {below}{rss/1024:7.1f} MiB  {verdict} ({status})"
                )

    with csv_path.open("w", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "instance", "checker", "rep", "wall_s",
                "max_rss_kb", "rss_floor_kb", "exit_code", "verdict", "status",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nwrote {csv_path}")

    # Cross-check: every checker must agree on every instance, and each checker
    # must be self-consistent across repetitions.
    disagreements = []
    for inst_name, per_checker in verdicts.items():
        for cid, vs in per_checker.items():
            if len(vs) > 1:
                disagreements.append(
                    f"{inst_name}: {cid} is not deterministic ({', '.join(sorted(vs))})"
                )
        distinct = {next(iter(vs)) for vs in per_checker.values() if len(vs) == 1}
        if len(distinct) > 1:
            detail = ", ".join(
                f"{cid}={'/'.join(sorted(vs))}" for cid, vs in sorted(per_checker.items())
            )
            disagreements.append(f"{inst_name}: checkers disagree ({detail})")

    if not args.no_report:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import report

        report.generate(csv_path, out_dir, build_info, disagreements)

    if disagreements:
        print("\nVERDICT DISAGREEMENTS:", file=sys.stderr)
        for d in disagreements:
            print(f"  {d}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
