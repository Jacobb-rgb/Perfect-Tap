--[[
	Preview-only setup for the Foundry (WP-Foundry, step 3).
	  lune run tools/lune/export_scene.luau foundry          the buildings (overview shots)
	  lune run tools/lune/export_scene.luau foundry_moment   + the hammer moment and the reveal
	The world with plot 5's and plot 6's yard placeholders replaced by the
	real FoundryBuilder building (as FoundryService does at server start),
	the FOUNDRY chute receivers, and:
	  plot 5  a Clay Furnace whose output belt runs off the FOUNDRY chute into
	          the receiver (ingots riding it, one flying into the hood)
	Only in "foundry_moment" (the props exist only while forging, so the
	overview shots never show them):
	  plot 5  the hammer moment on the anvil: the glowing billet, the hammer up
	  plot 6  the reveal: the new blaster floating over the anvil with rays
	UI overlays (FoundryView, the HUD):
	  ui_foundry          the panel, ready to forge (PC)
	  ui_foundry_phone    the panel on a 667 x 375 pt phone (compact), coins missing
	  ui_forge            the hammer HUD mid-forge (PC)
	  ui_forge_phone      the hammer HUD on a phone (STRIKE bottom right)
	  ui_forge_reveal     the NEW BLASTER card
	Shots: tools/preview/foundry_shots.json (scene "foundry"). Camera points
	are printed (the close-ups use the buildings' CamPoint).
]]

local UiExport = require("./uiexport")

local FoundryPreview = {}

FoundryPreview.Plot = 5
FoundryPreview.RevealPlot = 6

local STOCK = {
	["Ingot|Gold|Clean|"] = 2,
	["Ingot|Gold|Rough|"] = 1,
	["Ingot|Silver|Pristine|"] = 2,
	["Ingot|Copper||"] = 3,
	["Ingot|Coal||"] = 4,
}

function FoundryPreview.build(Loader: any, workspace: any, moment: boolean?): { [string]: any }
	local roblox = Loader.roblox
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Format = Loader.requirePath("ReplicatedStorage.Shared.Util.Format")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
	local Grid = Loader.requirePath("ReplicatedStorage.Shared.Machines.Grid")
	local FoundryBuilder = Loader.requirePath("ServerScriptService.Server.World.FoundryBuilder")
	local HudView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudView")
	local FoundryView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.FoundryView")

	local folder = roblox.Instance.new("Folder")
	folder.Name = "FoundryPreview"
	folder.Parent = workspace
	local plots = workspace:FindFirstChild("Map"):FindFirstChild("Plots")

	-- the building in place of the placeholder (what FoundryService does)
	local function setup(plotId: number, rackLevel: number): (any, any)
		local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[plotId])
		local plot = plots:FindFirstChild("Plot_" .. plotId)
		local yard = plot:FindFirstChild("Yard")
		yard:FindFirstChild("Foundry"):Destroy()
		local building = FoundryBuilder.build(plotCF, rackLevel)
		building.Parent = yard
		FoundryBuilder.receiver(plotCF).Parent = plot
		return plotCF, building
	end
	local plotCF, building = setup(FoundryPreview.Plot, 3)
	local revealCF, revealBuilding = setup(FoundryPreview.RevealPlot, 4)

	-- a Clay Furnace feeding a belt that runs off the FOUNDRY chute
	local cx, cz = BaseLayout.chuteCell("Foundry")
	local furnaceX, furnaceZ = cx, cz - 6
	local furnace = MachineBuilder.build("ClayFurnace")
	furnace:PivotTo(plotCF * Grid.localCFrame("ClayFurnace", furnaceX, furnaceZ, 2))
	furnace.Parent = folder
	local ox, oz = Grid.outputCell("ClayFurnace", furnaceX, furnaceZ, 2)
	for z = oz, cz do
		local belt = MachineBuilder.build("Conveyor")
		belt:PivotTo(plotCF * Grid.localCFrame("Conveyor", ox, z, BaseLayout.SinkRotation))
		belt.Parent = folder
	end
	-- ingots riding the belt, and one flying into the hood's mouth
	local half = 24
	for i, ore in { "Gold", "Silver", "Copper" } do
		local z = -half + (oz + 0.5) * 4 + (i - 1) * 3.6 + 1.2
		local x = -half + (ox + 0.5) * 4
		local item =
			ItemBuilder.build({ Kind = "Ingot", OreId = ore, Grade = "Clean" }, plotCF * CF.new(x, 1.05, z) * CF.Angles(0, 0.2 * i, 0), i)
		item.Parent = folder
	end
	local mouth = BaseLayout.FoundryIntake.Mouth
	local flying = ItemBuilder.build(
		{ Kind = "Ingot", OreId = "Gold", Grade = "Pristine" },
		plotCF * CF.new(mouth.X, mouth.Y + 1.7, mouth.Z - 2.2) * CF.Angles(0.5, 0.4, 0.2),
		9
	)
	flying.Parent = folder

	local function attachmentWorld(model: any, name: string): any
		local base = model.PrimaryPart
		return base.CFrame * base:FindFirstChild(name).CFrame
	end
	local revealCam = attachmentWorld(revealBuilding, "CamPoint")
	if moment then
		-- the hammer moment on plot 5's anvil (FoundryController's billet and hammer)
		local props = { Anchored = true, CanCollide = false, CastShadow = false }
		local anvil = attachmentWorld(building, "AnvilPoint")
		local ore = OreData.ById.Gold
		local billet = Geo.block(
			folder,
			anvil * CF.new(0, 0.21, 0),
			V3.new(1.3, 0.42, 0.6),
			ore.Color:Lerp(C3.fromRGB(255, 140, 50), 0.45),
			roblox.Enum.Material.Neon,
			props
		)
		billet.Name = "Billet"
		local pivot = anvil * CF.new(1.75, 0.8, 0.1) * CF.Angles(0, 0, -1.0)
		Geo.block(folder, pivot * CF.new(-0.85, 0, 0), V3.new(1.7, 0.18, 0.18), C3.fromRGB(120, 80, 48), nil, props)
		Geo.block(folder, pivot * CF.new(-1.75, 0, 0), V3.new(0.5, 0.75, 0.45), C3.fromRGB(70, 72, 82), roblox.Enum.Material.Metal, props)
		for i = 1, 7 do
			local a = i * 0.9
			local p = anvil.Position + V3.new(math.cos(a) * (0.6 + i * 0.12), 0.4 + (i % 3) * 0.35, math.sin(a) * 0.5)
			Geo.ball(folder, p, 0.12, C3.fromRGB(255, 210, 120), roblox.Enum.Material.Neon, props)
		end

		-- the reveal on plot 6: a level 4 blaster in the Gold look over the anvil
		local revealAnvil = attachmentWorld(revealBuilding, "AnvilPoint")
		local center = revealAnvil.Position + V3.new(0, 1.6, 0)
		local tool = BlasterBuilder.build(4, "Gold")
		local facing = CF.lookAt(center, revealCam.Position)
		local at = CF.new(center) * facing.Rotation * CF.Angles(0, 0.5, 0) * CF.Angles(0, math.pi / 2, 0)
		local parts = {}
		local sum = V3.new(0, 0, 0)
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				sum += d.CFrame.Position
			end
		end
		local middle = sum / math.max(1, #parts)
		for _, d in parts do
			for _, child in d:GetChildren() do
				child:Destroy()
			end
			d.Anchored = true
			d.CFrame = at * CF.new(d.CFrame.Position - middle) * d.CFrame.Rotation
			d.Parent = folder
		end
		local rarity = Rarity.ById[ore.Rarity]
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2 + 0.3
			local dir = facing:VectorToWorldSpace(V3.new(math.cos(a), math.sin(a), -0.2))
			Geo.block(
				folder,
				CF.lookAt(center + dir * 2.9, center + dir * 4),
				V3.new(0.14, 0.14, 5),
				rarity.Color,
				roblox.Enum.Material.Neon,
				{
					Anchored = true,
					CanCollide = false,
					CastShadow = false,
					Transparency = 0.45,
				}
			)
		end
		local glow = Geo.ball(folder, center, 0.1, ore.Glow, nil, { Anchored = true, Transparency = 1 })
		local light = roblox.Instance.new("PointLight")
		light.Color = ore.Glow
		light.Range = 14
		light.Brightness = 2
		light.Parent = glow
	end

	-- camera points for the shots json
	local function show(name: string, cf: any)
		local look = cf.Position + cf.LookVector * 6
		print(
			string.format(
				"%s: position [%.2f, %.2f, %.2f] target [%.2f, %.2f, %.2f]",
				name,
				cf.Position.X,
				cf.Position.Y,
				cf.Position.Z,
				look.X,
				look.Y,
				look.Z
			)
		)
	end
	show("forge cam (plot 5)", attachmentWorld(building, "CamPoint"))
	show("reveal cam (plot 6)", revealCam)
	local function world(cf: any, x: number, y: number, z: number): string
		local p = cf * V3.new(x, y, z)
		return string.format("[%.1f, %.1f, %.1f]", p.X, p.Y, p.Z)
	end
	print("plot 5 foundry centre", world(plotCF, 13, 4, 46), "chute", world(plotCF, 13.6, 1.5, 24))
	local _ = revealCF

	---------------------------------------------------------------- UI

	local pcScale = 1.25 -- 900 px tall render / 720 design height
	local phoneScale = 0.62 * 900 / 375 -- a 667 x 375 pt phone at the 0.62 floor, scaled up to the render
	local function hud(scale: number): any
		local refs = HudView.build()
		refs.Gui.Scale.Scale = scale
		refs.Coins.Text = Format.money(3450)
		refs.Income.Text = Format.perSecond(42)
		refs.Income.TextColor3 = C3.fromRGB(110, 214, 92)
		return refs
	end
	local function panel(scale: number, compact: boolean, coins: number, level: number, look: string): any
		local state = { FoundryStock = STOCK, FoundryCount = 12, BlasterLevel = level, BlasterOre = look, Coins = coins }
		local refs = FoundryView.build()
		refs.Gui.Scale.Scale = scale
		refs.Gui.Enabled = true
		FoundryView.setCompact(refs, compact)
		FoundryView.setRows(refs, FoundryView.oreRows(state.FoundryStock, state.BlasterLevel), state.FoundryCount)
		FoundryView.setCard(refs, FoundryView.status(state, nil), state)
		FoundryView.setHint(
			refs,
			if compact
				then "FORGE makes your next blaster  -  TAKE moves an ingot to the Ore Pen"
				else "FORGE makes your next blaster  -  TAKE moves an ingot to the Ore Pen  -  Backspace: close",
			nil,
			nil
		)
		return refs
	end
	-- gameScale: the in-game UI scale (the top bar inset is 58 pt)
	local function forge(scale: number, gameScale: number, touch: boolean, done: number, feedback: string?): any
		local refs = FoundryView.buildForge(touch)
		refs.Gui.Scale.Scale = scale
		FoundryView.placeTop(refs, 58, gameScale)
		refs.Banner.Text = "FORGE: GOLD SPARK BLASTER"
		FoundryView.setPips(refs, 5, done)
		refs.Ring.Size = roblox.UDim2.fromScale(1.45, 1.45)
		refs.StrikeHint.Text = if touch then "Tap STRIKE (or the anvil)" else "Click or press Space  -  Backspace: leave"
		if feedback then
			refs.Feedback.Text = feedback
			refs.Feedback.TextColor3 = C3.fromRGB(255, 206, 72)
			refs.Feedback.TextTransparency = 0
		end
		return refs
	end

	local exports: { [string]: any } = {}
	local pcHud = hud(pcScale)
	-- PC: level 2 -> 3 (Common+), ready; phone: level 3 -> 4 needs Uncommon+, so
	-- Copper and Coal are too common (TAKE ALL) and one ingot is missing
	exports.ui_foundry = UiExport.export({ pcHud.Gui, panel(pcScale, false, 3450, 2, "Copper").Gui })
	local phoneHud = hud(phoneScale)
	exports.ui_foundry_phone = UiExport.export({ phoneHud.Gui, panel(phoneScale, true, 1200, 3, "Silver").Gui })
	exports.ui_forge = UiExport.export({ forge(pcScale, 1, false, 3, "PERFECT!").Gui })
	exports.ui_forge_phone = UiExport.export({ forge(phoneScale, 0.62, true, 2, "GOOD!").Gui })
	local reveal = forge(pcScale, 1, false, 5, nil)
	FoundryView.showCard(reveal, 4, "Gold", 3, "Copper")
	reveal.Banner.Text = "FORGE: GOLD EMBER BLASTER"
	exports.ui_forge_reveal = UiExport.export({ reveal.Gui })
	return exports
end

return FoundryPreview
