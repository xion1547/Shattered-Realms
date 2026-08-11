-- src/gameModes/dungeon/server/boot/Scheduler.luau
--
-- One Heartbeat connection, each system ticking at its declared frequency.
-- See Architecture-Reference.md Part 14.
--
-- Most systems do not need 60Hz, and independent per-service Heartbeat
-- subscriptions at full frame rate waste CPU for no benefit.
--
-- Per-entity gating is each Service's own job, never this module's. The
-- Scheduler knows "call AIService:tick at 10Hz" and has no concept of
-- individual bosses, dungeon instances or state flags -- which is why it
-- never has to change as gating conditions accumulate.

local RunService = game:GetService("RunService")

local Scheduler = {}

-- One row per ticking system. Adding one is one line.
--
-- There is exactly one AI row: per-creature pacing (bosses ~10Hz, pets ~4Hz)
-- is a field on the AI profile, skipped inside AIService:tick for entities
-- not yet due.
local SCHEDULE = {
    { service = "BuffService", hz = 60 },       -- expiry must be frame-accurate
    -- Position history for lag-compensated hit detection. 30Hz because
    -- Roblox replicates character position at ~20Hz -- sampling faster only
    -- writes the same position into consecutive slots (HitDetection.md).
    { service = "SpatialService", hz = 30 },
    { service = "ResourceService", hz = 20 },   -- regen; 20Hz is plenty
    { service = "AIService", hz = 10 },         -- decisions do not need a frame
}

function Scheduler.start(services, router)
    local entries = {}

    for _, row in ipairs(SCHEDULE) do
        local service = services[row.service]
        if not service then
            -- A scheduled service absent from this place is not an error --
            -- it is place separation working. Skip it.
            continue
        end
        if type(service.tick) ~= "function" then
            error(string.format(
                "[Scheduler] '%s' is scheduled but has no tick method", row.service), 0)
        end
        table.insert(entries, {
            service = service,
            interval = 1 / row.hz,
            accumulator = 0,
        })
    end

    return RunService.Heartbeat:Connect(function(deltaTime)
        -- EventTape drains FIRST, before any scheduled tick, so a Service
        -- tick always sees whatever arrived this frame already applied and
        -- never mid-flight.
        if router then
            router:drain()
        end

        for _, entry in ipairs(entries) do
            entry.accumulator += deltaTime
            if entry.accumulator >= entry.interval then
                entry.accumulator -= entry.interval
                local ok, err = pcall(entry.service.tick, entry.service, entry.interval)
                if not ok then
                    warn(string.format("[Scheduler] tick failed: %s", tostring(err)))
                end
            end
        end
    end)
end

return Scheduler
