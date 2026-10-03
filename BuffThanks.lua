-- Buff Thanks 1.3
-- Forever seals the aura caster even out of combat.
-- Identify them from the cast we saw, or from the combat-log chat line.
-- Friendly nameplates have to be on, or a stranger in the world is invisible.

local ADDON = "BuffThanks"
local COOLDOWN = 8
local CAST_WINDOW = 4

local EMOTES = {
    "THANK", "WAVE", "BOW", "SALUTE", "CHEER", "APPLAUSE", "HELLO",
}

local CHAT_EVENTS = {
    "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
    "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
    "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
    "CHAT_MSG_COMBAT_MISC_INFO",
    "CHAT_MSG_SYSTEM",
}

local f = CreateFrame("Frame")
local lastThank = {}
local recentCast = {}
local known = {}
local primed = false

local function Sealed(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function IsFalse(value)
    if value == nil or Sealed(value) then return false end
    return not value
end

local function Debug(msg)
    if BuffThanksDB and BuffThanksDB.debug then
        print("|cff33ff99Buff Thanks|r " .. msg)
    end
end

local function Enabled()
    return not BuffThanksDB or BuffThanksDB.enabled ~= false
end

local function Thank(unit, why)
    if not Enabled() then return end
    if not unit or Sealed(unit) then return end
    if unit ~= "player" and not UnitExists(unit) then
        Debug("unit gone (" .. why .. ")")
        return
    end
    local now = GetTime()
    local key = (unit == "player") and "player" or UnitGUID(unit)
    if Sealed(key) or not key then key = unit end
    if lastThank[key] and (now - lastThank[key]) < COOLDOWN then
        Debug("cooldown " .. tostring(key))
        return
    end
    lastThank[key] = now
    local emote = EMOTES[math.random(#EMOTES)]
    if not pcall(DoEmote, emote, unit) then
        pcall(DoEmote, emote)
    end
    local name = UnitName(unit)
    if Sealed(name) then name = unit end
    print("|cff33ff99Buff Thanks|r " .. emote .. " at " .. tostring(name) .. " (" .. why .. ")")
end

local function IsPlayerUnit(unit)
    if not unit or Sealed(unit) then return false end
    if unit == "player" then return true end
    if not UnitExists(unit) then return false end
    local isPlayer = UnitIsPlayer(unit)
    if Sealed(isPlayer) then return true end
    return isPlayer and true or false
end

local function RecentCaster()
    local now = GetTime()
    local best, bestTime
    for unit, when in pairs(recentCast) do
        if (now - when) <= CAST_WINDOW and IsPlayerUnit(unit) then
            if not bestTime or when > bestTime then
                best, bestTime = unit, when
            end
        elseif (now - when) > 12 then
            recentCast[unit] = nil
        end
    end
    return best
end

local function NoteCast(unit)
    if not IsPlayerUnit(unit) then return end
    recentCast[unit] = GetTime()
    Debug("cast from " .. tostring(unit))
    C_Timer.After(0.4, function() pcall(Scan) end)
end

local function FindByName(name)
    if not name or name == "" then return nil end
    if UnitExists("target") and UnitName("target") == name then return "target" end
    if UnitExists("mouseover") and UnitName("mouseover") == name then return "mouseover" end
    if UnitExists("focus") and UnitName("focus") == name then return "focus" end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitName(u) == name then return u end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) and UnitName(u) == name then return u end
        u = "raid" .. i
        if UnitExists(u) and UnitName(u) == name then return u end
    end
    return nil
end

local function NoteChat(msg)
    if not msg or Sealed(msg) then return end
    Debug("chat: " .. msg)
    local name = msg:match("from ([^%.]+)$") or msg:match("by ([^%.]+)$")
    if not name then return end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local unit = FindByName(name)
    if unit then
        NoteCast(unit)
    else
        Debug("chat names " .. name .. " but they are not a unit")
    end
end

local function ReadInstance(instanceID)
    if not instanceID or Sealed(instanceID) then return nil end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then return nil end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceID)
    if ok then return data end
    return nil
end

local function Consider(id)
    local aura = ReadInstance(id)
    if aura and IsFalse(aura.isFromPlayerOrPlayerPet) then
        Debug("skip " .. id .. " not from a player")
        return
    end
    local src = aura and aura.sourceUnit
    if src and not Sealed(src) and IsPlayerUnit(src) then
        Thank(src, "source")
        return
    end
    local caster = RecentCaster()
    if caster then
        Thank(caster, "recent cast")
        return
    end
    if IsPlayerUnit("target") then
        Thank("target", "target")
        return
    end
    if IsPlayerUnit("mouseover") then
        Thank("mouseover", "mouseover")
        return
    end
    Debug("aura " .. id .. ", caster sealed, no watched player")
end

function Scan()
    if InCombatLockdown() then return end
    if not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL", 40)
    if not ok or not auras or Sealed(auras) then return end
    local seen = {}
    local n = 0
    for _, aura in pairs(auras) do
        if type(aura) == "table" then
            local id = aura.auraInstanceID
            if id and not Sealed(id) then
                seen[id] = true
                n = n + 1
                if primed and not known[id] then
                    known[id] = true
                    Debug("new aura " .. id)
                    Consider(id)
                else
                    known[id] = true
                end
            end
        end
    end
    for id in pairs(known) do
        if not seen[id] then known[id] = nil end
    end
    if not primed then
        primed = true
        Debug("1.3 primed with " .. n .. " buffs")
    end
end

local function Watch(unit)
    if unit and UnitExists(unit) then
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    end
end

local function WatchAll()
    Watch("player")
    Watch("target")
    Watch("focus")
    Watch("mouseover")
    Watch("softfriend")
    Watch("softinteract")
    for i = 1, 4 do Watch("party" .. i) end
    for i = 1, 40 do
        Watch("raid" .. i)
        Watch("nameplate" .. i)
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates and not Sealed(plates) then
            for _, plate in pairs(plates) do
                if plate.namePlateUnitToken then Watch(plate.namePlateUnitToken) end
            end
        end
    end
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end
        BuffThanksDB = BuffThanksDB or {}
        if BuffThanksDB.enabled == nil then BuffThanksDB.enabled = true end
        if BuffThanksDB.debug == nil then BuffThanksDB.debug = true end
        pcall(SetCVar, "nameplateShowFriends", 1)
        print("|cff33ff99Buff Thanks 1.3|r loaded. Friendly nameplates on. /bt debug is " .. (BuffThanksDB.debug and "on" or "off"))
        WatchAll()
        C_Timer.After(1, Scan)
    elseif event == "UNIT_AURA" then
        if ... == "player" then
            Debug("aura event")
            pcall(Scan)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        NoteCast(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Watch(...)
    elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"
        or event == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS"
        or event == "CHAT_MSG_SPELL_SELF_BUFF"
        or event == "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF"
        or event == "CHAT_MSG_COMBAT_MISC_INFO"
        or event == "CHAT_MSG_SYSTEM" then
        NoteChat(...)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_REGEN_ENABLED" then
        WatchAll()
        if event == "PLAYER_REGEN_ENABLED" then C_Timer.After(0.2, Scan) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(lastThank)
        wipe(recentCast)
        wipe(known)
        primed = false
        pcall(SetCVar, "nameplateShowFriends", 1)
        WatchAll()
        C_Timer.After(1, Scan)
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
for i = 1, #CHAT_EVENTS do f:RegisterEvent(CHAT_EVENTS[i]) end
Watch("player")

C_Timer.NewTicker(1, function()
    WatchAll()
    if primed and not InCombatLockdown() then pcall(Scan) end
end)

SLASH_BUFFTHANKS1 = "/bt"
SLASH_BUFFTHANKS2 = "/buffthanks"
SlashCmdList.BUFFTHANKS = function(msg)
    BuffThanksDB = BuffThanksDB or { enabled = true, debug = true }
    msg = (msg or ""):lower()
    if msg == "debug" then
        BuffThanksDB.debug = not BuffThanksDB.debug
        print("|cff33ff99Buff Thanks 1.3|r debug " .. (BuffThanksDB.debug and "on" or "off"))
        return
    end
    if msg == "test" then
        DoEmote("WAVE", "player")
        print("|cff33ff99Buff Thanks 1.3|r test wave.")
        return
    end
    BuffThanksDB.enabled = not BuffThanksDB.enabled
    print("|cff33ff99Buff Thanks 1.3|r " .. (BuffThanksDB.enabled and "on" or "off"))
end
