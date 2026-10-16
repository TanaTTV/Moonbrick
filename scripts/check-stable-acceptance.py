"""Report V1-stable human acceptance gates; never claims engine tests were run.

Only validates evidence *recording*, not the accuracy of externally supplied logs.
Default reporting always exits 0 for a valid pending ledger; --release exits 1
until every mandatory gate is passed or explicitly waived by the owner.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / "acceptance/v1-stable/gates.json"
REQUIRED_GATES = frozenset({
    "device-emulator-touch", "device-gamepad", "device-physical-performance",
    "streaming-streamout", "blender-studio-static-pbr", "blender-studio-rig-animation",
    "terrain-import", "datastore-engine-shutdown-restart",
    "datastore-natural-lock-expiry", "datastore-independent-servers",
    "datastore-provider-failures", "datastore-forced-disconnect",
    "plugin-interactive-reload",
})
STATUSES = frozenset({"pending", "passed", "failed", "waived"})
DATE = re.compile(r"^20\d\d-\d\d-\d\d$")


def validate(data):
    """Return validation errors and a Counter of recorded gate states."""
    errors = []
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        return ["expected JSON object with schema_version=1"], Counter()
    if data.get("baseline") != "v1.0.0-beta.1":
        errors.append("baseline must be v1.0.0-beta.1")
    gates = data.get("gates")
    if not isinstance(gates, list):
        return errors + ["gates must be an array"], Counter()
    ids = [gate.get("id") for gate in gates if isinstance(gate, dict)]
    missing, extra = REQUIRED_GATES - set(ids), set(ids) - REQUIRED_GATES
    if missing:
        errors.append("missing mandatory gates: " + ", ".join(sorted(missing)))
    if extra:
        errors.append("unknown gates: " + ", ".join(sorted(str(x) for x in extra)))
    if len(ids) != len(set(ids)) or len(ids) != len(gates):
        errors.append("duplicate or malformed gate entries")
    counts = Counter()
    for index, gate in enumerate(gates):
        if not isinstance(gate, dict):
            continue
        label = gate.get("id", f"row-{index}")
        status = gate.get("status")
        if status not in STATUSES:
            errors.append(f"{label}: invalid status")
            continue
        counts[status] += 1
        evidence = gate.get("evidence")
        if not isinstance(evidence, list):
            errors.append(f"{label}: evidence must be an array")
            continue
        if status in ("passed", "waived") and not evidence:
            errors.append(f"{label}: {status} requires recorded evidence")
        if status == "waived":
            if not isinstance(gate.get("approved_by"), str) or not gate["approved_by"].strip():
                errors.append(f"{label}: waiver requires approved_by")
            if not isinstance(gate.get("reason"), str) or not gate["reason"].strip():
                errors.append(f"{label}: waiver requires reason")
        if status == "passed" and gate.get("approved_by"):
            errors.append(f"{label}: approved_by is reserved for waivers")
        for n, record in enumerate(evidence):
            if not isinstance(record, dict):
                errors.append(f"{label}: evidence {n} must be an object")
                continue
            for field in ("reference", "environment", "result", "date"):
                if not isinstance(record.get(field), str) or not record[field].strip():
                    errors.append(f"{label}: evidence {n} missing {field}")
            if "date" in record and isinstance(record["date"], str) and not DATE.fullmatch(record["date"]):
                errors.append(f"{label}: evidence {n} date must be YYYY-MM-DD")
            if record.get("result") not in ("pass", "fail", "inconclusive"):
                errors.append(f"{label}: evidence {n} invalid result")
        if status == "passed" and evidence and not any(isinstance(e, dict) and e.get("result") == "pass" for e in evidence):
            errors.append(f"{label}: passed requires a pass result")
        if status == "passed" and any(isinstance(e, dict) and e.get("result") == "fail" for e in evidence):
            errors.append(f"{label}: passed cannot include a fail result")
    return errors, counts


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, default=DEFAULT)
    parser.add_argument("--release", action="store_true", help="fail if V1 stable gates remain open")
    args = parser.parse_args(argv)
    try:
        data = json.loads(args.file.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"INVALID acceptance ledger: {exc}", file=sys.stderr)
        return 2
    errors, counts = validate(data)
    if errors:
        for error in errors:
            print(f"INVALID: {error}", file=sys.stderr)
        return 2
    for gate in data["gates"]:
        print(f"{gate['status'].upper():7} {gate['id']}")
    ready = counts["pending"] == 0 and counts["failed"] == 0
    print(f"V1 stable gates: {counts['passed']} passed, {counts['waived']} waived, "
          f"{counts['pending']} pending, {counts['failed']} failed. "
          f"Record review: {'READY' if ready else 'NOT READY'}")
    print("Evidence references are not independently verified by this script.")
    if args.release and not ready:
        print("Stable release gate is BLOCKED; beta remains unaffected.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
