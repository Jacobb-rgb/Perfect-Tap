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

Showcase.Column = 3.1 -- studs between two ores on a step
Showcase.Depth = 3.9 -- studs per step
Showcase.Rise = 2.5 -- studs each step is higher than the one in front
Showcase.Pedestal = Vector3.new(2.4, 0.7, 2.2) -- the dark box under each ore (its name plate on the front)

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
	local STEP = C3.fromRGB(36, 38, 54)
	local BOX = C3.fromRGB(46, 48, 66)
	local PLATE = C3.fromRGB(18, 18, 28)
	local TEXT = C3.fromRGB(246, 244, 255)

	-- a dark name plate with a thin glowing frame in the rarity colour (the owner's picture)
	local function label(cf: any, width: number, height: number, text: string, frame: any, textColor: any)
		Geo.block(root, cf * CF.new(0, 0, -0.03), V3.new(width + 0.1, height + 0.1, 0.05), frame, NEON)
		local board = Geo.block(root, cf, V3.new(width, height, 0.08), PLATE)
		local gui = roblox.Instance.new("SurfaceGui")
		gui.Face = roblox.Enum.NormalId.Back
		gui.Parent = board
		local textLabel = roblox.Instance.new("TextLabel")
		textLabel.Text = text
		textLabel.TextColor3 = textColor
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
	local width = most * Showcase.Column + 6.5
	-- the room: black floor and back wall
	Geo.block(root, CF.new(0, -0.5, -10), V3.new(200, 1, 160), C3.fromRGB(12, 12, 18))
	local rows = #Rarity.List
	local backZ = -(rows - 1) * Showcase.Depth - Showcase.Depth / 2 - 0.5
	Geo.block(root, CF.new(0, 20, backZ - 0.5), V3.new(200, 42, 1), C3.fromRGB(10, 10, 14))

	local ped = Showcase.Pedestal
	local count = 0
	for r = 1, rows do
		local ores = byRarity[r]
		if not ores then
			continue
		end
		local rarity = Rarity.get(ores[1].Rarity)
		-- white neon blooms into a blob: Common glows a soft grey
		local glow = if rarity.Order == 1 then C3.fromRGB(150, 152, 166) else rarity.Color
		local z = -(r - 1) * Showcase.Depth
		local top = 0.5 + (r - 1) * Showcase.Rise
		local front = z + Showcase.Depth / 2
		-- the step (down to the floor) with a glowing line along its front edge
		Geo.block(root, CF.new(0, top / 2, z), V3.new(width, top, Showcase.Depth), STEP)
		Geo.block(root, CF.new(0, top - 0.04, front - 0.04), V3.new(width - 0.3, 0.08, 0.08), glow, NEON)
		-- the rarity sign at the left end of the step
		local signX = -width / 2 + 2.1
		Geo.block(root, CF.new(signX, top + 0.3, front - 1.0), V3.new(3.0, 0.6, 0.9), BOX)
		label(CF.new(signX, top + 0.32, front - 0.52), 2.8, 0.52, string.upper(rarity.Name), glow, rarity.Color)
		for i, ore in ores do
			local x = (i - (#ores + 1) / 2) * Showcase.Column + 1.3
			local pz = front - ped.Z / 2 - 0.25
			Geo.block(root, CF.new(x, top + ped.Y / 2, pz), ped, BOX)
			local item = ItemBuilder.display({ K = "Clean", O = ore.Id }, CF.new(x, top + ped.Y, pz) * CF.Angles(0, 0.3, 0), ore.Id)
			item.Parent = root
			label(CF.new(x, top + ped.Y * 0.5, pz + ped.Z / 2 + 0.05), ped.X - 0.1, 0.46, ore.Name, glow, TEXT)
			count += 1
		end
	end
	print(string.format("Ore showcase: %d ores on %d steps", count, rows))
	return root
end

return Showcase
