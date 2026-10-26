"""認証なし Proxy プレビュー。systemd と Docker build 用設定を生成する。"""
import json
from pathlib import Path
import sys
from state import proxy, write

d = proxy(sys.argv[1])
# systemd の Environment は shell ではない。% の specifier 展開も抑止する。
values = {'HTTP_PROXY': d['httpProxy'], 'HTTPS_PROXY': d['httpsProxy'], 'NO_PROXY': d['noProxy']}
Path(sys.argv[2]).write_text('[Service]\n' + ''.join(
    'Environment=' + json.dumps(k + '=' + v.replace('%', '%%')) + '\n' for k, v in values.items()))
path = Path.home() / '.docker/config.json'
path.parent.mkdir(mode=0o700, exist_ok=True)
config = json.loads(path.read_text()) if path.exists() else {}
config.setdefault('proxies', {})['unix:///var/run/docker.sock'] = d
write(path, config)
