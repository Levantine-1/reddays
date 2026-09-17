-- Multiplayer simulation: a client environment and a server environment in one
-- process, joined by a message bus.
--
-- The client's sendClientCommand() deep-copies its payload (standing in for
-- serialisation, so accidental shared-table aliasing shows up) and delivers it to
-- the server env's registered OnClientCommand handlers. The two environments have
-- SEPARATE player and item doubles that merely share IDs -- so a change the server
-- makes does not magically appear on the client, which is exactly the drift we
-- want tests to be able to see.

local M = {}

local H = require "harness.init"
local itemLib = require "harness.doubles.item"

-- ================= SERIALISATION =================

local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do out[deepCopy(k, seen)] = deepCopy(val, seen) end
    return out
end
M.deepCopy = deepCopy

-- Wraps a payload so every field the handler actually reads is recorded.
-- Anything sent but never read is drift: the client is talking about something
-- the server does not listen for.
local function trackingProxy(payload)
    local read = {}
    local proxy = setmetatable({}, {
        __index = function(_, key)
            read[key] = true
            return payload[key]
        end,
        __newindex = function(_, key, value) payload[key] = value end,
    })
    return proxy, read
end

-- ================= PROTOCOL SOURCE SCAN =================
-- The server's `Commands` table is a file-local and cannot be enumerated at
-- runtime, so the wire contract is recovered from source. This is what catches a
-- renamed handler or a command name typo -- both of which fail silently in game.

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function luaRoot()
    return H.hostConfig().luaRoot
end

local CLIENT_FILES = {
    "RD_hygiene_manager.lua", "RD_effects_pms.lua", "RD_tss_manager.lua", "RD_main.lua",
    "RD_selftest.lua",
}

-- Every ('RedDays', 'command') pair the client can send, with its source file.
--
-- Scanned positionally rather than with one pattern, because the first argument
-- is itself a call -- sendClientCommand(getPlayer(), 'RedDays', 'x', ...) -- and a
-- single pattern cannot span the nested parentheses.
function M.clientCommands()
    local found, order = {}, {}
    for _, name in ipairs(CLIENT_FILES) do
        local src = readFile(luaRoot() .. "/client/" .. name)
        if src then
            local pos = 1
            while true do
                local callStart = string.find(src, "sendClientCommand", pos, true)
                if not callStart then break end
                -- Look ahead a bounded window for the module/command literal pair.
                local window = string.sub(src, callStart, callStart + 200)
                local command = string.match(window, "'RedDays'%s*,%s*'([%w_]+)'")
                if command and not found[command] then
                    found[command] = name
                    order[#order + 1] = command
                end
                pos = callStart + 1
            end
        end
    end
    return order, found
end

-- { [fileName] = source } for every scanned client file that exists.
function M.clientSources()
    local out = {}
    for _, name in ipairs(CLIENT_FILES) do
        local src = readFile(luaRoot() .. "/client/" .. name)
        if src then out[name] = src end
    end
    return out
end

-- Every command the server implements.
function M.serverCommands()
    local src = readFile(luaRoot() .. "/server/RD_server_commands.lua") or ""
    local order = {}
    for command in string.gmatch(src, "function%s+Commands%.([%w_]+)") do
        order[#order + 1] = command
    end
    return order
end

-- Every hpMode string literal the client can assign, and every one the server
-- matches explicitly (i.e. NOT via the catch-all else).
function M.hpModes()
    local clientSrc = readFile(luaRoot() .. "/client/RD_tss_manager.lua") or ""
    local serverSrc = readFile(luaRoot() .. "/server/RD_server_commands.lua") or ""

    local emitted = {}

    -- Only ASSIGNMENTS count, not the `local mode = "none"` declaration: that
    -- initial value is always overwritten before pending.hpMode is set, so it
    -- never reaches the wire and must not be treated as part of the contract.
    -- %f[%w_] is a frontier pattern: it anchors to the START of the identifier, so
    -- `recovery_mode = "antibiotics"` is not mistaken for the hpMode variable.
    local pos = 1
    while true do
        local s, e, mode = string.find(clientSrc, "%f[%w_]mode%s*=%s*\"([%w_]+)\"", pos)
        if not s then break end
        local preceding = string.sub(clientSrc, math.max(1, s - 6), s - 1)
        if not string.find(preceding, "local%s*$") then
            emitted[mode] = true
        end
        pos = e + 1
    end

    -- `mode = isSleeping and "a" or "b"` needs the second literal picked up too.
    for a, b in string.gmatch(clientSrc,
            "%f[%w_]mode%s*=%s*[%w_]+%s+and%s+\"([%w_]+)\"%s+or%s+\"([%w_]+)\"") do
        emitted[a] = true
        emitted[b] = true
    end

    local handled = {}
    for mode in string.gmatch(serverSrc, "args%.hpMode%s*==%s*\"([%w_]+)\"") do
        handled[mode] = true
    end

    return emitted, handled
end

-- ================= THE BUS =================

-- opts: sandbox, seed, player (client-side), serverPlayer, selftest, verboseLog, debug
function M.newPair(opts)
    opts = opts or {}

    local client = H.newWorld({
        sandbox = opts.sandbox,
        seed = opts.seed or 1,
        player = opts.player,
        isClient = true,
        autoStart = opts.autoStart,
        selftest = opts.selftest,
        verboseLog = opts.verboseLog,
        debug = opts.debug,
    })
    local server = H.newWorld({
        sandbox = opts.sandbox,
        seed = opts.seed or 1,
        player = opts.serverPlayer or opts.player,
        isServer = true,
        load = "server",
        selftest = opts.selftest,
        verboseLog = opts.verboseLog,
        debug = opts.debug,
    })

    local bus = { sent = {}, delivered = {}, dropped = {}, toClient = {} }

    local pair = {
        client = client,
        server = server,
        bus = bus,
        serverPlayer = server.t.player,
        clientPlayer = client.t.player,
    }

    -- Delivers one command to the server exactly as the engine would.
    local function deliver(sender, module, command, args)
        local wire = deepCopy(args)
        local proxy, read = trackingProxy(wire)

        local record = {
            module = module,
            command = command,
            payload = wire,
            read = read,
            handlers = 0,
        }
        bus.sent[#bus.sent + 1] = record

        local handlers = server.t.events.handlersFor("OnClientCommand")
        for _, fn in ipairs(handlers) do
            fn(module, command, server.t.player, proxy)
            record.handlers = record.handlers + 1
        end

        -- Keys sent but never looked at by any handler.
        local unread = {}
        for key in pairs(wire) do
            if not read[key] then unread[#unread + 1] = key end
        end
        table.sort(unread)
        record.unread = unread

        if #unread > 0 then
            bus.dropped[#bus.dropped + 1] = record
        end
        bus.delivered[#bus.delivered + 1] = record
        return record
    end

    -- Route the client environment's outbound traffic into the server.
    client.env.sendClientCommand = function(sender, module, command, args)
        return deliver(sender, module, command, args)
    end

    -- Route the server's replies back to the client's OnServerCommand handlers.
    server.env.sendServerCommand = function(a, b, c, d)
        local module, command, args
        if type(a) == "string" then module, command, args = a, b, c else module, command, args = b, c, d end
        local record = { module = module, command = command, payload = deepCopy(args) }
        bus.toClient[#bus.toClient + 1] = record
        client.t.events.fire("OnServerCommand", module, command, record.payload)
    end

    -- transmitModData(): the server's copy of the player's modData becomes the client's.
    local clientPlayer = client.t.player
    local rawTransmit = clientPlayer.transmitModData
    function clientPlayer:transmitModData()
        rawTransmit(self)
        server.t.player.modData = deepCopy(self.modData)
    end
    server.t.player.modData = deepCopy(clientPlayer.modData)

    -- Sends a command directly, without going through mod code.
    function pair.send(command, args)
        return deliver(client.t.player, "RedDays", command, args)
    end

    -- Creates the same logical item on both sides: separate doubles sharing an ID.
    -- where = "worn" (default) or "inventory"; container = "backpack" to nest it
    -- inside a bag on the server, reproducing the case the server cannot resolve.
    function pair.giveItem(opts2)
        opts2 = opts2 or {}
        local spec = {
            type = opts2.type or "Tampon",
            fullType = opts2.fullType or ("RedDays." .. (opts2.type or "Tampon")),
            condition = opts2.condition or 10,
            name = opts2.name,
            bodyLocation = opts2.bodyLocation or "RedDays:HygieneItem",
        }

        local clientItem = itemLib.new(spec)
        local serverSpec = {}
        for k, v in pairs(spec) do serverSpec[k] = v end
        serverSpec.id = clientItem.id
        local serverItem = itemLib.new(serverSpec)

        local where = opts2.where or "worn"
        if where == "worn" then
            client.t.player.worn:add(clientItem, spec.bodyLocation)
            server.t.player.worn:add(serverItem, spec.bodyLocation)
        elseif where == "backpack" then
            -- Inside a container: the server's lookup only scans worn items and
            -- TOP-LEVEL inventory, so this deliberately cannot be resolved.
            client.t.player.inventory:AddItem(clientItem)
            local bag = itemLib.new({ type = "Bag", isContainer = true })
            bag.inventory = require("harness.doubles.container").newInventory(itemLib.new)
            bag.inventory:AddItem(serverItem)
            server.t.player.inventory:AddItem(bag)
        else
            client.t.player.inventory:AddItem(clientItem)
            server.t.player.inventory:AddItem(serverItem)
        end

        return clientItem, serverItem
    end

    -- The last delivered record for a given command name.
    function pair.lastCommand(name)
        for i = #bus.delivered, 1, -1 do
            if bus.delivered[i].command == name then return bus.delivered[i] end
        end
        return nil
    end

    function pair.commandsNamed(name)
        local out = {}
        for _, record in ipairs(bus.delivered) do
            if record.command == name then out[#out + 1] = record end
        end
        return out
    end

    -- Gives the server-side player an admin role (vanilla's Capability.AddItem check).
    function pair.makeServerAdmin()
        local Capability = server.env.Capability
        function pair.serverPlayer:getRole()
            return { hasCapability = function(_, cap) return cap == Capability.AddItem end }
        end
    end

    return pair
end

return M
