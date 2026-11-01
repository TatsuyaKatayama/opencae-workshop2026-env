"""共有 .env の改行を WSL 側で正規化する。Windows 側の取得元は変更しない。"""
from pathlib import Path
import sys

CONFIG_FILES = ('versions.env', 'setup/config/agents.env', 'setup/config/docker.env')


def normalized(path):
    text = Path(path).read_bytes().decode('utf-8-sig').replace('\r\n', '\n')
    if '\r' in text or '\x00' in text:
        raise ValueError(f'Invalid shared configuration encoding: {Path(path).name}')
    return text.encode('utf-8')


def normalize(root):
    root = Path(root)
    # 全件の読み込みに成功してから書き換える。対象は既知の共有設定だけ。
    files = [(root / name, normalized(root / name)) for name in CONFIG_FILES]
    for path, data in files:
        if path.read_bytes() != data:
            path.write_bytes(data)


def main(args):
    if len(args) == 2 and args[0] == 'normalize':
        normalize(args[1])
    elif len(args) == 3 and args[0] == 'compare':
        return int(normalized(args[1]) != normalized(args[2]))
    else:
        raise ValueError('Usage: config_files.py normalize ROOT | compare SOURCE TARGET')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, UnicodeError, ValueError) as error:
        sys.exit(str(error))
