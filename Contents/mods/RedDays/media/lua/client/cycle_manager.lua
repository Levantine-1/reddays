CycleManager = {}

local function random_between(range)
    return ZombRand(range[1], range[2] + 1)
end

local function default_cycle()
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
        stiffness_target = 100,
        stiffness_increment = 2,
        discomfort_target = 100,
        endurance_decrement = 0.0005,
        fatigue_increment = 0.0001,
        reason_for_cycle = "defaultCycle"
    }
end

function CycleManager.newCycle(whoDidThis)
    sbv = SandboxVars.RedDays
    local range_total_menstrual_cycle_duration = {sbv.menstrual_cycle_duration_lowerBound, sbv.menstrual_cycle_duration_upperBound}
    local range_red_phase_duration = {sbv.red_phase_duration_lowerBound, sbv.red_phase_duration_upperBound}
    local range_follicular_phase_duration = {sbv.follicular_phase_duration_lowerBound, sbv.follicular_phase_duration_upperBound}
    local range_ovulation_phase_duration = {sbv.ovulation_phase_duration_lowerBound, sbv.ovulation_phase_duration_upperBound}
    local range_luteal_phase_duration = {sbv.luteal_phase_duration_lowerBound, sbv.luteal_phase_duration_upperBound}

    local max_attempts = 10
    for attempt = 1, max_attempts do
        if whoDidThis ~= "isCycleValid" then
            print("Attempt " .. attempt .. " to generate a new menstrual cycle...")
        end

        local cycle_start_day = getGameTime():getWorldAgeHours() / 24

        local cycle_duration = random_between(range_total_menstrual_cycle_duration)

        local min_follicular = math.max(range_follicular_phase_duration[1], cycle_duration - range_luteal_phase_duration[2])
        local max_follicular = math.min(range_follicular_phase_duration[2], cycle_duration - range_luteal_phase_duration[1])

        if min_follicular <= max_follicular then
            local follicular_duration = random_between({min_follicular, max_follicular})

            local min_red = range_red_phase_duration[1]
            local max_red = math.min(range_red_phase_duration[2], follicular_duration - 1)
            if min_red > max_red then
                min_red = max_red
            end
            local red_days_duration = random_between({min_red, max_red})

            local offset = ZombRand(0,1000) / 1000
            local follicle_stimulating_start_day = cycle_start_day + red_days_duration + 1 + offset
            local follicle_stimulating_duration = follicular_duration - red_days_duration

            local offset = ZombRand(0,200) / 1000
            local ovulation_duration = random_between(range_ovulation_phase_duration)
            local ovulation_day = red_days_duration + follicle_stimulating_duration + offset

            local offset = ZombRand(0,1000) / 1000
            local luteal_start_day = follicular_duration + ovulation_duration + offset
            local luteal_duration = cycle_duration - follicular_duration - ovulation_duration

            local stiffness_target = ZombRand(20, 81) -- Default 100
            local stiffness_increment = 1 -- Defaul 2
            local discomfort_target = ZombRand(25,100)
            local endurance_decrement = 0.0005
            local fatigue_increment = 0.0001

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
                reason_for_cycle = whoDidThis
            }
        end
    end

    print("Error: Failed to generate a valid menstrual cycle after " .. max_attempts .. " attempts. Returning default cycle values.")
    return default_cycle()
end

function CycleManager.getCurrentCyclePhase(cycle)
    local current_day = getGameTime():getWorldAgeHours() / 24 
    if not cycle then
        print("Error: Invalid cycle structure detected.")
        return "invalidCycle"
    end
    local days_into_cycle = current_day - cycle.cycle_start_day

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
    print("Error: Unable to determine current cycle phase.")
    return "unknownPhase"
end

function CycleManager.isCycleValid(cycle)
    local reference = CycleManager.newCycle("isCycleValid")
    local function get_keys(tbl)
        local keys = {}
        for k, _ in pairs(tbl) do keys[k] = true end
        return keys
    end
    local cycle_keys = get_keys(cycle)
    local ref_keys = get_keys(reference)

    for k in pairs(ref_keys) do
        if not cycle_keys[k] then
            return false
        end
    end
    for k in pairs(cycle_keys) do
        if not ref_keys[k] then
            return false
        end
    end
    return true
end

return CycleManager