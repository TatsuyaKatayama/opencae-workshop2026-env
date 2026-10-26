"""ホストを変更せず、セットアップと実行入口の失敗・権限境界を検証する。"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'setup/ubuntu2404'
spec = importlib.util.spec_from_file_location('setup_state', SCRIPTS / 'state.py')
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class StateTest(unittest.TestCase):
    def test_port_bounds_and_newline_rejected(self):
        for port in (0, 1023, 65536, 'abc'):
            with self.assertRaises(ValueError):
                state.config('/home/user/project', port)
        with self.assertRaises(ValueError):
            state.config('/home/user/line\nbreak', 5476)

    def test_roundtrip_conflict_and_literal_path(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'config.json'
            project = str(Path(d) / '日本語 $(touch bad)')
            state.main(['init', str(path), project, '5476'])
            original = path.read_bytes()
            state.main(['init', str(path), project, '5476'])
            self.assertEqual(path.read_bytes(), original)
            with self.assertRaises(ValueError):
                state.main(['init', str(path), project, '5477'])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_proxy_rejects_credentials_permissions_and_injection(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'proxy.json'
            p.write_text(json.dumps({'httpProxy': 'http://host:8080'}))
            p.chmod(0o644)
            with self.assertRaises(ValueError):
                state.proxy(p)
            p.chmod(0o600)
            self.assertIn('localhost', state.proxy(p)['noProxy'])
            for url in ('http://user:secret@host:80', 'http://host\nEnvironment=EVIL', 'file:///tmp/proxy'):
                p.write_text(json.dumps({'httpsProxy': url}))
                with self.assertRaises(ValueError):
                    state.proxy(p)


class ShellTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / '.local/bin'
        self.bin.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        MOCK_HOME=str(self.home), MOCK_ARCH='aarch64', MOCK_AUTH='0')
        for key in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY',
                    'http_proxy', 'https_proxy', 'no_proxy'):
            self.env.pop(key, None)
        self.state = self.home / '.local/state/opencae-workshop2026'
        self.state.mkdir(parents=True)
        state.main(['init', str(self.state / 'crew.json'), str(ROOT), '5476'])
        shim = '''#!/usr/bin/python3
import json, os, pathlib, sys
h=pathlib.Path(os.environ['MOCK_HOME']); name=pathlib.Path(sys.argv[0]).name; a=sys.argv[1:]
with (h/'calls').open('a') as f: f.write(json.dumps([name,*a])+'\\n')
if name=='uname': print(os.environ['MOCK_ARCH'])
elif name=='ps': print('systemd')
elif name=='systemctl':
    if 'is-active' in a: sys.exit(0 if (h/'active').exists() else 3)
    if 'stop' in a:
        if os.environ.get('MOCK_STOP_FAIL'): sys.exit(1)
        (h/'active').unlink(missing_ok=True)
elif name=='systemd-run': (h/'active').touch()
elif name=='kiro-cli':
    if a==['--version']: print('kiro-cli 2.34.0')
    elif 'whoami' in a: sys.exit(int(os.environ['MOCK_AUTH']))
elif name=='kirocrew':
    if a==['--version']: print('kirocrew 0.9.0')
    elif a==['token']: print(os.environ.get('MOCK_URL','http://localhost:5476/?token=private-test-value'))
elif name=='opencode': print('1.19.4')
elif name=='codex': print('codex-cli 0.164.0')
elif name=='curl':
    if '-o' in a and a[a.index('-o')+1].endswith('.part'):
        pathlib.Path(a[a.index('-o')+1]).write_text('tampered')
    sys.exit(int(os.environ.get('MOCK_CURL_EXIT','0')))
elif name=='docker':
    if a[0]=='context': print('unix:///var/run/docker.sock')
    elif a[0]=='info': print('Ubuntu|linux|'+os.environ['MOCK_ARCH'])
elif name=='sudo':
    if a==['-v']: sys.exit(0)
    if 'bash' in a:
        script=a[a.index('bash')+1]
        if script.endswith(os.environ.get('MOCK_FAIL_SCRIPT','NEVER')): sys.exit(23)
elif name=='dpkg-query': sys.exit(1)
elif name=='tee': sys.stdin.read()
elif name=='python3':
    if a==['-','5476']: sys.exit(int(os.environ.get('MOCK_PORT_BUSY','0')))
    os.execv('/usr/bin/python3',['python3',*a])
elif name=='download-shim': sys.exit(0)
'''
        for name in ('uname', 'ps', 'systemctl', 'systemd-run', 'kiro-cli', 'kirocrew',
                     'opencode', 'codex', 'curl', 'docker', 'sudo', 'dpkg-query', 'tee', 'python3'):
            p = self.bin / name
            p.write_text(shim)
            p.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run(['bash', str(SCRIPTS / name), *args], env=self.env,
                              text=True, capture_output=True, timeout=15)

    def calls(self):
        p = self.home / 'calls'
        return [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []

    def test_plan_and_invalid_inputs_never_sudo_or_download(self):
        p = self.run_script('setup.sh', '--plan')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('arm64', p.stdout)
        for args in (('--port', '65536'), ('--port', '2;touch BAD'), ('--proxy-config', '/tmp/x'), ('--unknown',)):
            self.assertNotEqual(self.run_script('setup.sh', *args).returncode, 0)
        self.assertFalse(any(c[0] in ('sudo', 'curl') for c in self.calls()))

    def test_unsupported_architecture(self):
        self.env['MOCK_ARCH'] = 'riscv64'
        p = self.run_script('setup.sh', '--plan')
        self.assertNotEqual(p.returncode, 0)
        self.assertFalse(any(c[0] == 'sudo' for c in self.calls()))

    def test_native_artifact_selection_on_both_architectures(self):
        for machine, arch, cpu, code_name in (
            ('aarch64', 'arm64', 'aarch64', 'opencode-linux-arm64.tar.gz'),
            ('arm64', 'arm64', 'aarch64', 'opencode-linux-arm64.tar.gz'),
            ('x86_64', 'amd64', 'x86_64', 'opencode-linux-x64-baseline.tar.gz'),
            ('amd64', 'amd64', 'x86_64', 'opencode-linux-x64-baseline.tar.gz'),
        ):
            with self.subTest(machine=machine):
                self.env['MOCK_ARCH'] = machine
                command = '''source "$1/lib.sh"
platform
source "$SETUP_ROOT/setup/config/agents.env"
printf '%s\\n' "$ARCH"
for tool in KIRO_CLI OPENCODE CODEX; do
    select_artifact "$tool"
    printf '%s\\n' "$ARTIFACT_URL" "$ARTIFACT_SHA256"
done
archive_binary codex
archive_binary opencode
'''
                p = subprocess.run(['bash', '-euc', command, 'test', str(SCRIPTS)],
                                   env=self.env, capture_output=True, text=True)
                self.assertEqual(p.returncode, 0, p.stderr)
                lines = p.stdout.splitlines()
                self.assertEqual(lines[0], arch)
                self.assertTrue(lines[1].endswith(f'/2.34.0/kirocli-{cpu}-linux.zip'))
                self.assertTrue(lines[3].endswith('/v1.19.4/'+code_name))
                self.assertTrue(lines[5].endswith(f'/rust-v0.164.0/codex-{cpu}-unknown-linux-musl.tar.gz'))
                for digest in lines[2:7:2]:
                    self.assertRegex(digest, r'^[a-f0-9]{64}$')
                self.assertEqual(lines[7:], [f'codex-{cpu}-unknown-linux-musl', 'opencode'])

    def test_amd64_plan_and_existing_service(self):
        self.env['MOCK_ARCH'] = 'x86_64'
        p = self.run_script('setup.sh', '--plan')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('CPU=amd64', p.stdout)
        (self.home/'active').touch()
        p = self.run_script('crew-start.sh')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse(any(c[0] == 'systemd-run' for c in self.calls()))

    def test_logged_in_does_not_login_and_missing_login_status(self):
        self.assertEqual(self.run_script('kiro-login.sh').returncode, 0)
        self.env['MOCK_AUTH'] = '1'
        self.assertEqual(self.run_script('kiro-login.sh', '--status').returncode, 3)
        self.assertFalse(any(c[:2] == ['kiro-cli', 'login'] for c in self.calls()))

    def test_start_reuses_service_and_stdout_only_contains_url(self):
        (self.home / 'active').touch()
        p = self.run_script('crew-start.sh')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout.strip(), 'http://localhost:5476/?token=private-test-value')
        self.assertNotIn('private-test-value', p.stderr)
        self.assertFalse(any(c[0] == 'systemd-run' for c in self.calls()))

    def test_unauthenticated_start_does_not_spawn(self):
        self.env['MOCK_AUTH'] = '1'
        p = self.run_script('crew-start.sh')
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('Kiro CLI Login', p.stderr)
        self.assertFalse(any(c[0] == 'systemd-run' for c in self.calls()))

    def test_new_start_and_port_conflict(self):
        self.env['MOCK_PORT_BUSY'] = '1'
        self.assertNotEqual(self.run_script('crew-start.sh').returncode, 0)
        self.assertFalse(any(c[0] == 'systemd-run' for c in self.calls()))
        self.env['MOCK_PORT_BUSY'] = '0'
        p = self.run_script('crew-start.sh')
        self.assertEqual(p.returncode, 0, p.stderr)
        starts = [c for c in self.calls() if c[0] == 'systemd-run']
        self.assertEqual(len(starts), 1)
        self.assertIn('--no-tunnel', starts[0])
        self.assertEqual((self.state/'logs/crew.log').stat().st_mode & 0o777, 0o600)

    def test_does_not_output_remote_or_wrong_port_access_url(self):
        (self.home/'active').touch()
        for url in ('https://example.com/?token=secret', 'http://localhost:9999/?token=secret'):
            self.env['MOCK_URL'] = url
            p = self.run_script('crew-start.sh')
            self.assertNotEqual(p.returncode, 0)
            self.assertNotIn('token=secret', p.stdout + p.stderr)

    def test_state_mismatch_aborts_before_install(self):
        p = self.run_script('setup.sh', '--port', '5477')
        self.assertNotEqual(p.returncode, 0)
        self.assertFalse(any(c[0] == 'sudo' and 'apt-get' in c for c in self.calls()))

    def test_download_hash_mismatch_never_promotes_archive(self):
        dest = self.home / 'archive'
        p = subprocess.run(['bash', '-euc',
                            'source "$1"; download "$2" "$3" "$4"',
                            'test', str(SCRIPTS/'lib.sh'), 'https://example.invalid/archive',
                            '0'*64, str(dest)], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('SHA256', p.stderr)
        self.assertFalse(dest.exists())

    def test_zip_build_does_not_require_git_metadata(self):
        import shutil
        project = self.home / 'ZIP 日本語 project'
        shutil.copytree(ROOT/'scripts', project/'scripts')
        shutil.copytree(ROOT/'compose', project/'compose')
        shutil.copy2(ROOT/'versions.env', project/'versions.env')
        (project/'containers/cfd-tools').mkdir(parents=True)
        shutil.copy2(ROOT/'containers/cfd-tools/requirements.lock', project/'containers/cfd-tools/requirements.lock')
        p = subprocess.run(['bash', str(project/'scripts/build-image.sh')],
                           env=self.env, text=True, capture_output=True, timeout=15)
        self.assertEqual(p.returncode, 0, p.stderr)
        records = list((project/'work').glob('build-*'))
        self.assertEqual(len(records), 1)
        self.assertEqual((records[0]/'git-status.txt').read_text().strip(), 'unavailable-zip')

    def test_stop_targets_only_configured_unit_and_is_idempotent(self):
        (self.home / 'active').touch()
        self.assertEqual(self.run_script('crew-stop.sh').returncode, 0)
        self.assertEqual(self.run_script('crew-stop.sh').returncode, 0)
        stops = [c for c in self.calls() if c[0] == 'systemctl' and 'stop' in c]
        self.assertEqual(stops, [['systemctl', '--user', 'stop', state.config(ROOT, 5476)['unit'] + '.service']])
        self.assertFalse(any(c[0] in ('sudo', 'docker') for c in self.calls()))

    def test_stop_failure_propagates(self):
        (self.home / 'active').touch()
        self.env['MOCK_STOP_FAIL'] = '1'
        self.assertNotEqual(self.run_script('crew-stop.sh').returncode, 0)
        self.assertTrue((self.home / 'active').exists())

    def test_build_failure_records_step_and_never_runs_smoke(self):
        # download は既存のハッシュ検証済みキーを再利用させる。
        key = b'test-key'
        download = self.state / 'downloads'
        download.mkdir()
        (download / 'docker.asc').write_bytes(key)
        # 共有設定を書き換えず、sha256sum の検証だけを模擬する。
        p = self.bin / 'sha256sum'
        p.write_text('#!/bin/sh\ncat >/dev/null\nexit 0\n')
        p.chmod(0o755)
        self.env['MOCK_FAIL_SCRIPT'] = 'build-image.sh'
        result = self.run_script('setup.sh')
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual((self.state / 'failed-step').read_text().strip(), 'cfd-build')
        self.assertFalse(any('smoke-test.sh' in ' '.join(c) for c in self.calls()))


if __name__ == '__main__':
    unittest.main()
