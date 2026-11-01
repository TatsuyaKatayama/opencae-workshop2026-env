"""macOS の専用 Colima とユーザー launchd を制御する。認証内容は保存しない。"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

from install import install_agents, sha256

PROFILE = 'opencae-workshop2026'
CONTEXT = 'colima-' + PROFILE


def save_json(path, data):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    temporary.chmod(0o600)
    temporary.replace(path)


@contextmanager
def lock(path, seconds=30):
    with path.open('a') as f:
        until = time.monotonic() + seconds
        while True:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= until:
                    raise ValueError('別のセットアップ・Crew 操作が実行中です') from None
                time.sleep(0.1)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def access_url(text, port):
    for url in re.findall(r'https?://[^\s\x1b]+', text):
        try:
            u = urlsplit(url)
            if (u.scheme == 'http' and u.hostname in ('localhost', '127.0.0.1', '::1')
                    and u.port == port and not u.username and not u.password):
                return url
        except ValueError:
            continue
    raise ValueError('Crew の localhost アクセス URL を取得できません')


class Settings:
    def __init__(self, root=None, home=None):
        self.root = Path(root or Path(__file__).resolve().parents[2]).resolve()
        self.home = Path(home or Path.home()).resolve()
        self.state = self.home / '.local/state/opencae-workshop2026-macos'
        self.tools = self.home / '.local/share/opencae/macos'
        self.file = self.state / 'environment.json'
        self.env = dict(os.environ, HOME=str(self.home),
                        KIROCREW_HOME=str(self.tools / 'crew'), DOCKER_CONTEXT=CONTEXT)
        self.env.pop('DOCKER_HOST', None)
        self.env['PATH'] = ':'.join([str(self.tools / 'bin'), '/opt/homebrew/opt/python@3.12/libexec/bin',
                                    '/opt/homebrew/bin', '/opt/homebrew/sbin', os.environ.get('PATH', '')])
        self.config = None

    def private_dirs(self):
        for path in (self.state, self.tools):
            if path.is_symlink():
                raise ValueError('管理フォルダーにシンボリックリンクは使用できません')
            path.mkdir(parents=True, exist_ok=True, mode=0o700)
            path.chmod(0o700)

    def fingerprint(self):
        return hashlib.sha256(b''.join((self.root / p).read_bytes() for p in (
            'setup/config/agents.env', 'setup/config/macos.env', 'setup/config/codex-acp/package-lock.json'))).hexdigest()

    def init(self, args):
        identity = dict(schema=1, project=str(self.root), port=args.port, profile=PROFILE,
                        cpu=args.cpu, memory=args.memory, disk=args.disk, tools=self.fingerprint())
        if self.file.exists():
            self.load()
            if any(self.config.get(k) != v for k, v in identity.items()):
                raise ValueError('既存の構築設定と異なります。配置先・版・オプションを確認してください')
        else:
            self.config = dict(identity, phase='Initializing', vmOwned=False)
            save_json(self.file, self.config)

    def load(self):
        if not self.file.exists():
            raise ValueError('先に setup/macos/setup.sh を実行してください')
        d = json.loads(self.file.read_text())
        if (d.get('schema') != 1 or d.get('project') != str(self.root) or d.get('profile') != PROFILE
                or type(d.get('port')) is not int or not 1024 <= d['port'] <= 65535
                or type(d.get('vmOwned')) is not bool):
            raise ValueError('環境設定の配置先・profile・port が不正です')
        self.config = d
        return d

    def run(self, command, capture=False, check=True, timeout=120, stdin=None):
        return subprocess.run([str(x) for x in command], cwd=self.root, env=self.env, check=check,
                              capture_output=capture, text=True, timeout=timeout, stdin=stdin)

    @property
    def label(self):
        return 'org.opencae.crew.' + hashlib.sha256(str(self.root).encode()).hexdigest()[:12]

    @property
    def target(self):
        return f'gui/{os.getuid()}/{self.label}'

    def service_loaded(self):
        return self.run(['launchctl', 'print', self.target], capture=True, check=False).returncode == 0

    def service_running(self):
        result = self.run(['launchctl', 'print', self.target], capture=True, check=False)
        return result.returncode == 0 and bool(re.search(r'^\s*pid = [1-9][0-9]*\s*$', result.stdout, re.M))

    def colima(self):
        self.load()
        if not self.config['vmOwned']:
            profile = self.home / '.colima' / PROFILE
            if profile.exists() or profile.is_symlink():
                raise ValueError('同名の既存 Colima があります。別用途の VM を引き継ぎません')
            # 起動途中の失敗でも、本セットアップで作成した profile だけ再開可能にする。
            self.config['vmOwned'] = True
            save_json(self.file, self.config)
        status = self.run(['colima', '--profile', PROFILE, 'status'], capture=True, check=False)
        if status.returncode != 0:
            self.run(['colima', '--profile', PROFILE, 'start', '--activate=false', '--arch', 'aarch64',
                      '--vm-type', 'vz', '--mount-type', 'virtiofs', '--runtime', 'docker',
                      '--cpus', self.config['cpu'], '--memory', self.config['memory'], '--disk', self.config['disk'],
                      '--mount', str(self.root) + ':w'], timeout=1200)
        # Docker Desktop、別 context、別 CPU ではここで止める。
        self.run(['bash', '-c', 'source "$1"; require_engine', 'opencae', self.root / 'scripts/lib/common.sh'])

    def plugins(self):
        directory = self.home / '.docker/cli-plugins'
        directory.mkdir(parents=True, exist_ok=True)
        for name in ('docker-compose', 'docker-buildx'):
            target = directory / name
            # 既存プラグインは上書きしない。require_engine で実際の利用可否を確認する。
            if not target.exists() and not target.is_symlink():
                target.symlink_to('/opt/homebrew/opt/' + name + '/bin/' + name)

    def setup(self, args):
        self.private_dirs()
        with lock(self.state / 'setup.lock'), lock(self.state / 'crew.lock'):
            self.init(args)
            if self.service_loaded():
                raise ValueError('3_StopCrew.command で停止してからセットアップを再開してください')
            step = 'agents'
            try:
                install_agents(self)
                step = 'crew-config'
                if self.config['phase'] == 'Initializing':
                    self.run(['kirocrew', 'setup', '--agent-only'], timeout=300, stdin=subprocess.DEVNULL)
                    self.run(['kirocrew', 'config', 'set', 'dashboard.url', f"http://localhost:{self.config['port']}"])
                    self.run(['kirocrew', 'config', 'set', 'agent.acp_backend', 'kiro'])
                self.run(['kirocrew', 'config', 'set', 'agent.kas_bundle', 'false'])
                if self.config['phase'] != 'Ready':
                    self.config['phase'] = 'AgentsReady'
                save_json(self.file, self.config)
                if not args.agents_only:
                    step = 'colima'
                    self.plugins()
                    self.colima()
                    step = 'cfd-build'
                    self.run(['bash', self.root / 'scripts/build-image.sh'], timeout=21600)
                    step = 'cfd-check'
                    self.run(['bash', self.root / 'scripts/smoke-test.sh'], timeout=1800)
                    self.config['phase'] = 'Ready'
                    save_json(self.file, self.config)
                self.record_versions()
                (self.state / 'failed-step').unlink(missing_ok=True)
            except Exception:
                (self.state / 'failed-step').write_text(step + '\n')
                print(f'セットアップ失敗: {step}。同じコマンドで再開できます。', file=sys.stderr)
                raise
        print('CLI・Crew 導入完了（Docker・CFD 未構築）。' if args.agents_only else 'macOS セットアップ完了。')
        print('1_StartBackend.command → 2_StartCrew.command の順に実行してください。')

    def record_versions(self):
        versions = {}
        for name in ('kiro-cli', 'kirocrew', 'opencode', 'codex'):
            versions[name] = self.run([name, '--version'], capture=True).stdout.strip()
        versions['homebrew'] = self.run(['/opt/homebrew/bin/brew', 'list', '--versions'], capture=True).stdout.strip()
        save_json(self.state / 'installed-versions.json', versions)

    def backend(self, args):
        self.load()
        for name in ('kirocrew', 'kiro-cli' if args.backend == 'kiro' else args.backend):
            if not (self.tools / 'bin' / name).exists():
                raise ValueError(name + ' がありません。setup.sh を確認してください')
        if args.backend == 'codex' and not (self.tools / 'bin/codex-acp').exists():
            raise ValueError('Codex ACP adapter がありません')
        if args.skip_auth and args.backend != 'opencode':
            raise ValueError('--skip-auth は OpenCode 専用です')
        commands = {'kiro': ['kiro-cli', 'whoami'], 'codex': ['codex', 'login', 'status']}

        def authenticated():
            if args.backend == 'opencode':
                return False
            return self.run(commands[args.backend], capture=True, check=False, timeout=30).returncode == 0

        if args.status:
            if args.backend == 'opencode':
                print('OpenCode の提供先・モデルは Crew の画面で確認してください。', file=sys.stderr)
                return 4
            return 0 if authenticated() else 3
        with lock(self.state / 'crew.lock'):
            if not args.skip_auth and not authenticated():
                if not sys.stdin.isatty() or not sys.stdout.isatty():
                    raise ValueError('認証には対話端末が必要です')
                if args.open_browser:
                    self.run([sys.executable, self.root / 'setup/ubuntu2404/login_browser.py', args.backend], timeout=None)
                else:
                    login = {'kiro': ['kiro-cli', 'login', '--use-device-flow'],
                             'codex': ['codex', 'login', '--device-auth'], 'opencode': ['opencode', 'auth', 'login']}
                    self.run(login[args.backend], timeout=None)
                if args.backend != 'opencode' and not authenticated():
                    raise ValueError('認証を確認できません。再実行してください')
            self.run(['kirocrew', 'config', 'set', 'agent.acp_backend', args.backend])
            self.run(['kirocrew', 'config', 'set', 'agent.kas_bundle', 'false'])
            (self.state / 'backend').write_text(args.backend + '\n')
        print(f'バックエンドを {args.backend} に設定しました。2_StartCrew.command を実行してください。')
        print('起動中の場合は 3_StopCrew.command → 2_StartCrew.command で反映します。')
        return 0

    def plist(self):
        log = self.state / 'logs/crew.log'
        log.parent.mkdir(mode=0o700, exist_ok=True)
        log.touch(mode=0o600, exist_ok=True)
        log.chmod(0o600)
        data = dict(Label=self.label,
                    ProgramArguments=[str(self.tools / 'bin/kirocrew'), 'gateway', '--no-open', '--no-tunnel', '--port', str(self.config['port'])],
                    WorkingDirectory=str(self.root), EnvironmentVariables={k: self.env[k] for k in (
                        'HOME', 'PATH', 'KIROCREW_HOME', 'DOCKER_CONTEXT')},
                    RunAtLoad=True, KeepAlive=True, ThrottleInterval=5, ExitTimeOut=45, Umask=0o077,
                    StandardOutPath=str(log), StandardErrorPath=str(log))
        # ~/Library/LaunchAgents に置かず、明示 start 時だけ bootstrap する。
        path = self.state / (self.label + '.plist')
        with path.open('wb') as f:
            plistlib.dump(data, f)
        path.chmod(0o600)
        return path

    def healthy(self):
        # macOS のシステム Proxy を含め、localhost の確認では Proxy を使わない。
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(f"http://127.0.0.1:{self.config['port']}/", timeout=2) as r:
                return r.status == 200
        except (OSError, urllib.error.URLError):
            return False

    def start(self, args):
        self.load()
        if self.config.get('phase') != 'Ready':
            raise ValueError('CFD 構築未完了です。setup.sh を通常モードで完了してください')
        with lock(self.state / 'crew.lock'):
            if args.status:
                return 0 if self.service_running() and self.healthy() else 3
            self.colima()
            if not self.service_loaded():
                with socket.socket() as s:
                    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    try:
                        s.bind(('127.0.0.1', self.config['port']))
                    except OSError:
                        raise ValueError('Crew のポートは別プロセスが使用中です') from None
                self.run(['launchctl', 'bootstrap', f'gui/{os.getuid()}', self.plist()])
            for _ in range(60):
                if self.service_running() and self.healthy():
                    break
                time.sleep(1)
            else:
                raise ValueError('Crew 起動待ちがタイムアウトしました。Stop 後に再試行してください。本人用ログ: ' + str(self.state / 'logs/crew.log'))
            url = access_url(self.run(['kirocrew', 'token'], capture=True).stdout, self.config['port'])
            print(url)
            if args.open_browser:
                # URL をコマンドや AppleScript として評価しない。
                self.run(['/usr/bin/open', url])
        return 0

    def stop(self):
        self.load()
        with lock(self.state / 'crew.lock'):
            if not self.service_loaded():
                print('Crew は停止しています。')
                return 0
            self.run(['launchctl', 'bootout', self.target], timeout=60)
            if self.service_loaded():
                raise ValueError('Crew の停止を確認できません')
        print('Crew を停止しました。Colima と計算コンテナは稼働を継続します。')
        return 0


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    p = commands.add_parser('setup')
    for name, default in [('port', 5476), ('cpu', 2), ('memory', 8), ('disk', 100)]:
        p.add_argument('--' + name, type=int, default=default)
    p.add_argument('--agents-only', action='store_true')
    p = commands.add_parser('backend')
    p.add_argument('--backend', choices=['kiro', 'codex', 'opencode'], required=True)
    for flag in ('status', 'open-browser', 'skip-auth'):
        p.add_argument('--' + flag, action='store_true')
    p = commands.add_parser('start')
    p.add_argument('--status', action='store_true')
    p.add_argument('--open-browser', action='store_true')
    commands.add_parser('stop')
    args = parser.parse_args()
    settings = Settings()
    try:
        if sys.platform != 'darwin' or os.getuid() == 0:
            raise ValueError('通常ユーザーの macOS から実行してください')
        if args.command == 'setup':
            return settings.setup(args)
        settings.load()
        if args.command == 'backend':
            return settings.backend(args)
        if args.command == 'start':
            return settings.start(args)
        return settings.stop()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        # token / 認証 URL を含み得る subprocess の stdout/stderr は再掲しない。
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
