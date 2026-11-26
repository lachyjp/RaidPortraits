-- RaidPortraits: adds portraits to the game's raid-style party frames (and,
-- optionally, raid frames).
--
-- Blizzard's compact unit frames are protected, so this add-on never moves,
-- resizes or changes them. It only hangs its own (unprotected) portrait frames
-- off them and listens with hooksecurefunc, which is safe in combat.
--
-- In combat this client may hand add-ons "secret" values. Everything that can
-- be secret is checked with NS.Secret and falls back to secret-safe setters.
--
-- Schema.lua holds the settings, Portrait.lua draws a portrait, Designer.lua is
-- the options window.

local ADDON, NS = ...
local Secret = NS.Secret

local db
local portraits = {}     -- Blizzard compact frame -> our portrait (kept out of Blizzard's tables to avoid taint)

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffRaidPortraits|r: " .. msg)
end
NS.Print = Print

------------------------------------------------------------------------
-- Which frames get portraits
------------------------------------------------------------------------

-- "party" for raid-style party frames, "raid" for raid frames, nil otherwise
-- (nameplates and other compact frames have no name and are skipped).
-- The same Blizzard functions run for nameplates, some of which are forbidden
-- to add-ons (even GetName errors), so those are skipped first.
local function Kind(frame)
    if type(frame) ~= "table" or not frame.GetName then return end
    if frame.namePlateFrame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or type(name) ~= "string" then return end
    if name:find("^CompactPartyFrame") then return "party" end
    if name:find("^CompactRaidFrame%d") or name:find("^CompactRaidGroup%d") then return "raid" end
end

local function UnitOf(frame)
    local unit = frame.displayedUnit or frame.unit
    if type(unit) ~= "string" or Secret(unit) then return end
    return unit
end

local function IsPlayer(unit)
    if unit == "player" then return true end
    if unit:find("^party") then return false end
    local me = UnitIsUnit(unit, "player")
    if Secret(me) then return false end
    return me and true or false
end

local function Wanted(frame, unit)
    if not db.enabled or not unit then return false end
    local kind = Kind(frame)
    if kind == "party" and not db.showParty then return false end
    if kind == "raid" and not db.showRaid then return false end
    if not kind then return false end
    if unit:find("pet") and not db.showPets then return false end
    if not db.showPlayer and IsPlayer(unit) then return false end
    if not db.showOwnFrame and IsPlayer(unit) then return false end
    if db.hideInCombat and NS.inCombat then return false end
    local exists = UnitExists(unit)
    if not Secret(exists) and not exists then return false end
    return true
end

local function Update(frame, reload)
    local P = portraits[frame]
    local unit = UnitOf(frame)
    if not Wanted(frame, unit) then
        if P and P:IsShown() then
            P:Hide()
            if Kind(frame) == "party" then NS.RequestArrange() end
        end
        return
    end
    if not P then
        local ok, made = pcall(NS.CreatePortrait, frame)
        if not ok then return end
        P = made
        portraits[frame] = P
        reload = true
    end
    NS.ApplyPortrait(P, unit, NS.UnitInfo(unit), reload)
    NS.UpdateUnitState(P, unit)
    NS.UpdatePower(P, unit)
    NS.UpdateThreat(P, unit)
    P:Show()
    if Kind(frame) == "party" then NS.RequestArrange() end
end

-- Party portraits in "own column / row" mode depend on every party frame's
-- position, so they're re-arranged together, once per frame at most.
local arrangePending = false
local function ArrangeParty()
    arrangePending = false
    local list = {}
    for frame, P in pairs(portraits) do
        if P:IsShown() and Kind(frame) == "party" and frame:IsShown() then list[#list + 1] = P end
    end
    NS.ArrangeColumn(list)
end

function NS.RequestArrange()
    if arrangePending then return end
    arrangePending = true
    if C_Timer and C_Timer.After then C_Timer.After(0, ArrangeParty) else ArrangeParty() end
end

-- Every compact party/raid frame that exists, once each.
local function ForEachFrame(fn)
    local seen = {}
    local function visit(f)
        if f and not seen[f] then seen[f] = true fn(f) end
    end
    for i = 1, 5 do
        visit(_G["CompactPartyFrameMember" .. i])
        visit(_G["CompactPartyFramePet" .. i])
    end
    for i = 1, 40 do visit(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do
        for m = 1, 5 do visit(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
    end
    for f in pairs(portraits) do visit(f) end
end

------------------------------------------------------------------------
-- Health bar styling
------------------------------------------------------------------------

-- What each restyled bar looked like before we touched it, so turning the
-- styling off puts the game's look back. Kept here, not on Blizzard's frames.
local original = setmetatable({}, { __mode = "k" })

local function KindWanted(frame)
    local kind = Kind(frame)
    if kind == "party" then return db.showParty end
    if kind == "raid" then return db.showRaid end
    return false
end

local function Restore(frame)
    local bar, o = frame.healthBar, original[frame]
    if not o then return end
    original[frame] = nil
    if o.tex then bar:SetStatusBarTexture(o.tex) end
    bar:SetStatusBarColor(o.r, o.g, o.b)
    local bg = frame.background
    if bg and o.bg then bg:SetVertexColor(o.bg[1], o.bg[2], o.bg[3], o.bg[4]) end
end

local function StyleHealth(frame)
    local bar = frame.healthBar
    if not bar or not bar.SetStatusBarColor then return end
    local unit = UnitOf(frame)
    if not (db.enabled and db.healthStyle and unit and KindWanted(frame)) then return Restore(frame) end

    if not original[frame] then
        local t = bar:GetStatusBarTexture()
        local r, g, b = bar:GetStatusBarColor()
        local o = { tex = t and t:GetTexture(), r = r, g = g, b = b }
        local bg = frame.background
        if bg and bg.GetVertexColor then o.bg = { bg:GetVertexColor() } end
        original[frame] = o
    end

    -- "Game default" texture: put back the one the game used.
    if not NS.HEALTH_TEXTURES[db.healthTexture] and original[frame].tex then
        bar:SetStatusBarTexture(original[frame].tex)
    end

    -- Dead and offline players keep the game's grey (only the texture changes).
    local dead, online = UnitIsDeadOrGhost(unit), UnitIsConnected(unit)
    local out = (not Secret(dead) and dead) or (not Secret(online) and not online)
    if out then
        local file = NS.HEALTH_TEXTURES[db.healthTexture]
        if file then bar:SetStatusBarTexture(file) end
    else
        NS.PaintHealthBar(bar, NS.HealthColor(NS.UnitInfo(unit), NS.HealthPct(unit)))
    end

    local bg, o = frame.background, original[frame]
    if bg and bg.SetVertexColor then
        if db.healthBg then
            local c = db.healthBgColor
            bg:SetVertexColor(c[1], c[2], c[3], db.healthBgAlpha)
        elseif o.bg then
            bg:SetVertexColor(o.bg[1], o.bg[2], o.bg[3], o.bg[4])
        end
    end
end

-- Health numbers on the frame (see HealthBars.lua).
local function HealthText(frame)
    if Kind(frame) then NS.UpdateHealthText(frame, UnitOf(frame), KindWanted(frame)) end
end

-- The "Party" / "Group N" labels above the frames. Only their alpha is
-- changed (never shown/hidden), which add-ons may do even in combat.
local function Titles()
    local show = not db.enabled or db.showGroupTitle
    local function apply(group)
        local t = group and group.title
        if t and t.SetAlpha then t:SetAlpha(show and 1 or 0) end
    end
    apply(_G.CompactPartyFrame)
    for i = 1, 8 do apply(_G["CompactRaidGroup" .. i]) end
end

------------------------------------------------------------------------
-- Hiding your own frame
------------------------------------------------------------------------

-- Your own frame is made invisible (alpha 0), click-through and parked off
-- screen (see Reflow), and the other frames are closed up over its slot. It is never Hidden or Shown by this
-- add-on: doing that runs Blizzard's OnShow / OnHide code from add-on code,
-- which taints the frame. Tainted frames then stop updating properly (stuck
-- white target border, faded colours) until /reload.
-- Alpha may be changed at any time. Mouse and anchors only out of combat, so a
-- change during combat finishes when it ends.
local selfHidden = setmetatable({}, { __mode = "k" })   -- frames we've hidden
NS.selfHidden = selfHidden

-- true / false, or nil when the game won't say (secret, in combat).
local function IsMe(unit)
    if unit == "player" then return true end
    -- Party tokens never mean you (you are "player"). Answering from the token
    -- matters in combat, where the game's answer is secret.
    if unit:find("^party") then return false end
    local me = UnitIsUnit(unit, "player")
    if Secret(me) then return nil end
    return me and true or false
end

local function SetMouse(frame, on)
    if InCombatLockdown() or not frame.EnableMouse then return false end
    frame:EnableMouse(on)
    return true
end

local function ApplyOwnFrame(frame)
    if not Kind(frame) then return end
    local unit = UnitOf(frame)
    local me = unit and IsMe(unit)
    if unit and me == nil then return end   -- can't tell: leave it as it is
    local hide = db.enabled and not db.showOwnFrame and me
    if hide then
        frame:SetAlpha(0)
        if not selfHidden[frame] then
            -- "mouse": still clickable (combat), retried when combat ends.
            selfHidden[frame] = SetMouse(frame, false) and true or "mouse"
            if NS.SpaceParty then NS.SpaceParty() end
        elseif selfHidden[frame] == "mouse" then
            if SetMouse(frame, false) then selfHidden[frame] = true end
        end
    elseif selfHidden[frame] then
        -- Shows someone else now (the group re-sorted), or the setting changed.
        -- (Alpha only when it's still at our 0, so the game's range fading stays.)
        local a = frame:GetAlpha()
        if not Secret(a) and a < 0.01 then frame:SetAlpha(1) end
        if InCombatLockdown() then return end
        selfHidden[frame] = nil
        SetMouse(frame, true)
        if NS.SpaceParty then NS.SpaceParty() end
    end
end

-- Clean outlines: the game's target (selectionHighlight) and threat
-- (aggroHighlight) outlines are drawn from a texture with square nubs at the
-- corners, under the health bar. With "cleanOutlines" on, we read what the
-- game just decided (right after its own update, through hooks), hide its
-- textures and draw plain thin edges of our own on top of the health bar.
-- Textures have no scripts, so hiding them from here taints nothing.
local outl = setmetatable({}, { __mode = "k" })
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function NewEdges(parent)
    local e = {}
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(WHITE)
        e[i] = t
    end
    return e
end

local function PlaceEdges(e, box, inset, size)
    local t, b, l, r = e[1], e[2], e[3], e[4]
    for i = 1, 4 do e[i]:ClearAllPoints() end
    t:SetPoint("TOPLEFT", box, "TOPLEFT", inset, -inset)
    t:SetPoint("TOPRIGHT", box, "TOPRIGHT", -inset, -inset)
    t:SetHeight(size)
    b:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", inset, inset)
    b:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -inset, inset)
    b:SetHeight(size)
    l:SetPoint("TOPLEFT", t, "BOTTOMLEFT")
    l:SetPoint("BOTTOMLEFT", b, "TOPLEFT")
    l:SetWidth(size)
    r:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT")
    r:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT")
    r:SetWidth(size)
end

local function ColorEdges(e, r, g, b, a)
    for i = 1, 4 do e[i]:SetVertexColor(r, g, b, a or 1) end
end

local function Outline(frame)
    local o = outl[frame]
    if not o then o = {} outl[frame] = o end
    return o
end

local function CleanWanted(frame)
    return db.enabled and db.cleanOutlines and KindWanted(frame) and true or false
end

local function DrawOutlines(frame)
    local o = outl[frame]
    if not CleanWanted(frame) then
        if o and o.box then o.box:Hide() end
        return
    end
    o = Outline(frame)
    if not o.box then
        o.box = CreateFrame("Frame", nil, frame)
        o.box:SetAllPoints(frame)
        o.threat = CreateFrame("Frame", nil, o.box)
        o.threat:SetAllPoints(o.box)
        o.target = CreateFrame("Frame", nil, o.box)
        o.target:SetAllPoints(o.box)
        o.threatEdges = NewEdges(o.threat)
        o.targetEdges = NewEdges(o.target)
    end
    local bar = frame.healthBar
    o.box:SetFrameLevel(((bar and bar:GetFrameLevel()) or frame:GetFrameLevel()) + 4)
    local size = db.outlineSize or 1
    PlaceEdges(o.threatEdges, o.box, 0, size)
    PlaceEdges(o.targetEdges, o.box, o.aggro and size or 0, size)
    -- Threat: the game's own colour and alpha (either may be secret).
    o.threat:SetShown(o.aggro and true or false)
    if o.aggro then
        if o.ar then pcall(ColorEdges, o.threatEdges, o.ar, o.ag, o.ab) end
        if o.aa ~= nil then pcall(o.threat.SetAlpha, o.threat, o.aa) end
    end
    local c = db.outlineTargetColor or { 1, 1, 1 }
    ColorEdges(o.targetEdges, c[1], c[2], c[3])
    o.target:SetShown((o.sel and not db.hideGameOutline) and true or false)
    o.box:Show()
end
NS.DrawOutlines = DrawOutlines

-- After the game's selection update: remember its answer, then hide its texture.
local function AfterSelection(frame, fromHook)
    local hl = rawget(frame, "selectionHighlight")
    if type(hl) ~= "table" or not hl.IsShown then return end
    if not fromHook and CleanWanted(frame) then
        -- Not straight after the game's update: its texture may be one we hid,
        -- so ask the game directly (keep the last answer while it's secret).
        local unit = UnitOf(frame)
        local isTarget = unit and UnitIsUnit(unit, "target")
        if not Secret(isTarget) then Outline(frame).sel = isTarget and true or false end
        if hl:IsShown() then hl:Hide() end
        DrawOutlines(frame)
        return
    end
    local o = outl[frame]
    if not fromHook and o and o.sel and not hl:IsShown() and not (db.enabled and db.hideGameOutline) then
        -- Clean outlines just turned off: give the game its outline back.
        local unit = UnitOf(frame)
        local isTarget = unit and UnitIsUnit(unit, "target")
        if not Secret(isTarget) and isTarget then hl:Show() end
        o.sel = nil
    end
    local shown = hl:IsShown()
    if shown then
        -- Guard against a stale outline on someone who isn't your target.
        local unit = UnitOf(frame)
        local isTarget = unit and UnitIsUnit(unit, "target")
        if not Secret(isTarget) and not isTarget then shown = false hl:Hide() end
    end
    if CleanWanted(frame) then
        Outline(frame).sel = shown
        hl:Hide()
    elseif shown and db.enabled and db.hideGameOutline then
        hl:Hide()
    end
    DrawOutlines(frame)
end

local function AfterAggro(frame, fromHook)
    local hl = rawget(frame, "aggroHighlight")
    if type(hl) ~= "table" or not hl.IsShown then return end
    -- Outside the game's update a hidden texture may be one we hid: only a
    -- shown one is news.
    if not fromHook and CleanWanted(frame) and not hl:IsShown() then DrawOutlines(frame) return end
    if not CleanWanted(frame) then
        local o = outl[frame]
        if o and o.hidAggro then
            -- Turned off: let the game's own outline show again on its next update.
            o.hidAggro = nil
            if o.aggro then hl:Show() end
        end
        DrawOutlines(frame)
        return
    end
    local o = Outline(frame)
    o.aggro = hl:IsShown()
    if o.aggro then
        o.ar, o.ag, o.ab = hl:GetVertexColor()
        o.aa = hl:GetAlpha()
        hl:Hide()
        o.hidAggro = true
    end
    DrawOutlines(frame)
end

local function ClearStuckHighlight(frame)
    AfterSelection(frame)
    AfterAggro(frame)
end

local function RefreshAll(reload)
    Titles()
    ForEachFrame(function(f)
        ApplyOwnFrame(f)
        Update(f, reload)
        if Kind(f) then StyleHealth(f) ClearStuckHighlight(f) HealthText(f) end
    end)
end
NS.RefreshAll = RefreshAll

-- Portraits currently showing unit (by token).
local function ForUnit(unit, fn)
    if not unit or Secret(unit) then return end
    for frame, P in pairs(portraits) do
        if P:IsShown() and P.unit == unit then fn(frame, P) end
    end
end

------------------------------------------------------------------------
-- Gap between party frames
------------------------------------------------------------------------

-- Blizzard stacks the party members edge to edge (CompactRaidGroup_UpdateLayout).
-- They are secure buttons, which add-ons may only move out of combat, so the
-- gap is applied after each Blizzard layout pass when not in combat, and again
-- when combat ends.
-- The same pass also closes the gap left by your own frame when it's hidden
-- (party frames, and raid frames with "Keep Groups Together").
local spacingPending = false
local layoutDir, touched = {}, {}   -- per group: "TOP" / "LEFT", and whether we moved anything

-- Re-chains one group's five members: gap between them, skipping frames in
-- selfHidden. The first visible member takes the group's first slot.
-- Your hidden frame is parked off screen, so nothing of it can show through
-- (the game sometimes puts its alpha or name text back) or overlap the frame
-- that takes its slot.
local PARK = -3000
local slots = {}   -- per group: the first slot's anchor, remembered while member 1 is parked
local applied = {} -- per group: the first slot we last set, when moved for centre / bottom

local function Parked(m)
    local _, rel, _, x = m:GetPoint(1)
    return rel == UIParent and x == PARK
end

-- Edit Mode open: put every member back in Blizzard's own chain (nothing
-- parked off screen), so dragging and snapping the party frames works on the
-- layout the game expects. Re-applied when Edit Mode closes.
local function EditModeOpen()
    local m = _G.EditModeManagerFrame
    if not m then return false end
    if m.IsEditModeActive then
        local ok, on = pcall(m.IsEditModeActive, m)
        if ok then return on and true or false end
    end
    return m:IsShown() and true or false
end
NS.EditModeOpen = EditModeOpen

local function Reflow(prefix, gap)
    local members = {}
    for i = 1, 5 do members[i] = _G[prefix .. i] end
    if not members[1] then return end
    local editing = EditModeOpen()
    local hiding = false
    if not editing then
        for i = 1, 5 do if members[i] and selfHidden[members[i]] then hiding = true end end
    end
    local anchor = (prefix == "CompactPartyFrameMember" and db.enabled and not editing) and db.partyAnchor or "start"
    if anchor ~= "center" and anchor ~= "end" then anchor = "start" end
    if gap == 0 and not hiding and anchor == "start" and not touched[prefix] then return end
    if InCombatLockdown() then spacingPending = true return end

    -- Blizzard stacks members TOP-to-BOTTOM or LEFT-to-RIGHT. Members we put
    -- in the first slot carry that slot's anchor instead, so look past them.
    local dir
    for i = 2, 5 do
        local p = members[i] and members[i]:GetPoint(1)
        if p == "TOP" or p == "LEFT" then dir = p break end
    end
    dir = dir or layoutDir[prefix]
    if not dir then return end
    layoutDir[prefix] = dir

    -- Remember Blizzard's own first slot: not while member 1 is parked, and not
    -- when it still carries a slot we moved (centre / bottom), or it would creep.
    if not Parked(members[1]) then
        local slot = { members[1]:GetPoint(1) }
        local a = applied[prefix]
        local ours = a and slot[1] == a[1] and slot[2] == a[2] and slot[3] == a[3]
            and math.abs((slot[4] or 0) - a[4]) < 0.5 and math.abs((slot[5] or 0) - a[5]) < 0.5
        if slot[1] and not ours then slots[prefix] = slot end
    end
    local slot = slots[prefix]
    if not slot then return end

    -- Centre / bottom: the box is sized for five, so move the first slot along
    -- by the room the missing members would have taken.
    if anchor ~= "start" then
        local shown = 0
        for i = 1, 5 do
            local m = members[i]
            if m and m:IsShown() and not (selfHidden[m] and not editing) then shown = shown + 1 end
        end
        local size = dir == "TOP" and members[1]:GetHeight() or members[1]:GetWidth()
        local free = (5 - shown) * ((size or 0) + gap)
        if shown > 0 and free > 0 then
            if anchor == "center" then free = free / 2 end
            free = math.floor(free + 0.5)
            slot = { slot[1], slot[2], slot[3], slot[4] or 0, slot[5] or 0 }
            if dir == "TOP" then slot[5] = slot[5] - free else slot[4] = slot[4] + free end
        end
    end
    applied[prefix] = { slot[1], slot[2], slot[3], slot[4] or 0, slot[5] or 0 }

    local prev
    for i = 1, 5 do
        local m = members[i]
        if m and selfHidden[m] and not editing then
            m:ClearAllPoints()
            m:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", PARK, PARK)
        elseif m then
            m:ClearAllPoints()
            if not prev then
                m:SetPoint(unpack(slot))
            elseif dir == "TOP" then
                m:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
            else
                m:SetPoint("LEFT", prev, "RIGHT", gap, 0)
            end
            prev = m
        end
    end
    touched[prefix] = gap > 0 or hiding or anchor ~= "start"
end

local function SpaceParty()
    if not db then return end
    spacingPending = false
    local gap = (db.enabled and db.showParty) and db.spacing or 0
    Reflow("CompactPartyFrameMember", gap)
    for g = 1, 8 do Reflow("CompactRaidGroup" .. g .. "Member", 0) end
    if NS.RequestArrange then NS.RequestArrange() end
end
NS.SpaceParty = SpaceParty

------------------------------------------------------------------------
-- Hooks into Blizzard's compact frames
------------------------------------------------------------------------

local editModeHooked = false
function NS.HookEditMode()
    local emf = _G.EditModeManagerFrame
    if editModeHooked or not (emf and emf.HookScript) then return end
    editModeHooked = true
    local function later() if C_Timer and C_Timer.After then C_Timer.After(0, SpaceParty) else SpaceParty() end end
    emf:HookScript("OnShow", later)
    emf:HookScript("OnHide", later)
end

local function HookFrames()
    if CompactUnitFrame_SetUnit then
        hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
            if Kind(frame) then ApplyOwnFrame(frame) Update(frame, true) end
        end)
    end
    if CompactUnitFrame_UpdateAll then
        hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            if Kind(frame) then ApplyOwnFrame(frame) Update(frame) end
        end)
    end
    -- The game shows frames and sets their (range) alpha in these: hide ours again.
    for _, fn in ipairs({ "CompactUnitFrame_UpdateVisible", "CompactUnitFrame_UpdateInRange" }) do
        if _G[fn] then
            hooksecurefunc(fn, function(frame)
                if frame and selfHidden[frame] or (db and not db.showOwnFrame and frame and Kind(frame)) then
                    ApplyOwnFrame(frame)
                end
            end)
        end
    end
    -- Health bars: re-apply our style right after the game sets its own colour,
    -- texture (frame setup) or, for "By health", the health value.
    for _, fn in ipairs({ "CompactUnitFrame_UpdateHealthColor", "DefaultCompactUnitFrameSetup" }) do
        if _G[fn] then
            hooksecurefunc(fn, function(frame)
                if frame and Kind(frame) then
                    -- After a setup pass the game has put its own texture back:
                    -- remember that one as the original.
                    if fn == "DefaultCompactUnitFrameSetup" and original[frame] then
                        local t = frame.healthBar and frame.healthBar:GetStatusBarTexture()
                        original[frame].tex = t and t:GetTexture()
                    end
                    StyleHealth(frame)
                end
            end)
        end
    end
    -- The game shows its white target outline here; take it off again when
    -- "Hide the game's target outline" is on (or it's stuck on a non-target).
    if CompactUnitFrame_UpdateAggroHighlight then
        hooksecurefunc("CompactUnitFrame_UpdateAggroHighlight", function(frame)
            if frame and Kind(frame) then pcall(AfterAggro, frame, true) end
        end)
    end
    if CompactUnitFrame_UpdateSelectionHighlight then
        hooksecurefunc("CompactUnitFrame_UpdateSelectionHighlight", function(frame)
            if frame and Kind(frame) then pcall(AfterSelection, frame, true) end
        end)
    end
    if CompactUnitFrame_UpdateHealth then
        hooksecurefunc("CompactUnitFrame_UpdateHealth", function(frame)
            if db.healthStyle and db.healthColorMode == "health" and frame and Kind(frame) then StyleHealth(frame) end
        end)
    end
    -- Health numbers follow every health, max health and status text update.
    for _, fn in ipairs({ "CompactUnitFrame_UpdateHealth", "CompactUnitFrame_UpdateMaxHealth",
                          "CompactUnitFrame_UpdateStatusText" }) do
        if _G[fn] then
            hooksecurefunc(fn, function(frame)
                if frame and db.healthText ~= "none" then pcall(HealthText, frame) end
            end)
        end
    end
    if CompactRaidGroup_UpdateLayout then
        hooksecurefunc("CompactRaidGroup_UpdateLayout", function(frame)
            Titles()
            if frame == _G.CompactPartyFrame and InCombatLockdown() then NS.layoutStale = true end
            SpaceParty()
        end)
    end
    -- Other passes that can re-stack the party frames edge to edge.
    for _, fn in ipairs({ "CompactPartyFrame_RefreshMembers", "CompactPartyFrame_UpdateLayout",
                          "CompactPartyFrame_SetFlowSortFunction" }) do
        if _G[fn] then hooksecurefunc(fn, function() SpaceParty() end) end
    end
    if _G.CompactPartyFrame and CompactPartyFrame.RefreshMembers then
        hooksecurefunc(CompactPartyFrame, "RefreshMembers", function() SpaceParty() end)
    end
    -- Edit Mode opening / closing: unpark / re-park your hidden frame.
    NS.HookEditMode()
    -- Edit Mode's Opacity slider sets the container's alpha. Portraits follow
    -- it automatically, except when range fading is off (see NS.PortraitAlpha).
    for _, name in ipairs({ "CompactPartyFrame", "CompactRaidFrameContainer" }) do
        local container = _G[name]
        if container and container.SetAlpha then
            hooksecurefunc(container, "SetAlpha", function()
                if db.rangeFade then return end
                for _, P in pairs(portraits) do if P:IsShown() then NS.PortraitAlpha(P) end end
            end)
        end
    end
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

local function Refresh()
    SpaceParty()
    RefreshAll()
    if NS.RefreshDesigner then NS.RefreshDesigner() end
end

-- Single entry point for changing a setting, used by the designer and slash commands.
function NS.Change(key, value)
    db[key] = NS.Copy(value)
    Refresh()
end

-- Changes several settings at once (presets, saved looks, resets).
function NS.ChangeMany(values)
    for k, v in pairs(values) do db[k] = NS.Copy(v) end
    Refresh()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

local function Register(event)
    pcall(events.RegisterEvent, events, event)
end

local function ThreatAll()
    if not db.threat then return end
    local enemies
    for _, P in pairs(portraits) do
        if P:IsShown() and P.unit then
            if not enemies and NS.ShowPackThreat(db) then enemies = NS.VisibleThreatEnemies() end
            NS.UpdateThreat(P, P.unit, enemies)
        end
    end
end

function handlers.ADDON_LOADED(name)
    if name == "Blizzard_EditMode" and db then NS.HookEditMode() end
    if name ~= ADDON then return end
    RaidPortraitsDB = RaidPortraitsDB or {}
    RaidPortraitsLooks = RaidPortraitsLooks or {}
    db = RaidPortraitsDB
    -- Pre-release builds had separate frame and portrait spacing; it's one setting now.
    if db.frameSpacing ~= nil then
        db.spacing = db.frameSpacing
        db.frameSpacing = nil
    end
    for k, v in pairs(NS.DEFAULTS) do
        if db[k] == nil then db[k] = NS.Copy(v) end
    end
    NS.db = db
    HookFrames()
    if NS.CreateDesigner then NS.CreateDesigner() end
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
                         "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PORTRAIT_UPDATE",
                         "UNIT_MODEL_CHANGED", "UNIT_HEALTH", "UNIT_CONNECTION", "UNIT_FLAGS",
                         "EDIT_MODE_LAYOUTS_UPDATED", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
                         "UNIT_DISPLAYPOWER", "PLAYER_ROLES_ASSIGNED", "UNIT_NAME_UPDATE",
                         "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }) do
        Register(e)
    end
    -- The game only loads models for nearby players and has no event for
    -- "came into view", so swap between model and fallback every so often.
    if C_Timer and C_Timer.NewTicker then
        -- Keep counts current when an enemy dies, leaves combat or goes out of range.
        C_Timer.NewTicker(0.25, function()
            if db.enabled and NS.ShowPackThreat(db) then ThreatAll() end
        end)
        -- Safety net for your hidden frame: if any layout pass we don't hook put
        -- it back in the column (leaving an invisible row), close it up again.
        C_Timer.NewTicker(0.5, function()
            if InCombatLockdown() or EditModeOpen() then return end
            for f in pairs(selfHidden) do
                if f:IsShown() and not Parked(f) then SpaceParty() return end
            end
        end)
        C_Timer.NewTicker(1.5, function()
            if not db.enabled or db.portraitType ~= "3d" then return end
            for frame, P in pairs(portraits) do
                if P:IsShown() and P.unit then
                    local vis = UnitIsVisible(P.unit)
                    if not Secret(vis) and (vis and true or false) ~= (P.kind == "3d") then
                        Update(frame, true)
                    elseif P.kind == "3d" and P.model.GetModelFileID then
                        -- A model asked for just as the player came into view can
                        -- stay empty (a black square): ask again until it loads.
                        local ok, id = pcall(P.model.GetModelFileID, P.model)
                        if ok and not Secret(id) and (not id or id == 0) then Update(frame, true) end
                    end
                end
            end
        end)
    end
end

function handlers.PLAYER_ENTERING_WORLD()
    SpaceParty()
    RefreshAll(true)
end
-- A member who has just joined can still read as offline or classless for a
-- moment, and the game doesn't always repaint their health bar once the real
-- data arrives (it stays grey until /reload). So look again shortly after.
local rosterPending = false
function handlers.GROUP_ROSTER_UPDATE()
    RefreshAll(true)
    if rosterPending or not (C_Timer and C_Timer.After) then return end
    rosterPending = true
    -- Spacing too: not every client's layout pass goes through the hook below.
    C_Timer.After(1, function() SpaceParty() RefreshAll() end)
    C_Timer.After(3, function() rosterPending = false SpaceParty() RefreshAll() end)
end
-- Edit Mode changes (size, layout, opacity, raid-style on/off): re-fit everything.
function handlers.EDIT_MODE_LAYOUTS_UPDATED()
    if C_Timer then C_Timer.After(0, function() RefreshAll() end) else RefreshAll() end
end
-- Own combat flag: InCombatLockdown() can still be false while PLAYER_REGEN_DISABLED runs.
function handlers.PLAYER_REGEN_DISABLED()
    NS.inCombat = true
    if db.hideInCombat then RefreshAll() end
end
function handlers.PLAYER_REGEN_ENABLED()
    NS.inCombat = false
    NS.layoutStale = false
    if spacingPending then SpaceParty() end
    RefreshAll()
end

function handlers.PLAYER_TARGET_CHANGED()
    ForEachFrame(function(f) if Kind(f) then ClearStuckHighlight(f) end end)
    for _, P in pairs(portraits) do
        if P:IsShown() and P.unit then
            NS.UpdateUnitState(P, P.unit)
        end
    end
    ThreatAll()
end

local function ThreatChanged()
    -- The pack ticker batches threat changes across all nameplates.
    if not NS.ShowPackThreat(db) then
        ThreatAll()
    end
end
handlers.UNIT_THREAT_SITUATION_UPDATE = ThreatChanged
handlers.UNIT_THREAT_LIST_UPDATE = ThreatChanged

local function Reload(unit) ForUnit(unit, function(frame) Update(frame, true) end) end
local function State(unit) ForUnit(unit, function(_, P) NS.UpdateUnitState(P, unit) end) end

-- Repaints the health bar of every frame showing unit (no portrait needed).
local function StyleUnit(unit)
    if not unit or Secret(unit) then return end
    ForEachFrame(function(f)
        if Kind(f) and UnitOf(f) == unit then StyleHealth(f) HealthText(f) end
    end)
end

-- Coming online, dying or reviving changes the bar between our colour and the game's grey.
local function StateAndStyle(unit)
    State(unit)
    StyleUnit(unit)
end

handlers.UNIT_PORTRAIT_UPDATE = Reload
handlers.UNIT_MODEL_CHANGED = Reload
handlers.UNIT_HEALTH = State
handlers.UNIT_CONNECTION = StateAndStyle
handlers.UNIT_FLAGS = StateAndStyle
handlers.UNIT_NAME_UPDATE = function(unit) Reload(unit) StyleUnit(unit) end   -- name / class data arrived

local function Power(unit)
    if not db.power then return end
    ForUnit(unit, function(_, P) NS.UpdatePower(P, unit) end)
end
handlers.UNIT_POWER_FREQUENT = Power
handlers.UNIT_MAXPOWER = Power
handlers.UNIT_DISPLAYPOWER = Power   -- type and colour change (e.g. druid forms)
handlers.PLAYER_ROLES_ASSIGNED = function() RefreshAll() end    -- "only for healers"

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then h(...) end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

local TOGGLES = { on = "enabled", party = "showParty", raid = "showRaid", self = "showPlayer", me = "showOwnFrame", pets = "showPets", combat = "hideInCombat" }

local function OnOff(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end

local function Debug()
    local out = function(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffRPT|r " .. s) end
    out(("enabled=%s group=%s raid=%s combat=%s"):format(tostring(db.enabled), tostring(IsInGroup()),
        tostring(IsInRaid()), tostring(InCombatLockdown())))
    out(("CompactPartyFrame=%s shown=%s"):format(CompactPartyFrame and "yes" or "no",
        CompactPartyFrame and tostring(CompactPartyFrame:IsShown()) or "-"))
    local n = 0
    ForEachFrame(function(f)
        local unit = UnitOf(f)
        local P = portraits[f]
        if unit or P then
            n = n + 1
            out(("%s unit=%s shown=%s alpha=%.2f portrait=%s kind=%s"):format(f:GetName() or "?", tostring(unit),
                tostring(f:IsShown()), f:GetAlpha() or -1, P and (P:IsShown() and "shown" or "hidden") or "none", P and tostring(P.kind) or "-"))
            local bar = f.healthBar
            if bar and unit then
                local r, g, b = bar:GetStatusBarColor()
                local t = bar:GetStatusBarTexture()
                local _, class = UnitClass(unit)
                out(("  bar=%.2f,%.2f,%.2f tex=%s class=%s online=%s dead=%s styled=%s"):format(r or -1, g or -1, b or -1,
                    tostring(t and t:GetTexture()), tostring(class), tostring(UnitIsConnected(unit)),
                    tostring(UnitIsDeadOrGhost(unit)), tostring(original[f] ~= nil)))
            end
        end
    end)
    out(("combat=%s spacingPending=%s dir=%s"):format(tostring(InCombatLockdown()), tostring(spacingPending),
        tostring(layoutDir.CompactPartyFrameMember)))
    for i = 1, 5 do
        local m = _G["CompactPartyFrameMember" .. i]
        if m then
            local p, rel, rp, x, y = m:GetPoint(1)
            out(("  member%d %s -> %s %s (%s,%s) hidden=%s mouse=%s"):format(i, tostring(p),
                rel and rel.GetName and tostring(rel:GetName()) or tostring(rel), tostring(rp), tostring(x), tostring(y),
                tostring(selfHidden[m]), tostring(m:IsMouseEnabled())))
        end
    end
    if n == 0 then out("no raid-style party or raid frames found. Turn on \"Use Raid-Style Party Frames\" in Edit Mode.") end
end

-- /rpt layers: everything drawn on or over each visible party/raid frame, to
-- find what tints a frame or draws an outline on it.
local function Layers(only)
    local out = function(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffRPT|r " .. s) end
    local function n2(v)
        if Secret(v) then return "secret" end
        return type(v) == "number" and ("%.2f"):format(v) or tostring(v)
    end
    local function Keys(f)
        local k = {}
        for key, v in pairs(f) do if type(v) == "table" and type(key) == "string" then k[v] = key end end
        return k
    end
    local function Region(r, keys, indent)
        if not (r.IsShown and r:IsShown()) or not r.IsObjectType or not r:IsObjectType("Texture") then return end
        local a = r:GetAlpha()
        if type(a) == "number" and not Secret(a) and a < 0.03 then return end
        local layer = r:GetDrawLayer()
        local cr, cg, cb, ca = r:GetVertexColor()
        local w, h = r:GetSize()
        if Secret(w) or Secret(h) then w, h = 0, 0 end
        out(("%s%s %s blend=%s a=%s col=%s,%s,%s,%s size=%dx%d tex=%s ipa=%s"):format(indent,
            keys[r] or r:GetName() or "?", tostring(layer), tostring(r:GetBlendMode()), n2(a),
            n2(cr), n2(cg), n2(cb), n2(ca), math.floor((w or 0) + 0.5), math.floor((h or 0) + 0.5),
            tostring(r:GetTexture()), tostring(r.IsIgnoringParentAlpha and r:IsIgnoringParentAlpha())))
    end
    local rects = {}
    ForEachFrame(function(f)
        if not (Kind(f) and f:IsShown() and UnitOf(f)) then return end
        local unitName = UnitName(UnitOf(f))
        if only and only ~= "" and not (Secret(unitName) or tostring(unitName):lower():find(only, 1, true)) then return end
        local keys = Keys(f)
        local ok, l, b, w, h = pcall(f.GetRect, f)
        if ok and l and not (Secret(l) or Secret(b) or Secret(w) or Secret(h)) then rects[#rects + 1] = { f, l, b, w, h } end
        out(("%s unit=%s name=%s alpha=%s eff=%s rect=%s,%s %sx%s"):format(f:GetName() or "?", tostring(UnitOf(f)),
            tostring(UnitName(UnitOf(f))), n2(f:GetAlpha()), n2(f:GetEffectiveAlpha()), n2(l), n2(b), n2(w), n2(h)))
        for _, r in ipairs({ f:GetRegions() }) do pcall(Region, r, keys, "  ") end
        for _, c in ipairs({ f:GetChildren() }) do
            if c:IsShown() then
                local ck = Keys(c)
                for _, r in ipairs({ c:GetRegions() }) do pcall(Region, r, ck, "  " .. (keys[c] or c:GetName() or "child") .. ".") end
            end
        end
    end)
    -- Other add-ons' frames lying over a party frame.
    local f = EnumerateFrames()
    while f do
        if f:IsShown() and not (f.IsForbidden and f:IsForbidden()) and f.GetRect then
            local ok, l, b, w, h = pcall(f.GetRect, f)
            if ok and l and not (Secret(l) or Secret(b) or Secret(w) or Secret(h)) then
                for _, r in ipairs(rects) do
                    if f ~= r[1] and type(r[2]) == "number" and math.abs(l - r[2]) < 4 and math.abs(b - r[3]) < 4 and math.abs(w - r[4]) < 6
                        and math.abs(h - r[5]) < 6 and f:GetParent() ~= r[1] then
                        out(("over %s: %s a=%s strata=%s level=%s"):format(r[1]:GetName() or "?", f:GetName() or tostring(f),
                            n2(f:GetEffectiveAlpha()), tostring(f:GetFrameStrata()), tostring(f:GetFrameLevel())))
                    end
                end
            end
        end
        f = EnumerateFrames(f)
    end
end

SLASH_RAIDPORTRAITS1 = "/raidportraits"
SLASH_RAIDPORTRAITS2 = "/rpt"
SlashCmdList.RAIDPORTRAITS = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" then
        if NS.OpenDesigner then NS.OpenDesigner() end
        return
    end
    if cmd == "layers" then
        local ok, err = pcall(Layers, (msg or ""):lower():match("^%s*%S+%s+(%S+)"))
        if not ok then Print("layers error: " .. tostring(err)) end
        return
    end
    if cmd == "debug" then
        local ok, err = pcall(Debug)
        if not ok then Print("debug error: " .. tostring(err)) end
        return
    end
    local key = TOGGLES[cmd]
    if not key then
        Print("/rpt opens the designer. Quick toggles: /rpt on, party, raid, self, pets, combat. /rpt me shows or hides your own frame. /rpt debug prints diagnostics.")
        return
    end
    NS.Change(key, not db[key])
    Print(("%s %s"):format(cmd, OnOff(db[key])))
end
