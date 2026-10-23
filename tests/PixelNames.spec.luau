--!nocheck
--[[
	Long names in the pixel windows (review 2026-10-22): "HEARTSTONE COLOSSUS"
	shrank to 5 pt on phones. The golem cards and slots, the pen's grade chips
	and the book's tiles are laid out for PC and phones; every name must stay
	at least 10 design units on PC and 8 pt on a 568x320 phone (UI scale 0.62),
	fit its box on at most two lines (three for the book's longest names) and
	never be cut. Sentences a view makes round stay round (Pop.round).
]]
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local function ui(name: string)
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI." .. name)
	end
	local GolemView = ui("GolemView")
	local PenView = ui("PenView")
	local CollectionView = ui("CollectionView")
	local Pop = ui("Pop")
	local PopTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.PopTheme")
	local GolemConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.GolemConfig")
	local ArtifactConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.ArtifactConfig")

	-- the fonts as the views budget them: a pixel letter is 1 em wide (Press Start 2P), a
	-- round capital about 0.6 em; a line 1.1 em (pixel) or 1.2 em (round) tall
	local PIXEL = { Em = 1, Line = 1.1 }
	local ROUND = { Em = 0.6, Line = 1.2 }
	local PHONE = 0.62 -- HudController's UI scale on phones
	local PC_MIN = 10 -- design units at UI scale 1
	local PHONE_PT = 8 -- points on a phone

	local function letters(s: string): number
		return utf8.len(s) or #s
	end

	-- Lines `text` takes wrapped at `perLine` letters (math.huge: a word is longer than a line).
	local function wrapLines(text: string, perLine: number): number
		local lines, line = 1, 0
		for _, word in string.split(text, " ") do
			local n = letters(word)
			if n > perLine then
				return math.huge
			end
			local need = if line == 0 then n else line + 1 + n
			if need > perLine then
				lines += 1
				line = n
			else
				line = need
			end
		end
		return lines
	end

	--[[
		What Roblox draws a label at in a `w` x `h` box (TextScaled under the
		label's UITextSizeConstraint; else its TextSize): (size, lines, cut).
	]]
	local function shown(label: any, w: number, h: number): (number, number, boolean)
		local pad = label:FindFirstChildOfClass("UIPadding")
		if pad then
			w -= pad.PaddingLeft.Offset + pad.PaddingRight.Offset
			h -= pad.PaddingTop.Offset + pad.PaddingBottom.Offset
		end
		local font = if Pop.isPixel(label.FontFace) then PIXEL else ROUND
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
		local max = if label.TextScaled then (if limit then limit.MaxTextSize else 100) else label.TextSize
		local min = if label.TextScaled then (if limit then limit.MinTextSize else 1) else label.TextSize
		local text = label.Text
		for s = max, 1, -0.5 do
			local perLine = math.floor(w / (s * font.Em))
			local lines = if label.TextWrapped then wrapLines(text, perLine) else (if letters(text) <= perLine then 1 else math.huge)
			if lines * s * font.Line <= h + 0.01 then
				if s < min then
					return min, lines, true
				end
				return s, lines, false
			end
			if not label.TextScaled then
				return s, lines, true -- (a fixed size that doesn't fit)
			end
		end
		return min, math.huge, true
	end

	-- The label's box: its Size against a parent `parentW` wide.
	local function box(label: any, parentW: number): (number, number)
		return parentW * label.Size.X.Scale + label.Size.X.Offset, label.Size.Y.Offset
	end

	type Screen = { Name: string, Compact: boolean, Scale: number, W: number, H: number }

	-- Asserts the label's text is big enough and fits its box in at most `maxLines` lines.
	local function readable(label: any, parentW: number, screen: Screen, maxLines: number, what: string, floorPt: number?)
		local w, h = box(label, parentW)
		local size, lines, cut = shown(label, w, h)
		local where = `{screen.Name} {what} "{label.Text}" ({w}x{h}: {size} at {lines} lines)`
		T.falsy(cut, where .. ": fits, never cut")
		T.le(lines, maxLines, where .. ": lines")
		if screen.Scale < 1 then
			T.truthy(size * screen.Scale >= (floorPt or PHONE_PT) - 0.01, where .. `: at least {floorPt or PHONE_PT} pt`)
		else
			T.truthy(size >= PC_MIN, where .. `: at least {PC_MIN} units`)
		end
	end

	-- PC (scale 1) and phones (scale 0.62, the top bar 58 pt)
	local SCREENS: { Screen } = {
		{ Name = "1280x720", Compact = false, Scale = 1, W = 1280, H = 684 },
		{ Name = "1920x1080", Compact = false, Scale = 1, W = 1920, H = 1044 },
		{ Name = "667x375", Compact = true, Scale = PHONE, W = 667 / PHONE, H = (375 - 58) / PHONE },
		{ Name = "568x320", Compact = true, Scale = PHONE, W = 568 / PHONE, H = (320 - 58) / PHONE },
	}

	-- the longest golem names first (19, 19, 18 letters), then shorter two-word ones
	local GOLEMS =
		{ "HeartstoneColossus", "CelestialSovereign", "ScaleKnight", "MoonstoneOracle", "GildedPorter", "PebbleGolem", "EmberImp" }

	local function golemState(equipped: { number }, bond: number?): any
		local s: any = {
			Coins = 0,
			Golems = { Owned = {}, Equipped = equipped, NextId = 1 },
			Bonuses = { GolemBond = bond or 0 },
		}
		for _, id in GOLEMS do
			GolemConfig.add(s.Golems, id)
		end
		return s
	end

	local function checkGolems(refs: any, screen: Screen)
		local cellW = refs.GridLayout.CellSize.X.Offset
		local cellH = refs.GridLayout.CellSize.Y.Offset
		for _, c in refs.Cards do
			readable(c.Name, cellW, screen, 2, "card")
			-- the name above the picture, the picture above the bonus line
			local nameBottom = c.Name.Position.Y.Offset + c.Name.Size.Y.Offset
			T.le(nameBottom, c.Portrait.Position.Y.Offset + 1, `{screen.Name} "{c.Name.Text}": the name above the picture`)
			local bonusTop = cellH + c.Bonus.Position.Y.Offset - c.Bonus.Size.Y.Offset
			T.le(
				c.Portrait.Position.Y.Offset + c.Portrait.Size.Y.Offset,
				bonusTop + 1,
				`{screen.Name} "{c.Name.Text}": the picture above the bonus`
			)
			T.truthy(c.Portrait.Size.Y.Offset >= 70, `{screen.Name} "{c.Name.Text}": the picture keeps its room`)
		end
		for _, slot in refs.Slots do
			local frameW, frameH = slot.Frame.Size.X.Offset, slot.Frame.Size.Y.Offset
			readable(slot.Name, frameW, screen, 2, "slot")
			if slot.Bonus.Text ~= "" then
				readable(slot.Bonus, frameW, screen, 1, "slot bonus")
			end
			local nameBottom = slot.Name.Position.Y.Offset + slot.Name.Size.Y.Offset
			T.le(nameBottom, slot.Bonus.Position.Y.Offset, `{screen.Name} slot "{slot.Name.Text}": the bonus under the name`)
			local bonusBottom = slot.Bonus.Position.Y.Offset + slot.Bonus.Size.Y.Offset
			T.le(bonusBottom, frameH - Pop.lipUnits(frameH), `{screen.Name} slot "{slot.Name.Text}": above the lip`)
			T.le(slot.Name.Position.X.Offset + box(slot.Name, frameW), frameW, `{screen.Name} slot: inside`)
		end
		readable(refs.DetailName, refs.Detail.Size.X.Offset, screen, 1, "detail")
	end

	T.test("PixelNames: golem card and slot names stay readable on PC and phones", function()
		for _, screen in SCREENS do
			local refs = GolemView.build(screen.Compact)
			GolemView.layout(refs, screen.Compact, screen.W, screen.H)
			local s = golemState({ 1, 2, 5 })
			local cards = GolemView.cards(s)
			GolemView.setCards(refs, cards, cards[1].Id, nil)
			GolemView.setEquipped(refs, GolemView.equipped(s), GolemView.totals(s))
			GolemView.setDetail(refs, cards[1])
			checkGolems(refs, screen)
			-- the 19-letter names take two lines (a single line would be ~6 units)
			for _, c in refs.Cards do
				if letters(c.Name.Text) >= 18 then
					T.eq(c.Name:GetAttribute("NameLines"), 2, `{screen.Name} "{c.Name.Text}": two lines`)
				end
			end
			-- the other equipped golems in the slots; an empty slot is one line
			local s2 = golemState({ 3, 4 })
			GolemView.setEquipped(refs, GolemView.equipped(s2), GolemView.totals(s2))
			checkGolems(refs, screen)
			-- Golem Bond: 13-letter bonus lines ("+13.8% MINING") in the slots and on the cards
			for _, bond in { 0.25, 0.5 } do
				local s3 = golemState({ 1, 4, 5 }, bond)
				local bonded = GolemView.cards(s3)
				GolemView.setCards(refs, bonded, bonded[1].Id, nil)
				GolemView.setEquipped(refs, GolemView.equipped(s3), GolemView.totals(s3))
				checkGolems(refs, screen)
				for _, c in refs.Cards do
					readable(c.Bonus, refs.GridLayout.CellSize.X.Offset, screen, 1, "card bonus")
				end
			end
			GolemView.setEquipped(refs, GolemView.equipped(s2), GolemView.totals(s2))
			T.eq(refs.Slots[3].Name.Text, "EMPTY")
			T.eq(refs.Slots[3].Name:GetAttribute("NameLines"), 1)
		end
		-- a phone turned / resized with the cards built: the names follow the new cells
		local refs = GolemView.build(true)
		GolemView.layout(refs, true, SCREENS[3].W, SCREENS[3].H)
		local s = golemState({ 1 })
		GolemView.setCards(refs, GolemView.cards(s), nil, nil)
		GolemView.setEquipped(refs, GolemView.equipped(s), GolemView.totals(s))
		GolemView.layout(refs, true, SCREENS[4].W, SCREENS[4].H)
		checkGolems(refs, SCREENS[4])
	end)

	T.test("PixelNames: GolemView.nameFit picks one line or two", function()
		T.eq(select(2, GolemView.nameFit("EMBER IMP", 16, 150, 13)), 1, "short: one line")
		local size, lines = GolemView.nameFit("HEARTSTONE COLOSSUS", 16, 150, 13)
		T.eq(lines, 2)
		T.eq(size, 15, "HEARTSTONE (10 letters) in 150")
		T.eq(select(2, GolemView.nameFit("SUPERCALIFRAGILISTIC", 16, 150, 13)), 1, "no space: one line")
		T.le(GolemView.nameFit("AB CD", 40, 400, 10), 40, "never past max")
		T.le(GolemView.nameFit("PEBBLE GOLEM", 40, 120, 10), 10 + GolemView.NameTwo, "two lines stay modest")
	end)

	T.test("PixelNames: the pen's grade chips and names stay readable", function()
		local summary = {
			["Clean|Gold|Pristine|"] = 3,
			["Clean|Copper|Flawless|"] = 2,
			["Clean|Copper|Rough|"] = 2,
			["Raw|Copper||"] = 1,
		}
		-- (income multipliers for the longest amounts: "+$1.23K/s", "+$12.3Qa/s")
		for _, case in
			{
				{ SCREENS[1], 1 },
				{ SCREENS[2], 1 },
				{ SCREENS[3], 1 },
				{ SCREENS[4], 1 },
				{ SCREENS[4], 41 },
				{ SCREENS[4], 4.1e16 },
				{ SCREENS[1], 4.1e16 },
			}
		do
			local screen, mult = case[1], case[2]
			local refs = PenView.build()
			PenView.setCompact(refs, screen.Compact, roblox.Vector2.new(screen.W, screen.H))
			PenView.setEntries(refs, PenView.entries(summary, "Pen", mult), true)
			local graded = 0
			for _, row in refs.Rows do
				local rowW = row.Frame.Size.X.Offset
				readable(row.Name, rowW, screen, 1, "pen name")
				if row.Grade.Visible then
					graded += 1
					readable(row.Grade, rowW, screen, 1, "grade")
					local gradeRight = row.Grade.Position.X.Offset + row.Grade.Size.X.Offset
					T.le(gradeRight, row.Income.Position.X.Offset, `{screen.Name} {row.Grade.Text}: the income right of the chip`)
				end
				if string.sub(row.Income.Text, 1, 1) == "+" then -- (an amount; the mystery line is a round sentence)
					readable(row.Income, rowW, screen, 1, "income")
				end
				local textEnd = row.Name.Position.X.Offset + row.Name.Size.X.Offset
				T.le(row.Income.Position.X.Offset + row.Income.Size.X.Offset, textEnd, `{screen.Name}: the income inside the text column`)
			end
			T.eq(graded, 3, "three graded rows")
		end
	end)

	T.test("PixelNames: the book's tile names and rarity chips stay readable", function()
		local found = {}
		for _, art in ArtifactConfig.List do
			found[art.Id] = 1
		end
		local record = { Found = found, Chapters = {} }
		for _, screen in SCREENS do
			local book = CollectionView.build(screen.Compact)
			CollectionView.layout(book, screen.W, screen.H)
			local cellW = book.Grid:FindFirstChildOfClass("UIGridLayout").CellSize.X.Offset
			for _, collection in ArtifactConfig.Collections do
				book.Collection = collection.Id
				CollectionView.fill(book, record)
				for _, t in book.Tiles do
					if t.Button.Visible then
						-- (every name at the floor: two lines, three for the two longest names
						-- (23 and 27 letters) or in a box made taller for three lines on the
						-- smallest phones, CollectionView.nameHeight)
						local nameH = t.Name.Size.Y.Offset
						local tall = nameH > (if screen.Compact then 18 else 16) * 2 + 4
						local long = letters(t.Name.Text) > 19
						readable(t.Name, cellW, screen, if long or tall then 3 else 2, "tile")
						T.le(6 + nameH, t.Icon.Position.Y.Offset, `{screen.Name} "{t.Name.Text}": the name above the picture`)
						T.truthy(t.Icon.Size.X.Offset >= 40, `{screen.Name}: the picture keeps its room`)
						if t.Chip.Visible then
							readable(t.Chip, cellW, screen, 1, "tile chip")
						end
					end
				end
			end
		end
	end)

	T.test("PixelNames: sentences made round stay round when a short text comes", function()
		local refs = GolemView.build(false)
		for _, label in { refs.Status, refs.Hint, refs.Totals } do
			T.eq(label:GetAttribute("Round"), true, label.Name .. ": round for good")
			label.Text = "Saved"
			Pop.sentence(label, 15) -- (what the label's Text watcher does in the game)
			T.falsy(Pop.isPixel(label.FontFace), label.Name .. ": still round")
			T.eq(label.TextTruncate, roblox.Enum.TextTruncate.AtEnd, label.Name .. ": still cut, never spilled")
		end
		-- a pen row: the mystery sentence is round, an amount pixel again
		local pen = PenView.build()
		PenView.setEntries(pen, PenView.entries({ ["Raw|Copper||"] = 1 }, "Pen"), true)
		local _, row = next(pen.Rows)
		if row.Income.Text ~= "" then
			T.eq(row.Income:GetAttribute("Round"), true, "the mystery line is round")
			T.falsy(Pop.isPixel(row.Income.FontFace))
		end
		PenView.setEntries(pen, PenView.entries({ ["Clean|Gold|Pristine|"] = 1 }, "Pen"), true)
		local _, gold = next(pen.Rows)
		T.truthy(Pop.isPixel(gold.Income.FontFace), "an amount is a pixel word")
		T.eq(gold.Income:GetAttribute("Round"), nil)
		-- the book's hint
		local book = CollectionView.build(false)
		T.eq(book.Hint:GetAttribute("Round"), true, "the book's hint")
		book.Hint.Text = "Tap a tile"
		Pop.sentence(book.Hint, 16)
		T.eq(book.Hint.FontFace, PopTheme.Font, "the book's hint stays round")
	end)
end
