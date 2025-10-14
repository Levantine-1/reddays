require "MF_ISMoodle"

require "RedDays/hygiene_manager"
require "RedDays/cycle_manager"

local RedDaysMoodles = {}

MF.createMoodle("DirtyPantyLiner");
MF.createMoodle("BloodyPantyLiner");

MF.createMoodle("DirtySanitaryPad");
MF.createMoodle("BloodySanitaryPad");

MF.createMoodle("DirtyTampon");
MF.createMoodle("BloodyTampon");

MF.createMoodle("Leak");


-- Moodle level is a float value between 0 and 1 where 0 is worst moodle state and 1 is best moodle state and .5 is neutral
function RedDaysMoodles.setMoodle(name, level, playerID)
    MF.getMoodle(name, playerID):setValue(level)
end

-- Determine if player bathed based on clothes/body dirtiness/bloody
function getMoodleLevel(hygieneItemCondition)
    local moodleLevel = 0.5
    if hygieneItemCondition == 4 then
        moodleLevel = 0.4
    elseif hygieneItemCondition == 3 then
        moodleLevel = 0.3
    elseif hygieneItemCondition == 2 then
        moodleLevel = 0.2
    elseif hygieneItemCondition < 2 then
        moodleLevel = 0
    end
    return moodleLevel
end


function getHygieneItemName(hygieneItem)
    local hygieneItemName = hygieneItem:getType()
    hygieneItemName = string.gsub(hygieneItemName, "_", "") -- Remove all underscores
    return hygieneItemName
end


local function getCurrentPlayerNum()
    return getPlayer():getPlayerNum()
end

local function getCurrentHygieneItem()
    return HygieneManager.getCurrentlyWornSanitaryItem()
end

local function getCurrentPhaseData()
    return CycleManager.getPhaseStatus(modData.ICdata.currentCycle)
end

local function getMoodleType(phase)
    return (phase == "redPhase") and "Bloody" or "Dirty"
end

local function getMoodleLevelForItem(moodletype, condition)
    if moodletype == "Dirty" and condition <= 1 then
        return 0.4 -- Only show level 1 moodle for dirty from discharge
    else
        return getMoodleLevel(condition)
    end
end

local function resetMoodles()
    local playerNum = getCurrentPlayerNum()
    local moodleNames = {
        "DirtyPantyLiner",
        "BloodyPantyLiner",
        "DirtySanitaryPad",
        "BloodySanitaryPad",
        "DirtyTampon",
        "BloodyTampon"
    }
    for _, name in ipairs(moodleNames) do
        MF.getMoodle(name, playerNum):setValue(0.5)
    end
end

function mainLoop()
    print("RedDaysMoodles.mainLoop")
    local hygieneItem = getCurrentHygieneItem()
    if not hygieneItem then
        print("No hygiene item found.")
        return
    end

    print("Hygiene item found")
    local playerNum = getCurrentPlayerNum()
    local hygieneItemCondition = hygieneItem:getCondition()
    local hygieneItemName = getHygieneItemName(hygieneItem)
    print("Hygiene Item - " .. hygieneItemName .. " Condition - " .. hygieneItemCondition)

    local phaseData = getCurrentPhaseData()
    print("Current phase: " .. tostring(phaseData.phase) .. " Time remaining: " .. tostring(phaseData.time_remaining) .. " Percent complete: " .. tostring(phaseData.percent_complete))

    local moodletype = getMoodleType(phaseData.phase)
    local moodleLevel = getMoodleLevelForItem(moodletype, hygieneItemCondition)
    local moodleName = moodletype .. hygieneItemName

    print("Setting moodle - " .. moodleName .. " to level - " .. moodleLevel)
    MF.getMoodle(moodleName, playerNum):setValue(moodleLevel)
end
Events.EveryOneMinute.Add(mainLoop)


-- Below are intercept functions that are triggered when the player interacts with hygiene items.

-- If player unequips the hygiene item, inspect the item and update the cycle tracker
local o_ISUnequipAction_perform = ISUnequipAction.perform
function ISUnequipAction:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        print("Resetting moodles due to unequip")
        resetMoodles()
    end
    o_ISUnequipAction_perform(self)
end

-- If the player replaces a hygiene item, inspect the item and update the cycle tracker
local o_ISWearClothing_perform = ISWearClothing.perform
function ISWearClothing:perform()
    if self.item:getBodyLocation() == "HygieneItem" then
        print("Resetting moodles due to equipping a new hygiene item")
        resetMoodles()
    end
    o_ISWearClothing_perform(self)
end

return RedDaysMoodles