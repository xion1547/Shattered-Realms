-- src/gameModes/dungeon/server/globalManagers/ServerManager.luau
--
-- The boot sequence for this place. See Architecture-Reference.md Part 11.5
-- (boot order) and Part 13 (place manifests).
--
-- Ordering is load-bearing, not stylistic:
--   1. remotes exist before anything asks for one
--   2. the signal vocabulary exists before anything declares or subscribes
--   3. content is valid before any Service reads it
--   4. services boot in dependency-layer order (authority first)
--   5. routing resolves against services that now exist
--   6. every validation gate runs before gameplay, never after
--   7. the Scheduler starts last, once there is something to tick

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverRoot = game.ServerScriptService:WaitForChild("Server")
local bootFolder = serverRoot:WaitForChild("boot")
local signalFolder = ReplicatedStorage:WaitForChild("utils"):WaitForChild("signal")
local eventFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event")

local PlayerEntity = require(serverRoot:WaitForChild("entities"):WaitForChild("PlayerEntity"))
local ServiceLoader = require(bootFolder:WaitForChild("ServiceLoader"))
local PlaceManifest = require(bootFolder:WaitForChild("PlaceManifest"))
local BootValidation = require(bootFolder:WaitForChild("BootValidation"))
local Scheduler = require(bootFolder:WaitForChild("Scheduler"))
local EventRouter = require(serverRoot:WaitForChild("eventTape"):WaitForChild("EventRouter"))
local EventRoutingRegistry = require(serverRoot:WaitForChild("eventTape"):WaitForChild("EventRoutingRegistry"))
local EffectHandlers = require(serverRoot:WaitForChild("resolution"):WaitForChild("EffectHandlers"))
local EventRegistry = require(eventFolder:WaitForChild("EventRegistry"))
-- The fact vocabulary is server-only: it is the list of every internal event
-- name in the game, which is exactly the "internal shape" Part 13 says a
-- client should never be able to enumerate. The client gets its own,
-- separate vocabulary of client-local facts.
local ServerStorage = game:GetService("ServerStorage")
local serverShared = ServerStorage:WaitForChild("Shared")
local ServerSignals = require(serverShared:WaitForChild("signal"):WaitForChild("SignalVocabulary"))
local SignalService = require(signalFolder:WaitForChild("SignalService"))
local RemoteEventsManager = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsManager"))
local RemoteEventsEnum = require(ReplicatedStorage:WaitForChild("remoteEvents"):WaitForChild("RemoteEventsEnum"))

local ServerManager = {}
ServerManager.__index = ServerManager

function ServerManager.new()
    return setmetatable({
        players = {},

        -- Fire-capable Signal references for the facts this manager owns.
        -- Private to this object on purpose (Part 11.5).
        signals = {},
        services = {},
        router = nil,
        schedulerConnection = nil,
    }, ServerManager)
end

function ServerManager:init()
    local remoteEventsManager = RemoteEventsManager.new()
    remoteEventsManager:init()

    -- Every place loads the shared server vocabulary; this place will add a
    -- DungeonSignals vocabulary alongside it once Dungeon-owned facts exist.
    SignalService.init({ ServerSignals })

    -- ServerManager owns the session facts for now because it is what
    -- observes players arriving and leaving. These move to SessionService
    -- once that service actually does the work -- a fact belongs to whoever
    -- causes it.
    self.signals.OnJoined = SignalService.declare("Player.Session.OnJoined")
    self.signals.OnLeft = SignalService.declare("Player.Session.OnLeft")

    -- Content is validated before any Service reads it. Discovering a broken
    -- stat block when a boss spawns is far worse than at boot.
    BootValidation.checkDefinitions()

    -- Two-way manifest check, then boot in dependency-layer order.
    self.services = ServiceLoader.load(serverRoot:WaitForChild("services"), PlaceManifest)

    self:_initEventTape()

    BootValidation.checkEffectCoverage(EffectHandlers)

    -- Every declared fact has an owner, every subscription resolves.
    SignalService.validate()

    self:_bindPlayerEvents()

    -- Last: the Scheduler drains EventTape and ticks services every frame,
    -- so nothing should start ticking until everything it touches is up.
    self.schedulerConnection = Scheduler.start(self.services, self.router)

    print("[ServerManager] boot complete")
end

function ServerManager:_initEventTape()
    -- Every event declaration is well-formed: schemas are valid and every
    -- parameter has its builder method. A mistake fails here, at startup,
    -- rather than the first time a player triggers that event type.
    --
    -- Nothing downstream gates on this having run -- what it checks is static
    -- (see EventRegistry.validate). It is a boot gate, not a precondition.
    EventRegistry.validate()

    local remote = RemoteEventsManager.getEventStatic(RemoteEventsEnum.EventTapeRemote)
    self.router = EventRouter.new(remote)

    -- Declarative names resolved lazily against the services actually
    -- present here. An eventType whose Service is absent from this place
    -- stays unroutable and its events are rejected -- that is the mechanism,
    -- not a gap (Part 13).
    self.router:resolveRoutes(EventRoutingRegistry, serverRoot:WaitForChild("services"))
    self.router:start()
end

function ServerManager:_bindPlayerEvents()
    game.Players.PlayerAdded:Connect(function(player)
        self:AddPlayer(player)
    end)

    game.Players.PlayerRemoving:Connect(function(player)
        self:RemovePlayer(player)
    end)

    for _, player in ipairs(game.Players:GetPlayers()) do
        self:AddPlayer(player)
    end
end

function ServerManager:AddPlayer(player)
    local entity = PlayerEntity.new(player)
    self.players[entity:getId()] = entity

    -- Announced last, after the entity exists: a Fact is only fired once the
    -- thing it describes has actually finished happening.
    self.signals.OnJoined:Fire(entity)
end

function ServerManager:RemovePlayer(player)
    local entity = self.players[player.UserId]
    if not entity then
        return
    end

    self.players[player.UserId] = nil
    entity:destroy()
    self.signals.OnLeft:Fire(entity)
end

function ServerManager:GetAllPlayers()
    return self.players
end

function ServerManager:GetService(serviceName)
    return self.services[serviceName]
end

return ServerManager
