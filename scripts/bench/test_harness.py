"""Boundary tests: never launch Claude or read authentication files."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run
import sandbox


class Boundaries(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.project = self.root / 'project'
        self.project.mkdir()
        self.artifact = self.root / 'artifacts'
        self.artifact.mkdir()
        self.config = {'project': str(self.project), 'root': str(run.ROOT),
                       'artifact': str(self.artifact), 'condition': 'B', '_path': str(self.root / 'sandbox.json')}

    def tearDown(self):
        self.temp.cleanup()

    def decision(self, name, args):
        data = {'tool_name': name, 'tool_input': args, 'cwd': str(self.project)}
        with patch('sys.stdin', io.StringIO(json.dumps(data))), contextlib.redirect_stdout(io.StringIO()) as output:
            sandbox.hook(self.config)
        return json.loads(output.getvalue())['hookSpecificOutput']['permissionDecision']

    def test_file_write_boundary(self):
        self.assertEqual(self.decision('Write', {'file_path': str(self.project / 'src/game.server.luau')}), 'allow')
        for target in (self.root / 'escape.lua', run.ROOT / 'CHANGELOG.md', self.project / '.claude/settings.json', self.project / '.Claude/settings.json', self.project / '.git/config'):
            self.assertEqual(self.decision('Write', {'file_path': str(target)}), 'deny')

    def test_shell_boundary(self):
        command = f'python "{Path(sandbox.__file__).as_posix()}" check "{self.config["_path"]}" "."'
        self.assertEqual(self.decision('Bash', {'command': command}), 'allow')
        for text in (command + '; echo escape', 'python -c "print(1)"', 'bash tools/setup.sh', 'rm -rf ~', 'git push', command + ' > escape'):
            self.assertEqual(self.decision('Bash', {'command': text}), 'deny')

    def test_baseline_cannot_read_plugin(self):
        target = str(run.ROOT / 'skills/new/SKILL.md')
        self.assertEqual(self.decision('Read', {'file_path': target}), 'deny')
        self.config['condition'] = 'A'
        self.assertEqual(self.decision('Read', {'file_path': target}), 'allow')

    def test_plugin_inventory_required(self):
        clean = {'plugins': [], 'skills': [], 'slash_commands': [], 'mcp_servers': [], 'tools': ['Read', 'Write']}
        self.assertTrue(run.isolation(clean, 'B')[0])
        for changed in ({'plugins': [{'name': 'moonbrick'}]}, {'skills': ['moonbrick:new']},
                        {'mcp_servers': [{'name': 'Studio'}]}, {'tools': ['mcp__Studio__execute']}, {'plugins': None}):
            self.assertFalse(run.isolation(dict(clean, **changed), 'B')[0])
        self.assertFalse(run.isolation(dict(clean, plugins=[{'name': 'moonbrick', 'path': str(self.root)}], skills=['moonbrick:new']), 'A')[0])
        self.assertTrue(run.isolation(dict(clean, plugins=[{'name': 'moonbrick', 'path': str(run.ROOT)}], skills=['moonbrick:new']), 'A')[0])

    def test_accounting_missing_stays_missing(self):
        run.summarize(self.artifact, [{'condition': 'B', 'repetition': 1, 'status': 'blocked'}])
        self.assertIn('not reported', (self.artifact / 'summary.md').read_text())
        medians = json.loads((self.artifact / 'medians.json').read_text())
        self.assertIsNone(medians['B']['total_cost_usd'])

    def test_download_stops_after_two_transports(self):
        with patch('run.urllib.request.urlopen', side_effect=OSError('blocked')), patch('run.shutil.which', return_value='curl'), patch('run.command', return_value={'returncode': 22}) as fallback:
            with self.assertRaises(RuntimeError):
                run.fetch_definitions(self.artifact)
        fallback.assert_called_once()
        data = json.loads((self.artifact / 'definitions.json').read_text())
        self.assertEqual(len(data['attempts']), 2)
        self.assertFalse(data['success'])

    def test_static_reward_boundary(self):
        server = self.project / 'Game.server.luau'
        client = self.project / 'HUD.client.luau'
        server.write_text('''local coins = Instance.new("Part")
coins.Touched:Connect(function(hit)
 local player = Players:GetPlayerFromCharacter(hit.Parent)
 local humanoid = hit.Parent:FindFirstChild("Humanoid")
 if player and humanoid and not collected then
  collected = true
  player.Coins.Value += 1
  coins:Destroy()
 end
end)
local store = DataStoreService:GetDataStore("Coins")
store:GetAsync("key")
store:UpdateAsync("key", function() end)
Players.PlayerRemoving:Connect(save)
game:BindToClose(save)
''')
        client.write_text('''local gui = Instance.new("ScreenGui")
local label = Instance.new("TextLabel")
gui.Parent = player.PlayerGui
player.Coins.Changed:Connect(function(count) label.Text = "Coins " .. count end)
''')
        def tree():
            return {'name': 'game', 'children': [
                {'name': 'ServerScriptService', 'children': [{'name': 'Game', 'className': 'Script', 'filePaths': [str(server)]}]},
                {'name': 'StarterPlayer', 'children': [{'name': 'HUD', 'className': 'LocalScript', 'filePaths': [str(client)]}]}]}
        criteria, _ = sandbox.static_score(self.project, tree(), run.ROOT)
        self.assertTrue(all(criteria.values()))
        client.write_text(client.read_text() + '\nplayer.Coins.Value += 1\n')
        criteria, _ = sandbox.static_score(self.project, tree(), run.ROOT)
        self.assertFalse(criteria['server_authority_static'])
        client.write_text('-- player.Coins.Value += 1\n')
        criteria, _ = sandbox.static_score(self.project, tree(), run.ROOT)
        self.assertTrue(criteria['server_authority_static'])
        self.assertFalse(criteria['hud_static'])
        server.write_text('--' + server.read_text().replace('\n', '\n--'))
        criteria, _ = sandbox.static_score(self.project, tree(), run.ROOT)
        self.assertFalse(criteria['persistence_static'])
        self.assertFalse(criteria['coin_touch_static'])

    def test_strict_scope_cannot_be_empty(self):
        self.config['definitions'] = str(self.root / 'defs.luau')
        Path(self.config['definitions']).write_text('')
        self.config['tools'] = {name: 'unused' for name in ('rojo', 'luau-lsp', 'selene')}
        (self.project / 'default.project.json').write_text('{"name":"Empty","tree":{"$className":"DataModel"}}')
        with patch('sandbox.invoke', return_value={'returncode': 0}), contextlib.redirect_stdout(io.StringIO()):
            sandbox.check(self.config, self.project)
        score = json.loads((self.artifact / 'score.json').read_text())
        self.assertFalse(score['criteria']['strict_types'])
        self.assertFalse(score['criteria']['all_criteria'])


if __name__ == '__main__':
    unittest.main()
