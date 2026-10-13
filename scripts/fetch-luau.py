"""Download a pinned official Luau CLI; verify release SHA256 before extracting executables."""
import hashlib
import io
from pathlib import Path
import platform
import urllib.request
import zipfile

VERSION = "0.742"
DIGESTS = {
    "Windows": ("windows", "1114966cd8198f407069f07e8b4e6bacf2ded933e4a57d6ddc75617969278c75"),
    "Linux": ("ubuntu", "152058b98c60ff1f5b5ec9bca0b8eb37793cae161dd3a05608cc3d8738ba1a4d"),
    "Darwin": ("macos", "bdd415766fbe03bc090b65fa6141531a4a54608db95a5350a5a0b49862bdac83"),
}


def main():
    target, digest = DIGESTS[platform.system()]
    url = f"https://github.com/luau-lang/luau/releases/download/{VERSION}/luau-{target}.zip"
    with urllib.request.urlopen(url, timeout=60) as response:
        content = response.read()
    if hashlib.sha256(content).hexdigest() != digest:
        raise RuntimeError("Luau release checksum mismatch")
    dest = Path(__file__).resolve().parents[1] / ".artifacts/tools/luau"
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        for name in ("luau", "luau-compile", "luau-analyze"):
            filename = name + (".exe" if platform.system() == "Windows" else "")
            path = dest / filename
            path.write_bytes(archive.read(filename))
            path.chmod(0o755)
    print(dest)


if __name__ == "__main__":
    main()
