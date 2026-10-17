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
end
