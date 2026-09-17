-- RD_hygiene_manager.lua and the red-phase wiring in RD_effects_manager.lua.

local T = require "runner"
local H = require "harness.init"
local MP = require "harness.mp"

local HYGIENE = "RedDays:HygieneItem"

local function merge(a, b)
    local out = {}
    for k, v in pairs(a or {}) do out[k] = v end
    for k, v in pairs(b or {}) do out[k] = v end
    return out
end

local function world(sandbox)
    return H.newWorld({ sandbox = merge({ phase_start_delay_enabled = false }, sandbox) })
end

local function wear(w, typeName, opts)
    opts = opts or {}
    local item = w.t.newItem({
        type = typeName, bodyLocation = HYGIENE, condition = opts.condition, name = opts.name,
    })
    w.t.player.worn:add(item, HYGIENE)
    return item
end

local function wearClothing(w, typeName, clothingType, location)
    local item = w.t.newItem({
        type = typeName, name = typeName, isClothing = true,
        bloodClothingType = clothingType and w.env.BloodClothingType[clothingType],
    })
    w.t.player.worn:add(item, location or typeName)
    return item
end

local function consume(w) return w.env.RD_HygieneManager.consumeHygieneProduct() end
local function part(w, name) return w.env.BloodBodyPartType[name] end
local function bodyBlood(w, name) return w.t.player.visual:getBlood(part(w, name)) end
local function bodyDirt(w, name) return w.t.player.visual:getDirt(part(w, name)) end
local function setLeak(w, level) w.icdata().LeakLevel = level end
local function groin(w) return w.t.player.bodyDamage:getBodyPart(w.env.BodyPartType.Groin) end

local function setNameCount(item)
    local n = 0
    for _, h in ipairs(item.history) do
        if h.what == "setName" then n = n + 1 end
    end
    return n
end

-- ================= WIRING =================

T.describe("red-phase tick registration", function()

    T.it("registers the red-phase wear-down tick exactly once", function()
        -- The flag is only set when the handler first RUNS. That is safe because the engine's
        -- Event.trigger walks the live handler list, so a handler added mid-dispatch runs in
        -- the same minute (confirmed via bytecode; the harness now mirrors it).
        local w = world()
        T.eq(w.cycle().current_phase, "redPhase")
        local before = #w.t.events.handlersFor("EveryOneMinute")

        w.advanceMinutes(15)

        T.eq(#w.t.events.handlersFor("EveryOneMinute"), before + 1,
            "one wear-down handler, not one per minute")
    end)

end)

-- ================= WEAR-DOWN =================

T.describe("hygiene item wear-down", function()

    T.it("marks a fresh item used at once, then again every 100 ticks", function()
        local w = world()
        local item = wear(w, "Tampon", { condition = 10 })

        consume(w)
        T.eq(item:getCondition(), 9)

        for _ = 1, 100 do consume(w) end
        T.eq(item:getCondition(), 9, "not before the counter passes 100")

        consume(w)
        T.eq(item:getCondition(), 8)
    end)

    T.it("never goes below condition 1", function()
        local w = world()
        local item = wear(w, "Tampon", { condition = 1 })
        for _ = 1, 150 do consume(w) end
        T.eq(item:getCondition(), 1)
    end)

    T.it("names the item after how used it is", function()
        local cases = {
            { 10, "Tampon (Spotty)" }, { 9, "Tampon (Spotty)" }, { 8, "Tampon (Bloody)" },
            { 5, "Tampon (Very Bloody)" }, { 4, "Tampon (Very Bloody)" },
            { 3, "Tampon" }, { 2, "Tampon (Nearly Saturated)" }, { 1, "Tampon (Saturated)" },
        }
        for _, case in ipairs(cases) do
            local w = world()
            local item = wear(w, "Tampon", { condition = case[1], name = "Tampon" })
            w.t.rng.script({ 1 })  -- a d20 roll that never leaks
            consume(w)
            T.eq(item:getName(), case[2], "at condition " .. case[1])
        end
    end)

    T.it("keeps the base name when a suffix is already there", function()
        local w = world()
        local item = wear(w, "Tampon", { condition = 8, name = "Tampon (Spotty)" })
        consume(w)
        T.eq(item:getName(), "Tampon (Bloody)")
    end)

    T.it("renames only when the name actually changes", function()
        local w = world()
        local item = wear(w, "Tampon", { condition = 8, name = "Tampon" })
        consume(w)
        consume(w)
        T.eq(setNameCount(item), 1)
    end)

    T.it("syncs each change to the server on an MP client", function()
        local pair = MP.newPair({ sandbox = { phase_start_delay_enabled = false } })
        local _, serverItem = pair.giveItem({ condition = 10 })
        pair.client.env.RD_HygieneManager.consumeHygieneProduct()
        T.eq(serverItem:getCondition(), 9)
        T.eq(serverItem:getName(), "Tampon (Spotty)")
    end)

end)

T.describe("hygiene item leaks", function()

    local function leaks(condition, d20)
        local w = world()
        wear(w, "Tampon", { condition = condition })
        w.t.rng.script({ d20 })
        return consume(w) == false
    end

    T.it("leaks at condition 3 on a d20 roll of 15 or more", function()
        T.truthy(leaks(3, 15))
        T.falsy(leaks(3, 14))
    end)

    T.it("leaks at condition 2 on a d20 roll of 10 or more", function()
        T.truthy(leaks(2, 10))
        T.falsy(leaks(2, 9))
    end)

    T.it("always leaks once saturated, and never while fresh", function()
        T.truthy(leaks(1, 1))
        T.falsy(leaks(10, 20))
        T.falsy(leaks(6, 20))
    end)

end)

T.describe("discharge", function()

    T.it("marks the item Dirty and used up", function()
        local w = world()
        local item = wear(w, "Panty_Liner", { condition = 10, name = "Panty_Liner" })
        T.truthy(w.env.RD_HygieneManager.consumeDischargeProduct())
        T.eq(item:getCondition(), 1)
        T.eq(item:getName(), "Panty_Liner (Dirty)")
        T.eq(bodyDirt(w, "Groin"), 0)
    end)

    T.it("into an already-used item, it stains the groin", function()
        local w = world()
        wear(w, "Panty_Liner", { condition = 1, name = "Panty_Liner (Dirty)" })
        T.falsy(w.env.RD_HygieneManager.consumeDischargeProduct())
        T.near(bodyDirt(w, "Groin"), 0.01, 1e-12)
        T.eq(bodyDirt(w, "UpperLeg_L"), 0, "dirt stays on the groin")
    end)

    T.it("does nothing with no item worn", function()
        local w = world()
        T.falsy(w.env.RD_HygieneManager.consumeDischargeProduct())
        T.eq(bodyDirt(w, "Groin"), 0)
    end)

end)

-- ================= STAINS =================

T.describe("blood stains", function()

    T.it("a light leak stains only the groin, up to 25%", function()
        local w = world()
        setLeak(w, 0.35)
        w.env.RD_HygieneManager.addBloodStains()
        T.near(bodyBlood(w, "Groin"), 0.01, 1e-12)
        T.eq(bodyBlood(w, "UpperLeg_L"), 0)

        w.t.player.visual:setBlood(part(w, "Groin"), 0.25)
        w.env.RD_HygieneManager.addBloodStains()
        T.near(bodyBlood(w, "Groin"), 0.25, 1e-12, "capped for this leak level")
    end)

    T.it("heavier leaks spread further down the legs", function()
        local function spread(level)
            local w = world()
            setLeak(w, level)
            w.env.RD_HygieneManager.addBloodStains()
            return w
        end
        local w2 = spread(0.25)
        T.truthy(bodyBlood(w2, "UpperLeg_R") > 0)
        T.eq(bodyBlood(w2, "LowerLeg_L"), 0)

        local w3 = spread(0.15)
        T.truthy(bodyBlood(w3, "LowerLeg_R") > 0)
        T.eq(bodyBlood(w3, "Foot_L"), 0)

        local w4 = spread(0.05)
        T.truthy(bodyBlood(w4, "Foot_R") > 0)
    end)

    T.it("no leak means no stains", function()
        local w = world()
        setLeak(w, 0.42)
        w.env.RD_HygieneManager.addBloodStains()
        T.eq(bodyBlood(w, "Groin"), 0)
    end)

    T.it("stains the clothing over a stained part, and only there", function()
        local w = world()
        local trousers = wearClothing(w, "Trousers", "Trousers")
        local shirt = wearClothing(w, "Shirt", "Shirt")
        setLeak(w, 0.25)
        w.env.RD_HygieneManager.addBloodStains()

        T.near(trousers:getBlood(part(w, "Groin")), 0.01, 1e-12)
        T.near(trousers:getBlood(part(w, "UpperLeg_L")), 0.01, 1e-12)
        T.eq(trousers:getBlood(part(w, "LowerLeg_L")), 0, "tier 3 not reached at this level")
        T.eq(shirt:getBlood(part(w, "Torso_Upper")), 0)
    end)

end)

T.describe("stain sync in multiplayer", function()

    T.it("REGRESSION: an MP client's stains reach the server's body and clothing", function()
        -- Seen in a hosted game: "body stains LOST on the server", "clothing stains LOST".
        local pair = MP.newPair({ sandbox = { phase_start_delay_enabled = false } })
        local function trousers(side)
            local item = side.t.newItem({
                type = "Trousers", id = 9001, isClothing = true,
                bloodClothingType = side.env.BloodClothingType.Trousers,
            })
            side.t.player.worn:add(item, "Pants")
            return item
        end
        local clientTrousers, serverTrousers = trousers(pair.client), trousers(pair.server)
        pair.client.icdata().LeakLevel = 0.25

        pair.client.env.RD_HygieneManager.addBloodStains()
        pair.client.env.RD_HygieneManager.addDirtStains()

        local cGroin = pair.client.env.BloodBodyPartType.Groin
        local sGroin = pair.server.env.BloodBodyPartType.Groin
        T.eq(#pair.commandsNamed("applyStains"), 2)
        T.near(pair.serverPlayer.visual:getBlood(sGroin), pair.clientPlayer.visual:getBlood(cGroin), 1e-12)
        T.near(pair.serverPlayer.visual:getDirt(sGroin), pair.clientPlayer.visual:getDirt(cGroin), 1e-12)
        T.near(serverTrousers:getBlood(sGroin), clientTrousers:getBlood(cGroin), 1e-12)
        T.near(serverTrousers:getBlood(pair.server.env.BloodBodyPartType.UpperLeg_L), 0.01, 1e-12)
        T.truthy(serverTrousers:getBlood(sGroin) > 0)
    end)

    T.it("sends nothing in single player", function()
        local w = world()
        setLeak(w, 0.25)
        w.env.RD_HygieneManager.addBloodStains()
        T.eq(#w.t.sentCommands, 0)
        T.truthy(bodyBlood(w, "Groin") > 0)
    end)

    T.it("REGRESSION: a missing RD_stains never breaks the client or server", function()
        -- shared/RD_stains.lua is a new file, and PZ keeps the file list it scanned at launch, so
        -- until a full restart its require fails and RD_Stains is nil (as happened with RD_config).
        for _, side in ipairs({ "client", "server" }) do
            local w = H.newWorld({
                load = "none", isServer = side == "server",
                sandbox = { phase_start_delay_enabled = false },
            })
            w.env.__loaded.RD_stains = true  -- require "RD_stains" yields nothing
            local load = side == "client" and w.loader.loadClient or w.loader.loadServer
            local ok, err = pcall(load, w.env)
            T.truthy(ok, side .. " must load without RD_Stains, got: " .. tostring(err))

            local ran, runErr
            if side == "client" then
                w.start()
                w.icdata().LeakLevel = 0.05
                ran, runErr = pcall(w.env.RD_HygieneManager.consumeHygieneProduct)
            else
                ran, runErr = pcall(w.t.events.fire, "OnClientCommand", "RedDays", "applyStains",
                    w.t.player, { blood = true, dirt = false, maxTier = 1, maxLevel = 1 })
            end
            T.truthy(ran, side .. " must keep working without RD_Stains, got: " .. tostring(runErr))
        end
    end)

    T.it("sends nothing when the leak is too light to stain", function()
        local pair = MP.newPair({ sandbox = { phase_start_delay_enabled = false } })
        pair.client.icdata().LeakLevel = 0.42
        pair.client.env.RD_HygieneManager.addBloodStains()
        T.eq(#pair.commandsNamed("applyStains"), 0)
    end)

end)

T.describe("blood dripping to the ground", function()

    local function drips(setup)
        local w = world()
        setLeak(w, 0.05)  -- the heaviest tier: 15% base chance
        setup(w)
        w.env.RD_HygieneManager.addBloodStains()
        return #w.t.bloodSplats > 0
    end

    T.it("drips freely with nothing on below the waist (3x chance)", function()
        T.truthy(drips(function(w) w.t.rng.script({ 45 }) end))
        T.falsy(drips(function(w) w.t.rng.script({ 46 }) end))
    end)

    T.it("underwear holds it until the groin is soaked", function()
        T.falsy(drips(function(w)
            wearClothing(w, "Underwear", nil, "base:underwearbottom")
            w.t.rng.script({ 1 })
        end))
        T.truthy(drips(function(w)
            wearClothing(w, "Underwear", nil, "base:underwearbottom")
            w.t.player.visual:setBlood(part(w, "Groin"), 0.995)
            w.t.rng.script({ 1 })
        end))
    end)

    T.it("fully clothed, it drips only once the shins are soaked", function()
        local function dressed(w)
            wearClothing(w, "Trousers", "Trousers")
            wearClothing(w, "Shoes", "Shoes")
        end
        T.falsy(drips(function(w)
            dressed(w)
            w.t.rng.script({ 1 })
        end))
        T.truthy(drips(function(w)
            dressed(w)
            w.t.player.visual:setBlood(part(w, "LowerLeg_L"), 1.0)
            w.t.player.visual:setBlood(part(w, "LowerLeg_R"), 1.0)
            w.t.rng.script({ 1 })
        end))
    end)

    T.it("a skirt drips once both the groin and the skirt are half soaked", function()
        T.falsy(drips(function(w)
            wearClothing(w, "Skirt", "Skirt")
            w.t.player.visual:setBlood(part(w, "Groin"), 0.2)
            w.t.rng.script({ 1 })
        end))
        T.truthy(drips(function(w)
            local skirt = wearClothing(w, "Skirt", "Skirt")
            w.t.player.visual:setBlood(part(w, "Groin"), 0.6)
            skirt:setBlood(part(w, "Groin"), 0.6)
            w.t.rng.script({ 1 })
        end))
    end)

end)

-- ================= NO INJURY =================
-- Periods are shown through moodles and stains, never by injuring the player: the mod does not
-- touch the groin's bleeding state, and a bandage is not a stand-in for a pad (a later update may
-- let players fold one into a pad).

T.describe("periods never injure the player", function()

    T.it("with no item, blood stains the body even with a bandaged groin", function()
        local w = world()
        setLeak(w, 0.05)
        groin(w).isBandaged = true
        groin(w).bandageLife = 1
        T.falsy(consume(w), "a bandage is not a pad")
        T.near(bodyBlood(w, "Groin"), 0.01, 1e-12)
        T.eq(groin(w).bandageLife, 1, "the bandage is left alone")
    end)

    T.it("with no item and no bandage, blood stains the body", function()
        local w = world()
        setLeak(w, 0.05)
        T.falsy(consume(w))
        T.near(bodyBlood(w, "Groin"), 0.01, 1e-12)
    end)

    T.it("never touches the groin's bleeding flag", function()
        local w = world()
        wear(w, "Tampon", { condition = 10 })
        consume(w)
        T.eq(#w.t.player:callsOf("setBleeding"), 0, "with an item worn")

        local bare = world()
        consume(bare)
        T.eq(#bare.t.player:callsOf("setBleeding"), 0, "with nothing worn")
    end)

    T.it("leaving the red phase clears the leak switch, even with a real groin wound", function()
        local w = world()
        groin(w).bleedingTime = 5
        w.advanceMinutes(1)
        T.truthy(w.icdata().LeakSwitchState, "sanity: leaking with no item in the red phase")

        w.cycle().current_phase = "follicularPhase"
        w.cycle().phase_minutes_remaining = 100000
        w.advanceMinutes(1)

        T.falsy(w.icdata().LeakSwitchState)
    end)

end)

-- ================= STARTER ITEMS =================

T.describe("starter hygiene items", function()

    T.it("are granted once when the sandbox option is on", function()
        local w = world({ spawn_with_hygiene_products = true })
        T.eq(w.t.player.inventory:size(), 4)
        w.env.RD_HygieneManager.grantStarterHygieneItems()
        T.eq(w.t.player.inventory:size(), 4, "not granted twice")
        T.truthy(w.icdata().hygieneStarterItemsGranted)
    end)

    T.it("are not granted when the option is off", function()
        local w = world({ spawn_with_hygiene_products = false })
        T.eq(w.t.player.inventory:size(), 0)
    end)

end)
