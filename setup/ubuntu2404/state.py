"""構成検証と原子的な保存。認証情報は扱わない。"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import urlsplit


def write(path, value):
    path = Path(path)
    fd, name = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    temp = Path(name)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, ensure_ascii=False, indent=2)
            f.write('\n')
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def config(project, port):
    project = str(Path(project).resolve())
    if any(c in project for c in '\n\r\0'):
        raise ValueError('配置先に改行は使えません')
    port = int(port)
    if not 1024 <= port <= 65535:
        raise ValueError('port は 1024..65535')
    unit = 'opencae-crew-' + hashlib.sha256(project.encode()).hexdigest()[:12]
    return dict(project=project, port=port, unit=unit)


def proxy(path):
    path = Path(path)
    if path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
        raise ValueError('Proxy 設定は本人所有・権限600が必要です')
    d = json.loads(path.read_text())
    for key in ('httpProxy', 'httpsProxy'):
        value = d.get(key, '')
        u = urlsplit(value)
        if value and (u.scheme not in ('http', 'https') or not u.hostname or
                      u.username is not None or u.password is not None or
                      any(c in value for c in '\n\r\0')):
            raise ValueError('プレビューは認証なしの HTTP(S) Proxy のみ対応します')
    no = d.get('noProxy', '')
    if not isinstance(no, str) or any(c in no for c in '\n\r\0'):
        raise ValueError('noProxy が不正です')
    return dict(httpProxy=d.get('httpProxy', ''), httpsProxy=d.get('httpsProxy', ''),
                noProxy=','.join(dict.fromkeys(['localhost', '127.0.0.1', '::1'] + no.split(','))))


def main(args):
    command, path, *rest = args
    if command == 'init':
        new = config(*rest)
        p = Path(path)
        if p.exists() and json.loads(p.read_text()) != new:
            raise ValueError('既存の構成と異なります。配置先・port を確認してください')
        write(p, new)
    elif command == 'read':
        d = json.loads(Path(path).read_text())
        if d != config(d['project'], d['port']) or not re.fullmatch(r'opencae-crew-[0-9a-f]{12}', d['unit']):
            raise ValueError('構成が不正です')
        print(d['project'], d['port'], d['unit'], sep='\n')
    elif command == 'proxy-copy':
        write(path, proxy(rest[0]))
    elif command == 'proxy-read':
        d = proxy(path)
        print(d['httpProxy'], d['httpsProxy'], d['noProxy'], sep='\n')
    else:
        raise ValueError('未対応の操作')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, KeyError, OSError, TypeError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
