--[[
	MachineBillboard: the small sign above YOUR busy machines.

	   Output blocked            status line, only when something is wrong
	  [==========-----]          job progress, in the ore's colour
	   o o o .  FULL  2 ready    queue (the item being worked counts), a red
	                             FULL chip, finished items waiting to leave
	   Low power 80%             power line (PowerService attributes, below)
	   Rare+ ▶ right             the machine's Detail attribute (the Sorter's setting)
	   Quality 2: 30% Rough ...  an optional note under it (setNote: the
	   50% Clean · 20% Pristine  Cleaning Plant's grade odds, qualityNote),
	                             up to two wrapped lines

	It hangs on the machine's Status attachment (its bottom just above it,
	so a taller sign grows upward, never into the machine) and hides itself
	beyond 45 studs. MachineFxController decides which machines get one (at
	most 12) and calls update() every frame; update() writes only what
	changed. Pure builder: it only creates and changes Instances and reads
	the model's attributes (no services, no events), so the Lune tests can
	run it.

	Info lines (refreshInfo: read from the model's attributes, by update()
	at most every INFO_INTERVAL seconds, or when called):
	  machines (PowerSpeed, Powered)  "⚡ 100%" at full speed, "Low power 80%"
	                                  while slowed, "No power 60%" when on no
	                                  network with power
	  generators (PowerOut, Network)  "⚡ +40 power" (", no pole" when no pole reaches it)
	  poles (PowerSupply/PowerDemand) "Network 35/50" (supply/demand)
	  Detail (string)                 shown as it is (one line; longer than DETAIL_MAX
	                                  characters, it is cut with "…")
	attachInfo builds a compact sign with only these lines (no status, bar
	or queue): PowerController puts it on your poles, generators and
	machines with a Detail (those never get the busy sign while idle).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UITheme"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Format"))
local UIKit = require(script.Parent.UIKit)

local MachineBillboard = {}

export type Refs = {
	Gui: BillboardGui,
	Bar: Frame,
	Fill: Frame,
	PipRow: Frame,
	Pips: { Frame },
	Full: TextLabel,
	Ready: TextLabel,
	Status: TextLabel,
	Note: TextLabel, -- optional line under the queue (setNote)
	Power: TextLabel, -- info line: power (refreshInfo)
	Detail: TextLabel, -- info line: the Detail attribute (refreshInfo)
	Model: Model, -- whose attributes the info lines read
	Compact: boolean, -- attachInfo: only the info lines
	InfoAt: number, -- os.clock() of the next info refresh from update()
	-- what is on screen now (update() skips unchanged values)
	Shown: {
		Pixels: number,
		Queue: number,
		QueueMax: number,
		OutCount: number,
		Status: string,
		Color: Color3,
		Power: string,
		PowerColor: Color3,
		Detail: string,
	},
}

local MAX_DISTANCE = 45
local WIDTH = 170
local BAR_WIDTH = 150
local MAX_PIPS = 8
local PIP = 10
local PIP_STEP = 13
local HEIGHT = 58
local NOTE_HEIGHT = 30 -- two lines of 12 px text
local NOTE_WIDTH = WIDTH + 80
local INFO_TEXT = 14
local INFO_LINE = 17 -- one info line (14 px text)
local INFO_INTERVAL = 0.25 -- seconds between info refreshes from update()
local DETAIL_MAX = 24 -- characters of the Detail attribute shown (fits one line on the sign)

MachineBillboard.NoteTextSize = 12
MachineBillboard.NoteSize = Vector2.new(NOTE_WIDTH, NOTE_HEIGHT)
MachineBillboard.InfoTextSize = INFO_TEXT
MachineBillboard.InfoSize = Vector2.new(NOTE_WIDTH, INFO_LINE)
MachineBillboard.DetailMax = DETAIL_MAX
MachineBillboard.Name = "MachineBillboard"
MachineBillboard.InfoName = "InfoSign"

local STATUS_TEXT: { [string]: string } = {
	OutputBlocked = "Output blocked",
	TooManyItems = "Too many loose items",
	PenFull = "Ore Pen full", -- an Iron Box whose kept ore can't go into the pen
	NeedsOtherOre = "Needs an ingot of another ore", -- an Alloy Furnace with one ore waiting
}
MachineBillboard.StatusText = STATUS_TEXT

-- Where a model's signs hang: its Status attachment, else its Base, else the model.
function MachineBillboard.anchorOf(model: Model): Instance
	local base = model.PrimaryPart
	local status = base and base:FindFirstChild("Status")
	return if status and status:IsA("Attachment") then status else (base or model)
end

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function numberAttr(model: Instance, name: string): number?
	local value = model:GetAttribute(name)
	return if type(value) == "number" and value == value then value else nil
end

--[[
	The power line of a model from its PowerService attributes, and its
	colour ("" when the model has no power attributes); see the header.
]]
function MachineBillboard.powerLine(model: Instance): (string, Color3)
	local speed = numberAttr(model, "PowerSpeed")
	if speed then
		local pct = round(math.clamp(speed, 0, 1) * 100)
		if model:GetAttribute("Powered") ~= true then
			return `No power {pct}%`, Theme.Bad
		elseif pct >= 100 then
			return `⚡ {pct}%`, Theme.Good
		end
		return `Low power {pct}%`, Theme.Accent
	end
	local out = numberAttr(model, "PowerOut")
	if out then
		local text = `⚡ +{Format.big(round(out))} power`
		if model:GetAttribute("Network") == "" then
			return text .. ", no pole", Theme.Accent
		end
		return text, Theme.Good
	end
	local supply = numberAttr(model, "PowerSupply")
	local demand = numberAttr(model, "PowerDemand")
	if supply and demand then
		local color = if supply <= 0 and demand <= 0
			then Theme.TextDim
			elseif supply <= 0 then Theme.Bad
			elseif supply < demand then Theme.Accent
			else Theme.Good
		return `Network {Format.big(round(supply))}/{Format.big(round(demand))}`, color
	end
	return "", Theme.Text
end

-- The model's Detail attribute as one short line ("" = none).
function MachineBillboard.detailLine(model: Instance): string
	local detail = model:GetAttribute("Detail")
	if type(detail) ~= "string" or detail == "" then
		return ""
	end
	local length = utf8.len(detail)
	if not length then
		return "" -- not valid UTF-8
	end
	if length > DETAIL_MAX then
		-- DETAIL_MAX characters in all, the last one an ellipsis
		local cut = utf8.offset(detail, DETAIL_MAX)
		return if cut then detail:sub(1, cut - 1) .. "…" else detail
	end
	return detail
end

local function infoLabel(gui: Instance, name: string, color: Color3): TextLabel
	return UIKit.label(gui, "", INFO_TEXT, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(NOTE_WIDTH, INFO_LINE),
		TextColor3 = color,
		TextWrapped = false,
		Visible = false,
	})
end

-- Sizes the sign and places its rows: status, bar and queue (not on a
-- compact sign), the info lines, then the note.
local function layout(refs: Refs)
	local noteOn = refs.Note.Text ~= ""
	local width = if noteOn then NOTE_WIDTH else WIDTH
	-- keep the bar and queue centred in a wider sign
	local shift = (width - WIDTH) / 2
	refs.Bar.Position = UDim2.fromOffset((WIDTH - BAR_WIDTH) / 2 + shift, 20)
	refs.PipRow.Position = UDim2.fromOffset((WIDTH - BAR_WIDTH) / 2 + shift, 39)
	local y = if refs.Compact then 0 else HEIGHT
	if refs.Power.Visible then
		refs.Power.Position = UDim2.new(0.5, 0, 0, y)
		y += INFO_LINE
	end
	if refs.Detail.Visible then
		refs.Detail.Position = UDim2.new(0.5, 0, 0, y)
		y += INFO_LINE
	end
	refs.Note.Position = UDim2.new(0.5, 0, 0, y)
	if noteOn then
		y += NOTE_HEIGHT
	end
	refs.Gui.Size = UDim2.fromOffset(width, y)
	refs.Gui.Enabled = y > 0
end

local function build(model: Model, compact: boolean): Refs
	local anchor = MachineBillboard.anchorOf(model)
	local gui = UIKit.new("BillboardGui", {
		Name = if compact then MachineBillboard.InfoName else MachineBillboard.Name,
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		StudsOffset = Vector3.new(0, 0.6, 0),
		-- the bottom edge sits at the anchor: a taller sign grows upward
		SizeOffset = Vector2.new(0, 0.5),
		MaxDistance = MAX_DISTANCE,
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		ClipsDescendants = false,
	}) :: BillboardGui
	if anchor:IsA("Attachment") or anchor:IsA("BasePart") then
		gui.Adornee = anchor
	end

	-- wider than the sign (centred), so a long status stays on one line
	local statusLabel = UIKit.label(gui, "", 15, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(NOTE_WIDTH, 18),
		Position = UDim2.new(0.5, 0, 0, 0),
		TextColor3 = Theme.Bad,
		TextWrapped = false,
		Visible = false,
	})

	local bar = UIKit.new("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(BAR_WIDTH, 14),
		Position = UDim2.fromOffset((WIDTH - BAR_WIDTH) / 2, 20),
		Visible = not compact,
	}, gui) :: Frame
	UIKit.corner(bar, 7)
	UIKit.stroke(bar, 2)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Visible = false,
	}, bar) :: Frame
	UIKit.corner(fill, 7)
	UIKit.gradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))

	local row = UIKit.new("Frame", {
		Name = "Queue",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BAR_WIDTH, 16),
		Position = UDim2.fromOffset((WIDTH - BAR_WIDTH) / 2, 39),
		Visible = not compact,
	}, gui) :: Frame
	local full = UIKit.chip(row, "FULL", Theme.Bad, {
		Name = "Full",
		Size = UDim2.fromOffset(40, 16),
		TextSize = 12,
		Visible = false,
	})
	local ready = UIKit.label(row, "", 13, {
		Name = "Ready",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(52, 16),
		TextColor3 = Theme.Coin,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		Visible = false,
	})

	local power = infoLabel(gui, "Power", Theme.Good)
	local detail = infoLabel(gui, "Detail", Theme.Info)

	local note = UIKit.label(gui, "", MachineBillboard.NoteTextSize, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HEIGHT),
		Size = UDim2.fromOffset(NOTE_WIDTH, NOTE_HEIGHT),
		TextColor3 = Theme.Text,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
	})

	local refs: Refs = {
		Gui = gui,
		Bar = bar,
		Fill = fill,
		PipRow = row,
		Pips = {},
		Full = full,
		Ready = ready,
		Status = statusLabel,
		Note = note,
		Power = power,
		Detail = detail,
		Model = model,
		Compact = compact,
		InfoAt = 0,
		Shown = {
			Pixels = 0,
			Queue = -1,
			QueueMax = -1,
			OutCount = -1,
			Status = "",
			Color = Theme.Accent,
			Power = "",
			PowerColor = Theme.Good,
			Detail = "",
		},
	}
	layout(refs)
	gui.Parent = anchor
	return refs
end

-- Builds the sign on the model's Status attachment (or its Base).
function MachineBillboard.attach(model: Model): Refs
	return build(model, false)
end

-- A compact sign with only the info lines (power, Detail), filled at
-- once; hidden (Enabled false) while the model has none. Call
-- refreshInfo when its attributes may have changed.
function MachineBillboard.attachInfo(model: Model): Refs
	local refs = build(model, true)
	MachineBillboard.refreshInfo(refs)
	return refs
end

-- Reads the info lines from the model's attributes again (writes only what changed).
function MachineBillboard.refreshInfo(refs: Refs)
	refs.InfoAt = os.clock() + INFO_INTERVAL
	local power, color = MachineBillboard.powerLine(refs.Model)
	local detail = MachineBillboard.detailLine(refs.Model)
	local shown = refs.Shown
	local relayout = false
	if power ~= shown.Power or color ~= shown.PowerColor then
		relayout = (power ~= "") ~= (shown.Power ~= "")
		shown.Power, shown.PowerColor = power, color
		refs.Power.Text = power
		refs.Power.TextColor3 = color
		refs.Power.Visible = power ~= ""
	end
	if detail ~= shown.Detail then
		relayout = relayout or (detail ~= "") ~= (shown.Detail ~= "")
		shown.Detail = detail
		refs.Detail.Text = detail
		refs.Detail.Visible = detail ~= ""
	end
	if relayout then
		layout(refs)
	end
end

local function setPips(refs: Refs, queue: number, queueMax: number)
	local wanted = math.clamp(queueMax, 0, MAX_PIPS)
	while #refs.Pips > wanted do
		local pip = table.remove(refs.Pips) :: Frame
		pip:Destroy()
	end
	while #refs.Pips < wanted do
		local pip = UIKit.new("Frame", {
			Name = "Pip" .. (#refs.Pips + 1),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(PIP, PIP),
			Position = UDim2.fromOffset(#refs.Pips * PIP_STEP, (16 - PIP) / 2),
		}, refs.PipRow) :: Frame
		UIKit.corner(pip, PIP)
		UIKit.stroke(pip, 1.5)
		table.insert(refs.Pips, pip)
	end
	for i, pip in refs.Pips do
		pip.BackgroundColor3 = if i <= queue then Theme.Accent else Theme.PanelLight
	end
	local isFull = queueMax > 0 and queue >= queueMax
	refs.Full.Visible = isFull
	refs.Full.Position = UDim2.fromOffset(wanted * PIP_STEP + 3, 0)
end

-- progress 0..1 of the running job; status is the machine's Status
-- attribute ('' | 'OutputBlocked' | 'TooManyItems' | 'NeedsOtherOre') or
-- 'PenFull' (an Iron Box's PenFull attribute, MachineFxController). The
-- info lines follow the model's attributes (refreshInfo, every
-- INFO_INTERVAL seconds).
function MachineBillboard.update(
	refs: Refs,
	progress: number,
	queue: number,
	queueMax: number,
	outCount: number,
	status: string,
	oreColor: Color3?
)
	local shown = refs.Shown
	local p = if progress == progress then math.clamp(progress, 0, 1) else 0
	-- whole pixels, so a slow bar doesn't rewrite every frame
	local pixels = math.floor(p * BAR_WIDTH + 0.5)
	if pixels ~= shown.Pixels then
		shown.Pixels = pixels
		refs.Fill.Size = UDim2.new(0, pixels, 1, 0)
		refs.Fill.Visible = pixels > 0
	end
	local color = oreColor or Theme.Accent
	if color ~= shown.Color then
		shown.Color = color
		refs.Fill.BackgroundColor3 = color
	end
	if queue ~= shown.Queue or queueMax ~= shown.QueueMax then
		shown.Queue = queue
		shown.QueueMax = queueMax
		setPips(refs, queue, queueMax)
	end
	if outCount ~= shown.OutCount then
		shown.OutCount = outCount
		refs.Ready.Text = `{outCount} ready`
		refs.Ready.Visible = outCount > 0
	end
	if status ~= shown.Status then
		shown.Status = status
		local text = STATUS_TEXT[status] or status
		refs.Status.Text = text
		refs.Status.Visible = text ~= ""
	end
	if os.clock() >= refs.InfoAt then
		MachineBillboard.refreshInfo(refs)
	end
end

-- The Cleaning Plant's note: its Quality level and grade odds.
function MachineBillboard.qualityNote(level: number, odds: string): string
	return `Quality {level}: {odds}`
end

-- A short note under the queue, up to two wrapped lines ("" hides it);
-- the sign grows to make room.
function MachineBillboard.setNote(refs: Refs, text: string)
	if refs.Note.Text == text then
		return
	end
	refs.Note.Text = text
	refs.Note.Visible = text ~= ""
	layout(refs)
end

function MachineBillboard.detach(refs: Refs)
	refs.Gui:Destroy()
end

return MachineBillboard
