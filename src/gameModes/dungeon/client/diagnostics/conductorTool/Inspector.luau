-- src/gameModes/dungeon/client/diagnostics/conductorTool/Inspector.luau
--
-- THE EDITOR FOR WHATEVER IS SELECTED IN THE TIMELINE. One thing at a time.
--
-- ============================================================================
-- WHY A SEPARATE PANE RATHER THAN CONTROLS ON EVERY LANE
-- ============================================================================
--
-- The first version put every track's slider, range boxes and key buttons
-- inline, all visible at once. That is fine for two tracks and unusable for
-- ten -- a Score with four emitters, a beam and a clip is six lanes of
-- controls, and the timeline itself gets pushed off the bottom of the panel by
-- the widgets meant to edit it.
--
-- Select a lane, edit it here. The timeline stays a timeline.

local Widgets = require(script.Parent:WaitForChild("Widgets"))
local Document = require(script.Parent:WaitForChild("Document"))

local Inspector = {}

-- The caller supplies these rather than the Inspector reaching for shared
-- state: it edits whatever it is handed and knows nothing about the tool's
-- lifecycle, which is what keeps it rebuildable on every selection change.
export type Context = {
    doc: any,
    scrubTime: () -> number,
    say: (string) -> (),
    refresh: () -> (),
}

local function header(parent: Instance, text: string)
    local label = Widgets.label(parent, text)
    label.TextColor3 = Color3.fromRGB(235, 238, 242)
    label.Font = Enum.Font.GothamBold
end

-- ============================================================================
-- PROPERTY TRACKS
-- ============================================================================

local function numberEditor(parent: Instance, ctx: Context, track: any)
    local row = Widgets.row(parent)
    Widgets.label(row, "value", UDim.new(0, 46))
    local readout = Widgets.label(row, "", UDim.new(0, 52))
    readout.TextColor3 = Color3.fromRGB(235, 238, 242)

    local slider
    slider = Widgets.slider(row, track.min, track.max, track.staged or track.original, 190, function(v)
        readout.Text = string.format("%.3f", v)
        track.staged = v
        Document.preview(ctx.doc, track, v)
    end)

    local current = track.staged or track.original
    slider.set(current)
    readout.Text = string.format("%.3f", current)
    track.staged = current

    -- WITHOUT THIS A SLIDER IS USELESS OFF 0-1. Transparency is genuinely 0-1;
    -- Brightness runs to 100 and a ParticleEmitter's Rate to hundreds.
    local rangeRow = Widgets.row(parent)
    Widgets.label(rangeRow, "range", UDim.new(0, 46))
    local minBox = Widgets.textBox(rangeRow, "min", 60, tostring(track.min))
    local maxBox = Widgets.textBox(rangeRow, "max", 60, tostring(track.max))

    local function applyRange()
        local lo = tonumber(minBox.Text) or track.min
        local hi = tonumber(maxBox.Text) or track.max
        if hi > lo then
            track.min, track.max = lo, hi
            slider.setRange(lo, hi)
        end
    end
    minBox.FocusLost:Connect(applyRange)
    maxBox.FocusLost:Connect(applyRange)
end

local function booleanEditor(parent: Instance, ctx: Context, track: any)
    local row = Widgets.row(parent)
    Widgets.label(row, "value", UDim.new(0, 46))

    track.staged = if track.staged ~= nil then track.staged else track.original

    local toggle
    toggle = Widgets.button(row, tostring(track.staged), 70, function()
        track.staged = not track.staged
        toggle.Text = tostring(track.staged)
        Document.preview(ctx.doc, track, track.staged)
    end)

    Widgets.label(row, "snaps at its key -- no ease", UDim.new(0, 170))
end

local function colorEditor(parent: Instance, ctx: Context, track: any)
    local swatchRow = Widgets.row(parent)
    Widgets.label(swatchRow, "value", UDim.new(0, 46))

    local swatch = Instance.new("Frame")
    swatch.Size = UDim2.new(0, 40, 0, 16)
    swatch.BorderSizePixel = 0
    swatch.BackgroundColor3 = track.staged or track.original
    swatch.Parent = swatchRow

    track.staged = track.staged or track.original
    local values = {
        track.staged.R * 255,
        track.staged.G * 255,
        track.staged.B * 255,
    }

    for index, channel in ipairs({ "R", "G", "B" }) do
        local row = Widgets.row(parent)
        Widgets.label(row, "  " .. channel, UDim.new(0, 46))
        local readout = Widgets.label(row, "", UDim.new(0, 40))

        local slider = Widgets.slider(row, 0, 255, values[index], 190, function(v)
            values[index] = v
            readout.Text = string.format("%d", math.round(v))
            track.staged = Color3.fromRGB(
                math.round(values[1]), math.round(values[2]), math.round(values[3]))
            swatch.BackgroundColor3 = track.staged
            Document.preview(ctx.doc, track, track.staged)
        end)
        slider.set(values[index])
        readout.Text = string.format("%d", math.round(values[index]))
    end
end

-- ============================================================================
-- CAPTURE -- the editor for everything without an inline widget
-- ============================================================================
--
-- Vector3, CFrame, UDim2, a Texture id, an EnumItem. No slider, and none
-- wanted: **Studio's own move and rotate tools beat any widget this could
-- grow**, and the Properties panel already edits every one of these live
-- during a play test.
--
-- So the tool's job is not to build a worse manipulator. It is to READ what is
-- there when you say so.
local function captureEditor(parent: Instance, ctx: Context, track: any)
    local row = Widgets.row(parent)
    Widgets.label(row, "live", UDim.new(0, 46))

    local readout = Widgets.label(row, "", UDim.new(0, 250))
    readout.TextColor3 = Color3.fromRGB(235, 238, 242)

    local function refreshLive()
        local instance = Document.resolve(ctx.doc, track.target)
        if not instance then
            readout.Text = "target missing"
            return
        end
        local ok, current = pcall(function()
            return (instance :: any)[track.property]
        end)
        readout.Text = if ok then tostring(current) else "unreadable"
    end
    refreshLive()

    Widgets.button(row, "Read", 44, refreshLive)

    local hint = Widgets.row(parent)
    Widgets.label(hint,
        "  move it in Studio, then Key current",
        UDim.new(0, 300))
end

local function trackInspector(parent: Instance, ctx: Context, index: number)
    local track = ctx.doc.tracks[index]
    if not track then
        return
    end

    header(parent, string.format("%s . %s   (%s)", track.target, track.property, track.kind))

    if track.kind == "number" then
        numberEditor(parent, ctx, track)
    elseif track.kind == "boolean" then
        booleanEditor(parent, ctx, track)
    elseif track.kind == "Color3" then
        colorEditor(parent, ctx, track)
    else
        captureEditor(parent, ctx, track)
    end

    -- ---- easing ---------------------------------------------------------
    --
    -- Applied to the key being written, and it describes ARRIVING at that key
    -- rather than leaving it -- so A -> B uses B's ease and the first key's is
    -- never read. Matching Roblox's own `Pose`, which carries EasingStyle for
    -- getting INTO that pose.
    local easeRow = Widgets.row(parent)
    Widgets.label(easeRow, "ease", UDim.new(0, 46))
    local easeBox = Widgets.textBox(easeRow, "LINEAR", 120, track.ease or "LINEAR")
    Widgets.label(easeRow, "arriving at the key", UDim.new(0, 130))

    -- ---- keys -----------------------------------------------------------
    local keyRow = Widgets.row(parent)
    Widgets.label(keyRow, "keys", UDim.new(0, 46))

    local keysLabel = Widgets.label(keyRow, "", UDim.new(0, 150))
    local function refreshKeys()
        local times = {}
        for _, key in ipairs(track.keys) do
            table.insert(times, string.format("%.2f", key.t))
        end
        keysLabel.Text = if #times > 0 then table.concat(times, " ") else "none"
    end
    refreshKeys()

    -- Keys the STAGED value -- what the slider or toggle is showing. Only
    -- offered for kinds that have one; there is nothing staged to key otherwise.
    if track.kind ~= "capture" then
        Widgets.button(keyRow, "Key", 44, function()
            track.ease = easeBox.Text
            Document.key(ctx.doc, track, ctx.scrubTime(), track.staged, easeBox.Text)
            refreshKeys()
            ctx.say(string.format("keyed %s at %.2f", track.property, ctx.scrubTime()))
            ctx.refresh()
        end)
    end

    -- KEYS WHAT IS ACTUALLY ON THE INSTANCE RIGHT NOW, whatever put it there.
    --
    -- The only gesture that works for every type -- and the better one even
    -- where a slider exists, since nudging a value in the Properties panel and
    -- capturing beats hunting for it on a 0-to-100 slider.
    Widgets.button(keyRow, "Key current", 82, function()
        track.ease = easeBox.Text
        local value, reason = Document.keyCurrent(ctx.doc, track, ctx.scrubTime(), easeBox.Text)
        if not value and reason then
            ctx.say(reason)
            return
        end
        refreshKeys()
        ctx.say(string.format("keyed %s = %s at %.2f",
            track.property, tostring(value), ctx.scrubTime()))
        ctx.refresh()
    end)

    Widgets.button(keyRow, "Clear", 48, function()
        Document.clearKeys(ctx.doc, track)
        refreshKeys()
        ctx.refresh()
    end)

    local removeRow = Widgets.row(parent)
    Widgets.button(removeRow, "Remove track", 110, function()
        Document.removeTrack(ctx.doc, index)
        ctx.say("removed, property restored")
        ctx.refresh()
    end)
end

-- ============================================================================
-- CLIPS
-- ============================================================================

local function clipInspector(parent: Instance, ctx: Context, index: number)
    local clip = ctx.doc.clips[index]
    if not clip then
        return
    end

    header(parent, string.format("clip  %s", clip.clip))

    local atRow = Widgets.row(parent)
    Widgets.label(atRow, "at", UDim.new(0, 46))
    local atBox = Widgets.textBox(atRow, "0.00", 60, string.format("%.2f", clip.at))
    Widgets.label(atRow, "seconds into the Score", UDim.new(0, 160))

    local speedRow = Widgets.row(parent)
    Widgets.label(speedRow, "speed", UDim.new(0, 46))
    local speedBox = Widgets.textBox(speedRow, "1.0", 60, tostring(clip.speed or 1))
    Widgets.label(speedRow, "fits one clip to any weapon", UDim.new(0, 180))

    local applyRow = Widgets.row(parent)
    Widgets.button(applyRow, "Apply", 60, function()
        clip.at = tonumber(atBox.Text) or clip.at
        clip.speed = tonumber(speedBox.Text) or 1
        ctx.say(string.format("%s @ %.2f x%.2f", clip.clip, clip.at, clip.speed))
        ctx.refresh()
    end)
    Widgets.button(applyRow, "Remove", 70, function()
        Document.removeClip(ctx.doc, index)
        ctx.refresh()
    end)
end

-- ============================================================================
-- TRIGGERS
-- ============================================================================

local function triggerInspector(parent: Instance, ctx: Context, index: number)
    local trigger = ctx.doc.triggers[index]
    if not trigger then
        return
    end

    header(parent, string.format("%s  %s", trigger.action, trigger.target))

    local atRow = Widgets.row(parent)
    Widgets.label(atRow, "at", UDim.new(0, 46))
    local atBox = Widgets.textBox(atRow, "0.00", 60, string.format("%.2f", trigger.at))

    Widgets.label(atRow, "count", UDim.new(0, 44))
    local countBox = Widgets.textBox(atRow, "1", 44, tostring(trigger.count or 1))

    local actionRow = Widgets.row(parent)
    Widgets.button(actionRow, "Apply", 60, function()
        trigger.at = tonumber(atBox.Text) or trigger.at
        trigger.count = tonumber(countBox.Text)
        ctx.refresh()
    end)

    -- FIRES NOW, IGNORING THE TRANSPORT. Playback deliberately does not fire
    -- triggers while scrubbing -- dragging a playhead across t=0.3 would emit
    -- on every crossing -- so this is how you see one without watching the
    -- whole Score.
    Widgets.button(actionRow, "Test fire", 80, function()
        local ok, reason = Document.testTrigger(ctx.doc, trigger)
        ctx.say(ok and ("fired " .. trigger.action) or (reason or "failed"))
    end)

    Widgets.button(actionRow, "Remove", 70, function()
        Document.removeTrigger(ctx.doc, index)
        ctx.refresh()
    end)
end

-- ============================================================================

-- Rebuilt wholesale on every selection change rather than diffed. A pane with
-- a handful of rows can afford it, and a diffing renderer is the kind of thing
-- that turns a weekend tool into a project.
function Inspector.render(parent: Instance, ctx: Context, selection: any?)
    for _, child in ipairs(parent:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    if not selection then
        Widgets.label(parent, "select a lane above to edit it")
        return
    end

    if selection.kind == "track" then
        trackInspector(parent, ctx, selection.index)
    elseif selection.kind == "clip" then
        clipInspector(parent, ctx, selection.index)
    elseif selection.kind == "trigger" then
        triggerInspector(parent, ctx, selection.index)
    end
end

return Inspector
