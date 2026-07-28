# Build context is evaluation/.ctx, produced by prepare-context.sh.
#
# No Isabelle here: the image compiles code that Isabelle has already exported
# (checker.ML for the MLton backend, *.ll for the LLVM backend).
#
# Ubuntu rather than Debian because MLton is not packaged in Debian; all stages
# share the base so the MLton binary's glibc matches the runtime's.

# --- pacheck2: C++20 + GMP -------------------------------------------------
FROM ubuntu:24.04 AS builder-pacheck
RUN apt-get update && apt-get install -y --no-install-recommends \
        g++ make libgmp-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pacheck2/ ./
# configure.sh probes for getrusage/getc_unlocked, creates build/ and writes the
# makefile; it must run from the source directory.
RUN ./configure.sh && make && mkdir -p /out && cp pacheck /out/

# --- pasteque, Imperative-HOL / MLton backend (shared variables) ------------
FROM ubuntu:24.04 AS builder-sml
RUN apt-get update && apt-get install -y --no-install-recommends \
        mlton \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY sml/ ./
# Same flags as isabelle/Makefile:build_pasteque_sml.
RUN mkdir -p /out && mlton \
        -output /out/pasteque-sml \
        -const 'MLton.safe false' \
        -verbose 1 \
        -default-type int64 \
        -codegen native \
        -inline 700 \
        -cc-opt -O3 \
        pasteque.mlb

# --- pasteque, Isabelle-LLVM backend (both variants) ------------------------
FROM ubuntu:24.04 AS builder-llvm
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang make \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY llvm/ ./
# The exported IR needs no external library: parser.c defines the only two
# symbols it declares (isabelle_llvm_calloc / isabelle_llvm_free).
RUN make pasteque pasteque_shared && mkdir -p /out && cp pasteque pasteque_shared /out/

# --- runtime ---------------------------------------------------------------
FROM ubuntu:24.04 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgmp10 python3 python3-matplotlib \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder-pacheck /out/pacheck            /opt/checkers/bin/
COPY --from=builder-sml     /out/pasteque-sml       /opt/checkers/bin/
COPY --from=builder-llvm    /out/pasteque           /opt/checkers/bin/
COPY --from=builder-llvm    /out/pasteque_shared    /opt/checkers/bin/

COPY bench/ /opt/bench/
COPY checkers.json build-info.json /opt/bench/

ENV PYTHONDONTWRITEBYTECODE=1
WORKDIR /results
ENTRYPOINT ["python3", "/opt/bench/run_bench.py"]
CMD []
