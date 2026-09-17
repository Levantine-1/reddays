-- RedDays build-time switches, shared so client and server read the same values.

RD_Config = RD_Config or {}

-- In-game SP/MP self-test: rd.mptest.run() and rd.mptest.actions() (client/RD_selftest.lua),
-- plus the rdTestProbe / rdTestGiveItems server commands. Inert until called, but SET THIS TO
-- false BEFORE A WORKSHOP UPLOAD. The `== nil` form lets the test harness pre-seed the value.
if RD_Config.selftest == nil then RD_Config.selftest = false end

-- Non-debugger diagnostic prints (load banners, cycle/TSS/PMS state chatter) are gated behind
-- this flag so a live game only prints what rd.* console commands ask for. Leave false for a
-- Workshop upload; flip on when chasing a bug that needs more than the rd.* commands show.
if RD_Config.verboseLog == nil then RD_Config.verboseLog = false end
