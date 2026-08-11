-- DRIVER. One tick harness for every entity carrying an AIState component.
-- See Architecture-Reference.md Parts 10 and 14.
--
-- This replaces BossAIService and PetAIService. Both did the same four
-- things -- tick, read aiState, gate on StateService, emit an Intention --
-- and differed only in the DECISION function, which is already content
-- (`template.aiProfile`). Per-creature pacing is a profile field, not a
-- second Service and not a second Scheduler row.
--
-- Structurally a client of the Service layer rather than a member of it: it
-- decides something should happen, then goes through the same doors a player
-- Request would.

local AIService = {}

AIService._entities = {}    -- entityId -> entity
AIService._profiles = {}    -- profileId -> decision module

function AIService:boot()
    -- TODO: load decision modules behind a flat table, the same shape as
    -- EffectHandlers -- a declared map, not folder discovery.
end

function AIService:register(entity)
    assert(entity.aiState, "[AIService] entity has no AIState component")
    self._entities[entity.identity:getId()] = entity
end

function AIService:unregister(entity)
    self._entities[entity.identity:getId()] = nil
end

-- Scheduler entry point. Per-entity gating is this service's job, never the
-- Scheduler's: the Scheduler only knows "call tick at 10Hz" and has no
-- concept of individual entities, instances or flags.
function AIService:tick(deltaTime)
    local now = os.clock()

    for _, entity in pairs(self._entities) do
        -- A frozen or dying entity does not think. One shared gate rather
        -- than a per-service reimplementation of the same check.
        -- TODO: if not StateService:canAct(entity) then continue end

        if entity.aiState:isDue(now) then
            -- TODO: local decision = self._profiles[entity.aiState:getProfile()]
            -- TODO: emit the resulting Intention through the normal Service
            --       call path, then entity.aiState:markDecided(now, interval)
        end
    end
end

return AIService
