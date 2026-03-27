# CLAUDE.md — CouchPotato WoW Addon Project

This file provides guidance to Claude Code, Copilot, and other agents when working with the CouchPotato addon project.

---

## Critical Rules

### Installation Rule
**After ANY changes to addon code, you MUST run the install script BEFORE reporting completion to the user.**

```bash
bash install.sh
```

Run from the project root. The script auto-detects the OS and uses the correct WoW AddOns path.

- This applies to all code modifications: bug fixes, features, refactors, configuration changes.
- Running the install script validates the addon structure and copies files to WoW's AddOns folder.
- **Never tell the user a fix is done without installing it first.**
- Only after successful install completion should you report the task as finished.

---

## Addons in This Project

- **ControllerCompanion_Loader** — Lightweight gamepad detection and auto-loader
- **ControllerCompanion** — Full radial UI and controller support (load-on-demand)
- **DelveCompanionStats** — Companion stat tracking utility (in development)

---

## Quick Reference

### Project Paths

| Item | macOS | Windows |
|---|---|---|
| Project root | `~/code/4JS/CouchPotato/` | `C:\Users\johnr\Code\4JS\CouchPotato\` |
| Install script | `~/code/4JS/CouchPotato/install.sh` | `C:\Users\johnr\Code\4JS\CouchPotato\install.sh` |
| WoW AddOns | `/Applications/World of Warcraft/_retail_/Interface/AddOns` | `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns` |
| README | `~/code/4JS/CouchPotato/README.md` | `C:\Users\johnr\Code\4JS\CouchPotato\README.md` |

- Tests: `busted --output=plain spec/`
