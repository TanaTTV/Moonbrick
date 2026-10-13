# Contributing to Moonbrick

Thanks for helping make AI-built Roblox games faster and better looking.

## Ways to help
- **Report a bug** or a Roblox gotcha (use the issue templates).
- **Add a gotcha** to `skills/studio/SKILL.md` when something cost you real debugging time: what broke, why, and the fix.
- **Improve a library** in `luau/lib/` (with tests in `luau/tests/`).
- **Test on macOS**: the scripts are written for it, but haven't had a full run yet.

## Developing
1. Clone into `~/.claude/skills/moonbrick`; Claude Code loads it as `moonbrick@skills-dir` next session.
2. Create a sandbox game: `bash scripts/new-project.sh ~/RobloxProjects/sandbox sandbox`.
3. After changing `luau/`, copy it into the sandbox: `bash scripts/sync-kit.sh ~/RobloxProjects/sandbox`.
4. Check: `bash tools/check.sh` in the sandbox (strict types + lint) must print `OK`.
5. Playtest: `K.test()` in the Server datamodel must pass, and features you touched must work via their debug hooks.
6. `claude plugin validate --strict .` must pass.

## Style
- Luau: `--!strict` in libraries, tabs, StyLua formatting, no silent early returns.
- Skills: short, imperative and specific. Every line should change what Claude does.
- Keep `CHANGELOG.md` updated in the same PR.
