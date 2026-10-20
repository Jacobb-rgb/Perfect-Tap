--[[
	Dusty relics (owner's YES, 2026-10-20): a rock that holds an artifact
	drops a dusty relic item; cleaning it by hand (Cleaning Station) or in the
	Restoration Table puts the artifact into the collection. Nothing is ever
	lost: a relic a rescue move would store is cleaned on the way; it is
	never sold, stored in the pen, put on a podium or loaded on the train.
]]

return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local Instance = roblox.Instance
	local ItemData = Loader.requirePath("ReplicatedStorage.Shared.Config.ItemData")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local MachineLogic = Loader.requirePath("ReplicatedStorage.Shared.Machines.MachineLogic")
	local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local ItemService = Loader.requirePath("ServerScriptService.Server.Services.ItemService")
	local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")
	local CleaningService = Loader.requirePath("ServerScriptService.Server.Services.CleaningService")
	local Players = Loader.game:GetService("Players")

	local RELIC = "EmberCrown"
	local USER = 921

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

	local function withWorld(name: string, body: (any) -> ())
		T.test(name, function()
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			local w: any = { replies = {}, rolls = {} }
			w.player = { UserId = USER, Name = "Relic", Parent = true }
			w.data = deepCopy(DataTemplate)
			patch(DataService, "get", function(p)
				return if p == w.player then w.data else nil
			end)
			patch(DataService, "changed", function() end)
			patch(Net, "fire", function(event: string, p: any, a: any)
				table.insert(w.replies, { Event = event, Player = p, A = a })
			end)
			patch(PlotService, "plotOf", function()
				return nil
			end)
			patch(Players, "GetPlayerByUserId", function(_, id)
				return if id == USER then w.player else nil
			end)
			ItemService._test.reset()
			ArtifactService._test.reset()
			ArtifactService._test.setRandom(function()
				return if #w.rolls > 0 then table.remove(w.rolls, 1) else 0.5
			end)
			ItemService.setRelicKeeper(function(player, id, position)
				return ArtifactService.cleanRelic(player, id, position) ~= nil
			end)
			w.count = function(event: string): number
				local n = 0
				for _, r in w.replies do
					if r.Event == event then
						n += 1
					end
				end
				return n
			end
			local ok, err = pcall(body, w)
			ItemService.setRelicKeeper(nil)
			ItemService._test.reset()
			ArtifactService._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	T.test("Relics: a relic item kind that is never sold, stored or listed", function()
		T.truthy(ItemData.Kinds.Relic, "a kind")
		T.eq(ItemData.value("Relic", RELIC), 0, "worth nothing at Tobin's")
		T.eq(ItemData.income({ K = "Relic", O = RELIC }), 0, "no podium income")
		T.eq(ItemData.displayName("Relic", RELIC), ItemData.RelicName, "its name stays a secret")
		T.eq(ItemData.parseKey("Relic|" .. RELIC .. "||"), nil, "no summary lists it")
		T.truthy(MachineLogic.isValidDesc({ K = "Relic", O = RELIC }), "a valid machine item")
		T.falsy(MachineLogic.isValidDesc({ K = "Relic", O = "Nope" }), "an unknown artifact isn't")
		T.falsy(MachineLogic.isValidDesc({ K = "Relic", O = RELIC, G = "Flawless" }), "a relic has no grade")
		local table_ = MachineData.ById.RestorationTable
		T.truthy(table_ and table_.Accepts.Relic and table_.Time and table_.Output == nil, "the table is a sorter that takes relics")
		T.eq(CleaningService.relicOre(RELIC) ~= nil, true, "the minigame has an ore of the relic's rarity")
		T.eq(CleaningService.relicOre("Nope"), nil)
	end)

	T.test("Relics: the dusty look is the relic's own shape, light on belts", function()
		for _, art in ArtifactConfig.List do
			local model = ItemBuilder.build({ Kind = "Relic", OreId = art.Id }, CFrame.new(0, 5, 0), 1)
			local parts, neon = 0, 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					if d.Material == roblox.Enum.Material.Neon then
						neon += 1
					end
				end
				T.falsy(d:IsA("Light") or d:IsA("ParticleEmitter"), art.Id .. ": no light, no particles")
			end
			T.truthy(model.PrimaryPart and model.PrimaryPart.Name == "Body", art.Id .. ": a Body")
			T.le(parts, 1 + ArtifactConfig.MaxParts, art.Id .. ": parts")
			T.eq(neon, 0, art.Id .. ": all dust, no glow")
			local light = ItemBuilder.buildLight({ Kind = "Relic", OreId = art.Id }, CFrame.new(0, 5, 0), 1)
			T.le(#light:GetDescendants() - #light:GetChildren() + #light:GetChildren(), 6, "light: 3 parts + welds")
		end
	end)

	withWorld("Relics: a rock drops a dusty relic; cleaning it puts the artifact into the collection", function(w)
		local at = Vector3.new(4, 2, -180)
		w.rolls = { 0.01, 0.5, 0.5 }
		ArtifactService.dropRelic(w.player, "Quarry", at)
		local relics = {}
		for _, record in ItemService.ownedBy(USER) do
			if record.Kind == "Relic" then
				table.insert(relics, record)
			end
		end
		T.eq(#relics, 1, "one relic item")
		local relic = relics[1]
		T.truthy(ArtifactConfig.ById[relic.OreId], "it carries a real artifact")
		T.eq(relic.Model.Name, "Relic", "the model name keeps the secret")
		T.eq(relic.Model:GetAttribute("OreId"), nil, "no artifact id attribute")
		T.eq(ArtifactConfig.uniqueCount(w.data.Artifacts), 0, "not in the collection yet")
		T.eq(w.count("Notify"), 1, "a hint where to clean it")
		ArtifactService.dropRelic(w.player, "Quarry", at)
		T.eq(w.count("Notify"), 1, "the hint is throttled")
		-- the Cleaning Station / Restoration Table cleans it
		local found = ArtifactService.cleanRelic(w.player, relic.OreId, at)
		T.truthy(found and found.New, "found")
		T.eq(ArtifactConfig.countOf(w.data.Artifacts, relic.OreId), 1, "in the collection")
		T.eq(w.count("ArtifactFound"), 1, "the find moment plays")
		T.eq(ArtifactService.cleanRelic(w.player, "Nope", at), nil, "an unknown id does nothing")
	end)

	withWorld("Relics: a relic a rescue move would store is cleaned on the way (never in the pen)", function(w)
		local before = #w.data.Storage
		T.eq(ItemService.storeDesc(w.player, { K = "Relic", O = RELIC }, nil), "Stored", "kept")
		T.eq(#w.data.Storage, before, "not in the pen")
		T.eq(ArtifactConfig.countOf(w.data.Artifacts, RELIC), 1, "in the collection")
		T.truthy(ItemService.keepRelic(w.player, RELIC, nil), "the station's path")
		T.eq(ArtifactConfig.countOf(w.data.Artifacts, RELIC), 2, "a copy counts")
	end)

	withWorld("Relics: the Restoration Table cleans a relic when its job ends", function(w)
		local base = Instance.new("Part")
		local model = Instance.new("Model")
		base.Parent = model
		model.PrimaryPart = base
		local machine: any = { Id = "RestorationTable", Owner = w.player, Model = model }
		T.truthy(ArtifactService.restorer.take(machine, { K = "Relic", O = RELIC }), "taken")
		T.eq(ArtifactConfig.countOf(w.data.Artifacts, RELIC), 1, "in the collection")
		T.falsy(ArtifactService.restorer.take(machine, { K = "Clean", O = "Coal", G = "Rough" }), "nothing else")
	end)

	withWorld("Relics: cleaned by hand at the Cleaning Station, the artifact goes into the collection", function(w)
		local SprayScoring = Loader.requirePath("ReplicatedStorage.Shared.Cleaning.SprayScoring")
		local GameConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GameConfig")
		local MachineService = Loader.requirePath("ServerScriptService.Server.Services.MachineService")
		local cleaning = CleaningService._test
		-- a station model with its vise point and output tray
		local model = Instance.new("Model")
		local base = Instance.new("Part")
		base.Name = "Base"
		base.Parent = model
		model.PrimaryPart = base
		model.Parent = Instance.new("Folder")
		for _, name in { "OrePoint", "Output" } do
			local a = Instance.new("Attachment")
			a.Name = name
			a.Parent = base
		end
		local machine: any = { Id = "CleaningStation", Owner = w.player, Model = model, State = {}, Entry = {} }
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		local ok, err = pcall(function()
			patch(MachineService, "point", function(_, name)
				local a = base:FindFirstChild(name)
				return if a then base.CFrame * a.CFrame else nil
			end)
			-- the minigame itself is tested in Cleaning.spec: here a valid run
			patch(SprayScoring, "score", function()
				return { Valid = true, Score = 0.95, Grade = "Flawless", Speed = 1, Aim = 1, Cracks = 0, Time = 9 }
			end)
			patch(SprayScoring, "fitsSession", function()
				return true
			end)
			patch(GameConfig, "CleaningMinSeconds", 0)
			patch(Loader.game:GetService("HttpService"), "GenerateGUID", function()
				return "relic-session"
			end)
			cleaning.setRandom({
				NextInteger = function(_, lo: number, _hi: number): number
					return lo + 41
				end,
			})
			local relic = ItemService.spawnDesc({ K = "Relic", O = RELIC }, USER, CFrame.new(0, 3, 0))
			relic.Model.Parent = Instance.new("Folder")
			T.truthy(cleaning.mount(machine, relic), "the relic goes into the vise")
			cleaning.start(w.player, machine)
			local begin: any = nil
			for _, r in w.replies do
				if r.Event == "CleanBegin" then
					begin = r.A
				end
			end
			T.truthy(begin, "a session starts")
			T.eq(begin.Relic, RELIC, "the client learns it is a relic")
			T.eq(begin.OreId, CleaningService.relicOre(RELIC), "the pattern of an ore of its rarity")
			local session = cleaning.session(w.player)
			cleaning.submit(w.player, session.Id, { Strokes = {} })
			local result: any = nil
			for _, r in w.replies do
				if r.Event == "CleanResult" then
					result = r.A
				end
			end
			T.truthy(result and result.Ok, "cleaned")
			T.eq(result.Relic, RELIC)
			T.eq(result.Collected, true, "into the collection")
			T.eq(relic.State, "Consumed", "the relic item is gone")
			T.eq(ArtifactConfig.countOf(w.data.Artifacts, RELIC), 1, "in the collection")
			T.eq(w.count("ArtifactFound"), 1, "the find moment plays at the station")
			for _, item in ItemService.ownedBy(USER) do
				T.falsy(item.Kind == "Clean", "no clean ore came out")
			end
		end)
		cleaning.setRandom(nil)
		for i = #saved, 1, -1 do
			rawset(saved[i][1], saved[i][2], saved[i][3])
		end
		if not ok then
			error(err, 0)
		end
	end)

	T.test("Relics: a saved Restoration Table queue keeps its relic", function()
		local data = deepCopy(DataTemplate)
		data.PlacedMachines = { { Id = "RestorationTable", X = 0, Z = 0, Rot = 0, In = { { K = "Relic", O = RELIC } } } }
		Migrations.run(data)
		local entry = data.PlacedMachines[1]
		T.truthy(entry and entry.In and entry.In[1] and entry.In[1].O == RELIC, "still in the queue")
	end)

	T.test("Relics: the pen, the train and hand loading never take a relic", function()
		local pen = fs.readFile("src/server/Services/PenService.luau")
		local train = fs.readFile("src/server/Services/TrainService.luau")
		local sell = fs.readFile("src/server/Services/SellService.luau")
		T.truthy(pen:find('if record.Kind == "Relic" then', 1, true), "the pen's intake bounces it")
		T.truthy(pen:find('return r.Kind ~= "Relic"', 1, true), "Put In leaves it in the hands")
		T.truthy(train:find("refuse(hook, record, owner, ItemData.RelicRefused)", 1, true), "the hopper refuses it")
		T.truthy(train:find('r.Kind ~= "Relic"', 1, true), "Load Train leaves it in the hands")
		T.truthy(sell:find('record.Kind == "Relic" and record.State == "Loose"', 1, true), "Tobin passes it to the guild")
	end)
end
