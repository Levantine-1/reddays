-- Loading saves written by older versions of the mod.
--
-- Everything the mod keeps lives in player:getModData().ICdata. Newer fields must be filled
-- in with a default on load (`x = x or default`), and a cycle whose structure no longer matches
-- is caught by RD_CycleManager.isCycleValid and regenerated. These fixtures reproduce the real
-- shapes each release saved (taken from the version folders in this repo), load them the way
-- the game does, and then play three in-game days on top of them.

local T = require "runner"
local H = require "harness.init"

local HYGIENE = "RedDays:HygieneItem"

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deepCopy(val) end
    return out
end

local SYMPTOMS = {
    pms_agitation = true, pms_cramps = true, pms_fatigue = false,
    pms_tenderBreasts = false, pms_craveFood = true, pms_Sadness = false,
}

-- The calendar layout is identical in the legacy 42 build and 42.20 (newCalendar()).
local function oldCalendar()
    local lines = {}
    for i = 1, 14 do
        local days = { [i] = "______", [i + 14] = "______" }
        if i <= 3 then days[i + 28] = "______" end
        lines[i] = { days = days }
    end
    lines[1].days[1] = "__H___"  -- a day the player already logged
    return lines
end

-- The countdown-based cycle 42.13 through 42.18 saved: today's shape minus
-- traumaDelayAppliedThisCycle (added with period irregularity in 42.20).
local function countdownCycle(reason)
    local cycle = {
        current_phase = "lutealPhase",
        phase_minutes_remaining = 5000,
        redPhase_duration_mins = 4320,
        follicularPhase_duration_mins = 20160,
        ovulationPhase_duration_mins = 1440,
        lutealPhase_duration_mins = 20160,
        cycle_duration_mins = 46080,
        stiffness_target = 50, stiffness_increment = 2, discomfort_target = 50,
        endurance_decrement = 0.001, fatigue_increment = 0.0002,
        healthEffectSeverity = 50,
        pms_duration_mins = 7200,
        reason_for_cycle = reason,
    }
    for k, v in pairs(SYMPTOMS) do cycle[k] = v end
    return cycle
end

-- The day-based cycle the legacy 42 build saved (42/media/lua/client/cycle_manager.lua).
local function legacyDayBasedCycle()
    local cycle = {
        cycle_start_day = 3.2, cycle_duration = 30, follicular_duration = 14,
        red_days_duration = 4, follicle_stimulating_start_day = 8.5,
        follicle_stimulating_duration = 10, ovulation_duration = 1, ovulation_day = 14.1,
        luteal_start_day = 15.3, luteal_duration = 15,
        stiffness_target = 50, stiffness_increment = 2, discomfort_target = 50,
        endurance_decrement = 0.001, fatigue_increment = 0.0002,
        reason_for_cycle = "fixture_legacy42", timeToDelaycycle = 0,
        healthEffectSeverity = 50, pms_duration = 5,
    }
    for k, v in pairs(SYMPTOMS) do cycle[k] = v end
    return cycle
end

local function trackerKeys(t)
    t.calendar = oldCalendar()
    t.calendarMonth = 7
    t.journalID = "OLDSAVEID001"
    t.pmsSymptoms = deepCopy(SYMPTOMS)
    return t
end

local FIXTURES = {
    {
        name = "empty ICdata",
        icdata = function() return {} end,
    },
    {
        name = "legacy 42 (day-based cycle)",
        keepsTracker = true,
        icdata = function()
            return trackerKeys({
                currentCycle = legacyDayBasedCycle(),
                cycleDelayed = true,
                LeakLevel = 0.3, LeakSwitchState = true, cSIHDC_counter = 40,
                pill_recently_taken = false, pill_effect_active = false, pill_effect_counter = 0,
            })
        end,
    },
    {
        name = "42.13-42.18 (no TSS, no food fields)",
        keepsCycle = "fixture_42_13",
        keepsTracker = true,
        icdata = function()
            return trackerKeys({
                currentCycle = countdownCycle("fixture_42_13"),
                cycleDelayed = true,
                LeakLevel = 0.42, LeakSwitchState = false, cSIHDC_counter = 0,
                pill_recently_taken = false, pill_effect_active = false, pill_effect_counter = 0,
            })
        end,
    },
    {
        name = "42.18 partial TSS table (no antibiotic bank fields)",
        keepsCycle = "fixture_42_18",
        keepsTracker = true,
        tssStage = 2,
        icdata = function()
            return trackerKeys({
                currentCycle = countdownCycle("fixture_42_18"),
                cycleDelayed = true,
                LeakLevel = 0.42, LeakSwitchState = false,
                pill_recently_taken = false, pill_effect_active = false, pill_effect_counter = 0,
                tss = {
                    stage = 2, exposure_minutes = 900, untreated_minutes = 120,
                    stage_threshold = 9000, source_active = false, source_removed = true,
                    source_type = "tampon", warning_cooldown = 30, recovery_mode = "none",
                },
            })
        end,
    },
    {
        name = "pre-food 42.20",
        keepsCycle = "fixture_pre_food",
        keepsTracker = true,
        icdata = function()
            local cycle = countdownCycle("fixture_pre_food")
            cycle.traumaDelayAppliedThisCycle = false
            return trackerKeys({
                currentCycle = cycle,
                cycleDelayed = true,
                LeakLevel = 0.42, LeakSwitchState = false, cSIHDC_counter = 10,
                pill_recently_taken = false, pill_effect_active = false, pill_effect_counter = 0,
                tss = { stage = 0, exposure_minutes = 0, severity = 0, abx_dose_count = 0 },
            })
        end,
    },
    {
        name = "mid-effect (painkiller and food countdowns running)",
        keepsCycle = "fixture_mid_effect",
        keepsTracker = true,
        icdata = function()
            return trackerKeys({
                currentCycle = countdownCycle("fixture_mid_effect"),
                cycleDelayed = true,
                LeakLevel = 0.42, LeakSwitchState = false,
                pill_recently_taken = true, pill_effect_active = true, pill_effect_counter = 10,
                food_pms_effect_active = true, food_pms_effect_counter = 5, food_pms_reduction_pct = 18,
                tss = { stage = 0 },
            })
        end,
    },
}

-- Every key the current code reads, which must exist after a load.
local DEFAULTED = {
    "currentCycle", "pmsSymptoms", "calendar", "calendarMonth", "journalID",
    "pill_recently_taken", "pill_effect_active", "pill_effect_counter",
    "food_pms_reduction_pct", "food_pms_effect_active", "food_pms_effect_counter",
    "LeakLevel", "LeakSwitchState", "tss",
}
local TSS_DEFAULTED = {
    "stage", "exposure_minutes", "severity", "stage_threshold", "recovery_timer",
    "wear_minutes", "source_item_id", "recovery_mode", "tss_risk",
    "abx_toxin_level", "abx_cooldown_mins", "abx_suppress_mins", "abx_dose_count",
    "abx_bank_points", "abx_bank_cap", "abx_bank_drain_per_min", "abx_toxin_clear_per_point",
}

local function loadFixture(fixture, isClient)
    local w = H.newWorld({
        autoStart = false,
        isClient = isClient,
        player = { modData = { ICdata = fixture.icdata() } },
    })
    local ok, err = pcall(w.start)
    T.truthy(ok, fixture.name .. " failed to load: " .. tostring(err))
    return w
end

-- Plays the kind of session an old save would see: a period tracker in the bag, a tampon put
-- on and taken off (which writes the old calendar into the journal), and 3 in-game days.
local function playThreeDays(w, fixtureName)
    local journal = w.t.newItem({ type = "Period_Tracker", isClothing = false })
    w.t.player.inventory:AddItem(journal)
    local tampon = w.t.newItem({ type = "Tampon", bodyLocation = HYGIENE })

    local ok, err = pcall(function()
        w.t.player.worn:add(tampon, HYGIENE)
        w.env.ISWearClothing.perform(w.t.actions.instance("ISWearClothing", tampon))
        w.advanceHours(12, { framesPerMinute = 1 })
        w.env.ISUnequipAction.perform(w.t.actions.instance("ISUnequipAction", tampon))
        w.t.player.worn:remove(tampon)
        w.advanceDays(2.5, { framesPerMinute = 1 })
    end)
    T.truthy(ok, fixtureName .. " errored during play: " .. tostring(err))
    return journal
end

for _, mode in ipairs({ { label = "SP", isClient = false }, { label = "MP client", isClient = true } }) do
    T.describe("loading old saves (" .. mode.label .. ")", function()
        for _, fixture in ipairs(FIXTURES) do

            T.it(fixture.name .. ": loads, keeps what is valid, fills in the rest", function()
                local w = loadFixture(fixture, mode.isClient)
                local ic = w.icdata()

                T.truthy(w.env.RD_CycleManager.isCycleValid(ic.currentCycle), "the cycle must be valid after load")
                if fixture.keepsCycle then
                    T.eq(ic.currentCycle.reason_for_cycle, fixture.keepsCycle, "a still-valid cycle is kept")
                else
                    T.isNil(ic.currentCycle.cycle_start_day, "an old-structure cycle is regenerated")
                end

                if fixture.keepsTracker then
                    T.eq(ic.journalID, "OLDSAVEID001", "the journal ID must survive, or the player's book is orphaned")
                    T.eq(ic.calendar[1].days[1], "__H___", "logged calendar days must survive")
                    T.eq(ic.pmsSymptoms, SYMPTOMS, "the character's PMS symptoms must survive")
                end
                if fixture.tssStage then
                    T.eq(ic.tss.stage, fixture.tssStage, "an in-progress TSS stage must survive")
                    T.eq(ic.tss.severity, 120, "the old untreated_minutes field migrates to severity")
                end

                for _, key in ipairs(DEFAULTED) do
                    T.notNil(ic[key], "ICdata." .. key .. " must be defaulted on load")
                end
                for _, key in ipairs(TSS_DEFAULTED) do
                    T.notNil(ic.tss[key], "ICdata.tss." .. key .. " must be defaulted on load")
                end
            end)

            T.it(fixture.name .. ": survives three in-game days of play", function()
                local w = loadFixture(fixture, mode.isClient)
                local journal = playThreeDays(w, fixture.name)
                local ic = w.icdata()

                T.truthy(w.env.RD_CycleManager.isCycleValid(ic.currentCycle))
                T.notNil(ic.cSIHDC_counter, "the hygiene counter is saved within the first ten minutes")
                for key in pairs(ic) do
                    T.falsy(string.find(tostring(key), "^_selftest"), "self-test key left in the save: " .. tostring(key))
                end
                if fixture.keepsTracker then
                    local idPage = journal:seePage(14)
                    T.truthy(idPage and string.find(idPage, "OLDSAVEID001", 1, true),
                        "the journal must be registered to the save's own journal ID")
                end
                T.falsy(ic.pill_effect_active, "a running painkiller effect must still expire")
                T.falsy(ic.food_pms_effect_active, "a running food effect must still expire")
                T.eq(ic.food_pms_reduction_pct, 0)
            end)

        end
    end)
end
