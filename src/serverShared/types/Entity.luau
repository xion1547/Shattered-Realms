-- src/serverShared/types/Entity.luau
--
-- What every entity has in common, and nothing more.
-- See Architecture-Reference.md Part 7.
--
-- TYPES ONLY. This module returns an empty table on purpose -- it exists so
-- other files can write `Entity.Entity` in an annotation, not to be called.
--
-- WHY THE SHAPE IS THIS SMALL. Composition means there is no fixed entity
-- shape: a player has resources and equipment, an enemy has aiState and a
-- loot table, a friendly NPC may have neither. The only thing universally
-- true is that an entity has an identity. Anything richer would be a lie
-- about some entity type.
--
-- Luau is STRUCTURALLY typed, so PlayerEntity and EnemyEntity satisfy this
-- without declaring that they implement anything -- and so does a bare
-- `{ identity = ... }` table, which is what the targeting tests build. That
-- is deliberate: a module should demand the least it can get away with.
--
-- Note there is no `getId` here. Entities used to carry a convenience method
-- that forwarded to the component, which meant two valid spellings for one
-- value. It was removed; `entity.identity:getId()` is the only path.
--
-- GROWING THIS IS ADDITIVE. When the other components export their own
-- types, they join as OPTIONAL fields -- optional because composition
-- guarantees nothing beyond identity:
--
--     export type Entity = {
--         identity: IdentityComponent.Identity,
--         spatial: SpatialComponent.Spatial?,
--         resources: ResourcesComponent.Resources?,
--     }
--
-- A `?` field still needs a runtime check at the boundary that requires it,
-- which is why SpatialService:attach asserts rather than trusting a type.

local ServerStorage = game:GetService("ServerStorage")
local components = ServerStorage:WaitForChild("Shared"):WaitForChild("components")

local IdentityComponent = require(components:WaitForChild("IdentityComponent"))

export type Entity = {
    identity: IdentityComponent.Identity,

    -- OPTIONAL, following this file's own rule about how it grows. Both real
    -- entity classes define it, but the targeting tests satisfy this type with
    -- a bare `{ identity = ... }` table and should keep being able to.
    --
    -- EntityService:deleteEntity calls it when present. That is the only
    -- caller -- destroy is teardown, and teardown has one door.
    destroy: ((Entity) -> ())?,
}

return {}
