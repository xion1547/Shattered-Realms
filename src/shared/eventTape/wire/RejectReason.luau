-- src/shared/eventTape/wire/RejectReason.luau
--
-- Why the server refused an event. Shared so the client can branch on a
-- constant instead of matching a string the server might rename.
--
-- The split that matters: the first three are the client (or something
-- pretending to be one) sending a shape the server will not accept. ILLEGAL
-- is the only one where the message was well-formed and the ACTION was
-- refused -- which is the only one a legitimate player will ever see, and
-- therefore the only one worth surfacing in the UI.

-- WHAT IS ACTUALLY SENT TODAY: all four structural reasons, every one from
-- EventRouter. ILLEGAL is the only one with no sender, and it is not missing
-- code so much as missing a caller -- it is the one reason a SERVICE produces,
-- and every Service is currently a stub.

export type Reason = "MALFORMED" | "UNROUTABLE" | "OVERSIZED" | "RATE_LIMITED" | "ILLEGAL"

local RejectReason = {
    -- Structural: a real client should never produce these. Every one is
    -- refused before any game logic runs, and the tape-level ones send ONE
    -- reject for the whole tape rather than one per event -- see EventRouter,
    -- where answering every id would hand an attacker amplification.
    MALFORMED = "MALFORMED",         -- failed deserialization or validation
    UNROUTABLE = "UNROUTABLE",       -- no Service owns this eventType here
    OVERSIZED = "OVERSIZED",         -- tape past the per-tape BURST cap
    RATE_LIMITED = "RATE_LIMITED",   -- past the SUSTAINED per-player budget

    -- Behavioural: well-formed, but the game said no.
    ILLEGAL = "ILLEGAL",             -- e.g. skill on cooldown, out of range,
                                     --   target already dead, cannot act
}

function RejectReason.isValid(reason: any): boolean
    return type(reason) == "string" and rawget(RejectReason, reason) ~= nil
end

-- Structural rejections mean something is wrong with the client build or
-- someone is probing the server. Worth logging loudly; never worth an
-- in-game message, because a legitimate player cannot cause one.
function RejectReason.isStructural(reason: any): boolean
    return reason ~= RejectReason.ILLEGAL and RejectReason.isValid(reason)
end

return table.freeze(RejectReason)
