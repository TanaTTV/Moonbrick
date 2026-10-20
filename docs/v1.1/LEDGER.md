# V1.1 ledger: what was built, reused, verified and not verified

Branch `v1.1/creative-engine`, cut from `main` at `1d847a5` (v1.0.0). Not merged or released.
Studio checks ran in disposable places in Studio 0.743.0.7431133 on one Windows desktop.

**The nine V1.0 waivers are still open.** Touch layouts, a real gamepad, real-phone performance,
2-player streaming and the remaining live DataStore scenarios were not part of this work and are not
claimed ([WAIVERS.md](../../acceptance/v1-stable/WAIVERS.md)).

## Integrations and licences

| Source | Revision | Licence | Used as | Where |
|---|---|---|---|---|
| zriptic/roclicks-skills | `a8b66c1bb9ca` | MIT (+ MIT TabooHarmony/Roqer for `roblox-vfx`) | **Adapted:** Emit attribute convention and time-scale hitstop. **Idea only:** lathe/tube surfaces, shape spots, local content-folder previews | `Fx.emit`, `Geo`, `fxtex.py`/`sfx.py preview`; notices in `THIRD_PARTY_NOTICES.md` |
| anthropics/skills `frontend-design` | 2026-10-09 | Apache-2.0 | Idea only (AI-default calibration step) | `skills/game-design/SKILL.md` §3 |
| Willikk/Roblox | `c77902e8f59c` | none | Reference only; no code copied | — |
| Sleitnick/RbxUtil | `31f9120fca02` | MIT | Reference only; local code covers it | — |
| TeamSwordphin/ShapecastHitbox | `ac5c0e0a9fe7` | MIT | Reference only | — |
| yansha-os/motion-tools | `7ff9b0bbdddc` | none | **Rejected:** no licence, resident 6.5 MB MCP server | — |
| Mqxsyy/Lumina | `08969fa9d612` | MIT | **Rejected:** inactive since 2024-07; native emitters suffice | — |
| Creator Store audio | — | per-upload, unclear | **Rejected:** search results were rights-unclear rips; sounds are synthesised locally instead | `scripts/sfx.py` |

No new dependencies, package managers, MCP servers or background services. Everything is written locally
in strict Luau or stdlib Python.

## Requirements

Status: **V** verified (with evidence), **P** partly verified, **N** not verified.

| Area | What exists | Status | Evidence / gap |
|---|---|---|---|
| Creative brief | game-design skill: ≤ 3 questions or 3 directions, hybrid-genre ownership, reference rules, AI-default calibration, screenshot rubric | P | Written and wired into `new`/CLAUDE.md. Whether agents trigger and follow it needs the paid benchmark (not run). |
| Art direction record | `docs/design.md` section; `art.json` `style.genres/references/ui/motion`; `assets.py theme` | V | `tests/test_assets.py` (4 new tests); generated module passes strict check in a scaffold |
| Effect runtime (A) | `Fx` on a shared `Scheduler`, pooling, quality levels, markers, hitstop, time scale; `VFX` unchanged | V | Headless + Studio specs; cleanup to 0 after 1 and 8 overlapping casts; Low ≈ ⅓ of High's instances |
| Animation (B) | `Pose`: R15/R6 joint sets, rig checks, clips, markers, weights/fades, Animator track wrapper | P | R15 verified in play (Collapse). R6: classification tested headless only; no R6 rig played. Blending of two simultaneous clips not separately tested. |
| Audio (C) | `Audio` groups/cues/loops, `sfx.py` synthesis, no uploads | P | Sounds load and play in Studio. **Audio timing against markers was not measured**; you have to listen. |
| Procedural modelling (D) | `Geo` primitives, vertex colours, `register`/`dress`, fixed-size baking | V | Geo.spec winding/volume tests; 96 + 36 props dressed; cold build 260 ms for 66 props / 12 meshes, 3 ms cached. Blender path unchanged and not re-run. |
| UI styling (E) | `UI.useTheme`, `buttonFill`, `displayFont`, `panelStroke`, `panelTransparency`, `labelStroke`; V1 defaults | V | VFX_UI theme test; two themed cards in Studio. StyleSheets instantiate but live status unverified, so not used. |
| Celestial Collapse | ability, two styles, server damage | V | README; 71/71; damage numbers; evidence stills |
| Mythic Hatch | server-rolled hatch, procedural egg/creature/grove, reward card | V | README; 70/70; 3 sends → 1 hatch → 1 saved pet; evidence stills |
| Neon Frontier | cyberpunk-western street, props, neon signs, bounty card | V | README; 69/69; evidence stills |
| Variants | Celestial/Abyssal effects; Hatch/Frontier card composition | V | `docs/v1.1/VARIANTS.md` |
| Server authority | Net validation, cooldowns, server rolls/targets | V | Collapse cooldown refusal. Hatch: 3 rapid requests (one with an extra argument) produced exactly 1 server-rolled hatch; which guard refused which request was not isolated. Net's argument validation has its own headless specs. |
| Performance | frame time, instance peaks, cleanup | P | Desktop only, 60 Hz cap. **No phone measured.** |
| Visual review | top-3 loop to plateau, before/after stills | P | 3–4 rounds per showcase. **Stills only: motion, pacing and sound need a human review.** |
| Agent cost | card/skill sizes measured | P | `docs/v1.1/BENCHMARK.md`; paid A/B not run (needs your approval) |

## Kit bugs found and fixed on the way

- `Geo` surfaces (lathe, tube, torus, sphere, box) were inside-out; extrude was half wrong. Fixed;
  Studio specs check signed volume.
- Clients allow only 8 live growable EditableMeshes; `Geo` now bakes into fixed-size copies.
- Labels always had a 2 px outline; `UI.Theme.labelStroke` (default 2 keeps V1).
- `Fx` mesh spin only tumbled on X; optional `spinAxis` (default unchanged).

## Needs human artistic review

- Motion and timing of all three showcases (stills can't show them), including the Mothling's flap and
  the Collapse hitstop.
- The hoverbike (rough silhouette) and the Mothling's wings.
- Placeholder sounds from `sfx.py`: tone and mix.
- Whether the three looks match what you'd want to ship; record likes and dislikes in each design doc.
