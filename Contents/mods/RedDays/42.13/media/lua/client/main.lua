require "RedDays/cycle_manager"
require "RedDays/effects_manager"
require "RedDays/hygiene_manager"
Main = {}

function Main.LoadPlayerData()
	local player = getPlayer()
	modData = player:getModData()
	modData.ICdata = modData.ICdata or {}
    modData.ICdata.currentCycle = modData.ICdata.currentCycle or CycleManager.newCycle("LoadPlayerData") -- Initialize the current cycle or generate a new one if it doesn't exist
    if not CycleManager.isCycleValid(modData.ICdata.currentCycle) then
        print("Cycle data structure mismatch! This could be due to a mod update. Regenerating cycle...")
        modData.ICdata.currentCycle = CycleManager.newCycle("LoadPlayerData_afterValidation")
    end
end
-- 2026-01-22 - Hooked into OnGameStart event in events_intercepts.lua

local function phaseIsValid(phase)
    local valid_phases = {"delayPhase", "redPhase", "follicularPhase", "ovulationPhase", "lutealPhase"}
    for _, valid_phase in ipairs(valid_phases) do
        if phase == valid_phase then
            return true
        end
    end
    return false
end

function Main.main()
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

return Main
