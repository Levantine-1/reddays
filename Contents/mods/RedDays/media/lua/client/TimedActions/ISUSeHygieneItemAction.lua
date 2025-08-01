ISUseHygieneItemAction = ISBaseTimedAction:derive("ISUseHygieneItemAction")

function ISUseHygieneItemAction:isValid()
    if not self.character:isFemale() and not SandboxVars.RedDays.affectsAllGenders then return false end
    if self.item:getFullType() == "RedDays.Tampon" then return false end
    local container = self.item:getContainer()
    return self.item and container and container:contains(self.item) and self.item:getCondition() > 0
end

function ISUseHygieneItemAction:update()
end

function ISUseHygieneItemAction:start()
    self:setActionAnim("Loot")
    self.underwear = self.character:getWornItem("UnderwearBottom")
    if not self.underwear then
        self.character:Say("I'm not wearing underwear.")
        self:forceStop()
    end
end

function ISUseHygieneItemAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISUseHygieneItemAction:perform()
    if self.underwear then
        local uwModData = self.underwear:getModData()
        if not uwModData.attachedHygiene then
            local baseName = self.item:getName():match("^(.-) %(") or self.item:getName()
            local hygieneType
            local maxCondition = 10
            if baseName == "Panty Liner" then
                hygieneType = "PantyLiner"
                maxCondition = 6
            elseif baseName == "Sanitary Pad" then
                hygieneType = "Pad"
            else
                hygieneType = "Unknown"
            end
            uwModData.attachedHygiene = {
                fullType = self.item:getFullType(),
                name = self.item:getName(),
                condition = maxCondition,
                hygieneType = hygieneType
            }
            self.underwear:setTooltip("Attached: " .. uwModData.attachedHygiene.name .. " Condition: " .. uwModData.attachedHygiene.condition)
            self.item:getContainer():Remove(self.item)
            self.character:Say("Attached hygiene item.")
        end
    end
    ISBaseTimedAction.perform(self)
end

function ISUseHygieneItemAction:new(character, item, time)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = time
    o.item = item
    return o
end