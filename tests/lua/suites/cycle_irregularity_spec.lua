-- RD_cycle_irregularity.lua -- health-driven follicular-phase delays.

local T = require "runner"
local H = require "harness.init"

local DAY = 1440
local HOUR = 60

local BASE_SANDBOX = {
    follicular_phase_max_days = 45,
    follicular_irregularity_severity_pct = 100,
    trauma_hp_threshold_pct = 25,
    trauma_follicular_delay_days = 30,
    phase_start_delay_enabled = false,
}

local function follicularCycle(overrides)
    local cycle = {
        current_phase = "follicularPhase",
        phase_minutes_remaining = 10 * DAY,
        follicularPhase_duration_mins = 12 * DAY,
        traumaDelayAppliedThisCycle = false,
    }
    for k, v in pairs(overrides or {}) do cycle[k] = v end
    return cycle
end

local function world(sandbox, player)
    local merged = {}
    for k, v in pairs(BASE_SANDBOX) do merged[k] = v end
    for k, v in pairs(sandbox or {}) do merged[k] = v end
    return H.newWorld({ sandbox = merged, player = player })
end

T.describe("RD_CycleIrregularity.addFollicularMinutes", function()

    T.it("extends both the phase duration and the remaining countdown", function()
        local w = world()
        local cycle = follicularCycle()
        local added = w.env.RD_CycleIrregularity.addFollicularMinutes(cycle, 3 * HOUR)
        T.eq(added, 3 * HOUR)
        T.eq(cycle.follicularPhase_duration_mins, (12 * DAY) + (3 * HOUR))
        T.eq(cycle.phase_minutes_remaining, (10 * DAY) + (3 * HOUR))
    end)

    T.it("does nothing outside the follicular phase", function()
        local w = world()
        for _, phase in ipairs({ "redPhase", "ovulationPhase", "lutealPhase" }) do
            local cycle = follicularCycle({ current_phase = phase })
            T.eq(w.env.RD_CycleIrregularity.addFollicularMinutes(cycle, 5 * HOUR), 0,
                 "should be a no-op during " .. phase)
            T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
        end
    end)

    T.it("ignores non-positive amounts and a nil cycle", function()
        local w = world()
        local cycle = follicularCycle()
        T.eq(w.env.RD_CycleIrregularity.addFollicularMinutes(cycle, 0), 0)
        T.eq(w.env.RD_CycleIrregularity.addFollicularMinutes(cycle, -60), 0)
        T.eq(w.env.RD_CycleIrregularity.addFollicularMinutes(nil, 60), 0)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
    end)

    T.it("clamps growth to follicular_phase_max_days", function()
        local w = world({ follicular_phase_max_days = 20 })
        local cycle = follicularCycle({ follicularPhase_duration_mins = 18 * DAY })
        -- Only 2 days of room left, so a 10-day request is trimmed.
        local added = w.env.RD_CycleIrregularity.addFollicularMinutes(cycle, 10 * DAY)
        T.eq(added, 2 * DAY)
        T.eq(cycle.follicularPhase_duration_mins, 20 * DAY)
    end)

    T.it("never shrinks a phase that already exceeds the cap", function()
        local w = world({ follicular_phase_max_days = 20 })
        local cycle = follicularCycle({
            follicularPhase_duration_mins = 30 * DAY,   -- already over the cap
            phase_minutes_remaining = 25 * DAY,
        })
        local added = w.env.RD_CycleIrregularity.addFollicularMinutes(cycle, 5 * DAY)
        T.eq(added, 0, "no room, so nothing is added")
        T.eq(cycle.follicularPhase_duration_mins, 30 * DAY, "and nothing is taken away")
        T.eq(cycle.phase_minutes_remaining, 25 * DAY)
    end)

end)

T.describe("RD_CycleIrregularity.applyDailyWeightCause", function()

    local SEVERE = { "VERY_UNDERWEIGHT", "OBESE", "EMACIATED" }
    local MILD = { "UNDERWEIGHT", "OVERWEIGHT" }

    T.it("adds a large delay for each severe weight trait", function()
        for _, trait in ipairs(SEVERE) do
            local w = world(nil, { traits = { trait } })
            w.t.rng.script({ 24 })          -- ZombRand(16, 37) -> 24 hours
            local cycle = follicularCycle()
            w.env.RD_CycleIrregularity.applyDailyWeightCause(cycle)
            T.eq(cycle.follicularPhase_duration_mins, (12 * DAY) + (24 * HOUR),
                 "trait " .. trait .. " should add its rolled hours")
        end
    end)

    T.it("adds a small delay for each mild weight trait", function()
        for _, trait in ipairs(MILD) do
            local w = world(nil, { traits = { trait } })
            w.t.rng.script({ 6 })           -- ZombRand(0, 9) -> 6 hours
            local cycle = follicularCycle()
            w.env.RD_CycleIrregularity.applyDailyWeightCause(cycle)
            T.eq(cycle.follicularPhase_duration_mins, (12 * DAY) + (6 * HOUR),
                 "trait " .. trait .. " should add its rolled hours")
        end
    end)

    T.it("treats a severe trait as severe even alongside a mild one", function()
        local w = world(nil, { traits = { "OVERWEIGHT", "OBESE" } })
        w.t.rng.script({ 30 })
        local cycle = follicularCycle()
        w.env.RD_CycleIrregularity.applyDailyWeightCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, (12 * DAY) + (30 * HOUR))
    end)

    T.it("does nothing for a character with no weight trait", function()
        local w = world(nil, { traits = {} })
        local cycle = follicularCycle()
        w.env.RD_CycleIrregularity.applyDailyWeightCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
        T.eq(cycle.phase_minutes_remaining, 10 * DAY)
    end)

    T.it("scales the delay by follicular_irregularity_severity_pct", function()
        local w = world({ follicular_irregularity_severity_pct = 50 }, { traits = { "OBESE" } })
        w.t.rng.script({ 24 })
        local cycle = follicularCycle()
        w.env.RD_CycleIrregularity.applyDailyWeightCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, (12 * DAY) + (12 * HOUR),
             "50% severity should halve the rolled delay")
    end)

    T.it("is disabled entirely at zero severity", function()
        local w = world({ follicular_irregularity_severity_pct = 0 }, { traits = { "OBESE" } })
        local cycle = follicularCycle()
        w.env.RD_CycleIrregularity.applyDailyWeightCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
    end)

    T.it("only applies during the follicular phase", function()
        local w = world(nil, { traits = { "OBESE" } })
        local cycle = follicularCycle({ current_phase = "lutealPhase" })
        w.env.RD_CycleIrregularity.applyDailyWeightCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
    end)

end)

T.describe("RD_CycleIrregularity.checkTraumaCause", function()

    T.it("adds the configured delay when health drops below the threshold", function()
        local w = world(nil, { health = 20 })     -- threshold is 25
        local cycle = follicularCycle()
        w.env.RD_CycleIrregularity.checkTraumaCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, (12 * DAY) + (30 * DAY))
        T.truthy(cycle.traumaDelayAppliedThisCycle)
    end)

    T.it("does nothing while health is at or above the threshold", function()
        for _, health in ipairs({ 25, 26, 100 }) do
            local w = world(nil, { health = health })
            local cycle = follicularCycle()
            w.env.RD_CycleIrregularity.checkTraumaCause(cycle)
            T.eq(cycle.follicularPhase_duration_mins, 12 * DAY,
                 "health " .. health .. " should not trigger trauma")
            T.falsy(cycle.traumaDelayAppliedThisCycle)
        end
    end)

    T.it("fires at most once per cycle", function()
        local w = world(nil, { health = 10 })
        local cycle = follicularCycle()
        w.env.RD_CycleIrregularity.checkTraumaCause(cycle)
        local afterFirst = cycle.follicularPhase_duration_mins
        for _ = 1, 20 do
            w.env.RD_CycleIrregularity.checkTraumaCause(cycle)
        end
        T.eq(cycle.follicularPhase_duration_mins, afterFirst,
             "repeated low-health ticks must not stack delays")
    end)

    T.it("latches even when the cap prevents any minutes being added", function()
        -- Already over the cap, so addFollicularMinutes contributes nothing --
        -- but the trauma event itself has still happened.
        local w = world({ follicular_phase_max_days = 10 }, { health = 5 })
        local cycle = follicularCycle({ follicularPhase_duration_mins = 12 * DAY })
        w.env.RD_CycleIrregularity.checkTraumaCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
        T.truthy(cycle.traumaDelayAppliedThisCycle,
                 "the trauma event happens once per cycle regardless of capping")
    end)

    T.it("respects a zero-day trauma delay setting", function()
        local w = world({ trauma_follicular_delay_days = 0 }, { health = 5 })
        local cycle = follicularCycle()
        w.env.RD_CycleIrregularity.checkTraumaCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
        T.truthy(cycle.traumaDelayAppliedThisCycle)
    end)

    T.it("only applies during the follicular phase", function()
        local w = world(nil, { health = 1 })
        local cycle = follicularCycle({ current_phase = "redPhase" })
        w.env.RD_CycleIrregularity.checkTraumaCause(cycle)
        T.eq(cycle.follicularPhase_duration_mins, 12 * DAY)
        T.falsy(cycle.traumaDelayAppliedThisCycle)
    end)

end)
