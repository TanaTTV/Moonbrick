"""Run shipped Luau specs with a pinned Luau CLI and a small deterministic store harness."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def bundle():
    module = (ROOT / "luau/lib/server/PlayerData.luau").read_text(encoding="utf-8")
    suite = (ROOT / "luau/tests/PlayerData.spec.luau").read_text(encoding="utf-8")
    code = "loadPlayerData = function()\n" + module + "\nend\nmodules = { PlayerData = loadPlayerData() }\n"
    net = (ROOT / "luau/lib/shared/Net.luau").read_text(encoding="utf-8")
    net_suite = (ROOT / "luau/tests/Net.spec.luau").read_text(encoding="utf-8")
    code += "loadNet = function(game, Instance, os, warn)\n" + net + "\nend\n"
    code += "services.ReplicatedStorage = { Kit = { Net = 'Net' } }\n"
    code += "modules.Net = loadNet(game, Instance, os, warn)\n"
    for name in ("Cooldown", "Round", "Economy"):
        source = (ROOT / f"luau/lib/server/{name}.luau").read_text(encoding="utf-8")
        code += f"modules.{name} = (function()\n{source}\nend)()\nservices.ServerScriptService.Kit.{name} = '{name}'\n"
    gameplay = (ROOT / "luau/tests/Gameplay.spec.luau").read_text(encoding="utf-8")
    rules = (ROOT / "examples/crystal-rush/src/server/Rules.luau").read_text(encoding="utf-8")
    rules_spec = (ROOT / "examples/crystal-rush/tests/Rules.spec.luau").read_text(encoding="utf-8")
    code += "modules.Rules = (function()\n" + rules + "\nend)()\nservices.ServerScriptService.Server = { Rules = 'Rules' }\n"
    # Element Brawl's rules/elements are pure; its spec's Studio paths map to these module keys.
    brawl = ROOT / "examples/element-brawl"
    code += "modules.BrawlRules = (function()\n" + (brawl / "src/server/Rules.luau").read_text(encoding="utf-8") + "\nend)()\n"
    code += "modules.BrawlElements = (function()\n" + (brawl / "src/shared/Elements.luau").read_text(encoding="utf-8") + "\nend)()\n"
    brawl_spec = (brawl / "tests/Rules.spec.luau").read_text(encoding="utf-8")
    brawl_spec = brawl_spec.replace('game:GetService("ServerScriptService").Server.Rules', '"BrawlRules"')
    brawl_spec = brawl_spec.replace('game:GetService("ReplicatedStorage").Shared.Elements', '"BrawlElements"')
    code += "suites = {(function()\n" + suite + "\nend)(), (function()\n" + gameplay + "\nend)(), (function()\n" + rules_spec + "\nend)(), (function()\n" + net_suite + "\nend)(), (function()\n" + brawl_spec + "\nend)()}\n"
    return (ROOT / "tests/headless.luau").read_text(encoding="utf-8").replace("-- MODULES --", code)


def studio_bundle():
    # Inline trusted source; use memory stores only. No scripts/instances are parented to the place.
    module = (ROOT / "luau/lib/server/PlayerData.luau").read_text(encoding="utf-8")
    suite = (ROOT / "luau/tests/PlayerData.spec.luau").read_text(encoding="utf-8")
    suite = suite.replace('t.require(game:GetService("ServerScriptService").Kit.PlayerData)', "PlayerData")
    helpers = '''
local passed, failed, errors = 0, 0, {}
local t = {}
function t.eq(a,b,msg) assert(a == b, (msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a)) end
function t.ok(v,msg) assert(v,msg or "expected truthy") end
function t.fails(fn,contains)
    local ok,err = pcall(fn); assert(not ok,"expected failure")
    assert(not contains or tostring(err):find(contains,1,true),tostring(err))
end
function t.test(name,fn)
    local ok,err = pcall(fn)
    if ok then passed += 1 else failed += 1; table.insert(errors,name .. ": " .. tostring(err)) end
end
suite(t)
return string.format("%d passed, %d failed (Studio, memory stores only)",passed,failed) .. (#errors > 0 and "\\n" .. table.concat(errors,"\\n") or "")
'''
    return "local PlayerData = (function()\n" + module + "\nend)()\nlocal suite = (function()\n" + suite + "\nend)()\n" + helpers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", default=shutil.which("luau"))
    parser.add_argument("--studio-script", type=Path, help="write a memory-only session test for execute_luau")
    args = parser.parse_args()
    if args.studio_script:
        args.studio_script.parent.mkdir(parents=True, exist_ok=True)
        args.studio_script.write_text(studio_bundle(), encoding="utf-8", newline="\n")
        return
    if not args.luau:
        parser.error("Luau CLI required; use scripts/fetch-luau.py or --luau <path>")
    with tempfile.TemporaryDirectory() as tmp:
        file = Path(tmp) / "headless.luau"
        file.write_text(bundle(), encoding="utf-8", newline="\n")
        result = subprocess.run([str(Path(args.luau).resolve()), str(file)], timeout=60)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
