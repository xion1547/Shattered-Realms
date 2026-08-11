-- src/gameModes/dungeon/server/eventTape/EventRouter.luau
--
-- SERVER ONLY. Receive, deserialize, buffer, drain, route.
-- See Architecture-Reference.md Part 12.
--
-- This replaces the EventTapeManager / EventTapeController / EventTapeSystem
-- trio. Those three each held their own handler table and their own buffer,
-- which meant one inbound stream had two competing buffering strategies and
-- two competing handler registries. There is one of each here.
--
-- Contains zero game logic and trusts nothing from the client. Its entire
-- job is to hand a validated, typed Event to exactly one Service method by
-- ordinary function call -- never a Signal.

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventTapeFolder = ReplicatedStorage:WaitForChild("eventTape")
local eventFolder = eventTapeFolder:WaitForChild("event")
local wireFolder = eventTapeFolder:WaitForChild("wire")
local EventTape = require(eventFolder:WaitForChild("EventTape"))
local EventRegistry = require(eventFolder:WaitForChild("EventRegistry"))
local EventDeserializer = require(eventFolder:WaitForChild("EventDeserializer"))
local MessageKind = require(wireFolder:WaitForChild("MessageKind"))
local RejectReason = require(wireFolder:WaitForChild("RejectReason"))

-- Client-facing caps. A tape is a batch of a player's own actions across a
-- frame or two; anything near these numbers is not a player playing.
--
-- PER TAPE, NOT PER SECOND. A tape is one frame's batch, so this cap alone
-- permits MAX_EVENTS_PER_TAPE x framerate per second -- roughly 3000 at 60fps.
-- It bounds one burst; it does nothing about sustained load. That is what the
-- rate limiter below is for, and why a cap on its own was never enough.
local MAX_EVENTS_PER_TAPE = 50
local MAX_BUFFERED_EVENTS = 2048

-- SUSTAINED throughput, per player. This is the real limit.
--
-- A token bucket rather than a fixed per-second counter, because a fixed
-- window punishes honest bursts: a player mashing an ability at a window
-- boundary gets rejected while their average rate is fine. The bucket refills
-- continuously, so short bursts draw down a balance and quiet periods restore
-- it -- which is how real input actually behaves.
--
-- BURST is deliberately larger than RATE: two seconds of budget can be spent
-- at once, then must be earned back. A player cannot exceed RATE on average
-- no matter how they spend it.
local RATE_LIMIT_PER_SECOND = 50
local RATE_LIMIT_BURST = 100

local EventRouter = {}
EventRouter.__index = EventRouter

function EventRouter.new(remote)
    assert(typeof(remote) == "Instance" and remote:IsA("RemoteEvent"),
        "[EventRouter] remote must be a RemoteEvent")
    assert(RunService:IsServer(), "[EventRouter] is server-only")

    return setmetatable({
        _remote = remote,
        _routes = {},      -- eventType -> function(player, event, receivedAt)
        _buffer = {},      -- arrival-ordered { player, event, receivedAt }
        _connection = nil,
        _dropped = 0,
        -- player -> { tokens, lastRefill }. WEAK KEYS: a player who leaves is
        -- collected along with their bucket, so this cannot grow without
        -- bound over a long-running server. Nothing else has to remember to
        -- clean it up, which is the failure mode a manual table would have.
        _buckets = setmetatable({}, { __mode = "k" }),
    }, EventRouter)
end

-- Draws `count` tokens for this player, refilling first. Returns false if the
-- player cannot afford them, in which case NOTHING is deducted -- a rejected
-- tape must not also cost budget, or a spamming client would dig itself into
-- a hole it can never climb out of and stay locked out after it stopped.
function EventRouter:_takeTokens(player, count)
    local now = os.clock()
    local bucket = self._buckets[player]

    if not bucket then
        bucket = { tokens = RATE_LIMIT_BURST, lastRefill = now }
        self._buckets[player] = bucket
    end

    local elapsed = math.max(0, now - bucket.lastRefill)
    bucket.tokens = math.min(RATE_LIMIT_BURST, bucket.tokens + elapsed * RATE_LIMIT_PER_SECOND)
    bucket.lastRefill = now

    if bucket.tokens < count then
        return false
    end

    bucket.tokens -= count
    return true
end

-- Resolves each declarative registry entry against the Services actually
-- present in this place. Called once at boot, before start().
--
-- Three outcomes per entry, and the difference matters:
--   * module present, method present -> routable
--   * module ABSENT                  -> not routable here, and that is
--                                       correct, not an error (Part 13)
--   * module present, method missing -> a real bug, fails boot
function EventRouter:resolveRoutes(registry, servicesFolder)
    local failures = {}

    for eventType, entry in pairs(registry) do
        if not EventRegistry.isValid(eventType) then
            table.insert(failures, string.format(
                "'%s' is not a declared eventType (see EventRegistry.luau)", tostring(eventType)))
            continue
        end
        if type(entry) ~= "table" or type(entry.service) ~= "string"
            or type(entry.method) ~= "string" then
            table.insert(failures, string.format(
                "'%s': entry must be { service = \"Name\", method = \"Name\" }", eventType))
            continue
        end

        -- Recursive: services are organised by ROLE (authority/domain/infra/
        -- drivers), so a name does not sit directly under the services folder.
        -- Place membership is declared in PlaceManifest and .project.json, not
        -- expressed through folder depth.
        local module = servicesFolder and servicesFolder:FindFirstChild(entry.service, true)
        if not module then
            -- Absent in this place. Events of this type will be rejected as
            -- UNROUTABLE, which is the intended behaviour, not a gap.
            continue
        end

        local ok, service = pcall(require, module)
        if not ok then
            table.insert(failures, string.format(
                "'%s': failed to require '%s': %s", eventType, entry.service, tostring(service)))
            continue
        end
        if type(service) ~= "table" or type(service[entry.method]) ~= "function" then
            table.insert(failures, string.format(
                "'%s': '%s' has no method '%s'", eventType, entry.service, entry.method))
            continue
        end

        -- receivedAt is forwarded, not dropped. It is the ONLY
        -- server-authoritative time any handler can see -- the client's own
        -- construction stamp never crosses the wire -- so a closure that
        -- silently swallowed it left the latency rewind with nothing to
        -- rewind against. Lua discards extra arguments without complaint,
        -- which is exactly why this went unnoticed.
        self._routes[eventType] = function(player, event, receivedAt)
            return service[entry.method](service, player, event, receivedAt)
        end
    end

    if #failures > 0 then
        table.sort(failures)
        error(string.format(
            "[EventRouter] %d routing entry/entries failed to resolve:\n  - %s",
            #failures, table.concat(failures, "\n  - ")), 0)
    end
end

function EventRouter:start()
    assert(not self._connection, "[EventRouter] already started")
    self._connection = self._remote.OnServerEvent:Connect(function(player, payload)
        self:_receive(player, payload)
    end)
end

function EventRouter:stop()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

-- Buffers only. Nothing is routed from inside the RemoteEvent callback --
-- draining on a frame boundary is what makes ordering observable and keeps a
-- burst of traffic from interleaving with a Service mid-mutation.
function EventRouter:_receive(player, message)
    if type(message) ~= "table" or message.kind ~= MessageKind.TAPE then
        warn(string.format(
            "[EventRouter] discarded a non-TAPE message from %s", player.Name))
        return
    end

    local serializedEvents, reason = EventTape.unpackSerialized(message.tape)
    if not serializedEvents then
        -- Nothing to reject against: a malformed payload carries no event ids.
        warn(string.format("[EventRouter] malformed tape from %s: %s", player.Name, reason))
        return
    end

    -- ONE reject per refused TAPE, never one per event in it, and that is a
    -- deliberate trade rather than laziness. Answering every id would let a
    -- sender turn one inbound message into fifty outbound ones -- amplification
    -- handed to exactly the traffic being refused. The client's PendingActions
    -- sweep already resolves anything unanswered as TIMEOUT, so the remaining
    -- ids are not stranded, only slower to clear.
    local function refuse(reason)
        local first = serializedEvents[1]
        local eventId = type(first) == "table" and first.eventId or nil
        self:reject(player, eventId, reason)
    end

    if #serializedEvents > MAX_EVENTS_PER_TAPE then
        warn(string.format("[EventRouter] oversized tape from %s: %d events, dropped",
            player.Name, #serializedEvents))
        refuse(RejectReason.OVERSIZED)
        return
    end

    -- Charged for the WHOLE tape, before any of it is processed. Charging per
    -- event as they are deserialized would mean a refused tape had already
    -- paid for the work it was refused for.
    if not self:_takeTokens(player, #serializedEvents) then
        warn(string.format(
            "[EventRouter] rate limited %s: %d events exceeded the budget",
            player.Name, #serializedEvents))
        refuse(RejectReason.RATE_LIMITED)
        return
    end

    -- Stamped ONCE per tape, on the server clock, and used for every event in
    -- it. This is the ONLY timestamp anything ordering-related may use: the
    -- client's own construction time is never serialized, because os.clock()
    -- has an arbitrary per-process origin and a client-reported time would be
    -- untrustworthy regardless (Part 13).
    local receivedAt = os.clock()

    for _, serialized in ipairs(serializedEvents) do
        if #self._buffer >= MAX_BUFFERED_EVENTS then
            self._dropped += 1
            continue
        end

        local event, failure = EventDeserializer.deserialize(serialized)
        if event then
            table.insert(self._buffer, {
                player = player,
                event = event,
                receivedAt = receivedAt,
            })
        else
            -- The payload may still carry a usable id even when the rest of
            -- it did not validate, so the client can clear its pending state.
            local eventId = type(serialized) == "table" and serialized.eventId or nil
            self:reject(player, eventId, RejectReason.MALFORMED)
            warn(string.format("[EventRouter] rejected event from %s: %s", player.Name, failure))
        end
    end
end

-- Processes everything buffered since the last drain, in arrival order.
--
-- There is deliberately no sort. Arrival order IS the ordering guarantee
-- (Part 12): the buffer is append-only, so it is already ordered, and
-- table.sort is not stable -- sorting by timestamp actively reordered
-- same-timestamp events in the previous implementation.
function EventRouter:drain()
    if #self._buffer == 0 then
        return
    end

    local batch = self._buffer
    self._buffer = {}

    if self._dropped > 0 then
        warn(string.format("[EventRouter] dropped %d event(s) at buffer cap", self._dropped))
        self._dropped = 0
    end

    for _, item in ipairs(batch) do
        self:_route(item.player, item.event, item.receivedAt)
    end
end

function EventRouter:_route(player, event, receivedAt)
    local eventType = event:getEventType()
    local handler = self._routes[eventType]

    if not handler then
        -- No Service owns this type in this place. This is the Hub-has-no-
        -- combat case: reject explicitly rather than standing up a null
        -- service that silently succeeds (Part 13).
        self:reject(player, event:getEventId(), RejectReason.UNROUTABLE)
        return
    end

    local ok, err = pcall(handler, player, event, receivedAt)
    if not ok then
        warn(string.format("[EventRouter] '%s' handler errored: %s", eventType, tostring(err)))
    end
end

function EventRouter:reject(player, eventId, reason)
    self._remote:FireClient(player, {
        kind = MessageKind.REJECT,
        eventId = eventId,
        reason = reason,
    })
end

-- Answers a specific Request. `diff` must be built from what the COMMIT calls
-- actually returned, never from what the pipeline computed -- otherwise the
-- client renders a number that never landed (Part 11.1).
function EventRouter:confirm(player, eventId, diff)
    self._remote:FireClient(player, {
        kind = MessageKind.CONFIRM,
        eventId = eventId,
        diff = diff,
    })
end

-- PROVISIONAL. Part 12 specifies the inbound path in detail and leaves the
-- outbound shape open -- it never says whether the server batches pushes into
-- tapes or sends them discretely. This is the minimum that works: one
-- message, one payload, no batching. Decide the real shape when the first
-- Service actually needs it, and update Part 12 then.
function EventRouter:push(player, eventType, payload)
    self._remote:FireClient(player, {
        kind = MessageKind.PUSH,
        eventType = eventType,
        payload = payload,
    })
end

return EventRouter
