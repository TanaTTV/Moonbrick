import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("scanner", ROOT / "scripts/scan-project.py")
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)


class ScanTests(unittest.TestCase):
    def test_scan_is_read_only_and_flags_imported_remote_code_and_opaque_models(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "Untrusted.server.luau"
            payload = b"-- review lead even in a comment\nrequire(1234)\nloadstring('x')\n"
            source.write_bytes(payload)
            (root / "Opaque.rbxm").write_bytes(b"opaque")
            report = scanner.scan(root)
            self.assertEqual({finding["rule"] for finding in report["findings"]}, {"external-require", "dynamic-code", "opaque-model"})
            self.assertEqual(source.read_bytes(), payload)
            self.assertTrue(report["advisory"])
            self.assertIn("does not establish safety", report["note"])


if __name__ == "__main__": unittest.main()
