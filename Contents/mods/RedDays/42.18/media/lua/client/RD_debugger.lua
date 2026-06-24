RD_CycleDebugger = RD_CycleDebugger or {}
RDCycleDebugger = RD_CycleDebugger -- Alias for backward compatibility
require "RD_cycle_tracker_logic"
require "RD_cycle_manager"
require "RD_hygiene_manager"
require "RD_game_api"

local MINUTES_PER_DAY = 1440
local MINUTES_PER_HOUR = 60

local function printTSSStatus()
    local sb = SandboxVars.RedDays or {}
    local tss = RD_modData and RD_modData.ICdata and RD_modData.ICdata.tss or nil

    print("--- TSS Diagnostics ---------------------")
    print("TSS enabled ----------------------------- " .. tostring(sb.tss_enabled ~= false))
    print("TSS lethal enabled ---------------------- " .. tostring(sb.tss_lethal_enabled ~= false))
    print("TSS progression speed pct --------------- " .. tostring(sb.tss_progression_speed_pct or 100))
    print("TSS risk multiplier pct ----------------- " .. tostring(sb.tss_risk_multiplier_pct or 100))

    if not tss then
        print("TSS state ------------------------------- unavailable")
        return
    end

    local stage = tss.stage or 0
    local stageLabel = "none"
    if stage == 1 then stageLabel = "warning"
    elseif stage == 2 then stageLabel = "worsening"
    elseif stage == 3 then stageLabel = "critical"
    elseif stage >= 4 then stageLabel = "toxic_shock" end

    local threshold = tss.stage_threshold or 0
    local thresholdDays = threshold / MINUTES_PER_DAY

    print("TSS stage ------------------------------- " .. tostring(stage) .. " (" .. stageLabel .. ")")
    print("TSS stage threshold --------------------- " .. tostring(threshold) .. " mins (" .. string.format("%.2f", thresholdDays) .. " days)")
    print("TSS tss_risk ---------------------------- " .. tostring(tss.tss_risk or 0))
    print("TSS recovery mode ----------------------- " .. tostring(tss.recovery_mode or "none"))
    print("TSS cured flag -------------------------- " .. tostring(tss.cured or false))
    print("TSS source active ----------------------- " .. tostring(tss.source_active or false))
    print("TSS source removed ---------------------- " .. tostring(tss.source_removed or false))
    print("TSS source type ------------------------- " .. tostring(tss.source_type or ""))
    print("TSS source item id ---------------------- " .. tostring(tss.source_item_id or -1))
    print("TSS wear minutes ------------------------ " .. tostring(tss.wear_minutes or 0) .. " mins (" .. tostring((tss.wear_minutes or 0) / MINUTES_PER_HOUR) .. " hours)")
    local expMin = tss.exposure_minutes or 0
    print("TSS exposure minutes -------------------- " .. tostring(expMin) .. " mins (" .. string.format("%.2f", expMin / MINUTES_PER_HOUR) .. " hours / " .. string.format("%.2f", expMin / MINUTES_PER_DAY) .. " days)")
    local untMin = tss.untreated_minutes or 0
    print("TSS untreated minutes ------------------- " .. tostring(untMin) .. " mins (" .. string.format("%.2f", untMin / MINUTES_PER_HOUR) .. " hours / " .. string.format("%.2f", untMin / MINUTES_PER_DAY) .. " days)")
    print("TSS first symptom minutes --------------- " .. tostring(tss.first_symptom_minutes or 0))
    print("TSS warning cooldown -------------------- " .. tostring(tss.warning_cooldown or 0))
    print("TSS stabilized until -------------------- " .. tostring(tss.stabilized_until or 0))
    print("TSS treatment flags --------------------- ABX=" .. tostring(tss.antibiotics_taken_recently or false) .. ", DIS=" .. tostring(tss.disinfectant_recently or false) .. ", ALC=" .. tostring(tss.alcohol_recently or false))
    print("TSS counters ---------------------------- rolls=" .. tostring(tss.tss_rolls or 0) .. ", treatmentAttempts=" .. tostring(tss.treatment_attempts or 0))

    local player = RD_zapi.getPlayer()
    if player then
        print("TSS current corpse sickness rate -------- " .. tostring(player:getCorpseSicknessRate()))
        print("TSS current blur effect ----------------- " .. tostring(player:getSleepingTabletEffect()))
        print("TSS baseline blur effect ---------------- " .. tostring(tss.baseline_blur_effect or 0))
    else
        print("TSS current corpse sickness rate -------- unavailable")
        print("TSS current blur effect ----------------- unavailable")
        print("TSS baseline blur effect ---------------- " .. tostring(tss.baseline_blur_effect or 0))
    end
end

-- Don't use colons in strings here because the game won't print the whole string before a colon
local function PrintStatus(cycle)
    print("=========================== Generated menstrual cycle details ==============================")
    print("Mod version ----------------------------- 42.18")
    local mpMode = "singleplayer"
    if isClient() then mpMode = "client (multiplayer)"
    elseif isServer() then mpMode = "server (multiplayer)" end
    print("Session mode ---------------------------- " .. mpMode)
    print("MoodleFramework loaded ------------------ " .. tostring(getActivatedMods():contains("MoodleFramework")))
    local currentDay = RD_zapi.getGameTime("getWorldAgeHours") / 24
    print("Current time in days -------------------- " .. currentDay)
    local gt = getGameTime()
    print("In-game date ---------------------------- Day " .. tostring(gt:getDay()) .. ", Month " .. tostring(gt:getMonth()) .. ", Year " .. tostring(gt:getYear()))

    print("The reason for last cycle generation ---- " .. cycle.reason_for_cycle)
    print("Cycle delayed (first spawn delay used) -- " .. tostring(RD_modData.ICdata.cycleDelayed or false))
    print("Current phase --------------------------- " .. cycle.current_phase)
    print("Phase minutes remaining ----------------- " .. cycle.phase_minutes_remaining .. " mins (" .. (cycle.phase_minutes_remaining / MINUTES_PER_DAY) .. " days)")
    print("Total cycle duration -------------------- " .. (cycle.cycle_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.cycle_duration_mins .. " mins)")

    print("Red phase duration ---------------------- " .. (cycle.redPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.redPhase_duration_mins .. " mins)")
    print("Follicular phase duration --------------- " .. (cycle.follicularPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.follicularPhase_duration_mins .. " mins)")
    print("Ovulation phase duration ---------------- " .. (cycle.ovulationPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.ovulationPhase_duration_mins .. " mins)")
    print("Luteal phase duration ------------------- " .. (cycle.lutealPhase_duration_mins / MINUTES_PER_DAY) .. " days (" .. cycle.lutealPhase_duration_mins .. " mins)")

    local currentPhase = RD_CycleManager.getCurrentCyclePhase(cycle)
    print("Current cycle phase (from func) --------- " .. currentPhase)
    if not cycle.healthEffectSeverity then return end
    print("Target Health Effect Severity ----------- " .. cycle.healthEffectSeverity)

    local sanitaryItem = RD_HygieneManager.getCurrentlyWornSanitaryItem()
    if sanitaryItem then
        print("Currently worn sanitary item ------------ " .. sanitaryItem:getName())
        print("Sanitary item condition ----------------- " .. sanitaryItem:getCondition())
    else
        print("Currently worn sanitary item ------------ None")
    end
    print("Hygiene saturation counter (cSIHDC) ----- " .. tostring(RD_modData.ICdata.cSIHDC_counter or 0))
    print("Leak level ------------------------------ " .. tostring(RD_modData.ICdata.LeakLevel or 0))
    print("Leak switch state ----------------------- " .. tostring(RD_modData.ICdata.LeakSwitchState or false))
    printTSSStatus()

    local groin = RD_zapi.getBodyPart(BodyPartType.Groin)
    local lowerTorso = RD_zapi.getBodyPart(BodyPartType.Torso_Lower)
    local upperTorso = RD_zapi.getBodyPart(BodyPartType.Torso_Upper)
    print("Body stiffness - Groin ------------------ " .. (groin and tostring(groin:getStiffness()) or "unavailable"))
    print("Body stiffness - Torso Lower ------------ " .. (lowerTorso and tostring(lowerTorso:getStiffness()) or "unavailable"))
    print("Body stiffness - Torso Upper ------------ " .. (upperTorso and tostring(upperTorso:getStiffness()) or "unavailable"))

    local phaseStatus = RD_CycleManager.getPhaseStatus(cycle)
    if phaseStatus then
        print("Phase Status ---------------------------- " .. phaseStatus.phase)
        print("Time remaining in current phase --------- " .. phaseStatus.time_remaining .. " days (" .. phaseStatus.time_remaining_mins .. " mins)")
        print("Phase percent complete ------------------ " .. phaseStatus.percent_complete .. "%")
    else
        print("No valid phase status found for the current cycle.")
    end

    local dataCodes = RD_CycleTrackerLogic.getDataCodes(cycle)
    if dataCodes then
        print("Data codes for the current phase -------- " .. table.concat(dataCodes, ", "))
    else
        print("No data codes available for the current cycle phase.")
    end
    print("PMS Duration ---------------------------- " .. tostring(cycle.pms_duration_mins / MINUTES_PER_DAY) .. " days (" .. tostring(cycle.pms_duration_mins) .. " mins)")
    print("PMS Severity ---------------------------- " .. tostring(RD_CycleManager.getPMSseverity()))
    print("PMS Symptom - Agitation ----------------- " .. tostring(cycle.pms_agitation))
    print("PMS Symptom - Cramps -------------------- " .. tostring(cycle.pms_cramps))
    print("PMS Symptom - Fatigue ------------------- " .. tostring(cycle.pms_fatigue))
    print("PMS Symptom - Tender Breasts ------------ " .. tostring(cycle.pms_tenderBreasts))
    print("PMS Symptom - Crave Food ---------------- " .. tostring(cycle.pms_craveFood))
    print("PMS Symptom - Sadness ------------------- " .. tostring(cycle.pms_Sadness))
    print("Painkiller active ----------------------- " .. tostring(RD_modData.ICdata.pill_effect_active))
    print("Painkiller counter/max ------------------ " .. tostring(RD_modData.ICdata.pill_effect_counter or 0) .. " / " .. tostring(SandboxVars.RedDays.painkillerEffectDuration or 36))
    print("This log output was formatted to be read in a separate terminal window with a monospace font, not the in-game console.")
    print("==========================================================================================")
end
-- Events.OnGameStart.Add(PrintStatus(RD_modData.ICdata.currentCycle)) Sometimes this prints before the cycle is generated, so we call it in main() instead.


function RD_CycleDebugger.printWrapper() -- Wrapper to control printing frequency when running from main function
    if not RD_modData or not RD_modData.ICdata then return end
    local cycle = RD_modData.ICdata.currentCycle
    if not cycle then return end
    PrintStatus(cycle)
    -- There used to be a lot more logic here, but keeping this to keep it consistent.
end

return RD_CycleDebugger
