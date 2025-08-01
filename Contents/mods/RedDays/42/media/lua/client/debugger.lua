CycleDebugger = {}

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

    local phaseStatus = CycleManager.getPhaseStatus(cycle)
    if phaseStatus then
        print("Phase Status: " .. phaseStatus.phase)
        print("Time remaining in current phase: " .. phaseStatus.time_remaining .. " days")
        print("Percentage complete: " .. phaseStatus.percent_complete .. "%")
    else
        print("No valid phase status found for the current cycle.")
    end

    local dataCodes = CycleTrackerLogic.getDataCodes(cycle)
    if dataCodes then
        print("Data codes for the current cycle phase: " .. table.concat(dataCodes, ", "))
    else
        print("No data codes available for the current cycle phase.")
    end
    print("==========================================================================================")
end
-- Events.OnGameStart.Add(PrintStatus(modData.ICdata.currentCycle)) Sometimes this prints before the cycle is generated, so we call it in main() instead.

local print_counter = 0
local hasPrintedOnStart = false -- Don't change this one manually
local debugPrinting = false -- Set to true to enable debug printing every 10 minutes
function CycleDebugger.printWrapper(cycle) -- Wrapper to control printing frequency when running from main function
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

return CycleDebugger