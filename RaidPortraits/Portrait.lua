-- Draws one portrait next to (or on) a unit frame. Used for the real raid-style
-- party/raid frames and for the designer's preview, so both always match.
--
-- Layers, bottom to top, each its own child frame so levels are predictable:
--   ring   target highlight
--   body   border, background, 2D portrait / class icon
--   model  3D model
--   top    dead/offline darkening

local ADDON, NS = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = MEDIA .. "Circle"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end
NS.Secret = Secret

------------------------------------------------------------------------
-- Colours and unit info
------------------------------------------------------------------------

local FALLBACK = { r = 1, g = 0.82, b = 0 }
local WHITE_C, BLACK_C = { r = 1, g = 1, b = 1 }, { r = 0, g = 0, b = 0 }

function NS.ClassColor(class)
    if class and not Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        return RAID_CLASS_COLORS[class]
    end
    return FALLBACK
end

-- Resolves a colour-mode setting ("class", "custom", "white", "black").
function NS.Color(mode, customKey, info)
    if mode == "class" then return info.color or FALLBACK end
    if mode == "white" then return WHITE_C end
    if mode == "black" then return BLACK_C end
    local c = NS.db[customKey] or { 1, 1, 1 }
    return { r = c[1], g = c[2], b = c[3] }
end

function NS.UnitInfo(unit)
    local _, class = UnitClass(unit)
    if Secret(class) then class = nil end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if Secret(role) then role = nil end
    return { unit = unit, class = class, color = NS.ClassColor(class), role = role }
end

-- Show a region when cond is true. cond may be a secret boolean in combat.
local function ShowIf(region, cond)
    if Secret(cond) then
        if region.SetAlphaFromBoolean then
            region:Show()
            region:SetAlphaFromBoolean(cond, 1, 0)
        else
            region:Hide()
        end
    else
        region:SetAlpha(1)
        region:SetShown(cond and true or false)
    end
end
NS.ShowIf = ShowIf

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- Four textures forming a rectangular outline.
local function Edges(frame, layer)
    local e = {}
    for i = 1, 4 do e[i] = frame:CreateTexture(nil, layer) e[i]:SetTexture(WHITE) end
    return e
end

-- Outline of `anchor` grown by `out` pixels, `th` pixels thick (drawn inward from the grown edge).
local function PlaceEdges(e, anchor, out, th)
    local t, b, l, r = e[1], e[2], e[3], e[4]
    for i = 1, 4 do e[i]:ClearAllPoints() end
    t:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    t:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    t:SetHeight(th)
    b:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    b:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    b:SetHeight(th)
    l:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out - th)
    l:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out + th)
    l:SetWidth(th)
    r:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out - th)
    r:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out + th)
    r:SetWidth(th)
end

local function EdgesColor(e, c, a)
    for i = 1, 4 do e[i]:SetVertexColor(c.r, c.g, c.b, a) end
end

local function EdgesShown(e, shown)
    for i = 1, 4 do e[i]:SetShown(shown) end
end

-- The game refuses to change a texture's crop while a mask is applied, so the
-- mask is lifted, the texture painted, then the mask put back.
local function SetMask(tex, mask)
    if not tex.SetMask then return end
    if tex.rpMask == mask then return end
    if pcall(tex.SetMask, tex, mask or "") then tex.rpMask = mask end
end

local function Unmasked(tex, fn)
    local mask = tex.rpMask
    if mask then SetMask(tex, nil) end
    fn()
    if mask then SetMask(tex, mask) end
end

-- Crops texture coords (l, r, t, b) by `trim` on every side, then to the
-- aspect ratio w:h so nothing is stretched.
local function Crop(l, r, t, b, w, h, trim)
    if trim and trim > 0 then
        local dx, dy = (r - l) * trim, (b - t) * trim
        l, r, t, b = l + dx, r - dx, t + dy, b - dy
    end
    if w > 0 and h > 0 then
        local aspect = w / h
        if aspect > 1 then
            local cut = (b - t) * (1 - 1 / aspect) / 2
            t, b = t + cut, b - cut
        elseif aspect < 1 then
            local cut = (r - l) * (1 - aspect) / 2
            l, r = l + cut, r - cut
        end
    end
    return l, r, t, b
end

local function ClassCoords(class)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then return c[1], c[2], c[3], c[4] end
end

------------------------------------------------------------------------
-- Create
------------------------------------------------------------------------

function NS.CreatePortrait(host)
    local P = CreateFrame("Frame", nil, host)
    P.host = host

    P.ring = CreateFrame("Frame", nil, P)
    P.ring:SetAllPoints()
    P.ringEdges = Edges(P.ring, "BACKGROUND")

    P.body = CreateFrame("Frame", nil, P)
    P.body:SetAllPoints()
    -- The round highlight sits behind the portrait, so it lives in the same
    -- frame (layers order it) rather than relying on frame-level order.
    P.ringCircle = P.body:CreateTexture(nil, "BACKGROUND", nil, -7)
    P.ringCircle:SetTexture(CIRCLE)

    -- Threat outline, outside the target highlight.
    P.threatFrame = CreateFrame("Frame", nil, P)
    P.threatFrame:SetAllPoints()
    P.threatEdges = Edges(P.threatFrame, "BACKGROUND")
    P.threatCircle = P.body:CreateTexture(nil, "BACKGROUND", nil, -8)
    P.threatCircle:SetTexture(CIRCLE)
    P.threatFrame:Hide()
    P.threatCircle:Hide()
    P.borderEdges = Edges(P.body, "BORDER")
    P.borderCircle = P.body:CreateTexture(nil, "BORDER")
    P.borderCircle:SetTexture(CIRCLE)
    P.borderCircle:SetAllPoints(P)
    P.content = CreateFrame("Frame", nil, P.body)   -- the area inside the border
    P.bg = P.body:CreateTexture(nil, "ARTWORK", nil, -1)
    P.bg:SetAllPoints(P.content)
    P.tex = P.body:CreateTexture(nil, "ARTWORK", nil, 1)
    P.tex:SetAllPoints(P.content)

    P.model = CreateFrame("PlayerModel", nil, P)
    P.model:SetAllPoints(P.content)
    pcall(P.model.SetScript, P.model, "OnModelLoaded", function() NS.ModelCamera(P) end)

    P.top = CreateFrame("Frame", nil, P)
    P.top:SetAllPoints()
    P.dim = P.top:CreateTexture(nil, "OVERLAY")
    P.dim:SetAllPoints(P.content)

    -- Resource bar (mana, energy, rage...). StatusBar setters accept secret
    -- values, so it keeps working in combat.
    P.power = CreateFrame("StatusBar", nil, P)
    P.power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    P.power:SetMinMaxValues(0, 1)
    P.powerBg = P.power:CreateTexture(nil, "BACKGROUND")
    P.powerBg:SetPoint("TOPLEFT", -1, 1)
    P.powerBg:SetPoint("BOTTOMRIGHT", 1, -1)
    P.powerBg:SetTexture(WHITE)
    P.power:Hide()

    -- Threat badge and percentage, on top of everything else.
    P.over = CreateFrame("Frame", nil, P)
    P.over:SetAllPoints()
    P.threatBadgeBg = P.over:CreateTexture(nil, "OVERLAY", nil, 1)
    P.threatBadge = P.over:CreateTexture(nil, "OVERLAY", nil, 2)
    P.threatText = P.over:CreateFontString(nil, "OVERLAY")
    P.threatText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    P.threatBadgeBg:Hide()
    P.threatBadge:Hide()
    P.threatText:Hide()

    if host.HookScript then
        host:HookScript("OnSizeChanged", function()
            if P:IsShown() then
                NS.LayoutPortrait(P)
                if NS.RequestArrange then NS.RequestArrange() end
            end
        end)
    end
    return P
end

------------------------------------------------------------------------
-- Apply
------------------------------------------------------------------------

function NS.ModelCamera(P)
    local db, m = NS.db, P.model
    if not db then return end
    pcall(m.SetPortraitZoom, m, db.modelZoom)
    pcall(m.SetCamDistanceScale, m, db.modelDistance)
    pcall(m.SetRotation, m, math.rad(db.modelRotation))
    if m.SetPaused then pcall(m.SetPaused, m, not db.modelAnimate) end
end

-- Whether a 3D model can be shown for unit right now.
local function CanModel(unit)
    if not unit then return false end
    local vis = UnitIsVisible(unit)
    if Secret(vis) then return true end
    return vis and true or false
end

-- Paints portrait P for unit. info = NS.UnitInfo(unit). reload forces the 2D
-- portrait / 3D model to be fetched again (unit changed, model changed).
function NS.ApplyPortrait(P, unit, info, reload)
    local db = NS.db
    local previewTexture = info.previewTexture
    local textureChanged = previewTexture ~= (P.info and P.info.previewTexture)
    P.info = info

    -- Which kind of image: 3D, or the fallback when the model can't load.
    local kind = db.portraitType
    if kind == "3d" and not CanModel(unit) then kind = previewTexture and "2d" or db.fallback end
    local changed = reload or kind ~= P.kind or unit ~= P.unit or textureChanged
    P.kind, P.unit = kind, unit

    local round = db.shape == "circle" and kind ~= "3d"
    P.round = round

    -- Image
    if kind == "3d" then
        P.tex:Hide()
        P.model:Show()
        if changed then
            pcall(P.model.ClearModel, P.model)
            pcall(P.model.SetUnit, P.model, unit)
        end
        NS.ModelCamera(P)
    else
        P.model:Hide()
        if changed then pcall(P.model.ClearModel, P.model) end
        P.tex:Show()
        SetMask(P.tex, round and CIRCLE_MASK or nil)
        if kind == "2d" then
            if changed or P.texKind ~= "2d" then
                Unmasked(P.tex, function()
                    if previewTexture then
                        P.tex:SetTexture(previewTexture)
                    elseif not (unit and pcall(SetPortraitTexture, P.tex, unit, true)) then
                        P.tex:SetTexture(UNKNOWN)
                    end
                end)
            end
        else
            Unmasked(P.tex, function()
                if ClassCoords(info.class) then P.tex:SetTexture(CLASS_TEX) else P.tex:SetTexture(UNKNOWN) end
            end)
        end
        P.texKind = kind
    end

    -- Background
    local bc = db.backgroundColor
    P.bg:SetTexture(round and CIRCLE or WHITE)
    P.bg:SetVertexColor(bc[1], bc[2], bc[3], db.backgroundAlpha)
    P.bg:SetShown(db.background)

    -- Border
    local c = NS.Color(db.borderColorMode, "borderColor", info)
    EdgesColor(P.borderEdges, c, db.borderAlpha)
    P.borderCircle:SetVertexColor(c.r, c.g, c.b, db.borderAlpha)
    EdgesShown(P.borderEdges, not round and db.border > 0)
    P.borderCircle:SetShown(round and db.border > 0)

    -- Target highlight
    local tc = db.targetColor
    EdgesColor(P.ringEdges, { r = tc[1], g = tc[2], b = tc[3] }, 1)
    P.ringCircle:SetVertexColor(tc[1], tc[2], tc[3], 1)
    EdgesShown(P.ringEdges, not round)
    P.ringCircle:SetShown(round)

    -- Darkening for dead/offline
    P.dim:SetTexture(round and CIRCLE or WHITE)
    P.dim:SetVertexColor(0, 0, 0, db.deadDarkness)

    -- Resource bar
    local showPower = db.power and (not db.powerOnlyHealers or info.role == "HEALER")
    P.power:SetShown(showPower and true or false)
    P.powerBg:SetVertexColor(0, 0, 0, db.powerBgAlpha)

    NS.PortraitAlpha(P)
    NS.LayoutPortrait(P)
end

local MANA = { r = 0, g = 0, b = 1 }

-- Colour for a power type, from the game's own power colours.
local function PowerColor(ptype, token)
    local t = PowerBarColor
    if not t then return MANA end
    if token and not Secret(token) and t[token] then return t[token] end
    if ptype and not Secret(ptype) and t[ptype] then return t[ptype] end
    return MANA
end

-- Sets the resource bar from the unit's current power.
function NS.UpdatePower(P, unit)
    if not P.power:IsShown() or not unit then return end
    local db = NS.db
    local ptype, token = UnitPowerType(unit)
    pcall(P.power.SetMinMaxValues, P.power, 0, UnitPowerMax(unit, ptype))
    pcall(P.power.SetValue, P.power, UnitPower(unit, ptype))
    local c
    if db.powerColorMode == "power" then c = PowerColor(ptype, token)
    else c = NS.Color(db.powerColorMode, "powerColor", P.info) end
    P.power:SetStatusBarColor(c.r, c.g, c.b)
end

-- Sets the resource bar to a made-up value (designer preview).
function NS.PreviewPower(P, value, token)
    local db = NS.db
    P.power:SetMinMaxValues(0, 1)
    P.power:SetValue(value)
    local c
    if db.powerColorMode == "power" then c = PowerColor(nil, token)
    else c = NS.Color(db.powerColorMode, "powerColor", P.info) end
    P.power:SetStatusBarColor(c.r, c.g, c.b)
end

-- The game fades out-of-range frames by setting the unit frame's own alpha.
-- With range fading off, the portrait ignores that, but still follows the
-- party/raid container's alpha (Edit Mode's Opacity slider).
function NS.PortraitAlpha(P)
    local db = NS.db
    local ignore = not db.rangeFade and P.SetIgnoreParentAlpha
    if P.SetIgnoreParentAlpha then P:SetIgnoreParentAlpha(ignore and true or false) end
    local alpha = db.alpha
    if ignore then
        local container = P.host.GetParent and P.host:GetParent()
        local ca = container and container.GetEffectiveAlpha and container:GetEffectiveAlpha()
        if type(ca) == "number" and not Secret(ca) then alpha = alpha * ca end
    end
    P:SetAlpha(alpha)
end

-- Lowest frame level used by the unit frame's other children above its own
-- level (buffs, debuffs, dispel highlight, status icons), or nil.
local function OverlayLevel(host, P)
    local L = host:GetFrameLevel()
    local best
    for _, c in ipairs({ host:GetChildren() }) do
        if c ~= P and c.GetFrameLevel then
            local lv = c:GetFrameLevel()
            if lv > L and (not best or lv < best) then best = lv end
        end
    end
    return best
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------

local POINTS = {
    left = { "RIGHT", "LEFT", -1, 0 },
    right = { "LEFT", "RIGHT", 1, 0 },
    top = { "BOTTOM", "TOP", 0, 1 },
    bottom = { "TOP", "BOTTOM", 0, -1 },
    insideLeft = { "LEFT", "LEFT", 1, 0 },
    insideRight = { "RIGHT", "RIGHT", -1, 0 },
}

-- Outer size (border included) of a portrait on a frame of size hw x hh.
function NS.PortraitSize(hw, hh)
    local db = NS.db
    local pos, gap = db.position, db.gap
    local w, h
    if pos == "fill" then
        w, h = hw - 2 * gap, hh - 2 * gap
    elseif db.matchSize then
        if pos == "top" or pos == "bottom" then
            w = hw
            h = w / db.aspect
        else
            h = (pos == "insideLeft" or pos == "insideRight") and (hh - 2 * gap) or hh
            w = h * db.aspect
        end
    else
        h = db.size
        w = h * db.aspect
    end
    return math.max(w, 4), math.max(h, 4)
end

function NS.LayoutPortrait(P)
    local db, host = NS.db, P.host
    if not db or not P.info then return end
    local hw, hh = host:GetWidth(), host:GetHeight()
    if not hw or not hh or hw <= 0 or hh <= 0 then return end

    local pos, gap = db.position, db.gap
    P:ClearAllPoints()
    local w, h = NS.PortraitSize(hw, hh)
    local col = P.colPoint
    if col then
        -- Placed by NS.ArrangeColumn.
        P:SetSize(w, h)
        P:SetPoint(col[1], col[2], col[3], col[4], col[5])
    elseif pos == "fill" then
        P:SetPoint("TOPLEFT", host, "TOPLEFT", gap + db.offsetX, -gap + db.offsetY)
        P:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -gap + db.offsetX, gap + db.offsetY)
    else
        P:SetSize(w, h)
        local p = POINTS[pos] or POINTS.left
        P:SetPoint(p[1], host, p[2], p[3] * gap + db.offsetX, p[4] * gap + db.offsetY)
    end

    -- Levels. The health bar shares the unit frame's level, so L + 1 is just
    -- above it. Inside/fill portraits set to "under" stay below the frame's
    -- other children (auras, dispel highlight, status icons); outside
    -- portraits don't overlap anything, so they simply sit above.
    -- Portraits never take the mouse, so clicks still reach the frame.
    local L = host:GetFrameLevel()
    local inside = pos == "fill" or pos == "insideLeft" or pos == "insideRight"
    local lo, hi = L + 1, L + 8
    if inside and db.layer == "under" then
        local cap = OverlayLevel(host, P)
        if cap then hi = cap - 1 end
        if hi < lo then lo, hi = L, L end
    else
        lo = L + 5
    end
    P:SetFrameLevel(lo)
    P.ring:SetFrameLevel(lo)
    P.body:SetFrameLevel(lo)
    P.content:SetFrameLevel(lo)
    P.model:SetFrameLevel(math.min(lo + 1, hi))
    P.top:SetFrameLevel(math.min(lo + 2, hi))
    P.power:SetFrameLevel(math.min(lo + 3, hi))
    P.threatFrame:SetFrameLevel(lo)
    P.over:SetFrameLevel(math.min(lo + 3, hi))

    -- Threat outline sits outside the target highlight; badge in the top-right
    -- corner; percentage text on the portrait.
    local tt = db.threatSize
    local tout = (db.targetHighlight and db.targetSize or 0) + tt
    PlaceEdges(P.threatEdges, P, tout, tt)
    P.threatCircle:ClearAllPoints()
    P.threatCircle:SetPoint("TOPLEFT", P, "TOPLEFT", -tout, tout)
    P.threatCircle:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", tout, -tout)
    local bs = db.threatBadgeSize
    local badgeTex = P.round and CIRCLE or WHITE
    P.threatBadgeBg:SetTexture(badgeTex)
    P.threatBadgeBg:SetVertexColor(0, 0, 0, 1)
    P.threatBadgeBg:SetSize(bs + 2, bs + 2)
    P.threatBadgeBg:ClearAllPoints()
    P.threatBadgeBg:SetPoint("TOPRIGHT", P.content, "TOPRIGHT", 0, 0)
    P.threatBadge:SetTexture(badgeTex)
    P.threatBadge:SetSize(bs, bs)
    P.threatBadge:ClearAllPoints()
    P.threatBadge:SetPoint("CENTER", P.threatBadgeBg, "CENTER")
    if not P.threatText:SetFont(STANDARD_TEXT_FONT, db.threatTextSize, "OUTLINE") then
        P.threatText:SetFont("Fonts\\FRIZQT__.TTF", db.threatTextSize, "OUTLINE")
    end
    P.threatText:ClearAllPoints()
    if db.threatTextPos == "bottom" then
        P.threatText:SetPoint("BOTTOM", P.content, "BOTTOM", 0, 2 + ((db.power and db.powerPlace == "inside") and db.powerHeight or 0))
    elseif db.threatTextPos == "center" then
        P.threatText:SetPoint("CENTER", P.content, "CENTER", 0, 0)
    else
        P.threatText:SetPoint("TOP", P.content, "TOP", 0, -2)
    end

    -- Resource bar
    local ph = db.powerHeight
    P.power:ClearAllPoints()
    if db.powerPlace == "below" then
        P.power:SetPoint("TOPLEFT", P, "BOTTOMLEFT", 1, -2)
        P.power:SetPoint("TOPRIGHT", P, "BOTTOMRIGHT", -1, -2)
    elseif db.powerPlace == "above" then
        P.power:SetPoint("BOTTOMLEFT", P, "TOPLEFT", 1, 2)
        P.power:SetPoint("BOTTOMRIGHT", P, "TOPRIGHT", -1, 2)
    else
        P.power:SetPoint("BOTTOMLEFT", P.content, "BOTTOMLEFT", 1, 1)
        P.power:SetPoint("BOTTOMRIGHT", P.content, "BOTTOMRIGHT", -1, 1)
    end
    P.power:SetHeight(ph)

    -- Border and content area.
    local b = db.border
    if P.round then b = math.min(b, math.min(w, h) / 2 - 1) end
    P.content:ClearAllPoints()
    P.content:SetPoint("TOPLEFT", P, "TOPLEFT", b, -b)
    P.content:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", -b, b)
    PlaceEdges(P.borderEdges, P, 0, math.max(b, 0.01))

    local t = db.targetSize
    PlaceEdges(P.ringEdges, P, t, t)
    P.ringCircle:ClearAllPoints()
    P.ringCircle:SetPoint("TOPLEFT", P, "TOPLEFT", -t, t)
    P.ringCircle:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", t, -t)

    -- Crop the flat image to the content's shape.
    if P.kind ~= "3d" then
        local cw, ch = w - 2 * b, h - 2 * b
        local l, r, tt, bb = 0, 1, 0, 1
        if P.kind == "class" then
            local cl, cr, ct, cb = ClassCoords(P.info.class)
            if cl then l, r, tt, bb = cl, cr, ct, cb end
        end
        l, r, tt, bb = Crop(l, r, tt, bb, cw, ch, db.zoom)
        Unmasked(P.tex, function() P.tex:SetTexCoord(l, r, tt, bb) end)
    end
end

------------------------------------------------------------------------
-- State: target highlight and dead/offline
------------------------------------------------------------------------

-- target and dead may be plain or secret booleans.
function NS.PortraitState(P, target, dead)
    local db = NS.db
    if db.targetHighlight then
        ShowIf(P.ring, target)
        if P.round then ShowIf(P.ringCircle, target) else P.ringCircle:Hide() end
    else
        P.ring:Hide()
        P.ringCircle:Hide()
    end

    local style = db.deadStyle
    local grey = false
    if style == "none" then
        P.top:Hide()
    elseif style == "grey" and P.kind ~= "3d" and not Secret(dead) then
        -- Grey: desaturate, plus a lighter darkening so it reads as "out".
        grey = dead and true or false
        P.dim:SetVertexColor(0, 0, 0, db.deadDarkness * 0.5)
        ShowIf(P.top, dead)
    else
        P.dim:SetVertexColor(0, 0, 0, db.deadDarkness)
        ShowIf(P.top, dead)
    end
    P.tex:SetDesaturated(grey)
end

-- Reads target/dead/offline for a real unit and applies them.
function NS.UpdateUnitState(P, unit)
    local target = UnitIsUnit(unit, "target")
    local dead = UnitIsDeadOrGhost(unit)
    local online = UnitIsConnected(unit)
    if not Secret(dead) and not Secret(online) then
        dead = dead or not online
    elseif not Secret(online) and not online then
        dead = true
    end
    NS.PortraitState(P, target, dead)
end

------------------------------------------------------------------------
-- Column / row arrangement
------------------------------------------------------------------------

-- Lays the portraits in `list` out as one line beside their frames (instead
-- of each beside its own frame), with spacing and alignment. Falls back to
-- per-frame placement when it isn't wanted or frame positions can't be read.
function NS.ArrangeColumn(list)
    local db = NS.db
    local pos = db.position
    local function each() for _, P in ipairs(list) do NS.LayoutPortrait(P) end end
    -- NS.layoutStale: the game re-laid the party frames out in combat, when we
    -- can't read or move them. A column computed earlier no longer lines up,
    -- so each portrait follows its own frame until combat ends.
    if db.arrange ~= "column" or not NS.OUTSIDE[pos] or #list == 0 or NS.layoutStale then
        for _, P in ipairs(list) do P.colPoint = nil end
        return each()
    end

    local items = {}
    for _, P in ipairs(list) do
        local ok, l, b, w, h = pcall(P.host.GetRect, P.host)
        if not ok or not l or not w or Secret(l) or Secret(b) or Secret(w) or Secret(h) then
            -- Positions unreadable (can happen in combat): keep each portrait
            -- where it was rather than jumping; ones never placed go beside
            -- their frame until the next successful pass.
            return each()
        end
        items[#items + 1] = { P = P, l = l, b = b, r = l + w, t = b + h, w = w, h = h }
    end

    local vertical = pos == "left" or pos == "right"
    if vertical then
        table.sort(items, function(x, y) return x.t > y.t end)
    else
        table.sort(items, function(x, y) return x.l < y.l end)
    end
    local minL, maxR, maxT, minB = math.huge, -math.huge, -math.huge, math.huge
    for _, it in ipairs(items) do
        minL, maxR = math.min(minL, it.l), math.max(maxR, it.r)
        maxT, minB = math.max(maxT, it.t), math.min(minB, it.b)
    end

    -- Every point is given relative to the first frame's bottom-left corner.
    local ref = items[1]
    local pw, ph = NS.PortraitSize(ref.w, ref.h)
    local n, sp, gap = #items, db.spacing, db.gap
    for i, it in ipairs(items) do
        local point, x, y
        if vertical then
            local total = n * ph + (n - 1) * sp
            local top
            if db.align == "end" then top = minB + total
            elseif db.align == "center" then top = (maxT + minB) / 2 + total / 2
            else top = maxT end
            y = top - (i - 1) * (ph + sp)
            if pos == "left" then point, x = "TOPRIGHT", minL - gap
            else point, x = "TOPLEFT", maxR + gap end
        else
            local total = n * pw + (n - 1) * sp
            local left
            if db.align == "end" then left = maxR - total
            elseif db.align == "center" then left = (minL + maxR) / 2 - total / 2
            else left = minL end
            x = left + (i - 1) * (pw + sp)
            if pos == "top" then point, y = "BOTTOMLEFT", maxT + gap
            else point, y = "TOPLEFT", minB - gap end
        end
        it.P.colPoint = { point, ref.P.host, "BOTTOMLEFT", x - ref.l + db.offsetX, y - ref.b + db.offsetY }
        NS.LayoutPortrait(it.P)
    end
end

------------------------------------------------------------------------
-- Threat
------------------------------------------------------------------------

local function ThreatColor(status)
    if GetThreatStatusColor then
        local ok, r, g, b = pcall(GetThreatStatusColor, status)
        if ok and r then return r, g, b end
    end
    if status >= 3 then return 1, 0, 0 elseif status == 2 then return 1, 0.6, 0 end
    return 1, 1, 0.47
end

local function ThreatText(db, pct, held, total, contested)
    local lines = {}
    if NS.ShowPackThreat(db) and total and total > 0 then
        local pack = db.threatHeldCount and ("%d/%d"):format(held, total)
        if db.threatHeldPercent then
            local share = ("%d%%"):format(math.floor(100 * held / total + 0.5))
            pack = pack and (pack .. " (" .. share .. ")") or share
        end
        if pack then lines[#lines + 1] = pack end
        if db.threatContested then lines[#lines + 1] = ("%d at risk"):format(contested) end
    end
    if db.threatText and not Secret(pct) and pct and pct > 0 then
        local target = ("%d%%"):format(math.floor(pct + 0.5))
        lines[#lines + 1] = #lines > 0 and ("Target " .. target) or target
    end
    if #lines > 0 then return table.concat(lines, "\n") end
end

-- Target threat and visible-enemy counts can be displayed together.
function NS.PortraitThreat(P, status, pct, held, total, contested)
    local db = NS.db
    local known = not Secret(status) and status ~= nil
    local show = db.threat and known and status >= (db.threatFrom == "aggro" and 2 or 1)
    local r, g, b = 1, 1, 1
    if known and status >= 1 then r, g, b = ThreatColor(status) end

    local outline = show and (db.threatStyle == "outline" or db.threatStyle == "both")
    EdgesColor(P.threatEdges, { r = r, g = g, b = b }, 1)
    P.threatCircle:SetVertexColor(r, g, b, 1)
    P.threatFrame:SetShown(outline and not P.round)
    P.threatCircle:SetShown(outline and P.round)

    local badge = show and (db.threatStyle == "badge" or db.threatStyle == "both")
    P.threatBadge:SetVertexColor(r, g, b, 1)
    P.threatBadge:SetShown(badge)
    P.threatBadgeBg:SetShown(badge)

    local text = db.threat and ThreatText(db, pct, held, total, contested)
    if text then
        P.threatText:SetText(text)
        P.threatText:SetTextColor(r, g, b)
    end
    P.threatText:SetShown(text and true or false)
end

local function Attackable(unit)
    local exists = UnitExists(unit)
    if Secret(exists) or not exists then return false end
    local ok = UnitCanAttack("player", unit)
    if Secret(ok) then return true end
    return ok and true or false
end

function NS.VisibleThreatEnemies()
    local enemies = {}
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return enemies end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = not plate:IsForbidden() and plate.GetUnit and plate:GetUnit()
        if not Secret(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") then
            local active = UnitAffectingCombat(unit)
            local hostile = UnitCanAttack("player", unit)
            local dead = UnitIsDeadOrGhost(unit)
            local player = UnitIsPlayer(unit)
            if not Secret(active) and active and not Secret(hostile) and hostile
                and not Secret(dead) and not dead and not Secret(player) and not player then
                enemies[#enemies + 1] = unit
            end
        end
    end
    return enemies
end

local function PackThreat(unit, enemies)
    local held, total, contested = 0, 0, 0
    for _, enemy in ipairs(enemies) do
        local status = UnitThreatSituation(unit, enemy)
        if not Secret(status) then
            total = total + 1
            if status == 2 or status == 3 then held = held + 1 end
            if status == 2 then contested = contested + 1 end
        end
    end
    return held, total, contested
end

-- Reads a real unit's threat and applies it.
function NS.UpdateThreat(P, unit, enemies)
    local db = NS.db
    if not db.threat or not unit or not UnitThreatSituation then return NS.PortraitThreat(P) end
    local hasTarget = Attackable("target")
    local status
    if db.threatAgainst == "target" then
        if hasTarget then status = UnitThreatSituation(unit, "target") end
    else
        status = UnitThreatSituation(unit)
    end
    local pct
    if db.threatText and hasTarget and UnitDetailedThreatSituation then
        local _, _, scaled = UnitDetailedThreatSituation(unit, "target")
        pct = scaled
    end
    local held, total, contested
    if NS.ShowPackThreat(db) then
        held, total, contested = PackThreat(unit, enemies or NS.VisibleThreatEnemies())
    end
    NS.PortraitThreat(P, status, pct, held, total, contested)
end
