"""macOS 用の固定バイナリ導入。ホストの既存 CLI と分離して配置する。"""
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


def env_file(path):
    # 値をコードとして実行しない。共有 env は単純な KEY=VALUE のみ。
    values = {}
    for line in Path(path).read_text(encoding='utf-8-sig').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        key, value = line.split('=', 1)
        if not re.fullmatch('[A-Z][A-Z0-9_]*', key) or any(c in value for c in '\r\n\0'):
            raise ValueError('配布設定が不正です')
        values[key] = value
    return values


def sha256(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def download(url, digest, destination):
    destination = Path(destination)
    if not url.startswith('https://') or not re.fullmatch('[0-9a-f]{64}', digest):
        raise ValueError('配布設定が不正です')
    if destination.exists() and sha256(destination) == digest:
        return destination
    part = destination.with_name(destination.name + '.part')
    subprocess.run(['curl', '--fail', '--location', '--show-error', '--retry', '3',
                    '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '30',
                    '--max-time', '1200', url, '-o', str(part)], check=True)
    if sha256(part) != digest:
        raise ValueError('取得ファイルの SHA256 が一致しません: ' + destination.name)
    part.replace(destination)
    return destination


def has_version(binary, version, env):
    if not Path(binary).exists():
        return False
    out = subprocess.run([str(binary), '--version'], env=env, capture_output=True,
                         text=True, timeout=30, check=True).stdout
    if not re.search(r'(?<![0-9.])' + re.escape(version) + r'(?![0-9.])', out):
        raise ValueError(str(binary) + ' の版が異なります。管理領域を自動で上書きしません。')
    return True


def install_agents(settings):
    versions = env_file(settings.root / 'setup/config/agents.env')
    artifacts = env_file(settings.root / 'setup/config/macos.env')
    tools, cache, env = settings.tools, settings.state / 'downloads', settings.env
    cache.mkdir(exist_ok=True)
    (tools / 'bin').mkdir(parents=True, exist_ok=True)

    def fetch(prefix, filename):
        return download(artifacts[prefix + '_MACOS_URL'], artifacts[prefix + '_MACOS_SHA256'], cache / filename)

    kiro = tools / 'bin/kiro-cli'
    if not has_version(kiro, versions['KIRO_CLI_VERSION'], env):
        image = fetch('KIRO', 'kiro-' + versions['KIRO_CLI_VERSION'] + '.dmg')
        app = tools / 'apps/Kiro CLI.app'
        if app.exists():
            # 前回コピー完了後、ランチャー作成前に中断した場合だけ再利用。
            has_version(app / 'Contents/MacOS/kiro-cli', versions['KIRO_CLI_VERSION'], env)
        else:
            app.parent.mkdir(exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='opencae-dmg-') as mount:
                subprocess.run(['hdiutil', 'attach', str(image), '-nobrowse', '-readonly',
                                '-owners', 'off', '-mountpoint', mount], check=True)
                try:
                    source = Path(mount) / 'Kiro CLI.app'
                    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
                    subprocess.run(['ditto', str(source), str(app)], check=True)
                finally:
                    subprocess.run(['hdiutil', 'detach', mount], check=True)
        kiro.write_text('#!/bin/bash\nexec ' + shlex.quote(str(app / 'Contents/MacOS/kiro-cli')) + ' "$@"\n')
        kiro.chmod(0o755)
        has_version(kiro, versions['KIRO_CLI_VERSION'], env)

    for tool, prefix, member, suffix in (
            ('opencode', 'OPENCODE', 'opencode', '.zip'),
            ('codex', 'CODEX', 'codex-aarch64-apple-darwin', '.tar.gz')):
        binary = tools / 'bin' / tool
        if has_version(binary, versions[prefix + '_VERSION'], env):
            continue
        archive = fetch(prefix, tool + '-' + versions[prefix + '_VERSION'] + suffix)
        # 期待する単一バイナリだけ取り出す。アーカイブ内パスを出力先に使用しない。
        if suffix == '.zip':
            with zipfile.ZipFile(archive) as z, z.open(member) as src, binary.open('wb') as dst:
                shutil.copyfileobj(src, dst)
        else:
            with tarfile.open(archive) as t:
                info = t.getmember(member)
                if not info.isfile():
                    raise ValueError('CLI 配布物が通常ファイルではありません')
                with t.extractfile(info) as src, binary.open('wb') as dst:
                    shutil.copyfileobj(src, dst)
        binary.chmod(0o755)
        has_version(binary, versions[prefix + '_VERSION'], env)

    node_root = tools / ('node-' + versions['NODE_VERSION'])
    node = node_root / 'bin/node'
    if not has_version(node, versions['NODE_VERSION'], env):
        archive = fetch('NODE', 'node-' + versions['NODE_VERSION'] + '.tar.gz')
        with tempfile.TemporaryDirectory(dir=tools, prefix='node-extract-') as staging:
            with tarfile.open(archive) as t:
                t.extractall(staging, filter='data')
            (Path(staging) / ('node-v' + versions['NODE_VERSION'] + '-darwin-arm64')).rename(node_root)
        has_version(node, versions['NODE_VERSION'], env)
    adapter = tools / 'codex-acp'
    lock = settings.root / 'setup/config/codex-acp/package-lock.json'
    digest = sha256(lock)
    adapter.mkdir(exist_ok=True)
    marker = adapter / 'lock.sha256'
    entry = adapter / 'node_modules/@agentclientprotocol/codex-acp/dist/index.js'
    if not marker.exists() or marker.read_text().strip() != digest or not entry.exists():
        for name in ('package.json', 'package-lock.json'):
            shutil.copyfile(lock.parent / name, adapter / name)
        subprocess.run([str(node), str(node_root / 'lib/node_modules/npm/bin/npm-cli.js'),
                        'ci', '--prefix', str(adapter), '--ignore-scripts', '--no-audit', '--no-fund'],
                       env=dict(env, PATH=str(node.parent) + ':' + env['PATH']), check=True)
        if not entry.exists():
            raise ValueError('Codex ACP の導入結果を確認できません')
        marker.write_text(digest + '\n')
    (tools / 'bin/codex-acp').write_text('#!/bin/bash\nexec ' + shlex.quote(str(node)) + ' ' + shlex.quote(str(entry)) + ' "$@"\n')
    (tools / 'bin/codex-acp').chmod(0o755)

    if not has_version(tools / 'bin/kirocrew', versions['KIRO_CREW_VERSION'], env):
        installer = download(versions['KIRO_CREW_INSTALLER_URL'], versions['KIRO_CREW_INSTALLER_SHA256'], cache / 'crew-install.sh')
        private = dict(env, PIPX_HOME=str(tools / 'pipx'), PIPX_BIN_DIR=str(tools / 'bin'),
                       PIPX_MAN_DIR=str(tools / 'man'), KIROCREW_ALLOW_SOURCE_BUILDS='0')
        subprocess.run(['sh', str(installer), '--version', versions['KIRO_CREW_VERSION'],
                        '--system-python', '--no-kas'], env=private, check=True)
        has_version(tools / 'bin/kirocrew', versions['KIRO_CREW_VERSION'], env)
