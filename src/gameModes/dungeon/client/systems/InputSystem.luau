-- src/gameModes/dungeon/client/systems/InputSystem.luau
--
-- INPUT BECOMES INTENT, and nothing else happens here.
--
-- This file may say "I pressed attack" and "I was pointing at that". It may
-- never say how far the swing reached, what it hit, or how much it hurt --
-- the server owns all of that and would ignore it anyway (Part 13). If a
-- change to this file ever needs to know a hitbox size, the change is wrong.
--
-- There is deliberately no prediction and no optimistic damage number. Those
-- are the client rewrite's job, and adding them before the server half is
-- trustworthy makes every bug ambiguous between "the server disagreed" and
-- "the client lied to me".
--
-- THE SWING ANIMATION IS THE ONE EXCEPTION, added 2026-08-23, and it is not a
-- softening of that rule. Playing a clip predicts NOTHING: it changes no state,
-- claims no hit, and is not a number that could later be found wrong. The
-- server neither hears about it nor cares. If the swing is rejected the clip
-- was a lie told to one screen for 300ms, which is the entire cost.
--
-- >>> THE `_rig` WIRING IS FLAGGED FOR REPLACEMENT 2026-08-23. <<< The clip
-- call goes through the Conductor once it exists -- it is the single door for
-- client-side animation, so a system reaching past it to an Animator is the
-- thing that door exists to prevent. The CALL SITE is right; what it calls is
-- temporary.
--
-- It is here rather than deferred because the round trip is real and the weapon
-- has to feel immediate. An animation that waits for the server IS the input
-- lag it would otherwise be hiding.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event")
local EventFactory = require(eventFolder:WaitForChild("EventFactory"))
local CombatEvent = require(eventFolder:WaitForChild("types"):WaitForChild("CombatEvent"))

-- Prints the event id on send so it can be matched against what the server
-- logs on arrival -- that match is what proves the wire end to end, rather
-- than "something arrived". Off now that it has; flip it on when a change to
-- the send path needs proving again.
local VERBOSE = false

local InputSystem = {}
InputSystem.__index = InputSystem

function InputSystem.new(eventTape, rig)
    assert(eventTape, "[InputSystem] needs the EventTapeClient to send through")

    return setmetatable({
        _eventTape = eventTape,

        -- OPTIONAL. Nil means no clip plays and the attack still resolves
        -- normally -- the swing is a server fact and the animation is a picture
        -- of it. Keeping this optional is also what lets the send path be
        -- tested with no rig at all.
        _rig = rig,

        _mouse = Players.LocalPlayer:GetMouse(),
        _connection = nil,
    }, InputSystem)
end

function InputSystem:start()
    assert(not self._connection, "[InputSystem] already started")

    self._connection = UserInputService.InputBegan:Connect(function(input, processedByUI)
        -- True when the click landed on a GUI element. Without this, every
        -- button press in the HUD also swings the sword.
        if processedByUI then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:_attack(CombatEvent.SubType.MELEE, "swing", "WARRIOR_SWING_1")
        elseif input.KeyCode == Enum.KeyCode.One then
            self:_attack(CombatEvent.SubType.AOE, "cleave")
        elseif input.KeyCode == Enum.KeyCode.Two then
            self:_attack(CombatEvent.SubType.RANGED, "thrust")
        end
    end)
end

function InputSystem:stop()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

-- THREE BINDS, THREE VOLUME SHAPES, and the second and third are TEMPORARY.
--
--   click  MELEE   the arc         the real attack
--   1      AOE     a wide box      a horizontal cleave, to exercise BOX
--   2      RANGED  a long capsule  a forward thrust, to exercise CAPSULE
--
-- The subtypes are borrowed rather than fitted: a thrust is not really
-- "RANGED". They exist so the server can tell the three apart without a new
-- event type, and they go away with the mock volumes in CombatService.
--
-- THIS FILE STILL KNOWS NOTHING ABOUT SHAPE. It sends "I pressed 1"; which
-- volume that means lives on the server, where the reach and the size stay
-- out of a client's reach (Part 13).
function InputSystem:_attack(subType: string, label: string, clip: string?)
    -- BEFORE THE SEND, DELIBERATELY. Not for speed -- these are microseconds
    -- apart -- but because the ordering states the relationship: the clip is
    -- not waiting on anything and never will be. Written after the send, the
    -- next person to read it has to work out whether it is a response.
    --
    -- THE CLIP NEVER CROSSES THE WIRE. What goes out is "I pressed attack";
    -- which animation that looked like is a private rendering decision this
    -- machine made. That is what keeps a new animation from being a server
    -- change (Animation.md Part 14).
    if clip and self._rig then
        self._rig:play(clip)
    end

    local builder = EventFactory.create(CombatEvent)
        :withSubType(subType)

    local targetId = self:_pointedAtId()
    if targetId then
        builder = builder:withTargetId(targetId)
    end

    -- sendNow rather than queue: batching saves a remote call per frame, and
    -- an attack is precisely the input where a frame of added latency costs
    -- more than the call does.
    local eventId = self._eventTape:sendNow(builder:build(), label)

    if VERBOSE then
        print(string.format("[InputSystem] %s sent  event=%s  pointingAt=%s",
            label, tostring(eventId), targetId and tostring(targetId) or "nothing"))
    end
end

-- What the cursor is over, if anything.
--
-- SENT AS A HINT, NOT A TARGET. The server resolves its own volume and uses
-- this only to break ties on a capped skill. That is why no checking is done
-- here: a name that matches no entity matches nothing on the server either,
-- and lying about it can at worst pick a different enemy that was genuinely
-- inside the swing. Nothing to gain, so nothing to guard.
--
-- It works because DummySpawner names each part after its entity id. Real
-- enemies will need the id somewhere more deliberate than the instance name
-- -- an attribute on the model -- but that is a spawner change, not one here.
function InputSystem:_pointedAtId(): string?
    local target = self._mouse.Target
    return target and target.Name or nil
end

return InputSystem
