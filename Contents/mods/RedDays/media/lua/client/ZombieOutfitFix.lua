local original_addRandomUnderwear = UnderwearDefinition.addRandomUnderwear

function UnderwearDefinition.addRandomUnderwear(character, female)
    if character:isZombie() then
        -- Skip modded hygiene items for zombies
        local validUnderwear = {}
        for _, item in ipairs(UnderwearDefinition.UnderwearItems) do
            if not item:startsWith("RedDays.") then
                table.insert(validUnderwear, item)
            end
        end
        if #validUnderwear > 0 then
            local item = validUnderwear[ZombRand(#validUnderwear) + 1]
            if ScriptManager.instance:getItem(item) then
                character:getInventory():AddItem(item)
            end
        end
        return
    end
    -- Call original for players
    original_addRandomUnderwear(character, female)
end