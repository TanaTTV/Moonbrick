---
name: game-design
description: Roblox game design guidance — design docs, core loops, game feel ("juice"), first-time player experience, mobile/console/PC support, UI/visual review with screenshots, and fair monetization. Use when planning a game or feature, when the user asks to make something feel better, look better, or be more fun, and before calling a player-facing feature done.
---

# Game design

## 1. Start from a design doc
If `docs/design.md` doesn't exist, offer to write it with the user using `design-doc-template.md` (next to this file) — ask about audience, fantasy, core loop and mood; don't invent their game. Keep it to one page. Before building any feature, check it serves the core loop and the mood; if not, say so.

## 2. Game feel checklist (every player-facing action)
Each meaningful action gets **anticipation → action → impact → follow-through**:
- **Anticipation:** wind-up, camera push-in, sound/visual charge (e.g. a dash crouches and glows for 0.2 s before launching).
- **Impact:** the peak moment stacks 3+ channels at once: visual (`VFX.impact`/`burst`), screen (`VFX.shake`/`flash`/`fovPunch`), UI (`VFX.title`, number pop), sound.
- **Follow-through:** lingering aura/particles, camera settle, a readable new state.
- **Escalation:** repeated actions grow (bigger flips, combo counters, rising pitch).
- **Feedback for everything:** hover/press on UI, a pop on every number change, something visible when an action is refused ("Need 50 coins").
- Small things should feel snappy (< 0.15 s response); big moments may take 2–8 s, but **must be skippable or worth it on repeat**.
- Sounds: you can't hear them, so ask the user to pick/approve audio; leave a clearly named `Sound` hook in code.

## 3. First-time experience (players decide in < 60 s)
- Within 10 s of spawning: the player sees the goal and the first interactable (glow, arrow, prompt).
- Teach by doing, not by text walls; one instruction at a time.
- First reward in under 30 s; the first big "wow" moment in the first few minutes.
- Nothing blocks movement on spawn (no modal menus).

## 4. Platforms (most Roblox players are on phones)
- **Mobile:** buttons ≥ 48 px (UI kit enforces it), nothing important in the top-left/top-right corners (Roblox buttons), thumb-reachable bottom-right actions, `TextScaled` or tested sizes on small screens.
- **Console:** every action reachable by gamepad (`ProximityPrompt`, `GuiService.SelectedObject` for menus); ClickDetectors don't work.
- **PC:** keyboard shortcuts for frequent actions.
- **Performance:** keep `K.perf()` part counts sensible, avoid per-frame server loops, anchor static parts, `StreamingEnabled` on.

## 5. Visual and UI review (use screenshots here)
Numbers prove logic; only images prove looks. For a visual feature, capture 1–3 screenshots at key moments (`screen_capture`, or during a playtest at the peak of the effect) and critique against:
- **Readability:** can a new player tell what's interactive and what just happened?
- **Hierarchy:** one focal point per moment; UI doesn't cover the action.
- **Consistency:** colours/fonts from `UI.Theme`; effects in the game's palette (design doc).
- **Contrast:** text readable on bright and dark backgrounds (UI kit adds strokes).
- **Clutter:** remove anything that doesn't serve the moment.
Report findings as a short prioritized list with concrete fixes, then fix the top ones.

## 6. Retention and monetization (fair and policy-safe)
- Loops that bring players back: progression (levels, unlocks), collection, daily goals, social (play with friends, show off cosmetics).
- Monetize convenience and cosmetics, never power that ruins fairness for others.
- Paid random items must show odds before purchase (Roblox policy); no misleading or pressuring purchase prompts; experiences may be played by children — keep it honest.

## 7. When the user gives feedback
If they say something is great or off, record **why** in `docs/design.md` (a "What works" / "Avoid" list) so future features match their taste.
