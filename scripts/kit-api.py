"""Generate the compact Kit API card (luau/API.md) from the Kit sources.

Projects get a copy at tools/KIT_API.md so agents can use exact signatures without
loading ~65 KB of library source into context. `--check` fails when the card is stale.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "luau/API.md"
# (file, where it lives in a project, how to require it)
MODULES = [
    ("luau/lib/shared/Net.luau", "both", 'require(ReplicatedStorage.Kit.Net)'),
    ("luau/lib/shared/VFX.luau", "both (screen effects: client)", 'require(ReplicatedStorage.Kit.VFX)'),
    ("luau/lib/shared/UI.luau", "client", 'require(ReplicatedStorage.Kit.UI)'),
    ("luau/lib/server/PlayerData.luau", "server", 'require(ServerScriptService.Kit.PlayerData)'),
    ("luau/lib/server/Cooldown.luau", "server", 'require(ServerScriptService.Kit.Cooldown)'),
    ("luau/lib/server/Round.luau", "server", 'require(ServerScriptService.Kit.Round)'),
    ("luau/lib/server/Economy.luau", "server", 'require(ServerScriptService.Kit.Economy)'),
    ("template/src/kit/server/DebugHooks.luau", "server (Studio only)", 'require(ServerScriptService.Kit.DebugHooks)'),
]
# Classes whose methods are public even though they are not the module table.
EXTRA_OWNERS = {"PlayerData": ("Session",)}
FUNCTION = re.compile(r"^function (\w+)[.:](\w+)(\(.*)$")
ASSIGN = re.compile(r"^(\w+)\.(\w+) = (.+)$")
LOCAL_FUNCTION = re.compile(r"^local function (\w+)(<[^>]*>)?(\(.*)$")


def comment_text(line: str) -> str:
    return line.strip()[2:].strip()


def header(lines: list[str]) -> list[str]:
    out = []
    for line in lines:
        if line.startswith("--!"):
            continue
        if not line.startswith("--"):
            break
        out.append(comment_text(line))
    return out


def doc_above(lines: list[str], index: int, limit: int = 3) -> list[str]:
    docs = []
    i = index - 1
    while i >= 0 and lines[i].startswith("--") and not lines[i].startswith("--!"):
        docs.insert(0, comment_text(lines[i]))
        i -= 1
    # The module header is not documentation for the first function.
    if i < 0:
        return []
    return docs[-limit:]


def block(lines: list[str], start: int) -> list[str]:
    """Return a declaration starting at `start`, through its balanced brackets."""
    depth, out = 0, []
    for line in lines[start:]:
        out.append(line.rstrip())
        depth += line.count("{") + line.count("(") - line.count("}") - line.count(")")
        if depth <= 0:
            break
    return out


def signature(lines: list[str], index: int, start: str) -> str:
    """Join a signature that spans lines until its parentheses balance."""
    sig, i = start, index
    while sig.count("(") > sig.count(")") and i + 1 < len(lines):
        i += 1
        sig += " " + lines[i].strip()
    return re.sub(r"\(\s+", "(", re.sub(r",?\s+\)", ")", sig))


def card_for(rel: str, side: str, require: str) -> list[str]:
    lines = (ROOT / rel).read_text(encoding="utf-8").splitlines()
    name = Path(rel).stem
    owners = (name,) + EXTRA_OWNERS.get(name, ())
    locals_ = {}
    for i, line in enumerate(lines):
        m = LOCAL_FUNCTION.match(line)
        if m:
            locals_[m.group(1)] = (m.group(2) or "") + signature(lines, i, m.group(3))
    out = [f"## {name}", f"`local {name} = {require}` — {side}", ""]
    out += [f"> {text}" if text else ">" for text in header(lines)]
    types, api = [], []
    for i, line in enumerate(lines):
        if line.startswith("export type "):
            decl = block(lines, i)
            if "setmetatable(" in decl[0]:
                types.append(decl[0].split("=")[0].strip() + " = <object; methods listed below>")
            else:
                types.extend(decl)
        match = FUNCTION.match(line)
        if match and match.group(1) in owners:
            owner, method, sig = match.groups()
            api.append((f"{owner}.{method}{signature(lines, i, sig)}", doc_above(lines, i)))
            continue
        match = ASSIGN.match(line)
        if match and match.group(1) in owners and not match.group(2).startswith("__"):
            owner, field, value = match.groups()
            value = value.strip()
            if value in locals_:
                api.append((f"{owner}.{field}{locals_[value]}", doc_above(lines, i)))
            elif value.endswith(".Event"):
                api.append((f"{owner}.{field}: RBXScriptSignal", doc_above(lines, i)))
            elif value.endswith("{"):
                keys = []
                for inner in block(lines, i)[1:-1]:
                    key = re.match(r"\s*(\w+)\s*=", inner)
                    if key:
                        keys.append(key.group(1))
                api.append((f"{owner}.{field} = {{ {', '.join(keys)} }}", doc_above(lines, i)))
            else:
                api.append((f"{owner}.{field} = {value}", doc_above(lines, i)))
    if types:
        out += ["", "```lua", *types, "```"]
    out += [""]
    for sig, docs in api:
        out.append(f"- `{sig}`")
        out += [f"  {text}" for text in docs if text]
    out.append("")
    return out


def render() -> str:
    out = [
        "# Moonbrick Kit API",
        "",
        "Generated from the Kit sources by `scripts/kit-api.py`; do not edit by hand.",
        "Use this card for exact signatures. Open the Kit source only when the card is not enough.",
        "`ReplicatedStorage`/`ServerScriptService` mean `game:GetService(...)`; on the client use `:WaitForChild(\"Kit\")`.",
        "`Mod.fn(self: Obj, ...)` is a method: call it as `obj:fn(...)` on the object returned by `Mod.new`.",
        "",
    ]
    for rel, side, require in MODULES:
        out += card_for(rel, side, require)
    return "\n".join(out).rstrip() + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if luau/API.md is out of date")
    args = parser.parse_args(argv)
    text = render()
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current.replace("\r\n", "\n") != text:
            print("luau/API.md is out of date; run python scripts/kit-api.py", file=sys.stderr)
            return 1
        print("luau/API.md is up to date")
        return 0
    OUTPUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT.relative_to(ROOT).as_posix()} ({len(text.encode())} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
