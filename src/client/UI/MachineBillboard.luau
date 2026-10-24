--[[
	MachineBillboard: the small sign above YOUR machines.

	  (>) Working                status row: a round lamp with a glyph and a
	                             word (statusOf / STATUS_LOOK, below)
	  [==========-----]          job progress, in the ore's colour
	   o o o .  FULL  2 ready    queue (the item being worked counts), a red
	                             FULL chip, finished items waiting to leave
	   Low power 80%             power line (PowerService attributes, below)
	   Rare+ ▶ right             the machine's Detail attribute (the Sorter's setting)
	   Quality 2: 30% Rough ...  an optional note under it (setNote: the
	   50% Clean · 20% Pristine  Cleaning Plant's grade odds, qualityNote),
	                             up to two wrapped lines

	The bar and queue rows show only while the machine is busy (a job, a
	queue or finished items); an idle machine's sign is just its status row
	and info lines.

	Status row (statusOf reads the replicated attributes, in this order):
	  red    (-)  a Status attribute (Output blocked, Too many loose items)
	              or an Iron Box's PenFull
	  grey   (||) "Needs an ingot of another ore" (an Alloy Furnace's Status)
	  yellow (z)  "No power: 60%": needs power, on no powered network
	              (PowerSpeed set, Powered false; the power line then hides)
	  green  (>)  "Working": a job runs or items wait in the queue
	  grey   (||) "Needs clean ore": a processor (it has a job Time) idle
	              with an empty queue (needsText, from its Accepts)
	The glyphs are built from frames: fonts differ per platform and ▶ / ⏸ /
	⚡ may come out as colour emoji. lampOf gives the same state as a stack
	light lamp (green / amber / red; generators: green while a pole takes
	their power); stackLamps finds a model's lamps and lightStack lights
	one. wants() says which of your machines get a sign: busy ones
	within Range, every machine with a status within StatusRange, the
	Cleaning Plant's odds within OddsRange; signRank / signBefore which of
	them keep it under the cap (blocked, working, no power, waiting).

	A "FULL" / "BUSY" pop (buildPop) rises over a hopper that refused a
	dropped item (IntakeService's Fx 'Full'; MachineFxController animates it).

	It hangs on the machine's Status attachment (its bottom just above it,
	so a taller sign grows upward, never into the machine) and hides itself
	beyond 45 studs. MachineFxController decides which machines get one (at
	most 12) and calls update() when an attribute changed or a job runs;
	update() writes only what changed. Pure builder: it only creates and
	changes Instances and reads the model's attributes and MachineData (no
	services, no events), so the Lune tests can run it.

	Info lines (refreshInfo: read from the model's attributes, by update()
	at most every INFO_INTERVAL seconds, or when called):
	  machines (PowerSpeed, Powered)  "Power 100%" at full speed, "Low power 80%"
	                                  while slowed, "No power 60%" when on no
	                                  network with power
	  generators (PowerOut, Network)  "+40 power" (", no pole" when no pole reaches it)
	  poles (PowerSupply/PowerDemand) "Network 35/50" (supply/demand)
	  Detail (string)                 shown as it is (one line; longer than DETAIL_MAX
	                                  characters, it is cut with "…")
	attachInfo builds a compact sign with only these lines (no status, bar
	or queue): PowerController puts it on your poles, generators and
	machines with a Detail (those never get the busy sign while idle).

	decodeJob reads a processor's packed Job attribute (ProcessingService
	jobText: "cycles|start|time|ore", "cycles|||" when idle) for the
	progress bar and MachineFxController's effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Config"):WaitForChild("UITheme"))
local MachineData = require(Shared:WaitForChild("Config"):WaitForChild("MachineData"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local MachineBuilder = require(Shared:WaitForChild("Builders"):WaitForChild("MachineBuilder"))
local UIKit = require(script.Parent.UIKit)

local STACK = MachineBuilder.Stack
local LAMP_NAMES = { "StackRed", "StackAmber", "StackGreen" }

local MachineBillboard = {}

export type Refs = {
	Gui: BillboardGui,
	Bar: Frame,
	Fill: Frame,
	PipRow: Frame,
	Pips: { Frame },
	Full: TextLabel,
	Ready: TextLabel,
	StatusRow: Frame, -- the lamp and the status word, centred
	Icon: Frame, -- the round lamp in the status colour
	Glyph: Frame, -- the glyph's frames on the lamp
	Status: TextLabel,
	Note: TextLabel, -- optional line under the queue (setNote)
	Power: TextLabel, -- info line: power (refreshInfo)
	Detail: TextLabel, -- info line: the Detail attribute (refreshInfo)
	Model: Model, -- whose attributes the info lines read
	Compact: boolean, -- attachInfo: only the info lines
	Busy: boolean, -- the bar and queue rows show (a job, a queue or finished items)
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
local STATUS_ROW = 20 -- the status row's height (the bar starts under it)
local STATUS_TEXT_SIZE = 15
local ICON = 18 -- the status lamp's diameter
local ICON_GAP = 4 -- between the lamp and the word

MachineBillboard.NoteTextSize = 12
MachineBillboard.NoteSize = Vector2.new(NOTE_WIDTH, NOTE_HEIGHT)
MachineBillboard.InfoTextSize = INFO_TEXT
MachineBillboard.InfoSize = Vector2.new(NOTE_WIDTH, INFO_LINE)
MachineBillboard.DetailMax = DETAIL_MAX
MachineBillboard.Name = "MachineBillboard"
MachineBillboard.InfoName = "InfoSign"
MachineBillboard.PopName = "MachinePop"
-- the status word fits one line next to its lamp in this many pixels
MachineBillboard.StatusWidth = NOTE_WIDTH - ICON - ICON_GAP
MachineBillboard.StatusTextSize = STATUS_TEXT_SIZE
-- which of your machines get a sign (wants): busy ones this close...
MachineBillboard.Range = 50 -- (the sign hides itself beyond 45)
-- ...every machine with a status (working, waiting, no power) this close...
MachineBillboard.StatusRange = 30
-- ...and the Cleaning Plant with its grade odds, idle too, this close
MachineBillboard.OddsRange = 24

local STATUS_TEXT: { [string]: string } = {
	OutputBlocked = "Output blocked",
	TooManyItems = "Too many loose items",
	PenFull = "Ore Pen full", -- an Iron Box whose kept ore can't go into the pen
	NeedsOtherOre = "Needs an ingot of another ore", -- an Alloy Furnace with one ore waiting
	Working = "Working",
	Waiting = "Waiting", -- the sign says what for: "Needs clean ore" (needsText)
	NoPower = "No power", -- with the speed: "No power: 60%" (statusText)
}
MachineBillboard.StatusText = STATUS_TEXT

--[[
	Status glyphs: frames on the lamp, each { x, y, width, height, rotation }
	in pixels from the lamp's centre (x right, y down). Play: four columns
	stepping down to a point; Pause: two bars; Stop: the no-entry bar;
	Bolt: two slanted strokes joined in the middle.
]]
local GLYPHS: { [string]: { { number } } } = {
	Play = { { -2.5, 0, 2, 10, 0 }, { -0.5, 0, 2, 7.5, 0 }, { 1.5, 0, 2, 5, 0 }, { 3.5, 0, 2, 2.5, 0 } },
	Pause = { { -2.5, 0, 3, 10, 0 }, { 2.5, 0, 3, 10, 0 } },
	Stop = { { 0, 0, 10, 3, 0 } },
	Bolt = { { 1.2, -2.6, 2.5, 6, 25 }, { -1.2, 2.6, 2.5, 6, 25 }, { 0, 0, 5, 2, 0 } },
}
MachineBillboard.Glyphs = GLYPHS

local WAIT_GREY = Color3.fromRGB(128, 118, 110) -- (the light skin's grey "off" colour)
local WHITE = Color3.new(1, 1, 1)
-- The look of each status: the lamp's glyph and colour, the glyph's colour,
-- the word's colour. Any other status (STATUS_TEXT's blocks, an unknown
-- word) is Blocked.
type Look = { Glyph: string, Lamp: Color3, Ink: Color3, Text: Color3 }
local LOOKS: { [string]: Look } = {
	Working = { Glyph = "Play", Lamp = Theme.Good, Ink = WHITE, Text = Theme.Good },
	Waiting = { Glyph = "Pause", Lamp = WAIT_GREY, Ink = WHITE, Text = Theme.TextDim },
	NoPower = { Glyph = "Bolt", Lamp = Theme.Coin, Ink = Theme.Outline, Text = Theme.Coin },
	Blocked = { Glyph = "Stop", Lamp = Theme.Bad, Ink = WHITE, Text = Theme.Bad },
}
-- statuses that only wait for something (the Waiting look, an amber lamp)
local WAITS: { [string]: boolean } = { Waiting = true, NeedsOtherOre = true }

-- The look of a status ("Working", "Waiting", "NoPower" or "Blocked").
function MachineBillboard.toneOf(status: string): string
	if status == "Working" or status == "NoPower" then
		return status
	end
	return if WAITS[status] then "Waiting" else "Blocked"
end

local function lookOf(status: string): Look
	return LOOKS[MachineBillboard.toneOf(status)]
end

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

-- A processor's job as its Job attribute says (decodeJob).
export type Job = {
	Cycles: number, -- jobs finished since the model appeared
	Working: boolean, -- a job runs now
	Start: number, -- its server start time (0 when idle)
	Time: number, -- its seconds (0 when idle)
	Ore: string, -- the ore worked ("" for dirty ore or when idle)
}

local function finiteOr(text: string?, default: number?): number?
	local n = if text then tonumber(text) else nil
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

--[[
	Reads the packed Job attribute ("cycles|start|time|ore"; start and time
	empty while idle). Anything else (nil, junk) reads as idle with 0 jobs.
]]
function MachineBillboard.decodeJob(value: any): Job
	local job: Job = { Cycles = 0, Working = false, Start = 0, Time = 0, Ore = "" }
	if type(value) ~= "string" then
		return job
	end
	local cycles, start, seconds, ore = string.match(value, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
	job.Cycles = finiteOr(cycles, 0) :: number
	local s, t = finiteOr(start, nil), finiteOr(seconds, nil)
	if s and t then
		job.Working = true
		job.Start = s
		job.Time = t
		job.Ore = ore or ""
	end
	return job
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
			return `Power {pct}%`, Theme.Good
		end
		return `Low power {pct}%`, Theme.Accent
	end
	local out = numberAttr(model, "PowerOut")
	if out then
		local text = `+{Format.big(round(out))} power`
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

---------------------------------------------------------------- status

-- Ore kinds a waiting machine names as "<words> ore", the other kinds as they are.
local ORE_WORDS: { { string } } = { { "Raw", "dirty" }, { "Clean", "clean" }, { "Crushed", "crushed" } }
local OTHER_WORDS: { { string } } = { { "Ingot", "ingots" }, { "Alloy", "alloy" }, { "Gear", "gears" }, { "Relic", "a relic" } }

--[[
	What an idle processor waits for, from its Accepts: "Needs clean ore",
	"Needs clean or crushed ore", "Needs dirty ore", "Needs ore or ingots"
	(every ore kind is just "ore"), "Needs a relic"; "Waiting" without one.
]]
function MachineBillboard.needsText(info: MachineData.Machine?): string
	local accepts = info and info.Accepts
	if not accepts then
		return STATUS_TEXT.Waiting
	end
	local ores: { string } = {}
	for _, pair in ORE_WORDS do
		if accepts[pair[1]] then
			table.insert(ores, pair[2])
		end
	end
	local parts: { string } = {}
	if #ores == #ORE_WORDS then
		table.insert(parts, "ore")
	elseif #ores > 0 then
		table.insert(parts, table.concat(ores, " or ") .. " ore")
	end
	for _, pair in OTHER_WORDS do
		if accepts[pair[1]] then
			table.insert(parts, pair[2])
		end
	end
	if #parts == 0 then
		return STATUS_TEXT.Waiting
	end
	return "Needs " .. table.concat(parts, " or ")
end

--[[
	The status a machine's sign and stack light show, from its replicated
	attributes (a model's GetAttributes(), or MachineFxController's Attr
	with Working filled from the packed Job) and its MachineData entry; ""
	when there is nothing to say (belts, poles, generators, an idle machine
	without jobs). See the header for the order.
]]
function MachineBillboard.statusOf(attrs: { [string]: any }, info: MachineData.Machine?): string
	local status = attrs.Status
	if type(status) == "string" and status ~= "" then
		return status
	end
	if attrs.PenFull == true then
		return "PenFull"
	end
	if type(attrs.PowerSpeed) == "number" and attrs.Powered ~= true then
		return "NoPower"
	end
	local working = attrs.Working == true
	if attrs.Working == nil and attrs.Job ~= nil then
		working = MachineBillboard.decodeJob(attrs.Job).Working
	end
	local queue = attrs.Queue
	if working or (type(queue) == "number" and queue > 0) then
		return "Working"
	end
	if info and info.Time and info.Accepts and not info.NoIntake and not info.IsConveyor then
		return "Waiting"
	end
	return ""
end

-- The status row's words for a status of this model ("" = no row).
function MachineBillboard.statusText(model: Instance, status: string): string
	if status == "Waiting" then
		local id = model:GetAttribute("MachineId")
		local tier = model:GetAttribute("Tier")
		local info: MachineData.Machine? = nil
		if type(id) == "string" and MachineData.ById[id] then
			info = MachineData.info(id, if type(tier) == "number" then tier else 0)
		end
		return MachineBillboard.needsText(info)
	elseif status == "NoPower" then
		local speed = numberAttr(model, "PowerSpeed")
		return if speed then `No power: {round(math.clamp(speed, 0, 1) * 100)}%` else STATUS_TEXT.NoPower
	end
	return STATUS_TEXT[status] or status
end

--[[
	The stack light lamp for a machine (MachineBuilder.Stack.Lamps names):
	green while it works, red when it is blocked, amber when it waits or has
	no power. A generator: green while a pole takes its power, else amber.
]]
function MachineBillboard.lampOf(attrs: { [string]: any }, info: MachineData.Machine?): string
	if info and info.Behaviour == "Generator" then
		local network = attrs.Network
		return if type(network) == "string" and network ~= "" then "StackGreen" else "StackAmber"
	end
	local status = MachineBillboard.statusOf(attrs, info)
	if status == "Working" then
		return "StackGreen"
	end
	return if status ~= "" and MachineBillboard.toneOf(status) == "Blocked" then "StackRed" else "StackAmber"
end

-- A machine's stack light lamps: its direct children named like
-- MachineBuilder.Stack.Lamps (StackRed / StackAmber / StackGreen); nil
-- when it has none.
function MachineBillboard.stackLamps(model: Instance): { [string]: BasePart }?
	local lamps: { [string]: BasePart } = {}
	local found = false
	for _, name in LAMP_NAMES do
		local lamp = model:FindFirstChild(name)
		if lamp and lamp:IsA("BasePart") then
			lamps[name] = lamp
			found = true
		end
	end
	return if found then lamps else nil
end

-- Lights one lamp (Neon, its colour toned down by Stack.Glow so it glows
-- in its colour instead of blooming white); the others are plastic in
-- their own hue, dimmed by Stack.Dim (MachineBuilder's built look).
function MachineBillboard.lightStack(lamps: { [string]: BasePart }, lit: string)
	for name, lamp in lamps do
		local on = name == lit
		local color = STACK.Lamps[name] or lamp.Color
		lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		lamp.Color = color:Lerp(Color3.new(0, 0, 0), if on then STACK.Glow else STACK.Dim)
	end
end

--[[
	Whether one of YOUR machines gets the sign (the caller checks the
	owner): `status` is statusOf's answer, `distance` in studs. Busy (a
	queue, a job, a Status attribute, a full pen) within Range; any status
	within StatusRange; the Cleaning Plant's odds within OddsRange.
]]
function MachineBillboard.wants(attrs: { [string]: any }, status: string, distance: number): boolean
	if distance > MachineBillboard.Range then
		return false
	end
	local odds = attrs.QualityOdds
	if distance <= MachineBillboard.OddsRange and type(odds) == "string" and odds ~= "" then
		return true
	end
	if status ~= "" and distance <= MachineBillboard.StatusRange then
		return true
	end
	local queue = attrs.Queue
	local blocked = attrs.Status
	return (type(queue) == "number" and queue > 0)
		or attrs.Working == true
		or (type(blocked) == "string" and blocked ~= "")
		or attrs.PenFull == true
end

--[[
	Which machines keep a sign when more want one than MachineFxController
	hands out (its cap): blocked first (red: a Status, a full pen), then
	working, then no power, then waiting and the Cleaning Plant's odds
	alone (status ""). signBefore is the table.sort order: rank, then the
	nearer first.
]]
function MachineBillboard.signRank(status: string): number
	if status == "" then
		return 3
	end
	local tone = MachineBillboard.toneOf(status)
	return if tone == "Blocked" then 0 elseif tone == "Working" then 1 elseif tone == "NoPower" then 2 else 3
end

export type SignCandidate = { Status: string, Distance: number }

function MachineBillboard.signBefore(a: SignCandidate, b: SignCandidate): boolean
	local rankA, rankB = MachineBillboard.signRank(a.Status), MachineBillboard.signRank(b.Status)
	if rankA ~= rankB then
		return rankA < rankB
	end
	return a.Distance < b.Distance
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
-- compact sign; the bar and queue only while busy, under the status row's
-- place, so they never jump when a status comes or goes), the info lines,
-- then the note.
local function layout(refs: Refs)
	local noteOn = refs.Note.Text ~= ""
	local width = if noteOn then NOTE_WIDTH else WIDTH
	-- keep the bar and queue centred in a wider sign
	local shift = (width - WIDTH) / 2
	refs.Bar.Position = UDim2.fromOffset((WIDTH - BAR_WIDTH) / 2 + shift, STATUS_ROW)
	refs.PipRow.Position = UDim2.fromOffset((WIDTH - BAR_WIDTH) / 2 + shift, STATUS_ROW + 19)
	local busy = refs.Busy and not refs.Compact
	refs.Bar.Visible = busy
	refs.PipRow.Visible = busy
	local y = if refs.Compact then 0 elseif busy then HEIGHT elseif refs.StatusRow.Visible then STATUS_ROW else 0
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

	-- status row: wider than the sign, the lamp and the word centred in it
	-- (the word sizes to its text), so a long status stays on one line
	local statusRow = UIKit.new("Frame", {
		Name = "StatusRow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(NOTE_WIDTH, STATUS_ROW),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui) :: Frame
	UIKit.list(statusRow, Enum.FillDirection.Horizontal, ICON_GAP, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(ICON, ICON),
		LayoutOrder = 1,
	}, statusRow) :: Frame
	UIKit.corner(icon, ICON)
	UIKit.stroke(icon, 1.5)
	local glyph = UIKit.new("Frame", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
	}, icon) :: Frame
	local statusLabel = UIKit.label(statusRow, "", STATUS_TEXT_SIZE, {
		Name = "Status",
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		TextColor3 = Theme.Bad,
		TextWrapped = false,
		Visible = false,
	})
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(MachineBillboard.StatusWidth, 18) }, statusLabel)

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
		StatusRow = statusRow,
		Icon = icon,
		Glyph = glyph,
		Status = statusLabel,
		Note = note,
		Power = power,
		Detail = detail,
		Model = model,
		Compact = compact,
		-- a new sign keeps the bar's place until update() says it is idle
		Busy = not compact,
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

-- Reads the info lines from the model's attributes again (writes only
-- what changed). While the status row says "No power: 60%", it keeps that
-- figure fresh and the power line (the same news) stays hidden.
function MachineBillboard.refreshInfo(refs: Refs)
	refs.InfoAt = os.clock() + INFO_INTERVAL
	local shown = refs.Shown
	local power, color = MachineBillboard.powerLine(refs.Model)
	if shown.Status == "NoPower" then
		power = ""
		local text = MachineBillboard.statusText(refs.Model, "NoPower")
		if refs.Status.Text ~= text then
			refs.Status.Text = text
		end
	end
	local detail = MachineBillboard.detailLine(refs.Model)
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

-- Draws a glyph (GLYPHS) on the lamp in `ink`, replacing the one there.
local function drawGlyph(holder: Frame, name: string, ink: Color3)
	holder:ClearAllChildren()
	local bars = GLYPHS[name]
	if not bars then
		return
	end
	for i, bar in bars do
		UIKit.new("Frame", {
			Name = name .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(bar[1], bar[2]),
			Size = UDim2.fromOffset(bar[3], bar[4]),
			Rotation = bar[5],
			BackgroundColor3 = ink,
			BorderSizePixel = 0,
		}, holder)
	end
end

-- The status row for a status ("" hides it): the lamp, its glyph, the word.
local function setStatus(refs: Refs, status: string)
	local text = MachineBillboard.statusText(refs.Model, status)
	local on = text ~= ""
	refs.Status.Text = text
	refs.Status.Visible = on
	refs.StatusRow.Visible = on
	if on then
		local look = lookOf(status)
		refs.Status.TextColor3 = look.Text
		refs.Icon.BackgroundColor3 = look.Lamp
		drawGlyph(refs.Glyph, look.Glyph, look.Ink)
	end
end

--[[
	progress 0..1 of the running job; status is statusOf's answer ('' |
	'Working' | 'Waiting' | 'NoPower' | the machine's Status attribute:
	'OutputBlocked', 'TooManyItems', 'NeedsOtherOre' | 'PenFull'). The bar
	and queue rows show while busy (progress, a queue or finished items).
	The info lines follow the model's attributes (refreshInfo, every
	INFO_INTERVAL seconds, and when the status changes).
]]
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
	local relayout = false
	local busy = pixels > 0 or queue > 0 or outCount > 0
	if busy ~= refs.Busy then
		refs.Busy = busy
		relayout = true
	end
	local statusChanged = status ~= shown.Status
	if statusChanged then
		shown.Status = status
		setStatus(refs, status)
		relayout = true
	end
	if relayout then
		layout(refs)
	end
	if statusChanged or os.clock() >= refs.InfoAt then
		MachineBillboard.refreshInfo(refs)
	end
end

--[[
	A "FULL" (or "BUSY") pop for a hopper that refused a dropped item: a
	red chip on a BillboardGui adorned to `adornee` (an invisible part the
	caller moves to the hopper), shown on top of the world, Enabled false
	until the caller pops it. Scale is the chip's UIScale; Strokes are
	every outline to fade with it.
]]
export type Pop = { Gui: BillboardGui, Chip: TextLabel, Scale: UIScale, Strokes: { UIStroke } }

function MachineBillboard.buildPop(adornee: BasePart): Pop
	local gui = UIKit.new("BillboardGui", {
		Name = MachineBillboard.PopName,
		Size = UDim2.fromOffset(110, 44),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 80,
		ResetOnSpawn = false,
		Enabled = false,
		Adornee = adornee,
	}, adornee) :: BillboardGui
	local chip = UIKit.chip(gui, "FULL", Theme.Bad, {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(84, 32),
		FontFace = Theme.TitleFont,
		TextSize = 22,
	})
	local scale = UIKit.new("UIScale", { Scale = 1 }, chip) :: UIScale
	local strokes: { UIStroke } = {}
	for _, child in chip:GetChildren() do
		if child:IsA("UIStroke") then
			table.insert(strokes, child)
		end
	end
	return { Gui = gui, Chip = chip, Scale = scale, Strokes = strokes }
end

-- The pop's words for a refusal reason ("Busy" -> BUSY, anything else FULL).
function MachineBillboard.popText(reason: any): string
	return if reason == "Busy" then "BUSY" else "FULL"
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
