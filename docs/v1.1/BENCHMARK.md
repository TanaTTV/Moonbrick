# V1.1 before/after evidence

> The three showcases, their stills (`docs/v1.1/evidence/`) and `VARIANTS.md` were removed later to keep the plugin lean; they remain in git history (commit 405f49d).

What was measured on this branch, and what wasn't. No paid model runs were made for V1.1; the last
provider-accounted benchmark is the V1.0 one in [docs/BENCHMARK.md](../BENCHMARK.md).

## Context an agent reads (bytes, `main` → branch)

| File | Loaded | main | V1.1 |
|---|---|---|---|
| Skill descriptions (all skills) | every session | 2,642 | 2,791 (+149) |
| `tools/KIT_API.md` (core card) | every coding session | 14,880 | 15,219 (+339) |
| `tools/KIT_CREATIVE.md` (creative card) | only for visual work | — | 22,078 |
| `skills/game-design/SKILL.md` | design and visual work | 4,022 | 5,836 |
| `skills/studio/SKILL.md` | Studio work | 6,963 | 8,052 |
| `template/CLAUDE.md` | every project session | 3,068 | 3,352 |

- Non-visual sessions pay about 0.8 KB more than V1.0 (+149 + 339 + 284 bytes).
- The creative card stands in for 95,354 bytes of Kit source (Fx, Motion, Pose, Audio, Tex, Geo,
  Scheduler): 4.3× smaller. V1.0's benchmark found that reading Kit source was what made sessions cost
  1.9× ([docs/BENCHMARK.md](../BENCHMARK.md)); splitting the cards keeps that out of non-visual work.
- Characters are not cost: cache reads dominated V1.0's bills. Only a provider-accounted run can show cost.

## Runtime (Studio 0.743, Windows desktop, 60 Hz cap)

| Measurement | Result |
|---|---|
| Celestial cast, High | avg 16.7 ms, p95 18.0, worst 20.0; peak +49 instances; cleanup to 0 (`Fx.live`, `Scheduler`, `Pose`) |
| Celestial cast, Low | avg 16.7 ms, p95 18.2, worst 19.4; peak +18 instances |
| Abyssal cast, High / Low | peak +51 / +38 instances; effect lasts 8.5 s, then cleans up to 0 |
| 8 overlapping casts, High | avg 16.7 ms, p95 18.1, worst 22.8; peak +347 instances, 8 live effects; back to 0 |
| Mythic Hatch grove (client) | 66 props / 12 distinct meshes built cold in 260 ms; cached rebuild 3 ms |
| Client mesh budget | 8 live growable EditableMeshes before baking; all 96 + 36 props dress after the fix |

Frame times sit at the 60 Hz cap, so they show "no dropped frames here", not headroom. No phone, tablet
or console was measured.

## Visual before/after (stills from Studio)

| Showcase | Before | After |
|---|---|---|
| Celestial Collapse | `evidence/celestial-collapse/01-before-gather.jpg`, `02-before-blast.jpg` | `03-celestial-rise.jpg`, `04-celestial-blast.jpg`, `05-abyssal-blast.jpg` |
| Mythic Hatch | `evidence/mythic-hatch/00-before-winding-fix.jpg` | `01-idle.jpg` … `05-common-reveal-card.jpg` |
| Neon Frontier | `evidence/neon-frontier/00-before-street.jpg` | `01-main-street.jpg`, `02-props.jpg`, `03-bounty-card.jpg` |

Each pair went through 3–4 rounds of "top three weaknesses → fix → recapture" until a round found
nothing important. These are stills and prove composition, colour and readability only.

## Proposed paid benchmark (not run, needs approval)

To test whether the brief and creative card change outcomes (not just bytes), the existing harness could
run one visual task, for example *"a themed reward popup with a hit effect for a cozy game"*:

- Plain Claude Code vs Moonbrick V1.1, interleaved, n = 3 each (6 runs), Sonnet, same prompt and tool policy.
- Measures: provider cost, turns, wall time, Skill calls (does `game-design` trigger?), whether
  `KIT_CREATIVE.md` is read instead of the source, and static checks (`UI.useTheme`, `Fx` palette use).
- **Expected cost: about $3–9** (V1.0 runs cost $0.15–0.26 on a smaller task; a visual task runs about
  2–4× longer). Visual quality would still need a human or Studio review; the harness is headless.
