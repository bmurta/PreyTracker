-- PreyTracker — Data.lua
local PH  = PreyTracker
local CFG = PH.CFG

PH.liveHunts   = {}
PH.rewardCache = {}
local attemptCount = {}  -- [questID] = warm attempts this session

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------
local function ParseDifficulty(desc)
    if not desc then return "Normal" end
    if desc:find("Nightmare") then return "Nightmare" end
    if desc:find("Hard")      then return "Hard" end
    return "Normal"
end

local function GetZoneFromCoords(x, y)
    if not x or not y then return nil end
    if x > 0.70              then return "Harandar"      end
    if x > 0.40 and y < 0.40 then return "Voidstorm"     end
    if x > 0.32 and y > 0.55 then return "Zul'Aman"      end
    return "Eversong Woods"
end

-- ---------------------------------------------------------------------------
-- Pins
-- ---------------------------------------------------------------------------
local PIN_POOL = "AdventureMap_QuestOfferPinTemplate"

local function GetPinPool()
    local mt = CovenantMissionFrame and CovenantMissionFrame.MapTab
    return mt and mt.pinPools and mt.pinPools[PIN_POOL]
end

function PH.FindPin(questID)
    local pool = GetPinPool()
    if not pool then return nil end
    for pin in pool:EnumerateActive() do
        if pin.questID == questID then return pin end
    end
end

function PH.RefreshFromPins()
    local pool = GetPinPool()

    -- No pin pool at all (map closed, or framework not built yet). We have
    -- nothing to scan, so leave the existing/last-known hunts untouched — this
    -- is what lets /prey and the minimap render the last scan out of the map.
    if not pool then
        return #PH.liveHunts > 0
    end

    -- Collect new pins first without wiping anything yet
    local newHunts = {}
    local newIDs   = {}
    for pin in pool:EnumerateActive() do
        if pin.questID and pin.title then
            newHunts[#newHunts + 1] = {
                name       = pin.title,
                difficulty = ParseDifficulty(pin.description),
                questID    = pin.questID,
                zone       = GetZoneFromCoords(pin.normalizedX, pin.normalizedY),
            }
            newIDs[pin.questID] = true
        end
    end

    PH.lastScanTime = GetTime()   -- footer "scan age" reads this (HuntBoard.lua)

    -- Pool exists but offers no quest pins — this happens when a hunt is already
    -- in progress (Blizzard suppresses the other offers). Wiping here would drop
    -- the in-progress hunt and force a needless reward re-warm, so keep the last
    -- good scan; GetBoardHunts() re-surfaces the in-progress card from it.
    if #newHunts == 0 then
        return #PH.liveHunts > 0
    end

    -- Deduplicate: max 1 prey per (difficulty, zone) combination
    local seen    = {}
    local deduped = {}
    for _, h in ipairs(newHunts) do
        local key = h.difficulty .. ":" .. (h.zone or "")
        if not seen[key] then
            seen[key] = true
            deduped[#deduped + 1] = h
        end
    end
    newHunts = deduped

    -- Check if the set of quest IDs is identical to what we already have
    local cacheValid = (#newHunts == #PH.liveHunts)
    if cacheValid then
        for _, h in ipairs(PH.liveHunts) do
            if not newIDs[h.questID] then
                cacheValid = false
                break
            end
        end
    end

    if cacheValid then
        -- Same hunts — just refresh the hunt list (names/zones may have updated)
        -- but keep rewardCache intact so we don't reload
        wipe(PH.liveHunts)
        for _, h in ipairs(newHunts) do
            PH.liveHunts[#PH.liveHunts + 1] = h
        end
        return true   -- cache is warm
    end

    -- Different hunts — full reset
    wipe(PH.liveHunts)
    wipe(PH.rewardCache)
    wipe(attemptCount)
    for _, h in ipairs(newHunts) do
        PH.liveHunts[#PH.liveHunts + 1] = h
    end
    return false  -- cache needs warming
end

-- ---------------------------------------------------------------------------
-- Reward helpers
-- ---------------------------------------------------------------------------
local function IsXPNumber(s)
    -- Matches strings like "19415" or "19,415" with no alphabetic characters
    return s:match("^[%d,]+$") ~= nil
end

local function GetRewardIcon(name)
    if IsXPNumber(name) then return "Interface\\Icons\\xp_icon" end
    for _, entry in ipairs(PH.REWARD_ICONS) do
        if name:find(entry.match, 1, true) then return entry.icon end
    end
    return PH.FALLBACK_ICON
end

-- Ordered list so "Hero Dawncrest" (order 1) is checked before the generic
-- "Dawncrest" pattern (order 2), preventing Hero from matching the wrong bucket.
local REWARD_SORT = {
    { match = "Hero Dawncrest",  order = 1 },
    { match = "Dawncrest",       order = 2 },
    { match = "Chest",           order = 3 },
    { match = "Sack",            order = 3 },
    { match = "Coffer Key Shard",order = 4 },
    { match = "Journey",         order = 5 },
}
local function RewardSortKey(name)
    for _, entry in ipairs(REWARD_SORT) do
        if name:find(entry.match, 1, true) then return entry.order end
    end
    return 99
end

-- Snapshot the current reward pool for whatever quest is showing in the dialog.
local function SnapshotPool()
    local dialog = AdventureMapQuestChoiceDialog
    if not (dialog and dialog.rewardPool) then return {} end
    local rewards = {}
    for reward in dialog.rewardPool:EnumerateActive() do
        local name  = reward.Name  and reward.Name:GetText()
        local count = reward.Count and reward.Count:GetText()
        if name and name ~= "" then
            local displayName = IsXPNumber(name) and ("Player Experience (" .. name .. ")") or name
            rewards[#rewards + 1] = {
                name      = displayName,
                icon      = GetRewardIcon(name),
                count     = (count and count ~= "" and count ~= "1") and count or nil,
                sortOrder = IsXPNumber(name) and 5 or RewardSortKey(name),
            }
        end
    end
    table.sort(rewards, function(a, b) return a.sortOrder < b.sortOrder end)
    return rewards
end

-- ---------------------------------------------------------------------------
-- Sequential async warmer
--
-- Processes one quest at a time. For each quest:
--   1. ShowWithQuest (dialog hidden) to trigger server item data fetch.
--   2. Poll SnapshotPool every POLL_MS until the reward count is identical
--      for STABLE_NEEDED consecutive polls — meaning the pool has settled.
--   3. If count stays 0 for too long, or total time exceeds TIMEOUT_S, give up.
--   4. Commit result, call onProgress, move to next quest.
--
-- If a quest times out with 0 rewards and has been attempted fewer than
-- MAX_ATTEMPTS times this session, it is left as nil in the cache so it will
-- be re-queued on the next warm call (i.e. next time the map is opened).
-- After MAX_ATTEMPTS failures it is accepted as genuinely reward-less.
-- ---------------------------------------------------------------------------
local POLL_MS       = 0.10
local STABLE_NEEDED = 3
local TIMEOUT_S     = 4.0
local MAX_ATTEMPTS  = 3   -- retries across map opens before accepting empty

function PH.WarmRewardCacheAsync(onProgress, onDone)
    local dialog = AdventureMapQuestChoiceDialog
    if not (dialog and dialog.ShowWithQuest) then
        C_Timer.After(0.4, function() PH.WarmRewardCacheAsync(onProgress, onDone) end)
        return
    end

    -- Only queue quests not yet cached
    local queue = {}
    for _, hunt in ipairs(PH.liveHunts) do
        if PH.rewardCache[hunt.questID] == nil then
            queue[#queue + 1] = hunt
        end
    end

    local total     = #PH.liveHunts
    local doneCount = total - #queue

    if #queue == 0 then
        if onDone then onDone() end
        return
    end

    local prevAlpha = dialog:GetAlpha()
    local cancelled = false
    local ticker    = nil

    PH._rewardWarmCancel = function()
        cancelled = true
        if ticker then ticker:Cancel(); ticker = nil end
        dialog:Hide()
        dialog:SetAlpha(prevAlpha)
        PH._rewardWarmCancel = nil
    end

    local StartNext
    local qIdx      = 1
    local elapsed   = 0
    local lastCount = -1
    local stableN   = 0

    local function CleanupTicker()
        if ticker then ticker:Cancel(); ticker = nil end
    end

    local function CommitAndAdvance(rewards, timedOutEmpty)
        CleanupTicker()
        dialog:Hide()
        dialog:SetAlpha(prevAlpha)

        local questID = queue[qIdx].questID
        if timedOutEmpty then
            -- Timed out with no rewards — decide whether to accept or retry
            attemptCount[questID] = (attemptCount[questID] or 0) + 1
            if attemptCount[questID] >= MAX_ATTEMPTS then
                -- Exhausted retries — accept as genuinely reward-less
                PH.rewardCache[questID] = {}
            else
                -- Leave cache nil so next map open re-queues this quest
                PH.rewardCache[questID] = nil
            end
        else
            -- Got real rewards (or no-pin skip) — commit and clear attempt counter
            PH.rewardCache[questID] = rewards
            attemptCount[questID]   = nil
        end

        doneCount = doneCount + 1
        if onProgress then onProgress(doneCount, total) end

        qIdx = qIdx + 1
        if qIdx > #queue then
            PH._rewardWarmCancel = nil
            if onDone then onDone() end
            return
        end

        C_Timer.After(0.05, function()
            if cancelled then return end
            StartNext()
        end)
    end

    StartNext = function()
        if cancelled then return end
        elapsed   = 0
        lastCount = -1
        stableN   = 0

        local hunt = queue[qIdx]
        local pin  = PH.FindPin(hunt.questID)
        if not pin then
            CommitAndAdvance({}, false)
            return
        end

        dialog:SetAlpha(0)
        dialog:Hide()
        dialog:ShowWithQuest(CovenantMissionFrame, pin, hunt.questID)

        ticker = C_Timer.NewTicker(POLL_MS, function()
            if cancelled then return end
            elapsed = elapsed + POLL_MS

            local rewards = SnapshotPool()
            local n = #rewards

            if n > 0 and n == lastCount then
                stableN = stableN + 1
                if stableN >= STABLE_NEEDED then
                    CommitAndAdvance(rewards, false)
                    return
                end
            else
                stableN   = 0
                lastCount = n
            end

            if elapsed >= TIMEOUT_S then
                -- Pass timedOutEmpty=true only if we got nothing at all
                CommitAndAdvance(rewards, #rewards == 0)
            end
        end)
    end

    StartNext()
end

function PH.WarmRewardCache() end  -- legacy stub

-- ---------------------------------------------------------------------------
-- State helpers
-- ---------------------------------------------------------------------------
PH.filter = { difficulty = "All" }

function PH.IsInProgress(questID)
    return C_QuestLog.IsOnQuest(questID) == true
end

-- ---------------------------------------------------------------------------
-- Durable cache (PreyTrackerDB)
--
-- The Hunt Board is now the experience everywhere, including out of the map
-- where there are no pins to scrape. We persist the last good scan (hunts +
-- rewards) per character so /prey and the minimap button can render from it,
-- and so an in-progress hunt — whose offer pin Blizzard hides once accepted —
-- still has a home on the grid when the map is reopened.
-- ---------------------------------------------------------------------------

-- Rewards for a quest, preferring the live session cache and falling back to
-- the persisted snapshot (so out-of-map / post-accept cards still show icons).
function PH.RewardsFor(questID)
    return PH.rewardCache[questID]
        or (PreyTrackerDB and PreyTrackerDB.cachedRewards and PreyTrackerDB.cachedRewards[questID])
        or {}
end

-- The hunts the board should render: the live pin scan first (freshest), then
-- any persisted hunt that's currently in progress but absent from the live set
-- (its offer pin is gone). Deduped on (zone, difficulty) — the board invariant —
-- so a live cell is never shadowed by a stale persisted one.
function PH.GetBoardHunts()
    local out, seenCell = {}, {}
    local function add(h)
        if not (h.zone and h.difficulty) then return end
        local key = h.zone .. "|" .. h.difficulty
        if seenCell[key] then return end
        seenCell[key] = true
        out[#out + 1] = h
    end
    for _, h in ipairs(PH.liveHunts) do add(h) end
    local cached = PreyTrackerDB and PreyTrackerDB.cachedHunts
    if cached then
        local haveLive = #PH.liveHunts > 0
        for _, h in ipairs(cached) do
            -- Always re-surface an in-progress hunt that's missing from the live
            -- pins; when there are no live pins at all (out of the map, or a hunt
            -- is in progress and Blizzard hid every offer), fall back to the full
            -- cached set so the other cells still render as available cards.
            if (not haveLive) or PH.IsInProgress(h.questID) then add(h) end
        end
    end
    return out
end

-- Is any known hunt (live or cached) currently in progress? Used by Core.lua to
-- show the board promptly when the map opens mid-hunt and no offer pins exist.
function PH.HasInProgressHunt()
    for _, h in ipairs(PH.GetBoardHunts()) do
        if PH.IsInProgress(h.questID) then return true end
    end
    return false
end

-- Persist the current board view (merged hunts + their rewards). Saving the
-- merged set — not raw liveHunts — keeps an in-progress hunt that's missing
-- from the live pins from being dropped on the next scan. Never overwrites a
-- good cache with nothing.
function PH.SaveCache()
    if not PreyTrackerDB then PreyTrackerDB = {} end
    local hunts = PH.GetBoardHunts()
    if #hunts == 0 then return end
    local savedHunts, savedRewards = {}, {}
    for _, h in ipairs(hunts) do
        savedHunts[#savedHunts + 1] = {
            name = h.name, difficulty = h.difficulty, questID = h.questID, zone = h.zone,
        }
        local r = PH.RewardsFor(h.questID)
        if r and #r > 0 then savedRewards[h.questID] = r end
    end
    PreyTrackerDB.cachedHunts   = savedHunts
    PreyTrackerDB.cachedRewards = savedRewards
    PreyTrackerDB.lastScanEpoch = time()
end

-- Seed the live working set from the persisted snapshot at login, so the board
-- has data before the map is ever opened this session. Only fills gaps — a live
-- scan that has already happened wins.
function PH.LoadCache()
    if not PreyTrackerDB then return end
    if #PH.liveHunts == 0 and PreyTrackerDB.cachedHunts then
        for _, h in ipairs(PreyTrackerDB.cachedHunts) do
            PH.liveHunts[#PH.liveHunts + 1] = {
                name = h.name, difficulty = h.difficulty, questID = h.questID, zone = h.zone,
            }
        end
    end
    if PreyTrackerDB.cachedRewards then
        for qid, r in pairs(PreyTrackerDB.cachedRewards) do
            if PH.rewardCache[qid] == nil then PH.rewardCache[qid] = r end
        end
    end
end

function PH.GetZoneColor(zone)
    return CFG.ZONE_COLOR[zone] or CFG.ZONE_COLOR.DEFAULT
end

function PH.GetAnguishCurrency()
    local info = C_CurrencyInfo.GetCurrencyInfo(CFG.ANGUISH_CURRENCY_ID)
    return info and info.quantity or 0
end

function PH.GetSortedHunts()
    local out = {}
    for _, h in ipairs(PH.liveHunts) do
        if PH.filter.difficulty == "All" or h.difficulty == PH.filter.difficulty then
            out[#out + 1] = h
        end
    end
    table.sort(out, function(a, b)
        local da, db = PH.DIFF_ORDER[a.difficulty] or 3, PH.DIFF_ORDER[b.difficulty] or 3
        if da ~= db then return da < db end
        local za, zb = PH.ZONE_ORDER[a.zone] or 5, PH.ZONE_ORDER[b.zone] or 5
        if za ~= zb then return za < zb end
        local ia = PH.IsInProgress(a.questID) and 0 or 1
        local ib = PH.IsInProgress(b.questID) and 0 or 1
        if ia ~= ib then return ia < ib end
        return a.name < b.name
    end)
    return out
end