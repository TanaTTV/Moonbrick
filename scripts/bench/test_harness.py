"""Boundary tests: never launch Claude or read authentication files."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import shutil
import unittest
from unittest.mock import patch

import run
import sandbox
import report


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

    def test_plugin_scaffold_flow_a_and_e_only(self):
        script = (run.ROOT / 'scripts/new-project.sh').as_posix()
        command = f'bash "{script}" "demo" "demo" --no-tools'
        for condition in ('A', 'E'):
            self.config['condition'] = condition
            self.assertEqual(self.decision('Read', {'file_path': str(run.ROOT / 'skills/new/SKILL.md')}), 'allow')
            self.assertEqual(self.decision('Read', {'file_path': self.config['_path']}), 'deny')
            self.assertEqual(self.decision('Bash', {'command': command}), 'allow')
            for bad in (command.replace('--no-tools', ''), command.replace('"demo" "demo"', '"../escape" "demo"'),
                        command + ' && curl example.com', command.replace('"demo" --no-tools', '"--no-tools" --no-tools')):
                self.assertEqual(self.decision('Bash', {'command': bad}), 'deny')
        self.config['condition'] = 'B'
        self.assertEqual(self.decision('Bash', {'command': command}), 'deny')

    def test_e_prompt_command_and_isolation_match_a(self):
        spec = {'cli': ['provider-must-not-run'], 'tools': {}, 'selene_std': 'std'}
        # Dry construction must neither launch a provider nor copy credentials.
        with patch('run.subprocess.Popen', side_effect=AssertionError('provider called')), \
             patch('run.shutil.copyfile', side_effect=AssertionError('credentials copied')):
            for condition in ('A', 'E', 'B'):
                run.run_one(self.artifact, spec, condition, 1, 'sonnet', 8, dry_run=True)
        a, e, b = [json.loads((self.artifact / f'{condition}1/command.json').read_text()) for condition in ('A', 'E', 'B')]
        for item in (a, e):
            self.assertEqual(item['argv'][item['argv'].index('--plugin-dir') + 1], str(run.ROOT))
        self.assertNotIn('--plugin-dir', b['argv'])
        # Temp paths differ; after substitution E adds exactly the requested sentence.
        a_prompt = a['argv'][a['argv'].index('-p') + 1].replace(a['temp'].replace('\\', '/'), '<temp>')
        e_prompt = e['argv'][e['argv'].index('-p') + 1].replace(e['temp'].replace('\\', '/'), '<temp>')
        self.assertEqual(e_prompt, run.EXPLICIT_USE + '\n' + a_prompt)
        inventory = {'plugins': [{'name': 'moonbrick', 'path': str(run.ROOT)}], 'skills': ['moonbrick:new'],
                     'slash_commands': [], 'mcp_servers': [], 'tools': ['Skill']}
        self.assertEqual(run.isolation(inventory, 'E'), run.isolation(inventory, 'A'))
        self.assertEqual(run.trial_order(['E'], 3), [('E', 1), ('E', 2), ('E', 3)])

    def test_resolved_constant_reward_server_and_client(self):
        config = 'local Config = {\n COIN_VALUE = 1,\n}\nreturn Config\n'
        base = self.kit_coin().replace('PlayerData.increment(player, "Coins", 1)', 'coinsValue.Value += Config.COIN_VALUE')
        base = 'local Config = require(ReplicatedStorage.Shared)\n' + base
        for reward in ('coinsValue.Value += Config.COIN_VALUE', 'coinsValue.Value = coinsValue.Value + Config.COIN_VALUE',
                       'coinsValue.Value += COIN_VALUE'):
            with self.subTest(reward=reward):
                source = base.replace('coinsValue.Value += Config.COIN_VALUE', reward)
                if '+= COIN_VALUE' in reward:
                    source = source.replace('\n', '\nlocal COIN_VALUE = Config.COIN_VALUE\n', 1)
                criteria, evidence = self.feature(source, self.kit_hud(), config)
                self.assertTrue(criteria['server_authority_static'], evidence)
                self.assertTrue(criteria['coin_touch_static'])
                client = 'local Config = require(ReplicatedStorage.Shared)\nlocal COIN_VALUE = Config.COIN_VALUE\n' + reward
                criteria, evidence = self.feature(source, client, config)
                self.assertFalse(criteria['server_authority_static'], evidence)
                self.assertTrue(evidence['client_reward'])
        for bad_config in (config.replace('= 1,', '= 2,'), config.replace('= 1,', '= 1 + 2,'),
                           config.replace('return Config', 'Config.COIN_VALUE = 2\nreturn Config'), ''):
            self.assertFalse(self.feature(base, '', bad_config)[0]['coin_touch_static'])
        self.assertTrue(self.feature('local COIN_VALUE = 1\n' + base.replace('Config.COIN_VALUE', 'COIN_VALUE'))[0]['coin_touch_static'])
        self.assertFalse(self.feature('local COIN_VALUE = 1\nCOIN_VALUE = 2\n' + base.replace('Config.COIN_VALUE', 'COIN_VALUE'))[0]['coin_touch_static'])

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
        self.config['selene_std'] = str(self.root / 'roblox.yml')
        Path(self.config['selene_std']).write_text('name: roblox\n')
        self.config['tools'] = {name: 'unused' for name in ('rojo', 'luau-lsp', 'selene')}
        (self.project / 'default.project.json').write_text('{"name":"Empty","tree":{"$className":"DataModel"}}')
        with patch('sandbox.invoke', return_value={'returncode': 0}), contextlib.redirect_stdout(io.StringIO()):
            sandbox.check(self.config, self.project)
        score = json.loads((self.artifact / 'score.json').read_text())
        self.assertFalse(score['criteria']['strict_types'])
        self.assertFalse(score['criteria']['all_criteria'])

    def feature(self, server_text, client_text='', shared_text=''):
        nodes = []
        for service, filename, class_name, text in (
            ('ServerScriptService', 'Game.server.luau', 'Script', server_text),
            ('StarterPlayer', 'HUD.client.luau', 'LocalScript', client_text),
            ('ReplicatedStorage', 'Shared.luau', 'ModuleScript', shared_text)):
            file = self.project / filename
            file.write_text(text, encoding='utf-8')
            nodes.append({'name': service, 'children': [{'name': filename, 'className': class_name, 'filePaths': [str(file)]}]})
        data = self.project / 'PlayerData.luau'
        shutil.copyfile(run.ROOT / 'luau/lib/server/PlayerData.luau', data)
        nodes[0]['children'].append({'name': 'PlayerData', 'className': 'ModuleScript', 'filePaths': [str(data)]})
        return sandbox.static_score(self.project, {'name': 'game', 'children': nodes}, run.ROOT)

    def kit_coin(self):
        return '''local PlayerData = require(ServerScriptService.Kit.PlayerData)
PlayerData.start({template = {Coins = 0}})
local coin = Instance.new("Part")
local claimed = {}
coin.Touched:Connect(function(hit)
 local player = Players:GetPlayerFromCharacter(hit.Parent)
 local humanoid = hit.Parent:FindFirstChild("Humanoid")
 if not player or not humanoid or claimed[coin] then return end
 claimed[coin] = true
 local data = PlayerData.wait(player)
 PlayerData.increment(player, "Coins", 1)
end)
Net.on("CollectCoin", {Net.string(32)}, function(player, id) end)
'''

    def kit_hud(self):
        return '''local gui = UI.screen("Coins")
local label = UI.label({parent = gui, text = "Coins: 0"})
Net.listen("CoinsChanged", function(count) label.Text = "Coins: " .. count end)
'''

    def test_kit_and_plain_static_equivalence(self):
        criteria, evidence = self.feature(self.kit_coin(), self.kit_hud())
        self.assertTrue(all(criteria.values()), (criteria, evidence))
        self.assertTrue(evidence['remote_guard'])
        self.assertTrue(evidence['configured_playerdata'])
        self.assertIn('PlayerData.luau', evidence['stock_files_excluded'])

    def test_boolean_and_cooldown_debounce_need_guard_and_use(self):
        base = self.kit_coin().replace('claimed[coin]', 'busy')
        for flag in ('busy', 'collected', 'available', 'debounce'):
            with self.subTest(flag=flag):
                self.assertTrue(self.feature(base.replace('busy', flag))[0]['server_authority_static'])
        gated = self.kit_coin().replace('local claimed = {}', 'local gate = Cooldown.new()').replace(
            'if not player or not humanoid or claimed[coin] then return end\n claimed[coin] = true',
            'if not player or not humanoid then return end\n if not gate:use(coin, 10) then return end')
        self.assertTrue(self.feature(gated)[0]['server_authority_static'])
        assigned = gated.replace('if not gate:use(coin, 10) then', 'local allowed = gate:use(coin, 10)\n if not allowed then')
        self.assertTrue(self.feature(assigned)[0]['server_authority_static'])
        for bad in (gated.replace('if not gate:use(coin, 10) then return end', ''),
                    gated.replace('if not gate:use(coin, 10) then return end', 'gate:use(coin, 10)'),
                    gated.replace('coin, 10', 'coin, 0'),
                    self.kit_coin().replace('or claimed[coin]', '').replace('claimed[coin] = true', 'coin:Destroy()'),
                    self.kit_coin().replace('claimed[coin] = true', 'local unused = true')):
            with self.subTest(source=bad):
                self.assertFalse(self.feature(bad)[0]['server_authority_static'])

    def test_remote_validator_is_in_registration_and_every_handler(self):
        source = self.kit_coin()
        for validator in ('string(32)', 'number(0, 1)', 'int(0, 1)', 'boolean()', 'vector3(10)', 'instance("Part", workspace)', 'oneOf("coin")'):
            with self.subTest(validator=validator):
                self.assertTrue(self.feature(source.replace('string(32)', validator))[0]['server_authority_static'])
        for bad in (source.replace('{Net.string(32)}', '{}'),
                    source.replace('{Net.string(32)}', '{}') + '\nlocal unused = Net.string(32)',
                    source + '\nNet.on("Other", {}, function() end)',
                    source + '\nremote.OnServerEvent:Connect(function() end)'):
            with self.subTest(source=bad):
                self.assertFalse(self.feature(bad)[0]['server_authority_static'])
        plain = source.replace('Net.on("CollectCoin", {Net.string(32)}, function(player, id) end)',
                               'remote.OnServerEvent:Connect(function(player, id)\n if typeof(id) ~= "string" then return end\nend)')
        self.assertTrue(self.feature(plain)[0]['server_authority_static'])
        self.assertFalse(self.feature(plain.replace('if typeof(id) ~= "string" then return end', ''))[0]['server_authority_static'])

    def test_client_and_shared_reward_fail_both_idioms(self):
        for reward in ('player.Coins.Value += 1', 'PlayerData.increment(player, "Coins", 1)',
                       'coins[player] += 1', 'setCoins(player, current + 1)'):
            with self.subTest(reward=reward):
                self.assertFalse(self.feature(self.kit_coin(), self.kit_hud() + '\n' + reward)[0]['server_authority_static'])
                self.assertFalse(self.feature(self.kit_coin(), '', reward)[0]['server_authority_static'])
        for amount in ('2', 'amount'):
            self.assertFalse(self.feature(self.kit_coin().replace('"Coins", 1', '"Coins", ' + amount))[0]['server_authority_static'])
        self.assertTrue(self.feature(self.kit_coin().replace('"Coins", 1', 'Config.COIN_KEY, 1'))[0]['server_authority_static'])
        self.assertFalse(self.feature(self.kit_coin().replace('"Coins", 1', '"XP", 1'))[0]['server_authority_static'])

    def test_hud_needs_components_and_live_count_updates(self):
        for bad in (self.kit_hud().replace('UI.screen("Coins")', 'nil'),
                    self.kit_hud().replace('UI.label', 'UI.panel'),
                    self.kit_hud().replace('Net.listen', 'Net.on'),
                    'local gui = UI.screen("Coins")\nlocal label = UI.label({text = "Coins"})',
                    '-- ' + self.kit_hud().replace('\n', '\n-- ')):
            with self.subTest(source=bad):
                self.assertFalse(self.feature(self.kit_coin(), bad)[0]['hud_static'])
        self.assertFalse(self.feature(self.kit_coin(), 'local gui = Instance.new("ScreenGui")\nlocal label = Instance.new("TextLabel")\nlabel.Text = "Coins"')[0]['hud_static'])

    def test_plain_no_debounce_and_client_reward_fail_authority(self):
        server = '''local coin = Instance.new("Part")
coin.Touched:Connect(function(hit)
 local player = Players:GetPlayerFromCharacter(hit.Parent)
 local humanoid = hit.Parent:FindFirstChild("Humanoid")
 if not player or not humanoid then return end
 player.Coins.Value += 1
 coin:Destroy()
end)
'''
        self.assertFalse(self.feature(server)[0]['server_authority_static'])
        guarded = server.replace('if not player or not humanoid then return end',
                                 'if not player or not humanoid or collected then return end\n collected = true')
        self.assertTrue(self.feature(guarded)[0]['server_authority_static'])
        self.assertFalse(self.feature(guarded, 'player.Coins.Value += 1')[0]['server_authority_static'])

    def test_kit_persistence_rejects_memory_and_uncalled_library(self):
        self.assertFalse(self.feature(self.kit_coin().replace('template =', 'forceMemory = true, template ='))[0]['persistence_static'])
        self.assertFalse(self.feature(self.kit_coin().replace('PlayerData.start({template = {Coins = 0}})', ''))[0]['persistence_static'])
        self.assertFalse(self.feature('')[0]['persistence_static'])

    def test_snapshot_roundtrip_preserves_custom_sources_and_hashes_kit(self):
        (self.project / 'src').mkdir()
        (self.project / 'tests').mkdir()
        (self.project / 'src/Game.luau').write_text('custom reward')
        (self.project / 'tests/Game.spec.luau').write_text('custom tests')
        (self.project / 'default.project.json').write_text('{}')
        (self.project / 'src/UI.luau').write_bytes((run.ROOT / 'luau/lib/shared/UI.luau').read_bytes())
        (self.project / 'globalTypes.d.luau').write_text('large downloaded file')
        manifest = sandbox.preserve_project(self.project, self.artifact, run.ROOT)
        self.assertEqual(manifest['files']['src/UI.luau']['storage'], 'kit')
        self.assertEqual(manifest['files']['globalTypes.d.luau']['storage'], 'excluded_generated')
        self.assertFalse((self.artifact / 'project-source/src/UI.luau').exists())
        restored = sandbox.restore_project(self.artifact, self.root / 'restored', run.ROOT)
        for name in ('src/Game.luau', 'tests/Game.spec.luau', 'default.project.json', 'src/UI.luau'):
            self.assertEqual((restored / name).read_bytes(), (self.project / name).read_bytes())
        (self.artifact / 'project-source/src/Game.luau').write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            sandbox.restore_project(self.artifact, self.root / 'tampered', run.ROOT)

    def test_snapshot_refuses_path_escape_and_changed_kit(self):
        (self.project / 'UI.luau').write_bytes((run.ROOT / 'luau/lib/shared/UI.luau').read_bytes())
        manifest = sandbox.preserve_project(self.project, self.artifact, run.ROOT)
        manifest['files']['UI.luau']['sha256'] = 'changed'
        run.save(self.artifact / 'project-manifest.json', manifest)
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            sandbox.restore_project(self.artifact, self.root / 'restored', run.ROOT)
        manifest['files'] = {'../escape': {'storage': 'source', 'sha256': 'anything'}}
        run.save(self.artifact / 'project-manifest.json', manifest)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            sandbox.restore_project(self.artifact, self.root / 'restored', run.ROOT)

    def test_selene_std_capture_and_verification_are_isolated(self):
        cache = self.root / 'cache/selene'
        cache.mkdir(parents=True)
        (cache / 'roblox.yml').write_text('name: roblox\n')
        with patch.dict(os.environ, {'LOCALAPPDATA': str(cache.parent)}), patch('run.command', return_value={'returncode': 0}) as cmd, contextlib.redirect_stdout(io.StringIO()):
            std = run.prepare_selene_std(self.artifact, 'selene')
        self.assertEqual(std.read_bytes(), (cache / 'roblox.yml').read_bytes())
        self.assertNotEqual(cmd.call_args.kwargs['env']['LOCALAPPDATA'], str(cache.parent))
        self.assertEqual(cmd.call_count, 1)
        self.assertTrue(json.loads((self.artifact / 'selene-std.json').read_text())['success'])

    def test_selene_std_failure_stops_without_retries(self):
        with patch.dict(os.environ, {'LOCALAPPDATA': str(self.root / 'absent')}), patch('run.command', return_value={'returncode': 1}) as cmd:
            with self.assertRaisesRegex(RuntimeError, 'unavailable'):
                run.prepare_selene_std(self.artifact, 'selene')
        self.assertEqual(cmd.call_count, 1)

    def test_captured_selene_std_cannot_silently_change(self):
        (self.artifact / 'roblox.yml').write_text('new std')
        run.save(self.artifact / 'selene-std.json', {'attempts': [], 'sha256': 'old hash'})
        with patch('run.command') as cmd:
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                run.prepare_selene_std(self.artifact, 'selene')
        cmd.assert_not_called()

    def test_report_refreshes_outcomes_without_changing_accounting(self):
        out = self.artifact / 'A1'
        run.save(out / 'summary.json', {'condition': 'A', 'repetition': 1, 'total_cost_usd': 0.25, 'output_tokens': 100, 'selene': False})
        run.save(out / 'score.json', {'criteria': {'selene': True, 'all_criteria': True}})
        run.save(self.artifact / 'grader-smoke/summary.json', {'total_cost_usd': 99})
        rows = report.regenerate_summaries(self.artifact)
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]['selene'])
        self.assertEqual(rows[0]['total_cost_usd'], 0.25)
        self.assertEqual(json.loads((self.artifact / 'medians.json').read_text())['A']['output_tokens'], 100)

    def test_multi_batch_e_compares_to_earlier_b_without_pooling(self):
        baseline, explicit = self.artifact / 'old-B', self.artifact / 'new-E'
        for batch, condition, cost, tokens, turns in ((baseline, 'B', 0.2, 1000, 15), (explicit, 'E', 0.1, 800, 12)):
            for repetition in range(1, 4):
                run.save(batch / f'{condition}{repetition}/summary.json',
                         {'condition': condition, 'repetition': repetition, 'total_cost_usd': cost,
                          'output_tokens': tokens, 'num_turns': turns, 'all_criteria': True, 'model': 'sonnet'})
        # An A row and a rejected E attempt must not contaminate the E/B contrast.
        run.save(explicit / 'A1/summary.json', {'condition': 'A', 'total_cost_usd': 9, 'output_tokens': 9000})
        run.save(explicit / 'E4-rejected-model/summary.json', {'condition': 'E', 'total_cost_usd': 9,
                                                            'artifact': 'E4-rejected-model'})
        text, data = report.comparison([baseline, explicit])
        self.assertIn('| old-B | B | 3 | 0.2 | 1000 | 15 | 3/3 |', text)
        self.assertIn('| new-E | E | 3 | 0.1 | 800 | 12 | 3/3 |', text)
        self.assertEqual(data['contrasts'], [{'E_batch': 'new-E', 'B_batch': 'old-B',
                                             'E_minus_B': {'total_cost_usd': -0.1, 'output_tokens': -200.0, 'num_turns': -3.0},
                                             'models_match': True}])

    def test_rescore_missing_snapshot_does_not_launch_or_mutate_scores(self):
        batch = run.ROOT / '.artifacts/bench' / 'unit-missing'
        with patch('run.ROOT', self.root):
            batch = self.root / '.artifacts/bench/unit-missing'
            run.save(batch / 'A1/summary.json', {'condition': 'A'})
            run.save(batch / 'A1/score.json', {'criteria': {'selene': False}})
            before = (batch / 'A1/score.json').read_bytes()
            with patch('run.prepare') as prepare, patch('run.run_one') as provider:
                with self.assertRaisesRegex(ValueError, 'preserved projects unavailable'):
                    run.rescore(batch)
            prepare.assert_not_called()
            provider.assert_not_called()
            self.assertEqual(before, (batch / 'A1/score.json').read_bytes())

    def test_rescore_restores_snapshot_keeps_old_scores_and_provider_fields(self):
        batch = self.root / '.artifacts/bench/fixture'
        out = batch / 'A1'
        out.mkdir(parents=True)
        (self.project / 'default.project.json').write_text('{}')
        (self.project / 'Coin.server.luau').write_text('final game source')
        sandbox.preserve_project(self.project, out, run.ROOT)
        run.save(out / 'summary.json', {'condition': 'A', 'total_cost_usd': 0.25, 'output_tokens': 100, 'selene': False})
        run.save(out / 'score.json', {'criteria': {'selene': False}})
        binary = self.root / 'fake-selene'
        binary.write_text('captured binary')
        definitions = batch / 'globalTypes.d.luau'
        definitions.write_text('captured definitions')
        std = batch / 'roblox.yml'
        std.write_text('captured std')
        run.save(batch / 'setup.json', {'tools': {'selene': str(binary)}, 'tool_hashes': {'selene': run.digest(binary)}})
        run.save(batch / 'definitions.json', {'sha256': run.digest(definitions)})
        def grade(config, project):
            self.assertEqual((project / 'Coin.server.luau').read_text(), 'final game source')
            self.assertEqual(Path(config['selene_std']), std)
            run.save(Path(config['artifact']) / 'score.json', {'criteria': {'selene': True}})
            return 1  # outcome failures are still re-scored, not provider errors
        with patch('run.ROOT', self.root), patch('run.prepare_selene_std', return_value=std), patch('sandbox.check', side_effect=grade), patch('run.run_one') as provider, patch('run.prepare') as prepare, contextlib.redirect_stdout(io.StringIO()):
            run.rescore(batch)
        provider.assert_not_called()
        prepare.assert_not_called()
        self.assertTrue(json.loads((out / 'score.json').read_text())['criteria']['selene'])
        previous = list(out.glob('rescores/*/previous-score.json'))
        self.assertEqual(len(previous), 1)
        self.assertFalse(json.loads(previous[0].read_text())['criteria']['selene'])
        medians = json.loads((batch / 'medians.json').read_text())
        self.assertEqual(medians['A']['total_cost_usd'], 0.25)
        self.assertEqual(medians['A']['output_tokens'], 100)


if __name__ == '__main__':
    unittest.main()
