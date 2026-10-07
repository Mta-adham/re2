#!/usr/bin/env bash
# Run the RE2 regexp benchmark suite and write two flat JSON files at the
# repository root. Requires scripts/build.sh first.
#   artemis_results.json   the 5 headline scores and their std devs (what Artemis reads)
#   artemis_detailed.json  the scores plus every individual case
#
# Cases: every single-threaded RE2 benchmark (compile, parse/submatch, partial
# match) plus every search benchmark at a fixed 32 KiB input. 3 repetitions,
# medians reported. Override with BENCH_FILTER / BENCH_REPETITIONS / BENCH_MIN_TIME.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${ARTEMIS_BUILD_DIR:-build-artemis}"
FILTER="${BENCH_FILTER:-^[^/]+(/32768)?/threads:1\$}"
REPS="${BENCH_REPETITIONS:-3}"
MIN_TIME="${BENCH_MIN_TIME:-0.1s}"
RAW="$BUILD_DIR/benchmark_raw.json"

BIN="$BUILD_DIR/re2/regexp_benchmark"
[ -x "$BIN" ] || BIN="$BIN.exe"
[ -x "$BIN" ] || { echo "regexp_benchmark not found; run scripts/build.sh" >&2; exit 1; }

PY=python3
"$PY" -c "" >/dev/null 2>&1 || PY=python

# Never let a stale result survive a failed run.
rm -f artemis_results.json artemis_results.csv artemis_detailed.json "$RAW"

"$BIN" --benchmark_filter="$FILTER" \
  --benchmark_repetitions="$REPS" \
\
  --benchmark_min_time="$MIN_TIME" \
  --benchmark_display_aggregates_only=true \
  --benchmark_out="$RAW" --benchmark_out_format=json

# Flatten: one number per key, all times in ns, lower is better.
#   score               geometric mean time of all cases (headline metric)
#   score.<group>       geometric mean per group: search, submatch, compile, match
#   *.stddev            standard deviation of that score across the repetitions
#   time_ns.<case>      median time of one case            (detailed only)
#   noise.*, cv_pct.*   spread across repetitions in %      (detailed only)
"$PY" - "$RAW" artemis_results.json artemis_detailed.json <<'PY'
import json, math, os, re, statistics, sys
from collections import defaultdict

src, results_path, detailed_path = sys.argv[1:4]
UNIT = {"ns": 1.0, "us": 1e3, "ms": 1e6, "s": 1e9}

def clean_name(run_name):
    # Search_Easy0_CachedDFA/32768/threads:1 -> Search_Easy0_CachedDFA_32K
    parts = re.sub(r"/threads:\d+$", "", run_name).split("/")
    for n in map(int, parts[1:]):
        if n >= 1 << 20 and n % (1 << 20) == 0:
            parts[0] += f"_{n >> 20}M"
        elif n >= 1 << 10 and n % (1 << 10) == 0:
            parts[0] += f"_{n >> 10}K"
        else:
            parts[0] += f"_{n}"
    return parts[0]

def group(name):
    if name.startswith("Search"):
        return "search"
    if name.startswith("Parse_"):
        return "submatch"
    if name.startswith("BM_"):
        return "compile"
    return "match"

def geomean(values):
    values = [v for v in values if v > 0]
    return math.exp(sum(map(math.log, values)) / len(values)) if values else 0.0

times, cvs = {}, {}
reps = defaultdict(dict)  # repetition index -> {case: time_ns}
for b in json.load(open(src))["benchmarks"]:
    if b.get("error_occurred"):
        continue
    name = clean_name(b["run_name"])
    t = b["real_time"] * UNIT[b.get("time_unit", "ns")]
    if b.get("run_type") == "iteration":
        reps[b.get("repetition_index", 0)][name] = t
        times.setdefault(name, t)  # replaced by the median when there is one
    elif b.get("aggregate_name") == "median":
        times[name] = t
    elif b.get("aggregate_name") == "cv":
        cvs[name] = t * 100.0

if not times:
    sys.exit("benchmark.sh: no successful benchmark results found")

groups = defaultdict(list)
for name, t in times.items():
    groups[group(name)].append(t)

def stddev_of_score(pick):
    # Score each repetition on its own, then take the spread of those scores.
    scores = [geomean(t for n, t in rep.items() if pick(n)) for rep in reps.values()]
    return statistics.stdev(scores) if len(scores) > 1 else 0.0

summary = {"score": geomean(times.values()),
           "score.stddev": stddev_of_score(lambda n: True)}
for g in sorted(groups):
    summary[f"score.{g}"] = geomean(groups[g])
    summary[f"score.{g}.stddev"] = stddev_of_score(lambda n, g=g: group(n) == g)

detailed = dict(summary)
detailed["benchmark_count"] = len(times)
if cvs:
    detailed["noise.median_cv_pct"] = statistics.median(cvs.values())
    detailed["noise.max_cv_pct"] = max(cvs.values())
detailed.update({f"time_ns.{n}": times[n] for n in sorted(times)})
detailed.update({f"cv_pct.{n}": cvs[n] for n in sorted(cvs)})

def write(path, data):
    data = {k: round(float(v), 3) for k, v in data.items()}
    with open(path + ".tmp", "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(path + ".tmp", path)
    print(f"wrote {len(data)} metrics to {path}")

write(detailed_path, detailed)
write(results_path, summary)
print(f"score = {summary['score']:.1f} +- {summary['score.stddev']:.1f} ns "
      f"(geomean of {len(times)} cases, lower is better)")
PY
