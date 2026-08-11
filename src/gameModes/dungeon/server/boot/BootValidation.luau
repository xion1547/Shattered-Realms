-- src/gameModes/dungeon/server/boot/BootValidation.luau
--
-- Content Layer validation. See Architecture-Reference.md Parts 11.2 and 17.
--
-- Turns "some content references something nobody implemented" from a silent
-- no-op a player eventually notices into a boot-time crash a developer sees
-- immediately.

local ServerStorage = game:GetService("ServerStorage")
local definitionsFolder = ServerStorage:WaitForChild("Shared"):WaitForChild("definitions")

local BootValidation = {}

-- Walks the Content Layer GENERICALLY rather than naming definition files by
-- hand. A hardcoded list breaks this project's own derive-it-don't-hand-list-it
-- discipline: a new definitions file with an `effects` field, plus forgetting
-- to add it to the list, silently reintroduces the exact gap this check
-- exists to close.
local function iterateDefinitions()
    local out = {}
    for _, module in ipairs(definitionsFolder:GetDescendants()) do
        if module:IsA("ModuleScript") then
            local ok, definitions = pcall(require, module)
            if ok and type(definitions) == "table" then
                table.insert(out, { name = module.Name, entries = definitions })
            end
        end
    end
    return out
end

function BootValidation.checkEffectCoverage(effectHandlers)
    local failures = {}

    for _, file in ipairs(iterateDefinitions()) do
        for entryId, entry in pairs(file.entries) do
            if type(entry) == "table" and type(entry.effects) == "table" then
                for _, effect in ipairs(entry.effects) do
                    if type(effect) == "table" and not effectHandlers[effect.type] then
                        table.insert(failures, string.format(
                            "%s.%s references effect type '%s' with no handler",
                            file.name, tostring(entryId), tostring(effect.type)))
                    end
                end
            end
        end
    end

    if #failures > 0 then
        table.sort(failures)
        error(string.format(
            "[BootValidation] %d effect coverage problem(s):\n  - %s",
            #failures, table.concat(failures, "\n  - ")), 0)
    end
end

-- Definitions must be valid before any gameplay begins -- discovering a
-- broken stat block when a boss spawns is far worse than at boot.
function BootValidation.checkDefinitions()
    local failures = {}

    local ok, resources = pcall(require, definitionsFolder:WaitForChild("ResourceDefinitions"))
    if not ok then
        table.insert(failures, "ResourceDefinitions failed to load: " .. tostring(resources))
    else
        for id, definition in pairs(resources) do
            if definition.id ~= id then
                table.insert(failures, string.format(
                    "ResourceDefinitions.%s has mismatched id '%s'", id, tostring(definition.id)))
            end
            -- A ceiling naming another resource must name one that exists.
            if type(definition.ceiling) == "string" and resources[definition.ceiling] == nil then
                table.insert(failures, string.format(
                    "ResourceDefinitions.%s ceiling references unknown resource '%s'",
                    id, definition.ceiling))
            end
            for _, field in ipairs({ "onFloor", "onCeiling" }) do
                if definition[field] ~= nil and type(definition[field]) ~= "string" then
                    -- A behaviour tag is a string the engine recognises. A
                    -- function here means config has become code in disguise.
                    table.insert(failures, string.format(
                        "ResourceDefinitions.%s.%s must be a string tag", id, field))
                end
            end
        end
    end

    if #failures > 0 then
        table.sort(failures)
        error(string.format(
            "[BootValidation] %d definition problem(s):\n  - %s",
            #failures, table.concat(failures, "\n  - ")), 0)
    end
end

return BootValidation
