-- src/shared/utils/signal/Signal.luau
--
-- A Fact broadcast primitive. See Architecture-Reference.md Part 11.5.
--
-- A Signal announces that something has already, unconditionally happened.
-- It carries no validation, makes no decision, and returns nothing.
-- Everything connected to it is a listener, every listener is called, and
-- none of them is ever asked to approve or reject anything -- that decision
-- was already made and finished by a Service before Fire was reached.
--
-- Signals never cross the client/server boundary. This class lives in
-- shared/ because both sides use it, not because a signal is ever
-- transmitted; the wire is EventTape, in both directions.
--
-- Gameplay code does not construct these directly. SignalService.declare()
-- builds one and hands the fire-capable reference to exactly one owner --
-- that return value IS the access control.
--
-- THE TYPES ARE AT THE BOTTOM OF THIS FILE, not here. See the note there.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

-- The instance shapes, declared before the methods so `self` can be annotated.
-- The metatable-carrying types (Connection, Signal) are still at the bottom,
-- because those have to come after the methods they expose.
type ConnectionState = {
    Connected: boolean,
    _signal: any,
    _fn: Listener,
}

type SignalState = {
    _name: string,
    _listeners: { Connection },
    _destroyed: boolean,
}

function Connection.Disconnect(self: ConnectionState)
    if not self.Connected then
        return
    end
    self.Connected = false

    local signal: SignalState? = self._signal
    self._signal = nil
    if not signal then
        return
    end

    local index = table.find(signal._listeners, self :: any)
    if index then
        table.remove(signal._listeners, index)
    end
end

-- `name` is always supplied in practice, and is used in every error and
-- warning this class emits. A listener that fails inside Fire's pcall is
-- close to untraceable without it.
function Signal.new(name: string?): Signal
    return setmetatable({
        _name = name or "<anonymous>",
        _listeners = {},
        _destroyed = false,
    }, Signal)
end

function Signal.GetName(self: SignalState): string
    return self._name
end

-- Returns a connection handle carrying :Disconnect(). Holding that handle is
-- the only way to remove a listener, deliberately: anything that wraps a
-- handler in a closure could otherwise never disconnect it, which is a
-- listener leak for anything whose lifetime is shorter than the signal's --
-- a dungeon instance subscribing per run, a UI panel, a spawned entity.
--
-- Connecting the same function twice creates two connections and fires it
-- twice. An earlier version silently ignored duplicate functions; that hid
-- double-registration bugs instead of surfacing them, and boot validation in
-- SignalService is where that class of mistake is caught now.
function Signal.Connect(self: SignalState, listener: Listener): Connection
    if self._destroyed then
        error(string.format(
            "[Signal] '%s': cannot connect to a destroyed signal", self._name), 2)
    end
    if type(listener) ~= "function" then
        error(string.format(
            "[Signal] '%s': Connect expects a function, got %s",
            self._name, typeof(listener)), 2)
    end

    local state: ConnectionState = {
        Connected = true,
        _signal = self,
        _fn = listener,
    }
    local connection = setmetatable(state, Connection)

    table.insert(self._listeners, connection)
    return connection
end

-- Broadcast to every connected listener. This is the only firing method:
-- there is no way to target one listener and no separate "handler" concept.
--
-- Listener order is connection order, which is boot order -- deterministic,
-- but implicit. A listener must not mutate state another listener on the
-- same signal reads. If ordered reactions are ever genuinely needed, that is
-- evidence the relationship was inherent rather than optional, and belongs
-- in a direct call or a pipeline instead (Part 11.4).
function Signal.Fire(self: SignalState, ...: any)
    if self._destroyed then
        warn(string.format("[Signal] '%s': fired after being destroyed", self._name))
        return
    end

    -- Snapshot before iterating, so a listener that connects or disconnects
    -- during the broadcast cannot cause another listener to be skipped or
    -- fired twice. The Connected check inside the loop is what makes a
    -- mid-broadcast Disconnect actually take effect for listeners this
    -- broadcast has not reached yet.
    local snapshot = table.clone(self._listeners)

    for _, connection in ipairs(snapshot) do
        if connection.Connected then
            -- Each listener is isolated: one failing listener must never
            -- stop the others, because the fact being announced is true
            -- regardless of who mishandles it.
            local ok, err = pcall(connection._fn, ...)
            if not ok then
                warn(string.format(
                    "[Signal] '%s': listener errored: %s", self._name, tostring(err)))
            end
        end
    end
end

function Signal.DisconnectAll(self: SignalState)
    for _, connection in ipairs(self._listeners) do
        connection.Connected = false
        connection._signal = nil
    end
    table.clear(self._listeners)
end

function Signal.Destroy(self: SignalState)
    if self._destroyed then
        return
    end
    Signal.DisconnectAll(self)
    self._destroyed = true
end

-- Types -----------------------------------------------------------------
--
-- DECLARED AT THE BOTTOM ON PURPOSE. `typeof(setmetatable({}, Signal))`
-- resolves against the Signal table as it stands at that point in the file --
-- put these above the method definitions and the resulting types would carry
-- the fields but none of the methods. Type ALIASES are order-independent, so
-- `Signal.new(): Signal` above still resolves; only the typeof() needs to be
-- last.

-- A Fact listener. Signals return nothing and are never asked to approve
-- anything, so the return type is deliberately `()`, not `any`.
export type Listener = (...any) -> ()

-- The handle Connect returns. Holding it is the only way to disconnect.
--
-- Its `_signal` field is typed `any` in ConnectionState above, to break the
-- mutual reference between these two aliases. Nothing outside this file reads
-- it; the public surface is Connected and Disconnect.
export type Connection = typeof(setmetatable({} :: ConnectionState, Connection))

export type Signal = typeof(setmetatable({} :: SignalState, Signal))

return Signal
