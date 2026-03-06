-- =============================================================================
--  PreyHub — UI.lua
--  Panel, filter bar, row pool, minimap button. No game logic here.
-- =============================================================================

local PH = _G.PreyHub
local CFG = PH.CFG

-- ---------------------------------------------------------------------------
-- Row pool
-- ---------------------------------------------------------------------------
local rowPool   = {}
local activeRows = {}

PH.panel      = nil
PH.scrollChild = nil

local function MakeRewardIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(CFG.ICON_SIZE, CFG.ICON_SIZE)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT",     f, "TOPLEFT",      2, -2)
    f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2,  2)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints()
    f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    f.border:SetAlpha(0.7)
    f:Hide()
    return f
end

local function AcquireRow()
    if #rowPool > 0 then
        local r = table.remove(rowPool)
        r:Show()
        return r
    end

    local row = CreateFrame("Button", nil, PH.scrollChild)
    row:SetHeight(CFG.ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetWidth(4)
    row.stripe:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
    row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -7)
    row.nameText:SetWidth(CFG.PANEL_WIDTH - 105)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(true)

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statusText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)

    row.rewardIcons = {}
    for i = 1, 4 do
        local ic = MakeRewardIcon(row)
        ic:SetPoint(
            i == 1 and "BOTTOMLEFT" or "LEFT",
            i == 1 and row or row.rewardIcons[i-1],
            i == 1 and "BOTTOMLEFT" or "RIGHT",
            i == 1 and 14 or 3,
            i == 1 and 7  or 0)
        row.rewardIcons[i] = ic
    end

    row.diffBadge = CreateFrame("Frame", nil, row)
    row.diffBadge:SetSize(72, 18)
    row.diffBadge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -6)
    row.diffBadge.bg = row.diffBadge:CreateTexture(nil, "BACKGROUND")
    row.diffBadge.bg:SetAllPoints()
    row.diffBadge.text = row.diffBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.diffBadge.text:SetAllPoints()
    row.diffBadge.text:SetJustifyH("CENTER")

    row.acceptBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.acceptBtn:SetSize(72, 22)
    row.acceptBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 6)
    row.acceptBtn:SetText("|cff44ff44Accept|r")
    row.acceptBtn:SetPropagateMouseClicks(false)

    row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.zoneText:SetPoint("BOTTOMRIGHT", row.acceptBtn, "TOPRIGHT", 0, 4)
    row.zoneText:SetJustifyH("RIGHT")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    local sep = row:CreateTexture(nil, "OVERLAY")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.3, 0.3, 0.4, 0.4)

    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    rowPool[#rowPool + 1] = row
end

-- ---------------------------------------------------------------------------
-- Row population
-- ---------------------------------------------------------------------------
local function PopulateRow(row, hunt)
    local inprog  = PH.IsInProgress(hunt.questID)
    local dc      = CFG.DIFF_COLOR[hunt.difficulty] or CFG.DIFF_COLOR.Normal
    local zc      = PH.GetZoneColor(hunt.zone)
    local rewards = PH.rewardCache[hunt.questID] or {}

    if inprog then
        row.bg:SetColorTexture(0.18, 0.12, 0.00, 0.85)
        row.nameText:SetTextColor(1.00, 0.90, 0.30)
        row.statusText:SetText("|cffffd700⚔ In Progress|r")
        row.acceptBtn:Hide()
    else
        row.bg:SetColorTexture(0, 0, 0, 0.55)
        row.nameText:SetTextColor(1, 1, 1)
        row.statusText:SetText("|cff44ddffAvailable|r")
        row.acceptBtn:Show()
        row.acceptBtn:SetScript("OnClick", function()
            local dialog = AdventureMapQuestChoiceDialog
            if not (dialog and dialog.ShowWithQuest and dialog.AcceptQuest) then return end
            dialog:SetAlpha(1)
            dialog:ClearAllPoints()
            dialog:SetPoint("CENTER", UIParent, "CENTER")
            dialog:ShowWithQuest(CovenantMissionFrame, PH.FindPin(hunt.questID), hunt.questID)
            dialog:AcceptQuest()
            HideUIPanel(CovenantMissionFrame)
        end)
    end
    row.nameText:SetText(hunt.name)

    row.stripe:SetColorTexture(zc.r, zc.g, zc.b, 0.9)
    row.zoneText:SetText(hunt.zone or "")
    row.zoneText:SetTextColor(zc.r * 1.4, zc.g * 1.4, zc.b * 1.4)

    row.diffBadge.bg:SetColorTexture(dc.r * 0.22, dc.g * 0.22, dc.b * 0.22, 0.90)
    row.diffBadge.text:SetText(hunt.difficulty)
    row.diffBadge.text:SetTextColor(dc.r, dc.g, dc.b)

    for i, ic in ipairs(row.rewardIcons) do
        local r = rewards[i]
        if r then
            ic.tex:SetTexture(r.icon)
            ic:Show()
            ic:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(r.count and (r.name .. " x" .. r.count) or r.name, 1, 1, 1)
                GameTooltip:Show()
            end)
            ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            ic:Hide()
        end
    end

    row:SetScript("OnClick", function()
        local dialog = AdventureMapQuestChoiceDialog
        if dialog then
            dialog:SetAlpha(1)
            dialog:ClearAllPoints()
            dialog:SetPoint("CENTER", UIParent, "CENTER")
        end
        local pin = PH.FindPin(hunt.questID)
        if not pin then return end
        local dp = pin:GetDataProvider()
        if dp and dp.OnQuestOfferPinClicked then
            dp:OnQuestOfferPinClicked(pin)
        end
    end)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(hunt.name, 1, 1, 1)
        GameTooltip:AddLine(hunt.difficulty, dc.r, dc.g, dc.b)
        GameTooltip:AddLine(hunt.zone or "Unknown", zc.r * 1.4, zc.g * 1.4, zc.b * 1.4)
        GameTooltip:AddLine(inprog and "|cffffd700⚔ In Progress|r" or "|cff44ddffAvailable|r")
        if #rewards > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Rewards:", 1, 0.82, 0)
            for _, r in ipairs(rewards) do
                GameTooltip:AddLine(r.count and (r.name .. " x" .. r.count) or r.name, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ---------------------------------------------------------------------------
-- Refresh rows
-- ---------------------------------------------------------------------------
function PH.RefreshRows()
    for _, r in ipairs(activeRows) do ReleaseRow(r) end
    wipe(activeRows)

    local y = 0
    for _, hunt in ipairs(PH.GetSortedHunts()) do
        local row = AcquireRow()
        row:SetParent(PH.scrollChild)
        row:SetWidth(CFG.PANEL_WIDTH - 4)
        row:SetPoint("TOPLEFT",  PH.scrollChild, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", PH.scrollChild, "TOPRIGHT", 0, -y)
        PopulateRow(row, hunt)
        y = y + CFG.ROW_HEIGHT + CFG.ROW_PADDING
        activeRows[#activeRows + 1] = row
    end
    PH.scrollChild:SetHeight(math.max(y, 1))

    local inprog = 0
    for _, h in ipairs(PH.liveHunts) do
        if PH.IsInProgress(h.questID) then inprog = inprog + 1 end
    end
    local avail = #PH.liveHunts - inprog
    local parts = {}
    if inprog > 0 then parts[#parts+1] = string.format("|cffffd700%d In Progress|r", inprog) end
    if avail  > 0 then parts[#parts+1] = string.format("|cff44ddff%d Available|r",   avail)  end
    PH.panel.summaryText:SetText(table.concat(parts, "  "))
end

-- ---------------------------------------------------------------------------
-- Filter bar
-- ---------------------------------------------------------------------------
local function CreateFilterBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(26)
    bar:SetPoint("TOPLEFT",  parent.titleBg, "BOTTOMLEFT",  4, -6)
    bar:SetPoint("TOPRIGHT", parent.titleBg, "BOTTOMRIGHT", -4, -6)

    local diffs = { "All", "Normal", "Hard", "Nightmare" }
    local pillW = math.floor((CFG.PANEL_WIDTH - 10) / #diffs) - 2
    bar.pills = {}

    for i, diff in ipairs(diffs) do
        local pill = CreateFrame("Button", nil, bar)
        pill:SetSize(pillW, 20)
        pill:SetPoint("LEFT", bar, "LEFT", (i - 1) * (pillW + 2), 0)

        pill.bg = pill:CreateTexture(nil, "BACKGROUND")
        pill.bg:SetAllPoints()
        pill.bg:SetColorTexture(0.22, 0.22, 0.32, 0.90)

        pill.label = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pill.label:SetAllPoints()
        pill.label:SetJustifyH("CENTER")
        pill.label:SetText(diff == "All" and "All" or diff:sub(1, 4))

        local hl = pill:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.10)

        pill.diffKey = diff
        bar.pills[i] = pill

        pill:SetScript("OnClick", function()
            PH.filter.difficulty = diff
            for _, p in ipairs(bar.pills) do
                local sel = p.diffKey == diff
                local c   = CFG.DIFF_COLOR[p.diffKey]
                if sel then
                    p.bg:SetColorTexture(0.55, 0.45, 0.08, 0.95)
                    p.label:SetTextColor(1, 0.9, 0.3)
                elseif c then
                    p.bg:SetColorTexture(c.r * 0.28, c.g * 0.28, c.b * 0.28, 0.90)
                    p.label:SetTextColor(1, 1, 1)
                else
                    p.bg:SetColorTexture(0.22, 0.22, 0.32, 0.90)
                    p.label:SetTextColor(1, 1, 1)
                end
            end
            PH.RefreshRows()
        end)
    end

    return bar
end

-- ---------------------------------------------------------------------------
-- Panel construction
-- ---------------------------------------------------------------------------
function PH.BuildPanel()
    if PH.panel then return end

    local panel = CreateFrame("Frame", "PreyHubPanel", UIParent, "BackdropTemplate")
    panel:SetSize(CFG.PANEL_WIDTH, CFG.PANEL_HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(200)
    panel:Hide()
    panel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 18,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    panel:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
    panel:SetBackdropBorderColor(0.45, 0.20, 0.55, 1)

    panel.titleBg = panel:CreateTexture(nil, "ARTWORK")
    panel.titleBg:SetHeight(32)
    panel.titleBg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  6, -6)
    panel.titleBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
    panel.titleBg:SetColorTexture(0.22, 0.04, 0.28, 0.95)

    panel.titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.titleText:SetPoint("LEFT", panel.titleBg, "LEFT", 10, 0)
    panel.titleText:SetText("|cffcc44ccPrey|r|cffddddddHub|r")

    panel.closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButtonNoScripts")
    panel.closeBtn:SetSize(22, 22)
    panel.closeBtn:SetPoint("TOPRIGHT", panel.titleBg, "TOPRIGHT", -2, 0)
    panel.closeBtn:SetScript("OnClick", function() panel:Hide() end)

    panel.anguishText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.anguishText:SetPoint("RIGHT", panel.titleBg, "RIGHT", -32, 0)

    local filterBar = CreateFilterBar(panel)

    panel.summaryText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.summaryText:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)

    local sf = CreateFrame("ScrollFrame", "PreyHubScroll", panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     panel.summaryText, "BOTTOMLEFT",  0, -4)
    sf:SetPoint("BOTTOMRIGHT", panel,             "BOTTOMRIGHT", -26, 8)

    PH.scrollChild = CreateFrame("Frame", nil, sf)
    PH.scrollChild:SetWidth(CFG.PANEL_WIDTH - 30)
    PH.scrollChild:SetHeight(1)
    sf:SetScrollChild(PH.scrollChild)

    PH.panel = panel
end

function PH.AnchorPanel()
    PH.panel:ClearAllPoints()
    if CovenantMissionFrame and CovenantMissionFrame:IsShown() then
        PH.panel:SetPoint("TOPLEFT", CovenantMissionFrame, "TOPRIGHT", CFG.X_OFFSET, 0)
    else
        PH.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function PH.ShowPanel()
    PH.BuildPanel()
    PH.AnchorPanel()
    PH.panel.anguishText:SetText(
        string.format("|cffdd4444%d|r Anguish", PH.GetAnguishCurrency()))
    PH.RefreshRows()
    PH.panel:Show()
end

function PH.HidePanel()
    if PH.panel then PH.panel:Hide() end
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------
function PH.CreateMinimapButton()
    local btn = CreateFrame("Button", "PreyHubMinimapBtn", Minimap)
    btn:SetSize(28, 28)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    local tex = btn:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Icons\\Achievement_Character_BloodElf_Male")
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(math.rad(230)) * 82, math.sin(math.rad(230)) * 82)

    btn:SetScript("OnClick", function()
        PH.BuildPanel()
        PH.AnchorPanel()
        if PH.panel:IsShown() then PH.HidePanel()
        else PH.RefreshFromPins() PH.ShowPanel() end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PreyHub", 1, 0.8, 0)
        GameTooltip:AddLine("Toggle Prey Hunt panel", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end