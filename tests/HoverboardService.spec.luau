-- HoverboardService under Lune: buying coin boards (coins, once, Robux boards refused,
-- auto-equip of a faster board), equipping, riding on / off (every refusal: no board,
-- dead, seated, cleaning, elevator, cooldown), the character attribute + HipHeight,
-- the walk speed from the one formula (CarryService runs for real), dismount on
-- death / sitting / unequip, save repair and broken payloads. Players, saves and Net
-- are small fakes; EconomyService and CarryService run for real.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
	local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
	local HoverboardBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardBuilder")
	local DataTemplate = Loader.requirePath("ServerScriptService.Server.Data.DataTemplate")
	local DataService = Loader.requirePath("ServerScriptService.Server.Services.DataService")
	local StateService = Loader.requirePath("ServerScriptService.Server.Services.StateService")
	local ElevatorService = Loader.requirePath("ServerScriptService.Server.Services.ElevatorService")
	local HoverboardService = Loader.requirePath("ServerScriptService.Server.Services.HoverboardService")

	local h = HoverboardService._test
	local ATTR, HIP = HoverboardData.Attribute, HoverboardData.HipAttribute

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

	local function signal(): any
		local s: any = { handlers = {} }
		s.Connect = function(_, fn)
			table.insert(s.handlers, fn)
			return { Disconnect = function() end }
		end
		s.fire = function(...)
			for _, fn in s.handlers do
				fn(...)
			end
		end
		return s
	end

	local function fakePlayer(): any
		local p: any = { UserId = 31, Name = "Rider", Parent = true, attrs = {} }
		p.GetAttribute = function(_, key)
			return p.attrs[key]
		end
		p.SetAttribute = function(_, key, value)
			p.attrs[key] = value
		end
		p.humanoid = { Health = 100, HipHeight = 2, WalkSpeed = 16, Sit = false, Died = signal(), Seated = signal() }
		p.root = { Position = roblox.Vector3.new(0, 0, 0) }
		local character: any = { attrs = {} }
		character.FindFirstChildOfClass = function(_, class)
			return if class == "Humanoid" then p.humanoid else nil
		end
		character.FindFirstChild = function(_, name)
			return if name == "HumanoidRootPart" then p.root else nil
		end
		character.WaitForChild = function(_, name)
			return if name == "Humanoid" then p.humanoid else nil
		end
		character.GetAttribute = function(_, key)
			return character.attrs[key]
		end
		character.SetAttribute = function(_, key, value)
			character.attrs[key] = value
		end
		p.Character = character
		return p
	end

	local function setup(): any
		local w: any = { notes = {}, changed = 0, pushes = 0, cleaning = false, elevator = false, now = 100 }
		w.player = fakePlayer()
		w.data = deepCopy(DataTemplate)
		w.data.Coins = 0
		local saved = {}
		local function patch(t: any, key: string, value: any)
			table.insert(saved, { t, key, rawget(t, key) })
			rawset(t, key, value)
		end
		patch(DataService, "get", function(p)
			return if p == w.player then w.data else nil
		end)
		patch(DataService, "changed", function()
			w.changed += 1
		end)
		patch(Net, "fire", function(name, p, a)
			table.insert(w.notes, { Name = name, A = a })
		end)
		patch(StateService, "push", function()
			w.pushes += 1
		end)
		patch(HoverboardService, "isCleaning", function()
			return w.cleaning
		end)
		patch(ElevatorService, "isRiding", function()
			return w.elevator
		end)
		h.reset()
		h.setClock(function()
			return w.now
		end)
		w.restore = function()
			h.reset()
			for i = #saved, 1, -1 do
				rawset(saved[i][1], saved[i][2], saved[i][3])
			end
		end
		w.act = function(payload: any): any
			local before = 0
			for _, note in w.notes do
				if note.Name == "HoverboardResult" then
					before += 1
				end
			end
			h.action(w.player, payload)
			local last, count = nil, 0
			for _, note in w.notes do
				if note.Name == "HoverboardResult" then
					count += 1
					last = note.A
				end
			end
			T.eq(count, before + 1, "exactly one HoverboardResult per request")
			return last
		end
		w.attr = function(): any
			return w.player.Character.attrs[ATTR]
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

	withWorld("hoverboards: buy a coin board with coins, once; auto-equip the faster board", function(w)
		local r = w.act({ Action = "Buy", Board = "TimberDrifter" })
		T.falsy(r.Ok, "no coins yet")
		T.eq(r.Reason, "NoCoins", "reason")
		T.eq(w.data.Hoverboards.Owned.TimberDrifter, nil, "not owned")
		local p1 = HoverboardData.ById.TimberDrifter.Price :: number
		local p2 = HoverboardData.ById.CartCruiser.Price :: number
		local start = p1 + p2 + 15000
		w.data.Coins = start
		r = w.act({ Action = "Buy", Board = "TimberDrifter" })
		T.truthy(r.Ok, "bought")
		T.eq(w.data.Coins, start - p1, "paid the price")
		T.eq(w.data.Hoverboards.Owned.TimberDrifter, true, "owned")
		T.eq(w.data.Hoverboards.Equipped, "TimberDrifter", "equipped (the first board)")
		r = w.act({ Action = "Buy", Board = "TimberDrifter" })
		T.eq(r.Reason, "Owned", "a double tap buys once")
		T.eq(w.data.Coins, start - p1, "paid once")
		r = w.act({ Action = "Buy", Board = "CartCruiser" })
		T.truthy(r.Ok, "the second board")
		T.eq(w.data.Coins, 15000, "the second price paid")
		T.eq(w.data.Hoverboards.Equipped, "CartCruiser", "the faster board is equipped")
		-- equipping the slow one back, then buying nothing faster keeps the choice
		T.truthy(w.act({ Action = "Equip", Board = "TimberDrifter" }).Ok, "equip the old board")
		T.eq(w.data.Hoverboards.Equipped, "TimberDrifter", "equipped")
	end)

	withWorld("hoverboards: Robux boards are never sold for coins, bad boards are refused", function(w)
		w.data.Coins = 1e12
		local r = w.act({ Action = "Buy", Board = "TerraForgeCustom" })
		T.eq(r.Reason, "Robux", "Robux board")
		T.eq(w.data.Coins, 1e12, "no coins taken")
		T.eq(w.data.Hoverboards.Owned.TerraForgeCustom, nil, "not owned")
		T.eq(w.act({ Action = "Buy", Board = "Nope" }).Reason, "BadBoard", "unknown board")
		T.eq(w.act({ Action = "Buy", Board = 5 }).Reason, "BadBoard", "a number")
		T.eq(w.act({ Action = "Buy" }).Reason, "BadBoard", "no board")
		local before = #w.notes
		h.action(w.player, { Action = "Fly", Board = "TimberDrifter" })
		for i = before + 1, #w.notes do
			T.truthy(w.notes[i].Name ~= "HoverboardResult", "unknown actions get no answer")
		end
	end)

	T.test("hoverboards: broken payloads are ignored without an answer", function()
		local w = setup()
		local ok, err = pcall(function()
			for _, payload in { nil, 5, "Buy", { Action = 1 }, { 1, 2, 3, 4, 5, 6 } } do
				h.action(w.player, payload)
			end
			for _, note in w.notes do
				T.truthy(note.Name ~= "HoverboardResult", "no answer to junk")
			end
		end)
		w.restore()
		if not ok then
			error(err, 0)
		end
	end)

	withWorld("hoverboards: equip only owned boards; unequip gets you off", function(w)
		T.eq(w.act({ Action = "Equip", Board = "CartCruiser" }).Reason, "NotOwned", "not owned")
		w.data.Hoverboards.Owned.CartCruiser = true
		T.truthy(w.act({ Action = "Equip", Board = "CartCruiser" }).Ok, "owned")
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "ride")
		T.eq(w.attr(), "CartCruiser", "riding")
		T.truthy(w.act({ Action = "Equip", Board = "" }).Ok, "unequip")
		T.eq(w.data.Hoverboards.Equipped, "", "none equipped")
		T.eq(w.attr(), nil, "off the board")
		T.eq(w.act({ Action = "Equip", Board = "Nope" }).Reason, "BadBoard", "unknown")
	end)

	withWorld("hoverboards: riding sets the attribute, HipHeight and the board's speed; off puts it back", function(w)
		local r = w.act({ Action = "Ride", On = true })
		T.eq(r.Reason, "NoBoard", "no board equipped")
		w.data.Hoverboards.Owned.CartCruiser = true
		w.data.Hoverboards.Equipped = "CartCruiser"
		r = w.act({ Action = "Ride", On = true })
		T.truthy(r.Ok, "on")
		T.truthy(r.Riding, "the answer says riding")
		T.eq(w.attr(), "CartCruiser", "character attribute = the board")
		T.near(w.player.humanoid.HipHeight, 2 + HoverboardBuilder.DeckHeight, 1e-6, "HipHeight raised by the deck height")
		T.eq(w.player.Character.attrs[HIP], 2, "old HipHeight kept")
		T.eq(w.player.humanoid.WalkSpeed, 33, "the board's speed")
		T.truthy(HoverboardService.isRiding(w.player), "isRiding")
		-- a second "on" changes nothing (no double HipHeight)
		w.now += 5
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "already on")
		T.near(w.player.humanoid.HipHeight, 2 + HoverboardBuilder.DeckHeight, 1e-6, "HipHeight raised once")
		r = w.act({ Action = "Ride" })
		T.truthy(r.Ok, "toggle off")
		T.falsy(r.Riding, "not riding")
		T.eq(w.attr(), nil, "attribute cleared")
		T.eq(w.player.humanoid.HipHeight, 2, "HipHeight back")
		T.eq(w.player.Character.attrs[HIP], nil, "kept value cleared")
		T.eq(w.player.humanoid.WalkSpeed, HoverboardData.BaseWalkSpeed, "walking speed again")
		w.now += 5
		T.truthy(w.act({ Action = "Ride" }).Ok, "toggle on")
		T.eq(w.attr(), "CartCruiser", "on again")
	end)

	withWorld("hoverboards: the cooldown, dead, seated, cleaning and elevator refuse getting on", function(w)
		w.data.Hoverboards.Owned.TimberDrifter = true
		w.data.Hoverboards.Equipped = "TimberDrifter"
		w.cleaning = true
		T.eq(w.act({ Action = "Ride", On = true }).Reason, "Cleaning", "cleaning")
		w.cleaning = false
		w.elevator = true
		T.eq(w.act({ Action = "Ride", On = true }).Reason, "Elevator", "elevator ride")
		w.elevator = false
		w.player.humanoid.Sit = true
		T.eq(w.act({ Action = "Ride", On = true }).Reason, "Seated", "seated")
		w.player.humanoid.Sit = false
		w.player.humanoid.Health = 0
		T.eq(w.act({ Action = "Ride", On = true }).Reason, "Dead", "dead")
		w.player.humanoid.Health = 100
		T.eq(w.attr(), nil, "never got on")
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "on")
		T.truthy(w.act({ Action = "Ride", On = false }).Ok, "off is always allowed")
		T.eq(w.act({ Action = "Ride", On = true }).Reason, "Cooldown", "too quick")
		w.now += HoverboardService.ToggleCooldown + 0.01
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "after the cooldown")
	end)

	withWorld("hoverboards: one speed formula with carried items (Robux boards ignore it)", function(w)
		-- CarryService.updateWalkSpeed (run for real) reads the character attribute
		w.data.Hoverboards.Owned.CartCruiser = true
		w.data.Hoverboards.Owned.TerraForgeCustom = true
		w.data.Hoverboards.Equipped = "CartCruiser"
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "on the Cart Cruiser")
		T.eq(w.player.humanoid.WalkSpeed, HoverboardData.walkSpeed("CartCruiser", 0), "empty hands")
		T.eq(HoverboardData.walkSpeed("CartCruiser", 4), 31, "coin board: 33 - 4 x 0.5")
		T.truthy(w.act({ Action = "Equip", Board = "TerraForgeCustom" }).Ok, "switch while riding")
		T.eq(w.attr(), "TerraForgeCustom", "the new board under you")
		T.eq(w.player.humanoid.WalkSpeed, 48, "the new board's speed")
		T.eq(HoverboardData.walkSpeed("TerraForgeCustom", 10), 48, "Robux board: no carry slowdown")
		T.eq(w.player.attrs.CarryCount, 0, "CarryService published the carry count")
	end)

	withWorld("hoverboards: death, sitting down and a new character get you off", function(w)
		w.data.Hoverboards.Owned.TimberDrifter = true
		w.data.Hoverboards.Equipped = "TimberDrifter"
		h.hookCharacter(w.player, w.player.Character)
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "on")
		w.player.humanoid.Seated.fire(true, {})
		T.eq(w.attr(), nil, "sitting down: off")
		w.now += 5
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "on again")
		w.player.humanoid.Died.fire()
		T.eq(w.attr(), nil, "death: off")
		T.falsy(HoverboardService.isRiding(w.player), "not riding")
		w.now += 5
		w.act({ Action = "Ride", On = true })
		HoverboardService.dismount(w.player)
		T.eq(w.attr(), nil, "dismount (cleaning start / elevator departure call this)")
		T.eq(w.player.humanoid.HipHeight, 2, "HipHeight back")
	end)

	withWorld("hoverboards: the save record is repaired when read", function(w)
		w.data.Hoverboards = { Owned = { TimberDrifter = true, Nope = true, CartCruiser = "yes", [5] = true }, Equipped = "CartCruiser" }
		local record = HoverboardService.record(w.data)
		T.eq(record.Owned.TimberDrifter, true, "a real board stays")
		T.eq(record.Owned.Nope, nil, "unknown ids leave")
		T.eq(record.Owned.CartCruiser, nil, "non-true values leave")
		T.eq(record.Owned[5], nil, "non-string keys leave")
		T.eq(record.Equipped, "", "an unowned equipped board becomes none")
		T.eq(type(record.Passes), "table", "an old save gets the Passes record")
		w.data.Hoverboards = {
			Owned = { TerraForgeCustom = true, NeonComet = true },
			Equipped = "NeonComet",
			Passes = { TerraForgeCustom = true, RoyalPhoenix = true, Nope = true, TimberDrifter = "yes" },
		}
		record = HoverboardService.record(w.data)
		T.eq(record.Passes.TerraForgeCustom, true, "a pass mark on an owned board stays")
		T.eq(record.Owned.NeonComet, nil, "the removed Neon Comet (owner 2026-10-25) leaves")
		T.eq(record.Equipped, "", "an equipped Neon Comet becomes none")
		T.eq(record.Passes.RoyalPhoenix, nil, "a pass mark without the board leaves")
		T.eq(record.Passes.Nope, nil, "unknown ids leave")
		T.eq(record.Passes.TimberDrifter, nil, "non-true values leave")
		w.data.Hoverboards = "junk"
		record = HoverboardService.record(w.data)
		T.eq(type(record.Owned), "table", "rebuilt")
		T.eq(type(record.Passes), "table", "rebuilt")
		T.eq(record.Equipped, "", "rebuilt")
		w.data.Hoverboards = nil
		T.falsy(HoverboardService.owns(w.data, "TimberDrifter"), "missing record = nothing owned")
		T.eq(HoverboardService.equipped(w.data), nil, "nothing equipped")
	end)

	withWorld("hoverboards: a game pass grants the board once and a refund takes back only it", function(w)
		local entry = {
			Key = "HoverboardCustom",
			Kind = "GamePass",
			Id = 1,
			Robux = 49,
			Name = "Terra Forge Custom",
			Grant = "Hoverboard",
			BoardId = "TerraForgeCustom",
		}
		local unlocked = 0
		local function countUnlocked()
			unlocked = 0
			for _, note in w.notes do
				if note.Name == "Notify" and string.find(note.A.Text, "unlocked", 1, true) then
					unlocked += 1
				end
			end
		end
		w.data.Hoverboards.Owned.CartCruiser = true
		w.data.Hoverboards.Equipped = "CartCruiser"
		T.truthy(h.grant(w.player, w.data, entry), "granted: the save changed")
		T.falsy(h.grant(w.player, w.data, entry), "the next load: nothing new")
		countUnlocked()
		T.eq(unlocked, 1, "unlocked said once")
		T.eq(w.data.Hoverboards.Equipped, "TerraForgeCustom", "the faster board is equipped")
		T.truthy(w.act({ Action = "Ride", On = true }).Ok, "ride the pass board")
		T.eq(w.attr(), "TerraForgeCustom", "on it")
		T.truthy(h.revoke(w.player, w.data, entry), "refund: revoked")
		T.eq(w.data.Hoverboards.Owned.TerraForgeCustom, nil, "the pass board left")
		T.eq(w.data.Hoverboards.Owned.CartCruiser, true, "the coin board stays")
		T.eq(w.data.Hoverboards.Equipped, "", "unequipped")
		T.eq(w.attr(), nil, "got off")
		T.eq(w.player.humanoid.HipHeight, 2, "HipHeight back")
		T.falsy(h.revoke(w.player, w.data, entry), "a second revoke changes nothing")
		local coinEntry = { Key = "X", Kind = "GamePass", Id = 2, Robux = 1, Name = "X", Grant = "Hoverboard", BoardId = "CartCruiser" }
		T.falsy(h.revoke(w.player, w.data, coinEntry), "a coin board is never revoked")
		T.eq(w.data.Hoverboards.Owned.CartCruiser, true, "still owned")
		-- Robux boards still can't be bought for coins
		w.data.Coins = 1e12
		T.eq(w.act({ Action = "Buy", Board = "TerraForgeCustom" }).Reason, "Robux", "only through the pass")
	end)
end
