-- client/RD_selftest.lua + the rdTest* server commands: the in-game SP/MP self-test.
--
-- These run the REAL self-test end to end against the harness, in single player and in a
-- client/server pair, so a broken check fails here rather than confusing an in-game run.

local T = require "runner"
local H = require "harness.init"
local MP = require "harness.mp"

local HYGIENE = "RedDays:HygieneItem"

-- Drives real time (OnTick) and game time until `marker` appears in the log.
-- ~1 game minute per 2.5 real seconds, like the default day length in game.
local function drive(world, marker, onTick)
    for i = 1, 2000 do
        world.t.tick(250)
        if i % 10 == 0 then world.advanceMinutes(1) end
        if onTick then onTick(world.t.log()) end
        if string.find(world.t.log(), marker, 1, true) then return true end
    end
    return false
end

local function lines(world, kind)
    local out = {}
    for line in string.gmatch(world.t.log(), "[^\n]+") do
        if string.find(line, "[RD-TEST] " .. kind .. " ", 1, true) then out[#out + 1] = line end
    end
    return out
end

local function hasLine(world, kind, id)
    for _, line in ipairs(lines(world, kind)) do
        if string.find(line, "[RD-TEST] " .. kind .. " " .. id .. " ", 1, true) then return true end
    end
    return false
end

local function assertNoFailures(world)
    local failures = lines(world, "FAIL")
    T.eq(#failures, 0, "self-test reported failures:\n" .. table.concat(failures, "\n"))
end

-- Plays the player's part in rd.mptest.actions(): does whatever the latest instruction asks,
-- the way the engine would run it (SP runs both perform() and complete() locally -- the
-- in-game trace shows perform() entered first; an MP client only sees perform()).
local function actingPlayer(world, isMPClient)
    local done = {}
    local later = {}  -- actions the player does a few ticks after the cue, like a real pause
    local env = world.env
    local tampon = nil
    local function act(className, item)
        local action = world.t.actions.instance(className, item)
        env[className].perform(action)
        if not isMPClient then env[className].complete(action) end
    end
    local steps = {
        { cue = "Take one Painkillers", run = function()
            act("ISTakePillAction", world.t.newItem({ type = "Pills", fullType = "Base.Pills" }))
        end },
        { cue = "Eat one Antibiotics", run = function()
            act("ISEatFoodAction", world.t.newItem({ type = "Antibiotics", fullType = "Base.Antibiotics", isFood = true }))
        end },
        { cue = "Eat some Cheese", run = function()
            act("ISEatFoodAction", world.t.newItem({ type = "Cheese", fullType = "Base.Cheese", isFood = true }))
        end },
        { cue = "Drink the whole Milk carton", run = function()
            local milk = world.t.newItem({ type = "Milk", fullType = "Base.Milk" })
            if isMPClient then
                -- REGRESSION: what a hosted game did with a whole carton -- the server empties it
                -- first, so the client's action ends through stop(), never perform().
                env.ISDrinkFluidAction.stop(world.t.actions.instance("ISDrinkFluidAction", milk,
                    { fluidContainer = world.t.actions.fluidContainer(true) }))
            else
                act("ISDrinkFluidAction", milk)
            end
        end },
        { cue = "Wear the Tampon", run = function()
            -- REGRESSION: exactly what the player did in game -- wear, take off, then a pause of
            -- several seconds before wearing it again. The check used to finish during that
            -- pause and report nothing worn.
            tampon = world.t.newItem({ type = "Tampon", bodyLocation = HYGIENE })
            world.t.player.worn:add(tampon, HYGIENE)
            act("ISWearClothing", tampon)
            world.t.player.worn:remove(tampon)
            act("ISUnequipAction", tampon)
            later[#later + 1] = { ticks = 20, run = function()
                world.t.player.worn:add(tampon, HYGIENE)
                act("ISWearClothing", tampon)
            end }
        end },
        { cue = "Eat one more Antibiotics", run = function()
            act("ISEatFoodAction", world.t.newItem({ type = "Antibiotics", fullType = "Base.Antibiotics", isFood = true }))
        end },
    }
    return function(log)
        for i = #later, 1, -1 do
            later[i].ticks = later[i].ticks - 1
            if later[i].ticks <= 0 then
                local run = later[i].run
                table.remove(later, i)
                run()
            end
        end
        for _, step in ipairs(steps) do
            if not done[step.cue] and string.find(log, "ACTION NEEDED ---- " .. step.cue, 1, true) then
                done[step.cue] = true
                step.run()
            end
        end
    end
end

T.describe("self-test gating", function()

    T.it("is not loaded when RD_Config.selftest is off", function()
        local w = H.newWorld({ load = "both" })
        T.isNil(w.env.RD_SelfTest)
        T.isNil(w.env.RD_DebugAPI.mptest)
        w.env.sendClientCommand(w.t.player, "RedDays", "rdTestProbe", { nonce = "x" })
        T.eq(#w.t.serverCommands, 0, "no rdTest* handler may exist with the flag off")
    end)

    T.it("REGRESSION: a missing RD_Config never breaks loading, client or server", function()
        -- Reported crash: PZ keeps the mod file list it scanned at launch, so a newly added
        -- shared/RD_config.lua is not loaded until a full restart. The server's
        -- require "RD_config" then fails, RD_Config is nil, and indexing it killed
        -- RD_server_commands.lua before OnClientCommand was registered -- breaking ALL MP sync.
        for _, side in ipairs({ "client", "server" }) do
            local w = H.newWorld({ load = "none", isServer = side == "server" })
            w.env.RD_Config = nil
            w.env.__loaded.RD_config = true  -- require "RD_config" yields nothing, like the failed require

            local load = side == "client" and w.loader.loadClient or w.loader.loadServer
            local ok, err = pcall(load, w.env)

            T.truthy(ok, side .. " must load without RD_Config, got: " .. tostring(err))
            T.isNil(w.env.RD_SelfTest, "the self-test stays off when the flag can't be read")
            if side == "server" then
                T.truthy(#w.t.events.handlersFor("OnClientCommand") > 0,
                    "the sync command handler must still register")
            end
        end
    end)

    T.it("MP: refuses a player who is neither admin nor in debug mode", function()
        local pair = MP.newPair({ selftest = true })
        pair.client.env.rd.mptest.run()
        T.truthy(drive(pair.client, "DONE run"), "run() never finished")

        T.truthy(hasLine(pair.client, "FAIL", "probe"), "the probe must go unanswered")
        T.eq(#pair.bus.toClient, 0)
        T.contains(pair.server.t.log(), "rdTestProbe refused")
    end)

end)

T.describe("rd.mptest.run()", function()

    T.it("SP: completes with no failures", function()
        local w = H.newWorld({ selftest = true, load = "both" })
        w.env.rd.mptest.run()
        T.truthy(drive(w, "DONE run"), "run() never finished")

        assertNoFailures(w)
        T.contains(w.t.log(), "BEGIN run mode=sp")
        for _, id in ipairs({ "env", "probe", "moddata", "stat", "hp", "stiff", "tss", "pms", "stains" }) do
            T.truthy(hasLine(w, "PASS", id), "expected PASS " .. id)
        end
        T.truthy(hasLine(w, "SKIP", "item"), "no hygiene item is worn, so item is skipped")
        T.truthy(hasLine(w, "SKIP", "wear"), "and so is wear-down")
    end)

    T.it("MP: completes with no failures for an admin", function()
        local pair = MP.newPair({ selftest = true })
        pair.makeServerAdmin()
        pair.client.env.rd.mptest.run()
        T.truthy(drive(pair.client, "DONE run"), "run() never finished")

        assertNoFailures(pair.client)
        T.contains(pair.client.t.log(), "BEGIN run mode=mp")
        for _, id in ipairs({ "env", "probe", "moddata", "stat", "hp", "stiff", "tss", "pms" }) do
            T.truthy(hasLine(pair.client, "PASS", id), "expected PASS " .. id)
        end
        T.truthy(hasLine(pair.client, "INFO", "stat"), "reports which side owns a direct stat set")
        -- REGRESSION: the hosted game reported "body stains LOST on the server"; applyStains now
        -- carries them. No garment is worn here, so clothing is reported as not covered.
        T.contains(pair.client.t.log(), "PASS stains body stains reached the server")
        T.contains(pair.client.t.log(), "INFO stains no garment over the groin")
    end)

    T.it("REGRESSION: MP tss passes while PMS sadness pulls unhappiness down", function()
        -- Seen in a hosted game: "sends=3 client rise=-0.700 server rise=-0.700". TSS synced
        -- perfectly, but PMS sadness (now also synced) moved unhappiness down faster than TSS's
        -- +0.1/min raised it, and the check demanded a rise.
        local pair = MP.newPair({ selftest = true })
        pair.makeServerAdmin()
        local cycle = pair.client.cycle()
        cycle.current_phase = "lutealPhase"
        cycle.pms_duration_mins = 7 * 1440
        cycle.phase_minutes_remaining = 600
        cycle.healthEffectSeverity = 10  -- a low sadness target, below the seeded unhappiness
        for _, key in ipairs({ "pms_agitation", "pms_cramps", "pms_fatigue", "pms_tenderBreasts", "pms_craveFood" }) do
            cycle[key] = false
        end
        cycle.pms_Sadness = true
        for _, side in ipairs({ pair.client, pair.server }) do
            side.t.player.stats:__seed(side.env.CharacterStat.UNHAPPINESS, 50)
        end

        pair.client.env.rd.mptest.run()
        T.truthy(drive(pair.client, "DONE run"), "run() never finished")

        T.truthy(hasLine(pair.client, "PASS", "tss"), pair.client.t.log())
    end)

    T.it("MP: covers item and clothing-stain sync when a hygiene item and pants are worn", function()
        local pair = MP.newPair({ selftest = true, debug = true })
        pair.giveItem({ condition = 7 })
        for _, side in ipairs({ pair.client, pair.server }) do
            local pants = side.t.newItem({
                type = "Trousers", id = 9002, isClothing = true,
                bloodClothingType = side.env.BloodClothingType.Trousers,
            })
            side.t.player.worn:add(pants, "Pants")
        end
        pair.client.env.rd.mptest.run()
        T.truthy(drive(pair.client, "DONE run"), "run() never finished")

        assertNoFailures(pair.client)
        T.contains(pair.client.t.log(), "PASS stains clothing stains reached the server")
        T.truthy(hasLine(pair.client, "PASS", "item"), pair.client.t.log())
        T.truthy(hasLine(pair.client, "PASS", "wear"), "red-phase wear-down reaches the server")
        T.eq(pair.serverPlayer.worn:get(0).item:getCondition(), 7, "the check restores the item")
    end)

    T.it("restores the TSS state and stats it changed", function()
        local w = H.newWorld({ selftest = true, load = "both" })
        local CharacterStat = w.env.CharacterStat
        w.t.player.stats:__seed(CharacterStat.FATIGUE, 0.25)
        local stageBefore = w.icdata().tss.stage
        local phaseBefore = w.cycle().current_phase
        local leakBefore = w.icdata().LeakLevel

        w.env.rd.mptest.run()
        T.truthy(drive(w, "DONE run"))

        T.eq(w.icdata().tss.stage, stageBefore)
        T.eq(w.cycle().current_phase, phaseBefore, "the PMS check restores the cycle")
        T.eq(w.icdata().LeakLevel, leakBefore, "the stain check restores the leak level")
        T.near(w.t.player.stats:get(CharacterStat.FATIGUE), 0.25, 1e-9)
    end)

    T.it("counts the mod's sync traffic only during a run", function()
        local pair = MP.newPair({ selftest = true, debug = true })
        local original = pair.client.env.sendClientCommand
        pair.client.env.rd.mptest.run()
        T.truthy(pair.client.env.sendClientCommand ~= original, "the counter is installed for the run")
        T.truthy(drive(pair.client, "DONE run"))
        T.truthy(pair.client.env.sendClientCommand == original, "and removed afterwards")
    end)

end)

T.describe("rd.mptest.actions()", function()

    T.it("SP: passes when the player does each step, counting effects once", function()
        local w = H.newWorld({ selftest = true, load = "both" })
        w.env.rd.mptest.actions()
        T.truthy(drive(w, "DONE actions", actingPlayer(w, false)), "actions() never finished")

        assertNoFailures(w)
        for _, id in ipairs({ "pill", "abx", "cheese", "milk", "hygiene", "abx4" }) do
            T.truthy(hasLine(w, "PASS", id), "expected PASS " .. id)
        end
        T.contains(w.t.log(), "local perform x1 complete x1")
        T.falsy(string.find(w.t.log(), "bandage", 1, true), "no bandage prompt: periods never injure the player")
        T.truthy(w.t.player.inventory:size() >= 6, "rdTestGiveItems adds the test items")
        T.eq(w.icdata().tss.stage, 0, "the toxic-shock check restores TSS")
    end)

    T.it("MP: passes on a client that only sees perform()", function()
        local pair = MP.newPair({ selftest = true })
        pair.makeServerAdmin()
        pair.client.env.rd.mptest.actions()
        T.truthy(drive(pair.client, "DONE actions", actingPlayer(pair.client, true)), "actions() never finished")

        assertNoFailures(pair.client)
        for _, id in ipairs({ "pill", "abx", "cheese", "milk", "hygiene", "abx4" }) do
            T.truthy(hasLine(pair.client, "PASS", id), "expected PASS " .. id)
        end
        T.contains(pair.client.t.log(), "client perform x1 complete x0")
        T.contains(pair.client.t.log(), "PASS milk drink credit registered once ---- pct=18 client perform x0 complete x0 stop x1",
            "a whole carton ends through stop() and still counts")
        T.eq(#pair.server.t.addedToContainer, 6, "items are synced to the client with sendAddItemToContainer")
    end)

    T.it("reports a timeout instead of hanging when the player does nothing", function()
        local w = H.newWorld({ selftest = true, load = "both" })
        w.env.rd.mptest.actions()
        T.truthy(drive(w, "FAIL pill"), "a missed step must time out")
    end)

end)

T.describe("rd.mptest.persistSave() / persistCheck()", function()

    local PERSIST_FILE = "RD_selftest_persist.txt"

    T.it("SP: a snapshot matches after in-game time passes", function()
        local w = H.newWorld({ selftest = true, load = "both" })
        w.env.rd.mptest.persistSave()
        T.contains(w.t.files[PERSIST_FILE], "journalID=")
        w.advanceMinutes(30)

        w.env.rd.mptest.persistCheck()
        T.truthy(drive(w, "DONE persist"))

        assertNoFailures(w)
        T.truthy(#lines(w, "PASS") >= 5, w.t.log())
        T.contains(w.t.log(), "cycle countdown survived the reload")
        T.eq(w.t.files[PERSIST_FILE], "", "the snapshot is cleared after the check")
    end)

    T.it("reports a value that changed across the reload", function()
        local w = H.newWorld({ selftest = true, load = "both" })
        w.env.rd.mptest.persistSave()
        w.icdata().tss.stage = 3

        w.env.rd.mptest.persistCheck()
        T.truthy(drive(w, "DONE persist"))

        T.contains(w.t.log(), "FAIL persist TSS stage changed across the reload")
    end)

    T.it("fails clearly when there is no snapshot", function()
        local w = H.newWorld({ selftest = true, load = "both" })
        w.env.rd.mptest.persistCheck()
        T.truthy(drive(w, "DONE persist"))
        T.contains(w.t.log(), "FAIL persist no snapshot found")
    end)

    T.it("MP: also compares the server copy", function()
        local pair = MP.newPair({ selftest = true })
        pair.makeServerAdmin()
        pair.client.env.rd.mptest.persistSave()
        pair.client.advanceMinutes(30)

        pair.client.env.rd.mptest.persistCheck()
        T.truthy(drive(pair.client, "DONE persist"))

        assertNoFailures(pair.client)
        T.contains(pair.client.t.log(), "persist the server")
    end)

end)
