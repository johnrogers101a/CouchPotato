# Changelog

All notable changes to ControllerCompanion will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **InfoPanels** — New data-driven information panel engine replacing StatPriority, DelveCompanionStats, and DelversJourney
- In-game graphical editor (`/ip editor`) for creating custom panels with searchable data sources and live preview
- Profile string import/export for sharing panel configurations between players
- Discord bot (`discord-bot/`) for generating InfoPanels import strings from natural-language descriptions via Claude Sonnet 4.6
- Shared UI framework (UIFramework.lua) eliminating duplicated scaffolding code across panels

### Changed
- CouchPotato config window updated: replaced per-addon checkboxes with unified InfoPanels management
- Install scripts updated for new addon structure (CouchPotato, ControllerCompanion, ControllerCompanion_Loader, InfoPanels)

### Removed
- **StatPriority** addon — functionality now built into InfoPanels
- **DelveCompanionStats** addon — functionality now built into InfoPanels
- **DelversJourney** addon — functionality now built into InfoPanels
- **CouchPotatoDiag** addon — diagnostic data capture folded into CouchPotatoLog debug logging
- `/cpdiag` slash command removed entirely

## [1.0.1] - 2026-03-18

### Fixed
- DelveCompanionStats: Fixed companion name display bug — replaced incorrect `C_Reputation.GetFactionDataByID()` call (which returns faction name "Friendship" instead of companion display names) with hardcoded companion name lookup table keyed by companion ID
- DelveCompanionStats: Corrected `C_DelvesUI.GetFactionForCompanion()` call to pass actual companion ID instead of `nil`
- DelveCompanionStats: Added Waxmonger Squick (ID 3) to companion names table; shifted Turalyon to ID 4 and Thisalee Crow to ID 5
- DelveCompanionStats: Fixed frame position anchor — replaced `TOPLEFT/UIParent` with `BOTTOMLEFT/ChatFrame1` fallback to prevent frame rendering off-screen
- DelveCompanionStats: Fixed frame visibility — set frame strata to `MEDIUM`, level to 100, and explicitly called `Show()` on the fontstring after text assignment
- DelveCompanionStats: Fixed text color — companion name and renown text now rendered in white (`1, 1, 1`) for legibility on all backgrounds
- DelveCompanionStats: Eliminated race condition — added nil-guards and `pcall` safety wrapping around API calls that could fire before companion data is available
- DelveCompanionStats: Fixed Lua 5.1 compatibility — replaced WoW-only bitwise operators with a pure Lua fallback and `loadstring`-based `bit` library detection for CI/test environments

### Added
- GitHub Actions CI workflow: automated Busted unit tests + Luacheck static analysis on every push and pull request
- install.ps1: auto-discovery of WoW Retail AddOns folder via filesystem search; no longer requires manual path configuration
- DelveCompanionStats: new standalone addon scaffold with `.toc`, `Core.lua`, and `IconTexture` support for companion portrait display
- DelveCompanionStats: live companion data via `C_DelvesUI` API; registers `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `UPDATE_FACTION`, and `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` events for real-time updates
- DelveCompanionStats: `SavedVariables` persistence for companion data caching across sessions

### Technical
- All 132 tests passing; 0 luacheck warnings
- Companion display names are now correctly retrieved via static lookup (no API available for this in WoW 12.0.x)
- Faction ID for reputation lookups is correctly retrieved via `C_DelvesUI.GetFactionForCompanion(companionID)` instead of `nil`
- CI/CD pipeline: GitHub Actions + Busted + Luacheck — all checks green on merge
- Lua 5.1 bitwise operations use pure Lua fallback for CI/test environment compatibility (WoW client uses LuaJIT with `bit` library)

## [1.0.0] - 2026-03-01

### Added
- Initial release
- Two-component loader/UI architecture
  - ControllerCompanion_Loader: Always-on gamepad detection
  - ControllerCompanion: Load-on-demand full UI
- BG3-inspired radial action wheels (8 wheels × 12 slots)
- L1/R1 wheel cycling during gameplay
- Peek vs lock trigger behavior
  - Light trigger pull (35%) peeks at radial
  - Full trigger pull (75%) locks radial open
- DualSense LED color by spell school
- Haptic feedback on combat events
  - Critical hits
  - Low health warning
  - Ability ready notifications
- Heal mode with party frame overlay
- Virtual cursor (D-pad navigation)
- 39 spec ability layouts included
- Ace3 framework integration
  - AceAddon-3.0 lifecycle management
  - AceDB-3.0 profile system
  - AceEvent-3.0 event handling
  - AceConsole-3.0 slash commands
  - AceTimer-3.0 timer utilities
- Busted test suite for CI/CD

### Fixed
- Specs.lua: Use idiomatic `select(1, UnitClass())` pattern for first return value
- HealMode.lua: Fix call to non-existent `ClearHealModeBindings()` → `ClearControllerBindings()`
- Diagnostics.lua: Cache probeOwner frame to prevent accumulation on repeated `/cp test` calls
- ControllerCompanion.toc: Add explicit `SavedVariablesPerCharacter: ControllerCompanionDB` declaration

### Technical
- Interface version: 120001 (WoW Patch 12.0.1 Midnight)
- SetOverrideBinding for safe keyboard restoration
- Pre-created SecureActionButton pool for combat lockdown compliance
- Per-character wheel layouts via AceDB char scope
