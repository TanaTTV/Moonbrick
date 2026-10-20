"""Synthesize original sound effects (no samples, no third-party audio) as 16-bit mono WAV files.

    python scripts/sfx.py list
    python scripts/sfx.py render <out-dir> [name ...]          # all sounds when no names are given
    python scripts/sfx.py preview <out-dir>                     # copy into Roblox Studio's local content folder

`preview` copies the files into Studio's own content folder so `rbxasset://sounds/moonbrick/<name>.wav`
plays in Studio on THIS computer without uploading anything; players hear nothing until you upload the
files yourself (Creator Hub → Audio) and use the returned rbxassetid. Standard library only.
"""
from __future__ import annotations

import argparse
import array
import glob
import math
import os
from pathlib import Path
import random
import shutil
import wave

RATE = 44100


def _env(t: float, attack: float, decay: float, length: float) -> float:
    if t < attack:
        return t / attack if attack > 0 else 1.0
    if t > length - decay:
        return max(0.0, (length - t) / decay) if decay > 0 else 0.0
    return 1.0


class Noise:
    """Deterministic filtered noise: white → one-pole low-pass with a moving cutoff."""

    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        self.low = 0.0
        self.band = 0.0

    def white(self) -> float:
        return self.rng.uniform(-1.0, 1.0)

    def lowpass(self, cutoff: float) -> float:
        a = 1.0 - math.exp(-2.0 * math.pi * max(cutoff, 20.0) / RATE)
        self.low += a * (self.white() - self.low)
        return self.low

    def bandpass(self, centre: float) -> float:
        # Difference of two low-passes approximates a band around `centre`.
        low = self.lowpass(centre * 1.4)
        a = 1.0 - math.exp(-2.0 * math.pi * max(centre * 0.6, 20.0) / RATE)
        self.band += a * (low - self.band)
        return low - self.band


def _render(length: float, fn) -> list[float]:
    n = int(length * RATE)
    return [fn(i / RATE) for i in range(n)]


def _normalise(samples: list[float], peak: float = 0.89) -> list[float]:
    top = max(1e-9, max(abs(s) for s in samples))
    return [s / top * peak for s in samples]


def charge(length=1.4):
    """Rising energy: a swept sine choir over brightening noise, ending in a shimmer."""
    nz = Noise(1)
    phase = [0.0, 0.0, 0.0]

    def f(t):
        p = t / length
        freq = 110 + 520 * p * p
        out = 0.0
        for k, mult in enumerate((1.0, 1.5, 2.01)):
            phase[k] += 2 * math.pi * freq * mult / RATE
            out += math.sin(phase[k]) * (0.5 / (k + 1))
        hiss = nz.bandpass(400 + 5000 * p) * 0.6 * p
        tremolo = 0.75 + 0.25 * math.sin(2 * math.pi * (6 + 18 * p) * t)
        return (out * tremolo + hiss) * _env(t, 0.05, 0.08, length) * (0.3 + 0.7 * p)

    return _render(length, f)


def hum(length=2.0):
    """A steady magical drone with a slow shimmer (loopable)."""
    phase = [0.0, 0.0]

    def f(t):
        phase[0] += 2 * math.pi * 92 / RATE
        phase[1] += 2 * math.pi * (184.6 + 2 * math.sin(2 * math.pi * 0.5 * t)) / RATE
        return (math.sin(phase[0]) * 0.6 + math.sin(phase[1]) * 0.3) * (0.8 + 0.2 * math.sin(2 * math.pi * 3 * t))

    return _render(length, f)


def whoosh(length=0.55):
    nz = Noise(2)

    def f(t):
        p = t / length
        centre = 300 + 2600 * math.sin(math.pi * p)
        return nz.bandpass(centre) * math.sin(math.pi * p) ** 1.5

    return _render(length, f)


def implode(length=0.45):
    """Air being sucked in: a reversed swell that cuts off sharply."""
    nz = Noise(3)
    phase = [0.0]

    def f(t):
        p = t / length
        phase[0] += 2 * math.pi * (60 + 340 * p) / RATE
        swell = p ** 2.5
        return (nz.bandpass(200 + 3800 * p) * 0.8 + math.sin(phase[0]) * 0.5) * swell * _env(t, 0.0, 0.015, length)

    return _render(length, f)


def boom(length=2.6):
    """A deep explosion: pitch-dropping thump, noisy crack and a long rumbling tail."""
    nz = Noise(4)
    rumble = Noise(5)
    phase = [0.0]

    def f(t):
        phase[0] += 2 * math.pi * (38 + 140 * math.exp(-t * 9)) / RATE
        thump = math.sin(phase[0]) * math.exp(-t * 2.2)
        crack = nz.lowpass(9000 * math.exp(-t * 6) + 200) * math.exp(-t * 7) * 1.4
        tail = rumble.lowpass(160) * 3.0 * math.exp(-t * 1.3)
        return (thump * 1.1 + crack + tail) * _env(t, 0.002, 0.3, length)

    return _render(length, f)


def chime(length=1.6, base=880.0, seed=6):
    """A bright FM bell (rewards, reveals)."""
    rng = random.Random(seed)
    detune = rng.uniform(0.997, 1.003)

    def f(t):
        mod = math.sin(2 * math.pi * base * 3.5 * t) * 2.2 * math.exp(-t * 3)
        tone = math.sin(2 * math.pi * base * detune * t + mod)
        return tone * math.exp(-t * 2.4) * _env(t, 0.002, 0.2, length)

    return _render(length, f)


def fanfare(length=2.2):
    """An ascending chime arpeggio with a sustained sparkle (hatch reveal)."""
    notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
    voices = [chime(1.5, n, 10 + i) for i, n in enumerate(notes)]
    total = int(length * RATE)
    out = [0.0] * total
    for i, voice in enumerate(voices):
        start = int(i * 0.11 * RATE)
        for j, s in enumerate(voice):
            if start + j < total:
                out[start + j] += s * (0.7 if i < 4 else 1.0)
    nz = Noise(7)
    for j in range(total):
        t = j / RATE
        out[j] += nz.bandpass(7000) * 0.25 * math.exp(-max(0.0, t - 0.5) * 2) * (1 if t > 0.45 else 0)
    return out


def crack(length=0.35, seed=8):
    """Brittle shell cracking: a cluster of short clicks with a woody resonance."""
    rng = random.Random(seed)
    clicks = sorted(rng.uniform(0, length * 0.7) for _ in range(9))
    nz = Noise(seed)

    def f(t):
        out = 0.0
        for c in clicks:
            d = t - c
            if 0 <= d < 0.03:
                out += math.sin(2 * math.pi * 1800 * d) * math.exp(-d * 180) + nz.white() * math.exp(-d * 400) * 0.5
        return out

    return _render(length, f)


def click(length=0.06):
    def f(t):
        return math.sin(2 * math.pi * 1400 * t) * math.exp(-t * 90)

    return _render(length, f)


def hover(length=0.05):
    def f(t):
        return math.sin(2 * math.pi * 2200 * t) * math.exp(-t * 120) * 0.6

    return _render(length, f)


def buzz(length=2.0):
    """A neon sign's electrical hum with flicker (loopable)."""
    nz = Noise(9)

    def f(t):
        mains = math.sin(2 * math.pi * 120 * t) * 0.5 + math.sin(2 * math.pi * 240 * t) * 0.25
        flicker = 0.85 + 0.15 * (1 if math.sin(2 * math.pi * 7.3 * t) > 0.92 else 0)
        return (mains + nz.bandpass(3000) * 0.15) * flicker

    return _render(length, f)


def wind(length=4.0):
    """Desert wind (loopable): slowly moving filtered noise."""
    nz = Noise(10)

    def f(t):
        centre = 500 + 350 * math.sin(2 * math.pi * 0.25 * t) + 150 * math.sin(2 * math.pi * 0.61 * t)
        return nz.bandpass(centre) * (0.7 + 0.3 * math.sin(2 * math.pi * 0.25 * t + 1))

    return _render(length, f)


SOUNDS = {
    "charge": charge,
    "hum": hum,
    "whoosh": whoosh,
    "implode": implode,
    "boom": boom,
    "chime": chime,
    "fanfare": fanfare,
    "crack": crack,
    "click": click,
    "hover": hover,
    "buzz": buzz,
    "wind": wind,
}


def write(path: Path, samples: list[float]):
    data = array.array("h", (int(max(-1.0, min(1.0, s)) * 32767) for s in _normalise(samples)))
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data.tobytes())


def render(out_dir: Path, names: list[str]) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for name in names or sorted(SOUNDS):
        if name not in SOUNDS:
            raise SystemExit(f"unknown sound {name!r}; try: {', '.join(sorted(SOUNDS))}")
        path = out_dir / f"{name}.wav"
        write(path, SOUNDS[name]())
        written.append(path)
        print(f"{path} ({path.stat().st_size // 1024} KB)")
    return written


def studio_sound_dirs() -> list[str]:
    dirs = []
    local = os.environ.get("LOCALAPPDATA")
    if local:
        dirs += sorted(glob.glob(os.path.join(local, "Roblox", "Versions", "*", "content", "sounds")))
    for mac in ("/Applications/RobloxStudio.app/Contents/Resources/content/sounds",
                os.path.expanduser("~/Applications/RobloxStudio.app/Contents/Resources/content/sounds")):
        if os.path.isdir(mac):
            dirs.append(mac)
    return dirs


def preview(out_dir: Path):
    files = sorted(out_dir.glob("*.wav"))
    if not files:
        raise SystemExit(f"no .wav files in {out_dir}; run render first")
    dirs = studio_sound_dirs()
    if not dirs:
        raise SystemExit("Roblox Studio's content/sounds folder was not found")
    for root in dirs:
        target = Path(root) / "moonbrick"
        target.mkdir(exist_ok=True)
        for f in files:
            shutil.copyfile(f, target / f.name)
    for f in files:
        print(f"{f.name} -> rbxasset://sounds/moonbrick/{f.name}")
    print("Local Studio preview only: players hear these after you upload them yourself.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    r = sub.add_parser("render")
    r.add_argument("out", type=Path)
    r.add_argument("names", nargs="*")
    p = sub.add_parser("preview")
    p.add_argument("out", type=Path)
    args = parser.parse_args(argv)
    if args.command == "list":
        print("\n".join(sorted(SOUNDS)))
    elif args.command == "render":
        render(args.out, args.names)
    else:
        preview(args.out)


if __name__ == "__main__":
    main()
