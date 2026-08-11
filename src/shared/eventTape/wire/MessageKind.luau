-- src/shared/eventTape/wire/MessageKind.luau
--
-- What kind of thing is crossing the wire. Shared so neither side writes the
-- string literal twice and misspells it once.
--
-- Every payload over the EventTape remote is an envelope: `{ kind = ..., ... }`.
-- The kind is what the receiver switches on before it knows how to read the
-- rest, which is why it is the one field every message has.

-- A string literal union, so a mistyped kind is caught where it is written
-- rather than by a receiver silently failing to match it.
export type Kind = "TAPE" | "REJECT" | "CONFIRM" | "PUSH"

local MessageKind = {
    -- client -> server
    TAPE = "TAPE",          -- a batch of serialized Events, in send order

    -- server -> client
    REJECT = "REJECT",      -- one event refused; carries eventId + reason
    CONFIRM = "CONFIRM",    -- one event succeeded; carries eventId + the diff
                            --   of what ACTUALLY changed, built from what the
                            --   commits returned (Part 11.1)
    PUSH = "PUSH",          -- unsolicited: something happened that this client
                            --   did not ask for (another player's hit, a boss
                            --   telegraph). No eventId, nothing pending.
}

function MessageKind.isValid(kind: any): boolean
    return type(kind) == "string" and rawget(MessageKind, kind) ~= nil
end

return table.freeze(MessageKind)
