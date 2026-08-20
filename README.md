# code-chats

`code-chats` installs the `chat` command: an `fzf` interface for finding and
resuming local Claude Code, Codex, Cursor Agent, and Grok sessions. It can also
start a new session in one agent using sanitized context from another.

## Commands

```text
chat             Resume a selected conversation in its original agent
chat --list      List the 10 most recent conversations
chat -x          Compact cross-agent handoff
chat -xf         Full sanitized cross-agent handoff
chat --help      Show usage
chat --version   Show the installed version
```

Only agents whose command-line tools are installed appear as handoff targets.
Full handoffs omit system records, hidden reasoning, attachments, tool calls,
and tool results. A confirmation is required when the estimated transferred
context exceeds 50,000 tokens.

## Requirements

- macOS
- Zsh
- `fzf` 0.74.3 or newer
- `jq`
- At least one supported agent CLI: `claude`, `codex`, `cursor-agent`, or `grok`

## Install

One-line installer:

```zsh
curl -fsSL https://tonykastaneda.github.io/code-chats/install | bash
```

The installer downloads the pinned release, verifies its SHA-256 checksum,
installs `chat` to `~/.local/bin`, and offers to install missing `fzf`/`jq`
dependencies through Homebrew.

Inspect before running:

```zsh
curl -fsSL https://tonykastaneda.github.io/code-chats/install -o install.sh
less install.sh
bash install.sh
```

Homebrew:

```zsh
brew install tonykastaneda/tap/code-chats
```

Homebrew installs the executable as `chat`; no alias or `.zshrc` change is
required.

## Development

```zsh
zsh -n chat.zsh
./chat.zsh --help
./chat.zsh --version
```

## License

MIT
