-- InventoryItem / Clothing / Literature double.

local M = {}

local nextId = 0

-- opts: type, fullType, name, condition, conditionMax, bodyLocation,
--       bloodClothingType, isContainer, isClothing
function M.new(opts)
    opts = opts or {}
    nextId = nextId + 1

    local item = {
        __item = true,
        __isClothing = opts.isClothing ~= false,
        id = opts.id or nextId,
        type = opts.type or "Tampon",
        fullType = opts.fullType or ("RedDays." .. (opts.type or "Tampon")),
        name = opts.name or opts.type or "Tampon",
        condition = opts.condition or 10,
        conditionMax = opts.conditionMax or 10,
        blood = opts.blood or 0,
        dirt = opts.dirt or 0,
        bodyLocation = opts.bodyLocation,
        bloodClothingType = opts.bloodClothingType,
        modData = {},
        pages = {},
        -- Records every mutation so tests can assert on the sequence a tick produced.
        history = {},
    }

    local function record(what, value)
        item.history[#item.history + 1] = { what = what, value = value }
    end

    function item:getID() return self.id end
    function item:getType() return self.type end
    function item:getFullType() return self.fullType end
    function item:getName() return self.name end
    function item:setName(v) self.name = v; record("setName", v) end
    function item:getCondition() return self.condition end
    function item:setCondition(v) self.condition = v; record("setCondition", v) end
    function item:getConditionMax() return self.conditionMax end
    function item:getBlood() return self.blood end
    function item:setBlood(v) self.blood = v; record("setBlood", v) end
    function item:getDirt() return self.dirt end
    function item:setDirt(v) self.dirt = v; record("setDirt", v) end
    function item:getBloodClothingType() return self.bloodClothingType end
    function item:getModData() return self.modData end

    function item:isBodyLocation(loc)
        if not loc or not self.bodyLocation then return false end
        return self.bodyLocation == loc or self.bodyLocation == loc.id
    end

    function item:IsInventoryContainer() return opts.isContainer == true end
    function item:getInventory() return self.inventory end

    -- Literature (the period-tracker journal)
    function item:seePage(pageNum) return self.pages[pageNum] end
    function item:addPage(pageNum, data) self.pages[pageNum] = data end
    function item:getNumberOfPages() return #self.pages end

    return item
end

-- Reset between tests so item IDs are stable and comparable across runs.
function M.resetIds()
    nextId = 0
end

return M
