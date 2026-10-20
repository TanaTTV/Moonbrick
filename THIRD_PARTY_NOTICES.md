# Third-party notices

Moonbrick's own code is MIT licensed (see `LICENSE`). Parts of it are adapted from the following MIT-licensed
work; the original notices are reproduced below as their licences require.

| Moonbrick file | Adapted from | Revision | What was adapted |
|---|---|---|---|
| `luau/lib/shared/Fx.luau` (`Fx.emit`, editor-attribute playback) | RoClicks `roblox-vfx/templates/Emit.luau`, itself adapted from Roqer's `roblox-animation-vfx` `emit.lua` | zriptic/roclicks-skills `a8b66c1bb9ca` | The attribute convention (EmitDelay/EmitCount/EmitDuration, Start/End mesh tweens, EffectDuration) and time-scale hitstop. Rewritten for strict Luau, the shared scheduler, pooling and quality levels. |
| `luau/lib/shared/Geo.luau` | RoClicks `meshlab/Shapes.luau` | zriptic/roclicks-skills `a8b66c1bb9ca` | The lathe/tube/grid surface approach and the "shape spot" idea behind `Geo.dress`. Written fresh; no code copied. |
| `scripts/fxtex.py`, `scripts/sfx.py` (`preview`) | RoClicks `roblox-vfx/scripts/vfxtex.py` | zriptic/roclicks-skills `a8b66c1bb9ca` | The idea of copying generated files into Studio's local content folder for upload-free previews. Written fresh. |

Techniques also studied without copying code (no licence, so reference only): Willikk/Roblox `c77902e8f59c`
(pooling, hitstop, easing, camera shake, texture animation, R6 procedural layers).

Method only, no text reused: the "calibrate away from AI defaults" step in `skills/game-design/SKILL.md`
follows the approach of Anthropic's `frontend-design` skill (anthropics/skills, Apache-2.0), rewritten for
Roblox games.

---

## RoClicks (zriptic/roclicks-skills)

MIT License

Copyright (c) 2026 RoClicks (roclicks.gg)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## Roqer skills (TabooHarmony), via RoClicks roblox-vfx

MIT License

Copyright (c) 2026 TabooHarmony

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
