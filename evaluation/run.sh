#!/usr/bin/env bash
# Stage sources, build the image, run the benchmark inside a container.
#
#   ./run.sh                      # 3 reps on evaluation/instances
#   ./run.sh --reps 5 --warmup
#   ./run.sh --data /path/to/benchmarks --timeout 300
#   ./run.sh --checkers pacheck2,pasteque-llvm
#
# Environment:
#   IMAGE=pac-eval:latest   image tag
#   CPUSET=2                pin the container to CPU 2 (quieter timings)
#   NO_BUILD=1              skip prepare + docker build, reuse the image
#   DOCKER=podman           container CLI
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-pac-eval:latest}"
DOCKER="${DOCKER:-docker}"

DATA="$EVAL_DIR/instances"
RESULTS="$EVAL_DIR/results"

# Pull --data out of the argument list: it names a host directory, and the
# container always sees the instances at /data.
bench_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --data) DATA="$(cd "$2" && pwd)"; shift 2;;
    --data=*) DATA="$(cd "${1#*=}" && pwd)"; shift;;
    *) bench_args+=("$1"); shift;;
  esac
done

if [ "${NO_BUILD:-}" != "1" ]; then
  "$EVAL_DIR/prepare-context.sh"
  "$DOCKER" build -f "$EVAL_DIR/Dockerfile" -t "$IMAGE" "$EVAL_DIR/.ctx"
fi

[ -d "$DATA" ] || { echo "no such data directory: $DATA" >&2; exit 1; }
mkdir -p "$RESULTS"

run_args=(--rm -v "$DATA:/data:ro" -v "$RESULTS:/results")
[ -n "${CPUSET:-}" ] && run_args+=(--cpuset-cpus "$CPUSET")
# Make results land as the invoking user. Under rootless Docker/Podman the
# container's root already maps to that user, and forcing --user would instead
# map to an unprivileged subuid that cannot write the bind mount.
if ! "$DOCKER" info -f '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless; then
  run_args+=(--user "$(id -u):$(id -g)")
fi

exec "$DOCKER" run "${run_args[@]}" "$IMAGE" "${bench_args[@]}"
