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
local STIFFNESS_MIN = 0
local STIFFNESS_MAX = 100
local function clampStiffness(v)
    if type(v) ~= "number" then return nil end
    return math.max(STIFFNESS_MIN, math.min(STIFFNESS_MAX, v))
end

function Commands.applyBodyStiffness(player, args)
    if not player or not args then return end
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    local v
    v = clampStiffness(args.Torso_Lower)
    if v ~= nil then bodyDamage:getBodyPart(BodyPartType.Torso_Lower):setStiffness(v) end
    v = clampStiffness(args.Groin)
    if v ~= nil then bodyDamage:getBodyPart(BodyPartType.Groin):setStiffness(v) end
    v = clampStiffness(args.Torso_Upper)
    if v ~= nil then bodyDamage:getBodyPart(BodyPartType.Torso_Upper):setStiffness(v) end
end

-- Command to apply TSS (toxic shock) CharacterStat/BodyDamage/blur changes server-side.
-- Same reasoning as applyBodyStiffness above: CharacterStat and BodyDamage are server-authoritative,
-- so a client's direct stats:set()/bd:ReduceGeneralHealth() calls get silently overwritten by the
-- next server sync on a real dedicated-server client. RD_tss_manager.lua applies these locally too
-- (for instant client-side feedback) and additionally sends this command so the server's own copy
-- converges to the same value instead of reverting it later.
function Commands.applyTSSStats(player, args)
    if not player or not args then return end
    local stats = player:getStats()
    if stats then
        if args.sickness ~= nil then stats:set(CharacterStat.SICKNESS, args.sickness) end
        if args.endurance ~= nil then stats:set(CharacterStat.ENDURANCE, args.endurance) end
        if args.fatigue ~= nil then stats:set(CharacterStat.FATIGUE, args.fatigue) end
        if args.thirst ~= nil then stats:set(CharacterStat.THIRST, args.thirst) end
        if args.unhappiness ~= nil then stats:set(CharacterStat.UNHAPPINESS, args.unhappiness) end
        -- Delta, not absolute -- accumulated client-side across many ApplyFeverPressure ticks and
        -- flushed once per game-minute, so this stays commutative regardless of send timing.
        if args.temperatureAdd ~= nil then stats:add(CharacterStat.TEMPERATURE, args.temperatureAdd) end
    end

    -- Stage 4 HP drain/regen: replicate the exact branch the client took, using the SERVER's own
    -- live health (not a client-supplied absolute), so any prior client/server drift self-corrects.
    if args.hpMode then
        local bd = player:getBodyDamage()
        if bd then
            if args.hpMode == "abx_cap_sickness_drain" or args.hpMode == "abx_flat_drain" then
                -- ABX active: floor at the cap either way -- "at/below the cap the player
                -- cannot die" must hold for both the sickness-scaled and flat-trickle drain.
                bd:ReduceGeneralHealth(args.hpDrain or 0)
                if (bd:getHealth() or 0) < (args.hpCap or 0) then
                    bd:setOverallBodyHealth(args.hpCap)
                end
            elseif args.hpMode == "abx_sleep_regen" then
                local health = bd:getHealth() or 0
                bd:setOverallBodyHealth(math.min(args.hpCap or health, health + (args.hpDrain or 0)))
            else -- stage4_sleep_drain, stage4_sickness_drain (no ABX -- can be lethal)
                bd:ReduceGeneralHealth(args.hpDrain or 0)
            end
        end
    end

    if args.blur ~= nil then
        player:setSleepingTabletEffect(args.blur)
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
