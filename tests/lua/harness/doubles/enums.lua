-- Stand-ins for the PZ enum/registry globals the mod indexes.
-- Each member is a distinct table so identity comparison behaves like the real
-- Java enum objects (the mod passes these around as opaque handles).

local M = {}

local function enum(typeName, names, extra)
    local e = {}
    for _, name in ipairs(names) do
        local member = { __enum = typeName, name = name }
        if extra then extra(member) end
        setmetatable(member, { __tostring = function(s) return typeName .. "." .. s.name end })
        e[name] = member
    end
    return e
end
M.enum = enum

function M.build()
    local enums = {}

    -- CharacterStat.TEMPERATURE is queried for its bounds during TSS fever
    -- calibration. The mod itself logs these at runtime because the real values
    -- were uncertain; 0..1 normalised with a 0.5 default is the working
    -- assumption here, and tests that care can override it.
    enums.CharacterStat = enum("CharacterStat", {
        "ANGER", "ENDURANCE", "FATIGUE", "HUNGER",
        "THIRST", "SICKNESS", "UNHAPPINESS", "TEMPERATURE",
    }, function(member)
        member.min, member.max, member.default = 0, 1, 0.5
        function member:getMinimumValue() return self.min end
        function member:getMaximumValue() return self.max end
        function member:getDefaultValue() return self.default end
    end)

    enums.CharacterTrait = enum("CharacterTrait", {
        "VERY_UNDERWEIGHT", "UNDERWEIGHT", "EMACIATED", "OVERWEIGHT", "OBESE",
    })

    enums.BodyPartType = enum("BodyPartType", {
        "Torso_Upper", "Torso_Lower", "Groin",
        "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R",
        "Foot_L", "Foot_R", "Hand_L", "Hand_R", "Head", "Neck",
    })

    enums.BloodBodyPartType = enum("BloodBodyPartType", {
        "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R",
        "Foot_L", "Foot_R", "Torso_Upper", "Torso_Lower",
    })

    -- Clothing items report a BloodClothingType; the static getCoveredParts()
    -- maps one to the BloodBodyPartTypes it covers.
    enums.BloodClothingType = enum("BloodClothingType", {
        "Trousers", "Shirt", "Jacket", "Shoes", "FullSuit", "Underwear", "Skirt",
    })
    local coverage = {
        Trousers  = { "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R" },
        Skirt     = { "Groin", "UpperLeg_L", "UpperLeg_R" },
        Underwear = { "Groin" },
        Shirt     = { "Torso_Upper" },
        Jacket    = { "Torso_Upper", "Torso_Lower" },
        Shoes     = { "Foot_L", "Foot_R" },
        FullSuit  = { "Groin", "Torso_Upper", "Torso_Lower", "UpperLeg_L", "UpperLeg_R" },
    }
    function enums.BloodClothingType.getCoveredParts(bct)
        local names = bct and coverage[bct.name] or {}
        local list = {}
        for _, n in ipairs(names) do list[#list + 1] = enums.BloodBodyPartType[n] end
        return {
            size = function() return #list end,
            get = function(_, i) return list[i + 1] end,   -- Java lists are 0-based
        }
    end

    -- ItemBodyLocation.get(ResourceLocation.of("RedDays:HygieneItem"))
    local locations = {}
    enums.ResourceLocation = {
        of = function(str) return { __resource = true, id = str } end,
    }
    enums.ItemBodyLocation = {
        get = function(resource)
            if not resource or not resource.id then return nil end
            locations[resource.id] = locations[resource.id]
                or { __bodyLocation = true, id = resource.id }
            return locations[resource.id]
        end,
        register = function(id) return enums.ItemBodyLocation.get({ id = id }) end,
    }

    -- shared/definitions/BodyLocations.lua touches this at load time.
    enums.BodyLocations = {
        getGroup = function(_)
            return {
                getOrCreateLocation = function(_, name)
                    return { __bodyLocation = true, id = name }
                end,
            }
        end,
    }

    enums.MoodleType = enum("MoodleType", { "Endurance", "Sick", "Pain" })

    return enums
end

return M
