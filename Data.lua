-- =============================================================================
--  PreyHub — Data.lua
--  Hunt data from map pins, reward caching, filtering and sorting.
-- =============================================================================

local PH = _G.PreyHub
local CFG = PH.CFG

-- ---------------------------------------------------------------------------
-- Hunt list — repopulated each time the map opens
-- ---------------------------------------------------------------------------
PH.liveHunts   = {}
PH.rewardCache = {}  -- [questID] = { {name, icon, count}, ... }

-- ---------------------------------------------------------------------------
-- Parsing helpers
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
    if y > 0.55              then return "Zul'Aman"       end
    return "Eversong Woods"
end

-- ---------------------------------------------------------------------------
-- Pin access
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
    wipe(PH.liveHunts)
    local pool = GetPinPool()
    if not pool then return end
    for pin in pool:EnumerateActive() do
        if pin.questID and pin.title then
            PH.liveHunts[#PH.liveHunts + 1] = {
                name       = pin.title,
                difficulty = ParseDifficulty(pin.description),
                questID    = pin.questID,
                zone       = GetZoneFromCoords(pin.normalizedX, pin.normalizedY),
            }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Reward caching — reads from the quest dialog invisibly, caches per questID
-- ---------------------------------------------------------------------------
local function GetRewardIcon(name)
    for _, entry in ipairs(PH.REWARD_ICONS) do
        if name:find(entry.match, 1, true) then return entry.icon end
    end
    return PH.FALLBACK_ICON
end

local REWARD_SORT_ORDER = {
    ["Dawncrest"] = 1,  -- crests first
    ["Chest"]     = 2,
    ["Sack"]      = 3,
    ["Journey"]   = 4,
}

local function RewardSortKey(name)
    for pattern, order in pairs(REWARD_SORT_ORDER) do
        if name:find(pattern, 1, true) then return order end
    end
    return 99
end

function PH.GetRewards(questID)
    if PH.rewardCache[questID] ~= nil then return PH.rewardCache[questID] end

    local dialog = AdventureMapQuestChoiceDialog
    if not (dialog and dialog.ShowWithQuest) then
        return {}  -- don't cache — dialog may not be ready yet
    end

    local prevAlpha = dialog:GetAlpha()
    dialog:SetAlpha(0)
    dialog:Hide()  -- always start from a clean state
    dialog:ShowWithQuest(CovenantMissionFrame, PH.FindPin(questID), questID)

    local rewards = {}
    if dialog.rewardPool then
        for reward in dialog.rewardPool:EnumerateActive() do
            local name  = reward.Name  and reward.Name:GetText()
            local count = reward.Count and reward.Count:GetText()
            if name and name ~= "" then
                rewards[#rewards + 1] = {
                    name      = name,
                    icon      = GetRewardIcon(name),
                    count     = (count and count ~= "" and count ~= "1") and count or nil,
                    sortOrder = RewardSortKey(name),
                }
            end
        end
    end

    table.sort(rewards, function(a, b) return a.sortOrder < b.sortOrder end)

    dialog:Hide()
    dialog:SetAlpha(prevAlpha)

    PH.rewardCache[questID] = rewards
    return rewards
end

-- Warm the cache for all live hunts — call this before RefreshRows
function PH.WarmRewardCache()
    wipe(PH.rewardCache)
    for _, hunt in ipairs(PH.liveHunts) do
        PH.GetRewards(hunt.questID)
    end
end
PH.filter = { difficulty = "All" }

function PH.IsInProgress(questID)
    return C_QuestLog.IsOnQuest(questID) == true
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