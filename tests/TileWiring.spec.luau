--[[
	The owner's picture tiles, wired as the game wires them (review 2026-11-07: no spec ran the
	controllers): HudController builds the HUD, SideMenuController claims the tiles and builds the
	More flyout, and every tile's press is fired (Loader.press) under a stand-in LocalPlayer. Trade
	only says "coming soon" (never a paid window), More opens its flyout, a tile behind it shuts it
	and opens its own window, the hidden entries have no tile, and HudController hides the offers
	where they would meet the boost corner.
]]

return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Enum = roblox.Enum
	local Vector2 = roblox.Vector2

	local C = "StarterPlayer.StarterPlayerScripts.Client."
	local game = Loader.game
	-- the controllers that read the LocalPlayer when they load: loaded anew in every asClient
	local FRESH = {
		C .. "Controllers.HudController",
		C .. "Controllers.SideMenuController",
		C .. "Controllers.EmoteController",
		C .. "Controllers.HoverboardController",
	}

	local function signal()
		local s = {}
		function s.Connect()
			return { Connected = true, Disconnect = function() end }
		end
		function s.Once()
			return { Connected = true, Disconnect = function() end }
		end
		function s.Wait() end
		return s
	end

	-- (a list of { table, key, value }: set for the body, then put back)
	local function patched(list: { { any } }, body: () -> ())
		local saved = {}
		for i, entry in list do
			saved[i] = rawget(entry[1], entry[2])
			rawset(entry[1], entry[2], entry[3])
		end
		local ok, err = pcall(body)
		for i = #list, 1, -1 do
			rawset(list[i][1], list[i][2], saved[i])
		end
		if not ok then
			error(err, 0)
		end
	end

	-- Runs `body(w)` as a client on a `size` screen (touch or a mouse), presses recorded.
	local function asClient(size: Vector2, touch: boolean, body: (w: any) -> ())
		local Workspace = game:GetService("Workspace")
		local UIS = game:GetService("UserInputService")
		local Gui = game:GetService("GuiService")
		local Players = game:GetService("Players")
		local CAS = game:GetService("ContextActionService")
		local Tween = game:GetService("TweenService")
		local Run = game:GetService("RunService")
		local playerGui = Instance.new("PlayerGui")
		local me = {
			Name = "Me",
			UserId = 1,
			PlayerGui = playerGui,
			Character = nil,
			CharacterAdded = signal(),
			CharacterRemoving = signal(),
			AttributeChanged = signal(),
			WaitForChild = function()
				return playerGui
			end,
			FindFirstChild = function()
				return nil
			end,
			FindFirstChildOfClass = function(_, class: string)
				return if class == "PlayerGui" then playerGui else nil
			end,
			GetAttribute = function()
				return nil
			end,
			GetAttributeChangedSignal = function()
				return signal()
			end,
		}
		local w: any = {
			binds = {},
			toasts = {},
			calls = {},
			last = if touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1,
			playerGui = playerGui,
		}
		local camera = { ViewportSize = size, GetPropertyChangedSignal = signal }
		local function bind(_, name: string, _fn: any, _button: any, ...: any)
			for _, key in { ... } do
				w.binds[key] = name
			end
		end
		local function bindAt(_, name: string, _fn: any, _button: any, _priority: any, ...: any)
			for _, key in { ... } do
				w.binds[key] = name
			end
		end
		patched({
			{ Players, "LocalPlayer", me },
			{ Workspace, "CurrentCamera", camera },
			{ UIS, "TouchEnabled", touch },
			{ UIS, "MouseEnabled", not touch },
			{ UIS, "GamepadEnabled", false },
			{ UIS, "LastInputTypeChanged", signal() },
			{
				UIS,
				"GetLastInputType",
				function()
					return w.last
				end,
			},
			{
				UIS,
				"GetStringForKeyCode",
				function(_, key: any)
					return key.Name
				end,
			},
			{
				UIS,
				"GetImageForKeyCode",
				function()
					return ""
				end,
			},
			{
				UIS,
				"GetGamepadConnected",
				function()
					return false
				end,
			},
			{
				Gui,
				"IsTenFootInterface",
				function()
					return false
				end,
			},
			{
				Gui,
				"GetGuiInset",
				function()
					return Vector2.new(0, 58), Vector2.new(0, 0)
				end,
			},
			{ Gui, "GetPropertyChangedSignal", signal },
			{
				Run,
				"IsServer",
				function()
					return false
				end,
			},
			{
				Run,
				"IsClient",
				function()
					return true
				end,
			},
			{
				Run,
				"IsStudio",
				function()
					return false
				end,
			},
			{ Run, "Heartbeat", signal() },
			{ Run, "RenderStepped", signal() },
			{ Run, "Stepped", signal() },
			{ CAS, "BindAction", bind },
			{ CAS, "BindActionAtPriority", bindAt },
			{ CAS, "UnbindAction", function() end },
			{
				Tween,
				"Create",
				function()
					return { Play = function() end, Cancel = function() end, Completed = signal() }
				end,
			},
		}, function()
			-- (fresh controllers: the cached ones read another spec's stand-in LocalPlayer when they loaded)
			Loader.withFresh(FRESH, function()
				Loader.recordingPresses = true
				local ok, err = pcall(body, w)
				Loader.recordingPresses = false
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end

	-- HudController + SideMenuController as the game starts them; MenuPanels' calls and the
	-- toasts are recorded. Returns the HUD's refs.
	local function startMenu(w: any): any
		local HudController = Loader.requirePath(C .. "Controllers.HudController")
		local SideMenuController = Loader.requirePath(C .. "Controllers.SideMenuController")
		local MenuPanels = Loader.requirePath(C .. "Util.MenuPanels")
		local Sfx = Loader.requirePath(C .. "Effects.Sfx")
		local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
		local HudBubble = Loader.requirePath(C .. "UI.HudBubble")
		local saved = { HudController.toast, MenuPanels.controller, MenuPanels.isOpen, MenuPanels.call, Sfx.play, Net.listen, Net.send }
		local hook = HudBubble.onMoreToggled
		w.restore = function()
			HudController.toast, MenuPanels.controller, MenuPanels.isOpen, MenuPanels.call, Sfx.play, Net.listen, Net.send =
				table.unpack(saved)
			HudBubble.onMoreToggled = hook -- (SideMenuController's, set by its init)
		end
		Net.listen = function() end
		Net.send = function() end
		HudController.toast = function(text: string)
			table.insert(w.toasts, text)
		end
		MenuPanels.controller = function(name: string)
			return { Stand = name }
		end
		MenuPanels.isOpen = function()
			return false
		end
		MenuPanels.call = function(name: string, fn: string)
			table.insert(w.calls, `{name}.{fn}`)
			return fn == "open"
		end
		Sfx.play = function() end
		HudController.init()
		SideMenuController.init()
		return HudController.refs()
	end

	local function inRound(body: () -> ())
		local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
		local UIConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.UIConfig")
		local look, light = PopTheme.Look, UIConfig.LightUI
		PopTheme.setLook("Round")
		UIConfig.LightUI = true
		local ok, err = pcall(body)
		PopTheme.setLook(look)
		UIConfig.LightUI = light
		if not ok then
			error(err, 0)
		end
	end

	T.test("TileWiring: every left tile and every tile behind More does what it says (his 1402 x 490 window)", function()
		-- (review 2026-11-08: the run order mattered) a cached HudController that another spec's
		-- stand-in, with a Folder for its PlayerGui, loaded first: asClient runs its own fresh copy
		local Players = game:GetService("Players")
		patched({ { Players, "LocalPlayer", { Name = "Other", PlayerGui = Instance.new("Folder") } } }, function()
			Loader.requirePath(C .. "Controllers.HudController")
		end)
		inRound(function()
			asClient(Vector2.new(1402, 490), false, function(w)
				local ok, err = pcall(function()
					local hud = startMenu(w)
					T.eq(hud.Gui.Parent, w.playerGui, "the HUD is built in this client's own PlayerGui")
					local HudBubble = Loader.requirePath(C .. "UI.HudBubble")
					local menu = hud.Menu
					local flyout = hud.Gui:FindFirstChild("MoreFlyout")
					T.truthy(flyout, "the More flyout is built")
					local function press(where: Instance, id: string): (boolean, { string }, { string })
						table.clear(w.calls)
						table.clear(w.toasts)
						local holder = where:FindFirstChild(id) :: any
						T.truthy(holder and holder.Visible, id .. ": shown")
						local fired = Loader.press(holder:FindFirstChild("Face"))
						return fired, table.clone(w.calls), table.clone(w.toasts)
					end
					-- the side menu's tiles on the left open their own windows
					for id, controller in
						{
							Store = "StoreController",
							Rebirth = "RebirthController",
							Golems = "GolemController",
							Elevator = "ElevatorController",
						}
					do
						local fired, calls = press(menu, id)
						T.truthy(fired, id .. ": wired")
						T.eq(calls[1], controller .. ".open", id .. ": opens its window")
					end
					-- Trade only says so: never a window, above all never the paid Store
					local fired, calls, toasts = press(menu, "Trade")
					T.truthy(fired, "Trade: wired")
					T.eq(#calls, 0, "Trade opens no window")
					T.eq(toasts[1], "Trade is coming soon!", "Trade says it's coming")
					-- More opens its flyout and shuts it again; it says nothing is coming
					T.falsy((flyout :: any).Visible, "the flyout starts shut")
					fired, calls, toasts = press(menu, "More")
					T.truthy(fired, "More: wired")
					T.truthy((flyout :: any).Visible, "More opens the flyout")
					T.eq(#calls + #toasts, 0, "and nothing else")
					press(menu, "More")
					T.falsy((flyout :: any).Visible, "and shuts it")
					-- behind More, in his order: each opens its window and shuts the flyout
					local order = {}
					for _, holder in (flyout :: any):GetChildren() do
						if holder:IsA("Frame") and holder.Visible then
							table.insert(order, holder)
						end
					end
					table.sort(order, function(a, b)
						return a.LayoutOrder < b.LayoutOrder
					end)
					local names = {}
					for _, holder in order do
						table.insert(names, holder.Name)
					end
					T.eq(table.concat(names, ","), "Codex,Settings,Quests,Shop", "Index, Settings, Daily, Boosts (Spin: WheelController)")
					for id, controller in
						{ Codex = "CodexController", Settings = "SettingsController", Quests = "QuestController", Shop = "BoostController" }
					do
						HudBubble.toggleMore(menu, true)
						local behindFired, behindCalls = press(flyout :: any, id)
						T.truthy(behindFired, id .. ": wired")
						T.eq(behindCalls[1], controller .. ".open", id .. ": opens its window")
						T.falsy((flyout :: any).Visible, id .. ": the flyout shuts")
					end
					-- Spin, claimed as WheelController claims it: behind More, the same tile twice, a press shuts
					-- the flyout; its FREE! shows on More
					local spin = HudBubble.claimTile(menu, "Wheel", { Label = "SPIN", IconName = "Wheel" })
					T.truthy(spin:IsDescendantOf(flyout), "Spin stands behind More")
					T.eq(HudBubble.claimTile(menu, "Wheel"), spin, "a second claim gets the same tile")
					T.eq(spin.Parent.LayoutOrder, 4, "Spin fourth, before Boosts")
					HudBubble.setTileBadge(spin, 1, true)
					local more = (menu:FindFirstChild("More") :: any).Face
					T.truthy(more:FindFirstChild("Sticker"), "More wears FREE! while a spin is free")
					HudBubble.setTileBadge(spin, 0, false)
					T.falsy(more:FindFirstChild("Sticker") and more.Sticker.Visible, "and drops it after")
					HudBubble.toggleMore(menu, true)
					Loader.press(spin)
					T.falsy((flyout :: any).Visible, "a press on Spin shuts the flyout")
					-- no tile for what has no picture or no place (the owner, 2026-11-07)
					for _, id in { "Collection", "Boards", "Hoverboards", "Emotes", "Wheel", "Codex", "Settings", "Quests", "Shop" } do
						local holder = menu:FindFirstChild(id) :: any
						T.falsy(holder and holder.Visible, id .. ": not on the left")
					end
					for _, id in { "Collection", "Boards", "Hoverboards", "Emotes" } do
						T.falsy((flyout :: any):FindFirstChild(id), id .. ": not behind More")
					end
				end)
				w.restore()
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	T.test("TileWiring: phones keep More and drop the coming-soon Trade; the touch rows stay at 44 pt", function()
		inRound(function()
			asClient(Vector2.new(844, 390), true, function(w)
				local ok, err = pcall(function()
					local hud = startMenu(w)
					local HudBubble = Loader.requirePath(C .. "UI.HudBubble")
					local trade = hud.Menu:FindFirstChild("Trade") :: any
					T.falsy(trade and trade.Visible, "no Trade tile on a phone")
					local more = hud.Menu:FindFirstChild("More") :: any
					T.truthy(more and more.Visible, "More on a phone")
					Loader.press(more.Face)
					T.truthy((hud.Gui:FindFirstChild("MoreFlyout") :: any).Visible, "and it opens")
				end)
				w.restore()
				if not ok then
					error(err, 0)
				end
			end)
			local HudBubble = Loader.requirePath(C .. "UI.HudBubble")
			for _, phone in { { 844, 390, 6 }, { 667, 375, 4 }, { 568, 320, 4 } } do
				local scale = HudBubble.scaleFor(Vector2.new(phone[1], phone[2]))
				local layout = HudBubble.layout(scale, phone[1], true, false, phone[2] - 36)
				T.eq(layout.Columns, phone[3], `{phone[1]} x {phone[2]}: {phone[3]} a row at the top`)
				T.truthy(layout.Tile * scale >= 44 - 0.5, `{phone[1]} x {phone[2]}: 44 pt tiles`)
			end
		end)
	end)

	T.test("TileWiring: HudController hides the offers where they'd meet the boost corner, and on touch", function()
		inRound(function()
			asClient(Vector2.new(1402, 490), false, function(w)
				local ok, err = pcall(function()
					local HudController = Loader.requirePath(C .. "Controllers.HudController")
					local hud = startMenu(w)
					local offers = hud.Gui:FindFirstChild("Offers") :: any
					T.truthy(offers, "the offers on his mouse window")
					HudController.refreshOffers(Vector2.new(1402, 490 - 58))
					T.truthy(offers.Visible, "1402 x 490: shown")
					HudController.refreshOffers(Vector2.new(1402, 368 - 58))
					T.falsy(offers.Visible, "1402 x 368: they'd reach the clover, hidden")
					w.last = Enum.UserInputType.Touch
					HudController.refreshOffers(Vector2.new(1402, 490 - 58))
					T.falsy(offers.Visible, "a touch: hidden")
				end)
				w.restore()
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	-- (owner 2026-11-07: "odstranit i klávesu N") the round look binds no emote key and adds no Emotes tile
	T.test("TileWiring: the round look has no emotes: no N key, no Emotes tile behind More", function()
		inRound(function()
			asClient(Vector2.new(1402, 490), false, function(w)
				local ok, err = pcall(function()
					local hud = startMenu(w)
					local AnimConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AnimConfig")
					local EmoteController = Loader.requirePath(C .. "Controllers.EmoteController")
					-- (with the emotes switched on, so only the round look keeps them out)
					patched({ { AnimConfig, "Emotes", true } }, function()
						EmoteController.start()
					end)
					for key, name in w.binds do
						T.truthy(key ~= EmoteController.Key, `no emote key ({name})`)
					end
					local flyout = hud.Gui:FindFirstChild("MoreFlyout") :: any
					T.falsy(flyout:FindFirstChild(EmoteController.TileId), "no Emotes tile behind More")
				end)
				w.restore()
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	-- (owner 2026-11-07) the Hoverboard tile opens the window; while riding it stops the ride at once
	T.test("TileWiring: the Hoverboard tile opens the window, and stops a ride while riding", function()
		inRound(function()
			asClient(Vector2.new(1402, 490), false, function(w)
				local ok, err = pcall(function()
					local hud = startMenu(w)
					local HoverboardController = Loader.requirePath(C .. "Controllers.HoverboardController")
					HoverboardController._test.buildRide()
					local holder = hud.Menu:FindFirstChild("Ride") :: any
					T.truthy(holder and holder.Visible, "the Hoverboard tile")
					local said = {}
					for _, riding in { false, true } do
						table.clear(said)
						patched({
							{
								HoverboardController,
								"isRiding",
								function()
									return riding
								end,
							},
							{
								HoverboardController,
								"toggleRide",
								function()
									table.insert(said, "toggleRide")
								end,
							},
							{
								HoverboardController,
								"toggle",
								function()
									table.insert(said, "toggle")
								end,
							},
						}, function()
							T.truthy(Loader.press(holder:FindFirstChild("Face")), "the tile is wired")
						end)
						local want = if riding then "toggleRide" else "toggle"
						T.eq(table.concat(said, ","), want, if riding then "riding: it stops the ride" else "walking: it opens the window")
					end
				end)
				w.restore()
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	-- (owner 2026-11-07 23:20: "dal bych verzi A jenom ten train dej prosim pod to ale udelj ty velke
	-- dlazdice") the TRAIN chip under the tiles in every mouse window; his small Studio window
	-- keeps the big tiles three a row, a PC two a row
	T.test("TileWiring: the TRAIN chip is under the tiles in every mouse window; his window keeps them big", function()
		inRound(function()
			local HudBubble = Loader.requirePath(C .. "UI.HudBubble")
			for _, case in { { 1402, 490, 3 }, { 995, 485 }, { 1402, 368 }, { 1280, 720, 2 }, { 1280, 600, 2 }, { 1920, 1080, 2 } } do
				local where = `{case[1]} x {case[2]}`
				local scale = HudBubble.scaleFor(Vector2.new(case[1], case[2]))
				local layout = HudBubble.layout(scale, case[1], false, false, case[2] - 58)
				T.eq(layout.Chip, "Under", where .. ": the chip under the tiles")
				T.eq(layout.ChipStack, true, where .. ": the stacked chip, as wide as them")
				if case[3] then
					T.eq(layout.Columns, case[3], `{where}: {case[3]} a row`)
				end
			end
			-- his window: the big tiles (variant A's size), the chip under them above the floaters
			local scale = HudBubble.scaleFor(Vector2.new(1402, 490))
			local height = (490 - 58) / scale
			local his = HudBubble.layout(scale, 1402, false, false, 490 - 58)
			T.eq(his.Tile, HudBubble.RoundMouseTile, "1402 x 490: the big tiles")
			local rows = math.ceil(HudBubble.roundCount(his) / his.Columns)
			local bottom = HudBubble.menuTop(his)
				+ rows * his.Tile
				+ (rows - 1) * his.TileGap
				+ HudBubble.StackGap
				+ HudBubble.stackChipHeight(his)
			T.truthy(bottom <= HudBubble.roundFloor(his, height) + 1e-6, `1402 x 490: the chip ends at {bottom}, above the floaters`)
		end)
	end)

	-- (review 2026-11-07: a second R at the temple opened the Hoverboards window unseen under the hatch)
	T.test("TileWiring: every key HoverboardController exports is sunk while an egg opens", function()
		local fs = require("@lune/fs")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/HoverboardController.luau")
		-- (CapsuleController reads the LocalPlayer when it loads: its OWNED_KEYS table is read as text)
		local capsule = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		capsule = capsule:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "") -- (a commented-out entry doesn't count)
		local list = capsule:match("\nlocal OWNED_KEYS = (%b{})")
		T.truthy(list, "CapsuleController's OWNED_KEYS")
		local owned = {}
		for name in (list :: string):gmatch('{ "HoverboardController", "(%w+)" }') do
			owned[name] = true
		end
		-- (the gamepad's buttons are always sunk: SINK_KEYS)
		local always = capsule:match("\nlocal SINK_KEYS = (%b{})") or ""
		local found = 0
		for name, key in source:gmatch("\nHoverboardController%.(%w+) = Enum%.KeyCode%.(%w+)") do
			found += 1
			local sunk = owned[name] or always:find(`Enum.KeyCode.{key},`, 1, true) ~= nil
			T.truthy(sunk, `HoverboardController.{name} ({key}): sunk under an opening (CapsuleController OWNED_KEYS)`)
		end
		T.truthy(found >= 2, "H and R are found")
	end)

	-- (review 2026-11-07: "Stop" on the Ride picture was 8.7 pt on a phone) the live word on a picture tile
	T.test("TileWiring: a picture tile's word reads: 13 pt on a phone's 44 pt tile, 21 px on a TV", function()
		inRound(function()
			local HudBubble = Loader.requirePath(C .. "UI.HudBubble")
			for _, case in { { 72, 0.62, 13 }, { 57, 1.25, 21 } } do
				local holder = Instance.new("Frame")
				local face = HudBubble.tile(holder, { Name = "Ride", Label = "Stop", Icon = "hoverboard", Role = "Ride", Size = case[1] })
				T.truthy(face:GetAttribute("TileArt"), "the Ride tile wears his picture")
				local word = face:FindFirstChild("Label") :: any
				local fit = word:FindFirstChildOfClass("UITextSizeConstraint") :: any
				T.truthy(fit.MaxTextSize * case[2] >= case[3] - 0.5, `{case[1]} u at {case[2]}: the word {fit.MaxTextSize} u`)
				T.truthy(word.Size.Y.Scale * case[1] * case[2] >= case[3], `{case[1]} u at {case[2]}: its box tall enough`)
				holder:Destroy()
			end
		end)
	end)

	-- (HoverboardController.start spawns its endless LOD loop, which would keep the spec run alive: its
	-- key wiring is read as text; the tile's press runs above, through _test.buildRide) H rides, R
	-- opens the window, and the window's RIDE / STOP follows a knock-off and a picked card
	T.test("TileWiring: the Hoverboard tile, H and R, and the window's RIDE / STOP are wired", function()
		local fs = require("@lune/fs")
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/HoverboardController.luau")
		local function has(text: string, what: string)
			T.truthy(source:find(text, 1, true), what)
		end
		has("BindAction(WINDOW_ACTION, onWindowKey, false, HoverboardController.WindowKey)", "R opens the window")
		has("BindAction(RIDE_ACTION, onRideKey, false, HoverboardController.Key, HoverboardController.GamepadKey)", "H rides")
		has(
			'if HoverboardController.isRiding() then\n\t\t\t\tHoverboardController.toggleRide()\n\t\t\telse\n\t\t\t\tSfx.play("UIClick")\n\t\t\t\tHoverboardController.toggle()',
			"the tile stops a ride, else opens the window"
		)
		local update = source:match("\nupdateRideButton = function%(%)(.-)\nend\n")
		T.truthy(update and update:find("HoverboardView.setRideWord(view, riding)", 1, true), "a knock-off sets the window's word")
		local card = source:match("\nlocal function onCard%(.-%)(.-)\nend\n")
		T.truthy(card and card:find("HoverboardView.setRideWord(view, HoverboardController.isRiding())", 1, true), "a picked card too")
	end)

	-- (review 2026-11-07) a TV reporting 1280 x 720: the tiles and the TRAIN chip keep off the money
	T.test("TileWiring: a small TV (1280 x 720 and under) keeps the tiles and the TRAIN chip off the money", function()
		inRound(function()
			local HudBubble = Loader.requirePath(C .. "UI.HudBubble")
			local TrainView = Loader.requirePath(C .. "UI.TrainView")
			local function overlap(a: { number }, b: { number }): boolean
				return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
			end
			for _, case in { { 1280, 720, 58 }, { 1280, 720, 36 }, { 1024, 576, 36 }, { 960, 540, 36 }, { 854, 480, 36 } } do
				local inset = `{case[1]} x {case[2]}, inset {case[3]}`
				local scale = HudBubble.scaleFor(Vector2.new(case[1], case[2]))
				local width, height = case[1] / scale, (case[2] - case[3]) / scale
				local refs = HudBubble.buildGame(scale, case[1], false, true, case[2] - case[3]) :: any
				local function rectOf(object: any): { number }
					local x = width * object.Position.X.Scale + object.Position.X.Offset - object.AnchorPoint.X * object.Size.X.Offset
					local y = height * object.Position.Y.Scale + object.Position.Y.Offset - object.AnchorPoint.Y * object.Size.Y.Offset
					return { x, y, x + object.Size.X.Offset, y + object.Size.Y.Offset }
				end
				TrainView.useHud(refs.Gui)
				local chip = TrainView.chipSize(refs.Gui:GetAttribute("ChipStack") == true)
				TrainView.useHud(nil)
				local left, top = refs.Gui:GetAttribute("ChipLeft"), refs.Gui:GetAttribute("ChipTop")
				local chipRect = { left, top, left + chip.X, top + chip.Y }
				local money = rectOf(refs.CoinsPanel)
				T.falsy(overlap(rectOf(refs.Menu), money), `{inset}: the tiles clear of the money`)
				T.falsy(overlap(chipRect, money), `{inset}: the chip clear of the money`)
				refs.Gui:Destroy()
			end
		end)
	end)
end
