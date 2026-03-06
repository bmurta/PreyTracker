-- =============================================================================
--  PreyHub — Core.lua
--  Addon entry point: global table, hooks, events, slash commands.
--  Load order: Core → Config → Data → UI
-- =============================================================================

-- Global namespace — created first so all files can reference it
_G.PreyHub = {}
local PH = _G.PreyHub

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------
local hookApplied = false
local function HookMissionFrame()
    if hookApplied then return end

    hooksecurefunc("ShowUIPanel", function(frame)
        if frame and frame:GetName() == "CovenantMissionFrame" then
            C_Timer.After(0.5, function()
                PH.RefreshFromPins()
                PH.WarmRewardCache()
                PH.ShowPanel()
            end)
        end
    end)

    hooksecurefunc("HideUIPanel", function(frame)
        if frame and frame:GetName() == "CovenantMissionFrame" then
            PH.HidePanel()
        end
    end)

    -- Watchdog: catches cases where the frame closes without HideUIPanel firing.
    -- Throttled to once per second to avoid per-frame overhead.
    local elapsed = 0
    local watchdog = CreateFrame("Frame")
    watchdog:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if PH.panel and PH.panel:IsShown()
           and CovenantMissionFrame and not CovenantMissionFrame:IsShown() then
            PH.HidePanel()
        end
    end)

    hookApplied = true
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_PREYHUB1 = "/prey"
SLASH_PREYHUB2 = "/preyhub"
SlashCmdList["PREYHUB"] = function(msg)
    local cmd = msg:lower():match("^%s*(.-)%s*$")
    PH.BuildPanel()
    if cmd == "hide" then
        PH.HidePanel()
    elseif cmd == "reset" then
        PH.panel:ClearAllPoints()
        PH.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        PH.RefreshFromPins()
        PH.ShowPanel()
    else
        -- "show" or bare toggle
        if PH.panel:IsShown() and cmd ~= "show" then PH.HidePanel()
        else PH.RefreshFromPins() PH.ShowPanel() end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "PreyHub" then
        HookMissionFrame()
        PH.CreateMinimapButton()
        print("|cffcc44ccPreyHub|r loaded — /prey to toggle.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        HookMissionFrame()  -- safe no-op if already applied

    elseif event == "QUEST_LOG_UPDATE" then
        if PH.panel and PH.panel:IsShown() then PH.RefreshRows() end

    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        if PH.panel and PH.panel:IsShown() then
            PH.panel.anguishText:SetText(
                string.format("|cffdd4444%d|r Anguish", PH.GetAnguishCurrency()))
        end
    end
end)