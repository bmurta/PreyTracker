-- PreyTracker — Config.lua
local PH = PreyTracker

PH.CFG = {
    PANEL_WIDTH            = 290,
    PANEL_WIDTH_STANDALONE = 380,
    PANEL_HEIGHT           = 560,
    ROW_HEIGHT             = 78,
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

-- Hunt Board card models, keyed by hunt/creature name (the map-pin title).
--
-- PH.HUNT_CREATURES: NPC/creature id → rendered with PlayerModel:SetCreature
-- (textured + auto-framed). Source: the creature's Wowhead page (the id is in the
-- npc=<id> URL). This is the primary table; a name with no entry shows the flat
-- silhouette. Names match the pin title exactly (mind the commas).
PH.HUNT_CREATURES = {
    ["Grothoz, the Burning Shadow"]  = 246985,
    ["Petyoll the Razorleaf"]        = 246953,
    ["Dengzag, the Darkened Blaze"]  = 246988,
    ["Consul Nebulor"]               = 246510,
    ["Imperator Enigmalia"]          = 246969,
    ["Neydra the Starving"]          = 253918,
    ["Ranger Swiftglade"]            = 253905,
    ["Magister Sunbreaker"]          = 253562,
    ["Phaseblade Talasha"]           = 247340,
    ["The Talon of Jan'alai"]        = 253903,
    ["Praetor Singularis"]           = 246509,
    ["Magistrix Emberlash"]          = 246925,
    ["Zadu, Fist of Nalorakk"]       = 253902,
    ["The Wing of Akil'zon"]         = 246946,
    ["Senior Tinker Ozwold"]         = 246928,
    ["Mordril Shadowfell"]           = 246932,
    ["Jo'zolo the Breaker"]          = 246499,
    ["High Vindicator Vureem"]       = 253909,
    ["Executor Kaenius"]             = 253913,
    ["Knight-Errant Bloodshatter"]   = 253915,
    ["Lost Theldrin"]                = 253917,
    ["Thornspeaker Edgath"]          = 253919,
    ["Deliah Gloomsong"]             = 253898,
    ["Nexus-Edge Hadim"]             = 246939,
    ["Lieutenant Blazewing"]         = 246950,
    ["Lamyne of the Undercroft"]     = 253908,
    ["Crusader Luxia Maxwell"]       = 246958,
    ["Vylenna the Defector"]         = 253916,
    ["Thorn-Witch Liset"]            = 253920,
    ["L-N-0R the Recycler"]          = 247337,
}

-- Optional displayID override (wins over HUNT_CREATURES) via SetDisplayInfo,
-- filled by /prey model while targeting a lured-out prey.
PH.HUNT_MODELS = {
    -- ["Grothoz, the Burning Shadow"] = 0,
}