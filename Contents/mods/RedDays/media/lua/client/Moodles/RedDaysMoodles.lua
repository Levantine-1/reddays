-- file: RedDaysMoodles.lua
local success, err = pcall(require, "MF_ISMoodle")
if not success then print("[RedDays] Failed to require MF_ISMoodle: ", err) end

MF.createMoodle("Menstruation")
MF.createMoodle("HygieneIssue")
MF.createMoodle("TamponIssue")

function updateMoodles()
    local player = getPlayer()
    if not player or (not SandboxVars.RedDays.affectsAllGenders and not player:isFemale()) then
        --print("[RedDays] updateMoodles: No player or gender check failed")
        return
    end
    local modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    local globalData = ModData.getOrCreate("RedDays")
    local username = player:getUsername()
    if globalData[username] then
        modData.ICdata = globalData[username]
        --print("[RedDays] updateMoodles: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    end
    local cycle = modData.ICdata.currentCycle
    if not cycle then
        --print("[RedDays] updateMoodles: No cycle data")
        return
    end
    local current_phase = CycleManager and CycleManager.getCurrentCyclePhase(cycle) or "unknown"
    
    local underwear = player:getWornItem("UnderwearBottom")
    local modDataUnderwear = underwear and underwear:getModData()
    local attachedHygiene = modDataUnderwear and modDataUnderwear.attachedHygiene
    local condition = attachedHygiene and attachedHygiene.condition
    local tamponData = modData.ICdata.insertedTampon
    local tamponCondition = tamponData and tamponData.condition
    
    local hygieneMoodle = MF.getMoodle("HygieneIssue", player:getPlayerNum())
    if current_phase == "redPhase" then
        local hasProtection = tamponData or attachedHygiene
        if not hasProtection then
            hygieneMoodle:setValue(0.4)
        elseif attachedHygiene then
            if not condition or condition == nil then
                hygieneMoodle:setValue(0.4)
            else
                local neutralThresh, partialThresh, moderateThresh = 6, 4, 2
                if attachedHygiene.hygieneType == "PantyLiner" then
                    neutralThresh, partialThresh, moderateThresh = 4, 3, 2
                end
                if condition >= neutralThresh then
                    hygieneMoodle:setValue(0.5)
                elseif condition >= partialThresh then
                    hygieneMoodle:setValue(0.3)
                elseif condition >= moderateThresh then
                    hygieneMoodle:setValue(0.2)
                else
                    hygieneMoodle:setValue(0.1)
                end
            end
        else
            hygieneMoodle:setValue(0.5)
        end
    else
        hygieneMoodle:setValue(0.5)
    end
    
    local tamponMoodle = MF.getMoodle("TamponIssue", player:getPlayerNum())
    if tamponData then
        if not tamponCondition then
            tamponMoodle:setValue(0.5)
        else
            if tamponCondition >= 8 then
                tamponMoodle:setValue(0.4)
            elseif tamponCondition >= 6 then
                tamponMoodle:setValue(0.3)
            elseif tamponCondition >= 4 then
                tamponMoodle:setValue(0.2)
            else
                tamponMoodle:setValue(0.1)
            end
        end
    else
        tamponMoodle:setValue(0.5)
    end
    
    local menstruationMoodle = MF.getMoodle("Menstruation", player:getPlayerNum())
    if current_phase == "redPhase" then
        local effectiveCondition = tamponCondition or condition
        if effectiveCondition == nil or effectiveCondition <= 2 then
            menstruationMoodle:setValue(0.4)
        else
            menstruationMoodle:setValue(0.6)
        end
    else
        menstruationMoodle:setValue(0.5)
    end
    --print("[RedDays] updateMoodles: tamponMoodle set to ", tamponMoodle:getValue())
end

local initTicks = 0
function InitializeMoodles()
    local player = getPlayer()
    if not player then
        initTicks = initTicks + 1
        if initTicks > 100 then
            --print("[RedDays] InitializeMoodles: No player after 100 ticks, aborting")
            Events.OnTick.Remove(InitializeMoodles)
            return
        end
        --print("[RedDays] InitializeMoodles: No player yet, retrying... (tick " .. initTicks .. ")")
        return
    end
    updateMoodles()
    --print("[RedDays] InitializeMoodles: Moodles initialized")
    Events.OnTick.Remove(InitializeMoodles)
end
Events.OnGameStart.Add(function() Events.OnTick.Add(InitializeMoodles) end)

Events.OnPlayerUpdate.Add(updateMoodles)