-- MoodleFramework (external dependency mod) double.
--
-- RD_moodles.lua calls MF.createMoodle() eight times at FILE SCOPE, so this must
-- exist in the environment before that file is loaded or the load itself throws.

local M = {}

function M.new()
    local mf = { __mf = true, created = {}, values = {}, setCalls = {} }

    function mf.createMoodle(name)
        mf.created[#mf.created + 1] = name
        return name
    end

    function mf.getMoodle(name, playerNum)
        local key = tostring(name) .. "#" .. tostring(playerNum or 0)
        return {
            setValue = function(_, v)
                mf.values[name] = v
                mf.setCalls[#mf.setCalls + 1] = { moodle = name, value = v, key = key }
            end,
            getValue = function() return mf.values[name] or 0 end,
            -- The real framework's default thresholds, kept here so a test can
            -- assert which display level a value maps to.
            setThresholds = function() end,
        }
    end

    -- Value -> display level, using MoodleFramework's documented defaults
    -- (0.1/0.2/0.3/0.4 downward, 0.6/0.7/0.8/0.9 upward).
    function mf.levelFor(value)
        if value >= 0.9 then return 4
        elseif value >= 0.8 then return 3
        elseif value >= 0.7 then return 2
        elseif value >= 0.6 then return 1
        elseif value > 0.4 then return 0
        elseif value > 0.3 then return -1
        elseif value > 0.2 then return -2
        elseif value > 0.1 then return -3
        else return -4 end
    end

    function mf.reset()
        mf.values = {}
        for i = #mf.setCalls, 1, -1 do mf.setCalls[i] = nil end
    end

    return mf
end

return M
