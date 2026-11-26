-- RaidPortraits designer: a movable window with a live preview, a sidebar of
-- sections, search, per-setting and per-section reset, built-in and saved
-- looks, and a list of everything changed from the defaults.
-- Controls are built from NS.FIELDS (Schema.lua). Same layout as PartyPlates.

local ADDON, NS = ...

local GOLD = { 0.88, 0.73, 0.47 }
local W, H = 820, 700
local NAV_W = 176
local PREVIEW_H = 172
local CONTENT_X = NAV_W + 20
local CONTENT_W = W - CONTENT_X - 44
local REFRESH_ICON = "Interface\\Buttons\\UI-RefreshButton"
local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"

local designer, category
local rows = {}          -- every control row, in schema order
local pages = {}         -- section key -> scroll child frame
local navButtons = {}
local current = "portrait"
local refreshing = false
local query = ""
local preview = { layout = "stack", party = "friends" }
local dynamic = {}       -- refreshers for the looks and changes pages

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

local function Backdrop(f, bg, border)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border))
end

local function Label(parent, text, font)
    local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    l:SetJustifyH("LEFT")
    l:SetText(text)
    return l
end

-- Flat dark button matching the window, instead of the game's red panel
-- button. Grows to fit its text. :SetSelected(on) gives the gold "chosen" look.
local BTN_BG, BTN_EDGE = { 0.12, 0.11, 0.10, 1 }, { 0.32, 0.26, 0.17, 1 }
local SEL_BG, SEL_EDGE = { 0.36, 0.28, 0.16, 1 }, { 0.88, 0.73, 0.47, 1 }

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 22)
    Backdrop(b, BTN_BG, BTN_EDGE)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b:SetText(text)
    fs:SetTextColor(0.9, 0.9, 0.9)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.08)
    local need = fs:GetStringWidth() + 18
    if need > width then b:SetWidth(need) end
    function b:SetSelected(on)
        self.selected = on
        self:SetBackdropColor(unpack(on and SEL_BG or BTN_BG))
        self:SetBackdropBorderColor(unpack(on and SEL_EDGE or BTN_EDGE))
        if on then fs:SetTextColor(unpack(GOLD)) else fs:SetTextColor(0.9, 0.9, 0.9) end
    end
    b:SetScript("OnEnable", function() fs:SetAlpha(1) end)
    b:SetScript("OnDisable", function() fs:SetAlpha(0.4) end)
    b:SetScript("OnMouseDown", function() if b:IsEnabled() then fs:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function Tooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

local function SectionLabel(key)
    for _, s in ipairs(NS.SECTIONS) do if s.key == key then return s.label end end
    return key
end

local function ChoiceLabel(f, value)
    for _, c in ipairs(f.choices) do if c[1] == value then return c[2] end end
    return tostring(value)
end

local function ValueText(f, v)
    if f.type == "toggle" then return v and "On" or "Off" end
    if f.type == "choice" then return ChoiceLabel(f, v) end
    if f.type == "color" then
        local r, g, b = math.floor(v[1] * 255 + 0.5), math.floor(v[2] * 255 + 0.5), math.floor(v[3] * 255 + 0.5)
        return ("|TInterface\\Buttons\\WHITE8X8:12:12:0:0:8:8:0:8:0:8:%d:%d:%d|t %d, %d, %d"):format(r, g, b, r, g, b)
    end
    if f.step and f.step < 1 then return ("%.2f"):format(v) end
    return tostring(v)
end

local function IsDefault(key)
    return NS.Same(NS.db[key], NS.DEFAULTS[key])
end

-- A colour field only matters when its colour-mode setting is "Custom".
local function ModeKeyFor(key)
    local modeKey = key:gsub("Color$", "ColorMode")
    if modeKey ~= key and NS.FIELD[modeKey] then return modeKey end
end

-- Whether a row's controls are usable.
local function RowEnabled(f)
    local db = NS.db
    local p = f.parent
    while p do
        if not db[p] then return false end
        p = NS.FIELD[p].parent
    end
    if f.parentOff and db[f.parentOff] then return false end
    if f.cond and not f.cond(db) then return false end
    local modeKey = f.type == "color" and ModeKeyFor(f.key)
    if modeKey and db[modeKey] ~= "custom" then return false end
    return true
end

local function Matches(f)
    if query == "" then return true end
    return f.label:lower():find(query, 1, true) ~= nil
        or SectionLabel(f.section):lower():find(query, 1, true) ~= nil
        or (f.tip and f.tip:lower():find(query, 1, true) ~= nil)
end

local function PickColour(key)
    local old = NS.Copy(NS.db[key])
    local function changed()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        NS.Change(key, { r, g, b })
    end
    local function cancel() NS.Change(key, old) end
    ColorPickerFrame:Hide()
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = old[1], g = old[2], b = old[3], hasOpacity = false,
            swatchFunc = changed, cancelFunc = cancel })
    else
        ColorPickerFrame.func = changed
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(old[1], old[2], old[3])
        ColorPickerFrame:Show()
    end
end

------------------------------------------------------------------------
-- Control rows
------------------------------------------------------------------------

local sliderCount = 0

-- Builds one row for field f on page `page` at vertical offset y; returns its height.
local function BuildRow(page, f, y)
    local row = CreateFrame("Frame", nil, page)
    row:SetPoint("TOPLEFT", 8, y)
    row:SetSize(CONTENT_W - 16, 30)
    local r = { field = f, frame = row, controls = {} }

    local reset = CreateFrame("Button", nil, row)
    reset:SetSize(16, 16)
    reset:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -4)
    reset:SetNormalTexture(REFRESH_ICON)
    reset:SetHighlightTexture(REFRESH_ICON)
    reset:GetHighlightTexture():SetAlpha(0.5)
    reset:SetScript("OnClick", function() NS.Change(f.key, NS.DEFAULTS[f.key]) end)
    Tooltip(reset, "Reset to default", "Default: " .. ValueText(f, NS.DEFAULTS[f.key]))
    r.reset = reset

    local height
    if f.type == "toggle" then
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 0, 0)
        local t = Label(row, f.label)
        t:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        cb:SetHitRectInsets(0, -(t:GetStringWidth() + 10), 0, 0)
        cb:SetScript("OnClick", function(self) NS.Change(f.key, self:GetChecked() and true or false) end)
        if f.tip then Tooltip(cb, f.label, f.tip) end
        r.text = t
        r.controls = { cb }
        r.update = function(v) cb:SetChecked(v) end
        height = 28

    elseif f.type == "range" then
        local t = Label(row, f.label)
        t:SetPoint("TOPLEFT", 4, -2)
        local value = Label(row, "", "GameFontNormal")
        value:SetPoint("LEFT", t, "RIGHT", 8, 0)
        value:SetTextColor(unpack(GOLD))
        sliderCount = sliderCount + 1
        local s = CreateFrame("Slider", "RaidPortraitsDesignerSlider" .. sliderCount, row, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", 6, -22)
        s:SetSize(math.min(380, CONTENT_W - 80), 16)
        s:SetMinMaxValues(f.min, f.max)
        s:SetValueStep(f.step)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        local low, high = _G[s:GetName() .. "Low"], _G[s:GetName() .. "High"]
        if low then low:SetText(f.min) end
        if high then high:SetText(f.max) end
        local text = _G[s:GetName() .. "Text"]
        if text then text:SetText("") end
        s:SetScript("OnValueChanged", function(_, v)
            if refreshing then return end
            v = math.floor(v / f.step + 0.5) * f.step
            if not NS.Same(v, NS.db[f.key]) then NS.Change(f.key, v) end
        end)
        if f.tip then Tooltip(s, f.label, f.tip) end
        r.text = t
        r.controls = { s }
        r.update = function(v)
            s:SetValue(v)
            value:SetText(ValueText(f, v))
        end
        height = 54

    elseif f.type == "choice" then
        local t = Label(row, f.label)
        t:SetPoint("TOPLEFT", 4, -2)
        local n = #f.choices
        -- Long lists wrap onto a second line of buttons.
        local perLine = math.min(n, 4)
        local bw = math.min(130, math.floor((CONTENT_W - 50) / perLine) - 4)
        local buttons = {}
        -- Buttons grow to fit their text, so place them left to right and
        -- wrap onto a new line when the row is full.
        local x, line, maxX = 4, 0, CONTENT_W - 50
        for i, c in ipairs(f.choices) do
            local b = Button(row, c[2], bw, function() NS.Change(f.key, c[1]) end)
            local w = b:GetWidth()
            if (i - 1) % perLine == 0 and i > 1 or x + w > maxX then
                if x > 4 then x, line = 4, line + 1 end
            end
            b:SetPoint("TOPLEFT", x, -20 - line * 26)
            x = x + w + 4
            b.value = c[1]
            buttons[i] = b
        end
        local lines = line + 1
        if f.tip then Tooltip(buttons[1], f.label, f.tip) end
        r.text = t
        r.controls = buttons
        r.update = function(v)
            for _, b in ipairs(buttons) do b:SetSelected(b.value == v) end
        end
        height = 50 + (lines - 1) * 26

    elseif f.type == "color" then
        local sw = CreateFrame("Button", nil, row, "BackdropTemplate")
        sw:SetSize(22, 22)
        sw:SetPoint("TOPLEFT", 2, -2)
        Backdrop(sw, { 1, 1, 1, 1 }, { 0, 0, 0, 1 })
        local t = Label(row, f.label)
        t:SetPoint("LEFT", sw, "RIGHT", 8, 0)
        sw:SetScript("OnClick", function() PickColour(f.key) end)
        local tip = f.tip or "Click to choose a colour."
        local modeKey = ModeKeyFor(f.key)
        if modeKey then tip = tip .. " Used when \"" .. NS.FIELD[modeKey].label .. "\" is set to Custom colour." end
        Tooltip(sw, f.label, tip)
        r.text = t
        r.controls = { sw }
        r.update = function(v) sw:SetBackdropColor(v[1], v[2], v[3], 1) end
        height = 30
    end

    row:SetHeight(height)
    r.height = height
    rows[#rows + 1] = r
    return height
end

local function UpdateRow(r)
    local f = r.field
    local enabled = RowEnabled(f)
    r.update(NS.db[f.key])
    for _, c in ipairs(r.controls) do
        if c.SetEnabled then c:SetEnabled(enabled) end
    end
    local tc = enabled and 1 or 0.5
    r.text:SetTextColor(tc, tc, tc)
    r.reset:SetShown(not IsDefault(f.key))
    r.frame:SetAlpha(Matches(f) and 1 or 0.25)
end

------------------------------------------------------------------------
-- Preview: three stand-in raid-style party frames
------------------------------------------------------------------------

local SAMPLES = {
    { name = nil, target = false, dead = false, hp = 0.85, threat = 3, pct = 100, held = 4, enemies = 5, contested = 1 },
    { name = "Your target", target = true, dead = false, hp = 0.55, threat = 1, pct = 84, held = 1, enemies = 5, contested = 0 },
    { name = "Dead", target = false, dead = true, hp = 0 },
}

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FRIENDS = {
    { name = "Cerulean Waffle", class = "DRUID", power = "MANA", previewTexture = MEDIA .. "cerulean-waffle" },
    { name = "Amog Os", class = "ROGUE", power = "ENERGY", previewTexture = MEDIA .. "amog-os" },
    { name = "Etherea Lightsong", class = "WARRIOR", power = "RAGE", previewTexture = MEDIA .. "etherea-lightsong" },
}

local function PlayerClass()
    local _, c = UnitClass("player")
    return c
end

-- The game's own look for a party health bar: copied from the first real
-- party frame when there is one, else the game's default (green).
local function GameHealthLook()
    local tex, r, g, b = NS.GAME_HEALTH_TEXTURE, 0, 0.8, 0
    local f = _G.CompactPartyFrameMember1
    local bar = f and f.healthBar
    if bar and f:IsShown() then
        -- With restyling on, the real colour (and maybe texture) is ours, so
        -- only the game's texture is copied, and only when it's in use.
        local t = bar:GetStatusBarTexture()
        if t and t:GetTexture() and (not NS.db.healthStyle or not NS.HEALTH_TEXTURES[NS.db.healthTexture]) then
            tex = t:GetTexture()
        end
        if not NS.db.healthStyle then
            local cr, cg, cb = bar:GetStatusBarColor()
            if cr then r, g, b = cr, cg, cb end
        end
    end
    return tex, r, g, b
end

-- Paints a preview frame's health bar and background the way the real ones look.
local function PreviewHealth(f, info, s)
    local db = NS.db
    local gameTex, gr, gg, gb = GameHealthLook()
    if db.enabled and db.healthStyle and db.showParty then
        if not NS.HEALTH_TEXTURES[db.healthTexture] then f.bar:SetStatusBarTexture(gameTex) end
        if s.dead then
            local file = NS.HEALTH_TEXTURES[db.healthTexture]
            if file then f.bar:SetStatusBarTexture(file) end
            f.bar:SetStatusBarColor(0.5, 0.5, 0.5)
        else
            NS.PaintHealthBar(f.bar, NS.HealthColor(info, s.hp))
        end
        if db.healthBg then
            local c = db.healthBgColor
            f.bg:SetVertexColor(c[1], c[2], c[3], db.healthBgAlpha)
        else
            f.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
        end
    else
        f.bar:SetStatusBarTexture(gameTex)
        if s.dead then f.bar:SetStatusBarColor(0.5, 0.5, 0.5) else f.bar:SetStatusBarColor(gr, gg, gb) end
        f.bg:SetVertexColor(0.1, 0.1, 0.1, 1)
    end
end

-- Whether the real party frames are in a row (Edit Mode "Use Horizontal Layout").
local function RealLayout()
    local a, b = _G.CompactPartyFrameMember1, _G.CompactPartyFrameMember2
    if not (a and b and a:IsShown() and b:IsShown()) then return end
    local ax, ay = a:GetCenter()
    local bx, by = b:GetCenter()
    if not (ax and bx) then return end
    return math.abs(bx - ax) > math.abs(by - ay) and "row" or "stack"
end

-- Size of the real party frames, so the preview matches them.
local function FrameSize()
    local f = _G.CompactPartyFrameMember1
    local w, h = f and f:GetWidth(), f and f:GetHeight()
    if w and h and w > 10 and h > 10 then return w, h end
    return 72, 36
end

-- "All icons": every icon the game can put on a raid-style frame, at the
-- game's default spots and sizes (DefaultCompactUnitFrameSetup), so you can
-- see how much room the portrait and its extras have.
local ICON_TEX = {
    role = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    center = "Interface\\RaidFrame\\Raid-Icon-Rez",
    buffs = { "Interface\\Icons\\Spell_Holy_WordFortitude", "Interface\\Icons\\Spell_Nature_Regeneration",
              "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    debuffs = { "Interface\\Icons\\Spell_Shadow_ShadowWordPain", "Interface\\Icons\\Ability_Creature_Disease_02",
                "Interface\\Icons\\Spell_Nature_CorrosiveBreath" },
    dispel = { "Interface\\RaidFrame\\Raid-Icon-DebuffMagic", "Interface\\RaidFrame\\Raid-Icon-DebuffCurse",
               "Interface\\RaidFrame\\Raid-Icon-DebuffPoison" },
}

local function IconTex(parent, file, crop)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(file)
    if crop then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    return t
end

local function BuildAllIcons(f)
    local box = CreateFrame("Frame", nil, f)
    box:SetAllPoints(f)
    box:SetFrameLevel(f:GetFrameLevel() + 6)
    local a = { box = box }
    a.role = IconTex(box, ICON_TEX.role)
    a.role:SetTexCoord(20 / 64, 39 / 64, 1 / 64, 20 / 64)   -- healer
    a.ready = IconTex(box, ICON_TEX.ready)
    a.center = IconTex(box, ICON_TEX.center)
    a.buffs, a.debuffs, a.dispel = {}, {}, {}
    for i = 1, 3 do
        a.buffs[i] = IconTex(box, ICON_TEX.buffs[i], true)
        a.debuffs[i] = IconTex(box, ICON_TEX.debuffs[i], true)
        a.dispel[i] = IconTex(box, ICON_TEX.dispel[i])
    end
    a.hp = box:CreateFontString(nil, "OVERLAY")
    f.allIcons = a
    return a
end

local function LayoutAllIcons(f, fw, fh, on)
    local a = f.allIcons or (on and BuildAllIcons(f))
    if f.sampleAura then f.sampleAura:SetShown(not on) end
    if not a then return end
    a.box:SetShown(on)
    f.name:ClearAllPoints()
    if not on then
        f.name:SetPoint("TOPLEFT", 3, -3)
        f.name:SetPoint("RIGHT", -3, 0)
        return
    end
    local scale = math.min(fh / 36, fw / 72)
    local buff = 11 * scale
    local role = 12 * scale
    a.role:SetSize(role, role)
    a.role:ClearAllPoints()
    a.role:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -2)
    f.name:SetPoint("TOPLEFT", a.role, "TOPRIGHT", 1, -1)
    f.name:SetPoint("RIGHT", -3, 0)
    a.ready:SetSize(15 * scale, 15 * scale)
    a.ready:ClearAllPoints()
    a.ready:SetPoint("CENTER", f, "CENTER", -buff, 0)
    a.center:SetSize(buff * 2, buff * 2)
    a.center:ClearAllPoints()
    a.center:SetPoint("CENTER", f, "CENTER", buff * 1.2, 0)
    for i = 1, 3 do
        local b, d, x = a.buffs[i], a.debuffs[i], a.dispel[i]
        b:SetSize(buff, buff) d:SetSize(buff, buff) x:SetSize(buff, buff)
        b:ClearAllPoints() d:ClearAllPoints() x:ClearAllPoints()
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3 - (i - 1) * buff, 3)
        d:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3 + (i - 1) * buff, 3)
        x:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3 - (i - 1) * buff, -2)
    end
    local db = NS.db
    local style = db.healthText
    if style and style ~= "none" then
        a.hp:SetFont(STANDARD_TEXT_FONT, db.healthTextSize or 10, db.healthTextOutline and "OUTLINE" or "")
        local c = db.healthTextColor or { 1, 1, 1 }
        a.hp:SetTextColor(c[1], c[2], c[3])
        local p = ({ center = "CENTER", left = "LEFT", right = "RIGHT", bottom = "BOTTOM", top = "TOP" })[db.healthTextPos] or "CENTER"
        a.hp:ClearAllPoints()
        a.hp:SetPoint(p, f, p, 0, 0)
        local sample = { full = "1234 / 2000", short = "1.2k / 2k", percent = "62%", shortpct = "1.2k | 62%",
                         current = "1.2k", deficit = "-766" }
        a.hp:SetText(sample[style] or "")
        a.hp:Show()
    else
        a.hp:Hide()
    end
end

local function BuildPreview(p)
    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetPoint("TOPLEFT", CONTENT_X, -64)
    box:SetSize(W - CONTENT_X - 16, PREVIEW_H)
    Backdrop(box, { 0.09, 0.11, 0.08, 1 }, { 0.30, 0.25, 0.16, 1 })
    if box.SetClipsChildren then box:SetClipsChildren(true) end
    local bgArt = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgArt:SetPoint("TOPLEFT", 1, -1)
    bgArt:SetPoint("BOTTOMRIGHT", -1, 1)
    bgArt:SetTexture("Interface\\Buttons\\WHITE8X8")
    if bgArt.SetGradient and CreateColor then
        pcall(bgArt.SetGradient, bgArt, "VERTICAL", CreateColor(0.05, 0.07, 0.05, 1), CreateColor(0.16, 0.20, 0.13, 1))
    else
        bgArt:SetVertexColor(0.1, 0.13, 0.09)
    end
    preview.box = box

    local cap = Label(box, "PREVIEW", "GameFontNormalSmall")
    cap:SetPoint("TOPLEFT", 10, -8)
    cap:SetTextColor(unpack(GOLD))

    local iconsBtn = Button(box, "Show all icons", 90, function()
        preview.allIcons = not preview.allIcons
        NS.RefreshDesigner()
    end)
    iconsBtn:SetHeight(16)
    iconsBtn:SetPoint("LEFT", cap, "RIGHT", 8, 0)
    Tooltip(iconsBtn, "Show all icons", "Puts every icon the game can show on a party frame onto the preview at once, at the game's own spots and sizes: role, ready check, resurrect / summon, three buffs, three debuffs and three dispel types, plus your health numbers. Shows how much room your portrait has.")
    preview.iconsBtn = iconsBtn

    -- Area the stand-in frames are fitted into (left of the controls).
    local stage = CreateFrame("Frame", nil, box)
    stage:SetPoint("TOPLEFT", 10, -24)
    stage:SetPoint("BOTTOMRIGHT", -160, 8)
    preview.stage = stage

    local group = CreateFrame("Frame", nil, stage)
    preview.group = group
    preview.frames = {}
    for i, s in ipairs(SAMPLES) do
        local f = CreateFrame("Frame", nil, group, "BackdropTemplate")
        Backdrop(f, { 0.08, 0.08, 0.08, 1 }, { 0, 0, 0, 1 })
        -- Missing-health background, like the game's frame.background.
        f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.bg:SetPoint("TOPLEFT", 1, -1)
        f.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        f.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetPoint("TOPLEFT", 1, -1)
        bar:SetPoint("BOTTOMRIGHT", -1, 1)
        bar:SetStatusBarTexture(STATUSBAR)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(s.hp)
        bar:SetFrameLevel(f:GetFrameLevel()) -- like Blizzard's (useParentLevel)
        f.bar = bar
        if i == 1 then
            -- A sample dispellable curse, to show what sits above the portrait.
            local aura = CreateFrame("Frame", nil, f, "BackdropTemplate")
            aura:SetSize(14, 14)
            aura:SetPoint("BOTTOMRIGHT", -3, 3)
            aura:SetFrameLevel(f:GetFrameLevel() + 4)
            Backdrop(aura, { 0, 0, 0, 1 }, { 0.6, 0, 1, 1 })
            f.sampleAura = aura
            local icon = aura:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", -1, 1)
            icon:SetTexture("Interface\\Icons\\Spell_Shadow_CurseOfTounges")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        f.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.name:SetPoint("TOPLEFT", 3, -3)
        f.name:SetPoint("RIGHT", -3, 0)
        f.name:SetJustifyH("LEFT")
        f.name:SetWordWrap(false)
        f:EnableMouse(true)
        f:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.name:GetText())
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        f.status = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.status:SetPoint("CENTER", 0, -4)
        f.status:SetText(s.dead and (DEAD or "Dead") or "")
        f.portrait = NS.CreatePortrait(f)
        f.sample = s
        preview.frames[i] = f
    end

    -- Preview controls: layout, party and sample class.
    local side = Button(box, "Side by side", 66, function() preview.layout = "row" NS.RefreshDesigner() end)
    side:SetPoint("TOPRIGHT", -10, -30)
    local stack = Button(box, "Stacked", 140 - 4 - side:GetWidth(), function() preview.layout = "stack" NS.RefreshDesigner() end)
    stack:SetPoint("RIGHT", side, "LEFT", -4, 0)
    Tooltip(stack, "Stacked", "Party frames one above the other (the default party layout).")
    Tooltip(side, "Side by side", "Party frames in a row (Edit Mode's horizontal layout).")
    preview.layoutBtns = { stack = stack, row = side }
    local layoutCap = Label(box, "Frame layout", "GameFontHighlightSmall")
    layoutCap:SetPoint("BOTTOMLEFT", stack, "TOPLEFT", 2, 4)
    layoutCap:SetTextColor(0.7, 0.7, 0.7)

    local sampleBtn = Button(box, "Sample party", 72, function() preview.party = "sample" NS.RefreshDesigner() end)
    sampleBtn:SetPoint("TOPRIGHT", side, "BOTTOMRIGHT", 0, -26)
    local friendsBtn = Button(box, "Friends", 140 - 4 - sampleBtn:GetWidth(), function() preview.party = "friends" NS.RefreshDesigner() end)
    friendsBtn:SetPoint("RIGHT", sampleBtn, "LEFT", -4, 0)
    preview.partyBtns = { friends = friendsBtn, sample = sampleBtn }
    local partyCap = Label(box, "Preview party", "GameFontHighlightSmall")
    partyCap:SetPoint("BOTTOMLEFT", friendsBtn, "TOPLEFT", 2, 4)
    partyCap:SetTextColor(0.7, 0.7, 0.7)
    Tooltip(friendsBtn, "Friends", "Shows Blizzard Armory portraits and class colours for your friends.")
    Tooltip(sampleBtn, "Sample party", "Uses your character model to test the 3D controls and lets you preview other class colours.")

    local classes = {}
    for _, c in ipairs(CLASS_SORT_ORDER or {}) do classes[#classes + 1] = c end
    if #classes == 0 then for c in pairs(RAID_CLASS_COLORS or {}) do classes[#classes + 1] = c end table.sort(classes) end
    local classBtn = Button(box, "", 140, function(_, mouse)
        local cur = preview.class or PlayerClass()
        local idx = 1
        for i, c in ipairs(classes) do if c == cur then idx = i end end
        idx = idx + (mouse == "RightButton" and -1 or 1)
        if idx < 1 then idx = #classes elseif idx > #classes then idx = 1 end
        preview.class = classes[idx]
        NS.RefreshDesigner()
    end)
    classBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    classBtn:SetPoint("TOPRIGHT", sampleBtn, "BOTTOMRIGHT", 0, -26)
    Tooltip(classBtn, "Party members' class", "Changes the class of the two sample party members, for class colours and class icons. Left-click for the next class, right-click for the previous one. Portraits and 3D models always show your own character.")
    preview.classBtn = classBtn
    local classCap = Label(box, "Party members' class", "GameFontHighlightSmall")
    classCap:SetPoint("BOTTOMLEFT", classBtn, "TOPLEFT", 2, 4)
    classCap:SetTextColor(0.7, 0.7, 0.7)
    preview.classCap = classCap

    local note = Label(box, "Armory portraits are static. Use Sample party for 3D controls.", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", friendsBtn, "BOTTOMLEFT", 0, -10)
    note:SetWidth(140)
    note:SetTextColor(0.7, 0.7, 0.7)
    preview.friendsNote = note
end

local function RefreshPreview()
    if not preview.frames then return end
    local db = NS.db
    local fw, fh = FrameSize()
    local stacked = preview.layout == "stack"
    local spacing = (db.showParty and db.spacing) or 0   -- the game stacks frames edge to edge

    -- Fit the group (plus one portrait sticking out) into the stage.
    local pw, ph = NS.PortraitSize(fw, fh)
    local pos = db.position
    local extraW = (pos == "left" or pos == "right") and (pw + db.gap + math.abs(db.offsetX)) or 0
    local extraH = (pos == "top" or pos == "bottom") and (ph + db.gap + math.abs(db.offsetY)) or 0
    local gw = stacked and fw or (3 * fw + 2 * spacing)
    local gh = stacked and (3 * fh + 2 * spacing) or fh
    local sw, sh = preview.stage:GetWidth(), preview.stage:GetHeight()
    if not sw or sw <= 0 then sw, sh = W - CONTENT_X - 16 - 170, PREVIEW_H - 32 end
    local scale = math.min(1.6, (sw - 10) / (gw + extraW + 4), (sh - 6) / (gh + extraH + 4))
    scale = math.max(scale, 0.2)
    local group = preview.group
    group:SetScale(scale)
    group:SetSize(gw, gh)
    local dx = pos == "left" and extraW / 2 or pos == "right" and -extraW / 2 or 0
    local dy = pos == "top" and -extraH / 2 or pos == "bottom" and extraH / 2 or 0
    group:ClearAllPoints()
    group:SetPoint("CENTER", preview.stage, "CENTER", dx, dy)

    local showingFriends = preview.party == "friends"
    local otherClass = preview.class or PlayerClass()
    for i, f in ipairs(preview.frames) do
        f:SetSize(fw, fh)
        f:ClearAllPoints()
        if stacked then
            f:SetPoint("TOPLEFT", group, "TOPLEFT", 0, -(i - 1) * (fh + spacing))
        else
            f:SetPoint("TOPLEFT", group, "TOPLEFT", (i - 1) * (fw + spacing), 0)
        end
        local s = f.sample
        local friend = showingFriends and FRIENDS[i]
        local class = friend and friend.class or (i == 1 and PlayerClass() or otherClass)
        local unit = "player"
        if friend then unit = nil end
        -- Role "HEALER" so the sample resource bars show even with "Only for healers".
        local info = { unit = unit, class = class, color = NS.ClassColor(class), role = "HEALER",
                       previewTexture = friend and friend.previewTexture or nil }
        local playerName = not friend and not s.name and UnitName("player")
        if NS.Secret(playerName) then playerName = nil end
        f.name:SetText(friend and friend.name or s.name or playerName or "You")
        PreviewHealth(f, info, s)
        NS.ApplyPortrait(f.portrait, unit, info)
        NS.PortraitState(f.portrait, s.target, s.dead)
        NS.PortraitThreat(f.portrait, s.threat, s.pct, s.held, s.enemies, s.contested)
        local token = friend and friend.power or "MANA"
        if not friend and i == 1 then
            local _, t = UnitPowerType("player")
            if type(t) == "string" and not NS.Secret(t) then token = t end
        end
        NS.PreviewPower(f.portrait, s.dead and 0 or (0.9 - i * 0.15), token)
        f.portrait:SetShown(db.enabled)
        LayoutAllIcons(f, fw, fh, preview.allIcons and true or false)
    end
    preview.iconsBtn:SetSelected(preview.allIcons and true or false)
    local list = {}
    for _, f in ipairs(preview.frames) do list[#list + 1] = f.portrait end
    NS.ArrangeColumn(list)

    for key, b in pairs(preview.layoutBtns) do b:SetSelected(key == preview.layout) end
    for key, b in pairs(preview.partyBtns) do b:SetSelected(key == preview.party) end
    preview.classBtn:SetShown(not showingFriends)
    preview.classCap:SetShown(not showingFriends)
    preview.friendsNote:SetShown(showingFriends and db.portraitType == "3d")
    local oc = NS.ClassColor(otherClass)
    preview.classBtn:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[otherClass] or otherClass or "?") .. "  >")
    local fs = preview.classBtn:GetFontString()
    if fs then fs:SetTextColor(oc.r, oc.g, oc.b) end
end

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------

-- A scrolling page with a thin gold scroll bar (the game's default scroll
-- bar art doesn't match this window) and mouse-wheel scrolling.
local function NewPage(p, key)
    local scroll = CreateFrame("ScrollFrame", nil, p)
    scroll:SetPoint("TOPLEFT", CONTENT_X, -(64 + PREVIEW_H + 10))
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W, 10)
    scroll:SetScrollChild(child)
    scroll:Hide()

    local bar = CreateFrame("Slider", nil, p, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 10, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 10, 0)
    bar:SetWidth(8)
    Backdrop(bar, { 0.06, 0.055, 0.05, 1 }, { 0.25, 0.2, 0.13, 1 })
    bar:SetOrientation("VERTICAL")
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.75)
    thumb:SetSize(6, 40)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:Hide()
    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)

    local function Range()
        local range = scroll:GetVerticalScrollRange() or 0
        bar:SetMinMaxValues(0, range)
        bar:SetShown(scroll:IsShown() and range > 1)
        local h = scroll:GetHeight() or 0
        if h > 0 then thumb:SetHeight(math.max(24, (h - 2) * h / (h + range))) end
        if bar:GetValue() > range then bar:SetValue(range) end
    end
    scroll:SetScript("OnScrollRangeChanged", Range)
    scroll:SetScript("OnShow", Range)
    scroll:SetScript("OnHide", function() bar:Hide() end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local lo, hi = bar:GetMinMaxValues()
        bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 48)))
    end)

    pages[key] = { scroll = scroll, child = child, bar = bar }
    return child
end

local function BuildFieldPages(p)
    for _, s in ipairs(NS.SECTIONS) do
        if s.key ~= "looks" and s.key ~= "changes" then
            local child = NewPage(p, s.key)
            local y = -6
            local title = Label(child, s.label, "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 10, y)
            title:SetTextColor(unpack(GOLD))
            y = y - 30
            for _, f in ipairs(NS.FIELDS) do
                if f.section == s.key then
                    y = y - BuildRow(child, f, y) - 4
                end
            end
            if s.key == "general" then
                local note = Label(child, "Portraits are added to the game's own raid-style party frames, so everything else stays exactly as the game draws it: buffs, debuffs, dispel highlights and big defensives.\n\nTo turn raid-style party frames on, open Edit Mode, select the party frames and tick \"Use Raid-Style Party Frames\". The frames' width, height, sort order, horizontal layout, border, frame size, opacity and buff and icon sizes also stay in Edit Mode, and the portraits follow them.\n\nType /rpt to open this window, or /rpt debug if portraits aren't showing.", "GameFontHighlightSmall")
                note:SetPoint("TOPLEFT", 12, y - 8)
                note:SetWidth(CONTENT_W - 40)
                note:SetTextColor(0.7, 0.7, 0.7)
                y = y - 140
            end
            child:SetHeight(-y + 10)
        end
    end
end

-- Saved looks: built-in presets plus the player's own, stored account-wide.
local function LookValues()
    local t = {}
    for _, f in ipairs(NS.FIELDS) do
        if NS.IsLookKey(f.key) then t[f.key] = NS.Copy(NS.db[f.key]) end
    end
    return t
end

local function ApplyPreset(preset)
    local values = {}
    for _, f in ipairs(NS.FIELDS) do
        if NS.IsLookKey(f.key) then values[f.key] = NS.DEFAULTS[f.key] end
    end
    for k, v in pairs(preset.values) do values[k] = v end
    NS.ChangeMany(values)
    NS.Print("applied the \"" .. preset.name .. "\" look.")
end

StaticPopupDialogs["RAIDPORTRAITS_DELETE_LOOK"] = {
    text = "Delete the saved look \"%s\"?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data)
        RaidPortraitsLooks[data] = nil
        NS.RefreshDesigner()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["RAIDPORTRAITS_RESET_ALL"] = {
    text = "Reset every RaidPortraits style setting to its default?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        local values = {}
        for _, f in ipairs(NS.FIELDS) do
            if NS.IsLookKey(f.key) then values[f.key] = NS.DEFAULTS[f.key] end
        end
        NS.ChangeMany(values)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function BuildLooksPage(p)
    local child = NewPage(p, "looks")
    local y = -6
    local title = Label(child, "Saved looks", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, y)
    title:SetTextColor(unpack(GOLD))
    y = y - 30

    local sub = Label(child, "BUILT-IN", "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT", 12, y)
    sub:SetTextColor(unpack(GOLD))
    y = y - 20
    for _, preset in ipairs(NS.PRESETS) do
        local b = Button(child, "Apply", 70, function() ApplyPreset(preset) end)
        b:SetPoint("TOPLEFT", 12, y)
        local n = Label(child, preset.name, "GameFontNormal")
        n:SetPoint("LEFT", b, "RIGHT", 10, 0)
        n:SetWidth(120)
        local d = Label(child, preset.desc, "GameFontHighlightSmall")
        d:SetPoint("LEFT", n, "RIGHT", 6, 0)
        d:SetTextColor(0.75, 0.75, 0.75)
        y = y - 28
    end
    local note = Label(child, "Built-in looks change every section except General.", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 12, y - 2)
    note:SetWidth(CONTENT_W - 40)
    note:SetTextColor(0.7, 0.7, 0.7)
    y = y - 30

    local sub2 = Label(child, "YOUR LOOKS  (shared by all your characters)", "GameFontNormalSmall")
    sub2:SetPoint("TOPLEFT", 12, y)
    sub2:SetTextColor(unpack(GOLD))
    y = y - 22

    local box = CreateFrame("EditBox", nil, child, "InputBoxTemplate")
    box:SetSize(220, 22)
    box:SetPoint("TOPLEFT", 18, y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    local save = Button(child, "Save current look", 140, function()
        local name = strtrim(box:GetText() or "")
        if name == "" then NS.Print("type a name for the look first.") return end
        RaidPortraitsLooks[name] = { values = LookValues(), saved = time() }
        box:SetText("")
        box:ClearFocus()
        NS.Print("saved the look \"" .. name .. "\".")
        NS.RefreshDesigner()
    end)
    save:SetPoint("LEFT", box, "RIGHT", 8, 0)
    box:SetScript("OnEnterPressed", function() save:Click() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    y = y - 34

    local listTop = y
    local pool = {}
    local empty = Label(child, "No saved looks yet. Name your current design above and save it.", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", 14, listTop)
    empty:SetTextColor(0.6, 0.6, 0.6)

    dynamic.looks = function()
        local names = {}
        for name in pairs(RaidPortraitsLooks) do names[#names + 1] = name end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        empty:SetShown(#names == 0)
        for i, name in ipairs(names) do
            local r = pool[i]
            if not r then
                r = CreateFrame("Frame", nil, child)
                r:SetSize(CONTENT_W - 30, 26)
                r.load = Button(r, "Load", 60, function()
                    local look = RaidPortraitsLooks[r.name]
                    if look then NS.ChangeMany(look.values) NS.Print("loaded \"" .. r.name .. "\".") end
                end)
                r.load:SetPoint("LEFT", 0, 0)
                r.del = Button(r, "Delete", 60, function()
                    StaticPopup_Show("RAIDPORTRAITS_DELETE_LOOK", r.name, nil, r.name)
                end)
                r.del:SetPoint("LEFT", r.load, "RIGHT", 4, 0)
                r.text = Label(r, "", "GameFontNormal")
                r.text:SetPoint("LEFT", r.del, "RIGHT", 10, 0)
                pool[i] = r
            end
            r.name = name
            r.text:SetText(name)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 12, listTop - (i - 1) * 28)
            r:Show()
        end
        for i = #names + 1, #pool do pool[i]:Hide() end
        child:SetHeight(-listTop + math.max(#names, 1) * 28 + 20)
    end
end

local function BuildChangesPage(p)
    local child = NewPage(p, "changes")
    local title = Label(child, "Changes from the defaults", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -6)
    title:SetTextColor(unpack(GOLD))
    local resetAll = Button(child, "Reset all styling", 130, function() StaticPopup_Show("RAIDPORTRAITS_RESET_ALL") end)
    resetAll:SetPoint("TOPRIGHT", child, "TOPRIGHT", -16, -6)

    local empty = Label(child, "Everything is at its default.", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", 14, -40)
    empty:SetTextColor(0.6, 0.6, 0.6)
    local pool = {}

    dynamic.changes = function()
        local n = 0
        for _, f in ipairs(NS.FIELDS) do
            if not IsDefault(f.key) then
                n = n + 1
                local r = pool[n]
                if not r then
                    r = CreateFrame("Frame", nil, child)
                    r:SetSize(CONTENT_W - 30, 24)
                    r.reset = CreateFrame("Button", nil, r)
                    r.reset:SetSize(16, 16)
                    r.reset:SetPoint("LEFT", 0, 0)
                    r.reset:SetNormalTexture(REFRESH_ICON)
                    r.reset:SetHighlightTexture(REFRESH_ICON)
                    r.reset:SetScript("OnClick", function() NS.Change(r.key, NS.DEFAULTS[r.key]) end)
                    Tooltip(r.reset, "Reset to default")
                    r.section = Label(r, "", "GameFontHighlightSmall")
                    r.section:SetPoint("LEFT", r.reset, "RIGHT", 8, 0)
                    r.section:SetWidth(110)
                    r.section:SetTextColor(unpack(GOLD))
                    r.text = Label(r, "", "GameFontHighlight")
                    r.text:SetPoint("LEFT", r.section, "RIGHT", 6, 0)
                    pool[n] = r
                end
                r.key = f.key
                r.section:SetText(SectionLabel(f.section))
                r.text:SetText(f.label .. ":  |cffffd200" .. ValueText(f, NS.db[f.key]) ..
                    "|r  |cff888888(default " .. ValueText(f, NS.DEFAULTS[f.key]) .. ")|r")
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 12, -40 - (n - 1) * 26)
                r:Show()
            end
        end
        for i = n + 1, #pool do pool[i]:Hide() end
        empty:SetShown(n == 0)
        child:SetHeight(60 + n * 26)
    end
end

------------------------------------------------------------------------
-- Navigation and search
------------------------------------------------------------------------

local function SectionMatchCount(key)
    local n = 0
    for _, f in ipairs(NS.FIELDS) do
        if f.section == key and Matches(f) then n = n + 1 end
    end
    return n
end

local function SectionChangeCount(key)
    local n = 0
    for _, f in ipairs(NS.FIELDS) do
        if f.section == key and not IsDefault(f.key) then n = n + 1 end
    end
    return n
end

local function SelectSection(key)
    current = key
    for k, page in pairs(pages) do page.scroll:SetShown(k == key) end
    designer.resetSection:SetShown(key ~= "looks" and key ~= "changes")
    NS.RefreshDesigner()
end

local function RefreshNav()
    for _, b in ipairs(navButtons) do
        local key = b.key
        local selected = key == current
        b.selected:SetShown(selected)
        local extra = ""
        if key == "changes" then
            local total = 0
            for _, f in ipairs(NS.FIELDS) do if not IsDefault(f.key) then total = total + 1 end end
            if total > 0 then extra = "  |cffffd200" .. total .. "|r" end
        elseif key ~= "looks" then
            if SectionChangeCount(key) > 0 then extra = "  |cff888888•|r" end
        end
        b.text:SetText(b.label .. extra)
        local dim = query ~= "" and key ~= "looks" and key ~= "changes" and SectionMatchCount(key) == 0
        b:SetAlpha(dim and 0.35 or 1)
        if selected then b.text:SetTextColor(unpack(GOLD)) else b.text:SetTextColor(0.9, 0.9, 0.9) end
    end
end

local function OnSearch(text)
    query = strtrim((text or ""):lower())
    if query ~= "" and current ~= "looks" and current ~= "changes" and SectionMatchCount(current) == 0 then
        for _, s in ipairs(NS.SECTIONS) do
            if s.key ~= "looks" and s.key ~= "changes" and SectionMatchCount(s.key) > 0 then
                SelectSection(s.key)
                return
            end
        end
    end
    NS.RefreshDesigner()
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

function NS.CreateDesigner()
    local p = CreateFrame("Frame", "RaidPortraitsDesigner", UIParent, "BackdropTemplate")
    designer = p
    p:SetSize(W, H)
    p:SetPoint("CENTER")
    p:SetScale(math.min(1, (UIParent:GetHeight() - 40) / H))
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    Backdrop(p, { 0.035, 0.033, 0.032, 0.98 }, { 0.42, 0.34, 0.22, 1 })
    p:Hide()
    -- Escape closes the window. This is done with the window's own key handler
    -- rather than Blizzard's UISpecialFrames list: on this client the Escape /
    -- game menu code is protected, and an add-on entry in that list taints it
    -- ("blocked from an action only available to the Blizzard UI").
    -- SetPropagateKeyboardInput is off-limits in combat, so it's only changed
    -- outside combat; other keys always pass through to the game.
    p:EnableKeyboard(true)
    p:SetScript("OnKeyDown", function(self, key)
        local escape = key == "ESCAPE"
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(not escape) end
        if escape then self:Hide() end
    end)

    local title = Label(p, "RaidPortraits", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetTextColor(unpack(GOLD))
    local sub = Label(p, "RAID-STYLE PARTY FRAME PORTRAITS", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetTextColor(0.7, 0.62, 0.45)

    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Search
    local ok, search = pcall(CreateFrame, "EditBox", "RaidPortraitsDesignerSearch", p, "SearchBoxTemplate")
    if not ok then
        search = CreateFrame("EditBox", "RaidPortraitsDesignerSearch", p, "InputBoxTemplate")
    end
    search:SetSize(220, 22)
    search:SetPoint("TOPRIGHT", -44, -18)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self) OnSearch(self:GetText()) end)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    if search.Instructions then search.Instructions:SetText("Search settings") end
    Tooltip(search, "Search", "Type to find a setting. Sections without a match fade out, and the open section dims settings that don't match.")

    -- Sidebar
    local nav = CreateFrame("Frame", nil, p, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 12, -64)
    nav:SetPoint("BOTTOMLEFT", 12, 12)
    nav:SetWidth(NAV_W)
    Backdrop(nav, { 0.06, 0.055, 0.05, 1 }, { 0.25, 0.2, 0.13, 1 })
    local navY = -6
    for _, s in ipairs(NS.SECTIONS) do
        local b = CreateFrame("Button", nil, nav)
        b:SetSize(NAV_W - 8, 31)
        if s.divider then
            local line = nav:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(0.42, 0.34, 0.22, 0.6)
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", 10, navY - 5)
            line:SetPoint("TOPRIGHT", -10, navY - 5)
            navY = navY - 11
        end
        b:SetPoint("TOPLEFT", 4, navY)
        navY = navY - 33
        b.selected = b:CreateTexture(nil, "BACKGROUND")
        b.selected:SetAllPoints()
        b.selected:SetColorTexture(0.42, 0.34, 0.22, 0.45)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexture(s.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.text = Label(b, s.label, "GameFontHighlight")
        b.text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        b.key, b.label = s.key, s.label
        b:SetScript("OnClick", function() SelectSection(s.key) end)
        navButtons[#navButtons + 1] = b
    end

    BuildPreview(p)
    BuildFieldPages(p)
    BuildLooksPage(p)
    BuildChangesPage(p)

    -- Footer
    p.resetSection = Button(p, "Reset this section", 140, function()
        local values = {}
        for _, f in ipairs(NS.FIELDS) do
            if f.section == current then values[f.key] = NS.DEFAULTS[f.key] end
        end
        NS.ChangeMany(values)
    end)
    p.resetSection:SetPoint("BOTTOMLEFT", CONTENT_X, 14)
    p.status = Label(p, "", "GameFontHighlightSmall")
    p.status:SetPoint("LEFT", p.resetSection, "RIGHT", 14, 0)
    p.status:SetTextColor(0.65, 0.65, 0.65)

    local peek = Button(p, "Hold to peek", 110, nil)
    peek:SetPoint("BOTTOMRIGHT", -16, 14)
    peek:SetScript("OnMouseDown", function() p:SetAlpha(0.05) end)
    peek:SetScript("OnMouseUp", function() p:SetAlpha(1) end)
    Tooltip(peek, "Peek at your screen", "Hold to make this window see-through, so you can check the portraits on your real party frames.")

    p:SetScript("OnShow", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        preview.layout = RealLayout() or preview.layout
        NS.RefreshDesigner()
    end)
    p:SetScript("OnHide", function(self)
        self:SetAlpha(1)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)

    -- Entry under Options > AddOns that opens the designer.
    local panel = CreateFrame("Frame")
    panel.name = "RaidPortraits"
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 20, -20)
    t:SetText("RaidPortraits")
    local d = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
    d:SetText("Portraits for raid-style party frames, with a live preview.")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -16)
    open:SetSize(240, 30)
    open:SetText("Open the RaidPortraits designer")
    open:SetScript("OnClick", function() NS.OpenDesigner() end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "RaidPortraits")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    SelectSection("portrait")
end

function NS.RefreshDesigner()
    if not designer or not designer:IsShown() then return end
    refreshing = true
    for _, r in ipairs(rows) do
        if r.field.section == current then UpdateRow(r) end
    end
    if current == "looks" and dynamic.looks then dynamic.looks() end
    if current == "changes" and dynamic.changes then dynamic.changes() end
    RefreshNav()
    RefreshPreview()
    designer.status:SetText("Changes save and apply instantly. Hover any setting for details.")
    refreshing = false
end

function NS.OpenDesigner()
    if not designer then return end
    -- The Options window is left open (closing Blizzard panels from add-on
    -- code taints them too); the designer draws above it.
    designer:Raise()
    designer:Show()
end
