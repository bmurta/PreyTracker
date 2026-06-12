-- PreyTracker — Widgets.lua
-- Phase 1 of the Hunt Board revamp (see HUNTBOARD_SPEC.md): texture-path
-- constants for everything in media/, the revamp palette, and the four factory
-- helpers the board is built from (CreateCard / CreatePill / CreateGlow /
-- CreateIcon). No layout or data here — just reusable chrome.
--
-- Load order (CLAUDE.md): this file runs right after Config.lua. It only adds to
-- the shared PH table; nothing here calls into later files at load time.
local PH = PreyTracker

-- ---------------------------------------------------------------------------
-- Texture paths
-- ---------------------------------------------------------------------------
-- Reference any texture as PH.MEDIA.<name> (no extension, per media/README.md).
-- CreateIcon also accepts a raw path, so Interface\Icons\* still works.
local BASE = "Interface\\AddOns\\PreyTracker\\media\\"

PH.MEDIA = {}
for _, name in ipairs({
    -- chrome (white, tintable)
    "panel_bg", "panel_border", "pill_bg", "pill_border", "glow_radial", "card_glow",
    -- model stage
    "zone_glow", "platform",
    -- creature silhouettes
    "sil_stag", "sil_cat", "sil_bat", "sil_void",
    -- icons
    "icon_prey", "icon_paw", "icon_trophy", "icon_check", "icon_gem", "icon_reload",
    "icon_close", "icon_dot", "icon_skull", "icon_target", "pin",
}) do
    PH.MEDIA[name] = BASE .. name
end

-- ---------------------------------------------------------------------------
-- Palette (HUNTBOARD_SPEC.md §Palette) — RGB 0–1, stored as {r, g, b} arrays
-- so they unpack straight into Set* calls.
-- ---------------------------------------------------------------------------
PH.PAL = {
    bgTop         = { 0.078, 0.086, 0.114 },  -- #14161d
    bgBottom      = { 0.051, 0.055, 0.075 },  -- #0d0e13
    cardSurface   = { 0.102, 0.114, 0.149 },  -- #1a1d26
    cardBorder    = { 0.137, 0.153, 0.200 },  -- #232733
    viewportBg    = { 0.047, 0.051, 0.075 },  -- #0c0d13
    text          = { 0.910, 0.914, 0.933 },  -- #e8e9ee
    textDim       = { 0.545, 0.561, 0.627 },  -- #8b8fa0
    textFaint     = { 0.337, 0.357, 0.424 },  -- #565b6c
    violet        = { 0.769, 0.302, 0.847 },  -- #c44dd8
    cyan          = { 0.333, 0.800, 1.000 },  -- #55ccff
    gold          = { 1.000, 0.824, 0.302 },  -- #ffd24d
    anguishRed    = { 1.000, 0.333, 0.333 },  -- #ff5555
    diffNormal    = { 0.290, 0.871, 0.361 },  -- #4ade5c
    diffHard      = { 1.000, 0.663, 0.157 },  -- #ffa928
    diffNightmare = { 0.949, 0.271, 0.271 },  -- #f24545
    silhouette    = { 0.020, 0.030, 0.040 },  -- near-black creature fill
    acceptTop     = { 0.208, 0.722, 0.329 },  -- #35b854 (accept gradient top)
    acceptBottom  = { 0.122, 0.541, 0.227 },  -- #1f8a3a (accept gradient bottom)
}

-- Difficulty / zone color lookups by name, returning a {r,g,b} array.
function PH.DiffColor(diff)
    return PH.PAL["diff" .. tostring(diff)] or PH.PAL.textDim
end

-- ---------------------------------------------------------------------------
-- Low-level helpers
-- ---------------------------------------------------------------------------
-- Tint a texture from a PH.PAL array (optionally with alpha).
function PH.Color(tex, c, a)
    tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end

local function ColorObj(c, a)
    return CreateColor(c[1], c[2], c[3], a or 1)
end

-- Apply nine-slice margins in the exact order media/README.md documents them.
local function ApplySlice(tex, a, b, c, d)
    tex:SetTextureSliceMargins(a, b, c, d)
    tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
end
PH.ApplySlice = ApplySlice

-- ---------------------------------------------------------------------------
-- Factory: CreateCard — rounded bg + border nine-slice pair (media/README.md).
-- Returns a Frame with .bg and .border textures so callers can re-tint per
-- state (difficulty, selection violet, in-progress gold).
-- ---------------------------------------------------------------------------
function PH.CreateCard(parent, surface, border)
    local f = CreateFrame("Frame", nil, parent)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(PH.MEDIA.panel_bg)
    ApplySlice(f.bg, 16, 16, 16, 16)
    PH.Color(f.bg, surface or PH.PAL.cardSurface)

    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetAllPoints()
    f.border:SetTexture(PH.MEDIA.panel_border)
    ApplySlice(f.border, 16, 16, 16, 16)
    PH.Color(f.border, border or PH.PAL.cardBorder)

    return f
end

-- ---------------------------------------------------------------------------
-- Factory: CreatePill — pill_bg + pill_border nine-slice pair, margins
-- (16,8,16,8). Returns a Frame with .bg, .border and a right-anchored .text
-- FontString; callers re-anchor .text and add a dot/icon as needed.
-- ---------------------------------------------------------------------------
function PH.CreatePill(parent, surface, border)
    local f = CreateFrame("Frame", nil, parent)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(PH.MEDIA.pill_bg)
    ApplySlice(f.bg, 16, 8, 16, 8)
    PH.Color(f.bg, surface or { 0.055, 0.062, 0.082 }, surface and 1 or 0.92)

    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetAllPoints()
    f.border:SetTexture(PH.MEDIA.pill_border)
    ApplySlice(f.border, 16, 8, 16, 8)
    PH.Color(f.border, border or PH.PAL.cardBorder)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("RIGHT", -8, 0)

    return f
end

-- ---------------------------------------------------------------------------
-- Factory: CreateGlow — soft additive glow texture.
--   variant "card"/"ring" → card_glow (sliced 32) for the selected-card ring.
--   anything else          → glow_radial for status-dot halos, eyes, hover.
-- Returns the texture (ADD blend already set); caller positions/tints it.
-- ---------------------------------------------------------------------------
function PH.CreateGlow(parent, variant, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    if variant == "card" or variant == "ring" then
        t:SetTexture(PH.MEDIA.card_glow)
        ApplySlice(t, 32, 32, 32, 32)
    else
        t:SetTexture(PH.MEDIA.glow_radial)
    end
    t:SetBlendMode("ADD")
    return t
end

-- ---------------------------------------------------------------------------
-- Factory: CreateIcon — a texture from a MEDIA key (or raw path). Pass a number
-- `size` for a square icon; leave nil and size it yourself for non-square art
-- (zone_glow, platform, silhouettes). Returns the texture.
-- ---------------------------------------------------------------------------
function PH.CreateIcon(parent, key, size, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    t:SetTexture(PH.MEDIA[key] or key)
    if size then t:SetSize(size, size) end
    return t
end

-- ---------------------------------------------------------------------------
-- Helper: CreateAcceptButton — green gradient button used on selected/hover
-- cards. Returns a Button with .bg, .border and .text. Not one of the four
-- core factories, but the board (and the test card) need it in one place.
-- ---------------------------------------------------------------------------
function PH.CreateAcceptButton(parent, label)
    local b = CreateFrame("Button", nil, parent)

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(PH.MEDIA.panel_bg)
    ApplySlice(b.bg, 16, 16, 16, 16)
    if b.bg.SetGradient then
        b.bg:SetGradient("VERTICAL", ColorObj(PH.PAL.acceptBottom), ColorObj(PH.PAL.acceptTop))
    else
        PH.Color(b.bg, PH.PAL.acceptTop)
    end

    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetAllPoints()
    b.border:SetTexture(PH.MEDIA.panel_border)
    ApplySlice(b.border, 16, 16, 16, 16)
    PH.Color(b.border, PH.PAL.acceptTop)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label or "Accept")
    b.text:SetTextColor(1, 1, 1)

    return b
end

-- ---------------------------------------------------------------------------
-- /prey test — spawn one sample card centered on screen so every texture can
-- be eyeballed in-game. Models the Voidstorm / Nightmare card from the mockup:
-- viewport, zone glow, platform, silhouette (+ glowing eyes), status pill,
-- achievement chip, reward icons, and the accept button. Toggles on re-run.
-- ---------------------------------------------------------------------------
function PH.SpawnTestCard()
    if PH.testCard then
        PH.testCard:SetShown(not PH.testCard:IsShown())
        return
    end

    local PAL  = PH.PAL
    local zone = PH.CFG.ZONE_COLOR["Voidstorm"]
    local zoneC = { zone.r, zone.g, zone.b }

    -- Outer card --------------------------------------------------------------
    local card = PH.CreateCard(UIParent)
    card:SetSize(300, 216)
    card:SetPoint("CENTER")
    card:SetFrameStrata("DIALOG")
    card:EnableMouse(true)
    card:SetMovable(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", card.StartMoving)
    card:SetScript("OnDragStop", card.StopMovingOrSizing)
    PH.testCard = card

    -- Selected-state violet glow ring behind the card.
    local ring = PH.CreateGlow(card, "card", "BACKGROUND", -1)
    ring:SetPoint("TOPLEFT", -10, 10)
    ring:SetPoint("BOTTOMRIGHT", 10, -10)
    PH.Color(ring, PAL.violet, 0.9)
    PH.Color(card.border, PAL.violet)  -- selected border

    -- Difficulty bar across the top (inset 12px each side).
    local diffBar = card:CreateTexture(nil, "ARTWORK")
    diffBar:SetTexture(PH.MEDIA.panel_bg)
    diffBar:SetPoint("TOPLEFT", 12, -7)
    diffBar:SetPoint("TOPRIGHT", -12, -7)
    diffBar:SetHeight(3)
    PH.Color(diffBar, PAL.diffNightmare)

    -- Model viewport ----------------------------------------------------------
    local vp = PH.CreateCard(card, PAL.viewportBg, PAL.cardBorder)
    vp:SetPoint("TOPLEFT", 4, -14)
    vp:SetPoint("TOPRIGHT", -4, -14)
    vp:SetHeight(120)

    local zoneGlow = PH.CreateIcon(vp, "zone_glow", nil, "BACKGROUND", 1)
    zoneGlow:SetPoint("CENTER", 0, -6)
    zoneGlow:SetSize(260, 120)
    zoneGlow:SetBlendMode("ADD")
    PH.Color(zoneGlow, zoneC, 0.40)

    local platform = PH.CreateIcon(vp, "platform", nil, "ARTWORK", 0)
    platform:SetPoint("BOTTOM", 0, 8)
    platform:SetSize(180, 46)
    PH.Color(platform, zoneC)

    local sil = PH.CreateIcon(vp, "sil_void", nil, "ARTWORK", 1)
    sil:SetPoint("BOTTOM", 0, 18)
    sil:SetSize(150, 96)
    PH.Color(sil, PAL.silhouette)

    -- Void creature eyes: two small violet additive dots.
    for _, dx in ipairs({ -9, 9 }) do
        local eye = PH.CreateGlow(vp, "radial", "OVERLAY")
        eye:SetSize(7, 7)
        eye:SetPoint("CENTER", sil, "CENTER", dx, 20)
        PH.Color(eye, PAL.violet)
    end

    -- Status pill (top-left of viewport): cyan dot + "Available".
    local pill = PH.CreatePill(vp)
    pill:SetSize(84, 20)
    pill:SetPoint("TOPLEFT", 6, -6)
    local pdot = PH.CreateIcon(pill, "icon_dot", 8, "OVERLAY")
    pdot:SetPoint("LEFT", 9, 0)
    PH.Color(pdot, PAL.cyan)
    pill.text:ClearAllPoints()
    pill.text:SetPoint("LEFT", pdot, "RIGHT", 4, 0)
    pill.text:SetText("Available")
    pill.text:SetTextColor(PAL.cyan[1], PAL.cyan[2], PAL.cyan[3])

    -- Achievement chip (top-right of viewport): trophy = still needed.
    local chip = PH.CreateCard(vp, { 0.07, 0.08, 0.11 }, PAL.cardBorder)
    chip:SetSize(22, 22)
    chip:SetPoint("TOPRIGHT", -6, -6)
    local trophy = PH.CreateIcon(chip, "icon_trophy", 14, "OVERLAY")
    trophy:SetPoint("CENTER")

    -- Name --------------------------------------------------------------------
    local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", vp, "BOTTOMLEFT", 6, -8)
    name:SetText("Voidmaw Devourer")
    name:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])

    -- Reward icons (bottom-left) ---------------------------------------------
    local sampleRewards = {
        "Interface\\Icons\\inv_120_crest_hero",
        "Interface\\Icons\\inv_misc_treasurechest04d",
        "Interface\\Icons\\ui_prey",
    }
    for i, path in ipairs(sampleRewards) do
        local ri = CreateFrame("Frame", nil, card)
        ri:SetSize(22, 22)
        ri:SetPoint("BOTTOMLEFT", 10 + (i - 1) * 25, 12)
        local tex = ri:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 2, -2)
        tex:SetPoint("BOTTOMRIGHT", -2, 2)
        tex:SetTexture(path)
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local rb = ri:CreateTexture(nil, "OVERLAY")
        rb:SetAllPoints()
        rb:SetTexture(PH.MEDIA.panel_border)
        ApplySlice(rb, 16, 16, 16, 16)
        PH.Color(rb, PAL.cardBorder)
    end

    -- Accept button (bottom-right) with a soft green glow behind it.
    local accept = PH.CreateAcceptButton(card, "Accept")
    accept:SetSize(72, 24)
    accept:SetPoint("BOTTOMRIGHT", -10, 11)
    local ag = PH.CreateGlow(accept, "radial", "BACKGROUND", -1)
    ag:SetPoint("TOPLEFT", -8, 8)
    ag:SetPoint("BOTTOMRIGHT", 8, -8)
    PH.Color(ag, PAL.acceptTop, 0.7)
    accept:SetScript("OnClick", function()
        print("|cffcc44ccPreyTracker|r test: Accept clicked.")
    end)

    print("|cffcc44ccPreyTracker|r test card spawned (drag to move; /prey test to toggle).")
end
