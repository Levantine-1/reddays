require "RedDays/cycle_manager"
require "RedDays/effects_manager"
require "RedDays/hygiene_manager"
require "RedDays/cycle_tracker_logic"

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

-- If player unequips the hygiene item, inspect the item and update the cycle tracker
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        CycleTrackerLogic.cycleTrackerMainLogic()
    end
    o_ISUnequipAction_perform(self)
end

-- If the player replaces a hygiene item, inspect the item and update the cycle tracker
local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        local hygieneItem = HygieneManager.getCurrentlyWornSanitaryItem()
        if hygieneItem then
            CycleTrackerLogic.cycleTrackerMainLogic()
        end
    end
    o_ISWearClothing_perform(self)
end

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
