"""Flag hardcoded colours and fonts in game code that bypass ArtStyle or UI.Theme.

    python scripts/stylecheck.py [project-dir]

Reads src/ except src/kit and theme or palette modules. It looks only at GUI properties, UI and Fx
arguments and fonts, so a Part's colour or a team colour stays out of it. Pure black and white are
left alone (they mean "no tint"). Add `-- style-ok` to a line to accept it.

Exit 0 when clean, 1 with findings, 2 on bad usage.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

LIMIT = 40
SKIPPED_NAMES = re.compile(r"(theme|palette|artstyle|style|colors?|colours?|fonts?)\b", re.I)
COLOR = r"Color3\.(?:new|fromRGB|fromHex|fromHSV)\s*\([^)\n]*\)"
GUI_COLOR = re.compile(r"\b(BackgroundColor3|TextColor3|ImageColor3|BorderColor3|PlaceholderColor3|TextStrokeColor3|ScrollBarImageColor3)\s*=\s*(" + COLOR + ")")
ARGUMENT_COLOR = re.compile(r"\b(color|textColor|fill|stroke)\s*=\s*(" + COLOR + ")")
FONT = re.compile(r"\b(?:Font\s*=\s*Enum\.Font\.\w+|FontFace\s*=\s*\S+|Font\.(?:new|fromEnum|fromName|fromId)\s*\()")
THEMED_CALL = re.compile(r"\b(?:UI|Fx)\.\w+\s*\(")
NEUTRAL = re.compile(r"^Color3\.(?:new\(\s*\)|new\(\s*([01])\s*,\s*\1\s*,\s*\1\s*\)|fromRGB\(\s*(0|255)\s*,\s*\2\s*,\s*\2\s*\)|fromHex\(\s*[\"']#?(?:0{6}|[fF]{6})[\"']\s*\))$")


def code_only(line: str) -> str:
    """The line without its comment or string contents, keeping only fromHex's argument."""
    out, quote, index, keep = [], "", 0, False
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 1
            elif char == quote:
                quote = ""
                out.append(char)
            elif keep:
                out.append(char)
        elif char in "\"'`":
            quote, keep = char, "".join(out).endswith("fromHex(")
            out.append(char)
        elif line.startswith("--", index):
            break
        else:
            out.append(char)
        index += 1
    return "".join(out)


def in_themed_call(lines: list[str], index: int) -> bool:
    """Whether an open UI.x( or Fx.x( call surrounds this line, reading back to where it started."""
    depth = 0
    for number in range(index, max(-1, index - 40), -1):
        text = lines[number]
        depth += text.count(")") - text.count("(") if number != index else 0
        depth += text.count("}") - text.count("{") if number != index else 0
        if depth < 0 and THEMED_CALL.search(text):
            return True
    return bool(THEMED_CALL.search(lines[index]))


def scan_file(path: Path, relative: str) -> list[str]:
    lines = [code_only(line) for line in path.read_text(encoding="utf-8", errors="replace").splitlines()]
    raw = path.read_text(encoding="utf-8", errors="replace").splitlines()
    findings = []
    for index, line in enumerate(lines):
        if "style-ok" in raw[index]:
            continue
        for rule in (GUI_COLOR, ARGUMENT_COLOR):
            for match in rule.finditer(line):
                if NEUTRAL.match(match.group(2).strip()):
                    continue
                if rule is ARGUMENT_COLOR and not in_themed_call(lines, index):
                    continue
                findings.append(f"{relative}:{index + 1} {match.group(1)} = {match.group(2)}: use ArtStyle.palette or UI.Theme")
        match = FONT.search(line)
        if match:
            findings.append(f"{relative}:{index + 1} {match.group(0).rstrip('( ')}: use UI.Theme.font or displayFont")
    return findings


def scan(project: Path) -> list[str]:
    source = project / "src"
    findings = []
    for path in sorted(source.rglob("*.luau")) + sorted(source.rglob("*.lua")):
        relative = path.relative_to(project).as_posix()
        if relative.startswith("src/kit/") or SKIPPED_NAMES.search(path.stem.split(".")[0]) or ".spec" in path.name:
            continue
        findings.extend(scan_file(path, relative))
    return findings


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("project", nargs="?", type=Path, default=Path("."))
    args = parser.parse_args(argv)
    if not (args.project / "src").is_dir():
        parser.error(f"no src/ folder in {args.project}")
    findings = scan(args.project)
    for line in findings[:LIMIT]:
        print(line)
    if len(findings) > LIMIT:
        print(f"... {len(findings) - LIMIT} more")
    if not findings:
        print("OK")
    return 1 if findings else 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
