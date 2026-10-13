"""Safe local project operations. No shell interpolation, broad deletion, or git staging."""
from __future__ import annotations

import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid

KIT = Path(__file__).resolve().parents[1]
ENTRIES = ("ServerScriptService", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "StarterGui", "StarterPlayer/StarterPlayerScripts", "StarterPlayer/StarterCharacterScripts")


def run(*args: str, cwd: Path) -> str:
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr or f"{args[0]} exited {result.returncode}")
    return result.stdout


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def is_link(path: Path) -> bool:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    # Includes Windows junctions/reparse points on supported Python versions before is_junction exists.
    return path.is_symlink() or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def safe_root(project: Path) -> Path:
    # Resolve only AFTER rejecting symlink roots; never follow project-managed links.
    if is_link(project):
        raise ValueError("project root must not be a symlink")
    project = project.resolve(strict=True)
    for path in project.rglob("*"):
        if is_link(path):
            raise ValueError(f"project contains a symlink/junction: {path.relative_to(project)}")
    if not (project / "default.project.json").is_file():
        raise ValueError("not a Moonbrick/Rojo project (missing default.project.json)")
    return project


def sync(project: Path):
    project = safe_root(project)
    sources = {"tools/MCPKit.luau": KIT / "luau/MCPKit.luau", "tools/check.sh": KIT / "template/tools/check.sh"}
    for source, dest in (("luau/lib/shared", "src/kit/shared"), ("luau/lib/server", "src/kit/server"), ("luau/tests", "tests/kit"), ("template/src/kit/server", "src/kit/server")):
        for file in (KIT / source).rglob("*"):
            if file.is_file():
                sources[f"{dest}/{file.relative_to(KIT / source).as_posix()}"] = file
    contents = {rel: source.read_bytes() for rel, source in sources.items()}
    # Upgrade safety boundaries without changing explicit user choices or other mappings/settings.
    cfg = read_json(project / "default.project.json")
    tree = cfg.get("tree", {})
    modified = False
    nodes = [tree] + [tree[name] for name in ("Workspace", "ServerStorage", "ServerScriptService", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPlayer") if name in tree]
    starter = tree.get("StarterPlayer", {})
    nodes.extend(starter[name] for name in ("StarterPlayerScripts", "StarterCharacterScripts") if name in starter)
    for node in nodes:
        if "$ignoreUnknownInstances" not in node:
            node["$ignoreUnknownInstances"] = True
            modified = True
    if modified:
        contents["default.project.json"] = (json.dumps(cfg, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    ignore_path = project / ".gitignore"
    ignores = ignore_path.read_text(encoding="utf-8") if ignore_path.exists() else ""
    if ".moonbrick/" not in ignores.splitlines():
        contents[".gitignore"] = (ignores.rstrip() + "\n\n# Moonbrick local backups and listener state\n.moonbrick/\n").encode("utf-8")
    version = read_json(KIT / ".claude-plugin/plugin.json")["version"]
    contents["tools/.moonbrick-version"] = (version + "\n").encode("utf-8")
    # Validate every destination before the first write. Keep old copies for review/rollback.
    for rel in contents:
        path = project / rel
        if path.exists() and not path.is_file():
            raise ValueError(f"managed file conflicts with directory: {rel}")
    changed = {rel: content for rel, content in contents.items() if not (project / rel).exists() or (project / rel).read_bytes() != content}
    backup = project / ".moonbrick/backups" / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8])
    for rel in changed:
        path = project / rel
        if path.is_file():
            dest = backup / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
    installed = []
    try:
        for rel, content in changed.items():
            dest = project / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary = tempfile.mkstemp(prefix=".moonbrick-", dir=dest.parent)
            os.close(descriptor)
            temp = Path(temporary)
            try:
                temp.write_bytes(content)
                os.replace(temp, dest)
                installed.append(rel)
            finally:
                temp.unlink(missing_ok=True)
    except BaseException:
        for rel in reversed(installed):
            dest = project / rel
            old = backup / rel
            if old.exists():
                shutil.copy2(old, dest)
            else:
                dest.unlink()
        raise
    print(f"moonbrick {version}: {len(changed)} managed files updated; game files preserved")
    if backup.exists():
        print(f"Previous files: {backup}")


def new_project(target: Path, name: str):
    if not name.strip() or any(ord(char) < 32 for char in name):
        raise ValueError("project name must be nonempty and contain no control characters")
    if is_link(target) or (target.exists() and (not target.is_dir() or any(target.iterdir()))):
        raise ValueError("target must be absent or an empty directory")
    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(KIT / "template", target, dirs_exist_ok=True)
    cfg = read_json(target / "default.project.json")
    cfg["name"] = name
    write_json(target / "default.project.json", cfg)
    claude = target / "CLAUDE.md"
    claude.write_text(claude.read_text(encoding="utf-8").replace("__PROJECT_NAME__", name), encoding="utf-8", newline="\n")
    sync(target)


def import_config(original: dict, entries: list[str], with_kit: bool) -> dict:
    cfg = {key: value for key, value in original.items() if key != "tree"}
    tree = {"$className": "DataModel", "$ignoreUnknownInstances": True}
    for entry in entries:
        segments = entry.split("/")
        node = tree
        for segment in segments:
            node = node.setdefault(segment, {"$ignoreUnknownInstances": True})
        node["$path"] = "src/" + entry
    # Omitted world/lighting stay in the original place. Import never invents scripts-only Workspace mapping.
    if with_kit:
        for service, children in {
            "ServerScriptService": {"Kit": {"$path": "src/kit/server"}},
            "ReplicatedStorage": {"Kit": {"$path": "src/kit/shared"}},
            "ServerStorage": {"MCPKit": {"$path": "tools/MCPKit.luau"}, "Tests": {"$path": "tests"}},
        }.items():
            tree.setdefault(service, {"$ignoreUnknownInstances": True}).update(children)
    cfg["tree"] = tree
    return cfg


def missing_entry(output: str, entries: list[str]) -> list[str]:
    match = re.search(r"The child '([^']*)' of Instance '([^']*)' is present only in a project file", output)
    if not match:
        raise RuntimeError(output)
    child, parent = match.groups()
    # Diagnostics are untrusted input. Only remove known configuration entries; never derive filesystem paths.
    candidate = f"StarterPlayer/{child}" if parent == "StarterPlayer" else child
    removed = [entry for entry in entries if entry == candidate or (child == "StarterPlayer" and entry.startswith("StarterPlayer/"))]
    if not removed:
        raise RuntimeError("unexpected syncback diagnostic; refusing retry: " + output)
    return [entry for entry in entries if entry not in removed]


def import_place(project: Path, place: Path):
    project = safe_root(project)
    place = place.resolve(strict=True)
    if place.suffix.lower() not in (".rbxl", ".rbxlx") or not place.is_file():
        raise ValueError("input must be a .rbxl or .rbxlx file")
    original_bytes = (project / "default.project.json").read_bytes()
    original = read_json(project / "default.project.json")
    # Imports are for fresh scaffolds. Existing code is never replaced or staged into git.
    for folder in ("src/server", "src/client", "src/shared", "src/world", *["src/" + entry for entry in ENTRIES]):
        root = project / folder
        if root.exists() and (not root.is_dir() or any(p.name != ".gitkeep" for p in root.rglob("*") if p.is_file())):
            raise ValueError(f"import requires a fresh project; existing content at {folder}")
    def source_snapshot():
        snapshot = {}
        for folder in ("src/server", "src/client", "src/shared", "src/world", *["src/" + entry for entry in ENTRIES]):
            for path in (project / folder).rglob("*"):
                snapshot[path.relative_to(project).as_posix()] = path.read_bytes() if path.is_file() else None
        return snapshot
    original_sources = source_snapshot()
    entries = list(ENTRIES)
    stage_parent = project / ".moonbrick"
    stage_parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="import-", dir=stage_parent) as scratch:
        stage = Path(scratch)
        for attempt in range(len(ENTRIES) + 1):
            trial = stage / str(attempt)
            trial.mkdir()
            for entry in entries:
                (trial / "src" / entry).mkdir(parents=True, exist_ok=True)
            write_json(trial / "default.project.json", import_config(original, entries, False))
            try:
                run("rojo", "syncback", "default.project.json", "--input", str(place), "--non-interactive", cwd=trial)
                break
            except RuntimeError as error:
                entries = missing_entry(str(error), entries)
        else:
            raise RuntimeError("syncback retry limit exhausted; original project preserved")
        # Exact reserved names only. Never erase Kitten, TestsGameplay, or somebody else's Kit.
        for rel, names in {"ServerScriptService": ("Kit",), "ReplicatedStorage": ("Kit",), "ServerStorage": ("MCPKit", "Tests")}.items():
            root = trial / "src" / rel
            if root.exists():
                for item in root.iterdir():
                    basename = re.sub(r"\.(server|client)?\.?lua[u]?$|\.model\.json$|\.rbxm[x]?$", "", item.name)
                    if basename in names:
                        raise ValueError(f"imported place conflicts with reserved name {rel}/{item.name}; rename it in a copy of the place")
        shutil.copytree(project / "src/kit", trial / "src/kit")
        shutil.copytree(project / "tools", trial / "tools")
        shutil.copytree(project / "tests", trial / "tests")
        write_json(trial / "default.project.json", import_config(original, entries, True))
        run("rojo", "sourcemap", "default.project.json", "-o", "sourcemap.json", cwd=trial)
        scanner_spec = importlib.util.spec_from_file_location("moonbrick_scanner", KIT / "scripts/scan-project.py")
        scanner = importlib.util.module_from_spec(scanner_spec)
        scanner_spec.loader.exec_module(scanner)
        report = scanner.scan(trial / "src")
        write_json(trial / "import-report.json", report)
        # Check original unchanged before promotion. Staged output uses the same filesystem for atomic renames.
        safe_root(project)
        if (project / "default.project.json").read_bytes() != original_bytes:
            raise RuntimeError("project changed during import; refusing promotion")
        if source_snapshot() != original_sources:
            raise RuntimeError("project source changed during import; refusing promotion")
        backup = project / ".moonbrick/backups" / ("import-" + uuid.uuid4().hex)
        backup.mkdir(parents=True)
        (backup / "default.project.json").write_bytes(original_bytes)
        moved = []
        displaced = []
        try:
            for entry in entries:
                dest = project / "src" / entry
                dest.parent.mkdir(parents=True, exist_ok=True)
                if dest.exists():
                    saved = backup / "src" / entry
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    os.replace(dest, saved)
                    displaced.append((saved, dest))
                os.replace(trial / "src" / entry, dest)
                moved.append((dest, trial / "src" / entry))
            os.replace(trial / "default.project.json", project / "default.project.json")
            os.replace(trial / "import-report.json", project / ".moonbrick/import-report.json")
        except BaseException:
            for dest, source in reversed(moved):
                os.replace(dest, source)
            for saved, dest in reversed(displaced):
                os.replace(saved, dest)
            (project / "default.project.json").write_bytes(original_bytes)
            raise
    print(f"Imported {place.name}; review the Rojo connection diff before accepting. Backup: {backup}")
    print(f"Advisory import scan: {len(report['scripts'])} scripts, {len(report['findings'])} findings; review .moonbrick/import-report.json before play/publish.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    new = sub.add_parser("new")
    new.add_argument("project", type=Path)
    new.add_argument("name")
    update = sub.add_parser("sync")
    update.add_argument("project", type=Path)
    imp = sub.add_parser("import")
    imp.add_argument("project", type=Path)
    imp.add_argument("place", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "new":
            new_project(args.project, args.name)
        elif args.command == "sync":
            sync(args.project)
        else:
            import_place(args.project, args.place)
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
