--[[
	The confetti burst after a purchase (owner 2026-10-27, the UI pack reel:
	confetti rains over the screen when something is bought). Small bright
	paper bits (the Pop rainbow) fall from above the top edge with a sway and
	a spin, staggered, then fade; one ScreenGui over everything, gone after
	the burst. Reduce motion: a few slow bits only.

	  Confetti.pieces(count, seed) -> { Piece }   where and how each bit falls (pure, the specs)
	  Confetti.burst(playerGui?)                  plays one burst (the game only: tweens)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PopTheme = require(Shared.Config.PopTheme)

local Confetti = {}

Confetti.Count = 70 -- bits in a burst
Confetti.ReducedCount = 14 -- with reduce motion on
Confetti.Fall = { 1.5, 2.4 } -- seconds a bit takes from the top to the bottom
Confetti.Stagger = 0.45 -- seconds over which the bits start
Confetti.Size = { 10, 18 } -- a bit's long side (design units at 720 tall; the gui scales by screen)
Confetti.Order = 60 -- over every window

export type Piece = {
	X: number, -- 0..1 across the screen where it starts
	Drift: number, -- how far it sways sideways by the bottom (a share of the screen's width)
	Delay: number, -- seconds before it starts
	Time: number, -- seconds it falls
	Spin: number, -- degrees it turns while falling
	Rotation: number, -- its start angle
	Size: Vector2, -- design units
	Color: Color3,
}

-- A small deterministic random stream (the same burst for the same seed).
local function stream(seed: number): () -> number
	local state = (seed % 2147483646) + 1
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- Where and how each of `count` bits falls (seed: the same bits again).
function Confetti.pieces(count: number, seed: number): { Piece }
	local random = stream(seed)
	local colors = PopTheme.Rainbow
	local out: { Piece } = {}
	for i = 1, count do
		local long = Confetti.Size[1] + random() * (Confetti.Size[2] - Confetti.Size[1])
		local spin = 180 + random() * 540
		table.insert(out, {
			X = 0.02 + random() * 0.96,
			Drift = (random() - 0.5) * 0.16,
			Delay = random() * Confetti.Stagger,
			Time = Confetti.Fall[1] + random() * (Confetti.Fall[2] - Confetti.Fall[1]),
			Spin = if random() < 0.5 then spin else -spin,
			Rotation = random() * 360,
			Size = Vector2.new(math.floor(long * 0.55 + 0.5), math.floor(long + 0.5)),
			Color = colors[(i - 1) % #colors + 1],
		})
	end
	return out
end

--[[
	Plays one burst over the screen (`playerGui`: the local player's
	PlayerGui by default). `reduced`: reduce motion (fewer bits). Safe to call
	often: each burst has its own gui and cleans itself up.
]]
function Confetti.burst(playerGui: Instance?, reduced: boolean?)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local parent = playerGui
	if parent == nil then
		local player = Players.LocalPlayer
		parent = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	end
	if parent == nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TerraForgeConfetti"
	gui.DisplayOrder = Confetti.Order
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = parent
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 720
	local scale = math.max(0.6, height / PopTheme.BaseHeight)
	local seed = math.floor(os.clock() * 1000)
	local longest = 0
	for _, piece in Confetti.pieces(if reduced then Confetti.ReducedCount else Confetti.Count, seed) do
		local bit = Instance.new("Frame")
		bit.Name = "Bit"
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.BackgroundColor3 = piece.Color
		bit.BorderSizePixel = 0
		bit.Position = UDim2.new(piece.X, 0, 0, -24)
		bit.Rotation = piece.Rotation
		bit.Size = UDim2.fromOffset(math.floor(piece.Size.X * scale), math.floor(piece.Size.Y * scale))
		bit.Parent = gui
		local time = if reduced then piece.Time * 1.4 else piece.Time
		local fall = TweenService:Create(bit, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, piece.Delay), {
			Position = UDim2.new(piece.X + piece.Drift, 0, 1, 24),
			Rotation = piece.Rotation + (if reduced then piece.Spin * 0.25 else piece.Spin),
		})
		fall:Play()
		local fade = TweenService:Create(
			bit,
			TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, piece.Delay + time * 0.8),
			{
				BackgroundTransparency = 1,
			}
		)
		fade:Play()
		longest = math.max(longest, piece.Delay + time)
	end
	Debris:AddItem(gui, longest + 0.5)
end

return Confetti
