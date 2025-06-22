HygieneManager = {}

local function consumeSanitaryItem()
    local player = getPlayer()
    -- Get all equipped clothing items
    local wornItems = player:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:get(i):getItem()
        if item and item:getType() == "Sanitary_Pad" then
            local itemName = item:getName()
            print("Consuming sanitary item: " .. itemName)
            current_condition = item:getCondition()
            if current_condition > 1 then
                item:setCondition(current_condition - 1)
                print("Sanitary item consumed, remaining condition: " .. item:getCondition())
            else
                print("Sanitary item is already at unusable condition.")
            end

            if current_condition <= 3 then
                item:setName(itemName .. " (Dirty)")
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

    print("Attempting to consume hygiene product...")
    consumeSanitaryItem()
    print("Hygiene product consumed.")

    if groin:bandaged() then
        current_bandageLife = groin:getBandageLife()
        print("Bandage life before consuming hygiene product: " .. current_bandageLife)
        groin:setBandageLife(current_bandageLife - 0.1)
    else
        print("Groin is not bandaged, cannot consume hygiene product.")
        return false
    end
    return true
end

return HygieneManager