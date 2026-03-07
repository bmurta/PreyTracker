-- PreyHub — UI.lua
local PH  = PreyHub
local CFG = PH.CFG

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Layout constants
local TITLE_H     = 40
local FILTER_PAD  = 8
local FILTER_H    = 28
local SUMMARY_PAD = 8
local SUMMARY_H   = 16
local TOP_CONTENT = TITLE_H + FILTER_PAD + FILTER_H + SUMMARY_PAD + SUMMARY_H + 6

local function GetRowW()
    local panelW = (PH.standalone and CFG.PANEL_WIDTH_STANDALONE or CFG.PANEL_WIDTH)
    return panelW - 30
end

-- Subtle per-difficulty row background tints (very low saturation, just enough to read)
local DIFF_ROW_BG = {
    Normal    = { r = 0.055, g = 0.075, b = 0.055 },  -- very faint green
    Hard      = { r = 0.080, g = 0.068, b = 0.040 },  -- very faint amber
    Nightmare = { r = 0.090, g = 0.050, b = 0.050 },  -- very faint red
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function SolidTex(parent, r, g, b, a, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

local function AnimFadeIn(frame, dur)
    if not frame._fadeAnim then
        local ag = frame:CreateAnimationGroup()
        ag:SetToFinalAlpha(true)
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1)
        a:SetDuration(dur or 0.18)
        frame._fadeAnim = ag
    end
    frame:SetAlpha(0)
    frame._fadeAnim:Stop()
    frame._fadeAnim:Play()
end

local function AnimFadeOut(frame, dur)
    if not frame._fadeOutAnim then
        local ag = frame:CreateAnimationGroup()
        ag:SetToFinalAlpha(true)
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0)
        a:SetDuration(dur or 0.14)
        ag:SetScript("OnFinished", function() frame:Hide() end)
        frame._fadeOutAnim = ag
    end
    frame._fadeOutAnim:Stop()
    frame._fadeOutAnim:Play()
end

local function AttachPulse(obj, duration)
    local ag = obj:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.45)
    a:SetDuration(duration or 0.9)
    obj._pulse = ag
end

-- ---------------------------------------------------------------------------
-- Row pool
-- ---------------------------------------------------------------------------
local rowPool    = {}
local activeRows = {}
PH.panel       = nil
PH.scrollChild = nil

-- ---------------------------------------------------------------------------
-- Row construction
-- ---------------------------------------------------------------------------

local ICON_SIZE  = CFG.ICON_SIZE
local ICON_GAP   = 3
local ICON_LEFT  = 14   -- x from row BOTTOMLEFT
local ICON_BOT   = 8    -- y from row BOTTOMLEFT

local function MakeRewardIcon(row, index)
    -- Parent is always the row; anchor is set here so it's relative to the row
    -- and survives pool recycling (row re-parent does not break child anchors).
    local f = CreateFrame("Frame", nil, row)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT",
        ICON_LEFT + (index - 1) * (ICON_SIZE + ICON_GAP), ICON_BOT)

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT",     f, "TOPLEFT",      2, -2)
    f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2,  2)
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- slot border (WoW built-in empty slot texture)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints()
    f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    f.border:SetAlpha(0.6)

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
    row:SetSize(GetRowW(), CFG.ROW_HEIGHT)

    -- Base background (colour set per-difficulty in PopulateRow)
    row.bg = SolidTex(row, 0.055, 0.055, 0.075, 0.94)
    row.bg:SetAllPoints()

    -- In-progress amber pulse glow
    row.progressGlow = SolidTex(row, 1, 0.7, 0, 0, "BACKGROUND", -1)
    row.progressGlow:SetAllPoints()
    row.progressGlow:SetBlendMode("ADD")
    AttachPulse(row.progressGlow, 1.1)

    -- Hover highlight
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture(WHITE); hl:SetVertexColor(1,1,1,0.05); hl:SetBlendMode("ADD")

    -- Left zone stripe (3 px)
    row.stripe = SolidTex(row, 1, 1, 1, 0.85, "ARTWORK")
    row.stripe:SetWidth(3)
    row.stripe:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
    row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

    -- Bottom separator (1 px)
    local sep = SolidTex(row, 1, 1, 1, 0.06, "OVERLAY")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    -- Hunt name
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -8)
    row.nameText:SetWidth(GetRowW() - 115)  -- updated in RefreshRows
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    -- Status line (Available / In Progress)
    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statusText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -3)

    -- Difficulty badge (top-right)
    row.diffBadge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.diffBadge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -8)
    row.diffBadge:SetJustifyH("RIGHT")

    -- Zone text (below diff badge)
    row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.zoneText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -22)
    row.zoneText:SetJustifyH("RIGHT")

    -- Reward icons — each anchored to row BOTTOMLEFT with absolute offset
    row.rewardIcons = {}
    for i = 1, 4 do
        row.rewardIcons[i] = MakeRewardIcon(row, i)
    end

    -- Accept button (flat, no chrome)
    row.acceptBtn = CreateFrame("Button", nil, row)
    row.acceptBtn:SetSize(68, 20)
    row.acceptBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 8)
    row.acceptBtn:SetPropagateMouseClicks(false)

    row.acceptBtn.bg = SolidTex(row.acceptBtn, 0.10, 0.38, 0.10, 0.90)
    row.acceptBtn.bg:SetAllPoints()

    local abL = SolidTex(row.acceptBtn, 0.3, 0.85, 0.3, 0.5, "OVERLAY"); abL:SetSize(1,  20); abL:SetPoint("TOPLEFT",    row.acceptBtn, "TOPLEFT")
    local abR = SolidTex(row.acceptBtn, 0.3, 0.85, 0.3, 0.5, "OVERLAY"); abR:SetSize(1,  20); abR:SetPoint("TOPRIGHT",   row.acceptBtn, "TOPRIGHT")
    local abT = SolidTex(row.acceptBtn, 0.3, 0.85, 0.3, 0.5, "OVERLAY"); abT:SetSize(68,  1); abT:SetPoint("TOPLEFT",    row.acceptBtn, "TOPLEFT")
    local abB = SolidTex(row.acceptBtn, 0.3, 0.85, 0.3, 0.5, "OVERLAY"); abB:SetSize(68,  1); abB:SetPoint("BOTTOMLEFT", row.acceptBtn, "BOTTOMLEFT")

    local abHL = row.acceptBtn:CreateTexture(nil, "HIGHLIGHT")
    abHL:SetAllPoints(); abHL:SetTexture(WHITE); abHL:SetVertexColor(1,1,1,0.10); abHL:SetBlendMode("ADD")

    row.acceptBtn.label = row.acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.acceptBtn.label:SetAllPoints()
    row.acceptBtn.label:SetJustifyH("CENTER")
    row.acceptBtn.label:SetText("Accept")
    row.acceptBtn.label:SetTextColor(0.45, 1.0, 0.45)

    return row
end

local function ReleaseRow(row)
    if row.progressGlow and row.progressGlow._pulse then
        row.progressGlow._pulse:Stop()
    end
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

    -- Background: in-progress overrides difficulty tint
    if inprog then
        row.bg:SetVertexColor(0.13, 0.10, 0.02, 0.95)
        row.nameText:SetTextColor(1.00, 0.88, 0.30)
        row.statusText:SetText("|cffffd700In Progress|r")
        row.acceptBtn:Hide()
        row.progressGlow:SetAlpha(0.07)
        row.progressGlow._pulse:Play()
    else
        local tint = DIFF_ROW_BG[hunt.difficulty] or { r=0.055, g=0.055, b=0.075 }
        row.bg:SetVertexColor(tint.r, tint.g, tint.b, 0.94)
        row.nameText:SetTextColor(0.92, 0.92, 0.95)
        row.statusText:SetText("|cff55ccffAvailable|r")
        row.acceptBtn:Show()
        if PH.standalone then row.acceptBtn:Hide() end
        row.progressGlow._pulse:Stop()
        row.progressGlow:SetAlpha(0)

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
    -- Stripe uses difficulty color so it's an instant visual cue
    row.stripe:SetVertexColor(dc.r, dc.g, dc.b, 0.9)
    row.zoneText:SetText(hunt.zone or "")
    row.zoneText:SetTextColor(zc.r * 1.3, zc.g * 1.3, zc.b * 1.3)
    row.diffBadge:SetText(hunt.difficulty)
    row.diffBadge:SetTextColor(dc.r, dc.g, dc.b)

    -- Reward icons
    for i = 1, 4 do
        local ic = row.rewardIcons[i]
        local r  = rewards[i]
        if r then
            ic.tex:SetTexture(r.icon)
            ic:Show()
            ic:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(r.count and (r.name.." x"..r.count) or r.name, 1, 1, 1)
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
            dialog:SetAlpha(1); dialog:ClearAllPoints()
            dialog:SetPoint("CENTER", UIParent, "CENTER")
        end
        local pin = PH.FindPin(hunt.questID)
        if not pin then return end
        local dp = pin:GetDataProvider()
        if dp and dp.OnQuestOfferPinClicked then dp:OnQuestOfferPinClicked(pin) end
    end)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(hunt.name, 1, 1, 1)
        GameTooltip:AddLine(hunt.difficulty, dc.r, dc.g, dc.b)
        GameTooltip:AddLine(hunt.zone or "Unknown", zc.r*1.3, zc.g*1.3, zc.b*1.3)
        GameTooltip:AddLine(inprog and "|cffffd700In Progress|r" or "|cff55ccffAvailable|r")
        if #rewards > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Rewards:", 1, 0.82, 0)
            for _, r in ipairs(rewards) do
                GameTooltip:AddLine(r.count and (r.name.." x"..r.count) or r.name, 1, 1, 1)
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

    local rowW = GetRowW()
    if PH.scrollChild then PH.scrollChild:SetWidth(rowW) end

    local y = 0
    for _, hunt in ipairs(PH.GetSortedHunts()) do
        local row = AcquireRow()
        row:SetParent(PH.scrollChild)
        row:SetSize(rowW, CFG.ROW_HEIGHT)
        row.nameText:SetWidth(rowW - 115)
        row:SetPoint("TOPLEFT", PH.scrollChild, "TOPLEFT", 0, -y)
        PopulateRow(row, hunt)
        y = y + CFG.ROW_HEIGHT + CFG.ROW_PADDING
        activeRows[#activeRows + 1] = row
    end
    PH.scrollChild:SetHeight(math.max(y, 1))

    local isEmpty = PH.standalone and #PH.liveHunts == 0
    if PH.panel.emptyState then
        if isEmpty then PH.panel.emptyState:Show() else PH.panel.emptyState:Hide() end
    end

    local inprog, avail = 0, 0
    for _, h in ipairs(PH.liveHunts) do
        if PH.IsInProgress(h.questID) then inprog = inprog + 1 else avail = avail + 1 end
    end
    local parts = {}
    if inprog > 0 then parts[#parts+1] = string.format("|cffffd700%d In Progress|r", inprog) end
    if avail  > 0 then parts[#parts+1] = string.format("|cff55ccff%d Available|r",   avail)  end
    if PH.panel and PH.panel.summaryText then
        PH.panel.summaryText:SetText(table.concat(parts, "  ·  "))
    end
end

-- ---------------------------------------------------------------------------
-- Filter bar
-- ---------------------------------------------------------------------------
local function CreateFilterBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(FILTER_H)
    bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",  12, -(TITLE_H + FILTER_PAD))
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -(TITLE_H + FILTER_PAD))

    local diffs = { "All", "Nightmare", "Hard", "Normal" }
    bar.pills   = {}
    bar.diffs   = diffs

    for i, diff in ipairs(diffs) do
        local pill = CreateFrame("Button", nil, bar)
        pill:SetHeight(22)
        pill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)  -- positioned in ResizeFilterBar

        pill.bg = SolidTex(pill, 0.10, 0.10, 0.14, 0.90)
        pill.bg:SetAllPoints()

        pill.accent = SolidTex(pill, 1, 1, 1, 0, "OVERLAY")
        pill.accent:SetHeight(2)
        pill.accent:SetPoint("BOTTOMLEFT",  pill, "BOTTOMLEFT",  1, 0)
        pill.accent:SetPoint("BOTTOMRIGHT", pill, "BOTTOMRIGHT", -1, 0)

        local hl = pill:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetTexture(WHITE); hl:SetVertexColor(1,1,1,0.08); hl:SetBlendMode("ADD")

        pill.label = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pill.label:SetAllPoints()
        pill.label:SetJustifyH("CENTER")
        pill.label:SetText(diff)
        pill.label:SetTextColor(0.55, 0.55, 0.60)

        pill.diffKey = diff
        bar.pills[i] = pill

        pill:SetScript("OnClick", function()
            PH.filter.difficulty = diff
            for _, p in ipairs(bar.pills) do
                local sel = p.diffKey == diff
                local c   = CFG.DIFF_COLOR[p.diffKey]
                if sel then
                    p.bg:SetVertexColor(0.16, 0.16, 0.22, 0.95)
                    if c then
                        p.accent:SetVertexColor(c.r, c.g, c.b, 1)
                        p.label:SetTextColor(c.r * 1.2, c.g * 1.2, c.b * 1.2)
                    else
                        p.accent:SetVertexColor(0.40, 0.55, 0.80, 1)
                        p.label:SetTextColor(0.65, 0.80, 1.0)
                    end
                    p.accent:SetAlpha(1)
                else
                    p.bg:SetVertexColor(0.10, 0.10, 0.14, 0.90)
                    p.accent:SetAlpha(0)
                    p.label:SetTextColor(0.55, 0.55, 0.60)
                end
            end
            PH.RefreshRows()
        end)
    end

    -- Visually activate "All" without calling RefreshRows (scrollChild not built yet)
    do
        local p = bar.pills[1]
        p.bg:SetVertexColor(0.16, 0.16, 0.22, 0.95)
        p.accent:SetVertexColor(0.40, 0.55, 0.80, 1)
        p.accent:SetAlpha(1)
        p.label:SetTextColor(0.65, 0.80, 1.0)
    end

    return bar
end

-- Recalculate pill widths to fill the current panel width. Call after resize.
local function ResizeFilterBar(bar, panelW)
    if not bar then return end
    local totalW = (panelW or bar:GetWidth()) - 24  -- 12px padding each side
    local n      = #bar.pills
    local gap    = 2
    local pillW  = math.floor((totalW - gap * (n - 1)) / n)
    for i, pill in ipairs(bar.pills) do
        pill:SetWidth(pillW)
        pill:ClearAllPoints()
        pill:SetPoint("LEFT", bar, "LEFT", (i - 1) * (pillW + gap), 0)
    end
end

-- ---------------------------------------------------------------------------
-- Panel construction
-- ---------------------------------------------------------------------------
function PH.BuildPanel()
    if PH.panel then return end

    local panel = CreateFrame("Frame", "PreyHubPanel", UIParent)
    panel:SetSize(CFG.PANEL_WIDTH, CFG.PANEL_HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(200)
    panel:SetClampedToScreen(true)
    panel:Hide()

    -- Background — clean near-black
    panel.bg = SolidTex(panel, 0.06, 0.06, 0.07, 0.96)
    panel.bg:SetAllPoints()

    -- Subtle darker bottom band
    local bgBot = SolidTex(panel, 0.03, 0.03, 0.04, 0.60, "BACKGROUND", 1)
    bgBot:SetPoint("TOPLEFT",     panel, "CENTER",      0,  0)
    bgBot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0,  0)

    -- 1 px border — steel grey
    local br, bg_, bb = 0.20, 0.20, 0.24
    local bL = SolidTex(panel, br, bg_, bb, 0.75, "OVERLAY"); bL:SetWidth(1);  bL:SetPoint("TOPLEFT",    panel, "TOPLEFT");    bL:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT")
    local bR = SolidTex(panel, br, bg_, bb, 0.75, "OVERLAY"); bR:SetWidth(1);  bR:SetPoint("TOPRIGHT",   panel, "TOPRIGHT");   bR:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
    local bT = SolidTex(panel, br, bg_, bb, 0.75, "OVERLAY"); bT:SetHeight(1); bT:SetPoint("TOPLEFT",    panel, "TOPLEFT");    bT:SetPoint("TOPRIGHT",    panel, "TOPRIGHT")
    local bB = SolidTex(panel, br, bg_, bb, 0.40, "OVERLAY"); bB:SetHeight(1); bB:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT"); bB:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")

    -- 3 px top accent — steel blue
    local topAccent = SolidTex(panel, 0.25, 0.45, 0.70, 1.0, "ARTWORK")
    topAccent:SetHeight(3)
    topAccent:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -1)
    topAccent:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)

    -- Title
    panel.titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.titleText:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
    panel.titleText:SetText("|cffcc44ccPrey|r|cffddddddHub|r")

    -- Anguish currency
    panel.anguishText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.anguishText:SetPoint("RIGHT", panel, "TOPRIGHT", -36, -17)

    -- Close button
    panel.closeBtn = CreateFrame("Button", nil, panel)
    panel.closeBtn:SetSize(20, 20)
    panel.closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    local xTex = panel.closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xTex:SetAllPoints(); xTex:SetJustifyH("CENTER")
    xTex:SetText("|cff888888x|r")
    local xHL = panel.closeBtn:CreateTexture(nil, "HIGHLIGHT")
    xHL:SetAllPoints(); xHL:SetTexture(WHITE); xHL:SetVertexColor(1,1,1,0.08); xHL:SetBlendMode("ADD")
    panel.closeBtn:SetScript("OnClick", function() PH.ForceHidePanel() end)
    panel.closeBtn:SetScript("OnEnter", function() xTex:SetText("|cffeeeeeeX|r") end)
    panel.closeBtn:SetScript("OnLeave", function() xTex:SetText("|cff888888x|r") end)

    -- Title divider
    local titleDiv = SolidTex(panel, 1, 1, 1, 0.08, "ARTWORK")
    titleDiv:SetHeight(1)
    titleDiv:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -TITLE_H)
    titleDiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -TITLE_H)

    -- Filter bar
    panel.filterBar = CreateFilterBar(panel)

    -- Filter divider
    local filterBottom = TITLE_H + FILTER_PAD + FILTER_H + 4
    local filterDiv = SolidTex(panel, 1, 1, 1, 0.06, "ARTWORK")
    filterDiv:SetHeight(1)
    filterDiv:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -filterBottom)
    filterDiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -filterBottom)

    -- Summary text
    panel.summaryText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.summaryText:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -(filterBottom + SUMMARY_PAD))

    -- Empty state — shown in standalone mode when no hunts are cached yet
    local es = CreateFrame("Frame", nil, panel)
    es:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -TOP_CONTENT)
    es:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT",  0, 0)
    es:Hide()

    local esIcon = es:CreateTexture(nil, "ARTWORK")
    esIcon:SetSize(64, 64)
    esIcon:SetPoint("CENTER", es, "CENTER", 0, 60)
    esIcon:SetTexture("Interface\\Icons\\Ui_prey")
    esIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    esIcon:SetAlpha(0.35)

    local esTitle = es:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    esTitle:SetPoint("TOP", esIcon, "BOTTOM", 0, -14)
    esTitle:SetText("|cffcc44ccNo hunts recorded yet|r")

    local esBody = es:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    esBody:SetPoint("TOP", esTitle, "BOTTOM", 0, -10)
    esBody:SetWidth(240)
    esBody:SetJustifyH("CENTER")
    esBody:SetTextColor(0.55, 0.55, 0.62)
    esBody:SetText("Open the Prey Hunt map at least once\nto scan your available hunts.\n\nThey'll appear here automatically\nnext time you check.")

    panel.emptyState = es

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", "PreyHubScroll", panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     panel, "TOPLEFT",     8,  -TOP_CONTENT)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 8)

    PH.scrollChild = CreateFrame("Frame", nil, sf)
    PH.scrollChild:SetWidth(GetRowW())
    PH.scrollChild:SetHeight(1)
    sf:SetScrollChild(PH.scrollChild)

    -- Draggable
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    PH.panel = panel
end

function PH.AnchorPanel()
    local w = PH.standalone and CFG.PANEL_WIDTH_STANDALONE or CFG.PANEL_WIDTH
    PH.panel:SetWidth(w)
    if PH.scrollChild then PH.scrollChild:SetWidth(w - 30) end
    ResizeFilterBar(PH.panel.filterBar, w)
    PH.panel:ClearAllPoints()
    if PH.standalone then
        PH.panel:SetHeight(CFG.PANEL_HEIGHT)
        PH.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    elseif CovenantMissionFrame and CovenantMissionFrame:IsShown() then
        local mapH = CovenantMissionFrame:GetHeight()
        PH.panel:SetHeight(mapH)
        PH.panel:SetPoint("TOPRIGHT", CovenantMissionFrame, "TOPLEFT", -CFG.X_OFFSET, 0)
    else
        PH.panel:SetHeight(CFG.PANEL_HEIGHT)
        PH.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- ---------------------------------------------------------------------------
-- Loading overlay — shown while rewards are being fetched
-- ---------------------------------------------------------------------------
local loadFrame  = nil
local mapOverlay = nil  -- sits on top of CovenantMissionFrame

local function BuildMapOverlay()
    if mapOverlay then return end

    -- Parent to UIParent (not CovenantMissionFrame) so we can place it above
    -- the map without being clipped by it.
    mapOverlay = CreateFrame("Frame", "PreyHubMapOverlay", UIParent)
    mapOverlay:SetFrameStrata("DIALOG")
    mapOverlay:SetFrameLevel(210)  -- above CovenantMissionFrame
    mapOverlay:Hide()

    -- Dark semi-transparent blanket over the whole map
    local bg = SolidTex(mapOverlay, 0.03, 0.03, 0.04, 0.82)
    bg:SetAllPoints()

    -- Centered card
    local cardW, cardH = 260, 80
    local card = CreateFrame("Frame", nil, mapOverlay)
    card:SetSize(cardW, cardH)
    card:SetPoint("CENTER", mapOverlay, "CENTER", 0, 0)

    local cardBg = SolidTex(card, 0.08, 0.08, 0.10, 0.98)
    cardBg:SetAllPoints()

    -- Card border
    local br, bg_, bb = 0.22, 0.22, 0.28
    local cL = SolidTex(card, br, bg_, bb, 0.80, "OVERLAY"); cL:SetWidth(1);  cL:SetPoint("TOPLEFT",    card, "TOPLEFT");    cL:SetPoint("BOTTOMLEFT",  card, "BOTTOMLEFT")
    local cR = SolidTex(card, br, bg_, bb, 0.80, "OVERLAY"); cR:SetWidth(1);  cR:SetPoint("TOPRIGHT",   card, "TOPRIGHT");   cR:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")
    local cT = SolidTex(card, br, bg_, bb, 0.80, "OVERLAY"); cT:SetHeight(1); cT:SetPoint("TOPLEFT",    card, "TOPLEFT");    cT:SetPoint("TOPRIGHT",    card, "TOPRIGHT")
    local cB = SolidTex(card, br, bg_, bb, 0.80, "OVERLAY"); cB:SetHeight(1); cB:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT"); cB:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")

    -- 2px top accent
    local accent = SolidTex(card, 0.25, 0.45, 0.70, 1.0, "ARTWORK")
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT",  card, "TOPLEFT",  1, -1)
    accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)

    -- Title line
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", card, "TOP", 0, -14)
    title:SetText("|cffcc44ccPrey|r|cffddddddHub|r  |cff666677—|r  |cffaaaabbLoading reward data...|r")

    -- Progress bar track
    local barW = cardW - 40
    local track = SolidTex(card, 0.10, 0.10, 0.14, 1.0, "ARTWORK")
    track:SetSize(barW, 8)
    track:SetPoint("CENTER", card, "CENTER", 0, -6)

    mapOverlay.barFill = SolidTex(card, 0.30, 0.55, 0.85, 1.0, "ARTWORK", 1)
    mapOverlay.barFill:SetSize(1, 8)
    mapOverlay.barFill:SetPoint("LEFT", track, "LEFT", 0, 0)

    mapOverlay.progressText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mapOverlay.progressText:SetPoint("TOP", track, "BOTTOM", 0, -5)
    mapOverlay.progressText:SetTextColor(0.50, 0.50, 0.58)

    mapOverlay.barW = barW
end

local function UpdateBarState(frame, done, total)
    if done and total and total > 0 then
        local fillW = math.max(1, math.floor(frame.barW * (done / total)))
        frame.barFill:SetWidth(fillW)
        frame.progressText:SetText(string.format("%d / %d", done, total))
    else
        frame.barFill:SetWidth(1)
        frame.progressText:SetText("")
    end
end

local function BuildLoadingFrame()
    if loadFrame then return end

    loadFrame = CreateFrame("Frame", "PreyHubLoading", UIParent)
    loadFrame:SetSize(CFG.PANEL_WIDTH, CFG.PANEL_HEIGHT)
    loadFrame:SetFrameStrata("DIALOG")
    loadFrame:SetFrameLevel(199)
    loadFrame:Hide()

    -- Same background as main panel
    local bg = SolidTex(loadFrame, 0.06, 0.06, 0.07, 0.96)
    bg:SetAllPoints()

    local topAccent = SolidTex(loadFrame, 0.25, 0.45, 0.70, 1.0, "ARTWORK")
    topAccent:SetHeight(3)
    topAccent:SetPoint("TOPLEFT",  loadFrame, "TOPLEFT",  1, -1)
    topAccent:SetPoint("TOPRIGHT", loadFrame, "TOPRIGHT", -1, -1)

    -- Border
    local br, bg_, bb = 0.20, 0.20, 0.24
    local bL = SolidTex(loadFrame, br, bg_, bb, 0.75, "OVERLAY"); bL:SetWidth(1);  bL:SetPoint("TOPLEFT",    loadFrame, "TOPLEFT");    bL:SetPoint("BOTTOMLEFT",  loadFrame, "BOTTOMLEFT")
    local bR = SolidTex(loadFrame, br, bg_, bb, 0.75, "OVERLAY"); bR:SetWidth(1);  bR:SetPoint("TOPRIGHT",   loadFrame, "TOPRIGHT");   bR:SetPoint("BOTTOMRIGHT", loadFrame, "BOTTOMRIGHT")
    local bT = SolidTex(loadFrame, br, bg_, bb, 0.75, "OVERLAY"); bT:SetHeight(1); bT:SetPoint("TOPLEFT",    loadFrame, "TOPLEFT");    bT:SetPoint("TOPRIGHT",    loadFrame, "TOPRIGHT")
    local bB = SolidTex(loadFrame, br, bg_, bb, 0.40, "OVERLAY"); bB:SetHeight(1); bB:SetPoint("BOTTOMLEFT", loadFrame, "BOTTOMLEFT"); bB:SetPoint("BOTTOMRIGHT", loadFrame, "BOTTOMRIGHT")

    -- Title
    local title = loadFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", loadFrame, "TOPLEFT", 14, -12)
    title:SetText("|cffcc44ccPrey|r|cffddddddHub|r")

    -- Center label
    local label = loadFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", loadFrame, "CENTER", 0, 30)
    label:SetText("|cffaaaabbLoading rewards...|r")

    -- Progress bar track
    local barW = CFG.PANEL_WIDTH - 60
    local track = SolidTex(loadFrame, 0.12, 0.12, 0.16, 1.0, "ARTWORK")
    track:SetSize(barW, 10)
    track:SetPoint("CENTER", loadFrame, "CENTER", 0, 8)

    loadFrame.barFill = SolidTex(loadFrame, 0.30, 0.55, 0.85, 1.0, "ARTWORK", 1)
    loadFrame.barFill:SetSize(1, 10)
    loadFrame.barFill:SetPoint("LEFT", track, "LEFT", 0, 0)

    local progressText = loadFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("TOP", track, "BOTTOM", 0, -6)
    progressText:SetTextColor(0.55, 0.55, 0.60)
    loadFrame.progressText = progressText

    loadFrame.barW = barW
end

local function AnchorLoadingFrame()
    loadFrame:ClearAllPoints()
    if CovenantMissionFrame and CovenantMissionFrame:IsShown() then
        local mapH = CovenantMissionFrame:GetHeight()
        loadFrame:SetHeight(mapH)
        loadFrame:SetPoint("TOPRIGHT", CovenantMissionFrame, "TOPLEFT", -CFG.X_OFFSET, 0)
    else
        loadFrame:SetHeight(CFG.PANEL_HEIGHT)
        loadFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function AnchorMapOverlay()
    mapOverlay:ClearAllPoints()
    if CovenantMissionFrame and CovenantMissionFrame:IsShown() then
        mapOverlay:SetPoint("TOPLEFT",     CovenantMissionFrame, "TOPLEFT")
        mapOverlay:SetPoint("BOTTOMRIGHT", CovenantMissionFrame, "BOTTOMRIGHT")
    else
        mapOverlay:Hide()
    end
end

function PH.ShowLoadingFrame(done, total)
    -- Build and anchor the real panel now so the filter bar is sized correctly
    -- before the loading frame disappears. The panel stays hidden behind it.
    PH.BuildPanel()
    PH.AnchorPanel()

    BuildLoadingFrame()
    BuildMapOverlay()
    AnchorLoadingFrame()
    AnchorMapOverlay()
    UpdateBarState(loadFrame,  done, total)
    UpdateBarState(mapOverlay, done, total)
    loadFrame:Show()
    mapOverlay:Show()
end

function PH.HideLoadingFrame()
    if loadFrame  then loadFrame:Hide()  end
    if mapOverlay then mapOverlay:Hide() end
end

function PH.ShowPanel()
    PH.HideLoadingFrame()
    PH.BuildPanel()
    PH.AnchorPanel()
    PH.panel.anguishText:SetText(
        string.format("|cffdd4444%d|r Anguish", PH.GetAnguishCurrency()))
    PH.RefreshRows()
    PH.panel:Show()
    AnimFadeIn(PH.panel, 0.18)
end

-- Auto-close: ignored in standalone mode (map closing, watchdog)
function PH.HidePanel()
    if PH.standalone then return end
    PH.HideLoadingFrame()
    if PH._rewardWarmCancel then PH._rewardWarmCancel() end
    if PH.panel and PH.panel:IsShown() then
        AnimFadeOut(PH.panel, 0.14)
    end
end

-- Force-close: always hides (close button, /prey hide, toggle)
function PH.ForceHidePanel()
    PH.standalone = false
    PH.HideLoadingFrame()
    if PH._rewardWarmCancel then PH._rewardWarmCancel() end
    if PH.panel and PH.panel:IsShown() then
        AnimFadeOut(PH.panel, 0.14)
    end
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------
function PH.CreateMinimapButton()
    if not PreyHubDB then PreyHubDB = {} end
    if PreyHubDB.minimap == nil then PreyHubDB.minimap = {} end

    -- -----------------------------------------------------------------------
    -- Path A: LibDBIcon (handles ElvUI, MBB, every other manager addon)
    -- -----------------------------------------------------------------------
    local LDB    = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and LDBIcon then
        local broker = LDB:NewDataObject("PreyHub", {
            type  = "launcher",
            label = "PreyHub",
            icon  = "Interface\\Icons\\Ui_prey",
            OnClick = function(_, button)
                if button ~= "LeftButton" then return end
                PH.BuildPanel()
                if PH.panel:IsShown() then
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
            end,
            OnTooltipShow = function(tt)
                tt:AddLine("PreyHub", 0.85, 0.5, 1.0)
                tt:AddLine("Toggle Prey Hunt panel", 0.7, 0.7, 0.75)
            end,
        })
        LDBIcon:Register("PreyHub", broker, PreyHubDB.minimap)
        return
    end

    -- -----------------------------------------------------------------------
    -- Path B: Manual fallback (no LibDBIcon installed)
    -- -----------------------------------------------------------------------
    if not PreyHubDB.minimapAngle then PreyHubDB.minimapAngle = 225 end
    local RADIUS = 80

    local btn = CreateFrame("Button", "PreyHubMinimapBtn", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)

    local tex = btn:CreateTexture(nil, "BACKGROUND")
    tex:SetPoint("TOPLEFT",     btn, "TOPLEFT",      2, -2)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2,  2)
    tex:SetTexture("Interface\\Icons\\Ui_prey")
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("CENTER", btn, "CENTER")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(WHITE)
    hl:SetVertexColor(1, 1, 1, 0.18)
    hl:SetBlendMode("ADD")

    local function SetAngle(deg)
        PreyHubDB.minimapAngle = deg
        local rad = math.rad(deg)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(rad) * RADIUS,
            math.sin(rad) * RADIUS)
    end
    SetAngle(PreyHubDB.minimapAngle)

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            local deg = math.deg(math.atan2((cy / s - my), (cx / s - mx)))
            SetAngle(deg)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        PH.BuildPanel()
        if PH.panel:IsShown() then
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
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PreyHub", 0.85, 0.5, 1.0)
        GameTooltip:AddLine("Toggle Prey Hunt panel", 0.7, 0.7, 0.75)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888Drag to reposition|r", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end