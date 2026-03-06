-- =============================================================================
--  PreyHub — Config.lua
--  All constants. Everything else reads from PH.CFG.
-- =============================================================================

local PH = _G.PreyHub

PH.CFG = {
    PANEL_WIDTH  = 280,
    PANEL_HEIGHT = 560,
    ROW_HEIGHT   = 80,
    ROW_PADDING  = 4,
    X_OFFSET     = 8,
    ICON_SIZE    = 22,

    DIFF_COLOR = {
        Normal    = { r = 0.20, g = 0.80, b = 0.20 },
        Hard      = { r = 1.00, g = 0.65, b = 0.00 },
        Nightmare = { r = 0.80, g = 0.00, b = 0.00 },
    },

    ZONE_COLOR = {
        ["Eversong Woods"] = { r = 0.80, g = 0.30, b = 0.20 },
        ["Zul'Aman"]       = { r = 0.20, g = 0.55, b = 0.20 },
        ["Harandar"]       = { r = 0.20, g = 0.55, b = 0.80 },
        ["Voidstorm"]      = { r = 0.50, g = 0.10, b = 0.70 },
        DEFAULT            = { r = 0.15, g = 0.15, b = 0.20 },
    },

    ANGUISH_CURRENCY_ID = 3392,
}

-- Sort priority tables (hoisted here so Data.lua and UI.lua can share them)
PH.DIFF_ORDER = { Nightmare = 1, Hard = 2, Normal = 3 }
PH.ZONE_ORDER = { ["Eversong Woods"] = 1, ["Zul'Aman"] = 2, Harandar = 3, Voidstorm = 4 }

-- Reward icon mapping — matched in order, first hit wins.
-- Unknown rewards fall back to the question-mark icon.
PH.REWARD_ICONS = {
    { match = "Champion Dawncrest",   icon = "Interface\\Icons\\inv_120_crest_champion"    },
    { match = "Veteran Dawncrest",    icon = "Interface\\Icons\\inv_120_crest_veteran"     },
    { match = "Adventurer Dawncrest", icon = "Interface\\Icons\\inv_120_crest_adventurer"  },
    { match = "Champion Chest",       icon = "Interface\\Icons\\inv_misc_treasurechest04d" },
    { match = "Veteran Chest",        icon = "Interface\\Icons\\inv_misc_treasurechest04d" },
    { match = "Adventurer Chest",     icon = "Interface\\Icons\\inv_misc_treasurechest04a" },
    { match = "Champion Sack",        icon = "Interface\\Icons\\inv_misc_bag_10_red"       },
    { match = "Veteran Sack",         icon = "Interface\\Icons\\inv_misc_bag_10_red"       },
    { match = "Adventurer Sack",      icon = "Interface\\Icons\\inv_misc_bag_10_red"       },
    { match = "Preyseeker's Journey", icon = "Interface\\Icons\\ui_prey"                   },
}

PH.FALLBACK_ICON = "Interface\\Icons\\inv_misc_questionmark"