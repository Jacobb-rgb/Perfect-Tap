--[[
	The spray-washing look in the store-card style (owner 2026-10-20: "like
	the video, even better with animations and graphics"). It is
	DefaultLook (the clump, the wand, the jet, the reveal spin and the grade
	card) plus:

	  dirt chunks   every cell that comes clean throws a few dirt chunks off
	                the clump: they fly out toward the camera and the sides,
	                tumble, fall and fade (one RenderStepped for all of them,
	                at most MaxChunks at once)
	  % CLEAN bar   a green bar with a glossy top that turns gold at 100 %
	  the card      its border glows in the ore's rarity colour; a NEW ORE
	                DISCOVERED! / NEW RELIC! banner pops over it the first
	                time the player cleans that ore (CleanResult.New)

	CleaningLookController installs it (CleaningController.setLook).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CardTheme = require(Shared.Config.CardTheme)
local Geo = require(Shared.Builders.Geo)

local DefaultLook = require(script.Parent.DefaultLook)
local Motion = require(script.Parent.Parent.UI.Motion)
local Card = require(script.Parent.Parent.UI.Card)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CardLook = {}

CardLook.MaxChunks = 40
CardLook.ChunksPerCell = 2
CardLook.ChunkLife = 0.75 -- seconds
CardLook.Gravity = 38
CardLook.Fill = Color3.fromRGB(96, 214, 64)
CardLook.FillDone = Color3.fromRGB(255, 200, 40)

type Chunk = { Part: BasePart, Velocity: Vector3, Spin: Vector3, Born: number, Size: Vector3 }

-- (a tiny seeded generator per session: the same throw pattern every run)
local function rng(seed: number): () -> number
	local state = math.max(1, seed % 2147483647)
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- The velocity of a chunk thrown off the face at random r(): out of the
-- face (toward the camera), to the sides and up. Pure: specs check it.
function CardLook.throw(face: CFrame, r: () -> number): Vector3
	local out = face:VectorToWorldSpace(Vector3.new(0, 0, 1)) * (6 + r() * 6)
	local side = face:VectorToWorldSpace(Vector3.new((r() - 0.5) * 2, 0, 0)) * (5 + r() * 6)
	return out + side + Vector3.new(0, 7 + r() * 8, 0)
end

local function chunkLoop(ctx: any, state: any)
	if state.chunkLoop then
		return
	end
	state.chunkLoop = RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		local list: { Chunk } = state.chunks
		for i = #list, 1, -1 do
			local c = list[i]
			local age = (now - c.Born) / CardLook.ChunkLife
			if age >= 1 or not c.Part.Parent then
				c.Part:Destroy()
				table.remove(list, i)
			else
				c.Velocity -= Vector3.new(0, CardLook.Gravity * dt, 0)
				local cf = c.Part.CFrame
				c.Part.CFrame = (cf + c.Velocity * dt) * CFrame.Angles(c.Spin.X * dt, c.Spin.Y * dt, c.Spin.Z * dt)
				c.Part.Transparency = math.max(0, (age - 0.55) / 0.45)
				c.Part.Size = c.Size * (1 - age * 0.4)
			end
		end
	end)
	table.insert(ctx.Connections, state.chunkLoop)
end

-- Throws a few chunks of `color` from `position` off the face.
local function fling(ctx: any, state: any, position: Vector3, color: Color3)
	local face: CFrame = ctx.WorkCF
	for _ = 1, CardLook.ChunksPerCell do
		if #state.chunks >= CardLook.MaxChunks then
			local oldest = table.remove(state.chunks, 1)
			if oldest then
				oldest.Part:Destroy()
			end
		end
		local r = state.random
		local s = 0.12 + r() * 0.18
		local size = Vector3.new(s, s * (0.7 + r() * 0.5), s)
		local part = Geo.block(ctx.Folder, CFrame.new(position), size, color:Lerp(Color3.new(0, 0, 0), r() * 0.25), nil, {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Name = "DirtChunk",
		})
		table.insert(state.chunks, {
			Part = part,
			Velocity = CardLook.throw(face, r),
			Spin = Vector3.new((r() - 0.5) * 14, (r() - 0.5) * 14, (r() - 0.5) * 14),
			Born = os.clock(),
			Size = size,
		})
	end
	chunkLoop(ctx, state)
end

-- Where a chunk thrown from `from` with `velocity` is after `t` seconds (previews).
function CardLook.chunkAt(from: Vector3, velocity: Vector3, t: number): Vector3
	return from + velocity * t - Vector3.new(0, 0.5 * CardLook.Gravity * t * t, 0)
end

-- The "% CLEAN" bar in the card look: green with a glossy top, gold when done.
function CardLook.styleBar(view: any)
	local fill = view.CleanFill :: Frame
	fill.BackgroundColor3 = CardLook.Fill
	if not fill:FindFirstChild("Gloss") then
		local gloss = UIKit.new("Frame", {
			Name = "Gloss",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 3),
			Size = UDim2.new(1, -8, 0.36, 0),
			ZIndex = 2,
		}, fill)
		UIKit.corner(gloss, 8)
	end
	local bar = view.CleanBar :: Frame
	local edge = bar:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = CardTheme.Edge
		edge.Thickness = 3
	end
end

function CardLook.begin(ctx: any)
	DefaultLook.begin(ctx)
	local state = ctx.LookState
	state.chunks = {}
	state.random = rng(math.floor(os.clock() * 1000))
	CardLook.styleBar(ctx.View)
end

function CardLook.spray(uv: Vector2?, hit: Vector3?, active: boolean, ctx: any)
	DefaultLook.spray(uv, hit, active, ctx)
end

function CardLook.cleaned(cells: { number }, ctx: any)
	local state = ctx.LookState
	if state and state.shell and state.chunks then
		for _, index in cells do
			local block = state.shell.Dirt[index]
			if block and block.Parent then
				fling(ctx, state, block.Position, block.Color)
			end
		end
	end
	DefaultLook.cleaned(cells, ctx)
end

function CardLook.cracked(crystals: { number }, ctx: any)
	DefaultLook.cracked(crystals, ctx)
end

function CardLook.progress(fraction: number, ctx: any)
	DefaultLook.progress(fraction, ctx)
	local fill = ctx.View.CleanFill :: Frame
	fill.BackgroundColor3 = if fraction >= 1 then CardLook.FillDone else CardLook.Fill
end

function CardLook.quality(score: number, ctx: any)
	DefaultLook.quality(score, ctx)
end

function CardLook.finished(ctx: any)
	local state = ctx.LookState
	-- the last specks fly too
	if state and state.shell and state.chunks then
		local thrown = 0
		for _, block in state.shell.Dirt do
			if block.Parent and thrown < 12 then
				thrown += 1
				fling(ctx, state, block.Position, block.Color)
			end
		end
		-- and the clump's body breaks up into chunks as it crumbles (DefaultLook's crumble): a few
		-- of its parts, spread over the body (it has dozens of wedges)
		-- (Reduce motion: the clump just goes)
		local body = if Motion.reduced() then {} else state.shell.BackRock
		local step = math.max(1, math.floor(#body / 6))
		for i = 1, #body, step do
			local part = body[i]
			if part.Parent and thrown < 18 then
				thrown += 1
				fling(ctx, state, part.Position, part.Color)
			end
		end
	end
	DefaultLook.finished(ctx)
end

-- The card's border in the ore's rarity colour.
function CardLook.glowCard(view: any, color: Color3)
	local edge = view.Card:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = color
		edge.Thickness = 4
	end
end

-- The NEW ORE DISCOVERED! banner over the card (pops in, stays while the card shows).
function CardLook.banner(view: any, text: string, color: Color3): TextLabel
	local old = view.Gui:FindFirstChild("NewBanner")
	if old then
		old:Destroy()
	end
	local banner = Card.title(view.Gui, text, 40, "Gold", {
		Name = "NewBanner",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, view.Card.Position.Y.Scale, view.Card.Position.Y.Offset - view.Card.Size.Y.Offset / 2 - 6),
		Size = UDim2.fromOffset(620, 50),
		ZIndex = 32,
	})
	local gradient = banner:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 0.8), 0.55), color)
	end
	local pop = UIKit.new("UIScale", { Scale = 0.3 }, banner)
	local popped = pcall(function()
		TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	if not popped then
		pop.Scale = 1 -- (the Lune previews: no tweens)
	end
	-- it goes with the card (Collect)
	pcall(function()
		local watch: RBXScriptConnection? = nil
		watch = view.Card:GetPropertyChangedSignal("Visible"):Connect(function()
			if not view.Card.Visible then
				banner:Destroy()
				if watch then
					watch:Disconnect()
				end
			end
		end)
	end)
	return banner
end

function CardLook.done(result: { [string]: any }, ctx: any)
	DefaultLook.done(result, ctx)
	local view = ctx.View
	-- the card glows in the ore's rarity colour
	local rarityColor = ctx.Rarity and ctx.Rarity.Color or CardTheme.Glows.Gold.Edge
	CardLook.glowCard(view, rarityColor)
	if result.New then
		CardLook.banner(view, "NEW ORE DISCOVERED!", CardTheme.Glows.Gold.Edge)
	elseif ctx.Relic and result.Relic == ctx.Relic and result.Collected then
		CardLook.banner(view, "NEW RELIC!", rarityColor)
	end
end

function CardLook.cancel(ctx: any)
	DefaultLook.cancel(ctx)
	local state = ctx.LookState
	if state and state.chunks then
		for _, c in state.chunks do
			c.Part:Destroy()
		end
		table.clear(state.chunks)
	end
	local banner = ctx.View and ctx.View.Gui:FindFirstChild("NewBanner")
	if banner then
		banner:Destroy()
	end
end

return CardLook
