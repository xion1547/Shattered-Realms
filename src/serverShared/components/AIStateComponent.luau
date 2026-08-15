-- src/shared/components/AIStateComponent.luau
--
-- FSM state for anything AIService drives. See Architecture-Reference.md
-- Parts 7 and 10.
--
-- Attached to enemies, bosses and pets alike -- one AIService ticks every
-- entity carrying this component, with the decision function selected by
-- `profile` from the Content Layer. That is why there is no BossAIService
-- and no PetAIService.

local AIStateComponent = {}
AIStateComponent.__index = AIStateComponent

function AIStateComponent.new(profile)
    return setmetatable({
        _profile = profile,          -- Content Layer key selecting a decision module
        _state = "IDLE",             -- IDLE | TELEGRAPHING | ATTACKING | STAGGERED | ...
        _aggroTargetId = nil,
        _queuedMove = nil,
        _lastDecisionAt = 0,
        _nextDecisionAt = 0,
    }, AIStateComponent)
end

function AIStateComponent:getProfile()
    return self._profile
end

function AIStateComponent:getState()
    return self._state
end

function AIStateComponent:setState(state)
    assert(type(state) == "string", "[AIStateComponent] state must be a string")
    self._state = state
end

function AIStateComponent:getAggroTargetId()
    return self._aggroTargetId
end

function AIStateComponent:setAggroTargetId(targetId)
    self._aggroTargetId = targetId
end

function AIStateComponent:getQueuedMove()
    return self._queuedMove
end

function AIStateComponent:queueMove(move)
    self._queuedMove = move
end

function AIStateComponent:consumeQueuedMove()
    local move = self._queuedMove
    self._queuedMove = nil
    return move
end

-- Per-profile pacing lives here, not in the Scheduler: the Scheduler ticks
-- AIService at one rate and AIService skips whatever is not due.
function AIStateComponent:isDue(now)
    return now >= self._nextDecisionAt
end

function AIStateComponent:markDecided(now, interval)
    self._lastDecisionAt = now
    self._nextDecisionAt = now + (interval or 0)
end

return AIStateComponent
