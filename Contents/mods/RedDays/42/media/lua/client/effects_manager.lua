EffectsManager = {}

function EffectsManager.applyCycleEffects(cycle)
    local current_phase = CycleManager.getCurrentCyclePhase(cycle)
    print("Applying effects for phase: " .. current_phase)

    if current_phase == "redPhase" then
        -- Apply effects for red phase
    elseif current_phase == "follicularPhase" then
        -- Apply effects for follicular phase
    elseif current_phase == "ovulationPhase" then
        -- Apply effects for ovulation phase
    elseif current_phase == "lutealPhase" then
        -- Apply effects for luteal phase
    elseif current_phase == "endOfCycle" then
        -- Apply effects for end of cycle
    end
end

function EffectsManager.rampTo(cycle)
    local current_phase = CycleManager.getCurrentCyclePhase(cycle)

    local player = getPlayer()
    local bodyDamage = player:getBodyDamage()
    local lowerTorso = bodyDamage:getBodyPart(BodyPartType.Torso_Lower)
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    if current_phase == "redPhase" then
        print("Applying effects")
        groin:setBleeding(true)
        groin:setStiffness(100)
        lowerTorso:setStiffness(100)
    end
        
    -- TODO: groin strain and bleeding, lower torso strain
    -- Discomfort
    -- Reduce Stamina and Fatigue
end
-- Events.EveryOneMinute.Add(EffectsManager.rampTo)


return EffectsManager

