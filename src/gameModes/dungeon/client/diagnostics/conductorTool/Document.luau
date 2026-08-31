-- src/gameModes/dungeon/client/diagnostics/conductorTool/Document.luau
--
-- THE SCORE BEING EDITED. One table, mutated in place, with small local edits.
--
-- Identical in shape to what ships -- `toScore()` is a copy, not a conversion.
-- If the document needed translating into a Score, the tool would be authoring
-- something subtly different from what the game plays, which is the failure
-- mode that makes a homemade editor untrustworthy.
--
-- ============================================================================
-- WHAT MUTATES AND WHAT DOES NOT
-- ============================================================================
--
--   scrubbing        NOTHING. Reads the document, writes to instances.
--   dragging a slider  NOTHING YET. Writes the instance live so you can SEE it.
--   pressing Key     ONE key added or overwritten, at the current scrub time.
--
-- Keys are only ever created by an explicit gesture. Watching for property
-- changes and recording them automatically litters keys every time anything is
-- nudged, and makes an intentional edit indistinguishable from an accident.

local Actions = require(script.Parent.Parent.Parent:WaitForChild("playback")
    :WaitForChild("conductor"):WaitForChild("Actions"))

local Document = {}
Document.__index = Document

-- Which widget a property gets, inferred from the value already on the
-- instance rather than declared by the user.
--
-- READ THE PROPERTY, DO NOT ASK. Typing "Transparency" and then also picking
-- "number" from a dropdown is two chances to disagree, and the instance already
-- knows the answer.
-- `capture` means "no inline widget, key it from the live value" -- NOT
-- "unsupported". Nothing is rejected.
--
-- THE EDITOR USED TO BE NARROWER THAN THE ENGINE and that was a real defect.
-- `Evaluate.lerpValue` handles number, Vector2, Vector3, Color3, CFrame, UDim
-- and UDim2; this file accepted three of them and turned the rest away with
-- "better authored with Studio's own manipulator". True as far as it went, and
-- it left an animated beam offset or a moving prop -- both completely ordinary
-- -- authorable only by hand-editing the exported file.
--
-- The fix is not six sliders for a CFrame. It is the workflow Timeline.md 7.1
-- already described: **move the thing however you like, then capture what is
-- there.** Studio's own manipulator and Properties panel beat any widget this
-- tool could grow, and capture works for every type at once.
export type Kind = "number" | "boolean" | "Color3" | "capture"

export type Track = {
    target: string,
    property: string,
    kind: Kind,
    keys: { { t: number, v: any, ease: string? } },

    -- What the property was before this tool touched it. Restored on removal
    -- and on close, so a tuning session does not permanently alter the place.
    original: any,

    -- Slider bounds. Meaningless for booleans, and essential for numbers: a
    -- 0-1 slider is right for Transparency and useless for Brightness or Rate.
    min: number,
    max: number,

    -- WHAT THE WIDGET IS SHOWING, which is what `Key` commits. Nil until an
    -- editor is opened on this track, so the readers all fall back to
    -- `original`.
    --
    -- Editing state rather than document content, and it stays here for the
    -- same reason `original`, `min` and `max` do: it is per-track and it must
    -- outlive the pane, which is rebuilt from scratch on every selection
    -- change. `toScore` copies target, property and keys only, so none of the
    -- four ever reaches a Score.
    staged: any?,

    -- The last ease typed for this track, so the box comes back holding it
    -- rather than resetting to LINEAR on every selection change. The ease that
    -- actually matters is stored per KEY -- this is only the pane's default.
    ease: string?,
}

export type Document = typeof(setmetatable(
    {} :: {
        root: Instance?,
        duration: number,
        tracks: { Track },
        clips: { { clip: string, at: number, speed: number? } },
        triggers: { { target: string, action: string, at: number, count: number? } },
    },
    Document
))

function Document.new(): Document
    return setmetatable({
        root = nil,
        duration = 1.0,
        tracks = {},
        clips = {},
        triggers = {},
    }, Document)
end

-- ============================================================================
-- RESOLUTION
-- ============================================================================

-- Same dotted-path walk the Conductor uses. Duplicated rather than shared
-- because the Conductor's copy is private and this is a dev tool -- a shared
-- helper module for eight lines would couple the shipped engine to a tool that
-- must never ship with it.
function Document.resolve(self: Document, target: string): Instance?
    local root = self.root
    if not root then
        return nil
    end
    if target == "" then
        return root
    end

    local current: Instance? = root
    for segment in string.gmatch(target, "[^%.]+") do
        if not current then
            return nil
        end
        current = current:FindFirstChild(segment)
    end
    return current
end

-- Which INLINE WIDGET a property gets. Everything else is keyed by capture.
local function kindOf(value: any): Kind
    local t = typeof(value)
    if t == "number" then
        return "number"
    elseif t == "boolean" then
        return "boolean"
    elseif t == "Color3" then
        return "Color3"
    end
    return "capture"
end

-- ============================================================================
-- TRACKS
-- ============================================================================

-- Returns (track, nil) or (nil, reason). The reason is shown in the tool rather
-- than thrown -- a typo'd property name is the most likely thing to happen and
-- should read as a message, not a stack trace.
function Document.addTrack(self: Document, target: string, property: string): (Track?, string?)
    if not self.root then
        return nil, "set a root first"
    end

    local instance = Document.resolve(self, target)
    if not instance then
        return nil, string.format("no '%s' under %s", target, self.root:GetFullName())
    end

    local ok, current = pcall(function()
        return (instance :: any)[property]
    end)
    if not ok then
        return nil, string.format("%s has no property '%s'", instance.Name, property)
    end

    local kind = kindOf(current)

    -- SENSIBLE DEFAULT RANGES so a slider is usable the moment it appears.
    -- Transparency is the common case and is genuinely 0-1; anything else gets
    -- a range around its current value that the user can widen.
    local min, max = 0, 1
    if kind == "number" then
        if property == "Transparency" or property == "Reflectance" then
            min, max = 0, 1
        else
            max = math.max(current * 2, 1)
        end
    end

    local track: Track = {
        target = target,
        property = property,
        kind = kind,
        keys = {},
        original = current,
        min = min,
        max = max,
    }

    table.insert(self.tracks, track)
    return track, nil
end

function Document.removeTrack(self: Document, index: number)
    local track = self.tracks[index]
    if not track then
        return
    end

    Document.restoreTrack(self, track)
    table.remove(self.tracks, index)
end

function Document.restoreTrack(self: Document, track: Track)
    local instance = Document.resolve(self, track.target)
    if instance then
        pcall(function()
            (instance :: any)[track.property] = track.original
        end)
    end
end

function Document.restoreAll(self: Document)
    for _, track in ipairs(self.tracks) do
        Document.restoreTrack(self, track)
    end
end

-- Writes a value straight to the instance without touching the document. This
-- is what a slider drag calls, and it is why the tool is worth using: you are
-- looking at the real thing while you choose the number.
function Document.preview(self: Document, track: Track, value: any)
    local instance = Document.resolve(self, track.target)
    if instance then
        pcall(function()
            (instance :: any)[track.property] = value
        end)
    end
end

-- ============================================================================
-- KEYS
-- ============================================================================

-- Adds a key, or overwrites one already at that moment.
--
-- SILENT OVERWRITE, KEYED BY TIME. That is what every animation tool does, and
-- any other choice surprises: keying twice at the same moment should give you
-- the second value, not two keys fighting over one instant.
--
-- Kept sorted on insert so the Conductor's `keysAround` -- which assumes sorted
-- keys and does a linear scan -- is never handed an out-of-order track.
function Document.key(self: Document, track: Track, t: number, value: any, ease: string?)
    local rounded = math.round(t * 1000) / 1000

    for _, existing in ipairs(track.keys) do
        if math.abs(existing.t - rounded) < 0.0005 then
            existing.v = value
            existing.ease = ease
            return
        end
    end

    table.insert(track.keys, { t = rounded, v = value, ease = ease })
    table.sort(track.keys, function(a, b)
        return a.t < b.t
    end)
end

function Document.clearKeys(self: Document, track: Track)
    table.clear(track.keys)
end

-- Reads the property AS IT IS RIGHT NOW and keys that.
--
-- THE ONE GESTURE THAT WORKS FOR EVERY TYPE. Move a prop with Studio's move
-- tool, type a Vector3 into the Properties panel, let another script put it
-- somewhere -- however the value got there, this captures it. No widget has to
-- exist for the type, which is what makes CFrame and Vector3 authorable at all.
--
-- It is also the better gesture for types that DO have a slider: nudging a
-- number in the Properties panel and capturing beats hunting for it on a
-- 0-to-100 slider.
--
-- Returns (value, nil) or (nil, reason) so the caller can show what was keyed.
function Document.keyCurrent(self: Document, track: Track, t: number, ease: string?): (any, string?)
    local instance = Document.resolve(self, track.target)
    if not instance then
        return nil, string.format("no '%s' under the root", track.target)
    end

    local ok, current = pcall(function()
        return (instance :: any)[track.property]
    end)
    if not ok then
        return nil, string.format("could not read %s", track.property)
    end

    Document.key(self, track, t, current, ease)
    track.staged = current
    return current, nil
end

-- ============================================================================
-- CLIPS
-- ============================================================================

-- ============================================================================
-- TRIGGERS
-- ============================================================================
--
-- Not validated against the target's class here. A trigger authored onto the
-- wrong instance warns at PLAY time, from `Actions`, naming the class it
-- actually found -- which is a better message than anything this file could
-- produce, and it keeps the tool from needing to know what an EMIT wants.
function Document.addTrigger(self: Document, target: string, action: string, at: number, count: number?)
    table.insert(self.triggers, {
        target = target,
        action = action,
        at = at,
        count = count,
    })
    table.sort(self.triggers, function(a, b)
        return a.at < b.at
    end)
end

function Document.removeTrigger(self: Document, index: number)
    table.remove(self.triggers, index)
end

-- Fires one trigger NOW, ignoring the transport.
--
-- THE TOOL NEEDS THIS AND PLAYBACK MUST NOT HAVE IT. Scrubbing deliberately
-- does not fire triggers -- dragging a playhead across t=0.3 would emit every
-- time it crossed. But while authoring you need to see the burst without
-- watching the whole Score, so the tool gets an explicit "fire it" button and
-- playback keeps its fire-exactly-once rule.
function Document.testTrigger(self: Document, trigger: any): (boolean, string?)
    local instance = Document.resolve(self, trigger.target)
    if not instance then
        return false, string.format("no '%s' under the root", trigger.target)
    end

    local ok, result = pcall(Actions.run, instance, trigger)
    if not ok then
        return false, tostring(result)
    end
    if result == false then
        return false, string.format("unknown action '%s'", tostring(trigger.action))
    end
    return true, nil
end

-- ============================================================================
-- CLIPS
-- ============================================================================

function Document.addClip(self: Document, clip: string, at: number)
    table.insert(self.clips, { clip = clip, at = at })
    table.sort(self.clips, function(a, b)
        return a.at < b.at
    end)
end

function Document.removeClip(self: Document, index: number)
    table.remove(self.clips, index)
end

-- ============================================================================
-- THE SCORE
-- ============================================================================

-- A COPY, not a live reference. The Conductor freezes nothing, so handing it
-- the document itself would let a slider drag mutate a Score mid-playback --
-- and tracks with no keys are dropped, since a track that was added and never
-- keyed is an intention rather than content.
function Document.toScore(self: Document)
    local tracks = {}
    for _, track in ipairs(self.tracks) do
        if #track.keys > 0 then
            local keys = {}
            for _, key in ipairs(track.keys) do
                table.insert(keys, { t = key.t, v = key.v, ease = key.ease })
            end
            table.insert(tracks, {
                target = track.target,
                property = track.property,
                keys = keys,
            })
        end
    end

    local clips = nil
    if #self.clips > 0 then
        clips = {}
        for _, clip in ipairs(self.clips) do
            table.insert(clips, { clip = clip.clip, at = clip.at, speed = clip.speed })
        end
    end

    local triggers = nil
    if #self.triggers > 0 then
        triggers = {}
        for _, trigger in ipairs(self.triggers) do
            table.insert(triggers, {
                target = trigger.target,
                action = trigger.action,
                at = trigger.at,
                count = trigger.count,
            })
        end
    end

    return {
        duration = self.duration,
        tracks = tracks,
        clips = clips,
        triggers = triggers,
    }
end

return Document
