-- Every RaidPortraits setting, in display order. The designer window builds its
-- controls from this list, and defaults come from here, so adding a field here
-- is the whole change.
--
-- type: toggle | range | choice | color
-- parent:    greyed out in the designer while this other toggle is off
-- parentOff: greyed out while this other toggle is on
-- cond:      function(db) -> greyed out while it returns false

local _, NS = ...

local COLOR_MODES = {
    { "class", "Class colour" }, { "custom", "Custom colour" }, { "white", "White" }, { "black", "Black" },
}

local function Is3D(db) return db.portraitType == "3d" end
local function NotFill(db) return db.position ~= "fill" end
local OUTSIDE = { left = true, right = true, top = true, bottom = true }
local function Outside(db) return OUTSIDE[db.position] or false end
local function IsColumn(db) return Outside(db) and db.arrange == "column" end
NS.OUTSIDE = OUTSIDE

NS.SECTIONS = {
    { key = "general", label = "General", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { key = "portrait", label = "Portrait", icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
    { key = "model", label = "3D model", icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
    { key = "place", label = "Size & position", icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "border", label = "Shape & border", icon = "Interface\\Icons\\INV_Shield_06" },
    { key = "health", label = "Health bar", icon = "Interface\\Icons\\INV_Potion_51" },
    { key = "power", label = "Resource bar", icon = "Interface\\Icons\\INV_Potion_76" },
    { key = "threat", label = "Threat", icon = "Interface\\Icons\\Ability_Warrior_Challange" },
    { key = "highlight", label = "Target highlight", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { key = "states", label = "Dead & offline", icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit" },
    { key = "looks", divider = true, label = "Saved looks", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "changes", label = "Changes", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
}

NS.FIELDS = {
    -- General
    { key = "enabled", section = "general", type = "toggle", label = "Enable RaidPortraits", default = true },
    { key = "showParty", section = "general", type = "toggle", label = "Show on raid-style party frames", default = true, parent = "enabled",
      tip = "Adds portraits to the party frames when Edit Mode's \"Use Raid-Style Party Frames\" is on." },
    { key = "showRaid", section = "general", type = "toggle", label = "Show on raid frames", default = false, parent = "enabled",
      tip = "Also adds portraits to the raid frames when you're in a raid. With 20+ players, 2D portraits or class icons are lighter than 3D models." },
    { key = "showPlayer", section = "general", type = "toggle", label = "Show on your own frame", default = true, parent = "enabled" },
    { key = "showOwnFrame", section = "general", type = "toggle", label = "Show your own party / raid frame", default = true, parent = "enabled",
      tip = "Off hides your own frame from the raid-style party frames and raid frames, and closes the gap it leaves. It's hidden out of combat (the game doesn't let add-ons hide these frames in combat), and made invisible if the game shows it again mid-fight. Raid frames only close the gap with Keep Groups Together on. Also /rpt me." },
    { key = "showPets", section = "general", type = "toggle", label = "Show on pet frames", default = false, parent = "enabled" },
    { key = "showGroupTitle", section = "general", type = "toggle", label = "Show the \"Party\" / \"Group\" label above the frames", default = false, parent = "enabled",
      tip = "The game's title above the raid-style party frames and each raid group. Off hides it (the small space it takes stays, as the game lays the frames out around it)." },
    { key = "hideInCombat", section = "general", type = "toggle", label = "Hide portraits in combat", default = false, parent = "enabled" },

    -- Portrait
    { key = "portraitType", section = "portrait", type = "choice", label = "Portrait", default = "3d",
      choices = { { "3d", "3D model" }, { "2d", "2D portrait" }, { "class", "Class icon" } },
      tip = "3D models animate like the classic party frames. They need the player to be nearby; further away the fallback below is shown." },
    { key = "fallback", section = "portrait", type = "choice", label = "When the 3D model can't load", default = "2d", cond = Is3D,
      choices = { { "2d", "2D portrait" }, { "class", "Class icon" } },
      tip = "The game only loads models for players close enough to see." },
    { key = "zoom", section = "portrait", type = "range", label = "Zoom (2D portrait and class icon)", default = 0.08, min = 0, max = 0.4, step = 0.01,
      tip = "Trims the edges so the face fills more of the portrait." },
    { key = "alpha", section = "portrait", type = "range", label = "Opacity", default = 1, min = 0.1, max = 1, step = 0.05 },
    { key = "background", section = "portrait", type = "toggle", label = "Dark background behind the portrait", default = true,
      tip = "3D models have a see-through background. This fills it." },
    { key = "backgroundColor", section = "portrait", type = "color", label = "Background colour", default = { 0, 0, 0 }, parent = "background" },
    { key = "backgroundAlpha", section = "portrait", type = "range", label = "Background opacity", default = 0.8, min = 0.05, max = 1, step = 0.05, parent = "background" },

    -- 3D model
    { key = "modelZoom", section = "model", type = "range", label = "Face zoom (0 = whole body, 1 = face)", default = 1, min = 0, max = 1, step = 0.05, cond = Is3D },
    { key = "modelDistance", section = "model", type = "range", label = "Camera distance", default = 1, min = 0.5, max = 3, step = 0.05, cond = Is3D },
    { key = "modelRotation", section = "model", type = "range", label = "Turn (degrees)", default = 0, min = -180, max = 180, step = 5, cond = Is3D },
    { key = "modelAnimate", section = "model", type = "toggle", label = "Animate (idle breathing and blinking)", default = true, cond = Is3D,
      tip = "Off freezes the model in place." },

    -- Size & position
    { key = "position", section = "place", type = "choice", label = "Position", default = "left",
      choices = { { "left", "Left" }, { "right", "Right" }, { "top", "Above" }, { "bottom", "Below" },
                  { "insideLeft", "Inside left" }, { "insideRight", "Inside right" }, { "fill", "Fill frame" } },
      tip = "Outside positions sit next to the frame. Inside positions sit on the health bar. Fill frame covers the whole frame, best with low opacity." },
    { key = "arrange", section = "place", type = "choice", label = "Arrangement (party frames)", default = "frame", cond = Outside,
      choices = { { "frame", "Beside each frame" }, { "column", "Own column / row" } },
      tip = "Beside each frame: every portrait lines up with its own frame. Own column / row: portraits form their own line next to the party frames, with their own spacing and alignment. Raid frames always use Beside each frame." },
    { key = "spacing", section = "place", type = "range", label = "Spacing between party members", default = 0, min = 0, max = 40, step = 1,
      tip = "Moves the game's raid-style party frames apart and spaces the portraits by the same amount, so each portrait stays lined up with its frame. The game only lets add-ons move these frames out of combat: if your group changes during a fight, the spacing comes back when combat ends." },
    { key = "align", section = "place", type = "choice", label = "Line up portraits from", default = "start", cond = IsColumn,
      choices = { { "start", "Top / left" }, { "center", "Centre" }, { "end", "Bottom / right" } },
      tip = "Where the line of portraits starts against the party frames. With fewer players or smaller portraits, the line stays pinned to this end." },
    { key = "matchSize", section = "place", type = "toggle", label = "Match the frame's size", default = true, cond = NotFill,
      tip = "Left, right and inside: as tall as the frame. Above and below: as wide as the frame." },
    { key = "size", section = "place", type = "range", label = "Size", default = 36, min = 12, max = 140, step = 1, parentOff = "matchSize", cond = NotFill },
    { key = "aspect", section = "place", type = "range", label = "Width / height (1 = square)", default = 1, min = 0.5, max = 3, step = 0.05, cond = NotFill },
    { key = "gap", section = "place", type = "range", label = "Gap from the frame edge", default = 2, min = 0, max = 30, step = 1 },
    { key = "offsetX", section = "place", type = "range", label = "Move left / right", default = 0, min = -80, max = 80, step = 1 },
    { key = "offsetY", section = "place", type = "range", label = "Move up / down", default = 0, min = -80, max = 80, step = 1 },
    { key = "layer", section = "place", type = "choice", label = "Layer (inside and fill positions)", default = "under",
      cond = function(db) return db.position == "fill" or db.position == "insideLeft" or db.position == "insideRight" end,
      choices = { { "under", "Under buffs & debuffs" }, { "over", "Over everything" } },
      tip = "Under keeps the frame's buffs, debuffs, dispel highlight and status icons on top of the portrait. Over puts the portrait above them." },

    -- Shape & border
    { key = "shape", section = "border", type = "choice", label = "Shape", default = "square",
      choices = { { "square", "Square" }, { "circle", "Round" } },
      tip = "3D models can't be clipped round by the game, so they always show square. Round works with 2D portraits and class icons." },
    { key = "border", section = "border", type = "range", label = "Border thickness", default = 1, min = 0, max = 8, step = 1 },
    { key = "borderColorMode", section = "border", type = "choice", label = "Border colour", default = "black", choices = COLOR_MODES },
    { key = "borderColor", section = "border", type = "color", label = "Custom border colour", default = { 1, 0.82, 0 } },
    { key = "borderAlpha", section = "border", type = "range", label = "Border opacity", default = 1, min = 0.1, max = 1, step = 0.05 },

    -- Health bar (the game's own frames)
    { key = "healthStyle", section = "health", type = "toggle", label = "Restyle the frames' health bars", default = false,
      tip = "Recolours the game's raid-style party (and raid, if on) health bars. Off leaves them exactly as the game draws them: green, or class colours with Raid Frame Settings > Display Class Colors. Dead and offline players keep the game's grey." },
    { key = "healthColorMode", section = "health", type = "choice", label = "Colour", default = "class", parent = "healthStyle",
      choices = { { "class", "Class colour" }, { "health", "By health (green > red)" }, { "custom", "Custom colour" } } },
    { key = "healthColor", section = "health", type = "color", label = "Custom colour", default = { 0.15, 0.75, 0.25 }, parent = "healthStyle" },
    { key = "healthTexture", section = "health", type = "choice", label = "Texture", default = "game", parent = "healthStyle",
      choices = { { "game", "Game default" }, { "flat", "Flat" }, { "smooth", "Smooth" }, { "raid", "Raid" }, { "skills", "Soft" } } },
    { key = "healthGradient", section = "health", type = "toggle", label = "Gradient", default = false, parent = "healthStyle" },
    { key = "healthGradientDir", section = "health", type = "choice", label = "Direction", default = "vertical", parent = "healthGradient",
      choices = { { "vertical", "Top to bottom" }, { "horizontal", "Left to right" } } },
    { key = "healthGradientColorMode", section = "health", type = "choice", label = "Fades to", default = "dark", parent = "healthGradient",
      choices = { { "dark", "Darker shade" }, { "light", "Lighter shade" }, { "custom", "Custom colour" } } },
    { key = "healthGradientColor", section = "health", type = "color", label = "Custom fade colour", default = { 0.05, 0.05, 0.1 }, parent = "healthGradient" },
    { key = "healthGradientStrength", section = "health", type = "range", label = "Strength", default = 0.5, min = 0.1, max = 1, step = 0.05, parent = "healthGradient",
      cond = function(db) return db.healthGradientColorMode ~= "custom" end },
    { key = "healthBg", section = "health", type = "toggle", label = "Recolour the missing-health background", default = false, parent = "healthStyle" },
    { key = "healthBgColor", section = "health", type = "color", label = "Background colour", default = { 0.08, 0.08, 0.08 }, parent = "healthBg" },
    { key = "healthBgAlpha", section = "health", type = "range", label = "Background opacity", default = 0.9, min = 0, max = 1, step = 0.05, parent = "healthBg" },

    -- Resource bar
    { key = "power", section = "power", type = "toggle", label = "Show a resource bar (mana, energy, rage...)", default = false,
      tip = "A small bar on each portrait showing the player's main resource. The game's own raid frames can also show power bars: Raid Frame Settings > Display Power Bars." },
    { key = "powerOnlyHealers", section = "power", type = "toggle", label = "Only for healers", default = false, parent = "power",
      tip = "Shows the bar only for players in the healer role." },
    { key = "powerPlace", section = "power", type = "choice", label = "Position", default = "inside", parent = "power",
      choices = { { "inside", "Bottom of the portrait" }, { "below", "Below the portrait" }, { "above", "Above the portrait" } } },
    { key = "powerHeight", section = "power", type = "range", label = "Height", default = 4, min = 2, max = 16, step = 1, parent = "power" },
    { key = "powerColorMode", section = "power", type = "choice", label = "Colour", default = "power", parent = "power",
      choices = { { "power", "Resource colour" }, { "class", "Class colour" }, { "custom", "Custom colour" } } },
    { key = "powerColor", section = "power", type = "color", label = "Custom colour", default = { 0.2, 0.5, 1 }, parent = "power" },
    { key = "powerBgAlpha", section = "power", type = "range", label = "Background darkness", default = 0.8, min = 0, max = 1, step = 0.05, parent = "power" },

    -- Threat
    { key = "threat", section = "threat", type = "toggle", label = "Show threat", default = false,
      tip = "Colours portraits with the game's threat colours: yellow when close to pulling aggro, orange when about to lose aggro, red when they have it. Works for you and every party or raid member with a portrait." },
    { key = "threatFrom", section = "threat", type = "choice", label = "Show from", default = "warn", parent = "threat",
      choices = { { "warn", "Close to pulling aggro" }, { "aggro", "Has aggro" } } },
    { key = "threatAgainst", section = "threat", type = "choice", label = "Threat against", default = "any", parent = "threat",
      choices = { { "any", "Any enemy" }, { "target", "Your target only" } } },
    { key = "threatStyle", section = "threat", type = "choice", label = "Style", default = "outline", parent = "threat",
      choices = { { "outline", "Outline" }, { "badge", "Corner badge" }, { "both", "Both" }, { "text", "Text only" } } },
    { key = "threatSize", section = "threat", type = "range", label = "Outline thickness", default = 2, min = 1, max = 8, step = 1, parent = "threat",
      cond = function(db) return db.threatStyle == "outline" or db.threatStyle == "both" end },
    { key = "threatBadgeSize", section = "threat", type = "range", label = "Badge size", default = 8, min = 4, max = 20, step = 1, parent = "threat",
      cond = function(db) return db.threatStyle == "badge" or db.threatStyle == "both" end },
    { key = "threatText", section = "threat", type = "toggle", label = "Show threat % against your target", default = false, parent = "threat",
      tip = "Each player's threat on your current target, where 100% means they have (or are about to pull) aggro." },
    { key = "threatHeldCount", section = "threat", type = "toggle", label = "Show mobs held (4/5)", default = false, parent = "threat",
      tip = "Counts enemies this player has aggro on out of the living enemies in combat with active nameplates. Enemies with secret threat status are skipped for that player." },
    { key = "threatHeldPercent", section = "threat", type = "toggle", label = "Show share of mobs held (80%)", default = false, parent = "threat",
      tip = "The percentage of counted enemies this player is holding. Combines with the count as 4/5 (80%)." },
    { key = "threatContested", section = "threat", type = "toggle", label = "Show mobs held at risk", default = false, parent = "threat",
      tip = "Shows how many of the mobs this player is holding have another unit high on threat (orange threat status)." },
    { key = "threatTextSize", section = "threat", type = "range", label = "Text size", default = 10, min = 6, max = 20, step = 1, parent = "threat",
      cond = function(db) return db.threatText or NS.ShowPackThreat(db) end },
    { key = "threatTextPos", section = "threat", type = "choice", label = "Text position", default = "top", parent = "threat",
      cond = function(db) return db.threatText or NS.ShowPackThreat(db) end,
      choices = { { "top", "Top" }, { "center", "Middle" }, { "bottom", "Bottom" } } },

    -- Target highlight
    { key = "targetHighlight", section = "highlight", type = "toggle", label = "Outline the portrait of your target", default = true },
    { key = "targetSize", section = "highlight", type = "range", label = "Outline thickness", default = 2, min = 1, max = 8, step = 1, parent = "targetHighlight" },
    { key = "targetColor", section = "highlight", type = "color", label = "Outline colour", default = { 1, 0.82, 0 }, parent = "targetHighlight" },

    -- Dead & offline
    { key = "deadStyle", section = "states", type = "choice", label = "Dead or offline players", default = "grey",
      choices = { { "none", "No change" }, { "grey", "Grey out" }, { "dark", "Darken" } },
      tip = "Grey out works on 2D portraits and class icons; 3D models are darkened instead." },
    { key = "deadDarkness", section = "states", type = "range", label = "Darkness", default = 0.6, min = 0.1, max = 0.95, step = 0.05,
      cond = function(db) return db.deadStyle ~= "none" end },
    { key = "rangeFade", section = "states", type = "toggle", label = "Fade with the frame when out of range", default = true,
      tip = "The game fades frames of party members who are out of range. Off keeps the portrait fully visible." },
}

function NS.ShowPackThreat(db)
    return db.threat and (db.threatHeldCount or db.threatHeldPercent or db.threatContested)
end

NS.FIELD = {}
NS.DEFAULTS = {}
for _, f in ipairs(NS.FIELDS) do
    NS.FIELD[f.key] = f
    NS.DEFAULTS[f.key] = f.default
end

-- Settings that make up a "look": everything except the General section.
function NS.IsLookKey(key)
    local f = NS.FIELD[key]
    return f and f.section ~= "general"
end

function NS.Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = NS.Copy(x) end
    return t
end

function NS.Same(a, b)
    if type(a) == "table" and type(b) == "table" then
        for i = 1, 3 do if math.abs((a[i] or 0) - (b[i] or 0)) > 0.002 then return false end end
        return true
    end
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
    return a == b
end

-- Built-in looks. Each starts from the defaults and changes only what's listed.
NS.PRESETS = {
    { name = "Classic", desc = "3D model left of each frame, like the old party frames.", values = {} },
    { name = "Round portraits", desc = "Round 2D portraits with a class-coloured ring.", values = {
        portraitType = "2d", shape = "circle", border = 2, borderColorMode = "class", gap = 4 } },
    { name = "Class icons", desc = "Class icons with a class-coloured border.", values = {
        portraitType = "class", border = 2, borderColorMode = "class", zoom = 0.1 } },
    { name = "Inside badge", desc = "Small round portrait on the left of the health bar.", values = {
        portraitType = "2d", position = "insideLeft", shape = "circle", gap = 3, border = 1 } },
    { name = "Ghost", desc = "Faint 3D model filling the whole frame.", values = {
        position = "fill", gap = 1, alpha = 0.35, background = false, border = 0, modelZoom = 0.9,
        targetHighlight = false } },
    { name = "Wide banner", desc = "Wide 3D portrait above each frame.", values = {
        position = "top", aspect = 2.5, modelZoom = 0.85, border = 1, borderColorMode = "class" } },
}
