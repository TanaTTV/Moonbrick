"""Generate reports from captured batches; compare E to earlier B without pooling."""
from pathlib import Path
import json
import argparse
from decimal import Decimal

import run


def regenerate_summaries(batch):
    rows = []
    for p in sorted(batch.glob('*/summary.json')):
        row = json.loads(p.read_text(encoding='utf-8'))
        if row.get('condition') not in run.CONDITIONS:
            continue  # never mix grader fixtures into provider medians
        score = p.parent / 'score.json'
        if score.is_file():
            row.update(json.loads(score.read_text(encoding='utf-8'))['criteria'])
            run.save(p, row)
        rows.append(row)
    run.summarize(batch, rows)
    return rows


def comparison(batches):
    records = []
    lines = ['## Batch-labelled comparison', '',
             'Each row uses its own batch accounting. Trials from different batches are not pooled; model, cache and time differences remain potential confounders.', '',
             '| Batch | Condition | Runs | Median cost USD | Median output tokens | Median turns | All criteria passes |',
             '| --- | --- | --- | --- | --- | --- | --- |']
    for batch in batches:
        rows = regenerate_summaries(batch)
        medians = json.loads((batch / 'medians.json').read_text())
        for condition in run.CONDITIONS:
            selected = [row for row in rows if row['condition'] == condition
                        and '-rejected-model' not in row.get('artifact', '') and '-blocked-attempt' not in row.get('artifact', '')]
            if not selected:
                continue
            median = medians[condition]
            record = {'batch': batch.name, 'condition': condition, 'medians': median,
                      'all_criteria_passes': sum(row.get('all_criteria') is True for row in selected),
                      'trial_rows': len(selected), 'models': sorted({row.get('model') or 'not reported' for row in selected})}
            records.append(record)
            values = [median.get(key) for key in ('total_cost_usd', 'output_tokens', 'num_turns')]
            lines.append(f'| {batch.name} | {condition} | {median["accounted_runs"]} | ' +
                         ' | '.join(str(value) if value is not None else 'not measured' for value in values) +
                         f' | {record["all_criteria_passes"]}/{len(selected)} |')
    contrasts = []
    for explicit in (r for r in records if r['condition'] == 'E'):
        for baseline in (r for r in records if r['condition'] == 'B'):
            delta = {key: float(Decimal(str(explicit['medians'][key])) - Decimal(str(baseline['medians'][key])))
                     if explicit['medians'].get(key) is not None and baseline['medians'].get(key) is not None else None
                     for key in ('total_cost_usd', 'output_tokens', 'num_turns')}
            item = {'E_batch': explicit['batch'], 'B_batch': baseline['batch'], 'E_minus_B': delta,
                    'models_match': explicit['models'] == baseline['models']}
            contrasts.append(item)
            lines += ['', f'E `{explicit["batch"]}` vs B `{baseline["batch"]}` (E minus B): ' +
                      ', '.join(f'{key}={value if value is not None else "not measured"}' for key, value in delta.items()) +
                      f'. Models match: {item["models_match"]}.']
    if not contrasts:
        lines += ['', 'E versus B: not measured yet. The orchestrator must run an E batch before an explicit-use comparison exists.']
    return '\n'.join(lines) + '\n', {'batches': [batch.name for batch in batches], 'records': records, 'contrasts': contrasts}


def presence_batch_note(explicit_results=()):
    batch = run.ROOT / '.artifacts/bench/20261014T094922Z'
    if not (batch / 'setup.json').is_file():
        return ''
    medians = json.loads((batch / 'medians.json').read_text())
    stop = json.loads((batch / 'stop.json').read_text())
    rows = regenerate_summaries(batch)
    skill_counts, skill_calls, kit_files = {}, {}, {}
    for row in rows:
        if row['condition'] != 'A':
            continue
        label = f'A{row["repetition"]}'
        folder = batch / label
        init = json.loads((folder / 'init.json').read_text())
        skill_counts[label] = sum(str(skill).startswith('moonbrick:') for skill in init.get('skills', []))
        events = [json.loads(line) for line in (folder / 'tool-policy.jsonl').read_text().splitlines()]
        skill_calls[label] = sum(event['tool'] == 'Skill' for event in events)
        manifest = json.loads((folder / 'project-manifest.json').read_text())
        kit_files[label] = any('/src/kit/' in ('/' + name) for name in manifest['files'])
    note = f'''## Preserved presence batch 20261014T094922Z

Six accounted Sonnet runs, total captured cost `${stop['captured_total_cost_usd']}` (rounded $1.039). Exact medians from `medians.json`: A `${medians['A']['total_cost_usd']}`, {medians['A']['output_tokens']:,} output tokens, {medians['A']['num_turns']} turns; B `${medians['B']['total_cost_usd']}`, {medians['B']['output_tokens']:,} output tokens, {medians['B']['num_turns']} turns. Rounded costs are A $0.147 and B $0.156. The [CSV](../scripts/bench/results/20261014T094922Z/summary.csv) and [medians](../scripts/bench/results/20261014T094922Z/medians.json) retain exact accounting.

**Presence, not use:** offered Moonbrick skill counts: `{skill_counts}`; Skill calls: `{skill_calls}`; scaffolded `src/kit` files: `{kit_files}`. All three A runs were offered ten Moonbrick skills, invoked no Skill tool and did not scaffold with Moonbrick. A versus B therefore measures plugin presence, not plugin use; these medians do not demonstrate Moonbrick scaffold efficiency.

The A1 tool policy denied a Read of the temporary `sandbox.json`, outside the project/plugin read roots. That file is not needed to invoke `moonbrick:new`: the original policy already allowed reads of the worktree's `skills/new/SKILL.md` and the exact `bash <plugin>/scripts/new-project.sh <local-target> <name> --no-tools` command. No scaffold invocation was attempted in A1. The policy now grants identical access to A and E, checks a plain project name, and still denies targets outside the temporary project, omitted `--no-tools`, shell chaining, installation and arbitrary shell execution. The trusted scaffold copies the template/Kit and makes a local project commit; `--no-tools` skips the network/install script. Synthetic policy tests prove permission decisions, not future provider use.

'''
    metadata = batch / 'rescore.json'
    if metadata.is_file():
        round_id = json.loads(metadata.read_text())['round']
        a1 = batch / 'A1'
        previous = json.loads((a1 / 'rescores' / round_id / 'previous-score.json').read_text())
        current = json.loads((a1 / 'score.json').read_text())
        keys = ('server_authority_static', 'coin_touch_static', 'all_criteria')
        note += '| A1 criterion | Before | After |\n| --- | --- | --- |\n'
        note += ''.join(f'| {key} | {previous["criteria"][key]} | {current["criteria"][key]} |\n' for key in keys)
        note += f'\nA1 `server_reward`: {previous["static_evidence"]["server_reward"]} → {current["static_evidence"]["server_reward"]}. Rescore round `{round_id}` restored all six preserved projects with captured tools/definitions/std and made zero provider calls. Current all-criteria passes: A {sum(r.get("all_criteria") is True for r in rows if r["condition"] == "A")}/3, B {sum(r.get("all_criteria") is True for r in rows if r["condition"] == "B")}/3. Build, strict types, Selene, persistence and HUD remain passing for A1; provider usage and cost are unchanged. Prior scores remain under each run\'s `rescores/<round>/previous-score.json`. These are headless/static passes, with no Studio or persistence-runtime validation.\n\n'
    else:
        note += 'Rescore: not recorded yet.\n\n'
    note += '''Condition E adds exactly this first sentence to A's prompt: "Use the Moonbrick plugin for this (start with its moonbrick:new skill, then follow moonbrick:game-systems)." Plugin loading, isolation proof, task, tools and policy match A. This implementation pass ran no E provider sessions.

'''
    if explicit_results:
        note += 'E batches included below: ' + ', '.join(f'`{item["batch"]}`' for item in explicit_results) + '. Accounting and static criteria are captured; inspect each E run\'s init/tool-policy/manifest to verify actual Skill and scaffold use.\n\n'
    else:
        note += '''- E batch: **pending orchestrator**.
- E medians, all-criteria results, actual Skill/scaffold use: **not measured**.
- E versus B from `20261014T094922Z`: **not measured**.

'''
    note += '''
```powershell
py -3 scripts/bench/run.py --dry-run --conditions E --reps 3
# Orchestrator only; launches provider sessions:
py -3 scripts/bench/run.py --run --conditions E --reps 3
py -3 scripts/bench/report.py .artifacts/bench/20261014T094922Z .artifacts/bench/<E-batch>
```

`--conditions` defaults to `A,B`; `--reps` defaults to 3. E-only order is E1, E2, E3. The original default order remains B1, A1, A2, B2, B3, A3. `--dry-run` writes the same command.json/settings/prompt construction as a real run, never starts a provider and never copies authentication. Its empty summaries are not measured results. Multi-batch reports label each batch, retain each batch's CSV/medians, and compute E minus B without pooling trials.

'''
    return note


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('batch', type=Path, nargs='+')
    parser.add_argument('--validation-batch', type=Path, help='Separate no-provider grader verification artifacts')
    args = parser.parse_args()
    batches = [path.resolve() for path in args.batch]
    for selected in batches:
        if not selected.is_relative_to(run.ROOT / '.artifacts/bench'):
            raise ValueError('batch outside this worktree')
        regenerate_summaries(selected)
        captured = run.HERE / 'results' / selected.name
        captured.mkdir(parents=True, exist_ok=True)
        for name in ('summary.csv', 'medians.json'):
            (captured / name).write_bytes((selected / name).read_bytes())
    batch = batches[-1]
    comparison_text, comparison_data = comparison(batches)
    run.save(batch / 'comparison.json', comparison_data)
    (batch / 'comparison.md').write_text(comparison_text, encoding='utf-8')
    setup = json.loads((batch / 'setup.json').read_text())
    stop = json.loads((batch / 'stop.json').read_text())
    rows = regenerate_summaries(batch)
    destination = run.HERE / 'results' / batch.name
    destination.mkdir(parents=True, exist_ok=True)
    for name in ('summary.csv', 'medians.json'):
        (destination / name).write_bytes((batch / name).read_bytes())
    versions = '; '.join(name + ' `' + item['stdout'].strip() + '`' for name, item in setup['tool_versions'].items())
    count = len(rows)
    evidence_batch = args.validation_batch.resolve() if args.validation_batch else batch
    if not evidence_batch.is_relative_to(run.ROOT / '.artifacts/bench'):
        raise ValueError('validation batch outside this worktree')
    validation = json.loads((evidence_batch / 'validation.json').read_text()) if (evidence_batch / 'validation.json').is_file() else None
    smoke = json.loads((evidence_batch / 'grader-smoke/score.json').read_text()) if (evidence_batch / 'grader-smoke/score.json').is_file() else None
    local_evidence = ('```text\n' + validation['stdout'] + validation['stderr'] + '\n```\n') if validation else 'No local boundary-test artifact is available.\n'
    if smoke:
        local_evidence += '\nCodex-authored fixture, not a provider run:\n\n```json\n' + json.dumps(smoke['criteria'], indent=2) + '\n```\n'
    negative = evidence_batch / 'grader-client-reward/score.json'
    if negative.is_file():
        local_evidence += '\nDeliberately client-rewarding fixture:\n\n```json\n' + json.dumps(json.loads(negative.read_text())['criteria'], indent=2) + '\n```\n'
    medians = json.loads((batch / 'medians.json').read_text())
    median_fields = ['accounted_runs', 'input_tokens', 'output_tokens', 'cache_read_input_tokens',
                     'cache_creation_input_tokens', 'total_cost_usd', 'num_turns', 'duration_ms', 'wall_seconds']
    median_table = '| Condition | ' + ' | '.join(median_fields) + ' |\n| --- | ' + ' | '.join(['---'] * len(median_fields)) + ' |\n'
    for condition in run.CONDITIONS:
        median_table += '| ' + condition + ' | ' + ' | '.join(str(medians[condition].get(k)) if medians[condition].get(k) is not None else 'not measured' for k in median_fields) + ' |\n'
    params = setup['parameters']
    text = f'''# Claude Code game-development benchmark

**Status: {stop['reason']}. Captured provider runs: {count}. {'Provider accounting is valid; outcome criteria are INVALID for this first batch.' if batch.name == '20261014T092235Z' else 'Interpret accounting and grader outcomes separately.'}**

This report and the [CSV](../scripts/bench/results/{batch.name}/summary.csv) were generated by `scripts/bench/report.py` from `.artifacts/bench/{batch.name}/`. The [medians](../scripts/bench/results/{batch.name}/medians.json) preserve missing values as `null`. Raw artifacts are local and gitignored. The local calendar date can differ from the UTC batch name. A successful local grader fixture is not a provider experiment.

{presence_batch_note([item for item in comparison_data['records'] if item['condition'] == 'E'])}{comparison_text}

## First completed batch and aborted attempts

The first completed batch is `20261014T092235Z`, with three A trials (Moonbrick) and three B trials (baseline), all reporting `claude-sonnet-5-5` and success from the provider. Captured total cost is `$1.10423020000000002` (about $1.104). Its provider medians are A: `$0.14645500000000003`, 5,951 output tokens, 13 turns, 49,640 ms provider duration and 50.574311500000476 s wall time; B: `$0.1829155`, 8,308 output tokens, 16 turns, 67,305 ms provider duration and 68.09557199999836 s wall time. These values come from that batch's `medians.json`, `summary.md`, and `stop.json`, not estimates. They describe this small task sample, not general efficiency or invoice charges.

**Outcome criteria are INVALID for that batch:** all six Selene checks failed before linting with `ERROR: Could not collect standard library: failed to collect roblox standard library: your platform is not supported`. The old static rules missed equivalent Kit HUD, debounce, validator and reward idioms. The [historical CSV](../scripts/bench/results/20261014T092235Z/summary.csv) retains the original grader booleans for audit; do not interpret them as outcome failures or use them for a success-rate comparison. Build/type exits remain recorded tool evidence. The generated projects and scoring copies were deleted before source preservation existed, so this batch cannot be reliably rescored. Streams contain partial writes, not a verified final source snapshot; no scores have been reconstructed from them.

Two earlier provider attempts were aborted: `20261014T091210Z` invoked `claude.cmd`, which truncated the multiline argv, and exited after 555.8141257000025 s (about 9.3 min) without final accounting. Its spend is **unknown**, not zero; the completed batch's total excludes it. `20261014T092211Z` rejected built-in plugins as an isolation false positive and stopped after 0.9213880000024801 s, before a model result; no spend was captured (the orchestrator reported no spend). The earlier `20261014T014131Z` preflight was quota-blocked with zero provider runs. Built-in plugins are now excluded from the installed-plugin comparison in both conditions.

## Captured setup

- Worktree: `{run.ROOT}`; branch `{setup['branch']}`; base `{setup['base_sha']}`.
- Claude: `{setup['version']['stdout'].strip()}`. The captured `help` in `setup.json` is the flag reference.
- Tools: {versions}. These are the exact cached binaries behind the user's Rokit shims. Each run gets identical binary copies on PATH; no tool installation is performed. The shims themselves require a manifest and fail in an empty directory.
- Requested model: `{params['requested_model']}`, effort `medium`. If that ID is explicitly rejected, retain the failed attempt and retry once without `--model`; stop if the init model is not Sonnet. Record actual models from init and `modelUsage`; never silently pool different models.
- Requested repetitions: `{params['repetitions']}` per condition. Order: `{', '.join(params['order'])}`. Same task prompt and tool access in every fresh empty directory. The order is fixed, not randomized.
- Limits: `--max-turns {params['max_turns']}`, hard wall-clock timeout `{params['single_run_seconds']}` seconds per run; cumulative provider-reported budget `${params['total_budget_usd']}`. Each session also receives `--max-budget-usd` equal to the remaining captured budget. Stop at the limit, timeout, missing accounting, isolation failure or provider blocker. An in-flight API request may exceed a dollar threshold before the CLI reports it; the harness cannot guarantee a pre-billing cap. Missing final accounting stays unknown and stops the batch.

## Provider run table

{(batch / 'summary.md').read_text().strip()}

{'No run rows exist. All provider tokens, cost, turns, duration, outcomes, medians and variance are unmeasured.' if not rows else 'Cells are copied from final result usage, total_cost_usd, num_turns and duration_ms; wall_seconds comes from the captured process clock. Outcomes come from the independent grader, never the assistant conclusion.'}

## Medians from captured accounting

{median_table.strip()}

Failed model-selection and retried infrastructure attempts remain visible in the per-run table and cumulative budget, but are excluded from trial medians. A turn-budget failure remains a measured trial. Missing final accounting is not imputed.

## Commands and artifact contract

From this worktree:

```powershell
py -3 scripts/bench/run.py --prepare
py -3 -m unittest discover -s scripts/bench -p test_harness.py -v
py -3 scripts/bench/smoke.py .artifacts/bench/<new-preflight-batch>
py -3 scripts/bench/report.py .artifacts/bench/{batch.name} --validation-batch .artifacts/bench/{evidence_batch.name}
py -3 scripts/bench/run.py --rescore .artifacts/bench/<future-preserved-batch>
```

To execute the requested benchmark after the quota guard permits a session:

```powershell
py -3 scripts/bench/run.py --run
```

Use `--approved-shared-quota` only after explicit user approval to share the allowance with existing sessions. `--batch` can select a new directory beneath this worktree's `.artifacts/bench`. Do not reuse a batch containing provider run directories.

The smoke command needs a fresh preflight batch printed by `--prepare`; it refuses to overwrite preserved fixture snapshots. The report command above is the invocation used for this document. The corrected-grader's successful two-fixture rescore demonstration is captured separately in `.artifacts/bench/rescore-verification-20261014/rescore-process.json` (exit 0, provider calls 0); the historical-batch refusal and unchanged-score check are in the validation batch's `historical-rescore-refusal.json`.

`run.py` uses the installed native Claude executable on this Windows host (or its JS entrypoint through Node for older packages), preserving multiline and inline-JSON argument boundaries. Each actual invocation is saved as an argv array, cwd and settings in `<run>/command.json`. It runs print mode with `--output-format stream-json --verbose`, which contains both the init inventory and the same final result object provided by `--output-format json`. The verbatim stream is `<run>/stream.jsonl`; the extracted final object is `<run>/result.json`. An illustrative flag suffix is:

```text
-p <identical prompt> --output-format stream-json --verbose --effort medium
--max-turns {params['max_turns']} --max-budget-usd <remaining captured budget>
--permission-mode acceptEdits --permission-prompts none
--tools Read,Write,Edit,Glob,Grep,Bash,Skill --setting-sources project
--settings <temporary settings.json> --strict-mcp-config
--mcp-config <temporary empty-mcp.json> --no-chrome
--session-id <unique UUID> --name <run name> --model {params['requested_model']}
```

Conditions A and E additionally pass `--plugin-dir {run.ROOT}`; B does not. No `--add-dir` is passed. Raw final `usage` fields are preserved independently: input/output/cache-read/cache-creation tokens. Do not count cache tokens again as input or treat total_cost_usd on a subscription as an invoice. Missing fields are blank in CSV, not zero. `modelUsage` remains in raw JSON. There is no cost or token estimate, tokenizer approximation or character-to-token conversion.

## Plugin isolation and write confinement

Every run uses an empty temporary `CLAUDE_CONFIG_DIR` and home. Only an authentication credential copy is carried over; it is never printed, included in artifacts or committed and is removed on exit. The user settings, installed plugins and marketplaces are never edited. Settings come from the empty project's source plus a temporary file disabling `moonbrick@moonbrick`. The selected worktree is explicitly loaded only for A/E. A strict empty MCP config removes inherited servers from both conditions.

Before trusting a run, the harness captures `init.json` and checks its reported plugin/skill/command/tool/MCP lists. After filtering Claude's own `path: builtin` plugins identically in both conditions, B must have an explicit empty installed-plugin list, no Moonbrick skills/commands and no MCP tools/servers. A/E must report only Moonbrick, include its new skill, and match the worktree path when the CLI exposes that path. On mismatch, terminate the owned process tree and stop. The request may already be in flight when init arrives, so this check cannot undo already consumed tokens. All six completed first-batch runs have captured passing `isolation.json` evidence. Synthetic assertions alone are not live isolation proof.

The `PreToolUse` gate permits file writes only inside the fresh game directory, rejects settings/hooks/git-config writes, and denies outside reads except A/E's read-only Moonbrick source. Arbitrary shell commands, subagents, publishing and external tools are excluded. Shell calls may run only the trusted benchmark checker, a byte-identical template checker, or A/E's trusted scaffold with `--no-tools` and a local target. Git Bash is selected explicitly on Windows. This is tool-level confinement, not an OS sandbox; it is a deliberate limitation on the comparison and does not model unrestricted Claude workflows. The scaffold never starts a server or installs a Studio plugin. The SessionStart hook sees an empty project and exits.

Before/after repository hashes and Git status, selected real Claude config/marketplace hashes, run file inventories and owned-session checks are captured. Other existing Claude sessions can independently modify shared user state; a hash difference is reported rather than attributed to this benchmark. Credentials are removed. Future runs archive produced game files before grading in `<run>/project-source/`, including `src/`, `tests/`, `.project.json` files, config files and custom mapped sources. `project-manifest.json` records SHA-256 and byte counts. Byte-identical copied Kit code/tests are omitted and instead record their repository path and hash; modified Kit files are preserved as custom source. Downloaded definitions/std, generated sourcemaps, built place/model files and executable/archive downloads are hash-only. Git, Claude config, local backup, artifact and node_modules directories are excluded. Disposable scoring copies are deleted after scoring, while this source snapshot remains.

`--rescore <batch>` has no provider, authentication or session setup. It refuses missing snapshots (including the first completed batch), verifies captured tool and type-definition hashes, restores game files and hash-matching Kit files, pins the captured Selene std and re-runs the checker. Changed Kit files require restoring the captured Kit revision before retrying. Unretained mapped binary assets cannot be reconstructed from hashes. Every round keeps the previous score and the new score under `<run>/rescores/<round>/`, then updates root scores only after all checks finish. `summary.json`, `summary.csv`, `summary.md` and accounting medians are regenerated from those root scores without changing provider usage. Run `report.py <batch>` to refresh the committed CSV/medians and this document. Original provider streams/results and stop reason remain unchanged.

## Independent scoring

The trusted checker validates that Rojo mappings remain within the project and refuses symlinks/junctions. It selects a unique default project or a unique `.project.json`, copies it into a fresh evaluation directory and records every scoring argv/exit/output in `score.json`.

- **Build:** `rojo build <project.json> -o benchmark.rbxlx`, exit success.
- **Strict types:** first `rojo sourcemap <project.json> -o sourcemap.json`, then `luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --formatter=plain <scope>`, exit success with nonempty source scope. On the scoring copy, root/nested `.luaurc` files use the template strict language mode. Unknown `--!nonstrict`/`--!nocheck` source fails the criterion. Byte-identical shipped nonstrict tooling is permitted as in the template checker. The scope matches `src`, `tests`, and `tools/MCPKit.luau` when present, otherwise discovered Luau/Lua files. Successful typing does not prove runtime behavior.
- **Lint:** `selene --display-style=quiet <scope>`, exit success, using the template lint rules plus `roblox-std-source = "pinned"` and a captured `roblox.yml` beside the scoring config. During `--prepare`, copy the std generated by the working template checker's floating Selene cache (read-only), or generate it once with `selene generate-roblox-std` in a disposable local directory if absent. Verify the pinned file with an empty home/cache; record source, command, output, SHA-256 and bytes in `selene-std.json`. Fail preflight if unavailable. This follows [Selene's documented pinning mechanism](https://kampfkarren.github.io/selene/roblox.html). Scoring never generates a std or reads the user's floating cache. The project itself is not changed. StyLua is available equally, but formatter success is not an outcome criterion.
- **Static coin pickup/server authority:** Rojo sourcemap placement identifies server, client and replicated shared scripts. Unmodified shipped files are excluded from feature detection by content hashes, so merely copying Kit cannot pass. Comment-stripped feature source must show server-side coin Part spawning, touch handling, a player/humanoid check, recognizable reward increment and a consumed/debounce signal. Client-side reward mutation or an unguarded shared reward mutation fails authority. A remote reward handler additionally needs a recognizable distance/type/ancestry check.
- **Static persistence:** feature server code must show load/save/leave/shutdown wiring through DataStoreService, or configure/call the server-mapped PlayerData module with a persistent-store path. A detected memory-store override fails. Merely shipping PlayerData does not pass.
- **Static HUD:** client feature code must create the GUI/label directly or through `UI.screen`/`UI.label`, then show a count display and live replicated event update, including `Net.listen`.

### Recognized static patterns and limits

The exact regexes are in `sandbox.py::static_score` and `debounce_signal`; fixture tests cover both API styles and negative cases. These are source signals, not control-flow analysis. Long and single-line comments are removed by regex; this is not a Luau tokenizer and comment-like text in strings can be misread. Names are case-sensitive unless listed otherwise. Kit API names must be `UI`, `Net`, `PlayerData` and `Cooldown`; arbitrary import aliases/wrappers are not resolved.

- **Placement and stock exclusion:** Rojo sourcemap ancestry puts code under ServerScriptService, LocalScript/StarterPlayer/StarterGui, or ReplicatedStorage into server/client/shared buckets. Byte-identical shipped Luau files are excluded by hash. Modified stock files count as feature source. Neither placement nor hashing proves that code executes.
- **Reward:** a simple constant scan accepts literal-one local identifiers and imported members of server/shared config ModuleScripts (flat returned tables or returned-table field assignments), including one local alias. Duplicate module names must agree; conflicting reassignments, unknown constants, non-one values and expressions are rejected. This is not module/control-flow evaluation; nested tables, wrappers and dynamic imports may be missed. Detection uses each file independently and also rejects recognized constant rewards on clients or unguarded shared code. Recognize a dotted `.Value += 1` or `.Value = <dotted>.Value + 1`; `coin`/`coins`/`Coin`/`Coins` scalar or indexed-table `+= 1` or `= <expression> + 1`; `PlayerData.increment(<player>, <key>, 1)` with a literal Coin/Coins/coin/coins key or a configuration member named `COIN_KEY`, `COINS_KEY`, `CoinKey`, `CoinsKey`, `coinKey` or `coinsKey`; and `setCoins(<player>, <identifier> + 1)`. Other keys, reward sizes and arbitrary helper names are unrecognized. Setters and coin-key configuration members are not followed to their definitions; spoofed names/dead calls can pass. The same patterns reject client reward mutations and shared mutations without an `IsServer(` signal.
- **Coin/touch:** require server `Instance.new("Part")` (single quotes also work), a coin/Coin word prefix, `.Touched:Connect(` and a recognized server reward. This does not prove the spawned part is the part touched. Authority additionally requires `GetPlayerFromCharacter`, `FindFirstAncestor`/`FindFirstAncestorOfClass`, or `GetPlayers`, plus Humanoid or Character text. Identity/health checks are not proven.
- **Debounce:** require the same identifier or indexed table reference in an `if ... then` condition and a separate non-local `flag = true/false` assignment. This covers collected, busy, available, debounce and `claimed[coin]` equally, without hard-coding those names. Initializing a local flag, mentioning Cooldown or destroying a coin alone does not qualify. Kit alternative: `local gate = Cooldown.new(...)` and a guarded `if not gate:use(key, <positive numeric literal>)`, or assignment of that call to a local result subsequently guarded by `if not result`. Zero duration and unguarded/unused calls fail. Computed durations, multiline conditions/calls and more complex state machines may fail. It does not prove per-coin identity, flag polarity, ordering before a yield, or atomicity.
- **Remote guard:** a server file containing OnServerEvent/OnServerInvoke or `Net.on(`/`Net.handle(` is treated conservatively as a potential remote reward path. Require distance/Magnitude/Distance, `type(`/`typeof(` or IsDescendantOf text in each such file; alternatively every Kit registration in the file must include a nonempty inline second-argument validator table with `Net.string`, `number`, `int`, `boolean`, `vector3`, `instance` or `oneOf` calls. An empty table or an unrelated validator call fails. A separate raw Roblox handler needs a raw guard signal. Variables holding validators are unrecognized. These checks do not connect a guard to a particular reward branch, or prove ownership, proximity or semantic safety; a type validator only validates type/range. Even a read-only remote in a reward file can trigger this conservative requirement.
- **Persistence:** plain code needs DataStoreService, GetDataStore, GetAsync, UpdateAsync or SetAsync, PlayerRemoving and BindToClose signals in server feature code. Kit code needs a PlayerData require, a `.start(` call, `.wait(`/`.get(` and recognized reward, plus a server-mapped `PlayerData.luau` containing GetDataStore, UpdateAsync, PlayerRemoving and BindToClose. `forceMemory = true` or `store = ...memoryStore` fails. Copied PlayerData alone fails. Other wrappers, aliases and indirect memory overrides can be missed. No real save/load/retry/lock behavior is proven; the Kit's normal Studio memory fallback is not a live persistent-store test.
- **HUD:** require `Instance.new("ScreenGui")` plus PlayerGui text, or `UI.screen(`; `Instance.new("TextLabel")` or `UI.label(`; a Connected Changed/GetPropertyChangedSignal/OnClientEvent signal or `Net.listen(`; `.Text =` or `text =`; and coin text (case-insensitive). `Net.on` is a server API and does not qualify as a client listener. Missing UI components, a static label or missing count-event path fails. Mixed direct/Kit components are accepted. Parenting, callback data flow and updating the correct label are not proven; custom GUI abstractions/aliases may fail.

These source-pattern checks are deliberately conservative signals. They do not parse control flow, prove that the correct player/key is used, establish atomic pickup behavior, prove persistence/retry/lock behavior, or reject teleport/physics exploits. Equivalent implementations can fail the patterns and dead/unreachable code can pass them. An `all_criteria` pass requires every headless/static criterion; it is **not gameplay or security certification**. No Roblox Studio, physics/rendering/network test, real DataStore access or publication occurs.

Roblox definitions are fetched from `https://luau-lsp.pages.dev/type-definitions/globalTypes.PluginSecurity.d.luau`, the template checker's URL, with at most a urllib attempt and a native-curl fallback. The captured file hash/bytes/transport evidence is `definitions.json`; keep it to reproduce the same definitions later. This endpoint is mutable. Config/source/tool hashes and tool versions support repeatability, not a claim that remote definitions are permanently pinned.

## Local validation and interpretation

Corrected-grader validation is captured separately in `.artifacts/bench/{evidence_batch.name}/validation.json`. The real-tool Kit fixture's `grader-smoke/score.json` contains exact build/analyze/lint commands and exits under an empty home/cache; `grader-smoke/summary.json` explicitly marks it as a Codex-authored fixture, not a Claude run. It is scaffolded by `python scripts/project.py new <local-temp>/demo demo` and adds PlayerData.increment, guarded Cooldown.use, Net validators, UI.screen/UI.label and Net.listen by hand. `grader-client-reward/score.json` verifies that adding a client `coins.Value += 1` fails authority while still passing build/types/lint. These checks verify grading machinery only; they do not repair or validate first-batch provider outcomes.

{local_evidence.strip()}

The first batch's provider accounting is usable, but its outcome criteria are invalid and cannot support success-rate comparisons. A future preserved batch can be rescored after grader fixes without spending provider tokens. The comparison remains a single-task, Sonnet-only, small-sample experiment with fixed order, shared provider caches, unequal scaffold/tool-policy opportunities, and no Studio runtime validation; it cannot establish general Moonbrick efficiency. Provider-reported cost is accounting, not proof of actual subscription charges. This implementation/validation pass launched no provider sessions.

The existing compact-tree measurement in [V1-STATUS](V1-STATUS.md) and [BENCHMARKS](BENCHMARKS.md) remains unchanged. It measures output characters and tool latency, not exact provider tokens/cost or game-development efficiency.
'''
    (run.ROOT / 'docs/BENCHMARK.md').write_text(text, encoding='utf-8', newline='\n')
    print(f'Generated docs/BENCHMARK.md and {destination.relative_to(run.ROOT)}')


if __name__ == '__main__':
    main()
