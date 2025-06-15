CycleManager = {}

local range_total_menstrual_cycle_duration = {28, 34}
local range_follicular_phase_duration = {11, 16}
local range_red_phase_duration = {3, 5}
local range_luteal_phase_duration = {11, 18}
local range_ovulation_phase_duration = {1, 1}

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
        luteal_duration = 14
    }
end

function CycleManager.newCycle()
    local max_attempts = 10 -- Duration values can be user-defined and may not always yield a valid cycle, so we try multiple times to find a valid one and return a default cycle if we fail
    for attempt = 1, max_attempts do
        print("Attempt " .. attempt .. " to generate a new menstrual cycle...")

        local cycle_start_day = getGameTime():getWorldAgeHours() / 24

        local cycle_duration = random_between(range_total_menstrual_cycle_duration)

        local min_follicular = math.max(range_follicular_phase_duration[1], cycle_duration - range_luteal_phase_duration[2])
        local max_follicular = math.min(range_follicular_phase_duration[2], cycle_duration - range_luteal_phase_duration[1])

        if min_follicular <= max_follicular then
            local follicular_duration = ZombRand(min_follicular, max_follicular)

            -- Red day always occurs at the start of the cycle
            local red_days_duration = random_between(range_red_phase_duration)

            local follicle_stimulating_start_day = cycle_start_day + red_days_duration + 1
            local follicle_stimulating_duration = follicular_duration - red_days_duration

            local ovulation_duration = random_between(range_ovulation_phase_duration)
            local ovulation_day = follicular_duration

            local luteal_start_day = follicular_duration + ovulation_duration
            local luteal_duration = cycle_duration - follicular_duration - ovulation_duration

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
                luteal_duration = luteal_duration
            }
        end
    end

    print("Error: Failed to generate a valid menstrual cycle after " .. max_attempts .. " attempts. Returning default cycle values.")
    return default_cycle()
end

function CycleManager.getCurrentCyclePhase(cycle)
    local current_day = getGameTime():getWorldAgeHours() / 24 
    local days_into_cycle = current_day - cycle.cycle_start_day

    if days_into_cycle <= red_days_duration then
        return "redPhase"
    elseif days_into_cycle <= follicle_stimulating_start_day then
        return "follicularPhase"
    elseif days_into_cycle <= ovulation_day then
        return "ovulationPhase"
    elseif days_into_cycle < luteal_start_day then
        return "lutealPhase"
    end

    return "unknownPhase"
end

return CycleManager