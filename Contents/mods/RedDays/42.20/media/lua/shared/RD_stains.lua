-- Blood/dirt stain spreading for body and clothing.
--
-- Shared so the client (RD_hygiene_manager.lua) and the server (RD_server_commands.lua,
-- Commands.applyStains) run the exact same spread, each on its own copy of the player. Body and
-- clothing visuals are server-authoritative in MP: the hosted self-test showed stains made only on
-- the client never reached the server.
--
-- Stains spread from the groin outward: groin -> both thighs -> both shins -> both feet.

RD_Stains = RD_Stains or {}

-- Each tier is a group of body parts that stain together.
RD_Stains.TIERS = {
    { BloodBodyPartType.Groin },
    { BloodBodyPartType.UpperLeg_L, BloodBodyPartType.UpperLeg_R },
    { BloodBodyPartType.LowerLeg_L, BloodBodyPartType.LowerLeg_R },
    { BloodBodyPartType.Foot_L, BloodBodyPartType.Foot_R },
}
RD_Stains.INCREMENT = 0.01  -- added per call
RD_Stains.MAX = 1.0

local function coversPart(item, bodyPart)
    local clothingType = item:getBloodClothingType()
    if not clothingType then return false end
    local parts = BloodClothingType.getCoveredParts(clothingType)
    if not parts then return false end
    for i = 0, parts:size() - 1 do
        if parts:get(i) == bodyPart then return true end
    end
    return false
end

-- Stains the player's body over tiers 1..maxTier, plus any worn clothing covering those parts,
-- never above maxLevel. Returns the garments it touched, so the server can sync them.
function RD_Stains.apply(player, blood, dirt, maxTier, maxLevel)
    local stained = {}
    if not player then return stained end
    local visual = player:getHumanVisual()
    local wornItems = player:getWornItems()
    if not visual or not wornItems then return stained end

    maxTier = math.min(maxTier or #RD_Stains.TIERS, #RD_Stains.TIERS)
    maxLevel = maxLevel or RD_Stains.MAX
    if maxTier <= 0 then return stained end

    local seen = {}
    for tierIndex = 1, maxTier do
        for _, bodyPart in ipairs(RD_Stains.TIERS[tierIndex]) do
            if blood then
                local current = visual:getBlood(bodyPart)
                if current < maxLevel then
                    visual:setBlood(bodyPart, math.min(maxLevel, current + RD_Stains.INCREMENT))
                end
            end
            if dirt then
                local current = visual:getDirt(bodyPart)
                if current < maxLevel then
                    visual:setDirt(bodyPart, math.min(maxLevel, current + RD_Stains.INCREMENT))
                end
            end

            for i = 0, wornItems:size() - 1 do
                local entry = wornItems:get(i)
                local item = entry and entry:getItem()
                if item and instanceof(item, "Clothing") and coversPart(item, bodyPart) then
                    if blood then
                        local current = item:getBlood(bodyPart)
                        if current < maxLevel then
                            item:setBlood(bodyPart, math.min(maxLevel, current + RD_Stains.INCREMENT))
                        end
                    end
                    if dirt then
                        local current = item:getDirt(bodyPart)
                        if current < maxLevel then
                            item:setDirt(bodyPart, math.min(maxLevel, current + RD_Stains.INCREMENT))
                        end
                    end
                    if not seen[item] then
                        seen[item] = true
                        stained[#stained + 1] = item
                    end
                end
            end
        end
    end
    return stained
end

return RD_Stains
