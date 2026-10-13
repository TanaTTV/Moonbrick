"""Real Rojo smoke tests in disposable projects. Stops only the process created by this test."""
import importlib.util
import os
from pathlib import Path
import shutil
import socket
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    os.environ["PATH"] = str(Path.home() / ".rokit/bin") + os.pathsep + os.environ["PATH"]
    project = load("project", "project.py")
    server = load("dev_server", "dev-server.py")
    with tempfile.TemporaryDirectory(prefix="moonbrick-integration-") as tmp:
        root = Path(tmp)
        original = root / "original"
        original.mkdir()
        shutil.copy2(ROOT / "template/rokit.toml", original / "rokit.toml")
        (original / "src").mkdir()
        (original / "src/Hello.server.luau").write_text('print("hello")\n')
        (original / "src/Kitten.luau").write_text('return "preserve prefix names"\n')
        cfg = {"name": "Original", "tree": {"$className": "DataModel", "ServerScriptService": {"$path": "src"}, "Workspace": {"Map": {"$className": "Part", "$properties": {"Anchored": True, "Size": [20, 1, 20]}}}}}
        project.write_json(original / "default.project.json", cfg)
        project.run("rojo", "build", "default.project.json", "-o", "original.rbxlx", cwd=original)
        place = original / "original.rbxlx"
        before = place.read_bytes()
        imported = root / "imported"
        project.new_project(imported, 'Imported "quoted" game')
        project.import_place(imported, place)
        assert place.read_bytes() == before, "input place was mutated"
        assert (imported / "src/ServerScriptService/Hello.server.luau").read_text().strip() == 'print("hello")'
        assert (imported / "src/ServerScriptService/Kitten.luau").exists(), "prefix name erased"
        imported_cfg = project.read_json(imported / "default.project.json")
        assert "Workspace" not in imported_cfg["tree"], "import should preserve the original world's place ownership"
        project.run("rojo", "build", "default.project.json", "-o", "code-only.rbxlx", cwd=imported)
        with socket.socket() as connection:
            connection.bind(("127.0.0.1", 0))
            port = connection.getsockname()[1]
        imported_cfg["servePort"] = port
        project.write_json(imported / "default.project.json", imported_cfg)
        process = server.ensure(imported)
        assert process is not None, "test server did not start"
        try:
            info = server.probe(port)
            assert info["projectName"] == imported_cfg["name"]
            assert server.ensure(imported) is None, "duplicate server started"
        finally:
            process.terminate()
            process.wait(timeout=5)
        print("PASS: real Rojo build, missing-service syncback, prefix preservation, input fidelity, MessagePack handshake, startup ownership and reuse")


if __name__ == "__main__": main()
