# Benchmark summary

Hand-written summary of the latest benchmark result. The full generated report (setup, earlier batches, grader rules) is [BENCHMARK.md](BENCHMARK.md); `scripts/bench/report.py` regenerates that file, not this one.

## API card and recipes, same-batch B vs E (20261017T104744Z)

After the first E batch cost ~1.9× baseline, the stream logs showed why: E runs read ~35 KB of Kit source (PlayerData.luau alone is 25 KB), which then rode along as cache reads on every later turn. New projects now ship `tools/KIT_API.md` (a ~15 KB generated signature card) and checked copy-ready `tools/recipes/`, and the skills point there instead of the source. The prompt, grader, tool policy and model are unchanged.

Six accounted Sonnet runs in one batch, interleaved E1, B1, B2, E2, E3, B3 (so cache and time-of-day affect both sides alike); total captured cost `$1.34731559999999991` ([CSV](../scripts/bench/results/20261017T104744Z/summary.csv), [medians](../scripts/bench/results/20261017T104744Z/medians.json)).

| Condition | Runs | Median cost USD | Median output tokens | Median turns | Median wall s | All criteria passes |
| --- | --- | --- | --- | --- | --- | --- |
| B (no plugin) | 3 | 0.2197396 | 9587 | 22 | 76.1 | 3/3 |
| E (Moonbrick) | 3 | 0.2172396 | 6214 | 22 | 58.4 | 3/3 |

- Cost: E ≈ B (−$0.0025, about 1% lower), down from ≈1.9× in the earlier cross-batch comparison. Per-run E costs $0.208–0.240 versus B $0.202–0.260.
- Speed: E median wall time 58 s versus 76 s (about 23% faster), with about 35% fewer output tokens. Same median turn count.
- E still has more cache reads (median 287k vs 212k) from the skills and card, offset by writing less code.
- Actual use: every E run invoked `moonbrick:new` then `moonbrick:game-systems`, read `tools/KIT_API.md` and the Data/Pickups recipes, and read **no** Kit source files.
- Design (static scan of preserved sources): E 3/3 use session-locked `PlayerData` and validated `Net` remotes; B 3/3 wrote their own `SetAsync`/`UpdateAsync` DataStore code without session locking. The static grader does not score that difference.
- The B baseline in this batch (median $0.220, 22 turns) is higher than in `20261014T094922Z` ($0.156, 15 turns) with an identical prompt, which is why only the same-batch comparison is meaningful.

Limits as before: n=3 per condition, one small task, Sonnet only, headless/static grading, no Studio runtime test. This shows Moonbrick no longer costs more on this task; it does not show general savings.
