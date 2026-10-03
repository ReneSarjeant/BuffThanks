-- Buff Thanks 1.1
-- Emote at the player who buffed you.
-- Forever seals aura payloads. Do not boolean-test those fields.
-- Detection does not depend on the UNIT_AURA payload: out of combat we poll
-- the helpful aura list and treat a new auraInstanceID as a new buff.

local ADDON = "BuffThanks"
local COOLDOWN = 20
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
    if not Enabled() then
        Debug("off, skipped " .. tostring(why))
        return
    end
    if not unit or Sealed(unit) or not UnitExists(unit) then
        Debug("no caster unit (" .. tostring(why) .. ")")
        return
    end
    if unit == "player" or unit == "pet" or unit == "vehicle" then return end

    local now = GetTime()
    local key = UnitGUID(unit)
    if Sealed(key) or not key then key = unit end
    if lastThank[key] and (now - lastThank[key]) < COOLDOWN then
        Debug("cooldown on " .. tostring(key))
        return
    end
    lastThank[key] = now

    local emote = EMOTES[math.random(#EMOTES)]
    if not pcall(DoEmote, emote, unit) then
        pcall(DoEmote, emote)
    end
    local name = UnitName(unit)
    if Sealed(name) then name = unit end
    print("|cff33ff99Buff Thanks|r " .. emote .. " at " .. tostring(name))
end

local function IsOtherPlayer(unit)
    if not unit or Sealed(unit) or not UnitExists(unit) then return false end
    if unit == "player" or unit == "pet" or unit == "vehicle" then return false end
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

local function FallbackCaster()
    return RecentCaster() or (IsOtherPlayer("target") and "target") or (IsOtherPlayer("mouseover") and "mouseover") or nil
end

local function Consider(aura, id)
    if aura then
        if IsFalse(aura.isHelpful) then
            Debug("skip " .. tostring(id) .. " not helpful")
            return
        end
        if IsFalse(aura.isFromPlayerOrPlayerPet) then
            Debug("skip " .. tostring(id) .. " not from a player")
            return
        end
        local src = aura.sourceUnit
        if src and not Sealed(src) and IsOtherPlayer(src) then
            Thank(src, "sourceUnit")
            return
        end
        Debug("new aura " .. tostring(id) .. " source sealed")
    else
        Debug("new aura " .. tostring(id) .. " no data")
    end
    local caster = FallbackCaster()
    if caster then
        Thank(caster, "fallback")
    else
        Debug("new aura " .. tostring(id) .. " and no nearby caster")
    end
end

local function ReadInstance(instanceID)
    if not instanceID or Sealed(instanceID) then return nil end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then return nil end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceID)
    if ok then return data end
    return nil
end

local function NoteNew(id)
    if not id or Sealed(id) or known[id] then return end
    known[id] = true
    if not primed then return end
    Consider(ReadInstance(id), id)
end

local function Scan()
    if InCombatLockdown() then return end
    if not C_UnitAuras or not C_UnitAuras.GetUnitAuras then
        Debug("C_UnitAuras.GetUnitAuras missing")
        return
    end
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL", 40)
    if not ok or not auras then
        Debug("GetUnitAuras failed")
        return
    end
    if Sealed(auras) then
        Debug("aura list sealed")
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
                NoteNew(id)
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
    if unit and UnitExists(unit) then
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    end
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
        BuffThanksDB = BuffThanksDB or {}
        if BuffThanksDB.enabled == nil then BuffThanksDB.enabled = true end
        if BuffThanksDB.debug == nil then BuffThanksDB.debug = true end
        print("|cff33ff99Buff Thanks|r 1.1 loaded. /bt debug is " .. (BuffThanksDB.debug and "on" or "off"))
        WatchGroup()
        C_Timer.After(1, Scan)
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            Debug("aura event")
            local ok, err = pcall(Scan)
            if not ok then Debug("scan error: " .. tostring(err)) end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if IsOtherPlayer(unit) then
            recentCast[unit] = GetTime()
            Debug("cast from " .. tostring(unit))
            C_Timer.After(0.3, Scan)
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Watch(...)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        WatchGroup()
    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0.2, Scan)
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

C_Timer.NewTicker(1, function()
    if primed and not InCombatLockdown() then
        pcall(Scan)
    end
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
        DoEmote("WAVE")
        print("|cff33ff99Buff Thanks|r test wave. Emotes work.")
        return
    end
    if msg == "scan" then
        primed = true
        Scan()
        print("|cff33ff99Buff Thanks|r scanned.")
        return
    end
    BuffThanksDB.enabled = not BuffThanksDB.enabled
    print("|cff33ff99Buff Thanks|r " .. (BuffThanksDB.enabled and "on" or "off"))
end
