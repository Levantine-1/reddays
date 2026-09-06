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

return RD_CycleIrregularity
