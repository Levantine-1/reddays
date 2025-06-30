HygieneManager = {}

local function consumeSanitaryItemHelperRenameItemAndLeakChance(item)
    local itemName = item:getName()

    current_condition = item:getCondition()
    if current_condition > 1 then
        item:setCondition(current_condition - 1)
    end

    local baseName = itemName:match("^(.-) %(")
    if not baseName then
        baseName = itemName
    end

    d20Roll = ZombRand(1, 21) -- Chance to leak
    if current_condition >= 9 then
        item:setName(baseName .. " (Spotty)")
    elseif current_condition >= 7 then
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