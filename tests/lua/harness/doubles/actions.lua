-- Doubles for the five vanilla ISO action classes RD_main.lua monkeypatches.
--
-- RD_main.lua does `local original = ISUnequipAction.perform` then reassigns
-- `ISUnequipAction.perform`. Both the class table and the original method must
-- already exist at load time, or that file errors immediately.

local M = {}

-- Each class records how many times its ORIGINAL method ran, so tests can prove
-- the mod still chains through to vanilla rather than swallowing the action.
function M.new()
    local actions = { originalCalls = {} }

    local function defineClass(name, methodName)
        local class = { __actionClass = name }
        actions.originalCalls[name] = 0
        class[methodName] = function(self)
            actions.originalCalls[name] = actions.originalCalls[name] + 1
            return self
        end
        actions[name] = class
        return class
    end

    defineClass("ISUnequipAction", "perform")
    defineClass("ISWearClothing", "perform")
    defineClass("ISWashYourself", "perform")
    defineClass("ISTakePillAction", "perform")
    defineClass("ISEatFoodAction", "complete")
    defineClass("ISDrinkFluidAction", "complete")

    -- Builds an action instance to pass into an intercepted method.
    -- `item` is what the mod inspects via self.item.
    function actions.instance(className, item)
        return { item = item, character = actions.character }
    end

    return actions
end

return M
