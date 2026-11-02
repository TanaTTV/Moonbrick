# Studio tree-output benchmark

Raw results: [2026-10-13-tree.json](benchmarks/2026-10-13-tree.json).

On 2026-10-13, a temporary ServerStorage fixture contained one root, three child folders and 150 inert Parts (154 Instances). Compared `search_game_tree(path, max_depth=2, head_limit=200)` with a cached `MCPKit.tree(path, 2, nil, 200)` through `execute_luau`, alternating five samples on the same Studio Edit instance. Fixture and private helper cache were removed afterward. No existing place objects were changed.

| Metric | Standard MCP tree | Compact MCPKit tree |
|---|---:|---:|
| Text output characters, every sample | 22,883 | 2,480 |
| Median tool round-trip, measured by orchestrator clock | 34 ms | 81 ms |
| Calls per inspection | 1 | 1 |

Compact output was **89.2% smaller by character count**, but its median tool latency was **47 ms greater**. Standard output also carries full paths/relationships; compact output carries indentation/name/class. Use the detailed tool when those extra fields are necessary. No claim of equivalent schemas or faster network/tool execution follows from this experiment.

The private helper setup was 20,475 code characters and was excluded from warm-call timings; installed Moonbrick projects require their already-synced helper instead. The fixture is synthetic, one machine, five samples, and not a full game-development workload. Claude token counts, model reasoning time, API/subscription dollars and gameplay construction speed were **not measured**. Character savings are not exact token or cost savings.

Reproduce: `python scripts/benchmark.py .artifacts/benchmark`, run `prepare.luau` in a chosen Studio datamodel, alternate the two calls using `fixture.json`, record all samples and failures, then execute `cleanup.luau` in a `finally` step. Preserve startup/cache costs separately. Do not benchmark a user's active game hierarchy or stop their playtest to make comparisons.
