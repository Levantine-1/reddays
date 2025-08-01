-- ISInsertTamponAction.lua
ISInsertTamponAction = ISBaseTimedAction:derive("ISInsertTamponAction")

local function getItemWithIDRecurse(inventory, id)
    for i = 0, inventory:getItems():size() - 1 do
        local item = inventory:getItems():get(i)
        if item:getID() == id then
            return item
        end
        if instanceof(item, "InventoryContainer") then
            local found = getItemWithIDRecurse(item:getInventory(), id)
            if found then return found end
        end
    end
    return nil
end

function onInsertTampon(player, args)
    if not player then
        --print("[RedDays] onInsertTampon: No player found")
        return
    end
    local modData = player:getModData()
    if not modData then
        --print("[RedDays] onInsertTampon: getModData failed")
        return
    end
    modData.ICdata = modData.ICdata or {}
    modData.ICdata.insertedTampon = {
        name = args.name,
        condition = args.condition,
        hygieneType = "Tampon",
        insertionHour = getGameTime():getWorldAgeHours()
    }
    local inventory = player:getInventory()
    if not inventory then return end
    local item = getItemWithIDRecurse(inventory, args.itemId)
    if not item then return end
    item:getContainer():Remove(item)
    player:transmitModData()
    local globalData = ModData.getOrCreate("RedDays")
    globalData[player:getUsername()] = modData.ICdata
    ModData.transmit("RedDays")
    --print("[RedDays] onInsertTampon: Saved to global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    local bd = player:getBodyDamage()
    if bd then
        local current = bd:getUnhappynessLevel()
        bd:setUnhappynessLevel(current + 0.0001)
    else
        --print("[RedDays] onInsertTampon: getBodyDamage failed")
    end
end

function ISInsertTamponAction:isValid()
    if not self.character or not self.item then
        --print("[RedDays] ISInsertTamponAction:isValid failed: character=", self.character, "item=", self.item)
        return false
    end
    local modData = self.character:getModData()
    if not modData then
        --print("[RedDays] ISInsertTamponAction:isValid failed: getModData failed")
        return false
    end
    modData.ICdata = modData.ICdata or {}
    local globalData = ModData.getOrCreate("RedDays")
    local username = self.character:getUsername()
    if globalData[username] then
        modData.ICdata = globalData[username]
        --print("[RedDays] ISInsertTamponAction:isValid: Loaded from global ModData, insertedTampon = ", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    end
    local inventory = self.character:getInventory()
    local valid = inventory and inventory:containsRecursive(self.item) and not modData.ICdata.insertedTampon
    if not valid then
        --print("[RedDays] ISInsertTamponAction:isValid failed: inventory=", inventory, "inventoryContains=", inventory and inventory:contains(self.item), "insertedTampon=", modData.ICdata.insertedTampon and modData.ICdata.insertedTampon.name or "nil")
    end
    return valid
end

function ISInsertTamponAction:start()
    self:setActionAnim("Loot")
end

function ISInsertTamponAction:perform()
    if not self:isValid() then
        --print("[RedDays] ISInsertTamponAction:perform aborted due to invalid state")
        self:forceStop()
        return
    end
    local args = {itemId = self.item:getID(), name = self.item:getName(), condition = self.item:getCondition()}
    if isClient() then
        sendClientCommand(self.character, "RedDays", "insertTampon", args)
        --print("[RedDays] sendClientCommand: insertTampon")
    else
        onInsertTampon(self.character, args)
    end
    self.character:Say("Inserted tampon.")
    self:forceComplete()
end

function ISInsertTamponAction:new(character, item, time)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.item = item
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = time or 100
    return o
end

if isServer() or not isClient() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module == "RedDays" and command == "insertTampon" then
            onInsertTampon(player, args)
        end
    end)
end