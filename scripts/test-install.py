"""Isolated Claude plugin install/0.1 upgrade and empty-cache tool acceptance.

Requires Python 3.10+, Git, Claude Code and Bash (Git Bash on Windows).
Only non-model Claude CLI commands are used. --skip-tools omits downloads,
checking/building and the positive Rojo hook test; it is not full acceptance.
"""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ("skills", "hooks", "scripts", "template", "luau", ".claude-plugin")
_server_spec = importlib.util.spec_from_file_location("install_dev_server", ROOT / "scripts/dev-server.py")
dev_server = importlib.util.module_from_spec(_server_spec)
_server_spec.loader.exec_module(dev_server)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def snapshot(path):
    """Read only: record directory listing/mtimes without reading user config."""
    if not path.exists():
        return {"exists": False}
    entries = {}
    for item in sorted(path.rglob("*")):
        rel = item.relative_to(path)
        # Other running Claude sessions continuously write `.in_use/<pid>` markers and app-synced
        # plugin state; that churn is not ours. Directory mtimes only echo those child changes.
        if ".in_use" in rel.parts or rel.parts[0] == "synced":
            continue
        stat = item.lstat()
        entries[rel.as_posix()] = [None, None, True] if item.is_dir() else [stat.st_mtime_ns, stat.st_size, False]
    return {"exists": True, "root_mtime_ns": None, "entries": entries}


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def inventory(root):
    """Exact shipped file set and bytes, including stale-file detection."""
    files = {}
    for component in COMPONENTS:
        folder = root / component
        require(folder.is_dir(), f"missing installed component: {folder}")
        for path in folder.rglob("*"):
            if "__pycache__" in path.parts or path.suffix == ".pyc":
                continue
            if path.is_file():
                files[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return files


def verify_copy(source, installed):
    expected, actual = inventory(source), inventory(installed)
    missing = sorted(expected.keys() - actual.keys())
    stale = sorted(actual.keys() - expected.keys())
    changed = sorted(name for name in expected.keys() & actual.keys() if expected[name] != actual[name])
    require(not (missing or stale or changed), f"installed files differ: missing={missing}, stale={stale}, changed={changed}")
    expected_skills = {p.name for p in (source / "skills").iterdir() if p.is_dir() and p.name != "__pycache__"}
    actual_skills = {p.name for p in (installed / "skills").iterdir() if p.is_dir() and p.name != "__pycache__"}
    require(expected_skills == actual_skills, "installed skill directory set differs")
    print(f"Verified {len(actual_skills)} skill directories and {len(actual)} component file hashes; no stale files")


def isolated_env(root):
    home = root / "home"
    home.mkdir(parents=True)
    # Allow only OS/runtime basics. Credentials, startup scripts and tool/config
    # overrides must never reach plugin, Git, Bash or downloaded tool children.
    allowed = {"PATH", "SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "SYSTEMDRIVE",
               "PROGRAMDATA", "NUMBER_OF_PROCESSORS", "OS", "LANG", "TERM", "TZ"}
    env = {key: value for key, value in os.environ.items()
           if key.upper() in allowed or key.upper().startswith(("PROGRAMFILES", "PROCESSOR_", "LC_"))}
    # No rokit stub: setup-tools.sh bootstraps Rokit only when `command -v rokit` finds nothing.
    tool_names = ("rojo", "luau-lsp", "selene", "stylua")
    guard = root / "tool-guard"
    guard.mkdir()
    for name in tool_names:
        stub = guard / name
        stub.write_text(f'#!/bin/sh\necho "isolated install: inherited {name} blocked" >&2\nexit 99\n')
        stub.chmod(0o755)
        if os.name == "nt":
            (guard / (name + ".cmd")).write_text(
                f'@echo off\necho isolated install: inherited {name} blocked 1>&2\nexit /b 99\n')
    path = [str(guard)]
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        # Keep mixed system bins (git/bash/python); only discard Rokit's own bin.
        normalized = entry.replace("\\", "/").rstrip("/").lower()
        if entry and not normalized.endswith("/.rokit/bin"):
            path.append(entry)
    stray = shutil.which("rokit", path=os.pathsep.join(path[1:]))
    if stray:
        raise ValueError(f"rokit outside ~/.rokit/bin is on PATH ({stray}); remove it from PATH so the empty-cache bootstrap is real")
    env.update({
        "HOME": home.as_posix(), "USERPROFILE": str(home),
        "CLAUDE_CONFIG_DIR": str(root / "claude-config"),
        "ROKIT_ROOT": str(home / ".rokit"),
        "APPDATA": str(home / "AppData/Roaming"),
        "LOCALAPPDATA": str(home / "AppData/Local"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "TMPDIR": root.as_posix(), "TMP": str(root), "TEMP": str(root),
        "PATH": os.pathsep.join(path), "PYTHONUTF8": "1", "PYTHONDONTWRITEBYTECODE": "1",
        "GIT_CONFIG_GLOBAL": str(root / "gitconfig"), "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Moonbrick install test", "GIT_AUTHOR_EMAIL": "test@moonbrick.invalid",
        "GIT_COMMITTER_NAME": "Moonbrick install test", "GIT_COMMITTER_EMAIL": "test@moonbrick.invalid",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1",
    })
    for key in ("APPDATA", "LOCALAPPDATA", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME"):
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    return env


def validate_owned_pid(pid, port):
    require(type(pid) is int and pid > 1, "refusing invalid owned process PID")
    require(type(port) is int and 1024 <= port <= 65535, "refusing invalid owned listener port")
    listener = dev_server.listener_pid(port)
    # Rokit's rojo.exe shim records its launch PID, while the real rojo.exe
    # child owns the socket. Prove that relationship using the startup helper.
    require(listener == pid or dev_server.listener_owned(port, pid),
            "refusing PID that does not own the recorded loopback listener")
    require(dev_server.listener_pid(port) == listener, "loopback listener changed during ownership check")
    return listener


def stop_owned_process(pid, port):
    # Recheck immediately before killing; marker files alone are not proof.
    listener = validate_owned_pid(pid, port)
    # Kill the proven listener, never a marker-supplied ancestor's whole tree.
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(listener), "/T", "/F"], check=True, timeout=30)
    else:
        os.kill(listener, 15)


def process_image(pid):
    if os.name == "nt":
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"], capture_output=True, text=True, timeout=30).stdout
        return out.split('","')[0].strip().strip('"').lower() if out.startswith('"') else ""
    return subprocess.run(["ps", "-o", "comm=", "-p", str(pid)], capture_output=True, text=True, timeout=5).stdout.strip().lower()


def stop_orphaned_rojo(port):
    """After a hook timeout there is no marker/PID. The port is this test's own ephemeral port, so a
    rojo listener on it is ours; stop only that listener (never by PID from a file)."""
    with socket.socket() as sock:
        if sock.connect_ex(("127.0.0.1", port)) != 0:
            return False
    listener = dev_server.listener_pid(port)
    require(Path(process_image(listener)).name.startswith("rojo"), "refusing to stop a non-Rojo listener")
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(listener), "/F"], check=True, timeout=30)
    else:
        os.kill(listener, 15)
    return True


def protected_plugin_paths():
    paths = [Path.home() / ".claude/plugins"]
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        configured = Path(os.environ["CLAUDE_CONFIG_DIR"]) / "plugins"
        if configured.resolve() != paths[0].resolve():
            paths.append(configured)
    return paths


def settings_snapshot(path):
    """Read-only protection of settings bytes, size and mtime; never print bytes.

    ~/.claude.json is intentionally excluded: other running Claude sessions
    continually update its session state, independently of this isolated test.
    """
    if not path.exists():
        return {"exists": False}
    stat = path.stat()
    return {"exists": True, "mtime_ns": stat.st_mtime_ns, "size": stat.st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


class Acceptance:
    def __init__(self, root, cli, bash):
        self.root, self.cli, self.bash = root, cli, bash
        self.env = isolated_env(root)
        self.plugin_id = "moonbrick@" + json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())["name"]
        self.marketplace = self.plugin_id.split("@", 1)[1]

    def run(self, args, cwd=None, timeout=120, env=None, input=None):
        print("$ " + " ".join(str(arg) for arg in args), flush=True)
        result = subprocess.run([str(arg) for arg in args], cwd=cwd or self.root,
                                env=env or self.env, input=input, capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=timeout)
        self.last_output = result.stdout + result.stderr
        print(self.last_output, end="", flush=True)
        require(result.returncode == 0, f"command exited {result.returncode}: {args}")
        return result.stdout

    def claude(self, *args):
        # Install/update can stall on a slow network for minutes; still bounded.
        return self.run([self.cli, "plugin", *args], timeout=300)

    def installed(self):
        plugins = json.loads(self.claude("list", "--json"))
        matches = [p for p in plugins if p["id"] == self.plugin_id and p["scope"] == "user"]
        require(len(matches) == 1 and matches[0]["enabled"] is True, "plugin is not installed/enabled at user scope")
        path = Path(matches[0]["installPath"]).resolve()
        require(path.is_relative_to(self.root.resolve()), f"installPath escaped temporary directory: {path}")
        return path

    def help(self):
        self.run([self.cli, "--version"])
        for args in ((), ("marketplace",), ("marketplace", "add"), ("marketplace", "update"),
                     ("install",), ("update",), ("uninstall",), ("list",)):
            self.claude(*args, "--help")

    def fresh(self):
        require(not (Path(self.env["CLAUDE_CONFIG_DIR"]) / "plugins").exists(), "plugin cache is not empty")
        self.claude("marketplace", "add", ROOT)
        self.claude("install", self.plugin_id)
        verify_copy(ROOT, self.installed())

    def upgrade(self):
        # Archive does not check out, modify or create worktree metadata in any user's tree.
        data = subprocess.run(["git", "-c", f"safe.directory={ROOT.as_posix()}", "archive", "--format=zip", "v0.1.0"], cwd=ROOT,
                              env=self.env, check=True, capture_output=True, timeout=30).stdout
        baseline = self.root / "v0.1.0"
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for item in archive.infolist():
                dest = (baseline / item.filename).resolve()
                require(dest.is_relative_to(baseline.resolve()), "archive path escapes baseline")
                if item.is_dir():
                    dest.mkdir(parents=True, exist_ok=True)
                else:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(archive.read(item))
        require(json.loads((baseline / ".claude-plugin/plugin.json").read_text())["version"] == "0.1.0", "wrong baseline version")
        self.claude("marketplace", "add", baseline)
        self.claude("install", self.plugin_id)
        cached = self.installed()
        verify_copy(baseline, cached)
        self.claude("marketplace", "add", ROOT)
        self.claude("marketplace", "update", self.marketplace)
        self.claude("update", self.plugin_id)
        stale = inventory(self.installed()) != inventory(ROOT)
        print(f"Update-only cached copy stale: {stale}")
        current = json.loads((ROOT / ".claude-plugin/plugin.json").read_text())["version"]
        if current != "0.1.0":
            # A version bump is what makes the normal update command refresh the cache.
            require(not stale, f"`claude plugin update` did not refresh 0.1.0 -> {current}")
        else:
            # Same version (development checkout): only reinstall refreshes the cache.
            self.claude("uninstall", self.plugin_id)
            self.claude("install", self.plugin_id)
        self.copy = self.installed()
        verify_copy(ROOT, self.copy)

    def scaffold(self, skip_tools):
        home = Path(self.env["USERPROFILE"])
        require(not (home / ".rokit").exists(), "tool cache is not empty before bootstrap")
        self.game = self.root / "game"
        args = [self.bash, (self.copy / "scripts/new-project.sh").as_posix(), self.game.as_posix(), "install-acceptance"]
        if skip_tools:
            args.append("--no-tools")
        elif os.environ.get("CI") and os.environ.get("GITHUB_TOKEN"):
            # Shared CI runners hit GitHub's unauthenticated rate limit (403). Bootstrap Rokit with the
            # installed copy's verified fetcher and authenticate it inside the isolated cache only.
            self.run([sys.executable, str(self.copy / "scripts/fetch-rokit.py")], timeout=300)
            # Rokit 1.2.0 `authenticate github --help` offers only --token;
            # no stdin/env token input exists. Bash expands this scoped env var
            # into Rokit's argv (visible to local process inspection). Keep it
            # out of printed argv and all other children; remove when supported.
            self.run([self.bash, "-c", 'export PATH="$HOME/.rokit/bin:$PATH"; rokit authenticate github --token "$GITHUB_TOKEN" --skip-verify'],
                     env=dict(self.env, GITHUB_TOKEN=os.environ["GITHUB_TOKEN"]))
        self.run(args, timeout=600)
        require((self.game / "tools/MCPKit.luau").is_file(), "installed scaffold missing MCPKit")
        if not skip_tools:
            cache = home / ".rokit"
            require(any(cache.rglob("rojo*")), "Rojo did not populate the isolated cache")
            self.run([self.bash, "tools/check.sh"], cwd=self.game, timeout=180)
            self.run([self.bash, "-c", 'export PATH="$HOME/.rokit/bin:$PATH"; rojo build default.project.json -o acceptance.rbxlx'], cwd=self.game)
            require((self.game / "acceptance.rbxlx").stat().st_size > 0, "empty Rojo build")
            print(f"Empty-cache bootstrap and checker/build used only {cache}")

    def hook_commands(self, directory):
        env = dict(self.env, CLAUDE_PLUGIN_ROOT=self.copy.as_posix(), CLAUDE_PROJECT_DIR=directory.as_posix())
        hooks = json.loads((self.copy / "hooks/hooks.json").read_text())["hooks"]["SessionStart"]
        count = 0
        for group in hooks:
            for hook in group["hooks"]:
                require(hook["type"] == "command", "SessionStart acceptance only supports command hooks")
                self.run([self.bash, "-c", hook["command"]], cwd=directory, env=env,
                         timeout=hook.get("timeout", 20), input="{}\n")
                count += 1
        require(count > 0, "missing SessionStart hook")

    def hook_outside(self):
        outside = self.root / "not-moonbrick"
        outside.mkdir()
        # A valid Rojo project alone must not cause a launch without MCPKit.
        (outside / "default.project.json").write_text('{"name":"not-moonbrick"}')
        # Tripwire covers attempted launches even if a short-lived server exits.
        hook_home = self.root / "hook-home"
        guard = hook_home / ".rokit/bin"
        guard.mkdir(parents=True)
        tripwire = self.root / "unexpected-rojo-launch"
        (guard / "rojo").write_text(f'#!/usr/bin/env bash\necho attempted > "{tripwire.as_posix()}"\nexit 99\n')
        (guard / "rojo").chmod(0o755)
        if os.name == "nt":
            (guard / "rojo.cmd").write_text(f'@echo off\necho attempted > "{tripwire}"\nexit /b 99\n')
        before = snapshot(outside)
        original_env = self.env
        self.env = dict(self.env, HOME=hook_home.as_posix(), USERPROFILE=str(hook_home),
                        ROKIT_ROOT=str(hook_home / ".rokit"), PATH=str(guard) + os.pathsep + self.env["PATH"])
        try:
            self.hook_commands(outside)
        finally:
            self.env = original_env
        require(snapshot(outside) == before, "hook wrote outside a Moonbrick project")
        require(not tripwire.exists(), "hook attempted a Rojo launch outside a Moonbrick project")

    def hook_project(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        config_path = self.game / "default.project.json"
        config = json.loads(config_path.read_text())
        config["servePort"] = port
        config_path.write_text(json.dumps(config))
        marker = self.game / ".moonbrick/serve.json"
        self.last_output = ""
        try:
            self.hook_commands(self.game)
            require(marker.is_file(), "hook exited without establishing owned Rojo startup")
            state = json.loads(marker.read_text())
            require(Path(state["project"]).resolve() == self.game.resolve() and state["port"] == port, "hook claimed wrong project/port")
            validate_owned_pid(state["pid"], port)
            # Use the installed probe/decoder. Local loopback only; no Studio or publishing.
            self.run([sys.executable, "-c",
                      'import importlib.util,json,sys; s=importlib.util.spec_from_file_location("server",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); i=m.probe(int(sys.argv[2])); assert i["sessionId"]==sys.argv[3]; assert i["projectName"]==sys.argv[4]; print("Verified owned hook Rojo session")',
                      self.copy / "scripts/dev-server.py", port, state["sessionId"], config["name"]])
            self.hook_commands(self.game)
            require(json.loads(marker.read_text()) == state, "hook started a duplicate server")
        finally:
            pid = None
            if marker.is_file():
                state = json.loads(marker.read_text())
                require(Path(state["project"]).resolve() == self.game.resolve() and state["port"] == port, "refusing to stop an unowned process")
                pid = state["pid"]
                validate_owned_pid(pid, port)
            else:
                # The shipped helper reports its own PID if startup validation
                # fails before writing the marker. Never infer ownership merely
                # from whoever is listening on the requested port.
                failed = re.search(r"owned startup process PID (\d+) may still be running", self.last_output)
                if failed:
                    pid = int(failed[1])
            if pid is None:
                pid = -1 if stop_orphaned_rojo(port) else None
            elif pid > 0:
                stop_owned_process(pid, port)
            if pid is not None:
                # Wait for the listener to close before deleting its project/logs.
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    with socket.socket() as sock:
                        if sock.connect_ex(("127.0.0.1", port)) != 0:
                            break
                    time.sleep(0.1)
                else:
                    raise ValueError("owned hook listener did not stop")


def main():
    # Windows redirected stdout defaults to a legacy code page; Claude's CLI
    # prints Unicode status symbols even when its output is captured.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-tools", action="store_true")
    args = parser.parse_args()
    rows = []
    protected = protected_plugin_paths()
    before = {path: snapshot(path) for path in protected}
    settings_before = {path.parent / "settings.json": settings_snapshot(path.parent / "settings.json")
                       for path in protected}
    for path, state in settings_before.items():
        print(f"Real settings BEFORE ({path}): {json.dumps(state, sort_keys=True)}", flush=True)
    for path, state in before.items():
        print(f"Real plugins BEFORE ({path}): root_mtime_ns={state.get('root_mtime_ns')}, entries={len(state.get('entries', {}))}, sha256={fingerprint(state)}", flush=True)
    try:
        cli = (shutil.which("claude.cmd") or shutil.which("claude")) if os.name == "nt" else shutil.which("claude")
        if os.name == "nt":
            git = shutil.which("git")
            candidates = [Path(git).parents[1] / "bin/bash.exe"] if git else []
            candidates.append(Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git/bin/bash.exe")
            bash = next((path for path in candidates if path.is_file()), None)
        else:
            bash = shutil.which("bash")
        require(cli and bash and Path(bash).is_file(), "Claude Code and Bash (Git Bash on Windows) are required")
        with tempfile.TemporaryDirectory(prefix="moonbrick-install-") as tmp:
            root = Path(tmp)
            fresh = Acceptance(root / "fresh", cli, bash)
            upgrade = Acceptance(root / "upgrade", cli, bash)
            stages = [("CLI syntax", fresh.help), ("Fresh plugin install + enabled inventory", fresh.fresh),
                      ("v0.1.0 upgrade + exact cached file hashes", upgrade.upgrade),
                      ("Installed-copy scaffold" if args.skip_tools else "Empty-cache bootstrap + installed check/build", lambda: upgrade.scaffold(args.skip_tools)),
                      ("Installed hook outside Moonbrick", upgrade.hook_outside)]
            if not args.skip_tools:
                stages.append(("Installed SessionStart + Rojo ownership/reuse", upgrade.hook_project))
            for name, action in stages:
                try:
                    action()
                except (OSError, ValueError, subprocess.SubprocessError) as error:
                    rows.append((name, "FAIL"))
                    print(f"FAIL: {error}", flush=True)
                    break
                rows.append((name, "PASS"))
            if args.skip_tools:
                rows.append(("Tool bootstrap/check/build + positive hook", "SKIP"))
        rows.append(("Temporary directories cleaned", "PASS"))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", flush=True)
        rows.append(("Prerequisites / cleanup", "FAIL"))
    finally:
        for path, previous in settings_before.items():
            after = settings_snapshot(path)
            print(f"Real settings AFTER ({path}): {json.dumps(after, sort_keys=True)}", flush=True)
            rows.append((f"Real {path} mtime/size/sha256 unchanged", "PASS" if previous == after else "FAIL"))
        for path, previous in before.items():
            after = snapshot(path)
            print(f"Real plugins AFTER ({path}): root_mtime_ns={after.get('root_mtime_ns')}, entries={len(after.get('entries', {}))}, sha256={fingerprint(after)}", flush=True)
            if previous != after:
                first, last = previous.get("entries", {}), after.get("entries", {})
                print("Changed real plugin entries: " + json.dumps(sorted(name for name in first.keys() | last.keys() if first.get(name) != last.get(name))))
            rows.append((f"Real {path} listing/mtime unchanged", "PASS" if previous == after else "FAIL"))
    print("\n| Check | Result |\n|---|---|")
    for name, status in rows:
        print(f"| {name} | {status} |")
    return 1 if any(status == "FAIL" for _, status in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
