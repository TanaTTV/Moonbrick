---
name: playtest
description: Verify a Roblox feature works in a real playtest with the fewest MCP calls — unit tests, debug-hook driven actions, recorded UI/camera/effects on the client, and warning/error logs. Use after building or changing a feature, or when the user asks to test something in Studio.
argument-hint: "[feature or what to verify]"
---

# Playtest a feature

Follow the studio skill's playtest recipe. Plan before calling anything:

1. **What must be true?** Write 3–6 concrete checks for the feature (state after each action, UI visibility at each step, values like scale/speed/currency, cleanup after it ends, no warnings). Include the UI the feature shows or hides — hooks skip the UI's own input, so stale UI only shows up if you record it.
2. **Find the driver:** the feature's debug hooks (`grep -rn "DebugHooks.register" src`). If the feature has none, add them first (short status-string actions like `start`, `state`, `reset`) — then `bash tools/check.sh`.
3. **Run** (~5 calls): start play → Client: `K.mark()` + `K.record` for UI/camera/effects → Server: `K.mark()`, `K.test()` if logic changed, hooks + waits + assertions, `K.logs()` → Client: `K.results` + `K.logs()` → stop play.
   - Wait for the character with `while not player.Character do task.wait(0.1) end`, never a bare `CharacterAdded:Wait()`.
   - Keep each `execute_luau` under ~20 s.
4. **Report** each check as pass/fail with the measured value, plus the logs. If something fails, fix it in the files, `bash tools/check.sh`, and rerun only what's needed.
5. For **look and feel**, numbers aren't enough: take 1–2 screenshots at the peak moment and review them with the game-design skill.
