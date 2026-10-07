# Build, Test & Benchmark Commands

All commands run from the repository root in a POSIX shell (Git Bash on Windows).

| Phase         | Command                  | Typical time (16-core Windows, MinGW GCC 16) |
|---------------|--------------------------|----------------------------------------------|
| **Compile**   | `./scripts/build.sh`     | ~60–70 s clean, a few seconds incremental     |
| **Test**      | `./scripts/test.sh`      | ~2 s                                          |
| **Benchmark** | `./scripts/benchmark.sh` | ~55 s                                         |

Run all three in order:

```bash
./scripts/build.sh && ./scripts/test.sh && ./scripts/benchmark.sh
```

## Prerequisites

- CMake ≥ 3.22 and a C++17 compiler (GCC/MinGW, Clang, or MSVC). Ninja is used if it's installed.
- Python 3 (to flatten the benchmark output).
- Internet access on the **first** build. `scripts/CMakeLists.txt` downloads the
  pinned Abseil `20250814.1`, GoogleTest `1.17.0` and Google Benchmark `1.9.4`
  (the versions in `MODULE.bazel`). You don't need to install them system-wide.
  To reuse the downloads across clean checkouts, set `ARTEMIS_DEPS_DIR=/some/cache/dir`.

## Compile

```bash
./scripts/build.sh
```

Configures `scripts/` (a wrapper that fetches dependencies and then calls
`add_subdirectory` on the RE2 root) into `build-artemis/` as a Release build, then
builds the `re2` library, all test binaries and `regexp_benchmark`. On MinGW the
binaries are linked statically. Otherwise a mismatched `libstdc++-6.dll` on PATH
(for example the one in Git's `/mingw64/bin`) causes a blocking Windows error dialog.

## Test

```bash
./scripts/test.sh
```

Runs the 14 GoogleTest suites through `ctest`. Like upstream CI, it skips the slow
`dfa|exhaustive|random` suites. Exits non-zero if any test fails. To check this, we
broke case folding in `re2/parse.cc` and 5 suites failed.

## Benchmark

```bash
./scripts/benchmark.sh
```

- Runs `regexp_benchmark` on **108 single-threaded cases**: every RE2
  compile/parse/match benchmark, plus every search benchmark at a fixed **32 KiB** input.
- Runs **3 repetitions** of each case and reports the median.
- Deletes any old `artemis_results.json`, writes the raw Google Benchmark JSON to
  `build-artemis/benchmark_raw.json`, and turns it into two flat files at the repo
  root (a short Python step inside `benchmark.sh`):
  - **`artemis_results.json`:** the 5 headline scores and their standard deviations. Artemis reads this file.
  - **`artemis_detailed.json`:** the same scores plus every individual case.

Optional overrides: `BENCH_FILTER` (regex), `BENCH_REPETITIONS`, `BENCH_MIN_TIME`
(for example `0.5s`).

## How to read the results

Both files are flat lists of `name: number` pairs.
**All times are in nanoseconds (ns), and lower is better.**

### `artemis_results.json`: the summary

```json
{
  "score": 2399.876,
  "score.stddev": 10.414,
  "score.compile": 1175.669,
  "score.compile.stddev": 2.455,
  "score.match": 118.462,
  "score.match.stddev": 3.703,
  "score.search": 8458.87,
  "score.search.stddev": 41.18,
  "score.submatch": 735.043,
  "score.submatch.stddev": 9.137
}
```

Read each pair as "value ± standard deviation". For example, the first two lines say
**score = 2400 ± 10 ns**.

| Parameter | What it measures | Cases in it |
|---|---|---|
| **`score`** | **The one number to look at.** Average time of all 108 cases. | 108 |
| `score.search` | Finding a regex in a 32 KiB block of text, the core matching engine | 56 |
| `score.submatch` | Matching a short string and pulling out captured groups, such as the parts of `650-253-0001` | 37 |
| `score.compile` | Turning a regex string into a ready-to-run program: parse, simplify, compile | 8 |
| `score.match` | Everyday `RE2::PartialMatch` and `FindAndConsume` calls on short strings | 7 |

"Average" is the geometric mean, so a 20 ns case and a 20,000 ns case count
equally: a 10% speedup moves the average by the same amount, whichever case it is in.

| Parameter | Meaning |
|---|---|
| `<score>.stddev` | Standard deviation of that score, in ns. Each of the 3 repetitions is scored on its own, and this is the spread of those 3 scores. It shows how steady the number was during this run. |

The standard deviation only covers the repetitions within one run. It doesn't
include slower changes in the machine's speed between runs, which can be much
larger. For example, two runs a few minutes apart gave 2400 ± 10 and 2928 ± 14.

### `artemis_detailed.json`: every case

This file starts with the same scores and standard deviations, then adds:

| Parameter | Meaning |
|---|---|
| `benchmark_count` | Number of cases measured (always 108) |
| `time_ns.<case>` | Median time of one case, in ns. Lower is better. |
| `cv_pct.<case>` | How much that case varied across its 3 repetitions, in % |
| `noise.median_cv_pct`, `noise.max_cv_pct` | The typical and the largest `cv_pct` across all cases |

**Reading a case name.** For example, `time_ns.Search_Easy0_CachedDFA_32K` is made of:

| Part | Meaning |
|---|---|
| `Search_` | Group. `Search_*` and `SearchPhone_*` count towards `score.search`, `Parse_*` towards `score.submatch`, `BM_*` towards `score.compile`, and everything else towards `score.match`. |
| `Easy0` | What is being matched (see the table below) |
| `Cached` | The regex is compiled once, outside the timed loop, so only matching is timed. Without `Cached`, each iteration also compiles the regex. |
| `DFA` | Which RE2 engine runs. `RE2` is the public API, which picks an engine itself. `DFA`, `NFA`, `OnePass`, `BitState` and `Backtrack` force one internal engine. |
| `_32K` | Size of the input text: 32 KiB |

What is being matched:

| Name | Pattern or input |
|---|---|
| `Easy0`, `Easy1`, `Easy2` | Literal text that never matches: `ABCD…XYZ$`, the same with `[AB]`-style classes, and case-insensitive |
| `Medium` | `[XYZ]ABCD…XYZ$`, a character class in front |
| `Hard` | `[ -~]*ABCD…XYZ$`, a leading `.*`-like loop |
| `Fanout` | A large Unicode pattern that creates many DFA states |
| `Parens` | Many capture groups: `([ -~])*(A)(B)…` |
| `BigFixed` | A long literal string |
| `Success`, `Success1` | Patterns that do match the whole text: `.*$` and `.*\C$` |
| `AltMatch` | `\C*`, which matches anything |
| `Digits`, `DigitDs` | Phone number `650-253-0001` split into 3 groups, using `[0-9]+` or `\d+` |
| `Split`, `SplitHard`, `SplitBig1/2` | `[0-9]+-(.*)` style patterns that split a string around a separator |
| `BM_Regexp_Parse`, `_Simplify`, `_Compile`, … | Each step of turning a regex string into a program |
| `EmptyPartialMatch`, `SimplePartialMatch`, `HTTPPartialMatch`, `DotMatch`, `ASCIIMatch` | `RE2::PartialMatch` with an empty pattern, `abcdefg`, an HTTP request line, `(.+)` and `([ -~]+)` |

### Did the optimisation work?

1. Run `./scripts/benchmark.sh` on the original code and keep a copy of `artemis_results.json`.
2. Make the change, then run `./scripts/build.sh && ./scripts/test.sh && ./scripts/benchmark.sh`.
3. Compare `score`:
   - **`score` went down:** the code is faster.
   - **`score` went up:** the code is slower.
4. Look at the `score.*` groups to see which kind of work changed. Then open
   `artemis_detailed.json` and look at the `time_ns.*` values to find the specific cases.

Run both versions in the same session, because the machine's speed changes over time.

### Analysing in pandas

```python
import json, pandas as pd
before = pd.Series(json.load(open("before_detailed.json")))
after  = pd.Series(json.load(open("artemis_detailed.json")))
change = ((after - before) / before * 100).round(1)   # % change, negative = faster

change.filter(regex=r"^score")                         # the 5 scores
change.filter(like="time_ns.").sort_values()           # every case, biggest speedups first
```

## Artemis configuration

| Field | Value |
|---|---|
| compile | `./scripts/build.sh` |
| test | `./scripts/test.sh` |
| benchmark | `./scripts/benchmark.sh` |
| ranking metric | `score` (minimise) |
