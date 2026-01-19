require "RedDays/cycle_manager"
require "RedDays/effects_manager"
require "RedDays/hygiene_manager"

-- local function setOldCycle() -- Test old cycle structure before publishing updates
--     local player = getPlayer()
--     if not player then return end
--     modData = player:getModData()

--     print("Setting old cycle values for testing purposes.")
--     oldCycle = {
--         cycle_start_day = getGameTime():getWorldAgeHours() / 24,
--         cycle_duration = 28,
--         follicular_duration = 14,
--         red_days_duration = 4,
--         follicle_stimulating_start_day = 5,
--         follicle_stimulating_duration = 10,
--         ovulation_duration = 1,
--         ovulation_day = 14,
--         luteal_start_day = 15,
--         luteal_duration = 14,
--         stiffness_target = 55,
--         stiffness_increment = 2,
--         discomfort_target = 100,
--         endurance_decrement = 0.0005,
--         fatigue_increment = 0.0001,
--         reason_for_cycle = "defaultCycle",
--         timeToDelaycycle = 0
--     }
--     modData.ICdata.currentCycle = oldCycle
-- end
-- Events.OnGameStart.Add(setOldCycle)

local function LoadPlayerData()
	local player = getPlayer()
	modData = player:getModData()
	modData.ICdata = modData.ICdata or {}
    modData.ICdata.currentCycle = modData.ICdata.currentCycle or CycleManager.newCycle("LoadPlayerData") -- Initialize the current cycle or generate a new one if it doesn't exist
    if not CycleManager.isCycleValid(modData.ICdata.currentCycle) then
        print("Cycle data structure mismatch! This could be due to a mod update. Regenerating cycle...")
        modData.ICdata.currentCycle = CycleManager.newCycle("LoadPlayerData_afterValidation")
    end
end
Events.OnGameStart.Add(LoadPlayerData)

local function phaseIsValid(phase)
    local valid_phases = {"delayPhase", "redPhase", "follicularPhase", "ovulationPhase", "lutealPhase"}
    for _, valid_phase in ipairs(valid_phases) do
        if phase == valid_phase then
            return true
        end
    end
    return false
end

local function main()
    local cycle = modData.ICdata.currentCycle
    local current_phase = CycleManager.getCurrentCyclePhase(cycle)
    if not phaseIsValid(current_phase) then
        print("Invalid cycle phase detected: " .. current_phase .. ". Regenerating cycle...")
        reason_for_newCycle = "main_afterInvalidPhase_" .. current_phase
        modData.ICdata.currentCycle = CycleManager.newCycle(reason_for_newCycle)
        print("New cycle generated. Current cycle start day: " .. modData.ICdata.currentCycle.cycle_start_day)
        cycle = modData.ICdata.currentCycle
    end
    EffectsManager.determineEffects(cycle) -- Apply effects based on the current cycle phase
    CycleDebugger.printWrapper(cycle)
end
Events.EveryTenMinutes.Add(main)
