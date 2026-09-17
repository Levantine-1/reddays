-- Red Days Server Commands
-- Handles multiplayer synchronization for item modifications
-- This file must be in the server folder to receive client commands

require "RD_config"
require "RD_stains"

-- Same gate as client/RD_game_api.lua's RD_zapi.log, kept local since server/ never loads client/ Lua.
local function rdLog(msg)
    if RD_Config and RD_Config.verboseLog then print(msg) end
end

rdLog("[RedDays] Server commands loading...")

local RD_ServerCommands = {}
local Commands = {}

-- Finds an item by ID among the player's worn items, then top-level inventory.
-- Items nested inside a bag are not reached.
local function findPlayerItemById(player, itemId)
    local wornItems = player:getWornItems()
    if wornItems then
        for i = 0, wornItems:size() - 1 do
            local wornItem = wornItems:get(i)
            if wornItem and wornItem:getItem() then
                local checkItem = wornItem:getItem()
                if checkItem:getID() == itemId then
                    return checkItem
                end
            end
        end
    end

    local inventory = player:getInventory()
    if inventory then
        local items = inventory:getItems()
        for i = 0, items:size() - 1 do
            local checkItem = items:get(i)
            if checkItem and checkItem:getID() == itemId then
                return checkItem
            end
        end
    end
    return nil
end

-- Command to update sanitary item condition and name
function Commands.updateSanitaryItem(player, args)
    if not player or not args then return end

    local itemId = args.itemId
    local newCondition = args.newCondition
    local newName = args.newName

    if not itemId then return end

    local item = findPlayerItemById(player, itemId)

    if not item then
        rdLog("[RedDays] Server: Could not find item with ID " .. tostring(itemId))
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

-- Command to apply PMS stat effects server-side (agitation, fatigue, food cravings, sadness).
-- CharacterStat is server-authoritative in MP: the hosted-MP self-test showed a client's direct
-- stats:set() reverted by the server. The client sends the STEP it applied locally, and this
-- applies it to the server's own live value with the same clamps as RD_effects_pms.lua, so the
-- server's own stat changes in between are never overwritten.
local function numberOrNil(v)
    if type(v) == "number" then return v end
    return nil
end

function Commands.applyPMSStats(player, args)
    if not player or not args then return end
    local stats = player:getStats()
    if not stats then return end

    local angerTarget, angerStep = numberOrNil(args.angerTarget), numberOrNil(args.angerStep)
    if angerTarget and angerStep then
        stats:set(CharacterStat.ANGER, math.min(angerTarget, stats:get(CharacterStat.ANGER) + angerStep))
    end

    local enduranceDelta = numberOrNil(args.enduranceDelta)
    if enduranceDelta then
        local v = stats:get(CharacterStat.ENDURANCE) + enduranceDelta
        stats:set(CharacterStat.ENDURANCE, math.max(0, math.min(1, v)))
    end

    local fatigueDelta = numberOrNil(args.fatigueDelta)
    if fatigueDelta then
        local v = stats:get(CharacterStat.FATIGUE) + fatigueDelta
        stats:set(CharacterStat.FATIGUE, math.max(0, math.min(1, v)))
    end

    local hungerFloor = numberOrNil(args.hungerFloor)
    if hungerFloor and stats:get(CharacterStat.HUNGER) < hungerFloor then
        stats:set(CharacterStat.HUNGER, hungerFloor)
    end

    local unhappinessTarget, unhappinessStep = numberOrNil(args.unhappinessTarget), numberOrNil(args.unhappinessStep)
    if unhappinessTarget and unhappinessStep then
        local current = stats:get(CharacterStat.UNHAPPINESS)
        if current < unhappinessTarget then
            stats:set(CharacterStat.UNHAPPINESS, math.min(100, current + unhappinessStep))
        elseif current > unhappinessTarget then
            stats:set(CharacterStat.UNHAPPINESS, math.max(0, current - unhappinessStep))
        end
    end
end

-- Command to apply period blood/dirt stains server-side. Body and clothing visuals are
-- server-authoritative in MP: the hosted self-test showed client-only stains never reaching the
-- server. The client sends what it stained; this repeats the same spread (shared/RD_stains.lua)
-- on the server's copy and syncs it the way vanilla's washing actions do (ISWashClothing,
-- ISWashYourself).
function Commands.applyStains(player, args)
    if not player or not args or not RD_Stains then return end
    local blood, dirt = args.blood == true, args.dirt == true
    local maxTier, maxLevel = numberOrNil(args.maxTier), numberOrNil(args.maxLevel)
    if not (blood or dirt) or not maxTier or not maxLevel then return end
    maxTier = math.max(0, math.min(#RD_Stains.TIERS, math.floor(maxTier)))
    maxLevel = math.max(0, math.min(RD_Stains.MAX, maxLevel))

    local stained = RD_Stains.apply(player, blood, dirt, maxTier, maxLevel)
    for _, item in ipairs(stained) do
        syncItemFields(player, item)
    end
    syncVisuals(player)
    sendHumanVisual(player)
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

-- ================= SELF-TEST (RD_Config.selftest only) =================
-- Server half of client/RD_selftest.lua. Registered only when the flag is on. In SP these run
-- through the engine's local command loopback against the same player object.
-- RD_Config can be nil if PZ wasn't fully restarted after RD_config.lua was added; a crash here
-- would also skip registering OnClientCommand below and break every MP sync command.
if not RD_Config then
    print("[RedDays] Server: RD_config.lua not loaded (restart the game fully) -- self-test commands off")
end
if RD_Config and RD_Config.selftest then
    local SELFTEST_ITEMS = {
        -- Two antibiotics: actions() asks for a stage-1 dose and a toxic-shock dose.
        "Base.Pills", "Base.Antibiotics", "Base.Antibiotics", "Base.Cheese", "Base.Milk", "RedDays.Tampon",
    }
    local TRACED_ACTIONS = {
        "ISEatFoodAction", "ISDrinkFluidAction", "ISTakePillAction", "ISUnequipAction", "ISWearClothing",
    }

    -- Admins and debug sessions only, using vanilla's own check (server/ClientCommands.lua).
    -- SP has no other players, so the loopback is always allowed.
    local function selftestAllowed(player)
        if not isServer() then return true end
        if isDebugEnabled() then return true end
        local ok, role = pcall(function() return player:getRole() end)
        return ok and role ~= nil and role:hasCapability(Capability.AddItem)
    end

    function Commands.rdTestProbe(player, args)
        if not player or not args then return end
        if not selftestAllowed(player) then
            print("[RD-TEST][server] rdTestProbe refused ---- not admin and not in debug mode")
            return
        end
        local stats = player:getStats()
        local bd = player:getBodyDamage()
        local md = player:getModData()
        local ic = md and md.ICdata
        local tss = ic and ic.tss
        local visual = player:getHumanVisual()
        local reply = {
            nonce = args.nonce,
            side = isServer() and "server" or "local",
            icNonce = ic and ic._selftest_nonce,
            fatigue = stats and stats:get(CharacterStat.FATIGUE),
            unhappiness = stats and stats:get(CharacterStat.UNHAPPINESS),
            thirst = stats and stats:get(CharacterStat.THIRST),
            sickness = stats and stats:get(CharacterStat.SICKNESS),
            anger = stats and stats:get(CharacterStat.ANGER),
            hunger = stats and stats:get(CharacterStat.HUNGER),
            endurance = stats and stats:get(CharacterStat.ENDURANCE),
            health = bd and bd:getHealth(),
            upperTorsoStiffness = bd and bd:getBodyPart(BodyPartType.Torso_Upper):getStiffness(),
            groinBlood = visual and visual:getBlood(BloodBodyPartType.Groin),
            groinDirt = visual and visual:getDirt(BloodBodyPartType.Groin),
            itemCondition = -1,
            tssStage = tss and tss.stage or -1,
            abxDoses = tss and tss.abx_dose_count or -1,
            foodPct = ic and ic.food_pms_reduction_pct or -1,
            journalID = ic and ic.journalID,
        }
        if args.itemId and args.itemId ~= -1 then
            local item = findPlayerItemById(player, args.itemId)
            if item then
                reply.itemCondition = item:getCondition()
                reply.itemName = item:getName()
            end
        end
        if args.clothingId and args.clothingId ~= -1 then
            local garment = findPlayerItemById(player, args.clothingId)
            if garment then
                reply.garmentBlood = garment:getBlood(BloodBodyPartType.Groin)
                reply.garmentDirt = garment:getDirt(BloodBodyPartType.Groin)
            end
        end
        print("[RD-TEST][server] probe answered ---- side=" .. reply.side .. " health=" .. tostring(reply.health)
            .. " tssStage=" .. tostring(reply.tssStage) .. " abxDoses=" .. tostring(reply.abxDoses))
        if isServer() then
            sendServerCommand(player, "RedDays", "rdTestProbeReply", reply)
        elseif RD_SelfTest and RD_SelfTest.onServerCommand then
            -- SP: the sendServerCommand global returns unless GameServer.serverZ (confirmed via
            -- bytecode), so a reply sent that way is lost. Client and server share one Lua state
            -- here, so hand the reply to the client handler directly.
            RD_SelfTest.onServerCommand("RedDays", "rdTestProbeReply", reply)
        end
    end

    function Commands.rdTestGiveItems(player, args)
        if not player then return end
        if not selftestAllowed(player) then
            print("[RD-TEST][server] rdTestGiveItems refused ---- not admin and not in debug mode")
            return
        end
        local inventory = player:getInventory()
        for _, fullType in ipairs(SELFTEST_ITEMS) do
            local item = inventory:AddItem(fullType)
            if item and isServer() then sendAddItemToContainer(inventory, item) end
        end
        print("[RD-TEST][server] gave test items ---- " .. table.concat(SELFTEST_ITEMS, " "))
    end

    -- complete() runs only here in MP; log it so the client log's perform lines can be matched
    -- up. In SP the client-side tracer already sees complete(), so this would only duplicate.
    if isServer() then
        for _, className in ipairs(TRACED_ACTIONS) do
            local class = _G[className]
            if class and type(class.complete) == "function" then
                local original = class.complete
                class.complete = function(self)
                    local ok, fullType = pcall(function() return self.item:getFullType() end)
                    print("[RD-TEST][server] " .. className .. " complete fired server-side ---- "
                        .. (ok and tostring(fullType) or "unknown"))
                    return original(self)
                end
            end
        end
    end

    print("[RD-TEST][server] self-test commands registered")
end

-- Command handler for OnClientCommand event
RD_ServerCommands.OnClientCommand = function(module, command, player, args)
    if module == 'RedDays' and Commands[command] then
        Commands[command](player, args)
    end
end

Events.OnClientCommand.Add(RD_ServerCommands.OnClientCommand)

rdLog("[RedDays] Server: Event handler registered")

return RD_ServerCommands
