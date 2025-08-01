-- file: hygiene_manager.lua
HygieneManager = {}

cSIHDC_counter = 0
cSIHDC_counter_tgt = 100
cSIHDC_counter_increment = 20

function LoadPlayerData()
    local player = getPlayer()
    if not player then
        --print("[RedDays] LoadPlayerData: No player found")
        return
    end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local globalData = ModData.getOrCreate("RedDays")
    local username = player:getUsername()
    if globalData[username] then
        modData.ICdata = globalData[username]
        --print("[RedDays] LoadPlayerData: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    else
        --print("[RedDays] LoadPlayerData: No global ModData found for " .. username)
    end
    if modData.ICdata.cSIHDC_counter ~= nil then
        cSIHDC_counter = modData.ICdata.cSIHDC_counter
    else
        cSIHDC_counter = 0
        modData.ICdata.cSIHDC_counter = 0
    end
    if modData.ICdata.insertedTampon then
        if not modData.ICdata.insertedTampon.insertionHour or not modData.ICdata.insertedTampon.name or not modData.ICdata.insertedTampon.condition then
            modData.ICdata.insertedTampon = nil
            player:Say("Invalid tampon data detected, resetting.")
        end
    end
    --print("[RedDays] LoadPlayerData: insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    player:transmitModData()
    globalData[username] = modData.ICdata
    ModData.transmit("RedDays")
    --print("[RedDays] LoadPlayerData: Saved to global ModData")
end

local initTicks = 0
function InitializeHygiene()
    local player = getPlayer()
    if not player then
        initTicks = initTicks + 1
        if initTicks > 100 then
            print("[RedDays] InitializeHygiene: No player after 100 ticks, aborting")
            Events.OnTick.Remove(InitializeHygiene)
            return
        end
        --print("[RedDays] InitializeHygiene: No player yet, retrying... (tick " .. initTicks .. ")")
        return
    end
    LoadPlayerData()
    --print("[RedDays] InitializeHygiene: Hygiene initialized")
    Events.OnTick.Remove(InitializeHygiene)
end
Events.OnGameStart.Add(function() Events.OnTick.Add(InitializeHygiene) end)

function HygieneManager.resetHygieneData()
    local player = getPlayer()
    if not player then
        print("[RedDays] resetHygieneData: No player found")
        return
    end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    modData.ICdata.cSIHDC_counter = 0
    cSIHDC_counter = 0
    modData.ICdata.insertedTampon = nil
    player:transmitModData()
    local globalData = ModData.getOrCreate("RedDays")
    globalData[player:getUsername()] = modData.ICdata
    ModData.transmit("RedDays")
    --print("[RedDays] resetHygieneData: Saved to global ModData")
end

function SavePlayerData()
    local player = getPlayer()
    if not player then
        --print("[RedDays] SavePlayerData: No player found")
        return
    end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    modData.ICdata.cSIHDC_counter = cSIHDC_counter or 0
    if isClient() then
        sendClientCommand(player, "RedDays", "syncTampon", modData.ICdata.insertedTampon or {})
    end
    player:transmitModData()
    local globalData = ModData.getOrCreate("RedDays")
    globalData[player:getUsername()] = modData.ICdata
    ModData.transmit("RedDays")
    --print("[RedDays] SavePlayerData: Saved to global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
end
Events.OnSave.Add(SavePlayerData)
Events.EveryTenMinutes.Add(SavePlayerData)

function consumeSanitaryItemHelperDecrementCondition(current_condition, max_cond)
    cSIHDC_counter = cSIHDC_counter + cSIHDC_counter_increment
    if current_condition == max_cond or (current_condition > 1 and cSIHDC_counter > cSIHDC_counter_tgt) then
        current_condition = current_condition - 1
        cSIHDC_counter = 0
    end
    return current_condition
end

function consumeSanitaryItemHelperRenameItemAndLeakChance(data)
    local itemName = data.name
    local baseName = itemName:match("^(.-) %(") or itemName
    local isPantyLiner = (baseName == "Panty Liner")
    local isTampon = (data.hygieneType == "Tampon")
    local max_cond = isPantyLiner and 6 or 10
    local current_condition = data.condition or max_cond
    current_condition = math.min(current_condition, max_cond)
    data.condition = consumeSanitaryItemHelperDecrementCondition(current_condition, max_cond)
    current_condition = data.condition
    data.condition = math.max(0, math.min(data.condition, 10))

    local d20Roll = ZombRand(1, 21)
    if isTampon then
        if current_condition >= 8 then
            data.name = baseName .. " (Slightly Used)"
        elseif current_condition >= 4 then
            data.name = baseName .. " (Used)"
        elseif current_condition >= 2 then
            data.name = baseName .. " (Nearly Saturated)"
        else
            data.name = baseName .. " (Saturated)"
            return false
        end
        return true
    else
        if isPantyLiner then
            if current_condition >= 5 then
                data.name = baseName .. " (Spotty)"
            elseif current_condition == 4 then
                data.name = baseName .. " (Bloody)"
            elseif current_condition == 3 then
                data.name = baseName .. " (Very Bloody)"
            elseif current_condition == 2 then
                data.name = baseName .. " (Nearly Saturated)"
                if d20Roll >= 15 then
                    return false
                end
            elseif current_condition == 1 then
                data.name = baseName .. " (Saturated)"
                if d20Roll >= 10 then
                    return false
                end
            elseif current_condition < 1 then
                data.name = baseName .. " (Saturated)"
                return false
            end
        else
            if current_condition >= 9 then
                data.name = baseName .. " (Spotty)"
            elseif current_condition >= 6 then
                data.name = baseName .. " (Bloody)"
            elseif current_condition >= 4 then
                data.name = baseName .. " (Very Bloody)"
            elseif current_condition == 3 then
                data.name = baseName .. " (Nearly Saturated)"
                if d20Roll >= 15 then
                    return false
                end
            elseif current_condition == 2 then
                data.name = baseName .. " (Nearly Saturated)"
                if d20Roll >= 10 then
                    return false
                end
            elseif current_condition < 2 then
                data.name = baseName .. " (Saturated)"
                return false
            end
        end
    end

    local underwear = getPlayer():getWornItem("UnderwearBottom")
    if underwear then
        underwear:setTooltip("Attached: " .. data.name .. " Condition: " .. data.condition)
    end

    return true
end

function consumeSanitaryItem()
    local player = getPlayer()
    if not player then return false, false end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local globalData = ModData.getOrCreate("RedDays")
    local username = player:getUsername()
    if globalData[username] then
        modData.ICdata = globalData[username]
        --print("[RedDays] consumeSanitaryItem: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    end
    local isSanitaryItemFound = false
    local didConsumeSanitaryItem = false
    if modData.ICdata.insertedTampon then
        isSanitaryItemFound = true
        didConsumeSanitaryItem = consumeSanitaryItemHelperRenameItemAndLeakChance(modData.ICdata.insertedTampon)
    else
        local underwear = player:getWornItem("UnderwearBottom")
        if underwear and underwear:getModData().attachedHygiene then
            isSanitaryItemFound = true
            didConsumeSanitaryItem = consumeSanitaryItemHelperRenameItemAndLeakChance(underwear:getModData().attachedHygiene)
        end
    end
    player:transmitModData()
    globalData[username] = modData.ICdata
    ModData.transmit("RedDays")
    --print("[RedDays] consumeSanitaryItem: Saved to global ModData")
    return isSanitaryItemFound, didConsumeSanitaryItem
end

function HygieneManager.consumeHygieneProduct()
    local player = getPlayer()
    if not player then return false end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local globalData = ModData.getOrCreate("RedDays")
    local username = player:getUsername()
    if globalData[username] then
        modData.ICdata = globalData[username]
        --print("[RedDays] consumeHygieneProduct: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    end
    local isSanitaryItemEquipped, didConsumeSanitaryItem = consumeSanitaryItem()
    if isSanitaryItemEquipped and didConsumeSanitaryItem then
        return true
    end
    return false
end

function HygieneManager.consumeDischargeProduct()
    local player = getPlayer()
    if not player then return false end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local globalData = ModData.getOrCreate("RedDays")
    local username = player:getUsername()
    if globalData[username] then
        modData.ICdata = globalData[username]
        --print("[RedDays] consumeDischargeProduct: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    end
    if modData.ICdata.insertedTampon then
        local data = modData.ICdata.insertedTampon
        if data.condition == nil then
            data.condition = 10
        end
        local wasItemConsumed = data.condition > 1
        data.condition = 1
        data.name = data.name:match("^(.-) %(") or data.name .. " (Dirty)"
        player:transmitModData()
        globalData[username] = modData.ICdata
        ModData.transmit("RedDays")
        --print("[RedDays] consumeDischargeProduct: Saved to global ModData")
        return wasItemConsumed
    else
        local underwear = player:getWornItem("UnderwearBottom")
        if underwear and underwear:getModData().attachedHygiene then
            local data = underwear:getModData().attachedHygiene
            local baseName = data.name:match("^(.-) %(") or data.name
            if data.condition == nil then
                data.condition = (baseName == "Panty Liner") and 6 or 10
            end
            local wasItemConsumed = data.condition > 1
            data.condition = 1
            data.name = baseName .. " (Dirty)"
            if underwear then
                underwear:setTooltip("Attached: " .. data.name .. " Condition: " .. data.condition)
            end
            player:transmitModData()
            globalData[username] = modData.ICdata
            ModData.transmit("RedDays")
            --print("[RedDays] consumeDischargeProduct: Saved to global ModData")
            return wasItemConsumed
        end
    end
    return false
end

if isServer() or not isClient() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module == "RedDays" and command == "syncTampon" then
            if not player then
                --print("[RedDays] syncTampon: No player found")
                return
            end
            local modData = player:getModData()
            modData.ICdata = modData.ICdata or {}
            modData.ICdata.insertedTampon = args.name and args or nil
            player:transmitModData()
            local globalData = ModData.getOrCreate("RedDays")
            globalData[player:getUsername()] = modData.ICdata
            ModData.transmit("RedDays")
            --print("[RedDays] syncTampon: Saved to global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
        end
    end)
end

return HygieneManager