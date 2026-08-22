-- Main.server.luau

local serverRoot = game.ServerScriptService:WaitForChild("Server")

local RunTests = require(serverRoot:WaitForChild("tests"):WaitForChild("RunTests"))
local ServerManager = require(serverRoot:WaitForChild("globalManagers"):WaitForChild("ServerManager"))

-- Tests run BEFORE ServerManager, deliberately. SignalService.init() resets
-- module state, so the suite would otherwise wipe the live vocabulary and the
-- declared session facts. Running first also means a module that throws on
-- first use is reported before anything depends on it. See tests/RunTests.
RunTests.run()

local serverManager = ServerManager.new()
serverManager:init()

-- TEMPORARY: ten static dummies so hit detection has something to hit.
--
-- Called from here rather than left as its own Script because Roblox does not
-- order independent Scripts against each other. As a Script it sometimes ran
-- before RunTests, and its ten attached entities then showed up as candidates
-- inside the targeting suite -- a real failure with nothing wrong in the code
-- under test. Anything that MUTATES state the suite reads belongs after it,
-- in a place that says so.
local diagnostics = serverRoot:WaitForChild("diagnostics")

-- Publishes every Debug* flag onto Workspace as an attribute, so they are
-- visible in the Properties panel and can be flipped WHILE THE GAME RUNS.
-- First, so everything after it starts under the settings it will run with.
local DebugConfig = require(diagnostics:WaitForChild("DebugConfig"))
DebugConfig.publish()

local DummySpawner = require(diagnostics:WaitForChild("DummySpawner"))
DummySpawner.spawnAll()

-- TEMPORARY: draws every hurtbox as a glowing overlay. On by default while
-- hurtboxes are a known-wrong placeholder (HitDetection.md §7.1) -- the gap
-- between a dummy's 4-stud body and its 5-stud hurtbox is invisible while
-- playing and obvious the moment it is drawn. Flip ENABLED in the module to
-- turn it off.
--
-- Started after the spawner so the first redraw already has bodies to draw,
-- though it would self-correct within a frame either way.
local HurtboxDebug = require(diagnostics:WaitForChild("HurtboxDebug"))
HurtboxDebug.start()

-- RETIRED 2026-08-21, both moved to `_toDelete/` at the repo root:
--
--   EnemyAttackDemo   dummies swung at players on a timer. Removed with the
--                     rest of the enemy attack path -- enemies come back once
--                     the PATH hitbox model exists (HitDetection.md Part 9),
--                     and giving them the old SWEEP model first would mean
--                     building it twice.
--
--   LimbProbe         answered its one question and was deleted, which is what
--                     it said it would do. The finding is recorded as MEASURED
--                     in HitDetection.md 9.6: the server does see a
--                     client-animated limb, trailing by ~0.104s against an
--                     INTERPOLATION_CONSTANT of 0.100s.
--
--   PingProbe         same -- the unit question it existed for is closed in
--                     HitDetection.md Part 6.
--
--   SweepTrace        per-wedge table for a swing. Retired with the SWEEP
--                     default; its header also asserted that a hitbox never
--                     needs history, which stopped being true under PATH.
