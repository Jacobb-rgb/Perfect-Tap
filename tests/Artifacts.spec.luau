-- Artifacts (step 7): ArtifactBuilder (every relic within its part and
-- light budget, every shape family built), MuseumBuilder (inside its yard
-- spot, the found relics on their own spots facing the visitors, plaques),
-- ArtifactService (finds straight into the collection, duplicates give
-- shards, completing a collection, ReadChapter, the museum follows the
-- owner, the lobby prompts) and the client views' pure parts
-- (CollectionView, StoryView: texts, glyphs, phone layouts).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = Loader.CFrame
	local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.BaseLayout")
	local StoryConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.StoryConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local ArtifactBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ArtifactBuilder")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local MuseumBuilder = Loader.requirePath("ServerScriptService.Server.World.MuseumBuilder")
	local PlotBuilder = Loader.requirePath("ServerScriptService.Server.World.PlotBuilder")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local ArtifactService = Loader.requirePath("ServerScriptService.Server.Services.ArtifactService")
	local CollectionView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CollectionView")
	local StoryView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.StoryView")

	local PLOT = 3

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

	local function parts(model: any): { any }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function allFound(): { [string]: any }
		local found = {}
		for _, art in ArtifactConfig.List do
			found[art.Id] = 1
		end
		return { Found = found, Chapters = {} }
	end

	---------------------------------------------------------------- ArtifactBuilder

	T.test("Artifacts: every relic builds within its budget", function()
		for _, art in ArtifactConfig.List do
			local model = ArtifactBuilder.build(art.Id, CFrame.new(10, 2, -4))
			T.truthy(model, "built " .. art.Id)
			T.eq(model:GetAttribute("ArtifactId"), art.Id)
			T.truthy(model.PrimaryPart, "a PrimaryPart for " .. art.Id)
			local list = parts(model)
			T.truthy(#list >= 3, "not empty: " .. art.Id)
			T.le(#list, ArtifactConfig.MaxParts, "parts of " .. art.Id)
			local lights, neon = 0, 0
			for _, part in list do
				T.truthy(part.Anchored, "anchored")
				T.falsy(part.CanCollide, "no collisions")
				T.falsy(part.CanTouch, "no touch")
				T.falsy(part.CanQuery, "no query")
				T.falsy(part.CastShadow, "no shadow")
				if part.Material == roblox.Enum.Material.Neon then
					neon += 1
				end
				-- it stands on its spot: nothing far below or beside it
				local offset = part.CFrame.Position - Vector3.new(10, 2, -4)
				T.truthy(offset.Y > -0.2 and offset.Y < ArtifactBuilder.Height + 0.3, "height of " .. art.Id)
				T.truthy(
					math.abs(offset.X) < ArtifactBuilder.Footprint and math.abs(offset.Z) < ArtifactBuilder.Footprint,
					"footprint of " .. art.Id
				)
			end
			for _, d in model:GetDescendants() do
				if d:IsA("Light") then
					lights += 1
				end
			end
			if art.Rarity == ArtifactConfig.LightRarity then
				T.eq(lights, 1, "the Mythic's one light")
			else
				T.eq(lights, 0, "no light on " .. art.Id)
			end
			T.eq(neon > 0, art.Glow ~= nil, "a glow part exactly when the relic glows: " .. art.Id)
			T.eq(ArtifactBuilder.partCount(art.Id), #list)
		end
		T.eq(ArtifactBuilder.build("NoSuchRelic", CFrame.new()), nil)
	end)

	T.test("Artifacts: every shape family has a 3D builder and a flat glyph", function()
		for shape in ArtifactConfig.Shapes do
			T.truthy(ArtifactBuilder.Builders[shape], "3D " .. shape)
			T.truthy(CollectionView.Glyphs[shape], "glyph " .. shape)
		end
	end)

	T.test("Artifacts: relics scale with their spot", function()
		local small = ArtifactBuilder.build("EmberCrown", CFrame.new(), 0.5)
		local big = ArtifactBuilder.build("EmberCrown", CFrame.new(), 1)
		T.near(small.PrimaryPart.Size.X * 2, big.PrimaryPart.Size.X, 1e-4)
	end)

	T.test("Artifacts: the museum's relics carry no light (a plot keeps its one light)", function()
		local mythic = ArtifactConfig.List[#ArtifactConfig.List]
		T.eq(mythic.Rarity, ArtifactConfig.LightRarity)
		local lit = ArtifactBuilder.build(mythic.Id, CFrame.new())
		local dark = ArtifactBuilder.build(mythic.Id, CFrame.new(), 1, true)
		local function lights(model: any): number
			local n = 0
			for _, d in model:GetDescendants() do
				if d:IsA("Light") then
					n += 1
				end
			end
			return n
		end
		T.eq(lights(lit), 1, "the pop-out relic keeps its light")
		T.eq(lights(dark), 0, "noLight")
		local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT])
		local museum = MuseumBuilder.build(plotCF)
		MuseumBuilder.show(museum, plotCF, allFound())
		T.eq(lights(museum), 0, "no Light object in a museum, the Mythic on show too")
		local caseLights = 0
		for _, d in museum:GetDescendants() do
			if d.Name == "CaseLight" then
				caseLights += 1
				T.eq(d.Material, roblox.Enum.Material.Neon, "a neon panel lights the case")
			end
		end
		T.eq(caseLights, #ArtifactConfig.Collections, "one per case")
		T.truthy(museum:FindFirstChild("Backdrop"), "the pale panel behind the cases")
	end)

	---------------------------------------------------------------- the odds

	T.test("Artifacts: in every zone one artifact's chance falls with its rarity", function()
		local zones = { "SomeNewFloor" }
		for zoneId in ArtifactConfig.ZoneRarity do
			table.insert(zones, zoneId)
		end
		for _, zone in WorldLayout.Zones do
			table.insert(zones, zone.Id)
		end
		for _, zoneId in zones do
			local byRarity: { [number]: number } = {}
			for _, line in ArtifactConfig.odds(zoneId) do
				local order = Rarity.get(ArtifactConfig.ById[line.Artifact].Rarity).Order
				local seen = byRarity[order]
				T.truthy(seen == nil or math.abs(seen - line.Chance) < 1e-12, "the same chance within a rarity")
				byRarity[order] = line.Chance
			end
			local last = math.huge
			for order = 1, #Rarity.List do
				local chance = byRarity[order]
				if chance then
					T.truthy(chance < last, `{zoneId}: rarity {order} is rarer per artifact than the one before`)
					last = chance
				end
			end
		end
		-- the book's "1 in N" grows with rarity: a Mythic is the hardest of all to find
		local best: { [number]: number } = {}
		for _, art in ArtifactConfig.List do
			local _, chance = CollectionView.bestZone(art.Id)
			local order = Rarity.get(art.Rarity).Order
			best[order] = math.max(best[order] or 0, chance)
		end
		local last = math.huge
		for order = 1, #Rarity.List do
			if best[order] then
				T.truthy(best[order] < last, "the best chance falls with rarity: " .. order)
				last = best[order]
			end
		end
		-- the duplicate shards follow how rare a find is
		local prev = 0
		for _, info in Rarity.List do
			local shards = ArtifactConfig.DuplicateShards[info.Id]
			if shards then
				T.truthy(shards > prev, "more shards for rarer copies")
				prev = shards
			end
		end
	end)

	---------------------------------------------------------------- MuseumBuilder

	T.test("Artifacts: the museum stays inside its yard spot and its budget", function()
		local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT])
		local museum = MuseumBuilder.build(plotCF)
		local list = parts(museum)
		T.le(#list, MuseumBuilder.MaxStructureParts, "structure parts")
		local rect = BaseLayout.Museum
		for _, part in list do
			local p = plotCF:PointToObjectSpace(part.CFrame.Position)
			T.truthy(math.abs(p.X - rect.Center.X) <= rect.Size.X / 2 + 0.5, part.Name .. " x")
			T.truthy(math.abs(p.Z - rect.Center.Z) <= rect.Size.Z / 2 + 0.5, part.Name .. " z")
			T.truthy(p.Y + part.Size.Y / 2 <= rect.Size.Y + 0.01 or part.Name == "Sign", part.Name .. " height")
			T.truthy(p.Y <= rect.Size.Y, part.Name .. " under the height budget")
		end
		local floor = museum.PrimaryPart
		T.truthy(floor and floor.Name == "Floor")
		T.truthy(floor:FindFirstChild(MuseumBuilder.PromptName), "the prompt spot")
		T.eq(#MuseumBuilder.cases(), #ArtifactConfig.Collections, "a case per collection")
	end)

	T.test("Artifacts: the museum shows exactly the found relics on their own spots", function()
		local plotCF = WorldLayout.plotCFrame(WorldLayout.Plots[PLOT])
		local museum = MuseumBuilder.build(plotCF)
		local structure = #parts(museum)
		T.eq(MuseumBuilder.show(museum, plotCF, nil), 0, "an empty museum")
		local some = { Found = { CrownCoin = 3, EmberCrown = 1, GolemCog = 1, NewerRelic = 2 }, Chapters = {} }
		T.eq(MuseumBuilder.show(museum, plotCF, some), 3, "unknown ids are skipped")
		T.eq(#museum.Pieces:GetChildren(), 3)
		local all = allFound()
		T.eq(MuseumBuilder.show(museum, plotCF, all), #ArtifactConfig.List)
		T.eq(#museum.Pieces:GetChildren(), #ArtifactConfig.List, "one model each, nothing doubled")
		T.le(#parts(museum), structure + #ArtifactConfig.List * ArtifactConfig.MaxParts, "the whole budget")
		-- every relic on its own spot, facing the visitors (+Z of the plot)
		local seen = {}
		local plusZ = plotCF:VectorToWorldSpace(Vector3.new(0, 0, 1))
		for _, art in ArtifactConfig.List do
			local spot = MuseumBuilder.spot(plotCF, art.Id)
			T.truthy(spot, "a spot for " .. art.Id)
			local key = string.format("%.2f,%.2f,%.2f", spot.Position.X, spot.Position.Y, spot.Position.Z)
			T.falsy(seen[key], "spots are unique")
			seen[key] = true
			T.truthy(spot.LookVector:Dot(plusZ) > 0.99, "faces the visitors")
		end
		-- a new owner with fewer finds: the others are taken away; no owner: empty
		T.eq(MuseumBuilder.show(museum, plotCF, some), 3)
		T.eq(#museum.Pieces:GetChildren(), 3)
		-- plaques count the finds
		local case = museum:FindFirstChild("Case1")
		local label = case.Plaque.FaceFront.Text
		T.truthy(label.Text:find("2 / 6", 1, true), "Crown: 2 of 6")
		T.eq(MuseumBuilder.show(museum, plotCF, nil), 0)
		T.truthy(label.Text:find("0 / 6", 1, true))
	end)

	T.test("Artifacts: relics fit inside their glass case", function()
		local plotCF = CFrame.new()
		for _, case in MuseumBuilder.cases() do
			local list = ArtifactConfig.ByCollection[case.Collection]
			for slot = 1, #list do
				local spot = MuseumBuilder.spotLocal(case, slot, #list)
				T.truthy(
					math.abs(spot.X - case.Center.X) + ArtifactBuilder.Footprint * MuseumBuilder.ArtifactScale / 2 <= case.Width / 2,
					"inside the case width"
				)
				T.truthy(spot.Y + ArtifactBuilder.Height * MuseumBuilder.ArtifactScale <= case.Center.Y + 2.4, "under the glass top")
			end
		end
		T.truthy(plotCF)
	end)

	---------------------------------------------------------------- ArtifactService

	local function fakePlayer(userId: number): any
		local p: any = { UserId = userId, Name = "Digger" .. userId, Parent = true, attrs = {} }
		p.GetAttribute = function(_, key: string)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key: string, value: any)
			p.attrs[key] = value
		end
		return p
	end

	local function withFinds(name: string, body: (any) -> ())
		T.test(name, function()
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			local w: any = { replies = {}, rolls = {}, changed = 0 }
			w.player = fakePlayer(911)
			w.data = deepCopy(DataTemplate)
			w.plotModel = PlotBuilder.buildPlot(Instance.new("Folder"), WorldLayout.Plots[PLOT], Rng.new(PLOT))
			w.owner = w.player
			patch(DataService, "get", function(p)
				return if p == w.player then w.data else nil
			end)
			patch(DataService, "changed", function()
				w.changed += 1
			end)
			patch(Net, "fire", function(event: string, p: any, a: any, b: any)
				table.insert(w.replies, { Event = event, Player = p, A = a, B = b })
			end)
			patch(PlotService, "plotOf", function(p)
				return if p == w.player and w.owner == w.player then PLOT else nil
			end)
			patch(PlotService, "ownerOf", function(id)
				return if id == PLOT then w.owner else nil
			end)
			patch(PlotService, "model", function(id)
				return if id == PLOT then w.plotModel else nil
			end)
			ArtifactService._test.reset()
			ArtifactService._test.setRandom(function()
				return if #w.rolls > 0 then table.remove(w.rolls, 1) else 0.5
			end)
			w.last = function(event: string): any
				for i = #w.replies, 1, -1 do
					if w.replies[i].Event == event then
						return w.replies[i]
					end
				end
				return nil
			end
			local ok, err = pcall(body, w)
			ArtifactService._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	withFinds("Artifacts: a find goes straight into the collection and tells the finder", function(w)
		local at = Vector3.new(5, -12, -170)
		local found = ArtifactService.find(w.player, "Quarry", at, "CrownCoin")
		T.truthy(found)
		T.eq(found.Artifact, "CrownCoin")
		T.eq(found.Count, 1)
		T.eq(found.New, true)
		T.eq(found.Completed, false)
		T.eq(found.Shards, nil)
		T.eq(w.data.Artifacts.Found.CrownCoin, 1)
		T.eq(w.data.Stats.ArtifactsFound, 1)
		T.truthy(w.changed >= 1, "DataService.changed")
		local reply = w.last("ArtifactFound")
		T.eq(reply.Player, w.player)
		T.eq(reply.A.Artifact, "CrownCoin")
		T.eq(reply.A.Position, at)
		T.eq(reply.A.Collection, "CrownOfKaldrum")
	end)

	withFinds("Artifacts: a duplicate gives its rarity's shards and still counts", function(w)
		ArtifactService.find(w.player, "Quarry", nil, "EmberScepter")
		w.data.Shards = 10
		local again = ArtifactService.find(w.player, "Quarry", nil, "EmberScepter")
		T.eq(again.New, false)
		T.eq(again.Count, 2)
		local shards = ArtifactConfig.DuplicateShards[ArtifactConfig.ById.EmberScepter.Rarity]
		T.eq(again.Shards, shards)
		T.eq(w.data.Shards, 10 + shards)
		T.eq(w.data.Stats.ArtifactsFound, 2, "duplicates count on the ARTIFACTS board")
	end)

	withFinds("Artifacts: the rolled artifact follows the zone's odds", function(w)
		for _, roll in { 0.0, 0.37, 0.81, 0.999 } do
			w.rolls = { roll }
			local found = ArtifactService.find(w.player, "DeepHollow", nil, nil)
			T.eq(found.Artifact, ArtifactConfig.pick("DeepHollow", roll))
		end
		-- a zone this server doesn't list uses its depth class; junk finds nothing
		w.rolls = { 0.5 }
		T.truthy(ArtifactService.find(w.player, "SomeNewFloor", nil, nil), "depth class")
		T.eq(ArtifactService.find(w.player, 42 :: any, nil, nil), nil)
		T.eq(ArtifactService.find(fakePlayer(5), "Quarry", nil, nil), nil, "no save")
		T.eq(ArtifactService.find(w.player, "Quarry", nil, "NoSuchRelic"), nil)
	end)

	withFinds("Artifacts: the last missing one completes the collection: chapter + reward", function(w)
		local list = ArtifactConfig.ByCollection.RoyalRailway
		for i = 1, #list - 1 do
			local found = ArtifactService.find(w.player, "Quarry", nil, list[i].Id)
			T.eq(found.Completed, false)
		end
		local last = ArtifactService.find(w.player, "Quarry", nil, list[#list].Id)
		T.eq(last.Completed, true)
		T.truthy(ArtifactConfig.isComplete(w.data.Artifacts, "RoyalRailway"))
		local note = w.last("Notify")
		T.truthy(note, "a toast")
		T.eq(note.A.Kind, "Reward")
		T.truthy(note.A.Text:find("Royal Conductor", 1, true), "the title")
		T.truthy(note.A.Text:find("Chapter 2", 1, true), "the chapter")
		-- a later copy completes nothing again
		local copy = ArtifactService.find(w.player, "Quarry", nil, list[1].Id)
		T.eq(copy.Completed, false)
	end)

	withFinds("Artifacts: ReadChapter only for completed collections", function(w)
		local ok, reason = ArtifactService.readChapter(w.player, "CrownOfKaldrum")
		T.eq(ok, false)
		T.eq(reason, "NotComplete")
		T.eq(select(2, ArtifactService.readChapter(w.player, "Nope")), "BadCollection")
		T.eq(select(2, ArtifactService.readChapter(w.player, 7)), "BadCollection")
		for _, art in ArtifactConfig.ByCollection.CrownOfKaldrum do
			ArtifactService.find(w.player, "Quarry", nil, art.Id)
		end
		ArtifactService._test.action(w.player, "ReadChapter", { Collection = "CrownOfKaldrum" })
		local reply = w.last("ActionResult")
		T.eq(reply.A.Action, "Artifact")
		T.eq(reply.A.Op, "ReadChapter")
		T.eq(reply.A.Ok, true)
		T.eq(reply.A.Id, "CrownOfKaldrum")
		T.eq(w.data.Artifacts.Chapters.CrownOfKaldrum, true)
		-- junk is dropped without an answer
		local before = #w.replies
		ArtifactService._test.action(w.player, "Grant", { Collection = "CrownOfKaldrum" })
		T.eq(#w.replies, before)
		ArtifactService._test.action(w.player, "ReadChapter", "CrownOfKaldrum")
		T.eq(w.last("ActionResult").A.Reason, "BadCollection")
		for reasonId in { NotComplete = true, BadCollection = true } do
			T.truthy(ArtifactConfig.Reasons[reasonId], "a Reasons code")
		end
	end)

	withFinds("Artifacts: the base museum follows its owner's finds", function(w)
		T.truthy(ArtifactService._test.setupPlot(PLOT), "museum built")
		T.truthy(ArtifactService._test.setupPlot(PLOT), "only once")
		local museums = 0
		for _, child in w.plotModel.Yard:GetChildren() do
			if child.Name == MuseumBuilder.Name then
				museums += 1
			end
		end
		T.eq(museums, 1)
		local museum = ArtifactService._test.museumOf(PLOT)
		local prompt = museum.PrimaryPart:FindFirstChild("BookPoint")
		T.truthy(prompt and prompt:FindFirstChild("Prompt"), "Collection Book prompt")
		T.eq(prompt.Prompt.ActionText, "Collection Book")
		T.eq(prompt.Prompt.ObjectText, "Your Collection", "it opens the viewer's own book")
		T.eq(prompt.Prompt.RequiresLineOfSight, true, "not through the back wall from the pen")
		ArtifactService.find(w.player, "Quarry", nil, "GolemCog")
		T.eq(#museum.Pieces:GetChildren(), 1, "a new find shows up at home")
		ArtifactService.find(w.player, "Quarry", nil, "GolemCog")
		T.eq(#museum.Pieces:GetChildren(), 1, "a copy adds nothing")
		w.owner = nil
		T.eq(ArtifactService.refreshMuseum(PLOT), 0, "a freed plot is empty")
	end)

	withFinds("Artifacts: a completed collection's title and podium skin show (Equip picks one)", function(w)
		local railway = ArtifactConfig.CollectionById.RoyalRailway
		T.eq(ArtifactService.applyRewards(w.player), nil, "nothing completed: nothing shows")
		T.eq(w.player:GetAttribute("Title"), nil)
		-- not complete yet: refused
		local ok, reason = ArtifactService.equip(w.player, "RoyalRailway")
		T.eq(ok, false)
		T.eq(reason, "NotComplete")
		T.eq(select(2, ArtifactService.equip(w.player, "Nope")), "BadCollection")
		T.eq(select(2, ArtifactService.equip(w.player, 5)), "BadCollection")
		-- completing it puts its title and skin on at once (the last completed one)
		for _, art in ArtifactConfig.ByCollection.RoyalRailway do
			ArtifactService.find(w.player, "Quarry", nil, art.Id)
		end
		T.eq(w.player:GetAttribute("Title"), railway.Reward.Title)
		T.eq(w.player:GetAttribute("PodiumSkin"), railway.Reward.PodiumSkin)
		T.eq(w.plotModel:GetAttribute("PodiumSkin"), railway.Reward.PodiumSkin)
		local skin = ArtifactConfig.PodiumSkins[railway.Reward.PodiumSkin]
		local podium = w.plotModel.Yard.Podium1
		T.eq(podium.Base.Color, skin.Base, "the podium in the skin's colors")
		T.eq(podium.Top.Color, skin.Trim)
		T.truthy(podium.Rim.Color ~= skin.Base and podium.Rim:GetAttribute("SkinFrom") == nil, "the Rim stays PodiumService's")
		for _, child in podium:GetChildren() do
			if child.Name == "HoloRing" then
				T.eq(child.Color, skin.Glow, "the holo-ring glows in the skin")
			end
		end
		-- a second completed collection: the newest shows, Equip picks the other back
		for _, art in ArtifactConfig.ByCollection.CrownOfKaldrum do
			ArtifactService.find(w.player, "Quarry", nil, art.Id)
		end
		local crown = ArtifactConfig.CollectionById.CrownOfKaldrum
		T.eq(w.player:GetAttribute("Title"), railway.Reward.Title, "the last completed in collection order is the Railway")
		ArtifactService._test.action(w.player, "Equip", { Collection = "CrownOfKaldrum" })
		local reply = w.last("ActionResult")
		T.eq(reply.A.Op, "Equip")
		T.eq(reply.A.Ok, true)
		T.eq(w.data.Artifacts.Equipped, "CrownOfKaldrum")
		T.eq(w.player:GetAttribute("Title"), crown.Reward.Title)
		T.eq(podium.Base.Color, ArtifactConfig.PodiumSkins[crown.Reward.PodiumSkin].Base)
		-- "" takes them off: the podiums get their own colors back
		local before = podium.Column:GetAttribute("SkinFrom")
		T.truthy(before, "the own color is kept while a skin is on")
		ArtifactService._test.action(w.player, "Equip", { Collection = "" })
		T.eq(w.player:GetAttribute("Title"), nil)
		T.eq(w.plotModel:GetAttribute("PodiumSkin"), nil)
		T.eq(podium.Column.Color, before, "its own color back")
		T.eq(podium.Column:GetAttribute("SkinFrom"), nil)
		T.eq(ArtifactConfig.equipped(w.data.Artifacts), nil)
		-- a freed plot gets its own colors back too
		ArtifactService._test.action(w.player, "Equip", { Collection = "RoyalRailway" })
		T.truthy(ArtifactService.paintPodiums(PLOT, nil) > -1)
		T.eq(podium.Column.Color, before)
		-- the reward toast promises only what the game gives
		local text = ArtifactService.completedText("RoyalRailway")
		T.truthy(text:find(railway.Reward.Title, 1, true) and text:find(skin.Name, 1, true), "title and skin")
	end)

	withFinds("Artifacts: the FOSSIL DIG and the Guild board get their prompts", function(w)
		local dig = Instance.new("Model")
		local bed = Instance.new("Part")
		bed.Name = "Bed"
		bed.Size = Vector3.new(20, 0.2, 24)
		bed.Parent = dig
		dig.PrimaryPart = bed
		ArtifactService._test.hookDig(dig)
		ArtifactService._test.hookDig(dig)
		T.eq(bed.BookPoint.Prompt.ActionText, "Collection Book")
		T.eq(bed.StoryPoint.Prompt.ActionText, "Read Journal")
		T.truthy(bed.BookPoint.Prompt:HasTag(ArtifactService.PromptTag))
		local board = Instance.new("Model")
		local plate = Instance.new("Part")
		plate.Name = "Board"
		plate.Size = Vector3.new(7, 3.6, 0.4)
		plate.Parent = board
		board.PrimaryPart = plate
		ArtifactService._test.hookBoard(board)
		T.eq(plate.StoryPoint.Prompt.ActionText, "Read Journal")
		T.truthy(w)
	end)

	---------------------------------------------------------------- CollectionView / StoryView (pure)

	T.test("Artifacts: book texts (progress, chapter button, reward, where)", function()
		local some = { Found = { CrownCoin = 2, RoyalSeal = 1 }, Chapters = {} }
		local found, total = CollectionView.progress(some, "CrownOfKaldrum")
		T.eq(found, 2)
		T.eq(total, 6)
		local text, enabled = CollectionView.chapterButton(some, "CrownOfKaldrum")
		T.falsy(enabled)
		T.truthy(text:find("UNLOCK CHAPTER 1", 1, true))
		local all = allFound()
		local text2, enabled2 = CollectionView.chapterButton(all, "CrownOfKaldrum")
		T.truthy(enabled2)
		T.eq(text2, "READ CHAPTER 1")
		T.truthy(CollectionView.chapterNew(all, "CrownOfKaldrum"))
		all.Chapters.CrownOfKaldrum = true
		T.falsy(CollectionView.chapterNew(all, "CrownOfKaldrum"))
		T.falsy(CollectionView.chapterNew(some, "CrownOfKaldrum"))
		T.truthy(CollectionView.rewardText("CrownOfKaldrum"):find("Heir of Kaldrum", 1, true))
		-- the chance per rock in the best zone, exact
		for _, art in ArtifactConfig.List do
			local zone, chance = CollectionView.bestZone(art.Id)
			T.truthy(zone, "a zone for " .. art.Id)
			local share = 0
			for _, line in ArtifactConfig.odds(zone) do
				if line.Artifact == art.Id then
					share = line.Chance
				end
			end
			T.near(chance, ArtifactConfig.rockChance(zone) * share, 1e-12)
			T.truthy(CollectionView.whereText(art.Id):find("1 in", 1, true))
		end
		local mythicZone = CollectionView.bestZone("HeartstoneFragment")
		T.eq(mythicZone, "DeepHollow", "the Mythic only deep down")
	end)

	T.test("Artifacts: long tile names shrink to two lines", function()
		T.eq(CollectionView.fitSize("Golem Cog", 16, 150), 16, "short names keep their size")
		local size = CollectionView.fitSize("Queen's Amethyst Brooch", 16, 150)
		T.truthy(size < 16 and size >= math.floor(16 * 0.7), "a long name shrinks a little")
		for _, art in ArtifactConfig.List do
			T.truthy(CollectionView.fitSize(art.Name, 18, 120) >= 12, "readable: " .. art.Id)
		end
	end)

	T.test("Artifacts: the found card's texts", function()
		local fresh = { Found = { RailLantern = 1 }, Chapters = {} }
		local title, progress, extra = CollectionView.revealText({ Artifact = "RailLantern", New = true }, fresh)
		T.eq(title, "NEW ARTIFACT!")
		T.truthy(progress:find("1 / 6", 1, true))
		T.eq(extra, "")
		local title2, _, extra2 = CollectionView.revealText({ Artifact = "RailLantern", New = false, Shards = 2 }, fresh)
		T.eq(title2, "ARTIFACT FOUND!")
		T.truthy(extra2:find("+2 Shards", 1, true))
		local title3, _, extra3 = CollectionView.revealText({ Artifact = "EmberCrown", New = true, Completed = true }, allFound())
		T.eq(title3, "COLLECTION COMPLETE!")
		T.truthy(extra3:find("Chapter 1", 1, true))
		-- the State push with the find hasn't arrived yet: the find still counts
		local stale = allFound()
		stale.Found.EmberCrown = nil
		local _, progress4 = CollectionView.revealText({ Artifact = "EmberCrown", New = true, Completed = true }, stale)
		T.truthy(progress4:find("6 / 6", 1, true), "not 5 / 6 under COLLECTION COMPLETE")
		local _, progress5 = CollectionView.revealText({ Artifact = "RailLantern", New = true }, { Found = {}, Chapters = {} })
		T.truthy(progress5:find("1 / 6", 1, true))
		-- a copy is a toast
		T.eq(CollectionView.copyText({ Artifact = "GolemCog", Shards = 1 }), "Golem Cog (copy) +1 Shard")
		T.eq(CollectionView.copyText({ Artifact = "GolemCog", Shards = 4 }), "Golem Cog (copy) +4 Shards")
		T.eq(CollectionView.copyText({ Artifact = "GolemCog" }), "Golem Cog (copy)")
	end)

	T.test("Artifacts: the NEW ARTIFACT! banner is small, not modal, clear of the controls", function()
		local screens = {
			{ Compact = true, Scale = 0.62, W = 568 / 0.62, H = (320 - 58) / 0.62 },
			{ Compact = false, Scale = 1, W = 1280, H = 684 },
		}
		for _, screen in screens do
			local banner = CollectionView.buildBanner(screen.Compact)
			CollectionView.showBanner(banner, { Artifact = "QueensBrooch", New = true }, { Found = {}, Chapters = {} })
			T.truthy(banner.Gui.Enabled)
			T.eq(banner.Name.Text, "Queen's Amethyst Brooch")
			T.eq(banner.Progress.Text, "1 / 6 found", "counts the find before the State push")
			local card = banner.Card
			T.falsy(card.Active, "not modal")
			T.falsy(banner.Book.Selectable, "never takes a gamepad selection")
			local w, h = card.Size.X.Offset, card.Size.Y.Offset
			T.truthy(w <= screen.W * 0.6, "small: at most 60 % of the width")
			T.truthy(card.Position.Y.Offset >= 96, "under the coins panel")
			-- the bottom 40 % of the screen (thumbstick, jump, carry slots) stays free
			T.truthy(card.Position.Y.Offset + h <= screen.H * 0.6, "clear of the thumbstick and jump areas")
			if screen.Compact then
				T.truthy(banner.Book.Parent.Size.Y.Offset * screen.Scale >= 44, "BOOK is 44 pt")
			end
			CollectionView.setBannerKeys(banner, "rbxasset://a.png", "Book", "rbxasset://b.png", "Close")
			T.truthy(banner.BookGlyph.Visible and banner.CloseGlyph.Visible)
			CollectionView.setBannerKeys(banner, "", "", "", "")
			T.falsy(banner.Keys.Visible, "touch: no key row")
		end
	end)

	T.test("Artifacts: the HUD's BOOK button, its NEW badge and the title board", function()
		local menu = Instance.new("Frame")
		local m = CollectionView.menuButton(menu)
		T.eq(m.Button.Parent.Parent, menu)
		T.falsy(CollectionView.anyChapterNew({ Found = {}, Chapters = {} }))
		local all = allFound()
		T.truthy(CollectionView.anyChapterNew(all), "a completed chapter waits")
		for _, collection in ArtifactConfig.Collections do
			all.Chapters[collection.Id] = true
		end
		T.falsy(CollectionView.anyChapterNew(all), "all read")
		local board = CollectionView.titleBoard("Heir of Kaldrum")
		T.eq(board.ClassName, "BillboardGui")
		T.truthy(board.Text.Text:find("Heir of Kaldrum", 1, true))
		T.truthy(board.MaxDistance > 0 and board.MaxDistance <= 100, "only near players")
	end)

	T.test("Artifacts: the book's USE button and the scrolling detail text", function()
		local refs = CollectionView.build(true)
		CollectionView.layout(refs, 568 / 0.62, (320 - 58) / 0.62)
		refs.Collection = "CrownOfKaldrum"
		refs.Selected = "EmberCrown"
		CollectionView.fill(refs, { Found = { CrownCoin = 1 }, Chapters = {} })
		T.falsy(refs.Use.Parent.Visible, "not before the collection is complete")
		local all = allFound()
		CollectionView.fill(refs, all)
		T.truthy(refs.Use.Parent.Visible)
		T.eq(refs.Use.Text, "USE TITLE + SKIN")
		T.eq(refs.Use:GetAttribute("Equip"), "CrownOfKaldrum")
		all.Equipped = "CrownOfKaldrum"
		CollectionView.fill(refs, all)
		T.eq(refs.Use.Text, "IN USE ✓")
		T.eq(refs.Use:GetAttribute("Equip"), "", "a press takes it off")
		-- the last completed collection shows by itself (nothing picked)
		all.Equipped = nil
		T.truthy(CollectionView.inUse(all, ArtifactConfig.Collections[#ArtifactConfig.Collections].Id))
		-- a small phone scrolls the detail text instead of dropping the lore
		T.truthy(refs.DetailLore.Visible and refs.DetailCount.Visible, "nothing dropped")
		T.eq(refs.DetailLore.Text, ArtifactConfig.ById.EmberCrown.Lore)
		local body = refs.DetailBody
		T.truthy(body.CanvasSize.Y.Offset > body.Size.Y.Offset, "it scrolls on a small phone")
		T.truthy(refs.DetailWhere.Position.Y.Offset >= refs.DetailLore.Position.Y.Offset + refs.DetailLore.Size.Y.Offset, "where under the lore")
		-- the footer: reward, USE and the chapter button side by side, inside the panel
		local footer = refs.Footer.Size.X.Offset
		local used = refs.Reward.Size.X.Offset + refs.Use.Parent.Size.X.Offset + refs.Chapter.Parent.Size.X.Offset
		T.truthy(used <= footer, "the footer fits")
		T.truthy(refs.Use.Parent.Size.Y.Offset * 0.62 >= 44, "USE is 44 pt")
		T.truthy(refs.Reward.TextSize >= 12, "the reward stays readable")
		-- the journal is one tap away (the Prologue is always open), above the detail column
		local journal = refs.Journal.Parent
		T.truthy(journal.Size.Y.Offset * 0.62 >= 44, "JOURNAL is 44 pt")
		local panelW = refs.Panel.Size.X.Offset
		local journalLeft = panelW + journal.Position.X.Offset - journal.Size.X.Offset
		T.truthy(journalLeft >= refs.Detail.Position.X.Offset - 1, "over the detail column, not the tiles")
		T.truthy(journal.Position.Y.Offset + journal.Size.Y.Offset <= refs.Detail.Position.Y.Offset, "above it")
		local totalRight = panelW + refs.Total.Position.X.Offset
		T.truthy(totalRight <= journalLeft, "the count left of JOURNAL")
	end)

	T.test("Artifacts: glyphs draw every relic, silhouettes hide the colors", function()
		local box = Instance.new("Frame")
		for _, art in ArtifactConfig.List do
			CollectionView.glyph(box, art.Id, false)
			local pieces = 0
			for _, child in box:GetChildren() do
				if child:IsA("Frame") then
					pieces += 1
				end
			end
			T.truthy(pieces >= 3, "a glyph for " .. art.Id)
			CollectionView.glyph(box, art.Id, true)
			for _, child in box:GetChildren() do
				if child:IsA("Frame") then
					T.eq(child.BackgroundColor3, CollectionView.SilhouetteColor, "silhouette")
				end
			end
			T.truthy(box:FindFirstChild("Unknown"), "a ? on the silhouette")
		end
	end)

	T.test("Artifacts: the book and the journal fit phones, 44 pt to tap", function()
		local screens = {
			{ Compact = true, Scale = 0.62, W = 568 / 0.62, H = (320 - 58) / 0.62 },
			{ Compact = true, Scale = 0.62, W = 667 / 0.62, H = (375 - 58) / 0.62 },
			{ Compact = false, Scale = 1.25, W = 1920 / 1.25, H = (1080 - 36) / 1.25 },
		}
		for _, screen in screens do
			local book = CollectionView.build(screen.Compact)
			CollectionView.layout(book, screen.W, screen.H)
			CollectionView.fill(book, allFound())
			local size = book.Panel.Size
			T.truthy(size.X.Offset <= screen.W and size.Y.Offset <= screen.H, "the book fits")
			local detail = book.Detail
			T.truthy(detail.Position.X.Offset + detail.Size.X.Offset <= size.X.Offset, "the detail column fits")
			T.truthy(
				detail.Position.Y.Offset >= book.Close.Parent.Position.Y.Offset + book.Close.Parent.Size.Y.Offset - 1,
				"not under the X"
			)
			if screen.Compact and screen.Scale <= 0.62 then
				for _, button in book.TabList do
					T.truthy(button.Parent.Size.Y.Offset * screen.Scale >= 43.9, "a tab is 44 pt")
				end
				T.truthy(book.Chapter.Parent.Size.Y.Offset * screen.Scale >= 44, "the chapter button")
				local cell = book.Grid:FindFirstChildOfClass("UIGridLayout").CellSize
				T.truthy(cell.Y.Offset * screen.Scale >= 44 and cell.X.Offset * screen.Scale >= 44, "a tile is 44 pt")
			end
			local journal = StoryView.build(screen.Compact)
			StoryView.layout(journal, screen.W, screen.H)
			local jsize = journal.Panel.Size
			T.truthy(jsize.X.Offset <= screen.W and jsize.Y.Offset <= screen.H, "the journal fits")
			T.truthy(
				journal.Page.Position.Y.Offset >= journal.Close.Parent.Position.Y.Offset + journal.Close.Parent.Size.Y.Offset - 1,
				"the page is not under the X"
			)
			local reveal = CollectionView.buildReveal(screen.Compact)
			local fit = CollectionView.fitReveal(reveal, screen.W, screen.H)
			T.truthy(reveal.Card.Size.Y.Offset * fit <= screen.H, "the found card fits")
			T.truthy(reveal.Card.Size.X.Offset * fit <= screen.W)
			if screen.Compact and screen.Scale <= 0.62 then
				T.truthy(reveal.Ok.Parent.Size.Y.Offset * fit * screen.Scale >= 40, "OK stays big enough to tap")
			end
		end
	end)

	T.test("Artifacts: the journal's chapters open with their collections", function()
		local entries = StoryView.entries(nil)
		T.eq(#entries, 1 + #StoryConfig.Chapters)
		T.eq(entries[1].Key, StoryView.PrologueKey)
		T.truthy(entries[1].Unlocked, "the Prologue is always open")
		for i = 2, #entries do
			T.falsy(entries[i].Unlocked, "locked without finds")
			T.truthy(#entries[i].Locked > 0, "says what unlocks it")
			T.falsy(entries[i].New)
		end
		local all = allFound()
		all.Chapters.RoyalRailway = true
		local open = StoryView.entries(all)
		for i = 2, #open do
			T.truthy(open[i].Unlocked)
			T.eq(open[i].New, open[i].Key ~= "RoyalRailway", "NEW until read")
		end
		-- pages clamp, PREV / NEXT only where there is a page
		local refs = StoryView.build(false)
		local crown = StoryView.entry(open, "CrownOfKaldrum")
		StoryView.showPage(refs, crown, 99)
		T.eq(refs.PageIndex, #crown.Pages)
		T.falsy(refs.Next.Parent.Visible)
		T.truthy(refs.Prev.Parent.Visible)
		StoryView.showPage(refs, crown, 1)
		T.falsy(refs.Prev.Parent.Visible)
		T.eq(refs.Text.Text, crown.Pages[1].Text)
		local locked = StoryView.entry(entries, "Golemworks")
		StoryView.showPage(refs, locked, 1)
		T.eq(refs.Text.Text, locked.Locked)
		T.falsy(refs.Next.Parent.Visible)
	end)
end
