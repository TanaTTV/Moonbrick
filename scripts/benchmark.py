"""Prepare a disposable Studio hierarchy for a reproducible MCP tree-output benchmark."""
import argparse
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]


def prepare(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    name = "MoonbrickBench_" + uuid.uuid4().hex
    key = name + "_Kit"
    kit = (ROOT / "luau/MCPKit.luau").read_text(encoding="utf-8").replace("_G.K = K", "-- benchmark owns a separate cache")
    # Inert parts in a dedicated ServerStorage container; no modifications to existing objects.
    code = f'''local K = (function()\n{kit}\nend)()
local folder = Instance.new("Folder")
folder.Name = "{name}"
for group = 1,3 do
    local child = Instance.new("Folder"); child.Name = "Group" .. group
    for index = 1,50 do
        local part = Instance.new("Part"); part.Name = "Part" .. index; part.Anchored = true; part.Parent = child
    end
    child.Parent = folder
    task.wait()
end
folder.Parent = game:GetService("ServerStorage")
_G["{key}"] = K
return "prepared {name}: 154 instances"
'''
    compact = f'return _G["{key}"].tree("ServerStorage.{name}",2,nil,200)'
    cleanup = f'local root=game:GetService("ServerStorage"):FindFirstChild("{name}"); if root then root:Destroy() end; _G["{key}"]=nil; return "benchmark cleaned"'
    (directory / "prepare.luau").write_text(code, encoding="utf-8", newline="\n")
    (directory / "compact.luau").write_text(compact, encoding="utf-8", newline="\n")
    (directory / "cleanup.luau").write_text(cleanup, encoding="utf-8", newline="\n")
    (directory / "fixture.json").write_text(json.dumps({"path": "ServerStorage." + name, "instances": 154, "compactCode": compact, "cleanupCode": cleanup, "setupCodeCharacters": len(code)}, indent=2), encoding="utf-8")
    print(directory)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    prepare(parser.parse_args().directory)
