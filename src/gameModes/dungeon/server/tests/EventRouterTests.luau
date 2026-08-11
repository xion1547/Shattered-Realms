-- src/gameModes/dungeon/server/tests/EventRouterTests.luau
--
-- Exercises the full inbound path: a serialized tape arrives, gets
-- deserialized into typed Events, buffers in arrival order, and drains to
-- exactly one Service method. See Architecture-Reference.md Part 12.
--
-- Two test seams, both deliberate and neither requiring production changes:
--
--   * `router:_receive(...)` is called directly instead of firing the
--     RemoteEvent. OnServerEvent can only be raised by a real client, so
--     there is no way to drive it from a server-side test.
--   * `router.reject` is replaced per-instance so rejections can be
--     inspected. The real one calls FireClient, which needs a real Player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event")
local EventTape = require(eventFolder:WaitForChild("EventTape"))
local wireFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("wire")
local MessageKind = require(wireFolder:WaitForChild("MessageKind"))
local RejectReason = require(wireFolder:WaitForChild("RejectReason"))

local testsFolder = script.Parent
local EventRouter = require(testsFolder.Parent:WaitForChild("eventTape"):WaitForChild("EventRouter"))
local TestRunner = require(testsFolder:WaitForChild("TestRunner"))
local fixtures = testsFolder:WaitForChild("fixtures")

local EventFactory = require(eventFolder:WaitForChild("EventFactory"))
local EventType = require(eventFolder:WaitForChild("EventType"))
local CombatEvent = require(eventFolder:WaitForChild("types"):WaitForChild("CombatEvent"))
local InventoryEvent = require(eventFolder:WaitForChild("types"):WaitForChild("InventoryEvent"))

local FAKE_PLAYER = { Name = "TestPlayer" }

-- Payloads must be schema-valid now, so tests use real fields. targetId
-- doubles as the ordering marker.
local function mk(subType, targetId)
    local builder = EventFactory.create(CombatEvent):withSubType(CombatEvent.SubType[subType])
    if targetId ~= nil then
        builder:withTargetId(targetId)
    end
    return builder:build()
end

local function mkLoot()
    return EventFactory.create(InventoryEvent):withSubType(InventoryEvent.SubType.LOOT):build()
end

-- Builds a router with a captured reject list. The RemoteEvent is real but
-- unparented and never fired.
local function newRouter()
    local remote = Instance.new("RemoteEvent")
    local router = EventRouter.new(remote)

    local rejects = {}
    router.reject = function(_, player, eventId, reason)
        table.insert(rejects, { player = player, eventId = eventId, reason = reason })
    end

    return router, rejects, remote
end

-- Builds the exact envelope EventSender puts on the wire.
local function tapeOf(...)
    local tape = EventTape.new()
    for _, event in ipairs({ ... }) do
        tape:addEvent(event)
    end
    return { kind = MessageKind.TAPE, tape = tape:serialize() }
end

-- A tape of `count` identical MELEE events, for the limit tests. Token cost
-- is per EVENT, so exercising the budget needs volume the varargs form makes
-- unreadable.
local function tapeOfSize(count)
    local events = {}
    for index = 1, count do
        table.insert(events, mk("MELEE", index))
    end
    return tapeOf(table.unpack(events))
end

return function()
    local t = TestRunner.new("EventRouter")

    t:case("receives a serialized tape and deserializes it into typed Events", function(a)
        local router, rejects = newRouter()
        local sent = mk("MELEE", 11)

        router:_receive(FAKE_PLAYER, tapeOf(sent))

        a.equal(#rejects, 0, "a well-formed tape should produce no rejections")
        a.equal(#router._buffer, 1, "the event should be buffered")

        local buffered = router._buffer[1].event
        a.isType(buffered.getEventType, "function", "the buffer must hold typed Events, not raw tables")
        a.equal(buffered:getEventType(), EventType.COMBAT)
        a.equal(buffered:getSubType(), CombatEvent.SubType.MELEE)
        a.equal(buffered:getData().targetId, 11)
        a.equal(buffered:getEventId(), sent:getEventId(), "the id must survive the trip")
        a.equal(router._buffer[1].player, FAKE_PLAYER, "the sender must be retained")
    end)

    t:case("buffers a multi-event tape in arrival order", function(a)
        local router = newRouter()
        router:_receive(FAKE_PLAYER, tapeOf(
            mk("MELEE", 1),
            mk("RANGED", 2),
            mkLoot()
        ))

        a.equal(#router._buffer, 3)
        a.equal(router._buffer[1].event:get("targetId"), 1)
        a.equal(router._buffer[2].event:get("targetId"), 2)
        a.equal(router._buffer[3].event:getEventType(), EventType.INVENTORY,
            "a tape can mix domains and still keep its order")
    end)

    t:case("routes drained events to the resolved Service method", function(a)
        local router, rejects = newRouter()
        local FakeService = require(fixtures:WaitForChild("FakeService"))
        FakeService.reset()

        router:resolveRoutes({ [EventType.COMBAT] = { service = "FakeService", method = "OnAttack" } }, fixtures)
        router:_receive(FAKE_PLAYER, tapeOf(mk("MELEE", 2)))

        a.equal(#FakeService.received, 0, "nothing routes until drain")
        router:drain()

        a.equal(#FakeService.received, 1, "drain should route to the Service")
        a.equal(FakeService.received[1].player, FAKE_PLAYER)
        a.equal(FakeService.received[1].event:getData().targetId, 2)
        a.equal(#rejects, 0)
        FakeService.reset()
    end)

    t:case("the server timestamp reaches the Service, not just the buffer", function(a)
        -- REGRESSION: resolveRoutes built its closure as function(player,
        -- event), while _route called it with (player, event, receivedAt).
        -- Lua drops extra arguments without complaint, so receivedAt was
        -- stamped on the server clock, carried through the buffer, and thrown
        -- away one call short of the handler -- leaving the latency rewind
        -- with no server-authoritative time to rewind against. The client's
        -- own construction stamp never crosses the wire, so this was the only
        -- trustworthy time available and nothing could see it.
        local router = newRouter()
        local FakeService = require(fixtures:WaitForChild("FakeService"))
        FakeService.reset()

        router:resolveRoutes({ [EventType.COMBAT] = { service = "FakeService", method = "OnAttack" } }, fixtures)
        router:_receive(FAKE_PLAYER, tapeOf(mk("MELEE", 1)))

        local buffered = router._buffer[1].receivedAt
        router:drain()

        a.isType(FakeService.received[1].receivedAt, "number",
            "the handler must receive the server arrival time")
        a.equal(FakeService.received[1].receivedAt, buffered,
            "and it must be the same stamp the buffer held")
        FakeService.reset()
    end)

    t:case("drain preserves arrival order and empties the buffer", function(a)
        local router = newRouter()
        local order = {}
        router._routes[EventType.COMBAT] = function(_, event) table.insert(order, event:get("targetId")) end

        router:_receive(FAKE_PLAYER, tapeOf(
            mk("MELEE", 1),
            mk("MELEE", 2)
        ))
        router:_receive(FAKE_PLAYER, tapeOf(mk("MELEE", 3)))

        router:drain()

        a.deepEqual(order, { 1, 2, 3 }, "arrival order is the ordering guarantee -- no sorting")
        a.equal(#router._buffer, 0, "drain must empty the buffer")

        router:drain()
        a.equal(#order, 3, "a second drain with nothing buffered is a no-op")
    end)

    t:case("an unroutable eventType is rejected explicitly", function(a)
        -- This is the Hub-has-no-combat case: no Service owns the type here,
        -- so it is rejected rather than silently succeeding against a mock.
        local router, rejects = newRouter()
        local sent = mk("MELEE")

        router:_receive(FAKE_PLAYER, tapeOf(sent))
        router:drain()

        a.equal(#rejects, 1, "an unroutable event must be rejected")
        a.equal(rejects[1].reason, RejectReason.UNROUTABLE)
        a.equal(rejects[1].eventId, sent:getEventId(),
            "the client needs the id to clear its pending state")
    end)

    t:case("a malformed event is rejected without discarding the rest of the tape", function(a)
        local router, rejects = newRouter()
        local good = mk("MELEE", 1)

        local message = tapeOf(good)
        table.insert(message.tape.events, { eventType = "NOPE", subType = "MELEE", data = {}, eventId = "bad-1" })
        table.insert(message.tape.events, mk("RANGED", 3):serialize())

        router:_receive(FAKE_PLAYER, message)

        a.equal(#router._buffer, 2, "the two valid events must still be buffered")
        a.equal(#rejects, 1, "only the malformed event is rejected")
        a.equal(rejects[1].reason, RejectReason.MALFORMED)
        a.equal(rejects[1].eventId, "bad-1", "the id is salvaged from the raw payload")
    end)

    t:case("a malformed tape payload is dropped whole", function(a)
        local router, rejects = newRouter()

        router:_receive(FAKE_PLAYER, "not a table")
        router:_receive(FAKE_PLAYER, { kind = MessageKind.TAPE, tape = { notEvents = true } })

        a.equal(#router._buffer, 0, "nothing should buffer from a malformed payload")
        a.equal(#rejects, 0, "there are no event ids to reject against")
    end)

    t:case("a message that is not a TAPE is discarded", function(a)
        -- Only one kind travels client -> server. A client sending CONFIRM
        -- or PUSH is either a build mismatch or someone probing.
        local router, rejects = newRouter()

        router:_receive(FAKE_PLAYER, { kind = MessageKind.CONFIRM, eventId = "x" })
        router:_receive(FAKE_PLAYER, { kind = "NOT_A_KIND" })
        router:_receive(FAKE_PLAYER, {})

        a.equal(#router._buffer, 0)
        a.equal(#rejects, 0)
    end)

    t:case("buffered events carry a SERVER receive timestamp", function(a)
        -- The Event's own timestamp was set by whichever machine built it --
        -- the client, for inbound Requests -- so it crossed the wire and is
        -- not trustworthy (Part 13). Anything ordering-related uses this.
        local router = newRouter()
        local before = os.clock()
        router:_receive(FAKE_PLAYER, tapeOf(mk("MELEE")))
        local after = os.clock()

        local receivedAt = router._buffer[1].receivedAt
        a.isType(receivedAt, "number", "every buffered event needs a server timestamp")
        a.isTrue(receivedAt >= before and receivedAt <= after,
            "the stamp must come from the server clock, not the payload")
    end)

    t:case("a handler error does not stop the rest of the batch", function(a)
        local router = newRouter()
        local ran = 0
        router._routes[EventType.COMBAT] = function(_, event)
            -- This read `event:getData().n`, and `n` is not a CombatEvent
            -- field -- it was always nil, so the error never fired and BOTH
            -- events counted. targetId is what mk() actually sets.
            if event:getData().targetId == 1 then
                error("intentional handler failure")
            end
            ran += 1
        end

        router:_receive(FAKE_PLAYER, tapeOf(
            mk("MELEE", 1),
            mk("MELEE", 2)
        ))
        a.noThrow(function() router:drain() end, "drain must absorb a handler error")
        a.equal(ran, 1, "the event after the failing one must still route")
    end)

    t:case("resolveRoutes leaves an absent Service unroutable, without erroring", function(a)
        -- Absence is the mechanism, not a failure: a place that excludes a
        -- Service must load this registry cleanly (Part 13).
        local router = newRouter()
        a.noThrow(function()
            router:resolveRoutes({ [EventType.COMBAT] = { service = "NotHere", method = "OnAttack" } }, fixtures)
        end)
        a.isNil(router._routes[EventType.COMBAT], "an absent Service produces no route")
    end)

    t:case("resolveRoutes tolerates a nil services folder", function(a)
        local router = newRouter()
        a.noThrow(function()
            router:resolveRoutes({ [EventType.COMBAT] = { service = "FakeService", method = "OnAttack" } }, nil)
        end)
        a.isNil(router._routes[EventType.COMBAT])
    end)

    t:case("resolveRoutes fails boot when a present Service lacks the method", function(a)
        local router = newRouter()
        a.throws(function()
            router:resolveRoutes({ [EventType.COMBAT] = { service = "BrokenService", method = "OnAttack" } }, fixtures)
        end, "has no method")
    end)

    t:case("resolveRoutes rejects an undeclared eventType", function(a)
        local router = newRouter()
        a.throws(function()
            router:resolveRoutes({ MADE_UP = { service = "FakeService", method = "OnAttack" } }, fixtures)
        end, "not a declared eventType")
    end)

    -- Rate limiting ---------------------------------------------------------

    -- The budget is 100 tokens, one per EVENT, refilling at 50/sec. Four
    -- tapes of 25 spend it exactly; a fifth has nothing to draw on, because
    -- these calls are microseconds apart and refill is continuous.
    --
    -- The first version of these tests sent tapes of ONE event and expected
    -- ten of them to exhaust a hundred-token budget. They failed for the right
    -- reason: the limiter counts events, not messages.
    local function drainBudget(router)
        for _ = 1, 4 do
            router:_receive(FAKE_PLAYER, tapeOfSize(25))
        end
    end

    t:case("a sustained flood is rate limited, not merely capped per tape", function(a)
        -- The per-tape cap bounds ONE burst. It permits cap x framerate per
        -- second, which is why it was never enough on its own.
        local router, rejects = newRouter()

        drainBudget(router)
        a.equal(#rejects, 0, "spending the burst budget is legal")

        router:_receive(FAKE_PLAYER, tapeOfSize(25))
        a.equal(#rejects, 1, "past the budget the tape is refused")
        a.equal(rejects[1].reason, RejectReason.RATE_LIMITED)
    end)

    t:case("a refused tape is not buffered and does not cost budget", function(a)
        local router, rejects = newRouter()

        drainBudget(router)
        a.equal(#router._buffer, 100, "everything paid for reaches the buffer")

        router:_receive(FAKE_PLAYER, tapeOfSize(25))
        a.isTrue(#rejects >= 1, "the flood must be refused")
        a.equal(#router._buffer, 100, "and nothing refused is buffered")

        -- Deducting from a refused tape would dig a hole a spammer could
        -- never climb out of, staying locked out after it stopped.
        local bucket = router._buckets[FAKE_PLAYER]
        a.isTrue(bucket.tokens >= 0, "a refusal must never leave a negative balance")
    end)

    t:case("an oversized tape is answered, not silently dropped", function(a)
        -- It used to warn() and return, so every pending action in that tape
        -- sat until the client's 10s TIMEOUT sweep.
        local router, rejects = newRouter()

        router:_receive(FAKE_PLAYER, tapeOfSize(60))

        a.equal(#router._buffer, 0, "nothing oversized reaches the buffer")
        a.equal(#rejects, 1, "one reject for the tape, never one per event")
        a.equal(rejects[1].reason, RejectReason.OVERSIZED)
    end)

    t:case("the per-tape cap is checked before the budget", function(a)
        -- An oversized tape must not also drain tokens: it was refused before
        -- anything counted it, so charging for it would let a single bad
        -- message cost a legitimate client its whole budget.
        local router = newRouter()
        router:_receive(FAKE_PLAYER, tapeOfSize(60))
        a.isNil(router._buckets[FAKE_PLAYER], "an oversized tape never reaches the limiter")
    end)

    t:case("each player has their own budget", function(a)
        local router, rejects = newRouter()
        local other = { Name = "OtherPlayer" }

        drainBudget(router)
        router:_receive(FAKE_PLAYER, tapeOfSize(25))
        a.isTrue(#rejects >= 1, "the first player exhausted their budget")

        local before = #rejects
        router:_receive(other, tapeOfSize(25))
        a.equal(#rejects, before, "one player's flood must not throttle another")
    end)

    t:case("resolveRoutes rejects a malformed entry", function(a)
        local router = newRouter()
        a.throws(function()
            router:resolveRoutes({ [EventType.COMBAT] = "CombatService" }, fixtures)
        end, "entry must be")
    end)

    t:case("the shipped routing registry resolves cleanly", function(a)
        -- Whatever EventRoutingRegistry currently declares must resolve
        -- against this place, or boot is broken.
        local registry = require(testsFolder.Parent:WaitForChild("eventTape"):WaitForChild("EventRoutingRegistry"))
        local router = newRouter()
        a.noThrow(function()
            router:resolveRoutes(registry, testsFolder.Parent:FindFirstChild("services"))
        end)
    end)

    return t:run()
end
