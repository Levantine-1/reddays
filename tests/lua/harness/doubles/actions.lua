-- Doubles for the five vanilla ISO action classes RD_main.lua monkeypatches.
--
-- RD_main.lua does `local original = ISUnequipAction.perform` then reassigns
-- `ISUnequipAction.perform`. Both the class table and the original method must
-- already exist at load time, or that file errors immediately.

local M = {}

-- Each class records how many times its ORIGINAL perform() ran, so tests can prove
-- the mod still chains through to vanilla rather than swallowing the action.
--
-- Every class also has a complete(), exactly like vanilla B42. That split matters: in MP,
-- complete() runs ONLY on the server, which never loads client/ Lua -- so a client hook
-- on complete() silently never fires there. Having both here means a test calling
-- perform() fails if the mod hooked the wrong one.
function M.new()
    local actions = { originalCalls = {}, originalCompleteCalls = {}, originalStopCalls = {} }

    local function defineClass(name)
        local class = { __actionClass = name }
        actions.originalCalls[name] = 0
        actions.originalCompleteCalls[name] = 0
        actions.originalStopCalls[name] = 0
        class.perform = function(self)
            actions.originalCalls[name] = actions.originalCalls[name] + 1
            return self
        end
        class.complete = function(self)
            actions.originalCompleteCalls[name] = actions.originalCompleteCalls[name] + 1
            return true
        end
        -- stop() is what the engine calls instead of perform() when isValid() fails mid-action.
        class.stop = function(self)
            actions.originalStopCalls[name] = actions.originalStopCalls[name] + 1
        end
        actions[name] = class
        return class
    end

    defineClass("ISUnequipAction")
    defineClass("ISWearClothing")
    defineClass("ISWashYourself")
    defineClass("ISTakePillAction")
    defineClass("ISEatFoodAction")
    defineClass("ISDrinkFluidAction")

    -- Builds an action instance to pass into an intercepted method.
    -- `item` is what the mod inspects via self.item.
    -- `extra` adds action fields, e.g. { fluidContainer = actions.fluidContainer(true) }.
    function actions.instance(className, item, extra)
        local instance = { item = item, character = actions.character }
        for k, v in pairs(extra or {}) do instance[k] = v end
        return instance
    end

    -- ISDrinkFluidAction keeps the item's FluidContainer as self.fluidContainer.
    function actions.fluidContainer(empty)
        return { isEmpty = function() return empty == true end }
    end

    return actions
end

return M
