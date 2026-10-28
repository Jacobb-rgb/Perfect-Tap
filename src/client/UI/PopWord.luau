--[[
	PopWord: a comic word that pops (the owner's reels 2026-10-27: "WHOOSH!"
	beside the XP bar while it fills, "+1" when an ore lands in your bag).
	Pop look: chunky text in a PopTheme.Titles gradient with a thick dark
	edge, tilted; WHOOSH! trails three speed lines. Pure builder + pose (the
	Lune previews pose the same frames): no services, nothing runs on its own.

	  build(parent, text, size, opts) -> Word (hidden until posed)
	  pose(word, t, reduced?)         t seconds in (0..word.Seconds; outside it
	                                  the word hides). Returns true when done.
	The caller places word.Holder (Position / AnchorPoint) and may scale it
	with word.Scale's parent; pose only moves the word inside its holder.
	Reduce motion: no pop, wobble or rise; the word fades in and
	out at full size, straight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PopTheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PopTheme"))
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)

local PopWord = {}

export type Opts = {
	Colors: string?, -- a PopTheme.Titles name (default Gold)
	Tilt: number?, -- degrees (default -10)
	Lines: boolean?, -- speed lines on the left (WHOOSH!)
	Seconds: number?, -- how long it stays (default 0.95)
	Rise: number?, -- design units it drifts up while it stays (default 18)
	Z: number?, -- the label's ZIndex (the speed lines go under it)
}

export type Word = {
	Holder: Frame,
	Inner: Frame,
	Scale: UIScale,
	Label: TextLabel,
	Edge: UIStroke?,
	Lines: { Frame },
	Tilt: number,
	Seconds: number,
	Rise: number,
	Size: number,
}

local function span(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function easeOutBack(x: number): number
	local c1, c3 = 2.2, 3.2
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function easeOut(x: number): number
	return 1 - (1 - x) ^ 3
end

function PopWord.build(parent: Instance, text: string, size: number, opts: Opts?): Word
	local o: Opts = opts or {}
	local z = o.Z or 6
	local width = math.floor(size * (#text * 0.72 + 0.6))
	local height = math.floor(size * 1.3)
	local holder = UIKit.new("Frame", {
		Name = "PopWord",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height),
		Visible = false,
		ZIndex = z,
	}, parent)
	local inner = UIKit.new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, holder)
	local scale = UIKit.new("UIScale", { Scale = 1 }, inner)
	local lines: { Frame } = {}
	if o.Lines then
		for i = 1, 3 do
			local line = UIKit.new("Frame", {
				Name = "Line" .. i,
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0, -4 - (i % 2) * 6, 0.5, (i - 2) * math.floor(size * 0.36)),
				Size = UDim2.fromOffset(math.floor(size * (0.9 + 0.3 * (i % 2))), math.max(3, math.floor(size * 0.1))),
				ZIndex = z - 1,
			}, inner)
			UIKit.corner(line, 4)
			Pop.border(line, 2)
			table.insert(lines, line)
		end
	end
	local label = Pop.title(inner, text, size, o.Colors or "Gold", {
		Name = "Word",
		FontFace = PopTheme.Heavy,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	})
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Thickness = math.max(3, math.floor(size / 11))
	end
	return {
		Holder = holder,
		Inner = inner,
		Scale = scale,
		Label = label,
		Edge = edge,
		Lines = lines,
		Tilt = o.Tilt or -10,
		Seconds = o.Seconds or 0.95,
		Rise = o.Rise or 18,
		Size = size,
	}
end

local function fade(word: Word, alpha: number)
	local t = 1 - alpha
	word.Label.TextTransparency = t
	local edge = word.Edge
	if edge then
		edge.Transparency = t
	end
	for _, line in word.Lines do
		line.BackgroundTransparency = t
		local border = line:FindFirstChildOfClass("UIStroke")
		if border then
			border.Transparency = t
		end
	end
end

-- The word `t` seconds in; true when it is over (then hidden).
function PopWord.pose(word: Word, t: number, reduced: boolean?): boolean
	local total = word.Seconds
	if t < 0 or t >= total then
		word.Holder.Visible = false
		return t >= total
	end
	word.Holder.Visible = true
	local out = span(t, total - 0.28, total)
	if reduced then
		word.Scale.Scale = 1
		word.Inner.Rotation = 0
		word.Inner.Position = UDim2.fromScale(0.5, 0.5)
		fade(word, span(t, 0, 0.15) * (1 - out))
		return false
	end
	-- pops in big with an overshoot, wobbles out of its tilt, drifts up, fades
	local pop = easeOutBack(span(t, 0, 0.2))
	word.Scale.Scale = math.max(0, pop * (1 + 0.05 * math.sin(t * 9) * span(t, 0.2, 0.5)) * (1 - 0.25 * out))
	local wobble = 9 * math.sin(t * 34) * (1 - span(t, 0.05, 0.45))
	word.Inner.Rotation = word.Tilt + wobble
	word.Inner.Position = UDim2.new(0.5, 0, 0.5, -math.floor(word.Rise * easeOut(span(t, 0.12, total))))
	fade(word, 1 - out)
	-- the speed lines streak in from the left, then fade first
	for i, line in word.Lines do
		local k = easeOut(span(t, 0.02 * i, 0.25 + 0.02 * i))
		line.Size = UDim2.fromOffset(math.floor(word.Size * (0.4 + (0.6 + 0.3 * (i % 2)) * k)), line.Size.Y.Offset)
		local a = (1 - span(t, 0.35, 0.6)) * (1 - out)
		line.BackgroundTransparency = 1 - a
		local border = line:FindFirstChildOfClass("UIStroke")
		if border then
			border.Transparency = 1 - a
		end
	end
	return false
end

-- Hides the word (between plays).
function PopWord.hide(word: Word)
	word.Holder.Visible = false
end

return PopWord
