import importlib.util
import json
import os
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
