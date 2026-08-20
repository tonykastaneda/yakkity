#!/usr/bin/env bash

set -eu

PROGRAM="code-chats"
DEFAULT_VERSION="0.1.0"
DEFAULT_PREFIX="${HOME}/.local"
REPOSITORY="tonykastaneda/code-chats"
CHAT_SHA256_0_1_0="0ea9dd4af41de5878e9ec79fb92280104ff98cccefe281070834ba5cdf7855b0"

VERSION="$DEFAULT_VERSION"
PREFIX="$DEFAULT_PREFIX"
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

  --yes              Install missing Homebrew dependencies without prompting
  --version VERSION  Install a specific code-chats version (default: 0.1.0)
  --prefix PATH      Installation prefix (default: ~/.local)
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            ASSUME_YES=1
            shift
            ;;
        --version)
            [[ $# -ge 2 ]] || { echo "--version requires a value" >&2; exit 2; }
            VERSION="$2"
            shift 2
            ;;
        --prefix)
            [[ $# -ge 2 ]] || { echo "--prefix requires a value" >&2; exit 2; }
            PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || {
    echo "$PROGRAM currently supports macOS only." >&2
    exit 1
}

case "$VERSION" in
    0.1.0) CHAT_SHA256="$CHAT_SHA256_0_1_0" ;;
    *)
        echo "No trusted checksum is embedded for code-chats $VERSION." >&2
        exit 1
        ;;
esac

version_lt() {
    [[ "$1" == "$2" ]] && return 1
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

confirm_dependency_install() {
    [[ "$ASSUME_YES" -eq 1 ]] && return 0
    [[ -r /dev/tty ]] || return 1

    local reply
    printf "Install missing dependencies with Homebrew? [Y/n] " > /dev/tty
    read -r reply < /dev/tty
    [[ -z "$reply" || "$reply" == [Yy]* ]]
}

ensure_dependencies() {
    local need_fzf=0 need_jq=0 current_fzf=""

    if command -v fzf >/dev/null 2>&1; then
        current_fzf="$(fzf --version 2>/dev/null | awk '{print $1}')"
        [[ -n "$current_fzf" ]] && version_lt "$current_fzf" "0.74.3" && need_fzf=1
    else
        need_fzf=1
    fi

    command -v jq >/dev/null 2>&1 || need_jq=1
    [[ "$need_fzf" -eq 0 && "$need_jq" -eq 0 ]] && return 0

    echo "code-chats requires fzf 0.74.3+ and jq."

    if ! command -v brew >/dev/null 2>&1; then
        echo "Install the missing dependencies, then rerun this installer:" >&2
        [[ "$need_fzf" -eq 1 ]] && echo "  https://github.com/junegunn/fzf#installation" >&2
        [[ "$need_jq" -eq 1 ]] && echo "  https://jqlang.github.io/jq/download/" >&2
        exit 1
    fi

    confirm_dependency_install || {
        echo "Dependency installation cancelled." >&2
        exit 1
    }

    if [[ "$need_fzf" -eq 1 ]]; then
        if brew list --formula fzf >/dev/null 2>&1; then
            brew upgrade fzf
        else
            brew install fzf
        fi
    fi

    [[ "$need_jq" -eq 1 ]] && brew install jq
}

ensure_dependencies

BIN_DIR="${PREFIX}/bin"
DESTINATION="${BIN_DIR}/chat"
DOWNLOAD_URL="https://raw.githubusercontent.com/${REPOSITORY}/v${VERSION}/chat.zsh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/code-chats-install.XXXXXX")"
DOWNLOADED_CHAT="${TEMP_DIR}/chat"
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

echo "Downloading code-chats ${VERSION}..."
curl --proto '=https' --tlsv1.2 -fsSL "$DOWNLOAD_URL" -o "$DOWNLOADED_CHAT"

ACTUAL_SHA256="$(shasum -a 256 "$DOWNLOADED_CHAT" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$CHAT_SHA256" ]]; then
    echo "Checksum verification failed." >&2
    echo "Expected: $CHAT_SHA256" >&2
    echo "Received: $ACTUAL_SHA256" >&2
    exit 1
fi

mkdir -p "$BIN_DIR"
install -m 0755 "$DOWNLOADED_CHAT" "$DESTINATION"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
        PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
        if [[ "$PREFIX" == "$DEFAULT_PREFIX" ]]; then
            if [[ ! -f "$ZSHRC" ]] || ! grep -Fq "$PATH_LINE" "$ZSHRC"; then
                {
                    printf '\n# code-chats\n'
                    printf '%s\n' "$PATH_LINE"
                } >> "$ZSHRC"
                echo "Added ~/.local/bin to PATH in $ZSHRC"
            fi
        else
            echo "Add $BIN_DIR to your PATH to run chat from any directory."
        fi
        ;;
esac

"$DESTINATION" --version
echo "Installed: $DESTINATION"
echo "Open a new terminal, then run: chat --help"
