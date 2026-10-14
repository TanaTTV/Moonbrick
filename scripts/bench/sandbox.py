"""Trusted tool gate and independent scoring for run.py.

This is a CLI/tool confinement policy, not an operating-system sandbox.
No arbitrary shell/code execution is permitted to the benchmark agent.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


def inside(path, root):
    try:
        return Path(path).resolve().is_relative_to(Path(root).resolve())
    except (OSError, ValueError):
        return False


def local_path(value, cwd):
    # Accept Git Bash's /c/... spelling as well as native and relative paths.
    value = re.sub(r'^/([A-Za-z])/', lambda m: m[1] + ':/', value)
    p = Path(value)
    return p if p.is_absolute() else Path(cwd) / p


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def hook(config):
    data = json.load(sys.stdin)
    name, args = data.get('tool_name', ''), data.get('tool_input', {})
    root, kit = Path(config['project']), Path(config['root'])
    cwd = data.get('cwd', str(root))
    reason = None
    if name in ('Write', 'Edit'):
        target = local_path(args.get('file_path', ''), cwd)
        if not inside(target, root) or any(p.rstrip(' .').lower() in ('.claude', '.git') for p in target.parts):
            reason = 'Writes are confined to game files in the disposable project; settings/hooks/git writes denied.'
    elif name in ('Read', 'Glob', 'Grep'):
        target = local_path(args.get('file_path', args.get('path', cwd)), cwd)
        if not inside(target, root) and not (config['condition'] == 'A' and inside(target, kit)):
            reason = 'Reads confined to the disposable project and, for A only, the selected Moonbrick source.'
    elif name == 'Bash':
        try:
            text = args.get('command', '')
            # Never pass shell operators, substitutions or newlines through.
            if any(c in text for c in ('\n', '\r', ';', '&', '|', '>', '<', '`', '$', '*', '?')):
                raise ValueError('Shell operators and expansions are denied.')
            tokens = shlex.split(text)
            executor = Path(__file__).resolve()
            if len(tokens) == 5 and tokens[0] in ('python', 'python3') and Path(tokens[1]).resolve() == executor and tokens[2] == 'check':
                if Path(tokens[3]).resolve() != Path(config['_path']).resolve() or not inside(local_path(tokens[4], cwd), root):
                    raise ValueError('Checker config and target must belong to this run.')
            elif config['condition'] == 'A' and len(tokens) == 5 and tokens[0] == 'bash' and local_path(tokens[1], cwd).resolve() == kit / 'scripts/new-project.sh' and tokens[4] == '--no-tools':
                if not inside(local_path(tokens[2], cwd), root):
                    raise ValueError('Scaffold target must be inside the run directory.')
            elif len(tokens) == 2 and tokens[0] == 'bash':
                script = local_path(tokens[1], cwd)
                if not inside(script, root) or not script.is_file() or sha(script) != sha(kit / 'template/tools/check.sh'):
                    raise ValueError('Only the unmodified template checker may be run.')
            else:
                raise ValueError('Allowed shell commands: trusted benchmark checker, unmodified template checker, or A-only new-project.sh <local-target> <name> --no-tools.')
        except (ValueError, OSError) as e:
            reason = str(e)
    elif name != 'Skill':
        reason = 'Tool not permitted by this benchmark.'
    decision = 'deny' if reason else 'allow'
    with (Path(config['artifact']) / 'tool-policy.jsonl').open('a', encoding='utf-8') as f:
        f.write(json.dumps({'tool': name, 'decision': decision, 'reason': reason, 'input': args}) + '\n')
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                      'permissionDecision': decision, 'permissionDecisionReason': reason or 'Within benchmark scope'}}))


def no_links(root):
    for p in (root, *root.rglob('*')):
        info = p.lstat()
        if p.is_symlink() or getattr(info, 'st_file_attributes', 0) & 0x400:
            raise ValueError(f'link/reparse point refused: {p}')


def strip_comments(text):
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', '', text, flags=re.S)
    return re.sub(r'--[^\n]*', '', text)


def kit_sources(kit):
    """Content identities for copied Kit files, never feature code."""
    paths = [p for folder in ('luau/lib', 'luau/tests', 'template/src/kit')
             for p in (kit / folder).rglob('*') if p.is_file()]
    paths.append(kit / 'luau/MCPKit.luau')
    return {sha(p): p.relative_to(kit).as_posix() for p in paths}


def preserve_project(project, artifact, kit):
    project, artifact, kit = Path(project), Path(artifact), Path(kit)
    no_links(project)
    destination = artifact / 'project-source'
    destination.mkdir()  # refuse to overwrite an earlier snapshot
    stock = kit_sources(kit)
    manifest = {'version': 1, 'files': {}}
    for p in sorted(project.rglob('*')):
        rel = p.relative_to(project)
        if not p.is_file() or any(part in ('.git', '.claude', '.moonbrick', '.artifacts', 'node_modules') for part in rel.parts):
            continue
        entry = {'sha256': sha(p), 'bytes': p.stat().st_size}
        if entry['sha256'] in stock:
            entry.update(storage='kit', repository_path=stock[entry['sha256']])
        elif p.name in ('globalTypes.d.luau', 'roblox.yml', 'sourcemap.json') or p.suffix in ('.rbxl', '.rbxlx', '.rbxm', '.rbxmx', '.exe', '.zip'):
            entry['storage'] = 'excluded_generated'
        else:
            entry['storage'] = 'source'
            target = destination / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, target)
        manifest['files'][rel.as_posix()] = entry
    dump(artifact / 'project-manifest.json', manifest)
    return manifest


def restore_project(artifact, destination, kit):
    """Fail closed on missing/tampered snapshots or changed hash-only Kit files."""
    artifact, destination, kit = Path(artifact), Path(destination), Path(kit)
    no_links(artifact / 'project-source')
    manifest = json.loads((artifact / 'project-manifest.json').read_text(encoding='utf-8'))
    if manifest.get('version') != 1:
        raise ValueError('unsupported project manifest version')
    copies = []
    for rel, entry in manifest['files'].items():
        target = destination / rel
        if not inside(target, destination):
            raise ValueError('manifest path escapes restored project')
        if entry['storage'] == 'excluded_generated':
            continue
        base = kit if entry['storage'] == 'kit' else artifact / 'project-source'
        source = base / (entry['repository_path'] if entry['storage'] == 'kit' else rel)
        if not inside(source, base) or not source.is_file() or sha(source) != entry['sha256']:
            raise ValueError(f'preserved source/Kit hash mismatch: {rel}; restore the captured Kit revision')
        copies.append((source, target))
    for source, target in copies:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    return destination


def debounce_signal(text):
    # A boolean/table flag must be tested AND assigned (not just initialized).
    for match in re.finditer(r'(?m)^\s*(?!local\b)(\w+(?:\[[^\]\n]+\])?)\s*=\s*(?:true|false)\b', text):
        flag = re.escape(match[1])
        if re.search(r'\bif\b[^\n]*' + flag + r'[^\n]*\bthen\b', text):
            return True
    # Cooldown.new alone is insufficient: the result of gate:use must gate work.
    for gate in re.findall(r'local\s+(\w+)\s*=\s*Cooldown\s*\.\s*new\s*\(', text):
        call = re.escape(gate) + r'\s*:\s*use\s*\([^\n]+,\s*(?:[1-9]\d*(?:\.\d+)?|0\.\d*[1-9]\d*)\s*\)'
        if re.search(r'if\s+not\s+' + call, text):
            return True
        assigned = re.search(r'local\s+(\w+)\s*=\s*' + call, text)
        if assigned and re.search(r'if\s+not\s+' + re.escape(assigned[1]) + r'\b', text):
            return True
    return False


def static_score(source, sourcemap, kit):
    classes = {}
    def walk(node, ancestors=()):
        lineage = ancestors + (node.get('name', ''),)
        for file in node.get('filePaths', []):
            path = Path(file)
            if not path.is_absolute():
                path = source / path
            classes[path.resolve()] = (node.get('className', ''), lineage)
        for child in node.get('children', []):
            walk(child, lineage)
    walk(sourcemap)
    stock = set()
    for folder in ('template', 'luau/lib', 'luau/tests'):
        for p in (kit / folder).rglob('*.luau'):
            stock.add(sha(p))
    stock.add(sha(kit / 'luau/MCPKit.luau'))
    server, client, shared, files, omitted = [], [], [], {}, []
    for p, (class_name, lineage) in classes.items():
        if p.suffix not in ('.lua', '.luau') or not p.is_file():
            continue
        rel = p.relative_to(source).as_posix()
        if sha(p) in stock:
            omitted.append(rel)
            continue
        text = strip_comments(p.read_text(encoding='utf-8'))
        files[rel] = text
        if 'ServerScriptService' in lineage:
            server.append((rel, text))
        elif class_name == 'LocalScript' or any(n in lineage for n in ('StarterPlayer', 'StarterGui')):
            client.append((rel, text))
        elif 'ReplicatedStorage' in lineage:
            shared.append((rel, text))
    s, c = '\n'.join(t for _, t in server), '\n'.join(t for _, t in client)
    coin_key = r'(?:["\'][Cc]oins?["\']|\w+\.(?:COINS?_KEY|[Cc]oins?Key))'
    reward = (r'(?:\b[\w.]+\s*\.\s*Value\s*(?:\+=\s*1\b|=\s*[\w.]+\.Value\s*\+\s*1\b)'
              r'|\b[Cc]oins?(?:\[[^\]\n]+\])?\s*(?:\+=\s*1\b|=\s*[^\n]+\+\s*1\b)'
              r'|\bPlayerData\s*\.\s*increment\s*\([^,\n]+,\s*' + coin_key + r'\s*,\s*1\s*\)'
              r'|\bsetCoins\s*\([^,\n]+,\s*\w+\s*\+\s*1\s*\))')
    server_reward = bool(re.search(reward, s))
    client_reward = bool(re.search(reward, c))
    spawn = bool(re.search(r'Instance\.new\s*\(\s*["\']Part["\']', s)) and bool(re.search(r'\b(?:coin|Coin)', s))
    touch = bool(re.search(r'\.Touched\s*:\s*Connect\s*\(', s))
    player_resolve = bool(re.search(r'GetPlayerFromCharacter|FindFirstAncestor(?:OfClass)?|GetPlayers', s))
    humanoid = bool(re.search(r'Humanoid|Character', s))
    consumed = any(debounce_signal(text) for _, text in server)
    # A client remote reward path requires a recognizable server validation signal.
    remote_files = [text for _, text in server if re.search(r'OnServerEvent|OnServerInvoke|Net\s*\.\s*(?:handle|on)\s*\(', text)]
    remote_reward = bool(remote_files)
    def guarded(text):
        if re.search(r'Magnitude|Distance|distance|(?:typeof|type)\s*\(|IsDescendantOf', text):
            return True
        registrations = list(re.finditer(r'Net\s*\.\s*(?:on|handle)\s*\(', text))
        validated = re.findall(r'Net\s*\.\s*(?:on|handle)\s*\(\s*[^,\n]+,\s*\{[^}]*\bNet\s*\.\s*(?:string|number|int|boolean|vector3|instance|oneOf)\s*\([^}]*\}', text)
        return bool(registrations) and len(validated) == len(registrations) and not re.search(r'OnServerEvent|OnServerInvoke', text)
    remote_guard = bool(remote_files) and all(guarded(text) for text in remote_files)
    shared_reward = any(re.search(reward, text) and not re.search(r'IsServer\s*\(', text) for _, text in shared)
    authority = server_reward and player_resolve and humanoid and consumed and not client_reward and not shared_reward and (not remote_reward or remote_guard)
    direct = all(re.search(pattern, s) for pattern in (r'DataStoreService', r'GetDataStore\s*\(', r'GetAsync\s*\(', r'(?:UpdateAsync|SetAsync)\s*\(', r'PlayerRemoving', r'BindToClose'))
    playerdata = all(re.search(pattern, s) for pattern in (r'require\s*\([^\n]*PlayerData', r'\w+\.start\s*\(', r'\w+\.(?:wait|get)\s*\(', reward))
    # Actual managed PlayerData must be server-mapped, with a persistent-store path.
    data_modules = [p for p, (_, lineage) in classes.items() if p.name == 'PlayerData.luau' and 'ServerScriptService' in lineage and p.is_file()]
    managed = any(all(x in p.read_text(encoding='utf-8') for x in ('GetDataStore', 'UpdateAsync', 'PlayerRemoving', 'BindToClose')) for p in data_modules)
    memory_override = bool(re.search(r'(?:store\s*=\s*[^,\n]*memoryStore|forceMemory\s*=\s*true)', s))
    persistence = bool((direct or playerdata and managed) and not memory_override)
    screen = bool(re.search(r'Instance\.new\s*\(\s*["\']ScreenGui["\']', c) and re.search(r'PlayerGui', c)) or bool(re.search(r'\bUI\s*\.\s*screen\s*\(', c))
    label = bool(re.search(r'Instance\.new\s*\(\s*["\']TextLabel["\']|\bUI\s*\.\s*label\s*\(', c))
    updates = bool(re.search(r'(?:Changed|GetPropertyChangedSignal|OnClientEvent)[^\n]*:\s*Connect\s*\(|\bNet\s*\.\s*listen\s*\(', c))
    hud = screen and label and updates and bool(re.search(r'\.Text\s*=|\btext\s*=', c)) and bool(re.search(r'(?i)coin', c))
    evidence = dict(server_files=[p for p, _ in server], client_files=[p for p, _ in client], shared_files=[p for p, _ in shared], stock_files_excluded=omitted,
                    server_reward=server_reward, client_reward=client_reward, shared_unguarded_reward=bool(shared_reward),
                    server_spawn=spawn, server_touch=touch, player_resolve=player_resolve, humanoid=humanoid,
                    consumed=consumed, remote_reward=remote_reward, remote_guard=remote_guard,
                    hud_screen=screen, hud_label=label, hud_updates=updates,
                    direct_datastore=bool(direct), configured_playerdata=bool(playerdata and managed), memory_override=memory_override)
    return {'server_authority_static': bool(authority), 'persistence_static': persistence,
            'coin_touch_static': bool(spawn and touch and server_reward), 'hud_static': bool(hud)}, evidence


def invoke(argv, cwd):
    start = time.monotonic()
    try:
        p = subprocess.run([str(a) for a in argv], cwd=cwd, capture_output=True,
                           text=True, encoding='utf-8', errors='replace', timeout=90)
        return {'argv': [str(a) for a in argv], 'cwd': str(cwd), 'returncode': p.returncode,
                'stdout': p.stdout, 'stderr': p.stderr, 'wall_seconds': time.monotonic() - start}
    except subprocess.TimeoutExpired as e:
        return {'argv': [str(a) for a in argv], 'cwd': str(cwd), 'returncode': None,
                'stdout': str(e.stdout or ''), 'stderr': str(e.stderr or ''), 'timeout': True}


def check(config, project):
    project = Path(project).resolve()
    if not inside(project, config['project']):
        raise ValueError('checker target outside run project')
    no_links(project)
    excluded = ('.git', '.moonbrick', 'node_modules', '.artifacts')
    projects = [p for p in project.rglob('*.project.json') if not any(part in excluded for part in p.relative_to(project).parts)]
    default = [p for p in projects if p.name == 'default.project.json']
    if len(default) == 1:
        chosen = default[0]
    elif len(projects) == 1:
        chosen = projects[0]
    else:
        result = {'criteria': {k: False for k in ('build', 'strict_types', 'selene', 'server_authority_static', 'persistence_static', 'coin_touch_static', 'hud_static', 'all_criteria')},
                  'reason': 'missing or ambiguous Rojo project', 'projects': [str(p) for p in projects]}
        dump(Path(config['artifact']) / 'score.json', result)
        print(json.dumps(result)); return 1
    source = chosen.parent
    # Prevent Rojo's project mapping from following absolute/escaping paths.
    def validate_map(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key == '$path':
                    if not isinstance(child, str) or not inside(local_path(child, source), source):
                        raise ValueError('Rojo mapping escapes project')
                else:
                    validate_map(child)
        elif isinstance(value, list):
            for child in value:
                validate_map(child)
    validate_map(json.loads(chosen.read_text(encoding='utf-8')))
    with tempfile.TemporaryDirectory(prefix='score-', dir=config['artifact']) as evaluation:
        return score_copy(config, chosen, Path(evaluation))


def score_copy(config, chosen, evaluation):
    source = chosen.parent
    kit, tool = Path(config['root']), config['tools']
    excluded = ('.git', '.moonbrick', 'node_modules', '.artifacts')
    dest = evaluation / 'project'
    shutil.copytree(source, dest, ignore=shutil.ignore_patterns(*excluded))
    original_configs = {}
    for p in dest.rglob('.luaurc'):
        original_configs[p.relative_to(dest).as_posix()] = p.read_text(encoding='utf-8')
        p.write_text('{"languageMode":"strict"}\n', encoding='utf-8')
    shutil.copyfile(kit / 'template/.luaurc', dest / '.luaurc')
    shutil.copyfile(kit / 'template/selene.toml', dest / 'selene.toml')
    # Pin the captured std beside the config, bypassing unsupported isolated
    # platform discovery and mutable floating user caches during every check.
    lint_config = dest / 'selene.toml'
    lint_config.write_text('roblox-std-source = "pinned"\n' + lint_config.read_text(encoding='utf-8'), encoding='utf-8')
    shutil.copyfile(config['selene_std'], dest / 'roblox.yml')
    shutil.copyfile(config['definitions'], dest / 'globalTypes.d.luau')
    # Match the template checker's scope, including the shipped nonstrict inspection helper.
    scope = [p.name for p in (dest / 'src', dest / 'tests') if p.is_dir() and any(f.suffix in ('.luau', '.lua') for f in p.rglob('*'))]
    if (dest / 'tools/MCPKit.luau').is_file():
        scope.append('tools/MCPKit.luau')
    # Also analyze game sources outside the template layout; do not silently miss
    # a mapped root-level Script just because stock src/ or tests/ exists.
    for p in dest.rglob('*'):
        if p.suffix not in ('.lua', '.luau') or p.name == 'globalTypes.d.luau':
            continue
        if not any(p == dest / item or p.is_relative_to(dest / item) for item in scope):
            scope.append(p.relative_to(dest).as_posix())
    custom_nonstrict = []
    known_nonstrict = {sha(p) for p in (kit / 'luau', kit / 'template') for p in p.rglob('*.luau') if '--!nonstrict' in p.read_text(encoding='utf-8')}
    for target in scope:
        path = dest / target
        files = [path] if path.is_file() else [p for p in path.rglob('*') if p.suffix in ('.luau', '.lua')]
        for file in files:
            text = file.read_text(encoding='utf-8')
            if re.search(r'^\s*--!(?:nonstrict|nocheck)', text, re.M) and sha(file) not in known_nonstrict:
                custom_nonstrict.append(file.relative_to(dest).as_posix())
    commands = {}
    commands['build'] = invoke([tool['rojo'], 'build', chosen.name, '-o', 'benchmark.rbxlx'], dest)
    commands['sourcemap'] = invoke([tool['rojo'], 'sourcemap', chosen.name, '-o', 'sourcemap.json'], dest)
    if commands['sourcemap']['returncode'] == 0:
        commands['strict_types'] = invoke([tool['luau-lsp'], 'analyze', '--sourcemap=sourcemap.json', '--definitions=globalTypes.d.luau', '--formatter=plain', *scope], dest)
    commands['selene'] = invoke([tool['selene'], '--display-style=quiet', *scope], dest) if scope else {'returncode': None, 'reason': 'no Luau source files'}
    criteria = {key: commands.get(key, {}).get('returncode') == 0 for key in ('build', 'strict_types', 'selene')}
    criteria['strict_types'] = criteria['strict_types'] and bool(scope) and not custom_nonstrict
    evidence = {}
    if (dest / 'sourcemap.json').is_file():
        static, evidence = static_score(dest, json.loads((dest / 'sourcemap.json').read_text()), kit)
        criteria.update(static)
    else:
        criteria.update({k: False for k in ('server_authority_static', 'persistence_static', 'coin_touch_static', 'hud_static')})
    criteria['all_criteria'] = all(criteria.values())
    result = {'criteria': criteria, 'commands': commands, 'static_evidence': evidence,
              'original_luaurc': original_configs, 'custom_nonstrict': custom_nonstrict,
              'evaluation_directory': str(evaluation), 'evaluation_directory_retained': False,
              'selected_project': str(chosen), 'scope': scope,
              'configs': {'luaurc_sha256': sha(dest / '.luaurc'), 'selene_sha256': sha(dest / 'selene.toml'), 'selene_std_sha256': sha(dest / 'roblox.yml'), 'definitions_sha256': sha(dest / 'globalTypes.d.luau')}}
    dump(Path(config['artifact']) / 'score.json', result)
    print(json.dumps(result, indent=2))
    return 0 if criteria['all_criteria'] else 1


def main():
    operation, filename = sys.argv[1:3]
    config = json.loads(Path(filename).read_text(encoding='utf-8'))
    config['_path'] = filename
    if operation == 'hook':
        hook(config); return 0
    if operation == 'check':
        try:
            return check(config, sys.argv[3])
        except (ValueError, OSError) as e:
            result = {'criteria': {k: False for k in ('build', 'strict_types', 'selene', 'server_authority_static', 'persistence_static', 'coin_touch_static', 'hud_static', 'all_criteria')}, 'reason': str(e)}
            dump(Path(config['artifact']) / 'score.json', result)
            print(json.dumps(result)); return 1
    raise ValueError('unknown operation')


if __name__ == '__main__':
    sys.exit(main())
