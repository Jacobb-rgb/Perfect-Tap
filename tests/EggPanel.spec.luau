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
	local BrightTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BrightTheme")
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
					T.eq(line.Text, BrightTheme.chanceText(line.Chance), "the card's text: the bright look's")
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

	T.test("EggPanel: chance and price texts (the cards: two decimals at most, 1 in N under 0.1 %)", function()
		-- (the owner's clicker video: "46.33%", "6.5%", "1 in 3,333"; BrightTheme.chanceText)
		T.eq(BrightTheme.chanceText(0.4633), "46.33%")
		T.eq(BrightTheme.chanceText(0.45), "45%")
		T.eq(BrightTheme.chanceText(0.065), "6.5%")
		T.eq(BrightTheme.chanceText(0.001), "0.1%")
		T.eq(BrightTheme.chanceText(0.0003), "1 in 3,333")
		T.eq(BrightTheme.chanceText(1), "100%")
		T.eq(BrightTheme.chanceText(0), "-")
		T.eq(BrightTheme.chanceText(0 / 0), "-", "junk")
		for _, id in TEMPLE do
			for _, lucky in { false, true } do
				for _, line in EggPanel.lines(id, lucky, {}) do
					T.truthy(line.Text ~= "-" and line.Text ~= "0%", `{line.Golem}: a golem that can come out never reads 0`)
					if line.Chance < BrightTheme.OneInBelow then
						T.truthy(string.match(line.Text, "^1 in [%d,]+$") ~= nil, `{line.Text}: "1 in N" under 0.1 %`)
					else
						local decimals = string.match(line.Text, "%.(%d+)%%$")
						T.truthy(string.match(line.Text, "^[%d%.]+%%$") ~= nil, `{line.Text}: a percentage`)
						T.truthy(decimals == nil or #decimals <= 2, `{line.Text}: two decimals at most`)
					end
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
			T.eq(shadows, #lines - 1, "Crystal: the golems the player has none of are silhouettes")
			-- the name sits under the picture, inside the card (the card clips)
			local card = refs.Cards[1]
			T.truthy(card.Name.Size.Y.Offset == l.NameH and l.NameH >= 2 * l.NameSize, "two lines")
			T.truthy(card.Chance.Position.Y.Offset <= l.CardH - l.NameH + 2, "the chance over the name")
		end
		-- readable: 8 pt on a phone, every word of every name fits its card's width in the bright look's font
		-- (BrightTheme.Font, FredokaOne: the preview's copy)
		local width = fontWidth(Loader.root .. "/tools/preview/fonts/FredokaOne-Regular.ttf")
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
		T.truthy(width("Moonstone", 13) > 65, "the measure is the font's (Moonstone ~70 units at 13)")
		-- a TV (all-platforms: 18 px and more at 1080p, the HUD's scale 1.25 there): names and the x3 grow
		local tv = EggPanel.layout(14, false, true, { TenFoot = true })
		local hud = 1.25
		T.truthy(tv.TenFoot)
		T.truthy(tv.NameSize * hud >= 18, `the name {tv.NameSize * hud} px on a TV`)
		for _, word in { "Moonstone", "Heartstone", "Celestial", "Sovereign" } do
			T.truthy(width(word, tv.NameSize) <= tv.Card - 2, word .. " fits a TV card")
		end
		T.truthy(tv.LuckySize * hud >= 18, "the x3 18 px on a TV")
		T.truthy(tv.ChanceSize * hud >= 18, "the chance 18 px on a TV")
		local tvRefs = EggPanel.build()
		EggPanel.apply(tvRefs, "Stone", tv, hud)
		T.eq(tvRefs.Cards[1].Lucky.TextSize, tv.LuckySize, "applied: the x3's size")
		T.eq(tvRefs.Cards[1].Chance.TextSize, tv.ChanceSize, "applied: the chance's size")
		T.eq(tvRefs.Cards[1].Name.TextSize, tv.NameSize, "applied: the name's size")
		T.falsy(EggPanel.layout(14, true, true, { TenFoot = true }).TenFoot, "a touch screen isn't a TV")
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
				-- (PC: no opens in the panel, they stand round the big E: the cards end over the panel's foot)
				local foot = if touch then l.OpenY - l.OpenGap else l.Body - l.Pad
				for i = 1, count do
					local at = EggPanel.cardAt(l, i)
					T.truthy(at.X >= l.Pad - 0.01 and at.X + l.Card <= l.Width - l.Pad + 0.01, `{id} card {i}: inside left / right`)
					T.truthy(
						at.Y >= l.Pad + l.Head and at.Y + l.CardH <= foot + 0.01,
						`{id} card {i}: under the head row, above the opens (touch) or the foot (PC)`
					)
				end
				T.truthy(l.Picture >= (if touch then 44 else 72), `{id}: a big golem picture ({l.Picture})`)
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

	T.test("EggPanel: Auto's Waiting fits its toggle at its floor (phones, the narrow phone, a TV)", function()
		local TechShopView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.TechShopView")
		local refs = EggPanel.build()
		for _, case in
			{
				-- (phones: 10 pt outright at the HUD's 0.62 floor)
				{ 14, true, nil, EggPanel.PhoneScale, 10, "a phone, 14 golems" },
				{ 5, true, nil, EggPanel.PhoneScale, 10, "a phone, a five-golem egg" },
				{ 3, true, nil, EggPanel.PhoneScale, 10, "a phone, a three-golem egg (the Sky egg's size)" },
				{ 14, true, { Narrow = true }, EggPanel.PhoneScale, 10, "the narrow phone (568 x 320)" },
				{ 14, false, { TenFoot = true }, 1.25, 18, "a TV" },
			}
		do
			local count, touch, opts, scale, floor, label = case[1], case[2], case[3], case[4], case[5], case[6]
			local l = EggPanel.layout(count, touch, true, opts)
			EggPanel.apply(refs, "Stone", l, scale)
			EggPanel.setAuto(refs, true, true, if touch then "" else "G", nil, "Waiting")
			T.eq(refs.ToggleLabel.Text, "Waiting")
			local fit = refs.ToggleLabel:FindFirstChildOfClass("UITextSizeConstraint")
			T.truthy(fit ~= nil, label .. ": shrinks to its pill")
			T.truthy(fit.MinTextSize * scale >= floor, `{label}: never under {floor} ({fit.MinTextSize * scale})`)
			local room = refs.Toggle.Size.X.Offset + refs.ToggleLabel.Size.X.Offset
			T.truthy(TechShopView.textWidth("Waiting", fit.MinTextSize) + 4 <= room, `{label}: "Waiting" fits at its floor ({room} units)`)
		end
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

	T.test("EggPanel: the opens' keys (E is the prompt's; R and X go to the eggs at the temple)", function()
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
			if rel == "src/client/Controllers/HoverboardController.luau" then
				-- (R opens the hoverboards' window, owner 2026-11-07: bound once at start, so an egg
				-- panel's own R, bound later while it shows, goes first)
				T.eq(uses, 1, "the hoverboards' window key")
			elseif rel ~= "src/client/Controllers/PlacementController.luau" and rel ~= "src/client/Controllers/EggPanelController.luau" then
				T.eq(uses, 0, rel .. ": R / X are the eggs' (and build mode's)")
			end
		end
		local controller = fs.readFile(Loader.root .. "/src/client/Controllers/EggPanelController.luau")
		T.truthy(string.find(controller, "not ProximityPromptService.Enabled", 1, true), "the keys rest while the prompts are suppressed")
		T.truthy(string.find(controller, "UnbindAction(OPEN3_ACTION)", 1, true), "and are unbound when the panel goes")
	end)

	T.test("EggPanel: the opens' layout (touch: under the cards, 44 pt; PC: round the big E)", function()
		for _, id in TEMPLE do
			local count = #EggPanel.lines(id, false, {})
			for _, touch in { true } do
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
		local targets = EggPanel.touchTargets(refs)
		local trashes = 0
		for _, target in targets do
			T.truthy(target.Size.Y.Offset * EggPanel.PhoneScale >= EggPanel.MinTouch - 0.5, target.Name .. ": 44 pt high")
			T.truthy(target.Size.X.Offset * EggPanel.PhoneScale >= EggPanel.MinTouch - 0.5, target.Name .. ": 44 pt wide")
			trashes += if target.Name == "Trash" then 1 else 0
		end
		T.eq(trashes, math.min(14, EggPanel.MaxCards), "every card's trash is a 44 pt target (the whole card on touch)")
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
		-- PC and gamepads: no opens in the panel; they stand round the big E (owner's clicker video):
		-- Open 1 left of the disc (green, E), Open 3 under it (orange, R), Open 10 right (purple, X)
		local specs = {
			{ Count = 1, Robux = false, Price = "2,500", Enabled = true },
			{ Count = 3, Robux = false, Price = "7,500", Enabled = true },
			{ Count = 10, Robux = false, Price = "25K", Enabled = true },
		}
		EggPanel.apply(refs, "Stone", EggPanel.layout(14, false), 1)
		EggPanel.setOpens(refs, specs, EggPanel.OpenKeys, nil)
		for _, open in refs.Opens do
			T.falsy(open.Button.Visible, `PC: no Open {open.Count} in the panel`)
		end
		local p = EggPrompt.build()
		EggPrompt.setCluster(p, true)
		EggPrompt.setOpens(p, specs, EggPanel.OpenKeys, nil)
		local function boxOf(g: any): any
			local size = Vector2.new(g.Size.X.Offset, g.Size.Y.Offset)
			local at = Vector2.new(g.Position.X.Offset, g.Position.Y.Offset)
				- Vector2.new(g.AnchorPoint.X * size.X, g.AnchorPoint.Y * size.Y)
			return { Min = at, Max = at + size }
		end
		local disc = boxOf(p.Disc)
		local by: { [number]: any } = {}
		for _, open in p.Opens do
			local b = boxOf(open.Button)
			by[open.Count] = b
			T.truthy(open.Button.Visible, `Open {open.Count} round the E`)
			T.truthy(b.Min.X >= 0 and b.Min.Y >= 0 and b.Max.X <= EggPrompt.Width and b.Max.Y <= EggPrompt.Height, "inside the billboard")
			T.eq(EggPanel.overlap(b, disc), 0, `Open {open.Count} clear of the disc`)
			local paint = open.Button:FindFirstChild("Paint")
			T.eq(paint.Color.Keypoints[1].Value, BrightTheme.Paints[EggPanel.OpenPaints[open.Count]].Top, "its paint")
			T.eq(open.KeyText.Text, EggPanel.OpenKeys[open.Count], "its key")
		end
		T.truthy(by[1].Max.X <= disc.Min.X, "Open 1 left of the E")
		T.truthy(by[10].Min.X >= disc.Max.X, "Open 10 right of it")
		T.truthy(by[3].Min.Y >= disc.Max.Y, "Open 3 under it")
		T.truthy(p.Title.Position.Y.Offset <= disc.Min.Y, '"Buy Egg!" above the E')
		T.eq(EggPanel.OpenPaints[1], "Green")
		T.eq(EggPanel.OpenPaints[3], "Orange")
		T.eq(EggPanel.OpenPaints[10], "Purple")
		-- a gamepad walks round them: Open 1 -> Open 10 (right), Open 3 under both
		T.eq(by[1] and p.Opens[1].Button.NextSelectionRight, p.Opens[3].Button, "Open 1 -> Open 10")
		T.eq(p.Opens[1].Button.NextSelectionDown, p.Opens[2].Button, "Open 1 -> Open 3")
		T.eq(p.Opens[2].Button.NextSelectionUp, p.Opens[1].Button, "Open 3 -> Open 1")
		-- touch: the disc alone with its price under it (the floating panel has the opens)
		EggPrompt.setCluster(p, false)
		for _, open in p.Opens do
			T.falsy(open.Button.Visible, "touch: no opens round the E")
		end
		T.truthy(p.Price.Visible, "touch: the price under the disc")
		T.eq(EggPrompt.size(false), EggPrompt.Single)
		T.eq(EggPrompt.size(true), Vector2.new(EggPrompt.Width, EggPrompt.Height))
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

	-- A touch screen as EggPanelController measures it (px): Roblox's top bar row `inset` tall (36 in the
	-- previews, 58 live), the safe frame (`notch`: left, right, bottom insets), the HUD's teleport bar
	-- (HudBubble: the round look's row, centred), and the boost corner / tutorial bubble when given.
	-- The HUD's left column on a touch screen as EggPanelController measures it: the tiles and the
	-- TRAIN chip, two boxes (HudBubble: the chip under the tiles or, on the smallest phones, beside
	-- their last row; under the top bar; the gui `view.Y - inset` tall).
	local function hudLeft(view: any, inset: number, scale: number): { any }
		local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
		local layout = HudBubble.layout(scale, view.X, true, false, view.Y - inset)
		local m = HudBubble.menuMetrics(layout, #HudBubble.gameMenu())
		local x0, y0 = m.Origin.X.Offset, m.Origin.Y.Offset
		local chipLeft = HudBubble.chipLeft(layout) or x0
		local chipTop = HudBubble.chipTop(layout)
		local chipWidth = HudBubble.chipWidth(layout) or HudBubble.TouchChipWidth
		return {
			{
				Min = Vector2.new(x0 * scale, inset + y0 * scale),
				Max = Vector2.new((x0 + m.Width) * scale, inset + (y0 + m.Height) * scale),
			},
			{
				Min = Vector2.new(chipLeft * scale, inset + chipTop * scale),
				Max = Vector2.new((chipLeft + chipWidth) * scale, inset + (chipTop + HudBubble.TouchChipHeight) * scale),
			},
		}
	end
	local function touchScreen(view: any, inset: number, notch: { number }?, corner: any?, bubble: any?): (any, number, any)
		local HudBubble = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HudBubble")
		local scale = math.clamp(math.min(view.Y / 720, view.X / 1100), 0.62, 1.25)
		local n = notch or { 0, 0, 0 }
		local safe = { Min = Vector2.new(n[1], inset), Max = Vector2.new(view.X - n[2], view.Y - n[3]) }
		local bar = HudBubble.topBarSize(HudBubble.layout(scale, view.X, true, false)) * scale
		local y0 = inset + HudBubble.topBarY(inset, scale) * scale
		local cx = (safe.Min.X + safe.Max.X) / 2
		local topBar = { Min = Vector2.new(cx - bar.X / 2, y0), Max = Vector2.new(cx + bar.X / 2, y0 + bar.Y) }
		local input = {
			View = view,
			Safe = safe,
			TopInset = inset,
			Hud = { topBar, table.unpack(hudLeft(view, inset, scale)) },
			Corner = corner,
			Bubble = bubble,
		}
		return EggPanel.screen(input), scale, input
	end
	local function touchInput(view: any, inset: number, notch: { number }?, corner: any?, bubble: any?): any
		local _, _, input = touchScreen(view, inset, notch, corner, bubble)
		return input
	end
	-- The floating panel of egg `id` on `s` as the controller lays it out and places it.
	local function floatOn(s: any, scale: number, id: string, egg: any): any
		local count = #EggPanel.lines(id, false, {})
		local auto = EggPanel.autoAllowed(id)
		local narrow = EggPanel.pickNarrow(s, scale, count, auto)
		local l = EggPanel.layout(count, true, auto, { Narrow = narrow })
		local size = Vector2.new(math.ceil(l.Width * scale), math.ceil(l.Height * scale))
		local row, odds = EggPanel.rowBox(l, scale), EggPanel.oddsBox(l, scale)
		local at, fit = EggPanel.floatAt(s, size, row, odds, egg, 40)
		return { At = at, Fit = fit, Layout = l, Size = size, Row = row, Odds = odds, Narrow = narrow }
	end
	local function box(x0: number, y0: number, x1: number, y1: number): any
		return { Min = Vector2.new(x0, y0), Max = Vector2.new(x1, y1) }
	end

	T.test("EggPanel: on touch the panel floats clear of the thumbstick, the touch buttons and the top bar", function()
		local BoostView = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.BoostView")
		for _, view in { Vector2.new(568, 320), Vector2.new(667, 375), Vector2.new(844, 390), Vector2.new(1024, 768) } do
			for _, inset in { 36, 58 } do
				local s, scale = touchScreen(view, inset)
				local small = math.min(view.X, view.Y) <= 500
				T.eq(
					#s.Keep,
					#BoostView.TouchButtons[if small then "Small" else "Large"] + 3,
					"the touch buttons, the teleport bar, the left tiles, the TRAIN chip"
				)
				T.near(s.Zone.Max.X, view.X * 0.4, 1e-3, "the thumbstick's zone")
				for _, id in TEMPLE do
					for _, ex in { 0.3, 0.45, 0.5, 0.55, 0.7 } do
						for _, ey in { 0.35, 0.5, 0.65 } do
							local f = floatOn(s, scale, id, Vector2.new(view.X * ex, view.Y * ey))
							local where = `{id} on {view.X}x{view.Y} (inset {inset}), the egg at ({ex}, {ey})`
							-- never: the opens' row in the zone, under a touch button or the top bar, the panel off the screen
							T.eq(f.Fit.Hard, 0, where .. ": the opens' row clear, the panel on the screen")
							local row = { Min = f.Row.Min + f.At, Max = f.Row.Max + f.At }
							T.truthy(row.Min.X >= s.Zone.Max.X or row.Max.Y <= s.Zone.Min.Y, where .. ": the row out of the zone")
							T.truthy(f.At.X >= 0 and f.At.Y >= 0 and f.At.X + f.Size.X <= view.X and f.At.Y + f.Size.Y <= view.Y)
							if view.X >= 640 then
								-- and every card (picture, chance, name) visible
								T.eq(f.Fit.Odds, 0, where .. ": every odd visible")
								T.falsy(f.Narrow, "the usual layout")
							else
								-- (568: where the usual panel doesn't fit right of the zone under the top bar,
								-- the row on top, right-aligned; an egg of few golems may still fit)
								T.truthy(f.Narrow or f.Fit.Odds == 0, where .. ": the narrow layout, or every odd visible")
							end
						end
					end
				end
			end
		end
		-- 568 x 320: Grab and FIRE step aside for the narrow panel (EggPanelController.TinyWidth): every odd shows
		for _, inset in { 36, 58 } do
			local tiny, tinyScale, input = touchScreen(Vector2.new(568, 320), inset)
			input.Held = { Grab = true, Fire = true }
			tiny = EggPanel.screen(input)
			T.eq(#tiny.Keep - #input.Hud, 1, "only Jump left of the touch buttons (the HUD's boxes stay)")
			for _, id in TEMPLE do
				local f = floatOn(tiny, tinyScale, id, Vector2.new(284, 160))
				T.eq(f.Fit.Hard, 0, `568 {id}: the row clear`)
				T.eq(f.Fit.Odds, 0, `568 {id} (inset {inset}): with Grab and FIRE held, every odd visible`)
			end
		end
		-- the narrow layout: its row on top, right-aligned, still 44 pt; the cards under it
		local narrow = EggPanel.layout(14, true, true, { Narrow = true })
		T.truthy(narrow.RowFirst)
		T.eq(EggPanel.openAt(narrow, 1).Y, narrow.Pad, "the row first")
		T.truthy(EggPanel.cardAt(narrow, 1).Y >= narrow.OpenY + narrow.Open.Y, "the cards under it")
		local last = EggPanel.openAt(narrow, #CapsuleConfig.Counts + 1)
		T.near(last.X + narrow.Open.X, narrow.Width - narrow.Pad, 1e-9, "flush right")
		T.truthy(narrow.Open.Y * EggPanel.PhoneScale >= EggPanel.MinTouch - 0.5, "44 pt")
		-- the notch (844 x 390, an iPhone 12-14: 47 px each side, 21 at the bottom): inside the safe frame
		local s, scale = touchScreen(Vector2.new(844, 390), 58, { 47, 47, 21 })
		for _, ex in { 0.4, 0.5, 0.6 } do
			local f = floatOn(s, scale, "Stone", Vector2.new(844 * ex, 195))
			T.eq(f.Fit.Hard, 0, "notch: the row inside the safe frame, off FIRE (measured in it)")
			T.eq(f.Fit.Odds, 0, "notch: no chance under the notch")
			T.truthy(f.At.X + f.Size.X <= 844 - 47, "the panel's right edge inside")
		end
		-- the billboard's SizeOffset puts its top-left exactly there (x right, y up, in its own size)
		local size = Vector2.new(300, 160)
		local anchor = Vector2.new(400, 200)
		local at = Vector2.new(320, 60)
		local o = EggPanel.floatOffset(anchor, at, size)
		local center = Vector2.new(anchor.X + o.X * size.X, anchor.Y - o.Y * size.Y)
		T.near(center.X - size.X / 2, at.X, 1e-9)
		T.near(center.Y - size.Y / 2, at.Y, 1e-9)
		T.eq(EggPanel.overlap(box(0, 0, 10, 10), box(5, 5, 15, 15)), 25)
		T.eq(EggPanel.overlap(box(0, 0, 10, 10), box(10, 0, 20, 10)), 0)
		-- the cards' trash: on touch the whole card is its tap area, never in the thumbstick's zone
		-- (only the narrow layout of the smallest phones puts a card there: its trash rests, hidden)
		local tinyS, tinyScale = touchScreen(Vector2.new(568, 320), 36)
		local rested = 0
		for _, id in TEMPLE do
			local f = floatOn(tinyS, tinyScale, id, Vector2.new(284, 160))
			local blocked = EggPanel.trashInZone(f.Layout, f.At, tinyScale, tinyS.Zone)
			for i = 1, f.Layout.Count do
				local c = EggPanel.cardAt(f.Layout, i)
				local min = f.At + Vector2.new(c.X, f.Layout.Title + c.Y) * tinyScale
				local card = { Min = min, Max = min + Vector2.new(f.Layout.Card, f.Layout.CardH) * tinyScale }
				local inZone = EggPanel.overlap(card, tinyS.Zone) > 0
				T.eq(blocked[i] == true, inZone, `568 {id} card {i}: its trash rests exactly where the zone is`)
				rested += if inZone then 1 else 0
			end
		end
		T.truthy(rested >= 0, "(today's eggs of 4 or 5 golems keep clear of the zone; a bigger egg would rest them)")
		for _, view in { Vector2.new(667, 375), Vector2.new(844, 390) } do
			local s, scale = touchScreen(view, 58)
			for _, id in TEMPLE do
				local f = floatOn(s, scale, id, Vector2.new(view.X * 0.5, view.Y * 0.5))
				local blocked = EggPanel.trashInZone(f.Layout, f.At, scale, s.Zone)
				T.eq(next(blocked), nil, `{view.X} {id}: every card (its trash) clear of the zone`)
			end
		end
		local everywhere = box(0, 0, 9999, 9999)
		T.eq(next(EggPanel.trashInZone(EggPanel.layout(14, false), Vector2.zero, 1, everywhere)), nil, "PC: the icon only, no zone")
	end)

	T.test("EggPanel: the tutorial bubble and the boost corner never hide the odds or the buttons", function()
		-- the touch tutorial bubble (TutorialView, top right; review 2026-10-28: 667 x 375 x 467-658, y 64-172)
		for _, case in { { Vector2.new(667, 375), box(467, 64, 658, 172) }, { Vector2.new(844, 390), box(625, 64, 835, 172) } } do
			local view, bubble = case[1], case[2]
			local s, scale = touchScreen(view, 58, nil, nil, bubble)
			local f = floatOn(s, scale, "Stone", Vector2.new(view.X * 0.5, view.Y * 0.5))
			local input = touchInput(view, 58, nil, nil, bubble)
			local holdCorner, holdBubble = EggPanel.asides(input, f.Size, f.Row, f.Odds, Vector2.new(view.X * 0.5, view.Y * 0.5), 40)
			T.falsy(holdCorner, "no corner here")
			if holdBubble then
				-- no room beside it on a phone: the bubble steps aside (the controller holds it) and every odd shows
				local free, freeScale = touchScreen(view, 58)
				local g = floatOn(free, freeScale, "Stone", Vector2.new(view.X * 0.5, view.Y * 0.5))
				T.eq(g.Fit.Hard, 0, `{view.X}: with the bubble held, the opens clear`)
				T.eq(g.Fit.Odds, 0, `{view.X}: with the bubble held, every odd visible`)
			else
				T.eq(f.Fit.Hard, 0, `{view.X}: the opens never under the bubble`)
				T.eq(f.Fit.Odds, 0, `{view.X}: beside the bubble, every odd visible`)
			end
		end
		-- the boost corner (BoostView.cornerSpot; review: an iPad with Triple Lucky, one tile x 938-1005, y 465-549)
		local ipad = Vector2.new(1024, 768)
		local tile = box(938, 465, 1005, 549)
		local s, scale = touchScreen(ipad, 58, nil, tile)
		for _, id in TEMPLE do
			for _, ey in { 0.35, 0.45, 0.55, 0.65 } do
				local f = floatOn(s, scale, id, Vector2.new(ipad.X * 0.5, ipad.Y * ey))
				local where = `iPad {id}, the egg at y {ey}`
				T.eq(f.Fit.Hard, 0, where .. ": Auto clear of the clover tile")
				T.eq(f.Fit.Odds, 0, where .. ": every odd visible")
				local holdCorner =
					EggPanel.asides(touchInput(ipad, 58, nil, tile), f.Size, f.Row, f.Odds, Vector2.new(ipad.X * 0.5, ipad.Y * ey), 40)
				T.falsy(holdCorner, where .. ": room beside it: the corner stays")
			end
		end
		-- a phone with both boosts (review: 667 x 375, the column x 610-655, y 156-276; 844 x 390, y 171-291)
		for _, case in { { Vector2.new(667, 375), box(610, 156, 655, 276) }, { Vector2.new(844, 390), box(787, 171, 832, 291) } } do
			local view, column = case[1], case[2]
			local p, pScale = touchScreen(view, 58, nil, column)
			local f = floatOn(p, pScale, "Stone", Vector2.new(view.X * 0.5, view.Y * 0.5))
			local holdCorner =
				EggPanel.asides(touchInput(view, 58, nil, column), f.Size, f.Row, f.Odds, Vector2.new(view.X * 0.5, view.Y * 0.5), 40)
			if holdCorner then
				-- no room beside it: the corner steps aside (held), then the row and every odd are clear
				local free, freeScale = touchScreen(view, 58)
				local g = floatOn(free, freeScale, "Stone", Vector2.new(view.X * 0.5, view.Y * 0.5))
				T.eq(g.Fit.Hard, 0, `{view.X}: Auto clear`)
				T.eq(g.Fit.Odds, 0, `{view.X}: every odd visible`)
			else
				T.eq(f.Fit.Hard, 0, `{view.X}: Auto clear of the column`)
				T.eq(f.Fit.Odds, 0, `{view.X}: every odd visible beside it`)
			end
		end
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
		T.falsy(EggPanel.holdCards("Idle"), "the opening ended: the golems are out")
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
				PlayerGui = playerGui,
				CharacterRemoving = signal(),
				WaitForChild = function()
					return playerGui
				end,
				FindFirstChildOfClass = function(_, class: string)
					return if class == "PlayerGui" then playerGui else nil
				end,
				GetAttribute = function(_, key: string)
					return if key == "PaidRandomRestricted" then false else nil -- (the policy said: paid random items allowed)
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
		hooks.inputChanged = hooks.inputChanged or signal()
		local C0 = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.EggPanelController")
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
			touch = false,
			holds = {},
			tweens = {},
			renders = {},
			deletes = {},
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
				"GetPropertyChangedSignal",
				function()
					return signal() -- (the opening's selection lock watches SelectedObject: never fires here)
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
				function(_, name, _priority, fn)
					w.renders[name] = fn
				end,
			},
			{
				Run,
				"UnbindFromRenderStep",
				function(_, name)
					w.renders[name] = nil
				end,
			},
			{ UIS, "LastInputTypeChanged", hooks.inputChanged },
			{ UIS, "TouchEnabled", false },
			{ UIS, "MouseEnabled", true },
			{
				UIS,
				"GetLastInputType",
				function()
					return Enum.UserInputType.MouseButton1
				end,
			},
			{
				Workspace,
				"GetServerTimeNow",
				function()
					return NOW
				end,
			},
			{
				game:GetService("ReplicatedStorage"),
				"GetAttribute",
				function()
					return nil
				end,
			},
			{
				HudController,
				"predictedCoins",
				function()
					return w.coins
				end,
			},
			{
				C0,
				"holdCorner",
				function(on)
					table.insert(w.holds, { "Corner", on })
				end,
			},
			{
				C0,
				"holdBubble",
				function(on)
					table.insert(w.holds, { "Bubble", on })
				end,
			},
			{
				C0,
				"holdTouch",
				function(on)
					table.insert(w.holds, { "Touch", on })
				end,
			},
			{
				CapsuleController,
				"showing",
				function()
					return w.opening == "Playing"
				end,
			},
			{
				CapsuleController,
				"setAutoHook",
				function(hook)
					hooks.autoHook = hook -- (set once, at the controller's init)
				end,
			},
			{
				CapsuleController,
				"onPlaying",
				function(fn)
					hooks.onPlaying = fn
				end,
			},
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
				"justEnded",
				function()
					return w.justEnded == true
				end,
			},
			{
				CapsuleController,
				"setAutoDelete",
				function(kind, on)
					table.insert(w.deletes, { Kind = kind, On = on })
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
				function(on, note)
					table.insert(w.auto, on)
					w.autoNote = note
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
					return w.scale or 1
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
					return w.touch
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
					C._test.fresh()
					local inner, problem = pcall(body, C, w)
					w.opening = "Idle"
					w.leave()
					-- (Roblox hides a prompt out of reach: PromptHidden, which Lune can't fire)
					for id in C._test.state().Spots do
						C._test.unprompt(id)
					end
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
			-- PC: the opens stand round the big E (its prompt shows in reach), with their keys
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Keyboard)
			s = C._test.state()
			T.truthy(s.Prompt.Cluster, "PC: the opens round the E")
			for i, open in s.Prompt.Opens do
				T.truthy(open.Button.Visible, `Open {open.Count} shows round the E`)
				T.eq(open.KeyText.Text, EggPanel.OpenKeys[open.Count])
				T.falsy(s.Refs.Opens[i].Button.Visible, "and not in the panel")
			end
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
			T.eq(w.auto[#w.auto], true, "the opening knows (its fast timings, its Auto button on)")
			C._test.tick()
			T.eq(#w.buys, 1, "it opens one")
			T.truthy(w.buys[1].Quiet and w.buys[1].Count == 1, "one egg, quietly")
			-- one at a time: nothing while an open waits or its opening plays
			for _, state in { "Waiting", "Playing" } do
				w.opening = state
				C._test.tick()
				T.eq(#w.buys, 1, state .. ": it waits")
			end
			w.opening = "Idle"
			C._test.tick()
			T.eq(#w.buys, 2, "the next egg as soon as the opening ended (the golems flew to the player)")
			T.eq(C.AutoDwell, nil, "no end screen to dwell on")
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
				T.eq(w.auto[#w.auto], false, label .. ": the opening knows")
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
			stops("its button in the opening", function()
				T.truthy(hooks.autoHook and hooks.autoHook.available(), "the opening's Auto button shows here")
				hooks.autoHook.toggle()
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
			-- the odds change under Auto (Triple Lucky ran out during an opening): it stops, and the
			-- opening says why by its Auto button (the HUD's toasts hide while it plays)
			w.lucky = true
			stops("Triple Lucky ran out", function()
				w.opening = "Playing"
				w.lucky = false
				local buys = #w.buys
				hooks.onChanged() -- (the boost's end pushes State while the egg opens)
				w.opening = "Idle"
				C._test.tick()
				T.eq(#w.buys, buys, "no egg on odds the player hasn't seen")
			end)
			T.eq(w.autoNote, "Triple Lucky ended: Auto stopped", "the opening's note says why")
			T.eq(C._test.state().Lucky, false, "the panel shows the normal odds now")
			-- Triple Lucky begins under Auto (no opening up): it stops, a toast says why
			stops("Triple Lucky began", function()
				w.opening = "Idle"
				w.lucky = true
				hooks.onChanged() -- (the boost's State push)
			end)
			T.eq(w.autoNote, nil, "no overlay: no note")
			T.eq(w.toasts[#w.toasts], "Triple Lucky is on: Auto stopped", "a toast")
			T.eq(C._test.state().Lucky, true)
			-- the boost runs out mid-hatch while the panel is laid out again (a resize, another device):
			-- Auto compares with the odds it started on, not with the cards' (review 2026-10-28 LOW)
			stops("Triple Lucky ran out during a re-layout", function()
				w.opening = "Playing"
				w.lucky = false
				w.touch = true
				hooks.inputChanged.fire() -- (LastInputTypeChanged: layOut clears the cards' egg, then refreshPanel)
				w.touch = false
			end)
			T.eq(w.autoNote, "Triple Lucky ended: Auto stopped")
			w.opening = "Idle"
			hooks.inputChanged.fire()
			-- while an egg opens the panel steps aside (the opening's own Auto button shows), then comes back
			local r = C._test.state().Refs
			hooks.onPlaying(true)
			T.falsy(r.Gui.Enabled, "the panel steps aside while an egg opens")
			hooks.onPlaying(false)
			T.truthy(r.Gui.Enabled, "back with the HUD")
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
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Gamepad)
			local s = C._test.state()
			T.eq(s.Current, "Stone")
			T.eq(w.selected, nil, "the panel came up and selected nothing: the stick still walks")
			T.eq(w.actions.TerraForgeEggFocusKey, C.FocusKey, "the focus button is bound")
			T.eq(s.Prompt.Opens[2].KeyText.Text, C.FocusKey.Name, "Open 3's badge: the focus button")
			T.eq(s.Prompt.Opens[3].KeyText.Text, C.FocusKey.Name, "Open 10's badge")
			-- out of reach the focus button keeps its usual job
			w.at("Stone", EggPanel.PromptDistance + 0.5)
			local result = w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(result, Enum.ContextActionResult.Pass, "not in reach: passed on")
			T.eq(w.selected, nil)
			-- in reach: Open 1 round the E is selected, the D-pad walks to Open 10 / 3 and up to the cards' trash and Auto
			w.at("Stone")
			result = w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(result, Enum.ContextActionResult.Sink)
			T.eq(w.selected, s.Prompt.Opens[1].Button, "Open 1 (round the E) selected")
			T.eq(s.Prompt.Opens[1].Button.NextSelectionRight, s.Prompt.Opens[3].Button, "the D-pad: Open 10 right")
			T.eq(s.Prompt.Opens[1].Button.NextSelectionDown, s.Prompt.Opens[2].Button, "Open 3 under it")
			T.eq(s.Prompt.Opens[1].Button.NextSelectionUp, s.Refs.Toggle, "up: Auto (no golem found yet: no trash)")
			T.eq(s.Refs.Toggle.NextSelectionDown, s.Prompt.Opens[3].Button, "and back down")
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
			T.eq(w.selected, s.Prompt.Opens[1].Button)
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
			-- the opening is over (the golems flew to the player): it lights up
			w.opening = "Idle"
			hooks.onChanged()
			T.falsy(C._test.state().Lines[index].Silhouette, "in colour after the reveal")
			T.eq(s.Refs.Cards[index].View.ImageColor3, roblox.Color3.new(1, 1, 1))
			w.state.Golems.Owned = {}
		end)
	end)
	-- A camera for the controller (Lune has none): every point at `w.camZ` deep, on the screen when in front;
	-- the egg in the view's middle (`w.camShift` px aside).
	local function fakeCamera(w: any): any
		local CFrame = Loader.CFrame
		local view = w.view or Vector2.new(667, 375)
		return {
			ViewportSize = view,
			CFrame = CFrame.new(),
			WorldToViewportPoint = function(_, p)
				local x = view.X / 2 + math.clamp(p.X - w.camAt.X, -5, 5) * 4 + (w.camShift or 0)
				return Vector3.new(x, w.camY or 190, w.camZ), w.camZ > 0
			end,
		}
	end

	T.test("EggPanelController: no keys with the panel off the screen; Auto's badge rests while the panel is focused", function()
		withController(function(C, w)
			w.gamepad = true
			-- (PC: the panel over the egg, its card rows on a 1280 x 900 screen)
			w.view, w.camY = Vector2.new(1280, 900), 700
			rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
			w.camZ, w.camAt = 10, Vector3.zero
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Gamepad)
			local s = C._test.state()
			T.truthy(s.Reach, "in reach, the panel on the screen")
			T.eq(s.Refs.KeyText.Text, "ButtonB", "Auto's badge: B (its prompt's)")
			-- the panel takes the selection: B lets go there, so Auto's badge rests
			w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(w.selected, s.Prompt.Opens[1].Button)
			T.falsy(s.Refs.Key.Visible, "focused: no B on Auto (A presses the selected button)")
			w.actions.TerraForgeEggRelease("TerraForgeEggRelease", Enum.UserInputState.Begin)
			T.truthy(s.Refs.Key.Visible, "let go: B toggles Auto again")
			-- the player turns the camera away (the egg behind it): the panel isn't drawn, no key buys
			w.camZ = -5
			C._test.tick()
			T.falsy(C._test.state().Reach, "the panel behind the camera: out of reach")
			local before = #w.buys
			local open10 = w.actions.TerraForgeEggOpen10
			T.eq(open10("TerraForgeEggOpen10", Enum.UserInputState.Begin), Enum.ContextActionResult.Pass, "X passes")
			local focus = w.actions.TerraForgeEggFocus
			T.eq(focus("TerraForgeEggFocus", Enum.UserInputState.Begin), Enum.ContextActionResult.Pass, "D-pad Up: build / home")
			T.eq(w.selected, nil)
			T.eq(#w.buys, before, "nothing bought with the odds off the screen")
			w.camZ = 10
			C._test.tick()
			T.truthy(C._test.state().Reach, "back on the screen")
		end)
	end)

	T.test("EggPanelController: A on a focused open while an egg opens buys nothing (review HIGH 1)", function()
		withController(function(C, w)
			w.gamepad = true
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Gamepad)
			local s = C._test.state()
			w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(w.selected, s.Prompt.Opens[1].Button, "focused: Open 1 round the E")
			C.open("Stone", 1)
			local before = #w.buys
			T.eq(before, 1, "A buys while nothing opens")
			-- an egg opens: the panel veils, the selection is let go
			w.opening = "Playing"
			hooks.onPlaying(true)
			T.eq(w.selected, nil, "the opening let go of the selection")
			T.eq(w.actions.TerraForgeEggRelease, nil, "B is the opening's again")
			-- A on the button anyway (what its Activated calls): no buy is sent
			C.open("Stone", 1)
			C.open("Stone", 10)
			T.eq(#w.buys, before, "no buy while an egg opens")
			-- R / X and the focus button pass on (the opening's own keys), selecting nothing
			local r3 = w.actions.TerraForgeEggOpen3("TerraForgeEggOpen3", Enum.UserInputState.Begin)
			T.eq(r3, Enum.ContextActionResult.Pass, "R passes during the opening")
			local f = w.actions.TerraForgeEggFocus("TerraForgeEggFocus", Enum.UserInputState.Begin)
			T.eq(f, Enum.ContextActionResult.Pass, "D-pad Up selects nothing under the opening")
			T.eq(w.selected, nil)
			T.eq(#w.buys, before)
			-- the opening is over: the panel is back and buys again
			w.opening = "Idle"
			hooks.onPlaying(false)
			C.open("Stone", 1)
			T.eq(#w.buys, before + 1, "after the opening it buys again")
		end)
	end)

	T.test("EggPanelController: a card's trash asks first, then auto-deletes its golem; off at once; never on a Robux egg", function()
		withController(function(C, w)
			local kind = CapsuleConfig.odds("Stone", false)[1].Golem
			w.state.Golems.Owned = { { Id = 1, Kind = kind } }
			hooks.onChanged()
			w.at("Stone")
			local s = C._test.state()
			local index = nil
			for i, line in s.Lines do
				if line.Golem == kind then
					index = i
				end
				-- a silhouette (a golem not found yet) has no trash
				T.eq(s.Refs.Cards[i].Trash.Visible, not line.Silhouette, line.Golem .. ": a trash only on a found golem")
			end
			T.truthy(index ~= nil, "the found golem's card")
			local i = index :: number
			local card = s.Refs.Cards[i]
			T.truthy(card.Trash.Visible, "a coin egg's found golem: its trash")
			T.falsy(card.Confirm.Visible)
			-- first click: it asks
			C._test.trash(i)
			T.truthy(card.Confirm.Visible, 'first click: "AUTO-DELETE?"')
			T.eq(#w.deletes, 0, "nothing sent yet")
			-- second click: on (red), sent to the server
			C._test.trash(i)
			T.eq(#w.deletes, 1)
			T.eq(w.deletes[1].Kind, kind)
			T.eq(w.deletes[1].On, true)
			T.falsy(card.Confirm.Visible)
			T.eq(card.TrashDisc.BackgroundColor3, BrightTheme.Bad, "red while on")
			-- the server's State push keeps it on
			w.state.Golems.AutoDelete = { [kind] = true }
			hooks.onChanged()
			T.truthy(C._test.state().Deleting[kind], "the State's set")
			T.eq(card.TrashDisc.BackgroundColor3, BrightTheme.Bad)
			-- a change the State never takes (refused) shows the old state again once its wait is over
			patched({ { C, "TrashWait", -1 } }, function()
				C._test.trash(i)
				T.eq(#w.deletes, 2)
				T.eq(w.deletes[2].On, false)
				T.eq(card.TrashDisc.BackgroundColor3, BrightTheme.Bad, "the State still says on: red again")
			end)
			-- one click turns it off
			C._test.trash(i)
			T.eq(#w.deletes, 3)
			T.eq(w.deletes[3].On, false, "off at once, no question")
			T.eq(card.TrashDisc.BackgroundColor3, EggPanel.TrashOff)
			local base: number? = nil
			for _, f in s.Refs.Fades do
				if f.Target == card.TrashDisc and f.Property == "BackgroundTransparency" then
					base = f.Base
				end
			end
			T.eq(base, 0, "opaque either way: the panel's fade lerps from it (never washes the red out)")
			-- never while an egg opens
			w.opening = "Playing"
			hooks.onPlaying(true)
			C._test.trash(i)
			C._test.trash(i)
			T.eq(#w.deletes, 3, "the trash rests during an opening")
			w.opening = "Idle"
			hooks.onPlaying(false)
			-- an auto-deleted golem the player has none of stays found: its card in colour, its trash red
			w.state.Golems.Owned = {}
			hooks.onChanged()
			s = C._test.state()
			T.falsy(s.Lines[i].Silhouette, "auto-deleted: still discovered")
			T.truthy(s.Refs.Cards[i].Trash.Visible)
			-- a Robux egg: no trash at all (never a paid golem)
			w.at("Royal")
			s = C._test.state()
			T.eq(s.Current, "Royal")
			for j, line in s.Lines do
				T.falsy(line.Trash, line.Golem .. ": no trash on a Robux egg")
				T.falsy(s.Refs.Cards[j].Trash.Visible)
			end
			w.state.Golems.AutoDelete = nil
		end)
	end)

	T.test("EggPanelController: the panel's own buttons buy from ShowRange; the keys and the E need the prompt's reach", function()
		withController(function(C, w)
			-- a phone, a stud past the prompt's reach (the floating panel shows from ShowRange)
			w.touch = true
			w.scale = EggPanel.PhoneScale
			w.at("Stone", EggPanel.PromptDistance + 1)
			local s = C._test.state()
			T.eq(s.Current, "Stone", "the panel shows")
			T.falsy(s.Reach, "past the prompt's reach")
			local before = #w.buys
			T.truthy(C.open("Stone", 10, "Panel"), "the panel's own Open 10 buys")
			T.eq(#w.buys, before + 1)
			-- the big E's way (the keys, the disc, its opens) needs the reach: it says why
			local toasts = #w.toasts
			patched({ { C, "RefuseEvery", -1 } }, function() -- (a toast now, whatever the last spec showed)
				T.falsy(C.open("Stone", 1), "not from here")
			end)
			T.eq(#w.buys, before + 1)
			T.eq(w.toasts[#w.toasts], C.RefuseText.Far, "come closer")
			T.eq(#w.toasts, toasts + 1)
			-- mashing: one toast
			C.open("Stone", 1)
			C.open("Stone", 1)
			T.eq(#w.toasts, toasts + 1, "one toast for a mash")
			-- Auto from the panel's toggle: it starts and buys from here
			C.toggleAuto("Stone", "Panel")
			T.eq(C._test.state().Auto, "Stone", "the toggle starts Auto from ShowRange")
			local auto = #w.buys
			C._test.tick()
			T.truthy(#w.buys > auto, "Auto buys from here (the odds on the screen)")
			T.eq(s.Refs.ToggleLabel.Text, "Auto")
			C.toggleAuto("Stone", "Panel")
			-- right after an opening (a tap meant to skip it): the panel's buttons rest, quietly
			w.justEnded = true
			local quiet = #w.toasts
			T.falsy(C.open("Stone", 10, "Panel"), "no egg by a skip's tap")
			C.toggleAuto("Stone", "Panel")
			T.eq(C._test.state().Auto, nil, "no Auto by a skip's tap")
			T.eq(#w.toasts, quiet, "quietly")
			w.justEnded = false
			w.touch = false
			w.scale = nil
		end)
	end)

	T.test("EggPanelController: odds off the screen: the panel's buttons say so, Auto shows it waits", function()
		withController(function(C, w)
			w.view, w.camY = Vector2.new(1280, 900), 700
			rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
			w.camZ, w.camAt = 10, Vector3.zero
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Keyboard) -- (the big E up: the panel can't come down)
			local s = C._test.state()
			C.toggleAuto("Stone", "Panel")
			T.eq(C._test.state().Auto, "Stone")
			-- the camera pitched: the first card row above the screen
			w.camY = 80
			w.renders.TerraForgeEggPanelFloat()
			C._test.tick()
			T.eq(s.Refs.ToggleLabel.Text, "Waiting", "the toggle says Auto waits")
			local toasts = #w.toasts
			patched({ { C, "RefuseEvery", -1 } }, function() -- (a toast now, whatever the last spec showed)
				T.falsy(C.open("Stone", 1, "Panel"))
			end)
			T.eq(w.toasts[#w.toasts], C.RefuseText.Odds, "turn to see the odds")
			T.truthy(#w.toasts > toasts)
			w.camY = 700
			w.renders.TerraForgeEggPanelFloat()
			C._test.tick()
			T.eq(s.Refs.ToggleLabel.Text, "Auto", "back: Auto again")
			C.toggleAuto("Stone", "Panel")
			-- the PC odds box's sides: an egg near the screen's left edge has columns off the side
			w.camY = 700
			w.camShift = -500
			w.renders.TerraForgeEggPanelFloat()
			C._test.tick()
			T.falsy(C._test.state().Reach, "columns off the left side: not on the screen")
			w.camShift = nil
			C._test.tick()
			T.truthy(C._test.state().Reach, "in the middle: on it")
			-- and under Roblox's top bar: a first card row there isn't seen
			patched({
				{
					Loader.game:GetService("GuiService"),
					"GetGuiInset",
					function()
						return Vector2.new(0, 650), Vector2.zero -- (the first card row ends above 650 px)
					end,
				},
			}, function()
				C._test.tick()
				T.falsy(C._test.state().Reach, "the first row under the top bar: not on the screen")
			end)
		end)
	end)

	T.test("EggPanelController: refusals: live reach, one deny sound, keys never rebuy-guarded, Auto's Waiting cleared", function()
		withController(function(C, w)
			local Sfx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Effects.Sfx")
			local sounds: { string } = {}
			patched({
				{
					Sfx,
					"play",
					function(name: string)
						table.insert(sounds, name)
					end,
				},
				{ C, "RefuseEvery", 60 },
			}, function()
				-- reach measured live: a step into the prompt's reach on this very frame (no tick yet) buys
				w.at("Stone", EggPanel.PromptDistance + 1)
				T.falsy(C._test.state().Reach, "(the last tick: out of reach)")
				local spot = C._test.state().Spots.Stone
				w.position = spot.PromptAt
				local before = #w.buys
				T.truthy(C.open("Stone", 1), "E pressed the moment the prompt shows: it buys")
				T.eq(#w.buys, before + 1)
				-- one deny sound a refusal: the toast plays it; a mash between toasts plays it alone
				w.at("Stone", EggPanel.PromptDistance + 1)
				table.clear(sounds)
				local toasts = #w.toasts
				patched({ { C, "RefuseEvery", -1 } }, function()
					C.open("Stone", 1)
				end)
				T.eq(#w.toasts, toasts + 1, "a toast says why")
				T.falsy(table.find(sounds, "UIDeny"), "and plays the deny sound itself: none more")
				C.open("Stone", 1)
				T.eq(#w.toasts, toasts + 1, "a mash: no second toast")
				T.eq(#sounds, 1, "the deny sound alone")
				-- right after an opening: a pointer's press rests (a skip's tap), a key's buys
				w.at("Stone")
				w.justEnded = true
				before = #w.buys
				T.falsy(C.open("Stone", 10, "Pointer"), "the Open 10 round the E, clicked to skip: no")
				T.falsy(C.open("Stone", 3, "Panel"), "the panel's open: no")
				T.truthy(C.open("Stone", 1), "E (a key, never a skip): yes")
				T.eq(#w.buys, before + 1)
				-- and a card's trash: a skip's tap never asks "AUTO-DELETE?"
				local kind = CapsuleConfig.odds("Stone", false)[1].Golem
				w.state.Golems.Owned = { { Id = 1, Kind = kind } }
				hooks.onChanged()
				local card = C._test.state().Refs.Cards[1]
				T.truthy(card.Trash.Visible, "(a found golem's trash)")
				C._test.trash(1)
				T.falsy(card.Confirm.Visible, "no question by a skip's tap")
				w.justEnded = false
				C._test.trash(1)
				T.truthy(card.Confirm.Visible, "a real tap asks")
				w.state.Golems.Owned = {}
				hooks.onChanged()
			end)
		end)
	end)

	T.test("EggPanelController: B or G on the Auto prompt right after an opening never turns Auto on; later it does", function()
		withController(function(C, w)
			local CC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
			local ok, err = pcall(function()
				-- (the controller's own RebuyGuard, not the harness's stand-in)
				patched({ { CC, "justEnded", CC._test.justEnded } }, function()
					w.at("Stone")
					local spot = C._test.state().Spots.Stone
					local toasts = #w.toasts
					-- a pad's B mashed to skip the chain of openings (its skip-all) lands on the Auto prompt
					-- (Role "Second": B, G on a keyboard) the moment the chain ends and the prompts come back:
					-- its own Triggered handler, as Roblox fires it
					CC._test.ended(os.clock())
					T.truthy(C._test.trigger(spot.Auto), "(the Auto prompt's handler)")
					T.eq(C._test.state().Auto, nil, "within RebuyGuard: Auto stays off")
					T.eq(#w.toasts, toasts, "quietly")
					-- RebuyGuard later: a press means it
					CC._test.ended(os.clock() - CC.RebuyGuard - 0.05)
					C._test.trigger(spot.Auto)
					T.eq(C._test.state().Auto, "Stone", "after RebuyGuard: Auto on")
					-- it stops at once, though, even right after an opening
					CC._test.ended(os.clock())
					C._test.trigger(spot.Auto)
					T.eq(C._test.state().Auto, nil, "a press right after an opening still stops it")
					-- and E on the "Buy Egg!" prompt (one egg, never a skip) isn't guarded
					local before = #w.buys
					T.truthy(C._test.trigger(spot.Buy), "(the Buy prompt's handler)")
					T.eq(#w.buys, before + 1, "E buys")
				end)
			end)
			CC._test.ended(nil) -- (also when an assertion threw)
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.test("EggPanelController: a pause that begins or ends as Triple Lucky runs out: only Auto's stop is told, nothing bought", function()
		withController(function(C, w)
			w.view, w.camY = Vector2.new(1280, 900), 700
			rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
			w.camZ, w.camAt = 10, Vector3.zero
			-- (past the prompt's reach: the panel's toggle runs Auto from ShowRange; the tick's own refresh
			-- for a reach change stays out of it)
			w.lucky = true
			w.at("Stone", EggPanel.PromptDistance + 1)
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Keyboard) -- (the big E up: the panel can't come down)
			local function auto()
				C.toggleAuto("Stone", "Panel")
				T.eq(C._test.state().Auto, "Stone", "(Auto on)")
				T.truthy(C._test.state().Lucky, "(on Triple Lucky's odds)")
			end
			local function turn(camY: number)
				w.camY = camY
				w.renders.TerraForgeEggPanelFloat()
				C._test.tick()
			end
			-- the camera turns away (the odds off the screen) the moment Triple Lucky runs out
			auto()
			local toasts, buys = #w.toasts, #w.buys
			w.lucky = false
			turn(80)
			T.eq(C._test.state().Auto, nil, "Auto stopped on the new odds")
			T.eq(#w.toasts, toasts + 1, `one toast ({w.toasts[#w.toasts]})`)
			T.eq(w.toasts[#w.toasts], "Triple Lucky ended: Auto stopped", "Auto's stop, no Auto waits after it")
			T.eq(#w.buys, buys, "nothing bought")
			-- the other way: Auto waiting, the odds come back the moment Triple Lucky runs out
			turn(700)
			w.lucky = true
			hooks.onChanged()
			auto()
			turn(80)
			T.eq(C._test.state().Refs.ToggleLabel.Text, "Waiting", "(Auto waits)")
			toasts, buys = #w.toasts, #w.buys
			w.lucky = false
			turn(700)
			T.eq(C._test.state().Auto, nil, "Auto stopped on the new odds")
			T.eq(w.toasts[#w.toasts], "Triple Lucky ended: Auto stopped")
			T.eq(#w.buys, buys, "no egg bought as Auto stopped (the new odds only just showed)")
			w.lucky = false
		end)
	end)

	T.test("EggPanelController: Auto waits: a toast says why once a pause where the toggle isn't seen (PC; touch: egg behind)", function()
		withController(function(C, w)
			local function said(): number
				local n = 0
				for _, text in w.toasts do
					if text == C.AutoWaitsText then
						n += 1
					end
				end
				return n
			end
			-- PC: the panel over the egg, its odds rows on a 1280 x 900 screen
			w.view, w.camY = Vector2.new(1280, 900), 700
			rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
			w.camZ, w.camAt = 10, Vector3.zero
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Keyboard) -- (the big E up: the panel can't come down)
			C.toggleAuto("Stone", "Panel")
			T.eq(C._test.state().Auto, "Stone")
			local function turn(camY: number, camZ: number)
				w.camY, w.camZ = camY, camZ
				w.renders.TerraForgeEggPanelFloat()
				C._test.tick()
			end
			turn(80, 10) -- (the first card row above the screen)
			T.eq(C._test.state().Refs.ToggleLabel.Text, "Waiting")
			T.eq(said(), 1, "PC: the toast once")
			turn(80, 10)
			turn(140, 10)
			T.eq(said(), 1, "once a pause")
			turn(700, 10)
			T.eq(C._test.state().Refs.ToggleLabel.Text, "Auto", "the odds back")
			turn(80, 10)
			T.eq(said(), 2, "the next pause: once more")
			turn(700, 10)
			C.toggleAuto("Stone", "Panel")
			T.eq(C._test.state().Auto, nil)
			-- touch: the panel floats on the screen while its egg is in front of the camera (a 667 x 375 phone)
			local function phone(): any
				return {
					View = Vector2.new(667, 375),
					Safe = box(0, 58, 667, 375),
					TopInset = 58,
					Hud = { box(206, 4, 461, 55), box(0, 58, 190, 230) },
				}
			end
			patched({ { C, "screenInput", phone } }, function()
				w.touch = true
				w.scale = EggPanel.PhoneScale
				w.view = Vector2.new(667, 375)
				rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
				hooks.inputChanged.fire() -- (the touch layout: the panel floats beside the egg)
				w.at("Stone")
				turn(190, 10)
				T.truthy(C._test.state().Refs.Layout.Beside, "(touch: it floats)")
				C.toggleAuto("Stone", "Panel")
				T.eq(C._test.state().Auto, "Stone", "(touch: Auto on)")
				local before = said()
				-- the egg off the screen's side, in front: the panel docks on the screen, its toggle says Waiting
				w.camShift = 900
				turn(190, 10)
				T.eq(C._test.state().Refs.ToggleLabel.Text, "Waiting")
				T.eq(said(), before, "touch, the panel on the screen: its toggle says it, no toast")
				-- then behind the camera: the panel isn't drawn: the toast, once
				turn(190, -5)
				T.eq(said(), before + 1, "touch, the egg behind the camera: the toast")
				turn(190, -5)
				T.eq(said(), before + 1, "once a pause")
				-- in front again (still off the side: the same pause), then behind once more: no second toast
				turn(190, 10)
				T.eq(C._test.state().Refs.ToggleLabel.Text, "Waiting", "(the same pause)")
				turn(190, -5)
				T.eq(said(), before + 1, "behind, in front, behind: still once a pause")
				w.camShift = nil
				turn(190, 10)
				C.toggleAuto("Stone", "Panel")
				w.touch = false
				w.scale = nil
			end)
		end)
	end)

	T.test("EggPanelController: Auto's Waiting is gone once Triple Lucky stops it", function()
		withController(function(C, w)
			w.view, w.camY = Vector2.new(1280, 900), 700
			rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
			w.camZ, w.camAt = 10, Vector3.zero
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Keyboard)
			local s = C._test.state()
			C.toggleAuto("Stone", "Panel")
			w.camY = 80
			w.renders.TerraForgeEggPanelFloat()
			C._test.tick()
			T.eq(s.Refs.ToggleLabel.Text, "Waiting")
			-- Triple Lucky begins: Auto stops (the odds changed under it)
			w.lucky = true
			hooks.onChanged()
			T.eq(C._test.state().Auto, nil, "stopped")
			w.camY = 700
			w.renders.TerraForgeEggPanelFloat()
			C._test.tick()
			C.toggleAuto("Stone", "Panel")
			T.eq(C._test.state().Auto, "Stone")
			T.eq(s.Refs.ToggleLabel.Text, "Auto", "on again: no stale Waiting")
			C.toggleAuto("Stone", "Panel")
			w.lucky = false
			hooks.onChanged()
		end)
	end)

	T.test("EggPanelController: on touch the opens stay in the floating panel (the E alone), 44 pt", function()
		withController(function(C, w)
			w.touch = true
			w.scale = EggPanel.PhoneScale
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Touch)
			local s = C._test.state()
			T.falsy(s.Prompt.Cluster, "touch: the disc alone")
			for i, open in s.Prompt.Opens do
				T.falsy(open.Button.Visible, "no opens round the E on touch")
				T.truthy(s.Refs.Opens[i].Button.Visible, "they are in the panel's row")
				T.truthy(s.Refs.Opens[i].Button.Size.Y.Offset * EggPanel.PhoneScale >= EggPanel.MinTouch - 0.5, "44 pt")
			end
			T.truthy(s.Prompt.Price.Visible, "the price under the disc")
			w.touch = false
			w.scale = nil
		end)
	end)

	T.test("EggPanelController: on PC the panel stays on the screen (down under the top bar, never over the big E)", function()
		withController(function(C, w)
			w.view, w.camY = Vector2.new(1280, 900), 200
			rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
			w.camZ, w.camAt = 10, Vector3.zero
			-- the panel up, out of the prompt's reach (no big E): its top would be off the screen
			w.at("Stone", EggPanel.PromptDistance + 0.5)
			local s = C._test.state()
			local float = w.renders.TerraForgeEggPanelFloat
			T.truthy(float ~= nil, "PC: kept on the screen every frame while it shows")
			float()
			local h = s.Refs.Gui.Size.Y.Offset
			T.truthy(200 - h < 0, "(over the egg its top would be off the screen)")
			local top = 200 - h * (0.5 + s.Refs.Gui.SizeOffset.Y)
			T.near(top, EggPanel.Margin, 1, "it moved down: its top just under the top bar")
			-- far enough down the screen: over the egg as always
			w.camY = 700
			float()
			T.near(s.Refs.Gui.SizeOffset.Y, 0.5, 1e-6, "its bottom edge on the egg's top")
			-- the big E up under it: the panel never moves down over its opens
			w.camY = 200
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Keyboard)
			float()
			T.near(s.Refs.Gui.SizeOffset.Y, 0.5, 1e-6, "no room over the big E: it stays")
			w.leave()
			T.eq(w.renders.TerraForgeEggPanelFloat, nil, "unbound when the panel goes")
		end)
	end)

	T.test("EggPanelController: with the odds off the screen nothing buys: E, the opens, pad A and Auto refuse like R / X", function()
		withController(function(C, w)
			-- (PC, 1280 x 900: the panel over the egg; the big E with its opens up)
			w.view, w.camY = Vector2.new(1280, 900), 700
			rawset(Loader.game:GetService("Workspace"), "CurrentCamera", fakeCamera(w))
			w.camZ, w.camAt = 10, Vector3.zero
			w.at("Stone")
			C._test.prompt("Stone", Enum.ProximityPromptInputType.Keyboard)
			local float = w.renders.TerraForgeEggPanelFloat
			C.open("Stone", 1)
			T.eq(#w.buys, 1, "the odds on the screen: E buys")
			-- the camera pitched down: the panel's first card row above the screen; keepOnScreen can't
			-- move it down over the big E's opens, so the odds stay off
			w.camY = 80
			float()
			C._test.tick()
			local s = C._test.state()
			T.falsy(s.Reach, "the odds off the screen")
			T.near(s.Refs.Gui.SizeOffset.Y, 0.5, 1e-6, "(not moved: the big E is under it)")
			C.open("Stone", 1) -- (E, the disc, Open 1 round the E)
			C.open("Stone", 10) -- (Open 10, a gamepad's A on a focused open)
			T.eq(#w.buys, 1, "nothing bought")
			local x = w.actions.TerraForgeEggOpen10("TerraForgeEggOpen10", Enum.UserInputState.Begin)
			T.eq(x, Enum.ContextActionResult.Pass, "X passes, as before")
			C.toggleAuto("Stone")
			T.eq(C._test.state().Auto, nil, "Auto doesn't start on odds off the screen")
			-- Auto running: it waits while the odds are off, the next egg once they are back
			w.camY = 700
			float()
			C._test.tick()
			T.truthy(C._test.state().Reach)
			C.toggleAuto("Stone")
			T.eq(C._test.state().Auto, "Stone", "on the screen: Auto starts")
			local before = #w.buys
			w.camY = 80
			float()
			C._test.tick()
			C._test.tick()
			T.eq(#w.buys, before, "Auto waits while the odds are off the screen")
			T.eq(C._test.state().Auto, "Stone", "(still on)")
			w.camY = 700
			float()
			C._test.tick()
			T.truthy(#w.buys > before, "back on the screen: the next egg")
			C.toggleAuto("Stone")
			T.eq(C._test.state().Auto, nil)
		end)
	end)

	T.test("EggPanelController: on touch the tutorial bubble and the boost corner step aside for the floating panel", function()
		withController(function(C, w)
			local Workspace = Loader.game:GetService("Workspace")
			w.camZ, w.camAt = 10, Vector3.zero
			rawset(Workspace, "CurrentCamera", fakeCamera(w))
			local function screenWith(corner: any?, bubble: any?): any
				return function()
					return {
						View = Vector2.new(667, 375),
						Safe = box(0, 58, 667, 375),
						TopInset = 58,
						Hud = { box(206, 4, 461, 55), box(0, 58, 190, 230) },
						Corner = corner,
						Bubble = bubble,
					}
				end
			end
			local bubble = box(467, 64, 658, 172) -- (TutorialView's touch bubble on 667 x 375)
			w.scale = 0.62 -- (a phone's HUD scale)
			patched({ { C, "screenInput", screenWith(nil, bubble) } }, function()
				w.touch = true
				w.at("Stone")
				local float = w.renders.TerraForgeEggPanelFloat
				T.truthy(float ~= nil, "touch: the panel floats (every frame)")
				float()
				T.eq(w.holds[#w.holds] and w.holds[#w.holds][1], "Bubble", "the bubble would hide the odds: it steps aside")
				T.eq(w.holds[#w.holds][2], true)
				w.leave()
				T.eq(w.holds[#w.holds][1], "Bubble")
				T.eq(w.holds[#w.holds][2], false, "the panel gone: the bubble comes back")
			end)
			-- a corner the panel can't keep clear of (a tall column of tiles over the free part): it steps aside
			table.clear(w.holds)
			patched({ { C, "screenInput", screenWith(box(380, 60, 655, 300), nil) } }, function()
				w.at("Stone")
				w.renders.TerraForgeEggPanelFloat()
				T.eq(w.holds[1] and w.holds[1][1], "Corner")
				T.eq(w.holds[1] and w.holds[1][2], true, "the corner held")
				w.leave()
				T.eq(w.holds[#w.holds][2], false, "and back")
			end)
			-- nothing in the way: nothing held
			table.clear(w.holds)
			patched({ { C, "screenInput", screenWith(nil, nil) } }, function()
				w.at("Stone")
				w.renders.TerraForgeEggPanelFloat()
				T.eq(#w.holds, 0, "nothing to hold")
				local r = C._test.state().Refs
				T.truthy(r.Gui.SizeOffset ~= Vector2.new(0, 0.5), "moved on the screen")
				w.leave()
			end)
			w.touch = false
		end)
	end)

	T.test("CapsuleController: the opening's Auto button and note, B stops Auto, a buy on odds the panel didn't show is refused", function()
		withController(function(C, w)
			local CC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
			local ok, err = pcall(function()
				-- (the real controller's hook: the fake's recorder stands in the module, the real one here)
				local toggled = 0
				local available = true
				local o = CC._test.opening()
				CC._test.setAutoHook({
					available = function(): boolean
						return available
					end,
					toggle = function()
						toggled += 1
					end,
				})
				CC._test.setPlaying(true)
				CC._test.setAuto(true)
				T.truthy(o.AutoHolder.Visible, "Auto runs: its button shows")
				T.eq(o.AutoLabel.Text, "AUTO ON")
				T.eq(o.Auto.BackgroundColor3, BrightTheme.Paints.Green.Bottom, "green while on")
				-- a gamepad's B while Auto runs stops Auto (never skip-all then); off, B skips all
				local B = { KeyCode = roblox.Enum.KeyCode.ButtonB }
				CC._test.onSkipAll("x", roblox.Enum.UserInputState.Begin, B)
				T.eq(toggled, 1, "B: Auto off")
				-- the odds changed under it: the note by the Auto button says why (the HUD's toasts hide)
				CC._test.setAuto(false, "Triple Lucky ended: Auto stopped")
				T.truthy(o.Note.Visible)
				T.eq(o.Note.Text, "Triple Lucky ended: Auto stopped")
				T.eq(o.AutoLabel.Text, "AUTO")
				CC._test.onSkipAll("x", roblox.Enum.UserInputState.Begin, B)
				T.eq(toggled, 1, "B with Auto off skips all: it never turns Auto on")
				-- nowhere to run Auto (no egg here): no button
				available = false
				CC._test.refreshAuto()
				T.falsy(o.AutoHolder.Visible, "no Auto here: no button")
				CC._test.setPlaying(false)
				CC._test.setAutoHook(nil)
				-- request(): the odds the panel showed (lucky) aren't the card's (normal): refused, nothing sent
				local sent, reason = CC._test.request("Stone", 1, nil, true)
				T.falsy(sent)
				T.eq(reason, "OddsChanged", "refused: the panel shows the new odds first")
				local _ = C
				local _w = w
			end)
			CC._test.close()
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.test("CapsuleController: a x50 pack is 5 openings of 10, every golem named once (calm, skip-all, phones, all waiting)", function()
		withController(function(_C, w)
			local CC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
			local HatchStage = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchStage")
			local HatchFx = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.HatchFx")
			local Motion = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.Motion")
			-- a x50 Dragonforge pack: `woke` woke, the rest rolled past the inventory's hard cap (Pending)
			local odds = CapsuleConfig.odds("Dragonforge", false)
			local function pack(woke: number): (any, { [string]: number })
				local golems, pending = {}, {}
				local want: { [string]: number } = {}
				for i = 1, 50 do
					local kind = odds[(i - 1) % #odds + 1].Golem
					if i <= woke then
						table.insert(golems, { Id = i, Kind = kind })
					else
						table.insert(pending, kind)
					end
					local name = GolemConfig.ById[kind].Name
					want[name] = (want[name] or 0) + 1
				end
				return { Capsule = "Dragonforge", Count = 50, Golems = golems, Pending = pending, Lucky = false }, want
			end
			-- junk: no golems, unknown pending kinds, more than a pack holds
			T.eq(#CC.batches({ Capsule = "Stone", Golems = {} }), 0)
			T.eq(#CC.batches("x"), 0)
			local junk = CC.batches({ Capsule = "Stone", Golems = { { Id = 1, Kind = "PebbleGolem" } }, Pending = { "NoSuchGolem", 5 } })
			T.eq(#junk, 1)
			T.eq(#junk[1].Golems, 1, "an unknown pending kind is dropped")
			local many = {}
			for i = 1, 70 do
				many[i] = { Id = i, Kind = "PebbleGolem" }
			end
			local total = 0
			for _, r in CC.batches({ Capsule = "Stone", Golems = many }) do
				total += #r.Golems
			end
			T.eq(total, CapsuleConfig.MaxCount, "never more than the biggest pack")
			--[[
				One opening as hatch() plays it, with hatch()'s own arguments (CC.hatchArgs): "whole" to its end,
				"skip" with skip-all at its start (hatch's rule: to the burst, the flight once the last name
				showed MinShow), "names" until every name shows. Each golem counted once, when its name is
				fully on; its waiting note checked then.
			]]
			local function play(o: any, result: any, mode: string, inspect: ((any) -> ())?): ({ [string]: number }, number)
				local kinds = {}
				for _, g in result.Golems do
					table.insert(kinds, g.Kind)
				end
				local args = CC.hatchArgs(o, result, kinds)
				T.eq(args.Fast, (result.Batch or 1) > 1, "the later openings of a pack in the fast timings")
				T.eq(args.Reduced, Motion.reduced(), "Reduce motion's calm opening when it is on")
				local run = HatchStage.new(args)
				local tl = run.Timeline
				T.truthy(tl.Fly - tl.Reveal >= HatchFx.namedAt(tl) + HatchFx.MinShow, "MinShow after the last name")
				local named: { [string]: number } = {}
				local seen: { [number]: boolean } = {}
				local notes = 0
				local function look()
					for slot = 1, #kinds do
						local tag = o.Tags[slot]
						if not seen[slot] and tag.Frame.Visible and tag.Name.TextTransparency == 0 then
							seen[slot] = true
							named[tag.Name.Text] = (named[tag.Name.Text] or 0) + 1
							T.eq(tag.Waiting.Visible, run.Waiting[slot], "the waiting note only on a waiting golem")
							if tag.Waiting.Visible then
								notes += 1
								local words = tag.WaitingText.Text
								T.truthy(
									words == CapsuleView.WaitingText
										or words == CapsuleView.WaitingShort
										or words == CapsuleView.WaitingLines,
									"the note's words: the whole note, the short one where it doesn't fit, that on two lines beside AUTO"
								)
								T.eq(tag.Waiting.BackgroundTransparency, 0, "solid with its name")
								-- (never under the Auto button, its key or its label: the bottom-left golem's note)
								local x = tag.Frame.Position.X.Offset + tag.Waiting.Position.X.Offset
								local y = tag.Frame.Position.Y.Offset + tag.Waiting.Position.Y.Offset
								local half = tag.Waiting.Size.X.Offset / 2
								local note = { Min = Vector2.new(x - half, y), Max = Vector2.new(x + half, y + tag.Waiting.Size.Y.Offset) }
								for _, keep in o.AutoKeep do
									T.eq(
										EggPanel.overlap(note, keep),
										0,
										`slot {slot}: its note clear of the Auto button ({note.Min} {note.Max} vs {keep.Min} {keep.Max}, {o.Size}, Auto {o.AutoHolder.Visible})`
									)
								end
							end
						end
					end
				end
				local real, offset = 0, 0
				local revealedAt: number? = nil
				local wantFly = false
				if mode == "skip" then
					local t1 = HatchFx.skipTo(0, tl, 0)
					offset += if t1 then t1 else 0
					wantFly = true
				end
				while true do
					local shown = if revealedAt then real - revealedAt else 0
					if wantFly then
						local tt = real + offset
						local jump = if tt >= tl.Burst then HatchFx.skipTo(tt, tl, shown) else nil
						if jump then
							offset += jump - tt
							wantFly = false
						end
					end
					local t = math.min(real + offset, tl.Total)
					local events = HatchStage.pose(run, t)
					if table.find(events, "Reveal") then
						revealedAt = real
					end
					look()
					local done = 0
					for _ in seen do
						done += 1
					end
					if t >= tl.Total or (mode == "names" and done == #kinds) then
						break
					end
					real += 1 / 30
				end
				T.eq(
					#kinds,
					(function(): number
						local n = 0
						for _ in seen do
							n += 1
						end
						return n
					end)(),
					"every golem of the opening named"
				)
				if inspect then
					inspect(run)
				end
				HatchStage.pose(run, tl.Total)
				HatchStage.clear(o, HatchStage.golems(run))
				return named, notes
			end
			local payload, want = pack(40)
			local openings = CC.batches(payload)
			T.eq(#openings, 5, "a x50: five openings")
			local ids = {}
			for b, result in openings do
				T.eq(result.Batch, b)
				T.eq(result.Batches, 5)
				T.eq(#result.Golems, 10, `opening {b}: ten golems`)
				for _, g in result.Golems do
					if g.Id > 0 then
						T.falsy(ids[g.Id], `golem {g.Id} in one opening only`)
						ids[g.Id] = true
					end
				end
			end
			local o = CapsuleView.buildOpening(false)
			CapsuleView.layoutOpening(o, false, 1280, 720, {})
			for _, case in { { "whole", false }, { "whole", true }, { "skip", false } } do
				local mode, calm = case[1], case[2]
				patched({ {
					Motion,
					"reduced",
					function(): boolean
						return calm
					end,
				} }, function()
					local named: { [string]: number } = {}
					local notes = 0
					for _, result in openings do
						local got, n = play(o, result, mode)
						for name, k in got do
							named[name] = (named[name] or 0) + k
						end
						notes += n
					end
					local label = `{mode}{if calm then " (Reduce motion)" else ""}`
					for name, n in want do
						T.eq(named[name], n, `{label}: {name} named once for each of its golems`)
					end
					for name in named do
						T.truthy(want[name] ~= nil, name .. ": a golem of the pack")
					end
					T.eq(notes, 10, label .. ": the ten past the cap shown won, each with its note")
				end)
			end
			-- the pack's whole pack past the cap (the inventory at its hard cap): 5 openings, all waiting
			local all = CC.batches((pack(0)))
			T.eq(#all, 5, "no golem woke: still five openings")
			local waiting = 0
			for _, result in all do
				local _named, n = play(o, result, "names")
				waiting += n
			end
			T.eq(waiting, 50, "all 50 shown, each waiting")
			-- PC and phones (the HUD's 0.62): the note at the text floor, on two lines where the room is
			-- narrow; no two notes touch, none under the Auto button (the bottom-left golem's steps aside)
			for _, case in
				{
					{ Vector2.new(1280, 720), 1, false, 29, 0 },
					{ Vector2.new(844, 390), 0.62, true, 58, 21 }, -- (a notched iPhone: its home indicator, 21 pt)
					{ Vector2.new(568, 320), 0.62, true, 58, 0 },
				}
			do
				local view, scale, phone, inset, safe = case[1], case[2], case[3], case[4], case[5]
				w.touch = phone
				local p = CapsuleView.buildOpening(phone)
				local opts = { Touch = phone, Inset = inset / scale, SafeBottom = safe / scale }
				CapsuleView.layoutOpening(p, phone, view.X / scale, view.Y / scale, opts)
				local last = all[5]
				-- (an all-waiting opening: the rows part, so no top-row note covers a second-row golem's head)
				play(p, last, "names", function(run: any)
					T.truthy(run.Marked, `{view.X}: the top row carries notes`)
					T.eq(p.Gui:GetAttribute("MarksOverrun"), nil, `{view.X}: the marks fit above the safe bottom`)
					local size = run.Size
					local aspect = size.X / size.Y
					local heads = {}
					for slot, standing in run.Standing do
						if slot > 5 then
							local top = HatchFx.project(
								HatchFx.at(standing.Spot.X, standing.Spot.Y, standing.Depth, aspect)
									+ Vector3.new(0, standing.Height / 2, 0),
								aspect
							)
							local feet = HatchFx.project(
								HatchFx.at(standing.Spot.X, standing.Spot.Y, standing.Depth, aspect)
									- Vector3.new(0, standing.Height / 2, 0),
								aspect
							)
							local h = (feet.Y - top.Y) * size.Y
							table.insert(heads, {
								Min = Vector2.new(top.X * size.X - h * 0.35, top.Y * size.Y),
								Max = Vector2.new(top.X * size.X + h * 0.35, feet.Y * size.Y),
							})
						end
					end
					for slot = 6, #last.Golems do
						local tag = p.Tags[slot]
						local bottom = tag.Frame.Position.Y.Offset + tag.Waiting.Position.Y.Offset + tag.Waiting.Size.Y.Offset
						T.truthy(
							bottom <= size.Y - p.SafeBottom,
							`{view.X}: the second row's note {slot} above the safe bottom ({bottom} of {size.Y - p.SafeBottom})`
						)
						T.eq(tag.Waiting.Size.Y.Offset, CapsuleView.TagMin + 12, `{view.X}: one line`)
					end
					for slot = 1, 5 do
						local tag = p.Tags[slot]
						local x = tag.Frame.Position.X.Offset + tag.Waiting.Position.X.Offset
						local y = tag.Frame.Position.Y.Offset + tag.Waiting.Position.Y.Offset
						local half = tag.Waiting.Size.X.Offset / 2
						local note = { Min = Vector2.new(x - half, y), Max = Vector2.new(x + half, y + tag.Waiting.Size.Y.Offset) }
						for _, head in heads do
							T.eq(EggPanel.overlap(note, head), 0, `{view.X}: top-row note {slot} clear of the second row's golems`)
						end
					end
				end)
				local notes = {}
				for slot = 1, #last.Golems do
					local tag = p.Tags[slot]
					T.truthy(tag.Waiting.Visible, `{view.X}: the note`)
					T.truthy(tag.WaitingText.TextSize * scale >= 9.9, `{view.X}: the note {tag.WaitingText.TextSize * scale} pt`)
					local x = tag.Frame.Position.X.Offset + tag.Waiting.Position.X.Offset
					local y = tag.Frame.Position.Y.Offset + tag.Waiting.Position.Y.Offset
					local half = tag.Waiting.Size.X.Offset / 2
					local note = { Min = Vector2.new(x - half, y), Max = Vector2.new(x + half, y + tag.Waiting.Size.Y.Offset) }
					table.insert(notes, note)
					for _, keep in p.AutoKeep do
						T.eq(EggPanel.overlap(note, keep), 0, `{view.X} slot {slot}: clear of the Auto button`)
					end
				end
				for i = 1, #notes do
					for j = i + 1, #notes do
						T.eq(EggPanel.overlap(notes[i], notes[j]), 0, `{view.X}: notes {i} and {j} never touch`)
					end
				end
				p.Gui:Destroy()
				p.Controls:Destroy()
			end
			w.touch = false
			-- the counter: "2 / 5" while a pack's openings play, none for one opening
			CapsuleView.setChain(o, 2, 5)
			T.truthy(o.Chain.Visible)
			T.eq(o.Chain.Text, "2 / 5")
			CapsuleView.setChain(o, 1, 1)
			T.falsy(o.Chain.Visible)
		end)
	end)

	T.test("CapsuleController: a chain of openings is one HUD hold; a result that comes meanwhile waits after it", function()
		withController(function(_C, w)
			local CC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
			local played = {}
			local plays: { boolean } = {}
			local listening = true
			local ok, err = pcall(function()
				-- (stand-ins for the controllers whose keys an opening sinks: Lune can't load them)
				local K = roblox.Enum.KeyCode
				CC._test.setOwners({
					BackpackController = { Key = K.Q },
					EmoteController = { Key = K.N },
					GolemController = { ToggleKey = K.P },
					HoverboardController = { Key = K.H },
					ArtifactController = { BookKey = K.J },
					BoostController = { OpenKeys = { K.L, K.DPadRight } },
				})
				CC._test.onPlaying(function(on: boolean)
					if listening then
						table.insert(plays, on)
					end
				end)
				local pack = {}
				for i = 1, 50 do
					pack[i] = { Id = i, Kind = "PebbleGolem" }
				end
				local later = { Capsule = "Crystal", Count = 1, Golems = { { Id = 99, Kind = "QuartzSprite" } }, Lucky = false }
				-- (a recorder for the opening itself: the chain around it is the real one)
				CC._test.setHatch(function(o: any, result: any, kinds: { string })
					local idsOf = {}
					for _, g in result.Golems do
						table.insert(idsOf, g.Id)
					end
					table.insert(played, {
						Capsule = result.Capsule,
						Batch = result.Batch,
						Batches = result.Batches,
						Ids = idsOf,
						Kinds = #kinds,
						Hidden = CC._test.hudHidden(),
						Playing = CC._test.playing(),
						Sink = w.actions.TerraForgeCapsuleSink ~= nil,
						Skip = w.actions.TerraForgeCapsuleSkip ~= nil,
						Watch = CC._test.selectionWatched(),
						Chain = if o.Chain.Visible then o.Chain.Text else "",
					})
					local step, all = CC._test.skips()
					played[#played].Skipped = step or all
					if #played == 1 then
						-- (skip-all pressed twice in the first opening: it finishes that opening only)
						local backspace = { KeyCode = roblox.Enum.KeyCode.Backspace }
						CC._test.onSkipAll("x", roblox.Enum.UserInputState.Begin, backspace)
						CC._test.onSkipAll("x", roblox.Enum.UserInputState.Begin, backspace)
					end
					if #played == 2 then
						CC._test.result(later) -- (a new receipt arrives while the pack's second opening plays)
					end
				end)
				CC._test.result({ Capsule = "Stone", Count = 50, Golems = pack, Lucky = false })
				-- (the recorder never yields: the whole chain ran)
				T.eq(#played, 6, "the pack's five openings, then the one that came meanwhile")
				for i = 1, 5 do
					local p = played[i]
					T.eq(p.Capsule, "Stone")
					T.eq(p.Batch, i)
					T.eq(p.Batches, 5)
					T.eq(p.Kinds, 10)
					T.eq(p.Ids[1], (i - 1) * 10 + 1, `opening {i}: its golems in order`)
					T.eq(p.Ids[10], i * 10)
					T.eq(p.Chain, `{i} / 5`, "the counter")
				end
				for i, p in played do
					T.falsy(p.Skipped, `opening {i} starts unskipped: a skip (or two) finished the one it was pressed in only`)
				end
				T.eq(played[6].Capsule, "Crystal", "the new result: after the WHOLE chain, never between its openings")
				T.eq(played[6].Chain, "", "one opening: no counter")
				for i, p in played do
					T.truthy(p.Hidden, `opening {i}: the HUD away`)
					T.truthy(p.Playing, `opening {i}: playing (the egg panel and its keys rest)`)
					T.truthy(p.Sink and p.Skip, `opening {i}: the keys held`)
					T.truthy(p.Watch, `opening {i}: the selection lock watching (nothing gets selected under it)`)
				end
				T.eq(#plays, 2, "the chain told once that it began and once that it ended")
				T.eq(plays[1], true)
				T.eq(plays[2], false)
				T.falsy(CC._test.hudHidden(), "the HUD back once, after the last opening")
				T.falsy(CC._test.playing())
				-- right after it the shop's OPEN buttons rest a moment (a gamepad's A pressed to skip it)
				local view = CC._test.view()
				local sent, why = CC._test.request("Stone", 1, Instance.new("TextButton"))
				T.falsy(sent, "no egg bought by the A meant as a skip")
				T.eq(why, "Busy")
				T.eq(view.Status.Text, "One moment...", "a real click says why")
				CC._test.ended(nil)
				T.eq(w.actions.TerraForgeCapsuleSink, nil, "the keys free again")
				-- the window keys it sank: a gamepad's and their keyboard twins (none acts unseen under it);
				-- the keys other controllers own are read from their exports (stand-ins here)
				local sunk = CC.sinkKeys()
				for _, key in { K.ButtonL3, K.ButtonR3, K.T, K.B, K.Q, K.N, K.P, K.H, K.J, K.L, K.DPadRight } do
					T.truthy(table.find(sunk, key), key.Name .. " sunk while an egg opens")
				end
				for _, key in { K.Space, K.Return, K.Backspace, K.G, K.ButtonA, K.ButtonB } do
					T.falsy(table.find(sunk, key), key.Name .. ": the opening's own key")
				end
				T.falsy(CC._test.selectionWatched(), "the selection lock let go")
				T.eq(CC._test.queued(), 0)
				-- an opening that fails still lets the chain go on and end
				table.clear(played)
				table.clear(plays)
				CC._test.setHatch(function(_o: any, result: any)
					table.insert(played, result.Batch)
					if result.Batch == 1 then
						error("a broken opening")
					end
				end)
				CC._test.result({ Capsule = "Stone", Count = 20, Golems = table.move(pack, 1, 20, 1, {}), Lucky = false })
				T.eq(#played, 2, "the second opening plays after a failed first")
				T.eq(#plays, 2, "one begin, one end")
				T.falsy(CC._test.hudHidden())
				-- the notes by the Auto button: why Auto stopped shows once (not again on every opening of a
				-- chain), and a receipt's own notice waits for its result's opening (never on the one playing)
				local receipt = { Capsule = "Royal", Count = 1, Golems = { { Id = 77, Kind = "EmberImp" } }, Lucky = false }
				local notes = {}
				CC._test.setAuto(false, "Triple Lucky ended: Auto stopped")
				CC._test.setHatch(function(o: any, result: any)
					table.insert(notes, { Capsule = result.Capsule, Batch = result.Batch, Text = o.Note.Text, Shown = o.Note.Visible })
					o.Note.Visible = false -- (its time is up before the next opening)
					o.Note.Text = ""
					if #notes == 1 then
						CC._test.result(receipt) -- (a Robux receipt during the pack's first opening)
						CC.notice({ Text = "Your golem inventory is full", Kind = "Info" })
						T.eq(o.Note.Text, "", "its notice doesn't land on the opening playing")
					end
				end)
				CC._test.result({ Capsule = "Stone", Count = 20, Golems = table.move(pack, 1, 20, 1, {}), Lucky = false })
				T.eq(#notes, 3, "the pack's two openings, then the receipt's")
				T.truthy(notes[1].Shown and notes[1].Text == "Triple Lucky ended: Auto stopped", "Auto's note on the first opening")
				T.falsy(notes[2].Shown, "not again on the second")
				T.eq(notes[3].Capsule, "Royal")
				T.truthy(notes[3].Shown and notes[3].Text == "Your golem inventory is full", "the receipt's notice with its own opening")
				-- Auto stopped DURING an opening: its note shows then, and not again on the next one
				table.clear(notes)
				CC._test.setHatch(function(o: any, result: any)
					table.insert(notes, { Batch = result.Batch, Text = o.Note.Text, Shown = o.Note.Visible })
					if #notes == 1 then
						CC._test.setAuto(false, "Auto stopped: not enough coins")
						T.eq(o.Note.Text, "Auto stopped: not enough coins", "shown at once")
					end
					o.Note.Visible = false
					o.Note.Text = ""
				end)
				CC._test.result({ Capsule = "Stone", Count = 20, Golems = table.move(pack, 1, 20, 1, {}), Lucky = false })
				T.eq(#notes, 2)
				T.falsy(notes[2].Shown, "the next opening doesn't show it again")
				-- another player's notice right after a queued result shows at once (only a receipt's joins it)
				table.clear(notes)
				CC._test.setHatch(function(o: any, result: any)
					table.insert(notes, { Capsule = result.Capsule, Text = o.Note.Text })
					if #notes == 1 then
						CC._test.result(receipt)
						CC.notice({ Text = "Someone woke a Legendary!", Kind = "Discovery" })
						T.eq(o.Note.Text, "Someone woke a Legendary!", "on the opening playing")
					end
					o.Note.Text = ""
				end)
				CC._test.result({ Capsule = "Stone", Count = 1, Golems = { pack[1] }, Lucky = false })
				T.eq(#notes, 2)
				T.eq(notes[2].Text, "", "not carried to the receipt's opening")
			end)
			listening = false
			CC._test.setHatch(nil)
			CC._test.setOwners(nil)
			CC._test.close()
			CC._test.hideHud(false) -- (a failure mid-chain must not leave the HUD away for the next specs)
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.test("InteractController: held by an opening, its pickup target, highlight and hint go and stay off", function()
		withController(function(_C, _w)
			local IC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.InteractController")
			local _name, action, restore = IC._test.parts() -- (the highlight and the "[F] Pick up" hint)
			local item = Instance.new("Model") -- (a dirty chunk on the ground: its hint "[F] Pick up")
			item:SetAttribute("Kind", "Raw")
			item:SetAttribute("OreId", "Coal")
			item:SetAttribute("Value", 5)
			local ok, err = pcall(function()
				IC._test.show(item)
				local target, adornee, shown = IC._test.view()
				T.truthy(target == item and adornee == item and shown, "an item targeted: highlighted, its hint up")
				IC.hold("CapsuleOpening", true)
				target, adornee, shown = IC._test.view()
				T.eq(target, nil, "held: no pickup target")
				T.eq(adornee, nil, "no highlight")
				T.falsy(shown, "no hint")
				-- (an item right there to pick: the loop's next look would take it, if it looked)
				local looked = 0
				IC._test.setChooser(function(_root: any): any
					looked += 1
					return item
				end)
				IC._test.step()
				target, adornee, shown = IC._test.view()
				T.truthy(target == nil and adornee == nil and not shown, "still off after the loop's next look")
				T.eq(looked, 0, "held: it doesn't even look")
				IC.hold("CapsuleOpening", false)
				-- (its hint names the key: a keyboard's F)
				local UIS = Loader.game:GetService("UserInputService")
				patched({ { UIS, "GamepadEnabled", false }, { UIS, "KeyboardEnabled", true } }, function()
					IC._test.step()
				end)
				T.eq(looked, 1, "let go: it looks again")
				target, adornee, shown = IC._test.view()
				T.truthy(target == item and adornee == item and shown, "and the item is its target again, highlighted, its hint up")
				T.truthy(string.find(action.Text, "[F] Pick up", 1, true) == 1, `its hint names F: {action.Text}`)
			end)
			-- (also when an assertion threw: the real chooser and parts back, no hold left)
			IC._test.setChooser(nil)
			IC.hold("CapsuleOpening", false)
			restore()
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.test("CapsuleController: the HUD steps away while an egg opens (scale 0), what changed meanwhile is kept, back after", function()
		withController(function(_C, w)
			local CC = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
			local ok, err = pcall(function()
				local playerGui = me.PlayerGui
				local function screen(name: string, scale: number?): (any, any)
					local gui = Instance.new("ScreenGui")
					gui.Name = name
					local s = Instance.new("UIScale")
					s.Name = "Scale"
					s.Scale = scale or 1.25
					s.Parent = gui
					gui.Parent = playerGui
					return gui, s
				end
				local hud, hudScale = screen("TerraForgeHud")
				local shop, shopScale = screen("TerraForgeCapsules")
				local quest, questScale = screen("QuestPop") -- (a gui that isn't the game's own: never hidden)
				local fade = Instance.new("ScreenGui") -- (a fade without the HUD's scale finishes as it is)
				fade.Name = "TerraForgeTeleportFade"
				fade.Parent = playerGui
				hud.Enabled = true
				shop.Enabled = false
				CC._test.hideHud(true)
				T.eq(hudScale.Scale, 0, "the HUD hides")
				T.eq(shopScale.Scale, 0, "a window too")
				T.eq(questScale.Scale, 1.25, "a gui that isn't ours stays")
				T.truthy(hud.Enabled and not shop.Enabled, "no Enabled is touched (the windows keep their own state)")
				T.truthy(fade.Enabled, "the fade untouched")
				-- the HUD's scale changes meanwhile (a resize): the game's watcher hides it again at once
				-- (Lune's instances fire no property signals); the restore keeps the scale written
				hudScale.Scale = 0.9
				CC._test.hideHud(false)
				T.near(hudScale.Scale, 0.9, 1e-6, "back at the scale written meanwhile")
				T.eq(shopScale.Scale, 1.25, "back")
				for _, g in { hud, shop, quest, fade } do
					g:Destroy()
				end
				local _ = w
			end)
			if not ok then
				error(err, 0)
			end
		end)
	end)

	T.test("EggPanel V2: the world's tint: one at an Epic+ burst, none below or with Reduce motion, gone at the flight", function()
		local Color3 = roblox.Color3
		withController(function(_C, w)
			local CapsuleController = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers.CapsuleController")
			local seam = CapsuleController._test
			local camera = Instance.new("Camera")
			local function count(): number
				local n = 0
				for _, child in camera:GetChildren() do
					if child.Name == "TerraForgeOpeningMood" then
						n += 1
					end
				end
				return n
			end
			local function finishTweens()
				for _, made in w.tweens do
					made.Completed.fire()
				end
				table.clear(w.tweens)
			end
			seam.setMood(5, Color3.new(1, 0.7, 0.1), false, camera)
			T.eq(count(), 1, "one tint at an Epic+ burst")
			seam.setMood(6, Color3.new(1, 0.2, 0.5), false, camera)
			T.eq(count(), 1, "never two (two Epic+ openings)")
			seam.setMood(0, Color3.new(1, 1, 1), false, camera)
			finishTweens()
			T.eq(count(), 0, "gone at the flight")
			T.eq(seam.mood(), nil)
			seam.setMood(5, Color3.new(1, 0.7, 0.1), true, camera)
			T.eq(count(), 0, "none with Reduce motion")
			seam.setMood(3, Color3.new(0, 0.5, 1), false, camera)
			T.eq(count(), 0, "none below Epic")
			-- (left on by a skipped flight: the chain's end and a failing opening take it away)
			seam.setMood(6, Color3.new(1, 0.2, 0.5), false, camera)
			seam.setMood(0, Color3.new(1, 1, 1), true)
			finishTweens()
			T.eq(count(), 0, "endChain's setMood(0, ..., true) clears it whatever was skipped")
		end)
		local source = fs.readFile(Loader.root .. "/src/client/Controllers/CapsuleController.luau")
		local flat = string.gsub(source, "%s+", " ")
		T.truthy(string.find(flat, "setBlur(false) setMood(0, Color3.new(1, 1, 1), true)", 1, true), "endChain clears it")
		T.truthy(
			string.find(flat, 'setMood(0, Color3.new(1, 1, 1), true) pcall(Sfx.loop, "CaseCharge", false)', 1, true),
			"a failing opening clears it and the hum"
		)
	end)
end
