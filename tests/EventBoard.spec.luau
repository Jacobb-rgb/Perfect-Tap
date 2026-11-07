--[[
	The big iron billboard (owner 2026-11-07) and the Find of the Day on it:
	which find wins, what crosses servers, the pages, the iron itself.
]]

return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local FindOfDay = Loader.requirePath("ReplicatedStorage.Shared.Events.FindOfDay")
	local EventBoardLogic = Loader.requirePath("ReplicatedStorage.Shared.Events.EventBoardLogic")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local FindOfDayService = Loader.requirePath("ServerScriptService.Server.Services.FindOfDayService")
	local EventBoard = Loader.requirePath("ServerScriptService.Server.World.Lobby.Plaza.EventBoard")
	local EventBoardView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EventBoardView")

	local NOW = 1_794_000_000
	local TODAY = FindOfDay.day(NOW)

	local function entry(name: string, ore: string, grade: string, day: number?): any
		return { Day = day or TODAY, Name = name, Ore = ore, Grade = grade }
	end

	T.test("find of the day: the rarest ore wins, then the grade, the first keeps a tie", function()
		T.truthy(FindOfDay.rank("Gold", "Rough") > FindOfDay.rank("Silver", "Flawless"), "the ore first")
		T.truthy(FindOfDay.rank("Gold", "Flawless") > FindOfDay.rank("Gold", "Pristine"), "then the grade")
		T.truthy(FindOfDay.rank("FrostflameCrystal", "Flawless") > FindOfDay.rank("Heartstone", "Flawless"), "a secret above all")
		T.truthy(FindOfDay.rank("RainbowNova", "Flawless") > FindOfDay.rank("HollowEye", "Flawless"), "the rarer secret")
		T.eq(FindOfDay.rank("Nope", "Flawless"), 0)
		T.eq(FindOfDay.rank(nil, nil), 0)
		T.truthy(FindOfDay.better(entry("A", "Coal", "Rough"), nil, TODAY), "the first of the day")
		T.truthy(FindOfDay.better(entry("B", "Gold", "Rough"), entry("A", "Coal", "Rough"), TODAY))
		T.falsy(FindOfDay.better(entry("B", "Coal", "Rough"), entry("A", "Coal", "Rough"), TODAY), "a tie: the first stays")
		T.falsy(FindOfDay.better(entry("B", "Coal", "Rough"), entry("A", "Gold", "Rough"), TODAY))
		T.truthy(
			FindOfDay.better(entry("B", "Coal", "Rough"), entry("A", "RainbowNova", "Flawless", TODAY - 1), TODAY),
			"yesterday's doesn't count"
		)
		T.falsy(FindOfDay.better(entry("B", "RainbowNova", "Flawless", TODAY - 1), nil, TODAY), "nor a late message of yesterday")
	end)

	T.test("find of the day: anything broken from a store or a message is refused", function()
		T.truthy(FindOfDay.read(entry("Mia", "Gold", "Clean")), "a good one")
		for _, junk in
			{
				"junk",
				5,
				{},
				entry("", "Gold", "Clean"),
				entry(string.rep("x", 21), "Gold", "Clean"),
				entry("Mia", "Nope", "Clean"),
				{ Day = 0 / 0, Name = "Mia", Ore = "Gold", Grade = "Clean" },
				{ Day = 1.5, Name = "Mia", Ore = "Gold", Grade = "Clean" },
				{ Day = TODAY, Name = 7, Ore = "Gold", Grade = "Clean" },
				{ Day = TODAY, Name = "Mia", Ore = "Gold" },
			}
		do
			T.eq(FindOfDay.read(junk), nil)
		end
		T.truthy(FindOfDay.read(entry(string.rep("é", 20), "Gold", "Clean")), "20 characters, not bytes")
	end)

	local function service(): any
		local w: any = { published = {}, stored = nil, now = NOW, attrs = {} }
		local saved = {
			clock = FindOfDayService.clock,
			publish = FindOfDayService.publish,
			update = FindOfDayService.update,
			read = FindOfDayService.read,
			setAttribute = FindOfDayService.setAttribute,
		}
		FindOfDayService.setAttribute = function(name, value)
			w.attrs[name] = value
		end
		FindOfDayService.clock = function()
			return w.now
		end
		FindOfDayService.publish = function(e)
			table.insert(w.published, e)
		end
		FindOfDayService.update = function(_, merge)
			w.stored = merge(w.stored)
			return w.stored
		end
		FindOfDayService.read = function()
			return w.stored
		end
		FindOfDayService.reset()
		function w.done()
			FindOfDayService.reset()
			for key, value in saved do
				FindOfDayService[key] = value
			end
		end
		return w
	end

	local function guarded(w: any, fn: () -> ())
		local ok, err = pcall(fn)
		w.done()
		if not ok then
			error(err, 0)
		end
	end

	T.test("find of the day service: a better find shows at once, goes out once, the better of two stays", function()
		local w = service()
		guarded(w, function()
			local mia = { DisplayName = "Mia" }
			local leo = { DisplayName = "Leo" }
			FindOfDayService.report(mia, "Gold", "Clean")
			T.eq(FindOfDayService.current().Name, "Mia")
			T.eq(w.attrs.FindOfDayName, "Mia", "the clients see it")
			T.eq(w.attrs.FindOfDayOre, "Gold")
			T.truthy(FindOfDayService.isDirty())
			FindOfDayService.report(leo, "Copper", "Flawless")
			T.eq(FindOfDayService.current().Name, "Mia", "a worse one changes nothing")
			FindOfDayService.report(leo, "Nope", "Flawless")
			T.eq(FindOfDayService.current().Name, "Mia", "an unknown ore neither")
			FindOfDayService.save()
			T.eq(#w.published, 1, "one message")
			T.eq(w.stored.Name, "Mia")
			T.falsy(FindOfDayService.isDirty())
			FindOfDayService.save()
			T.eq(#w.published, 1, "nothing new, no message")
			-- another server stored a better one meanwhile
			w.stored = entry("Far", "Heartstone", "Flawless")
			FindOfDayService.report(leo, "Sapphire", "Clean")
			FindOfDayService.save()
			T.eq(w.stored.Name, "Far", "the store keeps the better")
			T.eq(#w.published, 1, "and ours isn't announced")
			T.eq(FindOfDayService.current().Name, "Far", "this server takes it")
			-- a message
			FindOfDayService.receive({ Data = entry("Nova", "RainbowNova", "Flawless") })
			T.eq(FindOfDayService.current().Name, "Nova")
			FindOfDayService.receive({ Data = "junk" })
			FindOfDayService.receive("junk")
			T.eq(FindOfDayService.current().Name, "Nova")
			T.falsy(FindOfDayService.isDirty(), "another server's find isn't saved again")
		end)
	end)

	T.test("find of the day service: a new day starts empty, a late server reads the store", function()
		local w = service()
		guarded(w, function()
			FindOfDayService.report({ DisplayName = "Mia" }, "Gold", "Clean")
			T.falsy(FindOfDayService.rollOver(), "same day")
			w.now = NOW + 86400
			T.eq(FindOfDayService.current(), nil, "not yesterday's")
			T.truthy(FindOfDayService.rollOver())
			T.eq(w.attrs.FindOfDayName, nil, "gone from the board")
			w.stored = entry("Leo", "Coal", "Rough", FindOfDay.day(w.now))
			FindOfDayService.refresh()
			T.eq(FindOfDayService.current().Name, "Leo")
			w.stored = "junk"
			FindOfDayService.refresh()
			T.eq(FindOfDayService.current().Name, "Leo", "junk changes nothing")
		end)
	end)

	T.test("event board: its pages rotate with the server's time, the weather counts down", function()
		T.eq(EventBoardLogic.clock(252), "4:12")
		T.eq(EventBoardLogic.clock(3700), "1:01:40")
		T.eq(EventBoardLogic.clock(-5), "0:00")
		local a, b = { Id = "A" }, { Id = "B" }
		local seconds = EventBoardLogic.PageSeconds
		T.eq(EventBoardLogic.pageAt(0, { a, b }).Id, "A")
		T.eq(EventBoardLogic.pageAt(seconds - 0.01, { a, b }).Id, "A")
		T.eq(EventBoardLogic.pageAt(seconds, { a, b }).Id, "B")
		T.eq(EventBoardLogic.pageAt(seconds * 2, { a, b }).Id, "A")
		local pages = EventBoardLogic.pages(NOW, nil, nil)
		T.eq(#pages, 2)
		T.eq(pages[1].Id, "Find")
		T.eq(pages[2].Id, "Weather")
		local storm = EventBoardLogic.weatherPage(NOW, "Storm")
		T.truthy(storm.Big:find("Storm", 1, true) ~= nil, storm.Big)
		-- the weather's bonus stands under it (owner 2026-11-07: WeatherBonus)
		local WeatherBonus = Loader.requirePath("ReplicatedStorage.Shared.Weather.WeatherBonus")
		T.eq(storm.Small, WeatherBonus.List.Storm.Text)
		T.eq(storm.BigColor, WeatherBonus.List.Storm.Color)
		for kind, bonus in WeatherBonus.List do
			local page = EventBoardLogic.weatherPage(NOW, kind)
			T.eq(page.Small, bonus.Text, kind)
			T.truthy(page.Big:find(kind, 1, true) == 1, page.Big)
		end
		T.eq(EventBoardLogic.weatherPage(NOW, "Rainbow").Big, "Rainbow", "a forced rainbow has no end to count down")
		T.truthy(EventBoardLogic.weatherPage(NOW, "Clear").Big == "Clear skies")
		local after = EventBoardLogic.nextWeather(NOW)
		T.truthy(after and after.Start > NOW, "the next event is ahead")
	end)

	T.test("event board: the find's page names the finder and the ore, an old one is gone", function()
		local page = EventBoardLogic.findPage(entry("EmberQueen", "PhoenixFeather", "Flawless"), NOW)
		T.eq(page.Title, "FIND OF THE DAY")
		T.eq(page.Big, "EmberQueen")
		T.eq(page.Small, "Phoenix Feather · Mythic · Flawless")
		T.eq(EventBoardLogic.findPage(nil, NOW).Big, "Nobody yet")
		T.eq(EventBoardLogic.findPage(entry("Old", "Gold", "Clean", TODAY - 1), NOW).Big, "Nobody yet")
	end)

	T.test("event board: its two feet stand clear of everything and beside the road", function()
		local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
		local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local board = map:FindFirstChild("EventBoard", true)
		local frame = LobbyLayout.frame(LobbyLayout.get("EventBoard"))
		local parts = {}
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and not d:IsDescendantOf(board) and d.Size.Magnitude < 400 then
				table.insert(parts, d)
			end
		end
		for _, side in { -EventBoard.PostAt, EventBoard.PostAt } do
			for _, y in { 0.45, 1, 3, 6, 10 } do
				local half = if y < 0.5 then EventBoard.FootSize / 2 else 1.4 -- the low concrete foot, then the beam
				for _, dx in { -half, 0, half } do
					for _, dz in { -half, 0, half } do
						local at = (frame * roblox.CFrame.new(side + dx, y, 0.6 + dz)).Position
						for _, d in parts do
							local l = d.CFrame:PointToObjectSpace(at)
							local inside = math.abs(l.X) <= d.Size.X / 2 and math.abs(l.Y) <= d.Size.Y / 2 and math.abs(l.Z) <= d.Size.Z / 2
							T.falsy(inside, `the foot at {side} stands in {d:GetFullName()} at {d.CFrame.Position} size {d.Size}`)
						end
						for _, road in WorldLayout.Roads do
							T.truthy(LobbyLayout.distanceToStrip(road.From, road.To, road.Width, at) > 0, "off the road")
						end
					end
				end
			end
		end
	end)

	T.test("event board: the iron stays in budget, its one screen faces the plaza, players walk under it", function()
		local folder = roblox.Instance.new("Folder")
		local model = EventBoard.build(folder)
		local screens, parts = {}, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d:HasTag("EventBoardScreen") then
					table.insert(screens, d)
				end
				local top = d.CFrame.Position.Y + d.Size.Y / 2
				local bottom = d.CFrame.Position.Y - d.Size.Y / 2
				local z = LobbyLayout.frame(LobbyLayout.get("EventBoard")):PointToObjectSpace(d.CFrame.Position).X
				if math.abs(z) < 4 and d.Size.X < 12 then
					T.truthy(bottom >= 3 or top <= 0.01, d.Name .. ": nothing to walk into over the road")
				end
			end
		end
		T.truthy(parts <= EventBoard.MaxParts, `{parts} parts`)
		T.eq(#screens, 1, "one screen")
		T.truthy(model:HasTag("NoStuds"), "iron, no studs")
		local facing = LobbyLayout.get("EventBoard").Facing.Unit
		T.truthy(screens[1].CFrame.LookVector:Dot(facing) > 0.99, "its Front face looks where the piece faces")
		local refs = EventBoardView.build(screens[1])
		EventBoardView.fill(refs, EventBoardLogic.findPage(entry("Mia", "Gold", "Clean"), NOW))
		T.eq(refs.Big.Text, "Mia")
		T.eq(refs.Gui.LightInfluence, 0, "readable at night")
		T.truthy(refs.Gui.MaxDistance > 0, "far away it doesn't draw")
		folder:Destroy()
	end)
end
