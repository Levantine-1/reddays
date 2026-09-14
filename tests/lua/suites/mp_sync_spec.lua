-- Client <-> server synchronisation.
--
-- Runs a real client environment and a real server environment side by side and
-- routes commands between them, so the wire contract is exercised without a
-- dedicated server or a second login.

local T = require "runner"
local H = require "harness.init"
local MP = require "harness.mp"

T.describe("MP protocol contract", function()

    T.it("every command the client sends has a server handler", function()
        local clientCommands, sources = MP.clientCommands()
        local serverCommands = MP.serverCommands()

        local implemented = {}
        for _, name in ipairs(serverCommands) do implemented[name] = true end

        T.truthy(#clientCommands > 0, "expected to find sendClientCommand call sites")
        for _, command in ipairs(clientCommands) do
            T.truthy(implemented[command],
                "client sends '" .. command .. "' (from " .. tostring(sources[command])
                .. ") but RD_server_commands.lua implements no Commands." .. command
                .. " -- unknown commands are dropped silently in game")
        end
    end)

    T.it("the server implements no command the client never sends", function()
        local clientCommands = MP.clientCommands()
        local sent = {}
        for _, name in ipairs(clientCommands) do sent[name] = true end

        for _, command in ipairs(MP.serverCommands()) do
            T.truthy(sent[command],
                "Commands." .. command .. " exists on the server but nothing sends it"
                .. " -- either dead code or a renamed client call site")
        end
    end)

    T.it("pins the exact set of hpMode values crossing the wire", function()
        -- The server's final `else` is a deliberate catch-all for the two
        -- no-antibiotics modes, which can legitimately be lethal. Any mode NOT in
        -- this list silently inherits that lethal branch, so the set is pinned
        -- here: adding a mode must be a conscious decision, not an accident.
        local expectedEmitted = {
            abx_cap_sickness_drain = true,   -- ABX: drain toward the cap, then floor
            abx_flat_drain = true,           -- ABX: awake trickle, floored at the cap
            abx_sleep_regen = true,          -- ABX: asleep, regen up to the cap
            stage4_sickness_drain = true,    -- no ABX, awake -- may be lethal
            stage4_sleep_drain = true,       -- no ABX, asleep -- may be lethal
        }
        local emitted, handled = MP.hpModes()

        for mode in pairs(emitted) do
            T.truthy(expectedEmitted[mode],
                "RD_tss_manager.lua emits a new hpMode '" .. mode .. "'. The server's"
                .. " catch-all else would treat it as an unconditional lethal drain,"
                .. " ignoring hpCap. Add an explicit branch in Commands.applyTSSStats"
                .. " (or add it here deliberately).")
        end
        for mode in pairs(expectedEmitted) do
            T.truthy(emitted[mode], "expected hpMode '" .. mode .. "' is no longer emitted")
        end

        -- Every antibiotic-protected mode must be matched explicitly, because the
        -- catch-all ignores hpCap and would kill a player the ABX should protect.
        for _, mode in ipairs({ "abx_cap_sickness_drain", "abx_flat_drain", "abx_sleep_regen" }) do
            T.truthy(handled[mode],
                "hpMode '" .. mode .. "' protects the player via hpCap but the server"
                .. " does not match it explicitly -- it would fall through to the"
                .. " lethal drain branch")
        end
    end)

end)

T.describe("Commands.updateSanitaryItem", function()

    T.it("applies condition and name to the server's copy of the item", function()
        local pair = MP.newPair()
        local clientItem, serverItem = pair.giveItem({ condition = 10 })

        pair.send("updateSanitaryItem", {
            itemId = clientItem:getID(),
            newCondition = 4,
            newName = "Tampon (Dirty)",
        })

        T.eq(serverItem:getCondition(), 4)
        T.eq(serverItem:getName(), "Tampon (Dirty)")
    end)

    T.it("broadcasts the change with syncItemFields", function()
        local pair = MP.newPair()
        local clientItem = pair.giveItem({ condition = 10 })
        pair.send("updateSanitaryItem", { itemId = clientItem:getID(), newCondition = 6 })

        local synced = pair.server.t.syncedItems
        T.eq(#synced, 1, "the server should re-broadcast the item to all clients")
        T.eq(synced[1].item:getID(), clientItem:getID())
    end)

    T.it("finds an item held in top-level inventory, not just worn", function()
        local pair = MP.newPair()
        local clientItem, serverItem = pair.giveItem({ where = "inventory", condition = 9 })
        pair.send("updateSanitaryItem", { itemId = clientItem:getID(), newCondition = 2 })
        T.eq(serverItem:getCondition(), 2)
    end)

    T.it("leaves the client's change unreplicated for an item inside a bag", function()
        -- Documents a real limitation: the server scans worn items and top-level
        -- inventory only, so an item in a backpack is never found.
        local pair = MP.newPair()
        local clientItem, serverItem = pair.giveItem({ where = "backpack", condition = 10 })

        pair.send("updateSanitaryItem", { itemId = clientItem:getID(), newCondition = 3 })

        T.eq(serverItem:getCondition(), 10, "the nested item is not reached")
        T.eq(#pair.server.t.syncedItems, 0)
        T.contains(pair.server.t.log(), "Could not find item with ID")
    end)

    T.it("ignores a payload with no item id", function()
        local pair = MP.newPair()
        local _, serverItem = pair.giveItem({ condition = 8 })
        pair.send("updateSanitaryItem", { newCondition = 1 })
        T.eq(serverItem:getCondition(), 8)
    end)

    T.it("applies condition without a name, and a name without a condition", function()
        local pair = MP.newPair()
        local clientItem, serverItem = pair.giveItem({ condition = 10, name = "Tampon" })

        pair.send("updateSanitaryItem", { itemId = clientItem:getID(), newCondition = 5 })
        T.eq(serverItem:getCondition(), 5)
        T.eq(serverItem:getName(), "Tampon", "name should be untouched")

        pair.send("updateSanitaryItem", { itemId = clientItem:getID(), newName = "Tampon (Dirty)" })
        T.eq(serverItem:getCondition(), 5, "condition should be untouched")
        T.eq(serverItem:getName(), "Tampon (Dirty)")
    end)

end)

T.describe("Commands.applyBodyStiffness", function()

    local function groin(pair)
        return pair.serverPlayer.bodyDamage:getBodyPart(pair.server.env.BodyPartType.Groin)
    end
    local function lowerTorso(pair)
        return pair.serverPlayer.bodyDamage:getBodyPart(pair.server.env.BodyPartType.Torso_Lower)
    end
    local function upperTorso(pair)
        return pair.serverPlayer.bodyDamage:getBodyPart(pair.server.env.BodyPartType.Torso_Upper)
    end

    T.it("sets stiffness on each supplied body part", function()
        local pair = MP.newPair()
        pair.send("applyBodyStiffness", { Torso_Lower = 40, Groin = 30, Torso_Upper = 20 })
        T.eq(lowerTorso(pair).stiffness, 40)
        T.eq(groin(pair).stiffness, 30)
        T.eq(upperTorso(pair).stiffness, 20)
    end)

    T.it("accepts a sparse payload and leaves the others alone", function()
        local pair = MP.newPair()
        pair.send("applyBodyStiffness", { Torso_Upper = 55 })
        T.eq(upperTorso(pair).stiffness, 55)
        T.eq(groin(pair).stiffness, 0)
        T.eq(lowerTorso(pair).stiffness, 0)
    end)

    T.it("clamps values into 0-100", function()
        local pair = MP.newPair()
        pair.send("applyBodyStiffness", { Groin = 500, Torso_Lower = -20 })
        T.eq(groin(pair).stiffness, 100)
        T.eq(lowerTorso(pair).stiffness, 0)
    end)

    T.it("skips non-numeric values rather than erroring", function()
        local pair = MP.newPair()
        pair.send("applyBodyStiffness", { Groin = "lots", Torso_Lower = 15 })
        T.eq(groin(pair).stiffness, 0, "a bad value is dropped")
        T.eq(lowerTorso(pair).stiffness, 15, "and does not stop the rest")
    end)

    T.it("reads every body part the client puts on the wire", function()
        -- If a fourth body part is ever added client-side, the server's explicit
        -- ladder would silently drop it. This catches that.
        local pair = MP.newPair()
        local record = pair.send("applyBodyStiffness",
            { Torso_Lower = 10, Groin = 10, Torso_Upper = 10 })
        T.eq(record.unread, {}, "server ignored fields the client sent: "
            .. table.concat(record.unread, ", "))
    end)

end)

T.describe("Commands.applyTSSStats", function()

    T.it("sets absolute stats and adds temperature as a delta", function()
        local pair = MP.newPair()
        local stats = pair.serverPlayer.stats
        local CharacterStat = pair.server.env.CharacterStat

        stats:__seed(CharacterStat.TEMPERATURE, 0.5)
        pair.send("applyTSSStats", {
            sickness = 0.4, endurance = 0.6, fatigue = 0.3,
            thirst = 0.2, unhappiness = 0.7, temperatureAdd = 0.05,
        })

        T.near(stats:get(CharacterStat.SICKNESS), 0.4)
        T.near(stats:get(CharacterStat.ENDURANCE), 0.6)
        T.near(stats:get(CharacterStat.FATIGUE), 0.3)
        T.near(stats:get(CharacterStat.THIRST), 0.2)
        T.near(stats:get(CharacterStat.UNHAPPINESS), 0.7)
        T.near(stats:get(CharacterStat.TEMPERATURE), 0.55,
               1e-9, "temperature must accumulate, not overwrite")
    end)

    T.it("keeps temperature deltas commutative across repeated sends", function()
        local pair = MP.newPair()
        local CharacterStat = pair.server.env.CharacterStat
        pair.serverPlayer.stats:__seed(CharacterStat.TEMPERATURE, 0)
        for _ = 1, 4 do
            pair.send("applyTSSStats", { temperatureAdd = 0.01 })
        end
        T.near(pair.serverPlayer.stats:get(CharacterStat.TEMPERATURE), 0.04, 1e-9)
    end)

    T.it("floors health at the cap for every antibiotic-protected mode", function()
        for _, mode in ipairs({ "abx_cap_sickness_drain", "abx_flat_drain" }) do
            local pair = MP.newPair()
            local bd = pair.serverPlayer.bodyDamage
            bd.health = 30
            pair.send("applyTSSStats", { hpMode = mode, hpDrain = 25, hpCap = 20 })
            T.eq(bd.health, 20,
                 mode .. " must not take health below the antibiotic cap")
        end
    end)

    T.it("regenerates toward the cap while asleep on antibiotics", function()
        local pair = MP.newPair()
        local bd = pair.serverPlayer.bodyDamage
        bd.health = 10
        pair.send("applyTSSStats", { hpMode = "abx_sleep_regen", hpDrain = 3, hpCap = 20 })
        T.eq(bd.health, 13)
    end)

    T.it("does not regenerate past the cap", function()
        local pair = MP.newPair()
        local bd = pair.serverPlayer.bodyDamage
        bd.health = 19
        pair.send("applyTSSStats", { hpMode = "abx_sleep_regen", hpDrain = 10, hpCap = 20 })
        T.eq(bd.health, 20)
    end)

    T.it("allows an unprotected stage-4 drain to be lethal", function()
        for _, mode in ipairs({ "stage4_sickness_drain", "stage4_sleep_drain" }) do
            local pair = MP.newPair()
            local bd = pair.serverPlayer.bodyDamage
            bd.health = 5
            pair.send("applyTSSStats", { hpMode = mode, hpDrain = 25, hpCap = 20 })
            T.eq(bd.health, 0, mode .. " has no antibiotic floor and may kill")
        end
    end)

    T.it("applies the blur effect", function()
        local pair = MP.newPair()
        pair.send("applyTSSStats", { blur = 0.35 })
        T.eq(pair.serverPlayer.sleepingTabletEffect, 0.35)
    end)

    T.it("reads every field the client puts on the wire", function()
        local pair = MP.newPair()
        local record = pair.send("applyTSSStats", {
            sickness = 0.1, endurance = 0.1, fatigue = 0.1, thirst = 0.1,
            unhappiness = 0.1, temperatureAdd = 0.01, blur = 0.1,
            hpMode = "abx_flat_drain", hpDrain = 1, hpCap = 20,
        })
        T.eq(record.unread, {},
            "the server never reads these fields the client sent: "
            .. table.concat(record.unread, ", "))
    end)

    T.it("flags a field the server has no branch for", function()
        -- Proves the drift detector actually detects: `stiffness` is not part of
        -- this command's contract, so it must be reported as unread.
        local pair = MP.newPair()
        local record = pair.send("applyTSSStats", { sickness = 0.2, stiffness = 99 })
        T.eq(record.unread, { "stiffness" })
    end)

end)

T.describe("wire serialisation", function()

    T.it("delivers a copy, so the server cannot mutate the client's table", function()
        local pair = MP.newPair()
        local payload = { Torso_Lower = 10, Groin = 10 }
        local record = pair.send("applyBodyStiffness", payload)
        T.neq(record.payload, payload == nil and 1 or record.payload == payload and payload or {},
              nil)
        T.falsy(rawequal(record.payload, payload),
                "the payload must be copied across the wire, not shared by reference")
    end)

    T.it("drops commands addressed to another mod's module", function()
        local pair = MP.newPair()
        local _, serverItem = pair.giveItem({ condition = 7 })
        pair.client.env.sendClientCommand(pair.clientPlayer, "SomeOtherMod",
                                          "updateSanitaryItem",
                                          { itemId = serverItem:getID(), newCondition = 1 })
        T.eq(serverItem:getCondition(), 7, "another mod's traffic must be ignored")
    end)

    T.it("ignores an unknown command name without erroring", function()
        local pair = MP.newPair()
        pair.send("noSuchCommand", { whatever = 1 })
        T.truthy(true, "delivery completed without raising")
    end)

end)

T.describe("client-side MP behaviour", function()

    T.it("sends an item update when hygiene condition changes on a client", function()
        local pair = MP.newPair({ sandbox = { spawn_with_hygiene_products = false } })
        local clientItem, serverItem = pair.giveItem({ condition = 10 })

        pair.client.env.RD_HygieneManager.debugSetCondition(6)

        local record = pair.lastCommand("updateSanitaryItem")
        T.notNil(record, "a client should push item changes to the server")
        T.eq(record.payload.itemId, clientItem:getID())
        T.eq(record.payload.newCondition, 6)
        T.eq(serverItem:getCondition(), 6, "and the server should apply them")
    end)

    T.it("does not send item updates in single player", function()
        local w = H.newWorld({ isClient = false })
        local item = w.t.newItem({ type = "Tampon", bodyLocation = "RedDays:HygieneItem" })
        w.t.player.worn:add(item, "RedDays:HygieneItem")

        w.env.RD_HygieneManager.debugSetCondition(6)

        T.eq(#w.t.sentCommands, 0, "single player must not emit network traffic")
        T.eq(item:getCondition(), 6, "but the local change still applies")
    end)

end)
