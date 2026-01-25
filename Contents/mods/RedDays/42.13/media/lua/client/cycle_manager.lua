CycleManager = {}
require "RedDays/game_api"

-- Constants
local MINUTES_PER_DAY = 1440  -- 24 hours * 60 minutes

-- Phase order for cycling through phases
local PHASE_ORDER = {"redPhase", "follicularPhase", "ovulationPhase", "lutealPhase"}

function CycleManager.LoadPlayerData()
    modData = zapi.getModData()
    modData.ICdata = modData.ICdata or {}
    cycleDelayed = modData.ICdata.cycleDelayed or false
    PMS_Symptoms = modData.ICdata.pmsSymptoms or CycleManager.generateRandomPMSsymptoms()

    -- Initialize or validate the current cycle
    modData.ICdata.currentCycle = modData.ICdata.currentCycle or CycleManager.newCycle("LoadPlayerData")
    if not CycleManager.isCycleValid(modData.ICdata.currentCycle) then
        print("Cycle data structure mismatch! This could be due to a mod update. Regenerating cycle...")
        modData.ICdata.currentCycle = CycleManager.newCycle("LoadPlayerData_afterValidation")
    end
end

local function phaseIsValid(phase)
    for _, valid_phase in ipairs(PHASE_ORDER) do
        if phase == valid_phase then
            return true
        end
    end
    return false
end

-- Get the next phase in the cycle order
local function getNextPhase(currentPhase)
    for i, phase in ipairs(PHASE_ORDER) do
        if phase == currentPhase then
            if i < #PHASE_ORDER then
                return PHASE_ORDER[i + 1]
            else
                return "endOfCycle"  -- lutealPhase is the last, cycle ends
            end
        end
    end
    return "endOfCycle"
end

-- Main cycle tick - decrements time and transitions phases
function CycleManager.tick(tickMinutes)
    if not tickMinutes or tickMinutes <= 0 then
        print("Invalid tickMinutes value: " .. tostring(tickMinutes))
        return modData.ICdata.currentCycle
    end
    local cycle = modData.ICdata.currentCycle
    
    if not cycle or not cycle.current_phase then
        print("Invalid cycle, regenerating...")
        modData.ICdata.currentCycle = CycleManager.newCycle("tick_invalidCycle")
        return modData.ICdata.currentCycle
    end
    
    -- Decrement the countdown
    cycle.phase_minutes_remaining = cycle.phase_minutes_remaining - tickMinutes
    
    -- Check if current phase has ended
    while cycle.phase_minutes_remaining <= 0 do
        local nextPhase = getNextPhase(cycle.current_phase)
        
        if nextPhase == "endOfCycle" then
            -- Generate a new cycle
            print("Cycle ended. New cycle generated.")
            modData.ICdata.currentCycle = CycleManager.newCycle("tick_endOfCycle")
            return modData.ICdata.currentCycle
        else
            -- Carry over any negative time to the next phase
            local overflow = math.abs(cycle.phase_minutes_remaining)
            cycle.current_phase = nextPhase
            cycle.phase_minutes_remaining = cycle[nextPhase .. "_duration_mins"] - overflow
            print("Phase transition: now in " .. nextPhase .. " with " .. cycle.phase_minutes_remaining .. " minutes remaining")
        end
    end
    
    return cycle
end

local function random_between(range)
    return ZombRand(range[1], range[2])
end

-- Convert days to minutes
local function daysToMinutes(days)
    return days * MINUTES_PER_DAY
end

local function default_cycle() -- Default cycle values if a new cycle cannot be generated
    return {
        -- Current state
        current_phase = "redPhase",
        phase_minutes_remaining = daysToMinutes(4),
        
        -- Phase durations in minutes
        redPhase_duration_mins = daysToMinutes(4),
        follicularPhase_duration_mins = daysToMinutes(10),
        ovulationPhase_duration_mins = daysToMinutes(1),
        lutealPhase_duration_mins = daysToMinutes(14),
        
        -- Total cycle duration in minutes (for reference)
        cycle_duration_mins = daysToMinutes(28),
        
        -- Health effect settings
        stiffness_target = 55,
        stiffness_increment = 2,
        discomfort_target = 100,
        endurance_decrement = 0.0005,
        fatigue_increment = 0.0001,
        healthEffectSeverity = 50,
        
        -- PMS settings
        pms_duration_mins = daysToMinutes(7),
        pms_agitation = false,
        pms_cramps = true,
        pms_fatigue = true,
        pms_tenderBreasts = false,
        pms_craveFood = false,
        pms_Sadness = false,
        
        -- Metadata
        reason_for_cycle = "defaultCycle"
    }
end

local function test_debug_cycle() -- The faster cycle for testing purposes
    return {
        -- Current state
        current_phase = "redPhase",
        phase_minutes_remaining = daysToMinutes(1),

        -- Phase durations in minutes
        redPhase_duration_mins = daysToMinutes(1),
        follicularPhase_duration_mins = daysToMinutes(1),
        ovulationPhase_duration_mins = daysToMinutes(1),
        lutealPhase_duration_mins = daysToMinutes(1),

        -- Total cycle duration in minutes (for reference)
        cycle_duration_mins = daysToMinutes(4),

        -- Health effect settings
        stiffness_target = 55,
        stiffness_increment = 2,
        discomfort_target = 100,
        endurance_decrement = 0.0005,
        fatigue_increment = 0.0001,
        healthEffectSeverity = 50,

        -- PMS settings
        pms_duration_mins = daysToMinutes(0.5),
        pms_agitation = false,
        pms_cramps = true,
        pms_fatigue = true,
        pms_tenderBreasts = false,
        pms_craveFood = false,
        pms_Sadness = false,

        -- Metadata
        reason_for_cycle = "testDebugCycle"
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

local testCycle = false
function CycleManager.newCycle(whoDidThis)
    -- Debug mode: use fast test cycle if enabled
    if testCycle then
        print("Debug fast cycle enabled - using test_debug_cycle()")
        local cycle = test_debug_cycle()
        cycle.reason_for_cycle = whoDidThis .. "_debugFastCycle"
        return cycle
    end

    local ranges = CycleManager.sandboxValues()
    local range_red_phase_duration = ranges.range_red_phase_duration
    local range_follicular_phase_duration = ranges.range_follicular_phase_duration
    local range_ovulation_phase_duration = ranges.range_ovulation_phase_duration
    local range_luteal_phase_duration = ranges.range_luteal_phase_duration
    local range_delay_duration = ranges.range_delay_duration
    local range_healthEffectLevel = ranges.range_healthEffectLevel
    local range_pms_duration = ranges.range_pms_duration
    local range_total_cycle = ranges.range_total_menstrual_cycle_duration

    if whoDidThis ~= "isCycleValid" then
        print("Generating a new menstrual cycle (countdown-based)...")
    end

    -- Try up to 10 times to generate a valid cycle (up to 10 times because sometimes the ranges make it possible)
    -- This is because the player can set ranges that make it impossible to generate a valid cycle
    local max_attempts = 10
    local red_days, follicular_days, ovulation_days, luteal_days, total_days
    local valid_cycle_generated = false

    for attempt = 1, max_attempts do
        red_days = random_between(range_red_phase_duration)
        follicular_days = random_between(range_follicular_phase_duration)
        ovulation_days = random_between(range_ovulation_phase_duration)
        luteal_days = random_between(range_luteal_phase_duration)
        total_days = red_days + follicular_days + ovulation_days + luteal_days

        -- Check if total falls within expected range
        if total_days >= range_total_cycle[1] and total_days <= range_total_cycle[2] then
            valid_cycle_generated = true
            if whoDidThis ~= "isCycleValid" then
                print("Valid cycle generated on attempt " .. attempt .. " (total: " .. total_days .. " days)")
            end
            break
        else
            if whoDidThis ~= "isCycleValid" then
                print("Attempt " .. attempt .. ": total " .. total_days .. " days outside range [" .. range_total_cycle[1] .. "-" .. range_total_cycle[2] .. "]")
            end
        end
    end

    -- Fallback to default cycle if we couldn't generate a valid one
    if not valid_cycle_generated then
        print("Failed to generate valid cycle after " .. max_attempts .. " attempts. Using default cycle.")
        local cycle = default_cycle()
        cycle.reason_for_cycle = whoDidThis .. "_fallbackDefault"
        return cycle
    end

    local pms_days = random_between(range_pms_duration)

    -- Determine starting phase based on delay setting
    local starting_phase = "redPhase"
    local starting_minutes = 0
    cycleDelayed = modData.ICdata.cycleDelayed or false

    if ranges.phase_start_delay_enabled and not cycleDelayed and whoDidThis ~= "isCycleValid" then
        -- Start on follicular phase with duration = delay value only
        local delay_days = random_between(range_delay_duration)
        print("Delay enabled for new player - starting on follicular phase.")
        print("Follicular phase set to delay duration: " .. delay_days .. " days.")
        starting_phase = "follicularPhase"
        starting_minutes = daysToMinutes(delay_days)
        modData.ICdata.cycleDelayed = true
    else
        starting_minutes = daysToMinutes(red_days)
    end

    -- Convert to minutes
    local redPhase_duration_mins = daysToMinutes(red_days)
    local follicularPhase_duration_mins = daysToMinutes(follicular_days)
    local ovulationPhase_duration_mins = daysToMinutes(ovulation_days)
    local lutealPhase_duration_mins = daysToMinutes(luteal_days)
    local pms_duration_mins = daysToMinutes(pms_days)

    local cycle_duration_mins = redPhase_duration_mins + follicularPhase_duration_mins +
                                 ovulationPhase_duration_mins + lutealPhase_duration_mins

    -- Health effects
    local healthEffectSeverity = random_between(range_healthEffectLevel)
    local stiffness_target = healthEffectSeverity
    local stiffness_increment = 2
    local discomfort_target = healthEffectSeverity

    local scaling = healthEffectSeverity / 50
    local endurance_decrement = 0.001 * scaling
    local fatigue_increment = 0.0002 * scaling

    -- PMS symptoms
    local pms_symptoms = CycleManager.getPMSymptoms()

    local cycle = {
        -- Current state
        current_phase = starting_phase,
        phase_minutes_remaining = starting_minutes,
        
        -- Phase durations in minutes
        redPhase_duration_mins = redPhase_duration_mins,
        follicularPhase_duration_mins = follicularPhase_duration_mins,
        ovulationPhase_duration_mins = ovulationPhase_duration_mins,
        lutealPhase_duration_mins = lutealPhase_duration_mins,
        
        -- Total cycle duration in minutes
        cycle_duration_mins = cycle_duration_mins,
        
        -- Health effect settings
        stiffness_target = stiffness_target,
        stiffness_increment = stiffness_increment,
        discomfort_target = discomfort_target,
        endurance_decrement = endurance_decrement,
        fatigue_increment = fatigue_increment,
        healthEffectSeverity = healthEffectSeverity,
        
        -- PMS settings
        pms_duration_mins = pms_duration_mins,
        pms_agitation = pms_symptoms.pms_agitation,
        pms_cramps = pms_symptoms.pms_cramps,
        pms_fatigue = pms_symptoms.pms_fatigue,
        pms_tenderBreasts = pms_symptoms.pms_tenderBreasts,
        pms_craveFood = pms_symptoms.pms_craveFood,
        pms_Sadness = pms_symptoms.pms_Sadness,
        
        -- Metadata
        reason_for_cycle = whoDidThis
    }

    if whoDidThis ~= "isCycleValid" then
        print("New cycle created: starting in " .. starting_phase .. " with " .. starting_minutes .. " minutes (" .. (starting_minutes / MINUTES_PER_DAY) .. " days)")
    end

    return cycle
end

function CycleManager.getCurrentCyclePhase(cycle)
    if not cycle or not cycle.current_phase then
        print("Invalid cycle structure detected.")
        return "invalidCycle"
    end
    return cycle.current_phase
end

function CycleManager.getPMSseverity()
    local currentCycle = modData.ICdata.currentCycle
    if not currentCycle then return 0 end

    local phase = currentCycle.current_phase
    if phase ~= "lutealPhase" and phase ~= "redPhase" then
        return 0
    end

    local pms_duration_mins = currentCycle.pms_duration_mins or daysToMinutes(7)
    local phase_minutes_remaining = currentCycle.phase_minutes_remaining or 0
    local PMSSeverity = 0

    if phase == "lutealPhase" then
        -- PMS ramps up as we approach the end of luteal phase
        -- When time_remaining <= pms_duration_mins, PMS starts
        if phase_minutes_remaining <= pms_duration_mins then
            local mins_into_pms = pms_duration_mins - phase_minutes_remaining
            PMSSeverity = math.min(100, math.max(0, (mins_into_pms / pms_duration_mins) * 100))
        end

    elseif phase == "redPhase" then
        -- PMS severity drains from 100 → 0 over first day of red phase
        local redPhase_duration_mins = currentCycle.redPhase_duration_mins or daysToMinutes(4)
        local mins_into_red = redPhase_duration_mins - phase_minutes_remaining
        if mins_into_red <= MINUTES_PER_DAY then
            PMSSeverity = math.max(0, 100 * (1 - (mins_into_red / MINUTES_PER_DAY)))
        else
            PMSSeverity = 0
        end
    end

    return PMSSeverity
end

function CycleManager.getPhaseStatus(cycle)
    if not cycle or not cycle.current_phase then
        return false
    end

    local phase = cycle.current_phase
    local phase_minutes_remaining = cycle.phase_minutes_remaining or 0
    local phase_duration_key = phase .. "_duration_mins"
    local phase_duration_mins = cycle[phase_duration_key] or MINUTES_PER_DAY

    -- Calculate progress
    local mins_elapsed = phase_duration_mins - phase_minutes_remaining
    local percent = 0
    if phase_duration_mins > 0 then
        percent = (mins_elapsed / phase_duration_mins) * 100
        percent = math.max(0, math.min(percent, 100))
    end

    -- Convert remaining time to days for compatibility
    local time_remaining_days = phase_minutes_remaining / MINUTES_PER_DAY

    return {
        phase = phase,
        time_remaining = time_remaining_days,  -- Keep in days for compatibility
        time_remaining_mins = phase_minutes_remaining,
        percent_complete = percent
    }
end

function CycleManager.isCycleValid(cycle) -- If mod is updated and the cycle structure changes, this function will check if the cycle is valid
    -- Check for required fields in the new countdown-based structure
    local required_fields = {
        "current_phase",
        "phase_minutes_remaining",
        "redPhase_duration_mins",
        "follicularPhase_duration_mins",
        "ovulationPhase_duration_mins",
        "lutealPhase_duration_mins",
        "cycle_duration_mins",
        "healthEffectSeverity",
        "pms_duration_mins",
        "reason_for_cycle"
    }
    
    for _, field in ipairs(required_fields) do
        if cycle[field] == nil then
            print("Cycle missing required field: " .. field)
            return false
        end
    end
    
    -- Validate current_phase is a known phase
    if not phaseIsValid(cycle.current_phase) then
        print("Cycle has invalid current_phase: " .. tostring(cycle.current_phase))
        return false
    end
    
    return true
end

return CycleManager
