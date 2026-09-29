# Evaluation
Evaluate Pastèque with LLVM-backend against the original SML backend and also against the C++ based Pacheck checker.
We use the GNU `time` tool for measuring wall clock time.
Benchmarking is done through a individual scripts:
- `./collect-checkers.sh` - builds all three checkers and copies the executables into `./checkers`
- `./run-checkers.sh` - runs all checkers for a given benchmark "stem", where a stem is the filename part of a benchmark in `./instances` without the suffix `.{target,input,proof}`. The results are appended to `./results.csv`
- `./average-results.py` - averages the per-round measurements of a raw CSV per (benchmark, checker) pair and writes them to `./results/averages.csv`. Defaults to reading `./results/raw.csv`.
- `./render-table.py` - renders an averages CSV as a LaTeX table (`./results/table.tex`).
- `./render-plot.py` - plots an averages CSV as `./results/plot.pdf`.
- `./run-benchmarks.sh` - combines the scripts above to generate a large csv file for all benchmarks included in a given file (defaults to `./instances/benchmark-include`)
