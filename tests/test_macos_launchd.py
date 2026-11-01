"""macOS CI 専用。ダミーHTTPサービスで実際のlaunchd起動・重複回避・停止を確認。"""
import argparse
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'setup/macos'))
import control as mac
sys.path.pop(0)


@unittest.skipUnless(sys.platform == 'darwin', 'macOS launchd only; no real VM or Crew')
class LaunchdTest(unittest.TestCase):
    def test_native_launchd_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='opencae-launchd-') as tmp:
            root = Path(tmp).resolve() / '日本語 project'
            root.mkdir()
            s = mac.Settings(root, Path(tmp) / 'home')
            s.private_dirs()
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            s.config = dict(schema=1, project=str(root), port=port, profile=mac.PROFILE,
                            phase='Ready', vmOwned=True)
            mac.save_json(s.file, s.config)
            binary = s.tools / 'bin/kirocrew'
            binary.parent.mkdir()
            # 実際のLLM・Crew・Docker・VMには接続しない。
            binary.write_text(f'''#!{sys.executable}
import http.server, sys
if sys.argv[1] == 'token':
    print('http://localhost:{port}/?token=LAUNCHD_TEST')
else:
    http.server.ThreadingHTTPServer(('127.0.0.1', {port}), http.server.SimpleHTTPRequestHandler).serve_forever()
''')
            binary.chmod(0o755)
            start = argparse.Namespace(status=False, open_browser=False)
            status = argparse.Namespace(status=True, open_browser=False)
            try:
                with patch.object(s, 'colima'), redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(s.start(start), 0)
                    self.assertEqual(s.start(start), 0)
                    self.assertIn(f'http://localhost:{port}/?token=LAUNCHD_TEST', output.getvalue())
                    self.assertEqual(s.start(status), 0)
                    self.assertTrue(s.service_running())
                    self.assertEqual(s.stop(), 0)
                    self.assertEqual(s.start(status), 3)
                    self.assertEqual(s.stop(), 0)
            finally:
                subprocess.run(['launchctl', 'bootout', s.target], capture_output=True, check=False)


if __name__ == '__main__':
    unittest.main()
