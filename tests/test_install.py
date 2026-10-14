"""Safety and stale-cache regressions for the isolated install acceptance runner."""
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("install_acceptance", ROOT / "scripts/test-install.py")
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)


class InstallTests(unittest.TestCase):
    def test_real_cache_and_config_overrides_are_replaced_only_in_child_env(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            inherited = dict(os.environ, ROKIT_ROOT="real-cache", CLAUDE_CONFIG_DIR="real-config",
                             BASH_ENV="real-startup", GIT_CONFIG_GLOBAL="real-git-config")
            with patch.dict(os.environ, inherited, clear=True):
                before = dict(os.environ)
                env = install.isolated_env(root)
                self.assertEqual(dict(os.environ), before)
            for key in ("HOME", "USERPROFILE", "ROKIT_ROOT", "CLAUDE_CONFIG_DIR", "APPDATA",
                        "LOCALAPPDATA", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "GIT_CONFIG_GLOBAL"):
                self.assertTrue(Path(env[key]).resolve().is_relative_to(root.resolve()), key)
            self.assertNotIn("BASH_ENV", env)

    def test_mixed_system_bins_preserved_and_tools_shadowed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mixed = root / "system-bin"
            rokit = root / ".rokit/bin"
            mixed.mkdir()
            rokit.mkdir(parents=True)
            (mixed / "rojo.exe").write_bytes(b"not executed")
            (mixed / "git").write_bytes(b"preserved")
            with patch.dict(os.environ, {"PATH": str(mixed) + os.pathsep + str(rokit)}):
                env = install.isolated_env(root / "isolated")
            entries = env["PATH"].split(os.pathsep)
            self.assertEqual(entries[1:], [str(mixed)])
            guard = Path(entries[0])
            self.assertFalse((guard / "rokit").exists(), "setup-tools must still bootstrap Rokit")
            for name in ("rojo", "luau-lsp", "selene", "stylua"):
                self.assertIn("exit 99", (guard / name).read_text())
                if os.name == "nt":
                    self.assertIn("exit /b 99", (guard / (name + ".cmd")).read_text())
            installed = Path(env["HOME"]) / ".rokit/bin"
            installed.mkdir(parents=True)
            (installed / "rojo.cmd").write_text("installed")
            bash = shutil.which("bash")
            if os.name == "nt":
                git_bash = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git/bin/bash.exe"
                if git_bash.is_file():
                    bash = str(git_bash)
            if bash:
                for name in ("rojo", "luau-lsp", "selene", "stylua"):
                    result = subprocess.run([bash, "--noprofile", "--norc", "-c", name], env=env, capture_output=True)
                    self.assertEqual(result.returncode, 99, name)
                tool = installed / "rojo"
                tool.write_text("#!/bin/sh\necho isolated-installed\n")
                tool.chmod(0o755)
                result = subprocess.run([bash, "--noprofile", "--norc", "-c",
                                         'export PATH="$HOME/.rokit/bin:$PATH"; rojo'],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "isolated-installed")

    def test_stray_rokit_outside_its_cache_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mixed = root / "system-bin"
            mixed.mkdir()
            name = "rokit.exe" if os.name == "nt" else "rokit"
            (mixed / name).write_bytes(b"not executed")
            (mixed / name).chmod(0o755)
            with patch.dict(os.environ, {"PATH": str(mixed)}), self.assertRaisesRegex(ValueError, "rokit outside"):
                install.isolated_env(root / "isolated")

    def test_credentials_actions_and_git_location_do_not_reach_children(self):
        secrets = {key: "secret" for key in ("GITHUB_TOKEN", "GH_TOKEN", "ACTIONS_RUNTIME_TOKEN",
                   "ACTIONS_ID_TOKEN_REQUEST_TOKEN", "ACTIONS_CACHE_URL", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, secrets):
            env = install.isolated_env(Path(tmp))
            for key in secrets:
                self.assertNotIn(key, env)

    def test_custom_claude_plugins_are_protected(self):
        with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": "custom-claude"}):
            self.assertIn(Path("custom-claude/plugins"), install.protected_plugin_paths())
            self.assertIn(Path.home() / ".claude/plugins", install.protected_plugin_paths())

    def test_invalid_cleanup_pid_never_reaches_kill(self):
        with patch.object(install.os, "killpg", create=True) as kill, patch.object(install.subprocess, "run") as run:
            for pid in (None, True, False, -1, 0, 1, "123", 2.0):
                with self.assertRaisesRegex(ValueError, "invalid owned process PID"):
                    install.stop_owned_process(pid)
            kill.assert_not_called()
            run.assert_not_called()

    def test_null_marker_pid_fails_without_killing(self):
        with tempfile.TemporaryDirectory() as tmp:
            runner = install.Acceptance(Path(tmp), "claude", "bash")
            runner.game = Path(tmp) / "game"
            runner.game.mkdir()
            runner.copy = ROOT
            config = runner.game / "default.project.json"
            config.write_text('{"name":"test"}')
            def hook(_):
                marker = runner.game / ".moonbrick/serve.json"
                marker.parent.mkdir()
                marker.write_text(json.dumps({"project": str(runner.game),
                                             "port": json.loads(config.read_text())["servePort"], "pid": None}))
            with patch.object(runner, "hook_commands", side_effect=hook), patch.object(install, "stop_owned_process") as stop:
                with self.assertRaisesRegex(ValueError, "invalid owned process PID"):
                    runner.hook_project()
                stop.assert_not_called()

    def test_known_launch_requires_matching_pid_or_descendant(self):
        install.validate_owned_pid(123, 123)
        with patch.object(install.subprocess, "run") as run:
            run.return_value.stdout = "123\n"
            install.validate_owned_pid(456, 123)
            run.return_value.stdout = "1\n"
            with self.assertRaisesRegex(ValueError, "outside launched process tree"):
                install.validate_owned_pid(456, 123)

    def test_authentication_token_is_scoped_to_one_command(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"CI": "1", "GITHUB_TOKEN": "test-token"}):
            runner = install.Acceptance(Path(tmp), "claude", "bash")
            runner.copy = ROOT
            # Stop before scaffold execution; inspect the fetch/auth/scaffold calls.
            with patch.object(runner, "run", side_effect=["", "", ValueError("stop at scaffold")]) as run:
                with self.assertRaisesRegex(ValueError, "stop at scaffold"):
                    runner.scaffold(False)
            self.assertNotIn("GITHUB_TOKEN", runner.env)
            self.assertNotIn("env", run.call_args_list[0].kwargs)
            self.assertEqual(run.call_args_list[1].kwargs["env"]["GITHUB_TOKEN"], "test-token")
            self.assertNotIn("env", run.call_args_list[2].kwargs)

    def test_archive_explicitly_trusts_only_this_repository(self):
        with tempfile.TemporaryDirectory() as tmp:
            runner = install.Acceptance(Path(tmp), "claude", "bash")
            with patch.object(install.subprocess, "run", side_effect=ValueError("stop at archive")) as run:
                with self.assertRaisesRegex(ValueError, "stop at archive"):
                    runner.upgrade()
            self.assertEqual(run.call_args.args[0][:4],
                             ["git", "-c", f"safe.directory={ROOT.as_posix()}", "archive"])

    def test_copy_comparison_refuses_stale_files_and_same_version_changed_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, cached = root / "source", root / "cached"
            for base in (source, cached):
                for component in install.COMPONENTS:
                    (base / component).mkdir(parents=True)
                (base / "skills/new").mkdir()
                (base / "skills/new/SKILL.md").write_text("current skill")
                (base / "scripts/new-project.sh").write_text("current scaffold")
            install.verify_copy(source, cached)
            stale = cached / "scripts/removed-in-current.sh"
            stale.write_text("old shadowing script")
            with self.assertRaisesRegex(ValueError, "stale=.*removed-in-current"):
                install.verify_copy(source, cached)
            stale.unlink()
            (cached / "skills/new/SKILL.md").write_text("old skill, same version")
            with self.assertRaisesRegex(ValueError, "changed=.*SKILL.md"):
                install.verify_copy(source, cached)

    def test_snapshot_detects_mtime_only_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "plugin.json"
            path.write_text("unchanged bytes")
            before = install.snapshot(root)
            stat = path.stat()
            os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1_000_000_000))
            self.assertNotEqual(before, install.snapshot(root))


if __name__ == "__main__":
    unittest.main()
