-- Buff Thanks
-- When a friendly player applies a helpful aura to you, emote back at that player.
-- Forever seals aura flags and often seals sourceUnit. Do not boolean-test those.
-- Out of combat, re-read the aura and also credit a player who just finished a cast.

local ADDON = "BuffThanks"
local COOLDOWN = 20
local CAST_WINDOW = 2.5

local EMOTES = {
    "THANK",
    "WAVE",
    "BOW",
    "SALUTE",
    "CHEER",
    "APPLAUSE",
    "HELLO",
}

local f = CreateFrame("Frame")
local lastThank = {}
local recentCast = {}
local known = {}
local watched = {}

local function Sealed(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function IsTrue(value)
    if value == nil or Sealed(value) then return false end
    return value and true or false
end

local function IsFalse(value)
    if value == nil or Sealed(value) then return false end
    return not value
end

local function Enabled()
    return not BuffThanksDB or BuffThanksDB.enabled ~= false
end

local function Thank(unit)
    if not Enabled() then return end
    if not unit or Sealed(unit) then return end
    if unit == "player" or unit == "pet" or unit == "vehicle" then return end
    if not UnitExists(unit) then return end

    local now = GetTime()
    local key = UnitGUID(unit)
    if Sealed(key) or not key then key = unit end
    if lastThank[key] and (now - lastThank[key]) < COOLDOWN then return end
    lastThank[key] = now

    local emote = EMOTES[math.random(#EMOTES)]
    local ok = pcall(DoEmote, emote, unit)
    if not ok then
        pcall(DoEmote, emote)
    end
    if BuffThanksDB and BuffThanksDB.debug then
        local name = UnitName(unit)
        if Sealed(name) then name = unit end
        print("|cff33ff99Buff Thanks|r " .. emote .. " at " .. tostring(name))
    end
end

local function IsOtherPlayer(unit)
    if not unit or Sealed(unit) then return false end
    if unit == "player" or unit == "pet" or unit == "vehicle" then return false end
    if not UnitExists(unit) then return false end
    local isPlayer = UnitIsPlayer(unit)
    if Sealed(isPlayer) then return true end
    return isPlayer and true or false
end

local function RecentCaster()
    local now = GetTime()
    local best, bestTime
    for unit, when in pairs(recentCast) do
        if (now - when) <= CAST_WINDOW and IsOtherPlayer(unit) then
            if not bestTime or when > bestTime then
                best, bestTime = unit, when
            end
        elseif (now - when) > 10 then
            recentCast[unit] = nil
        end
    end
    return best
end

local function ReadInstance(instanceID)
    if not instanceID or Sealed(instanceID) then return nil end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then return nil end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceID)
    if ok then return data end
    return nil
end

local function Consider(aura)
    if not aura then return end
    if IsTrue(aura.isHarmful) then return end
    if IsFalse(aura.isHelpful) then return end
    if IsFalse(aura.isFromPlayerOrPlayerPet) then return end

    local src = aura.sourceUnit
    if src and not Sealed(src) and IsOtherPlayer(src) then
        Thank(src)
        return
    end

    local caster = RecentCaster()
    if caster then
        Thank(caster)
    end
end

local function ScanAuras()
    if not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL", 40)
    if not ok or not auras or Sealed(auras) then return end
    local seen = {}
    local count = #auras
    if Sealed(count) then return end
    for i = 1, count do
        local aura = auras[i]
        local id = aura and aura.auraInstanceID
        if id and not Sealed(id) then
            seen[id] = true
            if not known[id] then
                known[id] = true
                local data = ReadInstance(id) or aura
                Consider(data)
            end
        end
    end
    for id in pairs(known) do
        if not seen[id] then known[id] = nil end
    end
end

local function Watch(unit)
    if not unit or watched[unit] then return end
    watched[unit] = true
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
end

local function WatchGroup()
    Watch("target")
    Watch("focus")
    Watch("mouseover")
    for i = 1, 4 do Watch("party" .. i) end
    for i = 1, 40 do Watch("raid" .. i) end
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end
        BuffThanksDB = BuffThanksDB or { enabled = true, debug = true }
        print("|cff33ff99Buff Thanks|r loaded. /bt toggles, /bt debug prints.")
        WatchGroup()
        C_Timer.After(1, ScanAuras)
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            local ok, err = pcall(ScanAuras)
            if not ok and BuffThanksDB and BuffThanksDB.debug then
                print("|cff33ff99Buff Thanks|r error: " .. tostring(err))
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if IsOtherPlayer(unit) then
            recentCast[unit] = GetTime()
            C_Timer.After(0.2, ScanAuras)
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Watch(...)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        WatchGroup()
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(lastThank)
        wipe(recentCast)
        wipe(known)
        WatchGroup()
        C_Timer.After(1, ScanAuras)
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

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
        DoEmote("WAVE")
        print("|cff33ff99Buff Thanks|r test wave. Emotes work.")
        return
    end
    BuffThanksDB.enabled = not BuffThanksDB.enabled
    print("|cff33ff99Buff Thanks|r " .. (BuffThanksDB.enabled and "on" or "off"))
end
