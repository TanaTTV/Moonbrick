"""Free test that the words in skills and docs match the repo.

    python scripts/check-refs.py [--root DIR]

Fails when a skill, doc or template names a repo path, script, flag or Kit function that doesn't
exist, or uses a plugin path a project session can't resolve. Exit 0 when clean, 1 with findings.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

SOURCES = ("skills/**/*.md", "agents/*.md", "template/CLAUDE.md", "docs/*.md", "README.md", "CONTRIBUTING.md", "luau/recipes/README.md")
# Reports of past runs quote old paths on purpose.
SKIPPED = {"docs/BENCHMARK.md", "docs/BENCHMARK-STUDIO-TREE.md"}
ROOTS = "scripts|skills|luau|docs|template|hooks|tests|acceptance|evals|agents|\\.claude-plugin|\\.github"
PATH_CHARS = r"[\w.-]+(?:/[\w.-]+)*/?"
PLUGIN_PATH = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/(" + PATH_CHARS + ")")
REPO_PATH = re.compile(r"(?<![\w./}$-])((?:" + ROOTS + r")/" + PATH_CHARS + ")")
TOOLS_PATH = re.compile(r"(?<![\w./}$-])(tools/" + PATH_CHARS + ")")
UNDEFINED_ROOT = re.compile(r"(?<![\w$])(KIT/[\w.-]+|<kit>/[\w.-]+)")
SCRIPT_CALL = re.compile(r"((?:scripts|tools)/[\w./-]+\.(?:py|sh))\b([^`\n]*)")
FLAG = re.compile(r"(?<![\w-])(--[a-z][a-z0-9-]+)")
SYMBOL = re.compile(r"(?<![\w.:\"'])(K|Fx|Tex|Geo|UI|Net|VFX|PlayerData|Cooldown|Round|Economy|Motion|Pose|Audio|DebugHooks|Scheduler)[.:]([A-Za-z_]\w*)")
INLINE_CODE = re.compile(r"`([^`\n]+)`")
LINK = re.compile(r"(?<!!)\[[^\]\n]*\]\(([^)\s#]+)(?:#[^)]*)?\)")
MODULES = {
    "K": ("luau/MCPKit.luau",), "Fx": ("luau/lib/shared/Fx.luau",), "Tex": ("luau/lib/shared/Tex.luau",), "Geo": ("luau/lib/shared/Geo.luau",),
    "UI": ("luau/lib/shared/UI.luau",), "Net": ("luau/lib/shared/Net.luau",), "VFX": ("luau/lib/shared/VFX.luau",), "Motion": ("luau/lib/shared/Motion.luau",),
    "Pose": ("luau/lib/shared/Pose.luau",), "Audio": ("luau/lib/shared/Audio.luau",), "Scheduler": ("luau/lib/shared/Scheduler.luau",),
    "PlayerData": ("luau/lib/server/PlayerData.luau",), "Cooldown": ("luau/lib/server/Cooldown.luau",), "Round": ("luau/lib/server/Round.luau",),
    "Economy": ("luau/lib/server/Economy.luau",), "DebugHooks": ("template/src/kit/server/DebugHooks.luau",),
}
# What sync() puts in a project's tools/ folder, beside template/tools.
PROJECT_TOOLS = {"tools/MCPKit.luau", "tools/KIT_API.md", "tools/KIT_CREATIVE.md", "tools/.moonbrick-version", "tools/recipes", "tools/recipes/"}
# Files a project creates for itself: named in plugin docs, but never in this repo.
PROJECT_RELATIVE = {"docs/design.md"}


def clean(path: str) -> str:
    return path.rstrip(".,;:")


def code_spans(lines: list[str]) -> list[tuple[int, str]]:
    """Inline code and fenced blocks, where a name means a real thing rather than prose."""
    spans, fenced = [], False
    for number, line in enumerate(lines, 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        elif fenced:
            spans.append((number, line))
        else:
            spans.extend((number, match.group(1)) for match in INLINE_CODE.finditer(line))
    return spans


class Checker:
    def __init__(self, root: Path):
        self.root = root
        self.symbols: dict[str, set[str]] = {}
        self.findings: list[str] = []

    def exists(self, relative: str) -> bool:
        return (self.root / relative.rstrip("/")).exists()

    def known_symbols(self, module: str) -> set[str]:
        if module not in self.symbols:
            names = set()
            for relative in MODULES[module]:
                path = self.root / relative
                if path.is_file():
                    text = path.read_text(encoding="utf-8", errors="replace")
                    names.update(re.findall(r"\b" + module + r"[.:]([A-Za-z_]\w*)\s*(?:\(|=|:)", text))
                    names.update(re.findall(r"function\s+" + module + r"[.:]([A-Za-z_]\w*)", text))
                    if module == "K":
                        names.update(re.findall(r"^\s*function\s+\w+[.:]([A-Za-z_]\w*)", text, re.M))
            self.symbols[module] = names
        return self.symbols[module]

    def add(self, source: str, number: int, message: str):
        entry = f"{source}:{number}: {message}"
        if entry not in self.findings:
            self.findings.append(entry)

    def check_tools_path(self, source: str, number: int, path: str):
        if path in PROJECT_TOOLS or path.startswith("tools/recipes/") or (self.root / "template" / path.rstrip("/")).exists():
            return
        self.add(source, number, f"{path} is not in a project's tools/ folder")

    def check_flags(self, source: str, number: int, script: str, rest: str):
        target = None
        if script.startswith("tools/"):
            target = self.root / "template" / script
        elif (self.root / script).is_file():
            target = self.root / script
        if not target or not target.is_file():
            return
        text = target.read_text(encoding="utf-8", errors="replace")
        # A flag may belong to the next command on the line.
        for flag in FLAG.findall(re.split(r"&&|\|\||;|\|", rest, maxsplit=1)[0]):
            if flag not in text:
                self.add(source, number, f"{script} has no {flag} flag")

    def check_file(self, path: Path):
        source = path.relative_to(self.root).as_posix()
        project_facing = source.startswith(("skills/", "agents/", "template/"))
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for number, line in enumerate(lines, 1):
            for match in PLUGIN_PATH.finditer(line):
                target = clean(match.group(1))
                if not self.exists(target):
                    self.add(source, number, f"${{CLAUDE_PLUGIN_ROOT}}/{target} does not exist")
            for match in LINK.finditer(line):
                target = match.group(1)
                if not re.match(r"[a-z]+:", target) and not target.startswith("$") and not (path.parent / target).exists():
                    self.add(source, number, f"broken link {target}")
            for match in UNDEFINED_ROOT.finditer(line):
                self.add(source, number, f"{match.group(1)}: nothing defines this root; use ${{CLAUDE_PLUGIN_ROOT}}")
        for number, span in code_spans(lines):
            without_plugin = PLUGIN_PATH.sub("", span)
            for match in REPO_PATH.finditer(without_plugin):
                target = clean(match.group(1))
                # In skills and templates, docs/ and tests/ usually mean the game's own folders.
                if target in PROJECT_RELATIVE or (project_facing and target.startswith(("docs/", "tests/"))):
                    continue
                if project_facing and target.startswith(("scripts/", "luau/", "template/", "hooks/")):
                    self.add(source, number, f"{target} is a plugin path, which a project can't resolve; use ${{CLAUDE_PLUGIN_ROOT}}/{target}")
                elif not self.exists(target):
                    self.add(source, number, f"{target} does not exist")
            for match in TOOLS_PATH.finditer(without_plugin):
                self.check_tools_path(source, number, clean(match.group(1)))
            for match in SCRIPT_CALL.finditer(span):
                self.check_flags(source, number, match.group(1), match.group(2))
            for module, name in SYMBOL.findall(span):
                if name not in self.known_symbols(module):
                    self.add(source, number, f"{module}.{name} is not in the Kit")

    def run(self) -> list[str]:
        for pattern in SOURCES:
            for path in sorted(self.root.glob(pattern)):
                if path.is_file() and path.relative_to(self.root).as_posix() not in SKIPPED:
                    self.check_file(path)
        return self.findings


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args(argv)
    findings = Checker(args.root.resolve()).run()
    for line in findings:
        print(line)
    print(f"{len(findings)} broken reference(s)" if findings else "OK")
    return 1 if findings else 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
