-- The Foundry (step 3, WP-Foundry): FoundryLogic (usable ingots, the pick,
-- the default look), FoundryBuilder (the building in its rect and part
-- budget, the rack silhouettes, the chute receiver in its zone),
-- FoundryService (placeholder replaced, chute sink, hopper, Put In, Take,
-- the whole forge flow with every refusal, timeouts, conservation) and the
-- pure parts of FoundryView. The plot is built by the real PlotBuilder;
-- players, saves, carrying and Net are small fakes.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
	local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local FoundryLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.FoundryLogic")
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local MachineLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineLogic")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local FoundryBuilder = Loader.requirePath("ServerScriptService.Server.World.FoundryBuilder")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local CarryService = Loader.requirePath("ServerScriptService.Server.Services.CarryService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
	local IntakeService = Loader.requirePath("ServerScriptService.Server.Services.IntakeService")
	local FoundryService = Loader.requirePath("ServerScriptService.Server.Services.FoundryService")
	local FoundryView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.FoundryView")
	local Players = Loader.game:GetService("Players")
	local HttpService = Loader.game:GetService("HttpService")

	local PLOT = 3
	local USER, OTHER = 701, 702
	local fs = FoundryService._test

	local function ingot(ore: string, grade: string?): any
		return { K = "Ingot", O = ore, G = grade }
	end

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	---------------------------------------------------------------- FoundryLogic

	T.test("FoundryLogic: recipe, usable ingots and taps per level", function()
		T.eq(FoundryLogic.recipe(1), BlasterData.ByLevel[2].Recipe, "level 1 makes level 2")
		T.eq(FoundryLogic.recipe(BlasterData.MaxLevel), nil, "no recipe at the top")
		T.eq(FoundryLogic.recipe("junk"), BlasterData.ByLevel[2].Recipe, "junk level counts as 1")
		T.eq(FoundryLogic.nextBlaster(BlasterData.MaxLevel).ComingSoon, true, "level 11 is coming soon")
		T.truthy(FoundryLogic.usable(ingot("Coal"), 1), "Common for level 2")
		T.falsy(FoundryLogic.usable(ingot("Coal"), 3), "level 4 needs Uncommon+")
		T.truthy(FoundryLogic.usable(ingot("Silver", "Pristine"), 3), "Uncommon for level 4")
		T.truthy(FoundryLogic.usable(ingot("Heartstone"), 9), "Mythic for level 10")
		T.falsy(FoundryLogic.usable(ingot("Gold"), BlasterData.MaxLevel), "nothing at the top")
		for _, junk in
			{
				{ K = "Clean", O = "Gold" },
				{ K = "Ingot", O = "Nope" },
				{ K = "Ingot", O = "Gold", G = "Shiny" },
				{ K = "Ingot", O = "Gold", R = "Dagger" },
				"x",
				nil,
			}
		do
			T.falsy(FoundryLogic.usable(junk, 1), "junk is never usable")
		end
		local last = 0
		for level = 2, BlasterData.MaxLevel do
			local hits = FoundryLogic.hits(level)
			T.truthy(hits >= 4 and hits <= 8, "taps in 4..8")
			T.le(last, hits, "taps never drop")
			last = hits
			T.le(BlasterData.ByLevel[level].Recipe.Ingots, GameConfig.MaxFoundryStock, "a recipe fits the stock")
		end
	end)

	T.test("FoundryLogic: the forge uses one skin ingot plus the cheapest others, the best stay", function()
		-- level 1 -> 2: 3 Common+ ingots
		local stock = {
			ingot("Gold", "Flawless"), -- 1 best
			ingot("Coal"), -- 2 cheapest
			ingot("Copper"), -- 3
			ingot("Gold", "Rough"), -- 4 the cheapest gold
			ingot("Coal"), -- 5 a tie with 2
			ingot("Iron"), -- 6
		}
		T.eq(FoundryLogic.defaultSkin(stock, 1), "Gold", "default look: the most valuable ingot's ore")
		local picked = FoundryLogic.pick(stock, 1, nil)
		T.eq(#picked, 3, "exactly the recipe")
		T.eq(picked[1], 4, "the skin ore's cheapest ingot first")
		T.eq(picked[2], 2, "then the cheapest other (ties: stock order)")
		T.eq(picked[3], 5, "the tie")
		local copper = FoundryLogic.pick(stock, 1, "Copper")
		T.eq(copper[1], 3, "a chosen look")
		T.eq(copper[2], 2, "plus the cheapest")
		T.eq(copper[3], 5, "...")
		local _, bad = FoundryLogic.pick(stock, 1, "Diamond")
		T.eq(bad, "BadOre", "a look must be among the usable ingots")
		local _, few = FoundryLogic.pick({ ingot("Gold"), ingot("Coal") }, 1, nil)
		T.eq(few, "NotEnough", "two of three")
		local _, top = FoundryLogic.pick(stock, BlasterData.MaxLevel, nil)
		T.eq(top, "MaxLevel")
		-- level 3 -> 4 needs Uncommon+: Common ingots never count
		local mixed = {
			ingot("Coal"),
			ingot("Silver"),
			ingot("Coal"),
			ingot("Silver"),
			ingot("Gold"),
			ingot("Silver"),
			ingot("Jade"),
			ingot("Silver"),
		}
		T.eq(FoundryLogic.usableCount(mixed, 3), 6, "six Uncommon+")
		local six = FoundryLogic.pick(mixed, 3, "Jade")
		T.eq(#six, 6, "six used")
		for _, index in six do
			T.truthy(mixed[index].O ~= "Coal", "never a Common one")
		end
		local unusable = FoundryLogic.unusable(mixed, 3)
		T.eq(#unusable, 2, "the two coal")
		T.eq(unusable[1], 1)
		T.eq(unusable[2], 3)
		-- ties between ores: the first in stock order wins the default look
		T.eq(FoundryLogic.defaultSkin({ ingot("Tin"), ingot("Coal"), ingot("Tin") }, 1), "Tin")
		local skins = FoundryLogic.skins({ ingot("Coal"), ingot("Gold"), ingot("Copper") }, 1)
		T.eq(skins[1], "Gold")
		T.eq(skins[2], "Copper")
		T.eq(skins[3], "Coal")
	end)

	T.test("FoundryLogic: status and the State summary", function()
		local list = FoundryLogic.fromSummary({
			["Ingot|Gold|Clean|"] = 2,
			["Ingot|Coal||"] = 1,
			["Raw|Gold||"] = 5,
			junk = 3,
			["Ingot|Tin||"] = 0 / 0,
		})
		T.eq(#list, 3, "only ingots, sane counts")
		local big = FoundryLogic.fromSummary({ ["Ingot|Coal||"] = 1e9 })
		T.eq(#big, GameConfig.MaxFoundryStock, "capped")
		local ready = FoundryLogic.status(list, 1, 1000, nil)
		T.truthy(ready.Ready, "3 ingots and 1000 coins")
		T.eq(ready.Skin, "Gold")
		T.eq(ready.Level, 2)
		local poor = FoundryLogic.status(list, 1, 10, "Coal")
		T.eq(poor.Reason, "NeedCoins")
		T.eq(poor.Skin, "Coal", "a valid choice is kept")
		local wrongChoice = FoundryLogic.status(list, 1, 1000, "Diamond")
		T.eq(wrongChoice.Skin, "Gold", "an invalid choice falls back to the default")
		local short = FoundryLogic.status(list, 3, 1e9, nil)
		T.eq(short.Reason, "NeedIngots")
		T.eq(short.Have, 2, "the Gold ingots only")
		local top = FoundryLogic.status(list, BlasterData.MaxLevel, 1e12, nil)
		T.eq(top.Reason, "MaxLevel")
		T.falsy(top.Ready)
	end)

	---------------------------------------------------------------- FoundryBuilder

	local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT])

	T.test("FoundryBuilder: the building stays in its rect, under the trains' arcs, on a mobile budget", function()
		local building = FoundryBuilder.build(plotCF, 2)
		local rect = BaseLayout.Foundry
		local parts, neon, collide = 0, 0, 0
		for _, d in building:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.truthy(d.Anchored, d.Name .. " anchored")
				if d.Material == roblox.Enum.Material.Neon then
					neon += 1
					T.falsy(d.CastShadow, "neon casts no shadow")
					T.falsy(d.CanCollide, "glows don't collide")
				end
				if d.CanCollide then
					collide += 1
				end
				-- corners of the part's box, plot-local
				local half = d.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p =
								plotCF:PointToObjectSpace(d.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)))
							if d.Name ~= "Intake" then
								T.le(math.abs(p.X - rect.Center.X), rect.Size.X / 2 + 0.01, d.Name .. " inside the Foundry rect (x)")
								T.le(math.abs(p.Z - rect.Center.Z), rect.Size.Z / 2 + 0.01, d.Name .. " inside the Foundry rect (z)")
								T.le(p.Y, rect.Size.Y, d.Name .. " under the trains' ore arcs")
							end
							T.lt(GameConfig.PlotCells * GameConfig.CellSize / 2 + 1, p.Z, d.Name .. " off the build grid")
						end
					end
				end
			end
		end
		T.le(parts, FoundryBuilder.MaxParts, "part budget")
		T.truthy(neon >= 6, "molten glows")
		T.lt(collide, parts / 2, "most details don't collide")
		local base = building.PrimaryPart
		T.eq(base and base.Name, "Base", "PrimaryPart")
		for _, name in { "AnvilPoint", "CamPoint", "Prompt", "HopperIn", "HopperOut", "RackMount" } do
			T.truthy(base:FindFirstChild(name), "attachment " .. name)
		end
		local anvil = (base.CFrame * base:FindFirstChild("AnvilPoint").CFrame).Position
		local expected = plotCF * FoundryBuilder.AnvilLocal
		T.near((anvil - expected).Magnitude, 0, 1e-3, "AnvilLocal matches the attachment")
		local cam = base.CFrame * base:FindFirstChild("CamPoint").CFrame
		T.lt(0.7, cam.LookVector:Dot((anvil - cam.Position).Unit), "the close-up camera looks at the anvil")
		local intake = building:FindFirstChild("Intake")
		T.truthy(intake and intake:IsA("BasePart") and intake.Transparency == 1 and not intake.CanCollide, "invisible hopper box")
		local warn = 0
		for _, d in building:GetDescendants() do
			if d.Name == "WarnLight" then
				warn += 1
			end
		end
		T.eq(warn, 2, "two warning lights")
		-- the hopper box sits over the hopper rim and HopperOut is outside it
		local out = (base.CFrame * base:FindFirstChild("HopperOut").CFrame).Position
		local o = intake.CFrame:PointToObjectSpace(out)
		T.truthy(
			math.abs(o.X) > intake.Size.X / 2 or math.abs(o.Y) > intake.Size.Y / 2 or math.abs(o.Z) > intake.Size.Z / 2,
			"bounce point outside the box"
		)
		local floor = building:FindFirstChild("HopperFloor")
		local r = intake.CFrame:PointToObjectSpace(floor.CFrame.Position + Vector3.new(0, floor.Size.Y / 2 + 0.4, 0))
		T.truthy(
			math.abs(r.X) < intake.Size.X / 2 and math.abs(r.Y) < intake.Size.Y / 2 and math.abs(r.Z) < intake.Size.Z / 2,
			"an ingot lying in the hopper cup is in the box"
		)
	end)

	T.test("FoundryBuilder: the rack shows every next level's silhouette, then COMING SOON", function()
		local building = FoundryBuilder.build(plotCF, 2)
		local board = building:FindFirstChild("RackBoard")
		local sign = building:FindFirstChild("RackSign"):FindFirstChild("Text", true)
		for level = 2, BlasterData.MaxLevel do
			FoundryBuilder.setRack(building, level)
			local silhouette = building:FindFirstChild("Silhouette")
			T.truthy(silhouette, "silhouette " .. level)
			local n = 0
			for _, d in silhouette:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
					T.eq(d.Color, FoundryBuilder.Colors.Silhouette, "black")
					T.truthy(d.Anchored and not d.CanCollide, "anchored decor")
					local p = board.CFrame:PointToObjectSpace(d.CFrame.Position)
					T.le(math.abs(p.X), board.Size.X / 2, `level {level} {d.Name} on the board (x)`)
					T.le(math.abs(p.Y), board.Size.Y / 2, `level {level} {d.Name} on the board (y)`)
					T.lt(p.Z, 0, "in front of the board")
				elseif d:IsA("WeldConstraint") or d:IsA("Attachment") then
					error("tool leftovers in the silhouette")
				end
			end
			T.le(n, 25, "a blaster's part budget")
			T.eq(sign.Text, `NEXT: LV {level}`)
			local count = 0
			for _, child in building:GetChildren() do
				if child.Name == "Silhouette" then
					count += 1
				end
			end
			T.eq(count, 1, "the old one is gone")
		end
		FoundryBuilder.setRack(building, BlasterData.MaxLevel + 1)
		T.eq(building:FindFirstChild("Silhouette"), nil, "no silhouette after the top level")
		T.eq(sign.Text, "COMING SOON")
		T.truthy(board:FindFirstChild("Mystery").Enabled, "a big ?")
	end)

	T.test("FoundryBuilder: the chute receiver fits BaseLayout.FoundryIntake and never blocks anything", function()
		local receiver = FoundryBuilder.receiver(plotCF)
		local zone = BaseLayout.FoundryIntake.Zone
		local parts = 0
		for _, d in receiver:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.falsy(d.CanCollide, d.Name .. " doesn't collide (items ride through)")
				T.falsy(d.CanQuery, d.Name .. " not raycast (build mode)")
				local half = d.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p =
								plotCF:PointToObjectSpace(d.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)))
							T.le(math.abs(p.X - zone.Center.X), zone.Size.X / 2 + 0.02, d.Name .. " in the zone (x)")
							T.le(math.abs(p.Z - zone.Center.Z), zone.Size.Z / 2 + 0.02, d.Name .. " in the zone (z)")
							T.le(p.Y, zone.Size.Y + 0.02, d.Name .. " under the zone's top")
						end
					end
				end
			end
		end
		T.le(parts, FoundryBuilder.ReceiverMaxParts, "receiver budget")
		local hood = receiver.PrimaryPart
		local mouth = hood:FindFirstChild("Mouth")
		local at = plotCF:PointToObjectSpace((hood.CFrame * mouth.CFrame).Position)
		T.near((at - BaseLayout.FoundryIntake.Mouth).Magnitude, 0, 1e-3, "Mouth where BaseLayout says")
		local sign = hood:FindFirstChild("PenFull")
		T.truthy(sign and sign:IsA("BillboardGui") and not sign.Enabled, "Ore Pen full sign, hidden")
	end)

	---------------------------------------------------------------- FoundryService world

	local function fakePlayer(userId: number, name: string): any
		local p: any = { UserId = userId, Name = name, Parent = true, attributes = {} }
		p.GetAttribute = function(self, key)
			return self.attributes[key]
		end
		p.alive = true
		p.root = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0) }
		p.Character = {
			FindFirstChildOfClass = function(_, class: string)
				return if class == "Humanoid" then { Health = if p.alive then 100 else 0 } else nil
			end,
			FindFirstChild = function(_, child: string)
				return if child == "HumanoidRootPart" then p.root else nil
			end,
		}
		p.stand = function(position: any)
			p.root.Position = position
			p.root.CFrame = CFrame.new(position)
		end
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, carried = {}, zones = {}, now = 1000, cells = {} }
		w.plotModel = PlotBuilder.buildPlot(roblox.Instance.new("Folder"), WorldLayout.Plots[PLOT], Rng.new(PLOT))
		w.placeholder = w.plotModel.Yard.Foundry
		w.player = fakePlayer(USER, "Smith")
		w.other = fakePlayer(OTHER, "Neighbour")
		w.data = deepCopy(DataTemplate)
		w.otherData = deepCopy(DataTemplate)
		w.anvil = plotCF * FoundryBuilder.AnvilLocal
		w.player.stand(w.anvil + Vector3.new(0, 0.5, -3))
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data elseif p == w.other then w.otherData else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, a, b, c, d, e, f)
			table.insert(w.notes, { Name = name, Player = p, A = a, B = b, C = c, D = d, E = e, F = f })
		end)
		patch(Net, "fireNear", function(name, _, _, _, a, b, c, d)
			table.insert(w.notes, { Name = name, Near = true, A = a, B = b, C = c, D = d })
		end)
		patch(PlotService, "plotOf", function(p)
			return if p == w.player and not w.free then PLOT elseif p == w.other then 1 else nil
		end)
		patch(PlotService, "ownerOf", function(id)
			return if id == PLOT and not w.free then w.player else nil
		end)
		patch(PlotService, "model", function(id)
			return if id == PLOT then w.plotModel else nil
		end)
		patch(Players, "GetPlayerByUserId", function(_, id)
			return if id == USER then w.player elseif id == OTHER then w.other else nil
		end)
		patch(HttpService, "GenerateGUID", function()
			w.ids = (w.ids or 0) + 1
			return "foundry-guid-" .. w.ids
		end)
		patch(IntakeService, "addZone", function(name, part, handler)
			table.insert(w.zones, { Name = name, Part = part, Handler = handler })
		end)
		patch(CarryService, "list", function()
			return w.carried
		end)
		patch(CarryService, "takeTop", function(_, predicate)
			for i = #w.carried, 1, -1 do
				local record = w.carried[i]
				if not predicate or predicate(record) then
					table.remove(w.carried, i)
					return record
				end
			end
			return nil
		end)
		patch(MachineService, "atCell", function(_, x, z)
			return w.cells[x .. "," .. z]
		end)
		ItemService._test.reset()
		fs.reset()
		fs.setClock(function()
			return w.now
		end)
		T.truthy(fs.setupPlot(PLOT), "foundry set up")
		w.building = FoundryService.building(PLOT)
		w.zone = w.zones[1]
		w.restore = function()
			ItemService._test.reset()
			fs.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		return w
	end

	local function withWorld(name: string, fn: (any) -> ())
		T.test(name, function()
			local w = setup()
			local ok, err = pcall(fn, w)
			w.restore()
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function notes(w: any, name: string): { any }
		local list = {}
		for _, note in w.notes do
			if note.Name == name then
				table.insert(list, note)
			end
		end
		return list
	end

	local function lastNote(w: any, name: string): any
		local list = notes(w, name)
		return list[#list]
	end

	local function stock(w: any): { any }
		return w.data.Foundry.Stock
	end

	local function countKey(list: { any }, key: string): number
		local n = 0
		for _, desc in list do
			if ItemData.storageKey(desc) == key then
				n += 1
			end
		end
		return n
	end

	-- A server-owned loose item on the FOUNDRY chute cell.
	local function onChute(owner: number, desc: any): any
		local cell = BaseLayout.chuteLocal("Foundry")
		return ItemService.spawnDesc(desc, owner, plotCF * CFrame.new(cell.X, 1, cell.Z), nil, true)
	end

	local function inHopper(w: any, owner: number, desc: any): any
		return ItemService.spawnDesc(desc, owner, w.zone.Part.CFrame, nil, true)
	end

	local function inBox(part: any, position: any): boolean
		local p = part.CFrame:PointToObjectSpace(position)
		return math.abs(p.X) <= part.Size.X / 2 and math.abs(p.Y) <= part.Size.Y / 2 and math.abs(p.Z) <= part.Size.Z / 2
	end

	withWorld("FoundryService: the placeholder is replaced by the building, with receiver, zone and prompts", function(w)
		local yard = w.plotModel.Yard
		local count = 0
		for _, child in yard:GetChildren() do
			if child.Name == "Foundry" then
				count += 1
			end
		end
		T.eq(count, 1, "one Foundry in the yard")
		T.eq(yard:FindFirstChild("ComingSoon", true), nil, "the placeholder (and its COMING SOON plank) is gone")
		T.eq(w.building:GetAttribute("PlotId"), PLOT)
		T.truthy(w.building:HasTag(FoundryService.BuildingTag), "tagged for the client")
		T.eq(w.building:GetAttribute("Forging"), false)
		T.truthy(FoundryService.receiver(PLOT), "chute receiver on the plot")
		T.eq(w.zone.Name, "Foundry" .. PLOT, "hopper zone")
		T.eq(w.zone.Part, w.building:FindFirstChild("Intake"))
		local prompts = {}
		for _, d in w.building:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				prompts[d.Name] = d
				T.truthy(d:HasTag(FoundryService.PromptTag), "prompt tag")
				T.eq(d:GetAttribute("PlotId"), PLOT)
			end
		end
		T.truthy(prompts.FoundryOpen and prompts.FoundryPutIn, "Open Foundry and Put In")
		T.eq(prompts.FoundryOpen.KeyboardKeyCode, roblox.Enum.KeyCode.G)
		T.eq(prompts.FoundryPutIn.GamepadKeyCode, roblox.Enum.KeyCode.ButtonY)
		-- setting up twice changes nothing
		T.truthy(fs.setupPlot(PLOT))
		T.eq(FoundryService.building(PLOT), w.building, "same building")
	end)

	withWorld("FoundryService: the chute sink sorts into the stock or the pen and waits when both are full", function(w)
		-- usable ingot -> stock
		local gold = onChute(USER, ingot("Gold", "Clean"))
		local ok = FoundryService.sink(PLOT, gold)
		T.truthy(ok, "taken")
		T.eq(gold.State, "Consumed")
		T.eq(#stock(w), 1, "in the stock")
		local fx = lastNote(w, "Fx")
		T.eq(fx.A, "FoundryIn", "flies into the hood")
		T.eq(fx.Player, w.player, "only the owner sees it")
		T.eq(fx.D, "Ingot")
		T.eq(fx.E, "Gold")
		T.eq(fx.F, "Stock", "into the stock")
		T.eq(#notes(w, "Notify"), 0, "no toast for the stock")
		-- dirty ore -> pen, and its ore stays secret
		local raw = onChute(USER, { K = "Raw", O = "Heartstone" })
		T.truthy(FoundryService.sink(PLOT, raw))
		T.eq(countKey(w.data.Storage, "Raw|Heartstone||"), 1, "dirty ore to the pen")
		local rawFx = notes(w, "Fx")[2]
		T.eq(rawFx.D, "Raw")
		T.eq(rawFx.E, "", "the dirty ore's secret is kept")
		T.eq(rawFx.F, "Pen", "the client tags it TO ORE PEN")
		T.truthy(lastNote(w, "Notify").A.Text:find("Only ingots", 1, true), "the owner is told why")
		T.eq(lastNote(w, "Notify").A.Kind, "Info")
		-- the same reason again soon: no second toast (a busy line)
		local toasts = #notes(w, "Notify")
		T.truthy(FoundryService.sink(PLOT, onChute(USER, { K = "Raw", O = "Coal" })))
		T.eq(#notes(w, "Notify"), toasts, "throttled")
		-- level 3 needs Uncommon+ for level 4: a Common ingot goes to the pen
		w.data.BlasterLevel = 3
		T.truthy(FoundryService.sink(PLOT, onChute(USER, ingot("Coal"))))
		T.eq(countKey(w.data.Storage, "Ingot|Coal||"), 1, "too common: the pen")
		T.eq(lastNote(w, "Fx").F, "Pen")
		local why = lastNote(w, "Notify").A.Text
		T.truthy(why:find("Coal ingots aren't needed", 1, true) and why:find("Ore Pen", 1, true), why)
		for _, note in notes(w, "Fx") do
			T.falsy(note.Near, "no FoundryIn to everyone near")
		end
		T.truthy(FoundryService.sink(PLOT, onChute(USER, ingot("Silver"))))
		T.eq(#stock(w), 2, "Uncommon into the stock")
		-- stock full: usable ingots go to the pen
		for _ = #stock(w) + 1, GameConfig.MaxFoundryStock do
			table.insert(stock(w), ingot("Silver"))
		end
		T.truthy(FoundryService.sink(PLOT, onChute(USER, ingot("Gold"))))
		T.eq(countKey(w.data.Storage, "Ingot|Gold||"), 1, "full stock: the pen")
		T.eq(#stock(w), GameConfig.MaxFoundryStock, "stock stays at the cap")
		-- both full: the item waits on the cell, the receiver says why
		local capacity = ItemService.penCapacity(w.data)
		for _ = #w.data.Storage + 1, capacity do
			table.insert(w.data.Storage, { K = "Raw", O = "Coal" })
		end
		local waiting = onChute(USER, ingot("Gold"))
		local taken, reason = FoundryService.sink(PLOT, waiting)
		T.falsy(taken)
		T.eq(reason, "Full")
		T.eq(waiting.State, "Loose", "still on the belt")
		local sign = FoundryService.receiver(PLOT).PrimaryPart:FindFirstChild("PenFull")
		T.truthy(sign.Enabled, "Ore Pen full shows")
		T.truthy(lastNote(w, "Notify").A.Text:find("full", 1, true), "owner told")
		w.now += 5
		fs.monitor(w.now)
		T.falsy(sign.Enabled, "the sign goes away again")
		-- someone else's item is refused as Foreign and never stored
		local before = #w.data.Storage + #stock(w)
		local foreign = onChute(OTHER, ingot("Diamond"))
		local fOk, fReason = FoundryService.sink(PLOT, foreign)
		T.falsy(fOk)
		T.eq(fReason, "Foreign")
		T.eq(foreign.State, "Loose")
		T.eq(#w.data.Storage + #stock(w), before, "nothing stored")
		T.eq(#w.otherData.Storage, 0, "not in the thrower's pen either")
	end)

	withWorld("FoundryService: the sink adapter accepts the arguments in any order and shape", function(w)
		local handler = FoundryService.sinkHandler
		T.truthy(handler(PLOT, onChute(USER, ingot("Coal"))), "(plotId, record)")
		T.truthy(handler(onChute(USER, ingot("Coal")), PLOT), "(record, plotId)")
		T.truthy(handler(w.player, onChute(USER, ingot("Coal"))), "(player, record)")
		local record = onChute(USER, ingot("Coal"))
		T.truthy(handler(record.Model), "(model): the plot from its position")
		T.eq(#stock(w), 4)
		local ok, reason = handler(PLOT)
		T.falsy(ok)
		T.eq(reason, "Wrong", "no item")
		-- a number that isn't a plot id (a clock, a count) is never taken for one
		T.truthy(handler(onChute(USER, ingot("Coal")), 1234.5), "(record, clock): the plot from its position")
		T.truthy(handler(99, onChute(USER, ingot("Coal"))), "(99, record): not a plot, the position decides")
		T.eq(#stock(w), 6)
		local lost = ItemService.spawnDesc(ingot("Coal"), USER, CFrame.new(0, 200, 0), nil, true)
		local okLost, whyLost = handler(4321, lost)
		T.falsy(okLost)
		T.eq(whyLost, "Wrong", "no plot anywhere")
		T.eq(lost.State, "Loose", "left alone")
		-- max level: everything goes to the pen
		w.data.BlasterLevel = BlasterData.MaxLevel
		T.truthy(handler(PLOT, onChute(USER, ingot("Heartstone"))))
		T.truthy(lastNote(w, "Notify").A.Text:find("top level", 1, true), "says why")
		T.eq(countKey(w.data.Storage, "Ingot|Heartstone||"), 1, "top level: the pen")
	end)

	withWorld("FoundryService: without a belt, items lying on the FOUNDRY cell go in (no ConveyorService)", function(w)
		local lying = onChute(USER, ingot("Iron"))
		local away = ItemService.spawnDesc(ingot("Iron"), USER, plotCF * CFrame.new(0, 1, 0), nil, true)
		fs.scanChuteFloor()
		T.eq(lying.State, "Consumed", "taken off the cell")
		T.eq(away.State, "Loose", "items elsewhere stay")
		T.eq(#stock(w), 1)
		-- a belt on the cell: the belt decides (ConveyorService), the scan keeps out
		local cx, cz = BaseLayout.chuteCell("Foundry")
		w.cells[cx .. "," .. cz] = { Id = "Conveyor" }
		local onBelt = onChute(USER, ingot("Iron"))
		fs.scanChuteFloor()
		T.eq(onBelt.State, "Loose", "not taken from a belt")
	end)

	withWorld("FoundryService: the hopper takes usable ingots and bounces everything else", function(w)
		local zone = w.zone
		local good = inHopper(w, USER, ingot("Copper"))
		zone.Handler(good)
		T.eq(good.State, "Consumed")
		T.eq(#stock(w), 1)
		-- dirty ore bounces back out
		local raw = inHopper(w, USER, { K = "Raw", O = "Gold" })
		zone.Handler(raw)
		T.eq(raw.State, "Loose", "bounced")
		T.falsy(inBox(zone.Part, raw.Body.CFrame.Position), "out of the box")
		T.truthy(lastNote(w, "Notify").A.Text:find("Only ingots", 1, true), "why")
		-- too common for the next level
		w.data.BlasterLevel = 3
		local coal = inHopper(w, USER, ingot("Coal"))
		zone.Handler(coal)
		T.eq(coal.State, "Loose")
		T.truthy(lastNote(w, "Notify").A.Text:find("Uncommon", 1, true), "needs Uncommon")
		-- a full stock
		for _ = #stock(w) + 1, GameConfig.MaxFoundryStock do
			table.insert(stock(w), ingot("Silver"))
		end
		local extra = inHopper(w, USER, ingot("Silver"))
		zone.Handler(extra)
		T.eq(extra.State, "Loose", "full stock bounces")
		T.eq(#stock(w), GameConfig.MaxFoundryStock)
		-- a stranger's ingot bounces and the thrower is told
		local foreign = inHopper(w, OTHER, ingot("Diamond"))
		zone.Handler(foreign)
		T.eq(foreign.State, "Loose")
		T.eq(lastNote(w, "Notify").Player, w.other, "thrower told")
	end)

	withWorld("FoundryService: Put In loads only the carried ingots the next level can use", function(w)
		fs.putIn(w.player, PLOT)
		T.truthy(lastNote(w, "Notify").A.Text:find("Carry ingots", 1, true), "empty hands")
		for _, desc in { { K = "Raw", O = "Gold" }, ingot("Coal"), ingot("Silver"), ingot("Gold") } do
			local record = ItemService.spawnDesc(desc, USER, CFrame.new(0, 5, 0), nil, true)
			record.State = "Carried"
			table.insert(w.carried, record)
		end
		w.data.BlasterLevel = 3
		fs.putIn(w.player, PLOT)
		T.eq(#stock(w), 2, "Silver and Gold")
		T.eq(#w.carried, 2, "dirty ore and coal stay in your hands")
		T.eq(lastNote(w, "Fx").A, "FoundryPut")
		fs.putIn(w.player, PLOT)
		T.truthy(lastNote(w, "Notify").A.Text:find("Uncommon", 1, true), "the top item's reason")
		fs.putIn(w.other, PLOT)
		T.eq(lastNote(w, "Notify").Player, w.other, "not your Foundry")
		T.eq(#stock(w), 2)
	end)

	withWorld("FoundryService: Open and Take", function(w)
		fs.open(w.player, PLOT)
		T.eq(lastNote(w, "OpenUI").A, "Foundry")
		fs.open(w.other, PLOT)
		T.eq(#notes(w, "OpenUI"), 1, "not for strangers")
		fs.action(w.player, "Open", nil)
		T.eq(#notes(w, "OpenUI"), 2, "FoundryAction Open")
		for _ = 1, 3 do
			table.insert(stock(w), ingot("Gold", "Clean"))
		end
		table.insert(stock(w), ingot("Iron"))
		fs.action(w.player, "Take", { Key = "Ingot|Gold|Clean|", Count = 2 })
		T.eq(countKey(stock(w), "Ingot|Gold|Clean|"), 1, "two out")
		T.eq(countKey(w.data.Storage, "Ingot|Gold|Clean|"), 2, "into the pen")
		-- junk is ignored
		for _, arg in
			{
				{ Key = "Raw|Gold||", Count = 1 },
				{ Key = "Ingot|Gold|Clean|", Count = 0 },
				{ Key = "Ingot|Gold|Clean|", Count = 1.5 },
				{ Key = 5, Count = 1 },
				"x",
			}
		do
			fs.action(w.player, "Take", arg)
		end
		T.eq(#stock(w), 2, "nothing else moved")
		-- TAKE ALL: every ingot of the ore, any grade
		table.insert(stock(w), ingot("Gold", "Rough"))
		table.insert(stock(w), ingot("Gold", "Pristine"))
		fs.action(w.player, "Take", { Key = "Ingot|Gold|Rough|", Count = 5, All = "yes" })
		T.eq(#stock(w), 4, "a bad All is ignored")
		fs.action(w.player, "Take", { Key = "Ingot|Gold|Rough|", Count = 5, All = true })
		T.eq(#stock(w), 1, "all three Gold out")
		T.eq(countKey(stock(w), "Ingot|Iron||"), 1, "the Iron stays")
		T.eq(countKey(w.data.Storage, "Ingot|Gold|Pristine|"), 1, "into the pen")
		T.eq(#w.data.Storage, 5)
		fs.action(w.player, "Take", { Key = "Ingot|Iron||", Count = 1, All = false })
		T.eq(#stock(w), 0, "All = false is one key")
		-- back to the state before TAKE ALL
		table.clear(stock(w))
		table.clear(w.data.Storage)
		table.insert(stock(w), ingot("Gold", "Clean"))
		table.insert(stock(w), ingot("Iron"))
		for _ = 1, 2 do
			table.insert(w.data.Storage, ingot("Gold", "Clean"))
		end
		-- as many as fit in the pen
		local capacity = ItemService.penCapacity(w.data)
		for _ = #w.data.Storage + 1, capacity - 1 do
			table.insert(w.data.Storage, { K = "Raw", O = "Coal" })
		end
		table.insert(stock(w), ingot("Iron"))
		fs.action(w.player, "Take", { Key = "Ingot|Iron||", Count = 2 })
		T.eq(#w.data.Storage, capacity, "pen exactly full")
		T.eq(countKey(stock(w), "Ingot|Iron||"), 1, "one stayed")
		fs.action(w.player, "Take", { Key = "Ingot|Iron||", Count = 1 })
		T.truthy(lastNote(w, "Notify").A.Text:find("full", 1, true), "pen full")
		-- too far away
		table.remove(w.data.Storage)
		w.player.stand(w.anvil + Vector3.new(60, 0, 0))
		fs.action(w.player, "Take", { Key = "Ingot|Iron||", Count = 1 })
		T.eq(countKey(stock(w), "Ingot|Iron||"), 1, "not from afar")
	end)

	withWorld("FoundryService: quick Takes share one toast", function(w)
		local function moved(): { any }
			local list = {}
			for _, note in notes(w, "Notify") do
				if note.A.Text:find("Moved", 1, true) then
					table.insert(list, note)
				end
			end
			return list
		end
		for _ = 1, 4 do
			table.insert(stock(w), ingot("Gold", "Clean"))
		end
		for _ = 1, 3 do
			fs.action(w.player, "Take", { Key = "Ingot|Gold|Clean|", Count = 1 })
			w.now += 0.2
		end
		T.eq(countKey(w.data.Storage, "Ingot|Gold|Clean|"), 3, "three moved")
		T.eq(#moved(), 0, "no toast per click")
		fs.monitor(w.now + 0.2)
		T.eq(#moved(), 0, "still clicking: wait")
		fs.monitor(w.now + 1)
		T.eq(#moved(), 1, "one toast")
		T.eq(moved()[1].A.Text, "Moved 3 ingots to your Ore Pen.")
		T.eq(moved()[1].Player, w.player)
		fs.monitor(w.now + 5)
		T.eq(#moved(), 1, "sent once")
		w.now += 10
		fs.action(w.player, "Take", { Key = "Ingot|Gold|Clean|", Count = 1 })
		fs.monitor(w.now + 1)
		T.eq(moved()[2].A.Text, "Moved 1 ingot to your Ore Pen.")
	end)

	---------------------------------------------------------------- forging

	-- Valid tap times for a session (0.6 s intro, 0.32 s apart).
	local function taps(hits: number): { number }
		local times = {}
		for i = 1, hits do
			table.insert(times, 0.6 + (i - 1) * 0.32 + 0.01)
		end
		return times
	end

	local function begin(w: any): any
		local note = lastNote(w, "FoundryBegin")
		T.truthy(note, "FoundryBegin sent")
		return note.A
	end

	withWorld("FoundryService: forging level 2 takes exactly the picked ingots and coins on the last strike", function(w)
		w.data.Coins = 1000
		local list = { ingot("Gold", "Flawless"), ingot("Coal"), ingot("Copper"), ingot("Gold", "Rough"), ingot("Coal") }
		for _, desc in list do
			table.insert(stock(w), desc)
		end
		fs.action(w.player, "Forge", {})
		local session = begin(w)
		T.eq(session.Level, 2)
		T.eq(session.Ore, "Gold", "default look")
		T.eq(session.Hits, FoundryLogic.hits(2))
		T.eq(session.Ingots, 3)
		T.eq(session.Coins, BlasterData.ByLevel[2].Recipe.Coins)
		T.eq(session.Timeout, GameConfig.AnvilTimeout)
		T.eq(#stock(w), 5, "nothing taken at the start")
		T.eq(w.data.Coins, 1000)
		T.eq(w.building:GetAttribute("Forging"), true, "warning lights on")
		-- a second Forge is Busy, Take waits
		fs.action(w.player, "Forge", {})
		T.eq(lastNote(w, "FoundryResult").A.Reason, "Busy")
		fs.action(w.player, "Take", { Key = "Ingot|Coal||", Count = 1 })
		T.eq(#stock(w), 5, "no Take during a session")
		-- the taps
		w.now += 3
		local changedBefore = w.changed
		fs.action(w.player, "Strike", { SessionId = session.Id, Times = taps(session.Hits) })
		local result = lastNote(w, "FoundryResult").A
		T.truthy(result.Ok, "forged")
		T.eq(result.Id, session.Id)
		T.eq(result.Level, 2)
		T.eq(result.Ore, "Gold")
		T.eq(result.Name, BlasterData.displayName(2, "Gold"))
		T.eq(w.data.BlasterLevel, 2)
		T.eq(w.data.BlasterOre, "Gold")
		T.eq(w.data.Coins, 1000 - BlasterData.ByLevel[2].Recipe.Coins, "the level-2 forge's coins")
		T.eq(w.data.Stats.BlastersForged, 1)
		T.eq(w.data.Stats.RunForged, w.data.BlasterLevel, "the rebirth run counts a forged level (RebirthConfig.reachedOf)")
		T.truthy(w.changed > changedBefore, "data changed (ToolService swaps the blaster)")
		-- used: the cheap Gold + both Coal; kept: the Flawless Gold and the Copper
		T.eq(#stock(w), 2)
		T.eq(countKey(stock(w), "Ingot|Gold|Flawless|"), 1, "the best stays")
		T.eq(countKey(stock(w), "Ingot|Copper||"), 1)
		T.eq(fs.sessions[w.player], nil, "session over")
		T.eq(w.building:GetAttribute("Forging"), false)
		T.eq(w.building:GetAttribute("RackLevel"), 3, "the rack shows level 3 next")
		-- the same Strike again does nothing
		fs.action(w.player, "Strike", { SessionId = session.Id, Times = taps(session.Hits) })
		T.eq(w.data.BlasterLevel, 2, "one forge per session")
		T.eq(w.data.Coins, 1000 - BlasterData.ByLevel[2].Recipe.Coins)
	end)

	withWorld("FoundryService: after a forge the ingots the new next level can't use move to the pen", function(w)
		-- level 3 -> 4 needs 6 Uncommon+; level 5 also takes Uncommon, level 6 needs Rare
		w.data.BlasterLevel = 3
		w.data.Coins = BlasterData.ByLevel[4].Recipe.Coins + 5000
		for _ = 1, 6 do
			table.insert(stock(w), ingot("Silver"))
		end
		table.insert(stock(w), ingot("Coal")) -- never usable from level 4 on
		table.insert(stock(w), ingot("Amethyst"))
		fs.action(w.player, "Forge", { Ore = "Amethyst" })
		local session = begin(w)
		T.eq(session.Ore, "Amethyst")
		w.now += 10
		fs.action(w.player, "Strike", { SessionId = session.Id, Times = taps(session.Hits) })
		T.truthy(lastNote(w, "FoundryResult").A.Ok)
		T.eq(w.data.BlasterOre, "Amethyst", "the chosen look")
		T.eq(countKey(w.data.Storage, "Ingot|Coal||"), 1, "the coal went to the pen")
		T.eq(#stock(w), 1, "one Silver left (still usable for level 5)")
		T.eq(countKey(stock(w), "Ingot|Silver||"), 1)
		-- the top level: everything left moves out (as many as fit)
		w.data.BlasterLevel = 9
		w.data.Coins = BlasterData.ByLevel[10].Recipe.Coins * 2
		table.clear(stock(w))
		for _ = 1, 13 do
			table.insert(stock(w), ingot("Sunstone"))
		end
		local capacity = ItemService.penCapacity(w.data)
		for _ = #w.data.Storage + 1, capacity - 0 do
			table.insert(w.data.Storage, { K = "Raw", O = "Coal" })
		end
		table.remove(w.data.Storage) -- room for one
		fs.action(w.player, "Forge", {})
		local top = begin(w)
		w.now += 10
		fs.action(w.player, "Strike", { SessionId = top.Id, Times = taps(top.Hits) })
		T.truthy(lastNote(w, "FoundryResult").A.Ok, "level 10")
		T.eq(w.data.BlasterLevel, 10)
		T.eq(#w.data.Storage, capacity, "the pen filled up")
		T.eq(#stock(w), 0, "13 - 12 used - 1 moved")
		T.eq(w.building:GetAttribute("RackLevel"), 11, "coming soon on the rack")
		fs.action(w.player, "Forge", {})
		T.eq(lastNote(w, "FoundryResult").A.Reason, "MaxLevel")
	end)

	withWorld("FoundryService: bad strikes, cancels, timeouts and walking away never take anything", function(w)
		w.data.Coins = 1000
		for _ = 1, 4 do
			table.insert(stock(w), ingot("Iron"))
		end
		local function start(): any
			fs.action(w.player, "Forge", {})
			return begin(w)
		end
		local function untouched(label: string)
			T.eq(#stock(w), 4, label .. ": ingots kept")
			T.eq(w.data.Coins, 1000, label .. ": coins kept")
			T.eq(w.data.BlasterLevel, 1, label .. ": same blaster")
			T.eq(fs.sessions[w.player], nil, label .. ": session over")
			T.eq(w.building:GetAttribute("Forging"), false, label .. ": lights off")
		end
		-- too few taps
		local s = start()
		w.now += 5
		local few = taps(s.Hits)
		table.remove(few)
		fs.action(w.player, "Strike", { SessionId = s.Id, Times = few })
		T.eq(lastNote(w, "FoundryResult").A.Reason, "BadStrikes")
		untouched("too few")
		-- taps faster than a human
		s = start()
		w.now += 5
		local fast = {}
		for i = 1, s.Hits do
			table.insert(fast, 0.6 + i * 0.05)
		end
		fs.action(w.player, "Strike", { SessionId = s.Id, Times = fast })
		T.eq(lastNote(w, "FoundryResult").A.Reason, "BadStrikes")
		untouched("too fast")
		-- plausible times, but the server saw too little time pass
		s = start()
		w.now += 0.5
		fs.action(w.player, "Strike", { SessionId = s.Id, Times = taps(s.Hits) })
		T.eq(lastNote(w, "FoundryResult").A.Reason, "BadStrikes")
		untouched("server clock")
		-- junk times
		for _, junk in { "x", { 0 / 0 }, { math.huge }, {} } do
			s = start()
			w.now += 5
			fs.action(w.player, "Strike", { SessionId = s.Id, Times = junk })
			T.eq(lastNote(w, "FoundryResult").A.Reason, "BadStrikes")
			untouched("junk times")
		end
		-- a wrong session id is ignored; Cancel ends it
		s = start()
		fs.action(w.player, "Strike", { SessionId = "nope", Times = taps(s.Hits) })
		T.truthy(fs.sessions[w.player], "still running")
		fs.action(w.player, "Cancel", { SessionId = s.Id })
		T.eq(lastNote(w, "FoundryResult").A.Reason, "Cancelled")
		untouched("cancel")
		-- timeout
		s = start()
		w.now += GameConfig.AnvilTimeout + 1
		fs.monitor(w.now)
		T.eq(lastNote(w, "FoundryResult").A.Reason, "Timeout")
		untouched("timeout")
		-- walking away
		s = start()
		w.player.stand(w.anvil + Vector3.new(GameConfig.AnvilWalkAway + 10, 0, 0))
		fs.monitor(w.now)
		T.eq(lastNote(w, "FoundryResult").A.Reason, "TooFar")
		untouched("walk away")
		-- away at the moment of the last strike
		w.player.stand(w.anvil + Vector3.new(0, 0, -3))
		s = start()
		w.now += 5
		w.player.stand(w.anvil + Vector3.new(GameConfig.AnvilWalkAway + 10, 0, 0))
		fs.action(w.player, "Strike", { SessionId = s.Id, Times = taps(s.Hits) })
		T.eq(lastNote(w, "FoundryResult").A.Reason, "TooFar")
		untouched("away at the strike")
		-- dying
		w.player.stand(w.anvil + Vector3.new(0, 0, -3))
		s = start()
		w.player.alive = false
		fs.monitor(w.now)
		T.eq(lastNote(w, "FoundryResult").A.Reason, "Cancelled")
		untouched("death")
		w.player.alive = true
		-- coins spent somewhere else meanwhile: NotEnough on the strike
		s = start()
		w.data.Coins = 100
		w.now += 5
		fs.action(w.player, "Strike", { SessionId = s.Id, Times = taps(s.Hits) })
		T.eq(lastNote(w, "FoundryResult").A.Reason, "NotEnough")
		T.eq(#stock(w), 4, "ingots kept")
		T.eq(w.data.Coins, 100, "coins kept")
		T.eq(w.data.BlasterLevel, 1)
	end)

	withWorld("FoundryService: Forge refusals", function(w)
		local function reason(): string
			return lastNote(w, "FoundryResult").A.Reason
		end
		fs.action(w.player, "Forge", {})
		T.eq(reason(), "NotEnough", "no ingots")
		T.eq(lastNote(w, "FoundryResult").A.Id, "", "no session id")
		for _ = 1, 3 do
			table.insert(stock(w), ingot("Tin"))
		end
		fs.action(w.player, "Forge", {})
		T.eq(reason(), "NotEnough", "no coins")
		w.data.Coins = BlasterData.ByLevel[2].Recipe.Coins
		fs.action(w.player, "Forge", { Ore = "Diamond" })
		T.eq(reason(), "BadOre", "a look that isn't in the stock")
		fs.action(w.player, "Forge", { Ore = "NotAnOre" })
		T.eq(reason(), "BadOre", "an unknown ore")
		fs.action(w.player, "Forge", { Ore = 5 })
		T.eq(reason(), "BadOre", "junk")
		w.player.stand(w.anvil + Vector3.new(60, 0, 0))
		fs.action(w.player, "Forge", {})
		T.eq(reason(), "TooFar")
		w.player.stand(w.anvil + Vector3.new(0, 0, -3))
		T.eq(#notes(w, "FoundryBegin"), 0, "no session yet")
		fs.action(w.player, "Forge", { Ore = "Tin" })
		T.eq(begin(w).Ore, "Tin")
		-- junk actions and args are ignored
		for _, args in { { 5, {} }, { "Forge", "x" }, { "Forge", { 1, 2, 3, 4, 5 } }, { string.rep("a", 40), {} } } do
			fs.action(w.player, args[1], args[2])
		end
		T.eq(#notes(w, "FoundryBegin"), 1)
		-- losing the plot / leaving ends it
		w.free = true
		fs.monitor(w.now)
		T.eq(reason(), "TooFar", "no plot any more")
		T.eq(fs.sessions[w.player], nil)
	end)

	withWorld("FoundryService: conservation fuzz (chute, hopper, Take, forges)", function(w)
		local rng = Rng.new(4242)
		local ores = { "Coal", "Copper", "Silver", "Gold", "Diamond", "Sunstone", "Heartstone" }
		local spawned, consumed = 0, 0
		w.data.Coins = 1e12
		local loose: { any } = {}
		for step = 1, 600 do
			local roll = rng:range(0, 1)
			if roll < 0.45 then
				local desc = if rng:range(0, 1) < 0.85 then ingot(ores[rng:int(1, #ores)]) else { K = "Raw", O = ores[rng:int(1, #ores)] }
				local record = onChute(if rng:range(0, 1) < 0.9 then USER else OTHER, desc)
				spawned += 1
				FoundryService.sink(PLOT, record)
				if record.State == "Loose" then
					table.insert(loose, record)
				end
			elseif roll < 0.7 then
				local record = inHopper(w, USER, ingot(ores[rng:int(1, #ores)]))
				spawned += 1
				w.zone.Handler(record)
				if record.State == "Loose" then
					table.insert(loose, record)
				end
			elseif roll < 0.85 then
				local desc = stock(w)[rng:int(1, math.max(1, #stock(w)))]
				if desc then
					fs.action(w.player, "Take", { Key = ItemData.storageKey(desc), Count = rng:int(1, 3) })
				end
			elseif roll < 0.95 then
				local before = #stock(w)
				local level = w.data.BlasterLevel
				fs.action(w.player, "Forge", {})
				local note = lastNote(w, "FoundryBegin")
				if note and fs.sessions[w.player] then
					w.now += 10
					fs.action(w.player, "Strike", { SessionId = note.A.Id, Times = taps(note.A.Hits) })
					if w.data.BlasterLevel > level then
						consumed += BlasterData.ByLevel[w.data.BlasterLevel].Recipe.Ingots
					end
				end
				local _ = before
			else
				-- the pen empties a bit (selling)
				for _ = 1, rng:int(0, 20) do
					if #w.data.Storage > 0 then
						table.remove(w.data.Storage, 1)
						consumed += 1
					end
				end
			end
			local stillLoose = 0
			for _, record in loose do
				if record.State == "Loose" then
					stillLoose += 1
				end
			end
			T.eq(#stock(w) + #w.data.Storage + stillLoose + consumed, spawned, "step " .. step .. ": every item is somewhere")
			T.le(#stock(w), GameConfig.MaxFoundryStock, "stock cap")
			for _, desc in stock(w) do
				T.truthy(FoundryLogic.isIngot(desc), "only ingots in the stock")
			end
		end
		T.truthy(w.data.BlasterLevel > 1, "some blasters were forged")
	end)

	---------------------------------------------------------------- FoundryView

	T.test("FoundryView: ore rows group the grades and sort usable ores first", function()
		local rows = FoundryView.oreRows({
			["Ingot|Gold|Clean|"] = 2,
			["Ingot|Gold|Rough|"] = 1,
			["Ingot|Coal||"] = 4,
			["Ingot|Emberite|Flawless|"] = 1,
			["Raw|Gold||"] = 9,
			["junk"] = 1,
		}, 3)
		T.eq(#rows, 3, "one row per ore")
		T.eq(rows[1].Ore, "Gold", "usable and most valuable first")
		T.eq(rows[1].Count, 3)
		T.eq(rows[1].Name, "Gold")
		T.eq(FoundryView.fitTextSize("Gold", 140, 19), 19, "short names keep the size")
		T.lt(FoundryView.fitTextSize("Heartstone Shard", 126, 21), 21, "long names shrink")
		T.le(12, FoundryView.fitTextSize(string.rep("W", 80), 50, 21), "never below 12")
		T.eq(rows[1].TakeKey, "Ingot|Gold|Rough|", "TAKE moves the cheapest")
		T.eq(rows[1].Detail, "2 Clean, 1 Rough")
		T.eq(rows[2].Ore, "Emberite")
		T.eq(rows[3].Ore, "Coal", "unusable last")
		T.falsy(rows[3].Usable)
		T.truthy(rows[3].Detail:find("Uncommon", 1, true), "says why")
		T.eq(#FoundryView.oreRows(nil, 1), 0)
	end)

	T.test("FoundryView: card texts and the strike ring", function()
		local state = { FoundryStock = { ["Ingot|Gold||"] = 1, ["Ingot|Coal||"] = 1 }, BlasterLevel = 1, Coins = 100, BlasterOre = "" }
		local status = FoundryView.status(state, nil)
		T.eq(FoundryView.reasonText(status, 100), "Need 1 more Common+ ingot")
		state.FoundryStock["Ingot|Tin||"] = 3
		status = FoundryView.status(state, nil)
		T.eq(status.Reason, "NeedCoins")
		T.eq(FoundryView.reasonText(status, 100), `Need ${BlasterData.ByLevel[2].Recipe.Coins - 100} more`)
		T.eq(FoundryView.usesText(status), "Uses 1 Gold + your 2 cheapest ingots")
		state.Coins = BlasterData.ByLevel[2].Recipe.Coins + 50
		status = FoundryView.status(state, "Tin")
		T.truthy(status.Ready)
		T.eq(status.Skin, "Tin")
		T.truthy(FoundryView.reasonText(status, 300):find("Ready", 1, true))
		T.truthy(FoundryView.damageText(1, "", 2, "Tin"):find("->", 1, true))
		local top = FoundryView.status({ BlasterLevel = 10 }, nil)
		T.truthy(FoundryView.reasonText(top, 0):find("best", 1, true))
		-- PERFECT / GOOD / HIT around the beat, and the ring lands on the target
		T.eq(FoundryView.grade(FoundryView.Beat), "Perfect")
		T.eq(FoundryView.grade(FoundryView.Beat + 0.12), "Good")
		T.eq(FoundryView.grade(FoundryView.Beat - 0.15), "Good")
		T.eq(FoundryView.grade(0.1), "Hit")
		T.eq(FoundryView.grade(FoundryView.Beat + FoundryView.GoodWindow + FoundryView.Beat), "Perfect", "the ring repeats")
		T.near(FoundryView.ringScale(FoundryView.Beat), 1, 1e-6, "on the target at the beat")
		T.near(FoundryView.ringScale(0), FoundryView.RingStart, 1e-6)
		T.le(0.6, FoundryView.ringScale(FoundryView.Beat + 0.17))
	end)

	T.test("FoundryView: every tap counts and a fast burst still passes the server's check", function()
		for level = 2, BlasterData.MaxLevel do
			local hits = FoundryLogic.hits(level)
			-- a player tapping 12 times a second from the start: the taps wait
			-- their turn (FoundryController counts one when tapTime allows)
			local times: { number } = {}
			local queued, last, t = 0, nil, 0
			while #times < hits and t < 30 do
				if t < 3 then
					queued += 1 -- a tap this frame (every 1/12 s)
				end
				while queued > 0 and #times < hits and t >= FoundryView.tapTime(#times + 1, last) do
					queued -= 1
					table.insert(times, math.floor(t * 1000 + 0.5) / 1000)
					last = t
				end
				t += 1 / 12
			end
			T.eq(#times, hits, "every tap up to Hits counted at level " .. level)
			local ok, why = MachineLogic.validateStrikes(times, hits, times[#times] + 0.05)
			T.truthy(ok, `a burst passes at level {level}: {why}`)
			T.le(times[1], FoundryView.Intro + 0.1, "the first tap counts once the camera is there")
		end
		-- the gap is shorter than before (0.3) but never under the server's
		T.lt(FoundryView.MinGap, 0.3)
		T.le(GameConfig.AnvilMinStrikeGap + 0.01, FoundryView.MinGap)
		T.eq(FoundryView.tapTime(1, nil), FoundryView.Intro, "the first after the intro")
		T.near(FoundryView.tapTime(2, 0.6), 0.8, 1e-9, "the gap")
		T.near(FoundryView.tapTime(8, 2.0), 8 * FoundryView.Pace, 1e-9, "the pace for the last ones")
	end)

	T.test("FoundryView: the panel fits short landscape phones below the top bar", function()
		-- a 667 x 375 and an 844 x 390 phone at the 0.62 UI floor, 58 pt top bar
		for _, screen in { { 667, 375 }, { 844, 390 }, { 568, 320 } } do
			local w, h = screen[1], screen[2] - 58
			local fit = FoundryView.fitScale(w, h, 0.62, true)
			T.le(510 * 0.62 * fit, h - 11.9, `compact panel height fits {screen[1]}x{screen[2]}`)
			T.le(980 * 0.62 * fit, w - 31.9, `compact panel width fits {screen[1]}x{screen[2]}`)
			T.le(0.5, fit)
		end
		T.near(FoundryView.fitScale(844, 332, 0.62, true), 1, 1e-9, "a 390 pt phone needs no shrink")
		T.eq(FoundryView.fitScale(1920, 1022, 1.25, false), 1, "desktop: no shrink")
		T.eq(FoundryView.fitScale(0, 0, 1, false), 1, "no size yet")
		local refs = FoundryView.build()
		FoundryView.setCompact(refs, true)
		FoundryView.fit(refs, 667, 317, 0.62)
		T.lt(refs.Fit.Scale, 1, "the panel's Fit scale")
		T.eq(refs.Panel.Size.Y.Offset, 510)
	end)

	T.test("FoundryView: the TAKE switch and the Ore Pen note", function()
		local refs = FoundryView.build()
		local summary = { ["Ingot|Gold|Clean|"] = 2, ["Ingot|Coal||"] = 5 }
		T.falsy(refs.TakeAllMode, "starts on ONE")
		T.truthy(refs.TakeOne:GetAttribute("On"))
		FoundryView.setRows(refs, FoundryView.oreRows(summary, 3), 7)
		T.eq(refs.Rows.Gold.Take.Text, "TAKE", "usable: one")
		T.eq(refs.Rows.Coal.Take.Text, "TAKE ALL", "too common: all")
		FoundryView.setTakeMode(refs, true)
		T.truthy(refs.TakeEvery:GetAttribute("On"))
		T.falsy(refs.TakeOne:GetAttribute("On"))
		FoundryView.setRows(refs, FoundryView.oreRows(summary, 3), 7)
		T.eq(refs.Rows.Gold.Take.Text, "TAKE ALL", "ALL: usable rows take all too")
		T.truthy(refs.Rows.Gold.TakeAll)
		T.eq(refs.Rows.Gold.Amount, 2)
		FoundryView.setTakeMode(refs, false)
		FoundryView.setRows(refs, FoundryView.oreRows(summary, 3), 7)
		T.falsy(refs.Rows.Gold.TakeAll, "back to ONE")
		-- usable ingots in the Ore Pen: Silver (Uncommon) counts for level 4, Coal and raw ore don't
		local pen = { ["Ingot|Silver|Pristine|"] = 3, ["Ingot|Silver||"] = 1, ["Ingot|Coal||"] = 9, ["Raw|Gold||"] = 4, junk = 2 }
		T.eq(FoundryView.penUsable(pen, 3), 4)
		T.eq(FoundryView.penUsable(pen, 1), 13, "level 2 takes Common too")
		T.eq(FoundryView.penUsable(nil, 1), 0)
		T.eq(FoundryView.penUsable({ ["Ingot|Gold||"] = 0 / 0 }, 1), 0, "NaN counts nothing")
		FoundryView.setPen(refs, 4)
		T.truthy(refs.PenNote.Visible, "note under the rows")
		T.truthy(refs.PenNote.Text:find("FOUNDRY chute", 1, true), "says how they come back")
		T.truthy(refs.PenNote.Text:find("Put In", 1, true))
		T.truthy(FoundryView.penText(1):find("1 ingot for your next blaster waits", 1, true))
		FoundryView.setPen(refs, 0)
		T.falsy(refs.PenNote.Visible)
		FoundryView.setRows(refs, {}, 0)
		FoundryView.setPen(refs, 2)
		T.falsy(refs.PenNote.Visible, "empty stock: in the empty text instead")
		T.truthy(refs.Empty.Visible)
		T.truthy(refs.Empty.Text:find("Ore Pen", 1, true))
		FoundryView.setPen(refs, 0)
		T.truthy(refs.Empty.Text:find("No ingots yet", 1, true))
	end)

	T.test("FoundryView: the panel and the hammer HUD build and fill in", function()
		local refs = FoundryView.build()
		local state = {
			FoundryStock = { ["Ingot|Gold|Clean|"] = 2, ["Ingot|Coal||"] = 5 },
			FoundryCount = 7,
			BlasterLevel = 1,
			Coins = 5000,
			BlasterOre = "",
		}
		local created = FoundryView.setRows(refs, FoundryView.oreRows(state.FoundryStock, 1), 7)
		T.eq(#created, 2)
		T.eq(refs.StockHeader.Text, `INGOTS  7 / {GameConfig.MaxFoundryStock}`)
		local status = FoundryView.status(state, nil)
		FoundryView.setCard(refs, status, state)
		T.eq(refs.Badge.Text, "LV 2")
		T.eq(refs.BlasterName.Text, BlasterData.displayName(2, "Gold"))
		T.truthy(refs.Forge:GetAttribute("Ready"))
		T.eq(refs.Rows.Gold.Take.Text, "TAKE", "usable rows take one")
		-- the uses row: real ingots have a rim and a shine, missing ones a "?"
		local filled, missing = 0, 0
		for _, square in refs.UsesRow:GetChildren() do
			if square:IsA("Frame") then
				if square:GetAttribute("Filled") then
					filled += 1
					T.truthy(square:FindFirstChild("Shine"), "a shine on a real ingot")
				else
					missing += 1
					T.truthy(square:FindFirstChild("Missing"), "a ? slot")
				end
			end
		end
		T.eq(filled, 3, "Gold + 2 Coal")
		T.eq(missing, 0)
		local short = { FoundryStock = { ["Ingot|Gold|Clean|"] = 1 }, BlasterLevel = 1, Coins = 0, BlasterOre = "" }
		FoundryView.setCard(refs, FoundryView.status(short, nil), short)
		missing = 0
		for _, square in refs.UsesRow:GetChildren() do
			if square:IsA("Frame") and not square:GetAttribute("Filled") then
				missing += 1
			end
		end
		T.eq(missing, 2, "two missing slots")
		-- rows the next level can't use say TAKE ALL
		FoundryView.setRows(refs, FoundryView.oreRows(state.FoundryStock, 3), 7)
		T.eq(refs.Rows.Coal.Take.Text, "TAKE ALL")
		T.truthy(refs.Rows.Coal.TakeAll)
		T.eq(refs.Rows.Coal.Amount, 5)
		T.falsy(refs.Rows.Gold.TakeAll)
		FoundryView.setCompact(refs, true)
		T.eq(#FoundryView.setRows(refs, FoundryView.oreRows({ ["Ingot|Coal||"] = 1 }, 1), 1), 0, "rows reused")
		T.eq(refs.Rows.Gold, nil, "gone rows removed")
		FoundryView.setCard(refs, FoundryView.status({ BlasterLevel = 10 }, nil), { BlasterLevel = 10 })
		T.truthy(refs.Soon.Visible, "coming soon")
		T.eq(refs.Badge.Text, "LV 11")
		local forge = FoundryView.buildForge(true)
		-- LEAVE and the banner start below the Roblox top bar (58 pt) at any UI scale
		for _, scale in { 0.62, 0.75, 1, 1.4 } do
			FoundryView.placeTop(forge, 58, scale)
			local leaveHolder = forge.Leave.Parent
			T.le(58, (leaveHolder.Position.Y.Offset - 5) * scale, "LEAVE below the top bar at " .. scale)
			T.le(58, forge.Banner.Position.Y.Offset * scale, "banner below the top bar at " .. scale)
		end
		T.eq(FoundryView.topShift(0, 1), 0, "no top bar: no shift")
		FoundryView.setPips(forge, 6, 2)
		T.eq(#forge.PipList, 6)
		FoundryView.showCard(forge, 3, "Gold", 2, "Coal")
		T.truthy(forge.Card.Visible)
		T.eq(forge.CardName.Text, BlasterData.displayName(3, "Gold"))
		T.falsy(forge.RingHolder.Visible)
		local _ = OreData
	end)
end
