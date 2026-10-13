---
name: update
description: Update a roblox-kit project's bundled code (MCPKit, Kit libraries, kit tests, check script) to the installed plugin version. Use when the user asks to update roblox-kit in a project or a newer kit version is installed.
disable-model-invocation: true
---

# Update roblox-kit in this project

The plugin root is two folders above this skill's base directory; call it `KIT`.

1. Confirm the working tree is clean (`git status --short`); if not, ask the user to commit or let you commit first, so the update is one reviewable diff.
2. Compare versions: project `tools/.roblox-kit-version` vs `KIT/.claude-plugin/plugin.json`. Read `KIT/CHANGELOG.md` entries in between and note breaking changes.
3. Run `bash "KIT/scripts/sync-kit.sh" .` — it only rewrites `tools/MCPKit.luau`, `tools/check.sh`, `src/kit/**` and `tests/kit/**`.
4. `git diff --stat`, then `bash tools/check.sh`. If game code broke because a Kit API changed, fix the call sites (CHANGELOG says how).
5. Playtest: `K.test()` in the Server datamodel, plus each feature's debug hooks (studio skill recipe).
6. Commit as "Update roblox-kit to <version>".
