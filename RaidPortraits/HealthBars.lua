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

------------------------------------------------------------------------
-- Health numbers on the game's party / raid frames
------------------------------------------------------------------------
-- Our own font string on a small frame of ours over the health bar (kept in a
-- table here, never as a field on Blizzard's frame). In combat the game can
-- hand out secret health values: those go straight to the font string's
-- SetFormattedText, which accepts them, so the numbers keep updating.


local texts = setmetatable({}, { __mode = "k" })

local function Short(n)
    if n >= 1e6 then return (("%.1fm"):format(n / 1e6):gsub("%.0m", "m")) end
    if n >= 1e4 then return ("%dk"):format(math.floor(n / 1e3 + 0.5)) end
    if n >= 1e3 then return (("%.1fk"):format(n / 1e3):gsub("%.0k", "k")) end
    return tostring(math.floor(n + 0.5))
end
NS.ShortNumber = Short

-- Writes unit's health into font string fs in the chosen style. Returns false
-- when there is nothing to show (style off, or "hide at full" and full).
function NS.WriteHealthText(fs, unit, style, hideFull)
    if not style or style == "none" or not unit then return false end
    local dead, online = UnitIsDeadOrGhost(unit), UnitIsConnected(unit)
    if not Secret(online) and not online then fs:SetText(PLAYER_OFFLINE or "Offline") return true end
    if not Secret(dead) and dead then
        local ghost = UnitIsGhost(unit)
        fs:SetText((not Secret(ghost) and ghost) and "Ghost" or (DEAD or "Dead"))
        return true
    end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if Secret(cur) or Secret(max) then
        -- Can't do arithmetic on secrets: show what the game lets us.
        if style == "percent" or style == "shortpct" then
            if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
                local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
                if ok and pcall(fs.SetFormattedText, fs, "%.0f%%", pct) then return true end
            end
        elseif style == "deficit" and UnitHealthMissing then
            local ok, miss = pcall(UnitHealthMissing, unit)
            if ok and pcall(fs.SetFormattedText, fs, "-%s", miss) then return true end
        end
        if style == "current" then
            if pcall(fs.SetFormattedText, fs, "%s", cur) then return true end
        elseif pcall(fs.SetFormattedText, fs, "%s / %s", cur, max) then
            return true
        end
        return false
    end
    if not max or max <= 0 then return false end
    if hideFull and cur >= max then return false end
    local pct = math.floor(cur / max * 100 + 0.5)
    if style == "full" then fs:SetFormattedText("%d / %d", cur, max)
    elseif style == "short" then fs:SetText(Short(cur) .. " / " .. Short(max))
    elseif style == "percent" then fs:SetFormattedText("%d%%", pct)
    elseif style == "shortpct" then fs:SetText(Short(cur) .. " | " .. pct .. "%")
    elseif style == "current" then fs:SetText(Short(cur))
    elseif style == "deficit" then
        if cur >= max then return false end
        fs:SetText("-" .. Short(max - cur))
    else return false end
    return true
end

local POINTS = { center = "CENTER", left = "LEFT", right = "RIGHT", bottom = "BOTTOM", top = "TOP" }

-- Shows / updates the health number on one compact frame.
function NS.UpdateHealthText(frame, unit, wanted)
    local db = NS.db
    local style = (db.enabled and wanted) and db.healthText or "none"
    local t = texts[frame]
    -- The game's own status text (its "Display Health Text" option): fade it
    -- while ours shows, so the two don't overlap. Alpha only, never Hide.
    local st = rawget(frame, "statusText")
    if type(st) == "table" and st.SetAlpha then st:SetAlpha(style ~= "none" and 0 or 1) end
    if style == "none" or not unit then
        if t then t.box:Hide() end
        return
    end
    local bar = frame.healthBar
    if not bar then return end
    if not t then
        local box = CreateFrame("Frame", nil, frame)
        box:SetAllPoints(bar)
        local fs = box:CreateFontString(nil, "OVERLAY")
        t = { box = box, fs = fs }
        texts[frame] = t
    end
    t.box:SetFrameLevel(bar:GetFrameLevel() + 5)
    local p = POINTS[db.healthTextPos] or "CENTER"
    local x = (p == "LEFT" and 3) or (p == "RIGHT" and -3) or 0
    local y = (p == "BOTTOM" and 2) or (p == "TOP" and -2) or 0
    t.fs:ClearAllPoints()
    t.fs:SetPoint(p, t.box, p, x, y)
    t.fs:SetFont(STANDARD_TEXT_FONT, db.healthTextSize or 10, db.healthTextOutline and "OUTLINE" or "")
    t.fs:SetShadowOffset(db.healthTextOutline and 0 or 1, db.healthTextOutline and 0 or -1)
    local c = db.healthTextColor or { 1, 1, 1 }
    t.fs:SetTextColor(c[1], c[2], c[3])
    local ok, show = pcall(NS.WriteHealthText, t.fs, unit, style, db.healthTextHideFull)
    t.box:SetShown(ok and show or false)
end
