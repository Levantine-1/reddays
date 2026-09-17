require "RD_hygiene_manager"
require "RD_moodles"
require "RD_game_api"

RD_EffectsManager = RD_EffectsManager or {}
RDEffectsManager = RD_EffectsManager -- Alias for backward compatibility

local stat_Adjustment_isEnabled = false
local function stat_Adjustment()
    stat_Adjustment_isEnabled = true
    local cycle = RD_modData.ICdata.currentCycle -- The event system calls the function with no arguments, so cycle is nil, so that's why it's set here

    local didConsume = RD_HygieneManager.consumeHygieneProduct()
    if didConsume then
        RD_modData.ICdata.LeakSwitchState = false
    else
        RD_modData.ICdata.LeakSwitchState = true
    end
end

local consumingDischargeItem = false
local function consumeDischargeProduct()
    consumingDischargeItem = true
    return RD_HygieneManager:consumeDischargeProduct()
end

-- The period is over, so stop the leak moodle building. Deliberately independent of the groin's
-- bleeding state: the mod never injures the player, so a real wound there is not period-related.
local function endRedPhaseLeak()
    RD_modData.ICdata.LeakSwitchState = false
end

function RD_EffectsManager.determineEffects(cycle)
    local current_phase = RD_CycleManager.getCurrentCyclePhase(cycle)

    if current_phase == "redPhase" then
        if not stat_Adjustment_isEnabled then
            Events.EveryOneMinute.Add(stat_Adjustment)
        end
        if consumingDischargeItem then
            Events.EveryDays.Remove(consumeDischargeProduct)
            consumingDischargeItem = false
        end
    else
        if stat_Adjustment_isEnabled then
            Events.EveryOneMinute.Remove(stat_Adjustment)
            endRedPhaseLeak()
        end
        stat_Adjustment_isEnabled = false

        if not consumingDischargeItem then
            Events.EveryDays.Add(consumeDischargeProduct)
            consumingDischargeItem = true
        end
    end
end

return RD_EffectsManager
