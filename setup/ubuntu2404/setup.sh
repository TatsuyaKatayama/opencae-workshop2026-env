#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

usage() {
    cat <<'EOF'
使用法: setup.sh [--port 5476] [--enable-proxy-preview --proxy-config FILE] [--plan]
Ubuntu 24.04 の通常ユーザーで実行します。sudo が必要です。
既定は全工程（Docker・CLI・Crew 導入、CFD ローカルビルド・確認）。
--plan は環境変更・通信なしで工程を表示します。
EOF
}
port=5476; preview=0; proxy_file=''; plan=0
while (( $# )); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --port) (( $# >= 2 )) || die '--port の値が必要です。'; port="$2"; shift 2 ;;
        --enable-proxy-preview) preview=1; shift ;;
        --proxy-config) (( $# >= 2 )) || die '--proxy-config の値が必要です。'; proxy_file="$2"; shift 2 ;;
        --plan) plan=1; shift ;;
        *) die "未対応の引数: $1" ;;
    esac
done
[[ "$port" =~ ^[0-9]{4,5}$ ]] && (( 10#$port >= 1024 && 10#$port <= 65535 )) || die 'port は 1024..65535 です。'
[[ -z "$proxy_file" || "$preview" == 1 ]] || die 'Proxy は --enable-proxy-preview が必要です。'
[[ "$preview" == 0 || -n "$proxy_file" ]] || die '--proxy-config が必要です。'
platform
source "$SETUP_ROOT/setup/config/agents.env"
source "$SETUP_ROOT/setup/config/docker.env"
if (( plan )); then
    printf 'CPU=%s\nport=%s\n工程: prerequisites docker agents crew-config cfd-build cfd-check\n' "$ARCH" "$port"
    exit 0
fi
[[ "$(ps -p 1 -o comm=)" == systemd ]] || die 'systemd が PID 1 の Ubuntu 24.04 が必要です。'
sudo -v
init_state
exec 9>"$STATE/setup.lock"
flock -n 9 || die '別のセットアップが実行中です。'
mkdir -p "$STATE/downloads" "$STATE/steps"
python3 "$SETUP_ROOT/setup/ubuntu2404/state.py" init "$STATE/crew.json" "$SETUP_ROOT" "$port"
if (( preview )); then
    note 'Proxy はプレビューです。認証付き Proxy・独自 CA は未対応です。'
    python3 "$SETUP_ROOT/setup/ubuntu2404/state.py" proxy-copy "$STATE/proxy.json" "$proxy_file"
fi
load_proxy
step=initializing
trap 'status=$?; printf "%s\n" "$step" > "$STATE/failed-step"; note "セットアップ失敗: $step (exit=$status)。同じコマンドで再開できます。"; exit "$status"' ERR

run_step() {
    step="$1"; shift
    # 関数は条件式で呼ばない。内部コマンドの errexit を有効に保つ。
    note "開始: $step"
    "$@"
    printf '%s\n' "$(date -u +%FT%TZ)" > "$STATE/steps/$step"
    note "完了: $step"
}

prerequisites() {
    sudo --preserve-env=http_proxy,https_proxy,no_proxy,HTTP_PROXY,HTTPS_PROXY,NO_PROXY apt-get update
    sudo --preserve-env=http_proxy,https_proxy,no_proxy,HTTP_PROXY,HTTPS_PROXY,NO_PROXY apt-get install -y ca-certificates curl gnupg unzip python3 python3-venv python3-pip git dbus-user-session uidmap libatomic1
    sudo loginctl enable-linger "$(id -un)"
    sudo systemctl start "user@$(id -u).service"
}

install_docker() {
    # 既存 Engine の削除や別デーモンの上書きはしない。
    for pkg in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            die "競合パッケージ $pkg があります。専用の新規環境を使用してください。"
        fi
    done
    [[ -z "${DOCKER_HOST:-}" && -z "${DOCKER_CONTEXT:-}" ]] || die 'DOCKER_HOST / DOCKER_CONTEXT を解除してください。'
    download https://download.docker.com/linux/ubuntu/gpg "$DOCKER_KEY_SHA256" "$STATE/downloads/docker.asc"
    sudo install -d -m 0755 /etc/apt/keyrings
    sudo install -m 0644 "$STATE/downloads/docker.asc" /etc/apt/keyrings/opencae-docker.asc
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/opencae-docker.asc] https://download.docker.com/linux/ubuntu noble stable\n' "$ARCH" |
        sudo tee /etc/apt/sources.list.d/opencae-docker.list >/dev/null
    sudo --preserve-env=http_proxy,https_proxy,no_proxy,HTTP_PROXY,HTTPS_PROXY,NO_PROXY apt-get update
    sudo --preserve-env=http_proxy,https_proxy,no_proxy,HTTP_PROXY,HTTPS_PROXY,NO_PROXY apt-get install -y \
        "docker-ce=$DOCKER_CE_VERSION" "docker-ce-cli=$DOCKER_CE_CLI_VERSION" \
        "containerd.io=$CONTAINERD_IO_VERSION" "docker-buildx-plugin=$DOCKER_BUILDX_PLUGIN_VERSION" \
        "docker-compose-plugin=$DOCKER_COMPOSE_PLUGIN_VERSION"
    sudo usermod -aG docker "$(id -un)"
    if [[ -f "$STATE/proxy.json" ]]; then
        python3 "$SETUP_ROOT/setup/ubuntu2404/proxy.py" "$STATE/proxy.json" "$STATE/docker-proxy.conf"
        sudo install -d -m 0755 /etc/systemd/system/docker.service.d
        sudo install -m 0600 "$STATE/docker-proxy.conf" /etc/systemd/system/docker.service.d/opencae-proxy.conf
        sudo systemctl daemon-reload
        sudo systemctl restart docker
    fi
    sudo systemctl enable --now docker
    # グループ追加は現在のシェルに反映されない。新しいユーザーセッションで検証する。
    as_user docker info --format '{{.OSType}}/{{.Architecture}}'
    as_user docker compose version
    as_user docker buildx version
}

as_user() {
    sudo --preserve-env=http_proxy,https_proxy,no_proxy,HTTP_PROXY,HTTPS_PROXY,NO_PROXY -u "$(id -un)" -H \
        env PATH="$PATH" "$@"
}

install_binary() {
    local tool="$1" version="$2" prefix="$3" archive dest binary
    if has_version "$tool" "$version"; then return; fi
    command -v "$tool" >/dev/null && die "$tool の別バージョンが存在します。専用の新規環境を使用してください。"
    select_artifact "$prefix"
    archive="$STATE/downloads/$tool-$version-$ARCH.tar.gz"
    download "$ARTIFACT_URL" "$ARTIFACT_SHA256" "$archive"
    dest="$(mktemp -d "$STATE/downloads/extract-XXXXXX")"
    tar -xzf "$archive" -C "$dest" --no-same-owner
    binary="$dest/$(archive_binary "$tool")"
    install -m 0755 "$binary" "$HOME/.local/bin/$tool"
    has_version "$tool" "$version" || die "$tool の版を確認できません。"
}

install_agents() {
    mkdir -p "$HOME/.local/bin"
    if ! has_version kiro-cli "$KIRO_CLI_VERSION"; then
        command -v kiro-cli >/dev/null && die 'Kiro CLI の別バージョンが存在します。'
        local dir
        select_artifact KIRO_CLI
        download "$ARTIFACT_URL" "$ARTIFACT_SHA256" "$STATE/downloads/kiro-$KIRO_CLI_VERSION-$ARCH.zip"
        dir="$(mktemp -d "$STATE/downloads/kiro-XXXXXX")"
        unzip -q "$STATE/downloads/kiro-$KIRO_CLI_VERSION-$ARCH.zip" -d "$dir"
        env -u Q_INSTALL_GLOBAL KIRO_CLI_SKIP_SETUP=1 bash "$dir/kirocli/install.sh"
        has_version kiro-cli "$KIRO_CLI_VERSION" || die 'Kiro CLI の版を確認できません。'
    fi
    install_binary opencode "$OPENCODE_VERSION" OPENCODE
    install_binary codex "$CODEX_VERSION" CODEX
    if ! has_version kirocrew "$KIRO_CREW_VERSION"; then
        command -v kirocrew >/dev/null && die 'Crew の別バージョンが存在します。'
        download "$KIRO_CREW_INSTALLER_URL" "$KIRO_CREW_INSTALLER_SHA256" "$STATE/downloads/crew-install.sh"
        # 署名付きバージョンマニフェストの検証は公式インストーラーが担当する。
        KIROCREW_ALLOW_SOURCE_BUILDS=0 sh "$STATE/downloads/crew-install.sh" --version "$KIRO_CREW_VERSION" --system-python
        has_version kirocrew "$KIRO_CREW_VERSION" || die 'Crew の版を確認できません。'
    fi
}

configure_crew() {
    python3 "$SETUP_ROOT/setup/ubuntu2404/state.py" init "$STATE/crew.json" "$SETUP_ROOT" "$port"
    if [[ ! -f "$STATE/steps/crew-config" ]]; then
        kirocrew setup --agent-only </dev/null
        kirocrew config set dashboard.url "http://localhost:$port"
    fi
    # 新しいログインシェルと非対話 PowerShell 起動の双方で PATH を確保する。
    local line='export PATH="$HOME/.local/bin:$PATH"'
    grep -Fqx "$line" "$HOME/.profile" 2>/dev/null || printf '\n%s\n' "$line" >> "$HOME/.profile"
}

run_step prerequisites prerequisites
run_step docker install_docker
run_step agents install_agents
run_step crew-config configure_crew
step=cfd-build
# 前回成功していても、変更された Dockerfile はビルドキャッシュで再評価する。
run_step cfd-build as_user bash "$SETUP_ROOT/scripts/build-image.sh"
run_step cfd-check as_user bash "$SETUP_ROOT/scripts/smoke-test.sh"
rm -f "$STATE/failed-step"
note 'セットアップ完了。認証は kiro-login.sh、起動は crew-start.sh を実行してください。'
