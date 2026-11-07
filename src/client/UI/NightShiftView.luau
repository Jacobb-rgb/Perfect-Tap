--[[
	NightShiftView: the "While you were away" window (Night Shift, owner
	2026-11-07, his picture without the golems). Built once, filled per return;
	NightShiftController shows it and talks to the server. Designed for 720
	units of height like every window (Gui.Scale = HudController.uiScale); the
	buttons are 72 units tall (44 pt on a phone).

	  fill(refs, payload)   OpenUI "Offline" { Amount, Seconds, Hours, Rate,
	                        Made?, Crate? } (PodiumService, NightShiftService)
	  setPrize(refs, result) the opened crate (NightCrateResult)
	  setOpening(refs, on)  Open Crate waits for the server
	The texts are pure functions (specced).
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
NightShiftView.Size = Vector2.new(700, 500)
NightShiftView.Band = 64
NightShiftView.ButtonHeight = 72
NightShiftView.MaxRows = 5

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Close: GuiButton,
	Time: TextLabel,
	Bar: GuiObject,
	Coins: TextLabel,
	Machines: TextLabel,
	Rows: Frame,
	Empty: TextLabel,
	CrateCard: Frame,
	CrateTitle: TextLabel,
	CrateText: TextLabel,
	CrateCount: GuiObject,
	CrateOdds: TextLabel,
	Collect: GuiButton,
	CollectHolder: GuiObject,
	Open: GuiButton,
	OpenHolder: GuiObject,
}

---------------------------------------------------------------- texts

-- "Your base kept working at 25% · max 8 h"
function NightShiftView.barText(rate: number, hours: number): string
	return `Your base kept working at {math.floor(rate * 100 + 0.5)}% · max {hours} h`
end

-- How much of the longest absence that counts was used.
function NightShiftView.barFraction(seconds: number, hours: number): number
	return math.clamp(seconds / math.max(hours * 3600, 1), 0, 1)
end

-- "+46 bars", or "+12 items" while some aren't bars yet (a line without a furnace).
function NightShiftView.machinesText(made: any): string
	local total = if type(made) == "table" then tonumber(made.Total) or 0 else 0
	local bars = if type(made) == "table" then tonumber(made.Bars) or 0 else 0
	return if total > 0 and bars < total then `+{total} items` else `+{bars} bars`
end

-- What the opened crate says: its big line and the small one.
function NightShiftView.prizeText(result: any): (string, string)
	if type(result) ~= "table" or not result.Ok then
		return "NIGHT CRATE", "Try again next time"
	end
	if result.Prize == "Ores" then
		local ores = tonumber(result.Ores) or 0
		local amount = tonumber(result.Amount) or 0
		return `{ores} dirty ores`, if amount > 0 then `In your pen, and +{Format.money(amount)}: it is full` else "In your pen"
	elseif result.Prize == "Relic" then
		local artifact = ArtifactConfig.ById[result.Artifact]
		return "A relic!", if artifact then artifact.Name else ""
	end
	return `+{Format.money(tonumber(result.Amount) or 0)}`, "Coins"
end

---------------------------------------------------------------- building

local function tile(parent: Instance, name: string, title: string, color: Color3, x: UDim, width: UDim): (Frame, TextLabel)
	local frame = Pop.well(parent, {
		Name = name,
		Position = UDim2.new(x, UDim.new(0, 92)),
		Size = UDim2.new(width, UDim.new(0, 98)),
	})
	Pop.border(frame, 3, color)
	Pop.text(frame, title, 22, {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(96, 8),
		Size = UDim2.new(1, -104, 0, 28),
		ZIndex = 6,
	})
	local value = Pop.text(frame, "", 38, {
		Name = "Value",
		Position = UDim2.fromOffset(96, 40),
		Size = UDim2.new(1, -104, 0, 48),
		TextColor3 = color,
		ZIndex = 6,
	})
	return frame, value
end

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
	local body = window.Body
	local inner = UIKit.new("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 1, -20),
		ZIndex = 3,
	}, body)

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

	local coinTile, coins = tile(inner, "Podiums", "Podiums", Color3.fromRGB(110, 230, 90), UDim.new(0, 0), UDim.new(0.5, -6))
	Pop.bandIcon(coinTile, "coins", 72, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 50, 0.5, 0),
		ZIndex = 7,
	})
	local barTile, machines = tile(inner, "MachinesTile", "Machines", Color3.fromRGB(255, 196, 70), UDim.new(0.5, 6), UDim.new(0.5, -6))
	picture(barTile, { K = "Ingot", O = "Gold", G = "Clean" }, UDim2.fromOffset(86, 86), UDim2.new(0, 50, 0.5, 0))

	-- Collected for you
	local collected = Pop.well(inner, {
		Name = "Collected",
		Position = UDim2.fromOffset(0, 202),
		Size = UDim2.new(0.58, -6, 0, 132),
	})
	Pop.text(collected, "Collected for you", 22, {
		Name = "Title",
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	})
	local rows = UIKit.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 0, 86),
		ZIndex = 5,
	}, collected)
	local empty = Pop.text(collected, "Your machines finish ore from the pen when the sorting billboard is on.", 19, {
		Name = "Empty",
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -28, 0, 84),
		TextWrapped = true,
		ZIndex = 6,
	})

	-- the crate
	local card = Pop.well(inner, {
		Name = "Crate",
		Position = UDim2.new(0.58, 6, 0, 202),
		Size = UDim2.new(0.42, -6, 0, 132),
		ClipsDescendants = true,
	})
	Pop.face(card, "Violet", 8, false)
	Pop.rays(card, UDim2.fromScale(0.2, 0.5), 10, 320, 0.88, 3)
	Pop.bandIcon(card, "coin_chest", 84, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 50, 0, 50),
		ZIndex = 7,
	})
	local crateTitle = Pop.text(card, "NIGHT CRATE", 23, {
		Name = "Title",
		Position = UDim2.fromOffset(98, 6),
		Size = UDim2.new(1, -104, 0, 28),
		ZIndex = 7,
	})
	local crateText = Pop.text(card, "Free every night", 18, {
		Name = "Text",
		Position = UDim2.fromOffset(98, 34),
		Size = UDim2.new(1, -104, 0, 40),
		TextColor3 = Color3.fromRGB(190, 250, 110),
		TextWrapped = true,
		ZIndex = 7,
	})
	local count = Pop.tag(card, "x1", "Amber", Vector2.new(54, 32), {
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0, 50, 0, 90),
		ZIndex = 7,
	})
	local odds = Pop.text(card, NightShiftConfig.oddsText(), 15, {
		Name = "Odds",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 98, 1, -6),
		Size = UDim2.new(1, -104, 0, 50),
		TextWrapped = true,
		ZIndex = 7,
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
	return {
		Gui = gui,
		Dim = dim,
		Panel = window.Root,
		Close = window.Close :: any,
		Time = time,
		Bar = bar,
		Coins = coins,
		Machines = machines,
		Rows = rows,
		Empty = empty,
		CrateCard = card,
		CrateTitle = crateTitle,
		CrateText = crateText,
		CrateCount = count,
		CrateOdds = odds,
		Collect = collect,
		CollectHolder = collect,
		Open = open,
		OpenHolder = open,
	}
end

local function fillRows(refs: Refs, made: any)
	for _, child in refs.Rows:GetChildren() do
		child:Destroy()
	end
	local list = if type(made) == "table" and type(made.List) == "table" then made.List else {}
	refs.Empty.Visible = #list == 0
	for k = 1, math.min(#list, NightShiftView.MaxRows) do
		local row = list[k]
		local cell = Pop.well(refs.Rows, {
			Name = `Row{k}`,
			Position = UDim2.fromOffset((k - 1) * 72, 4),
			Size = UDim2.fromOffset(66, 78),
		})
		picture(cell, { K = row.K, O = row.O, G = row.G }, UDim2.fromOffset(60, 60), UDim2.new(0.5, 0, 0.5, -6))
		local label = Pop.text(cell, `x{tonumber(row.N) or 0}`, 20, {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = UDim2.new(1, -8, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 8,
		})
		Pop.shadow(label, 2)
	end
end

-- Open Crate only while one waits; Collect alone stands in the middle.
local function setCrate(refs: Refs, waiting: boolean)
	refs.Open.Visible = waiting
	refs.Collect.AnchorPoint = if waiting then Vector2.new(1, 1) else Vector2.new(0.5, 1)
	refs.Collect.Position = if waiting then UDim2.new(0.5, -8, 1, 0) else UDim2.new(0.5, 0, 1, 0)
	refs.CrateCount.Visible = waiting
	refs.CrateOdds.Visible = true
	refs.CrateTitle.Text = "NIGHT CRATE"
	refs.CrateText.Text = if waiting then "Free every night" else "After a night away"
end

function NightShiftView.fill(refs: Refs, payload: { [string]: any })
	local seconds = tonumber(payload.Seconds) or 0
	local hours = tonumber(payload.Hours) or 8
	local rate = tonumber(payload.Rate) or 0.25
	refs.Time.Text = Format.seconds(seconds)
	Pop.setBar(refs.Bar, NightShiftView.barFraction(seconds, hours), NightShiftView.barText(rate, hours))
	refs.Coins.Text = "+" .. Format.money(tonumber(payload.Amount) or 0)
	refs.Machines.Text = NightShiftView.machinesText(payload.Made)
	fillRows(refs, payload.Made)
	setCrate(refs, payload.Crate == true)
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
	setCrate(refs, false)
	refs.CrateTitle.Text = big
	refs.CrateText.Text = small
	refs.CrateOdds.Visible = false
end

return NightShiftView
