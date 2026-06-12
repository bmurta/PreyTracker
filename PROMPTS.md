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

## Prompt 5 — Out-of-map board, current-prey highlight, close/minimize

Read HUNTBOARD_SPEC.md, Core.lua, and HuntBoard.lua. Implement phase 5 — the Hunt Board
becomes the single experience everywhere:

1. Out-of-map mode: `/prey` and the minimap button now open the Hunt Board centered on
   screen instead of the old standalone panel, rendered from the last scan's cached hunts
   and reward cache. Accepting requires live map pins, so in this mode replace Accept
   buttons with a faint "Open the Prey map to accept" hint (and say so in the card
   tooltip). Keep the existing "no hunts recorded yet" empty state for characters that
   have never scanned. Keep `/prey panel` as a fallback that opens the old UI.lua panel.
2. Current-prey highlight: when a hunt is in progress, its card gets the strongest
   emphasis on the board — gold border plus the card_glow ring — and every other cell
   renders as a normal "available this week" card. Applies in both modes.
3. Map-open-after-accept: the board must also show when the player opens the Prey map
   while a hunt is already in progress (not only when choosing) — same board, current
   prey highlighted, mini meter live from widget 7663. Check Core.lua's show path
   doesn't skip the board when nothing is acceptable.
4. Close button: when the board is over the map, X closes both the board and the map via
   HideUIPanel(CovenantMissionFrame) — route it so it doesn't double-fire through the
   existing HideUIPanel hook and watchdog in Core.lua. Out of map, X just closes the board.
5. Minimize: add a minimize (–) button next to X, map mode only. It hides the overlay,
   revealing Blizzard's map underneath, and shows a small restore chip (the icon_prey
   crystal in media/, on a dark rounded pill with a red glow) pinned to the top-right of CovenantMissionFrame; clicking it
   restores the board. Persist the minimized choice in PreyTrackerDB so reopening the map
   respects it within the session. The restore chip must hide through the same paths that
   hide the board (map close, watchdog, ForceHide).
6. New logo: media/icon_prey.tga (red prey crystal, pre-colored, do NOT vertex-tint it)
   replaces icon_paw everywhere the addon shows its identity: the Hunt Board header
   logo (drop the violet rounded square behind it — the crystal has its own glow), the
   minimap button icon, and the new restore chip. icon_paw stays in media/ but unused.
7. Update the `/prey` help listing and bump the version in the .toc.

**Verify in game:** `/prey` out of map → board with cached hunts, no Accept buttons; accept
a hunt with the map open, close and reopen the map → board shows, current prey highlighted
with live meter; X over map closes both; minimize → map usable, crystal chip top-right →
restore works; crystal shows on header + minimap button; reopen map while minimized → stays minimized; `/reload` mid-state breaks
nothing; watchdog still cleans up if the map closes abnormally.

## Prompt 6 — Achievement tracking for all difficulties + mount preview

Read Achievements.lua, HuntBoard.lua, and HUNTBOARD_SPEC.md. Expand achievement tracking
from Nightmare-only to all three difficulties. Nightmare stays the headline — most players
only care about it; Hard and Normal are there for completionists.

1. Generalize Achievements.lua into a registry keyed by difficulty:
   Nightmare → "Prey: Nightmare Mode III", Hard → "Prey: Hard Mode III",
   Normal → "Prey: Normal Mode III". Always track Mode III directly — no tier-walking,
   no fallback to I/II. Same locate-by-name + criteria-name-match logic as the existing
   Nightmare path — one shared implementation, three configs, no copy-paste. Cache
   located achievement IDs in PreyTrackerAccountDB (achievements are account-wide).
2. Chips on every row: the trophy/check chip now appears on Hard and Normal cards too,
   same placement and meaning as the Nightmare one. Tint the chip border with the
   difficulty color so rows stay distinct; trophy icon stays gold, icon_check green.
3. Card tooltip: on mouseover of any hunt card, after name/difficulty/zone/status/rewards,
   add an achievement section: the tracked achievement name, overall progress (e.g. 9/12),
   and this hunt's own line — "Not yet defeated" in red or "Defeated" with a check in
   green. If criteria lookup failed for this hunt name, show "No matching criteria found"
   in faint grey instead of guessing.
4. Footer hierarchy: Nightmare keeps the prominent center bar exactly as it is. Add Hard
   and Normal as visibly secondary — smaller/slimmer difficulty-colored bars beside it
   (e.g. compact "H 7/12" / "N 11/12" chips). Each of the three has a hover tooltip
   listing the remaining hunt names for that achievement.
5. Mount preview on the Nightmare tracker: mouseover of the "Prey: Nightmare Mode III"
   footer tracker opens a small anchored popup frame showing the achievement reward —
   the Preyseeker's Nightmare mount (item 257193). Implementation: a rounded panel
   (Widgets.lua chrome) containing a ModelScene/PlayerModel rendering the mount's 3D
   model — resolve it by scanning C_MountJournal for the mount named "Preyseeker's
   Nightmare" and using its creature displayID from GetMountInfoExtraByID; set a slow
   idle rotation. Below the model: mount name in epic purple and "Reward: Prey —
   Nightmare Mode III". If the mount can't be resolved (not in journal data yet on PTR),
   fall back to GameTooltip:SetItemByID(257193) and log one debug line. Hide the popup
   on mouse leave; it must die with the board through all hide paths.
6. Live updates: register ACHIEVEMENT_EARNED and CRITERIA_UPDATE (or the closest
   available criteria event) and refresh chips/bars/tooltips in place when they fire,
   so a kill counts immediately without a rescan. Throttle to at most one refresh per
   second. On ACHIEVEMENT_EARNED for a tracked achievement, print one chat line
   ("PreyTracker: Prey: Nightmare Mode III complete!").
7. Resilience: all three lookups are name-based joins on English strings — on localized
   clients hide chips/bars rather than showing wrong data. Extend the ARCHITECTURE.md
   fragility row to cover the three achievement lines, the mount-journal name lookup,
   and the hardcoded item ID 257193. Bump the version in the .toc.

**Verify in game:** chips on all 12 cards match the achievement pane across the three
difficulties; card tooltips show the achievement section with correct per-hunt state;
footer shows Nightmare prominent + compact H/N trackers, each with remaining-list
tooltips; hovering the Nightmare tracker shows the rotating Preyseeker's Nightmare
mount popup; kill a tracked hunt → chip flips and bar increments without rescan;
popup and trackers clean up through close/minimize/map-close paths.
