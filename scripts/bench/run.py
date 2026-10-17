"""Sequential, artifact-first Claude Code benchmark. No Studio or publication.

Run from the bench worktree with `py -3 scripts/bench/run.py`.
Provider calls require --run; --prepare captures a no-model preflight only.
--dry-run writes the real command artifacts without invoking a provider.
Only provider-reported accounting is used. Missing fields remain blank.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import queue
import shlex
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CONDITIONS = ('A', 'B', 'E')
EXPLICIT_USE = 'Use the Moonbrick plugin for this (start with its moonbrick:new skill, then follow moonbrick:game-systems).'
PROMPT = '''Create a new Roblox game project and implement a server-authoritative coin pickup: coins spawn on the map, touching/collecting one awards +1 coin persisted per player, with a client HUD showing the count; it must pass strict type checking/lint.

Work only inside the current empty directory (a subdirectory is fine). No Studio, MCP, publishing, installation, external writes, or subagents. The pinned rojo, luau-lsp, selene and stylua binaries are on PATH for both conditions. No tool installation is needed. Shell execution is confined to the trusted benchmark checker described below; use Read/Write/Edit/Glob/Grep for other file work. Do not write .claude settings or hooks, create symlinks, or modify files outside this directory.

Run the independent headless checker with: {check}
It runs Rojo build/sourcemap, strict luau-lsp with captured Roblox definitions, and Selene with the template lint configuration on a disposable copy. It does not install tools or use Studio. Pass the project directory containing the .project.json file as its argument. If Moonbrick is available, its new skill can be used; its scaffold command is permitted only with --no-tools and a target inside this directory. Skip starting Rojo serve, installation and Studio steps. Finish with a concise implementation and verification summary.
'''
FIELDS = ['condition', 'repetition', 'status', 'model', 'input_tokens', 'output_tokens',
          'cache_read_input_tokens', 'cache_creation_input_tokens', 'total_cost_usd',
          'num_turns', 'duration_ms', 'wall_seconds', 'build', 'strict_types', 'selene',
          'server_authority_static', 'persistence_static', 'coin_touch_static', 'hud_static',
          'all_criteria', 'artifact']


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, cwd=ROOT, env=None, timeout=120):
    start = time.monotonic()
    try:
        p = subprocess.run([str(a) for a in args], cwd=cwd, env=env, capture_output=True,
                           text=True, encoding='utf-8', errors='replace', timeout=timeout)
        return dict(argv=[str(a) for a in args], cwd=str(cwd), returncode=p.returncode,
                    stdout=p.stdout, stderr=p.stderr, wall_seconds=time.monotonic() - start)
    except subprocess.TimeoutExpired as e:
        return dict(argv=[str(a) for a in args], cwd=str(cwd), returncode=None,
                    timeout=True, stdout=str(e.stdout or ''), stderr=str(e.stderr or ''),
                    wall_seconds=time.monotonic() - start)


def claude_command():
    # Use the JS entrypoint directly: Windows .cmd quoting loses inline JSON.
    node, wrapper = shutil.which('node'), shutil.which('claude.cmd' if os.name == 'nt' else 'claude')
    if os.name == 'nt' and wrapper:
        package = Path(wrapper).parent / 'node_modules/@anthropic-ai/claude-code'
        # Newer packages ship a native bin/claude.exe; cmd.exe would cut argv at the prompt's first newline.
        if (package / 'bin/claude.exe').is_file():
            return [str(package / 'bin/claude.exe')]
        if node and (package / 'cli.js').is_file():
            return [node, str(package / 'cli.js')]
        raise RuntimeError('only the claude.cmd wrapper was found; it truncates multi-line prompts')
    if not wrapper:
        raise RuntimeError('claude executable unavailable')
    return [wrapper]


def tools():
    pins = {'rojo': ('rojo-rbx/rojo/7.7.1', 'rojo'),
            'luau-lsp': ('johnnymorganz/luau-lsp/1.70.1', 'luau-lsp'),
            'selene': ('kampfkarren/selene/0.32.0', 'selene'),
            'stylua': ('johnnymorganz/stylua/2.6.0', 'stylua')}
    found = {}
    for name, (rel, exe) in pins.items():
        candidate = Path.home() / '.rokit/tool-storage' / rel / (exe + ('.exe' if os.name == 'nt' else ''))
        if not candidate.is_file():
            raise RuntimeError(f'pinned cached tool unavailable: {candidate}; no installation attempted')
        found[name] = str(candidate)
    return found


def user_config_snapshot():
    paths = [Path.home() / '.claude/settings.json', Path.home() / '.claude/settings.local.json',
             Path.home() / '.claude/plugins/installed_plugins.json',
             Path.home() / '.claude/plugins/known_marketplaces.json']
    return {str(p): digest(p) if p.is_file() else None for p in paths}


def snapshot_repo():
    # Include tracked/untracked contents, excluding ignored artifacts/cache files.
    listing = command(['git', 'ls-files', '-co', '--exclude-standard'])['stdout'].splitlines()
    return {name: digest(ROOT / name) for name in sorted(set(listing)) if (ROOT / name).is_file()}


def fetch_definitions(batch):
    url = 'https://luau-lsp.pages.dev/type-definitions/globalTypes.PluginSecurity.d.luau'
    target = batch / 'globalTypes.d.luau'
    attempts = []
    if target.is_file() and target.stat().st_size:
        attempts.append({'source': 'already captured in this batch', 'bytes': target.stat().st_size})
    else:
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                target.write_bytes(response.read())
            attempts.append({'transport': 'urllib', 'success': True})
        except (OSError, urllib.error.URLError) as e:
            attempts.append({'transport': 'urllib', 'success': False, 'error': str(e)})
            # At most two attempts. Native curl succeeds on hosts rejecting urllib.
            curl = shutil.which('curl.exe' if os.name == 'nt' else 'curl')
            if curl:
                attempts.append(command([curl, '-fsSL', '--connect-timeout', '10', '--max-time', '60', '-o', target, url], timeout=75))
    metadata = {'url': url, 'attempts': attempts, 'success': target.is_file() and target.stat().st_size > 0}
    if metadata['success']:
        metadata.update(sha256=digest(target), bytes=target.stat().st_size)
    save(batch / 'definitions.json', metadata)
    if not metadata['success']:
        raise RuntimeError('Roblox definitions download blocked after at most two transports; see definitions.json')
    return target


def trial_order(conditions, reps):
    # Preserve the original six-trial order for the default experiment.
    if conditions == ['A', 'B'] and reps == 3:
        return [('B', 1), ('A', 1), ('A', 2), ('B', 2), ('B', 3), ('A', 3)]
    return [(condition, repetition) for repetition in range(1, reps + 1)
            for condition in (list(reversed(conditions)) if repetition % 2 else conditions)]


def prepare(batch, conditions=None, reps=3):
    conditions = conditions or ['A', 'B']
    cli = claude_command()
    spec = dict(created_utc=datetime.now(timezone.utc).isoformat(), base_sha=command(['git', 'rev-parse', 'HEAD'])['stdout'].strip(),
                branch=command(['git', 'branch', '--show-current'])['stdout'].strip(),
                parameters={'requested_model': 'claude-sonnet-5-5', 'max_turns': 40,
                            'conditions': conditions, 'repetitions': reps, 'single_run_seconds': 900, 'total_budget_usd': '8',
                            'order': [f'{c}{r}' for c, r in trial_order(conditions, reps)]},
                cli=cli, help=command(cli + ['--help']), version=command(cli + ['--version']),
                agents_before=command(cli + ['agents', '--json', '--all']),
                tools=tools(), user_config_before=user_config_snapshot(),
                git_status_before=command(['git', 'status', '--porcelain'])['stdout'],
                template_hashes={p.name: digest(p) for p in [ROOT / 'template/.luaurc', ROOT / 'template/selene.toml', ROOT / 'template/tools/check.sh']})
    # Measure only from known benchmark branches; perf/kit-api-card measures the API card + recipes change.
    if spec['branch'] not in ('dev/v1-beta-bench', 'perf/kit-api-card'):
        raise RuntimeError('wrong benchmark branch')
    for name, path in spec['tools'].items():
        spec.setdefault('tool_versions', {})[name] = command([path, '--version'])
        spec.setdefault('tool_hashes', {})[name] = digest(Path(path))
    spec['selene_std'] = str(prepare_selene_std(batch, spec['tools']['selene']))
    save(batch / 'setup.json', spec)
    return spec


def prepare_selene_std(batch, executable):
    """Capture a real generated Roblox std, then prove it works without user caches."""
    target = batch / 'roblox.yml'
    metadata = batch / 'selene-std.json'
    evidence = json.loads(metadata.read_text(encoding='utf-8')) if metadata.is_file() else {'attempts': []}
    if target.is_file() and evidence.get('sha256') and digest(target) != evidence['sha256']:
        raise ValueError('captured Selene std hash mismatch; original metadata unchanged')
    if not target.is_file():
        # The template checker uses Selene's floating user cache. Read it only;
        # never regenerate/update that cache or the user's project/configuration.
        cache_root = Path(os.environ.get('LOCALAPPDATA', Path.home() / '.cache'))
        cached = cache_root / 'selene/roblox.yml'
        if cached.is_file() and cached.stat().st_size:
            shutil.copyfile(cached, target)
            evidence['attempts'].append({'source': str(cached), 'sha256': digest(cached), 'transport': 'readonly cache copy'})
        else:
            with tempfile.TemporaryDirectory(prefix='std-generate-', dir=batch) as directory:
                attempt = command([executable, 'generate-roblox-std'], cwd=directory)
                evidence['attempts'].append(attempt)
                generated = Path(directory) / 'roblox.yml'
                if attempt['returncode'] == 0 and generated.is_file():
                    shutil.copyfile(generated, target)
    if not target.is_file() or not target.stat().st_size:
        save(batch / 'selene-std.json', evidence)
        raise RuntimeError('Selene Roblox std unavailable; see selene-std.json (no provider call)')
    with tempfile.TemporaryDirectory(prefix='std-verify-', dir=batch) as directory:
        folder = Path(directory)
        shutil.copyfile(target, folder / 'roblox.yml')
        (folder / 'selene.toml').write_text('std = "roblox"\nroblox-std-source = "pinned"\n', encoding='utf-8')
        (folder / 'probe.luau').write_text('local part = Instance.new("Part")\npart.Parent = workspace\n', encoding='utf-8')
        env = dict(os.environ)
        for name in ('HOME', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME'):
            env[name] = str(folder / 'empty-home')
        evidence['verification'] = command([executable, '--display-style=quiet', 'probe.luau'], cwd=folder, env=env)
    evidence.update(sha256=digest(target), bytes=target.stat().st_size,
                    success=evidence['verification']['returncode'] == 0)
    save(batch / 'selene-std.json', evidence)
    if not evidence['success']:
        raise RuntimeError('Pinned Selene std verification failed; see selene-std.json')
    print(f'Selene std prepared: {target} sha256={evidence["sha256"]}', flush=True)
    return target


def isolated_env(temp, binaries, copy_credentials=True):
    home, config, bin_dir = temp / 'home', temp / 'claude-config', temp / 'bin'
    for p in (home, config, bin_dir, temp / 'tmp'):
        p.mkdir()
    creds = Path.home() / '.claude/.credentials.json'
    if copy_credentials and creds.is_file():
        # Never save credentials in artifacts or committed summaries.
        shutil.copyfile(creds, config / '.credentials.json')
    for name, source in binaries.items():
        shutil.copyfile(source, bin_dir / Path(source).name)
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(('CLAUDE_', 'ROKIT_', 'GIT_', 'ACTIONS_')) or key in ('GH_TOKEN', 'GITHUB_TOKEN', 'BASH_ENV', 'ENV'):
            del env[key]
    env.update(HOME=str(home), USERPROFILE=str(home), CLAUDE_CONFIG_DIR=str(config),
               APPDATA=str(home / 'AppData/Roaming'), LOCALAPPDATA=str(home / 'AppData/Local'),
               XDG_CONFIG_HOME=str(home / '.config'), XDG_CACHE_HOME=str(home / '.cache'),
               XDG_DATA_HOME=str(home / '.local/share'), TEMP=str(temp / 'tmp'), TMP=str(temp / 'tmp'), TMPDIR=str(temp / 'tmp'),
               PATH=str(bin_dir) + os.pathsep + env['PATH'], GIT_CONFIG_GLOBAL=str(home / 'gitconfig'),
               GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='Moonbrick benchmark', GIT_AUTHOR_EMAIL='bench@moonbrick.invalid',
               GIT_COMMITTER_NAME='Moonbrick benchmark', GIT_COMMITTER_EMAIL='bench@moonbrick.invalid',
               PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1', DISABLE_AUTOUPDATER='1',
               CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1')
    git_bash = Path('C:/Program Files/Git/bin/bash.exe')
    if os.name == 'nt' and git_bash.is_file():
        env['CLAUDE_CODE_GIT_BASH_PATH'] = str(git_bash)
        env['PATH'] = str(git_bash.parent) + os.pathsep + env['PATH']
    return env


def isolation(init, condition):
    plugins = init.get('plugins')
    skills = init.get('skills', [])
    commands = init.get('slash_commands', [])
    if not isinstance(plugins, list):
        return False, 'init has no explicit plugin inventory'
    # Claude Code's own built-in plugins load identically in both conditions; only installed ones matter.
    plugins = [p for p in plugins if not (isinstance(p, dict) and p.get('path') == 'builtin')]
    names = [p.get('name', '') if isinstance(p, dict) else str(p) for p in plugins]
    moon = [n for n in names if 'moonbrick' in n.lower()]
    leaked = any('moonbrick' in str(s).lower() for s in skills + commands)
    mcp = init.get('mcp_servers')
    ok = isinstance(mcp, list) and not mcp and not any(str(t).startswith('mcp__') for t in init.get('tools', []))
    if condition == 'B':
        ok = ok and not names and not leaked
    else:
        ok = ok and len(moon) == 1 and len(names) == 1 and any('moonbrick:new' in str(s) for s in skills + commands)
        for p in plugins:
            if isinstance(p, dict) and p.get('path'):
                ok = ok and Path(p['path']).resolve() == ROOT.resolve()
    return ok, {'plugins': plugins, 'skills': skills, 'slash_commands': commands, 'mcp_servers': mcp, 'tools': init.get('tools')}


def kill_owned(proc):
    if proc.poll() is None:
        if os.name == 'nt':
            subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True)
        else:
            proc.kill()
        proc.wait(timeout=30)


def run_one(batch, spec, condition, repetition, model, remaining, dry_run=False):
    out = batch / f'{condition}{repetition}'
    out.mkdir()
    # Deliberately retained for review; credential copy is removed in finally.
    # Outside the plugin dir: Claude Code won't auto-approve edits inside a loaded plugin's tree,
    # and the run copies credentials into this directory.
    temp = Path(tempfile.mkdtemp(prefix='moonbrick-bench-'))
    project = temp / 'project'
    project.mkdir()
    env = isolated_env(temp, spec['tools'], copy_credentials=not dry_run)
    sandbox = temp / 'sandbox.json'
    save(sandbox, {'project': str(project), 'root': str(ROOT), 'condition': condition,
                   'artifact': str(out), 'definitions': str(batch / 'globalTypes.d.luau'),
                   'selene_std': spec['selene_std'],
                   'tools': spec['tools']})
    save(temp / 'empty-mcp.json', {'mcpServers': {}})
    hook = shlex.join([Path(sys.executable).as_posix(), (HERE / 'sandbox.py').as_posix(), 'hook', sandbox.as_posix()])
    settings = {'enabledPlugins': {'moonbrick@moonbrick': False},
                'hooks': {'PreToolUse': [{'matcher': '.*', 'hooks': [{'type': 'command', 'command': hook}]}]}}
    save(temp / 'settings.json', settings)
    check = f'python "{(HERE / "sandbox.py").as_posix()}" check "{sandbox.as_posix()}" "<project-directory>"'
    prompt = PROMPT.format(check=check)
    if condition == 'E':
        prompt = EXPLICIT_USE + '\n' + prompt
    argv = spec['cli'] + ['-p', prompt, '--output-format', 'stream-json', '--verbose',
              '--effort', 'medium', '--max-turns', '40', '--max-budget-usd', str(remaining),
              '--permission-mode', 'acceptEdits', '--permission-prompts', 'none',
              '--tools', 'Read,Write,Edit,Glob,Grep,Bash,Skill', '--setting-sources', 'project',
              '--settings', str(temp / 'settings.json'), '--strict-mcp-config',
              '--mcp-config', str(temp / 'empty-mcp.json'), '--no-chrome',
              '--session-id', str(uuid.uuid4()), '--name', f'moonbrick-bench-{condition}{repetition}']
    if model:
        argv += ['--model', model]
    if condition in ('A', 'E'):
        argv += ['--plugin-dir', str(ROOT)]
    save(out / 'command.json', {'argv': argv, 'cwd': str(project), 'temp': str(temp),
                              'settings': settings, 'sandbox': json.loads(sandbox.read_text()),
                              'initial_project_files': list(project.iterdir()), 'requested_model': model})
    if dry_run:
        save(out / 'dry-run.json', {'provider_calls': 0, 'credential_copy_created': False})
        print(f'{condition}{repetition}: dry-run command saved: {out / "command.json"}; provider calls: 0', flush=True)
        return None, None, ''
    start = time.monotonic()
    messages, q = [], queue.Queue()
    status, result, init = 'missing_result', None, None
    stderr = (out / 'stderr.txt').open('w', encoding='utf-8')
    proc = subprocess.Popen(argv, cwd=project, env=env, stdout=subprocess.PIPE, stderr=stderr,
                            text=True, encoding='utf-8', errors='replace')
    def reader():
        for line in proc.stdout:
            q.put(line)
        q.put(None)
    threading.Thread(target=reader, daemon=True).start()
    try:
        with (out / 'stream.jsonl').open('w', encoding='utf-8') as stream:
            while True:
                if time.monotonic() - start > spec['parameters']['single_run_seconds']:
                    status = 'timeout'; kill_owned(proc); break
                try:
                    line = q.get(timeout=1)
                except queue.Empty:
                    continue
                if line is None:
                    break
                stream.write(line); stream.flush()
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    continue
                messages.append(message)
                if message.get('type') == 'system' and message.get('subtype') == 'init':
                    init = message
                    save(out / 'init.json', init)
                    ok, proof = isolation(init, condition)
                    save(out / 'isolation.json', {'pass': ok, 'proof': proof})
                    print(f'{condition}{repetition}: init model={init.get("model")} isolation={ok}', flush=True)
                    if not ok:
                        status = 'isolation_failed'; kill_owned(proc); break
                    if 'sonnet' not in str(init.get('model', '')).lower():
                        status = 'non_sonnet_model'; kill_owned(proc); break
                if message.get('type') == 'result':
                    result = message
                    save(out / 'result.json', result)
                    status = message.get('subtype', 'unknown_result')
                    print(f'{condition}{repetition}: {status} cost={message.get("total_cost_usd")}', flush=True)
            proc.wait(timeout=30)
    finally:
        kill_owned(proc)
        stderr.close()
        (temp / 'claude-config/.credentials.json').unlink(missing_ok=True)
    save(out / 'process.json', {'status': status, 'exit_code': proc.returncode, 'wall_seconds': time.monotonic() - start,
                               'temp': str(temp), 'credential_copy_removed': True,
                               'agents_after': command(spec['cli'] + ['agents', '--json', '--all'])})
    save(out / 'inventory.json', {p.relative_to(project).as_posix(): {'bytes': p.stat().st_size, 'sha256': digest(p)}
                                for p in project.rglob('*') if p.is_file() and not p.is_symlink()})
    # Archive before grading, including failures/ambiguous projects. Never rely
    # on the disposable session or scoring directory surviving orchestration.
    from sandbox import preserve_project
    preserve_project(project, out, ROOT)
    # Independent checks even when the model hit max turns or returned an error.
    scoring = command([sys.executable, str(HERE / 'sandbox.py'), 'check', str(sandbox), str(project)], cwd=project, env=env, timeout=180)
    save(out / 'scoring-process.json', scoring)
    row = {'condition': condition, 'repetition': repetition, 'status': status,
           'model': init.get('model') if init else None,
           'wall_seconds': json.loads((out / 'process.json').read_text())['wall_seconds'],
           'artifact': str(out.relative_to(ROOT))}
    if result:
        usage = result.get('usage', {})
        for name in ('input_tokens', 'output_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens'):
            row[name] = usage.get(name)
        for name in ('total_cost_usd', 'num_turns', 'duration_ms'):
            row[name] = result.get(name)
        row['model'] = ','.join(result.get('modelUsage', {})) or row['model']
    grade = out / 'score.json'
    if grade.is_file():
        row.update(json.loads(grade.read_text())['criteria'])
    save(out / 'summary.json', row)
    return row, result, (out / 'stderr.txt').read_text(encoding='utf-8')


def summarize(batch, rows):
    with (batch / 'summary.csv').open('w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, extrasaction='ignore')
        writer.writeheader(); writer.writerows(rows)
    lines = ['| ' + ' | '.join(FIELDS) + ' |', '| ' + ' | '.join(['---'] * len(FIELDS)) + ' |']
    for row in rows:
        lines.append('| ' + ' | '.join(str(row.get(k)) if row.get(k) is not None else 'not reported' for k in FIELDS) + ' |')
    (batch / 'summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    medians = {}
    for condition in CONDITIONS:
        selected = [r for r in rows if r['condition'] == condition and r.get('total_cost_usd') is not None and '-rejected-model' not in r.get('artifact', '') and '-blocked-attempt' not in r.get('artifact', '')]
        medians[condition] = {'accounted_runs': len(selected)}
        for name in FIELDS[4:12]:
            values = [r[name] for r in selected if r.get(name) is not None]
            medians[condition][name] = statistics.median(values) if values else None
    save(batch / 'medians.json', medians)


def rescore(batch):
    """No CLI/provider/authentication setup: restore captured files and grade."""
    from sandbox import restore_project, check
    from report import regenerate_summaries
    if not batch.is_relative_to(ROOT / '.artifacts/bench'):
        raise ValueError('rescore batch must stay under this worktree .artifacts/bench')
    runs = [p.parent for p in sorted(batch.glob('*/summary.json'))
            if json.loads(p.read_text(encoding='utf-8')).get('condition') in CONDITIONS]
    if not runs:
        raise ValueError('no captured benchmark runs to rescore')
    missing = [p.name for p in runs if not (p / 'project-manifest.json').is_file() or not (p / 'project-source').is_dir()]
    if missing:
        raise ValueError('cannot rescore: preserved projects unavailable for ' + ', '.join(missing) + '; original scores unchanged')
    spec = json.loads((batch / 'setup.json').read_text(encoding='utf-8'))
    # Captured binaries/definitions are required, rather than silently substituting
    # newly installed tools or downloading today's type definitions.
    for name, executable in spec['tools'].items():
        if not Path(executable).is_file() or digest(Path(executable)) != spec['tool_hashes'][name]:
            raise ValueError(f'captured tool unavailable or changed: {name}')
    definitions = batch / 'globalTypes.d.luau'
    metadata = json.loads((batch / 'definitions.json').read_text(encoding='utf-8'))
    if not definitions.is_file() or digest(definitions) != metadata['sha256']:
        raise ValueError('captured type definitions unavailable or changed')
    std = prepare_selene_std(batch, spec['tools']['selene'])
    round_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    staged = []
    for artifact in runs:
        output = artifact / 'rescores' / round_id
        output.mkdir(parents=True)
        with tempfile.TemporaryDirectory(prefix='restore-', dir=output) as directory:
            project = Path(directory) / 'project'
            restore_project(artifact, project, ROOT)
            config = {'project': str(project), 'root': str(ROOT), 'artifact': str(output),
                      'tools': spec['tools'], 'definitions': str(definitions), 'selene_std': str(std)}
            check(config, project)
        staged.append((artifact, output))
    # Publish only after every restoration/check completes; retain all old scores.
    for artifact, output in staged:
        if (artifact / 'score.json').is_file():
            shutil.copyfile(artifact / 'score.json', output / 'previous-score.json')
        shutil.copyfile(output / 'score.json', artifact / 'score.json')
    save(batch / 'rescore.json', {'round': round_id, 'provider_calls': 0,
                                 'grader_sha256': digest(HERE / 'sandbox.py'),
                                 'runs': [p.name for p in runs]})
    regenerate_summaries(batch)
    print(f'Rescored {len(runs)} preserved projects; summary/medians regenerated; provider calls: 0')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--run', action='store_true', help='Execute sequential provider sessions for selected conditions')
    modes.add_argument('--prepare', action='store_true', help='Capture no-model preflight')
    modes.add_argument('--rescore', type=Path, help='Re-score preserved projects; never calls a provider')
    modes.add_argument('--dry-run', action='store_true', help='Write command.json for selected trials; no provider or authentication copy')
    parser.add_argument('--conditions', default='A,B', help='Comma-separated selection from A,B,E (default: A,B)')
    parser.add_argument('--reps', type=int, default=3, help='Repetitions per condition (positive integer; default: 3)')
    parser.add_argument('--approved-shared-quota', action='store_true', help='Explicit user approval for existing Claude sessions')
    parser.add_argument('--batch', type=Path)
    args = parser.parse_args()
    conditions = [c.strip() for c in args.conditions.split(',')]
    if not conditions or any(c not in CONDITIONS for c in conditions) or len(set(conditions)) != len(conditions):
        parser.error('--conditions must be unique comma-separated values from A,B,E')
    if args.reps < 1:
        parser.error('--reps must be positive')
    if args.rescore:
        try:
            rescore(args.rescore.resolve())
        except (ValueError, RuntimeError) as e:
            parser.error(str(e))
        return
    batch = args.batch or ROOT / '.artifacts/bench' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    batch = batch.resolve()
    if not batch.is_relative_to(ROOT / '.artifacts/bench'):
        parser.error('batch must stay under this worktree .artifacts/bench')
    batch.mkdir(parents=True, exist_ok=True)
    if args.run or args.dry_run:
        if any(batch.glob('*/command.json')):
            parser.error('batch already contains command artifacts; choose a new batch')
    spec = prepare(batch, conditions, args.reps)
    print(f'Artifacts: {batch}', flush=True)
    if args.dry_run:
        for condition, repetition in trial_order(conditions, args.reps):
            run_one(batch, spec, condition, repetition, spec['parameters']['requested_model'], Decimal('8'), dry_run=True)
        save(batch / 'stop.json', {'reason': 'dry_run_no_provider_calls', 'provider_runs': 0})
        summarize(batch, [])
        return
    if not args.run:
        save(batch / 'stop.json', {'reason': 'preflight_only_no_provider_runs'})
        summarize(batch, [])
        return
    before = snapshot_repo()
    active = json.loads(spec['agents_before']['stdout'])
    live = [a for a in active if a.get('state') not in ('done', 'stopped')]
    if live and not args.approved_shared_quota:
        save(batch / 'stop.json', {'reason': 'quota_guard_blocked_existing_sessions', 'provider_runs': 0})
        save(batch / 'safety.json', {'repository_contents_unchanged': snapshot_repo() == before,
                                   'git_status_after': command(['git', 'status', '--porcelain'])['stdout'],
                                   'user_config_unchanged': user_config_snapshot() == spec['user_config_before']})
        summarize(batch, [])
        return
    fetch_definitions(batch)
    rows, total, blockers = [], Decimal('0'), 0
    model = 'claude-sonnet-5-5'
    reason = 'completed'
    for condition, repetition in trial_order(conditions, args.reps):
        while True:
            # Recheck sessions before every call; no child Agent tool exists.
            agents = command(spec['cli'] + ['agents', '--json', '--all'])
            save(batch / f'agents-before-{condition}{repetition}.json', agents)
            row, result, error = run_one(batch, spec, condition, repetition, model, Decimal('8') - total)
            rows.append(row); summarize(batch, rows)
            if result is None or result.get('total_cost_usd') is None:
                reason = 'missing_provider_accounting'; break
            total += Decimal(str(result['total_cost_usd']))
            if row['status'] == 'timeout' or total >= Decimal('8') or row['status'] in ('isolation_failed', 'non_sonnet_model'):
                reason = row['status'] if total < Decimal('8') else 'budget_stop'; break
            # Exhausting a trial's turn budget is an outcome failure, not a
            # provider/authentication blocker; still grade and run other trials.
            failed = row['status'] != 'error_max_turns' and (bool(result.get('is_error')) or row['status'] in ('missing_result', 'error_during_execution'))
            if failed:
                blockers += 1
                text = json.dumps(result) + error
                model_rejected = re.search(r'invalid[_ ]model|model[^\n]{0,120}(?:not found|not available|does not exist|not supported|rejected)|not authorized[^\n]{0,120}model', text, re.I)
                if blockers < 2 and model and model_rejected:
                    # Preserve rejected attempt; second attempt has its own artifact directory.
                    (batch / f'{condition}{repetition}').rename(batch / f'{condition}{repetition}-rejected-model')
                    rows[-1]['artifact'] += '-rejected-model'
                    save(batch / f'{condition}{repetition}-rejected-model/summary.json', rows[-1])
                    model = None
                    continue
                if blockers < 2:
                    (batch / f'{condition}{repetition}').rename(batch / f'{condition}{repetition}-blocked-attempt')
                    rows[-1]['artifact'] += '-blocked-attempt'
                    save(batch / f'{condition}{repetition}-blocked-attempt/summary.json', rows[-1])
                    continue
                reason = 'provider_blocker'; break
            break
        if reason != 'completed':
            break
        if snapshot_repo() != before:
            reason = 'repository_changed'; break
    save(batch / 'stop.json', {'reason': reason, 'captured_total_cost_usd': str(total), 'attempts': len(rows)})
    save(batch / 'safety.json', {'repository_contents_unchanged': snapshot_repo() == before,
                               'git_status_after': command(['git', 'status', '--porcelain'])['stdout'],
                               'user_config_unchanged': user_config_snapshot() == spec['user_config_before'],
                               'user_config_after': user_config_snapshot()})
    summarize(batch, rows)
    print(json.dumps({'reason': reason, 'cost': str(total), 'attempts': len(rows)}), flush=True)


if __name__ == '__main__':
    main()
