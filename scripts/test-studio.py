"""Emit a Studio test bundle using isolated, unparented containers. Does not start/stop play or access persistent stores."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def bundle():
    prefix = '''
local engineGame = game
local sandbox = Instance.new("Folder")
local workspace = Instance.new("Model")
workspace.Parent = sandbox
local replication = Instance.new("Folder")
replication.Parent = sandbox
local removing = Instance.new("BindableEvent")
removing.Parent = sandbox
local services = {
    ReplicatedStorage = replication,
    Players = {PlayerRemoving = removing.Event},
    RunService = {IsServer = function() return true end, IsClient = function() return false end, IsStudio = function() return true end},
    DataStoreService = {GetDataStore = function() error("persistent store access forbidden in test bundle") end},
}
local game = {JobId = "moonbrick-isolated", GetService = function(_,name) return services[name] or engineGame:GetService(name) end}
local modules, suites = {}, {}
'''
    sources = {"PlayerData": "luau/lib/server/PlayerData.luau", "Net": "luau/lib/shared/Net.luau", "VFX": "luau/lib/shared/VFX.luau", "UI": "luau/lib/shared/UI.luau", "MCPKit": "luau/MCPKit.luau"}
    sources.update({name: f"luau/lib/server/{name}.luau" for name in ("Cooldown", "Round", "Economy")})
    sources["Rules"] = "examples/crystal-rush/src/server/Rules.luau"
    for name, rel in sources.items():
        source = (ROOT / rel).read_text(encoding="utf-8").replace("_G.K = K", "-- isolated test bundle: no global cache")
        prefix += f"modules.{name} = (function()\n{source}\nend)()\n"
    paths = sorted((ROOT / "luau/tests").glob("*.spec.luau")) + [ROOT / "examples/crystal-rush/tests/Rules.spec.luau"]
    for rel in paths:
        source = rel.read_text(encoding="utf-8")
        source = source.replace('t.require(game:GetService("ServerScriptService").Kit.PlayerData)', 'modules.PlayerData')
        source = source.replace('t.require(game:GetService("ReplicatedStorage").Kit.Net)', 'modules.Net')
        source = source.replace('t.require(game:GetService("ServerStorage").MCPKit)', 'modules.MCPKit')
        source = source.replace('t.require(game:GetService("ServerScriptService").Server.Rules)', 'modules.Rules')
        source = source.replace('local Kit = game:GetService("ReplicatedStorage").Kit', 'local Kit = modules')
        source = source.replace('local Kit = game:GetService("ServerScriptService").Kit', 'local Kit = modules')
        source = source.replace('t.require(Kit.VFX)', 'modules.VFX').replace('t.require(Kit.UI)', 'modules.UI')
        for name in ("Cooldown", "Round", "Economy"):
            source = source.replace(f't.require(Kit.{name})', f'modules.{name}')
        prefix += f"table.insert(suites, (function()\n{source}\nend)())\n"
    return prefix + '''
local passed, failed, errors = 0, 0, {}
local t = {}
function t.eq(a,b,msg) assert(a == b, (msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a)) end
function t.ok(v,msg) assert(v,msg or "expected truthy") end
function t.near(a,b,eps,msg) assert(math.abs(a-b) <= (eps or 1e-6),msg or "not near") end
function t.fails(fn,contains)
    local ok,err=pcall(fn); assert(not ok,"expected failure")
    assert(not contains or tostring(err):find(contains,1,true),tostring(err))
end
function t.test(name,fn)
    local ok,err = pcall(fn)
    if ok then passed += 1 else failed += 1; table.insert(errors,name .. ": " .. tostring(err)) end
end
for _,suite in suites do
    local ok,err = pcall(suite,t)
    if not ok then failed += 1; table.insert(errors,tostring(err)) end
end
-- Actual engine instances were never parented to the live place.
sandbox:Destroy()
return string.format("%d passed, %d failed (isolated Studio engine tests; memory stores)",passed,failed) .. (#errors > 0 and "\\n" .. table.concat(errors,"\\n") or "")
'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(bundle(), encoding="utf-8", newline="\n")
