CycleManager = {}

local function LoadPlayerData()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    cycleDelayed = modData.ICdata.cycleDelayed or false
    PMS_Symptoms = modData.ICdata.pmsSymptoms or CycleManager.generateRandomPMSsymptoms()
end
-- Events.OnGameStart.Add(LoadPlayerData)

local function random_between(range)
    return ZombRand(range[1], range[2])
end

local function default_cycle() -- Default cycle values if a new cycle cannot be generated
    return {
        cycle_start_day = getGameTime():getWorldAgeHours() / 24,
        cycle_duration = 28,
        follicular_duration = 14,
        red_days_duration = 4,
        follicle_stimulating_start_day = 5,
        follicle_stimulating_duration = 10,
        ovulation_duration = 1,
        ovulation_day = 14,
        luteal_start_day = 15,
        luteal_duration = 14,
        stiffness_target = 55,
        stiffness_increment = 2,
        discomfort_target = 100,
        endurance_decrement = 0.0005,
        fatigue_increment = 0.0001,
        reason_for_cycle = "defaultCycle",
        timeToDelaycycle = 0,
        healthEffectSeverity = 50,
        pms_duration = 7,
        pms_agitation = false,
        pms_cramps = true,
        pms_fatigue = true,
        pms_tenderBreasts = false,
        pms_craveFood = false,
        pms_Sadness = false
    }
end

function CycleManager.sandboxValues()
    -- Abstracted this to a function because this is used in multiple places
    sbv = SandboxVars.RedDays
    local range_total_menstrual_cycle_duration = {sbv.menstrual_cycle_duration_lowerBound, sbv.menstrual_cycle_duration_upperBound}
    local range_red_phase_duration = {sbv.red_phase_duration_lowerBound, sbv.red_phase_duration_upperBound}
    local range_follicular_phase_duration = {sbv.follicular_phase_duration_lowerBound, sbv.follicular_phase_duration_upperBound}
    local range_ovulation_phase_duration = {sbv.ovulation_phase_duration_lowerBound, sbv.ovulation_phase_duration_upperBound}
    local range_luteal_phase_duration = {sbv.luteal_phase_duration_lowerBound, sbv.luteal_phase_duration_upperBound}
    local range_delay_duration = {sbv.phase_start_delay_lowerBound, sbv.phase_start_delay_upperBound}
    local range_healthEffectLevel = {sbv.healthEffectLowerBound, sbv.healthEffectUpperBound}
    local range_pms_duration = {sbv.PMS_duration_lowerbound, sbv.PMS_duration_upperbound}

    return {
        range_total_menstrual_cycle_duration = range_total_menstrual_cycle_duration,
        range_red_phase_duration = range_red_phase_duration,
        range_follicular_phase_duration = range_follicular_phase_duration,
        range_ovulation_phase_duration = range_ovulation_phase_duration,
        range_luteal_phase_duration = range_luteal_phase_duration,
        range_delay_duration = range_delay_duration,
        range_healthEffectLevel = range_healthEffectLevel,
        range_pms_duration = range_pms_duration
    }
end

function CycleManager.generateRandomPMSsymptoms()
    local symptoms = {
        { key = "pms_agitation",     chance = 35 },
        { key = "pms_cramps",        chance = 75 },
        { key = "pms_fatigue",       chance = 70 },
        { key = "pms_tenderBreasts", chance = 60 },
        { key = "pms_craveFood",     chance = 55 },
        { key = "pms_Sadness",       chance = 45 },
    }

    local result = {}
    local trues = {}

    for _, s in ipairs(symptoms) do
        local ok = (ZombRand(100) < s.chance)
        result[s.key] = ok
        if ok then table.insert(trues, s.key) end
    end
    -- Ensure at most 3 true values by randomly turning extras off
    while #trues > 3 do
        local pick = ZombRand(#trues) + 1 -- ZombRand(n) yields 0..n-1
        local key = table.remove(trues, pick)
        result[key] = false
    end
    return result
end


function CycleManager.getPMSymptoms()
    PMS_Symptoms = modData.ICdata.pmsSymptoms or CycleManager.generateRandomPMSsymptoms() -- Use symptoms assigned at character creation
    local pms_agitation = PMS_Symptoms.pms_agitation
    local pms_cramps = PMS_Symptoms.pms_cramps
    local pms_fatigue = PMS_Symptoms.pms_fatigue
    local pms_tenderBreasts = PMS_Symptoms.pms_tenderBreasts
    local pms_craveFood = PMS_Symptoms.pms_craveFood
    local pms_Sadness = PMS_Symptoms.pms_Sadness

    local sbv = SandboxVars.RedDays
    if sbv.PMS_ConsistentVsRandom == false then
        random_pms_symptoms = CycleManager.generateRandomPMSsymptoms()
        pms_agitation = random_pms_symptoms.pms_agitation
        pms_cramps = random_pms_symptoms.pms_cramps
        pms_fatigue = random_pms_symptoms.pms_fatigue
        pms_tenderBreasts = random_pms_symptoms.pms_tenderBreasts
        pms_craveFood = random_pms_symptoms.pms_craveFood
        pms_Sadness = random_pms_symptoms.pms_Sadness
    end

    local symptoms = {
        pms_agitation = pms_agitation,
        pms_cramps = pms_cramps,
        pms_fatigue = pms_fatigue,
        pms_tenderBreasts = pms_tenderBreasts,
        pms_craveFood = pms_craveFood,
        pms_Sadness = pms_Sadness
    }
    return symptoms
end


function CycleManager.newCycle(whoDidThis)
    local ranges = CycleManager.sandboxValues()
    local range_total_menstrual_cycle_duration = ranges.range_total_menstrual_cycle_duration
    local range_red_phase_duration = ranges.range_red_phase_duration
    local range_follicular_phase_duration = ranges.range_follicular_phase_duration
    local range_ovulation_phase_duration = ranges.range_ovulation_phase_duration
    local range_luteal_phase_duration = ranges.range_luteal_phase_duration
    local range_delay_duration = ranges.range_delay_duration
    local range_healthEffectLevel = ranges.range_healthEffectLevel
    local range_pms_duration = ranges.range_pms_duration

    -- local range_total_menstrual_cycle_duration = {28, 34}
    -- local range_red_phase_duration = {2, 5}
    -- local range_follicular_phase_duration = {11, 16}
    -- local range_ovulation_phase_duration = {1, 1}
    -- local range_luteal_phase_duration = {11, 18}
    -- local range_delay_duration = {0, 5}
    -- local range_healthEffectLevel = {30, 70}
    -- local range_pms_duration = {2, 10}

    -- local range_total_menstrual_cycle_duration = {7, 9}
    -- local range_red_phase_duration = {1, 2}
    -- local range_follicular_phase_duration = {3, 4}
    -- local range_ovulation_phase_duration = {1, 1}
    -- local range_luteal_phase_duration = {3, 5}
    -- local range_delay_duration = {1, 1}
    -- local range_healthEffectLevel = {30, 70}
    -- local range_pms_duration = {1, 2}


    local max_attempts = 10 -- Duration values can be user-defined and may not always yield a valid cycle, so we try multiple times to find a valid one and return a default cycle if we fail
    for attempt = 1, max_attempts do
        if whoDidThis ~= "isCycleValid" then
            print("Attempt " .. attempt .. " to generate a new menstrual cycle...")
        end

        local cycle_start_day = getGameTime():getWorldAgeHours() / 24

        local timeToDelaycycle = 0
        cycleDelayed = modData.ICdata.cycleDelayed or false
        if  ranges.phase_start_delay_enabled and not cycleDelayed and whoDidThis ~= "isCycleValid" then
            print("Assuming player recently spawned, adding a random delay to the cycle start.")
            timeToDelaycycle = random_between(range_delay_duration)
            print("Cycle start will be delayed by " .. timeToDelaycycle .. " days.")
            modData.ICdata.cycleDelayed = true -- Only run this once per life time.
        end

        local cycle_duration = random_between(range_total_menstrual_cycle_duration)

        local min_follicular = math.max(range_follicular_phase_duration[1], cycle_duration - range_luteal_phase_duration[2])
        local max_follicular = math.min(range_follicular_phase_duration[2], cycle_duration - range_luteal_phase_duration[1])

        if min_follicular <= max_follicular then
            local follicular_duration = ZombRand(min_follicular, max_follicular)

            -- Red day always occurs at the start of the cycle
            local red_days_duration = random_between(range_red_phase_duration)

            local offset = ZombRand(0,1000) / 1000 -- For random start times
            local follicle_stimulating_start_day = cycle_start_day + red_days_duration + 1 + offset
            local follicle_stimulating_duration = follicular_duration - red_days_duration

            local offset = ZombRand(0,200) / 1000 -- For random start times
            local ovulation_duration = random_between(range_ovulation_phase_duration)
            local ovulation_day = red_days_duration + follicle_stimulating_duration + offset

            local offset = ZombRand(0,1000) / 1000 -- For random start times
            local luteal_start_day = follicular_duration + ovulation_duration + offset
            local luteal_duration = cycle_duration - follicular_duration - ovulation_duration

            local healthEffectSeverity = random_between(range_healthEffectLevel) -- 0 to 100
            local stiffness_target = healthEffectSeverity
            local stiffness_increment = 2
            local discomfort_target = healthEffectSeverity

            local scaling = healthEffectSeverity / 50
            local endurance_decrement = 0.001 * scaling
            local fatigue_increment = 0.0002 * scaling

            local pms_duration = random_between(range_pms_duration)
            local pms_symptoms = CycleManager.getPMSymptoms()

            return {
                cycle_start_day = cycle_start_day,
                cycle_duration = cycle_duration,
                follicular_duration = follicular_duration,
                red_days_duration = red_days_duration,
                follicle_stimulating_start_day = follicle_stimulating_start_day,
                follicle_stimulating_duration = follicle_stimulating_duration,
                ovulation_duration = ovulation_duration,
                ovulation_day = ovulation_day,
                luteal_start_day = luteal_start_day,
                luteal_duration = luteal_duration,
                stiffness_target = stiffness_target,
                stiffness_increment = stiffness_increment,
                discomfort_target = discomfort_target,
                endurance_decrement = endurance_decrement,
                fatigue_increment = fatigue_increment,
                reason_for_cycle = whoDidThis, -- This is used for debugging purposes to know what generated the cycle, for example on game load, no message is printed.
                timeToDelaycycle = timeToDelaycycle,
                healthEffectSeverity = healthEffectSeverity,
                pms_duration = pms_duration,
                pms_agitation = pms_symptoms.pms_agitation,
                pms_cramps = pms_symptoms.pms_cramps,
                pms_fatigue = pms_symptoms.pms_fatigue,
                pms_tenderBreasts = pms_symptoms.pms_tenderBreasts,
                pms_craveFood = pms_symptoms.pms_craveFood,
                pms_Sadness = pms_symptoms.pms_Sadness
            }
        end
    end

    print("Failed to generate a valid menstrual cycle after " .. max_attempts .. " attempts. Returning default cycle values.")
    return default_cycle()
end

function CycleManager.getCurrentCyclePhase(cycle)
    local current_day = getGameTime():getWorldAgeHours() / 24 
    if not cycle then
        print("Invalid cycle structure detected.")
        return "invalidCycle"
    end
    local days_into_cycle = current_day - cycle.cycle_start_day

    if days_into_cycle < cycle.timeToDelaycycle then
        return "delayPhase" -- This is for the random cycle start day for new characters
    end

    if days_into_cycle <= cycle.red_days_duration then
        return "redPhase"
    elseif days_into_cycle <= (cycle.red_days_duration + cycle.follicle_stimulating_duration) then
        return "follicularPhase"
    elseif days_into_cycle <= (cycle.red_days_duration + cycle.follicle_stimulating_duration + cycle.ovulation_duration) then
        return "ovulationPhase"
    elseif days_into_cycle <= cycle.cycle_duration then
        return "lutealPhase"
    elseif days_into_cycle > cycle.cycle_duration then
        return "endOfCycle"
    end
    print("Unable to determine current cycle phase.")
    return "unknownPhase"
end

function CycleManager.getPMSseverity()
    local currentCycle = modData.ICdata.currentCycle
    if not currentCycle then return 0 end

    local stat = CycleManager.getPhaseStatus(currentCycle)
    if not stat or (stat.phase ~= "lutealPhase" and stat.phase ~= "redPhase") then
        return 0
    end

    local pmsDuration = currentCycle.pms_duration  -- total PMS duration (days)
    local timeRemaining = stat.time_remaining
    local PMSSeverity = 0

    if stat.phase == "lutealPhase" then
        -- PMS ramps up in the last pmsDuration days before red phase
        if timeRemaining <= pmsDuration then
            local daysIntoPMS = pmsDuration - timeRemaining
            PMSSeverity = math.min(100, math.max(0, (daysIntoPMS / pmsDuration) * 100))
        end

    elseif stat.phase == "redPhase" then
        -- PMS severity drains from 100 → 0 over first day of red phase
        local redDayDuration = currentCycle.red_days_duration or 5
        local timeIntoRed = redDayDuration - timeRemaining
        if timeIntoRed <= 1 then
            PMSSeverity = math.max(0, 100 * (1 - timeIntoRed))
        else
            PMSSeverity = 0
        end
    end

    return PMSSeverity
end

function CycleManager.getPhaseStatus(cycle)
    local current_day = getGameTime():getWorldAgeHours() / 24
    local days_into_cycle = current_day - cycle.cycle_start_day
    local phase = CycleManager.getCurrentCyclePhase(cycle)

    local phase_start, phase_end

    if phase == "redPhase" then
        phase_start = 0
        phase_end = cycle.red_days_duration
    elseif phase == "follicularPhase" then
        phase_start = cycle.red_days_duration
        phase_end = cycle.red_days_duration + cycle.follicle_stimulating_duration
    elseif phase == "ovulationPhase" then
        phase_start = cycle.red_days_duration + cycle.follicle_stimulating_duration
        phase_end = cycle.red_days_duration + cycle.follicle_stimulating_duration + cycle.ovulation_duration
    elseif phase == "lutealPhase" then
        phase_start = cycle.red_days_duration + cycle.follicle_stimulating_duration + cycle.ovulation_duration
        phase_end = cycle.cycle_duration
    else
        return false
    end

    local phase_length = phase_end - phase_start
    local days_into_phase = days_into_cycle - phase_start
    days_into_phase = math.max(0, math.min(days_into_phase, phase_length))
    local percent = (days_into_phase / phase_length) * 100
    percent = math.max(0, math.min(percent, 100))

    local time_remaining = phase_end - days_into_cycle
    time_remaining = math.max(0, time_remaining)

    return {
        phase = phase,
        time_remaining = time_remaining,
        percent_complete = percent
    }
end

function CycleManager.isCycleValid(cycle) -- If mod is updated and the cycle structure changes, this function will check if the cycle is valid
    -- Generate a reference cycle to get the expected keys
    local reference = CycleManager.newCycle("isCycleValid")
    -- Collect keys from both tables
    local function get_keys(tbl)
        local keys = {}
        for k, _ in pairs(tbl) do keys[k] = true end
        return keys
    end
    local cycle_keys = get_keys(cycle)
    local ref_keys = get_keys(reference)

    -- Check for missing or extra keys
    for k in pairs(ref_keys) do
        if not cycle_keys[k] then
            return false -- missing key
        end
    end
    for k in pairs(cycle_keys) do
        if not ref_keys[k] then
            return false -- extra key
        end
    end
    return true
end

return CycleManager
