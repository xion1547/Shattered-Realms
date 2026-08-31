-- src/gameModes/dungeon/client/diagnostics/conductorTool/TimelineView.luau
--
-- EVERY TRACK AS A BAR, ON ONE SHARED TIME AXIS. The part of the tool that
-- makes a Score readable rather than merely editable.
--
--     0.0        0.35       0.70       1.05       1.40
--     Blade.Trail.Transparency  ▐──●═══════●──▌
--     Glow.Brightness             ▐●══════════●▌
--     clip WARRIOR_SWING_1      ▐████████████▌
--     EMIT Blade.Sparks                  ◆
--                                    |  <- playhead
--
-- ============================================================================
-- WHY THIS EXISTS WHEN THE NUMBERS WERE ALREADY EDITABLE
-- ============================================================================
--
-- The first version of this tool was text boxes and sliders with no picture,
-- and it could author any Score the engine can play. What it could not do is
-- answer the question an animator actually asks:
--
--     "Does the burst land ON the impact frame, or just after it?"
--
-- That is a question about two things RELATIVE TO EACH OTHER, and no column of
-- numbers answers it at a glance. Bars on a shared axis do.
--
-- ============================================================================
-- EVERYTHING IS POSITIONED BY FRACTION, NEVER BY PIXELS
-- ============================================================================
--
-- A bar at t=0.4 in a 1.4s Score sits at `UDim2.new(0.4/1.4, 0, ...)`. Resizing
-- the panel then costs nothing -- Roblox re-lays it -- where a pixel layout
-- would need every bar recomputed on every drag frame.

local Widgets = require(script.Parent:WaitForChild("Widgets"))

local TimelineView = {}
TimelineView.__index = TimelineView

export type Selection = {
    kind: "track" | "clip" | "trigger",
    index: number,
}

type State = {
    container: Frame,
    ruler: Frame,
    lanes: Frame,
    playhead: Frame,
    doc: any,
    selected: Selection?,
    onSelect: (Selection) -> (),
    onScrub: (number) -> (),
}

local RULER_STEPS = 5

-- Where a moment sits, 0-1, along the time axis.
--
-- CLAMPED, because a key past `duration` is a normal authoring state -- you
-- shorten a Score and its last key is briefly outside it. Drawing that off the
-- end of the lane would hide it; pinning it to the edge keeps it visible and
-- obviously wrong, which is the useful outcome.
local function alphaOf(t: number, duration: number): number
    if duration <= 0 then
        return 0
    end
    return math.clamp(t / duration, 0, 1)
end

local function clearChildren(frame: Instance)
    for _, child in ipairs(frame:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end
end

function TimelineView.new(
    parent: Instance,
    doc: any,
    onSelect: (Selection) -> (),
    onScrub: (number) -> ()
)
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.Parent = parent

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = container

    -- The ruler doubles as a scrub bar. Clicking anywhere on the time axis to
    -- move the playhead is the gesture every editor has, and without it the
    -- only way to reach t=0.62 is dragging a slider somewhere else on screen.
    local ruler = Instance.new("TextButton")
    ruler.BackgroundTransparency = 1
    ruler.Size = UDim2.new(1, 0, 0, 16)
    ruler.Text = ""
    ruler.AutoButtonColor = false
    ruler.LayoutOrder = 1
    ruler.Parent = container

    local lanes = Instance.new("Frame")
    lanes.BackgroundTransparency = 1
    lanes.Size = UDim2.new(1, 0, 0, 0)
    lanes.AutomaticSize = Enum.AutomaticSize.Y
    lanes.LayoutOrder = 2
    lanes.Parent = container

    local laneLayout = Instance.new("UIListLayout")
    laneLayout.SortOrder = Enum.SortOrder.LayoutOrder
    laneLayout.Padding = UDim.new(0, 2)
    laneLayout.Parent = lanes

    -- Spans the lanes, above them, so it can be read against every bar at once.
    local playhead = Instance.new("Frame")
    playhead.BackgroundColor3 = Widgets.PLAYHEAD
    playhead.BorderSizePixel = 0
    playhead.AnchorPoint = Vector2.new(0.5, 0)
    playhead.Size = UDim2.new(0, 2, 1, 0)
    playhead.ZIndex = 5
    playhead.Parent = lanes

    local self: State = {
        container = container,
        ruler = ruler,
        lanes = lanes,
        playhead = playhead,
        doc = doc,
        selected = nil,
        onSelect = onSelect,
        onScrub = onScrub,
    }

    ruler.Activated:Connect(function()
        local mouse = game:GetService("UserInputService"):GetMouseLocation()
        -- The ruler's own left edge plus the same 154px label gutter the lanes
        -- use, so clicking under a bar lands on that bar's moment.
        local left = ruler.AbsolutePosition.X + 154
        local span = math.max(ruler.AbsoluteSize.X - 158, 1)
        local alpha = math.clamp((mouse.X - left) / span, 0, 1)
        self.onScrub(alpha * doc.duration)
    end)

    return setmetatable(self, TimelineView)
end

function TimelineView.setSelected(self: State, selection: Selection?)
    self.selected = selection
    TimelineView.rebuild(self)
end

function TimelineView.setPlayhead(self: State, t: number)
    local alpha = alphaOf(t, self.doc.duration)
    -- Matches the lane gutter: 154px in, then a fraction of what remains.
    self.playhead.Position = UDim2.new(0, 154, 0, 0)
    self.playhead.Size = UDim2.new(0, 2, 1, 0)
    self.playhead.Position = UDim2.new(0, 154 + alpha * math.max(self.lanes.AbsoluteSize.X - 158, 1), 0, 0)
end

local function isSelected(self: State, kind: string, index: number): boolean
    local selected = self.selected
    return selected ~= nil and selected.kind == kind and selected.index == index
end

function TimelineView.rebuild(self: State)
    local doc = self.doc
    local duration = doc.duration

    -- ---- ruler ----------------------------------------------------------
    clearChildren(self.ruler)
    for step = 0, RULER_STEPS do
        local alpha = step / RULER_STEPS
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.AnchorPoint = Vector2.new(0.5, 0)
        label.Position = UDim2.new(0, 154 + alpha * math.max(self.ruler.AbsoluteSize.X - 158, 1), 0, 0)
        label.Size = UDim2.new(0, 44, 1, 0)
        label.Font = Enum.Font.Code
        label.TextSize = 10
        label.TextColor3 = Color3.fromRGB(150, 156, 165)
        label.Text = string.format("%.2f", alpha * duration)
        label.Parent = self.ruler
    end

    -- ---- lanes ----------------------------------------------------------
    for _, child in ipairs(self.lanes:GetChildren()) do
        if child ~= self.playhead and not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    local order = 0

    -- CLIPS FIRST, deliberately. The rig animation is the thing everything
    -- else is timed against, so it belongs at the top where it reads as the
    -- reference rather than as one row among many.
    for index, clip in ipairs(doc.clips) do
        order += 1
        local row, track = Widgets.lane(
            self.lanes,
            string.format("clip %s", clip.clip),
            function()
                self.onSelect({ kind = "clip", index = index })
            end)
        row.LayoutOrder = order
        Widgets.setSelected(row, isSelected(self, "clip", index))

        -- A CLIP'S REAL LENGTH IS UNKNOWN UNTIL THE ASSET LOADS
        -- (`AnimationTrack.Length` reads 0 until then), and this view has no
        -- Animator. So the bar runs from `at` to the end of the Score -- an
        -- honest "it starts here and we do not know when it ends" rather than
        -- a made-up width that would be read as fact.
        local from = alphaOf(clip.at, duration)
        Widgets.bar(track, from, 1, Widgets.BAR_CLIP)
        Widgets.tick(track, from, Color3.new(1, 1, 1), true)
    end

    -- ---- property tracks ------------------------------------------------
    for index, propertyTrack in ipairs(doc.tracks) do
        order += 1
        local row, track = Widgets.lane(
            self.lanes,
            string.format("%s.%s", propertyTrack.target, propertyTrack.property),
            function()
                self.onSelect({ kind = "track", index = index })
            end)
        row.LayoutOrder = order
        Widgets.setSelected(row, isSelected(self, "track", index))

        local keys = propertyTrack.keys
        if #keys > 0 then
            -- The span is first key to last. A track with one key is a value
            -- held for the whole Score, drawn as a tick rather than a bar --
            -- there is no span to show.
            if #keys > 1 then
                Widgets.bar(
                    track,
                    alphaOf(keys[1].t, duration),
                    alphaOf(keys[#keys].t, duration),
                    Widgets.BAR_TRACK)
            end
            for _, key in ipairs(keys) do
                Widgets.tick(track, alphaOf(key.t, duration), Color3.new(1, 1, 1))
            end
        end
    end

    -- ---- triggers -------------------------------------------------------
    for index, trigger in ipairs(doc.triggers) do
        order += 1
        local row, track = Widgets.lane(
            self.lanes,
            string.format("%s %s", trigger.action, trigger.target),
            function()
                self.onSelect({ kind = "trigger", index = index })
            end)
        row.LayoutOrder = order
        Widgets.setSelected(row, isSelected(self, "trigger", index))

        -- A POINT, NOT A SPAN, and drawn as one on purpose. A trigger has no
        -- duration -- `Emit(n)` happens and is over -- so giving it a bar would
        -- draw a lifetime it does not have. What lingers afterwards is the
        -- particles' own Lifetime, which belongs to the asset.
        Widgets.tick(track, alphaOf(trigger.at, duration), Widgets.BAR_TRIGGER, true)
    end
end

return TimelineView
