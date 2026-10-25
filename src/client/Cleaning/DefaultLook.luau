--[[
	The default look of spray-washing (CleaningController.setLook can swap it
	for another): the dirty clump (OreShellBuilder), the spray wand with its
	water jet and splash, dirt blocks that thin out and pop off, cracked
	crystals, the "% CLEAN" bar and QUALITY meter of CleaningView, then the
	rise-and-spin reveal (RevealFx) and the grade card.

	Every callback gets the session's ctx last (see CleaningController's
	header); this look keeps its own state in ctx.LookState.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared.Config.ItemData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local Geo = require(Shared.Builders.Geo)

local RevealFx = require(script.Parent.RevealFx)
local SprayParts = require(script.Parent.SprayParts)
local CleaningView = require(script.Parent.Parent.UI.CleaningView)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local StateController = require(script.Parent.Parent.Controllers.StateController)

local DefaultLook = {}

local JET_COLOR = SprayParts.JetColor
local HIDDEN = SprayParts.Hidden

local function props(extra: { [string]: any }?): { [string]: any }
	local p = { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local function emitter(parent: Instance, texture: string, configure: (ParticleEmitter) -> ()): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Enabled = false
	e.LightInfluence = 0
	configure(e)
	e.Parent = parent
	return e
end

function DefaultLook.begin(ctx: any)
	local state: any = {}
	ctx.LookState = state
	local folder = ctx.Folder
	-- the real ore (or the dusty relic) waits under the dirt
	state.shell = OreShellBuilder.build(ctx.Pattern, ctx.WorkCF, folder, ctx.Relic)
	OreShellBuilder.workLight(ctx.WorkCF, folder)
	for _, block in state.shell.Dirt do
		block:SetAttribute("FullCF", block.CFrame)
	end
	-- the crystals sparkle so players can spot them
	for _, shard in state.shell.Fragile do
		emitter(shard, "rbxasset://textures/particles/sparkles_main.dds", function(e)
			e.Color = ColorSequence.new(Color3.new(1, 1, 1))
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 0),
			})
			e.Lifetime = NumberRange.new(0.4, 0.7)
			e.Speed = NumberRange.new(0.1, 0.3)
			e.Rate = 4
			e.LightEmission = 1
			e.Enabled = true
		end)
	end
	state.wand = SprayParts.wand(folder)
	state.jet = SprayParts.jet(folder)
	state.spot = SprayParts.spot(folder)
	local splash = Geo.block(folder, HIDDEN, Vector3.new(0.1, 0.1, 0.1), JET_COLOR, nil, props({ Name = "Splash", Transparency = 1 }))
	state.splash = splash
	state.mist = emitter(splash, "rbxasset://textures/particles/smoke_main.dds", function(e)
		e.Color = ColorSequence.new(Color3.fromRGB(205, 235, 255))
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1.3) })
		e.Lifetime = NumberRange.new(0.25, 0.45)
		e.Speed = NumberRange.new(1.5, 2.5)
		e.SpreadAngle = Vector2.new(75, 75)
		e.Rate = 40
	end)
	state.drops = emitter(splash, "rbxasset://textures/particles/sparkles_main.dds", function(e)
		e.Color = ColorSequence.new(JET_COLOR)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.3, 0.5)
		e.Speed = NumberRange.new(4, 8)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Acceleration = Vector3.new(0, -30, 0)
		e.Rate = 60
		e.LightEmission = 0.6
	end)
	state.lastPop = 0
	state.lastDust = 0
	local view = ctx.View
	view.Title.Text = "SPRAY"
	view.Instruction.Text = if #ctx.Pattern.Crystals > 0
		then "Wash the dirt off. Don't blast the glowing crystals!"
		else "Wash all the dirt off the ore!"
	CleaningView.setClean(view, 0)
	CleaningView.setMeter(view, 1)
end

-- Every frame: the wand under the pointer, the jet and splash while spraying,
-- the dirt in reach thinning out as it is washed.
function DefaultLook.spray(uv: Vector2?, hit: Vector3?, active: boolean, ctx: any)
	local state = ctx.LookState
	if not state or state.finished then
		return
	end
	local workCF: CFrame = ctx.WorkCF
	-- a lifted finger has no hover: no wand without a touch
	if not uv or not hit or (not active and ctx.Input == "Touch") then
		SprayParts.placeWand(state.wand, nil)
		SprayParts.hideJet(state.jet)
		SprayParts.placeSpot(state.spot, workCF, nil)
		state.mist.Enabled = false
		state.drops.Enabled = false
		Sfx.loop("Spray", false)
		return
	end
	local wandCF, tip = SprayParts.wandFrame(workCF, hit, active)
	SprayParts.placeWand(state.wand, wandCF)
	if active then
		SprayParts.placeJet(state.jet, tip, hit)
		SprayParts.placeSpot(state.spot, workCF, hit, ctx.Radius * OreShellBuilder.Scale)
		state.splash.CFrame = CFrame.lookAt(hit, hit - workCF.LookVector)
	else
		SprayParts.hideJet(state.jet)
		SprayParts.placeSpot(state.spot, workCF, nil)
	end
	state.mist.Enabled = active
	state.drops.Enabled = active
	Sfx.loop("Spray", active)
	if not active then
		return
	end
	-- the dirt in reach thins out (cells that came clean pop in cleaned())
	local pattern = ctx.Pattern
	local reach = ctx.Radius * 1.1
	for index, cell in pattern.Cells do
		local block = state.shell.Dirt[index]
		if block and block.Parent and (cell.Center - uv).Magnitude < reach then
			local left = ctx.dirtLeft(index)
			if left > 0 then
				SprayParts.thin(block, left)
			end
		end
	end
end

local function popBlock(ctx: any, block: BasePart)
	local state = ctx.LookState
	local position = block.Position
	local tween = TweenService:Create(block, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = Vector3.new(0.02, 0.02, 0.02),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		block:Destroy()
	end)
	local now = os.clock()
	if now - state.lastDust > 0.06 then
		state.lastDust = now
		Vfx.burst("FineDust", position, 3, block.Color)
	end
end

function DefaultLook.cleaned(cells: { number }, ctx: any)
	local state = ctx.LookState
	if not state then
		return
	end
	for _, index in cells do
		local block = state.shell.Dirt[index]
		if block and block.Parent then
			popBlock(ctx, block)
		end
	end
	local now = os.clock()
	if #cells > 0 and now - state.lastPop > 0.08 then
		state.lastPop = now
		Sfx.play("DirtPop")
	end
end

function DefaultLook.cracked(crystals: { number }, ctx: any)
	local state = ctx.LookState
	if not state then
		return
	end
	for _, index in crystals do
		local shard = state.shell.Fragile[index]
		if shard then
			Vfx.burst("Glint", shard.Position, 10, ctx.Ore.Glow)
			Vfx.chips(shard.Position, 3, ctx.Ore.Glow, 0.5)
			shard:Destroy()
		end
	end
	Sfx.play("Chip")
	CameraShake.add(0.15)
	ctx.feedback("Crystal cracked!", Theme.Bad)
	ctx.flash(Color3.fromRGB(255, 80, 60), 0.85)
end

function DefaultLook.progress(fraction: number, ctx: any)
	CleaningView.setClean(ctx.View, fraction)
end

function DefaultLook.quality(score: number, ctx: any)
	CleaningView.setMeter(ctx.View, score)
end

---------------------------------------------------------------- reveal

-- All the dirt is off: the last specks go, the ore (or relic) rises and spins.
function DefaultLook.finished(ctx: any)
	local state = ctx.LookState
	if not state then
		return
	end
	state.finished = true
	Sfx.loop("Spray", false)
	SprayParts.placeWand(state.wand, nil)
	SprayParts.hideJet(state.jet)
	SprayParts.placeSpot(state.spot, ctx.WorkCF, nil)
	state.mist.Enabled = false
	state.drops.Enabled = false
	for _, block in state.shell.Dirt do
		if block.Parent then
			popBlock(ctx, block)
		end
	end
	ctx.feedback("Sparkling!", Color3.fromRGB(160, 255, 170))
	Vfx.burst("Glint", ctx.worldAt(0, 0, OreShellBuilder.CoreFront + 0.1), 14, ctx.Ore.Glow)
	CleaningView.setReveal(ctx.View, "Let's see what you uncovered...")
	local rarity = ctx.Rarity
	local order = rarity.Order
	local shell = state.shell
	-- the crystals that made it sparkle off with the dirt
	for _, shard in shell.Fragile do
		if shard.Parent then
			Vfx.burst("Glint", shard.Position, 6, ctx.Ore.Glow)
			shard:Destroy()
		end
	end
	for _, d in shell.Model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "CrystalBase" then
			d:Destroy()
		end
	end
	-- the ore (or relic) rises out of the clump and turns like on a turntable
	local parts: { BasePart } = shell.Core
	local pivot = shell.TreasurePivot
	local offsets = {}
	for i, p in parts do
		offsets[i] = pivot:ToObjectSpace(p.CFrame)
	end
	local center = pivot.Position
	local workLight = ctx.Folder:FindFirstChild("WorkLight")
	local workLamp = workLight and workLight:FindFirstChildOfClass("PointLight")
	if workLamp then
		TweenService:Create(workLamp, TweenInfo.new(0.4), { Brightness = 0.4 }):Play()
	end
	local holder = Geo.ball(ctx.Folder, center, 0.1, ctx.Ore.Glow, nil, props({ Transparency = 1 }))
	local light = Instance.new("PointLight")
	light.Color = ctx.Ore.Glow
	light.Range = 18
	light.Brightness = 0
	light.Shadows = false
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 3 + order * 0.5 }):Play()
	task.delay(0.35, function()
		TweenService:Create(light, TweenInfo.new(1.2), { Brightness = 1.2 }):Play()
	end)
	local burst = Geo.ball(ctx.Folder, center, 0.6, rarity.Color, Enum.Material.Neon, props({ Transparency = 0.2 }))
	TweenService
		:Create(
			burst,
			TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(7, 7, 7), Transparency = 1 }
		)
		:Play()
	local plan = RevealFx.plan(order)
	Vfx.burst("Burst", center, 20 + order * 10, rarity.Color)
	Vfx.burst("Glint", center, 12 + order * 4, ctx.Ore.Glow)
	Sfx.play("Reveal")
	if plan.Fanfare then
		Sfx.play("Discovery", center, 0.8 + 0.1 * (order - 5))
	end
	-- softer on phones and tablets (the shared module still has the last word: Settings)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	CameraShake.add(plan.Shake * (if touchOnly then RevealFx.TouchShake else 1))
	ctx.flash(rarity.Color, plan.Flash)
	-- Legendary and Mythic: the view narrows for a moment while the spin slows down
	local fitFov = ctx.FitFov
	if plan.FovPunch > 0 and fitFov then
		local camera = ctx.Camera
		TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = fitFov - plan.FovPunch,
		}):Play()
		task.delay(plan.Duration * 0.6, function()
			if not ctx.ended() then
				TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
					FieldOfView = fitFov,
				}):Play()
			end
		end)
	end
	-- a shine bar slides across the ore once it has risen
	local _, sweepAt = RevealFx.sweep(ctx.Folder, shell.WorkCF, OreShellBuilder.CoreFront + 1.1, 1.5)
	-- light rays for Legendary and Mythic
	local rays = {}
	for i = 1, plan.Rays do
		local ray = Geo.block(
			ctx.Folder,
			CFrame.new(center),
			Vector3.new(0.12, 0.12, 6),
			rarity.Color,
			Enum.Material.Neon,
			props({ Transparency = 0.3 })
		)
		table.insert(rays, { part = ray, angle = i / plan.Rays * math.pi * 2 })
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		local p = math.clamp(elapsed / plan.Duration, 0, 1)
		local ease = 1 - (1 - RevealFx.warp(p, plan.SlowMo)) ^ 3
		sweepAt((elapsed - RevealFx.SweepDelay) / RevealFx.SweepTime)
		local lift = math.min(1, p * 2.2)
		lift = 1 - (1 - lift) ^ 2
		local cf = pivot * CFrame.new(RevealFx.Rise * lift) * CFrame.Angles(0, ease * plan.Spins * math.pi * 2, 0)
		for i, part in parts do
			if part.Parent then
				part.CFrame = cf * offsets[i]
			end
		end
		for _, r in rays do
			local a = r.angle + p * 1.5
			local dir = shell.WorkCF:VectorToWorldSpace(Vector3.new(math.cos(a), math.sin(a), RevealFx.RayTilt))
			r.part.CFrame = CFrame.lookAt(center + dir * 3.2, center + dir * 4)
			r.part.Transparency = 0.3 + 0.7 * p
		end
		if p >= 1 or ctx.ended() then
			connection:Disconnect()
		end
	end)
end

local function stars(level: number): string
	return string.rep("★", level) .. string.rep("☆", 4 - level)
end

local function detail(result: { [string]: any }): string
	local text = string.format("Time %.1fs  ·  Aim %d%%", result.Time or 0, math.floor((result.Aim or 0) * 100 + 0.5))
	if (result.Cracks or 0) > 0 then
		text ..= `  ·  Cracked {result.Cracks}`
	end
	return text
end

local function popCard(ctx: any)
	local view = ctx.View
	view.CleanBar.Visible = false -- the card sits where the bar was
	view.Card.Visible = true
	local pop = view.Card:FindFirstChild("Pop") :: UIScale
	pop.Scale = 0.2
	TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local state = ctx.LookState
	if state and not state.collectBound then
		state.collectBound = true
		table.insert(
			ctx.Connections,
			view.Collect.Activated:Connect(function()
				ctx.collect()
			end)
		)
	end
end

-- The server's grade is in: the card (and the grade stamp on the ore).
function DefaultLook.done(result: { [string]: any }, ctx: any)
	local view = ctx.View
	if ctx.Relic and result.Relic == ctx.Relic then
		local art = ArtifactConfig.ById[ctx.Relic]
		local rarity = Rarity.get(art.Rarity)
		view.CardGrade.Text = "RELIC CLEANED"
		view.CardGrade.TextColor3 = rarity.Color
		view.CardStars.Text = ""
		view.CardOre.Text = `{art.Name}  ({rarity.Name})`
		view.CardOre.TextColor3 = rarity.Color
		view.CardValue.Text = if result.Collected then "Added to your collection" else "Your relic is safe"
		view.CardDetail.Text = detail(result)
		popCard(ctx)
		ctx.flash(rarity.Color, 0.4)
		return
	end
	local grade = ItemData.GradeById[result.Grade] or ItemData.Grades[1]
	view.CardGrade.Text = string.upper(grade.Name)
	view.CardGrade.TextColor3 = grade.Color
	view.CardStars.Text = stars(grade.Level)
	view.CardOre.Text = `{ctx.Ore.Name}  ({ctx.Rarity.Name})`
	view.CardOre.TextColor3 = ctx.Rarity.Color
	-- what Tobin pays for it with the player's sell bonus (result.Value is the base price)
	local worth = math.floor((result.Value or 0) * StateController.sellMult() + 0.5)
	view.CardValue.Text = `Worth {Format.commas(worth)} coins`
	view.CardDetail.Text = detail(result)
	CleaningView.setStreak(view, ctx.Streak)
	-- the grade stamp lands on the ore itself
	local state = ctx.LookState
	local face = if state then state.shell.WorkCF else ctx.WorkCF
	local plate, stampPop = RevealFx.stamp(ctx.Folder, face, OreShellBuilder.CoreFront + 1.2, grade.Name, grade.Color)
	stampPop.Scale = RevealFx.StampFrom
	TweenService:Create(stampPop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.16, function()
		if plate.Parent then
			Sfx.play("Place", plate.Position, 1.25)
			Vfx.burst("Dust", plate.Position, 4, grade.Color)
		end
	end)
	popCard(ctx)
	if grade.Id == "Flawless" then
		ctx.flash(grade.Color, 0.6)
		Sfx.play("Discovery", nil, 1.3)
	end
end

-- The session ended without a result (Leave, death, a timeout): the spray stops at once.
function DefaultLook.cancel(ctx: any)
	Sfx.loop("Spray", false)
	local state = ctx.LookState
	if not state or not state.wand then
		return
	end
	state.finished = true
	SprayParts.placeWand(state.wand, nil)
	SprayParts.hideJet(state.jet)
	SprayParts.placeSpot(state.spot, ctx.WorkCF, nil)
	state.mist.Enabled = false
	state.drops.Enabled = false
end

return DefaultLook
