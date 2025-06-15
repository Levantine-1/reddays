require "RedDays/cycle_manager"

local player
local function LoadPlayerData()
	player = getPlayer()
	modData = player:getModData()
	modData.ICdata = modData.ICdata or {}
	modData.ICdata.currentCycle = modData.ICdata.currentCycle or CycleManager.newCycle() -- Initialize the current cycle or generate a new one if it doesn't exist
end
Events.OnGameStart.Add(LoadPlayerData)

local function PrintStatus() -- Purely for debug purposes, will be removed in the future
    -- local cycle = modData.ICdata.currentCycle
    local cycle = CycleManager.newCycle() -- For testing purposes, we generate a new cycle every time this function is called
    print("================================== Generated menstrual cycle details: ==================================")
    print("Cycle start day: " .. cycle.cycle_start_day)
    print("Total expected menstrual cycle duration: " .. cycle.cycle_duration .. " days")
    print("Follicular phase start day: " .. cycle.cycle_start_day)
    print("Total Follicular phase duration: " .. cycle.follicular_duration .. " days")
    print("Red phase duration: " .. cycle.red_days_duration .. " days")
    print("Follicle stimulating phase start day: " .. cycle.follicle_stimulating_start_day)
    print("Follicle stimulating phase duration: " .. cycle.follicle_stimulating_duration .. " days")
    print("Ovulation day: " .. cycle.ovulation_day .. " days after the start of the cycle")
    print("Ovulation phase duration: " .. cycle.ovulation_duration .. " days")
    print("Luteal phase start day: " .. cycle.luteal_start_day)
    print("Luteal phase duration: " .. cycle.luteal_duration .. " days")

    local currentDay = getGameTime():getWorldAgeHours() / 24
    print("Current time in days: " .. currentDay)

    -- local currentPhase = CycleManager.getCurrentCyclePhase(cycle)
    -- print("Current cycle phase: " .. currentPhase)


end
Events.EveryTenMinutes.Add(PrintStatus)