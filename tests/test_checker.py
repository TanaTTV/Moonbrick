"""Regression tests run the shipped checker against controlled tool processes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("MOONBRICK_BASH") or (r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else shutil.which("bash"))


class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        (self.project / "tools").mkdir()
        shutil.copy(ROOT / "template/tools/check.sh", self.project / "tools/check.sh")
        (self.project / "src").mkdir()
        (self.project / "src/Main.luau").write_text("return {}\n")
        (self.project / "globalTypes.d.luau").write_text("-- fixture\n")
        (self.project / "default.project.json").write_text("{}")
        self.bin = self.project / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=self.project.as_posix(), PATH=self.bin.as_posix() + os.pathsep + os.environ["PATH"])
        self.tool("rojo", 'while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then shift; echo "{}" >"$1"; fi; shift; done')
        self.tool("luau-lsp", "exit 0")
        self.tool("selene", "exit 0")
        self.tool("stylua", "exit 0")

    def tool(self, name, body):
        file = self.bin / name
        file.write_text("#!/usr/bin/env bash\n" + body + "\n", newline="\n")
        file.chmod(0o755)

    def run_check(self, *args):
        # Git Bash prepends its own binaries at process startup; set test PATH inside Bash.
        return subprocess.run([BASH, "-c", 'export PATH="$PWD/bin:$PATH"; exec bash tools/check.sh "$@"', "check", *args], cwd=self.project, env=self.env, capture_output=True, text=True, timeout=20)

    def assertFailed(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("OK", result.stdout.splitlines())

    def test_clean(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "OK")

    def test_silent_analyzer_failure(self):
        self.tool("luau-lsp", "exit 42")
        self.assertFailed(self.run_check())

    def test_filtered_failure_is_not_success(self):
        self.tool("selene", "echo '[WARN] unavailable'; exit 2")
        self.assertFailed(self.run_check())

    def test_sourcemap_failure_does_not_use_stale_map(self):
        self.tool("rojo", "exit 3")
        stale = self.project / "sourcemap.json"
        stale.write_text("stale")
        self.assertFailed(self.run_check())
        self.assertEqual(stale.read_text(), "stale")

    def test_formatter_failure(self):
        self.tool("stylua", "exit 5")
        self.assertFailed(self.run_check("--fix"))

    def test_partial_download_not_installed(self):
        (self.project / "globalTypes.d.luau").unlink()
        self.tool("curl", 'while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then shift; echo partial >"$1"; fi; shift; done; exit 22')
        self.assertFailed(self.run_check())
        self.assertFalse((self.project / "globalTypes.d.luau").exists())

    def test_mcpkit_is_checked_even_without_game_scripts(self):
        (self.project / "src/Main.luau").unlink()
        (self.project / "tools/MCPKit.luau").write_text("return {}")
        self.tool("luau-lsp", 'case "$*" in *tools/MCPKit.luau*) exit 23 ;; *) exit 0 ;; esac')
        self.assertFailed(self.run_check())


if __name__ == "__main__":
    unittest.main()
