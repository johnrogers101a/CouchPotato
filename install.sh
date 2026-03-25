#!/usr/bin/env bash
# install.sh — macOS installer for CouchPotato WoW addons
# Installs all addons in this repo into the WoW Retail Interface/AddOns folder.
# Performs a CLEAN install: removes the destination addon directory before
# copying, so stale files from previously-installed-but-now-removed addons
# cannot persist and cause load failures.
#
# Usage:
#   ./install.sh [/path/to/WoW/_retail_/Interface/AddOns]
#
# If no path is given the script probes the standard macOS install location.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ADDON_NAMES=(
    CouchPotato
    CouchPotatoDiag
    ControllerCompanion
    ControllerCompanion_Loader
    DelveCompanionStats
    DelversJourney
    StatPriority
)

# ---------------------------------------------------------------------------
# Locate AddOns folder
# ---------------------------------------------------------------------------

find_addons_path() {
    # Standard macOS Blizzard install location
    local standard="/Applications/World of Warcraft/_retail_/Interface/AddOns"
    if [[ -d "$standard" ]]; then
        echo "$standard"
        return
    fi

    # Home directory installs
    local home_path="$HOME/Applications/World of Warcraft/_retail_/Interface/AddOns"
    if [[ -d "$home_path" ]]; then
        echo "$home_path"
        return
    fi

    echo ""
}

if [[ "${1:-}" != "" ]]; then
    ADDONS_PATH="$1"
else
    ADDONS_PATH="$(find_addons_path)"
fi

if [[ -z "$ADDONS_PATH" || ! -d "$ADDONS_PATH" ]]; then
    echo "ERROR: Could not find WoW Retail AddOns folder." >&2
    echo "Usage: $0 [/path/to/_retail_/Interface/AddOns]" >&2
    exit 1
fi

# Validate write access
touch "$ADDONS_PATH/.install_probe" 2>/dev/null || {
    echo "ERROR: '$ADDONS_PATH' is not writable. Check permissions." >&2
    exit 1
}
rm -f "$ADDONS_PATH/.install_probe"

echo "Installing to: $ADDONS_PATH"
echo ""

# ---------------------------------------------------------------------------
# Clean-install each addon
# ---------------------------------------------------------------------------

INSTALLED=()

for ADDON in "${ADDON_NAMES[@]}"; do
    SRC="$SCRIPT_DIR/$ADDON"

    if [[ ! -d "$SRC" ]]; then
        echo "WARNING: Source folder './$ADDON' not found — skipping."
        continue
    fi

    DEST="$ADDONS_PATH/$ADDON"

    # Remove stale destination so no old files survive a rename or move
    if [[ -d "$DEST" ]]; then
        rm -rf "$DEST"
    fi

    cp -R "$SRC" "$DEST"
    INSTALLED+=("$ADDON")
    echo "  [OK] $ADDON"
done

# ---------------------------------------------------------------------------
# Remove any installed addons that no longer exist in source
# ---------------------------------------------------------------------------

KNOWN_ADDONS=("${ADDON_NAMES[@]}")

for INSTALLED_DIR in "$ADDONS_PATH"/CouchPotato* "$ADDONS_PATH"/ControllerCompanion* \
                     "$ADDONS_PATH"/DelveCompanion* "$ADDONS_PATH"/DelversJourney* \
                     "$ADDONS_PATH"/StatPriority*; do
    [[ -d "$INSTALLED_DIR" ]] || continue
    BASENAME="$(basename "$INSTALLED_DIR")"
    FOUND=0
    for KNOWN in "${KNOWN_ADDONS[@]}"; do
        if [[ "$KNOWN" == "$BASENAME" ]]; then
            FOUND=1
            break
        fi
    done
    if [[ $FOUND -eq 0 ]]; then
        echo "  [REMOVED stale] $BASENAME"
        rm -rf "$INSTALLED_DIR"
    fi
done

echo ""
if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    echo "Installation complete. ${#INSTALLED[@]} addon(s) installed."
else
    echo "No addons were installed (all source folders were missing)."
fi
