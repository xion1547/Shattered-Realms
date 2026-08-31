-- src/gameModes/dungeon/client/diagnostics/conductorTool/Serialize.luau
--
-- SCORE -> PASTE-READY LUA. The output of the whole tool.
--
-- What comes out is a complete `.luau` file body, formatted the way the
-- handwritten Scores are, so it drops into
-- `src/shared/definitions/scores/<Name>.luau` without editing.
--
-- ============================================================================
-- WHY PRINT INSTEAD OF WRITE THE FILE
-- ============================================================================
--
-- A running game cannot write to the repo. Rojo syncs one way -- filesystem to
-- Studio -- and nothing in a live session can reach back the other direction.
--
-- So the export is text in the output window that gets copied by hand. That is
-- a real cost and it is the same manual commit point `Save to File` is for
-- models: the alternative is a plugin with filesystem access, which is a
-- different and much larger tool.

local Serialize = {}

local INDENT = "    "

local function rep(depth: number): string
    return string.rep(INDENT, depth)
end

-- ============================================================================
-- VALUES
-- ============================================================================
--
-- Every type a key can hold has to come back as SOURCE that reconstructs it.
-- `tostring(Color3)` gives "0.5, 0.2, 0.9" -- which is not Lua, and pasting it
-- produces a syntax error rather than a wrong colour. Each type needs its own
-- constructor spelled out.
local function value(v: any): string
    local t = typeof(v)

    if t == "number" then
        -- Trailing zeros trimmed, but a whole number keeps one decimal place so
        -- it still reads as a number rather than a count.
        if v == math.floor(v) then
            return string.format("%.1f", v)
        end
        return (string.format("%.4f", v):gsub("0+$", ""))
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "Color3" then
        -- fromRGB rather than Color3.new, because 0-255 is what the colour
        -- picker in every other tool shows and what anyone reading it expects.
        return string.format(
            "Color3.fromRGB(%d, %d, %d)",
            math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255))
    elseif t == "Vector3" then
        return string.format("Vector3.new(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vector2.new(%.3f, %.3f)", v.X, v.Y)
    elseif t == "UDim" then
        return string.format("UDim.new(%.3f, %d)", v.Scale, v.Offset)
    elseif t == "UDim2" then
        return string.format(
            "UDim2.new(%.3f, %d, %.3f, %d)",
            v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "CFrame" then
        local c = { v:GetComponents() }
        local parts = {}
        for _, n in ipairs(c) do
            table.insert(parts, string.format("%.4f", n))
        end
        return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
    end

    -- Deliberately loud. A value this cannot spell would otherwise paste as
    -- something that looks fine and is not.
    return string.format("--[[ UNSERIALISABLE %s ]] nil", t)
end

-- ============================================================================
-- THE SCORE
-- ============================================================================

local function serializeKeys(keys: { any }, depth: number): string
    local out = {}
    for _, key in ipairs(keys) do
        local ease = if key.ease and key.ease ~= "LINEAR"
            then string.format(", ease = %q", key.ease)
            else ""
        table.insert(out, string.format(
            "%s{ t = %.2f, v = %s%s },", rep(depth), key.t, value(key.v), ease))
    end
    return table.concat(out, "\n")
end

function Serialize.score(score: any, name: string?): string
    local out = {}
    local label = name or "Score"

    table.insert(out, string.format("-- src/shared/definitions/scores/%s.luau", label))
    table.insert(out, "--")
    table.insert(out, "-- EXPORTED FROM THE CONDUCTOR DEV TOOL. Authored by looking, not typed.")
    table.insert(out, "")
    table.insert(out, "local ReplicatedStorage = game:GetService(\"ReplicatedStorage\")")
    table.insert(out, "local Score = require(ReplicatedStorage:WaitForChild(\"types\"):WaitForChild(\"Score\"))")
    table.insert(out, "")
    table.insert(out, string.format("local %s: Score.Score = {", label))
    table.insert(out, string.format("%sduration = %.2f,", rep(1), score.duration))
    table.insert(out, "")

    if score.clips and #score.clips > 0 then
        table.insert(out, string.format("%sclips = {", rep(1)))
        for _, clip in ipairs(score.clips) do
            local speed = if clip.speed then string.format(", speed = %.2f", clip.speed) else ""
            table.insert(out, string.format(
                "%s{ clip = %q, at = %.2f%s },", rep(2), clip.clip, clip.at, speed))
        end
        table.insert(out, string.format("%s},", rep(1)))
        table.insert(out, "")
    end

    if score.triggers and #score.triggers > 0 then
        table.insert(out, string.format("%striggers = {", rep(1)))
        for _, trigger in ipairs(score.triggers) do
            local count = if trigger.count
                then string.format(", count = %d", trigger.count)
                else ""
            table.insert(out, string.format(
                "%s{ target = %q, action = %q, at = %.2f%s },",
                rep(2), trigger.target, trigger.action, trigger.at, count))
        end
        table.insert(out, string.format("%s},", rep(1)))
        table.insert(out, "")
    end

    table.insert(out, string.format("%stracks = {", rep(1)))
    for _, track in ipairs(score.tracks) do
        table.insert(out, string.format("%s{", rep(2)))
        table.insert(out, string.format("%starget = %q,", rep(3), track.target))
        table.insert(out, string.format("%sproperty = %q,", rep(3), track.property))
        table.insert(out, string.format("%skeys = {", rep(3)))
        table.insert(out, serializeKeys(track.keys, 4))
        table.insert(out, string.format("%s},", rep(3)))
        table.insert(out, string.format("%s},", rep(2)))
    end
    table.insert(out, string.format("%s},", rep(1)))

    table.insert(out, "}")
    table.insert(out, "")
    table.insert(out, string.format("return %s", label))

    return table.concat(out, "\n")
end

return Serialize
