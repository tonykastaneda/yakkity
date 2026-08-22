# yakkity

You probably could've built this yourself. `yakkity` is an `fzf` interface
that searches local coding agent sessions and resumes them for you. It can
also start a new session in one agent using context from another.

## Commands

```text
yakk             Resume a selected conversation in its original agent
yakk --list      List the 10 most recent conversations
yakk --listN     List the N most recent conversations, such as --list25
yakk --off       Compact cross-agent handoff
yakk --ass
                 Full sanitized cross-agent handoff
yakk --spawn-herdr --agent AGENT --task TEXT
                 Start a worker in a background Herdr tab
yakk --spawn-term --agent AGENT --task TEXT
                 Start a worker in a new terminal window
yakk --workers   List workers started by yakk
yakk --collect NAME
                 Print a completed worker's result
yakk --help      Show usage
yakk --version   Show the installed version
```

Only agents whose command-line tools are installed appear as handoff targets.
Full handoffs omit system records, hidden reasoning, attachments, tool calls,
and tool results. A confirmation is required when the estimated transferred
context exceeds 50,000 tokens.

## Workers (preview)

Worker orchestration is currently available on macOS/Zsh only. Both spawn
commands turn the supervising agent's current conversation into background
context for a new Claude, Codex, Cursor, or Grok worker. They do not open
`fzf` or ask interactive questions.

`--spawn-herdr` creates a background [Herdr](https://herdr.dev/) tab and uses
Herdr for agent startup and lifecycle detection. `--spawn-term` creates a
private launcher and opens the worker in a new macOS terminal window. Set
`YAKK_TERMINAL_APP` to choose an application other than Terminal. Over SSH,
that window appears on the remote Mac's graphical desktop; use
`--spawn-herdr` when the worker must remain remotely visible.

```zsh
yakk --spawn-herdr --agent claude --task "Review the installer"
yakk --spawn-term --agent grok --task "Review the CLI design"
yakk --workers
yakk --collect yakk-claude-1724260000-12345
```

To make any supported agent the supervisor, tell it:

```text
Read `man yakk`, then use the Yakk CLI to delegate this project through Herdr.
```

Workers are instructed to write a concise result containing their outcome,
changed files, verification, Git status, and unresolved issues. `--collect`
prints that result so a supervising agent can pull it into its own context.
Worker metadata and results are stored under a private temporary directory and
are not committed to the repository.

This preview does not create Git worktrees automatically. Before spawning,
start the supervising session inside the worktree you want the worker to use.
Otherwise, the worker inherits the supervisor's directory and multiple agents
can edit the same checkout.

## Requirements

- macOS with Zsh, or Windows with PowerShell 5.1+
- `fzf` 0.74.3 or newer
- `jq` (macOS handoffs and Herdr workers)
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

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/tonykastaneda/yakkity/main/install.ps1 | iex"
```

The Windows installer installs `fzf` through Winget when needed, places
`yakk.ps1` and a `yakk.cmd` launcher under `%LOCALAPPDATA%\Programs\yakkity`,
and adds that directory to the user `PATH`. Windows handoffs use PowerShell's
JSON parser, so `jq` is not required.

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
man ./man/yakk.1
```

On Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\yakk.ps1 -Help
powershell -NoProfile -ExecutionPolicy Bypass -File .\yakk.ps1 -Version
```

## License

MIT
