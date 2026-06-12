# Hunt Board — visual revamp spec

Design reference for the PreyTracker 2.0 revamp. The Hunt Board becomes the **main screen**:
when the player opens the Prey map, the addon renders this window on top of
`CovenantMissionFrame` and the player chooses hunts from here.

**Look at these files before writing code:**

- `mockups/preytracker_redesign_overlay.png` — the Hunt Board (primary deliverable, view this image)
- `mockups/preytracker_redesign_panel.png` — standalone panel restyle (kept as secondary view)
- `media/README.md` — every texture, its size, slice margins, and Lua usage snippets
- `ARCHITECTURE.md` — data acquisition, domain rules, fragility map (read first, per CLAUDE.md)

## Core decisions

- The Hunt Board **replaces the docked side panel** as the map-open experience. The old
  panel code in `UI.lua` stays for standalone mode (minimap button / `/prey`), restyled later.
- Grid is 4 columns (zones, in `PH.ZONE_ORDER`: Eversong Woods, Zul'Aman, Harandar, Voidstorm)
  × 3 rows (difficulties, top to bottom: **Nightmare, Hard, Normal**).
- One hunt per (difficulty, zone) is an addon invariant — the grid IS that invariant. A cell
  with no matching hunt renders an empty state (dashed `panel_border` tint 0.3 alpha,
  "No hunt detected" in faint text).
- All data comes from the existing pipeline: `PH.liveHunts` (name, questID, difficulty, zone),
  `PH.rewardCache[questID]`, `PH.IsInProgress(questID)`, widget 7663 progress, currency 3392.
  No new scraping for the board itself.

## Palette (RGB 0–1)

| Token | Hex | RGB |
|---|---|---|
| bg gradient top | #14161d | 0.078, 0.086, 0.114 |
| bg gradient bottom | #0d0e13 | 0.051, 0.055, 0.075 |
| card surface | #1a1d26 | 0.102, 0.114, 0.149 |
| card border | #232733 | 0.137, 0.153, 0.200 |
| viewport bg | #0c0d13 | 0.047, 0.051, 0.075 |
| text | #e8e9ee | 0.910, 0.914, 0.933 |
| text dim | #8b8fa0 | 0.545, 0.561, 0.627 |
| text faint | #565b6c | 0.337, 0.357, 0.424 |
| violet (brand/selection/achievement) | #c44dd8 | 0.769, 0.302, 0.847 |
| cyan (available) | #55ccff | 0.333, 0.800, 1.000 |
| gold (in progress) | #ffd24d | 1.000, 0.824, 0.302 |
| anguish red | #ff5555 | 1.000, 0.333, 0.333 |
| diff Normal | #4ade5c | 0.290, 0.871, 0.361 |
| diff Hard | #ffa928 | 1.000, 0.663, 0.157 |
| diff Nightmare | #f24545 | 0.949, 0.271, 0.271 |
| accept green grad | #35b854 → #1f8a3a | — |
| zone colors | keep existing `CFG.ZONE_COLOR` | — |

## Window layout (proportions from mockup, 1200×706 reference)

- Anchor: cover `CovenantMissionFrame` entirely (TOPLEFT/BOTTOMRIGHT), DIALOG strata above it.
  Inner content laid out from the reference proportions; don't hardcode 1200px.
- Header (58px): paw logo on violet rounded square, "PreyTracker" (Prey violet, Tracker white),
  "HUNT BOARD" label, subtitle "ONE HUNT PER DIFFICULTY, PER ZONE". Right: Anguish chip
  (gem icon + amount, red pill), close button. Violet gradient hairline across the very top.
- Column headers: zone name in zone color, small zone dot, centered over each column.
- Row gutter (left, ~36px): rotated difficulty label (`FontString:SetRotation(math.pi/2)`),
  3px vertical bar in difficulty color. Order: Nightmare, Hard, Normal.
- Cards: 262×170 ratio, 14px gaps, 10px corner radius.
- Footer: "N In Progress · N Available" | center: trophy icon + "PREY: NIGHTMARE MODE III" +
  progress bar (violet fill) + "9/12" | right: Rescan button + "Xm ago" scan age.

## Card anatomy

1. Background: `panel_bg` nine-slice, card surface tint; 3px difficulty-colored bar across the
   top (inset 12px each side); `panel_border` nine-slice, border tint.
2. Model viewport (full width minus 8px, 92px tall): `panel_bg` tinted viewport bg +
   `panel_border`; inside: `zone_glow` (zone tint, alpha ~0.4), `platform` (zone tint),
   creature silhouette `sil_<zone>` tinted near-black (0.02, 0.03, 0.04). For `sil_void`, add
   two 6px `glow_radial` dots tinted violet as eyes.
3. Status badge (viewport top-left): `pill_bg` dark + `pill_border`; cyan dot+text "Available"
   or gold "In Progress".
4. Achievement chip (viewport top-right, Nightmare row only): rounded 19px square,
   `icon_trophy` = still needed, `icon_check` tinted green = criteria done.
5. Name (12px bold), reward icons (22px, real `rewardCache` icons with quality-tinted
   `panel_border`, stack count badges), bottom-right: Accept button (selected/hover) or
   3-segment mini progress meter (in-progress card, from widget 7663).

## States

- **Available**: plain card. Hover: border lightens, accept button appears with green glow.
- **In Progress**: gold border 40% alpha, gold gradient wash from the left, gold status badge,
  mini meter instead of accept.
- **Selected** (clicked once): violet border + `card_glow` ring (ADD, violet), accept button
  glowing. Click accept = existing flow from UI.lua `PopulateRow` (AdventureMapQuestChoiceDialog
  ShowWithQuest → AcceptQuest → board refreshes).
- **Empty cell**: dashed-feel faint border, "No hunt detected", faint zone silhouette at 10% alpha.

## Achievement tracking (new module)

- Find achievement ID for "Prey: Nightmare Mode III" (search achievement API by name once,
  cache in saved variables; it's PTR so the ID may change — don't hardcode without fallback).
- `GetAchievementNumCriteria` + `GetAchievementCriteriaInfo` → match criteria name against hunt
  names (exact, then substring fallback). English-only caveat, same as difficulty parsing.
- Drives: per-card trophy/check chips (Nightmare row), footer progress bar (completed/total),
  tooltip on trophy listing remaining criteria.
- This is a name-based join on a real API: add a row to the ARCHITECTURE.md §14 fragility table.

## Phasing (one Claude Code session each)

1. **Widgets.lua** — texture path constants + factory helpers: `CreateCard(parent)` (bg+border
   nine-slice pair), `CreatePill`, `CreateGlow`, `CreateIcon`. Add to .toc after Config.lua.
   Test: `/prey test` spawns a sample card centered on screen.
2. **HuntBoard.lua** — full static layout with fake 12-hunt data, anchored over the map frame.
   Test: `/prey board` toggles it. Get spacing/scale right against the mockup before wiring data.
3. **Data wiring** — replace fake data with liveHunts/rewardCache/IsInProgress; accept flow;
   empty-cell state; hook into Core.lua show/hide path (board instead of docked panel; keep the
   loading overlay sequence); suppress the old panel in map context.
4. **Achievements.lua + polish** — chips, footer bar, tooltip; rescan button (re-runs
   RefreshFromPins + WarmRewardCacheAsync); scan-age text; update ARCHITECTURE.md (new files,
   fragility rows) and bump `## Version:` in the .toc.

## Constraints (from CLAUDE.md / ARCHITECTURE.md — do not violate)

- No build step; verify by `/reload` + slash commands; `/console scriptErrors 1`.
- `.toc` load order matters: `PreyTracker` global table shared; never capture functions from
  later files by value at load time.
- Don't rename `PreyTrackerDB` / `PreyTrackerAccountDB`.
- Everything anchored to `CovenantMissionFrame` is fragile across patches — keep all
  Blizzard-frame references in clearly marked spots.
- `SetTextureSliceMargins` / `SetTextureSliceMode` require the modern client (present in
  Midnight). All slice margins are documented in `media/README.md`.
