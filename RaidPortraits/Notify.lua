-- Chat notices: what's new after an update, and a patch-available warning when
-- a guild or group member runs a newer RaidPortraits. Versions are shared over a
-- hidden addon channel, since add-ons cannot check CurseForge themselves.
local ADDON, NS = ...
local PREFIX = "RPTVersion"
local Secret = NS.Secret

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
NS.version = (getMeta and getMeta(ADDON, "Version")) or "0"

-- One short line per release. Shown once, on the first login after updating.
NS.whatsNew = {
    ["1.5.1"] = "Health numbers, clean thin outlines and centred party frames are in /rpt. Also fixes black 3D portraits.",
    ["1.5.0"] = "Fixed party frames getting stuck with a white border or faded colours after joining a group, and the empty row left when your own frame is hidden.",
}

-- "1.10.2" -> 1010002, so versions compare as numbers. Unknown text -> nil.
function NS.VersionNumber(version)
    if type(version) ~= "string" then return nil end
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.?(%d*)$")
    if not major then return nil end
    return tonumber(major) * 1000000 + tonumber(minor) * 1000 + (tonumber(patch) or 0)
end

-- The last version seen is saved for the whole account, so the note shows on the
-- first login after an update and not again on other characters.
-- Returns the note to print, or nil.
function NS.CheckUpdated()
    RaidPortraitsGlobal = type(RaidPortraitsGlobal) == "table" and RaidPortraitsGlobal or {}
    local previous = RaidPortraitsGlobal.lastVersion
    -- Installs from before these notices kept no version: they had settings saved.
    if not previous and type(RaidPortraitsDB) == "table" and next(RaidPortraitsDB) then previous = "1.4.0" end
    RaidPortraitsGlobal.lastVersion = NS.version
    if not previous or previous == NS.version then return nil end
    local note = NS.whatsNew[NS.version]
    return "Updated to " .. NS.version .. "." .. (note and (" " .. note) or "")
end

local registerPrefix = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
local sendMessage = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
local lastSent = {}
local warned = false

local function send(channel)
    if not sendMessage then return end
    local now = GetTime and GetTime() or 0
    if lastSent[channel] and now - lastSent[channel] < 60 then return end
    lastSent[channel] = now
    pcall(sendMessage, PREFIX, NS.version, channel)
end

local function groupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

function NS.BroadcastVersion()
    if IsInGuild and IsInGuild() then send("GUILD") end
    local channel = groupChannel()
    if channel then send(channel) end
end

function NS.ReceiveVersion(prefix, message, channel)
    if Secret(prefix) or Secret(message) or prefix ~= PREFIX then return end
    local theirs, mine = NS.VersionNumber(message), NS.VersionNumber(NS.version)
    if not theirs or not mine or theirs == mine then return end
    if theirs > mine then
        if not warned then
            warned = true
            NS.Print("A patch is available: RaidPortraits " .. message .. " is out (you have " .. NS.version ..
                "). Update it from CurseForge.")
        end
    elseif not Secret(channel) and (channel == "GUILD" or channel == "PARTY" or channel == "RAID"
        or channel == "INSTANCE_CHAT") then
        -- Let someone on an older version know, at most once a minute per channel.
        send(channel)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, a, b, c)
    if event == "ADDON_LOADED" then
        if a ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        if registerPrefix then pcall(registerPrefix, PREFIX) end
        pcall(self.RegisterEvent, self, "CHAT_MSG_ADDON")
        pcall(self.RegisterEvent, self, "GROUP_ROSTER_UPDATE")
        local note = NS.CheckUpdated()
        -- Wait a few seconds so the note is not buried under login spam.
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function()
                if note then NS.Print(note) end
                NS.BroadcastVersion()
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        NS.ReceiveVersion(a, b, c)
    elseif event == "GROUP_ROSTER_UPDATE" then
        NS.BroadcastVersion()
    end
end)
