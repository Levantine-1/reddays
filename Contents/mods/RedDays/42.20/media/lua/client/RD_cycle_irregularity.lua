RD_CycleIrregularity = RD_CycleIrregularity or {}
require "RD_game_api"

local MINUTES_PER_HOUR = 60
local MINUTES_PER_DAY = 1440

local function getSandbox()
    return SandboxVars.RedDays or {}
end

-- Shared capping helper every irregularity cause funnels through.
-- No-op outside follicular phase. Caps GROWTH at follicular_phase_max_days without
-- ever shrinking an already-over-cap base roll (only clamps the amount being added).
function RD_CycleIrregularity.addFollicularMinutes(cycle, minutes)
    if not cycle or cycle.current_phase ~= "follicularPhase" then return 0 end
    if not minutes or minutes <= 0 then return 0 end

    local sb = getSandbox()
    local maxDays = sb.follicular_phase_max_days or 45
    local maxMins = maxDays * MINUTES_PER_DAY

    local currentDuration = cycle.follicularPhase_duration_mins or 0
    local room = maxMins - currentDuration
    if room <= 0 then return 0 end

    local actualAdd = math.min(minutes, room)
    cycle.follicularPhase_duration_mins = currentDuration + actualAdd
    cycle.phase_minutes_remaining = (cycle.phase_minutes_remaining or 0) + actualAdd
    return actualAdd
end

-- Cause 1: weight tier. Called once/day from RD_main.lua's EveryDays hook.
function RD_CycleIrregularity.applyDailyWeightCause(cycle)
    if not cycle or cycle.current_phase ~= "follicularPhase" then return end

    local sb = getSandbox()
    local severityPct = sb.follicular_irregularity_severity_pct
    if severityPct == nil then severityPct = 100 end
    if severityPct <= 0 then return end

    local player = RD_zapi.getPlayer()
    if not player then return end

    local isSevere = player:hasTrait(CharacterTrait.VERY_UNDERWEIGHT)
        or player:hasTrait(CharacterTrait.OBESE)
        or player:hasTrait(CharacterTrait.EMACIATED)
    local isMild = (not isSevere)
        and (player:hasTrait(CharacterTrait.UNDERWEIGHT) or player:hasTrait(CharacterTrait.OVERWEIGHT))

    local rolledHours
    if isSevere then
        rolledHours = ZombRand(16, 37) -- inclusive 16-36
    elseif isMild then
        rolledHours = ZombRand(0, 9)   -- inclusive 0-8
    else
        return
    end

    local scaledMinutes = math.floor(rolledHours * MINUTES_PER_HOUR * (severityPct / 100))
    if scaledMinutes <= 0 then return end

    RD_CycleIrregularity.addFollicularMinutes(cycle, scaledMinutes)
end

-- Cause 2: trauma. Called every minute from RD_main.lua's EveryOneMinute.
function RD_CycleIrregularity.checkTraumaCause(cycle)
    if not cycle or cycle.current_phase ~= "follicularPhase" then return end
    if cycle.traumaDelayAppliedThisCycle then return end

    local bd = RD_zapi.getBodyDamage()
    if not bd then return end
    local health = bd:getHealth() or 100

    local sb = getSandbox()
    local threshold = sb.trauma_hp_threshold_pct
    if threshold == nil then threshold = 25 end
    if health >= threshold then return end

    -- Mark applied regardless of capping outcome below: the trauma "event" happens once
    -- per cycle even if the cap already prevents any minutes from actually being added.
    cycle.traumaDelayAppliedThisCycle = true

    local delayDays = sb.trauma_follicular_delay_days
    if delayDays == nil then delayDays = 30 end
    if delayDays <= 0 then return end

    RD_CycleIrregularity.addFollicularMinutes(cycle, delayDays * MINUTES_PER_DAY)
end

-- Luteal counterpart of addFollicularMinutes, capped by luteal_phase_max_days. Same contract:
-- no-op outside the phase, clamps the amount being added rather than an over-cap base roll, and
-- deliberately leaves cycle_duration_mins alone, exactly as the follicular helper does.
function RD_CycleIrregularity.addLutealMinutes(cycle, minutes)
    if not cycle or cycle.current_phase ~= "lutealPhase" then return 0 end
    if not minutes or minutes <= 0 then return 0 end

    local maxDays = getSandbox().luteal_phase_max_days or 30
    local maxMins = maxDays * MINUTES_PER_DAY

    local currentDuration = cycle.lutealPhase_duration_mins or 0
    local room = maxMins - currentDuration
    if room <= 0 then return 0 end

    local actualAdd = math.min(minutes, room)
    cycle.lutealPhase_duration_mins = currentDuration + actualAdd
    cycle.phase_minutes_remaining = (cycle.phase_minutes_remaining or 0) + actualAdd
    return actualAdd
end

-- Cause 3: chronic stress. Called every ten in-game minutes from RD_main.lua.
--
-- Stress above the threshold feeds a 0-100 score that builds in about three hard days and takes
-- roughly four and a half calm ones to clear, so it tracks a rough patch rather than one bad
-- fight. While the player is in the luteal phase the score holds the period back, at most about
-- twelve hours per day -- deliberately gentler than the weight cause's 16-36 hours, and capped,
-- so a period is always late rather than cancelled.
local STRESS_SAMPLES_PER_DAY = 144          -- one per ten in-game minutes
local STRESS_SCORE_MAX = 100
local STRESS_GAIN_PER_SAMPLE = 0.25         -- 36/day at maximum stress
local STRESS_DECAY_PER_SAMPLE = 0.15        -- 21.6/day while calm
local STRESS_LUTEAL_MINUTES_PER_SAMPLE = 5  -- 12 hours/day at a maxed-out score

function RD_CycleIrregularity.checkStressCause(cycle)
    if not RD_modData or not RD_modData.ICdata then return end

    local player = RD_zapi.getPlayer()
    if not player then return end
    local stats = player:getStats()
    if not stats then return end

    local sb = getSandbox()
    local threshold = (sb.stress_threshold_pct or 25) / 100
    local stress = stats:get(CharacterStat.STRESS) or 0

    local score = RD_modData.ICdata.chronicStressScore or 0
    if stress > threshold then
        local headroom = 1 - threshold
        local intensity = headroom > 0 and ((stress - threshold) / headroom) or 1
        score = math.min(STRESS_SCORE_MAX, score + (intensity * STRESS_GAIN_PER_SAMPLE))
    else
        score = math.max(0, score - STRESS_DECAY_PER_SAMPLE)
    end
    RD_modData.ICdata.chronicStressScore = score

    if score <= 0 then return end

    local severityPct = sb.stress_irregularity_severity_pct
    if severityPct == nil then severityPct = 100 end
    if severityPct <= 0 then return end

    local minutes = (score / STRESS_SCORE_MAX) * STRESS_LUTEAL_MINUTES_PER_SAMPLE * (severityPct / 100)
    RD_CycleIrregularity.addLutealMinutes(cycle, minutes)
end

return RD_CycleIrregularity
