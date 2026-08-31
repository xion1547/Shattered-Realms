-- src/gameModes/dungeon/client/diagnostics/conductorTool/Widgets.luau
--
-- Small UI builders for the Conductor dev tool. Knows nothing about Scores,
-- tracks or keys -- it makes buttons, sliders and text boxes and hands them
-- back.
--
-- DEV ONLY. Ugly on purpose: flat colours, no theming, no layout system beyond
-- UIListLayout. Every minute spent making this pretty is a minute not spent on
-- the thing it exists to author.

local UserInputService = game:GetService("UserInputService")

local Widgets = {}

local BG = Color3.fromRGB(28, 30, 34)
local PANEL = Color3.fromRGB(38, 41, 46)
local ACCENT = Color3.fromRGB(90, 160, 240)
local TEXT = Color3.fromRGB(235, 238, 242)
local DIM = Color3.fromRGB(150, 156, 165)

Widgets.ROW_HEIGHT = 22

local function corner(instance: Instance, radius: number?)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 4)
    c.Parent = instance
end

function Widgets.screen(name: string): ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name = name
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 1000
    return gui
end

-- A vertical stack. Everything else goes inside one of these.
function Widgets.column(parent: Instance, padding: number?): Frame
    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(1, 0, 0, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, padding or 4)
    layout.Parent = frame

    frame.Parent = parent
    return frame
end

-- A horizontal strip, for putting two or three controls on one line.
function Widgets.row(parent: Instance, height: number?): Frame
    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(1, 0, 0, height or Widgets.ROW_HEIGHT)

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = frame

    frame.Parent = parent
    return frame
end

function Widgets.panel(parent: Instance, title: string, size: UDim2, position: UDim2): (Frame, Frame)
    local outer = Instance.new("Frame")
    outer.BackgroundColor3 = BG
    outer.BorderSizePixel = 0
    outer.Size = size
    outer.Position = position
    corner(outer, 6)

    local header = Instance.new("TextLabel")
    header.BackgroundColor3 = PANEL
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, 26)
    header.Font = Enum.Font.GothamBold
    header.TextSize = 13
    header.TextColor3 = TEXT
    header.Text = "  " .. title
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = outer
    corner(header, 6)

    local body = Instance.new("ScrollingFrame")
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.Position = UDim2.new(0, 6, 0, 30)
    body.Size = UDim2.new(1, -12, 1, -36)
    body.CanvasSize = UDim2.new(0, 0, 0, 0)
    body.AutomaticCanvasSize = Enum.AutomaticSize.Y
    body.ScrollBarThickness = 4
    body.Parent = outer

    outer.Parent = parent
    return outer, body
end

function Widgets.label(parent: Instance, text: string, width: UDim?): TextLabel
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(width or UDim.new(1, 0), UDim.new(0, Widgets.ROW_HEIGHT))
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = DIM
    label.Text = text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = parent
    return label
end

function Widgets.button(parent: Instance, text: string, width: number, onClick: () -> ()): TextButton
    local button = Instance.new("TextButton")
    button.BackgroundColor3 = PANEL
    button.BorderSizePixel = 0
    button.Size = UDim2.new(0, width, 0, Widgets.ROW_HEIGHT)
    button.Font = Enum.Font.GothamMedium
    button.TextSize = 12
    button.TextColor3 = TEXT
    button.Text = text
    button.AutoButtonColor = true
    button.Parent = parent
    corner(button)

    button.Activated:Connect(onClick)
    return button
end

function Widgets.textBox(parent: Instance, placeholder: string, width: number, initial: string?): TextBox
    local box = Instance.new("TextBox")
    box.BackgroundColor3 = PANEL
    box.BorderSizePixel = 0
    box.Size = UDim2.new(0, width, 0, Widgets.ROW_HEIGHT)
    box.Font = Enum.Font.Code
    box.TextSize = 12
    box.TextColor3 = TEXT
    box.PlaceholderText = placeholder
    box.Text = initial or ""
    box.ClearTextOnFocus = false
    box.Parent = parent
    corner(box)
    return box
end

-- ============================================================================
-- THE SLIDER -- the reason this tool exists
-- ============================================================================
--
-- Roblox ships no slider, so this is a track, a fill, and a handle plus drag
-- handling. About forty lines, and it is the whole difference between a tool
-- and a worse text editor: you cannot judge `Brightness = 3.0` by reading it,
-- and you can judge it instantly by dragging until it looks right.
--
-- `onChange` FIRES CONTINUOUSLY WHILE DRAGGING, not on release. That is
-- deliberate -- the caller writes the property live, so the thing you are
-- looking at moves with your mouse. Firing on release would make this a text
-- box with extra steps.
export type Slider = {
    frame: Frame,
    set: (value: number) -> (),
    setRange: (min: number, max: number) -> (),
}

function Widgets.slider(
    parent: Instance,
    min: number,
    max: number,
    initial: number,
    width: number,
    onChange: (number) -> ()
): Slider
    local low, high = min, max
    local current = initial

    local track = Instance.new("Frame")
    track.BackgroundColor3 = PANEL
    track.BorderSizePixel = 0
    track.Size = UDim2.new(0, width, 0, 6)
    track.Parent = parent
    corner(track, 3)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = ACCENT
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Parent = track
    corner(fill, 3)

    local dragging = false

    local function applyFromX(x: number)
        local left = track.AbsolutePosition.X
        local span = math.max(track.AbsoluteSize.X, 1)
        local alpha = math.clamp((x - left) / span, 0, 1)

        current = low + (high - low) * alpha
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        onChange(current)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            applyFromX(input.Position.X)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch)
        then
            applyFromX(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end)

    local slider: Slider
    slider = {
        frame = track,

        -- Sets the handle WITHOUT firing onChange. Used when the tool pushes a
        -- value in (scrubbing, selecting a key) -- firing would write the value
        -- straight back out and make every read a write.
        set = function(value: number)
            current = value
            local span = high - low
            local alpha = if span ~= 0 then math.clamp((value - low) / span, 0, 1) else 0
            fill.Size = UDim2.new(alpha, 0, 1, 0)
        end,

        setRange = function(newMin: number, newMax: number)
            low, high = newMin, newMax
            slider.set(current)
        end,
    }

    return slider
end

-- ============================================================================
-- DRAG AND RESIZE
-- ============================================================================
--
-- Roblox ships neither. Both are the same shape: grab, follow the mouse, let
-- go -- so both are ~20 lines and both are worth it, because a fixed panel
-- covering the thing you are authoring is a tool you fight.
--
-- `InputChanged` is bound on UserInputService rather than on the widget: once
-- the mouse leaves the small grab area mid-drag, the widget stops receiving
-- movement and the panel sticks. Watching globally and gating on a `dragging`
-- flag is what makes a drag survive moving faster than the frame rate.

function Widgets.makeDraggable(panel: Frame, handle: GuiObject)
    local dragging = false
    local grabOffset = Vector2.zero

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            grabOffset = Vector2.new(input.Position.X, input.Position.Y) - panel.AbsolutePosition
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            local target = Vector2.new(input.Position.X, input.Position.Y) - grabOffset
            panel.Position = UDim2.new(0, target.X, 0, target.Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end)
end

-- A grip in the bottom-right corner. `onResized` fires continuously so a
-- timeline can re-lay its bars against the new width while you are still
-- dragging -- otherwise the bars snap into place on release, which reads as a
-- broken widget.
function Widgets.makeResizable(
    panel: Frame,
    minWidth: number,
    minHeight: number,
    onResized: (() -> ())?
)
    local grip = Instance.new("TextButton")
    grip.Name = "ResizeGrip"
    grip.AnchorPoint = Vector2.new(1, 1)
    grip.Position = UDim2.new(1, 0, 1, 0)
    grip.Size = UDim2.new(0, 16, 0, 16)
    grip.BackgroundColor3 = PANEL
    grip.BorderSizePixel = 0
    grip.Text = "◢"
    grip.TextColor3 = DIM
    grip.TextSize = 12
    grip.Font = Enum.Font.Gotham
    grip.AutoButtonColor = false
    grip.ZIndex = 10
    grip.Parent = panel

    local resizing = false

    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            resizing = true
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not resizing then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        then
            local corner = Vector2.new(input.Position.X, input.Position.Y)
            local size = corner - panel.AbsolutePosition
            panel.Size = UDim2.new(
                0, math.max(size.X, minWidth),
                0, math.max(size.Y, minHeight))

            if onResized then
                onResized()
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            resizing = false
        end
    end)
end

-- ============================================================================
-- TIMELINE PRIMITIVES
-- ============================================================================

Widgets.BAR_CLIP = Color3.fromRGB(90, 160, 240)
Widgets.BAR_TRACK = Color3.fromRGB(120, 200, 140)
Widgets.BAR_TRIGGER = Color3.fromRGB(240, 180, 90)
Widgets.PLAYHEAD = Color3.fromRGB(250, 90, 90)

-- A span drawn inside a lane, positioned by FRACTION of the lane's width so it
-- survives the panel being resized without anything recomputing pixels.
function Widgets.bar(parent: Instance, fromAlpha: number, toAlpha: number, colour: Color3): Frame
    local width = math.max(toAlpha - fromAlpha, 0.004)

    local bar = Instance.new("Frame")
    bar.BackgroundColor3 = colour
    bar.BorderSizePixel = 0
    bar.Position = UDim2.new(fromAlpha, 0, 0.5, -5)
    bar.Size = UDim2.new(width, 0, 0, 10)
    bar.Parent = parent
    corner(bar, 3)

    return bar
end

-- A single moment -- a key, or a trigger.
function Widgets.tick(parent: Instance, alpha: number, colour: Color3, tall: boolean?): Frame
    local height = if tall then 16 else 10
    local tick = Instance.new("Frame")
    tick.BackgroundColor3 = colour
    tick.BorderSizePixel = 0
    tick.AnchorPoint = Vector2.new(0.5, 0.5)
    tick.Position = UDim2.new(alpha, 0, 0.5, 0)
    tick.Size = UDim2.new(0, 3, 0, height)
    tick.Parent = parent
    corner(tick, 1)
    return tick
end

-- A lane: the clickable full-width strip one row's bars live in.
function Widgets.lane(parent: Instance, label: string, onClick: () -> ()): (TextButton, Frame)
    local row = Instance.new("TextButton")
    row.BackgroundColor3 = PANEL
    row.BackgroundTransparency = 0.55
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 20)
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = parent
    corner(row, 3)
    row.Activated:Connect(onClick)

    local name = Instance.new("TextLabel")
    name.BackgroundTransparency = 1
    name.Size = UDim2.new(0, 150, 1, 0)
    name.Font = Enum.Font.Code
    name.TextSize = 11
    name.TextColor3 = TEXT
    name.Text = " " .. label
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.ZIndex = 3
    name.Parent = row

    -- The part time actually maps onto. Offset so the label never overlaps a
    -- bar -- otherwise a track starting at t=0 is drawn under its own name.
    local track = Instance.new("Frame")
    track.BackgroundTransparency = 1
    track.Position = UDim2.new(0, 154, 0, 0)
    track.Size = UDim2.new(1, -158, 1, 0)
    track.Parent = row

    return row, track
end

function Widgets.setSelected(row: TextButton, selected: boolean)
    row.BackgroundTransparency = if selected then 0.1 else 0.55
end

return Widgets
