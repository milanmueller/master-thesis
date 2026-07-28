# PAC checker evaluation

Docker-based build and benchmark harness comparing three PAC proof checkers
(four binaries):

| id | source | binary |
|---|---|---|
| `pacheck2` | `evaluation/pacheck2` (submodule) | `pacheck` |
| `pasteque-sml` | `isabelle/IsaFoL/PAC_Checker2/code` — Imperative-HOL/MLton, shared variables ("Efficient") | `pasteque-sml` |
| `pasteque-llvm` | `isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker2/code` — Isabelle-LLVM, non-shared | `pasteque` |
| `pasteque-llvm-shared` | same tree, `-DPASTEQUE_SHARED` | `pasteque_shared` |

All four take the same three positional arguments: `<input> <proof> <target>`.

## Prerequisites

The image **does not run Isabelle**; it only compiles code Isabelle has already
exported. Two artefacts must exist in the working tree:

1. `isabelle/IsaFoL/PAC_Checker2/code/checker.ML` — committed upstream, nothing
   to do. Regenerate with `cd isabelle && mk build_pasteque_sml` if needed.
2. `isabelle/IsaFoL-Pasteque-LLVM/PAC_Checker2/code/{pasteque,pasteque_shared}.{ll,h}`
   — **gitignored, working-tree only**. Regenerate with:

   ```sh
   cd isabelle
   isabelle build -d mirror-afp-2025-1/thys -d isabelle_llvm/thys \
                  -d IsabelleBigInteger -d IsaFoL-Pasteque-LLVM PAC_Checker2_LLVM
   ```

`prepare-context.sh` checks both and prints these commands if something is
missing.

### Variant sanity check

Both LLVM variants come from a single theory (`LPAC_CodeExport.thy`) via two
`export_llvm` invocations whose entry points differ only in name, so a stale or
mis-targeted export would silently turn the comparison into a self-comparison.
`prepare-context.sh` therefore checks that

- `pasteque.ll` references `LPAC_Checker_Synthesis_full_checker_l3_impl`, and
- `pasteque_shared.ll` references `LPAC_Efficient_Checker_Synthesis_full_checker_l_s3_impl`.

A mismatch warns and records `llvm_variant_mismatch: true` in `build-info.json`,
which surfaces as a warning in `results/summary.md`.

## Usage

```sh
./run.sh                        # build + 3 repetitions on evaluation/instances
./run.sh --reps 5 --warmup      # discard one warm-up run per (checker, instance)
./run.sh --data /path/to/bench  # larger benchmark set (mounted read-only at /data)
./run.sh --timeout 300          # per-run timeout in seconds (off by default)
./run.sh --checkers pacheck2,pasteque-llvm
NO_BUILD=1 ./run.sh             # reuse the existing image
CPUSET=2 ./run.sh               # pin to one core for quieter timings
DOCKER=podman ./run.sh
```

`./run.sh --help` forwards to the driver's own help.

`instances/` is seeded from `pacheck2/example` on first run. Both `results/` and
`instances/` are gitignored.

## Instances

An instance is three files sharing a stem, in either naming convention:

- `<stem>.input`, `<stem>.proof`, `<stem>.target` (pacheck2), or
- `<stem>.polys`, `<stem>.pac`, `<stem>.spec` (pasteque).

Incomplete groups are reported and skipped. Subdirectories are searched.

## Output

- `results/results-<timestamp>.csv` —
  `instance,checker,rep,wall_s,max_rss_kb,rss_floor_kb,exit_code,verdict,status`
- `results/logs/<instance>.<checker>.<rep>.log` — the command line, exit status
  and full stdout/stderr of every run
- `results/summary.md` — median/min runtime, peak RSS, verdict agreement matrix
- `results/plots/{runtime,memory}.png`, plus `cactus.png` once there are ≥5
  instances

Wall time is `time.perf_counter()` around the spawn; peak RSS is the child's
`wait4()` `ru_maxrss`. Container timings carry a small constant overhead; compare
checkers against each other, not against numbers measured on the host.

**Memory floor.** Linux seeds a child's high-water RSS from its parent's and does
not clear it on `exec`, so a checker can never be observed using less than the
driver process does (~13 MiB). The driver resets its own `VmHWM` via
`/proc/self/clear_refs` before each spawn — which keeps the floor constant
instead of ratcheting up with the driver's own peak — and records it per run as
`rss_floor_kb`. Values at the floor are shown as `< x` in `summary.md`: the
checker used at most that much. Real benchmark instances run well above it.

### Verdicts

Raw output is normalised to `TARGET` (proof valid *and* derives the target),
`NO_TARGET` (steps check but the target was not derived), `INVALID`, `ERROR`, or
`UNKNOWN`. The mapping lives in `checkers.json`, not in code, so adding a checker
or a flag variant is a data change.

Note the three exit-code conventions: `pacheck` exits non-zero on failure,
`pasteque-llvm*` exit 0 only for `TARGET` (2 for usage/IO errors), and
`pasteque-sml` **always exits 0** — its verdict is the `s SUCCESSFULL` /
`s FAILED, but correct PAC` / `s PAC FAILED` line on stdout.

The driver cross-checks that all checkers agree per instance and that each
checker is deterministic across repetitions; disagreements are listed in
`summary.md` and make the run exit non-zero.

## Layout

```
prepare-context.sh   stage sources into .ctx/ + preflight checks
Dockerfile           multi-stage: pacheck2 / mlton / clang builders -> slim runtime
run.sh               prepare + build + run
checkers.json        per-checker argv template and verdict rules
bench/run_bench.py   benchmark driver (stdlib only)
bench/report.py      CSV -> summary.md + plots (also usable standalone)
```

## Toolchain notes

All stages use `ubuntu:24.04`: MLton is not packaged in Debian, and sharing one
base keeps the MLton binary's glibc in step with the runtime's. That gives MLton
`20210117`, which is older than the `mlton` in `isabelle/flake.nix` — expect the
`pasteque-sml` numbers to differ slightly from a host build. `pacheck2` is built
with `./configure.sh` defaults (`-O3 -DNDEBUG`), the LLVM variants with the
checked-in `Makefile` defaults (`clang` for the IR, `cc -O2` for `parser.c`).

## Out of scope

Running Isabelle inside the image, the SML *non-shared* variant (its
`code/no_sharing/checker.ML` does not exist and can only be produced by an
Isabelle run), and memory limits.
