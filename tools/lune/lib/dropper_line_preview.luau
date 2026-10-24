--[[
	Scene "dropper_line": real ore on the belts (owner 2026-10-24), built
	from the game's own builders on a plot-like floor: two lines, each a
	dropper (MachineBuilder) pushing Drops (ItemBuilder.buildLight, kind
	"Drop") onto conveyors, the upper line through the little Money Laser
	gate, both into a Sell Box. Grid cells of GameConfig.CellSize, the
	machines' fronts toward +X.
]]

local Preview = {}

function Preview.build(Loader: any, workspace: any)
	local roblox = Loader.roblox
	local V3 = roblox.Vector3
	local CF = Loader.CFrame
	local C3 = roblox.Color3
	local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local DropperConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.DropperConfig")
	local cell = GameConfig.CellSize
	local face = CF.Angles(0, -math.pi / 2, 0) -- the machines' front (-Z) toward +X

	local stage = roblox.Instance.new("Model")
	stage.Name = "DropperLine"
	stage.Parent = workspace
	-- the plot floor: light metal tiles with seams
	Geo.block(stage, CF.new(16, -0.5, 0), V3.new(80, 1, 60), C3.fromRGB(188, 192, 204))
	for i = -10, 10 do
		Geo.block(stage, CF.new(16 + i * cell, 0.01, 0), V3.new(0.08, 0.02, 60), C3.fromRGB(150, 154, 170))
		Geo.block(stage, CF.new(16, 0.01, i * cell), V3.new(80, 0.02, 0.08), C3.fromRGB(150, 154, 170))
	end

	-- a machine of `size` cells whose min cell is (gx, gz), front toward +X
	local function place(id: string, gx: number, gz: number, w: number)
		local model = MachineBuilder.build(id)
		model:PivotTo(CF.new((gx + w / 2) * cell, 0, (gz + w / 2) * cell) * face)
		model.Parent = stage
	end
	local function line(dropperId: string, gz: number, laser: boolean, drops: number)
		-- the dropper's Output is in its second row: the belt line runs in that row
		place(dropperId, 0, gz, 2)
		local row = gz + 1
		local x = 2
		local cells = { "Conveyor", "Conveyor", if laser then DropperConfig.Laser.Id else "Conveyor", "Conveyor", "Conveyor" }
		for _, id in cells do
			place(id, x, row, 1)
			x += 1
		end
		place("SellBox", x, row - 1, 2)
		-- Drops riding the belts (the lasered ones after the gate)
		for k = 1, drops do
			local bx = (2 + (k - 1) * 1.2 + 0.5) * cell
			local marked = laser and bx > (4 + 1) * cell
			local item = ItemBuilder.buildLight({
				Kind = "Drop",
				OreId = dropperId,
				Recipe = if marked then DropperConfig.LaserMark else nil,
			}, CF.new(bx, 1.4, (row + 0.5) * cell) * CF.Angles(0, k, 0), k)
			item.Parent = stage
		end
	end
	line("GoldDropper", -3, true, 4)
	line("RedDropper", 2, false, 3)
end

return Preview
