-- This API abstraction layer was created in response to how confusing it was
-- to update this mod from B42.12 to B42.13

zapi = zapi or {}

-- ================= GAME TIME =================

-- https://projectzomboid.com/modding/zombie/GameTime.html
function zapi.getGameTime(parameter)
    local gameTime = getGameTime()
    if gameTime[parameter] and type(gameTime[parameter]) == "function" then
        return gameTime[parameter](gameTime)
    end
    return nil
end

-- ================= PLAYER =================

-- https://projectzomboid.com/modding/zombie/characters/IsoPlayer.html#getPlayer()
function zapi.getPlayer()
    return getPlayer()
end

-- https://projectzomboid.com/modding/zombie/characters/IsoPlayer.html#getPlayerNum()
function zapi.getPlayerNum()
    return getPlayer():getPlayerNum()
end

-- https://projectzomboid.com/modding/zombie/characters/IsoGameCharacter.html#isFemale()
function zapi.isFemale()
    return getPlayer():isFemale()
end

-- https://projectzomboid.com/modding/zombie/characters/IsoGameCharacter.html#getModData()
function zapi.getModData()
    return getPlayer():getModData()
end

-- https://projectzomboid.com/modding/zombie/characters/IsoGameCharacter.html#getWornItems()
function zapi.getWornItems()
    return getPlayer():getWornItems()
end

-- ================= BODY DAMAGE =================

-- https://projectzomboid.com/modding/zombie/characters/IsoGameCharacter.html#getBodyDamage()
function zapi.getBodyDamage()
    return getPlayer():getBodyDamage()
end

-- https://projectzomboid.com/modding/zombie/characters/BodyDamage/BodyDamage.html#getBodyPart(zombie.characters.BodyDamage.BodyPartType)
function zapi.getBodyPart(bodyPartType)
    return getPlayer():getBodyDamage():getBodyPart(bodyPartType)
end

-- ================= BODY LOCATIONS =================

-- https://projectzomboid.com/modding/zombie/inventory/ItemBodyLocation.html#get(zombie.asset.ResourceLocation)
function zapi.getBodyLocation(locationString)
    -- locationString format: "ModName:LocationName" e.g. "RedDays:HygieneItem"
    return ItemBodyLocation.get(ResourceLocation.of(locationString))
end

-- https://projectzomboid.com/modding/zombie/inventory/ItemBodyLocation.html
-- https://projectzomboid.com/modding/zombie/inventory/ItemContainer.html#getItem(zombie.inventory.ItemBodyLocation)
function zapi.getWornItemAtLocation(locationString)
    local wornItems = getPlayer():getWornItems()
    local bodyLocation = zapi.getBodyLocation(locationString)
    if not bodyLocation then
        return nil
    end
    return wornItems:getItem(bodyLocation)
end

-- https://projectzomboid.com/modding/zombie/inventory/InventoryItem.html#isBodyLocation(zombie.inventory.ItemBodyLocation)
function zapi.isItemAtBodyLocation(item, locationString)
    local bodyLocation = zapi.getBodyLocation(locationString)
    if not bodyLocation then
        return false
    end
    return item:isBodyLocation(bodyLocation)
end

return zapi