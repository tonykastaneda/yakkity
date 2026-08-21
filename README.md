# yakkity

`yakkity` installs the `yakk` command: an `fzf` interface for finding and
resuming local Claude Code, Codex, Cursor Agent, and Grok sessions. It can also
start a new session in one agent using sanitized context from another.

## Commands

```text
yakk             Resume a selected conversation in its original agent
yakk --list      List the 10 most recent conversations
yakk -off        Compact cross-agent handoff
yakk -off-fullfrontal
                 Full sanitized cross-agent handoff
yakk --help      Show usage
yakk --version   Show the installed version
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
curl -fsSL https://yakkity.dev/install | bash
```

The installer downloads the pinned release, verifies its SHA-256 checksum,
installs `yakk` to `~/.local/bin`, and offers to install missing `fzf`/`jq`
dependencies through Homebrew.

Inspect before running:

```zsh
curl -fsSL https://yakkity.dev/install -o install.sh
less install.sh
bash install.sh
```

Homebrew:

```zsh
brew install tonykastaneda/tap/yakkity
```

Homebrew installs the executable as `yakk`; no alias or `.zshrc` change is
required.

## Uninstall

One-line installation:

```zsh
curl -fsSL https://yakkity.dev/uninstall | bash
```

Homebrew installation:

```zsh
brew uninstall yakkity
```

The uninstaller leaves `fzf` and `jq` installed because other programs may
depend on them.

## Development

```zsh
zsh -n yakk.zsh
./yakk.zsh --help
./yakk.zsh --version
```

## License

MIT
