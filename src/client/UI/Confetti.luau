--[[
	Confetti: a burst of little paper bits when a NEW golem wakes in the
	capsule opening (owner 2026-10-28, round 2: "make it even cooler").

	- build(parent, count) makes the pieces once (small rounded frames,
	  hidden); burst() sends them all out from a point and lets them fall and
	  fade: three TweenService tweens a piece, made when it bursts (nothing
	  runs every frame, nothing is made while it flies).
	- targets(count, seed) is the pure part: where each piece ends up, its
	  turn and size, the same for the same seed (the Lune specs, the previews).
	- No flashing (the pieces only move and fade). CapsuleController never
	  bursts with Reduce motion.

	Pure apart from the tweens in burst().
]]

local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.UIKit)

local Confetti = {}

Confetti.Count = 28
Confetti.Seconds = 1.1 -- a piece's flight
Confetti.Spread = 0.34 -- how far out (share of the screen's width) the farthest piece flies
Confetti.Colors = {
	Color3.fromRGB(255, 92, 92),
	Color3.fromRGB(255, 196, 56),
	Color3.fromRGB(96, 226, 90),
	Color3.fromRGB(70, 186, 255),
	Color3.fromRGB(196, 110, 255),
	Color3.fromRGB(255, 255, 255),
}

export type Target = { X: number, Y: number, Turn: number, Size: number }

-- A small deterministic random (a seed's sequence; no Random object needed in the previews).
local function rng(seed: number): () -> number
	local state = math.floor(math.abs(seed) * 9301 + 49297) % 233280
	return function(): number
		state = (state * 9301 + 49297) % 233280
		return state / 233280
	end
end

--[[
	Where each of `count` pieces ends up from the burst point (shares of the
	screen: X right, Y down), its turn in degrees and its size (design
	units). The pieces fan out all round, most of them up first and down at
	the end (Y > 0: they fall), never past Spread.
]]
function Confetti.targets(count: number, seed: number): { Target }
	local next01 = rng(seed)
	local out: { Target } = {}
	for i = 1, math.max(0, math.floor(count)) do
		local angle = (i - 1) / math.max(1, count) * math.pi * 2 + next01() * 0.6
		local reach = Confetti.Spread * (0.45 + 0.55 * next01())
		local x = math.cos(angle) * reach
		-- (they fall: the end point is lower than the throw)
		local y = math.sin(angle) * reach * 0.55 + 0.12 + next01() * 0.1
		table.insert(out, {
			X = x,
			Y = y,
			Turn = (next01() - 0.5) * 720,
			Size = 8 + math.floor(next01() * 8),
		})
	end
	return out
end

-- Makes `count` pieces in `parent` (a full-screen frame), hidden.
function Confetti.build(parent: Instance, count: number?, z: number?): { Frame }
	local pieces: { Frame } = {}
	for i = 1, count or Confetti.Count do
		local piece = UIKit.new("Frame", {
			Name = "Confetti" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Confetti.Colors[(i - 1) % #Confetti.Colors + 1],
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(10, 6),
			Visible = false,
			ZIndex = z or 8,
		}, parent) :: Frame
		UIKit.corner(piece, 2)
		table.insert(pieces, piece)
	end
	return pieces
end

-- Poses the pieces `t` seconds into a burst from `center` (screen shares), without tweens (the previews).
function Confetti.pose(pieces: { Frame }, center: Vector2, seed: number, t: number)
	local k = math.clamp(t / Confetti.Seconds, 0, 1)
	local out = 1 - (1 - k) ^ 2 -- (fast out, slowing down)
	for i, target in Confetti.targets(#pieces, seed) do
		local piece = pieces[i]
		piece.Visible = t >= 0 and k < 1
		piece.Position = UDim2.fromScale(center.X + target.X * out, center.Y + target.Y * out - 0.12 * math.sin(k * math.pi))
		piece.Rotation = target.Turn * k
		piece.Size = UDim2.fromOffset(target.Size, math.floor(target.Size * 0.6))
		piece.BackgroundTransparency = math.clamp((k - 0.6) / 0.4, 0, 1)
	end
end

-- Sends every piece out from `center` (screen shares) and lets it fall and fade.
function Confetti.burst(pieces: { Frame }, center: Vector2, seed: number)
	for i, target in Confetti.targets(#pieces, seed) do
		local piece = pieces[i]
		piece.Visible = true
		piece.Position = UDim2.fromScale(center.X, center.Y)
		piece.Rotation = 0
		piece.Size = UDim2.fromOffset(target.Size, math.floor(target.Size * 0.6))
		piece.BackgroundTransparency = 0
		local seconds = Confetti.Seconds * (0.8 + 0.2 * (i % 5) / 4)
		TweenService:Create(piece, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(center.X + target.X, center.Y + target.Y),
			Rotation = target.Turn,
		}):Play()
		local fade = TweenService:Create(
			piece,
			TweenInfo.new(seconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, seconds * 0.6),
			{ BackgroundTransparency = 1 }
		)
		fade.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				piece.Visible = false
			end
		end)
		fade:Play()
	end
end

return Confetti
