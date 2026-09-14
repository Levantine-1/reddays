-- Long-run property tests.
--
-- These drive the real EveryOneMinute chain for months of in-game time across
-- many RNG seeds, asserting things that must hold at every point. This is the
-- class of bug that is close to untestable by hand: a stall or a runaway phase
-- that only shows up after several cycles.

local T = require "runner"
local H = require "harness.init"

local DAY = 1440
local VALID_PHASES = {
    redPhase = true, follicularPhase = true, ovulationPhase = true, lutealPhase = true,
}

-- Sampling interval for the invariant checks. Checking every single minute makes
-- these tests several times slower without finding anything extra, because the
-- state only changes meaningfully on phase boundaries.
local SAMPLE_EVERY = 60

local function runSimulation(opts)
    local w = H.newWorld({
        seed = opts.seed,
        sandbox = opts.sandbox,
        player = opts.player,
    })

    local phasesSeen = {}
    local cyclesGenerated = 0
    -- Counted by TABLE IDENTITY, not by reason_for_cycle: consecutive cycles
    -- legitimately share the same reason string ("tick_endOfCycle"), so comparing
    -- the string would silently under-count.
    local lastCycle = w.cycle()
    local violations = {}

    w.advanceDays(opts.days, {
        onMinute = function(env, minute)
            local cycle = env.RD_modData.ICdata.currentCycle
            if not cycle then
                violations[#violations + 1] = "no cycle at minute " .. minute
                return
            end
            if cycle ~= lastCycle then
                cyclesGenerated = cyclesGenerated + 1
                lastCycle = cycle
            end
            phasesSeen[cycle.current_phase] = true

            if minute % SAMPLE_EVERY ~= 0 then return end

            if not VALID_PHASES[cycle.current_phase] then
                violations[#violations + 1] =
                    "invalid phase '" .. tostring(cycle.current_phase) .. "' at minute " .. minute
            end
            if (cycle.phase_minutes_remaining or 0) < 0 then
                violations[#violations + 1] =
                    "negative countdown " .. tostring(cycle.phase_minutes_remaining)
                    .. " at minute " .. minute
            end
            if opts.maxFollicularDays
               and cycle.follicularPhase_duration_mins > opts.maxFollicularDays * DAY then
                violations[#violations + 1] =
                    "follicular phase " .. (cycle.follicularPhase_duration_mins / DAY)
                    .. " days exceeds cap " .. opts.maxFollicularDays
                    .. " at minute " .. minute
            end
        end,
    })

    return {
        world = w,
        violations = violations,
        phasesSeen = phasesSeen,
        cyclesGenerated = cyclesGenerated,
    }
end

T.describe("long-run cycle invariants", function()

    T.it("holds its invariants across 60 days on many seeds", function()
        for seed = 1, 6 do
            local result = runSimulation({ seed = seed, days = 60 })
            T.eq(result.violations, {}, "seed " .. seed .. " violated an invariant")
        end
    end)

    T.it("passes through every phase over a couple of cycles", function()
        local result = runSimulation({ seed = 7, days = 75 })
        for phase in pairs(VALID_PHASES) do
            T.truthy(result.phasesSeen[phase],
                     "never entered " .. phase .. " in 75 days")
        end
    end)

    T.it("keeps generating new cycles rather than stalling", function()
        local result = runSimulation({ seed = 11, days = 90 })
        T.truthy(result.cyclesGenerated >= 2,
                 "expected at least 2 new cycles in 90 days, saw " .. result.cyclesGenerated)
    end)

    T.it("never exceeds the follicular cap even with severe irregularity", function()
        -- An obese character rolls a weight delay every single day; the cap is the
        -- only thing stopping the follicular phase growing without bound.
        local result = runSimulation({
            seed = 3,
            days = 90,
            maxFollicularDays = 20,
            player = { traits = { "OBESE" } },
            sandbox = {
                follicular_phase_max_days = 20,
                follicular_irregularity_severity_pct = 300,
            },
        })
        T.eq(result.violations, {})
    end)

    T.it("survives a permanently near-dead character", function()
        -- Health below the trauma threshold every tick: the once-per-cycle latch
        -- is the only thing preventing an unbounded pile-up of delays.
        local result = runSimulation({
            seed = 5,
            days = 90,
            maxFollicularDays = 45,
            player = { health = 1 },
        })
        T.eq(result.violations, {})
    end)

    T.it("moves the countdown by exactly one minute per tick within a phase", function()
        -- Within a phase the countdown must fall by exactly the tick size. The only
        -- legal exception is an upward jump, which means an irregularity extended
        -- the phase. Anything else -- a skipped minute, a double decrement -- is a bug.
        local w = H.newWorld({ seed = 21, player = { traits = { "OBESE" } } })
        local previous = w.cycle().phase_minutes_remaining
        local previousCycle = w.cycle()
        local previousPhase = previousCycle.current_phase
        local anomalies = {}
        local extensions = 0

        w.advanceDays(40, {
            onMinute = function(env, minute)
                local cycle = env.RD_modData.ICdata.currentCycle
                local now = cycle.phase_minutes_remaining
                local sameSpan = (cycle == previousCycle) and (cycle.current_phase == previousPhase)
                if sameSpan then
                    if now > previous then
                        extensions = extensions + 1          -- irregularity added time
                    elseif now ~= previous - 1 then
                        anomalies[#anomalies + 1] =
                            "minute " .. minute .. ": " .. previous .. " -> " .. now
                    end
                end
                previous = now
                previousCycle = cycle
                previousPhase = cycle.current_phase
            end,
        })

        T.eq(anomalies, {}, "countdown moved by something other than one minute per tick")
        T.truthy(extensions > 0,
                 "an obese character should have had the follicular phase extended at least once")
    end)

end)

T.describe("determinism", function()

    T.it("reproduces an identical 30-day run from the same seed", function()
        local function fingerprint(seed)
            local w = H.newWorld({ seed = seed })
            local marks = {}
            w.advanceDays(30, {
                onMinute = function(env, minute)
                    if minute % (6 * 60) ~= 0 then return end
                    local cycle = env.RD_modData.ICdata.currentCycle
                    marks[#marks + 1] = cycle.current_phase .. ":" .. cycle.phase_minutes_remaining
                end,
            })
            return table.concat(marks, "|")
        end

        T.eq(fingerprint(99), fingerprint(99),
             "the same seed must produce a byte-identical run")
    end)

    T.it("produces different runs from different seeds", function()
        local function totalDuration(seed)
            return H.newWorld({ seed = seed }).cycle().cycle_duration_mins
        end
        local seen = {}
        for seed = 1, 20 do seen[totalDuration(seed)] = true end
        local distinct = 0
        for _ in pairs(seen) do distinct = distinct + 1 end
        T.truthy(distinct > 1, "20 seeds all produced the same cycle length")
    end)

end)
