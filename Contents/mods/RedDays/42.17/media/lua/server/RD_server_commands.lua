-- Red Days Server Commands
-- Handles multiplayer synchronization for item modifications
-- This file must be in the server folder to receive client commands

print("[RedDays] Server commands loading...")

local RD_ServerCommands = {}
local Commands = {}

-- Command to update sanitary item condition and name
function Commands.updateSanitaryItem(player, args)
    if not player or not args then return end
    
    local itemId = args.itemId
    local newCondition = args.newCondition
    local newName = args.newName
    
    if not itemId then return end
    
    -- Find the item in player's worn items or inventory
    local item = nil
    
    -- Check worn items first
    local wornItems = player:getWornItems()
    if wornItems then
        for i = 0, wornItems:size() - 1 do
            local wornItem = wornItems:get(i)
            if wornItem and wornItem:getItem() then
                local checkItem = wornItem:getItem()
                if checkItem:getID() == itemId then
                    item = checkItem
                    break
                end
            end
        end
    end
    
    -- If not found in worn items, check inventory
    if not item then
        local inventory = player:getInventory()
        if inventory then
            local items = inventory:getItems()
            for i = 0, items:size() - 1 do
                local checkItem = items:get(i)
                if checkItem and checkItem:getID() == itemId then
                    item = checkItem
                    break
                end
            end
        end
    end
    
    if not item then
        print("[RedDays] Server: Could not find item with ID " .. tostring(itemId))
        return
    end
    

    
    -- Apply changes
    if newCondition ~= nil then
        item:setCondition(newCondition)
    end
    
    if newName ~= nil then
        item:setName(newName)
    end
    
    -- Sync the item back to all clients (requires player and item)
    syncItemFields(player, item)
end

-- Command to apply body part stiffness server-side (used for PMS cramps/tender breasts in multiplayer)
-- BodyDamage is server-authoritative, so client-side setStiffness() gets overwritten; the server must apply it.
function Commands.applyBodyStiffness(player, args)
    if not player or not args then return end
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    if args.Torso_Lower ~= nil then
        bodyDamage:getBodyPart(BodyPartType.Torso_Lower):setStiffness(args.Torso_Lower)
    end
    if args.Groin ~= nil then
        bodyDamage:getBodyPart(BodyPartType.Groin):setStiffness(args.Groin)
    end
    if args.Torso_Upper ~= nil then
        bodyDamage:getBodyPart(BodyPartType.Torso_Upper):setStiffness(args.Torso_Upper)
    end
end

-- Command handler for OnClientCommand event
RD_ServerCommands.OnClientCommand = function(module, command, player, args)
    if module == 'RedDays' and Commands[command] then
        Commands[command](player, args)
    end
end

Events.OnClientCommand.Add(RD_ServerCommands.OnClientCommand)

print("[RedDays] Server: Event handler registered")

return RD_ServerCommands
