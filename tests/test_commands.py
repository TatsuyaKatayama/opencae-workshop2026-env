"""ホスト設定を変更せず、Docker 実行入口の契約を検証する。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CommandsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        docker = self.path / "docker"
        docker.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if args[0] == "context":
    print("unix:///var/run/docker.sock")
elif args[0] == "info":
    print(os.environ["FAKE_INFO"])
elif args[0] == "compose" and "run" in args:
    Path(os.environ["FAKE_ARGS"]).write_text(json.dumps(args))
    sys.exit(int(os.environ.get("FAKE_EXIT", "0")))
''')
        docker.chmod(0o755)
        arch = os.uname().machine
        self.env = dict(os.environ, PATH=f"{self.path}:{os.environ['PATH']}",
                        FAKE_INFO=f"Ubuntu 24.04 LTS|linux|{arch}",
                        FAKE_ARGS=str(self.path / "args.json"))
        for name in ("DOCKER_HOST", "DOCKER_CONTEXT", "CFD_PLATFORM"):
            self.env.pop(name, None)

    def run_tool(self, *args):
        return subprocess.run([str(ROOT / "scripts/run-tool.sh"), *args],
                              cwd=self.path, env=self.env, text=True,
                              capture_output=True)

    def test_preserves_arguments_cwd_and_exit_code(self):
        self.env["FAKE_EXIT"] = "42"
        args = ["printf", "%s\\n", "a b", "$(touch SHOULD_NOT_EXIST)", "line1\nline2"]
        result = self.run_tool(*args)
        self.assertEqual(result.returncode, 42, result.stderr)
        actual = json.loads((self.path / "args.json").read_text())
        self.assertEqual(actual[-len(args):], args)
        self.assertIn(str(ROOT / "compose/compose.yaml"), actual)
        self.assertIn("never", actual)
        self.assertFalse((self.path / "SHOULD_NOT_EXIST").exists())

    def test_rejects_desktop(self):
        self.env["FAKE_INFO"] = "Docker Desktop|linux|aarch64"
        result = self.run_tool("true")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("WSL", result.stderr)
        self.assertFalse((self.path / "args.json").exists())

    def test_rejects_remote_daemon(self):
        self.env["DOCKER_HOST"] = "tcp://example.invalid:2375"
        result = self.run_tool("true")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("標準構成", result.stderr)

    def test_requires_command(self):
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("使用法", result.stderr)


if __name__ == "__main__":
    unittest.main()
