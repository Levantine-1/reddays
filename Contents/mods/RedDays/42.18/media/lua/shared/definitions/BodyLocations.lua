-- BodyLocations are registered in registries.lua using ItemBodyLocation.register()
-- But we still need to add them to the Human body location group

local group = BodyLocations.getGroup("Human")

group:getOrCreateLocation("RedDays:HygieneItem")