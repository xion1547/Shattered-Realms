-- src/shared/remoteEvents/RemoteEventsEnum.luau
--
-- ONE centralized RemoteEvent, not one per domain. See
-- Architecture-Reference.md Part 12.
--
-- The previous model created a RemoteEvent per eventType, which gave each
-- domain its own independent ordering guarantee and therefore no ordering
-- guarantee at all across domains -- two events a player fired in sequence
-- could arrive out of order because they travelled on different instances.
-- One instance carrying eventType as a data field is what makes arrival
-- order meaningful.
--
-- It also never actually worked: EventTapeController asked for a RemoteEvent
-- named after the eventType ("COMBAT"), while this enum only ever declared
-- "GlobalCombatRemoteEvent", so the lookup asserted on the first event.

local RemoteEventsEnum = {
    EventTapeRemote = "EventTapeRemote",
}

return table.freeze(RemoteEventsEnum)
