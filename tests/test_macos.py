"""macOS 制御の契約テスト。実機 VM・認証・インストールには触れない。"""
import argparse
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'setup/macos'))
import control as mac
import install as installer
sys.path.pop(0)


class MacTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.root = self.base / '日本語 project'
        (self.root / 'setup/config/codex-acp').mkdir(parents=True)
        for name in ('agents.env', 'macos.env', 'codex-acp/package-lock.json'):
            shutil.copyfile(ROOT / 'setup/config' / name, self.root / 'setup/config' / name)
        self.s = mac.Settings(self.root, self.base / 'home')
        self.s.private_dirs()
        self.args = argparse.Namespace(port=5476, cpu=2, memory=8, disk=100, agents_only=False)
        self.s.init(self.args)
        self.calls = []
        self.loaded = False
        self.authenticated = False
        self.s.run = self.run_mock
        (self.s.tools / 'bin').mkdir()
        for name in ('kirocrew', 'kiro-cli', 'codex', 'codex-acp', 'opencode'):
            (self.s.tools / 'bin' / name).touch()

    def run_mock(self, command, capture=False, check=True, timeout=120, stdin=None):
        command = [str(x) for x in command]
        self.calls.append(command)
        out, code = '', 0
        if command[:2] == ['launchctl', 'print']:
            code = 0 if self.loaded else 1
            out = 'pid = 123\n' if self.loaded else ''
        elif command[:2] == ['launchctl', 'bootstrap']:
            self.loaded = True
        elif command[:2] == ['launchctl', 'bootout']:
            self.loaded = False
        elif command[:2] == ['kirocrew', 'token']:
            out = 'http://localhost:5476/?token=PRIVATE_TEST_TOKEN'
        elif command[:3] == ['codex', 'login', 'status'] or command[:2] == ['kiro-cli', 'whoami']:
            code = 0 if self.authenticated else 1
        elif command[:3] == ['colima', '--profile', mac.PROFILE] and command[3] == 'status':
            code = 1
        return subprocess.CompletedProcess(command, code, stdout=out, stderr='')

    def ready(self):
        self.s.config['phase'] = 'Ready'
        mac.save_json(self.s.file, self.s.config)

    def backend_args(self, backend='codex', **values):
        return argparse.Namespace(**dict(dict(backend=backend, status=False, skip_auth=False, open_browser=False), **values))

    def test_config_refuses_project_port_and_tool_changes(self):
        original = self.s.file.read_bytes()
        self.args.port += 1
        with self.assertRaises(ValueError):
            self.s.init(self.args)
        self.assertEqual(self.s.file.read_bytes(), original)
        data = json.loads(original)
        data['project'] = '/other'
        mac.save_json(self.s.file, data)
        with self.assertRaises(ValueError):
            self.s.load()

    def test_paths_and_crew_home_are_private_and_do_not_use_global_credentials(self):
        self.assertEqual(self.s.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.s.file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.s.env['DOCKER_CONTEXT'], mac.CONTEXT)
        self.assertEqual(self.s.env['KIROCREW_HOME'], str(self.s.tools / 'crew'))
        self.assertTrue(self.s.env['PATH'].startswith(str(self.s.tools / 'bin') + ':'))
        self.assertEqual(mac.Settings(self.root, self.s.home).label, self.s.label)

    def test_lock_is_exclusive_and_released_on_error(self):
        path = self.s.state / 'test.lock'
        with mac.lock(path):
            with self.assertRaises(ValueError):
                with mac.lock(path, seconds=0):
                    self.fail('duplicate lock acquired')
        with mac.lock(path, seconds=0):
            pass

    def test_agents_only_never_touches_colima_or_cfd_and_repeat_preserves_backend(self):
        self.args.agents_only = True
        with patch.object(mac, 'install_agents'):
            self.s.setup(self.args)
            self.s.setup(self.args)
        self.assertFalse(any(c[0] in ('colima', 'docker', 'bash') for c in self.calls))
        self.assertEqual(self.s.load()['phase'], 'AgentsReady')
        self.assertEqual(self.calls.count(['kirocrew', 'config', 'set', 'agent.acp_backend', 'kiro']), 1)
        self.assertIn(['kirocrew', 'config', 'set', 'agent.kas_bundle', 'false'], self.calls)

    def test_agents_only_preserves_ready_environment(self):
        self.ready()
        self.args.agents_only = True
        with patch.object(mac, 'install_agents'):
            self.s.setup(self.args)
        self.assertEqual(self.s.load()['phase'], 'Ready')

    def test_full_setup_runs_common_build_and_smoke_and_records_ready(self):
        with patch.object(mac, 'install_agents'), patch.object(self.s, 'plugins'):
            self.s.setup(self.args)
        self.assertIn(['bash', str(self.root / 'scripts/build-image.sh')], self.calls)
        self.assertIn(['bash', str(self.root / 'scripts/smoke-test.sh')], self.calls)
        self.assertEqual(self.s.load()['phase'], 'Ready')

    def test_setup_failure_preserves_state_and_records_failed_step(self):
        def fail(command, **kwargs):
            if str(command[-1]).endswith('build-image.sh'):
                raise subprocess.CalledProcessError(42, ['bash'])
            return self.run_mock(command, **kwargs)
        self.s.run = fail
        with patch.object(mac, 'install_agents'), patch.object(self.s, 'plugins'), self.assertRaises(subprocess.CalledProcessError):
            self.s.setup(self.args)
        self.assertEqual((self.s.state / 'failed-step').read_text().strip(), 'cfd-build')
        self.assertEqual(self.s.load()['phase'], 'AgentsReady')
        self.assertFalse(any(c[-1].endswith('smoke-test.sh') for c in self.calls))

    def test_colima_refuses_existing_unmanaged_profile(self):
        profile = self.s.home / '.colima' / mac.PROFILE
        profile.mkdir(parents=True)
        with self.assertRaises(ValueError):
            self.s.colima()
        self.assertEqual(self.calls, [])
        self.assertFalse(self.s.load()['vmOwned'])

    def test_colima_uses_native_vz_writable_project_without_changing_global_context(self):
        self.s.colima()
        call = next(c for c in self.calls if 'start' in c)
        self.assertIn('--activate=false', call)
        self.assertIn('aarch64', call)
        self.assertIn('vz', call)
        self.assertIn('virtiofs', call)
        self.assertEqual(call[-1], str(self.root) + ':w')
        self.assertTrue(self.s.load()['vmOwned'])
        self.assertFalse(any('use' in c for c in self.calls))

    def test_backend_status_does_not_select_or_authenticate(self):
        self.assertEqual(self.s.backend(self.backend_args(status=True)), 3)
        self.assertEqual(self.s.backend(self.backend_args('opencode', status=True)), 4)
        self.assertFalse(any('config' in c or '--device-auth' in c for c in self.calls))
        self.assertFalse((self.s.state / 'backend').exists())

    def test_codex_signed_in_does_not_call_kiro_or_login(self):
        self.authenticated = True
        self.assertEqual(self.s.backend(self.backend_args()), 0)
        self.assertIn(['kirocrew', 'config', 'set', 'agent.acp_backend', 'codex'], self.calls)
        self.assertFalse(any(c[0] == 'kiro-cli' or '--device-auth' in c for c in self.calls))

    def test_missing_adapter_and_noninteractive_auth_never_change_backend(self):
        (self.s.tools / 'bin/codex-acp').unlink()
        with self.assertRaises(ValueError):
            self.s.backend(self.backend_args())
        (self.s.tools / 'bin/codex-acp').touch()
        with patch.object(sys.stdin, 'isatty', return_value=False), self.assertRaises(ValueError):
            self.s.backend(self.backend_args())
        self.assertFalse((self.s.state / 'backend').exists())

    def test_opencode_skip_auth_and_invalid_skip_auth(self):
        self.assertEqual(self.s.backend(self.backend_args('opencode', skip_auth=True)), 0)
        self.assertFalse(any(c[0] == 'opencode' for c in self.calls))
        with self.assertRaises(ValueError):
            self.s.backend(self.backend_args('kiro', skip_auth=True))

    def test_plist_uses_exact_argv_private_log_and_no_login_autostart(self):
        path = self.s.plist()
        d = plistlib.loads(path.read_bytes())
        self.assertEqual(d['WorkingDirectory'], str(self.root))
        self.assertEqual(d['EnvironmentVariables']['DOCKER_CONTEXT'], mac.CONTEXT)
        self.assertEqual(d['ProgramArguments'], [str(self.s.tools / 'bin/kirocrew'), 'gateway', '--no-open', '--no-tunnel', '--port', '5476'])
        self.assertEqual(d['Umask'], 0o077)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('LaunchAgents', str(path))
        self.assertNotIn('PRIVATE_TEST_TOKEN', path.read_text())

    def test_start_reuses_service_and_opens_validated_token_url(self):
        self.ready()
        self.loaded = True
        with patch.object(self.s, 'colima'), patch.object(self.s, 'healthy', return_value=True), redirect_stdout(io.StringIO()):
            self.assertEqual(self.s.start(argparse.Namespace(status=False, open_browser=True)), 0)
        self.assertFalse(any('bootstrap' in c for c in self.calls))
        self.assertIn(['/usr/bin/open', 'http://localhost:5476/?token=PRIVATE_TEST_TOKEN'], self.calls)

    def test_start_status_never_starts_colima_or_launchd(self):
        self.ready()
        with patch.object(self.s, 'colima') as vm:
            self.assertEqual(self.s.start(argparse.Namespace(status=True, open_browser=False)), 3)
            vm.assert_not_called()
        self.assertFalse(any('bootstrap' in c for c in self.calls))

    def test_start_detects_busy_port_and_does_not_bootstrap(self):
        self.ready()
        with patch.object(self.s, 'colima'), patch.object(mac.socket, 'socket') as socket:
            socket.return_value.__enter__.return_value.bind.side_effect = OSError('busy')
            with self.assertRaisesRegex(ValueError, 'ポート'):
                self.s.start(argparse.Namespace(status=False, open_browser=False))
        self.assertFalse(any('bootstrap' in c for c in self.calls))

    def test_start_timeout_does_not_leak_token_or_open_browser(self):
        self.ready()
        self.loaded = True
        with patch.object(self.s, 'colima'), patch.object(self.s, 'healthy', return_value=False), patch.object(mac.time, 'sleep'), self.assertRaisesRegex(ValueError, 'タイムアウト'):
            self.s.start(argparse.Namespace(status=False, open_browser=True))
        self.assertFalse(any('token' in c or '/usr/bin/open' in c for c in self.calls))

    def test_stop_only_managed_job_and_is_idempotent(self):
        self.loaded = True
        self.s.stop()
        self.s.stop()
        self.assertEqual(self.calls.count(['launchctl', 'bootout', self.s.target]), 1)
        self.assertFalse(any(c[0] == 'colima' for c in self.calls))

    def test_access_url_rejects_remote_wrong_port_and_userinfo(self):
        for text in ['https://example.com/?token=X', 'http://localhost:5477/?token=X', 'http://user@localhost:5476/', 'http://localhost:BAD/']:
            with self.assertRaises(ValueError):
                mac.access_url(text, 5476)

    def test_download_hash_mismatch_never_promotes_and_cache_is_reused(self):
        output = self.base / 'archive'
        part = self.base / 'archive.part'
        part.write_bytes(b'bad')
        with patch.object(installer.subprocess, 'run'), self.assertRaises(ValueError):
            installer.download('https://example.invalid/archive', '0' * 64, output)
        self.assertFalse(output.exists())
        output.write_bytes(b'valid')
        with patch.object(installer.subprocess, 'run') as run:
            installer.download('https://example.invalid/archive', installer.sha256(output), output)
            run.assert_not_called()

    def test_official_artifacts_match_shared_versions_and_all_hashes_are_fixed(self):
        v = installer.env_file(ROOT / 'setup/config/agents.env')
        m = installer.env_file(ROOT / 'setup/config/macos.env')
        for tool,prefix in [('KIRO', 'KIRO_CLI'), ('OPENCODE', 'OPENCODE'), ('CODEX', 'CODEX'), ('NODE', 'NODE')]:
            self.assertIn(v[prefix + '_VERSION'], m[tool + '_MACOS_URL'])
            self.assertRegex(m[tool + '_MACOS_SHA256'], '^[0-9a-f]{64}$')
        lines = (ROOT / 'containers/cfd-tools/paraview-arm64.lock').read_text().splitlines()
        self.assertIn('@EXPLICIT', lines)
        urls = [s for s in lines if s.startswith('https://')]
        self.assertGreater(len(urls), 100)
        self.assertTrue(all(s.startswith('https://conda.anaconda.org/conda-forge/linux-aarch64/') or s.startswith('https://conda.anaconda.org/conda-forge/noarch/') for s in urls))
        self.assertTrue(all(len(s.rsplit('#', 1)[-1]) == 64 for s in urls))
        self.assertTrue(any('paraview-5.13.3-' in s and '_osmesa.conda#' in s for s in urls))

class MacShellTest(unittest.TestCase):
    def test_invalid_options_fail_before_any_installation(self):
        for arguments in (['--unknown'], ['--port'], ['--port', '1'], ['--memory', '0'],
                          ['--cpu', '1'], ['--disk', '79'], ['--port', '1;touch BAD']):
            with self.subTest(arguments=arguments), tempfile.TemporaryDirectory() as home:
                result = subprocess.run(['bash', str(ROOT / 'setup/macos/setup.sh'), *arguments],
                                        env=dict(os.environ, HOME=home), capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(Path(home).iterdir()))
                self.assertNotIn('Homebrew が必要', result.stderr)

    @unittest.skipIf(os.geteuid() == 0, 'setup requires a non-root user')
    def test_plan_does_not_require_homebrew_or_create_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'home').mkdir()
            for name, text in [('uname', 'case "$1" in -s) echo Darwin ;; -m) echo arm64 ;; esac'),
                               ('sw_vers', 'echo 15.0')]:
                script = root / name
                script.write_text('#!/bin/bash\n' + text + '\n')
                script.chmod(0o755)
            env = dict(os.environ, HOME=str(root / 'home'), PATH=str(root) + ':' + os.environ['PATH'])
            for name in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_CONFIG', 'COLIMA_HOME', 'LIMA_HOME'):
                env.pop(name, None)
            result = subprocess.run(['bash', str(ROOT / 'setup/macos/setup.sh'), '--plan'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('cfd-build', result.stdout)
            self.assertFalse(any((root / 'home').iterdir()))


if __name__ == '__main__':
    unittest.main()
