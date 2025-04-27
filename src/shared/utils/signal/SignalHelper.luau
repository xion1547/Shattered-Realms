-- src/shared/utils/signal/SignalHelper.lua
local SignalService = require(game:GetService("ReplicatedStorage"):WaitForChild("utils"):WaitForChild("signal"):WaitForChild("SignalService"))
local SignalHelper = {}

-- Cache frequently used functions for performance
local warn = warn
local tableConcat = table.concat
local typeof = typeof
local pcall = pcall

-- Safe Connect for signals with enhanced error handling
function SignalHelper.SafeConnect(signal, callback, signalPath)
    if typeof(callback) ~= "function" then
        warn("[SignalHelper] Tried to connect a non-function callback to signal:", signalPath or "unknown")
        return nil
    end

    if not (signal and signal.Connect) then
        warn("[SignalHelper] Invalid signal object provided for path:", signalPath or "unknown")
        return nil
    end

    local success, connection = pcall(function()
        return signal:Connect(callback)
    end)

    if not success then
        warn("[SignalHelper] Failed to connect callback to signal", signalPath or "unknown", ":", connection)
        return nil
    end

    return connection
end

-- Optimized AutoConnectAll with O(1) path tracking
function SignalHelper.AutoConnectAll(registry, currentPath, systemRoot)
    currentPath = currentPath or {}
    systemRoot = systemRoot or game.ServerScriptService:WaitForChild("Server"):WaitForChild("system")
    
    if not systemRoot then
        warn("[SignalHelper] System root not found:", systemRoot and systemRoot:GetFullName() or "nil")
        return
    end

    for key, value in pairs(registry) do
        if typeof(key) ~= "string" then
            warn("[SignalHelper] Non-string key in registry:", key)
            continue
        end

        -- Track path depth by modifying then restoring
        table.insert(currentPath, key)

        if typeof(value) == "table" then
            if value._isSignal then
                SignalHelper.ConnectSignal(currentPath, value, systemRoot)
            else
                SignalHelper.AutoConnectAll(value, currentPath, systemRoot)
            end
        else
            warn(string.format(
                "[SignalHelper] Unexpected value type '%s' at path: %s", 
                typeof(value), 
                SignalHelper.formatPath(currentPath)
            ))
        end

        -- Backtrack path
        table.remove(currentPath)
    end
end

-- ConnectSignal remains unchanged from previous optimized version
function SignalHelper.ConnectSignal(pathParts, signal, systemRoot)
    local signalPath = table.concat(pathParts, ".")
    local methodName = pathParts[#pathParts]
    local subPathParts = {table.unpack(pathParts, 1, #pathParts - 1)}
    local managerName = subPathParts[#subPathParts] .. "Manager"
    
    local modulePath = systemRoot
    local traversalLog = {modulePath:GetFullName()}
    local foundSubsystem = false

    -- Traverse path with subsystem awareness
    for i, part in ipairs(subPathParts) do
        -- First try exact case match
        local nextFolder = modulePath:FindFirstChild(part)
        
        -- If not found, try lowercase (optional)
        if not nextFolder then
            nextFolder = modulePath:FindFirstChild(string.lower(part))
        end

        if not nextFolder then
            warn(string.format(
                "[SignalHelper] Path traversal failed - cannot find '%s' under %s (path: %s)",
                part,
                modulePath:GetFullName(),
                signalPath
            ))
            return
        end

        modulePath = nextFolder
        table.insert(traversalLog, modulePath:GetFullName())

        -- Special case: Only enter subSystem if we're not at the manager level
        -- (i.e., don't enter subSystem for the immediate parent of the signal)
        if i < #subPathParts then
            local subSystem = modulePath:FindFirstChild("subSystem")
            if subSystem then
                modulePath = subSystem
                foundSubsystem = true
                table.insert(traversalLog, "-> subSystem:" .. modulePath:GetFullName())
            end
        end
    end

    -- First try finding manager in current path
    local managerModule = modulePath:FindFirstChild(managerName)
    
    -- If not found and we're in a subsystem, try parent directory
    if not managerModule and foundSubsystem then
        local parentPath = modulePath.Parent
        managerModule = parentPath:FindFirstChild(managerName)
        if managerModule then
            modulePath = parentPath
            table.insert(traversalLog, "<- exited subSystem")
        end
    end

    if not managerModule then
        warn(string.format(
            "[SignalHelper] Manager module '%s' not found under %s (path: %s)",
            managerName,
            modulePath:GetFullName(),
            signalPath
        ))
        return
    end

    local manager
    local success, err = pcall(function()
        manager = require(managerModule)
    end)

    if not success then
        warn("[SignalHelper] Failed to require manager", managerName, ":", err)
        return
    end

    if not manager then
        warn("[SignalHelper] Manager module returned nil:", managerName)
        return
    end

    local handler = manager[methodName]
    if typeof(handler) ~= "function" then
        warn(string.format(
            "[SignalHelper] Handler method '%s' not found or invalid in '%s' (path: %s)",
            methodName,
            managerName,
            signalPath
        ))
        return
    end

    local connection = SignalHelper.SafeConnect(
        signal,
        function(...)
            handler(manager, ...)
        end,
        signalPath
    )

    if connection then
        SignalService:getInstance():registerSignal(signalPath, signal)
    end
end

-- Optimized path formatting
function SignalHelper.formatPath(pathParts)
    if not pathParts or #pathParts == 0 then
        return "empty_path"
    end
    
    -- Use table.concat directly since we're not cleaning parts anymore
    return tableConcat(pathParts, ".")
end

return SignalHelper