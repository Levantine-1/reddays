HygieneManager = {}

local function LoadPlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    if modData.ICdata.cSIHDC_counter ~= nil then
        cSIHDC_counter = modData.ICdata.cSIHDC_counter
    else
        cSIHDC_counter = 0
    end
end
Events.OnLoad.Add(LoadPlayerData)

function HygieneManager.resetHygieneData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    modData.ICdata.cSIHDC_counter = 0
    cSIHDC_counter = 0
end

local function SavePlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata.cSIHDC_counter = cSIHDC_counter
end
-- Events.OnSave.Add(SavePlayerData) -- For some reason this doesn't work. It'll print the counter, but it doesn't seem save it as on load, value is 0.
Events.EveryTenMinutes.Add(SavePlayerData) -- Save every 10 minutes instead

local cSIHDC_counter_tgt = 100 -- Decrement 1 every 100 minutes, should get to very bloody condition around 10 hours and saturated around 20 hours
local cSIHDC_counter_increment = 1
local function consumeSanitaryItemHelperDecrementCondition(item, current_condition)
    cSIHDC_counter = cSIHDC_counter + cSIHDC_counter_increment
    -- modData.ICdata.cSIHDC_counter = cSIHDC_counter -- debugging counter saving -- But don't save here because it'll save every second which may have performance issues
    if current_condition == 10 or (current_condition > 1 and cSIHDC_counter > cSIHDC_counter_tgt) then
        item:setCondition(current_condition - 1)
        cSIHDC_counter = 0
    end
end

local function consumeSanitaryItemHelperRenameItemAndLeakChance(item)
    local itemName = item:getName()
    local baseName = itemName:match("^(.-) %(")
    if not baseName then
        baseName = itemName
    end

    local current_condition = item:getCondition()
    consumeSanitaryItemHelperDecrementCondition(item, current_condition)

    local d20Roll = ZombRand(1, 21) -- Chance to leak
    if current_condition >= 9 then
        item:setName(baseName .. " (Spotty)")
    elseif current_condition >= 8 then
        item:setName(baseName .. " (Bloody)")
    elseif current_condition >= 4 then
        item:setName(baseName .. " (Very Bloody)")
    elseif current_condition == 3 then
        if d20Roll >= 15 then
            return false -- 25% chance to leak
        end
    elseif current_condition == 2 then
        item:setName(baseName .. " (Nearly Saturated)")
        if d20Roll >= 10 then
            return false -- 50% chance to leak
        end
    elseif current_condition < 2 then
        item:setName(baseName .. " (Saturated)")
        return false
    end
    return true -- No leak
end

function HygieneManager.consumeDischargeProduct()
    local player = getPlayer()
    local wornItems = player:getWornItems()

    for i = 0, wornItems:size() - 1 do
        local item = wornItems:get(i):getItem()
        if item and item:getDisplayCategory() == "Feminine Hygiene" then
            local itemName = item:getName()
            local baseName = itemName:match("^(.-) %(")
            if not baseName then
                baseName = itemName
            end
            wasItemConsumed = false
            if item:getCondition() > 1 then
                wasItemConsumed = true
            end
            item:setCondition(1)
            item:setName(baseName .. " (Dirty)")
            return wasItemConsumed
        end
    end
    return false
end

local function consumeSanitaryItem()
    local player = getPlayer()
    local wornItems = player:getWornItems()

    local isSanitaryItemEquipped = false
    local didConsumeSanitaryItem = false

    for i = 0, wornItems:size() - 1 do
        local item = wornItems:get(i):getItem()
        if item and item:getDisplayCategory() == "Feminine Hygiene" then
            isSanitaryItemEquipped = true
            didConsumeSanitaryItem = consumeSanitaryItemHelperRenameItemAndLeakChance(item)
            return isSanitaryItemEquipped, didConsumeSanitaryItem
        end
    end
    return isSanitaryItemEquipped, didConsumeSanitaryItem
end

function HygieneManager.consumeHygieneProduct()
    local player = getPlayer()
    local bodyDamage = player:getBodyDamage()
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    isSanitaryItemEquipped, didConsumeSanitaryItem = consumeSanitaryItem()
    if isSanitaryItemEquipped then
        local bleedingTime = groin:getBleedingTime()
        if bleedingTime == 0 and didConsumeSanitaryItem then
            groin:setBleeding(false) -- Clear bleeding if no wounds. Cycle generates bleeding time of 0, so assumed no wounds.
        end
        return didConsumeSanitaryItem -- Returns true if sanitary item was consumed and no leak occurred
    elseif groin:bandaged() then
        current_bandageLife = groin:getBandageLife()
        groin:setBandageLife(current_bandageLife - 0.1)
        return true -- Always returns true because player could bleed to death if they have other injuries. Setting to false could remove the bandage.
    end
    return false -- No sanitary item equipped and no bandage
end

return HygieneManager