# CouchPotato

**BG3-inspired radial controller UI for World of Warcraft**

Play WoW with a gamepad using intuitive radial menus, just like Baldur's Gate 3. CouchPotato transforms your controller into a powerful interface with peek-and-lock trigger behavior, haptic feedback, DualSense LED integration, and intelligent heal mode targeting.

## Features

- **Radial Action Wheels** — 8 wheels × 12 slots for abilities, items, mounts, and macros
- **L1/R1 Wheel Cycling** — Quick switching between wheels during combat
- **Peek vs Lock Triggers** — Light trigger pull peeks at the radial; full pull locks it open
- **DualSense LED Colors** — Controller LED changes color based on spell school
- **Haptic Feedback** — Rumble on combat events (crits, low health, ability ready)
- **Heal Mode** — Party frame overlay with D-pad target cycling
- **Virtual Cursor** — D-pad navigation when radial is hidden
- **39 Spec Layouts** — Pre-configured ability layouts for all classes/specs

## Architecture

CouchPotato uses a two-component loader system:

| Component | Purpose |
|-----------|---------|
| **CouchPotato_Loader** | Always enabled. Lightweight gamepad detection (~150 lines). Automatically loads the main addon when a controller is detected. |
| **CouchPotato** | Load-on-demand. Full radial UI, Ace3-based. Only loads when you're actually using a controller. |

This design keeps WoW's memory footprint minimal for keyboard/mouse players while providing full controller support on demand.

## Installation

### CurseForge / WoWUp
1. Search for "CouchPotato" in your addon manager
2. Install and enable **both** CouchPotato Loader and CouchPotato

### Manual Installation
1. Download the latest release from [Releases](../../releases)
2. Extract both `CouchPotato_Loader/` and `CouchPotato/` folders to your `Interface/AddOns/` directory
3. Ensure **CouchPotato Loader** is enabled (CouchPotato will be loaded automatically)

## Quick Start

1. Enable the CouchPotato Loader addon
2. Connect your controller and ensure WoW recognizes it (check System > Controls > Enable Controller)
3. The loader will automatically detect your gamepad and load the full UI
4. Press **L2** or **R2** (triggers) to open the radial menu
5. Use **L1/R1** to cycle between wheels
6. Configure layouts via `/cp config` (coming soon)

## Slash Commands

| Command | Description |
|---------|-------------|
| `/cp` | Show help |
| `/cp show` | Show the radial UI |
| `/cp hide` | Hide the radial UI |
| `/cp status` | Show addon status |
| `/cp reload` | Reload the UI |
| `/cp reset` | Reset profile to defaults |
| `/cp debug` | Toggle debug mode |

## Requirements

- **World of Warcraft**: Patch 12.0.1 (Midnight) or later
- **Interface Version**: 120001
- **Controller**: Any XInput-compatible gamepad (Xbox, PlayStation, etc.)

## Development

### Prerequisites
- Lua 5.1 (WoW's Lua version)
- [Busted](https://olivinelabs.com/busted/) for running tests

### Running Tests
```bash
busted --output=plain spec/
```

### Project Structure
```
CouchPotato/
├── CouchPotato_Loader/     # Lightweight loader addon
│   ├── CouchPotato_Loader.toc
│   └── Loader.lua
├── CouchPotato/            # Main addon (load-on-demand)
│   ├── CouchPotato.toc
│   ├── CouchPotato.lua     # Ace3 entry point
│   ├── embeds.xml
│   ├── libs/               # Ace3 libraries
│   ├── Core/               # Core systems
│   └── UI/                 # UI components
└── spec/                   # Busted test suite
```

### Building for Release
The project uses BigWigs packager format (`.pkgmeta`). Real Ace3 libraries are pulled from WowAce repositories during packaging.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Credits

- [Ace3](https://www.wowace.com/projects/ace3) — addon framework
- Inspired by [Baldur's Gate 3](https://baldursgate3.game/)'s radial controller UI
- [Wow Lua Api](https://github.com/Gethe/wow-ui-source/tree/live)
