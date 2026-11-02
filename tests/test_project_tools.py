"""stylecheck, ship-check, check-refs and the eval suite, from small fixtures."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


style = load("stylecheck", "scripts/stylecheck.py")
ship = load("ship_check", "scripts/ship-check.py")
refs = load("check_refs", "scripts/check-refs.py")


class Project(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "src/client").mkdir(parents=True)

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def run_main(self, module, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = module.main([*args])
        return code, out.getvalue()


class StyleCheck(Project):
    def findings(self, code, file="src/client/Hud.client.luau"):
        self.write(file, code)
        return style.scan(self.root)

    def test_flags_gui_colours_and_fonts(self):
        code = 'label.TextColor3 = Color3.fromRGB(200, 30, 30)\nlabel.Font = Enum.Font.Arcade\nlocal f = Font.new("rbxasset://x")\n'
        lines = self.findings(code)
        self.assertEqual(len(lines), 3)
        self.assertIn("Hud.client.luau:1 TextColor3", lines[0])
        self.assertIn("Enum.Font.Arcade", lines[1])

    def test_table_properties_and_kit_arguments(self):
        lines = self.findings('local a = make({ BackgroundColor3 = Color3.new(0.2, 0.1, 0.1) })\nUI.label({\n\tparent = gui,\n\tcolor = Color3.fromHex("#ff0000"),\n})\n')
        self.assertEqual(len(lines), 2)
        self.assertIn(":4 color", lines[1])

    def test_nested_inside_a_kit_call(self):
        lines = self.findings('Fx.define({ name = "X", layers = {\n\t{ kind = "mesh",\n\t\tcolor = Color3.new(1, 0.5, 0) },\n} })\n')
        self.assertEqual(len(lines), 1)

    def test_clean_code_passes(self):
        code = "\n".join((
            "label.TextColor3 = UI.Theme.text",
            "label.BackgroundColor3 = ArtStyle.palette.core",
            "image.ImageColor3 = Color3.new(1, 1, 1)",
            "frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)",
            "part.Color = Color3.fromRGB(200, 30, 30)",
            "team.TeamColor = BrickColor.new('Bright red')",
            "local c = { color = Color3.new(1, 0, 0) }",
            '-- label.TextColor3 = Color3.fromRGB(1, 2, 3)',
            'local s = "label.Font = Enum.Font.Arcade"',
            "label.Font = UI.Theme.font",
        ))
        self.assertEqual(self.findings(code), [])

    def test_accepted_line_and_skipped_files(self):
        self.assertEqual(self.findings("x.TextColor3 = Color3.new(1, 0, 0) -- style-ok\n"), [])
        bad = "x.TextColor3 = Color3.new(1, 0, 0)\n"
        for file in ("src/kit/shared/UI.luau", "src/shared/ArtStyle.luau", "src/shared/Theme.luau", "src/shared/Palette.luau"):
            self.write(file, bad)
        self.assertEqual(style.scan(self.root), [])

    def test_exit_codes_and_cap(self):
        self.assertEqual(self.run_main(style, str(self.root)), (0, "OK\n"))
        self.write("src/client/A.luau", "x.TextColor3 = Color3.new(1, 0, 0)\n" * 50)
        code, out = self.run_main(style, str(self.root))
        self.assertEqual(code, 1)
        self.assertIn("... 10 more", out)


class ShipCheck(Project):
    def test_clean_project(self):
        self.write("src/client/A.client.luau", "print('hi')\n")
        self.assertEqual(self.run_main(ship, str(self.root)), (0, "OK\n"))

    def test_preview_textures_block(self):
        self.write("src/client/A.client.luau", "Tex.usePreview()\n")
        code, out = self.run_main(ship, str(self.root))
        self.assertEqual(code, 1)
        self.assertIn("blocker: src/client/A.client.luau:1 Tex.usePreview", out)

    def test_local_asset_paths_block_in_code_and_data(self):
        self.write("src/client/A.client.luau", 'sound.SoundId = "rbxasset://sounds/moonbrick/hit.wav"\n')
        self.write("src/world/B.model.json", '{"Texture": "rbxasset://textures/moonbrick/spark.png"}\n')
        code, out = self.run_main(ship, str(self.root))
        self.assertEqual(code, 1)
        self.assertEqual(out.count("blocker:"), 2)

    def test_studio_guard_is_a_note(self):
        self.write("src/client/A.client.luau", "if RunService:IsStudio() then\n\tTex.usePreview()\nend\n")
        code, out = self.run_main(ship, str(self.root))
        self.assertEqual(code, 0)
        self.assertIn("note:", out)

    def test_comments_and_the_kit_are_ignored(self):
        self.write("src/client/A.client.luau", "-- Tex.usePreview()\n")
        self.write("src/kit/shared/Tex.luau", 'Tex.usePreview("rbxasset://textures/moonbrick/")\n')
        self.assertEqual(self.run_main(ship, str(self.root))[0], 0)

    def test_geo_lists_the_setting_without_blocking(self):
        self.write("src/client/A.client.luau", 'local p = Geo.build(function() end)\n')
        code, out = self.run_main(ship, str(self.root))
        self.assertEqual(code, 0)
        self.assertIn("Allow Mesh & Image APIs", out)

    def test_no_geo_no_setting(self):
        self.write("src/client/A.client.luau", "local Geography = 1\n")
        self.assertNotIn("Allow Mesh", self.run_main(ship, str(self.root))[1])


class CheckRefs(Project):
    def setUp(self):
        super().setUp()
        self.write("scripts/tool.py", 'parser.add_argument("--real")\n')
        self.write("luau/lib/shared/Fx.luau", "function Fx.play() end\nFx.Palette = {}\n")
        self.write("luau/MCPKit.luau", "local K = {}\nfunction K.test() end\n")
        self.write("template/tools/check.sh", "--fix\n")

    def check(self, text, file="docs/guide.md"):
        self.write(file, text)
        return refs.Checker(self.root).run()

    def test_clean(self):
        self.assertEqual(self.check("Run `python scripts/tool.py --real` then `bash tools/check.sh --fix`. `Fx.play`, `Fx.Palette`, `K.test()`, `tools/KIT_API.md`.\n"), [])

    def test_missing_repo_path(self):
        self.assertIn("docs/guide.md:1: scripts/gone.py does not exist", self.check("`scripts/gone.py`\n"))

    def test_plugin_root_path(self):
        found = self.check('Run `python "${CLAUDE_PLUGIN_ROOT}/scripts/gone.py"`\n', "skills/a/SKILL.md")
        self.assertEqual(len(found), 1)
        self.assertIn("gone.py does not exist", found[0])

    def test_bare_plugin_path_in_a_skill(self):
        self.assertTrue(any("can't resolve" in line for line in self.check("`python scripts/tool.py`\n", "skills/a/SKILL.md")))

    def test_undefined_roots(self):
        self.assertEqual(len(self.check("`python KIT/scripts/tool.py` and `python <kit>/scripts/tool.py`\n")), 2)

    def test_unknown_flag(self):
        self.assertIn("docs/guide.md:1: scripts/tool.py has no --fake flag", self.check("`python scripts/tool.py --fake`\n"))

    def test_flag_of_the_next_command_is_not_blamed(self):
        self.assertEqual(self.check("`python scripts/tool.py --real && git commit --amend`\n"), [])

    def test_unknown_kit_function(self):
        self.assertIn("docs/guide.md:2: Fx.ghost is not in the Kit", self.check("```lua\nFx.ghost()\n```\n"))

    def test_prose_is_not_a_kit_call(self):
        self.assertEqual(self.check("Use UI.Something in prose, not code.\n"), [])

    def test_project_tools_path(self):
        self.assertEqual(len(self.check("`tools/nothing.sh`\n")), 1)

    def test_broken_link(self):
        self.assertEqual(len(self.check("[x](missing.md) [y](https://example.com) [z](guide.md#top)\n")), 1)

    def test_project_files_named_in_skills_are_allowed(self):
        self.assertEqual(self.check("`docs/design.md` and `tests/kit/` and `tests/foo.spec.luau`\n", "skills/a/SKILL.md"), [])

    def test_exit_codes(self):
        self.write("README.md", "`scripts/gone.py`\n")
        code, out = self.run_main(refs, "--root", str(self.root))
        self.assertEqual(code, 1)
        self.assertIn("1 broken reference(s)", out)
        (self.root / "README.md").unlink()
        self.assertEqual(self.run_main(refs, "--root", str(self.root)), (0, "OK\n"))

    def test_runs_on_the_real_repo(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertIn(refs.main([]), (0, 1))  # findings wait on other work; a crash is the failure here


class EvalSuite(unittest.TestCase):
    CASES = sorted((ROOT / "evals").glob("*/case.yaml"))

    def test_required_prompts_are_covered(self):
        text = "\n".join(path.read_text(encoding="utf-8") for path in self.CASES)
        for prompt in ("make a Roblox game about pets", "add a shop to my game", "make a fireball look better", "design a lobby level for my obby", "this model needs to look better in Blender", "React"):
            self.assertIn(prompt, text)

    def test_cases_follow_the_schema_of_the_installed_cli(self):
        self.assertGreaterEqual(len(self.CASES), 6)
        for path in self.CASES:
            with self.subTest(path=path.parent.name):
                text = path.read_text(encoding="utf-8")
                self.assertRegex(text, r'(?m)^schema_version: "1\.\d"$')
                self.assertRegex(text, rf"(?m)^name: {re.escape(path.parent.name)}$")
                for key in ("execution:", "  prompt:", "  allowed_tools:", "runs:", "graders:", "  - type: tool_used", "    tool: Skill"):
                    self.assertIn(key, text)
                scaffold = re.search(r"scaffold_script: (\S+)", text)
                if scaffold:
                    self.assertTrue((path.parent / scaffold.group(1)).is_file())

    def test_negative_cases_forbid_any_moonbrick_skill(self):
        negative = [path for path in self.CASES if "tags: [negative]" in path.read_text(encoding="utf-8")]
        self.assertGreaterEqual(len(negative), 2)
        for path in negative:
            text = path.read_text(encoding="utf-8")
            self.assertIn("max: 0", text)
            self.assertIn('input_match: "moonbrick:"', text)

    def test_every_expected_skill_exists(self):
        for path in self.CASES:
            match = re.search(r'input_match: "moonbrick:([^"]+)"', path.read_text(encoding="utf-8"))
            if match and match.group(1):
                for name in re.findall(r"[a-z-]+", match.group(1)):
                    self.assertTrue((ROOT / "skills" / name / "SKILL.md").is_file(), name)

    def test_scaffold_keeps_the_session_hook_out(self):
        for path in (ROOT / "evals").glob("*/scaffold.sh"):
            self.assertNotIn("MCPKit", path.read_text(encoding="utf-8").replace("no Kit", ""))
        json.loads('{"name":"game"}')


if __name__ == "__main__":
    unittest.main()
