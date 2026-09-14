-- Minimal test runner: describe/it + deep-equality assertions.
-- Deliberately dependency-free so it runs under any Lua 5.1 host.

local M = {}

M.suites = {}          -- ordered list of {name, tests={...}}
local currentSuite = nil
local beforeEachStack = {}

-- ================= VALUE FORMATTING =================

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

local function dump(v, indent, seen)
    indent = indent or ""
    seen = seen or {}
    local vt = type(v)
    if vt == "string" then return string.format("%q", v) end
    if vt ~= "table" then return tostring(v) end
    if seen[v] then return "<cycle>" end
    seen[v] = true

    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    if #keys == 0 then return "{}" end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local inner = indent .. "  "
    local parts = {}
    local array = isArray(v)
    for _, k in ipairs(keys) do
        local val = dump(v[k], inner, seen)
        if array then
            parts[#parts + 1] = inner .. val
        else
            parts[#parts + 1] = inner .. tostring(k) .. " = " .. val
        end
    end
    seen[v] = nil
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end
M.dump = dump

-- ================= DEEP EQUALITY =================

-- Returns true, or false plus a dotted path to the first difference.
local function deepEqual(a, b, path)
    path = path or ""
    if a == b then return true end
    if type(a) ~= type(b) then
        return false, path .. " (" .. type(a) .. " vs " .. type(b) .. ")"
    end
    if type(a) ~= "table" then return false, path end

    for k, av in pairs(a) do
        local sub = path == "" and tostring(k) or (path .. "." .. tostring(k))
        if b[k] == nil then return false, sub .. " (missing on right)" end
        local ok, where = deepEqual(av, b[k], sub)
        if not ok then return false, where end
    end
    for k in pairs(b) do
        if a[k] == nil then
            local sub = path == "" and tostring(k) or (path .. "." .. tostring(k))
            return false, sub .. " (missing on left)"
        end
    end
    return true
end
M.deepEqual = deepEqual

-- ================= ASSERTIONS =================
-- All raise with level 0 so the message is not prefixed by runner internals;
-- the suite/test name already localises the failure.

function M.fail(msg)
    error(msg, 0)
end

function M.eq(actual, expected, msg)
    local ok, where = deepEqual(actual, expected)
    if not ok then
        M.fail((msg and (msg .. "\n") or "")
            .. "expected: " .. dump(expected) .. "\n"
            .. "actual:   " .. dump(actual)
            .. (where and where ~= "" and ("\nfirst difference at: " .. where) or ""))
    end
end

function M.neq(actual, unexpected, msg)
    if deepEqual(actual, unexpected) then
        M.fail((msg and (msg .. "\n") or "") .. "expected value to differ from: " .. dump(unexpected))
    end
end

function M.near(actual, expected, tol, msg)
    tol = tol or 1e-9
    if type(actual) ~= "number" then
        M.fail((msg and (msg .. "\n") or "") .. "expected a number, got " .. type(actual) .. ": " .. dump(actual))
    end
    if math.abs(actual - expected) > tol then
        M.fail((msg and (msg .. "\n") or "")
            .. string.format("expected %s +/- %s, got %s", tostring(expected), tostring(tol), tostring(actual)))
    end
end

function M.truthy(v, msg)
    if not v then M.fail((msg and (msg .. "\n") or "") .. "expected truthy, got " .. dump(v)) end
end

function M.falsy(v, msg)
    if v then M.fail((msg and (msg .. "\n") or "") .. "expected falsy, got " .. dump(v)) end
end

function M.isNil(v, msg)
    if v ~= nil then M.fail((msg and (msg .. "\n") or "") .. "expected nil, got " .. dump(v)) end
end

function M.notNil(v, msg)
    if v == nil then M.fail((msg and (msg .. "\n") or "") .. "expected non-nil") end
end

-- Asserts a >= lo and a <= hi (inclusive both ends).
function M.between(actual, lo, hi, msg)
    if type(actual) ~= "number" or actual < lo or actual > hi then
        M.fail((msg and (msg .. "\n") or "")
            .. "expected a value in [" .. tostring(lo) .. ", " .. tostring(hi) .. "], got " .. dump(actual))
    end
end

function M.contains(haystack, needle, msg)
    if type(haystack) ~= "string" or not string.find(haystack, needle, 1, true) then
        M.fail((msg and (msg .. "\n") or "") .. "expected to find " .. dump(needle) .. " in " .. dump(haystack))
    end
end

-- ================= REGISTRATION =================

function M.describe(name, fn)
    currentSuite = { name = name, tests = {}, beforeEach = {} }
    M.suites[#M.suites + 1] = currentSuite
    beforeEachStack = currentSuite.beforeEach
    fn()
    currentSuite = nil
    beforeEachStack = {}
end

function M.before_each(fn)
    if not currentSuite then error("before_each() outside describe()", 2) end
    currentSuite.beforeEach[#currentSuite.beforeEach + 1] = fn
end

function M.it(name, fn)
    if not currentSuite then error("it() outside describe()", 2) end
    currentSuite.tests[#currentSuite.tests + 1] = { name = name, fn = fn }
end

-- ================= EXECUTION =================

-- Runs everything registered so far. Returns a summary table; `out` is a
-- line-consuming callback so the host controls presentation.
function M.run(out)
    out = out or function() end
    local passed, failed = 0, 0
    local failures = {}

    for _, suite in ipairs(M.suites) do
        out(suite.name)
        for _, test in ipairs(suite.tests) do
            local ctx = {}
            local ok, err = pcall(function()
                for _, be in ipairs(suite.beforeEach) do be(ctx) end
                test.fn(ctx)
            end)
            if ok then
                passed = passed + 1
                out("  PASS  " .. test.name)
            else
                failed = failed + 1
                out("  FAIL  " .. test.name)
                failures[#failures + 1] = {
                    suite = suite.name,
                    test = test.name,
                    err = tostring(err),
                }
            end
        end
    end

    return { passed = passed, failed = failed, failures = failures }
end

function M.reset()
    M.suites = {}
    currentSuite = nil
    beforeEachStack = {}
end

return M
