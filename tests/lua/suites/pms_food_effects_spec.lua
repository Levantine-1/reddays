-- RD_effects_pms.lua -- food-based PMS reduction (new feature) and the rebalanced,
-- now sandbox-configurable painkiller strength that shipped alongside it.

local T = require "runner"
local H = require "harness.init"

local TEN_MIN = "EveryTenMinutes"

-- ================= FOOD STACKING / DETECTION =================

T.describe("RD_EffectsPMS.registerFoodPMSEffect", function()

    T.it("activates the effect and records the item's reduction percent", function()
        local w = H.newWorld()
        local cheese = w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" })
        w.env.RD_EffectsPMS.registerFoodPMSEffect(cheese)

        local ic = w.icdata()
        T.truthy(ic.food_pms_effect_active)
        T.eq(ic.food_pms_reduction_pct, 8)
        T.eq(ic.food_pms_effect_counter, 0)
    end)

    T.it("does nothing for a food with no listed PMS benefit", function()
        local w = H.newWorld()
        local apple = w.t.newItem({ type = "Apple", fullType = "Base.Apple" })
        w.env.RD_EffectsPMS.registerFoodPMSEffect(apple)

        T.falsy(w.icdata().food_pms_effect_active)
        T.eq(w.icdata().food_pms_reduction_pct, 0)
    end)

    T.it("stacks distinct qualifying foods", function()
        local w = H.newWorld()
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" }))
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Banana", fullType = "Base.Banana" }))
        T.eq(w.icdata().food_pms_reduction_pct, 12)  -- 8 + 4
    end)

    T.it("caps the total at the sandbox cap", function()
        local w = H.newWorld({ sandbox = { foodPMSReductionCapPct = 20 } })
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Milk", fullType = "Base.Milk" }))       -- 10
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Chocolate", fullType = "Base.Chocolate" })) -- +10 = 20
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" }))   -- +8, would be 28
        T.eq(w.icdata().food_pms_reduction_pct, 20, "must not exceed the configured cap")
    end)

    T.it("resets the shared countdown when another qualifying food is eaten", function()
        local w = H.newWorld()
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" }))
        for _ = 1, 5 do w.t.events.fire(TEN_MIN) end
        T.eq(w.icdata().food_pms_effect_counter, 5)

        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Banana", fullType = "Base.Banana" }))
        T.eq(w.icdata().food_pms_effect_counter, 0,
             "eating again should reset the countdown, exactly like re-taking a painkiller")
    end)

    T.it("credits fish by tag rather than an exact FullType match", function()
        local w = H.newWorld()
        -- Real fish items are inconsistent on FoodType but consistently tagged base:fishmeat
        -- (ItemTag.FISH_MEAT). Tags are read from the script item via hasItemTag(String, ItemTag).
        w.t.setScriptItemTags("Base.RedearSunfish", { w.env.ItemTag.FISH_MEAT })
        local sunfish = w.t.newItem({ type = "RedearSunfish", fullType = "Base.RedearSunfish" })
        w.env.RD_EffectsPMS.registerFoodPMSEffect(sunfish)
        T.eq(w.icdata().food_pms_reduction_pct, 4)
    end)

    T.it("credits every qualifying ingredient folded into a cooked meal", function()
        local w = H.newWorld()
        -- The meal's own FullType is the fixed evolved-recipe result, not any ingredient's type.
        -- Ingredient lists hold full-type STRINGS (ArrayList<String>), not item objects.
        w.t.setScriptItemTags("Base.Salmon", { w.env.ItemTag.FISH_MEAT })
        local stew = w.t.newItem({ type = "PotOfStew", fullType = "Base.PotOfStew", isFood = true })
        stew:__addExtraItem("Base.Cheese")  -- 8
        stew:__addExtraItem("Base.Banana")  -- 4
        stew:__addSpice("Base.Salmon")      -- 4, via the fish tag

        w.env.RD_EffectsPMS.registerFoodPMSEffect(stew)
        T.eq(w.icdata().food_pms_reduction_pct, 16)
    end)

    T.it("does not inspect ingredients of a non-Food item", function()
        local w = H.newWorld()
        -- A hygiene item is not a Food instance; haveExtraItems must never be consulted on it.
        local nonFood = w.t.newItem({ type = "Tampon", fullType = "RedDays.Tampon" })
        w.env.RD_EffectsPMS.registerFoodPMSEffect(nonFood)
        T.eq(w.icdata().food_pms_reduction_pct, 0)
    end)

    T.it("expires after the configured duration with no further qualifying food", function()
        -- The countdown checks `counter < max` BEFORE incrementing (mirroring the pre-existing
        -- pill pattern exactly), so it takes max+1 ticks to reach the else/expire branch.
        local w = H.newWorld({ sandbox = { foodPMSEffectDuration = 3 } })
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" }))

        for _ = 1, 3 do w.t.events.fire(TEN_MIN) end
        T.truthy(w.icdata().food_pms_effect_active, "should still be active before the duration elapses")

        w.t.events.fire(TEN_MIN)  -- the 4th tick (max+1) reaches the else branch

        T.falsy(w.icdata().food_pms_effect_active)
        T.eq(w.icdata().food_pms_reduction_pct, 0)
        T.eq(w.icdata().food_pms_effect_counter, 0)
        T.contains(w.t.log(), "PMS Food Effect Ended")
    end)

    T.it("does not keep decrementing after it has already expired", function()
        local w = H.newWorld({ sandbox = { foodPMSEffectDuration = 1 } })
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" }))
        w.t.events.fire(TEN_MIN)  -- counter 0 -> 1 (still < max+1 semantics)
        w.t.events.fire(TEN_MIN)  -- counter(1) < max(1) is false -> expires here
        T.falsy(w.icdata().food_pms_effect_active)

        w.t.events.fire(TEN_MIN)  -- handler should have unregistered itself; this must be a no-op
        T.eq(w.icdata().food_pms_reduction_pct, 0)
        T.eq(w.icdata().food_pms_effect_counter, 0)
    end)

    T.it("REGRESSION: does not double-register the countdown when a second food is eaten while active", function()
        -- Events.Add never dedupes (confirmed via bytecode: plain ArrayList.add, no contains()
        -- check) -- registering twice would run the countdown at double speed and, on the next
        -- expiry, leave an orphan permanently stuck in the handler list (Remove only strips the
        -- first match). This is the exact bug behind the reported "0% / 31 of 36" reading.
        -- EveryTenMinutes already carries other legitimate handlers from normal mod load
        -- (RD_hygiene_manager's SavePlayerData, RD_main's own tick, etc.), so the assertion
        -- is on the DELTA this dose adds, not an absolute count.
        local w = H.newWorld()
        local baseline = #w.t.events.handlersFor(TEN_MIN)
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" }))
        T.eq(#w.t.events.handlersFor(TEN_MIN), baseline + 1)

        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Banana", fullType = "Base.Banana" }))
        T.eq(#w.t.events.handlersFor(TEN_MIN), baseline + 1,
             "a second dose while already active must not add a second registration")
    end)

    T.it("REGRESSION: self-heals an orphaned duplicate left over from the double-registration bug", function()
        -- Simulates a save/state as it would exist under the OLD (buggy) code: a duplicate
        -- registration already sitting in the handler list before this fix ever ran.
        local w = H.newWorld({ sandbox = { foodPMSEffectDuration = 2 } })
        local baseline = #w.t.events.handlersFor(TEN_MIN)
        w.env.RD_EffectsPMS.registerFoodPMSEffect(w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" }))

        local handlers = w.t.events.handlersFor(TEN_MIN)
        T.eq(#handlers, baseline + 1, "sanity: exactly one new registration after a single dose")
        -- Add() appends, so the countdown handler this dose just registered is the last entry.
        table.insert(handlers, handlers[#handlers])  -- artificially inject the duplicate the old bug created
        T.eq(#handlers, baseline + 2)

        -- Both copies fire every tick (counter += 2/tick), so expiry (counter reaches max=2)
        -- arrives on the 2nd real tick.
        w.t.events.fire(TEN_MIN)  -- counter: 0 -> 1 -> 2 (both copies still see active == true)
        T.truthy(w.icdata().food_pms_effect_active, "should not have expired after only 1 tick")

        -- On the 2nd tick, the FIRST copy to fire hits counter(2) < 2 == false and expires:
        -- Remove() strips only that one match (the reported bug) -- but the snapshot-based fire
        -- still calls the SECOND copy too, which now sees active == false (set by the first
        -- copy moments earlier in this same tick) and self-heals immediately, removing itself.
        -- Both copies are gone by the end of THIS tick, not the next one -- a better outcome
        -- than a real per-tick engine dispatch might give, but correct for this harness's
        -- snapshot iteration and still proves the self-heal actually engages.
        w.t.events.fire(TEN_MIN)
        T.falsy(w.icdata().food_pms_effect_active, "should have expired")
        T.eq(w.icdata().food_pms_reduction_pct, 0)
        T.eq(w.icdata().food_pms_effect_counter, 0)
        T.eq(#w.t.events.handlersFor(TEN_MIN), baseline,
             "both the expiring copy and the self-healing orphan must be gone")
    end)

end)

T.describe("RD_EffectsPMS.ISTakePillAction_perform (pre-existing pill system, same double-registration class)", function()

    local function takePills(w, item)
        w.env.RD_EffectsPMS.ISTakePillAction_perform({ item = item })
    end

    T.it("REGRESSION: does not double-register the countdown on a second dose while active", function()
        local w = H.newWorld()
        local baseline = #w.t.events.handlersFor(TEN_MIN)
        local pills = w.t.newItem({ type = "Pills", fullType = "Base.Pills" })

        takePills(w, pills)
        T.eq(#w.t.events.handlersFor(TEN_MIN), baseline + 1)

        takePills(w, pills)
        T.eq(#w.t.events.handlersFor(TEN_MIN), baseline + 1,
             "re-dosing while already active must not add a second registration")
    end)

end)

-- ================= WIRING: the real intercepted vanilla methods =================

T.describe("food PMS effect via the intercepted action classes", function()

    T.it("ISEatFoodAction:complete triggers the food effect for a qualifying item", function()
        local w = H.newWorld()
        local oatmeal = w.t.newItem({ type = "Oatmeal", fullType = "Base.Oatmeal" })
        w.env.ISEatFoodAction.complete(w.t.actions.instance("ISEatFoodAction", oatmeal))

        T.eq(w.icdata().food_pms_reduction_pct, 6)
        T.eq(w.t.actions.originalCalls.ISEatFoodAction, 1,
             "must still chain through to the original vanilla complete()")
    end)

    T.it("REGRESSION: eating a cooked meal with an unlisted FullType does not crash", function()
        -- Reproduces the exact reported bug: a fish/peanut/cheese soup's own FullType
        -- (Base.PotOfSoupRecipe) is not in FOOD_PMS_REDUCTIONS, so getFoodPMSReduction used to
        -- fall through to item:hasTag("fishmeat") -- a raw string, which throws unconditionally
        -- for ANY item, since hasTag only ever accepts an ItemTag object.
        local w = H.newWorld()
        -- Second reported crash: the ingredient list holds full-type STRINGS, and the old code
        -- called :getFullType() on each one ("Object tried to call nil").
        w.t.setScriptItemTags("Base.Salmon", { w.env.ItemTag.FISH_MEAT })
        local soup = w.t.newItem({ type = "PotOfSoupRecipe", fullType = "Base.PotOfSoupRecipe", isFood = true })
        soup:__addExtraItem("Base.Cheese")   -- 8
        soup:__addExtraItem("Base.Peanuts")  -- 4
        soup:__addExtraItem("Base.Salmon")   -- 4, via the fish tag

        w.env.ISEatFoodAction.complete(w.t.actions.instance("ISEatFoodAction", soup))

        T.eq(w.icdata().food_pms_reduction_pct, 16)
        T.eq(w.t.actions.originalCalls.ISEatFoodAction, 1,
             "the vanilla Eat() effect must apply -- this was silently skipped by the crash")
        -- The pcall guard in RD_main.lua would also keep vanilla running; prove the credit
        -- comes from the fix, not from an error being swallowed.
        T.falsy(string.find(w.t.log(), "food-PMS effect skipped", 1, true),
                "the food-PMS hook must not have thrown")
    end)

    T.it("REGRESSION: a bowl served from the pot credits the inherited ingredients", function()
        -- Make2Bowls' InheritFood flag -> Food.copyFoodFromSplit -> Food.copyExtraItems copies
        -- the ingredient list and spices into each bowl (confirmed via bytecode).
        local w = H.newWorld()
        w.t.setScriptItemTags("Base.Salmon", { w.env.ItemTag.FISH_MEAT })
        local bowl = w.t.newItem({ type = "SoupBowl", fullType = "Base.SoupBowl", isFood = true })
        bowl:__addExtraItem("Base.Cheese")
        bowl:__addExtraItem("Base.Peanuts")
        bowl:__addExtraItem("Base.Salmon")

        w.env.ISEatFoodAction.complete(w.t.actions.instance("ISEatFoodAction", bowl))

        T.eq(w.icdata().food_pms_reduction_pct, 16)
        T.falsy(string.find(w.t.log(), "food-PMS effect skipped", 1, true))
    end)

    T.it("credits an ingredient stored without its module prefix", function()
        local w = H.newWorld()
        local soup = w.t.newItem({ type = "PotOfSoupRecipe", fullType = "Base.PotOfSoupRecipe", isFood = true })
        soup:__addExtraItem("Cheese")

        w.env.ISEatFoodAction.complete(w.t.actions.instance("ISEatFoodAction", soup))

        T.eq(w.icdata().food_pms_reduction_pct, 8)
    end)

    T.it("REGRESSION: the vanilla eat effect still applies even if the food-PMS hook throws", function()
        -- Proves the pcall defense-in-depth in RD_main.lua independent of which bug caused a
        -- throw -- a deliberately unrelated failure, not the hasTag one (already fixed above).
        local w = H.newWorld()
        w.env.RD_EffectsPMS.ISEatFoodAction_complete = function() error("simulated unrelated failure", 0) end

        local item = w.t.newItem({ type = "Cheese", fullType = "Base.Cheese" })
        w.env.ISEatFoodAction.complete(w.t.actions.instance("ISEatFoodAction", item))

        T.eq(w.t.actions.originalCalls.ISEatFoodAction, 1,
             "the vanilla eat effect must run regardless of what our own hook does")
    end)

    T.it("REGRESSION: the vanilla drink effect still applies even if the food-PMS hook throws", function()
        local w = H.newWorld()
        w.env.RD_EffectsPMS.ISDrinkFluidAction_complete = function() error("simulated unrelated failure", 0) end

        local milk = w.t.newItem({ type = "Milk", fullType = "Base.Milk" })
        w.env.ISDrinkFluidAction.complete(w.t.actions.instance("ISDrinkFluidAction", milk))

        T.eq(w.t.actions.originalCalls.ISDrinkFluidAction, 1,
             "the vanilla drink effect must run regardless of what our own hook does")
    end)

    T.it("REGRESSION: Milk is drunk via ISDrinkFluidAction, not eaten, and must still register", function()
        -- Milk is a FluidContainer item (ItemType = base:normal) -- confirmed it never reaches
        -- ISEatFoodAction at all. Its only consumption path is ISDrinkFluidAction:complete().
        local w = H.newWorld()
        local milk = w.t.newItem({ type = "Milk", fullType = "Base.Milk" })
        w.env.ISDrinkFluidAction.complete(w.t.actions.instance("ISDrinkFluidAction", milk))

        T.eq(w.icdata().food_pms_reduction_pct, 10)
        T.eq(w.t.actions.originalCalls.ISDrinkFluidAction, 1)
    end)

    T.it("resumes an in-progress food effect across a reload (LoadPlayerData)", function()
        local w = H.newWorld({
            autoStart = false,
            player = { modData = { ICdata = {
                food_pms_effect_active = true,
                food_pms_effect_counter = 30,
                food_pms_reduction_pct = 10,
            } } },
        })
        w.start()  -- fires OnGameStart -> LoadPlayerData, must re-register the countdown handler

        T.truthy(w.icdata().food_pms_effect_active)
        w.t.events.fire(TEN_MIN)
        w.t.events.fire(TEN_MIN)
        T.eq(w.icdata().food_pms_effect_counter, 32)

        -- Default max is 36; the countdown needs max+1-32 = 5 more ticks past here to expire.
        for _ = 1, 5 do w.t.events.fire(TEN_MIN) end
        T.falsy(w.icdata().food_pms_effect_active,
                "the resumed countdown must still expire on schedule, proving the handler was re-registered")
    end)

end)

-- ================= REBALANCE: pill and food strength interaction =================

-- Builds a world with a synthetic luteal-phase cycle pinned at maximum PMS severity
-- (severity=100, healthEffectSeverity=100) with ONLY agitation enabled, so the anger
-- stat's convergence ceiling (severity = target_value/100) directly reveals the combined
-- multiplier -- without advancing the cycle clock, which would otherwise roll into a new phase.
local function maxSeverityWorld(sandbox)
    local w = H.newWorld({ sandbox = sandbox })
    local cycle = w.cycle()
    cycle.current_phase = "lutealPhase"
    cycle.pms_duration_mins = 7 * 1440
    cycle.phase_minutes_remaining = 0        -- mins_into_pms == pms_duration_mins -> severity 100
    cycle.healthEffectSeverity = 100
    cycle.pms_agitation = true
    cycle.pms_cramps = false
    cycle.pms_fatigue = false
    cycle.pms_tenderBreasts = false
    cycle.pms_craveFood = false
    cycle.pms_Sadness = false
    return w
end

-- setAngerMoodle moves ANGER toward `severity` (=target_value/100) by 0.02/call and then holds;
-- 60 calls (1.2 total headroom against a max ceiling of 1.0) guarantees full convergence.
local function convergedAnger(w)
    for _ = 1, 60 do w.env.RD_EffectsPMS.applyPMSEffectsMain() end
    return w.t.player.stats:get(w.env.CharacterStat.ANGER)
end

T.describe("painkiller + food PMS multiplier interaction", function()

    T.it("applies no reduction with neither pill nor food active", function()
        local w = maxSeverityWorld()
        T.near(convergedAnger(w), 1.0, 1e-9)
    end)

    T.it("defaults painkillers to a 50% reduction (rebalanced down from the old 75%)", function()
        local w = maxSeverityWorld()
        w.icdata().pill_effect_active = true
        T.near(convergedAnger(w), 0.5, 1e-9)
    end)

    T.it("honors a custom painkillerEffectReductionPct sandbox value", function()
        local w = maxSeverityWorld({ painkillerEffectReductionPct = 80 })
        w.icdata().pill_effect_active = true
        T.near(convergedAnger(w), 0.2, 1e-9)
    end)

    T.it("applies the food reduction on its own", function()
        local w = maxSeverityWorld()
        w.icdata().food_pms_reduction_pct = 20
        T.near(convergedAnger(w), 0.8, 1e-9)
    end)

    T.it("stacks pill and food as independent multipliers, not combined-additive", function()
        local w = maxSeverityWorld()
        w.icdata().pill_effect_active = true          -- default 50% -> *0.5
        w.icdata().food_pms_reduction_pct = 20         -- *0.8
        -- Independent multipliers: 1.0 * 0.5 * 0.8 = 0.4 (NOT 1 - (0.5+0.2) = 0.3).
        T.near(convergedAnger(w), 0.4, 1e-9)
    end)

end)
