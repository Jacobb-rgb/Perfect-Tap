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
	local Enum = roblox.Enum
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

	-- Runs `body` with shared tables' fields changed ({ table, key, value } each) and puts
	-- every one back, even when an assertion throws inside (the later specs see the config as shipped).
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

	-- A font's advance widths (the round look's sentence font, the preview's copy): `text`'s width at `size`.
	local function fontWidth(path: string): (string, number) -> number
		local d = fs.readFile(path)
		local function u16(o: number): number
			return (string.unpack(">I2", d, o + 1))
		end
		local function i16(o: number): number
			return (string.unpack(">i2", d, o + 1))
		end
		local function u32(o: number): number
			return (string.unpack(">I4", d, o + 1))
		end
		local tables: { [string]: number } = {}
		for i = 0, u16(4) - 1 do
			local rec = 12 + 16 * i
			tables[string.sub(d, rec + 1, rec + 4)] = u32(rec + 8)
		end
		local upem, metrics, hmtx, cmap = u16(tables.head + 18), u16(tables.hhea + 34), tables.hmtx, tables.cmap
		local glyph: { [number]: number } = {}
		for i = 0, u16(cmap + 2) - 1 do
			local sub = cmap + u32(cmap + 8 + 8 * i)
			if u16(sub) == 4 then
				local seg = u16(sub + 6) // 2
				local ends, starts, deltas, ranges = sub + 14, sub + 16 + 2 * seg, sub + 16 + 4 * seg, sub + 16 + 6 * seg
				for k = 0, seg - 1 do
					local first, delta, range = u16(starts + 2 * k), i16(deltas + 2 * k), u16(ranges + 2 * k)
					for c = first, math.min(u16(ends + 2 * k), 126) do
						local g = if range == 0 then (c + delta) % 65536 else u16(ranges + 2 * k + range + 2 * (c - first))
						if range ~= 0 and g ~= 0 then
							g = (g + delta) % 65536
						end
						glyph[c] = g
					end
				end
				break
			end
		end
		return function(text: string, size: number): number
			local w = 0
			for _, c in utf8.codes(text) do
				w += u16(hmtx + 4 * math.min(glyph[c] or 0, metrics - 1))
			end
			return w / upem * size
		end
	end

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

	T.test("EggPanel: every card names its golem; silhouettes (with their names) on coin eggs only", function()
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
		patched({ { EggPanel, "Silhouettes", false } }, function()
			for _, line in EggPanel.lines("Stone", false, {}) do
				T.falsy(line.Silhouette, "switched off: every picture shows")
			end
		end)
		T.truthy(EggPanel.Silhouettes, "put back")
		-- coin eggs are paid random items too (coin packs): every chance belongs to a golem the
		-- player can tell before buying: its name on the card, a silhouette's too
		T.truthy(MonetizationConfig.CoinPacksDefault, "coins can be bought")
		for _, id in TEMPLE do
			for _, lucky in { false, true } do
				for _, line in EggPanel.lines(id, lucky, {}) do
					T.eq(line.Name, GolemConfig.ById[line.Golem].Name, `{id} {line.Golem}: its name`)
					T.truthy(#line.Name > 0)
				end
			end
		end
		local refs = EggPanel.build()
		for _, touch in { false, true } do
			local lines = EggPanel.lines("Crystal", false, { QuartzSprite = true })
			local l = EggPanel.layout(#lines, touch)
			EggPanel.apply(refs, "Crystal", l, if touch then EggPanel.PhoneScale else 1)
			EggPanel.setLines(refs, lines, nil)
			local shadows = 0
			for i, line in lines do
				local card = refs.Cards[i]
				T.eq(card.Name.Text, line.Name, `{line.Golem}: named on its card`)
				T.truthy(card.Name.Visible and card.Name.TextTransparency == 0, "and the name shows")
				T.truthy(card.Name.TextWrapped, "two lines for a long name")
				if line.Silhouette then
					shadows += 1
					T.eq(card.View.ImageColor3, roblox.Color3.new(0, 0, 0), "a silhouette...")
					T.eq(card.Name.Text, GolemConfig.ById[line.Golem].Name, "...with its golem's name under it")
				end
			end
			T.truthy(shadows >= 10, "Crystal: the golems the player has none of are silhouettes")
			-- the name sits under the picture, inside the card (the card clips)
			local card = refs.Cards[1]
			T.truthy(card.Name.Size.Y.Offset == l.NameH and l.NameH >= 2 * l.NameSize, "two lines")
			T.truthy(card.Chance.Position.Y.Offset <= l.CardH - l.NameH + 2, "the chance over the name")
		end
		-- readable: 8 pt on a phone, every word of every name fits its card's width in the round font
		local width = fontWidth(Loader.root .. "/tools/preview/fonts/Montserrat-Bold.ttf")
		for _, touch in { false, true } do
			local l = EggPanel.layout(14, touch)
			T.truthy(l.NameSize * EggPanel.PhoneScale >= 8, "the name 8 pt on a phone")
			-- (the golems of every egg a panel shows: the stall's, not a limited edition's or the podium's)
			for _, capsule in CapsuleConfig.Stall do
				if capsule.Limited == nil and not capsule.Podium then
					for _, line in CapsuleConfig.odds(capsule.Id, false) do
						local name = GolemConfig.ById[line.Golem].Name
						for word in string.gmatch(name, "%S+") do
							T.truthy(
								width(word, l.NameSize) <= l.Card - 2,
								`{name}: "{word}" ({math.ceil(width(word, l.NameSize))} units) fits a card ({l.Card})`
							)
						end
					end
				end
			end
		end
		T.truthy(width("Moonstone", 13) > 70, "the measure is the font's (Moonstone ~77 units at 13)")
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
						at.Y >= l.Pad + l.Head and at.Y + l.CardH <= l.OpenY - l.OpenGap + 0.01,
						`{id} card {i}: under the head row, above the opens`
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
				T.eq(l.Beside, touch, "floating beside the egg on touch, over it on PC")
				if touch then
					T.eq(l.Head, 0, "touch: no head row (the opens show the price)")
				end
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
		patched({ { p1, "Id", 1 } }, function()
			for _, card in CapsuleView.cards(state(1, 0), 0, false, NOW, nil, true) do
				if card.Id == "Royal" then
					local specs = EggPanel.opens(card.Buys, true)
					T.eq(specs[1].Price, `R$ {p1.Robux}`, "Royal x1: its Robux price")
					T.truthy(specs[1].Enabled)
					T.eq(specs[2].Price, "Coming soon", "x3 still a placeholder")
				end
			end
		end)
		T.eq(p1.Id, old, "put back")
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
					T.truthy(at.Y >= lastCard.Y + l.CardH, `{id} open {i}: under the cards`)
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

	T.test("HatchFx: golems stay SOLID (nothing see-through over them, the glow behind)", function()
		local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
		local Color3 = roblox.Color3
		-- owner 2026-10-28: "the golems mustn't be see-through"
		local o = CapsuleView.buildOpening(false)
		local fx = HatchFx.overlay(o.Gui)
		T.eq(o.Hero.ImageTransparency, 0, "the hero view is opaque")
		T.truthy(fx.Tint.ZIndex < o.Hero.ZIndex, "the Mythic tint colours the backdrop, under the golem")
		T.truthy(fx.Aura.ZIndex < o.Hero.ZIndex, "the aura glows behind the golem")
		T.truthy(o.Rays.ZIndex < o.Hero.ZIndex, "the rays turn behind the golem")
		HatchFx.setLeak(fx, nil, HatchFx.plan(6), Color3.new(1, 0, 0))
		T.falsy(fx.Leak.Visible, "the leaking light (over the egg) is gone before the golem")
		T.truthy(HatchFx.BurstTime >= 0.45, "the break's flash (0.45 s) has faded when the golem pops")
		-- the controller: no flash over a golem (the reveal, the grid); the aura pulses behind instead
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		local reveal = string.match(source, "local function reveal%(.-\nend\n")
		local grid = string.match(source, "local function showGrid%(.-\nend\n")
		T.truthy(reveal and grid, "the reveal and the grid")
		local code = function(text: string): string
			return (string.gsub(text, "%-%-[^\n]*", ""))
		end
		T.falsy(string.find(code(reveal), "flash(", 1, true), "no flash over the revealed golem")
		T.falsy(string.find(code(grid), "flash(", 1, true), "no flash over the grid's golems")
		T.truthy(string.find(reveal, "o.Hero.ImageTransparency = 0", 1, true), "the golem's view made opaque")
		T.truthy(string.find(reveal, "HatchFx.pulseAura(fx)", 1, true), "its glow bursts out behind it")
		-- the grid's golems: every picture opaque
		CapsuleView.setGrid(o, { "PebbleGolem", "HeartstoneColossus", "RoseKnight" }, { [2] = true }, 2)
		for _, cell in o.Cells do
			for _, d in cell.Frame:GetDescendants() do
				if d:IsA("ViewportFrame") or (d:IsA("ImageLabel") and d.Name == "Picture") then
					T.eq((d :: any).ImageTransparency, 0, cell.Kind .. ": " .. d.Name .. " opaque")
				end
			end
		end
		-- the egg panel's cards: opaque at rest (silhouettes black, never faded)
		local refs = EggPanel.build()
		local lines = EggPanel.lines("Crystal", false, { QuartzSprite = true })
		EggPanel.apply(refs, "Crystal", EggPanel.layout(#lines, false), 1)
		EggPanel.setLines(refs, lines, nil)
		EggPanel.setFade(refs, 0)
		for i, card in refs.Cards do
			if lines[i] then
				T.eq(card.View.ImageTransparency, 0, lines[i].Golem .. ": its picture opaque")
				T.truthy(card.Picture.ZIndex > card.Rays.ZIndex, "the card's rays behind the golem")
			end
		end
	end)
	T.test("EggPanel: switching eggs moves the golem models between the cards (a real modelFor)", function()
		local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
		-- the controller's modelFor: one model per kind, built once and kept, lent to a card
		local cache: { [string]: any } = {}
		local built = 0
		local function modelFor(kind: string): (any, any, number)
			local model = cache[kind]
			if not model then
				model = GolemBuilder.build(kind)
				model:SetAttribute("Kind", kind)
				cache[kind] = model
				built += 1
			end
			local center, radius = EggPanel.bounds(model)
			return model, center, radius
		end
		local refs = EggPanel.build()
		local walk = { "Stone", "Crystal", "Royal", "Stone", "Royal", "Crystal", "Stone" }
		for step, id in walk do
			local lines = EggPanel.lines(id, step % 2 == 0, {})
			EggPanel.apply(refs, id, EggPanel.layout(#lines, false), 1)
			EggPanel.setLines(refs, lines, modelFor)
			local where: { [string]: number } = {} -- (by kind: Lune's instances are not one userdata each)
			for i, card in refs.Cards do
				local models = {}
				for _, child in card.View:GetChildren() do
					if child:IsA("Model") then
						table.insert(models, child)
					end
				end
				local line = lines[i]
				if line then
					T.eq(#models, 1, `{id} (step {step}) card {i}: one golem in its view`)
					T.eq(models[1] and models[1]:GetAttribute("Kind"), line.Golem, `{id} card {i} ({line.Text}): {line.Golem}'s model`)
					T.eq(card.Kind, line.Golem)
					if models[1] then
						where[models[1]:GetAttribute("Kind")] = i
					end
				else
					T.eq(#models, 0, `{id} (step {step}) card {i}: a hidden slot holds no golem`)
					T.eq(card.Kind, nil, `{id} card {i}: and knows it`)
				end
			end
			-- no golem a card shows is anywhere else
			for kind, model in cache do
				local shows = false
				for _, line in lines do
					shows = shows or line.Golem == kind
				end
				if shows then
					T.truthy(model.Parent ~= nil and where[kind] ~= nil, kind .. ": in its card")
				else
					T.eq(model.Parent, nil, `{kind}: not this egg's golem, let go`)
				end
			end
		end
		-- built once each: the walk only moves them
		local kinds = {}
		for _, id in TEMPLE do
			for _, line in EggPanel.lines(id, false, {}) do
				kinds[line.Golem] = true
			end
		end
		local n = 0
		for _ in kinds do
			n += 1
		end
		T.eq(built, n, "one model per golem")
	end)

	T.test("EggPanel: on touch the panel floats clear of the thumbstick, the touch buttons and the top bar", function()
		local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
		local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
		for _, screen in { Vector2.new(667, 375), Vector2.new(844, 390), Vector2.new(1024, 768) } do
			-- the HUD's scale (HudController.uiScale) and its teleport bar's foot (HudBubble: the round look)
			local scale = math.clamp(math.min(screen.Y / 720, screen.X / 1100), 0.62, 1.25)
			local inset = HudBubble.PreviewInset
			local bar = HudBubble.topBarSize(HudBubble.layout(scale, screen.X, true, false))
			local top = inset + (HudBubble.topBarY(inset, scale) + bar.Y) * scale
			local s = EggPanel.screen(screen, top)
			local small = math.min(screen.X, screen.Y) <= 500
			for _, b in BoostView.TouchButtons[if small then "Small" else "Large"] do
				T.truthy(s.Buttons <= screen.Y - b.Top, b.Name .. ": the panel stays above it")
			end
			T.near(s.Zone, screen.X * 0.4, 1e-9, "the thumbstick's zone")
			for _, id in TEMPLE do
				local l = EggPanel.layout(#EggPanel.lines(id, false, {}), true, EggPanel.autoAllowed(id))
				local size = Vector2.new(math.ceil(l.Width * scale), math.ceil(l.Height * scale))
				for _, ex in { 0.3, 0.45, 0.5, 0.55, 0.7 } do
					for _, ey in { 0.35, 0.5, 0.65 } do
						local egg = Vector2.new(screen.X * ex, screen.Y * ey)
						local at = EggPanel.floatAt(s, size, egg, 40)
						local where = `{id} on {screen.X}x{screen.Y}, the egg at ({ex}, {ey})`
						-- on the screen
						T.truthy(
							at.X >= 0 and at.Y >= 0 and at.X + size.X <= screen.X and at.Y + size.Y <= screen.Y,
							where .. ": on the screen"
						)
						-- the buttons (the opens and Auto: the white panel's last row) clear of the thumbstick's zone
						local rowTop = at.Y + (l.Title + l.OpenY) * scale
						local rowBottom = rowTop + l.Open.Y * scale
						T.truthy(at.X >= s.Zone, where .. ": right of the thumbstick's zone")
						-- and of the touch buttons in the bottom right (their tops)
						T.truthy(
							rowBottom <= s.Buttons,
							where .. `: the opens' row (to {math.ceil(rowBottom)}) above the touch buttons ({s.Buttons})`
						)
						-- under the top bar where it fits (else the buttons win: by a few px at most)
						local room = s.Buttons - s.Top - 2 * EggPanel.Margin
						if size.Y <= room then
							T.truthy(at.Y >= s.Top, where .. ": under the top bar")
						else
							T.truthy(at.Y >= s.Top - 12, where .. `: tucked under the top bar by {math.ceil(s.Top - at.Y)} px at most`)
						end
					end
				end
				-- beside the egg where there is room: right of it, its middle level with it
				local free = EggPanel.floatAt(s, size, Vector2.new(s.Zone, screen.Y * 0.5), 10)
				T.truthy(free.X >= s.Zone + 10, "right of the egg")
			end
		end
		-- the billboard's SizeOffset puts its top-left exactly there (x right, y up, in its own size)
		local size = Vector2.new(300, 160)
		local anchor = Vector2.new(400, 200)
		local at = Vector2.new(320, 60)
		local o = EggPanel.floatOffset(anchor, at, size)
		local center = Vector2.new(anchor.X + o.X * size.X, anchor.Y - o.Y * size.Y)
		T.near(center.X - size.X / 2, at.X, 1e-9)
		T.near(center.Y - size.Y / 2, at.Y, 1e-9)
		T.truthy(EggPanel.overlaps(Vector2.new(0, 0), Vector2.new(10, 10), Vector2.new(5, 5), Vector2.new(10, 10)))
		T.falsy(EggPanel.overlaps(Vector2.new(0, 0), Vector2.new(10, 10), Vector2.new(10, 0), Vector2.new(10, 10)))
	end)

	T.test("EggPanel: the keys and their badges only where the prompt reaches; the red flash keeps its pace", function()
		local point = Vector3.new(0, 4, 0)
		T.truthy(EggPanel.inReach(point + Vector3.new(0, 0, EggPanel.PromptDistance - 0.1), point))
		T.falsy(EggPanel.inReach(point + Vector3.new(0, 0, EggPanel.PromptDistance + 0.1), point), "past the prompt's reach")
		T.truthy(EggPanel.PromptDistance < EggPanel.ShowRange, "the panel shows from further away")
		T.falsy(EggPanel.alertOk(10, 10 + EggPanel.AlertSeconds - 0.01), "not while it flashes")
		T.truthy(EggPanel.alertOk(10, 10 + EggPanel.AlertSeconds))
		T.truthy(EggPanel.AlertFlashes / EggPanel.AlertSeconds <= 3, "2.5 flashes a second however fast a key is mashed")
		for _, state in { "Waiting", "Playing" } do
			T.truthy(EggPanel.holdCards(state), state .. ": the cards wait (no spoiler before the reveal)")
		end
		T.falsy(EggPanel.holdCards("End"), "the golem is out")
		T.falsy(EggPanel.holdCards("Idle"))
		-- the light skin leaves the eggs' own guis alone
		local light = fs.readFile(Loader.root .. "/src/client/Controllers/LightWorldController.luau")
		local skip = string.match(light, "LightWorldController%.Skip = {(.-)}")
		T.truthy(skip and string.find(skip, "TerraForgeEggPanel = true", 1, true), "Skip: the egg panel")
		T.truthy(skip and string.find(skip, "TerraForgeEggPrompt = true", 1, true), "Skip: the big E")
	end)
	---------------------------------------------------------------- the controller, run

	-- A signal the fakes fire by hand.
	local function signal(): any
		local list = {}
		return {
			Connect = function(_, fn)
				table.insert(list, fn)
				return { Connected = true, Disconnect = function() end }
			end,
			fire = function(...)
				for _, fn in list do
					fn(...)
				end
			end,
		}
	end
	-- (made once: the controller keeps the local player it found when it loaded, and its hooks from init())
	local me: any = nil
	local hooks: any = {}
	local stall: any = nil
	local NOW = 1_800_000_000

	--[[
		Runs EggPanelController on fakes for Roblox's services (Lune has none):
		the local player and its character, the prompts' service, the gamepad
		selection, the key binds; what it asks CapsuleController,
		StateController, HudController and MenuPanels is answered by `w` and
		recorded there. Everything is put back after `body`, also when it fails.
	]]
	local withLocal: (body: (C: any, w: any) -> ()) -> ()
	local function withController(body: (C: any, w: any) -> ())
		local Players = Loader.game:GetService("Players")
		if not me then
			local root = {
				IsA = function(_, class: string)
					return class == "BasePart"
				end,
			}
			local humanoid = { Health = 100 }
			local playerGui = Instance.new("Folder")
			me = {
				Name = "Me",
				UserId = 1,
				Root = root,
				Humanoid = humanoid,
				CharacterRemoving = signal(),
				WaitForChild = function()
					return playerGui
				end,
				GetAttribute = function()
					return nil
				end,
				GetAttributeChangedSignal = function()
					return signal()
				end,
			}
			me.Character = {
				FindFirstChild = function(_, name: string)
					return if name == "HumanoidRootPart" then root else nil
				end,
				FindFirstChildOfClass = function(_, class: string)
					return if class == "Humanoid" then humanoid else nil
				end,
			}
		end
		-- (the controllers read the local player when they load)
		local hadLocal = rawget(Players, "LocalPlayer")
		rawset(Players, "LocalPlayer", me)
		local loaded, failure = pcall(withLocal, body)
		rawset(Players, "LocalPlayer", hadLocal)
		if not loaded then
			error(failure, 0)
		end
	end

	function withLocal(body: (C: any, w: any) -> ())
		local CapsuleController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
		local StateController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController")
		local HudController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
		local MenuPanels = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.MenuPanels")
		local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")
		local Sfx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.Sfx")
		local Vfx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.Vfx")
		local game = Loader.game
		local Workspace = game:GetService("Workspace")
		local Tween = game:GetService("TweenService")
		local CAS = game:GetService("ContextActionService")
		local PPS = game:GetService("ProximityPromptService")
		local Gui = game:GetService("GuiService")
		local Run = game:GetService("RunService")
		local UIS = game:GetService("UserInputService")
		local w: any = {
			position = Vector3.new(0, 500, 0),
			opening = "Idle",
			endFor = 0,
			buys = {},
			answer = { true, nil },
			lucky = false,
			coins = 1e15,
			state = { PriceLevel = 1, Golems = { Owned = {}, Equipped = {}, NextId = 1, Pending = {} }, Boosts = {} },
			toasts = {},
			auto = {},
			actions = {},
			selected = nil,
			gamepad = false,
			window = false,
			tweens = {},
			renders = {},
		}
		setmetatable(me.Root, {
			__index = function(_, key)
				return if key == "Position" then w.position else nil
			end,
		})
		local guiMeta = getmetatable(Gui)
		setmetatable(Gui, {
			__index = function(t, key)
				if key == "SelectedObject" then
					return w.selected
				end
				return guiMeta.__index(t, key)
			end,
			__newindex = function(t, key, value)
				if key == "SelectedObject" then
					w.selected = value
				else
					rawset(t, key, value)
				end
			end,
			__tostring = guiMeta.__tostring,
		})
		local fakes = {
			{ Workspace, "Terrain", Instance.new("Folder") },
			{ Workspace, "CurrentCamera", false },
			{
				Tween,
				"Create",
				function(_, target, _info, goal)
					local made = { Target = target, Goal = goal, Completed = signal() }
					function made.Play() end
					function made.Cancel() end
					table.insert(w.tweens, made)
					return made
				end,
			},
			{
				CAS,
				"BindAction",
				function(_, name, fn)
					w.actions[name] = fn
				end,
			},
			{
				CAS,
				"BindActionAtPriority",
				function(_, name, fn, _touch, _priority, key)
					w.actions[name] = fn
					w.actions[name .. "Key"] = key
				end,
			},
			{
				CAS,
				"UnbindAction",
				function(_, name)
					w.actions[name] = nil
				end,
			},
			{ PPS, "Enabled", true },
			{
				Gui,
				"GetGuiInset",
				function()
					return Vector2.zero, Vector2.zero
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
				Run,
				"BindToRenderStep",
				function(_, name)
					w.renders[name] = true
				end,
			},
			{
				Run,
				"UnbindFromRenderStep",
				function(_, name)
					w.renders[name] = nil
				end,
			},
			{ UIS, "LastInputTypeChanged", signal() },
			{
				CapsuleController,
				"buy",
				function(id, count, lucky, quiet)
					table.insert(w.buys, { Id = id, Count = count, Lucky = lucky, Quiet = quiet })
					return w.answer[1], w.answer[2]
				end,
			},
			{
				CapsuleController,
				"quote",
				function(id)
					for _, card in CapsuleView.cards(w.state, w.coins, false, NOW, nil, false) do
						if card.Id == id then
							card.Lucky = w.lucky
							return card
						end
					end
					return nil
				end,
			},
			{
				CapsuleController,
				"openingState",
				function()
					return w.opening, w.endFor
				end,
			},
			{
				CapsuleController,
				"setAuto",
				function(on)
					table.insert(w.auto, on)
				end,
			},
			{
				CapsuleController,
				"onStop",
				function(fn)
					hooks.onStop = fn
				end,
			},
			{
				StateController,
				"get",
				function()
					return w.state
				end,
			},
			{
				StateController,
				"onChanged",
				function(fn)
					hooks.onChanged = fn
				end,
			},
			{
				HudController,
				"uiScale",
				function()
					return 1
				end,
			},
			{
				HudController,
				"toast",
				function(text)
					table.insert(w.toasts, text)
				end,
			},
			{
				HudController,
				"refs",
				function()
					return nil
				end,
			},
			{
				MenuPanels,
				"isTouch",
				function()
					return false
				end,
			},
			{
				MenuPanels,
				"usingGamepad",
				function()
					return w.gamepad
				end,
			},
			{
				MenuPanels,
				"isOpen",
				function()
					return w.window
				end,
			},
			{
				MenuPanels,
				"glyph",
				function()
					return ""
				end,
			},
			{
				MenuPanels,
				"padName",
				function(key)
					return key.Name
				end,
			},
			{
				Motion,
				"reduced",
				function()
					return true
				end,
			},
			{ Sfx, "play", function() end },
			{ Vfx, "burst", function() end },
			{
				Vfx,
				"folder",
				function()
					return Instance.new("Folder")
				end,
			},
			{ DecorController, "bounce", function() end },
		}
		local ok, err = pcall(function()
			patched(fakes, function()
				local C = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.EggPanelController")
				patched({ { C, "LuckySettle", 0 } }, function()
					if not hooks.inited then
						hooks.inited = true
						C.init()
						local Stall = Loader.requirePath("ServerScriptService.Server.World.Lobby.Districts.Capsules")
						local Rng = Loader.requirePath("ReplicatedStorage.Shared.Util.Rng")
						stall = Instance.new("Model")
						Stall.build(stall, Rng.new("Lobby/Districts/capsules"))
						C._test.watch(stall)
					end
					-- the helpers: walk to an egg's prompt (or `away` studs further out, toward the plaza), one tick
					function w.at(id: string, away: number?)
						local spot = C._test.state().Spots[id]
						local out = spot.PromptAt - spot.Center
						w.position = spot.PromptAt + Vector3.new(out.X, 0, out.Z).Unit * (away or 0)
						C._test.tick()
					end
					function w.leave()
						w.position = Vector3.new(0, 500, 0)
						C._test.tick()
					end
					w.leave()
					local inner, problem = pcall(body, C, w)
					w.opening = "Idle"
					w.leave()
					if not inner then
						error(problem, 0)
					end
				end)
			end)
		end)
		setmetatable(Gui, guiMeta)
		if not ok then
			error(err, 0)
		end
	end

	T.test("EggPanelController: the opens buy only at the shown egg, in reach, on the odds it shows", function()
		withController(function(C, w)
			w.at("Stone")
			local s = C._test.state()
			T.eq(s.Current, "Stone", "the panel came up at the Stone egg")
			T.truthy(s.Reach, "at its prompt: in reach")
			T.truthy(s.Refs.Gui.Enabled)
			T.eq(s.Refs.Opens[1].KeyText.Text, "E", "the keys' badges show in reach")
			-- the panel's buttons and keys
			C.open("Stone", 10)
			T.eq(#w.buys, 1)
			T.eq(w.buys[1].Count, 10)
			T.eq(w.buys[1].Lucky, false, "the odds on the panel")
			T.eq(w.buys[1].Quiet, false, "a refusal says why")
			C.open("Crystal", 1)
			T.eq(#w.buys, 1, "never an egg whose panel isn't up")
			w.actions.TerraForgeEggOpen3("TerraForgeEggOpen3", Enum.UserInputState.Begin)
			T.eq(w.buys[2] and w.buys[2].Count, 3, "R: Open 3")
			-- out of the prompt's reach (the panel still shows): no keys, no badges
			w.at("Stone", EggPanel.PromptDistance + 0.5)
			s = C._test.state()
			T.eq(s.Current, "Stone")
			T.falsy(s.Reach, "past the prompt's reach")
			local result = w.actions.TerraForgeEggOpen10("TerraForgeEggOpen10", Enum.UserInputState.Begin)
			T.eq(result, Enum.ContextActionResult.Pass, "X does nothing there (nor does E)")
			T.eq(#w.buys, 2)
			T.falsy(s.Refs.Opens[1].Key.Visible, "no E badge where E does nothing")
			T.falsy(s.Refs.Opens[3].Key.Visible)
			-- Triple Lucky on: the cards show its odds and the opens send them
			w.at("Stone")
			w.lucky = true
			hooks.onChanged() -- (the boost's State push; the panel also refreshes every Refresh seconds)
			T.eq(C._test.state().Lucky, true, "the cards show Triple Lucky's odds")
			C.open("Stone", 1)
			T.eq(w.buys[#w.buys].Lucky, true, "the boosted odds the panel shows now")
			-- no coins: the chip flashes red, but never faster than it can show (mashing)
			w.answer = { false, "NoCoins" }
			local before = #w.tweens
			for _ = 1, 6 do
				C.open("Stone", 1)
			end
			local flashes = 0
			for i = before + 1, #w.tweens do
				if w.tweens[i].Target == s.Refs.Alert then
					flashes += 1
				end
			end
			T.eq(flashes, 1, "six refused presses, one flash")
		end)
	end)

	T.test("EggPanelController: Auto opens one by one and stops on every rule (coins, room, walking away, death, odds)", function()
		withController(function(C, w)
			w.at("Stone")
			C.toggleAuto("Stone")
			T.eq(C._test.state().Auto, "Stone", "Auto on")
			T.eq(w.auto[#w.auto], true, "the end screen knows")
			C._test.tick()
			T.eq(#w.buys, 1, "it opens one")
			T.truthy(w.buys[1].Quiet and w.buys[1].Count == 1, "one egg, quietly")
			-- one at a time: nothing while an open waits, plays or its end screen is young
			for _, state in { { "Waiting", 0 }, { "Playing", 0 }, { "End", C.AutoDwell * 0.5 } } do
				w.opening, w.endFor = state[1], state[2]
				C._test.tick()
				T.eq(#w.buys, 1, state[1] .. ": it waits")
			end
			w.opening, w.endFor = "End", C.AutoDwell + 0.1
			C._test.tick()
			T.eq(#w.buys, 2, "the next egg after the end screen showed")
			-- a short wait isn't a stop
			for _, reason in { "Busy", "Cooldown" } do
				w.answer = { false, reason }
				C._test.tick()
				T.eq(C._test.state().Auto, "Stone", reason .. ": Auto goes on")
			end
			-- the stop rules
			local function stops(label: string, make: () -> ())
				w.answer = { true, nil }
				w.opening = "Idle"
				w.at("Stone")
				if C._test.state().Auto == nil then
					C.toggleAuto("Stone")
				end
				T.eq(C._test.state().Auto, "Stone", label .. ": on first")
				make()
				T.eq(C._test.state().Auto, nil, label .. ": Auto stopped")
				T.eq(w.auto[#w.auto], false, label .. ": the end screen knows")
			end
			stops("no coins", function()
				w.answer = { false, "NoCoins" }
				C._test.tick()
			end)
			stops("a full golem inventory", function()
				w.answer = { false, "InventoryFull" }
				C._test.tick()
			end)
			stops("the server refused", function()
				hooks.onStop("RateLimited")
			end)
			stops("the end screen closed", function()
				hooks.onStop("Closed")
			end)
			stops("walking away", function()
				w.leave()
			end)
			stops("death", function()
				me.CharacterRemoving.fire()
			end)
			stops("a window opened", function()
				w.window = true
				C._test.tick()
				w.window = false
			end)
			-- the odds change under Auto (Triple Lucky ran out under an end screen): it stops, says so
			w.lucky = true
			stops("Triple Lucky ran out", function()
				w.opening, w.endFor = "End", C.AutoDwell + 0.1
				w.lucky = false
				local buys = #w.buys
				C._test.tick()
				T.eq(#w.buys, buys, "no egg on odds the player hasn't seen")
			end)
			T.truthy(string.find(w.toasts[#w.toasts] or "", "Auto stopped", 1, true), "a toast says why")
			T.eq(C._test.state().Lucky, false, "the panel shows the normal odds now")
			-- never on a Robux egg
			w.opening = "Idle"
			w.at("Royal")
			T.eq(C._test.state().Current, "Royal")
			C.toggleAuto("Royal")
			T.eq(C._test.state().Auto, nil, "no Auto on the Royal egg")
			T.falsy(C._test.state().Refs.Toggle.Visible)
		end)
	end)

	T.test("EggPanelController: a gamepad focuses the panel only on its button; nothing is selected on show", function()
		withController(function(C, w)
			w.gamepad = true
			w.at("Stone")
			local s = C._test.state()
			T.eq(s.Current, "Stone")
			T.eq(w.selected, nil, "the panel came up and selected nothing: the stick still walks")
			T.eq(w.actions.TerraForgeEggFocusKey, C.FocusKey, "the focus button is bound")
			T.eq(s.Refs.Opens[2].KeyText.Text, C.FocusKey.Name, "Open 3's badge: the focus button")
			T.eq(s.Refs.Opens[3].KeyText.Text, C.FocusKey.Name, "Open 10's badge")
			-- out of reach the focus button keeps its usual job
			w.at("Stone", EggPanel.PromptDistance + 0.5)
			local result = w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(result, Enum.ContextActionResult.Pass, "not in reach: passed on")
			T.eq(w.selected, nil)
			-- in reach: Open 1 is selected, the D-pad walks to Open 3 / 10, Auto's prompt (B) rests
			w.at("Stone")
			result = w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(result, Enum.ContextActionResult.Sink)
			T.eq(w.selected, s.Refs.Opens[1].Button, "Open 1 selected")
			T.eq(s.Refs.Opens[1].Button.NextSelectionRight, s.Refs.Opens[2].Button, "the D-pad: Open 3")
			T.eq(s.Refs.Opens[2].Button.NextSelectionRight, s.Refs.Opens[3].Button, "then Open 10")
			T.falsy(s.Spots.Stone.Auto.Enabled, "B lets go here, it doesn't toggle Auto")
			T.truthy(w.actions.TerraForgeEggRelease ~= nil, "B is bound")
			-- B lets go
			result = w.actions.TerraForgeEggRelease("TerraForgeEggRelease", Enum.UserInputState.Begin)
			T.eq(result, Enum.ContextActionResult.Sink)
			T.eq(w.selected, nil, "B: the stick walks again")
			T.eq(w.actions.TerraForgeEggRelease, nil)
			T.truthy(s.Spots.Stone.Auto.Enabled, "Auto's prompt back")
			-- walking away lets go too
			w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(w.selected, s.Refs.Opens[1].Button)
			w.leave()
			T.eq(w.selected, nil, "walked away: let go")
			T.eq(w.actions.TerraForgeEggFocus, nil, "and the focus button is free again")
			-- another window holding the selection: the focus button passes
			w.at("Stone")
			w.selected = Instance.new("TextButton")
			result = w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(result, Enum.ContextActionResult.Pass, "a menu has it: the D-pad moves there")
			w.selected = nil
		end)
	end)

	T.test("EggPanelController: a golem that just woke lights its card after the reveal, not during the hatch", function()
		withController(function(C, w)
			w.at("Stone")
			local s = C._test.state()
			local index = nil
			for i, line in s.Lines do
				if line.Golem == "CopperTinker" then
					index = i
				end
			end
			T.truthy(index ~= nil and s.Lines[index].Silhouette, "CopperTinker: a silhouette first")
			-- the server grants it and pushes State while the egg still hatches
			w.state.Golems.Owned = { { Id = 1, Kind = "CopperTinker" } }
			w.opening = "Playing"
			hooks.onChanged()
			C._test.tick()
			T.truthy(C._test.state().Lines[index].Silhouette, "still dark while the egg hatches (no spoiler)")
			T.eq(s.Refs.Cards[index].View.ImageColor3, roblox.Color3.new(0, 0, 0))
			w.opening = "Waiting"
			hooks.onChanged()
			T.truthy(C._test.state().Lines[index].Silhouette, "nor while the next open waits")
			-- the reveal is over (the end screen): it lights up
			w.opening = "End"
			hooks.onChanged()
			T.falsy(C._test.state().Lines[index].Silhouette, "in colour after the reveal")
			T.eq(s.Refs.Cards[index].View.ImageColor3, roblox.Color3.new(1, 1, 1))
			w.state.Golems.Owned = {}
		end)
	end)
	T.test("HatchFx: many eggs move rigidly (a PivotTo an egg, a half), sizes as built, faded eggs left alone", function()
		local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
		local GolemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.GolemBuilder")
		local CFrame = Loader.CFrame
		local Color3 = roblox.Color3
		local plan = HatchFx.plan(3)
		local red = Color3.fromRGB(255, 0, 0)
		local place = CFrame.new(2, 1, -3)
		local function near(a: any, b: any): boolean
			return (a.Position - b.Position).Magnitude < 1e-3
				and (a.LookVector - b.LookVector).Magnitude < 1e-3
				and (a.UpVector - b.UpVector).Magnitude < 1e-3
		end
		for _, id in TEMPLE do
			local rec = HatchFx.record(GolemBuilder.capsule(id, nil, { Calm = true }))
			T.truthy(rec.Halves ~= nil, id .. ": two halves that pivot")
			-- the build-up, rigid: every part where the per-part pose would put it
			local t = plan.Shake * 0.6
			HatchFx.pose(rec, place, t, plan.Shake, plan, red, false)
			local roll, _, _, hop = HatchFx.shakeAt(t, plan)
			local cf = place * CFrame.new(0, hop, 0) * CFrame.Angles(0, 0.4 * math.sin(t * 2), roll)
			for i, part in rec.Parts do
				T.truthy(near(part.CFrame, cf * rec.Base[i]), `{id} {part.Name}: in place (build-up)`)
				T.eq(part.Size, rec.Sizes[i], "as built")
			end
			-- the break: the halves fly rigidly
			local u = HatchFx.BurstTime * 0.5
			HatchFx.pose(rec, place, plan.Shake + u, plan.Shake, plan, red, false)
			local k = math.clamp(u / HatchFx.BurstTime, 0, 1)
			local up = place * CFrame.new(1.4 * k, 1.4 + 5 * k, 0) * CFrame.Angles(0, 0, -1.6 * k) * CFrame.new(0, -1.4, 0)
			local down = place * CFrame.new(-0.8 * k, -4 * k * k, 0) * CFrame.Angles(0, 0, 0.8 * k)
			local top = rec.Model:FindFirstChild("Top")
			local bottom = rec.Model:FindFirstChild("Bottom")
			for i, part in rec.Parts do
				local half = if part:IsDescendantOf(top) then up elseif part:IsDescendantOf(bottom) then down else nil
				if half then
					T.truthy(near(part.CFrame, half * rec.Base[i]), `{id} {part.Name}: its half's place (break)`)
				end
				T.eq(part.Size, rec.Sizes[i], "no stretch: the size as built")
			end
			-- gone: once every part is see-through nothing is written any more
			HatchFx.pose(rec, place, plan.Shake + HatchFx.BurstTime + 0.01, plan.Shake, plan, red, false)
			T.truthy(rec.Faded, id .. ": faded")
			rec.Parts[1].Transparency = 0.5
			HatchFx.pose(rec, place, plan.Shake + HatchFx.BurstTime + 0.1, plan.Shake, plan, red, false)
			T.eq(rec.Parts[1].Transparency, 0.5, "a faded egg is left alone")
			HatchFx.reset(rec)
			T.falsy(rec.Faded, "back in the pool: whole")
		end
		-- one egg: squashed and stretched part by part, then every size back as built (once)
		local rec = HatchFx.record(GolemBuilder.capsule("Crystal"))
		HatchFx.pose(rec, place, plan.Shake * 0.99, plan.Shake, plan, red, true)
		T.truthy(rec.Bent, "squashed")
		HatchFx.pose(rec, place, plan.Shake + 0.02, plan.Shake, plan, red, true)
		T.truthy(rec.Bent, "stretched at the break")
		HatchFx.pose(rec, place, plan.Shake + 0.2, plan.Shake, plan, red, true)
		T.falsy(rec.Bent, "then whole again")
		for i, part in rec.Parts do
			T.eq(part.Size, rec.Sizes[i], part.Name .. ": as built")
		end
		-- the controller: calm eggs for many on a phone; no flash left over the golem after a skip-all
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		T.truthy(string.find(source, "takeEggs(capsuleId, n, n > 3 and compactNow())", 1, true), "Open 10 on a phone: calm eggs")
		for _, name in { "reveal", "showGrid" } do
			local fn = string.match(source, "local function " .. name .. "%(.-\nend\n")
			T.truthy(fn and string.find(fn, "noFlash(o)", 1, true), name .. ": the break's flash cut")
		end
		local cut = string.match(source, "local function noFlash%(.-\nend\n")
		T.truthy(
			cut and string.find(cut, "flashTween:Cancel()", 1, true) and string.find(cut, "o.Flash.BackgroundTransparency = 1", 1, true)
		)
	end)
end
