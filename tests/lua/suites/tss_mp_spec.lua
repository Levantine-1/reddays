-- TSS in multiplayer.
--
-- TSS used to be force-disabled on MP clients because antibiotic doses never registered
-- there. Root cause: the dose hook sat on ISEatFoodAction:complete(), which in B42 MP runs
-- only on the server -- and the server never loads client/ Lua. These tests pin the fix:
-- the hook lives on perform(), and the TSS tick runs (and syncs) on an MP client.

local T = require "runner"
local H = require "harness.init"
local MP = require "harness.mp"

local function antibiotics(w)
    return w.t.newItem({ type = "Antibiotics", fullType = "Base.Antibiotics", isFood = true })
end

T.describe("TSS on a multiplayer client", function()

    T.it("REGRESSION: eating antibiotics registers a dose on an MP client", function()
        local w = H.newWorld({ isClient = true })
        w.icdata().tss.stage = 1

        w.env.ISEatFoodAction.perform(w.t.actions.instance("ISEatFoodAction", antibiotics(w)))

        local tss = w.icdata().tss
        T.eq(tss.abx_dose_count, 1, "the dose must register client-side in MP")
        T.truthy((tss.abx_bank_points or 0) > 0, "and fill the antibiotic bank")
        T.eq(w.t.actions.originalCalls.ISEatFoodAction, 1, "vanilla perform() still runs")
    end)

    T.it("the TSS tick runs on an MP client and its stat changes reach the server", function()
        local pair = MP.newPair()
        local CharacterStat = pair.client.env.CharacterStat
        pair.client.icdata().tss.stage = 2

        pair.client.advanceMinutes(3)

        T.truthy(#pair.commandsNamed("applyTSSStats") >= 1,
            "an MP client must flush its TSS stat changes to the server")
        local clientUnhappy = pair.clientPlayer.stats:get(CharacterStat.UNHAPPINESS)
        T.truthy(clientUnhappy > 0, "stage 2 raises unhappiness on the client")
        T.near(pair.serverPlayer.stats:get(pair.server.env.CharacterStat.UNHAPPINESS), clientUnhappy,
            1e-9, "the server's copy must converge to the client's value")
    end)

end)

T.describe("TSS dose registration in single player", function()

    T.it("registers exactly once when the engine runs both perform() and complete()", function()
        -- In SP the engine runs both locally (the in-game trace shows perform() entered first).
        -- Only perform() is hooked, so a dose must not count twice.
        local w = H.newWorld({ isClient = false })
        w.icdata().tss.stage = 1
        local action = w.t.actions.instance("ISEatFoodAction", antibiotics(w))

        w.env.ISEatFoodAction.perform(action)
        w.env.ISEatFoodAction.complete(action)

        T.eq(w.icdata().tss.abx_dose_count, 1)
        T.eq(#w.t.sentCommands, 0, "single player must not emit network traffic")
    end)

end)
