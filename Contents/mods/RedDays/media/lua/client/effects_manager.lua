require "cycle_manager"
require "hygiene_manager"

EffectsManager = {}

local pill_recently_taken = false
local function takePillsStiffness()
    local player = getPlayer() -- Added for player:Say
    if pill_effect_counter < 36 then
        pill_effect_counter = pill_effect_counter + 1
        modData.ICdata.pill_effect_counter = pill_effect_counter
    else
        Events.EveryTenMinutes.Remove(takePillsStiffness)
        pill_effect_active = false
        modData.ICdata.pill_effect_active = pill_effect_active
        player:Say("My painkiller's worn off.") -- Replaced print
        return
    end
end

local function LoadPlayerData()
	local player = getPlayer()
	if not SandboxVars.RedDays.affectsAllGenders and not player:isFemale() then return end
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    pill_effect_counter = modData.ICdata.pill_effect_counter or 0
    pill_effect_active = modData.ICdata.pill_effect_active or false
    if pill_effect_active then
        Events.EveryTenMinutes.Add(takePillsStiffness)
    end
end
Events.OnLoad.Add(LoadPlayerData)

local o_ISTakePillAction_perform = ISTakePillAction.perform
function ISTakePillAction:perform()
    if self.item:getFullType() == "Base.Pills" then
        pill_effect_counter = 0
        pill_effect_active = true
        modData.ICdata.pill_effect_active = pill_effect_active
        pill_recently_taken = true
        Events.EveryTenMinutes.Add(takePillsStiffness)
        self.character:Say("Took a painkiller, feeling a bit better.") -- Replaced print
    end
    o_ISTakePillAction_perform(self)
end

local stat_Adjustment_isEnabled = false
local function stat_Adjustment()
    local player = getPlayer()
    local stats = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local modData = player:getModData()
    local cycle = modData.ICdata.currentCycle
    local isTamponInserted = modData.ICdata.insertedTampon ~= nil

    if not HygieneManager.consumeHygieneProduct() then
        bodyDamage:setUnhappynessLevel(bodyDamage:getUnhappynessLevel() + 1)
        local currentHour = getGameTime():getWorldAgeHours()
        modData.ICdata.lastBloodHour = modData.ICdata.lastBloodHour or 0
        if modData.ICdata.redPhaseStartHour and currentHour - modData.ICdata.redPhaseStartHour >= modData.ICdata.redPhaseGraceHours and currentHour - modData.ICdata.lastBloodHour >= 1 then
            if isTamponInserted then
                -- Internal penalty for saturated tampon
                if SandboxVars.RedDays.enableTamponRisks then
                    bodyDamage:setFoodSicknessLevel(bodyDamage:getFoodSicknessLevel() + 5)
                    player:Say("I feel sick... better remove the tampon.")
                end
            else
                -- Existing external bleeding
                local BloodBodyPartType = BloodBodyPartType
                local part = BloodBodyPartType.Groin
                player:addBlood(part, false, false, true)
				
				local wornItems = player:getWornItems()
				for i = 0, wornItems:size() - 1 do
					local item = wornItems:get(i):getItem()
					if item and instanceof(item, "Clothing") and (item:getBodyLocation() == "Bottoms" or item:getBodyLocation() == "UnderwearBottom") then
						item:setDirtyness(item:getDirtyness() + 0.5)
					end
				end
				
                player:Say("I need to clean up...") -- Verbal cue for hygiene issue
            end
            modData.ICdata.lastBloodHour = currentHour
        end
    end

    if pill_effect_active then
        if pill_recently_taken then
            if bodyDamage:getUnhappynessLevel() > 22.5 then
                bodyDamage:setUnhappynessLevel(22.5)
            end
            pill_recently_taken = false
        end
        return
    end

    local current_unhappiness = bodyDamage:getUnhappynessLevel()
    if current_unhappiness < cycle.stiffness_target then
        bodyDamage:setUnhappynessLevel(math.max(0, current_unhappiness + (cycle.stiffness_increment * 5)))
    end

    local current_fatigue = stats:getFatigue()
    stats:setFatigue(math.min(1, current_fatigue + (cycle.fatigue_increment * 5)))

    local current_endurance = stats:getEndurance()
    stats:setEndurance(math.min(1, current_endurance - (cycle.endurance_decrement * 5)))

    bodyDamage:setUnhappynessLevel(math.max(0, bodyDamage:getUnhappynessLevel() + 0.25))
end

-- New: Check for overdue tampon (TSS risk)
local function checkTamponOverdue()
    local player = getPlayer()
    local modData = player:getModData()
    local bodyDamage = player:getBodyDamage()
    if modData.ICdata.insertedTampon then
        local currentHour = getGameTime():getWorldAgeHours()
        local hoursInserted = currentHour - modData.ICdata.insertedTampon.insertionHour
        if hoursInserted > 8 and SandboxVars.RedDays.enableTamponRisks then
            -- Incremental sickness per hour overdue
            local overdueHours = math.floor(hoursInserted - 8)
            bodyDamage:setFoodSicknessLevel(bodyDamage:getFoodSicknessLevel() + overdueHours * 1)
            if overdueHours > 0 then
                player:Say("The tampon's been in too long... feeling unwell.")
            end
        end
    end
end
Events.EveryHours.Add(checkTamponOverdue)

local consumingDischargeItem = false
local function consumeDischargeProduct()
    consumingDischargeItem = true
    getPlayer():Say("Used a hygiene product for discharge.") -- Replaced print
    return HygieneManager.consumeDischargeProduct()
end

function EffectsManager.determineEffects(cycle)
    if not SandboxVars.RedDays.affectsAllGenders then
        local player = getPlayer()
        if not player:isFemale() then
            if stat_Adjustment_isEnabled then
                Events.EveryTenMinutes.Remove(stat_Adjustment)
                player:Say("No cycle effects for me.") -- Replaced print
            end
            return
        end
    end

    local current_phase = CycleManager.getCurrentCyclePhase(cycle)
    local player = getPlayer() -- Added for player:Say
    if current_phase == "redPhase" then
        if not stat_Adjustment_isEnabled then
            player:Say("My period's started, feeling rough.") -- Replaced print
            Events.EveryTenMinutes.Add(stat_Adjustment)
            stat_Adjustment_isEnabled = true
        end
        if consumingDischargeItem then
            player:Say("No need for discharge products during my period.") -- Replaced print
            Events.EveryDays.Remove(consumeDischargeProduct)
            consumingDischargeItem = false
        end
    else
        if stat_Adjustment_isEnabled then
            Events.EveryTenMinutes.Remove(stat_Adjustment)
            player:Say("My period's over, feeling better.") -- Replaced print
            stat_Adjustment_isEnabled = false
        end
        if not consumingDischargeItem then
            player:Say("Using a product for discharge.") -- Replaced print
            Events.EveryDays.Add(consumeDischargeProduct)
            consumingDischargeItem = true
        end
    end
end

function EffectsManager.resetEffects()
    local player = getPlayer()
    modData = player:getModData()
    modData.ICdata = modData.ICdata or {}
    stat_Adjustment_isEnabled = false
    modData.ICdata.pill_effect_counter = 0
    modData.ICdata.pill_effect_active = false
    modData.ICdata.insertedTampon = nil
    Events.EveryDays.Remove(consumeDischargeProduct)
    Events.EveryTenMinutes.Remove(stat_Adjustment)
    Events.EveryTenMinutes.Remove(takePillsStiffness)
    Events.EveryHours.Remove(checkTamponOverdue)
end

return EffectsManager