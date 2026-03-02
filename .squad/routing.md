# Work Routing

How to decide who handles what for CouchPotato.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|---------|
| Addon architecture, scope decisions, trade-offs | Mal | Two-component addon design, API policy decisions, combat lockdown strategy |
| Core Lua logic, C_GamePad API, event handling | Wash | Gamepad detection, dynamic addon loading, keybind logic, backend systems |
| WoW frame/widget UI, radial menu, visual layouts | Kaylee | Radial wheel frames, controller HUD, XML layout, texture/art integration |
| Code review, PR review, quality gate | Mal | Review PRs, check quality, enforce WoW addon best practices |
| Testing, edge cases, combat-lockdown regression | Zoe | Write test scenarios, verify gamepad detection edge cases, taint-free checks |
| Session logging | Scribe | Automatic — never needs routing |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:{member}` label | Mal |
| `squad:mal` | Pick up issue and complete the work | Mal |
| `squad:wash` | Pick up issue and complete the work | Wash |
| `squad:kaylee` | Pick up issue and complete the work | Kaylee |
| `squad:zoe` | Pick up issue and complete the work | Zoe |

## Rules

1. **Eager by default** — spawn all agents who could usefully start work, including anticipatory downstream work.
2. **Scribe always runs** after substantial work, always as `mode: "background"`. Never blocks.
3. **Quick facts → coordinator answers directly.** Don't spawn an agent for "what WoW patch are we targeting?"
4. **"Team, ..." → fan-out.** Spawn all relevant agents in parallel as `mode: "background"`.
5. **Lua + UI work is often paired** — when Wash writes backend logic, Kaylee should start on the UI side simultaneously.
6. **Anticipate downstream work** — if a feature is being built, spawn Zoe to write test scenarios from requirements simultaneously.
7. **Combat lockdown questions always go to Mal first** — taint and lockdown issues are architectural.
