-- The progress sign over your own machines (client UI builder) on a real
-- machine model: where it hangs, and what update() shows.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
	local fs = require("@lune/fs") :: any
	local Color3 = roblox.Color3
	local MachineBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.MachineBuilder")
	local Theme = Loader.requirePath("ReplicatedStorage.Shared.Config.UITheme")
	local MachineBillboard = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.MachineBillboard")

	local function visiblePips(refs: any): (number, number)
		local filled = 0
		for _, pip in refs.Pips do
			if pip.BackgroundColor3 == Theme.Accent then
				filled += 1
			end
		end
		return #refs.Pips, filled
	end

	T.test("MachineBillboard: hangs on the Status attachment, hidden beyond 45 studs", function()
		for _, id in { "ClayFurnace", "BlastFurnace", "Crusher", "AutoCleaner", "Anvil" } do
			local model = MachineBuilder.build(id)
			local refs = MachineBillboard.attach(model)
			local status = model.PrimaryPart:FindFirstChild("Status")
			T.truthy(refs.Gui.Parent == status, id .. " parented to Status")
			T.truthy(refs.Gui.Adornee == status, id .. " adorned to Status")
			T.eq(refs.Gui.MaxDistance, 45, id .. " MaxDistance")
			T.eq(refs.Gui.AlwaysOnTop, false, id .. " not through walls")
			T.falsy(refs.Fill.Visible, id .. " empty bar")
			T.falsy(refs.Status.Visible, id .. " no status")
			MachineBillboard.detach(refs)
			T.eq(status:FindFirstChild("MachineBillboard"), nil, id .. " detached")
		end
	end)

	T.test("MachineBillboard: update shows progress, queue, FULL, ready items and status", function()
		local model = MachineBuilder.build("ClayFurnace")
		local refs = MachineBillboard.attach(model)
		local copper = Color3.fromRGB(222, 120, 60)
		MachineBillboard.update(refs, 0.5, 2, 4, 0, "", copper)
		T.eq(refs.Fill.Size.X.Offset, 75, "half the bar")
		T.truthy(refs.Fill.Visible, "bar visible")
		T.truthy(refs.Fill.BackgroundColor3 == copper, "ore colour")
		local pips, filled = visiblePips(refs)
		T.eq(pips, 4, "4 pips")
		T.eq(filled, 2, "2 filled")
		T.falsy(refs.Full.Visible, "not full")
		T.falsy(refs.Ready.Visible, "nothing ready")
		T.falsy(refs.Status.Visible, "no status")

		MachineBillboard.update(refs, 3, 4, 4, 3, "OutputBlocked", nil)
		T.eq(refs.Fill.Size.X.Offset, 150, "clamped to full")
		T.truthy(refs.Fill.BackgroundColor3 == Theme.Accent, "default colour")
		T.truthy(refs.Full.Visible, "FULL chip")
		T.truthy(refs.Ready.Visible, "ready count")
		T.eq(refs.Ready.Text, "3 ready", "ready text")
		T.truthy(refs.Status.Visible, "status shown")
		T.eq(refs.Status.Text, "Output blocked", "status text")

		MachineBillboard.update(refs, 0 / 0, 1, 2, 0, "TooManyItems", nil)
		T.eq(refs.Fill.Size.X.Offset, 0, "NaN progress is empty")
		T.falsy(refs.Fill.Visible, "bar hidden at 0")
		pips, filled = visiblePips(refs)
		T.eq(pips, 2, "pips follow QueueMax")
		T.eq(filled, 1, "1 filled")
		T.falsy(refs.Full.Visible, "FULL gone")
		T.falsy(refs.Ready.Visible, "ready gone")
		T.eq(refs.Status.Text, "Too many loose items", "loose items text")

		MachineBillboard.update(refs, 0.2, 0, 0, 0, "", nil)
		T.falsy(refs.Status.Visible, "status cleared")
		pips = visiblePips(refs)
		T.eq(pips, 0, "no queue, no pips")
		T.falsy(refs.Full.Visible, "no FULL without a queue")
		MachineBillboard.detach(refs)
	end)
	T.test("MachineBillboard: an optional note line (the Cleaning Plant's odds)", function()
		local model = MachineBuilder.build("AutoCleaner")
		local refs = MachineBillboard.attach(model)
		T.falsy(refs.Note.Visible, "no note at first")
		local height = refs.Gui.Size.Y.Offset
		MachineBillboard.setNote(refs, "Quality 2: 30% Rough · 50% Clean · 20% Pristine")
		T.truthy(refs.Note.Visible, "shown")
		T.truthy(refs.Gui.Size.Y.Offset > height, "the sign grows")
		T.eq(refs.Note.Text, "Quality 2: 30% Rough · 50% Clean · 20% Pristine")
		MachineBillboard.update(refs, 0.5, 1, 4, 0, "", nil)
		T.eq(refs.Fill.Size.X.Offset, 75, "the bar still works")
		MachineBillboard.setNote(refs, "")
		T.falsy(refs.Note.Visible, "hidden again")
		T.eq(refs.Gui.Size.Y.Offset, height, "back to its size")
		MachineBillboard.detach(refs)
	end)

	--[[
		Lune has no text engine (TextBounds stays 0), so the note's lines are
		worked out with generous FredokaOne glyph widths (em = TextSize):
		capitals, digits and % 0.66, lower case 0.52, space and · 0.32, and
		wrapped word by word the way TextWrapped does.
	]]
	local function glyph(char: string): number
		if char == " " then
			return 0.32
		elseif char:match("%l") then
			return 0.52
		elseif #char > 1 then
			return 0.32 -- the middle dot (2 bytes in UTF-8)
		end
		return 0.66
	end
	local function wordWidth(word: string, size: number): number
		local em = 0
		for _, code in utf8.codes(word) do
			em += glyph(utf8.char(code))
		end
		return em * size
	end
	local function wrappedLines(text: string, size: number, width: number): number
		local lines, used = 1, 0
		local space = glyph(" ") * size
		for word in text:gmatch("%S+") do
			local w = wordWidth(word, size)
			if used > 0 and used + space + w > width then
				lines += 1
				used = w
			else
				used += (if used > 0 then space else 0) + w
			end
		end
		return lines
	end

	T.test("MachineBillboard: every Quality level's odds fit the note (two lines)", function()
		local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")
		local ProcessingService = Loader.requirePath("ServerScriptService.Server.Services.ProcessingService")
		local model = MachineBuilder.build("AutoCleaner")
		local refs = MachineBillboard.attach(model)
		local size = MachineBillboard.NoteTextSize
		local box = MachineBillboard.NoteSize
		for level = 0, MachineData.upgradeMax("AutoCleaner", "Quality") do
			local text = MachineBillboard.qualityNote(level, ProcessingService.oddsText(MachineData.gradeOdds(level)))
			MachineBillboard.setNote(refs, text)
			T.truthy(refs.Note.TextWrapped, "wraps")
			T.eq(refs.Note.Size.X.Offset, box.X, "note width")
			T.eq(refs.Note.Size.Y.Offset, box.Y, "note height")
			local lines = wrappedLines(text, size, box.X)
			T.truthy(lines <= 2, `level {level}: "{text}" is {lines} lines`)
			T.truthy(lines * size * 1.2 <= box.Y, `level {level} fits the note's height`)
			T.truthy(refs.Gui.Size.X.Offset >= box.X and refs.Gui.Size.Y.Offset >= box.Y + 58, "inside the sign")
		end
		-- a one-line estimate of the old single-line note was far too wide
		T.truthy(wordWidth("Quality 3: 15% Rough · 45% Clean · 35% Pristine · 5% Flawless", size) > box.X, "it needs the wrap")
		MachineBillboard.detach(refs)
	end)

	T.test("MachineBillboard: an Iron Box with a full pen says so", function()
		local model = MachineBuilder.build("IronBox")
		local refs = MachineBillboard.attach(model)
		MachineBillboard.update(refs, 0, 1, 4, 0, "PenFull", nil)
		T.truthy(refs.Status.Visible, "status shown")
		T.eq(refs.Status.Text, "Ore Pen full")
		MachineBillboard.detach(refs)
	end)

	---------------------------------------------------------------- power and Detail lines (WP-Power)

	-- A generous width estimate for the info lines: like glyph() above, but
	-- every other character (⚡, ▶, …, punctuation) counts as a full em.
	local function lineWidth(text: string, size: number): number
		local em = 0
		for _, code in utf8.codes(text) do
			local char = utf8.char(code)
			if char == " " then
				em += 0.32
			elseif char:match("%l") then
				em += 0.52
			elseif char:match("[%u%d%%]") then
				em += 0.66
			else
				em += 1
			end
		end
		return em * size
	end

	local function withAttrs(model: any, attrs: { [string]: any })
		for _, name in { "PowerSpeed", "Powered", "PowerOut", "Network", "PowerSupply", "PowerDemand", "Detail" } do
			model:SetAttribute(name, nil)
		end
		for name, value in attrs do
			model:SetAttribute(name, value)
		end
	end

	T.test("MachineBillboard: the power line of machines, generators and poles", function()
		local model = MachineBuilder.build("Crusher")
		local function line(attrs: { [string]: any }): (string, any)
			withAttrs(model, attrs)
			return MachineBillboard.powerLine(model)
		end
		local text, color = line({ PowerSpeed = 1, Powered = true })
		T.eq(text, "Power 100%", "full speed")
		T.truthy(color == Theme.Good, "green")
		text, color = line({ PowerSpeed = 0.8, Powered = true })
		T.eq(text, "Low power 80%", "slowed")
		T.truthy(color == Theme.Accent, "amber")
		text = line({ PowerSpeed = 0.99, Powered = true })
		T.eq(text, "Low power 99%", "almost full is still low")
		text, color = line({ PowerSpeed = 0.6, Powered = false })
		T.eq(text, "No power 60%", "no power")
		T.truthy(color == Theme.Bad, "red")
		T.eq((line({ PowerSpeed = 0.6 })), "No power 60%", "Powered missing counts as no")
		-- generators
		text, color = line({ PowerOut = 40, Network = "5,5" })
		T.eq(text, "+40 power", "generator")
		T.truthy(color == Theme.Good)
		T.eq((line({ PowerOut = 18.75, Network = "5,5" })), "+19 power", "whole numbers")
		T.eq((line({ PowerOut = 450, Network = "5,5" })), "+450 power")
		T.eq((line({ PowerOut = 1500, Network = "5,5" })), "+1.5K power", "big numbers formatter")
		text, color = line({ PowerOut = 40, Network = "" })
		T.eq(text, "+40 power, no pole", "no pole reaches it")
		T.truthy(color == Theme.Accent)
		-- poles
		text, color = line({ PowerSupply = 35, PowerDemand = 50, Network = "5,5" })
		T.eq(text, "Network 35/50", "supply/demand")
		T.truthy(color == Theme.Accent, "short of power")
		text, color = line({ PowerSupply = 60, PowerDemand = 50 })
		T.truthy(color == Theme.Good, "enough")
		text, color = line({ PowerSupply = 0, PowerDemand = 50 })
		T.truthy(color == Theme.Bad, "nothing")
		text, color = line({ PowerSupply = 0, PowerDemand = 0 })
		T.eq(text, "Network 0/0")
		T.truthy(color == Theme.TextDim, "an empty network is grey")
		T.eq((line({ PowerSupply = 18.75, PowerDemand = 2500 })), "Network 19/2.5K")
		-- nothing / junk
		T.eq((line({})), "", "no power attributes")
		T.eq((line({ PowerSpeed = "fast" })), "", "junk")
		T.eq((line({ PowerSpeed = 0 / 0 })), "", "NaN")
	end)

	T.test("MachineBillboard: the Detail line", function()
		local model = MachineBuilder.build("Sorter")
		withAttrs(model, { Detail = "Rare+ ▶ right" })
		T.eq(MachineBillboard.detailLine(model), "Rare+ ▶ right")
		withAttrs(model, { Detail = string.rep("ab", 30) })
		local cut = MachineBillboard.detailLine(model)
		T.eq(utf8.len(cut), MachineBillboard.DetailMax, "cut to DetailMax characters")
		T.eq(cut:sub(-3), "…", "with an ellipsis")
		withAttrs(model, { Detail = string.rep("▶", 30) })
		T.eq(utf8.len(MachineBillboard.detailLine(model)), MachineBillboard.DetailMax, "cut on whole characters")
		withAttrs(model, { Detail = "" })
		T.eq(MachineBillboard.detailLine(model), "")
		withAttrs(model, { Detail = 5 })
		T.eq(MachineBillboard.detailLine(model), "", "not a string")
		withAttrs(model, {})
		T.eq(MachineBillboard.detailLine(model), "")
	end)

	T.test("MachineBillboard: info lines on the sign, the note under them", function()
		local model = MachineBuilder.build("Sorter")
		local refs = MachineBillboard.attach(model)
		local base = refs.Gui.Size.Y.Offset
		local line = MachineBillboard.InfoSize.Y
		T.falsy(refs.Power.Visible, "no power line at first")
		T.falsy(refs.Detail.Visible, "no detail line at first")
		-- update() reads the attributes the first time it runs
		withAttrs(model, { PowerSpeed = 0.8, Powered = true })
		MachineBillboard.update(refs, 0.5, 1, 4, 0, "", nil)
		T.truthy(refs.Power.Visible, "power line shown")
		T.eq(refs.Power.Text, "Low power 80%")
		T.truthy(refs.Power.TextColor3 == Theme.Accent)
		T.eq(refs.Power.Position.Y.Offset, base, "under the queue")
		T.eq(refs.Gui.Size.Y.Offset, base + line, "the sign grows by one line")
		T.eq(refs.Fill.Size.X.Offset, 75, "the bar still works")
		-- ...then at most every INFO_INTERVAL: refreshInfo reads them now
		withAttrs(model, { PowerSpeed = 1, Powered = true, Detail = "Rare+ ▶ right" })
		MachineBillboard.refreshInfo(refs)
		T.eq(refs.Power.Text, "Power 100%")
		T.truthy(refs.Power.TextColor3 == Theme.Good)
		T.truthy(refs.Detail.Visible, "detail line")
		T.eq(refs.Detail.Text, "Rare+ ▶ right")
		T.eq(refs.Detail.Position.Y.Offset, base + line, "under the power line")
		T.eq(refs.Gui.Size.Y.Offset, base + 2 * line)
		MachineBillboard.setNote(refs, "A note")
		T.eq(refs.Note.Position.Y.Offset, base + 2 * line, "the note under the info lines")
		T.eq(refs.Gui.Size.Y.Offset, base + 2 * line + MachineBillboard.NoteSize.Y)
		-- the power attributes go (e.g. a machine that needs none): the line goes
		withAttrs(model, { Detail = "Rare+ ▶ right" })
		MachineBillboard.refreshInfo(refs)
		T.falsy(refs.Power.Visible, "power line hidden")
		T.eq(refs.Detail.Position.Y.Offset, base, "detail moves up")
		withAttrs(model, {})
		MachineBillboard.refreshInfo(refs)
		T.eq(refs.Note.Position.Y.Offset, base, "the note moves up")
		MachineBillboard.setNote(refs, "")
		T.eq(refs.Gui.Size.Y.Offset, base, "back to its size")
		T.eq(refs.Gui.SizeOffset.Y, 0.5, "the sign grows upward, never into the machine")
		MachineBillboard.detach(refs)
	end)

	T.test("MachineBillboard: an Alloy Furnace waiting for another ore says so", function()
		local model = MachineBuilder.build("AlloyFurnace")
		local refs = MachineBillboard.attach(model)
		MachineBillboard.update(refs, 0, 1, 4, 0, "NeedsOtherOre", nil)
		T.truthy(refs.Status.Visible, "status shown")
		T.eq(refs.Status.Text, "Needs an ingot of another ore")
		-- the word sizes to its text next to the lamp, in a row wider than the sign
		T.truthy(
			lineWidth(refs.Status.Text, refs.Status.TextSize) <= MachineBillboard.StatusWidth,
			"one line next to the lamp in the (centred, wider) status row"
		)
		T.falsy(refs.Status.TextWrapped, "never wraps")
		T.eq(refs.Status.AutomaticSize, roblox.Enum.AutomaticSize.X, "as wide as its text")
		T.eq(refs.StatusRow.AnchorPoint.X, 0.5, "centred")
		T.truthy(refs.StatusRow.Size.X.Offset >= MachineBillboard.StatusWidth + 18, "room for the lamp and the word")
		MachineBillboard.detach(refs)
	end)

	T.test("MachineBillboard: the compact info sign of poles and generators", function()
		local pole = MachineBuilder.build("PowerPole")
		withAttrs(pole, { PowerSupply = 35, PowerDemand = 50, Network = "5,5" })
		local refs = MachineBillboard.attachInfo(pole)
		local status = pole.PrimaryPart:FindFirstChild("Status")
		T.truthy(refs.Gui.Parent == status, "on the Status attachment")
		T.eq(refs.Gui.Name, MachineBillboard.InfoName, "not the progress sign's name")
		T.eq(status:FindFirstChild(MachineBillboard.Name), nil, "no progress sign")
		T.falsy(refs.Bar.Visible, "no bar")
		T.falsy(refs.PipRow.Visible, "no queue")
		T.falsy(refs.Status.Visible, "no status")
		T.eq(refs.Power.Text, "Network 35/50", "filled at once")
		T.eq(refs.Power.Position.Y.Offset, 0, "the first row")
		T.eq(refs.Gui.Size.Y.Offset, MachineBillboard.InfoSize.Y, "one line high")
		T.truthy(refs.Gui.Enabled, "shown")
		T.eq(refs.Gui.MaxDistance, 45)
		withAttrs(pole, { PowerSupply = 60, PowerDemand = 50 })
		MachineBillboard.refreshInfo(refs)
		T.eq(refs.Power.Text, "Network 60/50")
		withAttrs(pole, {})
		MachineBillboard.refreshInfo(refs)
		T.falsy(refs.Gui.Enabled, "nothing to say: hidden")
		MachineBillboard.detach(refs)
		T.eq(status:FindFirstChild(MachineBillboard.InfoName), nil, "detached")

		local turbine = MachineBuilder.build("WindTurbine")
		withAttrs(turbine, { PowerOut = 40, Network = "5,5" })
		local sign = MachineBillboard.attachInfo(turbine)
		T.eq(sign.Power.Text, "+40 power")
		T.truthy(MachineBillboard.anchorOf(turbine) == sign.Gui.Parent, "anchorOf: where signs hang")
		MachineBillboard.detach(sign)
	end)

	T.test("MachineBillboard: every info line fits one line of the sign (phones)", function()
		local width = MachineBillboard.InfoSize.X
		local size = MachineBillboard.InfoTextSize
		T.truthy(size >= 14, "readable text")
		local samples = {
			"Power 100%",
			"Low power 99%",
			"No power 60%",
			"+1.23K power, no pole",
			"+450 power",
			"Network 999/999",
			"Network 1.23K/4.56K",
			"Legendary+ ▶ right",
			string.rep("W", MachineBillboard.DetailMax - 1) .. "…",
		}
		for _, text in samples do
			T.truthy(lineWidth(text, size) <= width, `"{text}" fits {width} px`)
		end
	end)

	---------------------------------------------------------------- status row, stack lights, FULL pop (machine UX)

	local MachineData = Loader.requirePath("ReplicatedStorage.Shared.Config.MachineData")

	T.test("MachineBillboard: statusOf reads a machine's attributes in order", function()
		local function of(id: string, attrs: { [string]: any }): string
			return MachineBillboard.statusOf(attrs, MachineData.ById[id])
		end
		-- a processor: idle with an empty queue waits; a job or a queue works
		T.eq(of("Crusher", { Queue = 0, Status = "" }), "Waiting", "idle crusher waits")
		T.eq(of("Crusher", {}), "Waiting", "no attributes yet: waiting")
		T.eq(of("Crusher", { Working = true, Queue = 1 }), "Working", "a job runs")
		T.eq(of("Crusher", { Queue = 2, Working = false }), "Working", "items queued for the next job")
		T.eq(of("Crusher", { Job = "3|100|3|Copper", Queue = 1 }), "Working", "Working read from the packed Job")
		T.eq(of("Crusher", { Job = "3|||", Queue = 0 }), "Waiting", "an idle packed Job")
		-- a block comes first, even while a job runs
		T.eq(of("Crusher", { Working = true, Queue = 4, Status = "OutputBlocked" }), "OutputBlocked")
		T.eq(of("IronBox", { Queue = 1, PenFull = true }), "PenFull", "the Iron Box's full pen")
		T.eq(of("IronBox", { Queue = 1, PenFull = true, Status = "TooManyItems" }), "TooManyItems", "a Status before PenFull")
		T.eq(of("AlloyFurnace", { Queue = 1, Status = "NeedsOtherOre" }), "NeedsOtherOre")
		-- power: no powered network is news, working or not; low power is not
		local unpowered = { PowerSpeed = 0.6, Powered = false, Queue = 0 }
		T.eq(of("BrickFurnace", unpowered), "NoPower", "idle without power")
		T.eq(of("BrickFurnace", { PowerSpeed = 0.6, Powered = false, Working = true, Queue = 1 }), "NoPower", "slow job")
		T.eq(of("BrickFurnace", { PowerSpeed = 0.6, Queue = 0 }), "NoPower", "Powered missing counts as no")
		T.eq(of("BrickFurnace", { PowerSpeed = 0.8, Powered = true, Queue = 0 }), "Waiting", "low power")
		T.eq(of("BrickFurnace", { PowerSpeed = 1, Powered = true, Working = true }), "Working", "full power")
		T.eq(of("BrickFurnace", { PowerSpeed = 0.6, Powered = false, Status = "OutputBlocked" }), "OutputBlocked")
		T.eq(of("RobotArm", { PowerSpeed = 0.6, Powered = false }), "NoPower", "any machine that uses power")
		-- no jobs of its own: nothing to say while idle
		for _, id in { "Splitter", "SellBox", "CleaningStation", "RobotArm", "Conveyor", "PowerPole", "WindTurbine" } do
			T.eq(of(id, { Queue = 0 }), "", id .. " idle")
		end
		T.eq(of("Splitter", { Working = true }), "Working", "a busy splitter")
		T.eq(of("WindTurbine", { PowerOut = 40, Network = "" }), "", "generators have none")
		T.eq(MachineBillboard.statusOf({ Queue = 0 }, nil), "", "unknown machine")
	end)

	T.test("MachineBillboard: a waiting machine says what it needs (one line)", function()
		local expected = {
			AutoCleaner = "Needs dirty ore",
			ClayFurnace = "Needs clean or crushed ore",
			BlastFurnace = "Needs clean or crushed ore",
			Crusher = "Needs clean ore",
			Polisher = "Needs clean ore",
			CrystalExtractor = "Needs crushed ore",
			IronBox = "Needs ore or ingots",
			AlloyFurnace = "Needs ingots",
			RestorationTable = "Needs a relic",
		}
		for id, text in expected do
			T.eq(MachineBillboard.needsText(MachineData.ById[id]), text, id)
		end
		T.eq(MachineBillboard.needsText(nil), "Waiting", "unknown machine")
		T.eq(MachineBillboard.needsText(MachineData.ById.PowerPole), "Waiting", "takes nothing")
		-- every machine that can wait: its words fit next to the lamp
		local size = MachineBillboard.StatusTextSize
		for _, info in MachineData.List do
			if MachineBillboard.statusOf({ Queue = 0 }, info) == "Waiting" then
				local text = MachineBillboard.needsText(info)
				T.truthy(text:sub(1, 6) == "Needs ", info.Id .. " names its input")
				T.truthy(lineWidth(text, size) <= MachineBillboard.StatusWidth, `"{text}" fits`)
			end
		end
		for _, status in { "OutputBlocked", "TooManyItems", "PenFull", "NeedsOtherOre", "Working" } do
			local text = MachineBillboard.StatusText[status]
			T.truthy(lineWidth(text, size) <= MachineBillboard.StatusWidth, `"{text}" fits`)
		end
		T.truthy(lineWidth("No power: 100%", size) <= MachineBillboard.StatusWidth, "no power fits")
	end)

	-- the glyph frames on the lamp, by name prefix
	local function glyphOf(refs: any): (string, number)
		local name, count = "", 0
		for _, child in refs.Glyph:GetChildren() do
			count += 1
			name = child.Name:gsub("%d+$", "")
		end
		return name, count
	end

	T.test("MachineBillboard: the status row - lamp, glyph and words for each status", function()
		local model = MachineBuilder.build("BrickFurnace")
		withAttrs(model, {})
		local refs = MachineBillboard.attach(model)
		T.falsy(refs.StatusRow.Visible, "no row at first")

		-- idle and waiting: only the status row (no bar, no queue)
		MachineBillboard.update(refs, 0, 0, 4, 0, "Waiting", nil)
		T.truthy(refs.StatusRow.Visible and refs.Status.Visible, "row shown")
		T.eq(refs.Status.Text, "Needs clean or crushed ore")
		T.truthy(refs.Status.TextColor3 == Theme.TextDim, "grey words")
		local glyph, bars = glyphOf(refs)
		T.eq(glyph, "Pause", "pause glyph")
		T.eq(bars, #MachineBillboard.Glyphs.Pause)
		T.falsy(refs.Bar.Visible, "no bar while idle")
		T.falsy(refs.PipRow.Visible, "no queue while idle")
		T.eq(refs.Gui.Size.Y.Offset, 20, "just the status row")
		T.truthy(refs.Gui.Enabled, "shown")

		-- working: the bar and queue come back under the row
		MachineBillboard.update(refs, 0.3, 1, 4, 0, "Working", nil)
		T.eq(refs.Status.Text, "Working")
		T.truthy(refs.Icon.BackgroundColor3 == Theme.Good, "green lamp")
		T.truthy(refs.Status.TextColor3 == Theme.Good, "green words")
		glyph, bars = glyphOf(refs)
		T.eq(glyph, "Play", "play glyph")
		T.eq(bars, #MachineBillboard.Glyphs.Play, "the old glyph is gone")
		T.truthy(refs.Bar.Visible and refs.PipRow.Visible, "bar and queue")
		T.eq(refs.Bar.Position.Y.Offset, 20, "the bar under the row")
		T.eq(refs.Gui.Size.Y.Offset, 58)

		-- blocked: red, the no-entry bar
		MachineBillboard.update(refs, 1, 4, 4, 2, "OutputBlocked", nil)
		T.eq(refs.Status.Text, "Output blocked")
		T.truthy(refs.Icon.BackgroundColor3 == Theme.Bad, "red lamp")
		T.truthy(refs.Status.TextColor3 == Theme.Bad, "red words")
		T.eq((glyphOf(refs)), "Stop")

		-- no power: yellow with the speed; the power line (the same news) hides
		withAttrs(model, { PowerSpeed = 0.6, Powered = false })
		MachineBillboard.update(refs, 0, 0, 4, 0, "NoPower", nil)
		T.eq(refs.Status.Text, "No power: 60%")
		T.truthy(refs.Icon.BackgroundColor3 == Theme.Coin, "yellow lamp")
		T.truthy(refs.Status.TextColor3 == Theme.Coin, "yellow words")
		T.eq((glyphOf(refs)), "Bolt")
		for _, bar in refs.Glyph:GetChildren() do
			T.truthy(bar.BackgroundColor3 == Theme.Outline, "a dark bolt on yellow")
		end
		T.falsy(refs.Power.Visible, "no second no-power line")
		T.eq(refs.Gui.Size.Y.Offset, 20, "idle: just the row")
		-- powered again: the row says what it does, the power line is back
		withAttrs(model, { PowerSpeed = 1, Powered = true })
		MachineBillboard.update(refs, 0, 0, 4, 0, "Waiting", nil)
		T.truthy(refs.Power.Visible, "power line back")
		T.eq(refs.Power.Text, "Power 100%")
		T.eq(refs.Power.Position.Y.Offset, 20, "under the status row")
		T.eq(refs.Gui.Size.Y.Offset, 20 + MachineBillboard.InfoSize.Y)

		-- nothing to say and idle: hidden
		withAttrs(model, {})
		MachineBillboard.update(refs, 0, 0, 4, 0, "", nil)
		T.falsy(refs.StatusRow.Visible, "row hidden")
		T.falsy(refs.Gui.Enabled, "empty sign hidden")
		MachineBillboard.detach(refs)
	end)

	T.test("MachineBillboard: the status row in the light UI (and the dark look)", function()
		local LightSkin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LightSkin")
		local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
		local model = MachineBuilder.build("Crusher")
		withAttrs(model, {})
		local dark = MachineBillboard.attach(model)
		MachineBillboard.update(dark, 0, 0, 4, 0, "Waiting", nil)
		-- dark look: the kit's colours, a white glyph
		for _, bar in dark.Glyph:GetChildren() do
			T.truthy(bar.BackgroundColor3 == Color3.new(1, 1, 1), "white glyph")
		end
		MachineBillboard.detach(dark)

		local refs = MachineBillboard.attach(model)
		MachineBillboard.update(refs, 0.5, 1, 4, 0, "Working", nil)
		LightSkin.world(refs.Gui)
		T.truthy(refs.Icon.BackgroundColor3 == BubbleTheme.Roles.Go.Base, "the light skin's green")
		for _, bar in refs.Glyph:GetChildren() do
			T.truthy(bar.BackgroundColor3 == Color3.new(1, 1, 1), "the glyph stays white")
		end
		local edge = nil
		for _, child in refs.Status:GetChildren() do
			if child:IsA("UIStroke") and child.Enabled then
				edge = child
			end
		end
		T.truthy(edge and edge.Color == BubbleTheme.Outline, "the words get the light look's navy edge")
		T.truthy(refs.Status.TextColor3 == Theme.Good, "green words over the world")
		MachineBillboard.detach(refs)
	end)

	T.test("MachineBillboard: lampOf - the stack light tells the truth", function()
		local function lamp(id: string, attrs: { [string]: any }): string
			return MachineBillboard.lampOf(attrs, MachineData.ById[id])
		end
		for _, id in { "Crusher", "BlastFurnace", "AutoCleaner" } do
			T.eq(lamp(id, { Working = true, Queue = 1 }), "StackGreen", id .. " working")
			T.eq(lamp(id, { Queue = 0 }), "StackAmber", id .. " waiting")
			T.eq(lamp(id, { Working = true, Queue = 4, Status = "OutputBlocked" }), "StackRed", id .. " blocked")
			T.eq(lamp(id, { Queue = 4, Status = "TooManyItems" }), "StackRed", id .. " too many items")
		end
		T.eq(lamp("BlastFurnace", { PowerSpeed = 0.6, Powered = false, Working = true }), "StackAmber", "no power")
		T.eq(lamp("BlastFurnace", { PowerSpeed = 1, Powered = true, Working = true }), "StackGreen", "powered")
		T.eq(lamp("AlloyFurnace", { Queue = 1, Status = "NeedsOtherOre" }), "StackAmber", "waits for an ore")
		T.eq(lamp("IronBox", { Queue = 1, PenFull = true }), "StackRed", "full pen")
		-- the Fusion Reactor (a generator): green while a pole takes its power
		T.eq(lamp("FusionReactor", { PowerOut = 450, Network = "3,3" }), "StackGreen", "feeds a network")
		T.eq(lamp("FusionReactor", { PowerOut = 450, Network = "" }), "StackAmber", "no pole")
		T.eq(lamp("FusionReactor", {}), "StackAmber", "not computed yet")
	end)

	T.test("MachineBillboard: stack lights on every machine that has one, one lamp lit", function()
		local Stack = MachineBuilder.Stack
		for _, id in { "Crusher", "BlastFurnace", "FusionReactor", "AutoCleaner" } do
			local model = MachineBuilder.build(id)
			local lamps = MachineBillboard.stackLamps(model)
			T.truthy(lamps, id .. " has a stack light")
			for name in Stack.Lamps do
				T.truthy(lamps[name] and lamps[name].Parent == model, `{id} {name}`)
			end
			for _, lit in { "StackRed", "StackAmber", "StackGreen" } do
				MachineBillboard.lightStack(lamps, lit)
				for name, part in lamps do
					local on = name == lit
					T.eq(part.Material, if on then roblox.Enum.Material.Neon else roblox.Enum.Material.SmoothPlastic, `{id} {lit}: {name}`)
					local color = Stack.Lamps[name]:Lerp(Color3.new(0, 0, 0), if on then Stack.Glow else Stack.Dim)
					T.truthy(part.Color == color, `{id} {lit}: {name} keeps its hue`)
				end
			end
		end
		for _, id in { "ClayFurnace", "PowerPole", "Conveyor" } do
			T.eq(MachineBillboard.stackLamps(MachineBuilder.build(id)), nil, id .. " has none")
		end
	end)

	T.test("MachineBillboard: wants - which of your machines get a sign", function()
		local busy = { Queue = 2, Working = true }
		local idle = { Queue = 0 }
		T.truthy(MachineBillboard.wants(busy, "Working", 45), "busy within Range")
		T.falsy(MachineBillboard.wants(busy, "Working", MachineBillboard.Range + 1), "never beyond Range")
		T.truthy(MachineBillboard.wants(idle, "Waiting", MachineBillboard.StatusRange), "waiting within StatusRange")
		T.falsy(MachineBillboard.wants(idle, "Waiting", MachineBillboard.StatusRange + 1), "an idle status only up close")
		T.truthy(MachineBillboard.wants(idle, "NoPower", 12), "no power")
		T.falsy(MachineBillboard.wants(idle, "", 5), "nothing to say")
		T.truthy(MachineBillboard.wants({ Queue = 0, Status = "OutputBlocked" }, "OutputBlocked", 40), "blocked is busy")
		T.truthy(MachineBillboard.wants({ Queue = 1, PenFull = true }, "PenFull", 40), "full pen is busy")
		local odds = { Queue = 0, QualityOdds = "60% Rough · 40% Clean" }
		T.truthy(MachineBillboard.wants(odds, "", MachineBillboard.OddsRange), "the plant's odds up close")
		T.falsy(MachineBillboard.wants(odds, "", MachineBillboard.OddsRange + 1), "not from afar")
		T.truthy(MachineBillboard.StatusRange <= 45, "the sign shows that far (MaxDistance 45)")
	end)

	T.test("MachineBillboard: under the sign cap, blocked beats nearer waiting ones", function()
		T.eq(MachineBillboard.signRank("OutputBlocked"), 0)
		T.eq(MachineBillboard.signRank("TooManyItems"), 0)
		T.eq(MachineBillboard.signRank("PenFull"), 0)
		T.eq(MachineBillboard.signRank("Working"), 1)
		T.eq(MachineBillboard.signRank("NoPower"), 2)
		T.eq(MachineBillboard.signRank("Waiting"), 3)
		T.eq(MachineBillboard.signRank("NeedsOtherOre"), 3)
		T.eq(MachineBillboard.signRank(""), 3, "the plant's odds alone")
		-- a mid-game base: 20 idle machines close by, one blocked and one
		-- working further away, a cap of 12 (MachineFxController)
		local cap = 12
		local list = {}
		for i = 1, 20 do
			table.insert(list, { Status = "Waiting", Distance = i })
		end
		local blocked = { Status = "OutputBlocked", Distance = 29 }
		local working = { Status = "Working", Distance = 45 }
		local unpowered = { Status = "NoPower", Distance = 25 }
		table.insert(list, blocked)
		table.insert(list, working)
		table.insert(list, unpowered)
		table.sort(list, MachineBillboard.signBefore)
		T.truthy(list[1] == blocked, "blocked first")
		T.truthy(list[2] == working, "then working")
		T.truthy(list[3] == unpowered, "then no power")
		T.eq(list[4].Distance, 1, "then the nearest waiting")
		T.eq(list[cap].Distance, cap - 3, "the farther waiting ones lose their sign")
		local fx = fs.readFile("src/client/Controllers/MachineFxController.luau")
		T.truthy(string.find(fx, "table.sort(candidates, MachineBillboard.signBefore)", 1, true) ~= nil, "the cap sorts by it")
		T.truthy(string.find(fx, "local MAX_BILLBOARDS = " .. cap, 1, true) ~= nil, "the cap")
	end)

	T.test("MachineBillboard: the FULL / BUSY pop over a hopper", function()
		local LightSkin = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.UI.LightSkin")
		local BubbleTheme = Loader.requirePath("ReplicatedStorage.Shared.Config.BubbleTheme")
		local part = roblox.Instance.new("Part")
		local pop = MachineBillboard.buildPop(part)
		T.eq(pop.Gui.Name, MachineBillboard.PopName)
		T.truthy(pop.Gui.Parent == part and pop.Gui.Adornee == part, "on its anchor part")
		T.falsy(pop.Gui.Enabled, "hidden until popped")
		T.truthy(pop.Gui.AlwaysOnTop, "seen over the machine")
		T.eq(pop.Chip.Text, "FULL")
		T.truthy(pop.Chip.BackgroundColor3 == Theme.Bad, "red chip")
		T.truthy(pop.Scale:IsA("UIScale") and pop.Scale.Parent == pop.Chip, "scales for the pop-in")
		T.eq(MachineBillboard.popText("Full"), "FULL")
		T.eq(MachineBillboard.popText("Busy"), "BUSY")
		T.eq(MachineBillboard.popText(nil), "FULL", "junk reads as full")
		T.truthy(lineWidth("BUSY", pop.Chip.TextSize) <= pop.Chip.Size.X.Offset, "the words fit the chip")
		LightSkin.world(pop.Gui)
		T.truthy(pop.Chip.BackgroundColor3 == BubbleTheme.Roles.Danger.Base, "the light skin's red")
	end)
end
