-- InventoryItem / Clothing / Literature double.

local M = {}

local nextId = 0

-- opts: type, fullType, name, condition, conditionMax, bodyLocation,
--       bloodClothingType, isContainer, isClothing, tags (array of strings),
--       isFood (marks it as a Food instance for instanceof(item, "Food"))
function M.new(opts)
    opts = opts or {}
    nextId = nextId + 1

    local tags = {}
    for _, t in ipairs(opts.tags or {}) do tags[t] = true end

    local item = {
        __item = true,
        __isClothing = opts.isClothing ~= false,
        __isFood = opts.isFood == true,
        id = opts.id or nextId,
        type = opts.type or "Tampon",
        fullType = opts.fullType or ("RedDays." .. (opts.type or "Tampon")),
        name = opts.name or opts.type or "Tampon",
        condition = opts.condition or 10,
        conditionMax = opts.conditionMax or 10,
        blood = opts.blood or 0,
        dirt = opts.dirt or 0,
        -- InventoryItem.itemHeat: 1.0 is ambient, above that is hot. Engine-side it only ticks
        -- for items carrying a FluidContainer component (InventoryItem.update, confirmed via
        -- bytecode), so the double keeps the two together.
        itemHeat = opts.itemHeat or 1.0,
        fluidAmount = opts.fluidAmount,
        bodyLocation = opts.bodyLocation,
        bloodClothingType = opts.bloodClothingType,
        modData = {},
        pages = {},
        tags = tags,
        extraItems = {},   -- Food:getExtraItems() -- ingredients folded in via evolved recipes
        spices = {},       -- Food:getSpices() -- minor/spice ingredients
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
    -- Clothing:getBlood(BloodBodyPartType) / setBlood(BloodBodyPartType, value) are per body
    -- part, which is how RD_hygiene_manager stains clothing. The no-part forms keep a
    -- whole-item value.
    item.partBlood, item.partDirt = {}, {}
    function item:getBlood(part)
        if part ~= nil then return self.partBlood[part] or 0 end
        return self.blood
    end
    function item:setBlood(a, b)
        if b ~= nil then
            self.partBlood[a] = b
            record("setBlood", { part = a, value = b })
        else
            self.blood = a
            record("setBlood", a)
        end
    end
    function item:getDirt(part)
        if part ~= nil then return self.partDirt[part] or 0 end
        return self.dirt
    end
    function item:setDirt(a, b)
        if b ~= nil then
            self.partDirt[a] = b
            record("setDirt", { part = a, value = b })
        else
            self.dirt = a
            record("setDirt", a)
        end
    end
    function item:getBloodClothingType() return self.bloodClothingType end
    function item:getModData() return self.modData end

    function item:getItemHeat() return self.itemHeat end
    function item:setItemHeat(v)
        self.itemHeat = v
        record("setItemHeat", v)
    end

    function item:getFluidContainer()
        if self.fluidAmount == nil then return nil end
        local owner = self
        return {
            getAmount = function() return owner.fluidAmount end,
            isEmpty = function() return (owner.fluidAmount or 0) <= 0 end,
        }
    end

    function item:isBodyLocation(loc)
        if not loc or not self.bodyLocation then return false end
        return self.bodyLocation == loc or self.bodyLocation == loc.id
    end

    function item:IsInventoryContainer() return opts.isContainer == true end
    function item:getInventory() return self.inventory end
    -- Real hasTag ONLY accepts an ItemTag object -- confirmed via bytecode, no String overload
    -- exists anywhere in InventoryItem/Food. A raw string throws "No implementation found for
    -- function: hasTag(...)" in the real game; reproduce that here rather than silently
    -- accepting it, or this double would hide the exact bug class it's meant to catch.
    function item:hasTag(tag)
        if type(tag) == "string" then
            error("No implementation found for function: hasTag(item, string " .. tag
                .. ") -- hasTag only accepts an ItemTag object in real PZ, never a raw string", 0)
        end
        return self.tags[tag] == true
    end

    -- Food evolved-recipe ingredient lists. Java-style 0-based :size()/:get(i).
    local function itemList(list)
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    function item:haveExtraItems() return #self.extraItems > 0 or #self.spices > 0 end
    function item:getExtraItems()
        if #self.extraItems == 0 then return nil end
        return itemList(self.extraItems)
    end
    function item:getSpices()
        if #self.spices == 0 then return nil end
        return itemList(self.spices)
    end
    -- Test-side helpers, not a real vanilla API -- build up a cooked meal's ingredients.
    -- The real lists are ArrayList<String> of full types (confirmed via bytecode generic
    -- signatures), NOT item objects. Enforce that here: an earlier version of this double
    -- stored item doubles, and every cooked-meal test passed while the game crashed.
    local function requireTypeString(ingredient)
        if type(ingredient) ~= "string" then
            error("extra items / spices are full-type strings in real PZ (e.g. \"Base.Cheese\"), got "
                .. type(ingredient), 0)
        end
    end
    function item:__addExtraItem(ingredient)
        requireTypeString(ingredient)
        table.insert(self.extraItems, ingredient)
    end
    function item:__addSpice(ingredient)
        requireTypeString(ingredient)
        table.insert(self.spices, ingredient)
    end

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
