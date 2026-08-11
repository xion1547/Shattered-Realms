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
