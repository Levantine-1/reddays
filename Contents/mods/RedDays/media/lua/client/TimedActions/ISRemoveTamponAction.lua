ISRemoveTamponAction = ISBaseTimedAction:derive("ISRemoveTamponAction")

function ISRemoveTamponAction:isValid()
    return self.character:getModData().ICdata.insertedTampon ~= nil
end

function ISRemoveTamponAction:start()
    self:setActionAnim("Loot") -- Added for animation
end

function ISRemoveTamponAction:perform()
    local modData = self.character:getModData()
    local tamponData = modData.ICdata.insertedTampon
    local args = {condition = tamponData.condition}
    if isClient() then
        sendClientCommand(self.character, "RedDays", "removeTampon", args)
    else
        local usedTampon = self.character:getInventory():AddItem("RedDays.Tampon")
        local baseName = "Used Tampon"
        local condition = tamponData.condition or 0
        if condition >= 8 then
            usedTampon:setName(baseName .. " (Slightly Used)")
        elseif condition >= 4 then
            usedTampon:setName(baseName .. " (Used)")
        else
            usedTampon:setName(baseName .. " (Saturated)")
        end
        usedTampon:setCondition(condition)
        modData.ICdata.insertedTampon = nil
        self.character:transmitModData()
        self.character:Say("Removed tampon.")
    end
    ISBaseTimedAction.perform(self)
end

function ISRemoveTamponAction:new(character, time)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = time or 100  -- Adjust time as needed
    return o
end

if isServer() or not isClient() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module == "RedDays" and command == "removeTampon" then
            local modData = player:getModData()
            local tamponData = modData.ICdata.insertedTampon
            if tamponData then
                local usedTampon = player:getInventory():AddItem("RedDays.Tampon")
                local baseName = "Used Tampon"
                local condition = args.condition or 0
                if condition >= 8 then
                    usedTampon:setName(baseName .. " (Slightly Used)")
                elseif condition >= 4 then
                    usedTampon:setName(baseName .. " (Used)")
                else
                    usedTampon:setName(baseName .. " (Saturated)")
                end
                usedTampon:setCondition(condition)
                modData.ICdata.insertedTampon = nil
                player:transmitModData()
                player:Say("Removed tampon.")
            end
        end
    end)
end