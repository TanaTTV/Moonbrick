"""Fail-closed tests for the acceptance oracle; no Roblox tools required."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("import_fidelity", ROOT / "scripts/test-import-fidelity.py")
fidelity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fidelity)


def node(cls="Script", source=b"print('fixture')\n", attrs=None, props=None):
    return {"class": cls, "name": "Test", "parent": (), "source": source,
            "attrs": attrs or {}, "tags": (), "props": props or {}}


class FidelityOracleTests(unittest.TestCase):
    def test_every_difference_category_fails(self):
        key = (("Test", 0),)
        original = {key: node(props={"Disabled": ("bool", "false"), "RunContext": ("token", "0")})}
        for field, value, category in (("class", "LocalScript", "class"), ("source", b"changed", "source"),
                                       ("attrs", {"User": (2, b"changed")}, "attributes"), ("tags", (b"changed",), "tags"),
                                       ("props", {"Disabled": ("bool", "true")}, "properties")):
            with self.subTest(field=field):
                changed = copy.deepcopy(original)
                changed[key][field] = value
                counts, _, _ = fidelity.compare(original, changed, allow_design=True)
                self.assertGreater(counts[category], 0)
        counts, _, _ = fidelity.compare(original, {(("Renamed", 0),): original[key]})
        self.assertEqual((counts["missing"], counts["extra"], counts["name_path_parent"]), (1, 1, 2))

    def test_only_exact_crlf_to_lf_is_expected(self):
        key = (("Test", 0),)
        original = {key: node(source=b"-- unicode \xe7\x95\x8c\r\nreturn 1\r\n")}
        for source, wanted in ((b"-- unicode \xe7\x95\x8c\nreturn 1\n", 0),
                               (b"-- unicode \xe7\x95\x8c\nreturn 2\n", 1),
                               (b"-- unicode \xe7\x95\x8c\nreturn 1", 1)):
            changed = {key: node(source=source)}
            counts, _, expected = fidelity.compare(original, changed, allow_design=True)
            self.assertEqual(counts["source"], wanted)
            self.assertEqual(expected["source_crlf"], 1 - wanted)
        counts, _, _ = fidelity.compare(original, {key: node(source=original[key]["source"].replace(b"\r\n", b"\n"))})
        self.assertEqual(counts["source"], 1, "strict comparison must retain byte inequality")

    def test_defaults_require_measured_exact_value(self):
        key = (("Test", 0),)
        original = {key: node()}
        defaults = {"Script": {"RunContext": ("token", "0")}}
        for value, wanted in (("0", 0), ("1", 1)):
            changed = {key: node(props={"RunContext": ("token", value)})}
            counts, _, expected = fidelity.compare(original, changed, defaults, allow_design=True)
            self.assertEqual(counts["properties"], wanted)
            self.assertEqual(expected["default_properties"], 1 - wanted)
        counts, _, _ = fidelity.compare(original, {key: node(props={"Disabled": ("bool", "false")})}, defaults, allow_design=True)
        self.assertEqual(counts["properties"], 1)

    def test_reference_metadata_validates_targets_and_user_attributes(self):
        model, part = (("Model", 0),), (("Model", 0), ("Part", 0))
        original = {model: node("Model", None, {"User": (2, b"keep")}, {"PrimaryPart": ("Ref", part)}),
                    part: node("Part", None)}
        changed = copy.deepcopy(original)
        identifier = (2, b"0123456789abcdef0123456789abcdef")
        changed[part]["attrs"]["Rojo_Id"] = identifier
        changed[model]["attrs"]["Rojo_Target_PrimaryPart"] = identifier
        counts, _, expected = fidelity.compare(original, changed, allow_design=True)
        self.assertEqual(sum(counts.values()), 0)
        self.assertEqual(expected["reference_metadata"], 2)
        for mutate in (lambda n: n[model]["attrs"].update(Rojo_Target_PrimaryPart=(2, b"wrong")),
                       lambda n: n[model]["attrs"].update(User=(2, b"changed")),
                       lambda n: n[part]["attrs"].update(Rojo_Anything=(2, b"unexpected")),
                       lambda n: n[model]["props"].update(PrimaryPart=("Ref", None))):
            with self.subTest(mutate=mutate):
                bad = copy.deepcopy(changed)
                mutate(bad)
                counts, _, _ = fidelity.compare(original, bad, allow_design=True)
                self.assertGreater(sum(counts.values()), 0)

    def test_duplicate_reordering_is_ambiguous_and_not_rematched(self):
        keys = [(("Duplicate", i),) for i in range(2)]
        original = {keys[i]: node("StringValue", None, props={"Value": ("string", str(i))}) for i in range(2)}
        rebuilt = {keys[i]: original[keys[1 - i]] for i in range(2)}
        counts, details, _ = fidelity.compare(original, rebuilt, duplicates=[((), "Duplicate", 2)])
        self.assertEqual(counts["properties"], 2)
        self.assertEqual(counts["duplicate_ambiguity"], 2)
        self.assertTrue(any("identity is ambiguous" in detail for detail in details))

    def test_parser_preserves_source_cr_and_resolves_ref_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "place.rbxlx"
            path.write_bytes(b'<roblox><Item class="Script" referent="one"><Properties><string name="Name">Test</string>'
                             b'<ProtectedString name="Source"><![CDATA[a & b\r\nc]]></ProtectedString>'
                             b'<Ref name="Value">two</Ref></Properties></Item><Item class="Part" referent="two">'
                             b'<Properties><string name="Name">Test</string></Properties></Item></roblox>')
            nodes, duplicates = fidelity.parse_place(path)
            self.assertEqual(nodes[(("Test", 0),)]["source"], b"a & b\r\nc")
            self.assertEqual(nodes[(("Test", 0),)]["props"]["Value"], ("Ref", (("Test", 1),)))
            self.assertEqual(duplicates, [((), "Test", 2)])
            path.write_bytes(path.read_bytes().replace(b">two</Ref>", b">missing</Ref>"))
            with self.assertRaisesRegex(ValueError, "unresolved Ref"):
                fidelity.parse_place(path)

    def test_starterplayer_exception_is_exact_and_only_for_omitted_settings(self):
        key = (("StarterPlayer", 0),)
        original = {key: node("StarterPlayer", None, props={"CharacterWalkSpeed": ("float", 23.0)})}
        counts, _, expected = fidelity.compare(original, {key: node("StarterPlayer", None)}, allow_design=True)
        self.assertEqual(sum(counts.values()), 0)
        self.assertEqual(expected["starterplayer_settings"], 1)
        counts, _, _ = fidelity.compare(original, {key: node("StarterPlayer", None, props={"CharacterWalkSpeed": ("float", 99.0)})}, allow_design=True)
        self.assertEqual(counts["properties"], 1)

    def test_attributes_compare_semantically_but_keep_types(self):
        blob = fidelity.attributes_blob({"Unicode": "界", "Bool": True, "Number": 2.5})
        values = fidelity.decode_attributes(blob)
        self.assertEqual(values, {"Bool": (3, True), "Number": (6, 2.5), "Unicode": (2, "界".encode())})


if __name__ == "__main__":
    unittest.main()
