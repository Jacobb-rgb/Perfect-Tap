-- SECRET ores on the server (SecretService): the rate limits, the every-server message (only
-- Rainbow Nova, only checked fields), a find (counted, NEW! on a first find, the jackpot to the
-- finder, the chat line), and the rules that keep a secret ore from being lost (MachineData,
-- the sell plan, the wheel's prize, a save that holds one).
return function(T, Loader)
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
	local WheelConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.WheelConfig")
	local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
	local SecretService = Loader.requirePath("ServerScriptService.Server.Services.SecretService")
	local Migrations = Loader.requirePath("ServerScriptService.Server.Data.Migrations")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local SellView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.SellView")
	local RebirthConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RebirthConfig")
	local ProfileStore = Loader.requirePath("ServerScriptService.Server.Data.ProfileStore")
	local SecretRevealController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.SecretRevealController")

	-- runs `fn` with Net's fire / fireAll and SecretService's hooks swapped for recorders
	local function harness(fn: (any) -> ())
		local h = { fired = {}, all = {}, published = {}, now = 1000, data = nil :: any }
		local savedJob = SecretService.jobId
		local saved = {
			fire = Net.fire,
			fireAll = Net.fireAll,
			clock = SecretService.clock,
			publish = SecretService.publish,
			dataOf = SecretService.dataOf,
			changed = SecretService.changed,
		}
		rawset(Net, "fire", function(name, player, payload)
			table.insert(h.fired, { Name = name, Player = player, Payload = payload })
		end)
		rawset(Net, "fireAll", function(name, payload)
			table.insert(h.all, { Name = name, Payload = payload })
		end)
		SecretService.clock = function()
			return h.now
		end
		SecretService.publish = function(payload)
			table.insert(h.published, payload)
			return true
		end
		SecretService.dataOf = function()
			return h.data
		end
		SecretService.changed = function() end
		SecretService.jobId = function()
			return "this-server"
		end
		SecretService.resetLimits()
		local ok, err = pcall(fn, h)
		SecretService.jobId = savedJob
		rawset(Net, "fire", saved.fire)
		rawset(Net, "fireAll", saved.fireAll)
		SecretService.clock = saved.clock
		SecretService.publish = saved.publish
		SecretService.dataOf = saved.dataOf
		SecretService.changed = saved.changed
		SecretService.resetLimits()
		if not ok then
			error(err, 0)
		end
	end

	local function player(userId: number, name: string): any
		return { UserId = userId, DisplayName = name, Name = name, Parent = true }
	end

	T.test("secret service: a sliding-window limiter per key", function()
		local limiter = SecretService.newLimiter(2, 60)
		T.truthy(SecretService.take(limiter, "a", 0), "1st")
		T.truthy(SecretService.take(limiter, "a", 10), "2nd")
		T.falsy(SecretService.take(limiter, "a", 20), "3rd in the window")
		T.truthy(SecretService.take(limiter, "b", 20), "another key")
		T.truthy(SecretService.take(limiter, "a", 61), "the 1st fell out of the window")
		T.falsy(SecretService.take(limiter, "a", 65), "full again")
	end)

	T.test("secret service: only Rainbow Nova goes to every server, with checked fields only", function()
		T.truthy(SecretService.isGlobal("RainbowNova"), "Nova")
		T.falsy(SecretService.isGlobal("HollowEye"), "a floor's secret stays on its server")
		T.falsy(SecretService.isGlobal("Coal"), "not a secret")
		T.eq(SecretService.payload(5, "Mia", "HollowEye", "job"), nil, "no payload for a floor secret")
		local payload = SecretService.payload(5, "Mia", "RainbowNova", "job") :: any
		T.eq(payload.U, 5)
		T.eq(payload.N, "Mia")
		T.eq(payload.O, "RainbowNova")
		T.eq(payload.J, "job")
		local u, n, o, j = SecretService.read(payload)
		T.eq(u, 5)
		T.eq(n, "Mia")
		T.eq(o, "RainbowNova")
		T.eq(j, "job")
		-- anything broken or unknown is dropped
		for _, bad in
			{
				nil,
				"x",
				{},
				{ U = "5", N = "Mia", O = "RainbowNova", J = "j" },
				{ U = 0, N = "Mia", O = "RainbowNova", J = "j" },
				{ U = 1.5, N = "Mia", O = "RainbowNova", J = "j" },
				{ U = 0 / 0, N = "Mia", O = "RainbowNova", J = "j" },
				{ U = 5, N = "", O = "RainbowNova", J = "j" },
				{ U = 5, N = string.rep("a", 41), O = "RainbowNova", J = "j" },
				{ U = 5, N = "<b>x</b>", O = "RainbowNova", J = "j" },
				{ U = 5, N = "Mia\n", O = "RainbowNova", J = "j" },
				{ U = 5, N = "Mia", O = "HollowEye", J = "j" },
				{ U = 5, N = "Mia", O = "NoSuchOre", J = "j" },
				{ U = 5, N = "Mia", O = 7, J = "j" },
				{ U = 5, N = "Mia", O = "RainbowNova", J = 3 },
			} :: { any }
		do
			T.eq(SecretService.read(bad), nil, "dropped")
		end
	end)

	T.test("secret service: receiving another server's Rainbow Nova (checked, own server skipped, limited)", function()
		harness(function(h)
			SecretService.receive({ Data = { U = 9, N = "Leo", O = "RainbowNova", J = "other" } })
			T.eq(#h.all, 1, "shown")
			T.eq(h.all[1].Name, "SecretChat")
			T.eq(h.all[1].Payload.Global, true)
			T.eq(h.all[1].Payload.OreId, "RainbowNova")
			SecretService.receive({ Data = { U = 9, N = "Leo", O = "HollowEye", J = "other" } })
			SecretService.receive({ Data = "junk" })
			SecretService.receive(nil)
			SecretService.receive({ Data = { U = 9, N = "Leo", O = "RainbowNova", J = SecretService.jobId() } })
			T.eq(#h.all, 1, "a floor secret, junk and this server's own message show nothing")
			for _ = 1, 20 do
				SecretService.receive({ Data = { U = 9, N = "Leo", O = "RainbowNova", J = "other" } })
			end
			T.eq(#h.all, SecretService.ReceivePerServer, "at most ReceivePerServer a minute")
			h.now += 61
			SecretService.receive({ Data = { U = 9, N = "Leo", O = "RainbowNova", J = "other" } })
			T.eq(#h.all, SecretService.ReceivePerServer + 1, "again after a minute")
		end)
	end)

	T.test("secret service: a find counts, is NEW! once, sends the jackpot, announces and publishes Nova", function()
		harness(function(h)
			local mia = player(11, "Mia")
			h.data = DataTemplate.new and DataTemplate.new() or { Discovered = {}, Stats = { SecretsFound = 0 } }
			h.data.Discovered = h.data.Discovered or {}
			h.data.Stats = h.data.Stats or {}
			SecretService.found(mia, "HollowEye")
			T.eq(h.data.Stats.SecretsFound, 1, "counted")
			T.eq(h.fired[1].Name, "SecretFound")
			T.eq(h.fired[1].Payload.OreId, "HollowEye")
			T.eq(h.fired[1].Payload.New, true, "a first find")
			T.eq(h.fired[1].Payload.Stars, 1)
			T.eq(h.data.Discovered.HollowEye, nil, "Discovery marks it (after this), not SecretService")
			T.eq(h.all[1].Name, "SecretChat")
			T.eq(h.all[1].Payload.Name, "Mia")
			T.eq(h.all[1].Payload.Global, false)
			T.eq(#h.published, 0, "a floor secret is not published")
			h.data.Discovered.HollowEye = true
			SecretService.found(mia, "HollowEye")
			T.eq(h.fired[2].Payload.New, false, "found before: no NEW!")
			T.eq(h.data.Stats.SecretsFound, 2, "duplicates count")
			SecretService.found(mia, "RainbowNova")
			T.eq(#h.published, 1, "Rainbow Nova is published")
			T.eq(h.published[1].O, "RainbowNova")
			T.eq(h.published[1].U, 11)
			-- not a secret: nothing at all
			local before = #h.fired
			SecretService.found(mia, "Coal")
			T.eq(#h.fired, before, "Coal is no jackpot")
		end)
	end)

	T.test("secret service: the chat line and the publishes are rate limited", function()
		harness(function(h)
			local mia = player(12, "Mia")
			for _ = 1, 10 do
				SecretService.announce(mia, "RainbowNova")
			end
			T.eq(#h.all, SecretService.ChatPerPlayer, "chat lines per player a minute")
			T.eq(#h.published, SecretService.PublishPerPlayer, "publishes per player")
			for k = 1, 20 do
				SecretService.announce(player(100 + k, "P" .. k), "HollowEye")
			end
			T.eq(#h.all, SecretService.ChatPerServer, "chat lines per server a minute")
			h.now += 61
			SecretService.announce(player(500, "Zed"), "HollowEye")
			T.eq(#h.all, SecretService.ChatPerServer + 1, "a new minute")
		end)
	end)

	T.test("secret ores: the client's chat line is built from OreData, the name escaped", function()
		local line = SecretRevealController.chatLine({ Name = "Mia", OreId = "HollowEye" }) :: string
		T.truthy(line:find("Mia found Hollow Eye!", 1, true), line)
		T.truthy(line:find("1 in 4,000", 1, true), "the chance")
		local tricky = SecretRevealController.chatLine({ Name = "<i>x</i>", OreId = "RainbowNova" }) :: string
		T.falsy(tricky:find("<i>", 1, true), "rich text escaped")
		T.eq(SecretRevealController.chatLine({ Name = "Mia", OreId = "Coal" }), nil, "not a secret")
		T.eq(SecretRevealController.chatLine({ Name = "", OreId = "HollowEye" }), nil, "no name")
		T.eq(SecretRevealController.chatLine("junk"), nil, "junk")
	end)

	T.test("secret ores: never into a machine, always kept, never sold in a batch, no wheel prize", function()
		for _, kind in { "Raw", "Clean" } do
			local desc = { K = kind, O = "HollowEye", G = if kind == "Clean" then "Flawless" else nil }
			T.truthy(MachineData.refuses(desc), kind .. " refused by machines")
			for _, mode in { "RarePlus", "List", "All" } do
				T.truthy(MachineData.keeps(mode, { HollowEye = false }, desc), kind .. " kept in " .. mode)
			end
		end
		T.falsy(MachineData.refuses({ K = "Raw", O = "Coal" }), "Coal is fine")
		T.falsy(MachineData.keeps("RarePlus", {}, { K = "Raw", O = "Coal" }), "dirty Coal still passes on")
		T.truthy(MachineData.keepsOre("List", { RainbowNova = false }, "RainbowNova"), "the keep list can't drop a secret")
		-- the sell plan (SellView mirrors SellService.sellAll): a secret never in a batch
		local pen = { ["Raw|HollowEye||"] = 1, ["Raw|Coal||"] = 2, ["Clean|RainbowNova|Flawless|"] = 1 }
		local dirty = SellView.plan(pen, {}, "Dirty", nil, 1) :: any
		T.eq(dirty.Count, 2, "only the two Coal")
		local rest = SellView.plan(pen, {}, "AllButBest", nil, 1) :: any
		T.eq(rest.Count, 0, "the secret Nova is not sold")
		-- the wheel's ore prize follows the player's best ore, not a jackpot
		T.eq(WheelConfig.bestIncome({ Coal = true, RainbowNova = true }), OreData.get("Coal").Income, "no secret prize")
	end)

	T.test("secret ores: a rebirth keeps exactly the secret ores, where they are (owner: Zůstanou)", function()
		local data = ProfileStore.deepCopy(DataTemplate)
		data.BlasterLevel = 8
		data.Storage = {
			{ K = "Raw", O = "HollowEye" },
			{ K = "Clean", O = "Coal", G = "Rough" },
			{ K = "Clean", O = "RainbowNova", G = "Flawless" },
		}
		data.BackpackItems = { ["Clean|TidecrownPearl|Flawless|"] = 2, ["Raw|Coal||"] = 5 }
		data.Podiums = { "Clean|HeartOfTerra|Flawless|", "Clean|Gold|Rough|", "", "", "" }
		data.Train.Cargo = { { K = "Raw", O = "CagedLightning" }, { K = "Raw", O = "Tin" } }
		data.Discovered = { HollowEye = true, Coal = true }
		data.Stats.SecretsFound = 4
		RebirthConfig.reset(data)
		local pen = {}
		for _, item in data.Storage do
			table.insert(pen, item.K .. "|" .. item.O)
		end
		table.sort(pen)
		T.eq(table.concat(pen, ","), "Clean|RainbowNova,Raw|CagedLightning,Raw|HollowEye", "the pen: its secrets + the train's")
		T.eq(data.BackpackItems["Clean|TidecrownPearl|Flawless|"], 2, "the backpack's secrets stay in it")
		T.eq(data.BackpackItems["Raw|Coal||"], nil, "the rest of the backpack goes")
		T.eq(data.Podiums[1], "Clean|HeartOfTerra|Flawless|", "a secret stays on its podium")
		T.eq(data.Podiums[2], "", "other podiums empty")
		T.eq(#data.Train.Cargo, 0, "the train is empty")
		T.truthy(data.Discovered.HollowEye, "still discovered")
		T.eq(data.Stats.SecretsFound, 4, "the count stays")
	end)

	T.test("secret ores: a v9 save holding secrets comes to v10 with them all kept", function()
		local save = {
			Version = 9,
			Coins = 10,
			Storage = {
				{ K = "Raw", O = "HollowEye" },
				{ K = "Clean", O = "RainbowNova", G = "Flawless" },
			},
			BackpackItems = { ["Clean|TidecrownPearl|Flawless|"] = 1 },
			Podiums = { "Clean|HeartOfTerra|Flawless|", "", "", "", "" },
			Discovered = { HollowEye = true, RainbowNova = true },
			Stats = { OresMined = 3 },
		}
		Migrations.run(save)
		T.eq(save.Version, 10, "v10")
		T.eq(Migrations.Latest, DataTemplate.Version, "Latest = the template's Version")
		T.eq(#save.Storage, 2, "both pen items kept")
		T.eq(save.Storage[1].O, "HollowEye")
		T.eq(save.Storage[2].O, "RainbowNova")
		T.eq(save.BackpackItems["Clean|TidecrownPearl|Flawless|"], 1, "the backpack's secret kept")
		T.eq(save.Podiums[1], "Clean|HeartOfTerra|Flawless|", "the podium's secret kept")
		T.truthy(save.Discovered.HollowEye and save.Discovered.RainbowNova, "discovered kept")
	end)
end
