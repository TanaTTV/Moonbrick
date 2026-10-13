"""Isolated Claude plugin install/0.1 upgrade and empty-cache tool acceptance.

Requires Python 3.10+, Git, Claude Code and Bash (Git Bash on Windows).
Only non-model Claude CLI commands are used. --skip-tools omits downloads,
checking/building and the positive Rojo hook test; it is not full acceptance.
"""
import argparse
import hashlib
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


def require(condition, message):
    if not condition:
        raise ValueError(message)


def snapshot(path):
    """Read only: record directory listing/mtimes without reading user config."""
    if not path.exists():
        return {"exists": False}
    entries = {}
    for item in sorted(path.rglob("*")):
        stat = item.lstat()
        entries[item.relative_to(path).as_posix()] = [stat.st_mtime_ns, stat.st_size, item.is_dir()]
    return {"exists": True, "root_mtime_ns": path.stat().st_mtime_ns, "entries": entries}


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
    env = dict(os.environ)
    # Do not inherit a real tool wrapper or a real cache/config override.
    for key in list(env):
        if key.startswith(("CLAUDE_", "ROKIT_", "GIT_CONFIG_")) or key in ("BASH_ENV", "ENV"):
            del env[key]
    tool_names = ("rokit", "rojo", "luau-lsp", "selene", "stylua")
    path = []
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if entry and not any((Path(entry) / (name + suffix)).is_file()
                             for name in tool_names for suffix in ("", ".exe", ".cmd")):
            path.append(entry)
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
        return self.run([self.cli, "plugin", *args])

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
        data = subprocess.run(["git", "archive", "--format=zip", "v0.1.0"], cwd=ROOT,
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
        # Current and released manifests both say 0.1.0. Reinstall refreshes that
        # cache even on CLIs that use readFromFolder for local marketplaces.
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
            self.run([self.bash, "-c", 'export PATH="$HOME/.rokit/bin:$PATH"; rokit authenticate github --token "$GITHUB_TOKEN" --skip-verify'])
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
            else:
                # The shipped helper reports its own PID if startup validation
                # fails before writing the marker. Never infer ownership merely
                # from whoever is listening on the requested port.
                failed = re.search(r"owned startup process PID (\d+) may still be running", self.last_output)
                if failed:
                    pid = int(failed[1])
            if pid is not None:
                if os.name == "nt":
                    self.run(["taskkill", "/PID", str(pid), "/T", "/F"])
                else:
                    # Rojo's Rokit wrapper and binary share this new session.
                    os.killpg(pid, 15)
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
    protected = Path.home() / ".claude/plugins"
    before = snapshot(protected)
    print(f"Real plugins BEFORE: root_mtime_ns={before.get('root_mtime_ns')}, entries={len(before.get('entries', {}))}, sha256={fingerprint(before)}", flush=True)
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
        after = snapshot(protected)
        print(f"Real plugins AFTER:  root_mtime_ns={after.get('root_mtime_ns')}, entries={len(after.get('entries', {}))}, sha256={fingerprint(after)}", flush=True)
        if before != after:
            first, last = before.get("entries", {}), after.get("entries", {})
            print("Changed real plugin entries: " + json.dumps(sorted(name for name in first.keys() | last.keys() if first.get(name) != last.get(name))))
        rows.append(("Real ~/.claude/plugins listing/mtime unchanged", "PASS" if before == after else "FAIL"))
    print("\n| Check | Result |\n|---|---|")
    for name, status in rows:
        print(f"| {name} | {status} |")
    return 1 if any(status == "FAIL" for _, status in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
