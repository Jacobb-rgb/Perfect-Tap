--[[
	MachineUpgradeView: a machine's upgrades, at the machine (owner 2026-11-07:
	"když na ten stroj klikneš, E ... se ti otevře tabulka a tam bude upgrade toho
	daného stroje a nějaké krátké stats, proč se to vyplatí"). One row per upgrade:
	its level, what changes (now > next), a short why, and the price on a coin
	button (MAX at the top). The same items and prices as the server's
	(EconomyConfig.TechShop: Speed / Quality / Tier for every machine of that type,
	Bellows for every machine), bought with ShopBuy at the machine (ShopService:
	"Machine"). The texts are pure (rows, specced); MachineUpgradeController shows it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MachineData = require(Shared.Config.MachineData)
local Format = require(Shared.Util.Format)
local Pop = require(script.Parent.Pop)
local UIKit = require(script.Parent.UIKit)

local MachineUpgradeView = {}

MachineUpgradeView.GuiName = "TerraForgeMachineUpgrade"
MachineUpgradeView.Width = 640
MachineUpgradeView.Band = 64
MachineUpgradeView.RowHeight = 112
MachineUpgradeView.RowGap = 12
MachineUpgradeView.ButtonSize = Vector2.new(190, 72) -- 44 pt on a phone
MachineUpgradeView.CloseHit = 72
-- a row's texts: their sizes and their boxes (share of the row's width)
MachineUpgradeView.Sizes = { Title = 22, Level = 20, Change = 18, Why = 18 }
MachineUpgradeView.Boxes = { Title = 0.4, Level = 0.22, Change = 0.62, Why = 0.62 }
-- what a refused BUY says on its row (short: it fits the row; else Retry)
MachineUpgradeView.Reasons = {
	NoCoins = "Not enough coins",
	Max = "Already at the top",
	Stale = "Try again",
	AtMachine = "Go back to the machine",
	TooFar = "Go back to the machine",
	Busy = "Wait a moment",
	Retry = "Not bought, try again",
	NoAnswer = "No answer, try again",
	Bought = "BOUGHT!",
} :: { [string]: string }
MachineUpgradeView.CloseRange = 14 -- studs from the machine; the server sells within ShopService.MachineRange (18)

-- Why a Speed level pays off, per machine (else Generic).
MachineUpgradeView.Why = {
	ClayFurnace = "Every bar comes out faster",
	Crusher = "Crushes ore faster",
	AutoCleaner = "Cleans ore faster",
	IronBox = "Sorts ore faster",
	Splitter = "Splits items faster",
	Sorter = "Sorts items faster",
	RobotArm = "Moves items faster",
	Polisher = "Polishes faster",
	CrystalExtractor = "Finds shards faster",
	AlloyFurnace = "Makes alloys faster",
	RestorationTable = "Restores relics faster",
	Generic = "Works faster",
	Power = "Powers more machines",
	Quality = "Better grades pay more",
	Bellows = "All machines work faster",
} :: { [string]: string }

export type Row = {
	Item: string, -- the ShopBuy Item
	Title: string,
	Level: string, -- "LV 1 / 5", "MAX"
	Change: string, -- "3.5 s → 3.0 s"
	Why: string,
	Price: number?, -- the next level's price (nil: at the top)
	Next: number?, -- the level being bought (ShopBuy Level)
	Affordable: boolean,
}

local function num(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

local function seconds(s: number): string
	return string.format("%.1f s", s)
end

local function tierOf(state: any, machineId: string): number
	return MachineData.tierOf(state.MachineUpgrades, machineId)
end

local function bellowsOf(state: any): number
	local upgrades = if type(state.Upgrades) == "table" then state.Upgrades else {}
	return num(upgrades.Bellows)
end

-- The grade a Quality level makes most likely (from the best down, the first with a chance).
local function topGrade(odds: { [string]: number }): (string, number)
	for _, grade in { "Flawless", "Pristine", "Clean", "Rough" } do
		local chance = odds[grade]
		if chance and chance > 0 then
			return grade, chance
		end
	end
	return "Rough", 1
end

local function pct(x: number): string
	return `{math.floor(x * 100 + 0.5)}%`
end

local function row(entry: any, state: any, coins: number, title: string, change: string, why: string): Row
	local level, max = EconomyConfig.techLevel(entry, state)
	local price = if level < max then (entry.Prices :: { number })[level + 1] else nil
	return {
		Item = entry.Item,
		Title = title,
		Level = if price then `LV {level} / {max}` else "MAX",
		Change = change,
		Why = why,
		Price = price,
		Next = if price then level + 1 else nil,
		Affordable = price ~= nil and coins >= price,
	}
end

-- "now → next", or just "now" at the top level.
local function change(now: string, after: string, top: boolean): string
	return if top then now else `{now} → {after}`
end

-- How many times faster a Speed level makes a machine without a job time ("x1.14 speed").
local function times(level: number): string
	return string.format("x%.2f", 1 / MachineData.speedMult(level))
end

local function power(x: number): string
	return tostring(math.floor(x + 0.5))
end

-- Every upgrade of `machineId` for the player in `state` (the State snapshot) with `coins`.
function MachineUpgradeView.rows(machineId: string, state: any, coins: number): { Row }
	local machine = MachineData.ById[machineId]
	local list: { Row } = {}
	if not machine then
		return list
	end
	local safe = if type(state) == "table" then state else {}
	local tier = tierOf(safe, machineId)
	local info = MachineData.info(machineId, tier)
	local bellows = bellowsOf(safe)
	for _, kind in MachineData.UpgradeKinds do
		local entry = EconomyConfig.techItem(`Upgrade:{machineId}:{kind}`)
		if entry then
			local level, max = EconomyConfig.techLevel(entry, safe)
			local top = level >= max
			local nextLevel = math.min(level + 1, max)
			if kind == "Speed" and machine.PowerOut then
				local text = change(power(MachineData.powerOut(info, level)), power(MachineData.powerOut(info, nextLevel)), top) .. " power"
				table.insert(list, row(entry, safe, coins, "Power", text, MachineUpgradeView.Why.Power))
			elseif kind == "Speed" and not ((machine.Time or 0) > 0) then
				-- belts' helpers (Splitter, Sorter, Robot Arm): their own interval on the server, x speed here
				local text = change(times(level), times(nextLevel), top)
				local why = MachineUpgradeView.Why[machineId] or MachineUpgradeView.Why.Generic
				table.insert(list, row(entry, safe, coins, "Speed", text, why))
			elseif kind == "Speed" then
				local now = seconds(MachineData.processTime(info, bellows, level))
				local after = seconds(MachineData.processTime(info, bellows, nextLevel))
				local why = MachineUpgradeView.Why[machineId] or MachineUpgradeView.Why.Generic
				table.insert(list, row(entry, safe, coins, "Speed", change(now, after, top), why))
			elseif kind == "Quality" then
				local grade, now = topGrade(MachineData.gradeOdds(level))
				local nextGrade, after = topGrade(MachineData.gradeOdds(nextLevel))
				local text = if top or nextGrade == grade
					then change(`{grade} {pct(now)}`, pct(after), top)
					else `{grade} {pct(now)} → {nextGrade} {pct(after)}`
				table.insert(list, row(entry, safe, coins, "Quality", text, MachineUpgradeView.Why.Quality))
			elseif kind == "Tier" then
				local speed = EconomyConfig.upgradeLevel(safe, machineId, "Speed")
				local nextInfo = MachineData.info(machineId, nextLevel)
				local now = seconds(MachineData.processTime(info, bellows, speed))
				local after = seconds(MachineData.processTime(nextInfo, bellows, speed))
				local why = "Bakes faster"
				if top then
					why = "The best furnace there is"
				elseif (nextInfo.Batch or 1) > 1 then
					why = `{nextInfo.Batch} at once, needs power`
				elseif (nextInfo.Power or 0) > 0 then
					why = "Much faster, needs power"
				end
				table.insert(list, row(entry, safe, coins, nextInfo.Name, change(now, after, top), why))
			end
		end
	end
	if (machine.Time or 0) > 0 then
		local entry = EconomyConfig.techItem("Bellows")
		if entry then
			local level, max = EconomyConfig.techLevel(entry, safe)
			local step = MachineData.Bellows.SpeedPerLevel
			local text = change(`-{pct(level * step)}`, `-{pct(math.min(level + 1, max) * step)}`, level >= max)
			table.insert(list, row(entry, safe, coins, "Bellows", text, MachineUpgradeView.Why.Bellows))
		end
	end
	return list
end

--[[
	Where the machine's "Upgrades" prompt goes (MachineUpgradeController):
	E in slot 0 while "Put In" is hidden; while it shows, the Panel keys
	(T / L3) in the slot after it (and after a second prompt on G, "Keep
	List" / "Change Sort", in slot 1).
]]
function MachineUpgradeView.placement(loadShown: boolean, hasSecond: boolean): ("Main" | "Panel", number)
	if not loadShown then
		return "Main", 0
	end
	return "Panel", if hasSecond then 2 else 1
end

-- A placed machine's spot from its model's attributes (Owner, MachineId, GridX, GridZ, GridL):
-- a model the server rebuilds keeps it. Broken values make a key no real machine has.
function MachineUpgradeView.spotKey(owner: any, id: any, x: any, z: any, level: any): string
	local function part(v: any): string
		return if type(v) == "number" or type(v) == "string" then tostring(v) else "?"
	end
	return `{part(owner)}|{part(id)}|{part(x)}|{part(z)}|{part(level or 0)}`
end

-- Does this machine have anything to upgrade? (its prompt shows only then)
function MachineUpgradeView.has(machineId: string): boolean
	local machine = MachineData.ById[machineId]
	if not machine then
		return false
	end
	if (machine.Time or 0) > 0 then
		return true
	end
	for _, kind in MachineData.UpgradeKinds do
		if EconomyConfig.techItem(`Upgrade:{machineId}:{kind}`) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- building

export type RowRefs = {
	Frame: Frame,
	Title: TextLabel,
	Level: TextLabel,
	Change: TextLabel,
	Why: TextLabel,
	Buy: TextButton,
	Item: string?,
	Next: number?,
}

export type Refs = {
	Gui: ScreenGui,
	Dim: Frame,
	Panel: Frame,
	Title: TextLabel,
	Close: TextButton,
	Body: Frame,
	Rows: { RowRefs },
	Note: TextLabel,
}

-- The window's height for `count` rows.
function MachineUpgradeView.height(count: number): number
	return MachineUpgradeView.Band + 24 + count * (MachineUpgradeView.RowHeight + MachineUpgradeView.RowGap) + 36
end

function MachineUpgradeView.build(): Refs
	local gui = UIKit.screen(MachineUpgradeView.GuiName, 28)
	gui.Enabled = false
	gui.IgnoreGuiInset = true
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	local window = Pop.window(
		gui,
		"Upgrades",
		Vector2.new(MachineUpgradeView.Width, MachineUpgradeView.height(3)),
		MachineUpgradeView.Band,
		Pop.windowPaint(MachineUpgradeView.GuiName, "Sky")
	)
	local inner = UIKit.new("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -28, 1, -24),
		ZIndex = 3,
	}, window.Body)
	local note = Pop.text(inner, "", 18, {
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 6,
	})
	local x = window.Close :: GuiObject
	x.Selectable = false
	local closeHit = UIKit.new("TextButton", {
		Name = "CloseHit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Selectable = false,
		Size = UDim2.fromOffset(MachineUpgradeView.CloseHit, MachineUpgradeView.CloseHit),
		Text = "",
		ZIndex = x.ZIndex + 2,
	}, x)
	local root = window.Root
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	return { Gui = gui, Dim = dim, Panel = root, Title = window.Title, Close = closeHit, Body = inner, Rows = {}, Note = note }
end

local function buildRow(refs: Refs, k: number): RowRefs
	local y = (k - 1) * (MachineUpgradeView.RowHeight + MachineUpgradeView.RowGap)
	local card = Pop.well(refs.Body, {
		Name = `Row{k}`,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, MachineUpgradeView.RowHeight),
	})
	local function label(name: string, size: number, at: UDim2, width: UDim2, color: Color3?): TextLabel
		return Pop.text(card, "", size, {
			Name = name,
			Position = at,
			Size = width,
			TextColor3 = color or Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		})
	end
	local buy = Pop.coinButton(card, "", MachineUpgradeView.ButtonSize, {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
	})
	return {
		Frame = card,
		Title = label(
			"Title",
			MachineUpgradeView.Sizes.Title,
			UDim2.fromOffset(16, 8),
			UDim2.new(MachineUpgradeView.Boxes.Title, 0, 0, 32)
		),
		Level = label(
			"Level",
			MachineUpgradeView.Sizes.Level,
			UDim2.new(0.42, 0, 0, 10),
			UDim2.new(MachineUpgradeView.Boxes.Level, 0, 0, 28),
			Color3.fromRGB(255, 214, 70)
		),
		Change = label(
			"Change",
			MachineUpgradeView.Sizes.Change,
			UDim2.fromOffset(16, 42),
			UDim2.new(MachineUpgradeView.Boxes.Change, 0, 0, 30),
			Color3.fromRGB(130, 240, 120)
		),
		Why = label("Why", MachineUpgradeView.Sizes.Why, UDim2.fromOffset(16, 74), UDim2.new(MachineUpgradeView.Boxes.Why, 0, 0, 28)),
		Buy = buy,
	}
end

-- Fills the window for `title` with `rows`.
function MachineUpgradeView.fill(refs: Refs, title: string, rows: { Row })
	refs.Title.Text = title
	local window = refs.Panel
	window.Size = UDim2.fromOffset(MachineUpgradeView.Width, MachineUpgradeView.height(#rows))
	for k = #refs.Rows + 1, #rows do
		refs.Rows[k] = buildRow(refs, k)
	end
	for k, r in refs.Rows do
		local data = rows[k]
		r.Frame.Visible = data ~= nil
		if data then
			r.Item = data.Item
			r.Next = data.Next
			r.Title.Text = data.Title
			r.Level.Text = data.Level
			r.Change.Text = data.Change
			r.Why.Text = data.Why
			if data.Price then
				Pop.setCoinButton(r.Buy, Format.big(data.Price), data.Affordable)
				r.Buy.Visible = true
				r.Buy.Active = data.Affordable
			else
				r.Buy.Visible = false
			end
		end
	end
	refs.Note.Text = "Every machine of this kind gets the upgrade"
end

-- A row whose BUY waits for the server's answer.
function MachineUpgradeView.busy(r: RowRefs)
	Pop.setCoinButton(r.Buy, "...", false)
	r.Buy.Active = false
end

-- What a ShopResult reason says on a row (MachineUpgradeView.Reasons).
function MachineUpgradeView.reasonText(reason: any): string
	local reasons = MachineUpgradeView.Reasons
	return if type(reason) == "string" and reasons[reason] then reasons[reason] else reasons.Retry
end

-- A row's reason or result under its title (a refusal, "BOUGHT!").
function MachineUpgradeView.say(r: RowRefs, text: string)
	r.Why.Text = text
end

return MachineUpgradeView
