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
-- Required directly rather than read out of self.services: require is cached,
-- so both spellings are the same table, and this one says which service it
-- means at the top of the file instead of by string at the call site.
local EntityService = require(serverRoot:WaitForChild("services"):WaitForChild("authority")
    :WaitForChild("EntityService"))
local SpatialService = require(serverRoot:WaitForChild("services"):WaitForChild("authority")
    :WaitForChild("SpatialService"))

-- The radius of the sphere an attack volume is tested against for a player.
-- Roughly a character's width. Tuned separately from the visible body.
-- THE PLAYER'S CAPSULE IS DECLARED, NOT DERIVED, and that is the exception
-- HitDetection.md §7.2.1 exists for.
--
-- Everything else derives its capsule from its anchor's own Size, because the
-- anchor IS the body. A player's anchor is `HumanoidRootPart`, which is 2x2x1
-- -- the rig's ORIGIN, not its body. Deriving from it would give a hurtbox
-- one stud tall.
--
-- 1.5 and 1.5 gives a capsule 3 wide and 6 tall, centred on the root at ~3
-- studs up: roughly an R15 character. Replaces a 2.5-radius sphere that was
-- 5 studs across against a body 2 wide -- about 2.5x too fat horizontally,
-- which was the number §7.1 kept citing as the reason this work was overdue.
local PLAYER_HURTBOX_RADIUS = 1.5
local PLAYER_HURTBOX_HALF_HEIGHT = 1.5
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
        -- No player map here. EntityService holds every entity in this place,
        -- and a second table keyed the same way was two doors into one truth --
        -- the pair drifts the first time anything registers through only one.

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
    EntityService:register(entity)
    self:_bindCharacter(player, entity)

    -- Announced last, after the entity exists: a Fact is only fired once the
    -- thing it describes has actually finished happening.
    self.signals.OnJoined:Fire(entity)
end

-- A player's ENTITY exists from the moment they join. Their BODY does not,
-- and it comes and goes with every respawn -- so binding the two is an event
-- handler, not a line in AddPlayer. This is the asymmetry that made a
-- createEntity impossible to write (EntityService's header).
--
-- No matching detach on death, deliberately. SpatialService:tick self-heals
-- when an anchor leaves the workspace, which is exactly what a destroyed
-- character is, and attach clears the old history so a respawned player is
-- never rewindable into a position their previous body occupied.
function ServerManager:_bindCharacter(player, entity)
    local function attach(character)
        local root = character:WaitForChild("HumanoidRootPart", 10)
        if root then
            SpatialService:attach(entity, root, PLAYER_HURTBOX_RADIUS, PLAYER_HURTBOX_HALF_HEIGHT)

            -- Printed on every respawn, not just the first: attach clears the
            -- history buffer, so this line is also the marker for "rewind has
            -- nothing to reach back to yet" if a swing lands immediately after.
            print(string.format(
                "[ServerManager] %s attached to %s  capsule r=%.2f halfHeight=%.2f "
                    .. "(total height %.1f)  rootSize=%s",
                player.Name, root.Name, PLAYER_HURTBOX_RADIUS, PLAYER_HURTBOX_HALF_HEIGHT,
                PLAYER_HURTBOX_HALF_HEIGHT * 2 + PLAYER_HURTBOX_RADIUS * 2,
                tostring(root.Size)))
        else
            warn(string.format(
                "[ServerManager] %s spawned without a HumanoidRootPart within 10s; "
                    .. "they cannot be hit and cannot attack until they respawn",
                player.Name))
        end
    end

    player.CharacterAdded:Connect(attach)

    -- Already spawned -- this manager can boot after players are in. Spawned
    -- into its own thread because attach yields on WaitForChild and AddPlayer
    -- is called from a loop that must not block on one player's character.
    if player.Character then
        task.spawn(attach, player.Character)
    end
end

function ServerManager:RemovePlayer(player)
    -- player.UserId IS the entity id -- PlayerEntity builds its identity from
    -- it. EntityService deliberately has no forPlayer, so the translation
    -- happens here, at the boundary where a Roblox Player enters the system.
    local entity = EntityService:get(player.UserId)
    if not entity then
        return
    end

    -- One call, not three. This used to do entity:destroy() by hand and skip
    -- the spatial detach entirely, which left every disconnected player in
    -- SpatialService's attached set as a permanently valid hit-detection
    -- target -- silently, because nothing reads that set except hit queries.
    EntityService:deleteEntity(entity)

    self.signals.OnLeft:Fire(entity)
end

-- No GetAllPlayers. It had no callers, and reinstating it here would mean
-- either filtering EntityService's map by entity type -- which is exactly the
-- distinction that service refuses to make -- or keeping a parallel list,
-- which is what this change removed. If something needs the set of live player
-- entities, it walks game.Players:GetPlayers() and maps each through
-- EntityService:get(p.UserId); Roblox already keeps that list.

function ServerManager:GetService(serviceName)
    return self.services[serviceName]
end

return ServerManager
