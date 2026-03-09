-- PreyTracker — Progress.lua
-- Progress bar showing prey hunt stages (0→33%→66%→100%).
--
-- Default: our bar ON, Blizzard widget hidden.
--
-- /prey bar          — toggle our bar on/off
-- /prey bar reset    — snap bar back to default position
-- /prey widget       — toggle Blizzard's widget on/off
-- ─────────────────────────────────────────────────────────────────────────────
local PH = PreyTracker

-- ─── Constants ───────────────────────────────────────────────────────────────
local PREY_WIDGET_ID = 7663
local NUM_SEGS       = 3
local SEG_GAP        = 3
local BAR_H          = 12
local BAR_W          = 200
local CARD_H         = BAR_H + 18   -- bar + label
local TWEEN_DUR      = 0.28
local POLL_INTERVAL  = 2.0
local WHITE          = "Interface\\Buttons\\WHITE8X8"

local STATE_COLOR = {
    [0] = { r = 0.10, g = 0.10, b = 0.14 },  -- empty
    [1] = { r = 0.55, g = 0.04, b = 0.04 },  -- 33%  dark red
    [2] = { r = 1.00, g = 0.82, b = 0.00 },  -- 66%  yellow
    [3] = { r = 0.10, g = 0.58, b = 0.18 },  -- 100% muted green
    [4] = { r = 0.10, g = 0.58, b = 0.18 },  -- safety
}

-- Pulse alpha range for the leading segment glow
local PULSE_FROM, PULSE_TO, PULSE_DUR = 0.38, 0.04, 0.80

-- ─── Module state ─────────────────────────────────────────────────────────────
local card            = nil
local segments        = {}
local currentState    = -1
local built           = false
local blizzSuppressed = false

-- ─── State flags ──────────────────────────────────────────────────────────────
-- barEnabled:    whether our bar is shown (default true)
-- widgetHidden:  whether Blizzard's widget is suppressed (default true)
local function IsBarEnabled()
    if PreyTrackerDB and PreyTrackerDB.barEnabled ~= nil then
        return PreyTrackerDB.barEnabled
    end
    return true  -- on by default
end

local function IsWidgetHidden()
    if PreyTrackerDB and PreyTrackerDB.widgetHidden ~= nil then
        return PreyTrackerDB.widgetHidden
    end
    return true  -- suppressed by default
end

local function SetBarEnabled(v)
    if not PreyTrackerDB then PreyTrackerDB = {} end
    PreyTrackerDB.barEnabled = v
end

local function SetWidgetHidden(v)
    if not PreyTrackerDB then PreyTrackerDB = {} end
    PreyTrackerDB.widgetHidden = v
end

local function GetSavedPos()
    return PreyTrackerDB and PreyTrackerDB.progressBar
end

local function SavePos()
    if not card then return end
    local point, _, relPoint, x, y = card:GetPoint()
    if not PreyTrackerDB then PreyTrackerDB = {} end
    PreyTrackerDB.progressBar = { point=point, relPoint=relPoint, x=x, y=y }
end

local function ClearSavedPos()
    if PreyTrackerDB then PreyTrackerDB.progressBar = nil end
end

-- ─── Blizzard widget suppression ──────────────────────────────────────────────
local function SuppressBlizzWidget()
    if blizzSuppressed then return end
    local wf = UIWidgetPowerBarContainerFrame
              and UIWidgetPowerBarContainerFrame.widgetFrames
              and UIWidgetPowerBarContainerFrame.widgetFrames[PREY_WIDGET_ID]
    if not wf then return end
    wf:Hide()
    wf:SetScript("OnShow", function(self) self:Hide() end)
    blizzSuppressed = true
end

local function UnsuppressBlizzWidget()
    if not blizzSuppressed then return end
    local wf = UIWidgetPowerBarContainerFrame
              and UIWidgetPowerBarContainerFrame.widgetFrames
              and UIWidgetPowerBarContainerFrame.widgetFrames[PREY_WIDGET_ID]
    if not wf then return end
    wf:SetScript("OnShow", nil)
    wf:Show()
    blizzSuppressed = false
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function Tex(parent, r, g, b, a, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

local function TweenBar(sb, target, onDone)
    if sb._tw then sb._tw:Cancel(); sb._tw = nil end
    local from  = sb:GetValue()
    local delta = target - from
    if math.abs(delta) < 0.001 then sb:SetValue(target); if onDone then onDone() end; return end
    local elapsed = 0
    local tk
    tk = C_Timer.NewTicker(0.016, function()
        elapsed = elapsed + 0.016
        local t = math.min(elapsed / TWEEN_DUR, 1)
        sb:SetValue(from + delta * (1 - (1-t)^3))
        if t >= 1 then tk:Cancel(); sb._tw = nil; if onDone then onDone() end end
    end)
    sb._tw = tk
end

-- ─── Segment builder ──────────────────────────────────────────────────────────
local function BuildSegment(parent, idx, xOff, segW)
    -- Dark trough
    local bg = Tex(parent, 0.06, 0.06, 0.08, 1, "BACKGROUND", 0)
    bg:SetSize(segW, BAR_H)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, 0)

    -- Fill StatusBar (color set by ApplyState)
    local fill = CreateFrame("StatusBar", nil, parent)
    fill:SetSize(segW, BAR_H)
    fill:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, 0)
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    fill:SetStatusBarTexture(WHITE)
    fill:GetStatusBarTexture():SetVertexColor(0.15, 0.55, 1.00, 1)  -- placeholder

    -- Thin top highlight
    local shine = fill:CreateTexture(nil, "OVERLAY", nil, 1)
    shine:SetTexture(WHITE); shine:SetBlendMode("ADD")
    shine:SetVertexColor(1, 1, 1, 0.12)
    shine:SetHeight(math.ceil(BAR_H * 0.30))
    shine:SetPoint("TOPLEFT",  fill:GetStatusBarTexture(), "TOPLEFT")
    shine:SetPoint("TOPRIGHT", fill:GetStatusBarTexture(), "TOPRIGHT")

    -- Glow frame for pulse (child of fill so alpha is isolated)
    local glow = CreateFrame("Frame", nil, fill)
    glow:SetAllPoints(); glow:SetAlpha(0)
    local glowTex = glow:CreateTexture(nil, "OVERLAY", nil, 2)
    glowTex:SetTexture(WHITE); glowTex:SetBlendMode("ADD"); glowTex:SetAllPoints()
    glowTex:SetVertexColor(0.15 * 0.6, 0.55 * 0.6, 1.00 * 0.6, 1)  -- placeholder

    local pulseAG = glow:CreateAnimationGroup()
    pulseAG:SetLooping("BOUNCE")
    local pa = pulseAG:CreateAnimation("Alpha")
    pa:SetFromAlpha(PULSE_FROM); pa:SetToAlpha(PULSE_TO)
    pa:SetDuration(PULSE_DUR);   pa:SetSmoothing("IN_OUT")

    -- 1px border around trough
    local bL = Tex(parent, 0.12, 0.12, 0.16, 1, "OVERLAY", 5); bL:SetSize(1, BAR_H); bL:SetPoint("TOPLEFT",    bg, "TOPLEFT")
    local bR = Tex(parent, 0.12, 0.12, 0.16, 1, "OVERLAY", 5); bR:SetSize(1, BAR_H); bR:SetPoint("TOPRIGHT",   bg, "TOPRIGHT")
    local bT = Tex(parent, 0.20, 0.20, 0.26, 1, "OVERLAY", 5); bT:SetSize(segW, 1);  bT:SetPoint("TOPLEFT",    bg, "TOPLEFT")
    local bB = Tex(parent, 0.04, 0.04, 0.06, 1, "OVERLAY", 5); bB:SetSize(segW, 1);  bB:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")

    return { fill=fill, glow=glow, glowTex=glowTex, pulse=pulseAG }
end

-- ─── Tooltip ──────────────────────────────────────────────────────────────────
local function ShowTooltip()
    local pcts = { [0]="0%", [1]="33%", [2]="66%", [3]="100%", [4]="100%" }
    local pct  = pcts[math.max(0, currentState)] or "0%"
    GameTooltip:SetOwner(card, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Prey Hunt Progress", 0.85, 0.35, 1.0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Complete World Quests, rares, and treasures in this", 0.80, 0.65, 0.20)
    GameTooltip:AddLine("zone to fill the bar and lure your prey out of hiding.", 0.80, 0.65, 0.20)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff55ff55" .. pct .. "|r", 1, 1, 1)
    if currentState >= 3 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffff4444● Prey is ready — click to open the world map!|r")
    end
    GameTooltip:AddLine(" ")
    local widgetShown = not IsWidgetHidden()
    GameTooltip:AddLine(string.format("|cff444455Blizzard widget: %s  ·  /prey widget to toggle|r",
        widgetShown and "shown" or "hidden"))
    GameTooltip:AddLine("|cff444455Right-drag to move  ·  /prey bar reset  ·  /prey bar to hide this|r")
    GameTooltip:Show()
end

-- ─── Card construction ────────────────────────────────────────────────────────
local function BuildCard()
    if built then return end
    built = true

    card = CreateFrame("Frame", "PreyTrackerProgressCard", UIParent)
    card:SetSize(BAR_W, CARD_H)
    card:SetFrameStrata("MEDIUM")
    card:SetFrameLevel(95)
    card:SetClampedToScreen(true)
    card:Hide()

    -- Segment container
    local sc = CreateFrame("Frame", nil, card)
    card.sc = sc
    sc:SetPoint("TOPLEFT",  card, "TOPLEFT",  0, 0)
    sc:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    sc:SetHeight(BAR_H)

    local segW = math.floor((BAR_W - SEG_GAP * (NUM_SEGS - 1)) / NUM_SEGS)
    for i = 1, NUM_SEGS do
        segments[i] = BuildSegment(sc, i, (i-1) * (segW + SEG_GAP), segW)
    end

    -- Border wrapper — wraps only sc, so label is untouched
    local border = CreateFrame("Frame", nil, card, "BackdropTemplate")
    border:SetPoint("TOPLEFT",     sc, "TOPLEFT",     -4,  4)
    border:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT",  4, -4)
    border:SetFrameLevel(card:GetFrameLevel() - 1)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    border:SetBackdropBorderColor(0.35, 0.35, 0.40, 0.85)
    card.border = border

    -- Soft drop shadow behind the border wrapper only
    local function ShadowLayer(dx, dy, a)
        local f = CreateFrame("Frame", nil, card)
        f:SetFrameLevel(card:GetFrameLevel() - 2)
        f:SetPoint("TOPLEFT",     border, "TOPLEFT",     dx, -dy)
        f:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", dx, -dy)
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(WHITE); t:SetAllPoints()
        t:SetVertexColor(0, 0, 0, a)
    end
    ShadowLayer(-1, -1, 0.25)
    ShadowLayer(-2, -2, 0.10)
    ShadowLayer(-3, -3, 0.04)

    -- Percentage label sits below sc, outside the border
    card.label = card:CreateFontString(nil, "OVERLAY")
    card.label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    card.label:SetPoint("TOP", sc, "BOTTOM", 0, -4)
    card.label:SetJustifyH("CENTER")
    card.label:SetWidth(BAR_W)
    card.label:SetWordWrap(false)
    card.label:SetTextColor(1, 1, 1, 1)

    -- Mouse
    card:SetMovable(true)
    card:EnableMouse(true)
    card:RegisterForDrag("RightButton")
    card:SetScript("OnDragStart", function(self) self:StartMoving(); GameTooltip:Hide() end)
    card:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing(); SavePos() end)
    card:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" or currentState < 3 then return end
        C_Timer.After(0, function() ShowUIPanel(WorldMapFrame) end)
    end)
    card:SetScript("OnEnter", ShowTooltip)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ─── Anchor ───────────────────────────────────────────────────────────────────
local function AnchorToDefault()
    if not card then return end
    card:ClearAllPoints()
    local container = UIWidgetPowerBarContainerFrame
    local wf = container and container.widgetFrames and container.widgetFrames[PREY_WIDGET_ID]
    if wf then
        card:SetPoint("TOP", wf, "BOTTOM", 0, -2)
    elseif container and container:IsShown() then
        card:SetPoint("TOP", container, "BOTTOM", 0, -2)
    else
        card:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
end

local function ApplyWidgetSuppression()
    if IsWidgetHidden() then SuppressBlizzWidget()
    else                     UnsuppressBlizzWidget() end
end

local function ApplyAnchor()
    local saved = GetSavedPos()
    if saved then
        card:ClearAllPoints()
        card:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        AnchorToDefault()
    end
end

-- ─── Segment state ────────────────────────────────────────────────────────────

-- Smooth vertex color tween on a texture or statusbar texture
local function TweenColor(obj, r1, g1, b1, r2, g2, b2, dur, onDone)
    if obj._ctw then obj._ctw:Cancel(); obj._ctw = nil end
    local e = 0
    local tk
    tk = C_Timer.NewTicker(0.016, function()
        e = e + 0.016
        local t = math.min(e / dur, 1)
        local s = 1 - (1 - t)^3  -- ease-out cubic
        obj:SetVertexColor(r1 + (r2-r1)*s, g1 + (g2-g1)*s, b1 + (b2-b1)*s, 1)
        if t >= 1 then
            tk:Cancel(); obj._ctw = nil
            if onDone then onDone() end
        end
    end)
    obj._ctw = tk
end

-- Flash burst: spike glow alpha to `peak` then decay to `rest` over `dur`
local function FlashBurst(glow, peak, rest, dur)
    if glow._ftw then glow._ftw:Cancel(); glow._ftw = nil end
    glow:SetAlpha(peak)
    local e = 0
    local tk
    tk = C_Timer.NewTicker(0.016, function()
        e = e + 0.016
        local t = math.min(e / dur, 1)
        local s = 1 - (1 - t)^2  -- ease-out quad
        glow:SetAlpha(peak + (rest - peak) * s)
        if t >= 1 then tk:Cancel(); glow._ftw = nil end
    end)
    glow._ftw = tk
end

-- Fade label alpha in
local function FadeLabel(label, dur)
    label:SetAlpha(0)
    if label._ltw then label._ltw:Cancel(); label._ltw = nil end
    local e = 0
    local tk
    tk = C_Timer.NewTicker(0.016, function()
        e = e + 0.016
        local t = math.min(e / dur, 1)
        label:SetAlpha(1 - (1-t)^2)
        if t >= 1 then tk:Cancel(); label._ltw = nil end
    end)
    label._ltw = tk
end

local function FillSeg(seg, animate, isLeading, delay)
    delay = delay or 0
    local function DoFill()
        if animate then
            TweenBar(seg.fill, 1, function()
                -- Flash burst on completion, then settle into resting pulse
                if isLeading then
                    FlashBurst(seg.glow, 0.55, 0.12, 0.35)
                    C_Timer.After(0.35, function() seg.pulse:Play() end)
                else
                    FlashBurst(seg.glow, 0.30, 0, 0.25)
                end
            end)
        else
            seg.fill:SetValue(1)
            seg.glow:SetAlpha(isLeading and 0.12 or 0)
            if isLeading then seg.pulse:Play() else seg.pulse:Stop() end
        end
    end
    if delay > 0 then C_Timer.After(delay, DoFill) else DoFill() end
end

local function EmptySeg(seg, animate)
    seg.pulse:Stop()
    if animate then
        TweenBar(seg.fill, 0, nil)
        FlashBurst(seg.glow, 0.10, 0, 0.20)
    else
        seg.fill:SetValue(0)
        seg.glow:SetAlpha(0)
    end
end

local function SetSegColor(seg, c, animate, prevC)
    local st = seg.fill:GetStatusBarTexture()
    if animate and prevC then
        TweenColor(st, prevC.r, prevC.g, prevC.b, c.r, c.g, c.b, 0.30)
    else
        st:SetVertexColor(c.r, c.g, c.b, 1)
    end
    seg.glowTex:SetVertexColor(c.r * 0.6, c.g * 0.6, c.b * 0.6, 1)
    if card and card.border then
        card.border:SetBackdropBorderColor(c.r * 0.80, c.g * 0.80, c.b * 0.80, 0.90)
    end
end

local function ResetColors()
    for _, seg in ipairs(segments) do
        seg.glow:SetAlpha(0); seg.pulse:Stop()
    end
end

-- ─── Apply state ──────────────────────────────────────────────────────────────
local PCT_LABELS = { [0]="", [1]="33%", [2]="66%", [3]="100%", [4]="100%" }

local function ApplyState(new, animate)
    if new == currentState then return end
    local prev = currentState
    currentState = new

    -- Label: fade in on increase, instant on decrease/init
    local label = card.label
    local increasing = new > prev
    if animate and increasing then
        label:SetText(PCT_LABELS[new] or "")
        FadeLabel(label, 0.25)
    else
        label:SetAlpha(1)
        label:SetText(PCT_LABELS[new] or "")
    end

    ResetColors()

    local c    = STATE_COLOR[math.max(1, math.min(new, NUM_SEGS))] or STATE_COLOR[1]
    local prevC = prev > 0 and (STATE_COLOR[math.max(1, math.min(prev, NUM_SEGS))] or nil) or nil
    local fill = math.min(new, NUM_SEGS)

    for i = 1, NUM_SEGS do
        SetSegColor(segments[i], c, animate and increasing, prevC)
        local should  = (i <= fill)
        local was     = (i <= math.min(math.max(0, prev), NUM_SEGS))
        local leading = (i == fill) and fill > 0
        -- Stagger: each newly-filled segment starts slightly after the previous
        local delay   = (animate and increasing and (not was) and should)
                        and ((i - math.max(0, prev) - 1) * 0.08) or 0
        local doAnim  = animate and (should ~= was)
        if should then FillSeg(segments[i], doAnim, leading, delay)
        else           EmptySeg(segments[i], doAnim) end
    end
end

-- ─── Refresh ──────────────────────────────────────────────────────────────────
local function Refresh(animate)
    local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(PREY_WIDGET_ID)
    if info and info.shownState == 1 then
        ApplyWidgetSuppression()
        if IsBarEnabled() then
            BuildCard()
            ApplyAnchor()
            if not card:IsShown() then
                card:Show(); currentState = -1
            end
            ApplyState(info.progressState, animate)
        else
            if card and card:IsShown() then card:Hide(); currentState = -1 end
        end
    else
        if card and card:IsShown() then
            card:Hide(); currentState = -1
        end
        if blizzSuppressed then UnsuppressBlizzWidget() end
    end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

-- /prey bar — toggle our bar on/off
function PH.ToggleProgressBar()
    local next = not IsBarEnabled()
    SetBarEnabled(next)
    if next then
        Refresh(false)
    else
        if card then card:Hide(); currentState = -1 end
    end
    print(string.format("|cffcc44ccPreyTracker|r Progress bar: |cffffd700%s|r",
        next and "ON" or "OFF"))
end

-- /prey widget — toggle Blizzard's widget on/off
function PH.ToggleBlizzWidget()
    local next = not IsWidgetHidden()
    SetWidgetHidden(next)
    if next then SuppressBlizzWidget()
    else         UnsuppressBlizzWidget() end
    print(string.format("|cffcc44ccPreyTracker|r Blizzard widget: |cffffd700%s|r",
        next and "hidden" or "shown"))
end

-- /prey bar reset — snap bar back to default position
function PH.ResetProgressBarPosition()
    ClearSavedPos()
    if card then AnchorToDefault() end
    print("|cffcc44ccPreyTracker|r Progress bar position reset.")
end

-- ─── Events ───────────────────────────────────────────────────────────────────
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("UPDATE_UI_WIDGET")
evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evtFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
evtFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UPDATE_UI_WIDGET" then
        local wid = type(arg1) == "table" and arg1.widgetID or arg1
        if wid == PREY_WIDGET_ID or wid == nil then Refresh(true) end
    else
        C_Timer.After(0.8, function() Refresh(false) end)
    end
end)

C_Timer.NewTicker(POLL_INTERVAL, function() Refresh(false) end)