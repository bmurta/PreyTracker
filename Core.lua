-- PreyHub — Core.lua
PreyHub = PreyHub or {}
local PH = PreyHub

local hookApplied = false
local function HookMissionFrame()
    if hookApplied then return end

    hooksecurefunc("ShowUIPanel", function(frame)
        if frame and frame:GetName() == "CovenantMissionFrame" then
            -- Poll until the pin pool stops growing, then proceed.
            -- This handles slow clients where pins trickle in after the frame opens.
            local PIN_POLL     = 0.15  -- check interval
            local STABLE_READS = 3     -- identical non-zero counts before committing
            local MAX_WAIT     = 6.0   -- give up after this long
            local lastCount    = -1
            local stableN      = 0
            local elapsed      = 0
            local ticker

            local function Proceed()
                if ticker then ticker:Cancel(); ticker = nil end
                if not (CovenantMissionFrame and CovenantMissionFrame:IsShown()) then return end

                PH.standalone = false
                PH.RefreshFromPins()

                local cacheWarm = true
                for _, h in ipairs(PH.liveHunts) do
                    if PH.rewardCache[h.questID] == nil then
                        cacheWarm = false
                        break
                    end
                end

                if cacheWarm then
                    PH.ShowPanel()
                    return
                end

                PH.ShowLoadingFrame(0, #PH.liveHunts)
                PH.WarmRewardCacheAsync(
                    function(done, total)
                        if CovenantMissionFrame and CovenantMissionFrame:IsShown() then
                            PH.ShowLoadingFrame(done, total)
                        end
                    end,
                    function()
                        if CovenantMissionFrame and CovenantMissionFrame:IsShown() then
                            PH.ShowPanel()
                        else
                            PH.HideLoadingFrame()
                        end
                    end
                )
            end

            local function CountPins()
                local pool = CovenantMissionFrame
                    and CovenantMissionFrame.MapTab
                    and CovenantMissionFrame.MapTab.pinPools
                    and CovenantMissionFrame.MapTab.pinPools["AdventureMap_QuestOfferPinTemplate"]
                if not pool then return 0 end
                local n = 0
                for _ in pool:EnumerateActive() do n = n + 1 end
                return n
            end

            ticker = C_Timer.NewTicker(PIN_POLL, function()
                if not (CovenantMissionFrame and CovenantMissionFrame:IsShown()) then
                    ticker:Cancel(); ticker = nil
                    return
                end
                elapsed = elapsed + PIN_POLL
                local n = CountPins()
                if n > 0 and n == lastCount then
                    stableN = stableN + 1
                    if stableN >= STABLE_READS then
                        Proceed()
                    end
                else
                    stableN   = 0
                    lastCount = n
                end
                if elapsed >= MAX_WAIT then
                    Proceed()
                end
            end)
        end
    end)

    hooksecurefunc("HideUIPanel", function(frame)
        if frame and frame:GetName() == "CovenantMissionFrame" then
            PH.HidePanel()
        end
    end)

    local elapsed = 0
    local watchdog = CreateFrame("Frame")
    watchdog:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if CovenantMissionFrame and not CovenantMissionFrame:IsShown() then
            -- HidePanel is a no-op in standalone mode, so this is safe
            if PH.panel and PH.panel:IsShown() then
                PH.HidePanel()
            end
        end
    end)

    hookApplied = true
end

SLASH_PREYHUB1 = "/prey"
SLASH_PREYHUB2 = "/preyhub"
SlashCmdList["PREYHUB"] = function(msg)
    local cmd = msg:lower():match("^%s*(.-)%s*$")
    if cmd == "hide" then
        PH.ForceHidePanel()
    elseif cmd == "reset" then
        PH.BuildPanel()
        PH.panel:ClearAllPoints()
        PH.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        PH.standalone = true
        PH.ShowPanel()
    else
        PH.BuildPanel()
        if PH.panel:IsShown() and cmd ~= "show" then
            PH.ForceHidePanel()
        else
            PH.standalone = true
            PH.RefreshFromPins()
            local cacheWarm = true
            for _, h in ipairs(PH.liveHunts) do
                if PH.rewardCache[h.questID] == nil then cacheWarm = false; break end
            end
            if cacheWarm then
                PH.ShowPanel()
            else
                PH.ShowLoadingFrame(0, #PH.liveHunts)
                PH.WarmRewardCacheAsync(
                    function(done, total) PH.ShowLoadingFrame(done, total) end,
                    function() PH.ShowPanel() end
                )
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "PreyHub" then
        HookMissionFrame()
        PH.CreateMinimapButton()
        print("|cffcc44ccPreyHub|r loaded. /prey to toggle.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        HookMissionFrame()

    elseif event == "QUEST_LOG_UPDATE" then
        if PH.panel and PH.panel:IsShown() then PH.RefreshRows() end

    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        if PH.panel and PH.panel:IsShown() then
            PH.panel.anguishText:SetText(
                string.format("|cffdd4444%d|r Anguish", PH.GetAnguishCurrency()))
        end
    end
end)