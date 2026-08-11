-- src/serverShared/signal/SignalVocabulary.luau
--
-- The server-side signal VOCABULARY, shared across every place in the
-- experience: the flat list of fact names legal to declare or subscribe to
-- on the server. See Architecture-Reference.md Part 11.5.
--
-- SERVER-ONLY, and deliberately so. This is the complete list of every
-- internal event name in the game -- exactly the "internal shape" Part 13
-- says a client should never be able to enumerate. It lives in ServerStorage,
-- which is never replicated. The client keeps its own separate vocabulary of
-- client-local facts (input mode changed, cinematic started, panel opened),
-- because a Signal never crosses the boundary in either direction.
--
-- Renamed from GlobalRegistry. That name described a table of live Signal
-- objects, which is what this used to be and is exactly the problem: anything
-- that required it could fire any fact in the game. It holds names now, and
-- fire capability comes from the return value of SignalService.declare().
--
-- A name here is a promise that something declares it in every place this
-- vocabulary is loaded into. SignalService.validate() enforces that in both
-- directions at boot, so a name cannot be added before its owner exists.
--
-- Place-specific facts (Combat.*, Boss.*) belong in a place-specific
-- vocabulary passed alongside this one, not in this file.

return {
    "Player.Session.OnJoined",
    "Player.Session.OnLeft",
}

-- Planned, deliberately NOT listed above until an owner exists to declare
-- them -- adding a name with nothing declaring it fails boot, by design:
--
--   Player.Resources.<id>.OnChanged   generated at boot from
--                                     ResourceDefinitions once ResourceService
--                                     grows a real grant/drain (Part 8) --
--                                     never hand-written, one per resource,
--                                     for free
--   Player.Progression.OnLevelUp      LevelService
--   Player.Inventory.OnItemAdded      InventoryService
--   Player.Inventory.OnItemRemoved    InventoryService
--   Combat.OnHit / OnKill / OnParrySuccess   CombatService
