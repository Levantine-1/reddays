require "RedDays/cycle_manager"
require "RedDays/effects_manager"
require "RedDays/hygiene_manager"

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

-- NOTE: 2025-07-24 Disabled because this gets run on every load which means you always start on the first day of the cycle.
-- local function ResetCycleData()
--     print("Resetting cycle data...")
--     EffectsManager.resetEffects()
--     HygieneManager.resetHygieneData()
--     -- modData.ICdata.currentCycle = CycleManager.newCycle("ResetCycleData")
--     -- Disabled new cycle because this was running on every load which meant you always started on the
--     -- first day of the cycle. I guess this is a bug that could be a feature where a new character
--     -- continues the cycle from the previous character so new characters don't always start on red day.
-- end
-- Events.OnCreatePlayer.Add(ResetCycleData)

local function PrintStatus(cycle)
    print("================================== Generated menstrual cycle details: ==================================")
    local currentDay = getGameTime():getWorldAgeHours() / 24
    print("Current time in days: " .. currentDay)

    print("The reason for last cycle generation: " .. cycle.reason_for_cycle)
    print("Cycle Delayed time: " .. cycle.timeToDelaycycle .. " days")
    print("Cycle start day: " .. cycle.cycle_start_day)
    print("Total expected menstrual cycle duration: " .. cycle.cycle_duration .. " days")

    print("Follicular phase start day: " .. cycle.cycle_start_day)
    print("Total Follicular phase duration: " .. cycle.follicular_duration .. " days")

    print("Red phase duration: " .. cycle.red_days_duration .. " days")

    print("Follicle stimulating phase start day: " .. cycle.follicle_stimulating_start_day)
    print("Follicle stimulating phase duration: " .. cycle.follicle_stimulating_duration .. " days")

    print("Ovulation day: " .. cycle.ovulation_day .. " days after the start of the cycle")
    print("Ovulation phase duration: " .. cycle.ovulation_duration .. " days")

    print("Luteal phase start day: " .. cycle.luteal_start_day)
    print("Luteal phase duration: " .. cycle.luteal_duration .. " days")

    local days_into_cycle = currentDay - cycle.cycle_start_day
    print("Days into current cycle: " .. days_into_cycle)

    local currentPhase = CycleManager.getCurrentCyclePhase(cycle)
    print("Current cycle phase: " .. currentPhase)
    local sanitaryItem = HygieneManager.getCurrentlyWornSanitaryItem()
    if sanitaryItem then
        print("Currently worn sanitary item: " .. sanitaryItem:getName())
        print("Sanitary item condition: " .. sanitaryItem:getCondition())
    else
        print("No sanitary item currently worn.")
    end
    print("==========================================================================================")
end
-- Events.OnGameStart.Add(PrintStatus(modData.ICdata.currentCycle)) Sometimes this prints before the cycle is generated, so we call it in main() instead.

local print_counter = 0
local hasPrintedOnStart = false
local debugPrinting = true
local function printWrapper(cycle) -- Wrapper to control printing frequency when running from main function
    if debugPrinting then
        PrintStatus(cycle)
    elseif not hasPrintedOnStart then
        PrintStatus(cycle) -- Print status only once at the start
        hasPrintedOnStart = true
    elseif print_counter >= 6 then
        PrintStatus(cycle) -- Print status every 60 minutes (6 * 10 minutes)
        print_counter = 0
    end
    print_counter = print_counter + 1
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
    printWrapper(cycle)
end
Events.EveryTenMinutes.Add(main)
