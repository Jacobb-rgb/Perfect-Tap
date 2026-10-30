--[[
	RevealKit: the drawing parts every "you got it" reveal shares (owner
	2026-10-29: the secret ores' jackpot now, the egg opening once both are on
	main: the second to land moves Animace's RevealFx onto this, keeping its
	API). Pure: a parent + opts in, instances out, poses set transforms and
	colours; the one global thing is the flash gap tracker, so two flashes
	anywhere in the game are never closer than FlashGap (2.5 a second at most).
	Reduce motion is the caller's opts flag (Reduced).

	  RevealKit.Style                      the look: fonts, colours, counts, sizes, speeds
	  RevealKit.takeFlash(now) -> boolean  may a reveal flash now? (true takes the slot)
	  RevealKit.nextFlashAt() -> number    when the next one may (a flash that waits plays then)
	  RevealKit.word(parent, name, text, size, heavy, z) -> TextLabel
	  RevealKit.rays(parent, z) -> Rays     three layers of two-tone bars
	  RevealKit.poseRays(rays, t, grow, leave, opts)
	  RevealKit.rings(parent, count, z) -> { Frame }   shockwave rings
	  RevealKit.poseRing(ring, u, color)   u = 0..1 through its flight
	  RevealKit.flash(parent, z) -> Frame  a full-screen flash frame
	  RevealKit.poseFlash(frame, f)        f = 0..1 through its fade (>= 1: gone)
	  RevealKit.fade(root, alpha), rainbow(shift) -> ColorSequence, hue(x) -> Color3
	Style "Secret" values (the egg hatch v2's RevealFx "Secret" tier): rays
	alternating near-black (14,10,22) and a rainbow drifting 0.25 turn/s, layers
	+45 / -30 degrees a second, a gold one at 12; flash (255,240,200), at most
	0.9 opaque, gone in 0.45 s; Montserrat words with a dark PopTheme edge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local PopTheme = require(Config:WaitForChild("PopTheme"))
local SecretOreConfig = require(Config:WaitForChild("SecretOreConfig"))
local UIKit = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIKit"))

local RevealKit = {}

local WHITE = Color3.new(1, 1, 1)

RevealKit.FlashGap = 0.4 -- seconds between two reveal flashes, anywhere

RevealKit.Style = {
	Font = "rbxasset://fonts/families/Montserrat.json",
	Edge = PopTheme.Outline,
	Dark = Color3.fromRGB(14, 10, 22),
	Gold = Color3.fromRGB(255, 206, 72),
	FlashColor = Color3.fromRGB(255, 240, 200),
	FlashPeak = 0.9,
	FlashTime = 0.45,
	Rainbow = SecretOreConfig.Rainbow,
	RayLength = 860, -- design units, end to end through the middle
	Rays = {
		Front = { Count = 10, Width = 70, Speed = 45 }, -- a bar is two rays
		Back = { Count = 8, Width = 40, Speed = -30, Length = 0.86, Transparency = 0.45 },
		Gold = { Count = 6, Width = 120, Speed = 12, Length = 1.25, Transparency = 0.55 },
		Phone = 6, -- front bars on a phone (no back layer, every other gold bar)
		HueDrift = 0.25, -- rainbow turns a second
	},
	Ring = { Size = 200, Thickness = 22, Grow = 7 },
}

local lastFlash = -math.huge

-- May a reveal flash at `now` (os.clock())? True takes the slot: the next one waits FlashGap.
function RevealKit.takeFlash(now: number): boolean
	if now - lastFlash < RevealKit.FlashGap then
		return false
	end
	lastFlash = now
	return true
end

-- When the next reveal flash may come (os.clock() seconds): a flash that had to wait plays then.
function RevealKit.nextFlashAt(): number
	return lastFlash + RevealKit.FlashGap
end

-- (tests) forget the last flash
function RevealKit.resetFlash()
	lastFlash = -math.huge
end

function RevealKit.rainbow(shift: number): ColorSequence
	local colors = RevealKit.Style.Rainbow
	local keys = {}
	for k = 1, #colors + 1 do
		local color = colors[(k - 1 + math.floor(shift)) % #colors + 1]
		table.insert(keys, ColorSequenceKeypoint.new((k - 1) / #colors, color))
	end
	return ColorSequence.new(keys)
end

-- A rainbow hue at turn `x` (0..1), bright enough to read on black.
function RevealKit.hue(x: number): Color3
	return Color3.fromHSV(x % 1, 0.72, 1)
end

-- Fades every word, edge and filled box under `root` (alpha 0 = shown, 1 = gone).
function RevealKit.fade(root: Instance, alpha: number)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextTransparency = alpha
		elseif d:IsA("UIStroke") then
			d.Transparency = alpha
		elseif d:IsA("Frame") then
			d.BackgroundTransparency = alpha
		end
	end
end

function RevealKit.word(parent: Instance, name: string, text: string, size: number, heavy: boolean, z: number): TextLabel
	return UIKit.new("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = Font.new(RevealKit.Style.Font, if heavy then Enum.FontWeight.Heavy else Enum.FontWeight.Bold),
		Text = text,
		TextColor3 = WHITE,
		TextSize = size,
		Size = UDim2.fromOffset(math.max(200, #text * size * 0.8), size * 1.25),
		ZIndex = z,
	}, parent)
end

---------------------------------------------------------------- rays

export type Rays = { Front: { Frame }, Back: { Frame }, Gold: { Frame } }

export type RayOpts = {
	Phone: boolean?,
	Reduced: boolean?,
	Gold: boolean?, -- the third, gold layer
}

local function bar(parent: Instance, name: string, width: number, z: number): Frame
	local frame = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, RevealKit.Style.RayLength),
		Visible = false,
		ZIndex = z,
	}, parent)
	-- bright near the middle, gone at both ends
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, frame)
	return frame
end

-- The three ray layers in `parent` (its middle is the middle); gold and back at z, front at z + 1.
function RevealKit.rays(parent: Instance, z: number): Rays
	local style = RevealKit.Style.Rays
	local rays: Rays = { Front = {}, Back = {}, Gold = {} }
	for k = 1, style.Gold.Count do
		table.insert(rays.Gold, bar(parent, "Gold" .. k, style.Gold.Width, z))
	end
	for k = 1, style.Back.Count do
		table.insert(rays.Back, bar(parent, "Back" .. k, style.Back.Width, z))
	end
	for k = 1, style.Front.Count do
		table.insert(rays.Front, bar(parent, "Ray" .. k, style.Front.Width, z + 1))
	end
	return rays
end

-- The rays `t` seconds in: `grow` 0..1 (their length), `leave` 0..1 (fading out).
function RevealKit.poseRays(rays: Rays, t: number, grow: number, leave: number, opts: RayOpts)
	local style = RevealKit.Style
	local reduced = opts.Reduced == true
	local phone = opts.Phone == true
	local on = leave < 1
	local front = if phone then style.Rays.Phone else #rays.Front
	for k, frame in rays.Front do
		local show = on and k <= front
		frame.Visible = show
		if show then
			frame.Rotation = (k - 1) * 180 / front + (if reduced then 0 else t * style.Rays.Front.Speed)
			frame.Size = UDim2.fromOffset(style.Rays.Front.Width, style.RayLength * grow)
			frame.BackgroundColor3 = if k % 2 == 1 then style.Dark else RevealKit.hue((k - 1) / front + t * style.Rays.HueDrift)
			frame.BackgroundTransparency = leave
		end
	end
	local back = style.Rays.Back
	for k, frame in rays.Back do
		local show = on and not phone
		frame.Visible = show
		if show then
			frame.Rotation = (k - 0.5) * 180 / #rays.Back + (if reduced then 0 else t * back.Speed)
			frame.Size = UDim2.fromOffset(back.Width, style.RayLength * back.Length * grow)
			frame.BackgroundColor3 = RevealKit.hue((k - 1) / #rays.Back + 0.5 + t * style.Rays.HueDrift)
			frame.BackgroundTransparency = back.Transparency + (1 - back.Transparency) * leave
		end
	end
	local gold = style.Rays.Gold
	for k, frame in rays.Gold do
		local show = on and opts.Gold == true and (not phone or k % 2 == 0)
		frame.Visible = show
		if show then
			frame.Rotation = (k - 1) * 180 / #rays.Gold + 15 + (if reduced then 0 else t * gold.Speed)
			frame.Size = UDim2.fromOffset(gold.Width, style.RayLength * gold.Length * grow)
			frame.BackgroundColor3 = style.Gold
			frame.BackgroundTransparency = gold.Transparency + (1 - gold.Transparency) * leave
		end
	end
end

---------------------------------------------------------------- shockwave rings

function RevealKit.rings(parent: Instance, count: number, z: number): { Frame }
	local style = RevealKit.Style.Ring
	local list = {}
	for k = 1, count do
		local ring = UIKit.new("Frame", {
			Name = "Shock" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(style.Size, style.Size),
			Visible = false,
			ZIndex = z,
		}, parent)
		UIKit.corner(ring, 999)
		UIKit.new("UIStroke", { Color = WHITE, Thickness = style.Thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
		UIKit.new("UIScale", { Scale = 1 }, ring)
		table.insert(list, ring)
	end
	return list
end

-- A ring `u` (0..1) through its flight: it grows fast, thins and fades (u outside 0..1: hidden).
function RevealKit.poseRing(ring: Frame, u: number, color: Color3)
	local on = u >= 0 and u < 1
	ring.Visible = on
	if not on then
		return
	end
	local style = RevealKit.Style.Ring
	local scale = ring:FindFirstChildOfClass("UIScale") :: UIScale
	local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
	scale.Scale = 0.35 + style.Grow * (1 - (1 - u) ^ 3)
	stroke.Thickness = style.Thickness * (1 - u) + 2
	stroke.Color = color
	stroke.Transparency = u ^ 1.5
end

---------------------------------------------------------------- flash

function RevealKit.flash(parent: Instance, z: number): Frame
	return UIKit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = RevealKit.Style.FlashColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent)
end

-- The flash `f` (0..1) through its fade; f >= 1 or < 0: gone.
function RevealKit.poseFlash(frame: Frame, f: number)
	local style = RevealKit.Style
	frame.BackgroundTransparency = if f >= 0 and f < 1 then 1 - style.FlashPeak * (1 - f) ^ 3 else 1
end

return RevealKit
