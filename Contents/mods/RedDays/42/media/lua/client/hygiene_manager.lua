HygieneManager = {}

local function consumeSanitaryItemHelperRenameItemAndLeakChance(item)
    local itemName = item:getName()
    local current_condition = item:getCondition()
    print("Consuming sanitary item: " .. itemName)

    baseName = itemName:match("^(.-) %(")

    if not baseName then
        baseName = itemName
    end
    d20Roll = ZombRand(1, 21) -- Chance to leak
    print("d20 Roll: " .. d20Roll)
    if current_condition < 10 and current_condition > 5 then
        item:setName(baseName .. " (Bloody)")
    elseif current_condition == 5 then
        item:setName(baseName .. " (Very Bloody)")
        if d20Roll >= 17 then
            return false -- 15% chance to leak
        end
    elseif current_condition == 4 then
        if d20Roll >= 15 then
            return false -- 25% chance to leak
        end
    elseif current_condition == 3 then
        if d20Roll >= 10 then
            return false -- 50% chance to leak
        end
    elseif current_condition == 2 then
        item:setName(baseName .. " (Nearly Saturated)")
        if d20Roll >= 5 then
            return false -- 75% chance to leak
        end
    elseif current_condition < 2 then
        item:setName(baseName .. " (Saturated)")
        return false
    end
    return true -- No leak
end

local function consumeSanitaryItem()
    local player = getPlayer()
    -- Get all equipped clothing items
    local wornItems = player:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:get(i):getItem()
        if item and item:getType() == "Sanitary_Pad" then
            current_condition = item:getCondition()
            if current_condition > 1 then
                item:setCondition(current_condition - 1)
                print("Sanitary item consumed, remaining condition: " .. item:getCondition())
            else
                print("Sanitary item is already at unusable condition.")
            end
            if not consumeSanitaryItemHelperRenameItemAndLeakChance(item) then
                print("Sanitary item leaked.")
                return false
            end
            return true
        end
    end
    print("No sanitary item equipped.")
    return false
end

function HygieneManager.consumeHygieneProduct()
    local player = getPlayer()
    local stats = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    consumeSanitaryItem()

    if groin:bandaged() then
        current_bandageLife = groin:getBandageLife()
        groin:setBandageLife(current_bandageLife - 0.1)
    else
        return false
    end
    return true
end

return HygieneManager