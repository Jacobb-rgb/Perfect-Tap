--[[
	NightShiftView: the "While you were away" window (Night Shift, owner
	2026-11-07, his picture without the golems; the machines' tile comes with
	the feeder). Built once, filled per return; NightShiftController shows it and
	talks to the server. Designed for 720 units of height like every window
	(Gui.Scale = HudController.uiScale); the buttons are 72 units tall (44 pt on a
	phone).

	  fill(refs, payload)   OpenUI "Offline" { Amount, Seconds, Hours, Rate,
	                        Crate?, PenFull? } (PodiumService, NightShiftService)
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
local Pop = require(script.Parent.Pop)
local UIKit = require(script.Parent.UIKit)

local NightShiftView = {}

NightShiftView.GuiName = "TerraForgeNightShift"
NightShiftView.Size = Vector2.new(700, 400)
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
