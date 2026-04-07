-- PreyTracker — Config.lua
local PH = PreyTracker

PH.CFG = {
    PANEL_WIDTH            = 290,
    PANEL_WIDTH_STANDALONE = 380,
    PANEL_HEIGHT           = 560,
    ROW_HEIGHT             = 92,
    ROW_PADDING            = 2,
    X_OFFSET               = 8,
    ICON_SIZE              = 22,

    DIFF_COLOR = {
        Normal    = { r = 0.25, g = 0.85, b = 0.30 },
        Hard      = { r = 1.00, g = 0.65, b = 0.00 },
        Nightmare = { r = 0.95, g = 0.20, b = 0.20 },
        All       = { r = 0.40, g = 0.55, b = 0.80 },
    },

    ZONE_COLOR = {
        ["Eversong Woods"] = { r = 0.75, g = 0.28, b = 0.18 },
        ["Zul'Aman"]       = { r = 0.18, g = 0.58, b = 0.22 },
        ["Harandar"]       = { r = 0.18, g = 0.50, b = 0.82 },
        ["Voidstorm"]      = { r = 0.52, g = 0.10, b = 0.72 },
        DEFAULT            = { r = 0.25, g = 0.25, b = 0.30 },
    },

    ANGUISH_CURRENCY_ID = 3392,
}

PH.DIFF_ORDER = { Nightmare = 1, Hard = 2, Normal = 3 }
PH.ZONE_ORDER = { ["Eversong Woods"] = 1, ["Zul'Aman"] = 2, Harandar = 3, Voidstorm = 4 }

PH.REWARD_ICONS = {
    { match = "Hero Dawncrest",             icon = "Interface\\Icons\\inv_120_crest_hero"              },
    { match = "Champion Dawncrest",         icon = "Interface\\Icons\\inv_120_crest_champion"          },
    { match = "Veteran Dawncrest",          icon = "Interface\\Icons\\inv_120_crest_veteran"           },
    { match = "Adventurer Dawncrest",       icon = "Interface\\Icons\\inv_120_crest_adventurer"        },
    { match = "Champion Chest",             icon = "Interface\\Icons\\inv_misc_treasurechest04d"       },
    { match = "Veteran Chest",              icon = "Interface\\Icons\\inv_misc_treasurechest04d"       },
    { match = "Adventurer Chest",           icon = "Interface\\Icons\\inv_misc_treasurechest04a"       },
    { match = "Aspiring Preyseeker's Chest",icon = "Interface\\Icons\\inv_misc_treasurechest04a"      },
    { match = "Champion Sack",              icon = "Interface\\Icons\\inv_misc_bag_10_red"             },
    { match = "Veteran Sack",               icon = "Interface\\Icons\\inv_misc_bag_10_red"             },
    { match = "Adventurer Sack",            icon = "Interface\\Icons\\inv_misc_bag_10_red"             },
    { match = "Coffer Key Shard",           icon = "Interface\\Icons\\inv_gizmo_hardenedadamantitetube"},
    { match = "Preyseeker's Journey",       icon = "Interface\\Icons\\ui_prey"                         },
    { match = "Player Experience",          icon = "Interface\\Icons\\xp_icon"                         },
}

PH.FALLBACK_ICON = "Interface\\Icons\\inv_misc_questionmark"