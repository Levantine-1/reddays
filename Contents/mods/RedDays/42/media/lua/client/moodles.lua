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



local MLevel = .50
function flipFlopDebug()
    local playerNum = getPlayer():getPlayerNum()

    print("FlipFlopDebug - setting all moodles to " .. MLevel)

    MF.getMoodle("DirtyPantyLiner", playerNum):setValue(MLevel)
    MF.getMoodle("BloodyPantyLiner", playerNum):setValue(MLevel)

    MF.getMoodle("DirtySanitaryPad", playerNum):setValue(MLevel)
    MF.getMoodle("BloodySanitaryPad", playerNum):setValue(MLevel)

    MF.getMoodle("DirtyTampon", playerNum):setValue(MLevel)
    MF.getMoodle("BloodyTampon", playerNum):setValue(MLevel)

    MF.getMoodle("Leak", playerNum):setValue(MLevel)

    if MLevel < 0 then
        print("Resetting to .50")
        MLevel = .50
    else
        print("Decreasing by .10")
        MLevel = MLevel - .10
    end
end
Events.EveryOneMinute.Add(flipFlopDebug)

return RedDaysMoodles