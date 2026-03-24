#!/usr/bin/env bash
# jarvis-sync-watch — watches synced directories and auto-pushes on change
# Debounce: waits 5 seconds after the last detected change before pushing.
#
# This script is intended to be run by launchd (see com.jarvis.sync-watch.plist)
# or manually in a terminal for testing.

set -euo pipefail

JARVIS_SYNC="/Users/john/.local/bin/jarvis-sync"
DEBOUNCE_SECONDS=5

# Directories to watch (space-separated)
WATCH_DIRS=(
    "/Users/john/.claude"
    "/Users/john/code/4JS/CouchPotato/.agent-work"
)

# Google Drive may not always be mounted; add only if present
GDRIVE_REPORTS="/Users/john/Library/CloudStorage/GoogleDrive-go.hawks.2007@gmail.com/My Drive/Reports"
if [[ -d "$GDRIVE_REPORTS" ]]; then
    WATCH_DIRS+=("$GDRIVE_REPORTS")
fi

log() { echo "[jarvis-watch] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"; }

log "Starting watcher. Debounce: ${DEBOUNCE_SECONDS}s"
log "Watching: ${WATCH_DIRS[*]}"

TIMER_PID=""

trigger_push() {
    log "Change detected — waiting ${DEBOUNCE_SECONDS}s for quiet..."
    # Kill any existing debounce timer
    if [[ -n "$TIMER_PID" ]] && kill -0 "$TIMER_PID" 2>/dev/null; then
        kill "$TIMER_PID" 2>/dev/null || true
    fi
    # Start new debounce timer in background
    (sleep "$DEBOUNCE_SECONDS" && log "Quiet period elapsed — pushing..." && "$JARVIS_SYNC" push && log "Push complete") &
    TIMER_PID=$!
}

# fswatch: -r recursive, -o one-event-per-batch, --event Updated|Created|Removed
fswatch -r -o \
    --event Updated --event Created --event Removed \
    "${WATCH_DIRS[@]}" | while read -r _count; do
    trigger_push
done
