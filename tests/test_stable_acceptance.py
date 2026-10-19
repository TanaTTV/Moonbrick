"""Offline safety checks for the V1-stable evidence ledger validator."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("check_stable_acceptance", ROOT / "scripts/check-stable-acceptance.py")
_validator = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_validator)


def base():
    import json
    return json.loads((ROOT / "acceptance/v1-stable/gates.json").read_text(encoding="utf-8"))


class StableAcceptanceTests(unittest.TestCase):
    def test_checked_in_ledger_is_valid(self):
        self.assertEqual(_validator.validate(base())[0], [])

    def test_pending_ledger_is_valid_but_not_ready(self):
        data = base()
        for gate in data["gates"]:
            gate.update(status="pending", evidence=[])
            gate.pop("approved_by", None)
            gate.pop("reason", None)
        errors, counts = _validator.validate(data)
        self.assertEqual(errors, [])
        self.assertEqual(counts["pending"], len(_validator.REQUIRED_GATES))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "gates.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(_validator.main(["--release", "--file", str(path)]), 1)

    def test_missing_gate_cannot_be_removed_to_fake_readiness(self):
        data = base()
        data["gates"].pop()
        self.assertIn("missing mandatory gates", " ".join(_validator.validate(data)[0]))

    def test_pass_requires_real_record_fields(self):
        data = base()
        data["gates"][0]["status"] = "passed"
        self.assertIn("requires recorded evidence", " ".join(_validator.validate(data)[0]))
        data["gates"][0]["evidence"] = [{"reference": "review/abc", "environment": "Studio emulator",
            "result": "pass", "date": "2026-10-15"}]
        self.assertEqual(_validator.validate(data)[0], [])

    def test_waiver_requires_approval_and_reason(self):
        data = base()
        data["gates"][0]["status"] = "waived"
        data["gates"][0]["evidence"] = [{"reference": "issue/123", "environment": "owner review",
            "result": "inconclusive", "date": "2026-10-15"}]
        self.assertIn("waiver requires approved_by", " ".join(_validator.validate(data)[0]))
        data["gates"][0]["approved_by"] = "repository owner"
        data["gates"][0]["reason"] = "Deferred after evaluating risk"
        self.assertEqual(_validator.validate(data)[0], [])

    def test_bad_evidence_date_and_result_are_invalid(self):
        data = base()
        data["gates"][0]["evidence"] = [{"reference": "r", "environment": "x",
            "result": "ok", "date": "today"}]
        errors = " ".join(_validator.validate(data)[0])
        self.assertIn("date must be", errors)
        self.assertIn("invalid result", errors)

    def test_pass_with_contradicting_fail_is_invalid(self):
        data = base()
        data["gates"][0]["status"] = "passed"
        data["gates"][0]["evidence"] = [
            {"reference": "r1", "environment": "x", "result": "pass", "date": "2026-10-15"},
            {"reference": "r2", "environment": "x", "result": "fail", "date": "2026-10-15"}]
        self.assertIn("cannot include a fail result", " ".join(_validator.validate(data)[0]))

    def test_duplicates_rejected(self):
        data = base()
        data["gates"][1] = copy.deepcopy(data["gates"][0])
        self.assertIn("duplicate", " ".join(_validator.validate(data)[0]))


if __name__ == "__main__":
    unittest.main()
