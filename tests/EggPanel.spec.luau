-- The EGGS temple's egg panels (owner 2026-10-28, UI/EggPanel +
-- Controllers/EggPanelController): the odds a panel shows are the table the
-- server rolls (Triple Lucky too), Auto is never offered on a Robux egg,
-- the nearest egg takes the panel (with a little hysteresis), golems the
-- player has none of are silhouettes on coin eggs only, the layout keeps
-- Auto at 44 pt on phones and every card inside the white panel, the fade
-- reaches every transparency, and the temple's three eggs are found in the
-- built stall with their prompts in front. Round 2 (owner: "a big E, open
-- by 10, even cooler"): Open 1 / 3 / 10 show the window's own buys, their
-- keys are free at the temple, the big E is a 44 pt target on phones,
-- confetti and the egg's hop are bounded, flashes stay under 3 a second.
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector2 = roblox.Vector2
	local Vector3 = roblox.Vector3
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
	local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")
	local EggPrompt = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPrompt")
	local Confetti = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Confetti")
	local DecorController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.DecorController")
	local PromptConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.PromptConfig")
	local MonetizationConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonetizationConfig")

	local TEMPLE = { "Stone", "Royal", "Crystal" }

	T.test("EggPanel: the odds on the cards are the table the server rolls (normal and Triple Lucky)", function()
		for _, id in TEMPLE do
			for _, lucky in { false, true } do
				local lines = EggPanel.lines(id, lucky, {})
				local table_ = CapsuleConfig.odds(id, lucky)
				local window = CapsuleView.oddsLines(id, lucky)
				T.eq(#lines, #table_, `{id} {lucky}: a card per golem`)
				T.eq(#lines, #window, `{id} {lucky}: the window lists the same golems`)
				local sum = 0
				local from = Rarity.ById[CapsuleConfig.ById[id].LuckyFrom].Order
				for i, line in lines do
					T.eq(line.Golem, table_[i].Golem, `{id} {lucky} card {i}: the roll table's order`)
					T.eq(line.Chance, table_[i].Chance, `{id} {lucky} {line.Golem}: the exact chance`)
					T.eq(line.Chance, window[i].Chance, `{id} {lucky} {line.Golem}: the window's chance`)
					T.eq(line.Rarity, GolemConfig.ById[line.Golem].Rarity)
					T.eq(line.Text, EggPanel.chanceText(line.Chance))
					T.eq(
						line.Lucky,
						lucky and GolemConfig.order(line.Golem) >= from,
						`{line.Golem}: x3 only on the golems Triple Lucky triples`
					)
					sum += line.Chance
				end
				T.near(sum, 1, 1e-9, `{id} {lucky}: the chances add up to 100 %`)
				-- the server's roll lands in the card whose share of [0, 1) holds the roll
				local acc = 0
				for _, line in lines do
					for _, at in { 0.001, 0.5, 0.999 } do
						local r = acc + line.Chance * at
						local rolled = CapsuleService.roll(id, 1, lucky, {
							NextNumber = function()
								return r
							end,
						})
						T.eq(rolled[1], line.Golem, `{id} {lucky}: a roll of {r} wakes {line.Golem}`)
					end
					acc += line.Chance
				end
			end
		end
		-- a boosted golem's card shows its boosted chance, three times the normal one
		local normal = EggPanel.lines("Crystal", false, {})
		local boosted = EggPanel.lines("Crystal", true, {})
		for i, line in boosted do
			if line.Lucky then
				T.near(line.Chance, normal[i].Chance * CapsuleConfig.TripleLucky, 1e-12, line.Golem .. " x3")
			end
		end
	end)

	T.test("EggPanel: chance and price texts (three significant digits, three decimals at most)", function()
		T.eq(EggPanel.chanceText(0.45), "45%")
		T.eq(EggPanel.chanceText(0.64), "64%")
		T.eq(EggPanel.chanceText(0.205), "20.5%")
		T.eq(EggPanel.chanceText(0.125), "12.5%")
		T.eq(EggPanel.chanceText(0.0255), "2.55%")
		T.eq(EggPanel.chanceText(0.0028), "0.28%")
		T.eq(EggPanel.chanceText(0.0003), "0.03%")
		T.eq(EggPanel.chanceText(0.06), "6%")
		T.eq(EggPanel.chanceText(1), "100%")
		T.eq(EggPanel.chanceText(0), "0%")
		T.eq(EggPanel.chanceText(0 / 0), "0%", "junk")
		T.eq(EggPanel.chanceText(1e-7), "<0.001%", "a golem that can come out never reads 0%")
		for _, id in TEMPLE do
			for _, lucky in { false, true } do
				for _, line in EggPanel.lines(id, lucky, {}) do
					local digits = string.gsub(string.match(line.Text, "^[%d%.]+") or "", "%.", "")
					digits = string.gsub(digits, "^0+", "")
					T.truthy(#digits >= 1 and #digits <= 3, `{line.Text}: at most three significant digits`)
					local decimals = string.match(line.Text, "%.(%d+)%%$")
					T.truthy(decimals == nil or #decimals <= 3, `{line.Text}: at most three decimals`)
				end
			end
		end
		T.eq(EggPanel.priceText(2500), "2,500")
		T.eq(EggPanel.priceText(750000), "750K")
		T.eq(EggPanel.priceText(3.75e6), "3.75M", "Stone at blaster level 10")
		T.eq(EggPanel.promptText(false, 2500, "$2.5K", true), "$2,500")
		T.eq(EggPanel.promptText(true, nil, "R$ 49", true), "R$ 49")
		T.eq(EggPanel.promptText(true, nil, "Coming soon", false), "Coming soon", "a Robux egg that isn't live")
	end)

	T.test("EggPanel: Auto is never offered on a Robux egg", function()
		T.truthy(EggPanel.autoAllowed("Stone"))
		T.truthy(EggPanel.autoAllowed("Crystal"))
		for _, capsule in CapsuleConfig.List do
			if capsule.Currency == "Robux" then
				T.falsy(EggPanel.autoAllowed(capsule.Id), capsule.Id .. ": a Robux egg has no Auto")
			end
		end
		T.falsy(EggPanel.autoAllowed("NoSuchEgg"), "an unknown egg")
		-- the controller makes the Auto prompt and turns Auto on only behind autoAllowed
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/EggPanelController.luau")
		local code = string.gsub(string.gsub(source, "%-%-%[(=*)%[.-%]%1%]", ""), "%-%-[^\n]*", "")
		local _, makes = string.gsub(code, 'Role = "Second"', "")
		T.eq(makes, 1, "one Auto prompt maker")
		local guard = string.find(code, "if EggPanel.autoAllowed(id) then", 1, true)
		local made = string.find(code, 'Role = "Second"', 1, true)
		T.truthy(guard and made and guard < made, "the Auto prompt is made for coin eggs only")
		local toggle = string.match(code, "function EggPanelController%.toggleAuto.-\nend")
		T.truthy(toggle and string.find(toggle, "not EggPanel.autoAllowed(id)", 1, true), "Auto never turns on for a Robux egg")
	end)

	T.test("EggPanel: the nearest egg takes the panel (in range, with hysteresis)", function()
		local spots = {
			{ Id = "Stone", Center = Vector3.new(7.2, 4, 0) },
			{ Id = "Royal", Center = Vector3.new(0, 5, 2) },
			{ Id = "Crystal", Center = Vector3.new(-7.2, 4, 0) },
		}
		T.eq(EggPanel.nearest(spots, Vector3.new(7, 3, -5), nil), "Stone", "in front of Stone")
		T.eq(EggPanel.nearest(spots, Vector3.new(-6, 3, -5), nil), "Crystal")
		T.eq(EggPanel.nearest(spots, Vector3.new(0.5, 3, -4), nil), "Royal")
		T.eq(EggPanel.nearest(spots, Vector3.new(60, 3, 0), nil), nil, "far away: no panel")
		T.eq(EggPanel.nearest({}, Vector3.new(0, 0, 0), nil), nil, "no eggs streamed in")
		-- just past ShowRange: none comes up, but the one showing stays up to HideRange
		local edge = Vector3.new(7.2 + EggPanel.ShowRange + 0.5, 4, 0)
		T.eq(EggPanel.nearest(spots, edge, nil), nil, "not shown yet")
		T.eq(EggPanel.nearest(spots, edge, "Stone"), "Stone", "kept a little longer")
		T.eq(EggPanel.nearest(spots, Vector3.new(7.2 + EggPanel.HideRange + 0.1, 4, 0), "Stone"), nil, "then it goes")
		-- halfway between two eggs it doesn't flicker: the other must be SwitchMargin nearer
		local between = Vector3.new(3.6 - 0.4, 4, 0)
		T.eq(EggPanel.nearest(spots, between, "Royal"), "Royal", "Stone is a bit nearer, not enough")
		T.eq(EggPanel.nearest(spots, Vector3.new(6.8, 4, -1), "Royal"), "Stone", "clearly nearer: it switches")
		T.truthy(EggPanel.PromptDistance < EggPanel.ShowRange, "the prompt only works where the panel shows")
		T.truthy(EggPanel.HideRange > EggPanel.ShowRange)
	end)

	T.test("EggPanel: silhouettes for the golems the player has none of, on coin eggs only", function()
		local state = {
			Golems = {
				Owned = { { Id = 1, Kind = "PebbleGolem" }, { Id = 2, Kind = "EmberImp" }, "junk", { Id = 3 } },
				Equipped = { 1 },
				Pending = { { Kind = "RoseKnight", Paid = true } },
			},
		}
		local known = EggPanel.known(state)
		T.truthy(known.PebbleGolem and known.EmberImp, "the inventory")
		T.truthy(known.RoseKnight, "a paid golem waiting for room counts")
		T.falsy(known.CopperTinker)
		T.eq(next(EggPanel.known(nil)), nil, "no State yet: nothing known")
		T.eq(next(EggPanel.known({ Golems = "junk" })), nil, "junk")
		for _, line in EggPanel.lines("Stone", false, known) do
			T.eq(line.Silhouette, not known[line.Golem], `Stone {line.Golem}`)
		end
		local royal = EggPanel.lines("Royal", false, {})
		T.truthy(#royal > 0)
		for _, line in royal do
			T.falsy(line.Silhouette, `Royal {line.Golem}: a Robux egg shows every golem`)
		end
		T.falsy(EggPanel.silhouettes("Royal"))
		T.truthy(EggPanel.silhouettes("Crystal"))
		EggPanel.Silhouettes = false
		for _, line in EggPanel.lines("Stone", false, {}) do
			T.falsy(line.Silhouette, "switched off: every picture shows")
		end
		EggPanel.Silhouettes = true
	end)

	T.test("EggPanel: layout (columns, cards inside the panel, Auto 44 pt on phones)", function()
		T.eq(EggPanel.columns(3), 3)
		T.eq(EggPanel.columns(10), 5)
		T.eq(EggPanel.columns(14), 7)
		T.eq(EggPanel.columns(20), EggPanel.MaxColumns)
		for _, id in TEMPLE do
			local count = #EggPanel.lines(id, false, {})
			T.truthy(count <= EggPanel.MaxCards, id .. ": a slot per card")
			for _, touch in { false, true } do
				local l = EggPanel.layout(count, touch)
				T.eq(l.Height, l.Title + l.Body)
				T.eq(l.Rows * l.Columns >= count, true, "room for every card")
				for i = 1, count do
					local at = EggPanel.cardAt(l, i)
					T.truthy(at.X >= l.Pad - 0.01 and at.X + l.Card <= l.Width - l.Pad + 0.01, `{id} card {i}: inside left / right`)
					T.truthy(
						at.Y >= l.Pad + l.Head and at.Y + l.Card <= l.Body - l.Pad + 0.01,
						`{id} card {i}: under the head row, above the foot`
					)
				end
				if touch then
					T.truthy(l.Toggle.Y * EggPanel.PhoneScale >= EggPanel.MinTouch - 0.5, `{id}: Auto is 44 pt on a phone`)
				end
				if l.AutoInRow then
					T.eq(l.Toggle.Y, l.Open.Y, "touch: Auto is a button of the opens' row")
					local at = EggPanel.openAt(l, #CapsuleConfig.Counts + 1)
					T.truthy(at.X + l.Toggle.X <= l.Width - l.Pad + 0.5, "inside the panel")
				else
					T.truthy(l.Toggle.Y <= l.Head, "Auto fits the head row")
				end
				T.eq(l.Beside, touch, "beside the egg on touch, over it on PC")
				-- readable on a phone: the chance at least 8 pt (the project's floor)
				T.truthy(l.ChanceSize * EggPanel.PhoneScale >= 8, "the chance text is readable")
			end
		end
		-- a short last row is centred
		local l = EggPanel.layout(14, false)
		T.eq(EggPanel.cardAt(l, 1).X, EggPanel.cardAt(l, 8).X, "two full rows line up")
	end)

	T.test("EggPanel: the built panel (cards, silhouettes, x3, price, Auto, fade)", function()
		local refs = EggPanel.build()
		T.eq(refs.Gui.ClassName, "BillboardGui")
		T.truthy(refs.Gui.AlwaysOnTop, "over the temple's pillars and roof")
		T.eq(#refs.Cards, EggPanel.MaxCards)
		local known = { PebbleGolem = true }
		local lines = EggPanel.lines("Stone", true, known)
		local l = EggPanel.layout(#lines, true)
		EggPanel.apply(refs, "Stone", l, EggPanel.PhoneScale)
		EggPanel.setLines(refs, lines, nil)
		T.eq(refs.Title.Text, "Stone Egg")
		T.near(refs.Scale.Scale, EggPanel.PhoneScale, 1e-6)
		T.eq(refs.Gui.Size.X.Offset, math.ceil(l.Width * EggPanel.PhoneScale))
		local shown = 0
		for i, card in refs.Cards do
			if card.Frame.Visible then
				shown += 1
				local line = lines[i]
				T.eq(card.Chance.Text, line.Text)
				T.eq(card.Lucky.Visible, line.Lucky)
				T.eq(card.Picture:GetAttribute("Icon"), "golem_" .. line.Golem)
				local black = card.View.ImageColor3
				if line.Silhouette then
					T.truthy(black.R == 0 and black.G == 0 and black.B == 0, line.Golem .. ": black")
				else
					T.truthy(black.R == 1 and black.G == 1 and black.B == 1, line.Golem .. ": its colours")
				end
			end
		end
		T.eq(shown, #lines, "a card per golem, the other slots hidden")
		-- Royal: fewer cards, the spare slots hide
		local royal = EggPanel.lines("Royal", false, {})
		EggPanel.apply(refs, "Royal", EggPanel.layout(#royal, false), 1)
		EggPanel.setLines(refs, royal, nil)
		shown = 0
		for _, card in refs.Cards do
			shown += if card.Frame.Visible then 1 else 0
		end
		T.eq(shown, #royal)
		EggPanel.setPrice(refs, "Robux", "R$ 49", true)
		T.eq(refs.Price.Text, "R$ 49")
		T.falsy(refs.Coin.Visible, "no coin on a Robux price")
		EggPanel.setAuto(refs, EggPanel.autoAllowed("Royal"), false, "G", nil)
		T.falsy(refs.Toggle.Visible, "no Auto on the Royal egg")
		EggPanel.setPrice(refs, "Coins", "2,500", false)
		T.truthy(refs.Coin.Visible)
		EggPanel.setAuto(refs, true, true, "", nil)
		T.truthy(refs.Toggle.Visible)
		T.falsy(refs.Key.Visible, "touch: no key badge")
		EggPanel.setAuto(refs, true, false, "", "rbxasset://textures/ui/Controls/xboxB.png")
		T.truthy(refs.Glyph.Visible and refs.Key.Visible, "gamepad: the glyph")
		-- the fade reaches every transparency and comes back to the built values
		T.truthy(#refs.Fades > 40, `the fade list ({#refs.Fades})`)
		EggPanel.setFade(refs, 1)
		for _, fade in refs.Fades do
			T.eq((fade.Target :: any)[fade.Property], 1, fade.Target.Name .. "." .. fade.Property)
		end
		EggPanel.setFade(refs, 0)
		for _, fade in refs.Fades do
			T.eq((fade.Target :: any)[fade.Property], fade.Base)
		end
		local targets = EggPanel.touchTargets(refs)
		T.eq(targets[1], refs.Toggle)
	end)

	T.test("EggPanel: the temple's three eggs are found in the built stall, prompts in front", function()
		local Stall = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Capsules")
		local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
		local stall = Instance.new("Model")
		Stall.build(stall, Rng.new("Lobby/Districts/capsules"))
		local eggs = EggPanel.eggsIn(stall)
		local found = {}
		for id in eggs do
			table.insert(found, id)
		end
		table.sort(found)
		T.eq(table.concat(found, ","), "Crystal,Royal,Stone", "the three temple eggs")
		local front = LobbyLayout.frame(LobbyLayout.get("CapsuleStall")).LookVector
		for id, model in eggs do
			local center, top, prompt, bottom, half = EggPanel.spotOf(model, front)
			T.truthy(top > center.Y + 1, id .. ": the top is over the centre")
			T.truthy(bottom < center.Y - 1, id .. ": the foot is under it (the light ring)")
			T.truthy(half > 1 and half < 5, id .. ": a sane half width")
			local out = prompt - center
			T.near(out.Y, 0, 1e-6, id .. ": the prompt at the egg's middle")
			T.truthy(out:Dot(front) > 1.5, id .. ": the prompt in front of the egg, toward the plaza")
		end
		-- the eggs stand apart: each egg's prompt is nearest its own egg
		local spots = {}
		for id, model in eggs do
			local center = EggPanel.spotOf(model, front)
			table.insert(spots, { Id = id, Center = center })
		end
		for id, model in eggs do
			local _, _, prompt = EggPanel.spotOf(model, front)
			T.eq(EggPanel.nearest(spots, prompt, nil), id, id .. ": standing at its prompt shows its panel")
		end
		-- not the SKY EGG (its own podium) or a limited edition's capsule
		local sky = Instance.new("Model")
		sky:SetAttribute("Capsule", "Sky")
		T.eq(EggPanel.eggId(sky), nil)
		local shard = Instance.new("Model")
		shard:SetAttribute("Capsule", "Dragonforge")
		T.eq(EggPanel.eggId(shard), nil)
	end)

	T.test("EggPanel: Open 1 / 3 / 10 show the window's own buys (prices, grey when they can't be bought)", function()
		local NOW = 1_800_000_000
		local function state(level: number, owned: number): any
			local list = {}
			for i = 1, owned do
				list[i] = { Id = i, Kind = "PebbleGolem" }
			end
			return { PriceLevel = level, Golems = { Owned = list, Equipped = {}, NextId = owned + 1 }, Boosts = {} }
		end
		for _, level in { 1, 5, 10 } do
			local cards = CapsuleView.cards(state(level, 0), 1e15, false, NOW, nil, false)
			for _, card in cards do
				if card.Id == "Stone" or card.Id == "Crystal" then
					local specs = EggPanel.opens(card.Buys, card.Robux)
					T.eq(#specs, #CapsuleConfig.Counts, card.Id .. ": one button per count")
					for i, spec in specs do
						T.eq(spec.Count, CapsuleConfig.Counts[i], "the window's counts, in order")
						T.eq(
							spec.Price,
							EggPanel.priceText(CapsuleConfig.price(card.Id, spec.Count, level)),
							`{card.Id} x{spec.Count} at level {level}: the server's price`
						)
						T.truthy(spec.Enabled, "rich and room: buyable")
						T.falsy(spec.Robux)
					end
				elseif card.Id == "Royal" then
					local specs = EggPanel.opens(card.Buys, card.Robux)
					for _, spec in specs do
						T.truthy(spec.Robux)
						T.eq(spec.Price, "Coming soon", "ids still 0: Coming soon")
						T.falsy(spec.Enabled, "and grey")
					end
				end
			end
		end
		-- poor: Open 1 can be paid, Open 10 can't; a full inventory greys them all
		local price1 = CapsuleConfig.price("Stone", 1, 1)
		local poor = CapsuleView.cards(state(1, 0), price1 * 2, false, NOW, nil, false)
		for _, card in poor do
			if card.Id == "Stone" then
				local specs = EggPanel.opens(card.Buys, false)
				T.truthy(specs[1].Enabled, "Open 1: enough coins")
				T.falsy(specs[3].Enabled, "Open 10: not enough")
				T.eq(specs[3].Reason, "NoCoins")
			end
		end
		local full = CapsuleView.cards(state(1, GolemConfig.InventoryCap), 1e15, false, NOW, nil, false)
		for _, card in full do
			if card.Id == "Stone" then
				for _, spec in EggPanel.opens(card.Buys, false) do
					T.falsy(spec.Enabled, "a full golem inventory")
					T.eq(spec.Reason, "InventoryFull")
				end
			end
		end
		-- the Royal egg once its products are live: their Robux prices
		local p1 = MonetizationConfig.Products.RoyalCapsule1
		local old = p1.Id
		p1.Id = 1
		for _, card in CapsuleView.cards(state(1, 0), 0, false, NOW, nil, true) do
			if card.Id == "Royal" then
				local specs = EggPanel.opens(card.Buys, true)
				T.eq(specs[1].Price, `R$ {p1.Robux}`, "Royal x1: its Robux price")
				T.truthy(specs[1].Enabled)
				T.eq(specs[2].Price, "Coming soon", "x3 still a placeholder")
			end
		end
		p1.Id = old
	end)

	T.test("EggPanel: the opens' keys (E is the prompt's; R and X are free at the temple)", function()
		T.eq(EggPanel.OpenKeys[1], PromptConfig.Keys.Main.Keyboard.Name, "Open 1 is the prompt's key")
		T.eq(EggPanel.OpenKeys[3], "R")
		T.eq(EggPanel.OpenKeys[10], "X")
		-- nothing else binds R or X except build mode (PlacementController, on the plot)
		local function walk(dir: string, out: { string })
			for _, entry in fs.readDir(dir) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					walk(path, out)
				elseif entry:match("%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files = {}
		walk(Loader.root .. "/src", files)
		for _, full in files do
			local rel = string.sub(full, #Loader.root + 2)
			local code = string.gsub(string.gsub(fs.readFile(full), "%-%-%[(=*)%[.-%]%1%]", ""), "%-%-[^\n]*", "")
			local uses = 0
			for _, key in { "Enum%.KeyCode%.R%f[^%w_]", "Enum%.KeyCode%.X%f[^%w_]" } do
				local _, n = string.gsub(code, key, "")
				uses += n
			end
			if rel ~= "src/client/Controllers/PlacementController.luau" and rel ~= "src/client/Controllers/EggPanelController.luau" then
				T.eq(uses, 0, rel .. ": R / X are the eggs' (and build mode's)")
			end
		end
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/EggPanelController.luau")
		T.truthy(string.find(controller, "not ProximityPromptService.Enabled", 1, true), "the keys rest while the prompts are suppressed")
		T.truthy(string.find(controller, "UnbindAction(OPEN3_ACTION)", 1, true), "and are unbound when the panel goes")
	end)

	T.test("EggPanel: the opens' layout (under the cards, inside the panel, 44 pt on phones)", function()
		for _, id in TEMPLE do
			local count = #EggPanel.lines(id, false, {})
			for _, touch in { false, true } do
				local l = EggPanel.layout(count, touch)
				local lastCard = EggPanel.cardAt(l, count)
				for i = 1, #CapsuleConfig.Counts do
					local at = EggPanel.openAt(l, i)
					T.truthy(at.Y >= lastCard.Y + l.Card, `{id} open {i}: under the cards`)
					T.truthy(at.X >= l.Pad - 0.01 and at.X + l.Open.X <= l.Width - l.Pad + 0.5, `{id} open {i}: inside left / right`)
					T.truthy(at.Y + l.Open.Y <= l.Body - l.Pad + 0.01, `{id} open {i}: above the foot`)
				end
				T.truthy(l.Open.X >= 110, 'room for "Open 10" and a price')
				if touch then
					T.truthy(l.Open.Y * EggPanel.PhoneScale >= EggPanel.MinTouch - 0.5, `{id}: the opens are 44 pt on a phone`)
				end
			end
		end
		local refs = EggPanel.build()
		T.eq(#refs.Opens, #CapsuleConfig.Counts)
		EggPanel.apply(refs, "Stone", EggPanel.layout(14, true), EggPanel.PhoneScale)
		for _, target in EggPanel.touchTargets(refs) do
			T.truthy(target.Size.Y.Offset * EggPanel.PhoneScale >= EggPanel.MinTouch - 0.5, target.Name .. ": 44 pt")
		end
		EggPanel.setOpens(refs, {
			{ Count = 1, Robux = false, Price = "2,500", Enabled = true },
			{ Count = 3, Robux = false, Price = "7,500", Enabled = false, Reason = "NoCoins" },
		}, EggPanel.OpenKeys, nil)
		T.eq(refs.Opens[1].Amount.Text, "2,500")
		T.truthy(refs.Opens[1].Coin.Visible, "a coin before a coin price")
		T.eq(refs.Opens[1].KeyText.Text, "E")
		T.eq(refs.Opens[2].KeyText.Text, "R")
		T.falsy(refs.Opens[3].Button.Visible, "no spec: hidden")
		EggPanel.setOpens(refs, { { Count = 1, Robux = true, Price = "R$ 49", Enabled = true } }, nil, nil)
		T.falsy(refs.Opens[1].Coin.Visible, "no coin on a Robux price")
		T.falsy(refs.Opens[1].Key.Visible, "touch: no badge")
		-- the glows and the chip's red flash are not in the fade list (they animate on their own)
		for _, f in refs.Fades do
			T.falsy(f.Target:GetAttribute("NoFade"), f.Target.Name .. " fades")
		end
	end)

	T.test("EggPanel: the big round E (a 44 pt target on phones, its keys, its fade)", function()
		T.truthy(EggPanel.BigE, "the eggs' own big E")
		T.truthy(EggPrompt.Disc * EggPanel.PhoneScale >= EggPanel.MinTouch, "the disc is past 44 pt on a phone")
		local p = EggPrompt.build()
		T.eq(p.Gui.ClassName, "BillboardGui")
		T.truthy(p.Gui.AlwaysOnTop)
		EggPrompt.setScale(p, EggPanel.PhoneScale)
		T.eq(p.Gui.Size.X.Offset, math.ceil(EggPrompt.Width * EggPanel.PhoneScale))
		EggPrompt.setKey(p, "E", nil)
		T.eq(p.Key.Text, "E")
		T.truthy(p.Key.Visible)
		T.falsy(p.Glyph.Visible)
		EggPrompt.setKey(p, "", "rbxasset://textures/ui/Controls/xboxY.png")
		T.truthy(p.Glyph.Visible, "a gamepad: its glyph")
		T.falsy(p.Key.Visible)
		EggPrompt.setKey(p, "Tap", nil)
		T.eq(p.Key.Text, "Tap")
		EggPrompt.setText(p, "Buy Egg!", "$2,500", false)
		T.eq(p.Title.Text, "Buy Egg!")
		T.eq(p.Price.Text, "$2,500")
		EggPrompt.setFade(p, 1)
		for _, f in p.Fades do
			T.eq((f.Target :: any)[f.Property], 1)
		end
		EggPrompt.setFade(p, 0)
		for _, f in p.Fades do
			T.eq((f.Target :: any)[f.Property], f.Base)
		end
	end)

	T.test("EggPanel: the motion stays calm (flashes under 3 a second, a bounded hop, confetti in reach)", function()
		T.truthy(EggPanel.AlertFlashes / EggPanel.AlertSeconds <= 3, "the chip's red flash")
		T.truthy(EggPanel.GlowPeriod >= 1, "the glows breathe at most once a second")
		T.truthy(EggPrompt.ShineEvery >= 1 and EggPrompt.ShineTime < EggPrompt.ShineEvery, "the E's shine now and then")
		-- the egg's happy hop: nothing before or after, never higher than BounceHeight
		local a, b = DecorController.bounceAt(0)
		T.eq(a, 0)
		T.eq(b, 0)
		a, b = DecorController.bounceAt(DecorController.BounceSeconds)
		T.eq(a, 0, "it lands")
		T.eq(b, 0)
		local top = 0
		for i = 1, 70 do
			local lift, tilt = DecorController.bounceAt(i / 100)
			T.truthy(lift >= 0 and lift <= DecorController.BounceHeight + 1e-9, "a hop up, never down")
			T.truthy(math.abs(tilt) <= DecorController.BounceTilt + 1e-9, "a small wobble")
			top = math.max(top, lift)
		end
		T.truthy(top > DecorController.BounceHeight * 0.9, "it really hops")
		-- confetti: the same for the same seed, every piece within reach
		local first = Confetti.targets(Confetti.Count, 42)
		local again = Confetti.targets(Confetti.Count, 42)
		T.eq(#first, Confetti.Count)
		for i, t in first do
			T.eq(t.X, again[i].X, "deterministic")
			T.truthy(math.sqrt(t.X * t.X + t.Y * t.Y) <= Confetti.Spread + 0.25, "within reach")
			T.truthy(t.Size >= 8 and t.Size <= 16)
		end
		local other = Confetti.targets(Confetti.Count, 7)
		T.truthy(other[1].X ~= first[1].X or other[2].X ~= first[2].X, "another seed, another burst")
		local holder = Instance.new("Frame")
		local pieces = Confetti.build(holder, 6)
		Confetti.pose(pieces, Vector2.new(0.5, 0.4), 3, 0.3)
		T.truthy(pieces[1].Visible, "flying")
		Confetti.pose(pieces, Vector2.new(0.5, 0.4), 3, Confetti.Seconds)
		T.falsy(pieces[1].Visible, "gone at the end")
	end)

	T.test("HatchFx: a bigger hatch for rarer golems, the curves stay in bounds, flashes 0.4 s apart", function()
		local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
		local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
		local CFrame = Loader.CFrame
		local Color3 = roblox.Color3
		-- rarer golems: a longer build-up, more and brighter light, sparkles, Mythic's tint
		local previous = HatchFx.plan(1)
		for order = 2, 6 do
			local plan = HatchFx.plan(order)
			T.truthy(plan.Shake > previous.Shake, `order {order}: a longer build-up`)
			T.truthy(plan.Rays >= previous.Rays and plan.RayFade <= previous.RayFade, "more and brighter light")
			T.truthy(plan.Sparkles >= previous.Sparkles)
			T.truthy(plan.Rays <= HatchFx.MaxRays)
			previous = plan
		end
		T.truthy(HatchFx.plan(6).Tint, "Mythic tints the screen")
		T.falsy(HatchFx.plan(5).Tint)
		T.eq(HatchFx.plan(99).Order, 6, "out of range: the nearest")
		T.eq(HatchFx.plan(0 / 0).Order, 1)
		-- the shake grows and speeds up, the squash stays gentle, the last fifth gathers
		for _, order in { 1, 6 } do
			local plan = HatchFx.plan(order)
			local early, late = 0, 0
			for i = 1, 200 do
				local t = i / 200 * plan.Shake
				local roll, sy, sxz, hop = HatchFx.shakeAt(t, plan)
				T.truthy(math.abs(roll) <= 0.4 and sy >= 0.75 and sy <= 1.2 and sxz >= 0.85 and sxz <= 1.2, "in bounds")
				T.truthy(hop >= 0 and hop <= 0.2)
				if t < plan.Shake * 0.3 then
					early = math.max(early, math.abs(roll))
				elseif t < plan.Shake * 0.8 then
					late = math.max(late, math.abs(roll))
				end
			end
			T.truthy(late > early * 2, "harder as it builds")
			local _, sy = HatchFx.shakeAt(plan.Shake * 0.99, plan)
			T.truthy(sy < 0.85, "squashed just before the break")
		end
		local a, b, c, d = HatchFx.shakeAt(0, HatchFx.plan(1))
		T.eq(a, 0)
		T.eq(b, 1)
		T.eq(c, 1)
		T.eq(d, 0)
		-- the cracks one after another, the light grows, the golem bounces to full size
		local plan = HatchFx.plan(4)
		T.eq(HatchFx.cracksAt(0.1, plan), 0)
		T.eq(HatchFx.cracksAt(plan.Shake * 0.99, plan), 3)
		local lit = 0
		for i = 1, 100 do
			local n = HatchFx.cracksAt(i / 100 * plan.Shake, plan)
			T.truthy(n >= lit, "never fewer")
			lit = n
		end
		T.eq(HatchFx.leakAt(0, plan), 0)
		T.near(HatchFx.leakAt(plan.Shake, plan), 1, 1e-9)
		T.near(HatchFx.popAt(0), 0.25, 1e-9)
		T.near(HatchFx.popAt(HatchFx.PopTime), 1, 1e-9)
		local over = 0
		for i = 1, 40 do
			over = math.max(over, HatchFx.popAt(i / 40 * HatchFx.PopTime))
		end
		T.truthy(over > 1.02 and over < 1.2, "a bounce past full size")
		-- flashes: never sooner than FlashGap (2.5 a second at most)
		T.truthy(1 / HatchFx.FlashGap <= 3)
		T.falsy(HatchFx.flashOk(10, 10.2))
		T.truthy(HatchFx.flashOk(10, 10 + HatchFx.FlashGap))
		-- many eggs: a row of three, rows of five; they burst one after another, quickly
		local three, d3 = HatchFx.arrange(3)
		T.eq(#three, 3)
		local ten, d10 = HatchFx.arrange(10)
		T.eq(#ten, 10)
		T.truthy(d10 > d3, "the camera backs off for ten")
		T.truthy(HatchFx.Sequence * 9 < 1.5, "ten bursts in under a second and a half")
		-- a pooled egg: posed through the hatch and the break, then back whole
		local model = GolemBuilder.capsule("Stone")
		local rec = HatchFx.record(model)
		T.truthy(#rec.Parts > 10 and #rec.Cracks == 3, "the egg's parts and its three cracks")
		local stone = HatchFx.plan(1)
		local red = Color3.fromRGB(255, 0, 0)
		HatchFx.pose(rec, CFrame.new(), stone.Shake * 0.95, stone.Shake, stone, red, true)
		T.eq(rec.Cracks[3].Transparency, 0, "every crack glows at the end")
		HatchFx.pose(rec, CFrame.new(), stone.Shake + HatchFx.BurstTime, stone.Shake, stone, red, true)
		for i, part in rec.Parts do
			T.truthy(part.Transparency >= 0.999, part.Name .. ": gone after the break")
			local _ = i
		end
		HatchFx.reset(rec)
		for i, part in rec.Parts do
			T.eq(part.Transparency, rec.Trans[i], part.Name .. ": back as built")
			T.eq(part.Size, rec.Sizes[i])
		end
		-- the overlay: every piece hidden after clear()
		local gui = Instance.new("ScreenGui")
		local fx = HatchFx.overlay(gui)
		HatchFx.setLeak(fx, stone.Shake * 0.9, stone, red)
		T.truthy(fx.Leak.Visible, "light leaks near the end")
		HatchFx.setLeak(fx, nil, stone, red)
		T.falsy(fx.Leak.Visible)
		HatchFx.clear(fx)
		T.eq(fx.Tint.BackgroundTransparency, 1)
		for _, piece in fx.Shards do
			T.falsy(piece.Visible)
		end
		-- the controller: nothing shakes, flashes or nudges with Reduce motion
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		T.truthy(
			string.find(source, "if Motion.reduced() or not HatchFx.flashOk(lastFlash, now) then", 1, true),
			"flash: reduced and rate-limited"
		)
		local burst = string.match(source, "local function burst%(.-\nend\n")
		T.truthy(burst, "the hatch")
		local reducedAt = string.find(burst, "if Motion.reduced() then", 1, true)
		local shakeAt = string.find(burst, "CameraShake.add", 1, true)
		T.truthy(reducedAt and shakeAt and reducedAt < shakeAt, "Reduce motion returns before any shake")
	end)
end
