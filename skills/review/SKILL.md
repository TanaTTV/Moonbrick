---
name: review
description: Full quality and design review of a Roblox game or feature — code health (types, lint, tests), security (remotes, data), performance, platform support (mobile/console), and a screenshot-based visual/UX critique — ending in a prioritized fix list. Use when the user asks to review, polish, or improve their game.
argument-hint: "[feature or area, default: whole game]"
---

# Review

Gather evidence first (cheap, parallel where possible), then judge. Scope: the argument, or the whole game.

**Evidence**
1. `bash tools/check.sh` — count problems by kind.
2. Edit datamodel: `K.audit()` and `K.perf()` (one call).
3. Playtest (studio recipe): `K.test()`, then drive the main features via debug hooks; collect `K.logs()`.
4. Security read-through: every `Net.on`/`Net.handle`/`OnServerEvent` — are arguments validated *and* game rules checked on the server (ownership, distance from a server-trusted position — a raw client `HumanoidRootPart` can be teleported — cooldowns, prices from server tables)? Any data saved outside `PlayerData`?
5. Visuals: 2–4 screenshots of the key moments (spawn view, main UI, a big effect at its peak) — `screen_capture` with a camera position, or during the playtest.
6. Read `docs/design.md` if it exists.

**Judge** with the game-design skill: game feel, first-time experience, platforms, visual review checklist, design-doc consistency.

**Report** as one prioritized list (most player-impacting first), each item: what's wrong → evidence → concrete fix → effort (S/M/L). Group into *Fix now* (bugs, exploits, data risk, broken on a platform), *Polish* (feel, visuals, clarity), *Later*. Offer to fix the *Fix now* items, then do them one at a time with check + playtest.
