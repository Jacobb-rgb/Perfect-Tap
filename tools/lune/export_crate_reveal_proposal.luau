--[[
	PROPOSAL picture only (owner 2026-10-29: "a much better egg opening ...
	atd."): the Vault's blaster case in hatch v2's reveal look (Effects/
	RevealFx: the rarity rays and glow behind the blaster, the name / rarity
	banner, a headline for the rare ones), the case's stage and BACKGROUND
	unchanged (the owner kept the old one on 2026-10-28). Nothing in the
	game changes; this renders the case's end moment as it is and as it
	would be.
	  lune run tools/lune/export_crate_reveal_proposal.luau [level=7]
	  SHOTS_EXTRA=build/preview/crate_proposal_shots.json node tools/preview/render.mjs crate_proposal_now crate_proposal_now crate_proposal_new
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")
local Loader = require("./lib/loader")
local Export = require("./lib/export")
local UiExport = require("./lib/uiexport")
local root = process.cwd
Loader.init(root)
local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local Stage = Loader.requirePath("ReplicatedStorage.Shared.Builders.CrateOpeningStage")
local CrateOpeningView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CrateOpeningView")
local RevealFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.RevealFx")
local CF = Loader.CFrame
local V3 = roblox.Vector3
local Instance = roblox.Instance
local Enum = roblox.Enum
local UDim2 = roblox.UDim2

local level = tonumber(process.args[1]) or 7
local ore = BlasterData.vaultOre(level)
local rarity = (OreData.ById[ore] and OreData.ById[ore].Rarity) or "Rare"

local function presetsJson()
	local out = {}
	for name, preset in LightingConfig.Presets do
		local p = {}
		for group, values in preset do
			p[group] = {}
			for key, value in values do
				p[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
			end
		end
		out[name] = p
	end
	return out
end

local shots = {}
for _, variant in { "now", "new" } do
	local game = Instance.new("DataModel")
	local workspace = game:GetService("Workspace")
	local blaster = Stage.blasterModel(level, ore)
	local stage = Stage.build(workspace, CF.new(0, 3000, 0), level, ore, blaster)
	local t = stage.Reveal + 1.2
	stage.update(t)
	local cam, fov = stage.camera(t)
	local view = CrateOpeningView.build()
	view.Gui.Scale.Scale = 1.25
	CrateOpeningView.setBlaster(view, level, ore)
	CrateOpeningView.update(view, t, stage.Burst, stage.Reveal)
	local guis = { view.Gui }
	if variant == "new" then
		-- the reveal look: rays and a glow BEHIND the blaster (3D here: the renderer draws UI over 3D)
		-- (the blaster's middle: its parts' average, where the stage posed them)
		local sum, count = V3.new(0, 0, 0), 0
		for _, d in blaster:GetDescendants() do
			if d:IsA("BasePart") then
				sum += d.CFrame.Position
				count += 1
			end
		end
		local at = if count > 0 then sum / count else blaster:GetPivot().Position

		local back = (at - cam.Position).Unit
		local frame = CF.lookAt(at + back * 1.2, cam.Position)
		local tier = RevealFx.Tiers[RevealFx.tierOf(rarity)]
		local radius = 3.8
		local glow = Instance.new("Part")
		glow.Anchored = true
		glow.Shape = Enum.PartType.Cylinder
		glow.Material = Enum.Material.SmoothPlastic
		glow.Color = RevealFx.palette(rarity).Glow
		glow.Transparency = 0.45
		glow.Size = V3.new(0.05, radius * 1.15, radius * 1.15)
		glow.CFrame = frame * CF.Angles(0, math.pi / 2, 0)
		glow.Parent = workspace
		for layer = 1, (if tier.Back ~= 0 then 2 else 1) do
			local bars = math.floor(tier.Rays / 2)
			for i = 1, bars do
				local angle = (i - 1) * math.pi / bars + (layer - 1) * math.pi / (2 * bars) + 0.3
				-- (the renderer draws see-through parts very faintly in this dark stage: nearly solid here)
				for _, seg in { { 0.12, 0.5, 0 }, { 0.5, 0.82, 0.1 }, { 0.82, 1, 0.3 } } do
					for _, side in { 1, -1 } do
						local from, to = seg[1] * radius, seg[2] * radius
						local bar = Instance.new("Part")
						bar.Anchored = true
						bar.Material = Enum.Material.SmoothPlastic
						bar.Color = RevealFx.rayColor(rarity, i + (layer - 1), bars, 0.4)
						bar.Transparency = seg[3] + (if layer == 2 then 0.12 else 0)
						bar.Size = V3.new(to - from, radius * (if layer == 1 then 0.17 else 0.1), 0.04)
						bar.CFrame = frame * CF.new(0, 0, 0.05 * layer) * CF.Angles(0, 0, angle) * CF.new(side * (from + to) / 2, 0, 0)
						bar.Parent = workspace
					end
				end
			end
		end
		-- the banner (name, rarity, the level's stats) and the headline, as the eggs show theirs
		for _, name in { "Title", "RarityPill", "RarityText", "Name" } do
			local object = (view :: any)[name]
			if object then
				object.Visible = false
			end
		end
		local tierName = RevealFx.tierOf(rarity)
		local handle = RevealFx.show("Blaster", tostring(level), rarity, {
			Parent = view.Gui,
			Center = UDim2.fromScale(0.5, 0.45),
			Size = 560,
			Name = string.upper(BlasterData.displayName(level, ore)),
			Headline = if tierName == "Jackpot" then nil else "NEW BLASTER!", -- (a jackpot blaster: "LEGENDARY!" / "MYTHIC!")
			Manual = true,
			Flash = false,
			Sound = false,
			Shake = false,
			Reduced = false,
			Phone = false,
		})
		handle:pose(1.2)
		for _, layer in handle.Layers do
			layer.Visible = false
		end
		handle.Glow.Visible = false
	end
	local scene = Export.collect(workspace)
	scene.presets = presetsJson()
	local name = `crate_proposal_{level}_{variant}`
	fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", scene))
	fs.writeFile(root .. "/build/preview/ui_" .. name .. ".json", serde.encode("json", UiExport.export(guis)))
	local p, look = cam.Position, cam.Position + cam.LookVector * 20
	shots[name] = {
		scene = name,
		position = { p.X, p.Y, p.Z },
		target = { look.X, look.Y, look.Z },
		fov = fov,
		preset = "CrateOpening",
		maxLights = 4,
		ui = "ui_" .. name,
	}
	print(`{name}: level {level}, {ore} ({rarity}), t {t}`)
end
fs.writeFile(root .. "/build/preview/crate_proposal_shots.json", serde.encode("json", shots, true))
