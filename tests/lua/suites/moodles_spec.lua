-- RD_moodles.lua -- hygiene moodle lifecycle, specifically the "stuck moodle on
-- unequip" regression: dragging a worn item out of its paperdoll slot bypasses
-- ISUnequipAction entirely (confirmed against vanilla ISTransferAction source),
-- so clearing must not depend on that hook alone.

local T = require "runner"
local H = require "harness.init"

local CLEARED = 0.42

-- Forces redPhase so getMoodleType() picks "Bloody" (distinguishable from the
-- 0.42 cleared sentinel), and disables the first-cycle delay so the generated
-- cycle actually starts there.
local function redPhaseWorld()
    local w = H.newWorld({ sandbox = { phase_start_delay_enabled = false } })
    w.cycle().current_phase = "redPhase"
    return w
end

local function wearPantyLiner(w, condition)
    local item = w.t.newItem({
        type = "Panty_Liner", condition = condition or 1, bodyLocation = "RedDays:HygieneItem",
    })
    w.t.player.worn:add(item, "RedDays:HygieneItem")
    return item
end

local function bloodyPantyLinerValue(w)
    return w.t.mf.values["BloodyPantyLiner"]
end

T.describe("RD_moodles hygiene moodle clearing", function()

    T.it("sets the moodle from item condition while worn during red phase", function()
        local w = redPhaseWorld()
        wearPantyLiner(w, 1)                 -- condition 1 -> getMoodleLevel() = 0
        w.env.RD_moodles.mainLoop()
        T.eq(bloodyPantyLinerValue(w), 0)
    end)

    T.it("REGRESSION: clears when unequipped via a path that bypasses ISUnequipAction", function()
        -- Reproduces the reported bug: vanilla's drag-and-drop unequip calls
        -- ISTransferAction:removeItemOnCharacter(), which removes the worn item
        -- and fires OnClothingUpdated WITHOUT ever constructing ISUnequipAction.
        local w = redPhaseWorld()
        local item = wearPantyLiner(w, 1)
        w.env.RD_moodles.mainLoop()
        T.eq(bloodyPantyLinerValue(w), 0, "sanity: moodle should be set before removal")

        w.t.player.worn:remove(item)                          -- the item is gone...
        w.t.events.fire("OnClothingUpdated", w.t.player)      -- ...and vanilla fires this

        T.eq(bloodyPantyLinerValue(w), CLEARED,
             "OnClothingUpdated must clear the moodle even without ISUnequipAction firing")
    end)

    T.it("still clears instantly via the original ISUnequipAction hook (unregressed)", function()
        local w = redPhaseWorld()
        local item = wearPantyLiner(w, 1)
        w.env.RD_moodles.mainLoop()
        T.eq(bloodyPantyLinerValue(w), 0)

        w.env.ISUnequipAction.perform(w.t.actions.instance("ISUnequipAction", item))

        T.eq(bloodyPantyLinerValue(w), CLEARED)
    end)

    T.it("does not clear when an unrelated garment changes while the item stays worn", function()
        local w = redPhaseWorld()
        wearPantyLiner(w, 1)
        w.env.RD_moodles.mainLoop()
        T.eq(bloodyPantyLinerValue(w), 0)

        local shirt = w.t.newItem({ type = "Tshirt", bodyLocation = "Shirt" })
        w.t.player.worn:add(shirt, "Shirt")
        w.t.player.worn:remove(shirt)
        w.t.events.fire("OnClothingUpdated", w.t.player)

        T.eq(bloodyPantyLinerValue(w), 0,
             "removing unrelated clothing must not touch the hygiene moodle")
    end)

    T.it("self-heals inside mainLoop within one minute for an unhooked removal path", function()
        -- Even if OnClothingUpdated were somehow never fired, mainLoop's own
        -- fallback must catch a "nothing worn, moodle not confirmed cleared" state.
        local w = redPhaseWorld()
        local item = wearPantyLiner(w, 1)
        w.env.RD_moodles.mainLoop()
        T.eq(bloodyPantyLinerValue(w), 0)

        w.t.player.worn:remove(item)          -- removed with no event at all
        w.env.RD_moodles.mainLoop()           -- one in-game minute passes

        T.eq(bloodyPantyLinerValue(w), CLEARED)
        T.truthy(w.icdata().hygieneMoodlesCleared)
    end)

    T.it("does not repeatedly call resetMoodles once the latch is set", function()
        local w = redPhaseWorld()
        local item = wearPantyLiner(w, 1)
        w.env.RD_moodles.mainLoop()
        w.t.player.worn:remove(item)
        w.env.RD_moodles.mainLoop()

        w.t.mf.reset()                        -- clear the recorded call log, keep values
        w.env.RD_moodles.mainLoop()           -- a further minute with nothing worn

        -- mainLoop() always touches Leak and TSSInfection regardless of hygiene state;
        -- what must NOT happen is a further resetMoodles() sweep of the 6 hygiene moodles.
        T.eq(#w.t.mf.setCalls, 2,
             "expected only the Leak and TSSInfection updates, not another resetMoodles() "
             .. "sweep of all 6 hygiene moodles")
        for _, call in ipairs(w.t.mf.setCalls) do
            T.truthy(call.moodle == "Leak" or call.moodle == "TSSInfection",
                     "unexpected moodle write on a steady-state tick: " .. tostring(call.moodle))
        end
    end)

    T.it("re-arms the latch once a new item is worn", function()
        local w = redPhaseWorld()
        local first = wearPantyLiner(w, 1)
        w.env.RD_moodles.mainLoop()
        w.t.player.worn:remove(first)
        w.env.RD_moodles.mainLoop()
        T.truthy(w.icdata().hygieneMoodlesCleared)

        wearPantyLiner(w, 1)
        w.env.RD_moodles.mainLoop()

        T.falsy(w.icdata().hygieneMoodlesCleared, "latch should re-arm while something is worn")
        T.eq(bloodyPantyLinerValue(w), 0, "and the moodle should reflect the new item")
    end)

end)
