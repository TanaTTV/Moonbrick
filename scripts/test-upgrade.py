"""Upgrade an actual 0.1 scaffold from local git history; check game/settings preservation and build."""
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

from project import sync, run, write_json

ROOT = Path(__file__).resolve().parents[1]
BASE = "c451028"


def main():
    bash = r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else shutil.which("bash")
    data = subprocess.run(["git", "archive", "--format=zip", BASE, "template", "luau", "scripts", ".claude-plugin/plugin.json"], cwd=ROOT, check=True, capture_output=True).stdout
    env = dict(os.environ, GIT_AUTHOR_NAME="Moonbrick upgrade test", GIT_AUTHOR_EMAIL="test@moonbrick.invalid", GIT_COMMITTER_NAME="Moonbrick upgrade test", GIT_COMMITTER_EMAIL="test@moonbrick.invalid")
    with tempfile.TemporaryDirectory(prefix="moonbrick-upgrade-") as tmp:
        root = Path(tmp)
        baseline = root / "baseline"
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            # Local trusted repository snapshot, confined to the test's scratch directory.
            for item in archive.infolist():
                dest = baseline / item.filename
                if item.is_dir(): dest.mkdir(parents=True, exist_ok=True)
                else:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(archive.read(item))
        game = root / "game"
        subprocess.run([bash, str(baseline / "scripts/new-project.sh"), str(game), "upgrade-fixture", "--no-tools"], env=env, check=True, timeout=60)
        custom = game / "src/server/Game.server.luau"
        custom.write_text('--!strict\nprint("game code retained")\n')
        original = custom.read_bytes()
        cfg = json.loads((game / "default.project.json").read_text())
        cfg["servePort"], cfg["servePlaceIds"] = 34885, [123456]
        write_json(game / "default.project.json", cfg)
        old = (game / "src/kit/server/PlayerData.luau").read_bytes()
        sync(game)
        assert custom.read_bytes() == original
        cfg = json.loads((game / "default.project.json").read_text())
        assert cfg["servePort"] == 34885 and cfg["servePlaceIds"] == [123456]
        assert ".moonbrick/" in (game / ".gitignore").read_text()
        assert any(path.read_bytes() == old for path in (game / ".moonbrick/backups").rglob("PlayerData.luau"))
        subprocess.run([bash, "tools/check.sh"], cwd=game, check=True, timeout=120)
        os.environ["PATH"] = str(Path.home() / ".rokit/bin") + os.pathsep + os.environ["PATH"]
        run("rojo", "build", "default.project.json", "-o", "upgraded.rbxlx", cwd=game)
        print("PASS: actual 0.1 scaffold upgrade, game/settings preservation, backups, checker and Rojo build")


if __name__ == "__main__": main()
