# Claude Code prompts — Hunt Board revamp

Run one phase per session. Between phases: `/reload` in WoW and test the listed command.

## Prompt 1 — Widget foundation

Read HUNTBOARD_SPEC.md, media/README.md, and view mockups/preytracker_redesign_overlay.png.
Implement phase 1: create Widgets.lua with texture path constants for everything in media/
and factory helpers (CreateCard, CreatePill, CreateGlow, CreateIcon) using the nine-slice
margins from the README. Add it to the .toc after Config.lua, respecting the load-order rules
in CLAUDE.md. Add a `/prey test` command that spawns one sample card (viewport, zone glow,
platform, silhouette, status pill, reward icon, accept button) centered on screen so I can
verify all textures render correctly in-game.

**Verify in game:** `/reload`, then `/prey test` — every texture visible, rounded corners clean.

## Prompt 2 — Static Hunt Board

Read HUNTBOARD_SPEC.md and compare against mockups/preytracker_redesign_overlay.png.
Implement phase 2: HuntBoard.lua with the complete static layout — header, zone column
headers, rotated difficulty row labels (Nightmare top, Hard, Normal bottom), 4×3 card grid,
footer — anchored to cover CovenantMissionFrame, using fake 12-hunt data for now. Include one
card in each state: available, hovered, in-progress with mini meter, selected with violet
glow, and one empty cell. Add `/prey board` to toggle it standalone-centered when the map is
closed so I can iterate without opening the map.

**Verify in game:** `/prey board` — layout matches the mockup; also open the Prey map to check sizing over it.

## Prompt 3 — Data wiring

Implement phase 3 of HUNTBOARD_SPEC.md: replace the fake data in HuntBoard.lua with the real
pipeline (PH.liveHunts, PH.rewardCache, PH.IsInProgress, widget 7663, currency 3392), map
hunts into cells by (difficulty, zone), wire the accept flow exactly as UI.lua PopulateRow
does it, and handle the empty-cell state for missing hunts. Hook the board into Core.lua's
show/hide path so it appears after the loading overlay completes instead of the docked panel;
keep the old panel working for standalone mode. Don't break the watchdog or ForceHidePanel
paths.

**Verify in game:** open the Prey map — loading overlay, then the board with real hunts; accept one; close map; minimap button still opens the old standalone panel.

## Prompt 4 — Achievements + polish

Implement phase 4 of HUNTBOARD_SPEC.md: Achievements.lua that locates "Prey: Nightmare Mode
III" via the achievement API, matches criteria to hunt names, and drives the per-card
trophy/check chips and the footer progress bar with a remaining-criteria tooltip. Add the
Rescan button and scan-age text. Then update ARCHITECTURE.md (new files, the two new
fragility rows: achievement name-join, slice-texture API) and bump the version in the .toc.

**Verify in game:** trophy/check chips on Nightmare row match your achievement pane; footer count correct; Rescan refreshes the board.
