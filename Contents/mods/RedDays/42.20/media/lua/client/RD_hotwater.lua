-- Hot water bottle: a filled, heated bottle held in either hand eases PMS symptoms.
--
-- The engine already heats any item carrying a FluidContainer component -- InventoryItem.update
-- raises itemHeat from the container's temperature, so ovens, stoves, BBQs, campfires and
-- microwaves all work with no Lua involved. What it does NOT do is hold that heat: vanilla food
-- cools within minutes, while a real hot water bottle stays useful for hours. So the mod keeps its
-- own value on a half-life curve, adopts the engine's whenever the engine's is hotter (that is
-- something actively heating the bottle), and writes the result back with setItemHeat so the
-- inventory's red border still reflects the truth.

RD_HotWater = RD_HotWater or {}
require "RD_game_api"

-- itemHeat is 1.0 at ambient and climbs from there; vanilla treats ~1.6 as properly cooked.
local AMBIENT = 1.0
local WARM_FLOOR = 1.10   -- below this the bottle is spent and does nothing
local FULL_HEAT = 1.80    -- at or above this it gives the full configured reduction

local BOTTLE_TYPES = {
    ["Base.HotWaterBottle"] = true,
}

local function getSandbox()
    return SandboxVars.RedDays or {}
end

local function nowMinutes()
    local hours = RD_zapi.getGameTime("getWorldAgeHours")
    if not hours then return nil end
    return hours * 60
end

local function isBottle(item)
    if not item then return false end
    local ok, fullType = pcall(function() return item:getFullType() end)
    return ok and BOTTLE_TYPES[fullType] == true
end

-- An empty bottle has nothing to hold heat in, so it reads as ambient however hot it just was.
local function isEmpty(item)
    local ok, container = pcall(function() return item:getFluidContainer() end)
    if not ok or not container then return false end
    local gotAmount, amount = pcall(function() return container:getAmount() end)
    if not gotAmount or not amount then return false end
    return amount <= 0
end

-- Advances one bottle's tracked heat to `now` and returns it.
function RD_HotWater.updateItemHeat(item, now)
    if not item or not now then return AMBIENT end

    local md = item:getModData()
    local engineHeat = item:getItemHeat() or AMBIENT

    local heat
    if isEmpty(item) then
        heat = AMBIENT
    elseif md.rdHeat == nil or md.rdHeatAt == nil then
        heat = engineHeat
    else
        local elapsed = math.max(0, now - md.rdHeatAt)
        local halfLife = math.max(1, getSandbox().hot_water_bottle_cooling_halflife_mins or 90)
        local decayed = AMBIENT + (md.rdHeat - AMBIENT) * (0.5 ^ (elapsed / halfLife))
        -- Compare against what was last written, not against our own tracked value: setItemHeat
        -- puts our number into the same field the engine uses, so only a reading ABOVE that last
        -- write means an oven, stove or microwave is actively adding heat.
        local lastWritten = md.rdHeatWritten or AMBIENT
        if engineHeat > lastWritten + 1e-4 then
            heat = engineHeat
        else
            heat = decayed
        end
    end

    md.rdHeat = heat
    md.rdHeatAt = now
    md.rdHeatWritten = heat
    item:setItemHeat(heat)
    return heat
end

local function handItems(player)
    local items = {}
    local ok, primary = pcall(function() return player:getPrimaryHandItem() end)
    if ok and primary then items[#items + 1] = primary end
    local okOff, secondary = pcall(function() return player:getSecondaryHandItem() end)
    if okOff and secondary and secondary ~= items[1] then items[#items + 1] = secondary end
    return items
end

-- Keeps every bottle the player is holding up to date, so a spell in the oven isn't missed
-- between two PMS evaluations.
function RD_HotWater.EveryOneMinute()
    local player = RD_zapi.getPlayer()
    if not player then return end
    local now = nowMinutes()
    if not now then return end

    for _, item in ipairs(handItems(player)) do
        if isBottle(item) then
            RD_HotWater.updateItemHeat(item, now)
        end
    end
end

-- Percent reduction in PMS severity from the hottest bottle in hand, ramping from nothing at
-- WARM_FLOOR to the configured maximum at FULL_HEAT.
function RD_HotWater.getReductionPct()
    local maxPct = getSandbox().hot_water_bottle_reduction_pct or 30
    if maxPct <= 0 then return 0 end

    local player = RD_zapi.getPlayer()
    if not player then return 0 end
    local now = nowMinutes()
    if not now then return 0 end

    local best = AMBIENT
    for _, item in ipairs(handItems(player)) do
        if isBottle(item) then
            local heat = RD_HotWater.updateItemHeat(item, now)
            if heat > best then best = heat end
        end
    end

    if best <= WARM_FLOOR then return 0 end
    local scale = math.min(1, (best - WARM_FLOOR) / (FULL_HEAT - WARM_FLOOR))
    return maxPct * scale
end

return RD_HotWater
