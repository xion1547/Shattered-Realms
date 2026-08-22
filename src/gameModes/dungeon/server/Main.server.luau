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

-- TEMPORARY: every dummy faces the nearest player and swings on a timer, so
-- the enemy->player direction can be watched. Started AFTER the spawner
-- because it reads the spatial attach set to build its schedule -- run it
-- first and it arms nothing.
--
-- Takes the router so it can push damage down the same EventTape remote
-- everything else uses, rather than standing up a second wire for health.
local EnemyAttackDemo = require(diagnostics:WaitForChild("EnemyAttackDemo"))
EnemyAttackDemo.start(serverManager.router)

-- TEMPORARY, and scheduled for deletion the moment it has answered its one
-- question: can a SERVER script observe a limb moving while a CLIENT plays the
-- animation? The answer decides how hitboxes get their position
-- (HitDetection.md Part 9) and nothing downstream of that can be built until
-- it is known.
--
-- Builds its own control rig rather than borrowing a dummy, so that a null
-- result can be distinguished from a broken measurement -- see the file's
-- header. Started last because it watches things everything else created.
local LimbProbe = require(diagnostics:WaitForChild("LimbProbe"))
LimbProbe.start()
