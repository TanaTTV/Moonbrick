"""Exercise the real grader on a disposable Moonbrick coin fixture; no model call."""
import json
from pathlib import Path
import sys
import tempfile
import contextlib
import io

import run
import sandbox


def main():
    batch = Path(sys.argv[1]).resolve()
    temp = Path(tempfile.mkdtemp(prefix='moonbrick-bench-smoke-'))
    project = temp / 'project'
    artifact = batch / 'grader-smoke'
    artifact.mkdir(parents=True, exist_ok=True)
    setup = run.command([sys.executable, run.ROOT / 'scripts/project.py', 'new', project, 'BenchSmoke'])
    run.save(artifact / 'scaffold.json', setup)
    if setup['returncode']:
        raise RuntimeError(setup['stderr'])
    (project / 'src/server/Coins.server.luau').write_text('''--!strict
local Players = game:GetService("Players")
local PlayerData = require(game:GetService("ServerScriptService").Kit.PlayerData)
PlayerData.start({ template = { Coins = 0 }, leaderstats = { "Coins" } })
for index = 1, 5 do
 local coin = Instance.new("Part")
 coin.Name = "Coin"
 coin.Anchored = true
 coin.Position = Vector3.new(index * 5, 2, 0)
 coin.Parent = workspace
 local collected = false
 coin.Touched:Connect(function(hit: BasePart)
  local character = hit.Parent
  if not character or not character:IsA("Model") then return end
  local player = Players:GetPlayerFromCharacter(character)
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if not player or not humanoid or humanoid.Health <= 0 or collected then return end
  local data = PlayerData.wait(player)
  if not data then return end
  collected = true
  PlayerData.increment(player, "Coins", 1)
  coin:Destroy()
 end)
end
''', encoding='utf-8')
    (project / 'src/client/HUD.client.luau').write_text('''--!strict
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local coins = player:WaitForChild("leaderstats"):WaitForChild("Coins")
assert(coins:IsA("IntValue"))
local gui = Instance.new("ScreenGui")
gui.Name = "CoinHUD"
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(200, 50)
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")
local function update()
 label.Text = "Coins: " .. tostring(coins.Value)
end
coins:GetPropertyChangedSignal("Value"):Connect(update)
update()
''', encoding='utf-8')
    defs = run.fetch_definitions(batch)
    config = {'project': str(project), 'root': str(run.ROOT), 'artifact': str(artifact),
              'definitions': str(defs), 'tools': run.tools()}
    with contextlib.redirect_stdout(io.StringIO()):
        status = sandbox.check(config, project)
    print((artifact / 'score.json').read_text())
    run.save(artifact / 'summary.json', {'exit_code': status, 'scope': 'Codex-authored grader fixture, NOT a Claude benchmark run'})
    return status


if __name__ == '__main__':
    sys.exit(main())
