# PreyTracker — Architecture & Development Notes

A World of Warcraft addon (Interface `120007`, The War Within / Midnight prey
system) by **Valash**. It provides an alternative UI for the Prey Hunt system:
the **Hunt Board** (a 4×3 zone × difficulty grid) renders over
`CovenantMissionFrame` (the Hunt Table map) as the map-open main screen, with the
original side panel kept for standalone (`/prey` / minimap) use, plus a custom
progress bar that surfaces the otherwise-hidden prey completion percentage.

This document is the reference for migrating the project into a Claude Code
workspace. It describes how data is acquired, how locations are determined, every
fragile dependency on Blizzard internals, and the full history of work done so
far.

---

## 1. High-level overview

There is **no dedicated "prey" API**. Blizzard reused the Adventure Map /
Covenant Mission framework for the Hunt Table, so the addon scrapes everything
off `CovenantMissionFrame`. Nothing hands back clean structured data — the addon
polls frames, parses display strings, and infers map coordinates.

There are **three independent data sources**, each scraped differently:

| Source | What it yields | How it's read |
|--------|----------------|---------------|
| Quest offer **pins** on the map | hunt name, difficulty, zone, questID | iterate the pin pool, read pin fields, parse/derive |
| The hidden **quest choice dialog** | reward list (icon, name, count) | invisibly open the dialog, snapshot its reward pool |
| A **UI widget + currency** | live progress % and Anguish balance | read widget 7663 and currency 3392 directly |

Difficulty and zone are **derived**, not provided: difficulty by substring
matching on the pin description, zone by hardcoded coordinate boundaries.

---

## 2. File structure & load order

Declared in `PreyTracker.toc` (`SavedVariables: PreyTrackerDB`,
`SavedVariablesPerAccount: PreyTrackerAccountDB`):

```
Libs\LibStub.lua
Libs\CallbackHandler-1.0.lua
Libs\LibDataBroker-1.1.lua
Libs\LibDBIcon-1.0.lua

Core.lua
Config.lua
Widgets.lua
Data.lua
UI.lua
HuntBoard.lua
Achievements.lua
Progress.lua
```

| File | Responsibility |
|------|----------------|
| `Core.lua` | Event handling, slash commands, `ShowUIPanel`/`HideUIPanel` hooks, pin-stability polling, minimap button init |
| `Config.lua` | All constants: panel sizes, difficulty/zone colors, reward-icon map, currency ID, sort-order tables, `HUNT_CREATURES`/`HUNT_MODELS` card-model tables |
| `Widgets.lua` | Hunt Board chrome: media texture paths, the revamp palette (`PH.PAL`), and the `CreateCard`/`CreatePill`/`CreateGlow`/`CreateIcon` nine-slice factories; `/prey test` sample card |
| `Data.lua` | Pin scanning, cache-validity check, async reward-cache warmer, sort/filter helpers, state helpers, `lastScanTime` stamp |
| `UI.lua` | Side panel (standalone mode), row pool, filter bar, loading overlay, map overlay, minimap button (LibDBIcon + manual fallback) |
| `HuntBoard.lua` | The Hunt Board: 4×3 card grid over the map, header/footer, card models, accept flow, footer achievement bar + Rescan + scan age |
| `Achievements.lua` | Resolves "Prey: Nightmare Mode III" by name (cached/fallback), reads its criteria, joins them to hunt names for the per-card chips, footer bar, and trophy tooltip |
| `Progress.lua` | Custom progress bar reading widget 7663; suppression of Blizzard's native widget |
| `Libs/` | LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 |
| `LICENSE` | Proprietary, all rights reserved to Valash |

> **Hunt Board (`HuntBoard.lua`):** the map-open main screen, replacing the docked
> side panel. It reuses the existing pipeline only — `PH.liveHunts`,
> `PH.rewardCache`, `PH.IsInProgress`, widget 7663, currency 3392 — laid onto a
> 4 zones × 3 difficulties grid (the one-hunt-per-(difficulty, zone) invariant *is*
> the grid). All chrome is built from the `Widgets.lua` nine-slice factories. The
> `Rescan` footer button re-runs `RefreshFromPins` + `WarmRewardCacheAsync`; the
> "Xm ago" scan age reads `PH.lastScanTime` (stamped in `RefreshFromPins`).
>
> **The board is now the experience everywhere (Phase 5).** `/prey` and the minimap
> button open it centered on screen (`PH.OpenBoardStandalone`), rendered from a
> durable per-character snapshot of the last scan (`PreyTrackerDB.cachedHunts` /
> `cachedRewards`, written by `PH.SaveCache`, seeded at login by `PH.LoadCache`).
> Out of the map there are no offer pins to accept against, so Accept is replaced by
> a faint "Open the Prey map to accept" hint (`PH.standalone`). `PH.GetBoardHunts`
> merges live pins with the snapshot so an **in-progress hunt whose offer pin
> Blizzard hides** still renders — with the strongest emphasis (gold border +
> `card_glow` ring) and a live mini meter (widget 7663, `UPDATE_UI_WIDGET`). To make
> this safe, `RefreshFromPins` no longer wipes the cache when the pool is absent or
> empty. The map-mode header adds a **minimize** (–) button that hides the overlay
> and shows a restore chip on the map (`PreyTrackerDB.boardMinimized`, reset each
> session); the **close** button over the map routes through
> `HideUIPanel(CovenantMissionFrame)` so the existing Core hook tears the board down
> once. `/prey panel` still opens the old `UI.lua` list panel.
>
> **Achievements (`Achievements.lua`):** there is no "achievement by name" API and
> the PTR id drifts, so the id is resolved *by name* — cached id → hardcoded
> fallback → full category scan, each candidate verified by name and walked through
> its I→II→III series chain (`GetNextAchievement`). The resolved id is cached in
> `PreyTrackerAccountDB.achievementID`. Criteria (`GetAchievementNumCriteria` /
> `GetAchievementCriteriaInfo`) are joined to hunt names (exact-normalized, then
> substring) to drive the Nightmare-row trophy/check chips, the footer
> completed/total bar, and the trophy's remaining-criteria tooltip. Refreshed on
> `CRITERIA_UPDATE` / `ACHIEVEMENT_EARNED` (Core.lua).

> **Load-order note:** `Core.lua` loads before `UI.lua`. A historical bug came
> from a wrapper that captured `PH.CreateMinimapButton` at Core-load time, when
> it was still `nil`. See §10.

---

## 3. Grabbing the pins (`Data.lua`)

The pins live in a pin pool on the map's `MapTab`, keyed by the template name:

```lua
local PIN_POOL = "AdventureMap_QuestOfferPinTemplate"

local function GetPinPool()
    local mt = CovenantMissionFrame and CovenantMissionFrame.MapTab
    return mt and mt.pinPools and mt.pinPools[PIN_POOL]
end
```

`RefreshFromPins()` iterates the **active** pins and pulls four raw fields off
each pin object:

```lua
for pin in pool:EnumerateActive() do
    if pin.questID and pin.title then
        newHunts[#newHunts + 1] = {
            name       = pin.title,
            difficulty = ParseDifficulty(pin.description),       -- derived
            questID    = pin.questID,
            zone       = GetZoneFromCoords(pin.normalizedX, pin.normalizedY), -- derived
        }
    end
end
```

Raw inputs read directly off the pin: `pin.title`, `pin.description`,
`pin.questID`, `pin.normalizedX`, `pin.normalizedY`.

`PH.FindPin(questID)` is the lookup used elsewhere (reward warming, accept
button) — it re-enumerates the active pool and returns the pin whose `questID`
matches.

---

## 4. Determining difficulty (string matching)

Difficulty is **not a field**. It is parsed out of the pin's description text
with a substring waterfall, Normal as fallback:

```lua
local function ParseDifficulty(desc)
    if not desc then return "Normal" end
    if desc:find("Nightmare") then return "Nightmare" end
    if desc:find("Hard")      then return "Hard" end
    return "Normal"
end
```

> **Fragility:** English-only. Any localized client will collapse everything to
> "Normal". Flagged for the migration backlog.

---

## 5. Determining location (coordinate boundaries) — **the active bug**

There is no zone field on the pin, so zone is inferred from the pin's
**normalized map coordinates** (`normalizedX`, `normalizedY`, each 0–1 across the
map image) via a hardcoded boundary waterfall — first match wins:

```lua
local function GetZoneFromCoords(x, y)
    if not x or not y then return nil end
    if x > 0.70              then return "Harandar"      end
    if x > 0.40 and y < 0.40 then return "Voidstorm"     end
    if y > 0.55              then return "Zul'Aman"       end
    return "Eversong Woods"
end
```

Reading the rules:

- Far right of the map (`x > 0.70`) → **Harandar**
- Mid-right and upper area (`x > 0.40 and y < 0.40`) → **Voidstorm**
- Lower band (`y > 0.55`, no x constraint) → **Zul'Aman**
- Everything else (the catch-all) → **Eversong Woods**

### The bug

With Nightmare preys released, the pin for **"High Vindicator Vureem"** sits in
the **lower-left** of the map (Eversong Woods territory) but is misidentified as
**Zul'Aman**. Cause: the `y > 0.55` Zul'Aman rule has **no x constraint**, so it
sweeps the entire lower band — including the lower-left that belongs to Eversong.

### Fix direction (not yet finalized in the project files)

1. Constrain the Zul'Aman boundary with an x condition so the lower-**left** stays
   Eversong while the lower-**right** (true Zul'Aman) is still caught.
2. Add validation enforcing the domain rule **one prey per difficulty per zone**
   (see §8), so any future misclassification surfaces as a detectable duplicate
   rather than failing silently.

> The version currently in the repo is the **pre-fix** waterfall shown above.
> Confirm and lock the corrected boundary values when migrating. The exact
> corrected thresholds should be re-derived from a current screenshot of pin
> coordinates, since they are tuned to one specific map image.

---

## 6. Cache-validity check (avoid re-scraping)

`RefreshFromPins` does not rebuild blindly. It collects the new pins first, then
compares the **set of questIDs** against the existing cache:

```lua
local cacheValid = (#newHunts == #PH.liveHunts)
if cacheValid then
    for _, h in ipairs(PH.liveHunts) do
        if not newIDs[h.questID] then cacheValid = false; break end
    end
end
```

- **Identical questID set** → refresh `liveHunts` (names/zones may have shifted)
  but keep `rewardCache` intact; return `true` (warm).
- **Different set** → wipe `liveHunts`, `rewardCache`, and `attemptCount`; return
  `false` (needs warming).

This prevents a full reward re-scrape every time the map opens.

---

## 7. Scraping rewards (the hidden-dialog technique)

Reward data exists **only** inside `AdventureMapQuestChoiceDialog` — the popup
normally shown when clicking a pin. The addon **invisibly opens that dialog**,
reads its reward pool, then closes it.

### `SnapshotPool()`

Reads each active reward frame's `Name` and `Count` fontstrings:

```lua
for reward in dialog.rewardPool:EnumerateActive() do
    local name  = reward.Name  and reward.Name:GetText()
    local count = reward.Count and reward.Count:GetText()
    ...
end
```

Classification:

- **XP rewards** appear as bare numbers ("19,415"), detected by
  `IsXPNumber` (`s:match("^[%d,]+$")`), and relabeled `Player Experience (...)`.
- **Everything else** is substring-matched against `PH.REWARD_ICONS`
  (`Config.lua`) to pick an icon (e.g. "Champion Dawncrest", "Veteran Chest",
  "Preyseeker's Journey"), falling back to a question-mark icon.
- Rewards are sorted by a priority table: Dawncrest → Chest → Sack → Journey →
  XP.

### `WarmRewardCacheAsync(onProgress, onDone)` — sequential async warmer

Processes **one quest at a time**. Tunables:

```lua
local POLL_MS       = 0.10   -- poll interval
local STABLE_NEEDED = 3      -- identical reward counts before committing
local TIMEOUT_S     = 4.0    -- per-quest give-up time
local MAX_ATTEMPTS  = 3      -- retries across map opens before accepting empty
```

Per quest:

1. Set dialog alpha to 0 and hide it, then
   `dialog:ShowWithQuest(CovenantMissionFrame, pin, questID)` to trigger the
   server item-data fetch.
2. Poll `SnapshotPool()` every `POLL_MS`.
3. Commit once the reward count is identical for `STABLE_NEEDED` consecutive
   polls (pool has settled).
4. If the count stays 0 too long or total time exceeds `TIMEOUT_S`, give up.
5. Commit result, fire `onProgress(done, total)`, advance to the next quest.

Retry / accept-empty logic:

```lua
if timedOutEmpty then
    attemptCount[questID] = (attemptCount[questID] or 0) + 1
    if attemptCount[questID] >= MAX_ATTEMPTS then
        PH.rewardCache[questID] = {}    -- accept as genuinely reward-less
    else
        PH.rewardCache[questID] = nil   -- leave nil → re-queued next map open
    end
else
    PH.rewardCache[questID] = rewards   -- real rewards (or no-pin skip)
    attemptCount[questID]   = nil
end
```

A quest that times out empty is retried across up to 3 map opens before being
accepted as reward-less.

### Cancellation

`PH._rewardWarmCancel` restores the dialog's original alpha and cancels the
active ticker if the user closes the map mid-warm. It's invoked from
`HidePanel`/`ForceHidePanel`.

---

## 8. Domain rules (the prey system)

Established from research and in-game observation:

- **Difficulties:** Normal, Hard, Nightmare.
- **Zones:** Eversong Woods, Zul'Aman, Harandar, Voidstorm.
- **Constraint:** one hunt per difficulty per zone — so at most **one Nightmare
  per zone**. This is the invariant the planned validation (§5) should enforce.
- Progress accrues through an **invisible currency / progress bar**, filled by
  world quests, rares, treasures, and fighting minor/major Coalescing Anguishes.
  There is no player-facing numeric readout in the default UI — only a widget
  that pulses at 0 / 33 / 66 / 100%.

---

## 9. Pin-stability polling on map open (`Core.lua`)

Separate from the reward-stability problem: when `CovenantMissionFrame` first
opens, pins trickle in asynchronously on slow clients. Scraping immediately
yields a partial/empty list. The `ShowUIPanel` hook therefore polls the pin
**count** before doing anything:

```lua
local PIN_POLL     = 0.15  -- check interval (seconds)
local STABLE_READS = 3     -- identical non-zero counts before committing
local MAX_WAIT     = 6.0   -- hard give-up
```

It counts active pins every `PIN_POLL` and only `Proceed()`s once the count is
non-zero and unchanged for `STABLE_READS` reads (or `MAX_WAIT` elapses). Then it
calls `RefreshFromPins`, checks cache warmth, and either shows the panel directly
or shows the loading frame and starts `WarmRewardCacheAsync`.

A **watchdog** `OnUpdate` (1s cadence) force-hides the panel if the map closed
without firing `HideUIPanel`.

The hooks:

```lua
hooksecurefunc("ShowUIPanel", function(frame) ... end)  -- name == "CovenantMissionFrame"
hooksecurefunc("HideUIPanel", function(frame) ... end)  -- → PH.HidePanel()
```

---

## 10. Progress tracking (`Progress.lua`) — reverse-engineered feature

The game gives the player **no numeric prey progress** — only a UI element that
pulses at 0 / 33 / 66 / 100%. The source was traced to a power-bar widget, read
directly:

```lua
local PREY_WIDGET_ID = 7663
local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(PREY_WIDGET_ID)
if info and info.shownState == 1 then
    ... ApplyState(info.progressState, animate)   -- progressState is 0–3
end
```

- `info.progressState` (integer 0–3) drives a custom **3-segment bar** with
  tweened fills, per-state color transitions (empty → dark red → yellow → green),
  pulse glows, and flash bursts on completion.
- The addon **suppresses Blizzard's native widget**
  (`UIWidgetPowerBarContainerFrame.widgetFrames[7663]`) by hiding it and hooking
  its `OnShow` to keep it hidden, so only the custom bar shows. This is toggleable
  via `/prey widget`.
- State is refreshed on `UPDATE_UI_WIDGET` events (filtered to widget 7663) plus
  a 2s polling ticker, and on `PLAYER_ENTERING_WORLD` / `ZONE_CHANGED_NEW_AREA`.
- The bar is draggable (right-button), position persisted in
  `PreyTrackerDB.progressBar`; `/prey bar reset` restores the default anchor
  (under the widget).

Anguish currency is read separately:

```lua
C_CurrencyInfo.GetCurrencyInfo(CFG.ANGUISH_CURRENCY_ID)  -- 3392 → .quantity
```

---

## 11. Modes, panel, and minimap button (`UI.lua`)

- **Docked mode:** panel anchors to `CovenantMissionFrame`'s top-left, matching
  its height; opens automatically with the map.
- **Standalone mode** (`PH.standalone = true`): centered on screen, wider
  (`PANEL_WIDTH_STANDALONE = 380` vs docked `290`), accept buttons hidden, empty
  state shown if no hunts are cached. Triggered by minimap button or `/prey`.
- **Row pool:** rows are created once and recycled (`AcquireRow` / `ReleaseRow`)
  to avoid per-refresh frame churn. Each row has up to **5 reward icons** (raised
  from 4 — see §12), a difficulty stripe, badge, zone text, status line, and an
  accept button.
- **Filter bar:** difficulty pills (All / Nightmare / Hard / Normal) driving
  `PH.filter.difficulty`, re-running `RefreshRows`.
- **Loading overlay + map overlay:** shown while rewards warm; a progress bar
  reflects `done/total` from the warmer callback.
- **Minimap button — two paths:**
  - **Path A (preferred):** LibDBIcon broker object (handles ElvUI, MBB, other
    managers).
  - **Path B (fallback):** a manual `Minimap`-anchored button placed by angle on
    a fixed radius, draggable, position saved in `PreyTrackerDB.minimapAngle`.

### Slash commands (`Core.lua`)

```
/prey            toggle panel (standalone)
/prey show       show panel
/prey hide       force-hide
/prey reset      recenter + show standalone
/prey bar        toggle the custom progress bar
/prey bar reset  reset bar position
/prey widget     toggle Blizzard's native widget
```

`/preytracker` is an alias for `/prey`.

---

## 12. Configuration constants (`Config.lua`)

Key values that are likely to drift between game builds and are worth surfacing
in one place:

- `ANGUISH_CURRENCY_ID = 3392`
- `PREY_WIDGET_ID = 7663` (in `Progress.lua`)
- Panel sizing: `PANEL_WIDTH = 290`, `PANEL_WIDTH_STANDALONE = 380`,
  `PANEL_HEIGHT = 560`, `ROW_HEIGHT = 78`, `ICON_SIZE = 22`.
- `DIFF_COLOR`, `ZONE_COLOR` tables.
- `DIFF_ORDER = { Nightmare = 1, Hard = 2, Normal = 3 }` and
  `ZONE_ORDER = { Eversong Woods = 1, Zul'Aman = 2, Harandar = 3, Voidstorm = 4 }`
  drive `GetSortedHunts` (difficulty → zone → in-progress → name).
- `REWARD_ICONS` substring-match table and `FALLBACK_ICON`.

---

## 13. Work history (chronological)

1. **Initial build.** Researched the Midnight prey system; established it reuses
   `CovenantMissionFrame`. Built the side panel scraping pins for name /
   difficulty / zone / status.
2. **Naming evolution:** PreyHunterUI → PreyHub → PreyList → **PreyTracker**
   (renamed global table, frame names, broker label, saved-vars, slash commands,
   TOC). Note: saved-variable renames mean old data does not carry across a
   rename.
3. **Aesthetic study:** analyzed the **Plumber** addon as the visual reference
   for animations and polish.
4. **Reward cache warmer:** built the async, stable-poll, cross-session-retry
   reward scraper (§7).
5. **Progress bar feature (`Progress.lua`):** reverse-engineered widget 7663 to
   surface exact progress state; suppressed Blizzard's native widget; added
   tweens, pulses, flash bursts.
6. **Bug fixes:**
   - Minimap-button **persistence bug** — a wrapper captured
     `PH.CreateMinimapButton` as `nil` because Core loads before UI. Removed the
     wrapper; `ADDON_LOADED` now initializes `PreyTrackerDB` /
     `PreyTrackerAccountDB` before calling `CreateMinimapButton()`.
   - **Broken border** on the progress card — `BackdropTemplate` with
     `UI-Tooltip-Border` (a 9-slice sprite) rendered oversized corners at the
     bar's small size. Replaced with four plain 1px `WHITE` line textures that
     recolor with state.
7. **Reward slots 4 → 5:** raised the per-row reward icon count in `AcquireRow`
   and `PopulateRow` to accommodate the Nightmare "Journey" bonus reward. Extra
   slot stays hidden on rows with fewer rewards.
8. **In progress:** zone-boundary correction for the Nightmare-era misclassified
   pin, plus one-prey-per-difficulty-per-zone validation (§5).

---

## 14. Fragility map (read before any game patch)

Everything below is a silent-break risk on a Blizzard UI change:

| Dependency | Where | Risk |
|------------|-------|------|
| `CovenantMissionFrame.MapTab.pinPools["AdventureMap_QuestOfferPinTemplate"]` | `Data.lua`, `Core.lua` | UI refactor changes the path or template name |
| `AdventureMapQuestChoiceDialog.rewardPool` + reward `.Name`/`.Count` fontstrings | `Data.lua` | dialog structure change breaks reward scraping |
| `pin.normalizedX/Y` semantics | `Data.lua` | re-tuned map art shifts every zone boundary |
| Difficulty substring match | `Data.lua` | English-only; breaks on localized clients |
| Hardcoded zone boundaries | `Data.lua` | tuned to one map image; the active bug |
| `PREY_WIDGET_ID = 7663` | `Progress.lua` | widget ID can change between builds |
| `ANGUISH_CURRENCY_ID = 3392` | `Config.lua` | currency ID can change between builds |
| `C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo` | `Progress.lua` | API signature/field changes |
| Achievement criteria → hunt **name join** (and the by-name id resolution) | `Achievements.lua` | criterion text is matched to hunt names (exact-normalized, then substring), English-only like difficulty parsing; a renamed prey, reworded criterion, or a single progress-bar criterion silently drops the chip/footer match. The id is found by scanning categories for the name "Prey: Nightmare Mode III" — a renamed achievement makes it unresolvable until the fallback id is filled in |
| `SetTextureSliceMargins` / `SetTextureSliceMode` nine-slice API | `Widgets.lua` (every card/pill/glow), `HuntBoard.lua`, `UI.lua` reward borders | requires a modern client (present in Midnight); a signature change or pre-Midnight client breaks all rounded panel/card/pill chrome |
| `CovenantMissionFrame` top-right anchor for the minimized restore chip | `HuntBoard.lua` (`PH.ShowBoardChip`) | the chip is parented to `UIParent` but anchored to the map frame's TOPRIGHT; a renamed/removed frame leaves the chip unanchored (the board still closes via the `HideUIPanel` hook) |

### Open verification items for the migration

- **Lock the corrected zone boundaries** and add the per-difficulty-per-zone
  validation; the repo still holds the pre-fix waterfall.
- **Confirm `CallbackHandler-1.0` is bundled.** `LibDataBroker-1.1.lua` hard
  `assert`s on it, but the current `.toc` lists only LibStub, LibDataBroker, and
  LibDBIcon. If CallbackHandler is present on disk it must also be added to the
  load order before LibDataBroker, or the addon errors on load.
- Consider extracting all magic IDs (widget, currency) and the zone-boundary
  table into `Config.lua` so patches need a one-file edit.
