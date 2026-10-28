-- The EGGS temple's egg panels (owner 2026-10-28, UI/EggPanel +
-- Controllers/EggPanelController): the odds a panel shows are the table the
-- server rolls (Triple Lucky too), Auto is never offered on a Robux egg,
-- the nearest egg takes the panel (with a little hysteresis), golems the
-- player has none of are silhouettes on coin eggs only, the layout keeps
-- Auto at 44 pt on phones and every card inside the white panel, the fade
-- reaches every transparency, and the temple's three eggs are found in the
-- built stall with their prompts in front.
return function(T, Loader)
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox") :: any
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CapsuleConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CapsuleConfig")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local LobbyLayout = Loader.requirePath("ReplicatedStorage.Shared.Config.LobbyLayout")
	local Rarity = Loader.requirePath("ReplicatedStorage.Shared.Config.Rarity")
	local CapsuleService = Loader.requirePath("ServerScriptService.Server.Services.CapsuleService")
	local CapsuleView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.CapsuleView")
	local EggPanel = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.EggPanel")

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
				T.truthy(l.Toggle.Y <= l.Head, "Auto fits its row")
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
			local center, top, prompt = EggPanel.spotOf(model, front)
			T.truthy(top > center.Y + 1, id .. ": the top is over the centre")
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
end
