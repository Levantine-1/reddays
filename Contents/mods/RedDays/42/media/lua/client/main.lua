require "RedDays/cycle_manager"
require "RedDays/effects_manager"
require "RedDays/hygiene_manager"

local function LoadPlayerData()
	local player = getPlayer()
	modData = player:getModData()
	modData.ICdata = modData.ICdata or {}
    modData.ICdata.currentCycle = modData.ICdata.currentCycle or CycleManager.newCycle() -- Initialize the current cycle or generate a new one if it doesn't exist
    if not CycleManager.isCycleValid(modData.ICdata.currentCycle) then
        print("Cycle data structure mismatch! This could be due to a mod update. Regenerating cycle...")
        modData.ICdata.currentCycle = CycleManager.newCycle()
    end
end
Events.OnGameStart.Add(LoadPlayerData)

local function ResetCycleData()
    modData.ICdata.currentCycle = CycleManager.newCycle()
    EffectsManager.resetEffects()
    print("Menstrual cycle data has been reset for new player.")
end
Events.OnCreatePlayer.Add(ResetCycleData)

local function PrintStatus()
    local cycle = modData.ICdata.currentCycle
    print("================================== Generated menstrual cycle details: ==================================")
    local currentDay = getGameTime():getWorldAgeHours() / 24
    print("Current time in days: " .. currentDay)

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

    local days_into_cycle = currentDay - cycle.cycle_start_day
    print("Days into current cycle: " .. days_into_cycle)

    local currentPhase = CycleManager.getCurrentCyclePhase(cycle)
    print("Current cycle phase: " .. currentPhase)
    print("==========================================================================================")
end
Events.EveryHours.Add(PrintStatus)

local function main()
    local cycle = modData.ICdata.currentCycle
    if CycleManager.getCurrentCyclePhase(cycle) == "endOfCycle" then
        print("End of cycle reached, generating a new cycle...")
        modData.ICdata.currentCycle = CycleManager.newCycle()
        cycle = modData.ICdata.currentCycle
    end
    EffectsManager.determineEffects(cycle) -- Apply effects based on the current cycle phase
end
Events.EveryTenMinutes.Add(main)
