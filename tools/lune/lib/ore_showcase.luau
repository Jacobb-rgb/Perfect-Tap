--[[
	Every ore in one picture (scene "ore_showcase", shot in
	tools/preview/ore_shots.json): a tiered shelf, one step per rarity
	(Common in front and lowest, Mythic at the back and highest), each ore
	in its podium look (ItemBuilder.display) on a small plinth with its name
	in front, the rarity name at the left end of the step and a glowing
	strip in the rarity colour along every step's edge.
]]

local roblox = require("@lune/roblox") :: any

local Showcase = {}

Showcase.Column = 4.2 -- studs between two ores on a step
Showcase.Depth = 4.6 -- studs per step
Showcase.Rise = 1.9 -- studs each step is higher than the one in front

function Showcase.build(Loader: any, parent: any)
	local CF = Loader.CFrame
	local V3 = roblox.Vector3
	local C3 = roblox.Color3
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local NEON = roblox.Enum.Material.Neon
	local root = roblox.Instance.new("Model")
	root.Name = "OreShowcase"
	root.Parent = parent

	local function label(cf: any, width: number, height: number, text: string, color: any)
		local board = Geo.block(root, cf, V3.new(width, height, 0.08), C3.fromRGB(34, 28, 40))
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Back
		gui.Parent = board
		local textLabel = roblox.Instance.new("TextLabel")
		textLabel.Text = text
		textLabel.TextColor3 = color
		textLabel.FontFace = roblox.Font.fromEnum(roblox.Enum.Font.FredokaOne)
		textLabel.Parent = gui
		return board
	end

	local byRarity: { [number]: { any } } = {}
	local most = 0
	for _, ore in OreData.List do
		local order = Rarity.get(ore.Rarity).Order
		byRarity[order] = byRarity[order] or {}
		table.insert(byRarity[order], ore)
		most = math.max(most, #byRarity[order])
	end
	local width = most * Showcase.Column + 7
	-- the room: a dark floor and a back wall
	Geo.block(root, CF.new(0, -0.5, -10), V3.new(200, 1, 160), C3.fromRGB(40, 38, 52))
	local rows = #Rarity.List
	local backZ = -(rows - 1) * Showcase.Depth - Showcase.Depth / 2 - 0.5
	Geo.block(root, CF.new(0, 20, backZ - 0.5), V3.new(200, 42, 1), C3.fromRGB(32, 30, 44))

	local count = 0
	for r = 1, rows do
		local ores = byRarity[r]
		if not ores then
			continue
		end
		local rarity = Rarity.get(ores[1].Rarity)
		local z = -(r - 1) * Showcase.Depth
		local top = 0.4 + (r - 1) * Showcase.Rise
		-- the step (down to the floor) and its glowing front edge
		Geo.block(root, CF.new(0, top / 2, z), V3.new(width, top, Showcase.Depth), C3.fromRGB(96, 92, 116))
		Geo.block(root, CF.new(0, top - 0.06, z + Showcase.Depth / 2 - 0.08), V3.new(width - 0.4, 0.12, 0.12), rarity.Color, NEON)
		label(
			CF.new(-width / 2 + 2.3, top + 0.32, z + Showcase.Depth / 2 - 0.9) * CF.Angles(-1.0, 0, 0),
			3.6,
			0.7,
			string.upper(rarity.Name),
			rarity.Color
		)
		for i, ore in ores do
			local x = (i - (#ores + 1) / 2) * Showcase.Column + 1.2
			local plinthTop = top + 0.45
			Geo.block(root, CF.new(x, top + 0.225, z - 0.5), V3.new(3.0, 0.45, 3.0), C3.fromRGB(176, 172, 188))
			local item = ItemBuilder.display({ K = "Clean", O = ore.Id }, CF.new(x, plinthTop, z - 0.5) * CF.Angles(0, 0.45, 0), ore.Id)
			item.Parent = root
			label(CF.new(x, top + 0.3, z + 1.45) * CF.Angles(-1.0, 0, 0), 3.8, 0.6, ore.Name, rarity.Color)
			count += 1
		end
	end
	print(string.format("Ore showcase: %d ores on %d steps", count, rows))
	return root
end

return Showcase
