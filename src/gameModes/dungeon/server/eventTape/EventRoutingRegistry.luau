-- src/gameModes/dungeon/server/eventTape/EventRoutingRegistry.luau
--
-- SERVER ONLY. The single place a developer can read the entire map of
-- "which Service handles which incoming top-level eventType."
-- See Architecture-Reference.md Part 12.
--
-- One row per top-level domain, never one per subType -- dispatch within a
-- domain (MELEE vs RANGED) is that domain's own business once it has been
-- handed the Event.
--
-- Entries are DECLARATIVE DATA -- a service module name and a method name,
-- never an eager require(). A place that excludes a Service (the Hub has no
-- CombatService) must not error merely by loading this file; EventRouter
-- resolves each entry lazily against the services actually present in this
-- place, and an entry whose module is absent is simply not routable here.
-- That is the mechanism behind "absence is stronger than disconnection"
-- (Part 13): a COMBAT event arriving where Combat does not exist is
-- rejected as UNROUTABLE, by structure, with no null service to mock.
--
-- ANIMATION is deliberately absent and should stay absent. Animation is a
-- client rendering concern (the server sends what happened, the client picks
-- the animation); there is no AnimationService to route to.
--
-- KEYS ARE EventType CONSTANTS, not literals. Requiring the enum here is safe
-- and does not violate the no-eager-require rule above -- that rule is about
-- SERVICES, whose absence in a place is meaningful. EventType is a shared
-- vocabulary that exists identically everywhere. Service and method stay
-- strings because they name modules that may not exist in this place, which is
-- the entire point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventFolder = ReplicatedStorage:WaitForChild("eventTape"):WaitForChild("event")
local EventType = require(eventFolder:WaitForChild("EventType"))

return {
    [EventType.COMBAT]    = { service = "CombatService",    method = "OnAttack" },
    [EventType.INVENTORY] = { service = "InventoryService", method = "OnAction" },
    [EventType.SESSION]   = { service = "SessionService",   method = "OnAction" },
}
