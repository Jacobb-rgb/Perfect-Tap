--[[
	SecretCleanFx: the build-up of a SECRET ore's jackpot at the Cleaning
	Station (owner 2026-10-29: the jackpot plays when the player cleans the
	sparkly dirty ore). CleaningController runs it next to the look when
	the vise holds a secret ore (the same callbacks, ctx last), and hands it
	the look's done so the card comes after the jackpot:
	  begin      the ding; the ore's moving parts come alive under the dirt
	             (SecretOreFx); light rays and the shake start to follow
	  cleaned    rainbow light leaks out of every fourth hole as it opens,
	             a few sparkles fly
	  progress   the rays grow and the clump shakes harder the cleaner it is
	  finished   the last bit: three heartbeats (a rainbow ring off the
	             clump each), a rising tone, the camera pushes in
	  done       BOOM: a shockwave ring, the camera kicks back, and the
	             jackpot screen (SecretRevealController.play); then the
	             look's own done (the Flawless card)
	  cancel     everything goes
	Reduce motion (Motion.reduced()): no shake, no push, rings and rays
	stand still. Perf: at most MaxRays thin parts, one RenderStepped.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SecretOreConfig = require(Shared.Config.SecretOreConfig)
local SecretOreFx = require(Shared.Builders.SecretOreFx)
local OreShellBuilder = require(Shared.Builders.OreShellBuilder)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Motion = require(script.Parent.Parent.UI.Motion)

local SecretCleanFx = {}

SecretCleanFx.MaxRays = 14
SecretCleanFx.Beats = { 0.12, 0.42, 0.68 } -- seconds after finished
SecretCleanFx.Push = 0.86 -- the field of view at the end of the hold (x the fit)

local RAINBOW = SecretOreConfig.Rainbow
local NEON = Enum.Material.Neon

type Ray = { Part: Part, From: Vector3, Dir: Vector3, At: number, Index: number }
type State = {
	Rays: { Ray },
	Rings: { { Parts: { Part }, At: number } },
	Progress: number,
	FinishedAt: number?,
	Rig: SecretOreFx.Rig?,
	Pivot: CFrame?,
	Shell: any,
	Parts: { BasePart },
	Movers: { [BasePart]: boolean }, -- the rig's parts (posed with the shake, not moved by it)
	Offset: Vector3, -- the shake now (moved by its change each frame, so the look's own moves stay)
	Boom: boolean,
	Start: number,
}

local function part(parent: Instance, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = NEON
	p.Color = color
	p.Size = Vector3.new(0.06, 0.06, 0.1)
	p.Parent = parent
	return p
end

-- A ring of 16 rainbow bars in the clump's face, to be grown by pose.
local function ring(ctx: any): { Part }
	local bars = {}
	for k = 1, 16 do
		table.insert(bars, part(ctx.Folder, RAINBOW[(k - 1) % #RAINBOW + 1]))
	end
	return bars
end

local function poseRing(ctx: any, bars: { Part }, radius: number, alpha: number)
	local face: CFrame = ctx.WorkCF
	local n = #bars
	local chord = 2 * radius * math.sin(math.pi / n)
	for k, bar in bars do
		local a = (k - 0.5) * math.pi * 2 / n
		local at = face:PointToWorldSpace(Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0.3))
		local tangent = face:VectorToWorldSpace(Vector3.new(-math.sin(a), math.cos(a), 0))
		bar.Size = Vector3.new(0.09, 0.09, chord * 0.9)
		bar.CFrame = CFrame.lookAt(at, at + tangent, face.LookVector)
		bar.Transparency = alpha
	end
end

local function stateOf(ctx: any): State?
	return ctx.SecretFx
end

function SecretCleanFx.applies(ctx: any): boolean
	return ctx.Relic == nil and SecretOreConfig.isSecret(ctx.OreId)
end

function SecretCleanFx.begin(ctx: any)
	local shell = if type(ctx.LookState) == "table" then ctx.LookState.shell else nil
	local state: State = {
		Rays = {},
		Rings = {},
		Progress = 0,
		FinishedAt = nil,
		Rig = nil,
		Pivot = nil,
		Shell = shell,
		Parts = {},
		Movers = {},
		Offset = Vector3.zero,
		Boom = false,
		Start = os.clock(),
	}
	ctx.SecretFx = state
	if shell and shell.Treasure then
		local center = shell.Treasure:GetAttribute("Center")
		if typeof(center) == "Vector3" then
			local pivot = CFrame.new(center)
			state.Pivot = pivot
			local rig = SecretOreFx.rig(shell.Treasure, pivot)
			state.Rig = rig
			for _, e in rig.Entries do
				state.Movers[e.Part] = true
			end
		end
	end
	if shell and shell.Model then
		for _, d in shell.Model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(state.Parts, d)
			end
		end
	end
	Sfx.play("SecretDing")
	local reduced = Motion.reduced()
	table.insert(
		ctx.Connections,
		RunService.RenderStepped:Connect(function()
			local t = os.clock() - state.Start
			local hold = if state.FinishedAt then math.clamp((os.clock() - state.FinishedAt) / 0.9, 0, 1) else 0
			-- the shake: harder the cleaner it is, hardest in the hold, none after the BOOM
			local offset = Vector3.zero
			if not reduced and not state.Boom and state.Progress > 0.05 then
				local amount = 0.012 + 0.045 * state.Progress + 0.06 * hold
				local face: CFrame = ctx.WorkCF
				offset = face:VectorToWorldSpace(Vector3.new(math.sin(t * 61), math.cos(t * 47), 0)) * amount
			end
			-- the ore lives under the dirt, shaking with it (until the look lifts it out at the finish:
			-- from then on its moving parts move with the rest by the shake's change)
			local posing = state.Rig ~= nil and state.Pivot ~= nil and not state.FinishedAt
			if posing and state.Rig and state.Pivot then
				SecretOreFx.pose(state.Rig, CFrame.new(offset) * state.Pivot, t, reduced)
			end
			local delta = offset - state.Offset
			if delta.Magnitude > 1e-5 then
				for _, p in state.Parts do
					if p.Parent and not (posing and state.Movers[p]) then
						p.CFrame += delta
					end
				end
			end
			state.Offset = offset
			-- the leaking light
			for k, ray in state.Rays do
				local grow = math.min((os.clock() - ray.At) / 0.25, 1)
				local length = (0.7 + 1.5 * state.Progress + 0.4 * hold) * grow
				local flick = if reduced then 0 else ((math.floor(t * 14) + k * 3) % 5) / 10
				ray.Part.Size = Vector3.new(0.06 + 0.03 * hold, 0.06 + 0.03 * hold, math.max(length, 0.05))
				ray.Part.CFrame = CFrame.lookAt(ray.From + ray.Dir * length / 2, ray.From + ray.Dir * length)
				ray.Part.Transparency = 0.15 + flick * (1 - hold)
			end
			-- the heartbeat rings
			for _, r in state.Rings do
				local u = (os.clock() - r.At) / 0.5
				if u >= 0 and u < 1 then
					poseRing(ctx, r.Parts, 1.6 + (if reduced then 1.6 else 3.2 * u), u)
				else
					for _, bar in r.Parts do
						bar.Transparency = 1
					end
				end
			end
			-- the camera pushes in while it holds
			if not reduced and state.FinishedAt and ctx.Camera and ctx.FitFov then
				ctx.Camera.FieldOfView = ctx.FitFov * (1 - (1 - SecretCleanFx.Push) * (1 - (1 - hold) ^ 2))
			end
		end)
	)
end

function SecretCleanFx.cleaned(cells: { number }, ctx: any)
	local state = stateOf(ctx)
	if not state then
		return
	end
	local pattern = ctx.Pattern
	for _, index in cells do
		local cell = pattern.Cells[index]
		if cell and index % 4 == 1 and #state.Rays < SecretCleanFx.MaxRays then
			local face: CFrame = ctx.WorkCF
			table.insert(state.Rays, {
				Part = part(ctx.Folder, RAINBOW[(#state.Rays % #RAINBOW) + 1]),
				From = ctx.worldAt(cell.Center.X, cell.Center.Y, OreShellBuilder.CoreFront),
				Dir = face:VectorToWorldSpace(Vector3.new(cell.Center.X, cell.Center.Y, 0.55).Unit),
				At = os.clock(),
				Index = index,
			})
			Sfx.play("SecretSparkle")
		end
	end
end

function SecretCleanFx.progress(fraction: number, ctx: any)
	local state = stateOf(ctx)
	if state then
		state.Progress = math.clamp(fraction, 0, 1)
	end
end

function SecretCleanFx.finished(ctx: any)
	local state = stateOf(ctx)
	if not state then
		return
	end
	state.FinishedAt = os.clock()
	Sfx.play("SecretRise")
	for _, at in SecretCleanFx.Beats do
		task.delay(at, function()
			if ctx.ended() then
				return
			end
			Sfx.play("SecretThump")
			table.insert(state.Rings, { Parts = ring(ctx), At = os.clock() })
		end)
	end
end

-- BOOM, the jackpot screen, then `after` (the look's own done: the card).
function SecretCleanFx.done(result: any, ctx: any, after: () -> ())
	local state = stateOf(ctx)
	local oreId = if type(result) == "table" and type(result.OreId) == "string" then result.OreId else ctx.OreId
	if state then
		state.Boom = true
		-- the shockwave in the clump's face; the leaking light goes out
		local bars = ring(ctx)
		table.insert(state.Rings, { Parts = bars, At = os.clock() })
		for _, ray in state.Rays do
			ray.Part.Transparency = 1
		end
		table.clear(state.Rays)
		if ctx.Camera and ctx.FitFov then
			ctx.Camera.FieldOfView = ctx.FitFov
		end
	end
	-- while the jackpot screen is up, Collect's keys pass to its skip (CleaningController)
	ctx.revealing = true
	local SecretRevealController = require(script.Parent.Parent.Controllers.SecretRevealController)
	SecretRevealController.play(oreId, function()
		ctx.revealing = false
		if not ctx.ended() then
			after()
		end
	end)
end

function SecretCleanFx.cancel(ctx: any)
	ctx.SecretFx = nil
	if ctx.Camera and ctx.FitFov then
		ctx.Camera.FieldOfView = ctx.FitFov
	end
end

return SecretCleanFx
