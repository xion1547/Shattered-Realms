-- Main.server.luau
local ServerManager = require(game.ServerScriptService:WaitForChild("Server"):WaitForChild("globalManagers"):WaitForChild("ServerManager"))

-- 🔄 onConnect: Load only the modules you want on player join
local function onConnect()
	ServerManager:init() -- Initialize the server manager and its components
	print("[Client] RemoteEventsManager initialized.")
end

-- Kick off your custom loading logic
onConnect()
