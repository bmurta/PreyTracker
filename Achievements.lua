-- PreyTracker — Achievements.lua
-- Phase 4 of the Hunt Board revamp (HUNTBOARD_SPEC.md §Achievement tracking):
-- joins the "Prey: Nightmare Mode III" achievement to the on-board Nightmare
-- hunts so the board can show, per Nightmare card, whether that hunt's criterion
-- is already done (trophy vs. green check), and drive the footer progress bar +
-- the trophy tooltip's remaining-criteria list.
--
-- There is no clean "achievement by name" API, and on the PTR the numeric ID
-- drifts between builds, so we resolve the ID by *name*: try the cached id from a
-- previous session, then any hardcoded fallback, then a full category scan — each
-- candidate verified by name (and walked through its I→II→III series chain) so a
-- stale id can never surface the wrong achievement. The resolved id is cached in
-- PreyTrackerAccountDB so later sessions skip the scan.
--
-- The criteria→hunt join is a NAME match (exact-normalized, then substring),
-- English-only just like the difficulty parsing in Data.lua. See ARCHITECTURE.md
-- §14 for the fragility this introduces.
--
-- Load order (CLAUDE.md): runs after HuntBoard.lua; everything here is only ever
-- called at runtime (board populate / Core.lua achievement events), never
-- captured by value at load.
local PH = PreyTracker

-- The achievement we join against. TARGET_NAME is authoritative for the search;
-- FALLBACK_IDS is a maintainer escape hatch (drop a known id here if a future
-- build ever breaks the category scan) — each is still verified by name before
-- use, so a wrong guess is skipped, not trusted.
local TARGET_NAME = "Prey: Nightmare Mode III"
local FALLBACK_IDS = {
    -- 41234,   -- example: paste the real id here if the scan ever fails
}

-- Live achievement state, refreshed from the API on demand (board populate /
-- CRITERIA_UPDATE). `criteria` is the ordered list; `byNorm` indexes it by
-- normalized name for the exact-match fast path.
PH.achievement = {
    id        = nil,
    name      = nil,
    resolved  = false,   -- id locked in for the session
    scanned   = false,   -- the (expensive) full category scan has been tried
    criteria  = {},      -- { { name=, done=, norm= }, ... }
    byNorm    = {},       -- norm -> entry
    completed = 0,
    total     = 0,
}

-- Normalize a name for fuzzy matching: lowercase, drop everything non-alphanumeric
-- so "Grothoz, the Burning Shadow" and "Slay Grothoz the Burning Shadow" collapse
-- toward each other. English-only (same caveat as difficulty parsing).
local function Norm(s)
    return s and s:lower():gsub("[^%w]", "") or ""
end

-- ---------------------------------------------------------------------------
-- ID resolution (by name, with caching + series-chain walking)
-- ---------------------------------------------------------------------------
local function NameOf(id)
    if not id then return nil end
    local _, name = GetAchievementInfo(id)
    return name
end

-- Walk an achievement's I→II→III series forward from `id`, returning the node
-- whose name is TARGET_NAME (or nil). The category list surfaces only the
-- currently-relevant node of a series, so the III we want is often a couple of
-- GetNextAchievement hops away.
local function WalkChain(id)
    local guard = 0
    while id and guard < 16 do
        if NameOf(id) == TARGET_NAME then return id end
        id = GetNextAchievement(id)
        guard = guard + 1
    end
    return nil
end

-- Last resort: scan every achievement category for the target name. Heavy, so
-- it runs at most once per session (guarded by a.scanned); cheap once the
-- client's achievement data has loaded.
local function ScanCategories()
    if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then
        return nil
    end
    for _, cat in ipairs(GetCategoryList()) do
        local n = GetCategoryNumAchievements(cat, true) or 0
        for i = 1, n do
            local id, name = GetAchievementInfo(cat, i)
            if id then
                if name == TARGET_NAME then return id end
                local chained = WalkChain(id)
                if chained then return chained end
            end
        end
    end
    return nil
end

local function SaveID(id)
    PreyTrackerAccountDB = PreyTrackerAccountDB or {}
    PreyTrackerAccountDB.achievementID = id
end

-- Resolve (and cache) the achievement id. Returns the id or nil if achievement
-- data isn't available / the achievement isn't on this build yet.
local function ResolveID()
    local a = PH.achievement
    if a.resolved then return a.id end
    if not GetAchievementInfo then return nil end

    -- 1. cached from a previous session — re-verify by name (PTR id drift).
    local cached = PreyTrackerAccountDB and PreyTrackerAccountDB.achievementID
    if cached then
        local id = WalkChain(cached)
        if id then a.id, a.name, a.resolved = id, TARGET_NAME, true; SaveID(id); return id end
    end

    -- 2. hardcoded fallback(s) — also verified by name.
    for _, guess in ipairs(FALLBACK_IDS) do
        local id = WalkChain(guess)
        if id then a.id, a.name, a.resolved = id, TARGET_NAME, true; SaveID(id); return id end
    end

    -- 3. full category scan, once per session.
    if not a.scanned then
        a.scanned = true
        local id = ScanCategories()
        if id then a.id, a.name, a.resolved = id, TARGET_NAME, true; SaveID(id); return id end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Reading criteria
-- ---------------------------------------------------------------------------
-- Re-read the achievement's criteria into PH.achievement. Cheap; call it before
-- painting the board or on a CRITERIA_UPDATE. `force` re-runs the category scan
-- on a still-unresolved id (used by Rescan).
function PH.RefreshAchievements(force)
    local a = PH.achievement
    if force then a.scanned = false end

    local id = ResolveID()
    if not id then
        wipe(a.criteria); wipe(a.byNorm)
        a.completed, a.total = 0, 0
        return false
    end

    local _, name = GetAchievementInfo(id)
    if name then a.name = name end

    local num = GetAchievementNumCriteria(id) or 0
    wipe(a.criteria); wipe(a.byNorm)
    local done = 0
    for i = 1, num do
        local cName, _, cDone = GetAchievementCriteriaInfo(id, i)
        if cName and cName ~= "" then
            local entry = { name = cName, done = cDone and true or false, norm = Norm(cName) }
            a.criteria[#a.criteria + 1] = entry
            a.byNorm[entry.norm] = entry
            if entry.done then done = done + 1 end
        end
    end
    a.completed, a.total = done, #a.criteria

    -- Defensive fallback: some achievements expose a single progress-bar
    -- criterion ("Defeat 12 nightmare preys") instead of one criterion per prey.
    -- Per-card chips can't name-match that, but keep the footer count meaningful.
    if a.total == 1 then
        local _, _, _, quantity, reqQuantity = GetAchievementCriteriaInfo(id, 1)
        if reqQuantity and reqQuantity > 1 then
            a.completed, a.total = quantity or 0, reqQuantity
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Board-facing queries
-- ---------------------------------------------------------------------------
-- Is the criterion for this hunt complete? true / false, or nil when there's no
-- matching criterion (achievement unresolved, single-bar criterion, or a name
-- that doesn't line up) — the board treats nil as "still needed" (trophy).
function PH.HuntAchievementDone(huntName)
    local a = PH.achievement
    if not huntName or a.total == 0 then return nil end
    local hn = Norm(huntName)
    if hn == "" then return nil end

    -- Exact (normalized) match first.
    local exact = a.byNorm[hn]
    if exact then return exact.done end

    -- Substring fallback, either direction (handles "Slay <name>" criteria).
    for _, c in ipairs(a.criteria) do
        if c.norm ~= "" and (c.norm:find(hn, 1, true) or hn:find(c.norm, 1, true)) then
            return c.done
        end
    end
    return nil
end

-- name, completed, total — for the footer label + progress bar.
function PH.GetAchievementSummary()
    local a = PH.achievement
    return a.name or TARGET_NAME, a.completed or 0, a.total or 0
end

-- Ordered list of not-yet-complete criterion names — for the trophy tooltip.
function PH.GetRemainingCriteria()
    local out = {}
    for _, c in ipairs(PH.achievement.criteria) do
        if not c.done then out[#out + 1] = c.name end
    end
    return out
end
