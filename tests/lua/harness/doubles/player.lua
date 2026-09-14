-- IsoPlayer double, plus the object graph hanging off it:
-- BodyDamage -> BodyPart / Thermoregulator, CharacterStats, HumanVisual, Descriptor.
--
-- Every setter records into `calls` so tests can assert that the mod asked the
-- engine to do a thing, not merely that a Lua-side number changed.

local M = {}

local containers = require "harness.doubles.container"
local itemDouble = require "harness.doubles.item"

-- ================= BODY PART =================

local function newBodyPart(typeEnum, calls)
    local part = {
        __bodyPart = true,
        type = typeEnum,
        stiffness = 0,
        bleedingTime = 0,
        bandageLife = 0,
        isBandaged = false,
        infectedWound = false,
        infected = false,
        woundInfectionLevel = 0,
        isScratched = false,
        cut = false,
        deepWounded = false,
    }

    function part:getStiffness() return self.stiffness end
    function part:setStiffness(v)
        self.stiffness = v
        calls[#calls + 1] = { what = "setStiffness", part = self.type.name, value = v }
    end

    function part:getBleedingTime() return self.bleedingTime end
    function part:setBleeding(v)
        self.bleedingTime = v
        calls[#calls + 1] = { what = "setBleeding", part = self.type.name, value = v }
    end
    function part:bleeding() return self.bleedingTime > 0 end

    function part:bandaged() return self.isBandaged end
    function part:getBandageLife() return self.bandageLife end
    function part:setBandageLife(v) self.bandageLife = v end

    function part:isInfectedWound() return self.infectedWound end
    function part:IsInfected() return self.infected end
    function part:getWoundInfectionLevel() return self.woundInfectionLevel end
    function part:scratched() return self.isScratched end
    function part:isCut() return self.cut end
    function part:isDeepWounded() return self.deepWounded end

    return part
end

-- ================= PLAYER =================

-- opts: female (default true), health (0-100), coreCelcius, traits {name,...}
function M.new(enums, opts)
    opts = opts or {}
    local calls = {}

    local player = {
        __player = true,
        playerNum = opts.playerNum or 0,
        female = opts.female ~= false,
        modData = opts.modData or {},
        asleep = false,
        dead = false,
        sleepingTabletEffect = 0,
        transmitCount = 0,
        calls = calls,
    }

    -- Traits are held by name so tests can write { "OBESE" } without importing enums.
    local traits = {}
    for _, name in ipairs(opts.traits or {}) do traits[name] = true end
    function player:hasTrait(trait)
        if trait == nil then return false end
        local name = type(trait) == "table" and trait.name or trait
        return traits[name] == true
    end
    function player:addTrait(name) traits[name] = true end
    function player:removeTrait(name) traits[name] = nil end

    -- ---- stats ----
    local statValues = {}
    local stats = { __stats = true }
    function stats:get(stat) return statValues[stat] or 0 end
    function stats:set(stat, v)
        statValues[stat] = v
        calls[#calls + 1] = { what = "stats:set", stat = stat.name, value = v }
    end
    function stats:add(stat, delta)
        statValues[stat] = (statValues[stat] or 0) + delta
        calls[#calls + 1] = { what = "stats:add", stat = stat.name, value = delta }
    end
    -- Test-side helper: seed a value without polluting the call log.
    function stats:__seed(stat, v) statValues[stat] = v end

    -- ---- thermoregulator ----
    local thermo = { core = opts.coreCelcius or 37.0 }
    function thermo:getCoreCelcius() return self.core end
    function thermo:setCoreCelcius(v) self.core = v end

    -- ---- body damage ----
    local parts = {}
    local bodyDamage = { __bodyDamage = true, health = opts.health or 100, hasCold = false }

    function bodyDamage:getBodyPart(partType)
        if not partType then return nil end
        local key = partType.name or tostring(partType)
        if not parts[key] then parts[key] = newBodyPart(partType, calls) end
        return parts[key]
    end
    function bodyDamage:getThermoregulator() return thermo end
    function bodyDamage:getHealth() return self.health end
    function bodyDamage:ReduceGeneralHealth(amount)
        self.health = self.health - (amount or 0)
        if self.health < 0 then self.health = 0 end
        calls[#calls + 1] = { what = "ReduceGeneralHealth", value = amount }
    end
    function bodyDamage:setOverallBodyHealth(v)
        self.health = v
        calls[#calls + 1] = { what = "setOverallBodyHealth", value = v }
    end
    function bodyDamage:isHasACold() return self.hasCold end

    -- ---- human visual (body blood/dirt) ----
    local visual = { blood = {}, dirt = {} }
    function visual:getBlood(part) return self.blood[part] or 0 end
    function visual:setBlood(part, v) self.blood[part] = v end
    function visual:getDirt(part) return self.dirt[part] or 0 end
    function visual:setDirt(part, v) self.dirt[part] = v end

    -- ---- descriptor ----
    local descriptor = {
        forename = opts.forename or "Test",
        surname = opts.surname or "Subject",
    }
    function descriptor:getForename() return self.forename end
    function descriptor:getSurname() return self.surname end

    -- ---- containers ----
    local worn = containers.newWornItems()
    local inventory = containers.newInventory(function(o) return itemDouble.new(o) end)

    -- ---- player surface ----
    function player:getPlayerNum() return self.playerNum end
    function player:isFemale() return self.female end
    function player:getModData() return self.modData end
    function player:getWornItems() return worn end
    function player:getInventory() return inventory end
    function player:getBodyDamage() return bodyDamage end
    function player:getStats() return stats end
    function player:getHumanVisual() return visual end
    function player:getDescriptor() return descriptor end
    function player:getSquare() return { __square = true, x = 0, y = 0, z = 0 } end
    function player:resetModelNextFrame()
        calls[#calls + 1] = { what = "resetModelNextFrame" }
    end
    function player:isAsleep() return self.asleep end
    function player:isDead() return self.dead end
    function player:getSleepingTabletEffect() return self.sleepingTabletEffect end
    function player:setSleepingTabletEffect(v)
        self.sleepingTabletEffect = v
        calls[#calls + 1] = { what = "setSleepingTabletEffect", value = v }
    end
    function player:transmitModData()
        self.transmitCount = self.transmitCount + 1
        calls[#calls + 1] = { what = "transmitModData" }
    end

    -- Direct handles for test setup and assertions.
    player.stats = stats
    player.bodyDamage = bodyDamage
    player.thermo = thermo
    player.visual = visual
    player.worn = worn
    player.inventory = inventory

    -- Returns every recorded call matching `what`, in order.
    function player:callsOf(what)
        local out = {}
        for _, c in ipairs(calls) do
            if c.what == what then out[#out + 1] = c end
        end
        return out
    end

    function player:clearCalls()
        for i = #calls, 1, -1 do calls[i] = nil end
    end

    return player
end

return M
