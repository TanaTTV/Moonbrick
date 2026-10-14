"""Exercise the real grader on a disposable Moonbrick coin fixture; no model call."""
import json
from pathlib import Path
import sys
import tempfile
import os

import run
import sandbox


def main():
    batch = Path(sys.argv[1]).resolve()
    artifact = batch / 'grader-smoke'
    artifact.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='demo-', dir=batch) as directory:
        return exercise(batch, artifact, Path(directory))


def exercise(batch, artifact, temp):
    project = temp / 'demo'
    setup = run.command([sys.executable, run.ROOT / 'scripts/project.py', 'new', project, 'demo'])
    run.save(artifact / 'scaffold.json', setup)
    if setup['returncode']:
        raise RuntimeError(setup['stderr'])
    (project / 'src/server/Coins.server.luau').write_text('''--!strict
local Players = game:GetService("Players")
local PlayerData = require(game:GetService("ServerScriptService").Kit.PlayerData)
local Cooldown = require(game:GetService("ServerScriptService").Kit.Cooldown)
local Net = require(game:GetService("ReplicatedStorage").Kit.Net)
PlayerData.start({ template = { Coins = 0 }, leaderstats = { "Coins" } })
local gate = Cooldown.new()
Net.declare("CoinsChanged")
Net.on("CoinRequest", { Net.string(32) }, function(_player, _id) end)
for index = 1, 5 do
 local coin = Instance.new("Part")
 coin.Name = "Coin"
 coin.Anchored = true
 coin.Position = Vector3.new(index * 5, 2, 0)
 coin.Parent = workspace
 coin.Touched:Connect(function(hit: BasePart)
  local character = hit.Parent
  if not character or not character:IsA("Model") then return end
  local player = Players:GetPlayerFromCharacter(character)
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if not player or not humanoid or humanoid.Health <= 0 then return end
  if not gate:use(coin, 10) then return end
  local data = PlayerData.wait(player)
  if not data then return end
  local total = PlayerData.increment(player, "Coins", 1)
  Net.fire(player, "CoinsChanged", total)
  coin:Destroy()
 end)
end
''', encoding='utf-8')
    (project / 'src/client/HUD.client.luau').write_text('''--!strict
local Players = game:GetService("Players")
local UI = require(game:GetService("ReplicatedStorage").Kit.UI)
local Net = require(game:GetService("ReplicatedStorage").Kit.Net)
local player = Players.LocalPlayer
local coins = player:WaitForChild("leaderstats"):WaitForChild("Coins")
assert(coins:IsA("IntValue"))
local gui = UI.screen("CoinHUD")
local label = UI.label({parent = gui, text = "Coins: 0", size = UDim2.fromOffset(200, 50)})
local function update()
 label.Text = "Coins: " .. tostring(coins.Value)
end
Net.listen("CoinsChanged", function(count: any) label.Text = "Coins: " .. tostring(count) end)
update()
''', encoding='utf-8')
    defs = run.fetch_definitions(batch)
    std = run.prepare_selene_std(batch, run.tools()['selene'])
    config = {'project': str(project), 'root': str(run.ROOT), 'artifact': str(artifact),
              'definitions': str(defs), 'selene_std': str(std), 'tools': run.tools()}
    sandbox.preserve_project(project, artifact, run.ROOT)
    # Match provider scoring's empty home/cache, with no credential copy.
    env = dict(os.environ)
    for name in ('HOME', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME'):
        env[name] = str(temp / 'empty-home')
    run.save(artifact / 'sandbox.json', config)
    scored = run.command([sys.executable, run.HERE / 'sandbox.py', 'check', artifact / 'sandbox.json', project], env=env, timeout=180)
    run.save(artifact / 'scoring-process.json', scored)
    status = scored['returncode']
    print(scored['stdout'])
    run.save(artifact / 'summary.json', {'exit_code': status, 'scope': 'Codex-authored grader fixture, NOT a Claude benchmark run'})
    # A client must only display replicated rewards. This otherwise-valid source
    # mutation should fail authority independently of build/type/lint success.
    negative = batch / 'grader-client-reward'
    negative.mkdir()
    hud = project / 'src/client/HUD.client.luau'
    hud.write_text(hud.read_text(encoding='utf-8') + '\ncoins.Value += 1\n', encoding='utf-8')
    sandbox.preserve_project(project, negative, run.ROOT)
    run.save(negative / 'sandbox.json', dict(config, artifact=str(negative)))
    scored_negative = run.command([sys.executable, run.HERE / 'sandbox.py', 'check', negative / 'sandbox.json', project], env=env, timeout=180)
    run.save(negative / 'scoring-process.json', scored_negative)
    failed = json.loads((negative / 'score.json').read_text(encoding='utf-8'))
    run.save(negative / 'summary.json', {'scope': 'Codex-authored deliberate client-reward fixture, NOT a Claude run', 'criteria': failed['criteria']})
    print('Deliberate client reward:', json.dumps(failed['criteria']))
    if failed['criteria']['server_authority_static']:
        raise RuntimeError('client-reward fixture unexpectedly passed authority')
    return status


if __name__ == '__main__':
    sys.exit(main())
