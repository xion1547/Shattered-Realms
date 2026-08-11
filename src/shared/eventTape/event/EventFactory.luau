-- src/shared/eventTape/event/EventFactory.luau
--
-- THE ONE DOOR FOR CREATING EVENTS.
--
--     local EventFactory = require(ReplicatedStorage.eventTape.event.EventFactory)
--     local CombatEvent = require(ReplicatedStorage.eventTape.event.types.CombatEvent)
--
--     EventFactory.create(CombatEvent)
--         :withSubType(CombatEvent.SubType.SKILL)
--         :withTargetId("ENEMY_1")
--         :withSkillId("CLEAVE")
--         :build()
--
-- WHAT THIS IS, precisely, so it is not mistaken for something larger: a
-- named entry point, closer to `Stream.of(x)` than to a Java/Spring factory.
-- A real factory earns its name by DECIDING which concrete thing to build
-- from an abstract input -- that decision is its product. Here the caller
-- passes CombatEvent, which is the answer to the only question a factory
-- could have asked, so there is nothing left to decide and `create` forwards.
-- That is fine, and it is the whole file. It reads better at the call site
-- and gives event creation one obvious door.
--
-- WHY FLUENT: the methods ARE the documentation. Type a colon and Studio
-- lists exactly what this event accepts, with the argument type on each one.
-- A payload table gives you nothing until you already know the field names,
-- and `{ id = "asdf" }` looks identical whether it is right or wrong.
--
-- `CombatEvent.Builder.new()` is the identical call and is always statically
-- resolvable. If your editor ever loses the chain through the generic below,
-- drop to the direct form -- they are the same object.
--
-- THERE USED TO BE A `builder()` FUNCTION on every event module whose entire
-- body was `return Builder.new()`. It is gone. It bought nothing that
-- `Builder.new()` does not, and it cost a `Builder` / `builder` pair on the
-- same table differing only by case -- two members, one required and one
-- ceremonial, that read as though they were related.
--
-- BOOT VALIDATION LIVES IN EventRegistry, not here. It used to sit in this
-- file under the name `preload`, which was a fossil: the old deserializer
-- genuinely preloaded modules off the DataModel, and once EventRegistry
-- started requiring every class statically there was nothing left to load.
-- What it actually does is check declarations, so it moved to the registry
-- that owns them and is called `validate`.

local EventFactory = {}

-- Generic rather than taking Event.EventModule, and that is the whole point of
-- the signature: T flows through, so the returned builder keeps its concrete
-- per-type identity and every :withX() after it autocompletes. Widening the
-- parameter to EventModule would collapse every type's builder to one shape
-- and erase exactly that.
function EventFactory.create<T>(eventClass: { Builder: { new: () -> T } }): T
    if type(eventClass) ~= "table" or type(eventClass.Builder) ~= "table"
        or type(eventClass.Builder.new) ~= "function" then
        error("[EventFactory] create expects an event class, e.g. CombatEvent", 2)
    end
    return eventClass.Builder.new()
end

return EventFactory
