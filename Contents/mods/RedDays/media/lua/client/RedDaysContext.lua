require "TimedActions/ISDetachHygieneItemAction"
require "TimedActions/ISInsertTamponAction"
require "TimedActions/ISRemoveTamponAction"

local function getItemFromContainer(inventory, fullType)
    for i = 0, inventory:getItems():size() - 1 do
        local item = inventory:getItems():get(i)
        if item:getFullType() == fullType then
            return item
        end
        if instanceof(item, "InventoryContainer") then
            local found = getItemFromContainer(item:getInventory(), fullType)
            if found then return found end
        end
    end
    return nil
end

-- Existing inventory context menu
Events.OnFillInventoryObjectContextMenu.Add(function(playerIndex, context, items)
    local player = getSpecificPlayer(playerIndex)
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local inventory = player:getInventory()

    for _, entry in ipairs(items) do
        local item = entry.item
        if not item and entry.items then
            item = entry.items[1]
        end
        if item then
            if item:getDisplayCategory() == "FeminineHygiene" and item:getCondition() >= 1 then
                if item:getFullType() == "RedDays.Tampon" then
                    if not modData.ICdata.insertedTampon then
                        local targetItem = item
                        if not inventory:contains(item) then
                            targetItem = getItemFromContainer(inventory, "RedDays.Tampon")
                        end
                        if targetItem then
                            context:addOption("Insert Tampon", targetItem, function()
                                ISTimedActionQueue.add(ISInsertTamponAction:new(player, targetItem, 100))
                            end)
                        end
                    end
                else
                    -- Existing attach for external
                    context:addOption("Attach Hygiene Item", item, function()
                        ISTimedActionQueue.add(ISUseHygieneItemAction:new(player, item, 100))
                    end)
                end
            elseif item:getCategory() == "Clothing" and item:getBodyLocation() == "UnderwearBottom" and item:getModData().attachedHygiene then
                context:addOption("Detach Hygiene Item", item, function()
                    ISTimedActionQueue.add(ISDetachHygieneItemAction:new(player, item, 100))
                end)
            end
        end
    end
end)

-- New world context menu
Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
    local player = getSpecificPlayer(playerIndex)
    if not player or (not SandboxVars.RedDays.affectsAllGenders and not player:isFemale()) then return end
    local modData = player:getModData()
    
    -- Add Remove Tampon option if inserted
    if modData.ICdata and modData.ICdata.insertedTampon then
        context:addOption("Remove Tampon", player, function()
            ISTimedActionQueue.add(ISRemoveTamponAction:new(player, 100))
        end)
    end
end)