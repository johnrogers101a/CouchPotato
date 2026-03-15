# Couch Potato

*A collection of controller-friendly World of Warcraft addons.*

Couch Potato is a suite of WoW addons built for players who prefer gaming from the couch. The project focuses on seamless controller support, companion utilities, and intuitive interfaces that make WoW playable and enjoyable without a keyboard and mouse.

## Addons

| Addon | Purpose |
|-------|---------|
| **ControllerCompanion** | BG3-inspired radial controller UI — dual-component system (loader + full UI) for efficient, load-on-demand gamepad support. |
| **DelveCompanionStats** | Companion stat tracking and display utility *(In Development)*. |

---

## ControllerCompanion

**BG3-inspired radial controller UI for World of Warcraft**

Play WoW with a gamepad using intuitive radial menus, just like Baldur's Gate 3. ControllerCompanion transforms your controller into a powerful interface with peek-and-lock trigger behavior, haptic feedback, DualSense LED integration, and intelligent heal mode targeting.

### Features

- **Radial Action Wheels** — 8 wheels × 12 slots for abilities, items, mounts, and macros
- **L1/R1 Wheel Cycling** — Quick switching between wheels during combat
- **Peek vs Lock Triggers** — Light trigger pull peeks at the radial; full pull locks it open
- **DualSense LED Colors** — Controller LED changes color based on spell school
- **Haptic Feedback** — Rumble on combat events (crits, low health, ability ready)
- **Heal Mode** — Party frame overlay with D-pad target cycling
- **Virtual Cursor** — D-pad navigation when radial is hidden
- **39 Spec Layouts** — Pre-configured ability layouts for all classes/specs

### Architecture

ControllerCompanion uses a two-component loader system:

| Component | Purpose |
|-----------|---------|
| **ControllerCompanion_Loader** | Always enabled. Lightweight gamepad detection (~150 lines). Automatically loads the main addon when a controller is detected. |
| **ControllerCompanion** | Load-on-demand. Full radial UI, Ace3-based. Only loads when you're actually using a controller. |

This design keeps WoW's memory footprint minimal for keyboard/mouse players while providing full controller support on demand.

### Installation

#### Automated Installation (Windows)

Run the included PowerShell script to automatically detect your WoW installation and copy all addons:

```powershell
# From the repo root in PowerShell:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

The script will:
- Automatically locate your WoW Retail installation
- Copy **ControllerCompanion**, **ControllerCompanion_Loader**, and **DelveCompanionStats** to your `Interface/AddOns/` folder
- Prompt you for your WoW path if it cannot be found automatically

#### Manual Installation

1. Download the latest release from [Releases](../../releases)
2. Extract the `ControllerCompanion_Loader/`, `ControllerCompanion/`, and `DelveCompanionStats/` folders to your `Interface/AddOns/` directory
3. Ensure **ControllerCompanion Loader** is enabled (ControllerCompanion will be loaded automatically)

### Quick Start

1. Enable the ControllerCompanion Loader addon
2. Connect your controller and ensure WoW recognizes it (check System > Controls > Enable Controller)
3. The loader will automatically detect your gamepad and load the full UI
4. Press **L2** or **R2** (triggers) to open the radial menu
5. Use **L1/R1** to cycle between wheels
6. Configure layouts via `/cp config` (coming soon)

### Slash Commands

| Command | Description |
|---------|-------------|
| `/cp` | Show help |
| `/cp show` | Show the radial UI |
| `/cp hide` | Hide the radial UI |
| `/cp status` | Show addon status |
| `/cp reload` | Reload the UI |
| `/cp reset` | Reset profile to defaults |
| `/cp debug` | Toggle debug mode |

### Requirements

- **World of Warcraft**: Patch 12.0.1 (Midnight) or later
- **Interface Version**: 120001
- **Controller**: Any XInput-compatible gamepad (Xbox, PlayStation, etc.)

---

## DelveCompanionStats *(In Development)*

**Companion stat tracking and display utility for World of Warcraft**

DelveCompanionStats is a lightweight addon designed to track and surface companion statistics during Delve content.

*Planned features:*
- Companion level tracking
- Display panel above chat window
- SavedVariables persistence

> **Note:** Core functionality is not yet implemented. See [CHANGELOG.md](CHANGELOG.md) for status.

---

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
ControllerCompanion/
├── ControllerCompanion_Loader/     # Lightweight loader addon
│   ├── ControllerCompanion_Loader.toc
│   └── Loader.lua
├── ControllerCompanion/            # Main addon (load-on-demand)
│   ├── ControllerCompanion.toc
│   ├── ControllerCompanion.lua     # Ace3 entry point
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
