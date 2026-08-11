-- src/shared/eventTape/event/types/InventoryEvent.luau
--
--     EventFactory.create(InventoryEvent)
--         :withSubType(InventoryEvent.SubType.LOOT)
--         :build()
--
-- No parameters declared yet, so no :withX() methods and an empty schema --
-- which means an INVENTORY event carrying any payload is rejected. That is
-- deliberate: an undesigned schema should refuse everything, not accept
-- anything. Add fields here with their methods when the payload is designed.

local Event = require(script.Parent.Parent.Event)
local EventBuilder = require(script.Parent.Parent.EventBuilder)
local EventSchema = require(script.Parent.Parent.EventSchema)
local EventType = require(script.Parent.Parent.EventType)

local InventoryEvent = {}

InventoryEvent.eventType = EventType.INVENTORY

InventoryEvent.SubType = table.freeze({
    LOOT = "LOOT",
    USE = "USE",
    DROP = "DROP",
    EQUIP_GEAR = "EQUIP_GEAR",
    UNEQUIP_GEAR = "UNEQUIP_GEAR",
    -- Echo slots are Equipment slots like any other (Part 7), so these route
    -- through the same domain rather than a pet-specific eventType. There is
    -- no PET eventType and should not be one -- an entity type is not a
    -- domain.
    EQUIP_ECHO = "EQUIP_ECHO",
    UNEQUIP_ECHO = "UNEQUIP_ECHO",
})

local schema: EventSchema.Schema = {}

InventoryEvent.schema = schema

local Builder = EventBuilder.extend(InventoryEvent)
InventoryEvent.Builder = Builder

-- Conformance check -- see the note in CombatEvent.
local _conforms: Event.EventModule = InventoryEvent

return InventoryEvent
