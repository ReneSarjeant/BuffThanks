-- Buff Thanks
-- When a friendly player applies a helpful aura to you, emote back at that player.
-- WoW Forever uses the modern addon API: the combat log is not available,
-- so the caster comes from the aura's sourceUnit on UNIT_AURA.
-- Aura flags such as isFullUpdate can be secret. Never test those directly.

local ADDON = "BuffThanks"
local COOLDOWN = 20

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
local pending = {}

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

    local now = GetTime()
    if lastThank[unit] and (now - lastThank[unit]) < COOLDOWN then return end
    lastThank[unit] = now

    local emote = EMOTES[math.random(#EMOTES)]
    local ok = pcall(DoEmote, emote, unit)
    if not ok then
        pcall(DoEmote, emote)
    end
end

local function IsOtherPlayer(unit)
    if not unit or Sealed(unit) then return false end
    if unit == "player" or unit == "pet" or unit == "vehicle" then return false end

    local isPlayer = UnitIsPlayer(unit)
    if Sealed(isPlayer) then
        return true
    end
    return isPlayer and true or false
end

local function Consider(aura)
    if not aura then return end
    if IsTrue(aura.isHarmful) then return end
    if IsFalse(aura.isHelpful) then return end
    if IsFalse(aura.isFromPlayerOrPlayerPet) then return end

    local src = aura.sourceUnit
    if not src or Sealed(src) then
        local id = aura.auraInstanceID
        if id and not Sealed(id) then
            pending[id] = true
        end
        return
    end
    if IsOtherPlayer(src) then
        Thank(src)
    end
end

local function ReadInstance(instanceID)
    if not instanceID or Sealed(instanceID) then return nil end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then return nil end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceID)
    if ok then return data end
    return nil
end

local function OnAura(updateInfo)
    if not updateInfo then return end
    -- isFullUpdate is a secret boolean on Forever. Skip the check if sealed.
    if IsTrue(updateInfo.isFullUpdate) then return end

    local added = updateInfo.addedAuras
    if not added or Sealed(added) then return end

    local count = #added
    if Sealed(count) then return end
    for i = 1, count do
        local aura = added[i]
        if aura then
            local src = aura.sourceUnit
            if (not src or Sealed(src)) and aura.auraInstanceID and not Sealed(aura.auraInstanceID) then
                aura = ReadInstance(aura.auraInstanceID) or aura
            end
            Consider(aura)
        end
    end
end

local function FlushPending()
    if not next(pending) then return end
    for instanceID in pairs(pending) do
        local data = ReadInstance(instanceID)
        if data then Consider(data) end
        pending[instanceID] = nil
    end
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end
        BuffThanksDB = BuffThanksDB or { enabled = true }
        print("|cff33ff99Buff Thanks|r loaded. /bt to toggle.")
    elseif event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if unit == "player" then
            local ok, err = pcall(OnAura, updateInfo)
            if not ok then
                print("|cff33ff99Buff Thanks|r error: " .. tostring(err))
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushPending()
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(lastThank)
        wipe(pending)
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_AURA")

SLASH_BUFFTHANKS1 = "/bt"
SLASH_BUFFTHANKS2 = "/buffthanks"
SlashCmdList.BUFFTHANKS = function()
    BuffThanksDB = BuffThanksDB or { enabled = true }
    BuffThanksDB.enabled = not BuffThanksDB.enabled
    if BuffThanksDB.enabled then
        print("|cff33ff99Buff Thanks|r on.")
    else
        print("|cff33ff99Buff Thanks|r off.")
    end
end
