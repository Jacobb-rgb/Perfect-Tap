--[[
	NightShiftView: the "While you were away" window (Night Shift, owner
	2026-11-07, his picture without the golems; the Machines tile: what the
	machines made from the Ore Feeder's ore, NightShiftService). Built once,
	filled per return; NightShiftController shows it and
	talks to the server. Designed for 720 units of height like every window
	(Gui.Scale = HudController.uiScale); the buttons are 72 units tall (44 pt on a
	phone).

	  fill(refs, payload)   OpenUI "Offline" { Amount, Seconds, Hours, Rate,
	                        Made?, Why?, Crate?, PenFull? } (PodiumService,
	                        NightShiftService)
	  setPrize(refs, result) the opened crate (NightCrateResult)
	  setOpening(refs, on)  Open Crate waits for the server
	The texts are pure functions (specced). The coin and the chest need no
	upload (Pop.coin, a little chest of parts in a ViewportFrame).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared.Config.ArtifactConfig)
local NightShiftConfig = require(Shared.Config.NightShiftConfig)
local Format = require(Shared.Util.Format)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local Pop = require(script.Parent.Pop)
local UIKit = require(script.Parent.UIKit)

local NightShiftView = {}

NightShiftView.GuiName = "TerraForgeNightShift"
NightShiftView.Size = Vector2.new(700, 516)
NightShiftView.MaxRows = 5
-- why the machines made nothing (NightShiftService's Why)
NightShiftView.Why = {
	NoFeeder = "Get an Ore Feeder: your machines work its ore while you're away.",
	Empty = "Your Ore Feeder was empty: fill it before you go.",
	NoMachines = "Put machines after your Ore Feeder: they work its ore while you're away.",
	PenFull = "Your Ore Pen was full: make room so your machines can work at night.",
	Nothing = "Your machines had nothing to do with the feeder's ore.",
} :: { [string]: string }
NightShiftView.WhyDefault = "Your machines work the Ore Feeder's ore while you're away."
NightShiftView.Band = 64
NightShiftView.ButtonHeight = 72
NightShiftView.CloseHit = 72 -- units: what the X takes (44 pt on a phone; it draws smaller)
NightShiftView.OddsSize = 18 -- units: at least 10 pt on a phone

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Close: TextButton,
	Time: TextLabel,
	Bar: GuiObject,
	Coins: TextLabel,
	CrateCard: Frame,
	Machines: TextLabel,
	Rows: Frame,
	Empty: TextLabel,
	CrateTitle: TextLabel,
	CrateText: TextLabel,
	CrateCount: GuiObject,
	CrateOdds: TextLabel,
	Collect: GuiButton,
	Open: GuiButton,
}

---------------------------------------------------------------- texts

-- "Your podiums kept earning at 25% · max 8 h"
function NightShiftView.barText(rate: number, hours: number): string
	return `Your podiums kept earning at {math.floor(rate * 100 + 0.5)}% · max {hours} h`
end

-- "+12 bars" / "+5 items" (what went into the pen)
function NightShiftView.machinesText(made: any): string
	local total = if type(made) == "table" then tonumber(made.Total) or 0 else 0
	local bars = if type(made) == "table" then tonumber(made.Bars) or 0 else 0
	if total > 0 and bars < total then
		return if total == 1 then "+1 item" else `+{total} items`
	end
	return if bars == 1 then "+1 bar" else `+{bars} bars`
end

function NightShiftView.whyText(why: any): string
	return if type(why) == "string" and NightShiftView.Why[why] then NightShiftView.Why[why] else NightShiftView.WhyDefault
end

-- How much of the longest absence that counts was used.
function NightShiftView.barFraction(seconds: number, hours: number): number
	return math.clamp(seconds / math.max(hours * 3600, 1), 0, 1)
end

-- The crate's small line before it is opened.
function NightShiftView.crateText(waiting: boolean, penFull: boolean): string
	if not waiting then
		return "Once a day, after 1 h away"
	end
	return if penFull then "Pen full: ores pay coins" else "Free once a day"
end

-- What the opened crate says: its big line and the small one.
function NightShiftView.prizeText(result: any): (string, string)
	if type(result) ~= "table" or not result.Ok then
		return "NIGHT CRATE", "No crate waits right now"
	end
	if result.Prize == "Ores" then
		local ores = tonumber(result.Ores) or 0
		local amount = tonumber(result.Amount) or 0
		if ores == 0 then
			return `+{Format.money(amount)}`, "Your pen was full: the ores in coins"
		end
		local big = if ores == 1 then "1 dirty ore" else `{ores} dirty ores`
		return big, if amount > 0 then `In your pen, full now: +{Format.money(amount)}` else "In your pen"
	elseif result.Prize == "Relic" then
		local artifact = ArtifactConfig.ById[result.Artifact]
		return "A relic!", if artifact then artifact.Name else ""
	end
	return `+{Format.money(tonumber(result.Amount) or 0)}`, "Coins"
end

---------------------------------------------------------------- building

-- The little chest on the crate card (needs no upload): a dozen parts, shown in a ViewportFrame.
local function chestModel(): Model
	local model = Instance.new("Model")
	model.Name = "NightChest"
	local function part(cf: CFrame, size: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CFrame = cf
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = model
		return p
	end
	local wood = Color3.fromRGB(150, 84, 40)
	local dark = Color3.fromRGB(104, 56, 28)
	local gold = Color3.fromRGB(255, 200, 60)
	part(CFrame.new(0, 0.6, 0), Vector3.new(3, 1.2, 2), wood)
	part(CFrame.new(0, 1.22, 0), Vector3.new(3.1, 0.14, 2.1), dark)
	part(CFrame.new(0, 1.45, 1.05) * CFrame.Angles(math.rad(50), 0, 0), Vector3.new(3, 1.1, 0.26), wood)
	part(CFrame.new(0, 1.4, 0), Vector3.new(2.7, 0.3, 1.7), gold)
	for _, x in { -1, 1 } do
		part(CFrame.new(x, 0.62, -0.03), Vector3.new(0.3, 1.3, 2.1), gold)
	end
	part(CFrame.new(0, 0.95, -1.05), Vector3.new(0.5, 0.6, 0.14), gold)
	for k, at in { Vector3.new(-0.7, 1.62, -0.3), Vector3.new(0.1, 1.68, 0.2), Vector3.new(0.7, 1.6, -0.25) } do
		part(CFrame.new(at) * CFrame.Angles(0.3 * k, 0.5 * k, 0), Vector3.new(0.6, 0.16, 0.6), Color3.fromRGB(255, 226, 110))
	end
	return model
end

-- An item's picture (a live 3D model, as the backpack shows it).
local function picture(parent: Instance, desc: any, size: UDim2, position: UDim2)
	local name = `item_{desc.K}_{desc.O}`
	local ok, model = pcall(ItemBuilder.display, desc, CFrame.new(), name)
	Pop.model(parent, name, 10, if ok then model else nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		ZIndex = 7,
	}, Vector3.new(-0.5, 0.55, -1))
end

-- The pieces the machines made (best first), or why there are none.
local function fillRows(refs: Refs, made: any, why: any)
	for _, child in refs.Rows:GetChildren() do
		child:Destroy()
	end
	local list = if type(made) == "table" and type(made.List) == "table" then made.List else {}
	refs.Empty.Visible = #list == 0
	refs.Empty.Text = NightShiftView.whyText(why)
	refs.Machines.Text = NightShiftView.machinesText(made)
	for k = 1, math.min(#list, NightShiftView.MaxRows) do
		local row = list[k]
		local cell = Pop.well(refs.Rows, {
			Name = `Row{k}`,
			Position = UDim2.fromOffset((k - 1) * 78, 4),
			Size = UDim2.fromOffset(72, 78),
		})
		picture(cell, { K = row.K, O = row.O, G = row.G }, UDim2.fromOffset(60, 60), UDim2.new(0.5, 0, 0.5, -6))
		Pop.text(cell, `x{tonumber(row.N) or 0}`, 20, {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = UDim2.new(1, -8, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 8,
		})
	end
end

function NightShiftView.build(): Refs
	local gui = UIKit.screen(NightShiftView.GuiName, 30)
	gui.Enabled = false
	gui.IgnoreGuiInset = true
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	local window =
		Pop.window(gui, "Night Shift", NightShiftView.Size, NightShiftView.Band, Pop.windowPaint(NightShiftView.GuiName, "Violet"))
	local inner = UIKit.new("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 1, -20),
		ZIndex = 3,
	}, window.Body)

	Pop.text(inner, "While you were away", 28, {
		Name = "Lead",
		Size = UDim2.new(0.7, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	})
	local time = Pop.text(inner, "", 32, {
		Name = "Time",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.3, 0, 0, 36),
		TextColor3 = Color3.fromRGB(255, 214, 70),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
	})
	local bar = Pop.bar(inner, 0, "Sky", Vector2.new(NightShiftView.Size.X - 40, 36), "", {
		Position = UDim2.fromOffset(0, 44),
	})

	-- the podiums' coins
	local green = Color3.fromRGB(110, 230, 90)
	local tile = Pop.well(inner, {
		Name = "Podiums",
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(0.5, -6, 0, 132),
	})
	Pop.border(tile, 3, green)
	Pop.coin(tile, 72, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 56, 0.5, 0),
		ZIndex = 7,
	})
	Pop.text(tile, "Podiums", 24, {
		Name = "Title",
		Position = UDim2.fromOffset(104, 22),
		Size = UDim2.new(1, -112, 0, 30),
		ZIndex = 6,
	})
	local coins = Pop.text(tile, "", 38, {
		Name = "Value",
		Position = UDim2.fromOffset(104, 58),
		Size = UDim2.new(1, -112, 0, 48),
		TextColor3 = green,
		ZIndex = 6,
	})

	-- the crate
	local card = Pop.well(inner, {
		Name = "Crate",
		Position = UDim2.new(0.5, 6, 0, 92),
		Size = UDim2.new(0.5, -6, 0, 132),
		ClipsDescendants = true,
	})
	Pop.face(card, "Violet", 8, false)
	Pop.rays(card, UDim2.fromScale(0.2, 0.5), 10, 320, 0.88, 3)
	Pop.model(card, "night_chest", 10, chestModel(), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 56, 0, 50),
		Size = UDim2.fromOffset(90, 90),
		ZIndex = 7,
	}, Vector3.new(-0.7, 0.6, -1))
	local crateTitle = Pop.text(card, "NIGHT CRATE", 23, {
		Name = "Title",
		Position = UDim2.fromOffset(106, 6),
		Size = UDim2.new(1, -112, 0, 28),
		ZIndex = 7,
	})
	local crateText = Pop.text(card, NightShiftView.crateText(true, false), 18, {
		Name = "Text",
		Position = UDim2.fromOffset(106, 34),
		Size = UDim2.new(1, -112, 0, 40),
		TextColor3 = Color3.fromRGB(190, 250, 110),
		TextWrapped = true,
		ZIndex = 7,
	})
	local count = Pop.tag(card, "x1", "Amber", Vector2.new(54, 32), {
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0, 56, 0, 92),
		ZIndex = 7,
	})
	local odds = Pop.text(card, NightShiftConfig.oddsText(), NightShiftView.OddsSize, {
		Name = "Odds",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 106, 1, -6),
		Size = UDim2.new(1, -112, 0, 50),
		TextWrapped = true,
		ZIndex = 7,
	})

	-- the machines: what they made from the Ore Feeder's ore
	local gold = Color3.fromRGB(255, 196, 70)
	local machinesTile = Pop.well(inner, {
		Name = "MachinesTile",
		Position = UDim2.fromOffset(0, 236),
		Size = UDim2.new(1, 0, 0, 108),
	})
	Pop.border(machinesTile, 3, gold)
	picture(machinesTile, { K = "Ingot", O = "Gold", G = "Clean" }, UDim2.fromOffset(74, 74), UDim2.new(0, 52, 0.5, 0))
	Pop.text(machinesTile, "Machines", 24, {
		Name = "Title",
		Position = UDim2.fromOffset(100, 12),
		Size = UDim2.new(0.34, -100, 0, 30),
		ZIndex = 6,
	})
	local machines = Pop.text(machinesTile, "", 36, {
		Name = "Value",
		Position = UDim2.fromOffset(100, 46),
		Size = UDim2.new(0.34, -100, 0, 46),
		TextColor3 = gold,
		ZIndex = 6,
	})
	local rows = UIKit.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.36, 0, 0, 11),
		Size = UDim2.new(0.64, -12, 0, 86),
		ZIndex = 5,
	}, machinesTile)
	local empty = Pop.text(machinesTile, NightShiftView.WhyDefault, 19, {
		Name = "Empty",
		Position = UDim2.new(0.36, 0, 0, 8),
		Size = UDim2.new(0.64, -16, 0, 92),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	})

	local buttonSize = Vector2.new(300, NightShiftView.ButtonHeight)
	local collect = Pop.button(inner, "Collect", "Green", buttonSize, {
		Name = "Collect",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -8, 1, 0),
	})
	local open = Pop.button(inner, "Open Crate", "Orange", buttonSize, {
		Name = "Open",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 8, 1, 0),
	})
	-- the X keeps its size; what a thumb hits is bigger; a gamepad closes with B
	local x = window.Close :: GuiObject
	x.Selectable = false
	local closeHit = UIKit.new("TextButton", {
		Name = "CloseHit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Selectable = false,
		Size = UDim2.fromOffset(NightShiftView.CloseHit, NightShiftView.CloseHit),
		Text = "",
		ZIndex = x.ZIndex + 2,
	}, x)
	-- a gamepad stays in the window
	local root = window.Root
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	return {
		Gui = gui,
		Dim = dim,
		Panel = window.Root,
		Close = closeHit,
		Time = time,
		Bar = bar,
		Coins = coins,
		CrateCard = card,
		Machines = machines,
		Rows = rows,
		Empty = empty,
		CrateTitle = crateTitle,
		CrateText = crateText,
		CrateCount = count,
		CrateOdds = odds,
		Collect = collect,
		Open = open,
	}
end

-- Open Crate only while one waits; Collect alone stands in the middle.
local function setCrate(refs: Refs, waiting: boolean, penFull: boolean)
	refs.Open.Visible = waiting
	refs.Collect.AnchorPoint = if waiting then Vector2.new(1, 1) else Vector2.new(0.5, 1)
	refs.Collect.Position = if waiting then UDim2.new(0.5, -8, 1, 0) else UDim2.new(0.5, 0, 1, 0)
	refs.CrateCount.Visible = waiting
	refs.CrateOdds.Visible = true
	refs.CrateTitle.Text = "NIGHT CRATE"
	refs.CrateText.Text = NightShiftView.crateText(waiting, penFull)
end

function NightShiftView.fill(refs: Refs, payload: { [string]: any })
	local seconds = tonumber(payload.Seconds) or 0
	local hours = tonumber(payload.Hours) or 8
	local rate = tonumber(payload.Rate) or 0.25
	refs.Time.Text = Format.seconds(seconds)
	Pop.setBar(refs.Bar, NightShiftView.barFraction(seconds, hours), NightShiftView.barText(rate, hours))
	refs.Coins.Text = "+" .. Format.money(tonumber(payload.Amount) or 0)
	setCrate(refs, payload.Crate == true, payload.PenFull == true)
	fillRows(refs, payload.Made, payload.Why)
end

function NightShiftView.setOpening(refs: Refs, on: boolean)
	refs.Open.Active = not on
	refs.Open.AutoButtonColor = not on
	local label = refs.Open:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = if on then "Opening..." else "Open Crate"
	end
end

function NightShiftView.setPrize(refs: Refs, result: any)
	local big, small = NightShiftView.prizeText(result)
	setCrate(refs, false, false)
	refs.CrateTitle.Text = big
	refs.CrateText.Text = small
	refs.CrateOdds.Visible = false
end

return NightShiftView
