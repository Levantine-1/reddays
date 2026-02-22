print("[RedDays] CLIENT: RD_hygiene_manager.lua loading - VERSION 2")

RD_HygieneManager = RD_HygieneManager or {}
require "RD_game_api"

-- Helper function to sync item changes to server in multiplayer
-- This ensures condition and name changes persist when items are dropped/picked up
local function syncItemToServer(item, newCondition, newName)
    if not item then return end
    
    -- In multiplayer client, send command to server to sync the item
    if isClient() then
        local player = RD_zapi.getPlayer()
        if player then
            local args = {
                itemId = item:getID(),
                newCondition = newCondition,
                newName = newName
            }
            sendClientCommand(player, 'RedDays', 'updateSanitaryItem', args)
        end
    end
end

-- DEBUG: Test function to change worn sanitary item condition with sync
-- Call from Lua console: RD_HygieneManager.debugSetCondition(5)
function RD_HygieneManager.debugSetCondition(newCondition)
    local item = RD_HygieneManager.getCurrentlyWornSanitaryItem()
    if not item then
        print("[RedDays] DEBUG: No sanitary item worn")
        return
    end
    print("[RedDays] DEBUG: Setting condition to " .. tostring(newCondition))
    item:setCondition(newCondition)
    syncItemToServer(item, newCondition, nil)
    print("[RedDays] DEBUG: Condition set and synced")
end

function RD_HygieneManager.LoadPlayerData()
    RD_modData = RD_zapi.getModData()
    RD_modData.ICdata = RD_modData.ICdata or {}
    if RD_modData.ICdata.cSIHDC_counter ~= nil then
        cSIHDC_counter = RD_modData.ICdata.cSIHDC_counter
    else
        cSIHDC_counter = 0
    end
end
-- Events.OnLoad.Add(RD_HygieneManager.LoadPlayerData)
-- 2026-01-22 Moved to events_intercepts.lua

-- NOTE: 2025-07-24 Disabled because this gets run on every load which means you always start on the first day of the cycle.
-- function RD_HygieneManager.resetHygieneData()
--     local player = getPlayer()
--     RD_modData = player:getModData()
--     RD_modData.ICdata = RD_modData.ICdata or {}
--     RD_modData.ICdata.cSIHDC_counter = 0
--     cSIHDC_counter = 0
-- end

local function SavePlayerData()
    RD_modData = RD_zapi.getModData()
    RD_modData.ICdata = RD_modData.ICdata or {}
    RD_modData.ICdata.cSIHDC_counter = cSIHDC_counter or 0
end
-- Events.OnSave.Add(SavePlayerData) -- For some reason this doesn't work. It'll print the counter, but it doesn't seem save it as on load, value is 0.
Events.EveryTenMinutes.Add(SavePlayerData) -- Save every 10 minutes instead

local cSIHDC_counter_tgt = 100 -- Decrement 1 every 100 minutes, should get to very bloody condition around 10 hours and saturated around 20 hours
local cSIHDC_counter_increment = 1
local function consumeSanitaryItemHelperDecrementCondition(item, current_condition)
    cSIHDC_counter = cSIHDC_counter + cSIHDC_counter_increment
    -- RD_modData.ICdata.cSIHDC_counter = cSIHDC_counter -- debugging counter saving -- But don't save here because it'll save every second which may have performance issues
    if current_condition == 10 or (current_condition > 1 and cSIHDC_counter > cSIHDC_counter_tgt) then
        local newCondition = current_condition - 1
        item:setCondition(newCondition)
        syncItemToServer(item, newCondition, nil) -- Sync condition change to server in MP
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
    local newName = nil
    if current_condition >= 9 then
        newName = baseName .. " (Spotty)"
    elseif current_condition >= 8 then
        newName = baseName .. " (Bloody)"
    elseif current_condition >= 4 then
        newName = baseName .. " (Very Bloody)"
    elseif current_condition == 3 then
        if d20Roll >= 15 then
            return false -- 25% chance to leak
        end
    elseif current_condition == 2 then
        newName = baseName .. " (Nearly Saturated)"
        if d20Roll >= 10 then
            return false -- 50% chance to leak
        end
    elseif current_condition < 2 then
        newName = baseName .. " (Saturated)"
    end

    -- Only set name and sync if the name actually changed
    if newName and newName ~= itemName then
        item:setName(newName)
        syncItemToServer(item, nil, newName)
    end

    if current_condition < 2 then
        return false
    end
    return true -- No leak
end

function RD_HygieneManager.getCurrentlyWornSanitaryItem()
    -- 2025-07-24
    -- There used to be a lot of logic in here but it has since been simplified
    -- However keeping this here because a lot of existing code relies on this function
    -- And I'm too lazy to refactor all of it right now
    local hygieneItem = RD_zapi.getWornItemAtLocation("RedDays:HygieneItem")
    if hygieneItem then
        return hygieneItem
    end
    return false
end

function RD_HygieneManager.consumeDischargeProduct()
    local item = RD_HygieneManager.getCurrentlyWornSanitaryItem()
    if not item then
        return false
    end

    local itemName = item:getName()
    local baseName = itemName:match("^(.-) %(")
    if not baseName then
        baseName = itemName
    end

    local wasItemConsumed = false
    if item:getCondition() > 1 then
        wasItemConsumed = true
    end

    local newCondition = 1
    local newName = baseName .. " (Dirty)"
    item:setCondition(newCondition)
    item:setName(newName)
    syncItemToServer(item, newCondition, newName) -- Sync condition and name change to server in MP

    -- NOTE: 2025-08-30 I've given up on trying to add blood to player clothes and body at this time. Uncomment the addBloodToClothes function to continue later
    -- if not wasItemConsumed then
    --     print("Sanitary item was not consumed, adding blood to player clothes and body")
    --     addBloodToClothes(player, false, true)
    -- end
    return wasItemConsumed
end

local function consumeSanitaryItem()
    local wornItems = RD_zapi.getWornItems()

    local isSanitaryItemEquipped = false
    local didConsumeSanitaryItem = false

    local item = RD_HygieneManager.getCurrentlyWornSanitaryItem()
    if not item then
        isSanitaryItemEquipped = false
        didConsumeSanitaryItem = false
        return isSanitaryItemEquipped, didConsumeSanitaryItem
    end

    isSanitaryItemEquipped = true
    didConsumeSanitaryItem = consumeSanitaryItemHelperRenameItemAndLeakChance(item)

    return isSanitaryItemEquipped, didConsumeSanitaryItem
end

-- local function addBloodToClothes(player, blood, dirt)
--     print("Adding Blood To Clothes")
--     local bodyDamage = player:getBodyDamage()
--     local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

--     local msg = "Set Blood: " .. tostring(blood) .. "Set Blood: " .. tostring(blood) .. ", Set Dirt: " .. tostring(dirt)
--     print(msg)
--     local wornItems = player:getWornItems()

--     -- These body locations not valid locations to add/blood dirt even though it would make sense
--     -- "UnderwearBottom", "Underwear", "UnderwearExtra1", "UnderwearExtra2", "Legs1", "Legs5", "PantsExtra"

--     -- Valid body locations for adding blood/dirt in sorted order that I thought would make sense, the idea was that if one item was full of blood, it'd leak to the next worn item.
--     local validBodyLocations = {"Pants", "Pants_Skinny", "ShortPants", "ShortsShort", "Skirt", "LongDress", "LongSkirt"}
--     local clothingItemToAddBlood = nil
--     for i, location in ipairs(validBodyLocations) do
--         local clothingItem = wornItems:getItem(location)
--         if clothingItem and clothingItem:getBloodClothingType() then -- Check to make sure clothing item can be bloodied
--             print(clothingItem:getName() .. " can be bloodied")
--             clothingItemToAddBlood = clothingItem
--             break
--         end
--     end

--     -- Clothes can be on multiple parts of the body, so we need to figure out how to apply blood to clothes at that part
--     -- But this is so hard to implement due to lack of clear documentation an
--     if clothingItemToAddBlood then
--         print(tostring(clothingItemToAddBlood) .. " selected to add blood")
--         local bloodCoveredParts = clothingItemToAddBlood:getBloodClothingType()
--         print("bloodCoveredParts: " .. tostring(bloodCoveredParts))
--         if bloodCoveredParts then
--             print("bloodCoveredParts size: " .. tostring(bloodCoveredParts:size()))
--             for i = 0, bloodCoveredParts:size() - 1 do
--                 local part = bloodCoveredParts:get(i)
--                 local bloodValue = clothingItemToAddBlood:getBlood(part)
--                 print("Covered part: " .. tostring(part) .. ", blood value: " .. tostring(bloodValue))
--             end
--         else
--             print("No covered parts found for this clothing item.")
--         end
--     end
-- end

function RD_HygieneManager.consumeHygieneProduct()
    local groin = RD_zapi.getBodyPart(BodyPartType.Groin)

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

    -- print("Value didConsumeSanitaryItem: " .. tostring(didConsumeSanitaryItem))
    -- if not didConsumeSanitaryItem then
    --     -- If sanitary item was not consumed, assuming it leaked and made clothes and player dirty/bloody
    --     print("Sanitary item was not consumed, adding blood to player clothes and body")
    --     addBloodToClothes(player, true, true)
    -- end
    return false -- No sanitary item equipped and no bandage
end

return RD_HygieneManager
