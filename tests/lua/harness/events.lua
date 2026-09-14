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
    -- Iterates a snapshot so a handler that unregisters itself (as
    -- RD_effects_manager does) doesn't corrupt the traversal.
    function registry.fire(name, ...)
        local snapshot = {}
        for i, fn in ipairs(slot(name)) do snapshot[i] = fn end
        for _, fn in ipairs(snapshot) do fn(...) end
        return #snapshot
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
            function ev.Remove(fn)
                local handlers = slot(name)
                for i = #handlers, 1, -1 do
                    if handlers[i] == fn then table.remove(handlers, i) end
                end
            end
            eventObjects[name] = ev
            return ev
        end,
    })

    return registry
end

return M
