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

    if not wasItemConsumed then
        RD_HygieneManager.addDirtStains()
    end
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

-- Blood/dirt stain spreading for body and clothing
-- Stains spread from groin outward: groin → both thighs → both shins
-- blood = true adds blood, dirt = true adds dirt
-- Each tier is a group of body parts that stain together
local STAIN_TIERS = {
    { BloodBodyPartType.Groin },
    { BloodBodyPartType.UpperLeg_L, BloodBodyPartType.UpperLeg_R },
    { BloodBodyPartType.LowerLeg_L, BloodBodyPartType.LowerLeg_R },
    { BloodBodyPartType.Foot_L, BloodBodyPartType.Foot_R },
}

local STAIN_INCREMENT = 0.03 -- How much dirt to add per call (dirt still increments since it's groin-only)
local STAIN_MAX = 1.0

-- Maps leak moodle level to target blood intensity and max tier
-- LeakLevel: 0.42 = clear, ~0.4 = lvl1, ~0.3 = lvl2, ~0.2 = lvl3, ~0.0 = lvl4
-- Each entry: { maxBloodLevel, maxTier }
local LEAK_TO_STAIN = {
    { threshold = 0.4, maxBlood = 0.0,  maxTier = 0 }, -- No moodle visible, no stains
    { threshold = 0.3, maxBlood = 0.25, maxTier = 1 }, -- Lvl 1: light groin stain
    { threshold = 0.2, maxBlood = 0.50, maxTier = 2 }, -- Lvl 2: groin + thighs
    { threshold = 0.1, maxBlood = 0.75, maxTier = 3 }, -- Lvl 3: groin + thighs + shins
    { threshold = 0.0, maxBlood = 1.0,  maxTier = 4 }, -- Lvl 4: full saturation, all tiers
}

local function getStainParamsFromLeakLevel()
    local leakLevel = 0.42 -- default: no leak
    if RD_modData and RD_modData.ICdata and type(RD_modData.ICdata.LeakLevel) == "number" then
        leakLevel = RD_modData.ICdata.LeakLevel
    end

    for _, entry in ipairs(LEAK_TO_STAIN) do
        if leakLevel >= entry.threshold then
            return entry.maxBlood, entry.maxTier
        end
    end
    -- Fully leaked
    return 1.0, #STAIN_TIERS
end

local function addStainToClothingPart(item, bodyPart, blood, dirt, maxLevel)
    -- Check if the clothing covers this body part
    local coveredParts = RD_zapi.getClothingCoveredParts(item)
    if not coveredParts then return false end
    maxLevel = maxLevel or STAIN_MAX

    for i = 0, coveredParts:size() - 1 do
        local coveredPart = coveredParts:get(i)
        if coveredPart == bodyPart then
            if blood then
                local current = item:getBlood(coveredPart)
                if current < maxLevel then
                    item:setBlood(coveredPart, math.min(maxLevel, current + STAIN_INCREMENT))
                end
            end
            if dirt then
                local current = item:getDirt(coveredPart)
                if current < maxLevel then
                    item:setDirt(coveredPart, math.min(maxLevel, current + STAIN_INCREMENT))
                end
            end
            return true
        end
    end
    return false
end

local function addStainsToBodyAndClothes(blood, dirt, maxTier, maxLevel)
    local visual = RD_zapi.getHumanVisual()
    local wornItems = RD_zapi.getWornItems()
    if not visual or not wornItems then return end

    maxTier = maxTier or #STAIN_TIERS
    maxLevel = maxLevel or STAIN_MAX
    if maxTier <= 0 then return end

    -- Apply stains to each allowed tier
    for tierIndex = 1, math.min(maxTier, #STAIN_TIERS) do
        local tier = STAIN_TIERS[tierIndex]

        for _, bodyPart in ipairs(tier) do
            local bodyBlood = blood and visual:getBlood(bodyPart) or 0
            local bodyDirt = dirt and visual:getDirt(bodyPart) or 0

            if blood and bodyBlood < maxLevel then
                print("Adding blood stain to body part " .. tostring(bodyPart) .. " (target: " .. maxLevel .. ")")
                visual:setBlood(bodyPart, math.min(maxLevel, bodyBlood + STAIN_INCREMENT))
            end
            if dirt and bodyDirt < maxLevel then
                print("Adding dirt stain to body part " .. tostring(bodyPart))
                visual:setDirt(bodyPart, math.min(maxLevel, bodyDirt + STAIN_INCREMENT))
            end

            -- Add stain to any worn clothing covering this body part
            for i = 0, wornItems:size() - 1 do
                local wornItem = wornItems:get(i)
                if wornItem and wornItem:getItem() then
                    local clothingItem = wornItem:getItem()
                    if RD_zapi.isClothingItem(clothingItem) and clothingItem:getBloodClothingType() then
                        local wasStained = addStainToClothingPart(clothingItem, bodyPart, blood, dirt, maxLevel)
                        if wasStained then
                            print("Adding stains to clothing item " .. clothingItem:getName() .. " covering body part " .. tostring(bodyPart) .. " Stain Type: " .. (blood and "Blood " or "") .. (dirt and "Dirt" or ""))
                        end
                    end
                end
            end
        end
    end

    -- Update visuals so stains render
    RD_zapi.resetPlayerModel()
end

function RD_HygieneManager.addBloodStains()
    -- Blood intensity and spread are driven by the leak moodle level
    local maxBlood, maxTier = getStainParamsFromLeakLevel()
    if maxTier > 0 and maxBlood > 0 then
        addStainsToBodyAndClothes(true, false, maxTier, maxBlood)
    end
end

function RD_HygieneManager.addDirtStains()
    addStainsToBodyAndClothes(false, true, 1, STAIN_MAX) -- Dirt only stains groin, no cap
end

function RD_HygieneManager.consumeHygieneProduct()
    local groin = RD_zapi.getBodyPart(BodyPartType.Groin)

    isSanitaryItemEquipped, didConsumeSanitaryItem = consumeSanitaryItem()
    if isSanitaryItemEquipped then
        local bleedingTime = groin:getBleedingTime()
        if bleedingTime == 0 and didConsumeSanitaryItem then
            groin:setBleeding(false) -- Clear bleeding if no wounds. Cycle generates bleeding time of 0, so assumed no wounds.
        end
        if not didConsumeSanitaryItem then
            -- Sanitary item leaked - add blood stains to body and clothes
            RD_HygieneManager.addBloodStains()
        end
        return didConsumeSanitaryItem -- Returns true if sanitary item was consumed and no leak occurred
    elseif groin:bandaged() then
        current_bandageLife = groin:getBandageLife()
        groin:setBandageLife(current_bandageLife - 0.1)
        return true -- Always returns true because player could bleed to death if they have other injuries. Setting to false could remove the bandage.
    end

    -- No sanitary item equipped and no bandage - blood stains on body/clothes
    RD_HygieneManager.addBloodStains()
    return false
end

return RD_HygieneManager
