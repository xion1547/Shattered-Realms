-- src/gameModes/dungeon/server/boot/ServiceLoader.luau
--
-- Requires and boots every Service this place declares, in dependency-layer
-- order, and verifies the manifest in both directions.
-- See Architecture-Reference.md Part 13.
--
-- This is one of three small, explicit implementations of the same
-- discipline -- declared list, deterministic resolution, aggregated
-- boot-time failure. The other two are SignalService.validate and
-- EventRouter.resolveRoutes. They are deliberately NOT one shared generic
-- engine: signal wiring connects a listener, event routing calls a function
-- and cares about the return, service loading instantiates. Three different
-- verbs after resolution (Part 12).

local ServiceLoader = {}

function ServiceLoader.load(servicesFolder, manifest)
    assert(servicesFolder, "[ServiceLoader] services folder is required")

    local failures = {}
    local services = {}
    local declared = {}

    for _, layer in ipairs(manifest.order) do
        local layerFolder = servicesFolder:FindFirstChild(layer)
        if not layerFolder then
            table.insert(failures, string.format("layer folder '%s' is missing from the build", layer))
            continue
        end

        for _, serviceName in ipairs(manifest[layer] or {}) do
            declared[serviceName] = true

            local module = layerFolder:FindFirstChild(serviceName)
            if not module then
                -- Declared and missing: a .project.json misconfiguration or
                -- a typo, never something to skip past.
                table.insert(failures, string.format(
                    "'%s' is declared in layer '%s' but not present in the build", serviceName, layer))
                continue
            end

            local ok, service = pcall(require, module)
            if not ok then
                table.insert(failures, string.format(
                    "'%s' failed to require: %s", serviceName, tostring(service)))
                continue
            end
            if type(service) ~= "table" then
                table.insert(failures, string.format(
                    "'%s' must return a table, got %s", serviceName, type(service)))
                continue
            end

            services[serviceName] = service
        end
    end

    -- The other direction: anything present but undeclared is a leaked
    -- inclusion, and in a place-separated build that is a security question,
    -- not a tidiness one.
    for _, layerFolder in ipairs(servicesFolder:GetChildren()) do
        if layerFolder:IsA("Folder") then
            for _, module in ipairs(layerFolder:GetChildren()) do
                if module:IsA("ModuleScript") and not declared[module.Name] then
                    table.insert(failures, string.format(
                        "'%s' is present in layer '%s' but declared by no manifest entry",
                        module.Name, layerFolder.Name))
                end
            end
        end
    end

    if #failures > 0 then
        table.sort(failures)
        error(string.format(
            "[ServiceLoader] %d manifest problem(s) at boot:\n  - %s",
            #failures, table.concat(failures, "\n  - ")), 0)
    end

    -- Boot in layer order, so a domain Service can subscribe to an authority
    -- Fact that has already been declared.
    local bootFailures = {}
    for _, layer in ipairs(manifest.order) do
        for _, serviceName in ipairs(manifest[layer] or {}) do
            local service = services[serviceName]
            if type(service.boot) == "function" then
                local ok, err = pcall(service.boot, service)
                if not ok then
                    table.insert(bootFailures, string.format("'%s': %s", serviceName, tostring(err)))
                end
            end
        end
    end

    if #bootFailures > 0 then
        table.sort(bootFailures)
        error(string.format(
            "[ServiceLoader] %d service(s) failed to boot:\n  - %s",
            #bootFailures, table.concat(bootFailures, "\n  - ")), 0)
    end

    return services
end

return ServiceLoader
