"""Loopback-only Rojo startup with bounded probing and project/session ownership checks."""
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import time
import urllib.request


def decode_msgpack(payload: bytes):
    # Small bounded decoder for Rojo's server-info map; never processes scripts or arbitrary extensions.
    offset = 0
    def take(size):
        nonlocal offset
        if size > len(payload) - offset:
            raise ValueError("truncated Rojo response")
        value = payload[offset:offset + size]
        offset += size
        return value
    def integer(size):
        return int.from_bytes(take(size), "big")
    def read(depth=0):
        if depth > 16:
            raise ValueError("Rojo response nesting limit")
        code = integer(1)
        if code <= 0x7f: return code
        if code >= 0xe0: return code - 256
        if code == 0xc0: return None
        if code in (0xc2, 0xc3): return code == 0xc3
        if code in (0xcc, 0xcd, 0xce, 0xcf): return integer(1 << (code - 0xcc))
        if code in (0xd0, 0xd1, 0xd2, 0xd3): return int.from_bytes(take(1 << (code - 0xd0)), "big", signed=True)
        if 0xa0 <= code <= 0xbf: return take(code & 31).decode("utf-8")
        if code in (0xd9, 0xda, 0xdb): return take(integer(1 << (code - 0xd9))).decode("utf-8")
        if 0x90 <= code <= 0x9f or code in (0xdc, 0xdd):
            size = code & 15 if code <= 0x9f else integer(2 if code == 0xdc else 4)
            if size > 4096: raise ValueError("Rojo response array limit")
            return [read(depth + 1) for _ in range(size)]
        if 0x80 <= code <= 0x8f or code in (0xde, 0xdf):
            size = code & 15 if code <= 0x8f else integer(2 if code == 0xde else 4)
            if size > 256: raise ValueError("Rojo response map limit")
            result = {}
            for _ in range(size):
                key = read(depth + 1)
                if not isinstance(key, str) or key in result: raise ValueError("invalid Rojo response map key")
                result[key] = read(depth + 1)
            return result
        if code in (0xca, 0xcb): return struct.unpack(">f" if code == 0xca else ">d", take(4 if code == 0xca else 8))[0]
        raise ValueError("unsupported Rojo response type")
    result = read()
    if offset != len(payload): raise ValueError("trailing Rojo response bytes")
    return result


def probe(port):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(f"http://127.0.0.1:{port}/api/rojo", timeout=1) as response:
        payload = response.read(16385)
        if len(payload) > 16384: raise ValueError("Rojo response exceeds 16KB")
        result = json.loads(payload) if "json" in response.headers.get("Content-Type", "") else decode_msgpack(payload)
    if not isinstance(result, dict) or not isinstance(result.get("projectName"), str) or not isinstance(result.get("sessionId"), str):
        raise ValueError("invalid Rojo server identity")
    return result


def listener_pid(port):
    if os.name == "nt":
        result = subprocess.run(["netstat", "-ano", "-p", "tcp"], capture_output=True, text=True, check=True, timeout=3)
        owners = {int(row[-1]) for line in result.stdout.splitlines() if len(row := line.split()) >= 5 and row[0] == "TCP" and row[1] == f"127.0.0.1:{port}" and row[-2] == "LISTENING"}
    else:
        result = subprocess.run(["lsof", "-nP", f"-iTCP@127.0.0.1:{port}", "-sTCP:LISTEN", "-Fp"], capture_output=True, text=True, timeout=3)
        owners = {int(line[1:]) for line in result.stdout.splitlines() if line.startswith("p") and line[1:].isdigit()}
    if len(owners) != 1: raise ValueError("unable to establish exclusive Rojo listener process")
    return owners.pop()


def listener_owned(port, launched_pid):
    pid = listener_pid(port)
    for _ in range(16):
        if pid == launched_pid: return True
        if pid <= 1: return False
        if os.name == "nt":
            # Numeric PID only; never print process arguments, environment or credentials.
            command = f"(Get-CimInstance Win32_Process -Filter 'ProcessId = {pid}').ParentProcessId"
            # WMI/PowerShell cold start can exceed several seconds on busy or CI machines.
            result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command], capture_output=True, text=True, timeout=20)
        else:
            result = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True, timeout=3)
        value = result.stdout.strip()
        if not value.isdigit(): return False
        pid = int(value)
    return False


STALE_LOCK = 60  # startup holds the lock for at most ~5 s; an older lock was left by a killed process


def take_lock(lock: Path) -> bool:
    for _ in range(2):
        try:
            descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            if lock.is_symlink() or time.time() - lock.stat().st_mtime < STALE_LOCK:
                return False
            # Move the stale lock aside atomically. If another starter replaced it meanwhile, put theirs back.
            aside = lock.with_name(f"serve.lock.stale-{os.getpid()}")
            try:
                os.replace(lock, aside)
            except FileNotFoundError:
                continue
            if time.time() - aside.stat().st_mtime < STALE_LOCK:
                os.replace(aside, lock)
                return False
            aside.unlink()
            print("moonbrick: removed a stale startup lock left by an interrupted Rojo launch.")
            continue
        os.close(descriptor)
        return True
    return False


def ensure(project: Path):
    project = project.resolve()
    cfg = json.loads((project / "default.project.json").read_text(encoding="utf-8"))
    name = cfg.get("name", project.name)
    port = cfg.get("servePort", 34872)
    if type(port) != int or not 1024 <= port <= 65535: raise ValueError("servePort must be 1024..65535")
    state = project / ".moonbrick"
    if state.is_symlink() or (hasattr(state, "is_junction") and state.is_junction()):
        raise ValueError(".moonbrick must be a local directory")
    state.mkdir(exist_ok=True)
    marker = state / "serve.json"
    if marker.is_symlink() or (project / ".rojo.log").is_symlink(): raise ValueError("Rojo state/log must not be symlinks")
    try:
        current = probe(port)
    except (OSError, ValueError):
        with socket.socket() as connection:
            connection.settimeout(0.5)
            if connection.connect_ex(("127.0.0.1", port)) == 0:
                print(f"moonbrick: port {port} is occupied by an unrecognized service; choose another servePort.")
                return None
    else:
        owned = json.loads(marker.read_text()) if marker.exists() else {}
        if current["projectName"] == name and owned.get("project") == str(project) and owned.get("sessionId") == current["sessionId"]:
            print(f"moonbrick: Rojo already serving {name!r} on :{port}; verify Studio is connected.")
        else:
            print(f"moonbrick: :{port} serves {current['projectName']!r}; ownership for this folder is unverified. Choose another servePort or inspect the existing server.")
        return None
    rojo = shutil.which("rojo")
    if not rojo: raise ValueError("Rojo unavailable; run setup-tools.sh")
    lock = state / "serve.lock"
    if not take_lock(lock):
        print("moonbrick: another Rojo startup for this project is in progress; retry in a few seconds.")
        return None
    process = None
    try:
        with (project / ".rojo.log").open("a", encoding="utf-8") as log:
            process = subprocess.Popen([rojo, "serve", "default.project.json", "--port", str(port), "--address", "127.0.0.1"], cwd=project, stdout=log, stderr=log, start_new_session=os.name != "nt", creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if process.poll() is not None: raise ValueError("Rojo failed to start; see .rojo.log")
            try:
                current = probe(port)
            except (OSError, ValueError):
                time.sleep(0.1)
                continue
            if current["projectName"] != name: raise ValueError("port ownership changed during startup; see .rojo.log")
            if not listener_owned(port, process.pid): raise ValueError("startup listener belongs to another process; refusing ownership")
            confirmed = probe(port)
            if confirmed["sessionId"] != current["sessionId"]: raise ValueError("startup listener session changed; refusing ownership")
            if process.poll() is not None: raise ValueError("owned Rojo process exited during startup")
            marker.write_text(json.dumps({"pid": process.pid, "project": str(project), "port": port, "sessionId": current["sessionId"]}) + "\n", encoding="utf-8")
            print(f"moonbrick: started Rojo for {name!r} on :{port}; connect Studio and review its diff.")
            return process
        raise ValueError("Rojo startup timed out; see .rojo.log")
    finally:
        # Never stop another project/process. A failed owned launch may still be running; report its PID.
        lock.unlink(missing_ok=True)
        if process and process.poll() is None and not marker.exists():
            print(f"moonbrick: owned startup process PID {process.pid} may still be running; inspect .rojo.log before retrying.")


if __name__ == "__main__":
    try:
        root = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
        if (root / "default.project.json").is_file() and (root / "tools/MCPKit.luau").is_file():
            ensure(root)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"moonbrick: {error}")
