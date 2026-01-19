local group = BodyLocations.getGroup("Human")
local bodyLocation = BodyLocation.new(group, "HygieneItem")
group:getAllLocations():add(bodyLocation)