ISDetachHygieneItemAction = ISBaseTimedAction:derive("ISDetachHygieneItemAction")

function ISDetachHygieneItemAction:isValid()
    return self.underwear and self.underwear:getModData().attachedHygiene ~= nil
end

function ISDetachHygieneItemAction:update()
end

function ISDetachHygieneItemAction:start()
    self:setActionAnim("Loot")
end

function ISDetachHygieneItemAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISDetachHygieneItemAction:perform()
    if self.underwear then
        local uwModData = self.underwear:getModData()
        local data = uwModData.attachedHygiene
        if data then
			local baseType = data.fullType:match("^(.-)$") or data.fullType  -- Keep as-is, assuming it's the full type like "RedDays.Pad"
			local itemType = baseType:gsub("^RedDays%.", "")  -- Extract "Pad" or "PantyLiner"
			local baseName = data.name:match("^(.-) %(") or data.name
			local isPantyLiner = (baseName == "Panty Liner")
			local threshold = isPantyLiner and 5 or 9
			local usedType
			local setCustomName = false
			if data.name:find("Dirty") then
				usedType = itemType .. "_Dirty"
			else
				if data.condition >= threshold then
					usedType = itemType  -- Use base for Slightly Used
					setCustomName = true
				else
					usedType = itemType .. "_Bloody"
				end
			end
			-- Validate item exists
			local usedItem
			local fullUsedType = "RedDays." .. usedType
			if ScriptManager.instance:getItem(fullUsedType) then
				usedItem = self.character:getInventory():AddItem(fullUsedType)
			else
				-- Fallback to base item
				usedItem = self.character:getInventory():AddItem(data.fullType)
				if not usedItem then
					self.character:Say("Couldn't return the hygiene item.")
					print("Error: Item type " .. fullUsedType .. " not found, tried fallback " .. data.fullType)
				end
			end
			if usedItem then
				self.character:Say("Detached hygiene item.")
				usedItem:setCondition(data.condition or 0)  -- Preserve condition
				if setCustomName then
					usedItem:setName(baseName .. " (Slightly Used)")
				end
			end
            uwModData.attachedHygiene = nil
            self.underwear:setTooltip(nil)
        end
    end
    ISBaseTimedAction.perform(self)
end

function ISDetachHygieneItemAction:new(character, underwear, time)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = time
    o.underwear = underwear
    return o
end