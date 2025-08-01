-- main.lua
require "cycle_manager"
require "effects_manager"
require "hygiene_manager"
require "RedDaysContext"
require "TimedActions/ISUseHygieneItemAction"
require "RedDaysMoodles"

function LoadPlayerData()
    local player = getPlayer()
    if not player or (not SandboxVars.RedDays.affectsAllGenders and not player:isFemale()) then
        print("[RedDays] LoadPlayerData: No player or gender check failed")
        return
    end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local globalData = ModData.getOrCreate("RedDays")
    local username = player:getUsername()
    if globalData[username] then
        modData.ICdata = globalData[username]
        print("[RedDays] LoadPlayerData: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    else
        print("[RedDays] LoadPlayerData: No global ModData found for " .. username)
    end
    if not CycleManager then
        print("[RedDays] LoadPlayerData: CycleManager not defined")
        return
    end
    if not modData.ICdata.currentCycle then
        modData.ICdata.currentCycle = CycleManager.newCycle("LoadPlayerData")
        -- Randomize starting phase by offsetting cycle_start_day
        local cycleDuration = modData.ICdata.currentCycle.cycle_duration or 28 -- Default to 28 days
        local randomOffset = ZombRand(0, cycleDuration) -- Random day within cycle
        modData.ICdata.currentCycle.cycle_start_day = getGameTime():getWorldAgeHours() / 24 - randomOffset
        -- Adjust phase-specific fields
        local currentPhase = CycleManager.getCurrentCyclePhase(modData.ICdata.currentCycle)
        if currentPhase == "redPhase" then
            modData.ICdata.redPhaseStartHour = getGameTime():getWorldAgeHours()
            modData.ICdata.redPhaseGraceHours = ZombRandFloat(0.5, 1.5)
        else
            modData.ICdata.redPhaseStartHour = nil
            modData.ICdata.redPhaseGraceHours = nil
        end
        print("[RedDays] LoadPlayerData: Randomized cycle start day to " .. modData.ICdata.currentCycle.cycle_start_day .. ", phase: " .. currentPhase)
    elseif not CycleManager.isCycleValid(modData.ICdata.currentCycle) then
        print("[RedDays] Cycle data structure mismatch! Regenerating cycle...")
        modData.ICdata.currentCycle = CycleManager.newCycle("LoadPlayerData_afterValidation")
        local cycleDuration = modData.ICdata.currentCycle.cycle_duration or 28
        local randomOffset = ZombRand(0, cycleDuration)
        modData.ICdata.currentCycle.cycle_start_day = getGameTime():getWorldAgeHours() / 24 - randomOffset
        local currentPhase = CycleManager.getCurrentCyclePhase(modData.ICdata.currentCycle)
        if currentPhase == "redPhase" then
            modData.ICdata.redPhaseStartHour = getGameTime():getWorldAgeHours()
            modData.ICdata.redPhaseGraceHours = ZombRandFloat(0.5, 1.5)
        else
            modData.ICdata.redPhaseStartHour = nil
            modData.ICdata.redPhaseGraceHours = nil
        end
        print("[RedDays] LoadPlayerData: Randomized cycle start day to " .. modData.ICdata.currentCycle.cycle_start_day .. ", phase: " .. currentPhase)
    end
    modData.ICdata.redPhaseStartHour = modData.ICdata.redPhaseStartHour or nil
    modData.ICdata.redPhaseGraceHours = modData.ICdata.redPhaseGraceHours or nil
    --print("[RedDays] LoadPlayerData: currentCycle = ", modData.ICdata.currentCycle and modData.ICdata.currentCycle.cycle_start_day or "nil", "insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    player:transmitModData()
    globalData[username] = modData.ICdata
    ModData.transmit("RedDays")
end

local initTicks = 0
function InitializeMod()
    local player = getPlayer()
    if not player then
        initTicks = initTicks + 1
        if initTicks > 100 then
            print("[RedDays] InitializeMod: No player after 100 ticks, aborting")
            Events.OnTick.Remove(InitializeMod)
            return
        end
        print("[RedDays] InitializeMod: No player yet, retrying... (tick " .. initTicks .. ")")
        return
    end
    LoadPlayerData()
    print("[RedDays] InitializeMod: Mod initialized")
    Events.OnTick.Remove(InitializeMod)
end
Events.OnGameStart.Add(function() Events.OnTick.Add(InitializeMod) end)

local function OnSave()
    local player = getPlayer()
    if not player then
        print("[RedDays] OnSave: No player found")
        return
    end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local username = player:getUsername()
    --print("[RedDays] OnSave: Saving modData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil", "currentCycle = ", modData.ICdata.currentCycle and modData.ICdata.currentCycle.cycle_start_day or "nil")
    player:transmitModData()
    local globalData = ModData.getOrCreate("RedDays")
    globalData[username] = modData.ICdata
    ModData.transmit("RedDays")
end
Events.OnSave.Add(OnSave)

local function OnPlayerDeath()
    local player = getPlayer()
    if not player then return end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local username = player:getUsername()
    print("[RedDays] OnPlayerDeath: Saving modData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil", "currentCycle = ", modData.ICdata.currentCycle and modData.ICdata.currentCycle.cycle_start_day or "nil")
    player:transmitModData()
    local globalData = ModData.getOrCreate("RedDays")
    globalData[username] = modData.ICdata
    ModData.transmit("RedDays")
end
Events.OnPlayerDeath.Add(OnPlayerDeath)

local function ResetCycleData()
    local player = getPlayer()
    if not player then
        print("[RedDays] ResetCycleData: No player found")
        return
    end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    print("[RedDays] Resetting cycle data...")
    if EffectsManager then
        EffectsManager.resetEffects()
    else
        print("[RedDays] ResetCycleData: EffectsManager not defined")
    end
    if HygieneManager then
        HygieneManager.resetHygieneData()
    else
        print("[RedDays] ResetCycleData: HygieneManager not defined")
    end
    -- Randomize cycle on reset
    if CycleManager then
        modData.ICdata.currentCycle = CycleManager.newCycle("ResetCycleData")
        local cycleDuration = modData.ICdata.currentCycle.cycle_duration or 28
        local randomOffset = ZombRand(0, cycleDuration)
        modData.ICdata.currentCycle.cycle_start_day = getGameTime():getWorldAgeHours() / 24 - randomOffset
        local currentPhase = CycleManager.getCurrentCyclePhase(modData.ICdata.currentCycle)
        if currentPhase == "redPhase" then
            modData.ICdata.redPhaseStartHour = getGameTime():getWorldAgeHours()
            modData.ICdata.redPhaseGraceHours = ZombRandFloat(0.5, 1.5)
        else
            modData.ICdata.redPhaseStartHour = nil
            modData.ICdata.redPhaseGraceHours = nil
        end
        print("[RedDays] ResetCycleData: Randomized cycle start day to " .. modData.ICdata.currentCycle.cycle_start_day .. ", phase: " .. currentPhase)
    end
    player:transmitModData()
    local globalData = ModData.getOrCreate("RedDays")
    globalData[player:getUsername()] = modData.ICdata
    ModData.transmit("RedDays")
end
Events.OnCreatePlayer.Add(ResetCycleData)

local function PrintStatus()
    local player = getPlayer()
    if not player or (not SandboxVars.RedDays.affectsAllGenders and not player:isFemale()) then return end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local cycle = modData.ICdata.currentCycle
    if not cycle then
        print("[RedDays] PrintStatus: No cycle data")
        return
    end
    print("[RedDays] ================================== Generated menstrual cycle details: ==================================")
    local currentDay = getGameTime():getWorldAgeHours() / 24
    print("[RedDays] Current time in days: " .. currentDay)
    print("[RedDays] The reason for last cycle generation: " .. cycle.reason_for_cycle)
    print("[RedDays] Cycle start day: " .. cycle.cycle_start_day)
    print("[RedDays] Total expected menstrual cycle duration: " .. cycle.cycle_duration .. " days")
    print("[RedDays] Follicular phase start day: " .. cycle.cycle_start_day)
    print("[RedDays] Total Follicular phase duration: " .. cycle.follicular_duration .. " days")
    print("[RedDays] Red phase duration: " .. cycle.red_days_duration .. " days")
    print("[RedDays] Follicle stimulating phase start day: " .. cycle.follicle_stimulating_start_day)
    print("[RedDays] Follicle stimulating phase duration: " .. cycle.follicle_stimulating_duration .. " days")
    print("[RedDays] Ovulation day: " .. cycle.ovulation_day .. " days after the start of the cycle")
    print("[RedDays] Ovulation phase duration: " .. cycle.ovulation_duration .. " days")
    print("[RedDays] Luteal phase start day: " .. cycle.luteal_start_day)
    print("[RedDays] Luteal phase duration: " .. cycle.luteal_duration .. " days")
    local days_into_cycle = currentDay - cycle.cycle_start_day
    print("[RedDays] Days into current cycle: " .. days_into_cycle)
    local currentPhase = CycleManager and CycleManager.getCurrentCyclePhase(cycle) or "unknown"
    print("[RedDays] Current cycle phase: " .. currentPhase)
    print("[RedDays] ==========================================================================================")
end
Events.OnGameStart.Add(PrintStatus)
Events.EveryDays.Add(PrintStatus)

function phaseIsValid(phase)
    local valid_phases = {"redPhase", "follicularPhase", "ovulationPhase", "lutealPhase"}
    for _, valid_phase in ipairs(valid_phases) do
        if phase == valid_phase then
            return true
        end
    end
    return false
end

function main()
    local player = getPlayer()
    if not player or (not SandboxVars.RedDays.affectsAllGenders and not player:isFemale()) then return end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local username = player:getUsername()
    local globalData = ModData.getOrCreate("RedDays")
    if globalData[username] then
        modData.ICdata = globalData[username]
        --print("[RedDays] main: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    end
    local cycle = modData.ICdata.currentCycle
    if not CycleManager then
        print("[RedDays] main: CycleManager not defined")
        return
    end
    local current_phase = CycleManager.getCurrentCyclePhase(cycle)
    if not phaseIsValid(current_phase) then
        print("[RedDays] Invalid cycle phase detected: " .. current_phase .. ". Regenerating cycle...")
        local reason_for_newCycle = "main_afterInvalidPhase_" .. current_phase
        modData.ICdata.currentCycle = CycleManager.newCycle(reason_for_newCycle)
        local cycleDuration = modData.ICdata.currentCycle.cycle_duration or 28
        local randomOffset = ZombRand(0, cycleDuration)
        modData.ICdata.currentCycle.cycle_start_day = getGameTime():getWorldAgeHours() / 24 - randomOffset
        print("[RedDays] main: Randomized cycle start day to " .. modData.ICdata.currentCycle.cycle_start_day)
        cycle = modData.ICdata.currentCycle
        local currentPhase = CycleManager.getCurrentCyclePhase(cycle)
        if currentPhase == "redPhase" then
            modData.ICdata.redPhaseStartHour = getGameTime():getWorldAgeHours()
            modData.ICdata.redPhaseGraceHours = ZombRandFloat(0.5, 1.5)
        else
            modData.ICdata.redPhaseStartHour = nil
            modData.ICdata.redPhaseGraceHours = nil
        end
        player:transmitModData()
        globalData[username] = modData.ICdata
        ModData.transmit("RedDays")
    end

    local lastPhase = modData.ICdata.lastPhase
    
    if lastPhase ~= current_phase then
        modData.ICdata.lastPhase = current_phase
        if current_phase == "redPhase" then
            modData.ICdata.redPhaseStartHour = getGameTime():getWorldAgeHours()
            modData.ICdata.redPhaseGraceHours = ZombRandFloat(0.5, 1.5)
        end
        player:transmitModData()
        globalData[username] = modData.ICdata
        ModData.transmit("RedDays")
    end

    if EffectsManager then
        EffectsManager.determineEffects(cycle)
    end
end
Events.EveryTenMinutes.Add(main)