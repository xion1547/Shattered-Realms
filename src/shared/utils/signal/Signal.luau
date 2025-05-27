-- src/shared/utils/signal/Signal.lua
local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({}, Signal)
    self.listeners = {}  -- Table to hold connected listeners
    self._isSignal = true -- Flag to identify this as a Signal object
    self._destroyed = false
    return self
end

-- Connect a function to the signal
function Signal:Connect(listener)

    if self._destroyed then
        error("[Signal] Cannot connect to a destroyed signal.")
    end
    
    -- Prevent adding duplicate listeners
    for _, registeredListener in ipairs(self.listeners) do
        if registeredListener == listener then
            return  -- Listener already connected
        end
    end

    table.insert(self.listeners, listener)
end

-- Fire the signal, triggering a specific listener if provided
function Signal:Fire(listener, ...)
    if listener then
        -- If a listener is provided, only fire that listener
        for _, registeredListener in ipairs(self.listeners) do
            if registeredListener == listener then
                registeredListener(...)  -- Call the specific listener with the provided arguments
                return  -- Exit once the specific listener is fired
            end
        end
        warn("[Signal] The provided listener was not found in the signal's listeners.")
    end
end

-- Disconnect a specific listener from the signal
function Signal:Disconnect(listener)
    if self._destroyed then
        warn("[Signal] Attempted to disconnect from a destroyed signal.")
        return false
    end

    for i, registeredListener in ipairs(self.listeners) do
        if registeredListener == listener then
            table.remove(self.listeners, i)
            return true
        end
    end

    return false
end

-- Disconnect all listeners from the signal
function Signal:DisconnectAll()
    if self._destroyed then return end

    -- Use table.clear if available (LuaU supported)
    if table.clear then
        table.clear(self.listeners)
    else
        for i = #self.listeners, 1, -1 do
            self.listeners[i] = nil
        end
    end
end

-- Clean up the signal and prevent future use
function Signal:Destroy()
    if self._destroyed then return end
    self:DisconnectAll()
    self.listeners = nil
    self._destroyed = true
end

return Signal
