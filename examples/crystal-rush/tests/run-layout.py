"""Run the example's pure HUD layout specs without changing the shared headless harness."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", type=Path, required=True)
    args = parser.parse_args()
    example = Path(__file__).resolve().parents[1]
    module = (example / "src/shared/HUDLayout.luau").read_text(encoding="utf-8")
    suite = (example / "tests/HUDLayout.spec.luau").read_text(encoding="utf-8")
    harness = '''
local game = { GetService = function(_, name)
    assert(name == "ReplicatedStorage")
    return { Shared = { HUDLayout = "HUDLayout" } }
end }
local passed, failed = 0, 0
local t = {}
function t.require(name) assert(name == "HUDLayout"); return layout end
function t.eq(actual, expected, message)
    assert(actual == expected, (message or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
function t.ok(value, message) assert(value, message or "expected truthy") end
function t.test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed += 1 else failed += 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
'''
    code = "local layout = (function()\n" + module + "\nend)()\n" + harness
    code += "local suite = (function()\n" + suite + "\nend)()\nsuite(t)\n"
    code += 'print(string.format("%d layout specs passed, %d failed (headless)", passed, failed))\nassert(failed == 0)\n'
    with tempfile.TemporaryDirectory() as tmp:
        file = Path(tmp) / "layout.luau"
        file.write_text(code, encoding="utf-8", newline="\n")
        result = subprocess.run([str(args.luau.resolve()), str(file)], timeout=60)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
