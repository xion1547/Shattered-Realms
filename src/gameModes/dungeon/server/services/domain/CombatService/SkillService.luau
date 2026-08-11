-- src/gameModes/dungeon/server/services/domain/SkillService.luau
--
-- Sub-domain of CombatService, not a sibling of it.
-- See Architecture-Reference.md Part 10.
--
-- The coupling is conceptual, not contingent: a skill is BY DEFINITION a
-- combat concept, and combat resolution needs to know what a skill does.
-- Splitting them into independent top-level Services would just recreate a
-- circular dependency between them.
--
-- Owns skill unlock state, cooldowns, and skill-tree node effects. Cooldowns
-- live here rather than anywhere pet-shaped: a pet activating an ultimate is
-- the same call a player makes, with a different entity.

local SkillService = {}

SkillService._cooldowns = {}   -- entityId -> skillId -> readyAt

function SkillService:boot()
    -- Nothing to declare: skill Facts are Combat's.
end

-- QUERY.
function SkillService:isUnlocked(entity, skillId)
    -- TODO
    return false
end

function SkillService:isReady(entity, skillId)
    local perEntity = self._cooldowns[entity.identity:getId()]
    local readyAt = perEntity and perEntity[skillId]
    return readyAt == nil or os.clock() >= readyAt
end

-- MUTATION.
function SkillService:activate(entity, skillId, targetId)
    -- TODO: check unlocked + ready, read the skill definition, hand an
    -- activation to CombatService.resolveAttack. Works identically for a
    -- player, a pet or a boss -- if this ever needs to branch on entity
    -- type, something has drifted.
    return false, "NOT_IMPLEMENTED"
end

function SkillService:startCooldown(entity, skillId, duration)
    local entityId = entity.identity:getId()
    local perEntity = self._cooldowns[entityId]
    if not perEntity then
        perEntity = {}
        self._cooldowns[entityId] = perEntity
    end
    perEntity[skillId] = os.clock() + duration
end

return SkillService
