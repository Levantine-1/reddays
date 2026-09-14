-- ItemContainer and WornItems doubles.
--
-- Both mimic the Java collection API the mod iterates: :size() with :get(i)
-- indexed from ZERO. Getting that base wrong is a classic PZ modding bug, so the
-- doubles reproduce it faithfully rather than exposing Lua-style 1-based access.

local M = {}

-- A plain inventory container. `AddItem` accepts either a full type string
-- (resolved through `itemFactory`) or an existing item double.
function M.newInventory(itemFactory)
    local inv = { __container = true, items = {} }

    function inv:getItems()
        local list = self.items
        return {
            size = function() return #list end,
            get = function(_, i) return list[i + 1] end,
        }
    end

    function inv:size() return #self.items end
    function inv:get(i) return self.items[i + 1] end

    function inv:AddItem(spec)
        local item
        if type(spec) == "string" then
            local shortType = string.match(spec, "%.(.+)$") or spec
            item = itemFactory({ type = shortType, fullType = spec })
        else
            item = spec
        end
        table.insert(self.items, item)
        return item
    end

    function inv:Remove(item)
        for i = #self.items, 1, -1 do
            if self.items[i] == item then table.remove(self.items, i) end
        end
    end

    function inv:contains(item)
        for _, existing in ipairs(self.items) do
            if existing == item then return true end
        end
        return false
    end

    return inv
end

-- WornItems: a list of {getItem()} wrappers, also addressable by body location.
function M.newWornItems()
    local worn = { __worn = true, entries = {} }

    function worn:size() return #self.entries end
    function worn:get(i) return self.entries[i + 1] end

    -- `location` may be a body-location handle or its plain string id.
    function worn:add(item, location)
        local entry = {
            item = item,
            location = location or item.bodyLocation,
            getItem = function(self_) return self_.item end,
        }
        table.insert(self.entries, entry)
        return entry
    end

    function worn:remove(item)
        for i = #self.entries, 1, -1 do
            if self.entries[i].item == item then table.remove(self.entries, i) end
        end
    end

    function worn:getItem(bodyLocation)
        if not bodyLocation then return nil end
        local wanted = bodyLocation.id or bodyLocation
        for _, entry in ipairs(self.entries) do
            local loc = entry.location
            local locId = type(loc) == "table" and loc.id or loc
            if locId == wanted then return entry.item end
        end
        return nil
    end

    return worn
end

return M
