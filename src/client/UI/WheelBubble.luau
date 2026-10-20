--[[
	SPIN & WIN (the daily wheel) in the light "Bubble" look (pure builder,
	preview first; step 7's WheelView/WheelController move onto it).

	  header   pink (Wheel colour), wheel icon, red X
	  left     the wheel: 8 bright segments clockwise from the top, drawn from
	           rotated bars (Roblox UI has no wedges: each bar is a transparent
	           frame through the centre whose upper half is coloured, so it
	           turns around the wheel's centre), radial labels, a gold rim,
	           light studs, the pointer and a star hub; SPIN! + the countdown
	  right    ODDS: one row per segment (colour, name, what it pays, chance)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.BubbleTheme)
local UIKit = require(script.Parent.UIKit)
local Bubble = require(script.Parent.Bubble)

local WheelBubble = {}

export type Segment = { Id: string, Label: string, Detail: string, Chance: string, Color: Color3 }
export type Data = { Segments: { Segment }, Ready: boolean, Countdown: string }
export type Refs = { Window: Bubble.Window, Disc: Frame, Spin: TextButton, Rows: { [string]: TextButton } }

WheelBubble.BarStep = 3 -- degrees between the bars of a segment

-- One coloured spoke from the centre at `angle` (degrees clockwise from the top).
local function spoke(disc: Frame, radius: number, angle: number, width: number, color: Color3, name: string)
	local holder = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = angle,
		Size = UDim2.fromOffset(width, radius * 2),
		ZIndex = 3,
	}, disc)
	UIKit.new("Frame", {
		Name = "Half",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.5, 0),
		ZIndex = 3,
	}, holder)
end

-- The wheel disc (it turns as a whole when spinning).
function WheelBubble.disc(parent: Instance, segments: { Segment }, diameter: number): Frame
	local r = diameter // 2
	local disc = UIKit.new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(diameter, diameter),
		ZIndex = 3,
	}, parent)
	Bubble.corner(disc, diameter)
	local n = #segments
	local span = 360 / n
	for i, seg in segments do
		local center = (i - 1) * span
		local bars = math.ceil(span / WheelBubble.BarStep)
		local width = math.ceil(2 * math.pi * r * WheelBubble.BarStep / 360) + 2
		for b = 0, bars do
			local a = center - span / 2 + b * (span / bars)
			spoke(disc, r - 4, a, width, seg.Color, `Seg{i}_{b}`)
		end
	end
	-- dividers and labels on top of every segment
	for i, seg in segments do
		local edge = (i - 1) * span - span / 2
		spoke(disc, r - 4, edge, 4, Color3.fromRGB(255, 226, 120), `Divider{i}`)
		local holder = UIKit.new("Frame", {
			Name = "Label" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = (i - 1) * span,
			Size = UDim2.fromOffset(40, diameter),
			ZIndex = 4,
		}, disc)
		local label = Bubble.text(holder, seg.Label, 15, {
			Name = "Text",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.23, 0),
			Rotation = if (i - 1) * span > 180 then 90 else -90, -- never upside down
			Size = UDim2.fromOffset(math.floor(r * 0.62), 34),
			TextScaled = true,
			TextWrapped = true,
			ZIndex = 5,
		})
		label.ZIndex = 5
	end
	local rim = UIKit.new("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(diameter, diameter),
		ZIndex = 6,
	}, disc)
	Bubble.corner(rim, diameter)
	Bubble.stroke(rim, 10, Color3.fromRGB(255, 196, 40))
	for k = 0, 15 do
		local a = math.rad(k * 22.5)
		local stud = UIKit.new("Frame", {
			Name = "Stud" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 250, 220),
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, math.floor(math.sin(a) * (r + 1)), 0.5, -math.floor(math.cos(a) * (r + 1))),
			Size = UDim2.fromOffset(9, 9),
			ZIndex = 7,
		}, disc)
		Bubble.corner(stud, 5)
	end
	local hub = UIKit.new("Frame", {
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		ZIndex = 7,
	}, disc)
	Bubble.corner(hub, 32)
	Bubble.stroke(hub, 4)
	return disc
end

function WheelBubble.build(parent: Instance, uiScale: number, data: Data): Refs
	local compact, size, header = Bubble.windowSize(uiScale)
	local window = Bubble.window(parent, {
		Name = "Wheel",
		Title = "SPIN & WIN",
		Icon = "wheel",
		Role = "Wheel",
		Size = size,
		HeaderHeight = header,
	})
	local body = window.Body
	local leftW = if compact then 430 else 400
	local diameter = if compact then 262 else 330
	local wheelArea = UIKit.new("Frame", {
		Name = "WheelArea",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, leftW, 1, 0),
	}, body)
	local disc = WheelBubble.disc(wheelArea, data.Segments, diameter)
	disc.Position = UDim2.new(0.5, 0, 0, diameter // 2 + 22)
	-- pointer at the top + star hub (they do not turn)
	local pointer = UIKit.new("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 22),
		Rotation = 45,
		Size = UDim2.fromOffset(34, 34),
		ZIndex = 9,
	}, wheelArea)
	Bubble.corner(pointer, 6)
	Bubble.stroke(pointer, 3.5)
	Bubble.icon(wheelArea, "medal", 74, {
		Name = "HubStar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, diameter // 2 + 22),
		ZIndex = 9,
	})
	local spin, spinHolder = Bubble.button(wheelArea, {
		Name = "Spin",
		Text = if data.Ready then "SPIN!" else "WAIT",
		Role = if data.Ready then "Go" else "Plain",
		Size = Vector2.new(240, if compact then 72 else 62),
		TextSize = 32,
	})
	spinHolder.AnchorPoint = Vector2.new(0.5, 0)
	spinHolder.Position = UDim2.new(0.5, 0, 0, diameter + 44)
	Bubble.ink(wheelArea, data.Countdown, if compact then 22 else 18, {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, diameter + 44 + (if compact then 72 else 62) + Theme.Lip + 6),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Theme.InkSoft,
	})

	-- odds
	local odds = Bubble.inset(body, "Odds", UDim2.fromOffset(leftW + 18, 0), UDim2.new(1, -leftW - 18, 1, 0))
	Bubble.ink(odds, "ODDS", if compact then 24 else 20, {
		Name = "Heading",
		FontFace = Theme.TitleFont,
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local list = UIKit.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 1, -46),
		ZIndex = 3,
	}, odds)
	local rows = {}
	local count = #data.Segments
	if compact then
		-- phones: a 2 x 4 grid of 72-unit tiles (label + chance)
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 72 + Theme.Lip),
			CellPadding = UDim2.fromOffset(10, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, list)
	else
		UIKit.list(list, Enum.FillDirection.Vertical, 6)
	end
	local available = size.Y - header - 3 - 32 - 46
	local rowH = if compact then 72 else math.floor((available - (count - 1) * 6) / count) - Theme.Lip
	for i, seg in data.Segments do
		local holder, face = Bubble.body(list, Bubble.role("Plain"), Vector2.new(0, rowH), { Name = seg.Id, Corner = 14, Clickable = true })
		holder.LayoutOrder = i
		holder.Size = UDim2.new(1, 0, 0, rowH + Theme.Lip)
		for _, part in { "Shadow", "Lip" } do
			local piece = holder:FindFirstChild(part) :: Frame
			piece.Size = UDim2.new(1, 0, 0, rowH)
		end
		face.Size = UDim2.new(1, 0, 0, rowH)
		local swatch = UIKit.new("Frame", {
			Name = "Swatch",
			BackgroundColor3 = seg.Color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 7),
			Size = UDim2.new(0, 14, 1, -14),
			ZIndex = 4,
		}, face)
		Bubble.corner(swatch, 7)
		Bubble.ink(face, seg.Label, if compact then 22 else 17, {
			Name = "Label",
			Position = UDim2.fromOffset(30, if compact then 6 else 2),
			Size = UDim2.new(1, -110, 0, if compact then 30 else 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = compact,
			ZIndex = 4,
		})
		if not compact then
			Bubble.ink(face, seg.Detail, 12, {
				Name = "Detail",
				Position = UDim2.fromOffset(30, 22),
				Size = UDim2.new(1, -110, 0, 16),
				TextColor3 = Theme.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 4,
			})
		end
		Bubble.chip(face, seg.Chance, Vector2.new(if compact then 86 else 64, if compact then 30 else 26), if compact then 21 else 17, Bubble.roleFrom(seg.Color), {
			Name = "Chance",
			AnchorPoint = Vector2.new(1, if compact then 1 else 0.5),
			Position = if compact then UDim2.new(1, -8, 1, -6) else UDim2.new(1, -10, 0.5, 0),
		})
		rows[seg.Id] = face :: TextButton
	end
	return { Window = window, Disc = disc, Spin = spin, Rows = rows }
end

return WheelBubble
