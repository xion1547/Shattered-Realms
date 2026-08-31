-- src/gameModes/dungeon/client/diagnostics/conductorTool/init.luau
--
-- THE CONDUCTOR DEV TOOL. Authors a Score at runtime: every track as a bar on
-- one time axis, sliders that write live so you can see what you are choosing,
-- and an export that prints paste-ready Lua.
--
--     ConductorTool.start()      -- or flip DebugConductorTool on Workspace
--
-- ============================================================================
-- THE FIVE FILES
-- ============================================================================
--
--   init.luau       this. Assembly and the transport.
--   TimelineView    every track as a bar, on a shared axis. Selection.
--   Inspector       the editor for whatever is selected. One thing at a time.
--   Document        the Score being edited, and live preview writes.
--   Widgets         buttons, sliders, drag, resize. Knows nothing about Scores.
--   Serialize       Score -> paste-ready Lua.
--
-- ============================================================================
-- DEVELOPMENT ONLY -- AND THE HONEST VERSION OF WHAT THAT MEANS TODAY
-- ============================================================================
--
-- This must never ship, and right now the only thing stopping it is the flag.
--
-- REAL EXCLUSION IS A SECOND PROJECT FILE that omits `client/diagnostics/`, and
-- there isn't one -- `dungeon.project.json` is the only build. So "dev only" is
-- a convention, not a guarantee, and saying otherwise would be the kind of
-- comment that stops the next person checking.
--
-- ============================================================================
-- THE LOOP IT EXISTS FOR
-- ============================================================================
--
--   1. point it at a root -- a sword, an fx model, any Instance
--   2. add a track, a clip, or a trigger. A track reads the property's current
--      value and gives you the right control for its type
--   3. select the lane. DRAG until it looks right -- the property is written
--      live, so you are looking at the real thing
--   4. Key it at the playhead
--   5. scrub, watch the bars line up, Play the whole thing
--   6. Export
--
-- Step 3 is the justification for the sliders. Step 5 is the justification for
-- the timeline: "does the burst land ON the impact frame" is a question about
-- two things relative to each other, and no column of numbers answers it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Widgets = require(script:WaitForChild("Widgets"))
local Document = require(script:WaitForChild("Document"))
local Serialize = require(script:WaitForChild("Serialize"))
local TimelineView = require(script:WaitForChild("TimelineView"))
local Inspector = require(script:WaitForChild("Inspector"))

local playback = script.Parent.Parent:WaitForChild("playback")
local Conductor = require(playback:WaitForChild("conductor"))

local FLAG = "DebugConductorTool"
local MIN_WIDTH, MIN_HEIGHT = 420, 320

local ConductorTool = {}

local state = {
    doc = nil :: any,
    gui = nil :: ScreenGui?,
    running = nil :: any,
    scrubTime = 0,
    timeline = nil :: any,
    inspectorPane = nil :: Frame?,
    selection = nil :: any,
    status = nil :: TextLabel?,
    refresh = nil :: (() -> ())?,
    setScrub = nil :: ((number) -> ())?,
}

local function say(message: string)
    if state.status then
        state.status.Text = message
    end
    print("[ConductorTool] " .. message)
end

-- ============================================================================
-- SCRUBBING
-- ============================================================================
--
-- CALLS THE SHIPPED ENGINE, NOT A PREVIEW COPY. `Conductor.evaluate` is the
-- same function the game runs -- the one non-negotiable property of this tool.
-- A separate preview path means tuning against something the game will not
-- reproduce, which is what kills homemade editors. Not difficulty. Divergence.
--
-- Clips and triggers are deliberately NOT fired here. Both are events: a clip
-- starts or it does not, and dragging a playhead across a burst would emit on
-- every crossing. Press Play for those; the Inspector has a Test fire.
local function scrubTo(t: number)
    state.scrubTime = t

    local doc = state.doc
    if doc and doc.root then
        Conductor.evaluate(Document.toScore(doc), doc.root, t)
    end

    if state.timeline then
        TimelineView.setPlayhead(state.timeline, t)
    end
    if state.setScrub then
        state.setScrub(t)
    end
end

-- ============================================================================
-- THE PANEL
-- ============================================================================

local function build()
    local doc = state.doc

    local gui = Widgets.screen("ConductorTool")
    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    state.gui = gui

    local panel, body = Widgets.panel(
        gui, "Conductor Dev",
        UDim2.new(0, 620, 0, 620),
        UDim2.new(0, 12, 0, 12))

    Widgets.makeDraggable(panel, panel:FindFirstChildWhichIsA("TextLabel") :: GuiObject)

    local column = Widgets.column(body)

    -- ---- root and duration ----------------------------------------------
    local rootRow = Widgets.row(column)
    Widgets.label(rootRow, "root", UDim.new(0, 40))
    local rootBox = Widgets.textBox(rootRow, "Workspace.Sword", 280)
    Widgets.button(rootRow, "Set", 40, function()
        local ok, resolved = pcall(function()
            local current: Instance = game
            for segment in string.gmatch(rootBox.Text, "[^%.]+") do
                current = (current :: any)[segment]
            end
            return current
        end)

        if ok and typeof(resolved) == "Instance" then
            doc.root = resolved
            say("root = " .. resolved:GetFullName())
        else
            say("could not find " .. rootBox.Text)
        end
    end)

    local durationRow = Widgets.row(column)
    Widgets.label(durationRow, "duration", UDim.new(0, 56))
    local durationReadout = Widgets.label(durationRow, "1.00", UDim.new(0, 44))
    local durationSlider = Widgets.slider(durationRow, 0.1, 6, doc.duration, 240, function(v)
        doc.duration = math.round(v * 100) / 100
        durationReadout.Text = string.format("%.2f", doc.duration)
        if state.refresh then
            state.refresh()
        end
    end)
    durationSlider.set(doc.duration)
    durationReadout.Text = string.format("%.2f", doc.duration)

    -- ---- the timeline ---------------------------------------------------
    Widgets.label(column, "TIMELINE  — click a lane to edit, click the ruler to scrub")

    local timeline = TimelineView.new(column, doc,
        function(selection)
            state.selection = selection
            if state.refresh then
                state.refresh()
            end
        end,
        scrubTo)
    state.timeline = timeline

    -- ---- adding things --------------------------------------------------
    local addTrackRow = Widgets.row(column)
    local targetBox = Widgets.textBox(addTrackRow, "Blade.Trail", 130)
    local propertyBox = Widgets.textBox(addTrackRow, "Transparency", 110)
    Widgets.button(addTrackRow, "+ Track", 60, function()
        local track, reason = Document.addTrack(doc, targetBox.Text, propertyBox.Text)
        if not track then
            say(reason or "could not add track")
            return
        end
        state.selection = { kind = "track", index = #doc.tracks }
        say(string.format("added %s.%s (%s)", track.target, track.property, track.kind))
        if state.refresh then
            state.refresh()
        end
    end)

    local addClipRow = Widgets.row(column)
    local clipBox = Widgets.textBox(addClipRow, "WARRIOR_SWING_1", 150)
    local clipAtBox = Widgets.textBox(addClipRow, "at", 40, "0")
    Widgets.button(addClipRow, "+ Clip", 56, function()
        Document.addClip(doc, clipBox.Text, tonumber(clipAtBox.Text) or 0)
        if state.refresh then
            state.refresh()
        end
    end)

    local addTrigRow = Widgets.row(column)
    local trigTargetBox = Widgets.textBox(addTrigRow, "Blade.Sparks", 120)
    local trigActionBox = Widgets.textBox(addTrigRow, "EMIT", 54, "EMIT")
    local trigAtBox = Widgets.textBox(addTrigRow, "at", 40, "0")
    local trigCountBox = Widgets.textBox(addTrigRow, "n", 34, "1")
    Widgets.button(addTrigRow, "+ Trigger", 68, function()
        Document.addTrigger(doc, trigTargetBox.Text, trigActionBox.Text,
            tonumber(trigAtBox.Text) or 0, tonumber(trigCountBox.Text))
        if state.refresh then
            state.refresh()
        end
    end)

    -- ---- transport ------------------------------------------------------
    local scrubRow = Widgets.row(column)
    Widgets.label(scrubRow, "scrub", UDim.new(0, 40))
    local scrubReadout = Widgets.label(scrubRow, "0.00", UDim.new(0, 44))
    local scrubSlider = Widgets.slider(scrubRow, 0, 1, 0, 240, function(v)
        scrubTo(v * doc.duration)
    end)

    -- Lets the ruler and the slider agree: clicking the ruler moves the slider
    -- without the slider firing back and re-scrubbing.
    state.setScrub = function(t: number)
        scrubReadout.Text = string.format("%.2f", t)
        scrubSlider.set(if doc.duration > 0 then t / doc.duration else 0)
    end

    local transportRow = Widgets.row(column)

    Widgets.button(transportRow, "Play", 56, function()
        if not doc.root then
            say("set a root first")
            return
        end
        if state.running then
            state.running:stop()
        end
        state.running = Conductor.play(Document.toScore(doc), doc.root)
        say("playing")
    end)

    Widgets.button(transportRow, "Stop", 56, function()
        if state.running then
            state.running:stop()
            state.running = nil
        end
        say("stopped")
    end)

    Widgets.button(transportRow, "Revert", 60, function()
        Document.restoreAll(doc)
        say("restored every touched property")
    end)

    local nameBox = Widgets.textBox(transportRow, "Fissure", 90, "Fissure")
    Widgets.button(transportRow, "Export", 60, function()
        local text = Serialize.score(Document.toScore(doc), nameBox.Text)
        print("\n" .. string.rep("=", 70)
            .. "\n" .. text
            .. "\n" .. string.rep("=", 70) .. "\n")
        say("printed -- copy from the output window")
    end)

    -- ---- the inspector --------------------------------------------------
    Widgets.label(column, "SELECTED")
    local inspectorPane = Widgets.column(column)
    state.inspectorPane = inspectorPane

    local context: Inspector.Context = {
        doc = doc,
        scrubTime = function()
            return state.scrubTime
        end,
        say = say,
        refresh = function()
            if state.refresh then
                state.refresh()
            end
        end,
    }

    -- ---- one rebuild for everything -------------------------------------
    --
    -- Wholesale rather than diffed. A dozen lanes can afford being thrown away
    -- and remade; a diffing renderer is what turns a weekend tool into a
    -- project.
    state.refresh = function()
        -- A selection can outlive the thing it pointed at -- removing a track
        -- leaves an index into a shorter list. Clearing it here is cheaper than
        -- every Inspector branch guarding for nil.
        local selection = state.selection
        if selection then
            local list = if selection.kind == "track" then doc.tracks
                elseif selection.kind == "clip" then doc.clips
                else doc.triggers
            if not list[selection.index] then
                state.selection = nil
            end
        end

        TimelineView.setSelected(state.timeline, state.selection)
        TimelineView.setPlayhead(state.timeline, state.scrubTime)
        Inspector.render(inspectorPane, context, state.selection)
    end

    -- Bars are positioned by FRACTION, so Roblox re-lays them for free -- but
    -- the ruler labels and the playhead are placed in pixels off the lane's
    -- measured width, so they need a nudge per resize frame.
    Widgets.makeResizable(panel, MIN_WIDTH, MIN_HEIGHT, function()
        if state.refresh then
            state.refresh()
        end
    end)

    state.status = Widgets.label(column, "ready")
    state.refresh()
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function ConductorTool.start()
    if state.gui then
        return
    end
    if not RunService:IsClient() then
        warn("[ConductorTool] client only")
        return
    end

    state.doc = Document.new()
    build()
    say("ready -- set a root, add a track, select it, drag")
end

function ConductorTool.stop()
    if state.running then
        state.running:stop()
        state.running = nil
    end
    if state.doc then
        Document.restoreAll(state.doc)
    end
    if state.gui then
        state.gui:Destroy()
        state.gui = nil
    end

    state.doc = nil
    state.timeline = nil
    state.selection = nil
    state.refresh = nil
    state.setScrub = nil
end

-- Watches the same Workspace attribute switchboard the server diagnostics use.
-- Attributes replicate server -> client, so one flag drives both sides.
function ConductorTool.bindToFlag()
    local function apply()
        if workspace:GetAttribute(FLAG) == true then
            ConductorTool.start()
        else
            ConductorTool.stop()
        end
    end

    workspace:GetAttributeChangedSignal(FLAG):Connect(apply)
    apply()
end

return ConductorTool
