-- The progress sign over your own machines (client UI builder) on a real
-- machine model: where it hangs, and what update() shows.
return function(T, Loader)
	local roblox = require("@lune/roblox") :: any
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
		T.eq(text, "⚡ 100%", "full speed")
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
		T.eq(text, "⚡ +40 power", "generator")
		T.truthy(color == Theme.Good)
		T.eq((line({ PowerOut = 18.75, Network = "5,5" })), "⚡ +19 power", "whole numbers")
		T.eq((line({ PowerOut = 450, Network = "5,5" })), "⚡ +450 power")
		T.eq((line({ PowerOut = 1500, Network = "5,5" })), "⚡ +1.5K power", "big numbers formatter")
		text, color = line({ PowerOut = 40, Network = "" })
		T.eq(text, "⚡ +40 power, no pole", "no pole reaches it")
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
		T.eq(refs.Power.Text, "⚡ 100%")
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
		T.truthy(
			lineWidth(refs.Status.Text, refs.Status.TextSize) <= refs.Status.Size.X.Offset,
			"one line in the (centred, wider) status label"
		)
		T.eq(refs.Status.AnchorPoint.X, 0.5, "centred")
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
		T.eq(sign.Power.Text, "⚡ +40 power")
		T.truthy(MachineBillboard.anchorOf(turbine) == sign.Gui.Parent, "anchorOf: where signs hang")
		MachineBillboard.detach(sign)
	end)

	T.test("MachineBillboard: every info line fits one line of the sign (phones)", function()
		local width = MachineBillboard.InfoSize.X
		local size = MachineBillboard.InfoTextSize
		T.truthy(size >= 14, "readable text")
		local samples = {
			"⚡ 100%",
			"Low power 99%",
			"No power 60%",
			"⚡ +1.23K power, no pole",
			"⚡ +450 power",
			"Network 999/999",
			"Network 1.23K/4.56K",
			"Legendary+ ▶ right",
			string.rep("W", MachineBillboard.DetailMax - 1) .. "…",
		}
		for _, text in samples do
			T.truthy(lineWidth(text, size) <= width, `"{text}" fits {width} px`)
		end
	end)
end
