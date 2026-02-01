CycleDebugger = {}
require "cycle_tracker_logic"
require "cycle_manager"
require "hygiene_manager"
require "game_api"

local MINUTES_PER_DAY = 1440

-- Don't use colons in strings here because the game won't print the whole string before a colon
local function PrintStatus(cycle)
    print("=========================== Generated menstrual cycle details ==============================")
    local currentDay = zapi.getGameTime("getWorldAgeHours") / 24
    print("Current time in days -------------------- " .. currentDay)

    print("The reason for last cycle generation ---- " .. cycle.reason_for_cycle)
    print("Cycle delayed (first spawn delay used) -- " .. tostring(modData.ICdata.cycleDelayed or false))
    print("Current phase --------------------------- " .. cycle.current_phase)
    print("Phase minutes remaining ----------------- " .. cycle.phase_minutes_remaining .. " mins (" .. (cycle.phase_minutes_remaining / MINUTES_PER_DAY) .. " days)")
    print("Total cycle duration -------------------- " .. (cycle.cycle_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.cycle_duration_mins .. " mins)")

    print("Red phase duration ---------------------- " .. (cycle.redPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.redPhase_duration_mins .. " mins)")
    print("Follicular phase duration --------------- " .. (cycle.follicularPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.follicularPhase_duration_mins .. " mins)")
    print("Ovulation phase duration ---------------- " .. (cycle.ovulationPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.ovulationPhase_duration_mins .. " mins)")
    print("Luteal phase duration ------------------- " .. (cycle.lutealPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.lutealPhase_duration_mins .. " mins)")

    local currentPhase = CycleManager.getCurrentCyclePhase(cycle)
    print("Current cycle phase (from func) --------- " .. currentPhase)
    if not cycle.healthEffectSeverity then return end
    print("Target Health Effect Severity ----------- " .. cycle.healthEffectSeverity)

    local sanitaryItem = HygieneManager.getCurrentlyWornSanitaryItem()
    if sanitaryItem then
        print("Currently worn sanitary item ------------ " .. sanitaryItem:getName())
        print("Sanitary item condition ----------------- " .. sanitaryItem:getCondition())
    else
        print("Currently worn sanitary item ------------ None")
    end

    local phaseStatus = CycleManager.getPhaseStatus(cycle)
    if phaseStatus then
        print("Phase Status ---------------------------- " .. phaseStatus.phase)
        print("Time remaining in current phase --------- " .. phaseStatus.time_remaining .. " days (" .. phaseStatus.time_remaining_mins .. " mins)")
        print("Phase percent complete ------------------ " .. phaseStatus.percent_complete .. "%")
    else
        print("No valid phase status found for the current cycle.")
    end

    local dataCodes = CycleTrackerLogic.getDataCodes(cycle)
    if dataCodes then
        print("Data codes for the current phase -------- " .. table.concat(dataCodes, ", "))
    else
        print("No data codes available for the current cycle phase.")
    end
    print("PMS Duration ---------------------------- " .. tostring(cycle.pms_duration_mins / MINUTES_PER_DAY) .. " days (" .. tostring(cycle.pms_duration_mins) .. " mins)")
    print("PMS Severity ---------------------------- " .. tostring(CycleManager.getPMSseverity()))
    print("PMS Symptom - Agitation ----------------- " .. tostring(cycle.pms_agitation))
    print("PMS Symptom - Cramps -------------------- " .. tostring(cycle.pms_cramps))
    print("PMS Symptom - Fatigue ------------------- " .. tostring(cycle.pms_fatigue))
    print("PMS Symptom - Tender Breasts ------------ " .. tostring(cycle.pms_tenderBreasts))
    print("PMS Symptom - Crave Food ---------------- " .. tostring(cycle.pms_craveFood))
    print("PMS Symptom - Sadness ------------------- " .. tostring(cycle.pms_Sadness))
    print("This log output was formatted to be read in a separate terminal window with a monospace font, not the in-game console.")
    print("==========================================================================================")
end
-- Events.OnGameStart.Add(PrintStatus(modData.ICdata.currentCycle)) Sometimes this prints before the cycle is generated, so we call it in main() instead.


function CycleDebugger.printWrapper() -- Wrapper to control printing frequency when running from main function
    local cycle = modData.ICdata.currentCycle
    if not cycle then return end
    PrintStatus(cycle)
    -- There used to be a lot more logic here, but keeping this to keep it consistent.
end
return CycleDebugger