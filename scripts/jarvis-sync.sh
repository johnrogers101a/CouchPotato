#!/usr/bin/env bash
# jarvis-sync — Azure-backed cross-machine context sync
# Syncs agent work, learnings, Claude config, and reports to Azure Blob Storage.
# All operations use --auth-mode login (no keys, no SAS tokens).
#
# Usage:
#   jarvis-sync pull    — download everything from Azure to local
#   jarvis-sync push    — upload everything from local to Azure
#   jarvis-sync sync    — pull then push (bi-directional)
#   jarvis-sync status  — show last sync time and container blob counts

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — adjust these variables if paths change
# ---------------------------------------------------------------------------
STORAGE_ACCOUNT="stjarviscontext001"

# Local paths
CLAUDE_CONFIG_DIR="/Users/john/.claude"
AGENT_WORK_DIR="/Users/john/code/4JS/CouchPotato/.agent-work"
GDRIVE_REPORTS_DIR="/Users/john/Library/CloudStorage/GoogleDrive-go.hawks.2007@gmail.com/My Drive/Reports"

# Derived paths
LEARNINGS_FILE="${AGENT_WORK_DIR}/learnings.md"
RESEARCH_DIR="${AGENT_WORK_DIR}/research"
LOGS_DIR="${AGENT_WORK_DIR}/logs"
REPORTS_DIR="${AGENT_WORK_DIR}/reports"

# Azure containers
CONTAINER_CONFIG="claude-config"
CONTAINER_LEARNINGS="claude-learnings"
CONTAINER_STATUS="claude-status"
CONTAINER_REPORTS="claude-reports"
CONTAINER_DIRECTIVES="claude-directives"

# Status file for last-sync tracking
STATUS_FILE="${AGENT_WORK_DIR}/.last-sync"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() { echo "[jarvis-sync] $*"; }
err() { echo "[jarvis-sync] ERROR: $*" >&2; }

preflight() {
    if ! az account show &>/dev/null; then
        err "Not logged in to Azure CLI. Please run 'az login'."
        exit 1
    fi
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log "Created directory: $dir"
    fi
}

# Upload a single file to a container with a given blob name
upload_file() {
    local file="$1"
    local container="$2"
    local blob_name="$3"
    if [[ -f "$file" ]]; then
        az storage blob upload \
            --account-name "$STORAGE_ACCOUNT" \
            --container-name "$container" \
            --name "$blob_name" \
            --file "$file" \
            --overwrite \
            --auth-mode login \
            --output none 2>&1
        log "  uploaded: $blob_name -> $container"
    fi
}

# Upload a directory to a container using batch upload
upload_dir() {
    local src="$1"
    local container="$2"
    local prefix="${3:-}"
    if [[ -d "$src" ]] && [[ -n "$(ls -A "$src" 2>/dev/null)" ]]; then
        local args=(
            --account-name "$STORAGE_ACCOUNT"
            --destination "$container"
            --source "$src"
            --overwrite
            --auth-mode login
            --output none
        )
        if [[ -n "$prefix" ]]; then
            args+=(--destination-path "$prefix")
        fi
        az storage blob upload-batch "${args[@]}" 2>&1
        log "  uploaded dir: $src -> $container/${prefix:-}"
    else
        log "  skipped (empty or missing): $src"
    fi
}

# Download a container (or prefix) to a local directory
download_container() {
    local container="$1"
    local dest="$2"
    local prefix="${3:-}"
    ensure_dir "$dest"
    local args=(
        --account-name "$STORAGE_ACCOUNT"
        --source "$container"
        --destination "$dest"
        --overwrite
        --auth-mode login
        --output none
    )
    if [[ -n "$prefix" ]]; then
        args+=(--pattern "${prefix}*")
    fi
    az storage blob download-batch "${args[@]}" 2>&1
    log "  downloaded: $container/${prefix:-} -> $dest"
}

# ---------------------------------------------------------------------------
# Push — local to Azure
# ---------------------------------------------------------------------------
do_push() {
    log "=== PUSH: local -> Azure ==="

    # claude-config: entire ~/.claude/ directory
    upload_dir "$CLAUDE_CONFIG_DIR" "$CONTAINER_CONFIG"

    # claude-learnings: learnings.md + research/
    if [[ -f "$LEARNINGS_FILE" ]]; then
        upload_file "$LEARNINGS_FILE" "$CONTAINER_LEARNINGS" "learnings.md"
    fi
    upload_dir "$RESEARCH_DIR" "$CONTAINER_LEARNINGS" "research"

    # claude-status: .agent-work/logs/
    upload_dir "$LOGS_DIR" "$CONTAINER_STATUS"

    # claude-reports: .agent-work/reports/ + Google Drive Reports/
    upload_dir "$REPORTS_DIR" "$CONTAINER_REPORTS" "agent-work"
    if [[ -d "$GDRIVE_REPORTS_DIR" ]]; then
        upload_dir "$GDRIVE_REPORTS_DIR" "$CONTAINER_REPORTS" "gdrive"
    else
        log "  skipped (not mounted): $GDRIVE_REPORTS_DIR"
    fi

    # claude-directives: anything in ~/.claude/.team-installer/
    local directives_dir="${CLAUDE_CONFIG_DIR}/.team-installer"
    upload_dir "$directives_dir" "$CONTAINER_DIRECTIVES"

    record_sync "push"
    log "=== PUSH complete ==="
}

# ---------------------------------------------------------------------------
# Pull — Azure to local
# ---------------------------------------------------------------------------
do_pull() {
    log "=== PULL: Azure -> local ==="

    # Fix read-only git objects that block overwrites.
    # ~/.claude/plugins/ may contain git repos whose pack objects are mode 444;
    # az storage blob download-batch cannot overwrite them under set -euo pipefail.
    # Note: macOS find(1) does not support -writable; use -perm -u+w instead.
    find "$CLAUDE_CONFIG_DIR" -path '*/.git/objects/*' -type f ! -perm -u+w \
        -exec chmod u+w {} + 2>/dev/null || true

    # claude-config -> ~/.claude/
    # Note: az storage blob download-batch has no --exclude-path flag.
    # Syncing .git/ internals across machines is risky (pack objects are
    # machine-specific and break cross-machine checkouts), but there is no
    # supported way to exclude a path prefix with download-batch --pattern.
    # The chmod guard above ensures read-only objects don't abort the sync.
    download_container "$CONTAINER_CONFIG" "$CLAUDE_CONFIG_DIR"

    # claude-learnings -> .agent-work/ (learnings.md at root, research/ subdir)
    ensure_dir "$AGENT_WORK_DIR"
    # Download learnings.md directly
    az storage blob download \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER_LEARNINGS" \
        --name "learnings.md" \
        --file "$LEARNINGS_FILE" \
        --overwrite \
        --auth-mode login \
        --output none 2>&1 || log "  learnings.md not found in Azure (skipped)"
    # Download research/ subdir
    download_container "$CONTAINER_LEARNINGS" "$RESEARCH_DIR" "research/"

    # claude-status -> .agent-work/logs/
    download_container "$CONTAINER_STATUS" "$LOGS_DIR"

    # claude-reports -> .agent-work/reports/ and Google Drive
    download_container "$CONTAINER_REPORTS" "$REPORTS_DIR" "agent-work/"
    if [[ -d "$(dirname "$GDRIVE_REPORTS_DIR")" ]]; then
        ensure_dir "$GDRIVE_REPORTS_DIR"
        download_container "$CONTAINER_REPORTS" "$GDRIVE_REPORTS_DIR" "gdrive/"
    else
        log "  skipped Google Drive pull (not mounted)"
    fi

    # claude-directives -> ~/.claude/.team-installer/
    local directives_dir="${CLAUDE_CONFIG_DIR}/.team-installer"
    download_container "$CONTAINER_DIRECTIVES" "$directives_dir"

    record_sync "pull"
    log "=== PULL complete ==="
}

# ---------------------------------------------------------------------------
# Sync — bi-directional (pull then push)
# ---------------------------------------------------------------------------
do_sync() {
    log "=== SYNC: bi-directional ==="
    do_pull
    do_push
    log "=== SYNC complete ==="
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
do_status() {
    log "=== STATUS ==="
    if [[ -f "$STATUS_FILE" ]]; then
        echo "Last sync:"
        cat "$STATUS_FILE"
        echo ""
    else
        echo "No sync recorded yet."
    fi

    echo "Blob counts per container:"
    for container in "$CONTAINER_CONFIG" "$CONTAINER_LEARNINGS" "$CONTAINER_STATUS" "$CONTAINER_REPORTS" "$CONTAINER_DIRECTIVES"; do
        local count
        count=$(az storage blob list \
            --account-name "$STORAGE_ACCOUNT" \
            --container-name "$container" \
            --auth-mode login \
            --query "length(@)" \
            --output tsv 2>/dev/null || echo "error")
        printf "  %-22s %s blobs\n" "$container" "$count"
    done
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
record_sync() {
    local op="$1"
    ensure_dir "$AGENT_WORK_DIR"
    {
        echo "operation: $op"
        echo "timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "hostname:  $(hostname)"
        echo "user:      $(whoami)"
    } > "$STATUS_FILE"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
preflight

COMMAND="${1:-help}"
case "$COMMAND" in
    push)   do_push ;;
    pull)   do_pull ;;
    sync)   do_sync ;;
    status) do_status ;;
    *)
        echo "Usage: jarvis-sync <push|pull|sync|status>"
        echo ""
        echo "  push    Upload local context to Azure Blob Storage"
        echo "  pull    Download context from Azure Blob Storage to local"
        echo "  sync    Pull then push (bi-directional)"
        echo "  status  Show last sync time and blob counts"
        exit 1
        ;;
esac
