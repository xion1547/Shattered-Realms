-- src/shared/components/AIState.luau
--
-- FSM state for anything AIService drives. See Architecture-Reference.md
-- Parts 7 and 10.
--
-- Attached to enemies, bosses and pets alike -- one AIService ticks every
-- entity carrying this component, with the decision function selected by
-- `profile` from the Content Layer. That is why there is no BossAIService
-- and no PetAIService.

local AIState = {}
AIState.__index = AIState

function AIState.new(profile)
    return setmetatable({
        _profile = profile,          -- Content Layer key selecting a decision module
        _state = "IDLE",             -- IDLE | TELEGRAPHING | ATTACKING | STAGGERED | ...
        _aggroTargetId = nil,
        _queuedMove = nil,
        _lastDecisionAt = 0,
        _nextDecisionAt = 0,
    }, AIState)
end

function AIState:getProfile()
    return self._profile
end

function AIState:getState()
    return self._state
end

function AIState:setState(state)
    assert(type(state) == "string", "[AIState] state must be a string")
    self._state = state
end

function AIState:getAggroTargetId()
    return self._aggroTargetId
end

function AIState:setAggroTargetId(targetId)
    self._aggroTargetId = targetId
end

function AIState:getQueuedMove()
    return self._queuedMove
end

function AIState:queueMove(move)
    self._queuedMove = move
end

function AIState:consumeQueuedMove()
    local move = self._queuedMove
    self._queuedMove = nil
    return move
end

-- Per-profile pacing lives here, not in the Scheduler: the Scheduler ticks
-- AIService at one rate and AIService skips whatever is not due.
function AIState:isDue(now)
    return now >= self._nextDecisionAt
end

function AIState:markDecided(now, interval)
    self._lastDecisionAt = now
    self._nextDecisionAt = now + (interval or 0)
end

return AIState
