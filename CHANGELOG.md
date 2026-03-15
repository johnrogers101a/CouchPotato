# Changelog

All notable changes to CouchPotato will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-01

### Added
- Initial release
- Two-component loader/UI architecture
  - CouchPotato_Loader: Always-on gamepad detection
  - CouchPotato: Load-on-demand full UI
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
- CouchPotato.toc: Add explicit `SavedVariables_Per_Character: CouchPotatoDB` declaration

### Technical
- Interface version: 120001 (WoW Patch 12.0.1 Midnight)
- SetOverrideBinding for safe keyboard restoration
- Pre-created SecureActionButton pool for combat lockdown compliance
- Per-character wheel layouts via AceDB char scope
