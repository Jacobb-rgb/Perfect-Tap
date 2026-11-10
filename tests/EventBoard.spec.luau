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

	local USERS = { Mia = 41, Leo = 42, Far = 43, Nova = 44, EmberQueen = 45, Old = 46, A = 47, B = 48 }
	local function entry(name: string, ore: string, grade: string, day: number?): any
		return { Day = day or TODAY, UserId = USERS[name] or 99, Name = name, Ore = ore, Grade = grade }
	end
	local function player(name: string): any
		return { DisplayName = name, UserId = USERS[name] or 99 }
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
				{ Day = TODAY, UserId = 41, Name = "Mia", Ore = "Gold" },
				{ Day = TODAY, Name = "Mia", Ore = "Gold", Grade = "Clean" }, -- no UserId: the hidden list couldn't reach it
				{ Day = TODAY, UserId = 0, Name = "Mia", Ore = "Gold", Grade = "Clean" },
				{ Day = TODAY, UserId = 4.5, Name = "Mia", Ore = "Gold", Grade = "Clean" },
				{ Day = TODAY, UserId = "41", Name = "Mia", Ore = "Gold", Grade = "Clean" },
			}
		do
			T.eq(FindOfDay.read(junk), nil)
		end
		T.truthy(FindOfDay.read(entry(string.rep("é", 20), "Gold", "Clean")), "20 characters, not bytes")
	end)

	local function service(): any
		local w: any = { published = {}, stored = nil, now = NOW, attrs = {}, writes = 0, hidden = {} }
		local saved = {
			clock = FindOfDayService.clock,
			publish = FindOfDayService.publish,
			update = FindOfDayService.update,
			read = FindOfDayService.read,
			setAttribute = FindOfDayService.setAttribute,
			isHidden = FindOfDayService.isHidden,
			hiddenKnown = FindOfDayService.hiddenKnown,
			wait = FindOfDayService.wait,
		}
		FindOfDayService.isHidden = function(userId)
			return w.hidden[userId] == true
		end
		w.known = true
		FindOfDayService.hiddenKnown = function()
			return w.known
		end
		FindOfDayService.setAttribute = function(name, value)
			w.attrs[name] = value
		end
		FindOfDayService.clock = function()
			return w.now
		end
		FindOfDayService.publish = function(e)
			table.insert(w.published, e)
		end
		-- (the MemoryStore's UpdateAsync: nil from the merge keeps what is stored, no write)
		FindOfDayService.update = function(_, merge)
			if w.failUpdate then
				error("MemoryStore down")
			end
			local new = merge(w.stored)
			if new ~= nil then
				w.stored = new
				w.writes += 1
			end
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
			local mia = player("Mia")
			local leo = player("Leo")
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
			FindOfDayService.report(player("Mia"), "Gold", "Clean")
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

	T.test("find of the day service: another's find stops ours going out; the stored one wins a tie (review 11-07)", function()
		local w = service()
		guarded(w, function()
			-- ours (worse) waits, a better one arrives: nothing of ours is written or sent
			FindOfDayService.report(player("Leo"), "Copper", "Clean")
			T.truthy(FindOfDayService.isDirty())
			FindOfDayService.receive({ Data = entry("Nova", "RainbowNova", "Flawless") })
			T.falsy(FindOfDayService.isDirty(), "the better one isn't ours")
			FindOfDayService.save()
			T.eq(w.writes, 0, "no write")
			T.eq(#w.published, 0, "no message (N servers x N at midnight before)")
			-- a tie: the stored one stays and every server shows it
			FindOfDayService.reset()
			w.stored = entry("Far", "Heartstone", "Flawless")
			FindOfDayService.report(player("Mia"), "Heartstone", "Flawless")
			T.eq(FindOfDayService.current().Name, "Mia", "ours first on this server")
			FindOfDayService.save()
			T.eq(w.stored.Name, "Far", "the store keeps its own on a tie")
			T.eq(w.writes, 0, "and isn't rewritten")
			T.eq(#w.published, 0)
			T.eq(FindOfDayService.current().Name, "Far", "this server shows the stored finder")
			FindOfDayService.report(player("Leo"), "Heartstone", "Flawless")
			T.eq(FindOfDayService.current().Name, "Far", "a later tie of ours: the first keeps it")
			FindOfDayService.receive({ Data = entry("Nova", "Heartstone", "Flawless") })
			T.eq(FindOfDayService.current().Name, "Nova", "a stored one from another server: same wins")
			T.eq(w.attrs.FindOfDayUser, USERS.Nova, "the clients get the UserId with it")
		end)
	end)

	T.test("find of the day service: hidden users never go up, from anywhere (COMPLIANCE 2.10)", function()
		local w = service()
		guarded(w, function()
			w.hidden[USERS.Mia] = true
			FindOfDayService.report(player("Mia"), "RainbowNova", "Flawless")
			T.eq(FindOfDayService.current(), nil, "not from here")
			FindOfDayService.receive({ Data = entry("Mia", "RainbowNova", "Flawless") })
			T.eq(FindOfDayService.current(), nil, "not from another server")
			w.stored = entry("Mia", "RainbowNova", "Flawless")
			FindOfDayService.refresh()
			T.eq(FindOfDayService.current(), nil, "not from the store")
			FindOfDayService.report(player("Leo"), "Coal", "Rough")
			T.eq(FindOfDayService.current().Name, "Leo")
			T.eq(FindOfDayService.Expiry, 2 * 86400, "the store forgets it in 2 days")
			T.eq(FindOfDayService.MapName, "TerraForgeFindOfDay")
		end)
	end)

	T.test("find of the day service: a user hidden after going up comes off at the next round; later servers wait for the list", function()
		local w = service()
		guarded(w, function()
			FindOfDayService.report(player("Mia"), "RainbowNova", "Flawless")
			T.eq(FindOfDayService.current().Name, "Mia")
			w.hidden[USERS.Mia] = true -- (LeaderboardService.removeUser, after it went up)
			FindOfDayService.round(0)
			T.eq(FindOfDayService.current(), nil, "off the board within one round")
			T.eq(w.attrs.FindOfDayName, nil, "the clients see it go")
			T.falsy(FindOfDayService.isDirty(), "nothing of it is sent")
			-- a server started later: the hidden list isn't read yet
			FindOfDayService.reset()
			w.known = false
			local reads = 0
			FindOfDayService.read = function()
				reads += 1
				return entry("Mia", "RainbowNova", "Flawless")
			end
			FindOfDayService.refresh()
			T.eq(reads, 0, "no read before the hidden list")
			FindOfDayService.receive({ Data = entry("Mia", "RainbowNova", "Flawless") })
			T.eq(FindOfDayService.current(), nil, "a message waits too")
			w.known = true
			FindOfDayService.round(0)
			T.eq(reads, 1, "the round after the list came in reads the store at once")
			T.eq(FindOfDayService.current(), nil, "and the hidden user stays off")
			w.hidden[USERS.Mia] = nil
			FindOfDayService.round(30)
			T.eq(reads, 1, "then every RefreshEvery again")
		end)
	end)

	T.test("find of the day service: a round saves every 30 s, a failed save is tried again, reads every 5 min", function()
		local w = service()
		guarded(w, function()
			T.eq(FindOfDayService.SaveEvery, 30)
			T.eq(FindOfDayService.RefreshEvery, 300)
			T.eq(FindOfDay.day(86399), 0, "a UTC day")
			T.eq(FindOfDay.day(86400), 1)
			T.eq(FindOfDay.day(NOW), math.floor(NOW / 86400))
			FindOfDayService.refresh() -- (start()'s first read, the hidden list known)
			local reads = 0
			FindOfDayService.read = function()
				reads += 1
				return w.stored
			end
			FindOfDayService.report(player("Mia"), "Gold", "Clean")
			w.failUpdate = true
			local since = FindOfDayService.round(0)
			T.eq(since, 30)
			T.truthy(FindOfDayService.isDirty(), "the failed save waits for the next round")
			T.eq(#w.published, 0)
			w.failUpdate = false
			since = FindOfDayService.round(since)
			T.eq(#w.published, 1, "saved and sent the round after")
			T.eq(w.stored.Name, "Mia")
			T.eq(reads, 0, "no read before 5 minutes")
			for _ = 3, 10 do
				since = FindOfDayService.round(since)
			end
			T.eq(reads, 1, "one read at 300 s")
			T.eq(since, 0)
			-- a new day in a round: yesterday's best goes
			w.now = NOW + 86400
			FindOfDayService.round(0)
			T.eq(FindOfDayService.current(), nil)
			T.eq(w.attrs.FindOfDayName, nil)
			-- the loop (offline: Studio) rolls over every round and stops when the wait says so
			local saveOnline = FindOfDayService.online
			FindOfDayService.online = function()
				return false
			end
			w.now = NOW
			FindOfDayService.report(player("Leo"), "Gold", "Clean")
			local waits = 0
			FindOfDayService.wait = function(seconds: number): boolean
				T.eq(seconds, FindOfDayService.SaveEvery)
				waits += 1
				w.now = NOW + 86400 * waits
				return waits <= 2
			end
			FindOfDayService.start()
			FindOfDayService.online = saveOnline
			T.eq(waits, 3, "two rounds, then it stopped")
			T.eq(FindOfDayService.current(), nil, "rolled over in the loop")
		end)
	end)

	T.test("find of the day: the cleaning and the machines report every clean ore (the two hooks)", function()
		local fs = require("@lune/fs")
		local cleaning = fs.readFile("src/server/Services/CleaningService.luau")
		T.truthy(cleaning:find("FindOfDayService.report(player, session.OreId, result.Grade)", 1, true), "a player's own cleaning")
		local processing = fs.readFile("src/server/Services/ProcessingService.luau")
		T.truthy(processing:find("FindOfDayService.report(player, desc.O, desc.G)", 1, true), "a machine's clean ore")
		-- report never yields and never throws: a bad player or ore changes nothing
		local w = service()
		guarded(w, function()
			FindOfDayService.report({ DisplayName = 5, UserId = 41 } :: any, "Gold", "Clean")
			FindOfDayService.report({ DisplayName = "Mia" } :: any, "Gold", "Clean")
			FindOfDayService.report(player("Mia"), "Nope", "Clean")
			FindOfDayService.report(player("Mia"), "Gold", nil)
			T.eq(FindOfDayService.current(), nil)
		end)
	end)

	T.test("event board: its pages rotate with the server's time, the weather counts down", function()
		T.eq(EventBoardLogic.PageSeconds, 8, "each page 8 s")
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
		-- (review 11-07: readable on a phone) the ore big in its rarity's colour, the finder on a second big line
		T.eq(page.Big, "Phoenix Feather")
		T.eq(page.BigColor, Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity").ById.Mythic.Color)
		T.eq(page.Small, "EmberQueen · Flawless")
		T.eq(EventBoardLogic.findPage(nil, NOW).Big, "Nobody yet")
		T.eq(EventBoardLogic.findPage(entry("Old", "Gold", "Clean", TODAY - 1), NOW).Big, "Nobody yet")
	end)

	T.test("event board: planted in the mountains, off the roads, nothing in front of its face, seen from the spawn", function()
		local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
		local WorldBuilder = Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
		local game = roblox.Instance.new("DataModel")
		local map = WorldBuilder.build(game:GetService("Workspace"))
		local board = map:FindFirstChild("EventBoard", true)
		T.truthy(board, "the board is in the map")
		local screen = board and board:FindFirstChild("Screen")
		T.truthy(screen, "its screen")
		local frame = LobbyLayout.frame(LobbyLayout.get("EventBoard"))
		-- the opaque parts that aren't the board
		local parts = {}
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 and not d:IsDescendantOf(board) then
				table.insert(parts, d)
			end
		end
		local function inside(d: any, at: any): boolean
			local l = d.CFrame:PointToObjectSpace(at)
			return math.abs(l.X) <= d.Size.X / 2 and math.abs(l.Y) <= d.Size.Y / 2 and math.abs(l.Z) <= d.Size.Z / 2
		end
		-- the leg's foot stands on the ground or in the mountain, never on a road
		local legZ = 2.2 + EventBoard.Leg / 2 + 1
		local under = (frame * roblox.CFrame.new(0, -0.5, legZ)).Position
		local standing = false
		for _, d in parts do
			if inside(d, under) then
				standing = true
				break
			end
		end
		T.truthy(standing, "the leg stands on something")
		for _, dx in { -EventBoard.Leg, 0, EventBoard.Leg } do
			for _, dz in { -EventBoard.Leg, 0, EventBoard.Leg } do
				local at = (frame * roblox.CFrame.new(dx, 1, legZ + dz)).Position
				for _, road in WorldLayout.Roads do
					T.truthy(LobbyLayout.distanceToStrip(road.From, road.To, road.Width, at) > 0, "the foot is off the road")
				end
			end
		end
		-- nothing pokes through the screen: points just in front of its face are in the air
		for _, fx in { -0.45, 0, 0.45 } do
			for _, fy in { -0.4, 0, 0.4 } do
				local at = (screen.CFrame * roblox.CFrame.new(fx * EventBoard.Screen.X, fy * EventBoard.Screen.Y, -1)).Position
				for _, d in parts do
					T.falsy(inside(d, at), `{d:GetFullName()} stands in front of the screen`)
				end
			end
		end
		-- from the spawn (eye height) to the screen's middle: nothing opaque in the way
		local eye = WorldLayout.SpawnPoint + roblox.Vector3.new(0, 5, 0)
		local target = screen.CFrame.Position
		local span = target - eye
		local length = span.Magnitude
		T.truthy(length < EventBoardView.MaxDistance - 100, `its words draw from the spawn ({math.floor(length)} studs)`)
		local near = {}
		for _, d in parts do
			local t = math.clamp((d.CFrame.Position - eye):Dot(span) / (length * length), 0, 1)
			if (eye + span * t - d.CFrame.Position).Magnitude <= d.Size.Magnitude / 2 + 1 then
				table.insert(near, d)
			end
		end
		for k = 1, 59 do
			local at = eye + span * (k / 60)
			for _, d in near do
				T.falsy(inside(d, at), `{d:GetFullName()} hides the board from the spawn`)
			end
		end
	end)

	T.test("event board: the iron stays in budget, one screen faces the town, three lamps light it, it streams in", function()
		local folder = roblox.Instance.new("Folder")
		local model = EventBoard.build(folder)
		local screens, parts, lights = {}, 0, {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d:HasTag("EventBoardScreen") then
					table.insert(screens, d)
				end
			elseif d:IsA("SpotLight") or d:IsA("PointLight") or d:IsA("SurfaceLight") then
				table.insert(lights, d)
			end
		end
		T.truthy(parts <= EventBoard.MaxParts, `{parts} parts`)
		T.eq(#screens, 1, "one screen")
		T.truthy(model:HasTag("NoStuds"), "iron, no studs")
		local screen = screens[1]
		local facing = LobbyLayout.get("EventBoard").Facing.Unit
		T.truthy(screen.CFrame.LookVector:Dot(facing) > 0.99, "its Front face looks where the piece faces")
		-- the lamps: one SpotLight each, no shadows, aimed at the face and reaching it
		T.eq(#lights, EventBoard.Lamps, "one light a lamp")
		for _, light in lights do
			T.truthy(light:IsA("SpotLight"), "a spotlight")
			T.falsy(light.Shadows, "no shadows")
			-- its beam (the head's front) meets the screen's face inside the screen
			local head = light.Parent
			local from = screen.CFrame:PointToObjectSpace(head.CFrame.Position)
			local along = screen.CFrame:VectorToObjectSpace(head.CFrame.LookVector)
			T.truthy(from.Z < 0 and along.Z > 0, "in front, shining back at the face")
			local hit = from + along * (-from.Z / along.Z)
			T.truthy(math.abs(hit.X) <= EventBoard.Screen.X / 2 and math.abs(hit.Y) <= EventBoard.Screen.Y / 2, "aimed at the screen")
			T.truthy(light.Range >= (hit - from).Magnitude, "its light reaches the face")
		end
		-- the leg and the beams are behind the screen; in front of it only the lamps, above its top edge
		local top = EventBoard.Screen.Y / 2
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= screen then
				local l = screen.CFrame:PointToObjectSpace(d.CFrame.Position)
				if l.Z < -0.5 and math.abs(l.X) < EventBoard.Screen.X / 2 then
					T.truthy(l.Y > top, d.Name .. ": nothing hangs in front of the screen")
				end
			end
		end
		local mode = (model :: any).ModelStreamingMode
		T.truthy(mode == nil or mode == roblox.Enum.ModelStreamingMode.Persistent, "always streamed in")
		local refs = EventBoardView.build(screen)
		EventBoardView.fill(refs, EventBoardLogic.findPage(entry("Mia", "Gold", "Clean"), NOW))
		T.eq(refs.Big.Text, "Gold")
		T.eq(refs.Small.Text, "Mia · Clean")
		T.truthy(refs.Small.Size.Y.Scale >= 0.25, "the second line is big too")
		T.truthy(refs.Big.Size.Y.Scale >= 0.3)
		T.eq(refs.Gui.LightInfluence, 0, "readable at night")
		T.truthy(refs.Gui.MaxDistance > 0, "far away it doesn't draw")
		folder:Destroy()
	end)
end
