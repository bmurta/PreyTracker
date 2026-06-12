# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PreyTracker is a World of Warcraft addon (Lua, no build step) providing an alternative UI for the Midnight expansion's Prey Hunt system. This directory is the live AddOns folder of a WoW PTR install — edits take effect in-game after `/reload`.

**Read `ARCHITECTURE.md` before substantive changes.** It is the deep reference: data-acquisition techniques, domain rules, and a fragility map of every Blizzard-internal dependency. Two of its sections are stale, however:

- §5 describes the Zul'Aman zone-boundary bug as unfixed — the fix (`x > 0.40 and y > 0.55`) and the one-prey-per-difficulty-per-zone dedup are already committed in `Data.lua`.
- Interface version is `120007` (see `PreyTracker.toc`), not `120001`.

## Development workflow

There is no build, lint, or test tooling. The loop is: edit Lua → `/reload` in the game client → exercise via slash commands (`/prey`, `/prey bar`, `/prey widget`, `/prey hide`, `/prey reset`). Lua errors surface in-game (enable `/console scriptErrors 1`).

When bumping for a game patch, update both `## Interface:` and `## Version:` in `PreyTracker.toc`.

## Architecture (big picture)

There is **no prey API**. Blizzard reused the Adventure Map / Covenant Mission framework, so everything is scraped from `CovenantMissionFrame` via three independent sources:

1. **Map pins** (`Data.lua`) — hunt name, questID read off pin objects in `CovenantMissionFrame.MapTab.pinPools["AdventureMap_QuestOfferPinTemplate"]`. Difficulty and zone are *derived*, not provided: difficulty by English substring match on `pin.description`, zone by hardcoded coordinate boundaries on `pin.normalizedX/Y`.
2. **Hidden quest-choice dialog** (`Data.lua`) — rewards exist only inside `AdventureMapQuestChoiceDialog`. `WarmRewardCacheAsync` invisibly opens it per quest (alpha 0), polls the reward pool until the count is stable, and caches results. Quests that time out empty are retried across up to 3 map opens.
3. **UI widget + currency** (`Progress.lua`) — live progress from widget ID `7663` (`C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo`), Anguish balance from currency `3392`. The addon suppresses Blizzard's native widget and renders its own 3-segment bar.

Asynchrony is handled by **stability polling** in two places: `Core.lua` polls the pin *count* on map open (pins trickle in on slow clients) before scraping; the reward warmer polls reward counts per quest. Both commit only after N identical consecutive reads.

`Core.lua` owns events, slash commands, and `ShowUIPanel`/`HideUIPanel` hooks (plus a watchdog that force-hides the panel if the map closes without the hook firing). `UI.lua` builds the panel with a recycled row pool and has two modes: docked (anchored to `CovenantMissionFrame`) and standalone (centered, accept buttons hidden). `Config.lua` centralizes constants, colors, sort orders, and the reward-icon substring table.

### Load order matters

`.toc` order is Core → Config → Data → UI → Progress, but the global table `PreyTracker` (locally `PH`) is shared across all files. Functions defined in later files (e.g. `PH.CreateMinimapButton` in UI.lua) must not be captured by value at load time in earlier files — only called from event handlers after `ADDON_LOADED`. This caused a real bug historically (ARCHITECTURE.md §10/§13.6).

### Known fragilities

Everything scraped is a silent-break risk on a Blizzard UI change — see the fragility table in ARCHITECTURE.md §14 before touching anything after a game patch. Two standing caveats:

- **`CallbackHandler-1.0` is now bundled** (`Libs\CallbackHandler-1.0.lua`, listed in the `.toc` before LibDataBroker) — `libs/LibDataBroker-1.1.lua` hard-asserts on it. It used to load only because another installed addon provided it, and broke standalone; the bundled copy fixes that. It's the canonical Ace3 source — don't edit it.
- Difficulty parsing is English-only; localized clients collapse everything to "Normal".

## Domain rules

- Difficulties: Normal, Hard, Nightmare. Zones: Eversong Woods, Zul'Aman, Harandar, Voidstorm.
- Invariant: **one hunt per (difficulty, zone)** — `RefreshFromPins` dedupes on this key, so a zone misclassification shows up as a dropped hunt rather than a duplicate.
- Saved variables: `PreyTrackerDB` (per-character) and `PreyTrackerAccountDB`. Renaming them orphans existing user data.
