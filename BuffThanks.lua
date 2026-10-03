-- Buff Thanks 1.2
-- Emote at whoever just buffed you, including yourself.
-- Forever seals sourceUnit even out of combat. A new aura id plus the
-- cast that just finished is how we identify the caster.

local ADDON = "BuffThanks"
local COOLDOWN = 8
local CAST_WINDOW = 3

local EMOTES = {
    "THANK", "WAVE", "BOW", "SALUTE", "CHEER", "APPLAUSE", "HELLO",
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
    if not unit or Sealed(unit) then
        Debug("no unit (" .. tostring(why) .. ")")
        return
    end
    if unit ~= "player" and not UnitExists(unit) then
        Debug("unit gone (" .. tostring(why) .. ")")
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
    local name = (unit == "player") and UnitName("player") or UnitName(unit)
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
        elseif (now - when) > 10 then
            recentCast[unit] = nil
        end
    end
    return best
end

local function NoteCast(unit)
    if not IsPlayerUnit(unit) then return end
    recentCast[unit] = GetTime()
    Debug("cast from " .. tostring(unit))
    C_Timer.After(0.3, function() pcall(Scan) end)
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
        Debug("skip " .. tostring(id) .. " not from a player")
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
    Debug("new aura " .. tostring(id) .. " and no caster")
end

function Scan()
    if InCombatLockdown() then return end
    if not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL", 40)
    if not ok or not auras or Sealed(auras) then
        Debug("aura list unreadable")
        return
    end
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
                    Debug("new aura " .. tostring(id))
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
        Debug("primed with " .. n .. " buffs")
    end
end

local function Watch(unit)
    if unit then
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    end
end

local function WatchGroup()
    Watch("player")
    Watch("target")
    Watch("focus")
    Watch("mouseover")
    for i = 1, 4 do Watch("party" .. i) end
    for i = 1, 40 do
        Watch("raid" .. i)
        Watch("nameplate" .. i)
    end
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end
        BuffThanksDB = BuffThanksDB or {}
        if BuffThanksDB.enabled == nil then BuffThanksDB.enabled = true end
        if BuffThanksDB.debug == nil then BuffThanksDB.debug = true end
        print("|cff33ff99Buff Thanks|r 1.2 loaded. /bt debug is " .. (BuffThanksDB.debug and "on" or "off"))
        WatchGroup()
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
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_REGEN_ENABLED" then
        WatchGroup()
        if event == "PLAYER_REGEN_ENABLED" then C_Timer.After(0.2, Scan) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(lastThank)
        wipe(recentCast)
        wipe(known)
        primed = false
        WatchGroup()
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
Watch("player")

C_Timer.NewTicker(1, function()
    if primed and not InCombatLockdown() then pcall(Scan) end
end)

SLASH_BUFFTHANKS1 = "/bt"
SLASH_BUFFTHANKS2 = "/buffthanks"
SlashCmdList.BUFFTHANKS = function(msg)
    BuffThanksDB = BuffThanksDB or { enabled = true, debug = true }
    msg = (msg or ""):lower()
    if msg == "debug" then
        BuffThanksDB.debug = not BuffThanksDB.debug
        print("|cff33ff99Buff Thanks|r debug " .. (BuffThanksDB.debug and "on" or "off"))
        return
    end
    if msg == "test" then
        DoEmote("WAVE", "player")
        print("|cff33ff99Buff Thanks|r test wave.")
        return
    end
    BuffThanksDB.enabled = not BuffThanksDB.enabled
    print("|cff33ff99Buff Thanks|r " .. (BuffThanksDB.enabled and "on" or "off"))
end
