-- Signal class
local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({}, Signal)
    self.listeners = {}  -- Table to hold connected listeners
    return self
end

-- Connect a function to the signal
function Signal:Connect(listener)
    -- Add the listener function to the listeners table
    table.insert(self.listeners, listener)
end

-- Fire the signal, triggering all connected listeners
function Signal:Fire(...)
    for _, listener in ipairs(self.listeners) do
        listener(...)  -- Call each listener with the provided arguments
    end
end

-- Disconnect a specific listener from the signal
function Signal:Disconnect(listener)
    for i, registeredListener in ipairs(self.listeners) do
        if registeredListener == listener then
            -- Remove the listener from the table
            table.remove(self.listeners, i)
            break  -- No need to continue once we've found the listener
        end
    end
end

return Signal
