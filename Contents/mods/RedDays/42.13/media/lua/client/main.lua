require "game_api"
require "cycle_manager"
require "cycle_tracker_logic"
require "effects_manager"
require "hygiene_manager"
require "effects_pms"
require "moodles"

-- Gender check
local function isValidGenderCheck()
    if not SandboxVars.RedDays.affectsAllGenders then
        if not zapi.isFemale() then
            return false
        end
    end
    return true
end

-- ================= GLOBAL EVENT HOOKS =================
local function initializePlayerData()
    CycleManager.LoadPlayerData()
    CycleTrackerLogic.LoadPlayerData()
    EffectsPMS.LoadPlayerData()
    HygieneManager.LoadPlayerData()
    moodles.LoadPlayerData()
end

local function OnGameStart()
    if not isValidGenderCheck() then return end
    initializePlayerData()
end
Events.OnGameStart.Add(OnGameStart)

local function OnCreatePlayer(playerIndex, player) -- When player is created or respawned
    if playerIndex ~= 0 then return end
    if not isValidGenderCheck() then return end
    initializePlayerData()
end
Events.OnCreatePlayer.Add(OnCreatePlayer)

-- ================= TIMED EVENT HOOKS =================
local function EveryHours()
    if not isValidGenderCheck() then return end
    -- CycleDebugger.printWrapper()
end
Events.EveryHours.Add(EveryHours)

local function EveryTenMinutes()
    if not isValidGenderCheck() then return end
    CycleDebugger.printWrapper()
end
Events.EveryTenMinutes.Add(EveryTenMinutes)

local function EveryOneMinute()
    if not isValidGenderCheck() then return end
    local cycle = CycleManager.tick(1)
    EffectsManager.determineEffects(cycle)
    EffectsPMS.applyPMSEffectsMain()
    moodles.mainLoop()
end
Events.EveryOneMinute.Add(EveryOneMinute)

-- ================= INTERCEPT FUNCTIONS =================
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    if isValidGenderCheck() then
        moodles.ISUnequipAction_perform(self)
        CycleTrackerLogic.ISUnequipAction_perform(self)
    end
    o_ISUnequipAction_perform(self)
end

local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    if isValidGenderCheck() then
        moodles.ISWearClothing_perform(self)
        CycleTrackerLogic.ISWearClothing_perform(self)
    end
    o_ISWearClothing_perform(self)
end

local o_ISWashYourself_perform = ISWashYourself.perform
function ISWashYourself:perform()
    if isValidGenderCheck() then
        moodles.ISWashYourself_perform()
    end
    o_ISWashYourself_perform(self)
end

local o_ISTakePillAction_perform = ISTakePillAction.perform
function ISTakePillAction:perform()
    if isValidGenderCheck() then
        EffectsPMS.ISTakePillAction_perform(self)
    end
    o_ISTakePillAction_perform(self)
end
