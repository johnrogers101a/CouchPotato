# Project Context

- **Owner:** John Rogers
- **Project:** CouchPotato — a WoW addon that detects gamepad input and dynamically loads a BG3-style radial-wheel controller UI
- **Stack:** Lua, WoW Addon API (TOC, XML, C_GamePad, frame/widget system, SecureHandlerTemplate)
- **Created:** 2026-03-01

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-03-01: Foundation Scaffolding Complete

**Architecture Decisions Made:**
1. Two-component system: CouchPotato_Loader (always-on) + CouchPotato (LoadOnDemand)
2. Ace3 framework for lifecycle, DB profiles, events, console, timers
3. Functional lib stubs in repo for testing + .pkgmeta externals for production
4. SetOverrideBinding exclusively (never SetBinding) for keyboard restore on disconnect
5. Pre-create all 96 SecureActionButtons at load time (combat lockdown compliance)
6. Per-character wheel layouts via AceDB char scope
7. Module system via AceAddon:NewModule for clean separation

**File Structure Created:**
- CouchPotato_Loader/CouchPotato_Loader.toc
- CouchPotato/CouchPotato.toc, CouchPotato.lua, embeds.xml
- CouchPotato/libs/ with LibStub (real) + 5 Ace3 functional stubs
- CouchPotato/Core/ and CouchPotato/UI/ directories (for other agents)
- spec/ directory (for Zoe's tests)
- .pkgmeta, README.md, CHANGELOG.md

**Lib Stub Approach:**
- Real LibStub.lua (~40 lines, MIT licensed)
- Functional AceAddon, AceDB, AceEvent, AceConsole, AceTimer stubs
- Each stub has clear "STUB: Replace with real X for production" header
- Stubs implement core API surface needed for development and testing
- BigWigs packager replaces with real libs via .pkgmeta externals
