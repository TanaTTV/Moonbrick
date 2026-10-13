import importlib.util
import json
from pathlib import Path
import tempfile
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
            with patch.object(server, "probe", side_effect=[OSError("absent"), {"projectName": "same", "sessionId": "foreign"}]), patch.object(server.socket, "socket", return_value=connection), patch.object(server.shutil, "which", return_value="rojo"), patch.object(server.subprocess, "Popen", return_value=child), patch.object(server, "listener_owned", return_value=False), self.assertRaisesRegex(ValueError, "another process"):
                server.ensure(root)
            self.assertFalse((root / ".moonbrick/serve.json").exists())

    def test_native_listener_pid_parsing_refuses_ambiguous_owners(self):
        result = Mock(stdout="TCP 127.0.0.1:4999 0.0.0.0:0 LISTENING 42\nTCP 127.0.0.1:5000 0.0.0.0:0 LISTENING 43\n")
        with patch.object(server.os, "name", "nt"), patch.object(server.subprocess, "run", return_value=result):
            self.assertEqual(server.listener_pid(4999), 42)
            result.stdout += "TCP 127.0.0.1:4999 0.0.0.0:0 LISTENING 44\n"
            with self.assertRaisesRegex(ValueError, "exclusive"): server.listener_pid(4999)

    def test_listener_ownership_accepts_child_and_rejects_foreign_parent(self):
        with patch.object(server, "listener_pid", return_value=42), patch.object(server.subprocess, "run", return_value=Mock(stdout="99\n")):
            self.assertTrue(server.listener_owned(4999, 99))
        with patch.object(server, "listener_pid", return_value=42), patch.object(server.subprocess, "run", return_value=Mock(stdout="0\n")):
            self.assertFalse(server.listener_owned(4999, 99))


if __name__ == "__main__": unittest.main()
