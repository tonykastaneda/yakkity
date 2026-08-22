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
yakk --workers   List workers started by yakk
yakk --collect NAME
                 Print a completed worker's result
yakk --retarget NAME --agent AGENT
                 Resubmit a worker's task and context to a different agent
yakk --help      Show usage
yakk --version   Show the installed version
```

Only agents whose command-line tools are installed appear as handoff targets.
Full handoffs omit system records, hidden reasoning, attachments, tool calls,
and tool results. A confirmation is required when the estimated transferred
context exceeds 50,000 tokens.

## Workers (preview)

`--spawn-herdr` turns the supervising agent's current conversation into
background context for a new Claude, Codex, Cursor, or Grok worker, started
in a background [Herdr](https://herdr.dev/) tab. It does not open `fzf` or
ask interactive questions. Each worker agent is started with that agent's own
non-interactive/auto-approve flag (resolved through one small adapter table),
so it won't silently sit stuck at a permission prompt.

```zsh
yakk --spawn-herdr --agent claude --task "Review the installer"
yakk --workers
yakk --collect yakk-claude-1724260000-12345
yakk --retarget yakk-claude-1724260000-12345 --agent codex
```

To make any supported agent the supervisor, tell it:

```text
Read `man yakk`, then use the Yakk CLI to delegate this project through Herdr.
```

`--workers`/`--collect` report a live state per worker — `pending`, `working`,
`blocked` (stuck at an approval prompt despite the auto-approve flag),
`malformed` (wrote a result that doesn't match the expected shape), or `ready`
— by combining Herdr's own agent status with a structural check of the result
file. `--collect` only prints a `ready` result.

`--retarget NAME --agent AGENT` resubmits an existing worker's stored task
and context to a different agent without redescribing the task, and starts a
new worker — the original worker's tab is left running untouched. This is
why a worker's sanitized context file is expired by yakk itself on a TTL
(`YAKK_WORKER_CONTEXT_TTL`, default 24h) rather than deleted the moment
`--collect` succeeds.

Worker metadata and results are stored under a private temporary directory
and are not committed to the repository.

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
