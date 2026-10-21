-- Quick teleports: TeleportService's destinations (BASE at the front of
-- your plot, LOBBY at the town spawn, VAULT in front of the Blaster Vault,
-- the elevator stop), its refusals (cooldown, no base, closed place, dead,
-- cleaning, junk input), which elevator stop the "Elevator" jump picks (the
-- floor you are on, else floor 1's, else the lowest) and TeleportView's
-- layout (phone touch size, the bar fitting next to the coins, cooldown
-- covers; no elevator button: that is ElevatorController's side button).
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local TeleportConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.TeleportConfig")
	local WorldLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.WorldLayout")
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local Vault = Loader.requirePath("ServerScriptService.Server.World.Lobby.Vault")
	local PlotService = Loader.requirePath("ServerScriptService.Server.Services.PlotService")
	local TeleportService = Loader.requirePath("ServerScriptService.Server.Services.TeleportService")
	local TeleportView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TeleportView")

	local PLOT = 4

	local function character(): (any, any, any)
		local model = Instance.new("Model")
		model.Name = "Character"
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = model
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.CFrame = CFrame.new(500, 10, 500)
		root.Parent = model
		model.PrimaryPart = root
		return model, humanoid, root
	end

	-- A fake world: one player with a character, flat ground at y 0, replies logged.
	local function withWorld(name: string, body: (any) -> ())
		T.test(name, function()
			local saved = {}
			local function patch(t: any, key: string, value: any)
				table.insert(saved, { t, key, rawget(t, key) })
				rawset(t, key, value)
			end
			local model, humanoid, root = character()
			local w: any = {
				player = { UserId = 701, Name = "P701", Parent = true, Character = model },
				humanoid = humanoid,
				root = root,
				replies = {},
				plot = PLOT,
				cleaning = false,
				elevator = nil,
			}
			patch(Net, "fire", function(event: string, player: any, payload: any)
				if event == "TeleportResult" and player == w.player then
					table.insert(w.replies, payload)
				end
			end)
			patch(PlotService, "plotOf", function(p: any)
				return if p == w.player then w.plot else nil
			end)
			patch(TeleportService, "isCleaning", function(p: any)
				return p == w.player and w.cleaning
			end)
			patch(TeleportService, "groundAt", function(p: any, lift: number?)
				w.lift = lift
				return Vector3.new(p.X, 0, p.Z)
			end)
			patch(TeleportService, "elevatorStop", function(floor: number?)
				w.askedFloor = floor
				return w.elevator
			end)
			TeleportService._test.reset()
			w.go = function(destination: any): any
				local before = #w.replies
				TeleportService._test.handle(w.player, destination)
				return if #w.replies > before then w.replies[#w.replies] else nil
			end
			w.at = function(): any
				return w.root.CFrame.Position
			end
			local ok, err = pcall(body, w)
			TeleportService._test.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function flat(a: any, b: any): number
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end

	withWorld("Teleport: BASE lands at the front of your own plot, facing it", function(w)
		local reply = w.go("Base")
		T.truthy(reply and reply.Ok, "Ok")
		T.eq(reply.Destination, "Base")
		local home = PlotService.homeCFrame(PLOT)
		T.truthy(flat(w.at(), home.Position) <= TeleportConfig.Spread + 1e-6, "at the plot front (with the spread)")
		T.near(w.at().Y, TeleportConfig.StandHeight, 1e-6, "standing on the ground")
		local toPlot = (PlotService.plotCFrame(PLOT).Position - w.at()) * Vector3.new(1, 0, 1)
		T.truthy(w.root.CFrame.LookVector:Dot(toPlot.Unit) > 0.9, "facing the plot")
	end)

	withWorld("Teleport: BASE without a plot is refused and nobody moves", function(w)
		w.plot = nil
		local before = w.at()
		local reply = w.go("Base")
		T.truthy(reply and not reply.Ok, "refused")
		T.eq(reply.Reason, "NoBase")
		T.eq(w.at(), before, "not moved")
		-- a refusal doesn't start the cooldown
		w.plot = PLOT
		T.truthy(w.go("Base").Ok, "the next try works")
	end)

	withWorld("Teleport: a second jump within the cooldown is refused", function(w)
		T.truthy(w.go("Lobby").Ok)
		local spot = w.at()
		local reply = w.go("Base")
		T.truthy(reply and not reply.Ok, "too soon")
		T.eq(reply.Reason, "Cooldown")
		T.eq(w.at(), spot, "still in the lobby")
		T.truthy(TeleportConfig.ServerCooldown < TeleportConfig.Cooldown, "the server allows a little lag")
	end)

	withWorld("Teleport: LOBBY lands at the town spawn", function(w)
		local reply = w.go("Lobby")
		T.truthy(reply and reply.Ok)
		T.truthy(flat(w.at(), WorldLayout.SpawnPoint) <= TeleportConfig.Spread + 1e-6, "at the spawn")
	end)

	withWorld("Teleport: VAULT lands in front of the Blaster Vault's steps, facing it", function(w)
		local reply = w.go("Vault")
		T.truthy(reply and reply.Ok)
		local origin = Vault.origin()
		local localPos = origin:PointToObjectSpace(w.at())
		local front = TeleportService.VaultPodiumFront * Vault.Scale + TeleportConfig.VaultFront
		T.truthy(math.abs(localPos.Z - front) <= TeleportConfig.Spread + 1e-6, "in front of the podium")
		T.truthy(math.abs(localPos.X) <= TeleportConfig.Spread + 1e-6, "in the middle")
		local toVault = (origin.Position - w.at()) * Vector3.new(1, 0, 1)
		T.truthy(w.root.CFrame.LookVector:Dot(toVault.Unit) > 0.9, "facing the vault")
	end)

	withWorld("Teleport: the elevator is refused until the world has one, then lands in front of it", function(w)
		local reply = w.go("Elevator")
		T.truthy(reply and not reply.Ok)
		T.eq(reply.Reason, "NotHere")
		local base = Instance.new("Part")
		base.Size = Vector3.new(10, 1, 8)
		base.CFrame = CFrame.new(40, -20, 60)
		w.elevator = base
		local ok = w.go("Elevator")
		T.truthy(ok and ok.Ok, "now it works")
		local localPos = base.CFrame:PointToObjectSpace(w.at())
		T.near(localPos.Z, -(base.Size.Z / 2 + 3), 1e-6, "in front of the plate (-Z)")
		T.near(localPos.X, 0, 1e-6, "no spread at the elevator")
		-- the ground ray starts just above the plate (under the cave roofs of floors 2 and 3)
		T.eq(w.lift, TeleportService.IndoorLift, "an indoor ground ray")
		T.truthy(TeleportService.IndoorLift <= 8, "below every cave roof")
		TeleportService._test.reset()
		T.truthy(w.go("Lobby").Ok)
		T.eq(w.lift, nil, "outdoor jumps keep the long ray")
	end)

	withWorld("Teleport: the elevator jump asks for the stop of the mine floor you are on", function(w)
		local base = Instance.new("Part")
		base.Size = Vector3.new(10, 1, 8)
		base.CFrame = CFrame.new(40, -20, 60)
		w.elevator = base
		-- standing in Ember Caves (floor 2)
		local caves = WorldLayout.ZoneById.EmberCaves
		w.root.CFrame = CFrame.new((caves.Min + caves.Max) / 2)
		T.truthy(w.go("Elevator").Ok)
		T.eq(w.askedFloor, 2, "floor 2's stop")
		-- in town: no floor (floor 1's stop, else the lowest)
		TeleportService._test.reset()
		w.root.CFrame = CFrame.new(WorldLayout.SpawnPoint)
		T.truthy(w.go("Elevator").Ok)
		T.eq(w.askedFloor, nil, "no floor in town")
		T.eq(TeleportService.floorAt(WorldLayout.SpawnPoint), nil, "the town is no mine floor")
		local palace = WorldLayout.ZoneById.SunkenPalace
		T.eq(TeleportService.floorAt((palace.Min + palace.Max) / 2), 4, "Sunken Palace = floor 4")
	end)

	T.test("Teleport: pickStop takes the floor's stop, else floor 1's, else the lowest", function()
		local folder = Instance.new("Folder")
		local function stop(floor: number, withBase: boolean?): any
			local model = Instance.new("Model")
			model:SetAttribute("Floor", floor)
			model.Parent = folder
			if withBase ~= false then
				local base = Instance.new("Part")
				base.Name = "Base"
				base.Parent = model
			end
			return model
		end
		local s1, s2, s3 = stop(1), stop(2), stop(3)
		local broken = stop(4, false)
		local list = { s3, broken, s2, s1 }
		T.eq(TeleportService.pickStop(list, 2), s2.Base, "the floor's own stop")
		T.eq(TeleportService.pickStop(list, 4), s1.Base, "a stop without a Base doesn't count: floor 1's")
		T.eq(TeleportService.pickStop(list, nil), s1.Base, "no floor: floor 1's")
		T.eq(TeleportService.pickStop({ s3, s2 }, 5), s2.Base, "no floor 1: the lowest")
		s2.Parent = nil
		T.eq(TeleportService.pickStop({ s3, s2 }, 2), s3.Base, "a stop that left the world doesn't count")
		T.eq(TeleportService.pickStop({}, 1), nil, "no stops")
	end)

	withWorld("Teleport: dead, cleaning and junk requests", function(w)
		local before = w.at()
		w.cleaning = true
		local reply = w.go("Lobby")
		T.eq(reply and reply.Reason, "Cleaning")
		w.cleaning = false
		w.humanoid.Health = 0
		reply = w.go("Lobby")
		T.eq(reply and reply.Reason, "Dead")
		w.humanoid.Health = 100
		T.eq(w.go("Moon"), nil, "unknown place: no answer")
		T.eq(w.go(42), nil, "not a string")
		T.eq(w.go(string.rep("x", 100)), nil, "too long")
		T.eq(w.at(), before, "never moved")
		w.player.Character = nil
		reply = w.go("Base")
		T.eq(reply and reply.Reason, "Dead", "no character")
	end)

	T.test("Teleport: only a running cleaning session blocks it, not owning a Cleaning Station", function()
		local CleaningService = Loader.requirePath("ServerScriptService.Server.Services.CleaningService")
		local player: any = { UserId = 702, Name = "P702", Parent = true }
		T.falsy(CleaningService.isCleaning(player), "no session")
		local savedStation, savedCleaning = CleaningService.stationOf, CleaningService.isCleaning
		local ok, err = pcall(function()
			-- every player owns a station (the starter kit): that alone must not block
			rawset(CleaningService, "stationOf", function()
				return Instance.new("Model")
			end)
			T.falsy(TeleportService.isCleaning(player), "a station without a session")
			rawset(CleaningService, "isCleaning", function()
				return true
			end)
			T.truthy(TeleportService.isCleaning(player), "a running session")
		end)
		rawset(CleaningService, "stationOf", savedStation)
		rawset(CleaningService, "isCleaning", savedCleaning)
		if not ok then
			error(err, 0)
		end
	end)

	---------------------------------------------------------------- TeleportView

	T.test("TeleportView: phone buttons are big enough to tap and the bar fits next to the coins", function()
		local phone = TeleportView.layout(0.62)
		T.truthy(phone.Tall, "taller buttons on phones")
		T.truthy(phone.Height * 0.62 >= 44, "at least 44 pt tall at uiScale 0.62")
		T.truthy(phone.Width * 0.62 >= 44, "and wide")
		local big = TeleportView.layout(1)
		T.falsy(big.Tall, "the shorter buttons on big screens")
		-- the smallest landscape phone (iPhone SE, 667 x 375 pt): the bar stays clear of the coins panel
		local coinsRight = (16 + 236) * 0.62
		local half = TeleportView.barWidth(phone, 3) * 0.62 / 2
		T.truthy(667 / 2 - half > coinsRight + 8, "clear of the coins panel")
		T.eq(TeleportView.barWidth(big, 3), 3 * big.Width + 2 * big.Gap)
		-- the smallest phones (568 pt wide): square buttons, still big enough to tap, clear of the coins
		local tiny = TeleportView.layout(0.62, 568)
		T.truthy(tiny.Narrow, "squares below NarrowWidth")
		T.truthy(tiny.Height * 0.62 >= 44 and tiny.Width * 0.62 >= 44, "44 pt targets")
		local tinyHalf = TeleportView.barWidth(tiny, 3) * 0.62 / 2
		T.truthy(568 / 2 - tinyHalf > coinsRight + 12, "clear of the coins panel at 568 pt")
		T.falsy(TeleportView.layout(0.62, 667).Narrow, "667 pt keeps the wide buttons")
	end)

	T.test("TeleportView: three bar buttons (no elevator icon: the side menu has it), cooldown covers", function()
		local gui = Instance.new("ScreenGui")
		local topBar = Instance.new("Frame")
		topBar.Parent = gui
		Instance.new("UIListLayout").Parent = topBar
		local refs = TeleportView.build(topBar, 1)
		local count = 0
		for id, button in refs.Buttons do
			local spot = TeleportConfig.ById[id]
			T.truthy(spot, id)
			T.truthy(spot.Bar, id .. " is a bar spot")
			count += 1
			T.truthy(button:IsDescendantOf(topBar), id .. " in the bar")
			T.eq(button:FindFirstChild("Label").Text, spot.Label)
			T.falsy(button:FindFirstChild("Icon"), id .. ": words only, no emoji icon")
		end
		T.eq(count, 3, "BASE, LOBBY, VAULT")
		T.eq(refs.Buttons.Elevator, nil, "no LIFT icon (ElevatorController's side button sends the jump)")
		T.truthy(TeleportConfig.ById.Elevator, "the Elevator destination still exists")
		TeleportView.setCooldown(refs, 2.4)
		for _, cover in refs.Covers do
			T.truthy(cover.Visible, "cover on")
			T.eq(cover.Text, "3", "whole seconds left, rounded up")
		end
		TeleportView.setCooldown(refs, 0)
		for _, cover in refs.Covers do
			T.falsy(cover.Visible, "cover off")
		end
		TeleportView.relayout(refs, topBar, 0.62)
		local base = refs.Buttons.Base.Parent
		T.eq(base.Size.Y.Offset, TeleportView.layout(0.62).Height, "phone height after a relayout")
		TeleportView.relayout(refs, topBar, 0.62, 568)
		-- the smallest phones: the names stay (words only, no icon), smaller, and still fit the squares
		local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
		local narrow = TeleportView.layout(0.62, 568)
		for id, button in refs.Buttons do
			local name = button:FindFirstChild("Label") :: any
			T.truthy(name.Visible, id .. ": the name shows on the smallest phones")
			T.eq(name.TextSize, TeleportView.NarrowText)
			T.truthy(TechShopView.fits(name.Text, narrow.Width - 8, narrow.Height, name.TextSize, false), id .. " fits the square")
		end
		T.eq(base.Size.X.Offset, narrow.Width)
		TeleportView.relayout(refs, topBar, 1, 1920)
		T.truthy(refs.Buttons.Base:FindFirstChild("Label").Visible, "names on a big screen")
		T.eq((refs.Buttons.Base:FindFirstChild("Label") :: any).TextSize, TeleportView.LabelText, "the big name again")
	end)
end
