# CLAUDE.md — CouchPotato WoW Addon Project

This file provides guidance to Claude Code, Copilot, and other agents when working with the CouchPotato addon project.

---

## Critical Rules

### Incremental Approach Rule (MANDATORY FOR ALL WORK)
**ALWAYS use an incremental approach — break work into small chunks/phases. ALWAYS check for user buy-in and agreement at each step before proceeding to the next.**

This is not optional. Every task, every project, every piece of work must follow this pattern:
1. Propose the next chunk of work (small, focused, deliverable)
2. Get user buy-in and agreement before starting
3. Complete the chunk
4. Report outcome
5. Return to step 1 for the next chunk

Do not build everything at once. Do not assume agreement. Do not skip ahead.

---

### WoW Addon Debug Log Rule (MANDATORY FOR ALL OUTPUT)
**ALL output from WoW addons (debug info, validation results, diagnostics, any text the user needs to read or copy) MUST be written to the debug log (CouchPotatoLog / debug window), NOT just to chat.**

The user cannot copy/paste from chat. They need output in the debug log window to be able to access and share it. This is non-negotiable.

---

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

- **CouchPotato** — Core shared configuration hub, error logger, minimap button
- **ControllerCompanion_Loader** — Lightweight gamepad detection and auto-loader
- **ControllerCompanion** — Full radial UI and controller support (load-on-demand)
- **InfoPanels** — Data-driven information panel engine with graphical editor

---

## Quick Reference

- Project root: `/Users/john/code/4JS/CouchPotato/`
- Install script: `/Users/john/code/4JS/CouchPotato/install.sh`
- README: `/Users/john/code/4JS/CouchPotato/README.md`
- Tests: In-game via `/ip test` (see InfoPanels/Core/InGameTests.lua)
- Discord bot: `discord-bot/` (standalone Node.js application)
