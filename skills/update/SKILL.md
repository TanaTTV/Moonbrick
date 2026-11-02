---
name: update
description: Update a moonbrick project's bundled code (MCPKit, Kit libraries, kit tests, check script) to the installed plugin version. Use when the user asks to update moonbrick in a project or a newer kit version is installed.
disable-model-invocation: true
---

# Update moonbrick in this project

1. Record `git status --short`. Preserve unrelated changes. Managed edits are backed up under `.moonbrick/backups/`; inspect them before replacing intentional customizations.
2. Compare versions: project `tools/.moonbrick-version` vs `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Read `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` entries in between and note breaking changes.
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-kit.sh" .` — updates managed helper/library/spec files, adds missing safe service boundaries to project JSON, and ignores `.moonbrick/`. Explicit mappings/settings/ignore choices and game files are preserved; previous changed files are backed up. Identical updates are no-ops.
4. `git diff --stat`, then `bash tools/check.sh`. If game code broke because a Kit API changed, fix the call sites (CHANGELOG says how).
5. Playtest: `K.test()` in the Server datamodel, plus each feature's debug hooks (studio skill recipe).
6. Commit only the reviewed upgrade changes as "Update moonbrick to <version>"; never stage unrelated work.
