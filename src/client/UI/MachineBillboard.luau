--[[
	MachineBillboard: the small sign above YOUR busy machines.

	   Output blocked            status line, only when something is wrong
	  [==========-----]          job progress, in the ore's colour
	   o o o .  FULL  2 ready    queue (the item being worked counts), a red
	                             FULL chip, finished items waiting to leave

	It hangs on the machine's Status attachment and hides itself beyond
	45 studs. MachineFxController decides which machines get one (at most
	12) and calls update() every frame; update() writes only what changed.
	Pure builder: it only creates and changes Instances (no services, no
	events), so the Lune tests can run it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UITheme"))
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
	-- what is on screen now (update() skips unchanged values)
	Shown: {
		Pixels: number,
		Queue: number,
		QueueMax: number,
		OutCount: number,
		Status: string,
		Color: Color3,
	},
}

local MAX_DISTANCE = 45
local WIDTH = 170
local BAR_WIDTH = 150
local MAX_PIPS = 8
local PIP = 10
local PIP_STEP = 13

local STATUS_TEXT: { [string]: string } = {
	OutputBlocked = "Output blocked",
	TooManyItems = "Too many loose items",
}

-- Builds the sign on the model's Status attachment (or its Base).
function MachineBillboard.attach(model: Model): Refs
	local base = model.PrimaryPart
	local status = base and base:FindFirstChild("Status")
	local anchor: Instance = if status and status:IsA("Attachment") then status else (base or model)
	local gui = UIKit.new("BillboardGui", {
		Name = "MachineBillboard",
		Size = UDim2.fromOffset(WIDTH, 58),
		StudsOffset = Vector3.new(0, 0.6, 0),
		MaxDistance = MAX_DISTANCE,
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		ClipsDescendants = false,
	}) :: BillboardGui
	if anchor:IsA("Attachment") or anchor:IsA("BasePart") then
		gui.Adornee = anchor
	end

	local statusLabel = UIKit.label(gui, "", 15, {
		Name = "Status",
		Size = UDim2.fromOffset(WIDTH, 18),
		Position = UDim2.fromOffset(0, 0),
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

	gui.Parent = anchor
	return {
		Gui = gui,
		Bar = bar,
		Fill = fill,
		PipRow = row,
		Pips = {},
		Full = full,
		Ready = ready,
		Status = statusLabel,
		Shown = { Pixels = 0, Queue = -1, QueueMax = -1, OutCount = -1, Status = "", Color = Theme.Accent },
	}
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
-- attribute ('' | 'OutputBlocked' | 'TooManyItems').
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
end

function MachineBillboard.detach(refs: Refs)
	refs.Gui:Destroy()
end

return MachineBillboard
