"""Safety and stale-cache regressions for the isolated install acceptance runner."""
import importlib.util
from collections import Counter
from contextlib import redirect_stdout
import io
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
                   "ACTIONS_ID_TOKEN_REQUEST_TOKEN", "ACTIONS_CACHE_URL", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE",
                   "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
                   "NPM_TOKEN", "SSH_AUTH_SOCK", "GIT_ASKPASS", "GIT_EXEC_PATH", "UNRECOGNIZED_SECRET")}
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, secrets):
            env = install.isolated_env(Path(tmp))
            for key in secrets:
                self.assertNotIn(key, env)

    def test_custom_claude_plugins_are_protected(self):
        with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": "custom-claude"}):
            self.assertIn(Path("custom-claude/plugins"), install.protected_plugin_paths())
            self.assertIn(Path.home() / ".claude/plugins", install.protected_plugin_paths())

    def test_invalid_cleanup_pid_never_reaches_kill(self):
        with patch.object(install.os, "kill") as kill, patch.object(install.subprocess, "run") as run:
            for pid in (None, True, False, -1, 0, 1, "123", 2.0):
                with self.assertRaisesRegex(ValueError, "invalid owned process PID"):
                    install.stop_owned_process(pid, 34872)
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

    def test_cleanup_refuses_mismatched_listener_pid_without_killing(self):
        with patch.object(install.dev_server, "listener_pid", return_value=456) as listener, \
                patch.object(install.dev_server, "listener_owned", return_value=False), \
                patch.object(install.subprocess, "run") as run, patch.object(install.os, "kill") as kill:
            with self.assertRaisesRegex(ValueError, "does not own"):
                install.stop_owned_process(123, 34872)
            listener.assert_called_once_with(34872)
            run.assert_not_called()
            kill.assert_not_called()

    def test_cleanup_accepts_matching_listener_pid(self):
        with patch.object(install.dev_server, "listener_pid", return_value=123), \
                patch.object(install.subprocess, "run") as run, patch.object(install.os, "kill") as kill:
            install.stop_owned_process(123, 34872)
            if os.name == "nt":
                self.assertEqual(run.call_args.args[0], ["taskkill", "/PID", "123", "/T", "/F"])
                kill.assert_not_called()
            else:
                kill.assert_called_once_with(123, 15)
                run.assert_not_called()

    def test_cleanup_refuses_unproven_listener_or_invalid_port(self):
        with patch.object(install.dev_server, "listener_pid", side_effect=ValueError("no listener")), \
                patch.object(install.subprocess, "run") as run, patch.object(install.os, "kill") as kill:
            for port in (None, True, "34872", 0, 65536, 34872):
                with self.assertRaises(ValueError):
                    install.stop_owned_process(123, port)
            run.assert_not_called()
            kill.assert_not_called()

    def test_rokit_shim_descendant_only_kills_proven_listener(self):
        with patch.object(install.dev_server, "listener_pid", return_value=456), \
                patch.object(install.dev_server, "listener_owned", return_value=True) as owns, \
                patch.object(install.subprocess, "run") as run, patch.object(install.os, "kill") as kill:
            install.stop_owned_process(123, 34872)
            owns.assert_called_once_with(34872, 123)
            if os.name == "nt":
                self.assertEqual(run.call_args.args[0], ["taskkill", "/PID", "456", "/T", "/F"])
            else:
                kill.assert_called_once_with(456, 15)

    def test_listener_change_during_validation_never_reaches_kill(self):
        with patch.object(install.dev_server, "listener_pid", side_effect=[123, 456]), \
                patch.object(install.subprocess, "run") as run, patch.object(install.os, "kill") as kill:
            with self.assertRaisesRegex(ValueError, "listener changed"):
                install.stop_owned_process(123, 34872)
            run.assert_not_called()
            kill.assert_not_called()

    def test_child_env_preserves_only_platform_runtime_basics(self):
        inherited = {key: "runtime" for key in ("SystemRoot", "WINDIR", "COMSPEC", "PATHEXT", "SystemDrive",
                     "ProgramFiles", "ProgramFiles(x86)", "ProgramData", "NUMBER_OF_PROCESSORS",
                     "PROCESSOR_ARCHITECTURE", "OS", "LANG", "LC_ALL", "TERM", "TZ")}
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, inherited, clear=True):
            env = install.isolated_env(Path(tmp))
        for key, value in inherited.items():
            self.assertEqual({name.upper(): item for name, item in env.items()}[key.upper()], value)

    def test_settings_guard_detects_content_size_and_mtime_changes_read_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "settings.json"
            self.assertEqual(install.settings_snapshot(path), {"exists": False})
            path.write_bytes(b"abcd")
            before = install.settings_snapshot(path)
            stat = path.stat()
            self.assertEqual(install.settings_snapshot(path), before)
            self.assertEqual(path.read_bytes(), b"abcd")
            path.write_bytes(b"efgh")
            os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            after = install.settings_snapshot(path)
            self.assertEqual(after["size"], before["size"])
            self.assertEqual(after["mtime_ns"], before["mtime_ns"])
            self.assertNotEqual(after["sha256"], before["sha256"])
            os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1_000_000_000))
            self.assertNotEqual(install.settings_snapshot(path)["mtime_ns"], before["mtime_ns"])
            path.write_bytes(b"longer")
            self.assertNotEqual(install.settings_snapshot(path)["size"], before["size"])

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


class ImportReviewRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("review_fidelity", ROOT / "scripts/test-import-fidelity.py")
        cls.fidelity = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.fidelity)

    def node(self, name="Test", cls="Folder", props=None):
        return {"class": cls, "name": name, "parent": (), "source": None,
                "attrs": {}, "tags": (), "props": props or {}}

    def test_unlisted_property_change_addition_and_removal_are_unexpected(self):
        key = (("Test", 0),)
        old = {key: self.node(props={"Unlisted": ("string", "keep")})}
        for props in ({"Unlisted": ("string", "changed")}, {},
                      {"Unlisted": ("string", "keep"), "Extra": ("bool", "false")}):
            with self.subTest(props=props):
                counts, _, _ = self.fidelity.compare(old, {key: self.node(props=props)}, allow_design=True)
                self.assertEqual(counts["properties"], 1)

    def test_special_properties_still_check_presence_and_xml_type(self):
        key = (("Test", 0),)
        for name, value in (("Source", ("ProtectedString", "")),
                            ("AttributesSerialize", ("BinaryString", b"")), ("Tags", ("BinaryString", b""))):
            with self.subTest(name=name):
                old = {key: self.node()}
                new = {key: self.node(props={name: value})}
                counts, _, _ = self.fidelity.compare(old, new, allow_design=True)
                self.assertEqual(counts["properties"], 1)
                counts, _, expected = self.fidelity.compare(old, new, {"Folder": {name: value}}, allow_design=True)
                self.assertEqual(counts["properties"], 0)
                self.assertEqual(expected["default_properties"], 1)
                changed = {key: self.node(props={name: ("string", "")})}
                counts, _, _ = self.fidelity.compare(new, changed, allow_design=True)
                self.assertEqual(counts["properties"], 1)

    def test_validated_reference_metadata_can_create_attributes_property(self):
        model, part = (("Model", 0),), (("Model", 0), ("Part", 0))
        old = {model: self.node("Model", "Model", {"PrimaryPart": ("Ref", part)}),
               part: self.node("Part", "Part")}
        new = {key: dict(value, attrs=dict(value["attrs"]), props=dict(value["props"])) for key, value in old.items()}
        identifier = (2, b"0123456789abcdef0123456789abcdef")
        new[part]["attrs"]["Rojo_Id"] = identifier
        new[model]["attrs"]["Rojo_Target_PrimaryPart"] = identifier
        for key in new:
            new[key]["props"]["AttributesSerialize"] = ("BinaryString", b"validated metadata")
        counts, _, expected = self.fidelity.compare(old, new, allow_design=True)
        self.assertEqual(sum(counts.values()), 0)
        self.assertEqual(expected["reference_metadata"], 2)
        new[part]["attrs"]["Unrelated"] = (2, b"fail")
        counts, _, _ = self.fidelity.compare(old, new, allow_design=True)
        self.assertGreater(counts["attributes"], 0)

    def test_distinct_sibling_order_changes_are_unexpected(self):
        keys = [((name, 0),) for name in ("A", "B")]
        old = {key: self.node(key[0][0]) for key in keys}
        new = {key: old[key] for key in reversed(keys)}
        counts, _, _ = self.fidelity.compare(old, new, allow_design=True)
        self.assertEqual(counts["order"], 1)
        self.assertEqual(sum(counts.values()), 1)

    def test_default_breakdown_counts_exact_class_property_only(self):
        key = (("Test", 0),)
        default = ("bool", "false")
        tally = Counter()
        counts, _, expected = self.fidelity.compare({key: self.node()},
            {key: self.node(props={"Unlisted": default})}, {"Folder": {"Unlisted": default}},
            allow_design=True, default_breakdown=tally)
        self.assertEqual(sum(counts.values()), 0)
        self.assertEqual(expected["default_properties"], 1)
        self.assertEqual(tally, Counter({("Folder", "Unlisted"): 1}))
        counts, _, _ = self.fidelity.compare({key: self.node()},
            {key: self.node(props={"Unlisted": ("bool", "true")})}, {"Folder": {"Unlisted": default}},
            allow_design=True)
        self.assertEqual(counts["properties"], 1)

    def test_only_exact_directory_name_sort_can_exempt_order(self):
        parent = (("Parent", 0),)
        keys = [parent + ((name, 0),) for name in ("C", "A", "B")]
        old = {key: self.node(key[-1][0]) for key in keys}
        sorted_nodes = {key: old[key] for key in sorted(keys)}
        counts, _, expected = self.fidelity.compare(old, sorted_nodes, allow_design=True,
                                                   directory_parents={parent})
        self.assertEqual(counts["order"], 0)
        self.assertEqual(expected["order_filesystem"], 1)
        counts, _, _ = self.fidelity.compare(old, sorted_nodes, allow_design=True)
        self.assertEqual(counts["order"], 1, "model-blob/unknown origins must not qualify")
        reversed_nodes = {key: old[key] for key in reversed(sorted(keys))}
        counts, _, _ = self.fidelity.compare(old, reversed_nodes, allow_design=True,
                                            directory_parents={parent})
        self.assertEqual(counts["order"], 1)

    def test_order_origins_exclude_model_blobs_and_duplicate_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "src/Parent/Directory").mkdir(parents=True)
            (project / "src/Parent/Model.rbxm").write_bytes(b"fixture")
            keys = [(("Parent", 0), (name, ordinal)) for name, ordinal in
                    (("Directory", 0), ("Model", 0), ("Directory", 1))]
            origins = self.fidelity.directory_order_parents(project, {key: {} for key in keys})
            self.assertEqual(origins, {keys[0]})

    def test_successful_import_prints_original_place_notice(self):
        project = self.fidelity.load_project()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "game"
            place = Path(tmp) / "place.rbxl"
            place.write_bytes(b"fixture")
            project.new_project(root, "Notice test")
            def fake_rojo(*args, cwd):
                if args[1] == "syncback":
                    (cwd / "src/ServerScriptService/Test.server.luau").write_text("print('fixture')")
                elif args[1] == "sourcemap":
                    (cwd / "sourcemap.json").write_text("{}")
            out = io.StringIO()
            with patch.object(project, "run", fake_rojo), redirect_stdout(out):
                project.import_place(root, place)
            self.assertIn("Workspace, Lighting and StarterPlayer settings stay in the original place (not imported)", out.getvalue())


if __name__ == "__main__":
    unittest.main()
