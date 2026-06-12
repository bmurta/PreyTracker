-- PreyTracker — HuntBoard.lua
-- The Hunt Board (HUNTBOARD_SPEC.md): the map-open main screen that replaces the
-- docked side panel. Builds the static layout — header, zone column headers,
-- rotated difficulty row labels, the 4×3 card grid, and the footer — from the
-- Widgets.lua factories, then drives it from the live pipeline (PH.PopulateBoard
-- reads PH.liveHunts / PH.rewardCache / PH.IsInProgress / widget 7663 / currency
-- 3392). Core.lua shows it via PH.ShowBoard after the loading overlay finishes;
-- PH.HideBoard tears it down on map close / ForceHidePanel.
--
-- Load order (CLAUDE.md): runs after Widgets.lua + Config.lua, so PH.CreateCard,
-- PH.PAL and PH.CFG all exist. Functions here are only ever called at runtime
-- (slash handler, Core.lua event hooks), never captured by value at load.
local PH  = PreyTracker
local CFG = PH.CFG
local PAL = PH.PAL

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT  = "Fonts\\FRIZQT__.TTF"

local PREY_WIDGET_ID = 7663   -- prey hunt progress widget (Progress.lua owns the bar)

-- Card model framing. Portrait zoom aims the camera vertically (0 = full body,
-- 1 = head/shoulders) — higher moves up toward the face. Cam scale is the camera
-- distance multiplier — >1 pulls back (zooms out), <1 moves in. Tune to taste.
local MODEL_PORTRAIT_ZOOM = 1.0
local MODEL_CAM_SCALE     = 1.45

local function ColorObj(c, a) return CreateColor(c[1], c[2], c[3], a or 1) end

-- Small font-string helper so every label sets its size the same way.
local function FS(parent, size, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size, flags)
    return fs
end

-- Footer scan-age text. PH.lastScanTime is stamped by RefreshFromPins (Data.lua)
-- each time the pins are scraped; this renders the elapsed time coarsely.
local function FormatAge(t)
    if not t then return "not scanned" end
    local s = GetTime() - t
    if s < 5    then return "just now" end
    if s < 60   then return string.format("%ds ago", math.floor(s)) end
    if s < 3600 then return string.format("%dm ago", math.floor(s / 60)) end
    return string.format("%dh ago", math.floor(s / 3600))
end

-- ---------------------------------------------------------------------------
-- Layout constants (HUNTBOARD_SPEC.md §Window layout, 1200×706 reference).
-- Built at this reference size; ToggleHuntBoard SetScale's it to fit the screen
-- for standalone iteration. Phase 3 re-anchors it to cover CovenantMissionFrame.
-- ---------------------------------------------------------------------------
local PAD       = 16
local HEADER_H  = 58
local GUTTER_W  = 36   -- left row-label gutter
local COLH_H    = 22   -- zone column-header strip
local CARD_W    = 262
local CARD_H    = 170
local GAP       = 14
local FOOTER_H  = 46

-- Grid origin (offset from board TOPLEFT) derived from the stack above.
local GRID_LEFT = PAD + GUTTER_W                       -- 52
local GRID_TOP  = 8 + HEADER_H + 8 + COLH_H + 6        -- 102
local ROW_PITCH = CARD_H + GAP                         -- 184
local COL_PITCH = CARD_W + GAP                         -- 276

local WIN_W = GRID_LEFT + 4 * CARD_W + 3 * GAP + PAD   -- 1158
local WIN_H = GRID_TOP + 3 * CARD_H + 2 * GAP + 10 + FOOTER_H + 8  -- 704

-- Grid order: zones left→right (PH.ZONE_ORDER), difficulties top→bottom.
local ZONES = { "Eversong Woods", "Zul'Aman", "Harandar", "Voidstorm" }
local DIFFS = { "Nightmare", "Hard", "Normal" }

-- Creature silhouette texture per zone (media/README.md).
local ZONE_SIL = {
    ["Eversong Woods"] = "sil_stag",
    ["Zul'Aman"]       = "sil_cat",
    ["Harandar"]       = "sil_bat",
    ["Voidstorm"]      = "sil_void",
}

local CARD_BORDER_HOVER = { 0.28, 0.30, 0.38 }

-- ---------------------------------------------------------------------------
-- Load a creature into a card's PlayerModel, reliably. An uncached creature model
-- loads asynchronously, and SetCreature's auto-camera is computed once, against
-- the (empty) bounds available at call time — so a model set before its load
-- finishes frames on nothing and renders blank. The engine doesn't re-frame when
-- the load later completes, which is why blank cards only appeared after a close
-- + reopen (a second apply on the now-loaded model). So we re-apply once the load
-- completes: OnModelLoaded is the trigger, with a timer fallback if it doesn't
-- fire. Re-applying an already-framed (cached) model is a no-op, so no flicker.
-- _loadedKey skips redundant reloads so re-populates (QUEST_LOG_UPDATE) don't churn.
-- ---------------------------------------------------------------------------
local function LoadCardModel(model, creatureID, displayID)
    local key = displayID and ("d" .. displayID) or ("c" .. creatureID)
    if model._loadedKey == key then return end
    model._loadedKey = key

    local function reframe()
        if model._loadedKey ~= key then return end  -- superseded by a newer load
        if displayID then model:SetDisplayInfo(displayID)
        else               model:SetCreature(creatureID) end
        model:SetPortraitZoom(MODEL_PORTRAIT_ZOOM)  -- aim up toward the face
        model:SetCamDistanceScale(MODEL_CAM_SCALE)  -- pull the camera back a bit
        model:SetFacing(0.5)
    end

    model._reframe = reframe
    reframe()                        -- kick off the (async) load
    -- Fallback if OnModelLoaded doesn't fire: re-apply a few times over the next
    -- few seconds. Each skips once OnModelLoaded has cleared _reframe; re-applying
    -- an already-framed model is harmless.
    for _, delay in ipairs({ 0.5, 1.5, 3.0 }) do
        C_Timer.After(delay, function()
            if model._reframe == reframe then reframe() end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Card factory — one cell of the grid. Zone/difficulty are fixed per cell, so
-- the stage visuals (zone glow, platform, silhouette, difficulty bar) are baked
-- here; SetData only flips the per-hunt, per-state chrome.
-- ---------------------------------------------------------------------------
local function BuildCard(parent, zone, diff)
    local zc = CFG.ZONE_COLOR[zone] or CFG.ZONE_COLOR.DEFAULT
    local zoneC = { zc.r, zc.g, zc.b }

    local card = PH.CreateCard(parent)
    card:SetSize(CARD_W, CARD_H)
    card:EnableMouse(true)
    card.zone, card.diff = zone, diff

    -- Selected-state violet glow ring (behind the card).
    local ring = PH.CreateGlow(card, "card", "BACKGROUND", -1)
    ring:SetPoint("TOPLEFT", -10, 10)
    ring:SetPoint("BOTTOMRIGHT", 10, -10)
    PH.Color(ring, PAL.violet, 0.9)
    ring:Hide()
    card.ring = ring

    -- In-progress gold wash, fading in from the left edge.
    local wash = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetTexture(WHITE)
    wash:SetPoint("TOPLEFT", 3, -3)
    wash:SetPoint("BOTTOMRIGHT", -3, 3)
    if wash.SetGradient then
        wash:SetGradient("HORIZONTAL", ColorObj(PAL.gold, 0.16), ColorObj(PAL.gold, 0))
    else
        PH.Color(wash, PAL.gold, 0.08)
    end
    wash:Hide()
    card.wash = wash

    -- Difficulty bar across the top (inset 12px each side).
    local diffBar = card:CreateTexture(nil, "ARTWORK")
    diffBar:SetTexture(PH.MEDIA.panel_bg)
    diffBar:SetPoint("TOPLEFT", 12, -7)
    diffBar:SetPoint("TOPRIGHT", -12, -7)
    diffBar:SetHeight(3)
    PH.Color(diffBar, PH.DiffColor(diff))
    card.diffBar = diffBar

    -- Model viewport ---------------------------------------------------------
    local vp = PH.CreateCard(card, PAL.viewportBg, PAL.cardBorder)
    vp:SetPoint("TOPLEFT", 4, -14)
    vp:SetPoint("TOPRIGHT", -4, -14)
    vp:SetHeight(92)
    card.vp = vp

    local zoneGlow = PH.CreateIcon(vp, "zone_glow", nil, "BACKGROUND", 1)
    zoneGlow:SetPoint("CENTER", 0, -4)
    zoneGlow:SetSize(240, 92)
    zoneGlow:SetBlendMode("ADD")
    PH.Color(zoneGlow, zoneC, 0.40)
    card.zoneGlow = zoneGlow

    local platform = PH.CreateIcon(vp, "platform", nil, "ARTWORK", 0)
    platform:SetPoint("BOTTOM", 0, 6)
    platform:SetSize(160, 40)
    PH.Color(platform, zoneC)
    card.platform = platform

    local sil = PH.CreateIcon(vp, ZONE_SIL[zone], nil, "ARTWORK", 1)
    sil:SetPoint("BOTTOM", 0, 12)
    sil:SetSize(132, 82)
    PH.Color(sil, PAL.silhouette)
    card.sil = sil

    -- Void creature eyes: two small violet additive dots.
    card.eyes = {}
    if zone == "Voidstorm" then
        for _, dx in ipairs({ -8, 8 }) do
            local eye = PH.CreateGlow(vp, "radial", "OVERLAY")
            eye:SetSize(6, 6)
            eye:SetPoint("CENTER", sil, "CENTER", dx, 16)
            PH.Color(eye, PAL.violet)
            card.eyes[#card.eyes + 1] = eye
        end
    end

    -- Optional real 3D creature model (SetCreature from PH.HUNT_CREATURES, or a
    -- displayID override; resolved in SetData); otherwise the flat silhouette
    -- above stands in. Created before the pill/chip so those stay on top of it.
    local model = CreateFrame("PlayerModel", nil, vp)
    model:SetPoint("TOPLEFT", vp, "TOPLEFT", 6, -4)
    model:SetPoint("BOTTOMRIGHT", vp, "BOTTOMRIGHT", -6, 4)
    model:Hide()
    card.model = model

    -- A creature model set before it finishes loading (async, uncached creatures)
    -- can't auto-frame its camera yet, so the card comes up blank. Re-apply once
    -- the load completes, against the now-known model bounds. (This is why a blank
    -- card used to render only after a close + reopen — that was a second apply.)
    model:SetScript("OnModelLoaded", function(self)
        self:SetFacing(0.5)
        local reframe = self._reframe
        if reframe then
            self._reframe = nil
            reframe()
        end
    end)

    -- Status pill (top-left of viewport).
    local pill = PH.CreatePill(vp)
    pill:SetSize(86, 20)
    pill:SetPoint("TOPLEFT", 6, -6)
    pill.dot = PH.CreateIcon(pill, "icon_dot", 8, "OVERLAY")
    pill.dot:SetPoint("LEFT", 9, 0)
    pill.text:ClearAllPoints()
    pill.text:SetPoint("LEFT", pill.dot, "RIGHT", 4, 0)
    pill.text:SetFont(FONT, 10)
    card.pill = pill

    -- Achievement chip (top-right of viewport) — Nightmare row only.
    if diff == "Nightmare" then
        local chip = PH.CreateCard(vp, { 0.07, 0.08, 0.11 }, PAL.cardBorder)
        chip:SetSize(22, 22)
        chip:SetPoint("TOPRIGHT", -6, -6)
        chip.trophy = PH.CreateIcon(chip, "icon_trophy", 14, "OVERLAY")
        chip.trophy:SetPoint("CENTER")
        chip.check = PH.CreateIcon(chip, "icon_check", 14, "OVERLAY")
        chip.check:SetPoint("CENTER")
        PH.Color(chip.check, PAL.diffNormal)
        chip.check:Hide()
        card.chip = chip
    end

    -- Empty-cell label (hidden unless the cell has no hunt).
    local emptyText = FS(card, 11)
    emptyText:SetPoint("CENTER", vp, "CENTER", 0, 0)
    emptyText:SetText("No hunt detected")
    emptyText:SetTextColor(PAL.textFaint[1], PAL.textFaint[2], PAL.textFaint[3])
    emptyText:Hide()
    card.emptyText = emptyText

    -- Name -------------------------------------------------------------------
    local name = FS(card, 12, nil, "OVERLAY")
    name:SetPoint("TOPLEFT", vp, "BOTTOMLEFT", 4, -7)
    name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    name:SetJustifyH("LEFT")
    name:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    card.name = name

    -- Reward icons (bottom-left) --------------------------------------------
    card.rewardIcons = {}
    for i = 1, 3 do
        local ri = CreateFrame("Frame", nil, card)
        ri:SetSize(22, 22)
        ri:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 25, 10)
        ri.tex = ri:CreateTexture(nil, "ARTWORK")
        ri.tex:SetPoint("TOPLEFT", 2, -2)
        ri.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        ri.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ri.bd = ri:CreateTexture(nil, "OVERLAY")
        ri.bd:SetAllPoints()
        ri.bd:SetTexture(PH.MEDIA.panel_border)
        PH.ApplySlice(ri.bd, 16, 16, 16, 16)
        PH.Color(ri.bd, PAL.cardBorder)
        ri.count = FS(ri, 10, "OUTLINE")
        ri.count:SetPoint("BOTTOMRIGHT", 1, -1)
        ri:Hide()
        card.rewardIcons[i] = ri
    end

    -- Accept button (selected / hover), with a soft green glow.
    local accept = PH.CreateAcceptButton(card, "Accept")
    accept:SetSize(70, 22)
    accept:SetPoint("BOTTOMRIGHT", -8, 10)
    accept.text:SetFont(FONT, 11)
    local ag = PH.CreateGlow(accept, "radial", "BACKGROUND", -1)
    ag:SetPoint("TOPLEFT", -8, 8)
    ag:SetPoint("BOTTOMRIGHT", 8, -8)
    PH.Color(ag, PAL.acceptTop, 0.7)
    accept:SetPropagateMouseClicks(false)
    accept:SetScript("OnClick", function()
        -- Accept flow — identical to UI.lua PopulateRow's accept button: open
        -- the hidden quest-choice dialog for this quest, accept, close the map.
        local questID = card.questID
        if not questID then return end
        local dialog = AdventureMapQuestChoiceDialog
        if not (dialog and dialog.ShowWithQuest and dialog.AcceptQuest) then return end
        -- Needs a live offer pin to accept against; a card rendered from the
        -- cache (e.g. while another hunt is in progress) has none — bail quietly.
        local pin = PH.FindPin(questID)
        if not pin then return end
        dialog:SetAlpha(1)
        dialog:ClearAllPoints()
        dialog:SetPoint("CENTER", UIParent, "CENTER")
        dialog:ShowWithQuest(CovenantMissionFrame, pin, questID)
        dialog:AcceptQuest()
        HideUIPanel(CovenantMissionFrame)
    end)
    accept:Hide()
    card.accept = accept

    -- Out-of-map hint that stands in for Accept when there are no live pins to
    -- accept against (PH.standalone). Faint, right-aligned where Accept sits.
    local hint = FS(card, 9, nil, "OVERLAY")
    hint:SetPoint("BOTTOMRIGHT", -8, 9)
    hint:SetWidth(150)
    hint:SetJustifyH("RIGHT")
    hint:SetWordWrap(true)
    hint:SetText("Open the Prey map to accept")
    hint:SetTextColor(PAL.textFaint[1], PAL.textFaint[2], PAL.textFaint[3])
    hint:Hide()
    card.acceptHint = hint

    -- Mini 3-segment progress meter (in-progress card, from widget 7663).
    local meter = CreateFrame("Frame", nil, card)
    meter:SetSize(66, 7)
    meter:SetPoint("BOTTOMRIGHT", -10, 16)
    card.meterSegs = {}
    local segW = (66 - 2 * 3) / 3
    for i = 1, 3 do
        local seg = meter:CreateTexture(nil, "ARTWORK")
        seg:SetTexture(WHITE)
        seg:SetSize(segW, 7)
        seg:SetPoint("LEFT", (i - 1) * (segW + 3), 0)
        card.meterSegs[i] = seg
    end
    meter:Hide()
    card.meter = meter

    -- -----------------------------------------------------------------------
    -- Interaction. Hovering an available card lightens its border and reveals
    -- the Accept button; clicking selects it (violet ring + glowing Accept).
    -- In-progress and empty cells ignore the mouse. One card is selected at a
    -- time (PH.SelectCard). Accept fires the real quest-accept flow above.
    -- -----------------------------------------------------------------------
    card:SetScript("OnEnter", function(self)
        if self.data and not self.inProgress and not self.selected then
            self.hovered = true
            self:Render()
        end
        PH.ShowCardTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        -- The Accept button is a mouse-enabled child that only appears on hover;
        -- moving the cursor onto it fires this OnLeave even though we're still
        -- inside the card. Ignore those so showing/hiding Accept can't ping-pong
        -- the hover state (the flashing bug). Only truly leaving the card counts.
        if self:IsMouseOver() then return end
        if self.hovered then
            self.hovered = false
            self:Render()
        end
        GameTooltip:Hide()
    end)
    card:SetScript("OnMouseUp", function(self, button)
        -- Selecting only makes sense when Accept is live (map mode). Out of the
        -- map there's nothing to accept against, so a click just leaves the hint.
        if button == "LeftButton" and self.data and not self.inProgress
            and not PH.standalone then
            PH.SelectCard(self)
        end
    end)

    -- -----------------------------------------------------------------------
    -- Render — paint the card from self.data + interaction flags. self.data is
    -- a hunt table { name, questID, rewards, inProgress, progress } or nil for
    -- an empty cell.
    -- -----------------------------------------------------------------------
    function card:Render()
        local d = self.data

        -- Reset transient chrome to the plain "available" baseline.
        self.ring:Hide()
        self.wash:Hide()
        self.accept:Hide()
        self.acceptHint:Hide()
        self.meter:Hide()
        self.emptyText:Hide()
        PH.Color(self.border, PAL.cardBorder)
        PH.Color(self.bg, PAL.cardSurface)
        self.diffBar:Show()
        self.pill:Show()
        self.name:Show()
        self.zoneGlow:SetAlpha(1)
        self.platform:SetAlpha(1)
        self.sil:Show()
        self.sil:SetAlpha(1)
        for _, e in ipairs(self.eyes) do e:Show() end
        if self.chip then self.chip:Show() end

        if not d then
            -- Empty cell: faint border, dim stage, "No hunt detected".
            self.diffBar:Hide()
            self.pill:Hide()
            self.name:Hide()
            if self.chip then self.chip:Hide() end
            for _, ri in ipairs(self.rewardIcons) do ri:Hide() end
            for _, e in ipairs(self.eyes) do e:Hide() end
            PH.Color(self.border, PAL.cardBorder, 0.3)
            PH.Color(self.bg, PAL.cardSurface, 0.5)
            self.zoneGlow:SetAlpha(0.10)
            self.platform:SetAlpha(0.25)
            self.sil:SetAlpha(0.10)
            self.emptyText:Show()
            return
        end

        self.name:SetText(d.name)

        -- Real 3D creature model (set up in SetData) replaces the silhouette.
        if self.hasModel then
            self.sil:Hide()
            for _, e in ipairs(self.eyes) do e:Hide() end
        end

        -- Reward icons — real PH.rewardCache entries (icon + optional count).
        local rewards = d.rewards or {}
        for i, ri in ipairs(self.rewardIcons) do
            local r = rewards[i]
            if r then
                ri.tex:SetTexture(r.icon)
                ri.count:SetText(r.count or "")
                ri:Show()
            else
                ri:Hide()
            end
        end

        -- Achievement chip (Nightmare row): trophy = still needed, check = done.
        -- Live achievement state arrives in Phase 4; default to "needed".
        if self.chip then
            local done = d.achieveDone == true
            self.chip.trophy:SetShown(not done)
            self.chip.check:SetShown(done)
        end

        -- Status pill + per-state chrome.
        local function SetPill(c, label)
            PH.Color(self.pill.dot, c)
            self.pill.text:SetText(label)
            self.pill.text:SetTextColor(c[1], c[2], c[3])
            self.pill:SetWidth(self.pill.text:GetStringWidth() + 34)
        end

        if self.inProgress then
            -- Current prey: the strongest emphasis on the board — full gold
            -- border plus the card_glow ring (HUNTBOARD_SPEC.md Phase 5). Every
            -- other cell stays a plain "available this week" card.
            SetPill(PAL.gold, "In Progress")
            PH.Color(self.border, PAL.gold)
            PH.Color(self.ring, PAL.gold, 0.9)
            self.ring:Show()
            self.wash:Show()
            self.meter:Show()
            local prog = d.progress or 0
            for i, seg in ipairs(self.meterSegs) do
                if i <= prog then
                    seg:SetVertexColor(PAL.gold[1], PAL.gold[2], PAL.gold[3], 1)
                else
                    seg:SetVertexColor(0.10, 0.10, 0.14, 1)
                end
            end
        else
            SetPill(PAL.cyan, "Available")
            if self.selected then
                PH.Color(self.border, PAL.violet)
                PH.Color(self.ring, PAL.violet, 0.9)
                self.ring:Show()
            elseif self.hovered then
                PH.Color(self.border, CARD_BORDER_HOVER)
            end
            if PH.standalone then
                -- Out of the map (no live pins): faint hint instead of Accept.
                self.acceptHint:Show()
            elseif self.selected then
                self.accept:Show()
                ag:SetAlpha(1)
            elseif self.hovered then
                self.accept:Show()
                ag:SetAlpha(0.7)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- SetData — store this cell's hunt (or nil) and repaint. Clears transient
    -- selection/hover; PopulateBoard restores the prior selection afterward.
    -- -----------------------------------------------------------------------
    function card:SetData(d)
        self.data       = d
        self.questID    = d and d.questID or nil
        self.inProgress = (d and d.inProgress) or false
        self.selected   = false
        self.hovered    = false

        -- Resolve + apply the creature model once here (not in Render, which fires
        -- on every hover/select). Keyed by hunt/creature name: a hardcoded NPC id
        -- (PH.HUNT_CREATURES) via SetCreature is the norm; a displayID override
        -- (PH.HUNT_MODELS) wins if present. Apply while the model is shown so it
        -- actually renders (PlayerModels won't load a model set while hidden).
        local creatureID = d and PH.HUNT_CREATURES and PH.HUNT_CREATURES[d.name]
        local displayID  = d and PH.HUNT_MODELS    and PH.HUNT_MODELS[d.name]
        self.hasModel = (creatureID or displayID) and true or false
        if self.hasModel then
            self.model:Show()
            LoadCardModel(self.model, creatureID, displayID)
        else
            self.model:Hide()
        end

        self:Render()
    end

    return card
end

-- ---------------------------------------------------------------------------
-- Header — paw logo, title, Anguish chip, close button, violet hairline.
-- ---------------------------------------------------------------------------
local function BuildHeader(board, content)
    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", PAD, -8)
    header:SetPoint("TOPRIGHT", -PAD, -8)
    header:SetHeight(HEADER_H)

    -- Violet gradient hairline across the very top.
    local hair = content:CreateTexture(nil, "OVERLAY")
    hair:SetTexture(WHITE)
    hair:SetPoint("TOPLEFT", 10, -3)
    hair:SetPoint("TOPRIGHT", -10, -3)
    hair:SetHeight(2)
    if hair.SetGradient then
        hair:SetGradient("HORIZONTAL", ColorObj(PAL.violet, 0.9), ColorObj(PAL.violet, 0.05))
    else
        PH.Color(hair, PAL.violet, 0.6)
    end

    -- Logo: the red prey crystal (icon_prey). It carries its own aura/glow, so
    -- there's no violet plate behind it and it is NOT vertex-tinted (pre-colored).
    local logo = CreateFrame("Frame", nil, header)
    logo:SetSize(40, 40)
    logo:SetPoint("LEFT", 0, 0)
    local crystal = PH.CreateIcon(logo, "icon_prey", nil, "OVERLAY")
    crystal:SetSize(40, 40)
    crystal:SetPoint("CENTER")

    -- Title: "Prey" (violet) + "Tracker" (white), with "HUNT BOARD" beside it.
    local prey = FS(header, 20, nil, "OVERLAY")
    prey:SetPoint("BOTTOMLEFT", logo, "TOPRIGHT", 10, -22)
    prey:SetText("Prey")
    prey:SetTextColor(PAL.violet[1], PAL.violet[2], PAL.violet[3])

    local tracker = FS(header, 20, nil, "OVERLAY")
    tracker:SetPoint("LEFT", prey, "RIGHT", 0, 0)
    tracker:SetText("Tracker")
    tracker:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])

    local label = FS(header, 11, nil, "OVERLAY")
    label:SetPoint("LEFT", tracker, "RIGHT", 10, 1)
    label:SetText("HUNT BOARD")
    label:SetTextColor(PAL.textDim[1], PAL.textDim[2], PAL.textDim[3])

    local sub = FS(header, 9, nil, "OVERLAY")
    sub:SetPoint("TOPLEFT", prey, "BOTTOMLEFT", 0, -3)
    sub:SetText("ONE HUNT PER DIFFICULTY, PER ZONE")
    sub:SetTextColor(PAL.textFaint[1], PAL.textFaint[2], PAL.textFaint[3])

    -- Close button (right edge). Over the map it closes the map too, routing
    -- through HideUIPanel so the existing Core.lua hook tears the board down
    -- once (no double-fire); out of the map it just hides the board.
    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", 0, 0)
    local x = PH.CreateIcon(close, "icon_close", 14, "OVERLAY")
    x:SetPoint("CENTER")
    PH.Color(x, PAL.textDim)
    close:SetScript("OnEnter", function() PH.Color(x, PAL.text) end)
    close:SetScript("OnLeave", function() PH.Color(x, PAL.textDim) end)
    close:SetScript("OnClick", function()
        if CovenantMissionFrame and CovenantMissionFrame:IsShown() then
            HideUIPanel(CovenantMissionFrame)   -- Core hook → HidePanel → HideBoard
        else
            PH.HideBoard()
        end
    end)
    board.closeBtn = close

    -- Minimize button (–), left of close. Map mode only (UpdateBoardChrome shows
    -- it); reveals Blizzard's map underneath and drops a restore chip on it.
    local minBtn = CreateFrame("Button", nil, header)
    minBtn:SetSize(24, 24)
    minBtn:SetPoint("RIGHT", close, "LEFT", -2, 0)
    local dash = minBtn:CreateTexture(nil, "OVERLAY")
    dash:SetTexture(WHITE)
    dash:SetSize(11, 2)
    dash:SetPoint("CENTER")
    PH.Color(dash, PAL.textDim)
    minBtn:SetScript("OnEnter", function() PH.Color(dash, PAL.text) end)
    minBtn:SetScript("OnLeave", function() PH.Color(dash, PAL.textDim) end)
    minBtn:SetScript("OnClick", function() PH.MinimizeBoard() end)
    board.minBtn = minBtn

    -- Anguish chip (red pill: gem + amount). Anchored left of whichever control
    -- is rightmost for the current mode — UpdateBoardChrome re-points it.
    local chip = PH.CreatePill(header, { 0.18, 0.05, 0.05 }, PAL.anguishRed)
    chip:SetSize(72, 24)
    chip:SetPoint("RIGHT", minBtn, "LEFT", -8, 0)
    local gem = PH.CreateIcon(chip, "icon_gem", 14, "OVERLAY")
    gem:SetPoint("LEFT", 8, 0)
    chip.text:ClearAllPoints()
    chip.text:SetPoint("LEFT", gem, "RIGHT", 4, 0)
    chip.text:SetFont(FONT, 12)
    chip.text:SetText("1,250")
    chip.text:SetTextColor(PAL.anguishRed[1], PAL.anguishRed[2], PAL.anguishRed[3])
    board.anguishChip = chip

    -- Drag the board around by the header. When docked over the map the board is
    -- anchored to both map corners; undock it first (freezing the current size so
    -- clearing the corner anchors doesn't collapse the frame) so it can be moved
    -- aside to reach the map/pins behind it. Reopening the map re-docks it.
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if board.dockedToMap then
            board:SetSize(board:GetWidth(), board:GetHeight())
            board.dockedToMap = false
        end
        board:StartMoving()
    end)
    header:SetScript("OnDragStop", function() board:StopMovingOrSizing() end)
end

-- ---------------------------------------------------------------------------
-- Footer — counts | trophy + achievement bar | rescan + scan age.
-- ---------------------------------------------------------------------------
local function BuildFooter(board, content)
    local footer = CreateFrame("Frame", nil, content)
    footer:SetPoint("BOTTOMLEFT", GRID_LEFT, 8)
    footer:SetPoint("BOTTOMRIGHT", -PAD, 8)
    footer:SetHeight(FOOTER_H)

    -- Hairline above the footer.
    local rule = footer:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(WHITE)
    rule:SetPoint("TOPLEFT", 0, 2)
    rule:SetPoint("TOPRIGHT", 0, 2)
    rule:SetHeight(1)
    PH.Color(rule, PAL.cardBorder, 0.8)

    -- Left: "N In Progress · N Available".
    local counts = FS(footer, 12, nil, "OVERLAY")
    counts:SetPoint("LEFT", 0, 0)
    board.footerCounts = counts

    -- Center: trophy + achievement name + violet bar + "x/y". The trophy is a
    -- mouse-enabled frame so it can show a tooltip of the remaining criteria;
    -- the name/count/bar are driven from Achievements.lua by UpdateBoardAchievement.
    local trophyBtn = CreateFrame("Frame", nil, footer)
    trophyBtn:SetSize(18, 18)
    trophyBtn:SetPoint("CENTER", footer, "CENTER", -150, 0)
    trophyBtn:EnableMouse(true)
    local trophy = PH.CreateIcon(trophyBtn, "icon_trophy", 16, "OVERLAY")
    trophy:SetPoint("CENTER")
    trophyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local name, completed, total = PH.GetAchievementSummary()
        GameTooltip:SetText(name, PAL.violet[1], PAL.violet[2], PAL.violet[3])
        if total == 0 then
            GameTooltip:AddLine("Achievement not detected yet.",
                PAL.textFaint[1], PAL.textFaint[2], PAL.textFaint[3])
        else
            GameTooltip:AddLine(string.format("%d / %d complete", completed, total), 0.9, 0.9, 0.9)
            local remaining = PH.GetRemainingCriteria()
            if #remaining == 0 then
                GameTooltip:AddLine("All criteria complete!",
                    PAL.diffNormal[1], PAL.diffNormal[2], PAL.diffNormal[3])
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Remaining:", PAL.textDim[1], PAL.textDim[2], PAL.textDim[3])
                for _, n in ipairs(remaining) do
                    GameTooltip:AddLine("|cffffd24d•|r " .. n, PAL.text[1], PAL.text[2], PAL.text[3])
                end
            end
        end
        GameTooltip:Show()
    end)
    trophyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local achName = FS(footer, 11, nil, "OVERLAY")
    achName:SetPoint("LEFT", trophyBtn, "RIGHT", 6, 0)
    achName:SetText("PREY: NIGHTMARE MODE III")
    achName:SetTextColor(PAL.textDim[1], PAL.textDim[2], PAL.textDim[3])
    board.achName = achName

    local barBg = PH.CreatePill(footer, { 0.06, 0.06, 0.09 }, PAL.cardBorder)
    barBg:SetSize(120, 10)
    barBg:SetPoint("LEFT", achName, "RIGHT", 10, 0)
    local barFill = barBg:CreateTexture(nil, "ARTWORK")
    barFill:SetTexture(WHITE)
    barFill:SetPoint("LEFT", 2, 0)
    barFill:SetSize(1, 6)
    PH.Color(barFill, PAL.violet)
    board.achBarFill = barFill
    board.achBarW    = 116   -- pill width (120) minus the 2px inset on each side

    local barText = FS(footer, 11, nil, "OVERLAY")
    barText:SetPoint("LEFT", barBg, "RIGHT", 8, 0)
    barText:SetText("0/0")
    barText:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    board.achBarText = barText

    -- Right: scan age + Rescan button.
    local age = FS(footer, 11, nil, "OVERLAY")
    age:SetPoint("RIGHT", 0, 0)
    age:SetText(FormatAge(PH.lastScanTime))
    age:SetTextColor(PAL.textFaint[1], PAL.textFaint[2], PAL.textFaint[3])
    board.scanAge = age

    local rescan = PH.CreateCard(footer, { 0.10, 0.11, 0.15 }, PAL.cardBorder)
    rescan:SetSize(86, 26)
    rescan:SetPoint("RIGHT", age, "LEFT", -10, 0)
    rescan:EnableMouse(true)
    local rIcon = PH.CreateIcon(rescan, "icon_reload", 13, "OVERLAY")
    rIcon:SetPoint("LEFT", 10, 0)
    PH.Color(rIcon, PAL.cyan)
    local rText = FS(rescan, 11, nil, "OVERLAY")
    rText:SetPoint("LEFT", rIcon, "RIGHT", 5, 0)
    rText:SetText("Rescan")
    rText:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    board.rescanText = rText
    rescan:SetScript("OnMouseUp", function() PH.RescanBoard() end)
    rescan:SetScript("OnEnter", function() PH.Color(rescan.border, CARD_BORDER_HOVER) end)
    rescan:SetScript("OnLeave", function() PH.Color(rescan.border, PAL.cardBorder) end)
end

-- ---------------------------------------------------------------------------
-- Build the whole board once. Stored on PH.huntBoard; cards on PH.boardCards.
-- ---------------------------------------------------------------------------
function PH.BuildHuntBoard()
    if PH.huntBoard then return PH.huntBoard end

    local board = CreateFrame("Frame", "PreyTrackerHuntBoard", UIParent)
    board:SetSize(WIN_W, WIN_H)
    board:SetFrameStrata("DIALOG")
    board:EnableMouse(true)        -- swallow clicks meant for the board
    board:SetMovable(true)
    board:SetClampedToScreen(true)
    board:Hide()

    -- Keep the footer's "Xm ago" scan age ticking up while the board is open
    -- (throttled — the elapsed time only needs coarse, ~5s, accuracy).
    board._ageAccum = 5
    board:SetScript("OnUpdate", function(self, dt)
        self._ageAccum = self._ageAccum + dt
        if self._ageAccum < 5 then return end
        self._ageAccum = 0
        if self.scanAge then self.scanAge:SetText(FormatAge(PH.lastScanTime)) end
    end)

    -- Background gradient (top → bottom) + border.
    board.bg = board:CreateTexture(nil, "BACKGROUND")
    board.bg:SetAllPoints()
    board.bg:SetTexture(PH.MEDIA.panel_bg)
    PH.ApplySlice(board.bg, 16, 16, 16, 16)
    if board.bg.SetGradient then
        board.bg:SetGradient("VERTICAL", ColorObj(PAL.bgBottom), ColorObj(PAL.bgTop))
    else
        PH.Color(board.bg, PAL.bgTop)
    end

    board.border = board:CreateTexture(nil, "BORDER")
    board.border:SetAllPoints()
    board.border:SetTexture(PH.MEDIA.panel_border)
    PH.ApplySlice(board.border, 16, 16, 16, 16)
    PH.Color(board.border, PAL.cardBorder)

    -- Content holder at the fixed reference size. The bg/border above fill the
    -- board (which covers the whole map); this frame carries the actual layout
    -- and is uniformly scaled by AnchorBoardToMap so the grid keeps its
    -- proportions whatever size the map behind it is.
    local content = CreateFrame("Frame", nil, board)
    content:SetSize(WIN_W, WIN_H)
    content:SetPoint("CENTER", board, "CENTER", 0, 0)
    board.content = content

    BuildHeader(board, content)

    -- Zone column headers (zone color + dot, centered over each column).
    for j, zone in ipairs(ZONES) do
        local zc = CFG.ZONE_COLOR[zone] or CFG.ZONE_COLOR.DEFAULT
        local cx = GRID_LEFT + (j - 1) * COL_PITCH + CARD_W / 2

        local name = FS(content, 12, nil, "OVERLAY")
        name:SetPoint("CENTER", content, "TOPLEFT", cx + 7, -(8 + HEADER_H + 8 + COLH_H / 2))
        name:SetText(zone:upper())
        name:SetTextColor(zc.r, zc.g, zc.b)

        local dot = PH.CreateIcon(content, "icon_dot", 8, "OVERLAY")
        dot:SetPoint("RIGHT", name, "LEFT", -6, 0)
        PH.Color(dot, { zc.r, zc.g, zc.b })
    end

    -- Rotated difficulty row labels + colored gutter bars.
    for i, diff in ipairs(DIFFS) do
        local dc = PH.DiffColor(diff)
        local rowTop = -(GRID_TOP + (i - 1) * ROW_PITCH)

        local bar = content:CreateTexture(nil, "ARTWORK")
        bar:SetTexture(WHITE)
        bar:SetPoint("TOPLEFT", content, "TOPLEFT", GRID_LEFT - 11, rowTop)
        bar:SetSize(3, CARD_H)
        PH.Color(bar, dc)

        local label = FS(content, 11, nil, "OVERLAY")
        label:SetPoint("CENTER", content, "TOPLEFT", PAD + 8, rowTop - CARD_H / 2)
        label:SetText(diff:upper())
        label:SetTextColor(dc[1], dc[2], dc[3])
        label:SetRotation(math.pi / 2)
    end

    -- 4×3 card grid.
    PH.boardCards = {}
    for i, diff in ipairs(DIFFS) do
        for j, zone in ipairs(ZONES) do
            local card = BuildCard(content, zone, diff)
            card:SetPoint("TOPLEFT", content, "TOPLEFT",
                GRID_LEFT + (j - 1) * COL_PITCH,
                -(GRID_TOP + (i - 1) * ROW_PITCH))
            PH.boardCards[zone .. "|" .. diff] = card
        end
    end

    BuildFooter(board, content)

    -- Out-of-map empty state, covering the grid. PopulateBoard shows it only when
    -- the board is standalone and nothing has ever been scanned (mirrors the old
    -- UI.lua "no hunts recorded yet"); otherwise the 4×3 grid shows through.
    local empty = CreateFrame("Frame", nil, content)
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -(8 + HEADER_H + 8))
    empty:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD, FOOTER_H + 14)
    empty:SetFrameLevel(content:GetFrameLevel() + 50)
    empty:EnableMouse(true)   -- swallow clicks so cards behind it don't react
    local ebg = empty:CreateTexture(nil, "BACKGROUND")
    ebg:SetAllPoints()
    ebg:SetTexture(PH.MEDIA.panel_bg)
    PH.ApplySlice(ebg, 16, 16, 16, 16)
    PH.Color(ebg, PAL.bgTop)
    local ecrystal = PH.CreateIcon(empty, "icon_prey", nil, "OVERLAY")
    ecrystal:SetSize(72, 72)
    ecrystal:SetPoint("CENTER", empty, "CENTER", 0, 64)
    local etitle = FS(empty, 18, nil, "OVERLAY")
    etitle:SetPoint("TOP", ecrystal, "BOTTOM", 0, -16)
    etitle:SetText("No hunts recorded yet")
    etitle:SetTextColor(PAL.violet[1], PAL.violet[2], PAL.violet[3])
    local ebody = FS(empty, 12, nil, "OVERLAY")
    ebody:SetPoint("TOP", etitle, "BOTTOM", 0, -12)
    ebody:SetWidth(360)
    ebody:SetJustifyH("CENTER")
    ebody:SetTextColor(PAL.textDim[1], PAL.textDim[2], PAL.textDim[3])
    ebody:SetText("Open the Prey Hunt map at least once to scan your available hunts."
        .. "\n\nThey'll appear here automatically next time you check.")
    empty:Hide()
    board.emptyOverlay = empty

    PH.huntBoard = board
    return board
end

-- ---------------------------------------------------------------------------
-- Live data wiring (Phase 3). Everything below maps the existing pipeline
-- (PH.liveHunts / PH.rewardCache / PH.IsInProgress / widget 7663 / currency
-- 3392) onto the 4×3 grid built above. No new scraping happens here.
-- ---------------------------------------------------------------------------

-- Red Anguish chip in the header, formatted with thousands separators.
function PH.UpdateBoardAnguish()
    local board = PH.huntBoard
    if board and board.anguishChip then
        board.anguishChip.text:SetText(BreakUpLargeNumbers(PH.GetAnguishCurrency()))
    end
end

-- Footer achievement readout (name label, "x/y", violet fill) from the resolved
-- "Prey: Nightmare Mode III" (Achievements.lua). Safe before the data resolves —
-- shows the target name and 0/0 until criteria are available.
function PH.UpdateBoardAchievement()
    local board = PH.huntBoard
    if not (board and board.achBarFill) then return end
    local name, completed, total = PH.GetAchievementSummary()
    board.achName:SetText(name:upper())
    board.achBarText:SetText(string.format("%d/%d", completed, total))
    local frac = (total > 0) and (completed / total) or 0
    board.achBarFill:SetWidth(math.max(1, board.achBarW * frac))
    board.achBarFill:SetShown(frac > 0)
end

-- Lightweight refresh for achievement events (CRITERIA_UPDATE / ACHIEVEMENT_EARNED):
-- re-read criteria and repaint only the Nightmare chips + footer bar, without the
-- full SetData churn (model reloads etc.) of PopulateBoard.
function PH.RefreshBoardAchievements()
    local board = PH.huntBoard
    if not (board and board:IsShown()) then return end
    PH.RefreshAchievements()
    for _, card in pairs(PH.boardCards) do
        if card.chip and card.data then
            card.data.achieveDone = PH.HuntAchievementDone(card.data.name)
            card:Render()
        end
    end
    PH.UpdateBoardAchievement()
end

-- Rescan button — re-derive hunts from the live pins, re-resolve achievement
-- criteria, repaint immediately with whatever's cached, then warm any rewards we
-- don't have yet (repainting as they land). Mirrors the Core.lua map-open path
-- but keeps the board up instead of showing the loading overlay.
function PH.RescanBoard()
    local board = PH.huntBoard
    if not board then return end
    if board.rescanText then board.rescanText:SetText("Scanning…") end

    PH.RefreshFromPins()            -- re-scrape pins (stamps PH.lastScanTime)
    PH.RefreshAchievements(true)    -- force a fresh resolve + criteria read
    PH.PopulateBoard()              -- instant repaint from the current caches

    PH.WarmRewardCacheAsync(nil, function()
        if PH.huntBoard and PH.huntBoard:IsShown() then PH.PopulateBoard() end
        if board.rescanText then board.rescanText:SetText("Rescan") end
    end)
end

-- Card hover tooltip: name, difficulty, zone, status, rewards. Out of the map it
-- also spells out that accepting needs the live Prey map (the card shows the same
-- as a faint hint where Accept would be).
function PH.ShowCardTooltip(card)
    local d = card.data
    if not d then return end
    local dc = CFG.DIFF_COLOR[card.diff] or CFG.DIFF_COLOR.Normal
    local zc = PH.GetZoneColor(card.zone)
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(d.name, 1, 1, 1)
    GameTooltip:AddLine(card.diff, dc.r, dc.g, dc.b)
    GameTooltip:AddLine(card.zone or "Unknown", zc.r * 1.3, zc.g * 1.3, zc.b * 1.3)
    GameTooltip:AddLine(card.inProgress and "|cffffd700In Progress|r" or "|cff55ccffAvailable|r")
    local rewards = d.rewards or {}
    if #rewards > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Rewards:", 1, 0.82, 0)
        for _, r in ipairs(rewards) do
            GameTooltip:AddLine(r.count and (r.name .. " x" .. r.count) or r.name, 1, 1, 1)
        end
    end
    if PH.standalone and not card.inProgress then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Open the Prey map to accept this hunt.",
            PAL.textFaint[1], PAL.textFaint[2], PAL.textFaint[3])
    end
    GameTooltip:Show()
end

-- Selecting a card reveals its glowing Accept button; only one card across the
-- board is selected at a time. Clicking the selected card again deselects it.
function PH.SelectCard(card)
    if PH.selectedCard and PH.selectedCard ~= card then
        PH.selectedCard.selected = false
        PH.selectedCard:Render()
    end
    if card.selected then
        card.selected   = false
        PH.selectedCard = nil
    else
        card.selected   = true
        card.hovered    = false
        PH.selectedCard = card
    end
    card:Render()
end

-- Paint every cell from PH.liveHunts. The (difficulty, zone) invariant means at
-- most one hunt per cell; cells with no hunt render the empty state.
function PH.PopulateBoard()
    -- Remember the selected cell so a refresh (QUEST_LOG_UPDATE) doesn't drop it.
    local prevSelKey
    if PH.selectedCard then
        prevSelKey = PH.selectedCard.zone .. "|" .. PH.selectedCard.diff
    end
    PH.selectedCard = nil

    -- Re-read achievement criteria so the Nightmare chips + footer bar are current.
    PH.RefreshAchievements()

    -- Merged live + persisted view: live pins first, plus any in-progress hunt
    -- whose offer pin is gone, plus the out-of-map cache (PH.GetBoardHunts).
    local hunts = PH.GetBoardHunts()
    local byCell = {}
    for _, h in ipairs(hunts) do
        byCell[h.zone .. "|" .. h.difficulty] = h
    end

    -- Widget 7663 progress (0–3) drives the in-progress mini meter. Only one
    -- hunt is active at a time, so the value applies to whichever card is in
    -- progress. FRAGILE: widget id (see ARCHITECTURE.md §14).
    local progressState = 0
    local info = C_UIWidgetManager
        and C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(PREY_WIDGET_ID)
    if info then progressState = info.progressState or 0 end

    local inProgress, available = 0, 0
    for key, card in pairs(PH.boardCards) do
        local h = byCell[key]
        if not h then
            card:SetData(nil)
        else
            local prog = PH.IsInProgress(h.questID)
            card:SetData({
                name        = h.name,
                questID     = h.questID,
                rewards     = PH.RewardsFor(h.questID),
                inProgress  = prog,
                progress    = progressState,
                achieveDone = PH.HuntAchievementDone(h.name),
            })
            if prog then inProgress = inProgress + 1 else available = available + 1 end
        end
    end

    -- Restore selection if that cell still holds an available hunt.
    if prevSelKey then
        local card = PH.boardCards[prevSelKey]
        if card and card.data and not card.inProgress then
            card.selected   = true
            PH.selectedCard = card
            card:Render()
        end
    end

    local board = PH.huntBoard
    if board and board.footerCounts then
        board.footerCounts:SetText(string.format(
            "|cffffd24d%d|r In Progress  |cff565b6c·|r  |cff55ccff%d|r Available",
            inProgress, available))
        if board.scanAge then board.scanAge:SetText(FormatAge(PH.lastScanTime)) end
    end
    if board and board.emptyOverlay then
        board.emptyOverlay:SetShown(PH.standalone and #hunts == 0)
    end
    PH.UpdateBoardAnguish()
    PH.UpdateBoardAchievement()

    -- Persist this view so out-of-map opens and a post-accept map reopen can
    -- render without live pins.
    PH.SaveCache()
end

-- Make the board cover CovenantMissionFrame exactly (both corners), so its
-- background matches the map behind it, then uniformly scale the fixed-size
-- content frame to fit inside — cards keep their designed proportions at any map
-- size. Standalone (/prey board) has no map, so the board itself is scaled to
-- the screen. FRAGILE: CovenantMissionFrame reference.
local function AnchorBoardToMap(board)
    board:ClearAllPoints()
    board:SetScale(1)
    if CovenantMissionFrame and CovenantMissionFrame:IsShown() then
        board.dockedToMap = true
        board:SetPoint("TOPLEFT",     CovenantMissionFrame, "TOPLEFT")
        board:SetPoint("BOTTOMRIGHT", CovenantMissionFrame, "BOTTOMRIGHT")
        local bw, bh = board:GetWidth(), board:GetHeight()
        if not (bw and bw > 0) then bw, bh = CovenantMissionFrame:GetSize() end
        if bw and bw > 0 and bh and bh > 0 then
            board.content:SetScale(math.min(bw / WIN_W, bh / WIN_H))
        end
    else
        board.dockedToMap = false
        board:SetSize(WIN_W, WIN_H)
        board.content:SetScale(1)
        board:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        board:SetScale(math.min(1,
            (UIParent:GetWidth() * 0.98) / WIN_W,
            (UIParent:GetHeight() * 0.96) / WIN_H))
    end
end

-- Show/hide the map-only minimize button and re-anchor the Anguish chip to sit
-- left of whatever control is rightmost in the current mode.
function PH.UpdateBoardChrome()
    local board = PH.huntBoard
    if not board then return end
    local mapMode = board.dockedToMap and true or false
    board.minBtn:SetShown(mapMode)
    board.anguishChip:ClearAllPoints()
    if mapMode then
        board.anguishChip:SetPoint("RIGHT", board.minBtn, "LEFT", -8, 0)
    else
        board.anguishChip:SetPoint("RIGHT", board.closeBtn, "LEFT", -8, 0)
    end
end

-- ---------------------------------------------------------------------------
-- Restore chip — the crystal on a dark red-glowing pill, pinned to the map's
-- top-right while the board is minimized. Clicking it restores the board.
-- FRAGILE: CovenantMissionFrame reference (anchor only).
-- ---------------------------------------------------------------------------
local function BuildBoardChip()
    if PH.boardChip then return PH.boardChip end
    local chip = PH.CreateCard(UIParent, { 0.07, 0.05, 0.06 }, PAL.anguishRed)
    chip:SetSize(40, 40)
    chip:SetFrameStrata("DIALOG")
    chip:SetFrameLevel(230)
    chip:EnableMouse(true)

    local glow = PH.CreateGlow(chip, "radial", "BACKGROUND", -1)
    glow:SetPoint("TOPLEFT", -10, 10)
    glow:SetPoint("BOTTOMRIGHT", 10, -10)
    PH.Color(glow, PAL.anguishRed, 0.7)

    -- The prey crystal (pre-colored — not vertex-tinted).
    local crystal = PH.CreateIcon(chip, "icon_prey", nil, "OVERLAY")
    crystal:SetSize(30, 30)
    crystal:SetPoint("CENTER")

    chip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PreyTracker", PAL.violet[1], PAL.violet[2], PAL.violet[3])
        GameTooltip:AddLine("Click to restore the Hunt Board", 0.7, 0.7, 0.75)
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    chip:SetScript("OnMouseUp", function()
        if PreyTrackerDB then PreyTrackerDB.boardMinimized = false end
        PH.HideBoardChip()
        PH.ShowBoard()
    end)

    chip:Hide()
    PH.boardChip = chip
    return chip
end

function PH.ShowBoardChip()
    if not (CovenantMissionFrame and CovenantMissionFrame:IsShown()) then return end
    local chip = BuildBoardChip()
    chip:ClearAllPoints()
    chip:SetPoint("TOPRIGHT", CovenantMissionFrame, "TOPRIGHT", -12, -12)
    chip:Show()
end

function PH.HideBoardChip()
    if PH.boardChip then PH.boardChip:Hide() end
end

-- Minimize (map mode only): hide the overlay to reveal Blizzard's map, drop the
-- restore chip on it, and remember the choice for this session (PreyTrackerDB).
function PH.MinimizeBoard()
    if not PreyTrackerDB then PreyTrackerDB = {} end
    PreyTrackerDB.boardMinimized = true
    PH.selectedCard = nil
    if PH.huntBoard then PH.huntBoard:Hide() end
    PH.ShowBoardChip()
end

-- Main screen everywhere: over the map (Core.lua, after warming) and centered on
-- screen (PH.OpenBoardStandalone). Respects a minimized choice while over the map
-- by showing the restore chip instead of the board.
function PH.ShowBoard()
    PH.HideLoadingFrame()
    local board = PH.BuildHuntBoard()
    AnchorBoardToMap(board)
    PH.UpdateBoardChrome()
    if board.dockedToMap and PreyTrackerDB and PreyTrackerDB.boardMinimized then
        board:Hide()
        PH.ShowBoardChip()
        return
    end
    PH.HideBoardChip()
    board:Show()
    PH.PopulateBoard()   -- after Show so card PlayerModels render on first open
end

-- /prey and the minimap button: the Hunt Board centered on screen, rendered from
-- the cached hunts/rewards. Toggles. If the map happens to be open it behaves as
-- the live map-mode board; otherwise it's read-only (faint "open the map" hint).
function PH.OpenBoardStandalone()
    local board = PH.BuildHuntBoard()
    if board:IsShown() then
        PH.HideBoard()
        return
    end
    -- An explicit open un-minimizes (otherwise ShowBoard would just re-show the
    -- restore chip while a hunt's map is open).
    if PreyTrackerDB then PreyTrackerDB.boardMinimized = false end
    PH.standalone = not (CovenantMissionFrame and CovenantMissionFrame:IsShown())
    PH.ShowBoard()
end

-- Live update of the in-progress card's mini meter from widget 7663
-- (UPDATE_UI_WIDGET), without the full PopulateBoard churn.
function PH.UpdateBoardProgress()
    local board = PH.huntBoard
    if not (board and board:IsShown()) then return end
    local prog = 0
    local info = C_UIWidgetManager
        and C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(PREY_WIDGET_ID)
    if info then prog = info.progressState or 0 end
    for _, card in pairs(PH.boardCards) do
        if card.inProgress and card.data then
            card.data.progress = prog
            for i, seg in ipairs(card.meterSegs) do
                if i <= prog then
                    seg:SetVertexColor(PAL.gold[1], PAL.gold[2], PAL.gold[3], 1)
                else
                    seg:SetVertexColor(0.10, 0.10, 0.14, 1)
                end
            end
        end
    end
end

-- Hide the board (map close, /prey hide, close button, watchdog). Also hides the
-- restore chip so the minimized state can't linger past a board-hide. Safe anytime.
function PH.HideBoard()
    PH.selectedCard = nil
    PH.HideBoardChip()
    if PH.huntBoard and PH.huntBoard:IsShown() then
        PH.huntBoard:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- /prey model — capture the current target's creature displayID and print a
-- paste-ready PH.HUNT_MODELS line (Config.lua). The map pins carry no displayID,
-- so this is how the hardcoded model table gets filled: target a lured-out prey
-- in the world, run /prey model, paste the printed line keyed by the hunt name.
-- ---------------------------------------------------------------------------
function PH.CaptureModel()
    if not UnitExists("target") then
        print("|cffcc44ccPreyTracker|r /prey model: target a creature first.")
        return
    end
    local name = UnitName("target") or "?"

    -- Read the displayID off a scratch PlayerModel set to the target. The model
    -- loads async, so poll GetDisplayInfo a few times before giving up.
    PH._scratchModel = PH._scratchModel or CreateFrame("PlayerModel")
    local m = PH._scratchModel
    m:ClearModel()
    m:SetUnit("target")

    local tries = 0
    local function report()
        tries = tries + 1
        local id = m.GetDisplayInfo and m:GetDisplayInfo()
        if id and id > 0 then
            print(string.format('|cffcc44ccPreyTracker|r model  ["%s"] = %d,', name, id))
            print("|cff888888  -> paste into PH.HUNT_MODELS in Config.lua, then /reload|r")
        elseif tries < 10 then
            C_Timer.After(0.1, report)
        else
            print("|cffcc44ccPreyTracker|r /prey model: couldn't read a displayID (try again).")
        end
    end
    report()
end

-- ---------------------------------------------------------------------------
-- /prey dumpdialog — DISCOVERY for the in-dialog model idea. Opens the first
-- prey's AdventureMapQuestChoiceDialog (the same modal the reward warmer drives)
-- and probes it for any Model/PlayerModel/ModelScene widget, printing each one's
-- displayID / modelFileID so we can wire automatic per-quest model capture into
-- the existing warm cycle. Remove once that's wired.
-- ---------------------------------------------------------------------------
-- Pull whatever model identity an object (Model widget or ModelScene actor)
-- exposes: a creature displayID is ideal, a raw modelFileID is the fallback.
local function ModelIdentity(o)
    local s = ""
    if o.GetDisplayInfo then
        local ok, id = pcall(o.GetDisplayInfo, o)
        if ok and id and id ~= 0 then s = s .. " displayID=" .. tostring(id) end
    end
    if o.GetModelFileID then
        local ok, fid = pcall(o.GetModelFileID, o)
        if ok and fid and fid ~= 0 then s = s .. " modelFileID=" .. tostring(fid) end
    end
    return s
end

-- Walk the actual frame-child tree (GetChildren), reporting any Model/ModelScene
-- frame and its identity. This catches dynamically-created widget frames that a
-- keyed-field scan misses.
local function WalkFrames(frame, path, depth, out, seen)
    if depth < 0 or not frame or seen[frame] then return end
    seen[frame] = true
    local okT, ot = pcall(frame.GetObjectType, frame)
    ot = okT and ot or nil
    if ot == "ModelScene" then
        local n = (frame.GetNumActors and frame:GetNumActors()) or 0
        out[#out + 1] = string.format("%s <ModelScene> numActors=%d", path, n)
        if frame.GetActorAtIndex then
            for i = 1, n do
                local a = frame:GetActorAtIndex(i)
                if a then out[#out + 1] = string.format("    actor %d:%s", i, ModelIdentity(a)) end
            end
        end
    elseif ot == "Model" or ot == "PlayerModel" or ot == "CinematicModel"
        or ot == "DressUpModel" then
        out[#out + 1] = string.format("%s <%s>%s", path, tostring(ot), ModelIdentity(frame))
    end
    if frame.GetChildren then
        local kids = { frame:GetChildren() }
        for i = 1, #kids do
            local child = kids[i]
            local nm = (child.GetName and child:GetName()) or ("#" .. i)
            WalkFrames(child, path .. "/" .. nm, depth - 1, out, seen)
        end
    end
end

function PH.DumpDialog()
    local dialog = AdventureMapQuestChoiceDialog
    if not (dialog and dialog.ShowWithQuest) then
        print("|cffcc44ccPreyTracker|r dumpdialog: no quest dialog (open the Prey map first).")
        return
    end
    local pool = CovenantMissionFrame and CovenantMissionFrame.MapTab
        and CovenantMissionFrame.MapTab.pinPools
        and CovenantMissionFrame.MapTab.pinPools["AdventureMap_QuestOfferPinTemplate"]
    local pin
    if pool then for p in pool:EnumerateActive() do pin = p; break end end
    if not pin then
        print("|cffcc44ccPreyTracker|r dumpdialog: no pins on the map.")
        return
    end

    -- Mimic the reward warmer EXACTLY: invisible ShowWithQuest (alpha 0). The
    -- question is whether QuestModelScene's actors + modelFileIDs populate this
    -- way (→ the warmer can capture models silently) or whether the model only
    -- loads on the visible click path. Wait long enough for both actors to load.
    local prevAlpha = dialog:GetAlpha()
    dialog:SetAlpha(0)
    dialog:Hide()
    dialog:ShowWithQuest(CovenantMissionFrame, pin, pin.questID)

    C_Timer.After(2.5, function()
        local out = {}
        WalkFrames(dialog, "dialog", 8, out, {})
        print(string.format("|cffcc44ccPT-dlg|r [ShowWithQuest a0] questID=%s title=%s",
            tostring(pin.questID), tostring(pin.title)))
        if #out == 0 then
            print("|cffcc44ccPT-dlg|r no Model/ModelScene frames found.")
        else
            for _, line in ipairs(out) do print("|cffcc44ccPT-dlg|r " .. line) end
        end
        dialog:Hide()
        dialog:SetAlpha(prevAlpha)
    end)
end

-- ---------------------------------------------------------------------------
-- /prey board — toggle the live board standalone, scaled to fit the screen.
-- ---------------------------------------------------------------------------
function PH.ToggleHuntBoard()
    local board = PH.BuildHuntBoard()
    if board:IsShown() then
        PH.HideBoard()
        return
    end
    AnchorBoardToMap(board)
    PH.UpdateBoardChrome()
    PH.HideBoardChip()
    board:Show()
    PH.PopulateBoard()   -- after Show so card PlayerModels render
end
