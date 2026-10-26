import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("server", ROOT / "scripts/dev-server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class DevServerTests(unittest.TestCase):
    def test_msgpack_server_info(self):
        raw = b'\x83\xabprojectName\xa4game\xa9sessionId\xa3abc\xafprotocolVersion\x05'
        self.assertEqual(server.decode_msgpack(raw), {"projectName": "game", "sessionId": "abc", "protocolVersion": 5})

    def test_truncated_or_unsupported_payload_refused(self):
        for payload in (b'\xd9\xfftiny', b'\x81\xc0\xc0', b'\xa2x', b'\xc7', b'\xc0extra'):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                server.decode_msgpack(payload)

    def test_same_name_other_project_is_not_claimed_or_stopped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "default.project.json").write_text(json.dumps({"name": "same"}))
            with patch.object(server, "probe", return_value={"projectName": "same", "sessionId": "other"}), patch.object(server.subprocess, "Popen") as launch:
                self.assertIsNone(server.ensure(root))
                launch.assert_not_called()

    def test_invalid_port_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for value in (True, "1234", 80, 99999):
                (root / "default.project.json").write_text(json.dumps({"servePort": value}))
                with self.subTest(value=value), self.assertRaises(ValueError): server.ensure(root)

    def test_non_object_project_file_is_a_clear_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "default.project.json").write_text("[]")
            with self.assertRaisesRegex(ValueError, "JSON object"): server.ensure(root)

    def test_same_name_startup_race_cannot_claim_foreign_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "default.project.json").write_text(json.dumps({"name": "same"}))
            child = Mock(pid=12345)
            child.poll.return_value = None
            connection = Mock()
            connection.__enter__ = Mock(return_value=connection)
            connection.__exit__ = Mock(return_value=False)
            connection.connect_ex.return_value = 1
            with patch.object(server, "probe", side_effect=[OSError("absent"), {"projectName": "same", "sessionId": "foreign"}]), patch.object(server.socket, "socket", return_value=connection), patch.object(server.shutil, "which", return_value="rojo"), patch.object(server.subprocess, "Popen", return_value=child), patch.object(server, "listener_owned", return_value=False), patch.object(server, "stop_tree") as stop, self.assertRaisesRegex(ValueError, "another process"):
                server.ensure(root)
            self.assertFalse((root / ".moonbrick/serve.json").exists())
            stop.assert_called_once_with(child)  # a failed launch must not leave its own Rojo holding the port

    def test_successful_launch_is_left_running(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "default.project.json").write_text(json.dumps({"name": "game"}))
            child = Mock(pid=12345)
            child.poll.return_value = None
            connection = Mock()
            connection.__enter__ = Mock(return_value=connection)
            connection.__exit__ = Mock(return_value=False)
            connection.connect_ex.return_value = 1
            identity = {"projectName": "game", "sessionId": "mine"}
            with patch.object(server, "probe", side_effect=[OSError("absent"), identity, identity]), patch.object(server.socket, "socket", return_value=connection), patch.object(server.shutil, "which", return_value="rojo"), patch.object(server.subprocess, "Popen", return_value=child), patch.object(server, "listener_owned", return_value=True), patch.object(server, "stop_tree") as stop:
                self.assertIs(server.ensure(root), child)
            stop.assert_not_called()
            self.assertEqual(json.loads((root / ".moonbrick/serve.json").read_text())["sessionId"], "mine")

    def test_startup_lock_recovers_from_a_killed_launch_but_respects_a_live_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / "serve.lock"
            lock.write_text("")
            self.assertFalse(server.take_lock(lock), "fresh lock: another startup is running")
            old = time.time() - server.STALE_LOCK - 5
            os.utime(lock, (old, old))
            self.assertTrue(server.take_lock(lock), "stale lock from a killed process is reclaimed")
            self.assertTrue(lock.exists())
            self.assertEqual(sorted(p.name for p in Path(tmp).iterdir()), ["serve.lock"])
            lock.unlink()
            self.assertTrue(server.take_lock(lock))

    def test_live_startup_lock_reports_progress_instead_of_crashing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "default.project.json").write_text(json.dumps({"name": "game"}))
            (root / ".moonbrick").mkdir()
            (root / ".moonbrick/serve.lock").write_text("")
            connection = Mock()
            connection.__enter__ = Mock(return_value=connection)
            connection.__exit__ = Mock(return_value=False)
            connection.connect_ex.return_value = 1
            with patch.object(server, "probe", side_effect=OSError("absent")), patch.object(server.socket, "socket", return_value=connection), patch.object(server.shutil, "which", return_value="rojo"), patch.object(server.subprocess, "Popen") as launch:
                self.assertIsNone(server.ensure(root))
                launch.assert_not_called()
            self.assertTrue((root / ".moonbrick/serve.lock").exists(), "another starter's lock is left alone")

    def test_native_listener_pid_parsing_refuses_ambiguous_owners(self):
        result = Mock(stdout="TCP 127.0.0.1:4999 0.0.0.0:0 LISTENING 42\nTCP 127.0.0.1:5000 0.0.0.0:0 LISTENING 43\n")
        with patch.object(server.os, "name", "nt"), patch.object(server.subprocess, "run", return_value=result):
            self.assertEqual(server.listener_pid(4999), 42)
            result.stdout += "TCP 127.0.0.1:4999 0.0.0.0:0 LISTENING 44\n"
            with self.assertRaisesRegex(ValueError, "exclusive"): server.listener_pid(4999)

    def test_windows_listener_parsing_does_not_depend_on_english_state_names(self):
        # German netstat: LISTENING is "ABHÖREN"; an established loopback peer on the same port is not a listener.
        result = Mock(stdout="  TCP    127.0.0.1:4999    0.0.0.0:0    ABHÖREN    42\n  TCP    127.0.0.1:4999    127.0.0.1:50000    HERGESTELLT    77\n")
        with patch.object(server.os, "name", "nt"), patch.object(server.subprocess, "run", return_value=result):
            self.assertEqual(server.listener_pid(4999), 42)

    def test_linux_without_lsof_reads_proc(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = Path(tmp)
            (proc / "net").mkdir()
            header = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"
            listen = "   0: 0100007F:1387 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 555 1\n"
            other = "   1: 0100007F:1387 0100007F:C350 01 00000000:00000000 00:00000000 00000000  1000        0 556 1\n"
            (proc / "net/tcp").write_text(header + listen + other)
            for pid in ("42", "77"):
                (proc / pid / "fd").mkdir(parents=True)
                (proc / pid / "fd/3").write_text("")
            sockets = {"42": "socket:[555]", "77": "socket:[556]"}
            with patch.object(server.os, "readlink", side_effect=lambda fd: sockets[Path(fd).parent.parent.name]):
                self.assertEqual(server.proc_listener_pids(4999, proc), {42})

    def test_missing_lsof_and_proc_is_reported(self):
        with patch.object(server.os, "name", "posix"), patch.object(server.shutil, "which", return_value=None), patch.object(server.Path, "is_file", return_value=False):
            with self.assertRaisesRegex(ValueError, "lsof is required"): server.listener_pid(4999)

    def test_listener_ownership_accepts_child_and_rejects_foreign_parent(self):
        with patch.object(server.os, "name", "posix"), patch.object(server, "listener_pid", return_value=42), patch.object(server.subprocess, "run", return_value=Mock(stdout="99\n")):
            self.assertTrue(server.listener_owned(4999, 99))
        with patch.object(server.os, "name", "posix"), patch.object(server, "listener_pid", return_value=42), patch.object(server.subprocess, "run", return_value=Mock(stdout="0\n")):
            self.assertFalse(server.listener_owned(4999, 99))

    def test_windows_ownership_walks_snapshot_without_powershell(self):
        with patch.object(server.os, "name", "nt"), patch.object(server, "listener_pid", return_value=42), patch.object(server.subprocess, "run") as run:
            with patch.object(server, "windows_parents", return_value={42: 7, 7: 99}):
                self.assertTrue(server.listener_owned(4999, 99), "rokit shim -> rojo child is owned")
            with patch.object(server, "windows_parents", return_value={42: 7, 7: 4}):
                self.assertFalse(server.listener_owned(4999, 99))
            with patch.object(server, "windows_parents", return_value={42: 42}):
                self.assertFalse(server.listener_owned(4999, 99), "self-parent loops are bounded")
            run.assert_not_called()

    @unittest.skipUnless(os.name == "nt", "Windows process snapshot")
    def test_windows_snapshot_reports_this_process_parent(self):
        started = time.monotonic()
        parents = server.windows_parents()
        self.assertEqual(parents[os.getpid()], os.getppid())
        self.assertLess(time.monotonic() - started, 2)


if __name__ == "__main__": unittest.main()
