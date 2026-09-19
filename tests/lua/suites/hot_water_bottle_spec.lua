-- RD_hotwater.lua -- the hot water bottle's own heat model and the PMS relief it grants.
--
-- The engine heats any item carrying a FluidContainer component (InventoryItem.update, confirmed
-- via bytecode) but cools it far too quickly for a water bottle, so the mod tracks heat itself on
-- a half-life curve and writes the result back with setItemHeat so the inventory's red border
-- still matches.

local T = require "runner"
local H = require "harness.init"

local BOTTLE = "Base.HotWaterBottle"

local function world(sandbox)
    local merged = { phase_start_delay_enabled = false }
    for k, v in pairs(sandbox or {}) do merged[k] = v end
    return H.newWorld({ sandbox = merged })
end

local function bottle(w, opts)
    opts = opts or {}
    return w.t.newItem({
        type = "HotWaterBottle",
        fullType = BOTTLE,
        isClothing = false,
        itemHeat = opts.itemHeat or 1.0,
        fluidAmount = opts.fluidAmount == nil and 1.0 or opts.fluidAmount,
    })
end

local function hold(w, item)
    w.t.player:setPrimaryHandItem(item)
    return item
end

-- The heat model only samples on the minute tick, so time has to pass through the real handlers.
local function heatOf(w, item)
    return item:getModData().rdHeat
end

T.describe("RD_HotWater heat model", function()

    T.it("adopts the engine's heat while something is heating the bottle", function()
        local w = world()
        local item = hold(w, bottle(w, { itemHeat = 1.9 }))
        w.advanceMinutes(1)
        T.near(heatOf(w, item), 1.9, 1e-6)
    end)

    T.it("cools on a half-life curve instead of the engine's fast drop", function()
        local w = world({ hot_water_bottle_cooling_halflife_mins = 90 })
        local item = hold(w, bottle(w, { itemHeat = 2.0 }))
        w.advanceMinutes(1)                 -- picks up the 2.0
        item.itemHeat = 1.0                 -- the engine has already dumped its own heat

        w.advanceMinutes(90)
        T.near(heatOf(w, item), 1.5, 0.01, "half the warmth left after one half-life")

        w.advanceMinutes(90)
        T.near(heatOf(w, item), 1.25, 0.01, "and half of that again after the next")
    end)

    T.it("writes the tracked heat back so the inventory border matches", function()
        local w = world({ hot_water_bottle_cooling_halflife_mins = 90 })
        local item = hold(w, bottle(w, { itemHeat = 2.0 }))
        w.advanceMinutes(1)
        item.itemHeat = 1.0
        w.advanceMinutes(90)
        T.near(item:getItemHeat(), 1.5, 0.01)
    end)

    T.it("treats an empty bottle as cold", function()
        local w = world()
        local item = hold(w, bottle(w, { itemHeat = 2.0, fluidAmount = 0 }))
        w.advanceMinutes(1)
        T.near(heatOf(w, item), 1.0, 1e-6)
    end)

    T.it("respects a longer configured half-life", function()
        local w = world({ hot_water_bottle_cooling_halflife_mins = 180 })
        local item = hold(w, bottle(w, { itemHeat = 2.0 }))
        w.advanceMinutes(1)
        item.itemHeat = 1.0
        w.advanceMinutes(180)
        T.near(heatOf(w, item), 1.5, 0.01)
    end)

end)

T.describe("RD_HotWater.getReductionPct", function()

    local function reductionFor(heat, sandbox)
        local w = world(sandbox)
        local item = hold(w, bottle(w, { itemHeat = heat }))
        w.advanceMinutes(1)
        return w.env.RD_HotWater.getReductionPct()
    end

    T.it("gives the full configured reduction at a fully hot bottle", function()
        T.near(reductionFor(1.8), 30, 1e-6)
        T.near(reductionFor(2.0), 30, 1e-6, "hotter than full still caps at the configured value")
    end)

    T.it("scales down as the bottle cools", function()
        T.near(reductionFor(1.45), 15, 0.2, "halfway up the band is half the relief")
    end)

    T.it("gives nothing once the bottle is barely warm", function()
        T.eq(reductionFor(1.1), 0)
        T.eq(reductionFor(1.0), 0)
    end)

    T.it("honours the configured maximum", function()
        T.near(reductionFor(1.8, { hot_water_bottle_reduction_pct = 50 }), 50, 1e-6)
        T.eq(reductionFor(1.8, { hot_water_bottle_reduction_pct = 0 }), 0)
    end)

    T.it("gives nothing with empty hands, or with something else held", function()
        local w = world()
        T.eq(w.env.RD_HotWater.getReductionPct(), 0)

        hold(w, w.t.newItem({ type = "Pan", fullType = "Base.Pan", isClothing = false, itemHeat = 2.0 }))
        w.advanceMinutes(1)
        T.eq(w.env.RD_HotWater.getReductionPct(), 0, "a hot frying pan is not a hot water bottle")
    end)

    T.it("counts a bottle in the off hand too", function()
        local w = world()
        local item = bottle(w, { itemHeat = 1.8 })
        w.t.player:setSecondaryHandItem(item)
        w.advanceMinutes(1)
        T.near(w.env.RD_HotWater.getReductionPct(), 30, 1e-6)
    end)

end)

-- ================= PMS INTEGRATION =================

local function maxSeverityWorld(sandbox)
    local w = world(sandbox)
    local cycle = w.cycle()
    cycle.current_phase = "lutealPhase"
    cycle.pms_duration_mins = 7 * 1440
    cycle.phase_minutes_remaining = 0
    cycle.healthEffectSeverity = 100
    cycle.pms_agitation = true
    cycle.pms_cramps = false
    cycle.pms_fatigue = false
    cycle.pms_tenderBreasts = false
    cycle.pms_craveFood = false
    cycle.pms_Sadness = false
    return w
end

local function convergedAnger(w)
    for _ = 1, 60 do w.env.RD_EffectsPMS.applyPMSEffectsMain() end
    return w.t.player.stats:get(w.env.CharacterStat.ANGER)
end

T.describe("hot water bottle PMS relief", function()

    T.it("eases symptoms while a hot bottle is held", function()
        local w = maxSeverityWorld()
        hold(w, bottle(w, { itemHeat = 1.8 }))
        -- Seeded directly rather than through advanceMinutes: the pinned cycle has no time left,
        -- so a real tick would roll straight into a fresh one and wipe the severity.
        w.env.RD_HotWater.EveryOneMinute()
        T.near(convergedAnger(w), 0.7, 1e-6, "30% off at full heat")
    end)

    T.it("stacks multiplicatively with painkillers and food, like the other two sources", function()
        local w = maxSeverityWorld()
        hold(w, bottle(w, { itemHeat = 1.8 }))
        w.env.RD_HotWater.EveryOneMinute()
        w.icdata().pill_effect_active = true          -- 50% -> x0.5
        w.icdata().food_pms_reduction_pct = 20         -- x0.8
        -- 1.0 * 0.5 * 0.8 * 0.7
        T.near(convergedAnger(w), 0.28, 1e-6)
    end)

    T.it("changes nothing when no bottle is held", function()
        local w = maxSeverityWorld()
        T.near(convergedAnger(w), 1.0, 1e-9)
    end)

end)
