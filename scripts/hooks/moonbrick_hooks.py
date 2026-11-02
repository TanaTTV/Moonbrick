"""Moonbrick's Claude Code hooks. Standard library only; fails open and stays silent when not relevant.

    scripts/hooks/run.sh <prompt|pre-edit|post-tool|stop>   (hook JSON on stdin)

Field names were checked against the schemas embedded in Claude Code 2.1.312 and the hooks docs:
Bash's tool_response carries stdout/stderr/interrupted/isImage and no exit code, and a failing
command fires PostToolUseFailure instead of PostToolUse. A pipe can still hide a failed check, so
"passed" also needs check.sh's own OK line.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import sys

LOOP_WINDOW = 16
LOOP_RULES = ((1, 6), (2, 3), (3, 3), (4, 3))  # (period, repeats needed)
POLLING_TOOLS = ("wait_job_finished", "get_studio_state")
POLLING_CALLS = re.compile(r"\bK\.(results|logs)\b")
TRANSCRIPT_TAIL = 2_000_000

ROBLOX_WORDS = re.compile(r"\b(roblox|luau)\b", re.I)
ROJO_WORD = re.compile(r"\brojo\b", re.I)
# "Rojo" alone is also Spanish for red, so it needs a development word beside it.
ROJO_CONTEXT = re.compile(r"\b(serve|sync|syncback|sourcemap|project|plugin|build|studio|place|game|script|install|port|connect\w*|setup|set up)\b|\.project\.json|\.rbxl", re.I)

STUDIO_NAME = r"(?:roblox[ -]?studio|(?<!visual )(?<!android )\bstudio\b)(?:'s)?(?: (?:mcp|tools?|connection|server|instance|plugin|session)){0,2}"
UNAVAILABLE = (
    r"(?:is|are|was|were|seems?|appears?(?: to be)?)?\s*(?:currently |still )?"
    r"(?:unavailable|not available|isn'?t available|aren'?t available|not connected|isn'?t connected|aren'?t connected|"
    r"disconnected|not running|isn'?t running|not open|isn'?t open|not reachable|unreachable|offline|not responding)"
)
STUDIO_CLAIM = re.compile(
    "|".join((
        STUDIO_NAME + r"\s+" + UNAVAILABLE,
        r"(?:can(?:no|')t|could(?: not|n'?t)|unable to|failed to)\s+(?:reach|access|connect to|use|find|talk to)\s+(?:the\s+)?(?:roblox\s+)?" + STUDIO_NAME,
        r"(?:don'?t|do not|didn'?t) have (?:access to\s+)?(?:the\s+)?(?:any\s+)?(?:roblox\s+)?" + STUDIO_NAME,
        r"no (?:access to\s+)?(?:roblox\s+)?(?:studio (?:mcp|tools?|connection|instance|session)s?)",
        r"without (?:access to\s+)?(?:roblox\s+)?studio (?:mcp|tools?)",
    )),
    re.I,
)
OTHER_STUDIO = re.compile(r"\b(?:visual|android)\s+studio\b", re.I)


def is_project(root: Path) -> bool:
    return (root / "default.project.json").is_file() and (root / "tools/MCPKit.luau").is_file()


def walk_up(start: Path, test) -> Path | None:
    for folder in (start, *list(start.parents)[:8]):
        if test(folder):
            return folder
    return None


def project_dir(data: dict) -> Path:
    return Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd())


def moonbrick_root(data: dict) -> Path | None:
    return walk_up(project_dir(data), is_project)


def state_dir() -> Path:
    base = os.environ.get("TMPDIR") or os.environ.get("TEMP") or os.environ.get("TMP") or "/tmp"
    return Path(base) / "moonbrick-hooks"


def state_file(data: dict, kind: str) -> Path:
    # Session ids come from the CLI, but this is a file name: keep it boring.
    session = re.sub(r"[^A-Za-z0-9_-]", "", str(data.get("session_id") or "unknown"))[:80] or "unknown"
    return state_dir() / f"{session}.{kind}.json"


def load_state(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path: Path, value: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.{os.getpid()}")
    temporary.write_text(json.dumps(value), encoding="utf-8")
    os.replace(temporary, path)


# 1. UserPromptSubmit: point Roblox work outside a project at the right skill.


def about_roblox(prompt: str) -> bool:
    if ROBLOX_WORDS.search(prompt):
        return True
    return bool(ROJO_WORD.search(prompt) and ROJO_CONTEXT.search(prompt))


def has_rojo_project(folder: Path) -> bool:
    return (folder / "default.project.json").is_file() and not (folder / "tools/MCPKit.luau").is_file()


def is_empty(folder: Path) -> bool:
    ignored = {".git", ".claude", ".DS_Store", "Thumbs.db", ".gitignore", ".vscode", ".idea"}
    try:
        return not [item for item in folder.iterdir() if item.name not in ignored]
    except OSError:
        return False


def on_prompt(data: dict) -> dict | None:
    prompt = data.get("prompt")
    if not isinstance(prompt, str) or data.get("source") not in (None, "user", "sdk") or data.get("agent_id"):
        return None
    if not about_roblox(prompt) or "moonbrick" in prompt.lower() or moonbrick_root(data):
        return None
    folder = project_dir(data)
    rojo = walk_up(folder, has_rojo_project)
    if rojo:
        line = "This folder is a Rojo project without the Moonbrick kit. If the user wants Moonbrick here, have them run `/moonbrick:import`."
    elif is_empty(folder):
        line = "This folder is empty. For a new Roblox game, start with the `moonbrick:new` skill."
    else:
        line = "For a new Roblox game, start with the `moonbrick:new` skill; it creates the project in its own folder."
    marker = state_file(data, "prompt")
    if marker.exists():
        return None
    save_state(marker, {"told": True})
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "Moonbrick: " + line}}


# 2. Dirty tracking: edits are marked here, and on_stop asks for the check.


def track_edit(data: dict):
    if data.get("tool_name") not in ("Edit", "Write", "MultiEdit"):
        return
    tool_input = data.get("tool_input")
    path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if not isinstance(path, str) or not path.lower().endswith((".luau", ".lua")):
        return
    target = Path(path)
    if not target.is_absolute():
        target = project_dir(data) / target
    root = walk_up(target.parent, is_project)
    # Without a checker there is nothing the Stop hook could ask for.
    if not root or not (root / "tools/check.sh").is_file() or ".moonbrick" in target.parts:
        return
    state_path = state_file(data, "dirty")
    state = load_state(state_path)
    files = state.get("files") if isinstance(state.get("files"), list) else []
    relative = target.as_posix()
    state = {"files": ([*files, relative] if relative not in files else files)[-50:], "reminded": False}
    save_state(state_path, state)


def check_passed(data: dict) -> bool:
    if data.get("tool_name") != "Bash":
        return False
    tool_input = data.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or "tools/check.sh" not in command.replace("\\", "/"):
        return False
    response = data.get("tool_response")
    stdout = response.get("stdout") if isinstance(response, dict) else response
    if not isinstance(stdout, str):
        return False
    return any(line.strip() == "OK" or line.strip().startswith("OK (") for line in stdout.splitlines())


def track_check(data: dict):
    if check_passed(data):
        path = state_file(data, "dirty")
        if path.exists():
            path.unlink()


# 3. PreToolUse: Rojo overwrites Studio edits to anything under a mapped path.


def path_segments(raw: str) -> list[str]:
    text = raw.strip().replace("\\", "/")
    text = re.sub(r"""\bgame:GetService\(\s*["']([^"']+)["']\s*\)""", r"\1", text)
    text = re.sub(r"""\[\s*["']([^"']+)["']\s*\]""", lambda m: "." + m.group(1).replace(".", "\0"), text)
    parts = [part.replace("\0", ".") for part in re.split(r"[./]", text) if part]
    if parts and parts[0].lower() in ("game", "datamodel"):
        parts = parts[1:]
    return ["Workspace" if part == "workspace" else part for part in parts]


def target_paths(tool_input) -> list[str]:
    """multi_edit takes file_path today; stay tolerant of renames and batches."""
    if not isinstance(tool_input, dict):
        return []
    found = []
    for key in ("file_path", "filePath", "path", "script_path", "scriptPath", "target", "instance_path"):
        value = tool_input.get(key)
        if isinstance(value, str):
            found.append(value)
    for key in ("files", "paths", "targets"):
        value = tool_input.get(key)
        if isinstance(value, list):
            found.extend(item for item in value if isinstance(item, str))
            found.extend(item["file_path"] for item in value if isinstance(item, dict) and isinstance(item.get("file_path"), str))
    return found


def node_path(node: dict) -> str | None:
    value = node.get("$path")
    if isinstance(value, dict):
        value = value.get("optional")
    return value if isinstance(value, str) else None


def mapped_location(tree: dict, segments: list[str]) -> tuple[str, list[str]] | None:
    """The deepest $path above this instance and the path below it, or None if Rojo doesn't manage it."""
    node, best = tree, None
    if isinstance(node_path(node), str):
        best = (node_path(node), segments)
    for index, segment in enumerate(segments):
        child = node.get(segment)
        if not isinstance(child, dict):
            break
        node = child
        if node_path(node):
            best = (node_path(node), segments[index + 1:])
    return best


def file_for(root: Path, base: str, rest: list[str]) -> str:
    """Name the real file when it exists, else where a new script of that name would go."""
    folder = base.rstrip("/")
    if not rest:
        return folder
    stem = "/".join([folder, *rest])
    for suffix in (".luau", ".server.luau", ".client.luau", ".lua", ".server.lua", ".client.lua", "/init.luau", "/init.server.luau", "/init.client.luau"):
        if (root / (stem + suffix)).is_file():
            return stem + suffix
    return stem + ".luau"


def on_pre_edit(data: dict) -> dict | None:
    root = walk_up(project_dir(data), lambda folder: (folder / "default.project.json").is_file())
    if not root:
        return None
    config = json.loads((root / "default.project.json").read_text(encoding="utf-8"))
    tree = config.get("tree") if isinstance(config, dict) else None
    if not isinstance(tree, dict):
        return None
    for raw in target_paths(data.get("tool_input")):
        location = mapped_location(tree, path_segments(raw))
        if location:
            where = file_for(root, *location)
            reason = (f"Rojo syncs {raw} from {where}, so an edit in Studio would be overwritten. "
                      f"Change {where} with Read and Edit instead. Scripts outside the Rojo mappings can still use multi_edit.")
            return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}
    return None


# 4 and 2. Stop: the unchecked-edit reminder, then the "Studio is unavailable" claim.


def studio_tool(name) -> bool:
    return isinstance(name, str) and name.startswith("mcp__") and "studio" in name.lower()


def is_prompt_entry(entry: dict) -> bool:
    if entry.get("type") != "user" or entry.get("isMeta") or entry.get("isSidechain"):
        return False
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        return True
    return isinstance(content, list) and any(isinstance(block, dict) and block.get("type") == "text" for block in content) \
        and not any(isinstance(block, dict) and block.get("type") == "tool_result" for block in content)


def transcript_tail(path: str) -> list[dict]:
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            handle.seek(max(0, handle.tell() - TRANSCRIPT_TAIL))
            lines = handle.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return []
    entries = []
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    return entries


def studio_called_this_turn(entries: list[dict]) -> bool:
    for entry in reversed(entries):
        if is_prompt_entry(entry):
            return False
        if entry.get("type") == "assistant":
            for block in (entry.get("message") or {}).get("content") or []:
                if isinstance(block, dict) and block.get("type") == "tool_use" and studio_tool(block.get("name")):
                    return True
    return False


def last_text(entries: list[dict]) -> str:
    for entry in reversed(entries):
        if entry.get("type") == "assistant":
            blocks = (entry.get("message") or {}).get("content") or []
            text = "\n".join(block.get("text", "") for block in blocks if isinstance(block, dict) and block.get("type") == "text")
            if text:
                return text
    return ""


def claims_studio_down(message: str, in_project: bool) -> bool:
    cleaned = OTHER_STUDIO.sub("", message)
    if not STUDIO_CLAIM.search(cleaned):
        return False
    return in_project or "roblox" in cleaned.lower()


def on_stop(data: dict) -> dict | None:
    if data.get("stop_hook_active"):
        return None
    dirty_path = state_file(data, "dirty")
    dirty = load_state(dirty_path)
    if dirty.get("files") and not dirty.get("reminded"):
        dirty["reminded"] = True
        save_state(dirty_path, dirty)
        names = ", ".join(Path(name).name for name in dirty["files"][:5])
        return {"decision": "block", "reason": f"Luau files changed with no passing check since ({names}). Run `bash tools/check.sh` and fix what it reports before finishing."}
    entries = None
    message = data.get("last_assistant_message")
    if not isinstance(message, str):
        entries = transcript_tail(str(data.get("transcript_path")))
        message = last_text(entries)
    if not claims_studio_down(message, moonbrick_root(data) is not None):
        return None
    if entries is None:
        entries = transcript_tail(str(data.get("transcript_path")))
    if not entries or studio_called_this_turn(entries):
        return None  # no transcript means no proof either way, so stay out of the way
    return {"decision": "block", "reason": "You said Studio is unavailable but called no Studio tool this turn. Call list_roblox_studios first, then report what it returns."}


# 5. Loop guard.


def normalized(value):
    if isinstance(value, str):
        return " ".join(value.split())
    if isinstance(value, dict):
        return {key: normalized(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [normalized(item) for item in value]
    return value


def fingerprint(name: str, tool_input) -> str:
    text = name + json.dumps(normalized(tool_input), sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:16]


def is_polling(name: str, tool_input) -> bool:
    if name.endswith(POLLING_TOOLS):
        return True
    return bool(POLLING_CALLS.search(json.dumps(tool_input, default=str)))


def repeating(history: list[str]) -> list[str] | None:
    """The repeating pattern at the end of the history, if any."""
    for period, repeats in LOOP_RULES:
        span = period * repeats
        if len(history) < span:
            continue
        tail = history[-span:]
        pattern = tail[-period:]
        if period > 1 and len(set(pattern)) == 1:
            continue  # a single repeated call is period 1's job
        if tail == pattern * repeats:
            return pattern
    return None


def guard_loop(data: dict) -> dict | None:
    name, tool_input = data.get("tool_name"), data.get("tool_input")
    if not isinstance(name, str) or is_polling(name, tool_input):
        return None
    if not (name.startswith(("mcp__Roblox", "mcp__blender")) or moonbrick_root(data)):
        return None
    key = "loop-" + re.sub(r"[^A-Za-z0-9_-]", "", str(data.get("agent_id") or "main"))
    path = state_file(data, key)
    state = load_state(path)
    history = [*state.get("history", []), fingerprint(name, tool_input)][-LOOP_WINDOW:]
    pattern = repeating(history)
    if not pattern:
        save_state(path, {**state, "history": history})
        return None
    identity = hashlib.sha256("".join(pattern).encode()).hexdigest()[:16]
    # Each trip starts a fresh window, so the second one needs the full run of repeats again.
    if state.get("warned") == identity:
        save_state(path, {"history": []})
        return {"continue": False, "stopReason": f"Moonbrick stopped this turn: {name} kept repeating after a warning. Tell Claude what to try next."}
    save_state(path, {"history": [], "warned": identity})
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": f"Moonbrick loop guard: the same tool calls ({name}) just repeated with identical input and got nowhere. Change approach, or stop and tell the user what is blocking you."}}


def on_post_tool(data: dict) -> dict | None:
    track_edit(data)
    track_check(data)
    return guard_loop(data)


HANDLERS = {"prompt": on_prompt, "pre-edit": on_pre_edit, "post-tool": on_post_tool, "stop": on_stop}


def main():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
        handler = HANDLERS.get(sys.argv[1] if len(sys.argv) > 1 else "")
        result = handler(data) if handler and isinstance(data, dict) else None
        if result:
            sys.stdout.buffer.write(json.dumps(result).encode("utf-8"))
    except BaseException:  # fail open: a hook bug must never block the user
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
