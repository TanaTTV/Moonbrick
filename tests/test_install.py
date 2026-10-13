"""Safety and stale-cache regressions for the isolated install acceptance runner."""
import importlib.util
import os
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

    def test_real_tool_wrappers_are_removed_from_child_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            wrappers = root / "real-wrappers"
            safe = root / "safe-bin"
            wrappers.mkdir()
            safe.mkdir()
            (wrappers / "rokit.exe").write_bytes(b"not executed")
            with patch.dict(os.environ, {"PATH": str(wrappers) + os.pathsep + str(safe)}):
                env = install.isolated_env(root / "isolated")
            self.assertEqual(env["PATH"], str(safe))

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
