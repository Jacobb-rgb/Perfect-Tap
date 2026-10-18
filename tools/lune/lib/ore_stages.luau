--[[
	Every ore through the stages of the loop (scenes "ore_stages_1/2/3",
	shots in tools/preview/ore_shots.json): one row per ore, one column per
	stage, the ores split into three sheets by rarity (Common + Uncommon,
	Rare + Epic, Legendary + Mythic).
	Columns: Dirty (the raw chunk: the same crust for every ore by design,
	only a glint hints at it) · Clean (the physical item on a belt, Rough) ·
	Flawless (the same with the grade sparkle; Polisher output looks the same)
	· Podium (the display copy, Pristine; the Iron Box shows this one too) ·
	Crushed · Ingot (every furnace tier makes the same ingot) · Alloy.
	Particle emitters stay only where they are the point (Flawless, Podium).
]]

local roblox = require("@lune/roblox") :: any

local Stages = {}

Stages.Columns = { "Dirty", "Clean", "Flawless", "Podium", "Crushed", "Ingot", "Alloy" }
Stages.Groups = { { 1, 2 }, { 3, 4 }, { 5, 6 } } -- rarity orders per sheet
Stages.Col = 3.1 -- studs between columns
Stages.Row = 2.7 -- studs between rows

local function noEmitters(model: any)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
end

-- Lays a built model on a surface at height `top`.
local function settle(model: any, top: number, V3: any)
	local lowest = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
			local h = d.Size / 2
			lowest = math.min(lowest, d.CFrame.Position.Y - (math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z))
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + V3.new(0, top - lowest, 0)
		end
	end
end

function Stages.build(Loader: any, parent: any, sheet: number)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local root = roblox.Instance.new("Model")
	root.Name = "OreStages"
	root.Parent = parent

	local function label(cf: any, width: number, height: number, text: string, color: any)
		local board = Geo.block(root, cf, V3.new(width, height, 0.08), C3.fromRGB(26, 24, 34))
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Back
		gui.Parent = board
		local textLabel = roblox.Instance.new("TextLabel")
		textLabel.Text = text
		textLabel.TextColor3 = color
		textLabel.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
		textLabel.Parent = gui
	end

	local orders = Stages.Groups[sheet]
	local ores = {}
	for _, ore in OreData.List do
		local order = Rarity.get(ore.Rarity).Order
		if order == orders[1] or order == orders[2] then
			table.insert(ores, ore)
		end
	end
	local width = #Stages.Columns * Stages.Col + 8
	local depth = #ores * Stages.Row + 6
	local n = #ores
	Geo.block(root, CF.new(width / 2 - 6, -0.5, -depth / 2 + 3), V3.new(width + 60, 1, depth + 60), C3.fromRGB(150, 150, 164))
	-- column headers above the first row (the far end: the top of the picture)
	for c, name in Stages.Columns do
		local x = (c - 1) * Stages.Col
		label(CF.new(x, 0.35, -(n - 1) * Stages.Row - 1.9) * CF.Angles(-1.1, 0, 0), 2.9, 0.6, string.upper(name), C3.fromRGB(255, 214, 120))
	end
	for r, ore in ores do
		-- the first ore at the far end (top of the picture), the last nearest
		local z = -(n - r) * Stages.Row
		local rarity = Rarity.get(ore.Rarity)
		-- a light tile per row, the name at its left end
		Geo.block(root, CF.new(width / 2 - 6, 0.05, z), V3.new(width + 1, 0.1, Stages.Row - 0.25), C3.fromRGB(92, 92, 108))
		label(CF.new(-4.4, 0.35, z + 0.5) * CF.Angles(-1.1, 0, 0), 3.8, 0.62, ore.Name, rarity.Color)
		for c, stage in Stages.Columns do
			local x = (c - 1) * Stages.Col
			local cf = CF.new(x, 0, z) * CF.Angles(0, 0.5, 0)
			local model
			if stage == "Dirty" then
				model = ItemBuilder.build({ Kind = "Raw", OreId = ore.Id }, cf, r)
			elseif stage == "Clean" then
				model = ItemBuilder.build({ Kind = "Clean", OreId = ore.Id, Grade = "Rough" }, cf, r)
			elseif stage == "Flawless" then
				model = ItemBuilder.build({ Kind = "Clean", OreId = ore.Id, Grade = "Flawless" }, cf, r)
			elseif stage == "Podium" then
				model = ItemBuilder.display({ K = "Clean", O = ore.Id, G = "Pristine" }, CF.new(x, 0.1, z) * CF.Angles(0, 0.5, 0), r)
			elseif stage == "Crushed" then
				model = ItemBuilder.build({ Kind = "Crushed", OreId = ore.Id, Grade = "Clean" }, cf, r)
			elseif stage == "Ingot" then
				model = ItemBuilder.build({ Kind = "Ingot", OreId = ore.Id, Grade = "Clean" }, cf, r)
			else
				model = ItemBuilder.build({ Kind = "Alloy", OreId = ore.Id, Grade = "Clean" }, cf, r)
			end
			if stage ~= "Podium" then
				settle(model, 0.1, V3)
			end
			if stage ~= "Flawless" and stage ~= "Podium" then
				noEmitters(model)
			end
			model.Parent = root
		end
	end
	print(string.format("Ore stages sheet %d: %d ores x %d stages", sheet, #ores, #Stages.Columns))
	return root
end

return Stages
