-- BodyLocations are registered in registries.lua using ItemBodyLocation.register()
-- But we still need to add them to the Human body location group

local group = BodyLocations.getGroup("Human")

local hygieneLocation = ItemBodyLocation.get(ResourceLocation.of("RedDays:HygieneItem"))
if hygieneLocation then
    group:getOrCreateLocation(hygieneLocation)
else
    print("WARNING: RedDays - Could not get HygieneItem body location - ItemBodyLocation.get() returned nil")
end