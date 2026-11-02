"""Hook behaviour from fixture JSON, through the real run.sh entry point where it matters."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("moonbrick_hooks", ROOT / "scripts/hooks/moonbrick_hooks.py")
hooks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hooks)
BASH = os.environ.get("MOONBRICK_BASH") or (r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else shutil.which("bash"))

TREE = {
    "$className": "DataModel",
    "ReplicatedStorage": {"Shared": {"$path": "src/shared"}, "Kit": {"$path": "src/kit/shared"}},
    "ServerScriptService": {"Server": {"$path": "src/server"}},
    "ServerStorage": {"MCPKit": {"$path": "tools/MCPKit.luau"}},
    "Workspace": {"World": {"$path": "src/world"}},
}


class HookCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.project = self.base / "game"
        (self.project / "tools").mkdir(parents=True)
        (self.project / "src/server").mkdir(parents=True)
        (self.project / "default.project.json").write_text(json.dumps({"name": "game", "tree": TREE}))
        (self.project / "tools/MCPKit.luau").write_text("return {}")
        (self.project / "tools/check.sh").write_text("#!/bin/sh\n")
        self.state = self.base / "state"
        env = patch.dict(os.environ, {"TMPDIR": str(self.state), "CLAUDE_PROJECT_DIR": str(self.project)})
        env.start()
        self.addCleanup(env.stop)

    def payload(self, **fields):
        return {"session_id": "s1", "transcript_path": str(self.base / "t.jsonl"), "cwd": str(self.project), **fields}

    def post(self, name, tool_input=None, response=None, **fields):
        return hooks.on_post_tool(self.payload(hook_event_name="PostToolUse", tool_name=name, tool_input=tool_input or {}, tool_response=response or {}, **fields))


class PromptHook(HookCase):
    def ask(self, prompt, folder, **fields):
        with patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(folder)}):
            result = hooks.on_prompt(self.payload(prompt=prompt, cwd=str(folder), session_id=fields.pop("session", prompt[:20].replace(" ", "")), **fields))
        return result["hookSpecificOutput"]["additionalContext"] if result else None

    def empty(self):
        folder = self.base / "empty"
        folder.mkdir(exist_ok=True)
        return folder

    def test_empty_folder_suggests_new(self):
        self.assertIn("moonbrick:new", self.ask("make a Roblox game about pets", self.empty()))

    def test_output_shape_matches_the_cli_schema(self):
        with patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.empty())}):
            result = hooks.on_prompt(self.payload(prompt="a luau question", cwd=str(self.empty())))
        self.assertEqual(result["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
        self.assertEqual(result["hookSpecificOutput"]["additionalContext"].count("\n"), 0)

    def test_plain_rojo_project_suggests_import(self):
        folder = self.base / "rojo"
        folder.mkdir()
        (folder / "default.project.json").write_text("{}")
        line = self.ask("fix my Rojo sync", folder)
        self.assertIn("/moonbrick:import", line)
        self.assertNotIn("moonbrick:new", line)

    def test_silent_inside_a_moonbrick_project(self):
        self.assertIsNone(self.ask("add a Roblox shop", self.project))

    def test_silent_for_studio_alone_and_other_ides(self):
        for prompt in ("open it in Visual Studio", "my Android Studio build fails", "fix the Studio layout", "a recording studio website"):
            with self.subTest(prompt=prompt):
                self.assertIsNone(self.ask(prompt, self.empty()))

    def test_spanish_rojo_is_not_the_tool(self):
        self.assertIsNone(self.ask("pinta el coche de color rojo", self.empty()))
        self.assertIsNotNone(self.ask("rojo serve is failing", self.empty()))

    def test_only_once_per_session(self):
        folder = self.empty()
        self.assertIsNotNone(self.ask("a Roblox question", folder, session="same"))
        self.assertIsNone(self.ask("another Roblox question", folder, session="same"))

    def test_silent_when_moonbrick_is_already_named_or_for_automation(self):
        self.assertIsNone(self.ask("use moonbrick for my roblox game", self.empty()))
        self.assertIsNone(self.ask("roblox nightly", self.empty(), source="schedule_wakeup"))


class DirtyTracking(HookCase):
    def edit(self, path="src/server/Foo.server.luau", tool="Edit"):
        return self.post(tool, {"file_path": str(self.project / path), "old_string": "a", "new_string": "b"})

    def stop(self, **fields):
        return hooks.on_stop(self.payload(hook_event_name="Stop", stop_hook_active=fields.pop("active", False), last_assistant_message="done", **fields))

    def test_edit_then_stop_blocks_once(self):
        self.edit()
        first = self.stop()
        self.assertEqual(first["decision"], "block")
        self.assertIn("tools/check.sh", first["reason"])
        self.assertIn("Foo.server.luau", first["reason"])
        self.assertIsNone(self.stop())

    def test_stop_hook_active_is_honoured(self):
        self.edit("src/server/A.luau", "Write")
        self.assertIsNone(self.stop(active=True))

    def test_passing_check_clears(self):
        self.edit()
        self.post("Bash", {"command": "bash tools/check.sh"}, {"stdout": "OK\n", "stderr": "", "interrupted": False, "isImage": False})
        self.assertIsNone(self.stop())

    def test_check_on_an_absolute_or_windows_path_clears(self):
        for command in (f"bash {self.project.as_posix()}/tools/check.sh --fix", r"bash .\tools\check.sh"):
            with self.subTest(command=command):
                self.edit()
                self.post("Bash", {"command": command}, {"stdout": "OK"})
                self.assertIsNone(self.stop())

    def test_a_piped_failure_does_not_clear(self):
        self.edit()
        self.post("Bash", {"command": "bash tools/check.sh | tail -5"}, {"stdout": "src/x.luau:1: type error\nerror: luau-lsp exit=1\n"})
        self.assertEqual(self.stop()["decision"], "block")

    def test_other_commands_that_print_ok_do_not_clear(self):
        self.edit()
        self.post("Bash", {"command": "echo OK"}, {"stdout": "OK\n"})
        self.assertEqual(self.stop()["decision"], "block")

    def test_a_new_edit_after_the_reminder_reminds_again(self):
        self.edit()
        self.stop()
        self.edit("src/server/Other.luau")
        self.assertEqual(self.stop()["decision"], "block")

    def test_ignored_files(self):
        (self.base / "other").mkdir()
        for path in (str(self.project / "README.md"), str(self.base / "other/A.luau")):
            self.post("Edit", {"file_path": path})
        self.assertIsNone(self.stop())

    def test_project_without_a_checker_is_ignored(self):
        (self.project / "tools/check.sh").unlink()
        self.edit()
        self.assertIsNone(self.stop())


class RojoGuard(HookCase):
    def decide(self, file_path):
        result = hooks.on_pre_edit(self.payload(hook_event_name="PreToolUse", tool_name="mcp__Roblox_Studio__multi_edit", tool_input={"file_path": file_path, "edits": [], "datamodel_type": "Edit", "studio_id": "1"}))
        return result["hookSpecificOutput"] if result else None

    def test_mapped_script_is_denied_and_names_the_file(self):
        (self.project / "src/server/Main.server.luau").write_text("")
        output = self.decide("game.ServerScriptService.Server.Main")
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertEqual(output["permissionDecision"], "deny")
        self.assertIn("src/server/Main.server.luau", output["permissionDecisionReason"])

    def test_new_script_in_a_mapped_folder_gets_a_file_name(self):
        self.assertIn("src/server/New.luau", self.decide("ServerScriptService.Server.New")["permissionDecisionReason"])

    def test_file_mapping_and_nested_folders(self):
        self.assertIn("tools/MCPKit.luau", self.decide("game.ServerStorage.MCPKit")["permissionDecisionReason"])
        self.assertIn("src/shared/Data/Items.luau", self.decide("game.ReplicatedStorage.Shared.Data.Items")["permissionDecisionReason"])

    def test_other_path_spellings(self):
        for path in ('game:GetService("ServerScriptService").Server.Main', 'game["ServerScriptService"]["Server"].Main', "ServerScriptService/Server/Main", "game.ServerScriptService.Server.Main.luau"[:-5]):
            with self.subTest(path=path):
                self.assertIsNotNone(self.decide(path))

    def test_workspace_and_unmapped_scripts_stay_allowed(self):
        for path in ("game.Workspace.Door.Script", "workspace.Door.Script", "game.ServerScriptService.Legacy", "game.StarterGui.Menu.LocalScript"):
            with self.subTest(path=path):
                self.assertIsNone(self.decide(path))

    def test_imported_service_level_mapping_covers_every_child(self):
        tree = {"ServerScriptService": {"$path": "src/ServerScriptService", "Kit": {"$path": "src/kit/server"}}}
        (self.project / "default.project.json").write_text(json.dumps({"tree": tree}))
        self.assertIn("src/ServerScriptService/Combat.luau", self.decide("game.ServerScriptService.Combat")["permissionDecisionReason"])

    def test_tolerant_of_input_shapes(self):
        self.assertTrue(hooks.target_paths({"files": [{"file_path": "a"}, "b"], "path": "c"}))
        self.assertEqual(hooks.target_paths("nonsense"), [])
        self.assertEqual(hooks.target_paths({"edits": []}), [])

    def test_silent_without_a_project(self):
        with patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.base)}):
            self.assertIsNone(self.decide("game.ServerScriptService.Server.Main"))


class StudioClaim(HookCase):
    def transcript(self, *entries):
        path = self.base / "t.jsonl"
        path.write_text("\n".join(json.dumps(entry) for entry in entries) + "\n", encoding="utf-8")

    def user(self, text="do it"):
        return {"type": "user", "message": {"role": "user", "content": text}}

    def assistant(self, *names, text=""):
        blocks = [{"type": "tool_use", "name": name, "input": {}} for name in names]
        if text:
            blocks.append({"type": "text", "text": text})
        return {"type": "assistant", "message": {"role": "assistant", "content": blocks}}

    def result(self):
        return {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": "ok"}]}}

    def stop(self, message, active=False):
        return hooks.on_stop(self.payload(hook_event_name="Stop", stop_hook_active=active, last_assistant_message=message))

    def test_claim_without_a_call_blocks(self):
        self.transcript(self.user(), self.assistant("Read"), self.result())
        for message in ("Studio isn't connected, so I can't test this.", "The Roblox Studio MCP tools are not available in this session.", "I can't reach Studio right now.", "I don't have access to Studio.", "Studio is unavailable."):
            with self.subTest(message=message):
                result = self.stop(message)
                self.assertEqual(result["decision"], "block")
                self.assertIn("list_roblox_studios", result["reason"])

    def test_a_studio_call_this_turn_allows_the_claim(self):
        self.transcript(self.user(), self.assistant("mcp__Roblox_Studio__list_roblox_studios"), self.result())
        self.assertIsNone(self.stop("Studio isn't connected."))

    def test_a_call_in_an_earlier_turn_does_not_count(self):
        self.transcript(self.user("first"), self.assistant("mcp__Roblox_Studio__list_roblox_studios"), self.result(), self.user("second"), self.assistant("Read"), self.result())
        self.assertIsNotNone(self.stop("Studio is not connected."))

    def test_stop_hook_active_ends_it(self):
        self.transcript(self.user())
        self.assertIsNone(self.stop("Studio is unavailable.", active=True))

    def test_ordinary_messages_pass(self):
        self.transcript(self.user())
        for message in ("Done. Open Studio and click Connect.", "Studio is running and connected.", "Visual Studio is unavailable on this machine.", "Android Studio isn't running.", "The studio tools page looks better now."):
            with self.subTest(message=message):
                self.assertIsNone(self.stop(message))

    def test_outside_a_project_needs_the_word_roblox(self):
        self.transcript(self.user())
        with patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.base)}):
            self.assertIsNone(hooks.on_stop(self.payload(cwd=str(self.base), stop_hook_active=False, last_assistant_message="Studio is unavailable.")))
            self.assertIsNotNone(hooks.on_stop(self.payload(cwd=str(self.base), stop_hook_active=False, last_assistant_message="Roblox Studio is unavailable.")))

    def test_falls_back_to_the_transcript_for_the_message(self):
        self.transcript(self.user(), self.assistant(text="Studio is not connected."))
        self.assertIsNotNone(hooks.on_stop(self.payload(stop_hook_active=False)))

    def test_missing_transcript_never_blocks(self):
        self.assertIsNone(self.stop("Studio is unavailable."))


class LoopGuard(HookCase):
    def call(self, name="mcp__Roblox_Studio__execute_luau", **tool_input):
        return self.post(name, tool_input)

    def repeat(self, sequence, times):
        return [self.call(**item) for _ in range(times) for item in sequence]

    def warning(self, result):
        return result and result.get("hookSpecificOutput", {}).get("additionalContext", "")

    def test_period_one_needs_six(self):
        results = self.repeat([{"code": "x"}], 6)
        self.assertEqual(results[:5], [None] * 5)
        self.assertIn("loop guard", self.warning(results[5]))
        self.assertEqual(results[5]["hookSpecificOutput"]["hookEventName"], "PostToolUse")

    def test_periods_two_to_four_need_three(self):
        for period in (2, 3, 4):
            with self.subTest(period=period):
                sequence = [{"code": f"{period}-{index}"} for index in range(period)]
                results = self.repeat(sequence, 3)
                self.assertEqual(results[:-1], [None] * (len(results) - 1))
                self.assertIn("loop guard", self.warning(results[-1]))

    def test_second_trip_stops(self):
        self.repeat([{"code": "x"}], 6)
        results = self.repeat([{"code": "x"}], 6)
        self.assertEqual(results[:5], [None] * 5)
        self.assertIs(results[5]["continue"], False)
        self.assertIn("stopped", results[5]["stopReason"])

    def test_a_different_loop_gets_its_own_warning(self):
        self.repeat([{"code": "x"}], 6)
        self.assertIn("loop guard", self.warning(self.repeat([{"code": "y"}], 6)[5]))

    def test_whitespace_and_key_order_do_not_defeat_it(self):
        results = [self.call(code="a  b", n=1) for _ in range(3)] + [self.call(n=1, code="a b") for _ in range(3)]
        self.assertIsNotNone(results[5])

    def test_varied_calls_never_trip(self):
        self.assertEqual([self.call(code=str(i)) for i in range(40)], [None] * 40)

    def test_polling_is_exempt_and_does_not_break_a_pattern(self):
        for _ in range(10):
            self.assertIsNone(self.call("mcp__Roblox_Studio__wait_job_finished", id="1"))
            self.assertIsNone(self.call("mcp__Roblox_Studio__get_studio_state"))
            self.assertIsNone(self.call(code="return K.results()"))
            self.assertIsNone(self.call(code='return K.logs("Server", 20)'))

    def test_builtin_tools_outside_a_project_are_ignored(self):
        with patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.base)}):
            results = [hooks.on_post_tool(self.payload(cwd=str(self.base), tool_name="Read", tool_input={"file_path": "x"}, tool_response={})) for _ in range(8)]
        self.assertEqual(results, [None] * 8)

    def test_subagents_and_the_main_thread_count_separately(self):
        results = []
        for index in range(12):
            extra = {"agent_id": "sub"} if index % 2 else {}
            results.append(self.post("mcp__Roblox_Studio__execute_luau", {"code": "x"}, **extra))
        self.assertEqual([index for index, result in enumerate(results) if result], [10, 11])


class EntryPoint(HookCase):
    def run_hook(self, event, payload, cwd=None, env=None):
        raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        merged = dict(os.environ, TMPDIR=str(self.state), TEMP=str(self.state), **(env or {}))
        merged.pop("PYTHONPATH", None)
        return subprocess.run([BASH, str(ROOT / "scripts/hooks/run.sh"), event], input=raw, cwd=cwd or self.project, env=merged, capture_output=True, timeout=30)

    def test_deny_round_trips_as_json(self):
        result = self.run_hook("pre-edit", self.payload(tool_name="mcp__Roblox_Studio__multi_edit", tool_input={"file_path": "game.ServerScriptService.Server.X"}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_bad_input_fails_open_silently(self):
        for event, raw in (("stop", b"not json"), ("post-tool", b"[]"), ("pre-edit", b""), ("prompt", b'{"prompt": 5}'), ("nonsense", b"{}")):
            with self.subTest(event=event):
                result = self.run_hook(event, raw)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b"", b""))

    def test_broken_project_file_fails_open(self):
        (self.project / "default.project.json").write_text("{broken")
        result = self.run_hook("pre-edit", self.payload(tool_name="mcp__Roblox_Studio__multi_edit", tool_input={"file_path": "game.X"}))
        self.assertEqual((result.returncode, result.stdout), (0, b""))

    def test_non_ascii_survives(self):
        (self.project / "src/server/\u0e40\u0e01\u0e21.server.luau").write_text("")
        result = self.run_hook("pre-edit", self.payload(tool_name="mcp__Roblox_Studio__multi_edit", tool_input={"file_path": "game.ServerScriptService.Server.\u0e40\u0e01\u0e21"}))
        self.assertIn("\u0e40\u0e01\u0e21.server.luau", json.loads(result.stdout)["hookSpecificOutput"]["permissionDecisionReason"])

    def test_irrelevant_events_stay_fast_outside_projects(self):
        elsewhere = self.base / "elsewhere"
        elsewhere.mkdir()
        env = {"CLAUDE_PROJECT_DIR": str(elsewhere)}
        for event, payload in (("prompt", {"prompt": "write a React app"}), ("post-tool", {"tool_name": "Read", "tool_input": {"file_path": "a.txt"}})):
            with self.subTest(event=event):
                started = time.monotonic()
                result = self.run_hook(event, payload, cwd=elsewhere, env=env)
                self.assertEqual((result.returncode, result.stdout), (0, b""))
                self.assertLess(time.monotonic() - started, 2)

    def test_hooks_json_registers_each_event_through_the_runner(self):
        config = json.loads((ROOT / "hooks/hooks.json").read_text(encoding="utf-8"))["hooks"]
        self.assertEqual(set(config), {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"})
        for event in ("UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"):
            for group in config[event]:
                for hook in group["hooks"]:
                    self.assertIn("scripts/hooks/run.sh", hook["command"])
                    self.assertIn(hook["command"].split()[-1], hooks.HANDLERS)
        self.assertRegex("mcp__Roblox_Studio__multi_edit", config["PreToolUse"][0]["matcher"])

    def test_handlers_never_write_inside_the_project(self):
        before = sorted(str(path) for path in self.project.rglob("*"))
        self.post("Edit", {"file_path": str(self.project / "src/server/A.luau")})
        self.assertEqual(before, sorted(str(path) for path in self.project.rglob("*")))


if __name__ == "__main__":
    unittest.main()
