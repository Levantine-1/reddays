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

-- ================= CAUSE 3: CHRONIC STRESS =================
-- Stress is sampled every ten in-game minutes into a running score, and while the player is in
-- the luteal phase that score pushes the period back. Unlike the other two causes this one
-- extends LUTEAL, and its score lives in ICdata so it survives the end-of-cycle regeneration.

local function lutealCycle(overrides)
    local cycle = {
        current_phase = "lutealPhase",
        phase_minutes_remaining = 10 * DAY,
        lutealPhase_duration_mins = 14 * DAY,
    }
    for k, v in pairs(overrides or {}) do cycle[k] = v end
    return cycle
end

local function stressWorld(sandbox, stress)
    local w = world(sandbox)
    w.t.player.stats:__seed(w.env.CharacterStat.STRESS, stress or 0)
    return w
end

local function score(w) return w.icdata().chronicStressScore end

-- One sample per ten minutes.
local function sample(w, cycle, times)
    for _ = 1, (times or 1) do
        w.env.RD_CycleIrregularity.checkStressCause(cycle)
    end
end

T.describe("RD_CycleIrregularity.addLutealMinutes", function()

    T.it("extends both the phase duration and the remaining countdown", function()
        local w = world()
        local cycle = lutealCycle()
        local added = w.env.RD_CycleIrregularity.addLutealMinutes(cycle, 3 * HOUR)
        T.eq(added, 3 * HOUR)
        T.eq(cycle.lutealPhase_duration_mins, (14 * DAY) + (3 * HOUR))
        T.eq(cycle.phase_minutes_remaining, (10 * DAY) + (3 * HOUR))
    end)

    T.it("does nothing outside the luteal phase", function()
        local w = world()
        local cycle = lutealCycle({ current_phase = "follicularPhase" })
        T.eq(w.env.RD_CycleIrregularity.addLutealMinutes(cycle, 3 * HOUR), 0)
        T.eq(cycle.lutealPhase_duration_mins, 14 * DAY)
    end)

    T.it("clamps growth at luteal_phase_max_days without shrinking an over-cap phase", function()
        local w = world({ luteal_phase_max_days = 30 })
        local cycle = lutealCycle({ lutealPhase_duration_mins = 29 * DAY })
        T.eq(w.env.RD_CycleIrregularity.addLutealMinutes(cycle, 5 * DAY), 1 * DAY, "only the room left")
        T.eq(cycle.lutealPhase_duration_mins, 30 * DAY)

        local over = lutealCycle({ lutealPhase_duration_mins = 40 * DAY })
        T.eq(w.env.RD_CycleIrregularity.addLutealMinutes(over, 1 * DAY), 0)
        T.eq(over.lutealPhase_duration_mins, 40 * DAY, "never shrinks a phase already past the cap")
    end)

end)

T.describe("RD_CycleIrregularity.checkStressCause", function()

    T.it("builds the score while stress is above the threshold", function()
        local w = stressWorld({ stress_threshold_pct = 25 }, 1.0)
        sample(w, lutealCycle(), 144)   -- one full day at maximum stress
        T.near(score(w), 36, 0.5, "a day of maximum stress should be about a third of the scale")
    end)

    T.it("builds more slowly at moderate stress and not at all below the threshold", function()
        local moderate = stressWorld({ stress_threshold_pct = 25 }, 0.625)  -- halfway up the band
        sample(moderate, lutealCycle(), 144)
        T.near(score(moderate), 18, 0.5)

        local calm = stressWorld({ stress_threshold_pct = 25 }, 0.25)
        sample(calm, lutealCycle(), 144)
        T.eq(score(calm), 0, "at the threshold itself nothing accumulates")
    end)

    T.it("decays the score during calm and never goes negative", function()
        local w = stressWorld({ stress_threshold_pct = 25 }, 0)
        w.icdata().chronicStressScore = 50
        sample(w, lutealCycle(), 144)
        T.near(score(w), 50 - 21.6, 0.5, "about 21.6 points shed per calm day")

        sample(w, lutealCycle(), 1000)
        T.eq(score(w), 0)
    end)

    T.it("never passes 100", function()
        local w = stressWorld({ stress_threshold_pct = 25 }, 1.0)
        sample(w, lutealCycle(), 144 * 10)
        T.eq(score(w), 100)
    end)

    T.it("delays the period while in luteal, scaled by the score", function()
        -- Stress held at maximum so the score stays pinned at 100 for the whole day.
        local w = stressWorld({ stress_threshold_pct = 25 }, 1.0)
        w.icdata().chronicStressScore = 100
        local cycle = lutealCycle()
        sample(w, cycle, 144)   -- a full day at a maxed-out score
        T.near(cycle.phase_minutes_remaining, (10 * DAY) + (12 * HOUR), 30,
               "a maxed-out score adds about twelve hours per day")
    end)

    T.it("adds nothing outside the luteal phase, but still tracks the score", function()
        local w = stressWorld({ stress_threshold_pct = 25 }, 1.0)
        local cycle = lutealCycle({ current_phase = "follicularPhase",
                                    follicularPhase_duration_mins = 12 * DAY })
        sample(w, cycle, 144)
        T.eq(cycle.phase_minutes_remaining, 10 * DAY, "the follicular phase is not this cause's job")
        T.truthy(score(w) > 0, "stress still builds outside luteal")
    end)

    T.it("scales the delay with the severity option and is disabled at zero", function()
        local half = stressWorld({ stress_irregularity_severity_pct = 50 }, 1.0)
        half.icdata().chronicStressScore = 100
        local halfCycle = lutealCycle()
        sample(half, halfCycle, 144)
        T.near(halfCycle.phase_minutes_remaining, (10 * DAY) + (6 * HOUR), 30)

        local off = stressWorld({ stress_irregularity_severity_pct = 0 }, 1.0)
        off.icdata().chronicStressScore = 100
        local offCycle = lutealCycle()
        sample(off, offCycle, 144)
        T.eq(offCycle.phase_minutes_remaining, 10 * DAY, "severity 0 disables the delay entirely")
    end)

    T.it("respects the luteal cap", function()
        local w = stressWorld({ luteal_phase_max_days = 15 }, 1.0)
        w.icdata().chronicStressScore = 100
        local cycle = lutealCycle({ lutealPhase_duration_mins = 14 * DAY })
        sample(w, cycle, 144 * 5)
        T.eq(cycle.lutealPhase_duration_mins, 15 * DAY)
    end)

    T.it("keeps the score across a new cycle", function()
        local w = stressWorld({ stress_threshold_pct = 25 }, 1.0)
        sample(w, lutealCycle(), 144)
        local before = score(w)
        w.env.RD_CycleManager.newCycle("test_rollover")
        T.eq(score(w), before, "chronic stress is a property of the player, not the cycle")
    end)

end)
