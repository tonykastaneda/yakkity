#!/usr/bin/env bash

set -eu

DEFAULT_PREFIX="${HOME}/.local"
PREFIX="$DEFAULT_PREFIX"
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: uninstall.sh [OPTIONS]

  --yes          Uninstall without prompting
  --prefix PATH  Prefix used for the direct installation (default: ~/.local)
  -h, --help     Show this help

The uninstaller does not remove fzf or jq because they may be used by other
programs.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            ASSUME_YES=1
            shift
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

confirm() {
    local prompt="$1" reply
    [[ "$ASSUME_YES" -eq 1 ]] && return 0
    [[ -r /dev/tty ]] || return 1

    printf "%s [y/N] " "$prompt" > /dev/tty
    read -r reply < /dev/tty
    [[ "$reply" == [Yy]* ]]
}

remove_path_block() {
    local zshrc="$1" temporary path_line mode
    [[ -f "$zshrc" ]] || return 0

    path_line='export PATH="$HOME/.local/bin:$PATH"'
    temporary="$(mktemp "${TMPDIR:-/tmp}/code-chats-zshrc.XXXXXX")"

    awk -v marker="# code-chats" -v path_line="$path_line" '
        $0 == marker { pending = 1; next }
        pending {
            if ($0 == path_line) {
                pending = 0
                next
            }
            print marker
            pending = 0
        }
        { print }
        END { if (pending) print marker }
    ' "$zshrc" > "$temporary"

    if cmp -s "$zshrc" "$temporary"; then
        rm -f "$temporary"
    else
        mode="$(stat -f '%Lp' "$zshrc" 2>/dev/null || echo 644)"
        chmod "$mode" "$temporary"
        mv "$temporary" "$zshrc"
        echo "Removed the code-chats PATH block from $zshrc"
    fi
}

BIN_DIR="${PREFIX}/bin"
DESTINATION="${BIN_DIR}/chat"
DIRECT_FOUND=0

if [[ -f "$DESTINATION" || -L "$DESTINATION" ]]; then
    DIRECT_FOUND=1
    confirm "Remove $DESTINATION?" || {
        echo "Uninstall cancelled."
        exit 0
    }

    rm -f "$DESTINATION"
    echo "Removed $DESTINATION"

    if [[ "$PREFIX" == "$DEFAULT_PREFIX" ]]; then
        remove_path_block "${ZDOTDIR:-$HOME}/.zshrc"
    fi

    rmdir "$BIN_DIR" 2>/dev/null || true
fi

if command -v brew >/dev/null 2>&1 && brew list --formula code-chats >/dev/null 2>&1; then
    if [[ "$DIRECT_FOUND" -eq 1 ]]; then
        echo "A separate Homebrew installation is still present."
    fi

    if confirm "Uninstall the Homebrew code-chats formula too?"; then
        brew uninstall code-chats
    else
        echo "Homebrew installation retained. Remove it later with: brew uninstall code-chats"
    fi
elif [[ "$DIRECT_FOUND" -eq 0 ]]; then
    echo "No code-chats installation was found at $DESTINATION."
    echo "If installed elsewhere, rerun with: --prefix PATH"
fi

echo "fzf and jq were left installed because other programs may use them."
