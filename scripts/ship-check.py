"""Find what a game still needs before publishing that a playtest in Studio can't show.

    python scripts/ship-check.py [project-dir]

Blockers: local-preview textures and sounds that exist only on this computer, so players get stock
textures or silence. Reminders: Studio settings the code depends on. Reads src/ except src/kit.

Exit 0 with no blockers, 1 with blockers, 2 on bad usage.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

TEXT_FILES = {".luau", ".lua", ".json", ".txt", ".csv"}
PREVIEW_CALL = re.compile(r"\bTex\.usePreview\s*\(")
STUDIO_GUARD = re.compile(r"\bIsStudio\s*\(")
LOCAL_ASSET = re.compile(r"rbxasset://(?:textures|sounds)/moonbrick/[\w./-]*")
GEO_USE = re.compile(r"\bGeo\.(?:build|cached|dress|new|toPart|register|unitTorus|unitShard)\s*\(|\bEditableMesh\b|\bEditableImage\b|:CreateEditable(?:Mesh|Image)\b")
RUNTIME_IMAGE = re.compile(r"\bTex\.(?:get)\s*\(")


def without_comment(line: str) -> str:
    return line.split("--", 1)[0]


def guarded(lines: list[str], index: int) -> bool:
    """`if RunService:IsStudio() then Tex.usePreview() end`, on this line or just above it."""
    return any(STUDIO_GUARD.search(without_comment(line)) for line in lines[max(0, index - 3):index + 1])


def scan(project: Path) -> tuple[list[str], list[str], list[str]]:
    blockers, notes, needs = [], [], []
    source = project / "src"
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(project).as_posix()
        if not path.is_file() or path.suffix.lower() not in TEXT_FILES or relative.startswith("src/kit/"):
            continue
        is_code = path.suffix.lower() in (".luau", ".lua")
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for index, line in enumerate(lines):
            text = without_comment(line) if is_code else line
            where = f"{relative}:{index + 1}"
            if is_code and PREVIEW_CALL.search(text):
                if guarded(lines, index):
                    notes.append(f"{where} Tex.usePreview is Studio-only here, so players get stock textures until you call Tex.useFiles.")
                else:
                    blockers.append(f"{where} Tex.usePreview points players at files on this computer. Upload the textures and call Tex.useFiles, or guard it with RunService:IsStudio().")
            for match in LOCAL_ASSET.finditer(text):
                blockers.append(f"{where} {match.group(0)} exists only on this computer. Upload it and use the rbxassetid.")
            if is_code and (GEO_USE.search(text) or RUNTIME_IMAGE.search(text)):
                needs.append(where)
    return blockers, notes, needs


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("project", nargs="?", type=Path, default=Path("."))
    args = parser.parse_args(argv)
    if not (args.project / "src").is_dir():
        parser.error(f"no src/ folder in {args.project}")
    blockers, notes, needs = scan(args.project)
    for line in blockers:
        print(f"blocker: {line}")
    for line in notes:
        print(f"note: {line}")
    if needs:
        print(f"setting: turn on Game Settings > Security > \"Allow Mesh & Image APIs\" before publishing. Needed by {needs[0]}" + (f" and {len(needs) - 1} more" if len(needs) > 1 else "") + ".")
    if not blockers:
        print("OK")
    return 1 if blockers else 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
