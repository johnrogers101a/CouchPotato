# Couch Potato

A suite of World of Warcraft addons for delve tracking, stat priorities, and controller support — all manageable from a single settings hub.

![Couch Potato in a Delve](docs/images/couch-potato-in-delve.png)

## Addons

### CouchPotato (Core)

Shared configuration hub and error logger for the entire suite. Adds a minimap button that opens the Couch Potato Settings panel, where you can toggle visibility of each addon, view error and debug logs, and export configuration data.

![Couch Potato Settings](docs/images/couch-potato-settings.png)

### Delve Companion Stats

Displays your delve companion's details while inside a delve:

- **Companion name and level** with XP progress
- **Curios** — Combat and Utility curios currently active
- **Boons** — Active boons for the run
- **Enemy Groups Remaining** — How many groups are left in the delve

Docks alongside the objective tracker for an integrated, Blizzard-style appearance.

### Delver's Journey

Tracks your Delver's Journey season rank and XP progress. Shows your current season, rank, and exact XP toward the next rank. Docks below the objective tracker.

### Stat Priority

Displays stat priority weights for your current specialization as a compact bar (e.g., Int, Mastery, Haste, Crit, Vers with percentage weights). Supports a **Display Spec** override — view priorities for your loot spec or any specific spec, not just your active one. Configurable from the Couch Potato Settings panel.

### Controller Companion

BG3-inspired radial controller UI for World of Warcraft. Uses a two-component loader system:

- **ControllerCompanion_Loader** — Always enabled, lightweight gamepad detection. Automatically loads the main addon when a controller is detected.
- **ControllerCompanion** — Load-on-demand. Full radial UI with action wheels, trigger peek/lock behavior, DualSense LED integration, haptic feedback, heal mode, and virtual cursor.

This keeps WoW's memory footprint minimal for keyboard/mouse players while providing full controller support on demand.

---

## Installation

### Using the Install Script (macOS, Windows, WSL)

Run the included shell script to install all addons automatically:

```bash
bash install.sh
```

The script auto-detects your OS via `uname -s` and uses the correct WoW AddOns path for your platform:

| Platform | WoW AddOns path |
|---|---|
| macOS | `/Applications/World of Warcraft/_retail_/Interface/AddOns` |
| Windows (Git Bash) | `/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns` |
| WSL | `/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns` |

The script performs a clean install — removes stale files and copies all suite addons.

### Manual Installation

1. Locate your WoW Retail AddOns folder:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
2. Copy each of these folders from the project into your AddOns directory:
   - `CouchPotato/`
   - `ControllerCompanion/`
   - `ControllerCompanion_Loader/`
   - `DelveCompanionStats/`
   - `DelversJourney/`
   - `StatPriority/`
3. Restart WoW or type `/reload` in chat.
4. Ensure all addons are enabled in the AddOns menu on the character select screen.
