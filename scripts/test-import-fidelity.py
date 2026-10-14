"""Offline Rojo 7.7.1 import acceptance. Generates its own assets; never opens Studio.

Both input formats are built from the same synthetic XML model project. The binary
baseline is the XML build of that source project (not a second, lossy syncback).
Duplicate names are indexed in sibling order, never matched by guessed properties.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
SERVICES = ("ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPlayer", "ReplicatedFirst")
SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")
CATEGORIES = ("missing", "extra", "class", "name_path_parent", "source", "attributes", "tags", "properties", "references", "duplicate_ambiguity")
KIT_ROOTS = (("ReplicatedStorage", "Kit"), ("ServerScriptService", "Kit"), ("ServerStorage", "MCPKit"), ("ServerStorage", "Tests"))
EXPECTED_REASONS = {
    "source_crlf": "Rojo 7.7.1 src/snapshot_middleware/lua.rs:66 (LF-normalized file reads); skills/import/SKILL.md#fidelity-limits",
    "default_properties": "Rojo 7.7.1 src/syncback/property_filter.rs; exact defaults measured by generated binary-model probe",
    "reference_metadata": "Rojo 7.7.1 src/syncback/ref_properties.rs:100-175; only validated additions for original Ref targets",
    "starterplayer_settings": "scripts/project.py:ENTRIES maps StarterPlayer script containers only; skills/import/SKILL.md#fidelity-limits",
}
KEY_PROPERTIES = {
    "Script": ("Disabled", "RunContext"), "LocalScript": ("Disabled",),
    "ScreenGui": ("Enabled", "ResetOnSpawn", "IgnoreGuiInset", "DisplayOrder"),
    "Frame": ("Size", "Position", "BackgroundColor3", "BackgroundTransparency", "LayoutOrder"),
    "TextLabel": ("Size", "Position", "Text", "RichText", "TextColor3", "TextSize", "FontFace", "TextXAlignment"),
    "ImageLabel": ("Size", "Image", "ImageColor3", "ImageTransparency", "ScaleType"),
    "UIListLayout": ("Padding", "FillDirection", "SortOrder"),
    "UIGridLayout": ("CellSize", "CellPadding", "SortOrder"), "UIScale": ("Scale",),
    "UICorner": ("CornerRadius",), "UIStroke": ("Color", "Thickness", "Transparency", "ApplyStrokeMode"),
    "UIGradient": ("Color", "Transparency", "Rotation", "Offset"),
    "Part": ("Size", "CFrame", "Color3uint8", "Anchored", "CanCollide", "Material", "Transparency"),
    "Model": ("PrimaryPart",), "Motor6D": ("Part0", "Part1", "C0", "C1"),
    "Attachment": ("CFrame",), "Bone": ("CFrame",), "Animation": ("AnimationId",),
    "KeyframeSequence": ("Loop", "Priority"), "Keyframe": ("Time",),
    "Pose": ("CFrame", "Weight", "EasingStyle", "EasingDirection"),
    "StringValue": ("Value",), "Lighting": ("Brightness", "ClockTime", "Ambient", "OutdoorAmbient"),
    "Atmosphere": ("Density", "Offset", "Color", "Decay", "Glare", "Haze"),
    "Terrain": ("WaterColor", "WaterTransparency", "WaterWaveSize"),
    "StarterPlayer": ("CharacterWalkSpeed", "CameraMaxZoomDistance"),
}


def load_project():
    spec = importlib.util.spec_from_file_location("moonbrick_project", ROOT / "scripts/project.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def string_bytes(value):
    data = value.encode("utf-8")
    return struct.pack("<I", len(data)) + data


def attributes_blob(values):
    data = struct.pack("<I", len(values))
    for name, value in sorted(values.items()):
        data += string_bytes(name)
        if isinstance(value, bool):
            data += b"\x03" + bytes([value])
        elif isinstance(value, (int, float)):
            data += b"\x06" + struct.pack("<d", value)
        else:
            data += b"\x02" + string_bytes(value)
    return base64.b64encode(data).decode("ascii")


def decode_attributes(value):
    data = base64.b64decode(value or "")
    if not data:
        return {}
    offset = 0

    def unpack(fmt):
        nonlocal offset
        result = struct.unpack_from(fmt, data, offset)
        offset += struct.calcsize(fmt)
        return result[0] if len(result) == 1 else result

    def string():
        nonlocal offset
        size = unpack("<I")
        result = data[offset:offset + size]
        offset += size
        return result

    values = {}
    for _ in range(unpack("<I")):
        name, kind = string().decode("utf-8"), unpack("<B")
        if kind == 2:
            value = string()  # BinaryString/String share the wire type; preserve UTF-8 bytes.
        elif kind == 3:
            value = bool(unpack("<B"))
        elif kind in (4, 5, 6):
            value = unpack({4: "<i", 5: "<f", 6: "<d"}[kind])
        else:
            raise ValueError(f"unhandled fixture attribute type {kind} for {name}")
        if name in values:
            raise ValueError(f"duplicate attribute {name}")
        values[name] = (kind, value)
    if offset != len(data):
        raise ValueError("trailing attribute bytes")
    return values


def prop(kind, name, value=None, **children):
    element = ET.Element(kind, name=name)
    if value is not None:
        element.text = str(value)
    for key, content in children.items():
        ET.SubElement(element, key).text = str(content)
    return element


def cframe(name, x=0, y=0, z=0):
    return prop("CoordinateFrame", name, X=x, Y=y, Z=z, R00=1, R01=0, R02=0, R10=0, R11=1, R12=0, R20=0, R21=0, R22=1)


def udim2(name, sx=0, ox=0, sy=0, oy=0):
    return prop("UDim2", name, XS=sx, XO=ox, YS=sy, YO=oy)


def color(name, r=.25, g=.5, b=.75):
    return prop("Color3", name, R=r, G=g, B=b)


class Fixture:
    def __init__(self):
        self.serial = 0

    def node(self, cls, name, properties=(), children=(), attrs=None, tags=()):
        self.serial += 1
        node = ET.Element("Item", {"class": cls, "referent": f"RBX{self.serial}"})
        ps = ET.SubElement(node, "Properties")
        ps.append(prop("string", "Name", name))
        ps.extend(properties)
        if attrs:
            ps.append(prop("BinaryString", "AttributesSerialize", attributes_blob(attrs)))
        if tags:
            ps.append(prop("BinaryString", "Tags", base64.b64encode("\0".join(tags).encode()).decode()))
        node.extend(children)
        return node

    def ui(self):
        frame = self.node("Frame", "Main panel.界", [udim2("Size", .75, 13, .5, 29), udim2("Position", .125, 7, .25, -3), color("BackgroundColor3"), prop("float", "BackgroundTransparency", .25)], attrs={"Role": "HUD 世界", "EnabledFlag": True, "Version": 2.5}, tags=("MoonbrickFixture", "HUD"))
        label_props = [udim2("Size", .5, 12, 0, 35), prop("string", "Text", '<b>Coins & gems</b> 世界 🌙\nsecond line'), prop("bool", "RichText", "true"), color("TextColor3", .75, .25, .5), prop("float", "TextSize", 27), prop("token", "TextXAlignment", 0)]
        font = prop("Font", "FontFace")
        family = ET.SubElement(font, "Family")
        ET.SubElement(family, "url").text = "rbxasset://fonts/families/SourceSansPro.json"
        ET.SubElement(font, "Weight").text = "700"
        ET.SubElement(font, "Style").text = "Normal"
        label_props.append(font)
        frame.append(self.node("TextLabel", "Title", label_props))
        image = prop("Content", "Image")
        ET.SubElement(image, "url").text = "rbxasset://textures/ui/GuiImagePlaceholder.png"
        frame.append(self.node("ImageLabel", "Local image", [image, udim2("Size", 0, 96, 0, 96), color("ImageColor3"), prop("float", "ImageTransparency", .125), prop("token", "ScaleType", 3)]))
        frame.append(self.node("UIListLayout", "List", [prop("UDim", "Padding", S=.125, O=7), prop("token", "FillDirection", 0), prop("token", "SortOrder", 2)]))
        frame.append(self.node("UIScale", "Scale", [prop("float", "Scale", 1.25)]))
        frame.append(self.node("UICorner", "Corner", [prop("UDim", "CornerRadius", S=.25, O=5)]))
        frame.append(self.node("UIStroke", "Stroke", [color("Color"), prop("float", "Thickness", 3.5), prop("float", "Transparency", .25), prop("token", "ApplyStrokeMode", 1)]))
        frame.append(self.node("UIGradient", "Gradient", [prop("ColorSequence", "Color", "0 0.25 0.5 0.75 0 1 0.75 0.25 0.5 0"), prop("NumberSequence", "Transparency", "0 0.125 0 1 0.75 0"), prop("float", "Rotation", 35), prop("Vector2", "Offset", X=.125, Y=-.25)]))
        grid = self.node("Frame", "Grid", [udim2("Size", .5, 20, .25, 10)])
        grid.append(self.node("UIGridLayout", "Layout", [udim2("CellSize", .25, 30, 0, 48), udim2("CellPadding", 0, 7, 0, 9), prop("token", "SortOrder", 2)]))
        for i in range(2):
            grid.append(self.node("Frame", "Duplicate cell", [prop("int", "LayoutOrder", i + 1)], attrs={"Ordinal": i + 1}))
        frame.append(grid)
        return self.node("ScreenGui", "HUD screen", [prop("bool", "ResetOnSpawn", "false"), prop("bool", "IgnoreGuiInset", "true"), prop("int", "DisplayOrder", 7)], [frame], attrs={"Description": "Synthetic rich UI"}, tags=("UIFixture",))

    def rig(self):
        root_part = self.node("Part", "Root part", [prop("Vector3", "Size", X=2, Y=3, Z=4), cframe("CFrame", 1, 2, 3), prop("bool", "Anchored", "true"), prop("token", "Material", 512)])
        child_part = self.node("Part", "Limb", [prop("Vector3", "Size", X=1, Y=2, Z=1), cframe("CFrame", 3, 4, 5)])
        bone = self.node("Bone", "Upper bone", [cframe("CFrame", 0, 1, 0)], [self.node("Bone", "Tip bone", [cframe("CFrame", 0, 2, 0)])])
        root_part.append(self.node("Attachment", "Rig attachment", [cframe("CFrame", 0, .5, 0)], [bone]))
        motor = self.node("Motor6D", "Joint", [prop("Ref", "Part0", root_part.get("referent")), prop("Ref", "Part1", child_part.get("referent")), cframe("C0", 0, 1, 0), cframe("C1", 0, -1, 0)])
        root_part.append(motor)
        frames = []
        for t in (0, .5, 1):
            pose = self.node("Pose", "Root part", [cframe("CFrame", 0, t, 0), prop("float", "Weight", .75), prop("token", "EasingStyle", 1)], [self.node("Pose", "Limb", [cframe("CFrame", t, 0, 0)])])
            frames.append(self.node("Keyframe", f"Frame {t}", [prop("float", "Time", t)], [pose]))
        sequence = self.node("KeyframeSequence", "Walk clip", [prop("bool", "Loop", "true"), prop("token", "Priority", 2)], frames)
        animation_id = prop("Content", "AnimationId")
        ET.SubElement(animation_id, "url").text = "rbxassetid://0"  # inert reference; no download/upload
        return self.node("Model", "Synthetic rig", [prop("Ref", "PrimaryPart", root_part.get("referent"))], [root_part, child_part, sequence, self.node("Animation", "Animation reference", [animation_id])])

    def generate(self, directory):
        directory.mkdir()
        tree = {"$className": "DataModel"}
        for service in SERVICES:
            parent = self.node(service, service)
            if service == "StarterPlayer":
                # Service-level settings are a separate, intentionally exercised boundary.
                parent.find("Properties").extend([prop("float", "CharacterWalkSpeed", 23), prop("float", "CameraMaxZoomDistance", 175)])
                scripts = self.node("StarterPlayerScripts", "StarterPlayerScripts")
                parent.extend([scripts, self.node("StarterCharacterScripts", "StarterCharacterScripts", children=[self.node("LocalScript", "Character.client", [prop("ProtectedString", "Source", '-- character 世界\nprint("fixture")\n')])])])
            else:
                scripts = parent
            if service != "ReplicatedFirst":
                bulk = self.node("Folder", "LARGE folders.世界")
                scripts.append(bulk)
                for group in range(14):
                    folder = self.node("Folder", f"Group {group}.é")
                    bulk.append(folder)
                    # Large non-code hierarchies use Rojo's native model blobs;
                    # keep all 330 bulk scripts as separately editable files.
                    values_model = self.node("Model", "Values model")
                    for i in range(30):
                        ordinal = group * 30 + i
                        if ordinal < 66:
                            cls = SCRIPT_CLASSES[ordinal % 3]
                            newline = "\r\n" if ordinal < 3 else "\n"
                            source = f'-- {service} {ordinal} 世界 🌙{newline}' + ('return {value = "fixture"}' if cls == "ModuleScript" else 'print("synthetic only")') + newline
                            properties = [prop("ProtectedString", "Source", source)]
                            if cls != "ModuleScript":
                                properties.append(prop("bool", "Disabled", "true" if ordinal % 4 == 0 else "false"))
                            leaf = self.node(cls, f"Script {ordinal}.unicode_界", properties, attrs={"FixtureIndex": ordinal}, tags=("SyntheticScript",))
                        else:
                            leaf = self.node("StringValue", f"Value {ordinal}.界", [prop("string", "Value", f"payload {ordinal} 世界")])
                        (folder if ordinal < 66 else values_model).append(leaf)
                    if values_model.findall("Item"):
                        folder.append(values_model)
                deep = bulk
                for depth in range(14):
                    child = self.node("Folder", f"Deep {depth}")
                    deep.append(child)
                    deep = child
                # Folder fallback to a model blob must preserve both siblings and order.
                for i in range(2):
                    deep.append(self.node("StringValue", "Same name.界", [prop("string", "Value", f"duplicate {i}")]))
            if service == "StarterGui":
                parent.append(self.ui())
                menu = self.ui()
                menu.find("Properties/*[@name='Name']").text = "Menu screen"
                parent.append(menu)
            if service == "ReplicatedStorage":
                parent.append(self.rig())
            if service == "ReplicatedFirst":
                parent.append(self.node("LocalScript", "Loading", [prop("ProtectedString", "Source", '-- loading\nprint("fixture")\n')]))
            self.save_model(directory, service, parent)
            tree[service] = {"$path": f"{service}.rbxmx"}
        workspace = self.node("Workspace", "Workspace", children=[self.node("Part", "Place owned map", [prop("bool", "Anchored", "true"), prop("Vector3", "Size", X=100, Y=2, Z=100)]), self.node("Terrain", "Terrain", [color("WaterColor"), prop("float", "WaterTransparency", .35), prop("float", "WaterWaveSize", .25)]), self.node("Script", "Place owned script", [prop("ProtectedString", "Source", '-- world remains in original\n')])])
        lighting = self.node("Lighting", "Lighting", [prop("float", "Brightness", 3.25), prop("float", "ClockTime", 17.5), color("Ambient"), color("OutdoorAmbient", .5, .25, .75)], [self.node("Atmosphere", "Place atmosphere", [prop("float", "Density", .45), prop("float", "Haze", 2.5), color("Color")])])
        for service, node in (("Workspace", workspace), ("Lighting", lighting)):
            self.save_model(directory, service, node)
            tree[service] = {"$path": f"{service}.rbxmx"}
        (directory / "default.project.json").write_text(json.dumps({"name": "Generated import fidelity", "tree": tree}), encoding="utf-8")
        shutil.copy2(ROOT / "template/rokit.toml", directory / "rokit.toml")

    @staticmethod
    def save_model(directory, name, node):
        root = ET.Element("roblox", version="4")
        root.append(node)
        # Write bytes: ElementTree's filename writer translates LF on Windows.
        (directory / f"{name}.rbxmx").write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))


def canonical(element):
    """Canonicalize XML representation only; never round floats or normalize Source."""
    if list(element):
        return (element.tag, tuple((child.tag, canonical(child)) for child in element))
    text = element.text or ""
    if element.tag == "BinaryString":
        return (element.tag, base64.b64decode(text))
    if element.tag in ("float", "double", "X", "Y", "Z", "R", "G", "B", "S", "XS", "YS") or element.tag.startswith("R") and len(element.tag) == 3 and element.tag[1:].isdigit():
        return (element.tag, float(text))
    return (element.tag, text)


def parse_place(path):
    # xml-rs (Rojo) preserves Source carriage returns; Expat (ElementTree)
    # normalizes them. Escape CDATA/CR before parsing so comparisons retain bytes.
    xml = path.read_bytes().decode("utf-8")
    xml = re.sub(r"<!\[CDATA\[(.*?)\]\]>", lambda m: escape(m[1]), xml, flags=re.DOTALL)
    root = ET.fromstring(xml.replace("\r", "&#13;"))
    nodes, refs, duplicates = {}, {}, []

    def walk(children, parent=()):
        counts = Counter()
        totals = Counter(child.findtext("Properties/*[@name='Name']") for child in children)
        for name, count in totals.items():
            if count > 1:
                duplicates.append((parent, name, count))
        for child in children:
            name = child.findtext("Properties/*[@name='Name']")
            assert name is not None, "fixture/build instance lacks Name"
            key = parent + ((name, counts[name]),)
            counts[name] += 1
            ps = {p.get("name"): p for p in child.find("Properties")}
            nodes[key] = {"class": child.get("class"), "parent": parent, "name": name, "ps": ps,
                          "source": (ps["Source"].text or "").encode("utf-8") if "Source" in ps else None,
                          "attrs": decode_attributes(ps.get("AttributesSerialize").text if "AttributesSerialize" in ps else ""),
                          "tags": tuple(sorted(base64.b64decode(ps["Tags"].text or "").split(b"\0"))) if "Tags" in ps and ps["Tags"].text else ()}
            refs[child.get("referent")] = key
            walk(child.findall("Item"), key)

    walk(root.findall("Item"))
    for node in nodes.values():
        node["props"] = {}
        for name, p in node.pop("ps").items():
            if p.tag == "Ref":
                if p.text not in (None, "null") and p.text not in refs:
                    raise ValueError(f"unresolved Ref {p.text} in {name}")
                node["props"][name] = ("Ref", refs.get(p.text))
            else:
                node["props"][name] = canonical(p)
    return nodes, duplicates


def pretty(key):
    return "/".join(f"{name}[{ordinal}]" for name, ordinal in key)


def compare(original, rebuilt, defaults=None, allow_design=False, duplicates=()):
    counts, details = Counter({name: 0 for name in CATEGORIES}), []
    expected = Counter({name: 0 for name in EXPECTED_REASONS})
    defaults = defaults or {}
    duplicate_roots = [parent + ((name, ordinal),) for parent, name, total in duplicates for ordinal in range(total)]
    targets = {value[1] for node in original.values() for value in node["props"].values() if value[0] == "Ref" and value[1] is not None}

    def diff(category, key, field=""):
        counts[category] += 1
        details.append(f"{category}: {pretty(key)} {field}")
        if category != "duplicate_ambiguity" and any(key[:len(root)] == root for root in duplicate_roots):
            counts["duplicate_ambiguity"] += 1
            details.append(f"duplicate_ambiguity: {pretty(key)} differs at sibling ordinal; identity is ambiguous (no property-based rematching)")

    for key in sorted(original.keys() - rebuilt.keys()):
        diff("missing", key)
    for key in sorted(rebuilt.keys() - original.keys()):
        diff("extra", key)
    counts["name_path_parent"] = len(original.keys() ^ rebuilt.keys())
    for key in sorted(original.keys() & rebuilt.keys()):
        a, b = original[key], rebuilt[key]
        if a["class"] != b["class"]:
            diff("class", key, f"{a['class']} -> {b['class']}")
        if (a["name"], a["parent"]) != (b["name"], b["parent"]):
            diff("name_path_parent", key)
        for field, category in (("source", "source"), ("attrs", "attributes"), ("tags", "tags")):
            if a[field] != b[field]:
                if allow_design and field == "source" and a[field] is not None and b[field] == a[field].replace(b"\r\n", b"\n"):
                    expected["source_crlf"] += 1
                    continue
                if allow_design and field == "attrs":
                    remaining = dict(b[field])
                    for name, value in b[field].items():
                        if name in a[field]:
                            continue  # Existing user attributes never qualify for exemption.
                        if name == "Rojo_Id" and key in targets and value[0] == 2 and re.fullmatch(b"[0-9a-f]{32}", value[1]):
                            remaining.pop(name)
                            expected["reference_metadata"] += 1
                        elif name.startswith("Rojo_Target_"):
                            ref = a["props"].get(name[len("Rojo_Target_"):])
                            if ref and ref[0] == "Ref" and ref[1] in rebuilt and value == rebuilt[ref[1]]["attrs"].get("Rojo_Id"):
                                remaining.pop(name)
                                expected["reference_metadata"] += 1
                    if a[field] == remaining:
                        continue
                diff(category, key, repr(a[field]) + " -> " + repr(b[field]))
        for name in KEY_PROPERTIES.get(a["class"], ()):
            old, new = a["props"].get(name), b["props"].get(name)
            if old != new:
                if allow_design and key == (("StarterPlayer", 0),) and name in ("CharacterWalkSpeed", "CameraMaxZoomDistance") and new is None:
                    expected["starterplayer_settings"] += 1
                    continue
                default = defaults.get(a["class"], {}).get(name)
                if allow_design and default is not None and (old is None and new == default or new is None and old == default):
                    expected["default_properties"] += 1
                    continue
                diff("references" if (old or new or (None,))[0] == "Ref" else "properties", key, f"{name}: {old!r} -> {new!r}")
    return counts, details, expected


def default_properties(directory):
    """Measure pinned Rojo's defaults; never allow arbitrary added properties."""
    fixture = Fixture()
    # Binary property arrays fill absent values only when another instance of
    # that class serializes that property. Include the source as witnesses.
    children = ET.parse(directory / "original.rbxlx").getroot().findall("Item")
    probes = [fixture.node(cls, "Default_" + cls) for cls in KEY_PROPERTIES]
    probes.append(fixture.node("Script", "RunContext witness", [prop("token", "RunContext", 1)]))
    for probe in probes:
        probe.set("referent", "Probe_" + probe.get("referent"))
    children.extend(probes)
    root = fixture.node("Folder", "Default probe", children=children)
    root.set("referent", "Probe_root")
    Fixture.save_model(directory, "default-input", root)
    cfg = {"name": "Default probe", "tree": {"$path": "default-input.rbxmx"}}
    path = directory / "defaults.project.json"
    path.write_text(json.dumps(cfg), encoding="utf-8")
    run(["rojo", "build", path.name, "-o", "defaults.rbxm"], directory)
    path.write_text(json.dumps({"name": "Default probe", "tree": {"$path": "defaults.rbxm"}}), encoding="utf-8")
    run(["rojo", "build", path.name, "-o", "defaults.rbxmx"], directory)
    nodes, _ = parse_place(directory / "defaults.rbxmx")
    return {node["class"]: node["props"] for key, node in nodes.items() if len(key) == 2 and key[-1][0].startswith("Default_")}


def kit_nodes(nodes):
    return {key: node for key, node in nodes.items() if len(key) > 1 and (key[0][0], key[1][0]) in KIT_ROOTS}


def run(args, cwd, timeout=120):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, capture_output=True, text=True, encoding="utf-8", timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))}\n{result.stdout}{result.stderr}")
    return result.stdout


def managed_snapshot(project):
    return {p.relative_to(project).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in project.rglob("*") if p.is_file() and not {".git", ".moonbrick"}.intersection(p.relative_to(project).parts)
            and p.name != "default.project.json"}


def bash_executable():
    if os.name == "nt":
        git = shutil.which("git")
        # git.exe lives in Git/cmd or (inside Git Bash) Git/mingw64/bin.
        roots = list(Path(git).resolve().parents)[1:3] if git else []
        roots.append(Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git")
        for root in roots:
            if (root / "bin/bash.exe").is_file():
                return root / "bin/bash.exe"
        raise RuntimeError("Git Bash is required on Windows (WSL bash cannot run this checkout's tools)")
    return "bash"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", type=Path, help="keep generated fixtures and imports in a new/empty directory")
    args = parser.parse_args()
    os.environ["PATH"] = str(Path.home() / ".rokit/bin") + os.pathsep + os.environ["PATH"]
    os.environ["PYTHONUTF8"] = "1"
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    for key, value in {"GIT_AUTHOR_NAME": "Moonbrick acceptance", "GIT_AUTHOR_EMAIL": "test@moonbrick.invalid",
                       "GIT_COMMITTER_NAME": "Moonbrick acceptance", "GIT_COMMITTER_EMAIL": "test@moonbrick.invalid"}.items():
        os.environ[key] = value
    project = load_project()
    started = time.perf_counter()
    if args.keep:
        args.keep.mkdir(parents=True, exist_ok=True)
        if any(args.keep.iterdir()):
            raise ValueError("--keep requires an empty directory")
        root = args.keep.resolve()
        context = None
    else:
        (ROOT / ".artifacts").mkdir(exist_ok=True)
        context = tempfile.TemporaryDirectory(prefix="import-fidelity-", dir=ROOT / ".artifacts")
        root = Path(context.name)
    try:
        source = root / "source"
        Fixture().generate(source)
        version = run(["rojo", "--version"], source).strip()
        assert version == "Rojo 7.7.1", f"expected pinned Rojo 7.7.1, got {version}"
        print(version, flush=True)
        for suffix in ("rbxlx", "rbxl"):
            run(["rojo", "build", "default.project.json", "-o", f"original.{suffix}"], source)
        defaults = default_properties(source)
        assert (source / "original.rbxl").read_bytes().startswith(b"<roblox!"), "binary fixture is not binary"
        baseline, duplicates = parse_place(source / "original.rbxlx")
        imported_baseline = {key: node for key, node in baseline.items() if key[0][0] in SERVICES}
        scripts = Counter(node["class"] for node in imported_baseline.values() if node["class"] in SCRIPT_CLASSES)
        assert len(imported_baseline) >= 2000 and sum(scripts.values()) >= 300 and all(scripts[cls] for cls in SCRIPT_CLASSES)
        assert max(map(len, imported_baseline)) >= 12 and duplicates
        classes = Counter(node["class"] for node in imported_baseline.values())
        assert all(classes[cls] for cls in ("ScreenGui", "Frame", "TextLabel", "ImageLabel", "UIListLayout", "UIGridLayout", "UIScale", "UICorner", "UIStroke", "UIGradient", "Model", "Part", "Motor6D", "Bone", "Attachment", "KeyframeSequence", "Keyframe", "Pose"))
        assert any(node["attrs"] for node in imported_baseline.values()) and any(node["tags"] for node in imported_baseline.values())
        types = {value[0] for node in imported_baseline.values() for value in node["props"].values()}
        assert {"UDim2", "Color3", "ColorSequence", "NumberSequence", "Font", "token"} <= types
        print(f"LARGE: {len(imported_baseline)} imported-service instances; scripts={dict(scripts)}; depth={max(map(len, imported_baseline))}; duplicate sibling groups={len(duplicates)}", flush=True)
        print("Binary baseline: XML build of the same generated project; no lossy syncback used as an oracle", flush=True)
        reports = []
        for suffix in ("rbxlx", "rbxl"):
            place = source / f"original.{suffix}"
            before = place.read_bytes()
            target = root / f"imported-{suffix}"
            run([bash_executable(), (ROOT / "scripts/new-project.sh").as_posix(), target.as_posix(), f"Fidelity {suffix}", "--no-tools"], ROOT)
            managed = managed_snapshot(target)
            run(["rojo", "build", "default.project.json", "-o", "scaffold.rbxlx"], target)
            scaffold, _ = parse_place(target / "scaffold.rbxlx")
            original_kit = kit_nodes(scaffold)
            assert original_kit and any(node["source"] for node in original_kit.values()), "scaffold Kit missing"
            tick = time.perf_counter()
            run([bash_executable(), (ROOT / "scripts/import-place.sh").as_posix(), target.as_posix(), place.as_posix()], ROOT)
            seconds = time.perf_counter() - tick
            assert place.read_bytes() == before, "original input bytes changed"
            extracted_sources = Counter(p.read_bytes() for service in SERVICES for p in (target / "src" / service).rglob("*")
                                        if p.is_file() and p.suffix in (".luau", ".lua"))
            expected_sources = Counter(node["source"] for node in imported_baseline.values() if node["class"] in SCRIPT_CLASSES)
            assert extracted_sources == expected_sources, "syncback did not preserve all script file bytes"
            current = managed_snapshot(target)
            assert all(current.get(path) == digest for path, digest in managed.items()), "scaffold/Kit/managed file changed"
            run(["git", "diff", "--cached", "--exit-code"], target)
            cfg = project.read_json(target / "default.project.json")
            assert "Workspace" not in cfg["tree"] and "Lighting" not in cfg["tree"]
            assert cfg["tree"]["$ignoreUnknownInstances"] is True
            assert not (target / "src/Workspace").exists() and not (target / "src/Lighting").exists()
            assert all("$properties" not in cfg["tree"].get(name, {}) for name in ("Workspace", "Lighting", "StarterPlayer"))
            run(["rojo", "build", "default.project.json", "-o", "rebuilt.rbxlx"], target)
            rebuilt, new_duplicates = parse_place(target / "rebuilt.rbxlx")
            # Only these exact reserved subtrees are supplied by the intact scaffold.
            kit = kit_nodes(rebuilt)
            kit_counts, kit_details, _ = compare(original_kit, kit)
            assert not sum(kit_counts.values()), "rebuilt Kit changed: " + "\n".join(kit_details)
            actual = {key: node for key, node in rebuilt.items() if key[0][0] in SERVICES and key not in kit}
            assert not any(key[0][0] in ("Workspace", "Lighting") for key in rebuilt), "code build owns original world"
            counts, details, expected = compare(imported_baseline, actual, defaults, allow_design=True, duplicates=duplicates)
            for line in details:
                print(f".{suffix} {line}")
            files = sum(p.is_file() for service in SERVICES for p in (target / "src" / service).rglob("*"))
            reports.append((suffix, counts, seconds, files, len(kit), expected))
            print(f".{suffix}: LARGE import={seconds:.3f}s; imported files={files}; input byte-identical; {sum(extracted_sources.values())} script files byte-identical; {len(managed)} managed files byte-identical; {len(kit)} Kit instances intact", flush=True)
            print(f".{suffix}: {len(new_duplicates)} duplicate sibling groups checked by ordinal; identity ambiguous, no guessed matching", flush=True)
        print("\nDifference category          rbxlx    rbxl   classification")
        for category in CATEGORIES:
            print(f"{category:28} {reports[0][1][category]:7} {reports[1][1][category]:7}   unexpected")
        for category, reason in EXPECTED_REASONS.items():
            print(f"{category:28} {reports[0][5][category]:7} {reports[1][5][category]:7}   expected by design: {reason}")
        world = sum(key[0][0] in ("Workspace", "Lighting") for key in baseline)
        print(f"{'world instances omitted':28} {world:7} {world:7}   expected by design: scripts/project.py:import_config omits Workspace/Lighting; original input unchanged; terrain voxels/Studio connection untested")
        print(f"{'Kit instances added':28} {reports[0][4]:7} {reports[1][4]:7}   expected by design: scripts/project.py:import_config(with_kit=True); exact scaffold subtrees verified separately")
        print(f"Total wall-clock: {time.perf_counter() - started:.3f}s")
        assert not any(sum(report[1].values()) for report in reports), "unexpected import fidelity loss (see differences above)"
        print("PASS: real-Rojo LARGE/UI/RIG/WORLD import fidelity (.rbxlx + binary .rbxl); source and managed files intact")
    finally:
        if context:
            context.cleanup()


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
