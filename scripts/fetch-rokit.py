"""Install official Rokit 1.2.0 with SHA256 verification, without executing a remote installer."""
import argparse
import hashlib
import io
from pathlib import Path
import platform
import zipfile
import urllib.request

VERSION = "1.2.0"
DIGESTS = {
    ("Windows", "x86_64"): "f9ba1704014ff67d51e8005f605955c7c26d2429a5312a9419dc477fc310e96d",
    ("Windows", "aarch64"): "aff0e76e304fdc938cffa5b7ee1e183a052acac541868b4271192f20c734282a",
    ("Linux", "x86_64"): "951a7f3ec3d2a5e021fd1867d32f69f010ee4c2927f644b759578afc59c65fc0",
    ("Linux", "aarch64"): "b9ba200dd70620d9dbc11bbb0b368a62c6891328e6bc5fab4b7f68200089553a",
    ("Darwin", "x86_64"): "9643ca30421e9c3dda1f4996bb03b3a43b08dfdc17c28198843e2233e446ba10",
    ("Darwin", "aarch64"): "eb8e6b4f8026db2b80ad0887c50f342958ecdbacbdeda2fd6028b3c4f774a3ee",
}


def install(dest: Path):
    system = platform.system()
    arch = {"amd64": "x86_64", "arm64": "aarch64"}.get(platform.machine().lower(), platform.machine().lower())
    digest = DIGESTS.get((system, arch))
    if digest is None: raise ValueError(f"unsupported Rokit platform: {system}/{arch}")
    os_name = {"Windows": "windows", "Linux": "linux", "Darwin": "macos"}[system]
    executable = "rokit.exe" if system == "Windows" else "rokit"
    target = dest / executable
    if target.exists() or target.is_symlink(): raise ValueError(f"refusing to replace existing Rokit: {target}")
    url = f"https://github.com/rojo-rbx/rokit/releases/download/v{VERSION}/rokit-{VERSION}-{os_name}-{arch}.zip"
    with urllib.request.urlopen(url, timeout=60) as response: content = response.read()
    if hashlib.sha256(content).hexdigest() != digest: raise ValueError("Rokit release checksum mismatch")
    with zipfile.ZipFile(io.BytesIO(content)) as archive: data = archive.read(executable)
    dest.mkdir(parents=True, exist_ok=True)
    with target.open("xb") as file: file.write(data)
    target.chmod(0o755)
    print(f"Installed verified Rokit {VERSION} at {target}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, default=Path.home() / ".rokit/bin")
    try: install(parser.parse_args().dest)
    except (OSError, ValueError) as error: parser.exit(1, f"error: {error}\n")
