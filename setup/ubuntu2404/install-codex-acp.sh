#!/usr/bin/env bash
# setup.sh から呼び出す。Node と ACP 依存はユーザー専用領域へ配置する。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
platform
init_state
source "$SETUP_ROOT/setup/config/agents.env"
runtime="$HOME/.local/share/opencae/node/$NODE_VERSION-$ARCH"
adapter="$HOME/.local/share/opencae/codex-acp"
node_cpu=x64; [[ "$ARCH" != arm64 ]] || node_cpu=arm64
sha_var="NODE_${ARCH_KEY}_SHA256"
archive="$STATE/downloads/node-$NODE_VERSION-$ARCH.tar.xz"
mkdir -p "$STATE/downloads" "$HOME/.local/bin"
if [[ ! -x "$runtime/bin/node" ]]; then
    download "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$node_cpu.tar.xz" "${!sha_var}" "$archive"
    mkdir -p "$(dirname "$runtime")"
    staging="$(mktemp -d "$(dirname "$runtime")/extract-XXXXXX")"
    trap 'rm -rf -- "$staging"' EXIT
    tar -xJf "$archive" --strip-components=1 --no-same-owner -C "$staging"
    [[ "$("$staging/bin/node" --version)" == "v$NODE_VERSION" ]] || die 'Node.js の版を確認できません。'
    [[ ! -e "$runtime" ]] || die 'Node.js の導入途中の領域があります。内容を確認してください。'
    mv -- "$staging" "$runtime"
fi
[[ "$("$runtime/bin/node" --version)" == "v$NODE_VERSION" ]] || die 'Node.js の版が異なります。'
lock="$SETUP_ROOT/setup/config/codex-acp/package-lock.json"
digest="$(sha256sum "$lock" | cut -d ' ' -f 1)"
if [[ ! -f "$adapter/lock.sha256" || "$(cat "$adapter/lock.sha256")" != "$digest" || ! -f "$adapter/node_modules/@agentclientprotocol/codex-acp/dist/index.js" ]]; then
    mkdir -p "$adapter"
    cp "$SETUP_ROOT/setup/config/codex-acp/"package*.json "$adapter/"
    env PATH="$runtime/bin:$PATH" "$runtime/bin/node" "$runtime/lib/node_modules/npm/bin/npm-cli.js" \
        ci --prefix "$adapter" --ignore-scripts --no-audit --no-fund
    [[ -f "$adapter/node_modules/@agentclientprotocol/codex-acp/dist/index.js" ]] || die 'Codex ACP の導入結果を確認できません。'
    printf '%s\n' "$digest" > "$adapter/lock.sha256"
fi
# PATH 全体の Node を置き換えず、アダプターだけを固定ランタイムで動かす。
python3 - "$runtime" "$adapter" "$HOME/.local/bin/codex-acp" <<'PY'
import pathlib, shlex, sys
runtime, adapter, launcher = sys.argv[1:]
path = pathlib.Path(launcher)
if path.exists() and not path.read_bytes().startswith(b'#!/usr/bin/env bash\n# OpenCAE managed codex-acp\n'):
    sys.exit('ERROR: 管理対象外の codex-acp が存在します。')
path.write_text('#!/usr/bin/env bash\n# OpenCAE managed codex-acp\nexec ' +
                shlex.quote(runtime + '/bin/node') + ' ' +
                shlex.quote(adapter + '/node_modules/@agentclientprotocol/codex-acp/dist/index.js') + ' "$@"\n')
path.chmod(0o755)
PY
