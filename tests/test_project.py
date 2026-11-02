import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("project", ROOT / "scripts/project.py")
project = importlib.util.module_from_spec(spec)
spec.loader.exec_module(project)


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "game"
        project.new_project(self.root, 'Name / & "safe"')
        self.place = Path(self.tmp.name) / "place.rbxl"
        self.place.write_bytes(b"fixture")

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file() and ".moonbrick" not in p.parts}

    def fake_rojo(self, *args, cwd):
        if args[1] == "syncback":
            (cwd / "src/ServerScriptService/Hello.server.luau").write_text("print('imported')")
        elif args[1] == "sourcemap":
            (cwd / "sourcemap.json").write_text("{}")
        return ""

    def test_names_are_json_escaped(self):
        self.assertEqual(project.read_json(self.root / "default.project.json")["name"], 'Name / & "safe"')

    def test_failed_import_leaves_original_byte_identical(self):
        before = self.snapshot()
        def failed(*args, cwd):
            (cwd / "src/ServerScriptService/Partial.luau").write_text("partial")
            raise RuntimeError("bad place")
        with patch.object(project, "run", failed), self.assertRaisesRegex(RuntimeError, "bad place"):
            project.import_place(self.root, self.place)
        self.assertEqual(before, self.snapshot())

    def test_validation_failure_leaves_original_byte_identical(self):
        before = self.snapshot()
        def failed(*args, cwd):
            if args[1] == "sourcemap":
                raise RuntimeError("validation failed")
            return self.fake_rojo(*args, cwd=cwd)
        with patch.object(project, "run", failed), self.assertRaisesRegex(RuntimeError, "validation failed"):
            project.import_place(self.root, self.place)
        self.assertEqual(before, self.snapshot())

    def test_existing_game_code_is_refused(self):
        (self.root / "src/server/Main.server.luau").write_text("important")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "fresh project"):
            project.import_place(self.root, self.place)
        self.assertEqual(before, self.snapshot())

    def test_import_keeps_the_folders_claude_md_names_mapped(self):
        with patch.object(project, "run", self.fake_rojo):
            project.import_place(self.root, self.place)
        tree = project.read_json(self.root / "default.project.json")["tree"]
        self.assertEqual(tree["ServerScriptService"]["Server"]["$path"], "src/server")
        self.assertEqual(tree["ReplicatedStorage"]["Shared"]["$path"], "src/shared")
        self.assertEqual(tree["StarterPlayer"]["StarterPlayerScripts"]["Client"]["$path"], "src/client")
        self.assertEqual(tree["ServerScriptService"]["$path"], "src/ServerScriptService")
        guide = (self.root / "CLAUDE.md").read_text(encoding="utf-8")
        self.assertIn("## Imported game", guide)
        self.assertNotIn("not mapped, because the place already", guide)

    def test_import_skips_a_folder_name_the_place_already_uses(self):
        def named(*args, cwd):
            self.fake_rojo(*args, cwd=cwd)
            if args[1] == "syncback":
                (cwd / "src/ReplicatedStorage/Shared.luau").write_text("return {}")
            return ""
        with patch.object(project, "run", named):
            project.import_place(self.root, self.place)
        tree = project.read_json(self.root / "default.project.json")["tree"]
        self.assertNotIn("Shared", tree["ReplicatedStorage"])
        self.assertIn("`src/shared/`", (self.root / "CLAUDE.md").read_text(encoding="utf-8"))

    def test_failed_promotion_restores_claude_md(self):
        before = (self.root / "CLAUDE.md").read_bytes()
        original = project.Path.open
        def failed(path, *args, **kwargs):
            if path.name == "CLAUDE.md" and args and args[0] == "ab":
                raise OSError("guide write failed")
            return original(path, *args, **kwargs)
        with patch.object(project, "run", self.fake_rojo), patch.object(project.Path, "open", failed), self.assertRaises(OSError):
            project.import_place(self.root, self.place)
        self.assertEqual((self.root / "CLAUDE.md").read_bytes(), before)

    def test_new_projects_get_distinct_stable_ports(self):
        other = Path(self.tmp.name) / "game2"
        project.new_project(other, "two")
        first = project.read_json(self.root / "default.project.json")["servePort"]
        second = project.read_json(other / "default.project.json")["servePort"]
        self.assertNotEqual(first, second)
        self.assertTrue(project.PORT_BASE <= first < project.PORT_BASE + project.PORT_SPAN)
        self.assertNotEqual(first, 34872)

    def test_pick_port_skips_a_sibling_and_a_listener(self):
        target = Path(self.tmp.name) / "fresh"
        wanted = project.pick_port(target)
        (Path(self.tmp.name) / "sib").mkdir()
        (Path(self.tmp.name) / "sib/default.project.json").write_text(json.dumps({"servePort": wanted}))
        moved = project.pick_port(target)
        self.assertNotEqual(moved, wanted)
        with socket.socket() as held:
            held.bind(("127.0.0.1", moved))
            self.assertFalse(project.port_free(moved))
            self.assertNotIn(project.pick_port(target), (wanted, moved))

    def test_diagnostic_cannot_traverse_paths(self):
        with self.assertRaisesRegex(RuntimeError, "unexpected"):
            project.missing_entry("The child '../../outside' of Instance 'game' is present only in a project file", list(project.ENTRIES))

    def test_success_preserves_template_folders_and_ports(self):
        cfg = project.read_json(self.root / "default.project.json")
        cfg.update(servePort=34875, servePlaceIds=[1234])
        project.write_json(self.root / "default.project.json", cfg)
        with patch.object(project, "run", self.fake_rojo):
            project.import_place(self.root, self.place)
        self.assertTrue((self.root / "src/server/.gitkeep").exists())
        self.assertTrue((self.root / "src/ServerScriptService/Hello.server.luau").exists())
        cfg = project.read_json(self.root / "default.project.json")
        self.assertEqual(cfg["servePort"], 34875)
        self.assertEqual(cfg["servePlaceIds"], [1234])
        self.assertTrue(cfg["tree"]["ServerScriptService"]["$ignoreUnknownInstances"])

    def test_reserved_names_refused_without_deleting(self):
        before = self.snapshot()
        def conflict(*args, cwd):
            if args[1] == "syncback":
                (cwd / "src/ReplicatedStorage/Kit.luau").write_text("original game kit")
            return ""
        with patch.object(project, "run", conflict), self.assertRaisesRegex(ValueError, "reserved"):
            project.import_place(self.root, self.place)
        self.assertEqual(before, self.snapshot())

    def test_missing_service_retried_from_clean_stage(self):
        attempts = 0
        def retry(*args, cwd):
            nonlocal attempts
            if args[1] == "syncback":
                attempts += 1
                if attempts == 1:
                    (cwd / "src/ServerScriptService/Partial.luau").write_text("partial")
                    raise RuntimeError("The child 'ReplicatedFirst' of Instance 'game' is present only in a project file")
            return self.fake_rojo(*args, cwd=cwd)
        with patch.object(project, "run", retry):
            project.import_place(self.root, self.place)
        self.assertEqual(attempts, 2)
        self.assertFalse((self.root / "src/ServerScriptService/Partial.luau").exists())
        self.assertNotIn("ReplicatedFirst", project.read_json(self.root / "default.project.json")["tree"])

    def test_upgrade_preserves_game_files_and_backs_up_managed_edits(self):
        game = self.root / "src/server/MyGame.luau"
        game.write_text("my code")
        managed = self.root / "src/kit/server/PlayerData.luau"
        managed.write_text("local edits")
        project.sync(self.root)
        self.assertEqual(game.read_text(), "my code")
        self.assertEqual(managed.read_bytes(), (ROOT / "luau/lib/server/PlayerData.luau").read_bytes())
        self.assertTrue(any(p.read_text() == "local edits" for p in (self.root / ".moonbrick/backups").rglob("PlayerData.luau")))

    def test_interrupted_scaffold_resumes_and_keeps_existing_files(self):
        target = Path(self.tmp.name) / "partial"
        (target / ".moonbrick").mkdir(parents=True)
        (target / project.INCOMPLETE).write_text("x")
        (target / "notes.txt").write_text("mine")
        (target / "stylua.toml").write_text("mine too")
        project.new_project(target, "resumed")
        self.assertEqual((target / "notes.txt").read_text(), "mine")
        self.assertEqual((target / "stylua.toml").read_text(), "mine too")
        self.assertTrue((target / "tools/MCPKit.luau").is_file())
        self.assertFalse((target / project.INCOMPLETE).exists())
        self.assertEqual(project.read_json(target / "default.project.json")["name"], "resumed")

    def test_scaffold_without_a_commit_is_partial_and_keeps_its_port(self):
        before = project.read_json(self.root / "default.project.json")["servePort"]
        self.assertEqual(project.scaffold_state(self.root), "partial")
        project.new_project(self.root, "again")
        self.assertEqual(project.read_json(self.root / "default.project.json")["servePort"], before)

    def test_committed_project_is_left_alone(self):
        with patch.object(project, "has_commit", return_value=True):
            self.assertEqual(project.scaffold_state(self.root), "complete")
            before = self.snapshot()
            project.new_project(self.root, "other name")
            self.assertEqual(before, self.snapshot())

    def test_unrelated_folder_is_refused_untouched(self):
        target = Path(self.tmp.name) / "work"
        target.mkdir()
        (target / "default.project.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "unfinished Moonbrick scaffold"):
            project.new_project(target, "x")
        self.assertEqual([p.name for p in target.iterdir()], ["default.project.json"])

    def link_dir(self, link: Path, target: Path):
        try:
            link.symlink_to(target, target_is_directory=True)
        except OSError:
            # Windows without symlink privilege: a junction is the same escape and needs no privilege.
            if os.name != "nt" or subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)], capture_output=True).returncode:
                self.skipTest("symlink/junction creation unavailable")

    def test_symlink_cannot_escape_project(self):
        outside = Path(self.tmp.name) / "outside"
        outside.mkdir()
        for rel in ("src/kit/escape", "tools/escape", "tests/escape"):
            link = self.root / rel
            self.link_dir(link, outside)
            with self.assertRaisesRegex(ValueError, "symlink"):
                project.sync(self.root)
            os.rmdir(link) if os.name == "nt" else link.unlink()
        self.assertEqual(list(outside.iterdir()), [])

    def test_links_outside_managed_paths_do_not_block_sync(self):
        outside = Path(self.tmp.name) / "store"
        outside.mkdir()
        (self.root / "node_modules").mkdir()
        self.link_dir(self.root / "node_modules/pkg", outside)
        project.sync(self.root)
        self.assertEqual(list(outside.iterdir()), [])

    def test_upgrade_migrates_safety_and_ignores_without_touching_game_settings(self):
        cfg = project.read_json(self.root / "default.project.json")
        cfg["servePort"] = 34879
        del cfg["tree"]["ServerScriptService"]["$ignoreUnknownInstances"]
        cfg["tree"]["ReplicatedStorage"]["$ignoreUnknownInstances"] = False
        project.write_json(self.root / "default.project.json", cfg)
        (self.root / ".gitignore").write_text("# custom\nprivate/\n")
        project.sync(self.root)
        after = project.read_json(self.root / "default.project.json")
        self.assertEqual(after["servePort"], 34879)
        self.assertTrue(after["tree"]["ServerScriptService"]["$ignoreUnknownInstances"])
        self.assertFalse(after["tree"]["ReplicatedStorage"]["$ignoreUnknownInstances"])
        self.assertIn("private/", (self.root / ".gitignore").read_text())
        self.assertIn(".moonbrick/", (self.root / ".gitignore").read_text())
        before = self.snapshot()
        backups = list((self.root / ".moonbrick/backups").iterdir())
        project.sync(self.root)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(backups, list((self.root / ".moonbrick/backups").iterdir()))

    def test_upgrade_rolls_back_partial_write_failure(self):
        (self.root / "tools/check.sh").write_text("old checker")
        (self.root / "tools/MCPKit.luau").write_text("old helper")
        before = self.snapshot()
        original = project.os.replace
        calls = 0
        def fail_second(*args):
            nonlocal calls
            calls += 1
            if calls == 2: raise OSError("simulated permission failure")
            return original(*args)
        with patch.object(project.os, "replace", fail_second), self.assertRaisesRegex(OSError, "permission"):
            project.sync(self.root)
        self.assertEqual(before, self.snapshot())

    def test_concurrent_source_edits_are_not_promoted_over(self):
        def changed(*args, cwd):
            if args[1] == "sourcemap":
                (self.root / "src/server/UserNew.luau").write_text("user edit during import")
            return self.fake_rojo(*args, cwd=cwd)
        original_config = (self.root / "default.project.json").read_bytes()
        with patch.object(project, "run", changed), self.assertRaisesRegex(RuntimeError, "source changed"):
            project.import_place(self.root, self.place)
        self.assertEqual((self.root / "src/server/UserNew.luau").read_text(), "user edit during import")
        self.assertEqual((self.root / "default.project.json").read_bytes(), original_config)
        self.assertFalse((self.root / "src/ServerScriptService/Hello.server.luau").exists())

    def test_report_promotion_failure_rolls_back_import(self):
        before = self.snapshot()
        original = project.os.replace
        def failed(source, dest):
            if Path(dest).name == "import-report.json": raise OSError("report promotion failed")
            return original(source, dest)
        with patch.object(project, "run", self.fake_rojo), patch.object(project.os, "replace", failed), self.assertRaises(OSError):
            project.import_place(self.root, self.place)
        self.assertEqual(before, self.snapshot())


BASH = os.environ.get("MOONBRICK_BASH") or (r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else shutil.which("bash"))


class NewProjectScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.env = dict(os.environ, HOME=self.home.as_posix(), GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t.invalid", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t.invalid")
        self.env.pop("PYTHONUTF8", None)

    def script(self, *args, env=None):
        return subprocess.run([BASH, (ROOT / "scripts/new-project.sh").as_posix(), *args], cwd=self.base, env=env or self.env, capture_output=True, text=True, encoding="utf-8", timeout=120)

    def test_quoted_tilde_expands_to_home(self):
        result = self.script("~/RobloxProjects/g1", "g1", "--no-tools")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / "RobloxProjects/g1/default.project.json").is_file())
        self.assertFalse((self.base / "~").exists())

    def test_failed_commit_can_be_retried_with_the_same_command(self):
        # A pre-commit hook stands in for any git failure after the files are written.
        hooks = self.base / "hooks"
        hooks.mkdir()
        (hooks / "pre-commit").write_text("#!/bin/sh\nexit 1\n", newline="\n")
        (hooks / "pre-commit").chmod(0o755)
        broken = dict(self.env, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.hooksPath", GIT_CONFIG_VALUE_0=hooks.as_posix())
        first = self.script("game", "game", "--no-tools", env=broken)
        self.assertNotEqual(first.returncode, 0)
        self.assertIn("rerun this same command", first.stderr)
        second = self.script("game", "game", "--no-tools")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("Resuming", second.stdout)
        log = subprocess.run(["git", "log", "--oneline"], cwd=self.base / "game", capture_output=True, text=True)
        self.assertEqual(len(log.stdout.splitlines()), 1)

    def test_rerun_after_success_stages_nothing(self):
        self.assertEqual(self.script("game", "game", "--no-tools").returncode, 0)
        (self.base / "game/src/server/Work.luau").write_text("return {}\n")
        again = self.script("game", "game", "--no-tools")
        self.assertEqual(again.returncode, 0, again.stderr)
        status = subprocess.run(["git", "status", "--porcelain"], cwd=self.base / "game", capture_output=True, text=True).stdout
        self.assertIn("?? src/server/Work.luau", status)

    def test_non_ascii_name_survives_a_legacy_console_encoding(self):
        env = dict(self.env, PYTHONUTF8="0", PYTHONIOENCODING="cp1252")
        target = self.base / "script"
        result = subprocess.run(["python" if shutil.which("python") else "python3", str(ROOT / "scripts/project.py"), "new", str(target), "\u0e40\u0e01\u0e21"], env=env, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
