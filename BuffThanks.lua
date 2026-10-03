-- Buff Thanks 1.6
-- Forever seals the caster. A cast event from another player often never arrives.
-- If a new player buff lands and the source is sealed, thank a visible other player:
-- target, mouseover, then a friendly nameplate. Do not pass that unit to DoEmote.

local ADDON = "BuffThanks"
local COOLDOWN = 8
local CAST_WINDOW = 4

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

local function CleanName(unit)
    if not unit or Sealed(unit) then return nil end
    local name = UnitName(unit)
    if not name or Sealed(name) or type(name) ~= "string" then return nil end
    if name:find("[%c%%]") then return nil end
    return name
end

local function Enabled()
    return not BuffThanksDB or BuffThanksDB.enabled ~= false
end

local function IsSelf(unit)
    if unit == "player" then return true end
    local same = UnitIsUnit(unit, "player")
    if Sealed(same) then return false end
    return same and true or false
end

local function Thank(unit, why)
    if not Enabled() then return end
    if not unit or Sealed(unit) then return end
    if unit ~= "player" and not UnitExists(unit) then return end
    local now = GetTime()
    local key = IsSelf(unit) and "player" or UnitGUID(unit)
    if Sealed(key) or not key then key = unit end
    if lastThank[key] and (now - lastThank[key]) < COOLDOWN then
        Debug("cooldown for " .. tostring(CleanName(unit) or key))
        return
    end
    lastThank[key] = now
    local emote = EMOTES[math.random(#EMOTES)]
    pcall(DoEmote, emote)
    print("|cff33ff99Buff Thanks|r " .. emote .. " for " .. tostring(CleanName(unit) or unit) .. " (" .. why .. ")")
end

local function IsPlayerUnit(unit)
    if not unit or Sealed(unit) then return false end
    if unit == "player" then return true end
    if not UnitExists(unit) then return false end
    local isPlayer = UnitIsPlayer(unit)
    if Sealed(isPlayer) then return true end
    return isPlayer and true or false
end

local function VisibleOther()
    local list = { "target", "mouseover", "focus", "softfriend" }
    for i = 1, #list do
        local u = list[i]
        if IsPlayerUnit(u) and not IsSelf(u) then return u end
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not IsSelf(u) then return u end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if IsPlayerUnit(u) and not IsSelf(u) then return u end
        u = "raid" .. i
        if UnitExists(u) and not IsSelf(u) then return u end
    end
    return nil
end

local function RecentCaster()
    local now = GetTime()
    local best, bestTime
    for unit, when in pairs(recentCast) do
        if (now - when) <= CAST_WINDOW and IsPlayerUnit(unit) and not IsSelf(unit) then
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
    if not IsPlayerUnit(unit) or IsSelf(unit) then return end
    recentCast[unit] = GetTime()
    Debug("cast from " .. tostring(CleanName(unit) or unit))
    C_Timer.After(0.4, function() pcall(Scan) end)
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
    if src and not Sealed(src) and IsPlayerUnit(src) and not IsSelf(src) then
        Thank(src, "source")
        return
    end
    local caster = RecentCaster()
    if caster then
        Thank(caster, "recent cast")
        return
    end
    local other = VisibleOther()
    if other then
        Thank(other, "visible player")
        return
    end
    Debug("aura " .. id .. ", caster sealed, nobody else visible")
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
        Debug("1.6 primed with " .. n .. " buffs")
    end
end

local function Watch(unit)
    if unit and UnitExists(unit) then
        pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", unit)
    end
end

local function WatchAll()
    Watch("player")
    Watch("target")
    Watch("focus")
    Watch("mouseover")
    Watch("softfriend")
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
        pcall(SetCVar, "nameplateShowFriends", 1)
        print("|cff33ff99Buff Thanks 1.6|r loaded.")
        WatchAll()
        C_Timer.After(1, Scan)
    elseif event == "UNIT_AURA" then
        if ... == "player" then
            Debug("aura event")
            pcall(Scan)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        NoteCast(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_REGEN_ENABLED" then
        WatchAll()
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

local function SafeRegister(event)
    pcall(f.RegisterEvent, f, event)
end
SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("PLAYER_REGEN_ENABLED")
SafeRegister("GROUP_ROSTER_UPDATE")
SafeRegister("PLAYER_TARGET_CHANGED")
SafeRegister("UPDATE_MOUSEOVER_UNIT")
SafeRegister("NAME_PLATE_UNIT_ADDED")
SafeRegister("UNIT_AURA")
SafeRegister("UNIT_SPELLCAST_SUCCEEDED")

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
        print("|cff33ff99Buff Thanks 1.6|r debug " .. (BuffThanksDB.debug and "on" or "off"))
        return
    end
    if msg == "test" then
        DoEmote("WAVE")
        print("|cff33ff99Buff Thanks 1.6|r test wave.")
        return
    end
    BuffThanksDB.enabled = not BuffThanksDB.enabled
    print("|cff33ff99Buff Thanks 1.6|r " .. (BuffThanksDB.enabled and "on" or "off"))
end
