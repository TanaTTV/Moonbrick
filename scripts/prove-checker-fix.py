"""Reproduce the checker false-success defect on the original source and verify current behavior."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from test_checker import CheckerTests

fixture = CheckerTests()
fixture.setUp()
try:
    fixture.tool("luau-lsp", "exit 42")
    current = fixture.run_check()
    old = subprocess.run(["git", "show", "c451028:template/tools/check.sh"], cwd=ROOT, check=True, capture_output=True).stdout
    (fixture.project / "tools/check.sh").write_bytes(old)
    baseline = fixture.run_check()
    print(f"0.1 checker: exit={baseline.returncode}, output={baseline.stdout.strip()!r}")
    print(f"current checker: exit={current.returncode}, output={current.stdout.strip()!r}")
    assert baseline.returncode == 0 and baseline.stdout.strip() == "OK", "baseline defect not reproduced"
    assert current.returncode != 0 and "OK" not in current.stdout.splitlines(), "checker fix regressed"
finally:
    fixture.doCleanups()
