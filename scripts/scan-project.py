"""Read-only advisory scan of imported scripts/assets. Findings are review leads, not a safety certificate."""
import argparse
import hashlib
import json
from pathlib import Path
import re

RULES = (
    ("external-require", r"\brequire\s*\(\s*\d", "Numeric asset require can execute remote code"),
    ("dynamic-code", r"\b(?:loadstring|getfenv|setfenv)\s*\(", "Dynamic code/environment manipulation requires review"),
    ("http", r"\b(?:GetAsync|PostAsync|RequestAsync|HttpGet|HttpPost)\s*\(", "Review network endpoints and transmitted data"),
    ("teleport", r"\bTeleport(?:Async|ToPlaceInstance|ToPrivateServer)?\s*\(", "Review destinations and player consent"),
    ("purchase", r"\bPrompt(?:ProductPurchase|GamePassPurchase|Purchase|BulkPurchase)\s*\(", "Review purchase prompts and server receipts"),
    ("datastore-write", r"\b(?:SetAsync|IncrementAsync|RemoveAsync|UpdateAsync)\s*\(", "Review persistence ownership, migrations and retries"),
    ("encoded-string", r"(?:\\x[0-9A-Fa-f]{2}){8}|(?:\\\d{1,3}){8}", "Encoded strings can conceal executable code"),
)


def scan(root: Path):
    files, findings = [], []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink(): continue
        rel = path.relative_to(root).as_posix()
        if rel.startswith("kit/") or "/.moonbrick/" in rel: continue
        suffix = path.suffix.lower()
        if suffix in (".lua", ".luau"):
            content = path.read_bytes()
            source = content.decode("utf-8", errors="replace")
            files.append({"path": rel, "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()})
            for identifier, pattern, reason in RULES:
                for match in re.finditer(pattern, source):
                    findings.append({"path": rel, "line": source.count("\n", 0, match.start()) + 1, "rule": identifier, "reason": reason})
        elif suffix in (".rbxm", ".rbxmx"):
            findings.append({"path": rel, "rule": "opaque-model", "reason": "Model can contain scripts; inspect in an isolated non-running place before use"})
    return {"advisory": True, "scripts": files, "findings": findings, "note": "No code was executed. Absence of flags does not establish safety; review every imported script and model before play/publish."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    report = scan(args.root)
    if args.json: print(json.dumps(report, indent=2))
    else:
        print(f"{len(report['scripts'])} scripts, {len(report['findings'])} advisory findings")
        for finding in report["findings"][:60]: print(f"{finding['path']}:{finding.get('line', '?')} {finding['rule']}: {finding['reason']}")
        print(report["note"])
