# CLAUDE.md — CouchPotato WoW Addon Project

This file provides guidance to Claude Code, Copilot, and other agents when working with the CouchPotato addon project.

---

## Critical Rules

### Installation Rule
**After ANY changes to addon code, you MUST run the install script BEFORE reporting completion to the user.**

```bash
bash /Users/john/code/4JS/CouchPotato/install.sh
```

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

- Project root: `/Users/john/code/4JS/CouchPotato/`
- Install script: `/Users/john/code/4JS/CouchPotato/install.sh`
- README: `/Users/john/code/4JS/CouchPotato/README.md`
- Tests: `busted --output=plain spec/`
