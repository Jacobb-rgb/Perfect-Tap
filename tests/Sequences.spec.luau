--[[
	Roblox rules for ColorSequence and NumberSequence (Lune doesn't check
	them; Roblox throws, and a builder that throws leaves a model missing):
	at most 20 keypoints, the first at time 0, the last at exactly 1, times
	never going back. This walks every model the builders make (machines in
	both styles at every level, plots, the Foundry, items, artifacts, golems,
	rocks, blasters, hoverboard effects) and the whole baked place, and
	checks every gradient, particle emitter, beam and trail. A literal
	Sequence.new({ ... }) in the source is checked as well.
]]

return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local CFrame = roblox.CFrame
	local Vector3 = roblox.Vector3
	local Instance = roblox.Instance

	local MAX = 20

	local SEQUENCE_PROPS: { [string]: { string } } = {
		UIGradient = { "Color", "Transparency" },
		ParticleEmitter = { "Color", "Size", "Transparency" },
		Beam = { "Color", "Transparency" },
		Trail = { "Color", "Transparency", "WidthScale" },
	}

	-- Problems of one sequence value ("" = fine).
	local function problem(value: any): string
		local ok, keypoints = pcall(function()
			return value.Keypoints
		end)
		if not ok or type(keypoints) ~= "table" then
			return ""
		end
		local n = #keypoints
		if n > MAX then
			return `{n} keypoints (at most {MAX})`
		end
		if n < 2 then
			return `{n} keypoints`
		end
		if keypoints[1].Time ~= 0 then
			return `starts at {keypoints[1].Time}`
		end
		if keypoints[n].Time ~= 1 then
			return `ends at {keypoints[n].Time}`
		end
		for i = 2, n do
			if keypoints[i].Time < keypoints[i - 1].Time then
				return `goes back at keypoint {i}`
			end
		end
		return ""
	end

	-- Every bad sequence under `root` as "path.Prop: problem" (at most `limit`).
	local function scan(root: any, limit: number?): ({ string }, number)
		local bad = {}
		local checked = 0
		local function check(inst: any)
			local props = SEQUENCE_PROPS[inst.ClassName]
			if not props then
				return
			end
			for _, prop in props do
				local okRead, value = pcall(function()
					return inst[prop]
				end)
				if okRead and value ~= nil and type(value) ~= "number" then
					checked += 1
					local why = problem(value)
					if why ~= "" and #bad < (limit or 25) then
						table.insert(bad, `{inst:GetFullName()}.{prop}: {why}`)
					end
				end
			end
		end
		check(root)
		for _, d in root:GetDescendants() do
			check(d)
		end
		return bad, checked
	end

	local function expectClean(label: string, root: any): number
		local bad, checked = scan(root)
		T.eq(#bad, 0, label .. ": " .. table.concat(bad, "; "))
		return checked
	end

	T.test("Sequences: every machine in both styles, at every level", function()
		local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
		local KitMachines = Loader.requirePath("ReplicatedStorage.Shared.Builders.KitMachines")
		local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
		local checked = 0
		for _, machine in MachineData.List do
			for level = 0, KitMachines.MaxLevel do
				local okKit, kit = pcall(KitMachines.buildAny, machine.Id, level)
				if okKit and kit then
					checked += expectClean(`Kit {machine.Id} L{level}`, kit)
					kit:Destroy()
				end
			end
			local okOld, old = pcall(MachineBuilder.build, machine.Id, 1)
			if okOld and old then
				checked += expectClean(`MachineBuilder {machine.Id}`, old)
				old:Destroy()
			end
		end
		for _, id in { "Conveyor", "ExpressConveyor", "BeltLift", "Slide" } do
			local ok, model = pcall(KitMachines.buildAny, id)
			if ok and model then
				checked += expectClean("Kit " .. id, model)
			end
		end
		T.lt(20, checked, "the machines carry gradients (the stripes)")
	end)

	T.test("Sequences: plots, the Foundry and its receiver", function()
		local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
		local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
		local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
		local FoundryBuilder = Loader.requirePath("ServerScriptService.Server.World.FoundryBuilder")
		local folder = Instance.new("Folder")
		local plot = WorldLayout.Plots[1]
		PlotBuilder.buildPlot(folder, plot, Rng.new(1))
		expectClean("plot", folder)
		local cf = WorldLayout.plotCFrame(plot)
		for level = 2, 10 do
			expectClean("Foundry L" .. level, FoundryBuilder.build(cf, level))
		end
		expectClean("Foundry receiver", FoundryBuilder.receiver(cf))
	end)

	T.test("Sequences: items, artifacts, golems, rocks, blasters, hoverboard effects", function()
		local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
		local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
		local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
		local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
		local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
		local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
		local ArtifactBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ArtifactBuilder")
		local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
		local OreNodeBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.OreNodeBuilder")
		local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
		local HoverboardFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardFx")
		local at = CFrame.new(0, 5, 0)
		for _, ore in OreData.List do
			for kind in ItemData.Kinds do
				if kind ~= "Relic" then
					local info = { Kind = kind, OreId = ore.Id, Grade = "Flawless", Recipe = if kind == "Gear" then "Dagger" else nil }
					local ok, model = pcall(ItemBuilder.build, info, at, 1)
					if ok and model then
						expectClean(`item {kind} {ore.Id}`, model)
					end
				end
			end
			expectClean("rock " .. ore.Id, OreNodeBuilder.build(ore.Id, at, 3))
		end
		for _, art in ArtifactConfig.List do
			local model = ArtifactBuilder.build(art.Id, at, 1)
			if model then
				expectClean("artifact " .. art.Id, model)
			end
		end
		for _, golem in GolemConfig.List do
			expectClean("golem " .. golem.Id, GolemBuilder.build(golem.Id, at))
		end
		for level = 1, 10 do
			local ok, tool = pcall(BlasterBuilder.build, level, OreData.List[#OreData.List].Id)
			if ok and tool then
				expectClean("blaster " .. level, tool)
			end
		end
		for _, board in HoverboardData.List do
			for _, lite in { false, true } do
				local set = HoverboardFx.create(board.Id, lite)
				if set then
					for _, e in set.Emitters do
						expectClean("hoverboard fx " .. board.Id, e)
					end
					for _, trail in set.Trails do
						expectClean("hoverboard trail " .. board.Id, trail)
					end
				end
			end
		end
		T.truthy(Vector3, "loaded")
	end)

	T.test("Sequences: the whole baked place", function()
		local path = "build/TerraForge.rbxl"
		if not fs.isFile(path) then
			return -- a fresh checkout before the first bake: the builders above still ran
		end
		local place = roblox.deserializePlace(fs.readFile(path))
		local bad, checked = scan(place, 40)
		T.eq(#bad, 0, "baked place: " .. table.concat(bad, "; "))
		T.lt(0, checked, "the place has gradients and emitters")
	end)

	T.test("Sequences: literal Sequence.new({ ... }) blocks in the source start at 0 and end at 1", function()
		local bad = {}
		local function walk(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					walk(path)
				elseif name:match("%.luau$") then
					local source = fs.readFile(path)
					for block in source:gmatch("Sequence%.new%(%s*(%b{})") do
						local times = {}
						for t in block:gmatch("SequenceKeypoint%.new%(%s*([%d%.]+)%s*,") do
							table.insert(times, tonumber(t))
						end
						if #times >= 1 then
							local why = if #times > MAX
								then `{#times} keypoints`
								elseif times[1] ~= 0 then `starts at {times[1]}`
								elseif times[#times] ~= 1 then `ends at {times[#times]}`
								else nil
							if why then
								table.insert(bad, `{path}: {why}`)
							end
						end
					end
				end
			end
		end
		walk("src")
		T.eq(#bad, 0, table.concat(bad, "; "))
	end)
end
