#!/bin/zsh

# yakkity — Search, resume, and hand off local coding-agent sessions.

set -u

VERSION="0.2.1"

usage() {
    cat <<'EOF'
Usage: yakk [OPTION]

  (no option)  Resume the selected conversation in its original agent
  -l, --list   List the 10 most recent conversations
  -off         Hand off compact context to a different agent
  -ass
               Hand off the full sanitized conversation to a different agent
  -h, --help   Show this help
  -v, --version
               Show the installed version
EOF
}

HANDOFF_MODE=""

case "${1:-}" in
    "") ;;
    -l|--list) ;;
    -off) HANDOFF_MODE="compact" ;;
    -ass) HANDOFF_MODE="full" ;;
    -h|--help)
        usage
        exit 0
        ;;
    -v|--version)
        printf 'yakkity %s\n' "$VERSION"
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
esac

# ------------------------------------------------------------
# Validate dependencies. Package managers should install these;
# this command never downloads or updates software at runtime.
# ------------------------------------------------------------

MIN_FZF_VERSION="0.74.3"

version_lt() {
    [[ "$1" == "$2" ]] && return 1
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

confirm() {
    local reply
    printf "%s [y/N] " "$1"
    read -r reply
    [[ "$reply" == [Yy]* ]]
}

ensure_fzf() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "fzf is required. Install it with: brew install fzf" >&2
        exit 1
    fi

    local current
    current="$(fzf --version 2>/dev/null | awk '{print $1}')"
    [[ -n "$current" ]] || return

    if version_lt "$current" "$MIN_FZF_VERSION"; then
        echo "fzf $current is too old; yakkity requires $MIN_FZF_VERSION or newer." >&2
        exit 1
    fi
}

ensure_fzf

CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
CURSOR_DIR="$HOME/.cursor"
GROK_DIR="$HOME/.grok"

BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'
ORANGE=$'\033[38;5;208m'
BLUE=$'\033[38;5;39m'
GREEN=$'\033[38;5;82m'
LAVENDER=$'\033[38;5;141m'

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

format_time() {
    local epoch="$1"
    [[ -n "$epoch" ]] || { echo ""; return; }

    local now diff value unit
    now="$(date +%s)"
    diff=$(( now - epoch ))
    (( diff < 0 )) && diff=0

    if (( diff < 60 )); then
        echo "just now"
        return
    elif (( diff < 3600 )); then
        value=$(( diff / 60 )); unit="minute"
    elif (( diff < 86400 )); then
        value=$(( diff / 3600 )); unit="hour"
    elif (( diff < 604800 )); then
        value=$(( diff / 86400 )); unit="day"
    else
        date -r "$epoch" "+%Y-%m-%d %I:%M %p" 2>/dev/null || echo ""
        return
    fi

    if (( value == 1 )); then
        echo "${value} ${unit} ago"
    else
        echo "${value} ${unit}s ago"
    fi
}

# Pull a scalar string value out of flat JSON without a jq dependency.
# Matches "key":"value" regardless of field order.
json_str() {
    local file="$1" key="$2"
    grep -o "\"${key}\": *\"[^\"]*\"" "$file" 2>/dev/null |
        head -1 |
        sed -E "s/\"${key}\": *\"//;s/\"\$//"
}

# Turn a raw extracted fragment into a display-safe title: collapse
# literal \n/\t escape artifacts and repeated whitespace, and reject
# strings that still look like raw JSON or injected/synthetic preamble
# rather than something a human actually typed. Echoes "" if rejected.
clean_title() {
    local raw="$1" cleaned

    [[ -n "$raw" ]] || { echo ""; return; }

    cleaned="${raw//\\n/ }"
    cleaned="${cleaned//\\t/ }"
    cleaned="$(echo "$cleaned" | tr -s '[:space:]' ' ')"
    cleaned="${cleaned## }"
    cleaned="${cleaned%% }"

    case "$cleaned" in
        "{"*|"<"[A-Za-z]*)
            echo ""
            return
            ;;
    esac

    echo "$cleaned" | cut -c1-70
}

# Resolve the transcript containing the selected session's human-visible
# conversation. Cursor keeps it separately from meta.json; Grok keeps it next
# to summary.json. Claude and Codex use the file already discovered by ID.
session_transcript() {
    local provider="$1" id="$2" workspace="$3" file=""

    case "$provider" in
        Claude)
            file="$(find "$CLAUDE_DIR/projects" -type f -name "${id}.jsonl" -print -quit 2>/dev/null)"
            ;;
        Codex)
            file="$(find "$CODEX_DIR/sessions" -type f -name "*${id}*.jsonl" -print -quit 2>/dev/null)"
            ;;
        Cursor)
            if [[ -n "$workspace" ]]; then
                file="$CURSOR_DIR/projects/$(echo "$workspace" | sed 's#^/##; s#/#-#g')/agent-transcripts/${id}/${id}.jsonl"
            fi
            if [[ ! -f "$file" ]]; then
                file="$(find "$CURSOR_DIR/projects" -type f -path "*/agent-transcripts/${id}/${id}.jsonl" -print -quit 2>/dev/null)"
            fi
            ;;
        Grok)
            file="$(find "$GROK_DIR/sessions" -type f -path "*/${id}/chat_history.jsonl" -print -quit 2>/dev/null)"
            ;;
    esac

    [[ -f "$file" ]] && printf '%s\n' "$file"
}

# Print only user/assistant prose. Provider system records, reasoning blocks,
# attachments, tool calls, and tool results are deliberately omitted.
sanitized_transcript() {
    local provider="$1" file="$2"

    case "$provider" in
        Claude)
            jq -Rr '
                fromjson? |
                select(.type == "user" or .type == "assistant") |
                (.message.role // .type) as $role |
                .message.content as $content |
                (if ($content | type) == "string" then $content
                 elif ($content | type) == "array" then
                    [$content[]? | select(.type == "text") | .text] | join("\n")
                 else "" end) as $text |
                select(($text | length) > 0) |
                "## " + ($role | ascii_upcase) + "\n\n" + $text + "\n"
            ' "$file"
            ;;
        Codex)
            jq -Rr '
                fromjson? |
                select(.type == "response_item" and .payload.type == "message") |
                .payload.role as $role |
                select($role == "user" or $role == "assistant") |
                [.payload.content[]? |
                    select(.type == "input_text" or .type == "output_text" or .type == "text") |
                    (.text // "")] | join("\n") as $text |
                select(($text | length) > 0) |
                "## " + ($role | ascii_upcase) + "\n\n" + $text + "\n"
            ' "$file"
            ;;
        Cursor)
            jq -Rr '
                fromjson? |
                select(.role == "user" or .role == "assistant") |
                .role as $role |
                .message as $content |
                (if ($content | type) == "string" then $content
                 elif ($content | type) == "object" then
                    (($content.content // $content.text // "") as $body |
                     if ($body | type) == "string" then $body
                     elif ($body | type) == "array" then
                        [$body[]? | select(.type == "text") | (.text // "")] | join("\n")
                     else "" end)
                 else "" end) as $text |
                select(($text | type) == "string" and ($text | length) > 0) |
                "## " + ($role | ascii_upcase) + "\n\n" + $text + "\n"
            ' "$file"
            ;;
        Grok)
            jq -Rr '
                fromjson? |
                select(.type == "user" or .type == "assistant") |
                .type as $role |
                .content as $content |
                (if ($content | type) == "string" then $content
                 elif ($content | type) == "array" then
                    [$content[]? | select(.type == "text") | (.text // "")] | join("\n")
                 else "" end) as $text |
                select(($text | length) > 0) |
                "## " + ($role | ascii_upcase) + "\n\n" + $text + "\n"
            ' "$file"
            ;;
    esac
}

handoff_agent_picker() {
    local source="$1" agent command_name

    while IFS=$'\t' read -r agent command_name; do
        [[ "$agent" == "$source" ]] && continue
        command -v "$command_name" >/dev/null 2>&1 || continue
        printf '%s\t%s\n' "$agent" "$command_name"
    done <<'EOF' |
Claude	claude
Codex	codex
Cursor	cursor-agent
Grok	grok
EOF
        fzf \
            --delimiter=$'\t' \
            --with-nth=1 \
            --prompt="Hand off to> " \
            --height=35 \
            --layout=reverse \
            --header="Available destination agents" \
            --footer=$'↑↓ navigate  |  ENTER hand off  |  ESC cancel'
}

create_handoff_file() {
    local mode="$1" provider="$2" title="$3" transcript="$4"
    local full_file handoff_file total_bytes estimate_tokens first_bytes=5000 recent_bytes=15000

    full_file="$(mktemp "${TMPDIR:-/tmp}/chat-handoff-full.XXXXXX")" || return 1
    handoff_file="$(mktemp "${TMPDIR:-/tmp}/chat-handoff.XXXXXX")" || { rm -f "$full_file"; return 1; }
    chmod 600 "$full_file" "$handoff_file"

    sanitized_transcript "$provider" "$transcript" > "$full_file"
    total_bytes="$(wc -c < "$full_file" | tr -d ' ')"

    if [[ "$total_bytes" -eq 0 ]]; then
        rm -f "$full_file" "$handoff_file"
        return 1
    fi

    {
        printf '# Cross-agent conversation handoff\n\n'
        printf 'Source agent: %s\n\n' "$provider"
        printf 'Conversation: %s\n\n' "$title"
        if [[ "$mode" == "full" || "$total_bytes" -le $(( first_bytes + recent_bytes )) ]]; then
            cat "$full_file"
        else
            printf 'The middle of this conversation was omitted by compact handoff mode.\n\n'
            head -c "$first_bytes" "$full_file"
            printf '\n\n--- MIDDLE OMITTED ---\n\n'
            tail -c "$recent_bytes" "$full_file"
        fi
    } > "$handoff_file"

    rm -f "$full_file"
    estimate_tokens=$(( ($(wc -c < "$handoff_file" | tr -d ' ') + 3) / 4 ))
    printf '%s\t%s\n' "$handoff_file" "$estimate_tokens"
}

# Scan a JSONL transcript for the first genuinely-typed user message,
# skipping lines whose extraction fails (raw JSON leaking through) or
# whose content is synthetic/injected preamble — system reminders, tool
# tags, image-attachment references, etc.
#
# Session files can contain individual lines tens of megabytes long
# (e.g. a pasted image as inline base64) — reading such a line into an
# unbounded field, as plain awk or a naive `grep -m1 | sed` pipeline
# would, costs the better part of a second EACH, dominating startup
# time. `grep -o 'PATTERN.\{0,250\}'` extracts only a bounded window
# around each match without ever materializing the full line, so the
# huge-line cost disappears; awk then does the cheap cleanup/rejection
# work on that small piped output. 250 (not e.g. 300) because macOS's
# /usr/bin/grep hard-caps interval repetition at 255 and silently
# produces zero matches past that — no error on stdout, easy to miss.
# Avoids jq: matches either a plain string ("content":"...") or a
# nested content-array ("content":[{"text":"..."}]) shape via
# greedy-backtracking regex.
# Args: file, grep-style pattern identifying a user-turn line
extract_user_title() {
    local file="$1" role_pattern="$2"

    grep -m 20 -o "${role_pattern}.\{0,250\}" "$file" 2>/dev/null | awk '
        {
            line = $0
            if (match(line, /"(content|text)":"[^"]*"/)) {
                frag = substr(line, RSTART, RLENGTH)
                sub(/^"[a-z]+":"/, "", frag)
                sub(/"$/, "", frag)
            } else {
                next
            }
            gsub(/\\n/, " ", frag)
            gsub(/\\t/, " ", frag)
            gsub(/  +/, " ", frag)
            gsub(/^ +/, "", frag)
            gsub(/ +$/, "", frag)
            if (frag ~ /^\{/ || frag ~ /^<[a-zA-Z_-]+[ >]/) next
            if (length(frag) > 0) {
                print substr(frag, 1, 70)
                exit
            }
        }
    '
}

# ------------------------------------------------------------
# Phase 1: fast metadata-only scan per provider — no title
# extraction (that's the expensive part, deferred to Phase 2's
# emit_rows). Each scan_* prints one tab-delimited row per
# candidate session:
#   mtime  provider  titlefile  id  fallbackfile  workspace
# titlefile is what Phase 2 runs title-extraction against.
# fallbackfile is Grok-only (chat_history.jsonl, used when
# session_summary is empty) — "-" for the other three, since
# zsh's `read` collapses a genuinely-empty field that has more
# fields after it (shifting everything past it by one); a
# placeholder in a middle field sidesteps that entirely. Only
# workspace is left truly empty when unused, since it's always
# the last field and nothing follows it to shift.
# ------------------------------------------------------------

scan_claude() {
    local projects="$CLAUDE_DIR/projects"

    [[ -d "$projects" ]] || return

    # NOTE: locals must be declared once, outside the loop body — declaring
    # them fresh on every iteration of a `while read < <(...)` loop causes
    # zsh to spew `var=value` lines to stdout.
    local file id mtime

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        id="$(basename "$file" .jsonl)"
        mtime="$(stat -f "%m" "$file" 2>/dev/null || echo 0)"

        printf '%s\tClaude\t%s\t%s\t-\t\n' "$mtime" "$file" "$id"

    done < <(
        find "$projects" \
            -type f \
            -name '*.jsonl' \
            2>/dev/null
    )
}

scan_codex() {
    local sessions="$CODEX_DIR/sessions"

    [[ -d "$sessions" ]] || return

    local file filename id mtime

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        filename="$(basename "$file")"
        mtime="$(stat -f "%m" "$file" 2>/dev/null || echo 0)"

        # Codex rollout filenames commonly contain the session UUID.
        id="$(
            echo "$filename" |
            grep -Eo \
                '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' |
            tail -1
        )"

        [[ -n "$id" ]] || id="${filename%.jsonl}"

        printf '%s\tCodex\t%s\t%s\t-\t\n' "$mtime" "$file" "$id"

    done < <(
        find "$sessions" \
            -type f \
            -name '*.jsonl' \
            2>/dev/null
    )
}

scan_cursor() {
    local chats="$CURSOR_DIR/chats"

    [[ -d "$chats" ]] || return

    local file id cwd mtime_ms mtime

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        # Skip chats that were opened but never actually used.
        grep -q '"hasConversation": *true' "$file" 2>/dev/null || continue

        id="$(basename "$(dirname "$file")")"
        cwd="$(json_str "$file" cwd)"

        mtime_ms="$(grep -o '"updatedAtMs": *[0-9]*' "$file" 2>/dev/null | head -1 | grep -o '[0-9]*$')"
        if [[ -n "$mtime_ms" ]]; then
            mtime=$(( mtime_ms / 1000 ))
        else
            mtime="$(stat -f "%m" "$file" 2>/dev/null || echo 0)"
        fi

        printf '%s\tCursor\t%s\t%s\t-\t%s\n' "$mtime" "$file" "$id" "$cwd"

    done < <(
        find "$chats" \
            -type f \
            -name 'meta.json' \
            2>/dev/null
    )
}

scan_grok() {
    local sessions="$GROK_DIR/sessions"

    [[ -d "$sessions" ]] || return

    local file id cwd chat mtime

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        chat="$(dirname "$file")/chat_history.jsonl"

        # Skip sessions that were opened but never actually used.
        [[ -f "$chat" ]] || continue

        id="$(basename "$(dirname "$file")")"
        cwd="$(json_str "$file" cwd)"

        mtime="$(stat -f "%m" "$chat" 2>/dev/null || stat -f "%m" "$file" 2>/dev/null || echo 0)"

        printf '%s\tGrok\t%s\t%s\t%s\t%s\n' "$mtime" "$file" "$id" "$chat" "$cwd"

    done < <(
        find "$sessions" \
            -type f \
            -name 'summary.json' \
            2>/dev/null
    )
}

# ------------------------------------------------------------
# Phase 2: reads sorted Phase-1 rows from stdin and streams a
# resolved "provider mtime title id workspace project" record
# the instant each is ready — this is the only place the
# per-provider title-extraction dispatch happens.
#
# "project" is "StartFolder → LastFolderWritten" — the folder
# name (not full path) the session started in, and the folder
# name of whatever file it last wrote to. When a session never
# left its starting folder, both sides show the same name.
#
# Per-provider reliability of "last written" varies with what
# each tool actually records:
#   Claude — reliable: every Write/Edit tool call logs an exact
#     "file_path", so the true last write is known.
#   Cursor — reliable: cursor-agent also writes a plain JSONL
#     transcript (separate from its SQLite chat store) with the
#     same Write/StrReplace tool-call shape as Claude's; its
#     path is derived directly from the already-known cwd + id
#     rather than searched for.
#   Grok — best-effort/unverified: assumed to follow the same
#     "file_path" convention as Claude, but every Grok session on
#     this machine is a ghost session (see load filtering above),
#     so there is no real data to confirm this against.
#   Codex — not attempted: Codex has no dedicated write tool, it
#     runs arbitrary shell commands instead, and every regex tried
#     for spotting a file redirect in that shell text (`> foo`,
#     path-shaped targets, etc.) produced false positives against
#     real sessions (matched unrelated `>` in prose/XML-ish tags).
#     Rather than show a misleading folder, Codex just shows its
#     start folder on both sides of the arrow.
# ------------------------------------------------------------

emit_rows() {
    # NOTE: locals declared once, outside the loop body — same
    # while-read gotcha as scan_claude et al. above.
    local mtime provider titlefile id fallbackfile workspace title
    local start_path last_path start_name last_name project transcript

    while IFS=$'\t' read -r mtime provider titlefile id fallbackfile workspace; do
        last_path=""

        case "$provider" in
            Claude)
                title="$(extract_user_title "$titlefile" '"type":"user"')"
                [[ -n "$title" ]] || title="Claude session"

                start_path="$(grep -m1 -o '"cwd":"[^"]\{0,250\}"' "$titlefile" 2>/dev/null | sed -E 's/"cwd":"//;s/"$//')"
                last_path="$(grep -o '"file_path":"[^"]\{0,250\}"' "$titlefile" 2>/dev/null | tail -1 | sed -E 's/"file_path":"//;s/"$//')"
                ;;
            Codex)
                title="$(extract_user_title "$titlefile" '"role":"user"')"
                [[ -n "$title" ]] || title="Codex session"

                start_path="$(grep -m1 -o '"cwd":"[^"]\{0,250\}"' "$titlefile" 2>/dev/null | sed -E 's/"cwd":"//;s/"$//')"
                ;;
            Cursor)
                title="$(json_str "$titlefile" title)"
                [[ -n "$title" ]] || title="Cursor session"

                start_path="$workspace"
                if [[ -n "$workspace" ]]; then
                    transcript="$HOME/.cursor/projects/$(echo "$workspace" | sed 's#^/##; s#/#-#g')/agent-transcripts/${id}/${id}.jsonl"
                    if [[ -f "$transcript" ]]; then
                        last_path="$(grep -o '"name":"\(Write\|StrReplace\)","input":{"path":"[^"]\{0,250\}"' "$transcript" 2>/dev/null | tail -1 | sed -E 's/.*"path":"//;s/"$//')"
                    fi
                fi
                ;;
            Grok)
                # session_summary is usually empty, so fall back to the
                # first genuinely-typed user message.
                title="$(json_str "$titlefile" session_summary)"
                [[ -n "$title" ]] && title="$(clean_title "$title")"

                if [[ -z "$title" ]]; then
                    title="$(extract_user_title "$fallbackfile" '"type":"user"')"
                fi

                # No genuine user turn anywhere in this session — it's
                # not a real conversation, so skip it entirely rather
                # than showing junk.
                [[ -n "$title" ]] || continue

                start_path="$workspace"
                last_path="$(grep -o '"file_path":"[^"]\{0,250\}"' "$fallbackfile" 2>/dev/null | tail -1 | sed -E 's/"file_path":"//;s/"$//')"
                ;;
        esac

        start_name="${start_path:t}"
        [[ -n "$start_name" ]] || start_name="?"

        if [[ -n "$last_path" ]]; then
            last_name="${last_path:h:t}"
            [[ -n "$last_name" ]] || last_name="$start_name"
        else
            last_name="$start_name"
        fi

        project="${start_name} → ${last_name}"

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$provider" "$mtime" "$title" "$id" "$project" "$workspace"
    done
}

# ------------------------------------------------------------
# Phase 1: run the fast scan across all four providers up front.
# No title extraction happens here, so this is expected to
# complete in well under a second even across hundreds of
# sessions — everything after this point streams.
# ------------------------------------------------------------

meta_raw="$( { scan_claude; scan_codex; scan_cursor; scan_grok; } )"

if [[ -z "$meta_raw" ]]; then
    echo "No Claude Code, Codex, Cursor, or Grok sessions found."
    exit 1
fi

# ------------------------------------------------------------
# --list / -l: print the 10 most recent conversations and exit.
# Reuses the same scan -> sort -> emit_rows pipeline as the fzf
# picker below, so the per-provider title-dispatch logic exists
# in exactly one place. `head -10` closing early also naturally
# caps title-extraction work to roughly the top 10 sessions.
# ------------------------------------------------------------

if [[ "${1:-}" == "-l" || "${1:-}" == "--list" ]]; then
    printf "%s%-8s  %-19s  %-32s  %-50s%s\n" "$BOLD" "Agent" "Time" "Project" "Conversation" "$RESET"

    printf '%s\n' "$meta_raw" |
        sort -t $'\t' -k1,1rn |
        emit_rows |
        head -10 |
        while IFS=$'\t' read -r provider mtime title id project workspace; do
            printf "%-8s  %-19s  %-32s  %-50s\n" \
                "$provider" \
                "$(format_time "$mtime")" \
                "${project[1,32]}" \
                "${title[1,50]}"
        done

    exit 0
fi

# ------------------------------------------------------------
# fzf searchable selector
# ------------------------------------------------------------

if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required. Install it with: brew install fzf"
    exit 1
fi

clear

declare provider_color

selection="$(
    printf '%s\n' "$meta_raw" |
    sort -t $'\t' -k1,1rn |
    emit_rows |
    while IFS=$'\t' read -r provider mtime title id project workspace; do
        case "$provider" in
            Claude) provider_color="$ORANGE" ;;
            Codex)  provider_color="$BLUE" ;;
            Grok)   provider_color="$GREEN" ;;
            Cursor) provider_color="$LAVENDER" ;;
            *)      provider_color="$RESET" ;;
        esac

        # Pad each visible column to a fixed width so rows line up —
        # padding happens on the plain text before it's wrapped in
        # ANSI color codes, since color escapes would otherwise throw
        # off printf's width calculation.
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${provider_color}$(printf '%-8s' "$provider")${RESET}" \
            "$(printf '%-19s' "$(format_time "$mtime")")" \
            "$(printf '%-32s' "${project[1,32]}")" \
            "$title" \
            "$provider" \
            "$id" \
            "$workspace"
    done |
    fzf \
        --ansi \
        --delimiter=$'\t' \
        --with-nth=1,2,3,4 \
        --prompt="Resume> " \
        --height=35 \
        --layout=reverse \
        --header="$(printf '%-8s\t%-19s\t%-32s\tConversation' "Agent" "Time" "Project")" \
        --footer=$'↑↓ navigate  |  ENTER resume  |  ESC quit'
)"

[[ -n "$selection" ]] || exit 0

IFS=$'\t' read -r _ _ _ title provider session workspace <<< "$selection"

clear

if [[ -n "$HANDOFF_MODE" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is required for handoffs. Install it with: brew install jq" >&2
        exit 1
    fi

    transcript="$(session_transcript "$provider" "$session" "$workspace")"
    if [[ -z "$transcript" || ! -f "$transcript" ]]; then
        echo "Could not locate the readable transcript for this $provider session."
        exit 1
    fi

    agent_selection="$(handoff_agent_picker "$provider")"
    [[ -n "$agent_selection" ]] || exit 0
    IFS=$'\t' read -r destination destination_command <<< "$agent_selection"

    handoff_result="$(create_handoff_file "$HANDOFF_MODE" "$provider" "$title" "$transcript")"
    if [[ -z "$handoff_result" ]]; then
        echo "No transferable user/assistant text was found in this session."
        exit 1
    fi
    IFS=$'\t' read -r handoff_file estimate_tokens <<< "$handoff_result"

    if [[ "$HANDOFF_MODE" == "full" && "$estimate_tokens" -gt 50000 ]]; then
        confirm "Full handoff is approximately ${estimate_tokens} input tokens. Continue?" || {
            rm -f "$handoff_file"
            exit 0
        }
    fi

    source_cwd="$workspace"
    if [[ -z "$source_cwd" ]]; then
        source_cwd="$(grep -m1 -o '"cwd":"[^" ]\{0,250\}"' "$transcript" 2>/dev/null | sed -E 's/"cwd":"//;s/"$//')"
    fi
    [[ -d "$source_cwd" ]] && cd -- "$source_cwd"

    clear
    printf "%sHanding off to %s%s\n" "$BOLD" "$destination" "$RESET"
    printf "%s%s%s\n" "$DIM" "$title" "$RESET"
    printf "%sEstimated transferred context: ~%s tokens%s\n\n" "$DIM" "$estimate_tokens" "$RESET"

    handoff_prompt="Read the cross-agent conversation handoff at: ${handoff_file}

Use it as background context for this new session. Do not repeat the transcript. Briefly confirm that the handoff is loaded, state the current objective you inferred, and ask what I want to do next. After reading it, delete the temporary handoff file."

    case "$destination_command" in
        claude)       exec claude "$handoff_prompt" ;;
        codex)        exec codex "$handoff_prompt" ;;
        cursor-agent) exec cursor-agent "$handoff_prompt" ;;
        grok)         exec grok "$handoff_prompt" ;;
        *)
            rm -f "$handoff_file"
            echo "Unsupported destination command: $destination_command"
            exit 1
            ;;
    esac
fi

printf "%sResuming%s\n" "$BOLD" "$RESET"
printf "%s%s%s\n\n" "$DIM" "$title" "$RESET"

# ------------------------------------------------------------
# Launch correct agent
# ------------------------------------------------------------

case "$provider" in

    Claude)

        if ! command -v claude >/dev/null 2>&1; then
            echo "claude command not found."
            exit 1
        fi

        exec claude --resume "$session"
        ;;

    Codex)

        if ! command -v codex >/dev/null 2>&1; then
            echo "codex command not found."
            exit 1
        fi

        exec codex resume "$session"
        ;;

    Cursor)

        if ! command -v cursor-agent >/dev/null 2>&1; then
            echo "cursor-agent command not found."
            exit 1
        fi

        if [[ -n "$workspace" ]]; then
            exec cursor-agent --resume "$session" --workspace "$workspace"
        else
            exec cursor-agent --resume "$session"
        fi
        ;;

    Grok)

        if ! command -v grok >/dev/null 2>&1; then
            echo "grok command not found."
            exit 1
        fi

        if [[ -n "$workspace" ]]; then
            exec grok --resume "$session" --cwd "$workspace"
        else
            exec grok --resume "$session"
        fi
        ;;

esac
