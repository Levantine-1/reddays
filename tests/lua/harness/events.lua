-- Fake Events registry.
--
-- Auto-creates any event the mod touches, so no list needs maintaining here.
-- Handlers are captured rather than merely counted: RD_main.lua registers its
-- hooks as file-locals, and capturing them is what lets sim.lua drive the real
-- wiring instead of a reimplementation of it.

local M = {}

function M.new()
    local registry = { __handlers = {} }

    local function slot(name)
        local handlers = registry.__handlers[name]
        if not handlers then
            handlers = {}
            registry.__handlers[name] = handlers
        end
        return handlers
    end

    -- Returns the handler list for an event, in registration order.
    function registry.handlersFor(name)
        return slot(name)
    end

    -- Calls every handler registered for `name`, in order, passing ... through.
    --
    -- Mirrors zombie.Lua.Event.trigger exactly (confirmed via bytecode): it walks the LIVE
    -- list by index, re-reading size() every step, and only advances the index if the
    -- handler it just ran is still registered (callbacks.contains). So a handler added
    -- during dispatch runs in that same dispatch, and one that removes itself does not
    -- make the next handler get skipped. An earlier snapshot-based version reported a
    -- double registration in RD_effects_manager that cannot happen in game.
    function registry.fire(name, ...)
        local list = slot(name)
        local calls = 0
        local i = 1
        while i <= #list do
            local fn = list[i]
            fn(...)
            calls = calls + 1
            local stillRegistered = false
            for _, h in ipairs(list) do
                if h == fn then stillRegistered = true break end
            end
            if stillRegistered then i = i + 1 end
        end
        return calls
    end

    function registry.clear()
        registry.__handlers = {}
    end

    local eventObjects = {}
    setmetatable(registry, {
        __index = function(_, name)
            if eventObjects[name] then return eventObjects[name] end
            local ev = {}
            function ev.Add(fn) table.insert(slot(name), fn) end
            -- Matches real PZ's Event$Remove, which is a plain ArrayList.remove(Object) --
            -- confirmed via bytecode to strip only the FIRST match, not every occurrence.
            -- This matters: a handler added twice (Add never dedupes either) needs two
            -- Removes to fully unregister, and tests rely on that to catch double-registration.
            function ev.Remove(fn)
                local handlers = slot(name)
                for i = 1, #handlers do
                    if handlers[i] == fn then
                        table.remove(handlers, i)
                        return
                    end
                end
            end
            eventObjects[name] = ev
            return ev
        end,
    })

    return registry
end

return M
