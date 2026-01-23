require "RedDays/cycle_manager"
require "RedDays/cycle_tracker_logic"
require "RedDays/effects_manager"
require "RedDays/hygiene_manager"
require "RedDays/effects_pms"
require "RedDays/moodles"
require "RedDays/main"

-- ================= GLOBAL EVENT HOOKS =================

local function LoadPlayerData()
    Main.LoadPlayerData()
    CycleManager.LoadPlayerData()
    CycleTrackerLogic.LoadPlayerData()
    EffectsPMS.LoadPlayerData()
    HygieneManager.LoadPlayerData()
    moodles.LoadPlayerData()
end
Events.OnGameStart.Add(LoadPlayerData)

local function EveryTenMinutes()
    Main.main()
end
Events.EveryTenMinutes.Add(EveryTenMinutes)

local function EveryOneMinute()
    EffectsPMS.applyPMSEffectsMain()
    moodles.mainLoop()
end
Events.EveryOneMinute.Add(EveryOneMinute)

-- ================= INTERCEPT FUNCTIONS =================

-- If player unequips the hygiene item, inspect the item and update the cycle tracker
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    moodles.ISUnequipAction_perform(self)
    o_ISUnequipAction_perform(self)
end

-- If the player replaces a hygiene item, inspect the item and update the cycle tracker
local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    moodles.ISWearClothing_perform(self)
    o_ISWearClothing_perform(self)
end

-- If the player washes themselves, reset the leak moodle
local o_ISWashYourself_perform = ISWashYourself.perform
function ISWashYourself:perform()
    moodles.ISWashYourself_perform()
    o_ISWashYourself_perform(self)
end
