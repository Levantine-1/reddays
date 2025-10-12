require "MF_ISMoodle"

MF.createMoodle("DirtyPantyLiner");
MF.createMoodle("BloodyPantyLiner");

MF.createMoodle("DirtySanitaryPad");
MF.createMoodle("BloodySanitaryPad");

MF.createMoodle("DirtyTampon");
MF.createMoodle("BloodyTampon");

MF.createMoodle("Leak");

local RedDaysMoodles = {}
-- Moodle level is a float value between 0 and 1 where 0 is worst moodle state and 1 is best moodle state and .5 is neutral



local MLevel = 0
function flipFlopDebug()
    local playerNum = getPlayer():getPlayerNum()
    local moodleName, level
    moodleName = "DirtyPantyLiner"

    print("Setting Moodle - " .. moodleName .. " to level " .. tostring(MLevel) .. " for player " .. tostring(playerNum))
    MF.getMoodle(moodleName, playerNum):setValue(MLevel)
    MLevel = MLevel + .05
end
Events.EveryOneMinute.Add(flipFlopDebug)

return RedDaysMoodles