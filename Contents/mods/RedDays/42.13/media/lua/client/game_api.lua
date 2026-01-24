-- Keep game API calls here. The 42.12 to 42.13 update meant a lot of tracking down game api calls throughout the code
-- and moving them here to avoid issues with future updates.

zapi = zapi or {}

function zapi.getGameTime(parameter)
-- https://projectzomboid.com/modding/zombie/GameTime.html
    local gameTime = getGameTime()
    if gameTime[parameter] and type(gameTime[parameter]) == "function" then
        return gameTime[parameter](gameTime)
    end
    return nil
end

return zapi