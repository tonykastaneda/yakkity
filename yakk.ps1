# yakkity - Search, resume, and hand off local coding-agent sessions on Windows.

[CmdletBinding()]
param(
    [Alias('l')]
    [switch]$List,
    [switch]$Off,
    [switch]$Ass,
    [Alias('h')]
    [switch]$Help,
    [Alias('v')]
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
$YakkVersion = '0.2.2'
$MinFzfVersion = [version]'0.74.3'

function Show-Usage {
    @'
Usage: yakk [OPTION]

  (no option)  Resume the selected conversation in its original agent
  -l, --list   List the 10 most recent conversations
  --off        Hand off compact context to a different agent
  --ass        Hand off the full sanitized conversation to a different agent
  -h, --help   Show this help
  -v, --version
               Show the installed version
'@
}

if ($Help) { Show-Usage; exit 0 }
if ($Version) { "yakkity $YakkVersion"; exit 0 }
if ($Off -and $Ass) { Write-Error 'Choose either --off or --ass, not both.'; exit 2 }

$HandoffMode = if ($Ass) { 'full' } elseif ($Off) { 'compact' } else { $null }
$UserHome = [Environment]::GetFolderPath('UserProfile')
$ClaudeDir = Join-Path $UserHome '.claude'
$CodexDir = Join-Path $UserHome '.codex'
$CursorDir = Join-Path $UserHome '.cursor'
$GrokDir = Join-Path $UserHome '.grok'

function Get-CommandPath([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

function Assert-Fzf {
    $fzf = Get-CommandPath 'fzf'
    if (-not $fzf) {
        throw 'fzf is required. Install it with: winget install --id junegunn.fzf --exact'
    }
    $raw = (& $fzf --version 2>$null | Select-Object -First 1) -split '\s+' | Select-Object -First 1
    try { $current = [version]$raw } catch { return }
    if ($current -lt $MinFzfVersion) {
        throw "fzf $current is too old; yakkity requires $MinFzfVersion or newer."
    }
}

function ConvertFrom-JsonSafe([string]$Text) {
    try { return $Text | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

function Get-JsonProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Clean-Title([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $cleaned = ($Text -replace '\\[nt]', ' ' -replace '\s+', ' ').Trim()
    if ($cleaned -match '^(\{|<[A-Za-z_-]+(?:\s|>))') { return $null }
    if ($cleaned.Length -gt 70) { return $cleaned.Substring(0, 70) }
    return $cleaned
}

function Get-FirstUserTitle([string]$Path, [string]$Provider) {
    $seen = 0
    foreach ($line in [IO.File]::ReadLines($Path)) {
        if ($seen -ge 20) { break }
        $record = ConvertFrom-JsonSafe $line
        if (-not $record) { continue }

        $isUser = switch ($Provider) {
            'Claude' { (Get-JsonProperty $record 'type') -eq 'user' }
            'Codex'  { (Get-JsonProperty $record 'type') -eq 'response_item' -and
                       (Get-JsonProperty (Get-JsonProperty $record 'payload') 'role') -eq 'user' }
            'Grok'   { (Get-JsonProperty $record 'type') -eq 'user' }
            default  { $false }
        }
        if (-not $isUser) { continue }
        $seen++

        if ($Provider -eq 'Codex') {
            $content = Get-JsonProperty (Get-JsonProperty $record 'payload') 'content'
        } elseif ($Provider -eq 'Claude') {
            $content = Get-JsonProperty (Get-JsonProperty $record 'message') 'content'
        } else {
            $content = Get-JsonProperty $record 'content'
        }

        $texts = @()
        if ($content -is [string]) { $texts += $content }
        elseif ($content -is [System.Collections.IEnumerable]) {
            foreach ($part in $content) {
                $text = Get-JsonProperty $part 'text'
                if ($text -is [string]) { $texts += $text }
            }
        }
        $title = Clean-Title ($texts -join ' ')
        if ($title) { return $title }
    }
    return $null
}

function Get-FirstJsonValue([string]$Path, [string]$Name) {
    foreach ($line in [IO.File]::ReadLines($Path)) {
        $record = ConvertFrom-JsonSafe $line
        $value = Get-JsonProperty $record $Name
        if ($null -ne $value -and "$value" -ne '') { return "$value" }
    }
    return $null
}

function Get-LastJsonPath([string]$Path) {
    $last = $null
    foreach ($line in [IO.File]::ReadLines($Path)) {
        if ($line -match '"file_path"\s*:\s*"((?:\\.|[^"])*)"') {
            try { $last = ('"' + $Matches[1] + '"' | ConvertFrom-Json) } catch { }
        } elseif ($line -match '"name"\s*:\s*"(?:Write|StrReplace)".*?"path"\s*:\s*"((?:\\.|[^"])*)"') {
            try { $last = ('"' + $Matches[1] + '"' | ConvertFrom-Json) } catch { }
        }
    }
    return $last
}

function Get-FolderName([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '?' }
    $trimmed = $Path.TrimEnd([char[]]@('\', '/'))
    $name = Split-Path -Leaf $trimmed
    if ($name) { return $name }
    return $trimmed
}

function Get-ProjectLabel([string]$StartPath, [string]$LastPath) {
    $start = Get-FolderName $StartPath
    $last = if ($LastPath) { Get-FolderName (Split-Path -Parent $LastPath) } else { $start }
    if (-not $last -or $last -eq '?') { $last = $start }
    return "$start -> $last"
}

function New-Session([string]$Provider, [IO.FileInfo]$File, [string]$Id,
                     [string]$Title, [string]$Workspace, [string]$Transcript,
                     [string]$LastPath) {
    [pscustomobject]@{
        Provider   = $Provider
        Modified   = $File.LastWriteTime
        Title      = $Title
        Id         = $Id
        Workspace  = $Workspace
        Transcript = $Transcript
        Project    = Get-ProjectLabel $Workspace $LastPath
    }
}

function Get-ClaudeSessions {
    $root = Join-Path $ClaudeDir 'projects'
    if (-not (Test-Path $root)) { return }
    foreach ($file in Get-ChildItem $root -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue) {
        $title = Get-FirstUserTitle $file.FullName 'Claude'
        if (-not $title) { $title = 'Claude session' }
        $cwd = Get-FirstJsonValue $file.FullName 'cwd'
        New-Session 'Claude' $file $file.BaseName $title $cwd $file.FullName (Get-LastJsonPath $file.FullName)
    }
}

function Get-CodexSessions {
    $root = Join-Path $CodexDir 'sessions'
    if (-not (Test-Path $root)) { return }
    foreach ($file in Get-ChildItem $root -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue) {
        $match = [regex]::Matches($file.Name, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
        $id = if ($match.Count) { $match[$match.Count - 1].Value } else { $file.BaseName }
        $title = Get-FirstUserTitle $file.FullName 'Codex'
        if (-not $title) { $title = 'Codex session' }
        $cwd = Get-FirstJsonValue $file.FullName 'cwd'
        New-Session 'Codex' $file $id $title $cwd $file.FullName $null
    }
}

function ConvertTo-CursorProjectName([string]$Workspace) {
    return ($Workspace.TrimStart([char[]]@('\', '/')) -replace '[:\\/]', '-')
}

function Find-CursorTranscript([string]$Id, [string]$Workspace) {
    if ($Workspace) {
        $encoded = ConvertTo-CursorProjectName $Workspace
        $candidate = Join-Path $CursorDir "projects\$encoded\agent-transcripts\$Id\$Id.jsonl"
        if (Test-Path $candidate) { return $candidate }
    }
    $root = Join-Path $CursorDir 'projects'
    if (Test-Path $root) {
        $found = Get-ChildItem $root -Filter "$Id.jsonl" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*agent-transcripts*$Id*$Id.jsonl" } | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Get-CursorSessions {
    $root = Join-Path $CursorDir 'chats'
    if (-not (Test-Path $root)) { return }
    foreach ($file in Get-ChildItem $root -Filter 'meta.json' -File -Recurse -ErrorAction SilentlyContinue) {
        $meta = ConvertFrom-JsonSafe ([IO.File]::ReadAllText($file.FullName))
        if (-not (Get-JsonProperty $meta 'hasConversation')) { continue }
        $id = $file.Directory.Name
        $cwd = Get-JsonProperty $meta 'cwd'
        $title = Clean-Title (Get-JsonProperty $meta 'title')
        if (-not $title) { $title = 'Cursor session' }
        $transcript = Find-CursorTranscript $id $cwd
        $last = if ($transcript) { Get-LastJsonPath $transcript } else { $null }
        $session = New-Session 'Cursor' $file $id $title $cwd $transcript $last
        $updated = Get-JsonProperty $meta 'updatedAtMs'
        if ($updated) { $session.Modified = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$updated).LocalDateTime }
        $session
    }
}

function Get-GrokSessions {
    $root = Join-Path $GrokDir 'sessions'
    if (-not (Test-Path $root)) { return }
    foreach ($file in Get-ChildItem $root -Filter 'summary.json' -File -Recurse -ErrorAction SilentlyContinue) {
        $chat = Join-Path $file.Directory.FullName 'chat_history.jsonl'
        if (-not (Test-Path $chat)) { continue }
        $summary = ConvertFrom-JsonSafe ([IO.File]::ReadAllText($file.FullName))
        $title = Clean-Title (Get-JsonProperty $summary 'session_summary')
        if (-not $title) { $title = Get-FirstUserTitle $chat 'Grok' }
        if (-not $title) { continue }
        $cwd = Get-JsonProperty $summary 'cwd'
        $chatFile = Get-Item $chat
        New-Session 'Grok' $chatFile $file.Directory.Name $title $cwd $chat (Get-LastJsonPath $chat)
    }
}

function Format-Time([datetime]$Time) {
    $age = (Get-Date) - $Time
    if ($age.TotalMinutes -lt 1) { return 'just now' }
    if ($age.TotalHours -lt 1) { $n = [math]::Floor($age.TotalMinutes); return "$n minute$(if ($n -ne 1) {'s'}) ago" }
    if ($age.TotalDays -lt 1) { $n = [math]::Floor($age.TotalHours); return "$n hour$(if ($n -ne 1) {'s'}) ago" }
    if ($age.TotalDays -lt 7) { $n = [math]::Floor($age.TotalDays); return "$n day$(if ($n -ne 1) {'s'}) ago" }
    return $Time.ToString('yyyy-MM-dd hh:mm tt')
}

function Get-TextContent($Content) {
    if ($Content -is [string]) { return $Content }
    $texts = @()
    if ($Content -is [System.Collections.IEnumerable]) {
        foreach ($part in $Content) {
            $type = Get-JsonProperty $part 'type'
            if ($type -in @('text', 'input_text', 'output_text')) {
                $text = Get-JsonProperty $part 'text'
                if ($text -is [string]) { $texts += $text }
            }
        }
    }
    return ($texts -join "`n")
}

function Get-SanitizedTranscript($Session) {
    $builder = [Text.StringBuilder]::new()
    foreach ($line in [IO.File]::ReadLines($Session.Transcript)) {
        $record = ConvertFrom-JsonSafe $line
        if (-not $record) { continue }
        $role = $null; $content = $null
        switch ($Session.Provider) {
            'Claude' {
                $type = Get-JsonProperty $record 'type'
                if ($type -notin @('user', 'assistant')) { continue }
                $message = Get-JsonProperty $record 'message'
                $role = Get-JsonProperty $message 'role'; if (-not $role) { $role = $type }
                $content = Get-JsonProperty $message 'content'
            }
            'Codex' {
                if ((Get-JsonProperty $record 'type') -ne 'response_item') { continue }
                $payload = Get-JsonProperty $record 'payload'
                if ((Get-JsonProperty $payload 'type') -ne 'message') { continue }
                $role = Get-JsonProperty $payload 'role'
                $content = Get-JsonProperty $payload 'content'
            }
            'Cursor' {
                $role = Get-JsonProperty $record 'role'
                $content = Get-JsonProperty $record 'message'
                if ($content -and $content -isnot [string]) {
                    $content = Get-JsonProperty $content 'content'
                    if (-not $content) { $content = Get-JsonProperty (Get-JsonProperty $record 'message') 'text' }
                }
            }
            'Grok' {
                $role = Get-JsonProperty $record 'type'
                $content = Get-JsonProperty $record 'content'
            }
        }
        if ($role -notin @('user', 'assistant')) { continue }
        $text = Get-TextContent $content
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        [void]$builder.AppendLine("## $($role.ToUpperInvariant())`n")
        [void]$builder.AppendLine($text)
        [void]$builder.AppendLine()
    }
    return $builder.ToString()
}

function New-Handoff($Session, [string]$Mode) {
    $body = Get-SanitizedTranscript $Session
    if ([string]::IsNullOrWhiteSpace($body)) { return $null }
    $utf8 = [Text.UTF8Encoding]::new($false)
    $bytes = $utf8.GetBytes($body)
    if ($Mode -eq 'compact' -and $bytes.Length -gt 20000) {
        $first = $utf8.GetString($bytes, 0, 5000)
        $start = $bytes.Length - 15000
        $recent = $utf8.GetString($bytes, $start, 15000)
        $body = "$first`n`n--- MIDDLE OMITTED ---`n`n$recent"
    }
    $handoff = "# Cross-agent conversation handoff`n`nSource agent: $($Session.Provider)`n`nConversation: $($Session.Title)`n`n$body"
    $path = Join-Path ([IO.Path]::GetTempPath()) ("chat-handoff-{0}.md" -f [guid]::NewGuid())
    [IO.File]::WriteAllText($path, $handoff, $utf8)
    [pscustomobject]@{ Path = $path; Tokens = [math]::Ceiling($utf8.GetByteCount($handoff) / 4) }
}

function Invoke-Agent([string]$Command, [string[]]$Arguments) {
    $path = Get-CommandPath $Command
    if (-not $path) { throw "$Command command not found." }
    & $path @Arguments
    exit $LASTEXITCODE
}

Assert-Fzf
$sessions = @(& {
    Get-ClaudeSessions
    Get-CodexSessions
    Get-CursorSessions
    Get-GrokSessions
}) |
    Where-Object { $_ } | Sort-Object Modified -Descending
if (-not $sessions.Count) { Write-Error 'No Claude Code, Codex, Cursor, or Grok sessions found.'; exit 1 }

if ($List) {
    '{0,-8}  {1,-19}  {2,-32}  {3,-50}' -f 'Agent', 'Time', 'Project', 'Conversation'
    foreach ($session in $sessions | Select-Object -First 10) {
        $project = if ($session.Project.Length -gt 32) { $session.Project.Substring(0, 32) } else { $session.Project }
        $title = if ($session.Title.Length -gt 50) { $session.Title.Substring(0, 50) } else { $session.Title }
        '{0,-8}  {1,-19}  {2,-32}  {3,-50}' -f $session.Provider, (Format-Time $session.Modified), $project, $title
    }
    exit 0
}

$rows = for ($i = 0; $i -lt $sessions.Count; $i++) {
    $s = $sessions[$i]
    "{0,-8}`t{1,-19}`t{2,-32}`t{3}`t{4}" -f $s.Provider, (Format-Time $s.Modified), $s.Project, $s.Title, $i
}
$header = "{0,-8}`t{1,-19}`t{2,-32}`tConversation" -f 'Agent', 'Time', 'Project'
$selected = $rows | fzf --delimiter "`t" --with-nth '1,2,3,4' --prompt 'Resume> ' --height 35 --layout reverse --header $header --footer 'UP/DOWN navigate | ENTER resume | ESC quit'
if (-not $selected) { exit 0 }
$index = [int](($selected -split "`t")[-1])
$session = $sessions[$index]

if ($session.Workspace -and (Test-Path -LiteralPath $session.Workspace -PathType Container)) {
    Set-Location -LiteralPath $session.Workspace
} elseif ($session.Workspace) {
    Write-Warning "Original project directory is missing: $($session.Workspace)"
}

if ($HandoffMode) {
    if (-not $session.Transcript -or -not (Test-Path $session.Transcript)) {
        throw "Could not locate the readable transcript for this $($session.Provider) session."
    }
    $targets = @(
        [pscustomobject]@{ Name='Claude'; Command='claude' },
        [pscustomobject]@{ Name='Codex'; Command='codex' },
        [pscustomobject]@{ Name='Cursor'; Command='cursor-agent' },
        [pscustomobject]@{ Name='Grok'; Command='grok' }
    ) | Where-Object { $_.Name -ne $session.Provider -and (Get-CommandPath $_.Command) }
    if (-not $targets.Count) { throw 'No other supported agent CLI is installed.' }
    $choice = $targets | ForEach-Object { "$($_.Name)`t$($_.Command)" } |
        fzf --delimiter "`t" --with-nth 1 --prompt 'Hand off to> ' --height 35 --layout reverse
    if (-not $choice) { exit 0 }
    $destination, $command = $choice -split "`t", 2
    $handoff = New-Handoff $session $HandoffMode
    if (-not $handoff) { throw 'No transferable user/assistant text was found in this session.' }
    if ($HandoffMode -eq 'full' -and $handoff.Tokens -gt 50000) {
        $reply = Read-Host "Full handoff is approximately $($handoff.Tokens) input tokens. Continue? [y/N]"
        if ($reply -notmatch '^[Yy]') { Remove-Item $handoff.Path -Force; exit 0 }
    }
    "Handing off to $destination"
    $prompt = "Read the cross-agent conversation handoff at: $($handoff.Path)`n`nUse it as background context for this new session. Do not repeat the transcript. Briefly confirm that the handoff is loaded, state the current objective you inferred, and ask what I want to do next. After reading it, delete the temporary handoff file."
    Invoke-Agent $command @($prompt)
}

"Resuming`n$($session.Title)"
switch ($session.Provider) {
    'Claude' { Invoke-Agent 'claude' @('--resume', $session.Id) }
    'Codex'  { Invoke-Agent 'codex' @('resume', $session.Id) }
    'Cursor' {
        $args = @('--resume', $session.Id)
        if ($session.Workspace) { $args += @('--workspace', $session.Workspace) }
        Invoke-Agent 'cursor-agent' $args
    }
    'Grok' {
        $args = @('--resume', $session.Id)
        if ($session.Workspace) { $args += @('--cwd', $session.Workspace) }
        Invoke-Agent 'grok' $args
    }
}
