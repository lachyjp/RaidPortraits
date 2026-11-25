-- Health bar styling: colour, gradient, texture and background for the game's
-- own raid-style party/raid health bars, and the designer preview's bars.
--
-- Only widget methods are called on Blizzard's bars (never their Lua fields),
-- which doesn't taint them. RaidPortraits.lua decides which frames to style
-- and when (after the game's own colour/health updates).

local _, NS = ...
local Secret = NS.Secret

local TEXTURES = {
    flat = "Interface\\Buttons\\WHITE8X8",
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    skills = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}
NS.HEALTH_TEXTURES = TEXTURES
NS.GAME_HEALTH_TEXTURE = TEXTURES.raid

-- Fill colour for a player at `pct` health (0-1).
function NS.HealthColor(info, pct)
    local db = NS.db
    if db.healthColorMode == "custom" then
        local c = db.healthColor
        return c[1], c[2], c[3]
    elseif db.healthColorMode == "health" then
        pct = math.max(0, math.min(1, pct or 1))
        if pct > 0.5 then return (1 - pct) * 2, 1, 0 end
        return 1, pct * 2, 0
    end
    local c = info.color
    return c.r, c.g, c.b
end

local function FadeColor(r, g, b)
    local db = NS.db
    local mode, k = db.healthGradientColorMode, db.healthGradientStrength
    if mode == "custom" then
        local c = db.healthGradientColor
        return c[1], c[2], c[3]
    elseif mode == "light" then
        return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
    end
    return r * (1 - k), g * (1 - k), b * (1 - k)
end

local function Gradient(tex, orient, r1, g1, b1, r2, g2, b2)
    if CreateColor and pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1)) then return end
    pcall(tex.SetGradient, tex, orient, r1, g1, b1, r2, g2, b2)   -- older signature
end

-- Paints a StatusBar: texture (unless "Game default"), colour and gradient.
function NS.PaintHealthBar(bar, r, g, b)
    local db = NS.db
    local file = TEXTURES[db.healthTexture]
    if file then bar:SetStatusBarTexture(file) end
    bar:SetStatusBarColor(r, g, b)
    local tex = bar:GetStatusBarTexture()
    if tex and db.healthGradient then
        local r2, g2, b2 = FadeColor(r, g, b)
        if db.healthGradientDir == "horizontal" then
            Gradient(tex, "HORIZONTAL", r, g, b, r2, g2, b2)          -- left = colour
        else
            Gradient(tex, "VERTICAL", r2, g2, b2, r, g, b)            -- bottom = fade, top = colour
        end
    end
end

-- Health fraction for a unit, or nil when the game hides it.
function NS.HealthPct(unit)
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if Secret(cur) or Secret(max) or not max or max <= 0 then return nil end
    return cur / max
end
