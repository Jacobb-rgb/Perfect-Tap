--[[
	Foundry UI (pure builders; FoundryController fills them in and wires them).

	The panel (build), opened at your Foundry:
	  header   FOUNDRY title, the TAKE [ONE | ALL] switch, X button
	  left     INGOTS "12 / 60": one row per ore (grouped over grades): an
	           icon in the ore's colour framed in its rarity colour, the name,
	           a rarity chip, the grades ("2 Pristine, 1 Rough") or why the
	           next level can't use it, the count and TAKE (one ingot back to
	           the Ore Pen, the cheapest of that ore first; TAKE ALL on the
	           rows the next level can't use, and on every row while the
	           switch says ALL: all of that ore at once). Below the rows (or
	           in the empty text) a note when usable ingots wait in the Ore
	           Pen, saying how they come back.
	  right    NEXT BLASTER: level badge, the name the new blaster would get
	           in the chosen look's colour, damage now -> next, the LOOK
	           picker (< ore >, only ores among the usable ingots), the recipe
	           (ingots of MinRarity+ "have / need", coins), what the forge
	           uses, and FORGE (grey with the reason when it can't); after
	           level 10: "COMING SOON"
	  footer   control hint (gamepads: the platform's glyphs)
	Compact layout for phones (uiScale <= 0.75): taller rows and buttons. fit
	shrinks the panel (an extra UIScale) when it would be taller or wider
	than the screen below the Roblox top bar (short landscape phones).

	The hammer moment (buildForge): banner with the blaster's name, tap pips,
	the shrinking ring over the target circle (PERFECT / GOOD are cosmetic,
	every tap counts), a big STRIKE button (bottom right on touch), LEAVE,
	the feedback text, a white flash and the reveal card (NEW BLASTER!).
	placeTop keeps LEAVE and the banner below the Roblox top bar (the gui
	ignores the inset so the flash covers the whole screen).

	Pure helpers (tested): oreRows, status, reasonText, usesText, damageText,
	grade, ringScale, topShift, tapTime (when a tap may count), fitScale,
	penUsable, penText.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared.Config.UIConfig)
local BlasterData = require(Shared.Config.BlasterData)
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local FoundryLogic = require(Shared.Machines.FoundryLogic)
local Format = require(Shared.Util.Format)
local PopTheme = require(Shared.Config.PopTheme)
local ItemBuilder = require(Shared.Builders.ItemBuilder)
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local LightSkin = require(script.Parent.LightSkin)

local FoundryView = {}

export type OreRow = {
	Ore: string,
	Name: string,
	Rarity: string,
	Color: Color3,
	RarityColor: Color3,
	Count: number,
	Usable: boolean,
	TakeKey: string, -- the cheapest ingot of this ore
	Detail: string,
	Best: number, -- the best ingot's value (sorting)
}

export type Row = {
	Ore: string,
	TakeKey: string,
	TakeAll: boolean, -- TAKE ALL (the next level can't use this ore)
	Amount: number,
	Frame: Frame,
	Icon: Frame,
	IconStroke: UIStroke,
	Name: TextLabel,
	Chip: TextLabel,
	Detail: TextLabel,
	Count: TextLabel,
	Take: TextButton,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Close: TextButton,
	StockHeader: TextLabel,
	List: ScrollingFrame,
	Empty: TextLabel,
	Card: Frame,
	Badge: TextLabel,
	BlasterName: TextLabel,
	Damage: TextLabel,
	LookRow: Frame,
	LookPrev: TextButton,
	LookNext: TextButton,
	LookName: TextLabel,
	LookSwatch: Frame,
	Ingots: TextLabel,
	Coins: TextLabel,
	Uses: TextLabel,
	UsesRow: Frame,
	Forge: TextButton,
	Reason: TextLabel,
	Soon: TextLabel,
	Hint: TextLabel,
	PadHint: Frame,
	PadA: ImageLabel,
	PadB: ImageLabel,
	TakeMode: Frame,
	TakeOne: TextButton,
	TakeEvery: TextButton,
	TakeAllMode: boolean, -- the switch says ALL: every row's TAKE moves all of its ore
	PenNote: TextLabel,
	Fit: UIScale,
	Rows: { [string]: Row },
	Compact: boolean,
}

export type ForgeRefs = {
	Gui: ScreenGui,
	Banner: TextLabel,
	Sub: TextLabel,
	Pips: Frame,
	PipList: { Frame },
	RingHolder: Frame,
	Target: Frame,
	Ring: Frame,
	RingStroke: UIStroke,
	Feedback: TextLabel,
	Strike: TextButton,
	StrikeHint: TextLabel,
	Leave: TextButton,
	Flash: Frame,
	Card: Frame,
	CardTitle: TextLabel,
	CardName: TextLabel,
	CardLevel: TextLabel,
	CardDamage: TextLabel,
	Collect: TextButton,
}

FoundryView.MaxRows = 40
FoundryView.Beat = 0.75 -- seconds for the ring to shrink onto the target
FoundryView.PerfectWindow = 0.08
FoundryView.GoodWindow = 0.18
FoundryView.RingStart = 2.6 -- the ring's size (x the target) when a beat starts
FoundryView.Intro = 0.6 -- the camera flies in; taps wait until it is there
FoundryView.MinGap = 0.2 -- seconds between counted taps (the server needs GameConfig.AnvilMinStrikeGap)
-- the k-th tap counts no earlier than k x this after FoundryBegin, so the last
-- one always passes the server's Hits x AnvilMinSecondsPerHit rule
FoundryView.Pace = GameConfig.AnvilMinSecondsPerHit + 0.005

local PAD = 16
local HEADER = 60
local FOOTER = 34
local GAP = 8
local SCROLLBAR = 10

local EMPTY_TEXT =
	"No ingots yet. Smelt ore in a furnace, then run a belt off the FOUNDRY chute, throw them into the hopper or carry them here and press Put In."
local FIT_MARGIN_X = 16 -- screen pixels kept free around the panel (fit)
local FIT_MARGIN_Y = 6

-- Mode*: the TAKE [ONE | ALL] switch; Note*: the Ore Pen note under the rows
local LAYOUTS = {
	Normal = {
		Width = 920,
		Height = 500,
		Left = 470,
		RowH = 62,
		ButtonH = 46,
		TakeW = 88,
		Name = 19,
		Forge = 62,
		Close = 50,
		Arrow = 46,
		ModeH = 40,
		ModeW = 74,
		ModeLabel = 58,
		Note = 58,
		NoteText = 15,
	},
	-- 510 tall: at the 0.62 UI floor it fits a 375 pt landscape phone below the top bar
	Compact = {
		Width = 980,
		Height = 510,
		Left = 500,
		RowH = 86,
		ButtonH = 72,
		TakeW = 112,
		Name = 21,
		Forge = 78,
		Close = 72,
		Arrow = 72,
		ModeH = 52,
		ModeW = 96,
		ModeLabel = 64,
		Note = 66,
		NoteText = 17,
	},
}

local function layoutOf(refs: Refs): typeof(LAYOUTS.Normal)
	return if refs.Compact then LAYOUTS.Compact else LAYOUTS.Normal
end

---------------------------------------------------------------- pure helpers

local GRADE_ORDER = { "Flawless", "Pristine", "Clean", "Rough" }

--[[
	One row per ore from a State FoundryStock summary ("Ingot|O|G|" -> count):
	ores the next level can use first, then by their best ingot (most
	valuable first). TakeKey is the cheapest ingot of the ore.
]]
function FoundryView.oreRows(summary: any, level: any): { OreRow }
	local byOre: { [string]: { Grades: { [string]: number }, Count: number, Best: number, Cheapest: number, TakeKey: string } } = {}
	local order: { string } = {}
	if type(summary) == "table" then
		for key, count in summary do
			local desc = if type(key) == "string" then ItemData.parseKey(key) else nil
			if desc and FoundryLogic.isIngot(desc) and type(count) == "number" and count >= 1 and count == count then
				local n = math.floor(count)
				local value = FoundryLogic.value(desc)
				local entry = byOre[desc.O]
				if not entry then
					entry = { Grades = {}, Count = 0, Best = -math.huge, Cheapest = math.huge, TakeKey = key }
					byOre[desc.O] = entry
					table.insert(order, desc.O)
				end
				local grade = desc.G or "Rough"
				entry.Grades[grade] = (entry.Grades[grade] or 0) + n
				entry.Count += n
				entry.Best = math.max(entry.Best, value)
				if value < entry.Cheapest or (value == entry.Cheapest and key < entry.TakeKey) then
					entry.Cheapest = value
					entry.TakeKey = key
				end
			end
		end
	end
	local recipe = FoundryLogic.recipe(level)
	local rows: { OreRow } = {}
	for _, oreId in order do
		local entry = byOre[oreId]
		local ore = OreData.ById[oreId]
		local rarity = Rarity.ById[ore.Rarity]
		local usable = FoundryLogic.usable({ K = "Ingot", O = oreId }, level)
		local parts = {}
		for _, grade in GRADE_ORDER do
			local n = entry.Grades[grade]
			if n then
				table.insert(parts, `{n} {grade}`)
			end
		end
		local detail = table.concat(parts, ", ")
		if not usable then
			detail = if recipe then `Too common: needs {recipe.MinRarity}+` else "Not needed any more"
		end
		table.insert(rows, {
			Ore = oreId,
			Name = ore.Name,
			Rarity = ore.Rarity,
			Color = ore.Color,
			RarityColor = if rarity then rarity.Color else Theme.TextDim,
			Count = entry.Count,
			Usable = usable,
			TakeKey = entry.TakeKey,
			Detail = detail,
			Best = entry.Best,
		})
	end
	table.sort(rows, function(a: OreRow, b: OreRow): boolean
		if a.Usable ~= b.Usable then
			return a.Usable
		elseif a.Best ~= b.Best then
			return a.Best > b.Best
		end
		return a.Ore < b.Ore
	end)
	return rows
end

-- A text size (at most `max`, at least 12) that fits `text` into `width`
-- (FredokaOne is about 0.56 x its size per character): long ore names
-- shrink instead of running into the rarity chip.
function FoundryView.fitTextSize(text: string, width: number, max: number): number
	local chars = math.max(1, utf8.len(text) or #text)
	return math.clamp(math.floor(width / (chars * 0.56)), 12, max)
end

-- FoundryLogic.status for a State snapshot and the chosen look.
function FoundryView.status(state: any, skin: string?): FoundryLogic.Status
	local s = if type(state) == "table" then state else {}
	return FoundryLogic.status(FoundryLogic.fromSummary(s.FoundryStock), s.BlasterLevel, s.Coins, skin)
end

-- The line under FORGE.
function FoundryView.reasonText(status: FoundryLogic.Status, coins: any): string
	local recipe = status.Recipe
	if status.Reason == "MaxLevel" or not recipe then
		return "Your blaster is the best there is... for now!"
	elseif status.Reason == "NeedIngots" then
		local missing = status.Need - status.Have
		return `Need {missing} more {recipe.MinRarity}+ {if missing == 1 then "ingot" else "ingots"}`
	elseif status.Reason == "NeedCoins" then
		local balance = if type(coins) == "number" and coins == coins then coins else 0
		return `Need {Format.money(math.max(0, recipe.Coins - balance))} more`
	end
	return "Ready! Hammer it into shape."
end

-- What the forge would use, e.g. "Uses 1 Gold + 2 cheapest ingots".
function FoundryView.usesText(status: FoundryLogic.Status): string
	local recipe = status.Recipe
	local skin = status.Skin and OreData.ById[status.Skin]
	if not recipe then
		return ""
	end
	if not skin then
		return `Uses {recipe.Ingots} ingots: the cheapest ones, the best stay`
	end
	local others = recipe.Ingots - 1
	if others <= 0 then
		return `Uses 1 {skin.Name} ingot`
	end
	return `Uses 1 {skin.Name} + your {others} cheapest {if others == 1 then "ingot" else "ingots"}`
end

-- "Damage 5 -> 9 /s" (with the chosen look's rarity bonus).
function FoundryView.damageText(level: any, ore: string?, nextLevel: number, skin: string?): string
	local now = BlasterData.damage(level, ore)
	local after = BlasterData.damage(nextLevel, skin)
	return `Damage {Format.big(math.floor(now + 0.5))} -> {Format.big(math.floor(after + 0.5))} /s`
end

-- PERFECT / GOOD / HIT for a tap `t` seconds after the ring started (the
-- ring repeats every Beat + GoodWindow, see ringScale).
function FoundryView.grade(t: number): "Perfect" | "Good" | "Hit"
	local cycle = FoundryView.Beat + FoundryView.GoodWindow
	local off = math.abs(t % cycle - FoundryView.Beat)
	if off <= FoundryView.PerfectWindow then
		return "Perfect"
	elseif off <= FoundryView.GoodWindow then
		return "Good"
	end
	return "Hit"
end

-- The ring's size (x the target) `t` seconds into a beat: it shrinks onto the
-- target at Beat and a little past it, then the next beat starts.
function FoundryView.ringScale(t: number): number
	local cycle = FoundryView.Beat + FoundryView.GoodWindow
	local p = (t % cycle) / FoundryView.Beat
	return math.max(0.6, FoundryView.RingStart - (FoundryView.RingStart - 1) * p)
end

--[[
	The earliest time (seconds since FoundryBegin) the k-th tap may count when
	the one before counted at `last` (nil: none yet). Every tap counts: taps
	that come sooner wait their turn, so a burst of fast taps fills the pips
	at this pace and the times always pass MachineLogic.validateStrikes.
]]
function FoundryView.tapTime(k: number, last: number?): number
	local after = if last then last + FoundryView.MinGap else 0
	return math.max(FoundryView.Intro, after, k * FoundryView.Pace)
end

--[[
	The panel's extra scale so it fits an `areaW` x `areaH` screen area (the
	ScreenGui's size below the top bar) at UI scale `guiScale`: 1 when it
	fits, smaller on short landscape phones.
]]
function FoundryView.fitScale(areaW: number, areaH: number, guiScale: number, compact: boolean): number
	if areaW <= 0 or areaH <= 0 then
		return 1
	end
	local l = if compact then LAYOUTS.Compact else LAYOUTS.Normal
	local scale = if guiScale > 0 then guiScale else 1
	local w = (areaW - FIT_MARGIN_X * 2) / (l.Width * scale)
	local h = (areaH - FIT_MARGIN_Y * 2) / (l.Height * scale)
	return math.clamp(math.min(w, h), 0.5, 1)
end

-- How many ingots in the Ore Pen (a State Storage summary) the next level can use.
function FoundryView.penUsable(storage: any, level: any): number
	local n = 0
	if type(storage) ~= "table" then
		return 0
	end
	for key, count in storage do
		if type(key) == "string" and type(count) == "number" and count >= 1 and count == count and count < math.huge then
			local desc = ItemData.parseKey(key)
			if desc and FoundryLogic.usable(desc, level) then
				n += math.floor(count)
			end
		end
	end
	return n
end

-- The note for usable ingots waiting in the Ore Pen (how they come back).
function FoundryView.penText(n: number): string
	local what = if n == 1 then "1 ingot for your next blaster waits" else `{Format.commas(n)} ingots for your next blaster wait`
	return `{what} in your Ore Pen: take them out there and Put In here, or Send them on a belt into the FOUNDRY chute.`
end

---------------------------------------------------------------- the Pop pieces
--[[
	The panel's Pop look (popSkin, at the end of the file; the light UI)
	dresses the same instances the dark build makes. A lip button's holder
	becomes the painted Pop face (attribute Pop) and the button on it a
	see-through TextButton with white chunky words; rows and cards get a
	paint, the studs, a light rim and sparkles.
]]

local function isPop(refs: Refs): boolean
	return refs.Gui:GetAttribute("PopSkin") == true
end

-- The black edge of a text (its Contextual UIStroke, made when missing).
local function popEdge(label: GuiObject)
	local text: any = label
	local edge: UIStroke? = nil
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			edge = child
		end
	end
	local stroke = edge or Pop.edge(label)
	stroke.Color = PopTheme.Outline
	stroke.Transparency = 0
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Thickness = Pop.edgeFor(if text.TextScaled then 24 else text.TextSize)
end

-- White chunky words with a black edge on an old label or button.
local function popText(label: GuiObject, font: Font?)
	local text: any = label
	text.FontFace = font or PopTheme.Font
	text.TextColor3 = PopTheme.Ink
	popEdge(label)
end

-- A lip button (UIKit.button) as a Pop button: the holder painted, the button see-through on it.
local function popButton(button: TextButton, paint: string | Pop.Paint)
	local holder = button.Parent :: Frame
	for _, child in holder:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	local corner = holder:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 10)
	end
	Pop.face(holder, paint, 10)
	local rim = holder:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 1
	end
	Pop.studs(holder, 10, 0.45, 28, 1)
	holder:SetAttribute("Pop", true)
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
	button.BackgroundTransparency = 1
	button.Position = UDim2.new()
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 3
	popText(button)
end

-- A small label (UIKit.chip) as a Pop chip: a flat colour, a black edge, white words.
local function popChip(chip: TextLabel, color: Color3)
	chip.BackgroundColor3 = color
	chip.BackgroundTransparency = 0
	for _, child in chip:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child.Color = PopTheme.Outline
			child.Thickness = 2.5
		end
	end
	popText(chip)
end

-- A painted card face on an old frame: the paint, a light burst ("Burst": place
-- it at the picture), the studs, the light rim, sparkles. The frame's own
-- children move above the decoration (ZIndex 5+).
local function popCard(frame: GuiObject, paint: string | Pop.Paint, corner: number, rays: boolean): Frame
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		elseif child:IsA("GuiObject") then
			child.ZIndex = math.max(child.ZIndex, 5)
		end
	end
	local round = frame:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0, corner)
	end
	Pop.face(frame, paint, corner, false)
	frame.ClipsDescendants = true
	local p = Pop.paint(paint)
	local burst = UIKit.new("Frame", {
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 1,
	}, frame)
	if rays then
		local made = Pop.fx(burst, "fx_rays", {
			Name = "Rays",
			AnchorPoint = Vector2.new(0.5, 0.5),
			ImageTransparency = 0.35,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(520, 520),
			ZIndex = 1,
		})
		if not made then
			Pop.rays(burst, UDim2.fromScale(0.5, 0.5), 10, 260, 0.6, 1)
		end
	end
	local glow = Pop.fx(burst, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = p.Top:Lerp(Color3.new(1, 1, 1), 0.6),
		ImageTransparency = if rays then 0.3 else 0.5,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(if rays then 190 else 90, if rays then 190 else 90),
		ZIndex = 1,
	})
	if not glow then
		local disc = UIKit.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(if rays then 120 else 60, if rays then 120 else 60),
			ZIndex = 1,
		}, burst)
		UIKit.corner(disc, 999)
	end
	Pop.studs(frame, corner, 0.5, 44, 2)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	for i, spot in { { 0.1, 0.22, 18 }, { 0.9, 0.2, 16 }, { 0.62, 0.8, 12 } } do
		Pop.sparkle(frame, UDim2.fromScale(spot[1], spot[2]), spot[3], 3, 0.15 + i * 0.1)
	end
	return burst
end

FoundryView.PopPaints = {
	Header = "Orange", -- (LightSkin.BandRoles: TerraForgeFoundry = Vault)
	Card = "Purple", -- the next blaster
	Switch = "Blue", -- the TAKE switch's picked side
	Arrows = "Blue",
} :: { [string]: string }

local INGOT_FROM = Vector3.new(-0.55, 0.75, -1) -- a bar a little from above
local BLASTER_FROM = Vector3.new(-1, 0.3, 0.18) -- (PictureModels' "blaster": the side, barrel left)

-- A live 3D ingot of `oreId` (ItemBuilder: 4 parts), nil when it can't be built.
local function ingotModel(oreId: string): Model?
	local ok, made = pcall(ItemBuilder.build, { Kind = "Ingot", OreId = oreId, Grade = "Pristine" }, CFrame.new(), "foundry_" .. oreId)
	return if ok then made else nil
end

-- The blaster a forge would make (BlasterBuilder: a Tool's parts in a Model).
local function blasterModel(level: number, oreId: string?): Model?
	local ok, tool = pcall(BlasterBuilder.build, level, oreId)
	if not ok then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Blaster"
	for _, child: Instance in (tool :: Instance):GetChildren() do
		if child:IsA("BasePart") or child:IsA("Model") then
			local part: Instance = child
			part.Parent = model
		end
	end
	return model
end

---------------------------------------------------------------- the panel

local function labelProps(extra: { [string]: any }?): { [string]: any }
	local props: { [string]: any } = { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

function FoundryView.build(): Refs
	local gui = UIKit.screen("TerraForgeFoundry", 15)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	local l = LAYOUTS.Normal

	local panel = UIKit.panel(gui, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(l.Width, l.Height),
	})
	UIKit.label(
		panel,
		"FOUNDRY",
		30,
		labelProps({
			Name = "Title",
			Position = UDim2.fromOffset(PAD, 10),
			Size = UDim2.new(0.5, 0, 0, 38),
			FontFace = Theme.TitleFont,
			TextColor3 = Theme.Accent,
		})
	)
	local close = UIKit.button(panel, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 10),
		Size = UDim2.fromOffset(l.Close, l.Close),
		TextSize = 26,
	})
	-- shrinks the panel on screens too short for it (fit)
	local fitScale = UIKit.new("UIScale", { Name = "Fit", Scale = 1 }, panel)

	-- the TAKE [ONE | ALL] switch, right-aligned over the ingot list
	local mode = UIKit.new("Frame", {
		Name = "TakeMode",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(PAD + l.Left, (HEADER - l.ModeH) // 2),
		Size = UDim2.fromOffset(l.ModeLabel + l.ModeW * 2 + 12, l.ModeH),
	}, panel)
	UIKit.list(mode, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})
	UIKit.label(
		mode,
		"TAKE",
		17,
		labelProps({
			Name = "Label",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(l.ModeLabel, l.ModeH - 5),
			TextColor3 = Theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	)
	local takeOne = UIKit.button(mode, "ONE", Theme.Accent, Theme.AccentDark, {
		Name = "TakeOne",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(l.ModeW, l.ModeH - 5),
		TextSize = 18,
	})
	local takeEvery = UIKit.button(mode, "ALL", Theme.PanelLight, Theme.Panel, {
		Name = "TakeEvery",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(l.ModeW, l.ModeH - 5),
		TextSize = 18,
	})

	-- left: the ingot stock
	local left = UIKit.new("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAD, HEADER),
		Size = UDim2.new(0, l.Left, 1, -(HEADER + FOOTER)),
	}, panel)
	local stockHeader = UIKit.label(
		left,
		"INGOTS  0 / 60",
		20,
		labelProps({
			Name = "StockHeader",
			Size = UDim2.new(1, 0, 0, 26),
			TextColor3 = Theme.TextDim,
		})
	)
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
	}, left)
	UIKit.list(list, Enum.FillDirection.Vertical, GAP)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2) }, list)
	-- usable ingots in the Ore Pen: how they come back (after the rows)
	local penNote = UIKit.label(list, "", l.NoteText, {
		Name = "PenNote",
		LayoutOrder = FoundryView.MaxRows + 1,
		Size = UDim2.fromOffset(l.Left - SCROLLBAR - 6, l.Note),
		TextColor3 = Theme.Info,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	})
	local empty = UIKit.label(left, EMPTY_TEXT, 18, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, 110),
		TextColor3 = Theme.TextDim,
		Visible = false,
	})

	-- right: the next blaster
	local card = UIKit.new("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, HEADER),
		Size = UDim2.new(0, l.Width - l.Left - PAD * 3, 1, -(HEADER + FOOTER)),
	}, panel)
	UIKit.corner(card, 12)
	UIKit.stroke(card, 2.5)
	UIKit.label(
		card,
		"NEXT BLASTER",
		16,
		labelProps({
			Name = "CardTitle",
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -100, 0, 22),
			TextColor3 = Theme.TextDim,
		})
	)
	local badge = UIKit.chip(card, "LV 2", Theme.Accent, {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(74, 28),
		TextSize = 18,
	})
	local name = UIKit.label(
		card,
		"",
		26,
		labelProps({
			Name = "BlasterName",
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -28, 0, 34),
			FontFace = Theme.TitleFont,
			TextScaled = true,
		})
	)
	local damage = UIKit.label(
		card,
		"",
		17,
		labelProps({
			Name = "Damage",
			Position = UDim2.fromOffset(14, 72),
			Size = UDim2.new(1, -28, 0, 22),
			TextColor3 = Theme.Info,
		})
	)
	-- the look picker: < [swatch] Gold >
	local lookRow = UIKit.new("Frame", {
		Name = "LookRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 100),
		Size = UDim2.new(1, -24, 0, l.Arrow),
	}, card)
	local prev = UIKit.button(lookRow, "<", Theme.PanelLight, Theme.Panel, {
		Name = "LookPrev",
		Size = UDim2.fromOffset(l.Arrow, l.Arrow),
		TextSize = 24,
	})
	local nextButton = UIKit.button(lookRow, ">", Theme.PanelLight, Theme.Panel, {
		Name = "LookNext",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(l.Arrow, l.Arrow),
		TextSize = 24,
	})
	local swatch = UIKit.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, l.Arrow + 12, 0.5, -2),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, lookRow)
	UIKit.corner(swatch, 13)
	UIKit.stroke(swatch, 2)
	local lookName = UIKit.label(
		lookRow,
		"Look: -",
		19,
		labelProps({
			Name = "LookName",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, l.Arrow + 46, 0.5, -2),
			Size = UDim2.new(1, -(l.Arrow * 2 + 56), 0, 30),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	)
	local ingots = UIKit.label(
		card,
		"",
		18,
		labelProps({
			Name = "Ingots",
			Position = UDim2.fromOffset(14, 108 + l.Arrow),
			Size = UDim2.new(1, -28, 0, 24),
		})
	)
	local coins = UIKit.label(
		card,
		"",
		18,
		labelProps({
			Name = "Coins",
			Position = UDim2.fromOffset(14, 134 + l.Arrow),
			Size = UDim2.new(1, -28, 0, 24),
		})
	)
	local uses = UIKit.label(card, "", 15, {
		Name = "Uses",
		Position = UDim2.fromOffset(14, 160 + l.Arrow),
		Size = UDim2.new(1, -28, 0, 40),
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	-- the ingots the forge would use, as little squares in their ore colours
	local usesRow = UIKit.new("Frame", {
		Name = "UsesRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 186 + l.Arrow),
		Size = UDim2.new(1, -28, 0, 26),
	}, card)
	UIKit.list(usesRow, Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
	local forge = UIKit.button(card, "FORGE", Theme.Good, Theme.GoodDark, {
		Name = "Forge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(1, -28, 0, l.Forge),
		TextSize = 30,
	})
	local reason = UIKit.label(card, "", 16, {
		Name = "Reason",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 0, 26),
		TextColor3 = Theme.TextDim,
	})
	local soon = UIKit.label(card, "COMING SOON", 34, {
		Name = "Soon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, 60),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		Visible = false,
	})

	local hint = UIKit.label(panel, "", 15, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PAD, 1, -8),
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		TextColor3 = Theme.TextDim,
	})
	local padHint = UIKit.new("Frame", {
		Name = "PadHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(300, 24),
		BackgroundTransparency = 1,
		Visible = false,
	}, panel)
	UIKit.list(padHint, Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local function glyph(order: number): ImageLabel
		return UIKit.new(
			"ImageLabel",
			{ Name = "Glyph" .. order, LayoutOrder = order, Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1 },
			padHint
		)
	end
	local function word(order: number, text: string)
		UIKit.label(
			padHint,
			text,
			16,
			labelProps({ Name = "Word" .. order, LayoutOrder = order, Size = UDim2.fromOffset(84, 24), TextColor3 = Theme.TextDim })
		)
	end
	local padA = glyph(1)
	word(2, "choose")
	local padB = glyph(3)
	word(4, "close")

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Close = close,
		StockHeader = stockHeader,
		List = list,
		Empty = empty,
		Card = card,
		Badge = badge,
		BlasterName = name,
		Damage = damage,
		LookRow = lookRow,
		LookPrev = prev,
		LookNext = nextButton,
		LookName = lookName,
		LookSwatch = swatch,
		Ingots = ingots,
		Coins = coins,
		Uses = uses,
		UsesRow = usesRow,
		Forge = forge,
		Reason = reason,
		Soon = soon,
		Hint = hint,
		PadHint = padHint,
		PadA = padA,
		PadB = padB,
		TakeMode = mode,
		TakeOne = takeOne,
		TakeEvery = takeEvery,
		TakeAllMode = false,
		PenNote = penNote,
		Fit = fitScale,
		Rows = {},
		Compact = false,
	}
	FoundryView.setTakeMode(refs, false)
	return refs
end

local function layoutRow(refs: Refs, row: Row)
	local l = layoutOf(refs)
	local rowW = l.Left - SCROLLBAR - 6
	row.Frame.Size = UDim2.fromOffset(rowW, l.RowH)
	local icon = l.RowH - 18
	row.Icon.Size = UDim2.fromOffset(icon, icon)
	row.Icon.Position = UDim2.fromOffset(9, 9)
	local textX = icon + 20
	local countW = 52
	local textW = rowW - textX - l.TakeW - countW - 16
	row.Name.Position = UDim2.fromOffset(textX, 5)
	row.Name.Size = UDim2.fromOffset(textW - 90, math.floor(l.RowH * 0.45))
	row.Name.TextSize = FoundryView.fitTextSize(row.Name.Text, row.Name.Size.X.Offset, l.Name)
	row.Chip.Position = UDim2.fromOffset(textX + textW - 86, 8)
	row.Detail.Position = UDim2.fromOffset(textX, math.floor(l.RowH * 0.5) + 1)
	row.Detail.Size = UDim2.fromOffset(textW, math.floor(l.RowH * 0.4))
	row.Count.Position = UDim2.fromOffset(rowW - l.TakeW - countW - 12, 0)
	row.Count.Size = UDim2.fromOffset(countW, l.RowH)
	local take = row.Take.Parent :: Frame
	take.Position = UDim2.fromOffset(rowW - l.TakeW - 8, math.floor((l.RowH - l.ButtonH) / 2) + 3)
	take.Size = UDim2.fromOffset(l.TakeW, l.ButtonH)
end

local function newRow(refs: Refs, oreId: string): Row
	local frame = UIKit.new("Frame", { Name = "Row", BackgroundColor3 = Theme.PanelLight, BorderSizePixel = 0 }, refs.List)
	frame:SetAttribute("Ore", oreId)
	UIKit.corner(frame, 12)
	UIKit.stroke(frame, 2.5)
	local icon = UIKit.new("Frame", { Name = "Icon", BackgroundColor3 = Theme.PanelDark, BorderSizePixel = 0 }, frame)
	UIKit.corner(icon, 8)
	local iconStroke = UIKit.stroke(icon, 3)
	UIKit.gradient(icon, Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	local name = UIKit.label(frame, "", 19, labelProps({ Name = "ItemName", TextTruncate = Enum.TextTruncate.AtEnd }))
	local chip = UIKit.chip(frame, "", Theme.PanelDark, { Name = "Rarity", Size = UDim2.fromOffset(84, 22), TextSize = 13 })
	local detail =
		UIKit.label(frame, "", 14, labelProps({ Name = "Detail", TextColor3 = Theme.TextDim, TextTruncate = Enum.TextTruncate.AtEnd }))
	local count = UIKit.label(frame, "x0", 22, labelProps({ Name = "Count", TextXAlignment = Enum.TextXAlignment.Right }))
	local take = UIKit.button(frame, "TAKE", Theme.Accent, Theme.AccentDark, { Name = "Take", TextSize = 18 })
	local row: Row = {
		Ore = oreId,
		TakeKey = "",
		TakeAll = false,
		Amount = 0,
		Frame = frame,
		Icon = icon,
		IconStroke = iconStroke,
		Name = name,
		Chip = chip,
		Detail = detail,
		Count = count,
		Take = take,
	}
	refs.Rows[oreId] = row
	layoutRow(refs, row)
	return row
end

-- Shows the ore rows (reused by ore). Returns the rows just created.
function FoundryView.setRows(refs: Refs, rows: { OreRow }, total: number): { Row }
	local created: { Row } = {}
	local keep: { [string]: boolean } = {}
	for index, info in rows do
		if index > FoundryView.MaxRows then
			break
		end
		keep[info.Ore] = true
		local existing: Row? = refs.Rows[info.Ore]
		local row: Row
		if existing then
			row = existing
		else
			row = newRow(refs, info.Ore)
			table.insert(created, row)
		end
		row.TakeKey = info.TakeKey
		row.TakeAll = not info.Usable or refs.TakeAllMode
		row.Amount = info.Count
		row.Take.Text = if row.TakeAll then "TAKE ALL" else "TAKE"
		row.Take.TextSize = if row.TakeAll then (if refs.Compact then 17 else 14) else 18
		row.Frame.LayoutOrder = index
		row.Frame.BackgroundColor3 = if info.Usable then Theme.PanelLight else Theme.Panel
		row.Icon.BackgroundColor3 = info.Color
		row.IconStroke.Color = info.RarityColor
		row.Name.Text = info.Name
		row.Name.TextSize = FoundryView.fitTextSize(info.Name, row.Name.Size.X.Offset, layoutOf(refs).Name)
		row.Name.TextColor3 = if info.Usable then Theme.Text else Theme.TextDim
		row.Chip.Text = info.Rarity
		row.Chip.BackgroundColor3 = info.RarityColor
		row.Detail.Text = info.Detail
		row.Detail.TextColor3 = if info.Usable then Theme.TextDim else Theme.Bad
		row.Count.Text = "x" .. Format.big(info.Count)
	end
	local rowMap = refs.Rows :: { [string]: any }
	for oreId, row in refs.Rows do
		if not keep[oreId] then
			row.Frame:Destroy()
			rowMap[oreId] = nil
		end
	end
	refs.Empty.Visible = next(keep) == nil
	refs.StockHeader.Text = `INGOTS  {Format.commas(total)} / {Format.commas(GameConfig.MaxFoundryStock)}`
	return created
end

-- The ingots a forge would use (status.Uses into `stock`), as little ingots
-- in their ore colours with a rarity-coloured rim and a shine (so dark ores
-- like Coal still read as ingots); the look's ingot first with a gold frame.
-- The ingots still missing are see-through slots with a "?".
function FoundryView.setUses(refs: Refs, status: FoundryLogic.Status, stock: { FoundryLogic.Desc })
	for _, child in refs.UsesRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local framed = status.Uses ~= nil
	local uses: { number } = status.Uses or {}
	if not framed then
		-- not enough yet: the usable ones there are, then the missing ones
		for index, desc in stock do
			if #uses < status.Need and FoundryLogic.usable(desc, status.Level - 1) then
				table.insert(uses, index)
			end
		end
	end
	for i = 1, math.min(status.Need, 12) do
		local desc = stock[uses[i] or 0]
		local ore = desc and OreData.ById[desc.O]
		local square = UIKit.new("Frame", {
			Name = "Ingot" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = if ore then ore.Color else Theme.PanelDark,
			BackgroundTransparency = if ore then 0 else 1,
			BorderSizePixel = 0,
		}, refs.UsesRow)
		square:SetAttribute("Filled", ore ~= nil)
		UIKit.corner(square, 5)
		if ore then
			local skin = framed and i == 1
			local rarity = Rarity.ById[ore.Rarity]
			UIKit.stroke(square, if skin then 3 else 2, if skin then Theme.Coin elseif rarity then rarity.Color else Theme.Text)
			local shine = UIKit.new("Frame", {
				Name = "Shine",
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(8, 4),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
			}, square)
			UIKit.corner(shine, 2)
		else
			UIKit.stroke(square, 2, Theme.TextDim, 0.35)
			UIKit.label(square, "?", 15, { Name = "Missing", Size = UDim2.fromScale(1, 1), TextColor3 = Theme.TextDim })
		end
	end
end

-- Sets FORGE's look: green and live, or grey (still clickable for the reason).
function FoundryView.setForgeEnabled(refs: Refs, enabled: boolean)
	local holder = refs.Forge.Parent :: Frame
	refs.Forge.BackgroundColor3 = if enabled then Theme.Good else Color3.fromRGB(110, 102, 98)
	holder.BackgroundColor3 = if enabled then Theme.GoodDark else Color3.fromRGB(70, 64, 62)
	refs.Forge.TextColor3 = if enabled then Theme.Text else Theme.TextDim
	refs.Forge:SetAttribute("Ready", enabled)
end

-- The NEXT BLASTER card for a status (FoundryView.status).
function FoundryView.setCard(refs: Refs, status: FoundryLogic.Status, state: any)
	local s = if type(state) == "table" then state else {}
	local recipe = status.Recipe
	local soon = recipe == nil
	refs.Soon.Visible = soon
	local details: { GuiObject } = { refs.LookRow, refs.Ingots, refs.Coins, refs.Uses, refs.UsesRow, refs.Damage }
	for _, item in details do
		item.Visible = not soon
	end
	local forgeHolder = refs.Forge.Parent :: Frame
	forgeHolder.Visible = not soon
	refs.Badge.Text = if soon then "LV 11" else `LV {status.Level}`
	refs.Reason.Text = FoundryView.reasonText(status, s.Coins)
	refs.Reason.TextColor3 = if status.Ready then Theme.Good else Theme.TextDim
	if soon or not recipe then
		refs.BlasterName.Text = "???"
		refs.BlasterName.TextColor3 = Theme.TextDim
		return
	end
	local skin = status.Skin
	local ore = skin and OreData.ById[skin]
	local color = if ore then ore.Color:Lerp(Color3.new(1, 1, 1), 0.25) else Theme.Accent
	refs.BlasterName.Text = BlasterData.displayName(status.Level, skin)
	refs.BlasterName.TextColor3 = color
	refs.Damage.Text = FoundryView.damageText(s.BlasterLevel, s.BlasterOre, status.Level, skin)
	refs.LookSwatch.BackgroundColor3 = if ore then ore.Color else Theme.PanelLight
	refs.LookName.Text = if ore then `Look: {ore.Name}` else "Look: no ingots yet"
	local many = #status.Skins > 1
	for _, button in { refs.LookPrev, refs.LookNext } do
		local holder = button.Parent :: Frame
		holder.Visible = many
	end
	local enoughIngots = status.Have >= status.Need
	refs.Ingots.Text = `Ingots: {math.min(status.Have, status.Need)} / {status.Need}  ({recipe.MinRarity} or better)`
	refs.Ingots.TextColor3 = if enoughIngots then Theme.Good else Theme.Bad
	refs.Coins.Text = `Coins: {Format.money(recipe.Coins)}`
	refs.Coins.TextColor3 = if status.CoinsOk then Theme.Good else Theme.Bad
	refs.Uses.Text = FoundryView.usesText(status)
	FoundryView.setUses(refs, status, FoundryLogic.fromSummary(s.FoundryStock))
	FoundryView.setForgeEnabled(refs, status.Ready)
end

-- The footer: a text hint, or (gamepad) button glyphs.
function FoundryView.setHint(refs: Refs, text: string, glyphA: string?, glyphB: string?)
	local pad = glyphA ~= nil and glyphB ~= nil
	refs.Hint.Text = text
	refs.Hint.Visible = not pad
	refs.PadHint.Visible = pad
	if pad then
		refs.PadA.Image = glyphA :: string
		refs.PadB.Image = glyphB :: string
	end
end

-- Phone layout (taller rows and buttons) or the normal one.
function FoundryView.setCompact(refs: Refs, compact: boolean)
	refs.Compact = compact
	local l = layoutOf(refs)
	refs.Panel.Size = UDim2.fromOffset(l.Width, l.Height)
	local left = refs.List.Parent :: Frame
	left.Size = UDim2.new(0, l.Left, 1, -(HEADER + FOOTER))
	refs.Card.Size = UDim2.new(0, l.Width - l.Left - PAD * 3, 1, -(HEADER + FOOTER))
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Size = UDim2.fromOffset(l.Close, l.Close)
	refs.LookRow.Size = UDim2.new(1, -24, 0, l.Arrow)
	for _, button in { refs.LookPrev, refs.LookNext } do
		local holder = button.Parent :: Frame
		holder.Size = UDim2.fromOffset(l.Arrow, l.Arrow)
	end
	refs.LookSwatch.Position = UDim2.new(0, l.Arrow + 12, 0.5, -2)
	refs.LookName.Position = UDim2.new(0, l.Arrow + 46, 0.5, -2)
	refs.LookName.Size = UDim2.new(1, -(l.Arrow * 2 + 56), 0, 30)
	refs.Ingots.Position = UDim2.fromOffset(14, 108 + l.Arrow)
	refs.Coins.Position = UDim2.fromOffset(14, 134 + l.Arrow)
	refs.Uses.Position = UDim2.fromOffset(14, 160 + l.Arrow)
	refs.UsesRow.Position = UDim2.fromOffset(14, 186 + l.Arrow)
	local forgeHolder = refs.Forge.Parent :: Frame
	forgeHolder.Size = UDim2.new(1, -28, 0, l.Forge)
	refs.TakeMode.Position = UDim2.fromOffset(PAD + l.Left, (HEADER - l.ModeH) // 2)
	refs.TakeMode.Size = UDim2.fromOffset(l.ModeLabel + l.ModeW * 2 + 12, l.ModeH)
	local modeLabel = refs.TakeMode:FindFirstChild("Label")
	if modeLabel and modeLabel:IsA("TextLabel") then
		modeLabel.Size = UDim2.fromOffset(l.ModeLabel, l.ModeH - 5)
	end
	for _, button in { refs.TakeOne, refs.TakeEvery } do
		local holder = button.Parent :: Frame
		holder.Size = UDim2.fromOffset(l.ModeW, l.ModeH - 5)
	end
	refs.PenNote.Size = UDim2.fromOffset(l.Left - SCROLLBAR - 6, l.Note)
	refs.PenNote.TextSize = l.NoteText
	for _, row in refs.Rows do
		layoutRow(refs, row)
	end
end

-- The TAKE switch: ONE (usable rows take one ingot) or ALL (every row takes
-- all of its ore). Call setRows again to relabel the rows.
local function paintSwitch(button: TextButton, on: boolean)
	local holder = button.Parent :: Frame
	button.BackgroundColor3 = if on then Theme.Accent else Theme.PanelLight
	holder.BackgroundColor3 = if on then Theme.AccentDark else Theme.Panel
	button.TextColor3 = if on then Theme.Text else Theme.TextDim
	button:SetAttribute("On", on)
end

function FoundryView.setTakeMode(refs: Refs, all: boolean)
	refs.TakeAllMode = all
	paintSwitch(refs.TakeOne, not all)
	paintSwitch(refs.TakeEvery, all)
end

-- The Ore Pen note: `n` ingots there the next level can use (0 hides it).
-- With an empty stock it goes into the empty text instead.
function FoundryView.setPen(refs: Refs, n: number)
	local text = if n > 0 then FoundryView.penText(n) else ""
	refs.PenNote.Text = text
	refs.PenNote.Visible = n > 0 and next(refs.Rows) ~= nil
	refs.Empty.Text = if n > 0 then "No ingots here yet. " .. text else EMPTY_TEXT
end

-- Shrinks the panel to fit an `areaW` x `areaH` screen area (fitScale).
function FoundryView.fit(refs: Refs, areaW: number, areaH: number, guiScale: number)
	local scale = FoundryView.fitScale(areaW, areaH, guiScale, refs.Compact)
	if math.abs(refs.Fit.Scale - scale) > 0.001 then
		refs.Fit.Scale = scale
	end
end

---------------------------------------------------------------- the hammer moment

function FoundryView.buildForge(touch: boolean): ForgeRefs
	local gui = UIKit.screen("TerraForgeForge", 20)
	gui:SetAttribute("TerraForge", true)
	gui.IgnoreGuiInset = true

	local flash = UIKit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
	}, gui)
	local banner = UIKit.label(gui, "FORGE", 34, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(720, 44),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local sub = UIKit.label(gui, "Tap STRIKE when the ring hits the circle. Every tap counts!", 18, {
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(720, 26),
		TextColor3 = Theme.Text,
	})
	local pips = UIKit.new("Frame", {
		Name = "Pips",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(400, 26),
		BackgroundTransparency = 1,
	}, gui)
	UIKit.list(pips, Enum.FillDirection.Horizontal, 10, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

	-- the ring over the anvil
	local holder = UIKit.new("Frame", {
		Name = "RingHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(120, 120),
		BackgroundTransparency = 1,
	}, gui)
	local target = UIKit.new("Frame", {
		Name = "Target",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.82,
	}, holder)
	UIKit.corner(target, 999)
	UIKit.stroke(target, 5, Theme.Accent)
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(FoundryView.RingStart, FoundryView.RingStart),
		BackgroundTransparency = 1,
	}, holder)
	UIKit.corner(ring, 999)
	local ringStroke = UIKit.stroke(ring, 4, Color3.new(1, 1, 1))
	-- just above the ring (clear of the banner rows on short phone screens)
	local feedback = UIKit.label(gui, "", 44, {
		Name = "Feedback",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.56, -66),
		Size = UDim2.fromOffset(520, 60),
		FontFace = Theme.TitleFont,
		TextTransparency = 1,
	})

	-- STRIKE: bottom right for thumbs, bottom centre with a mouse/keyboard
	local strikeSize = if touch then UDim2.fromOffset(210, 150) else UDim2.fromOffset(300, 92)
	local strike = UIKit.button(gui, "STRIKE!", Theme.Accent, Theme.AccentDark, {
		Name = "Strike",
		AnchorPoint = if touch then Vector2.new(1, 1) else Vector2.new(0.5, 1),
		Position = if touch then UDim2.new(1, -40, 1, -40) else UDim2.new(0.5, 0, 1, -58),
		Size = strikeSize,
		TextSize = if touch then 40 else 38,
		Selectable = false,
	})
	strike.FontFace = Theme.TitleFont
	local strikeHint = UIKit.label(gui, "", 16, {
		Name = "StrikeHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = if touch then UDim2.new(1, -145, 1, -14) else UDim2.new(0.5, 0, 1, -26),
		Size = UDim2.fromOffset(320, 22),
		TextColor3 = Theme.TextDim,
	})
	local leave = UIKit.button(gui, "LEAVE", Theme.Bad, Theme.BadDark, {
		Name = "Leave",
		Position = UDim2.fromOffset(24, 76), -- placeTop moves it below the Roblox top bar
		Size = if touch then UDim2.fromOffset(140, 72) else UDim2.fromOffset(120, 50),
		TextSize = 20,
	})

	-- the reveal card
	local card = UIKit.panel(gui, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(560, 210),
		Visible = false,
	})
	local cardTitle = UIKit.label(card, "NEW BLASTER!", 34, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 42),
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
	})
	local cardName = UIKit.label(card, "", 26, {
		Name = "BlasterName",
		Position = UDim2.fromOffset(16, 54),
		Size = UDim2.new(1, -32, 0, 34),
		FontFace = Theme.TitleFont,
		TextScaled = true,
	})
	local cardLevel = UIKit.label(card, "", 18, {
		Name = "Level",
		Position = UDim2.fromOffset(16, 90),
		Size = UDim2.new(1, -32, 0, 22),
		TextColor3 = Theme.TextDim,
	})
	local cardDamage = UIKit.label(card, "", 18, {
		Name = "Damage",
		Position = UDim2.fromOffset(16, 112),
		Size = UDim2.new(1, -32, 0, 22),
		TextColor3 = Theme.Info,
	})
	local collect = UIKit.button(card, "AWESOME!", Theme.Good, Theme.GoodDark, {
		Name = "Collect",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = if touch then UDim2.fromOffset(260, 64) else UDim2.fromOffset(220, 54),
		TextSize = 24,
	})

	return {
		Gui = gui,
		Banner = banner,
		Sub = sub,
		Pips = pips,
		PipList = {},
		RingHolder = holder,
		Target = target,
		Ring = ring,
		RingStroke = ringStroke,
		Feedback = feedback,
		Strike = strike,
		StrikeHint = strikeHint,
		Leave = leave,
		Flash = flash,
		Card = card,
		CardTitle = cardTitle,
		CardName = cardName,
		CardLevel = cardLevel,
		CardDamage = cardDamage,
		Collect = collect,
	}
end

-- How far (in design pixels) the hammer HUD's top row moves down so it starts
-- below the Roblox top bar: `insetY` screen pixels (GuiService:GetGuiInset)
-- at UI scale `scale`. The top row starts at 52 (the banner).
function FoundryView.topShift(insetY: number, scale: number): number
	local s = if scale > 0 then scale else 1
	return math.max(0, math.ceil((math.max(0, insetY) + 8) / s - 52))
end

-- Moves the banner, the hint, the pips and LEAVE below the top bar.
function FoundryView.placeTop(refs: ForgeRefs, insetY: number, scale: number)
	local shift = FoundryView.topShift(insetY, scale)
	refs.Banner.Position = UDim2.new(0.5, 0, 0, 52 + shift)
	refs.Sub.Position = UDim2.new(0.5, 0, 0, 98 + shift)
	refs.Pips.Position = UDim2.new(0.5, 0, 0, 132 + shift)
	local leaveHolder = refs.Leave.Parent :: Frame
	leaveHolder.Position = UDim2.fromOffset(24, 76 + shift)
end

-- `hits` empty pips (rebuilt), `done` of them filled.
function FoundryView.setPips(refs: ForgeRefs, hits: number, done: number)
	if #refs.PipList ~= hits then
		for _, pip in refs.PipList do
			pip:Destroy()
		end
		table.clear(refs.PipList)
		for i = 1, hits do
			local pip = UIKit.new("Frame", {
				Name = "Pip" .. i,
				LayoutOrder = i,
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = Theme.PanelDark,
				BorderSizePixel = 0,
			}, refs.Pips)
			UIKit.corner(pip, 12)
			UIKit.stroke(pip, 2.5)
			table.insert(refs.PipList, pip)
		end
	end
	for i, pip in refs.PipList do
		pip.BackgroundColor3 = if i <= done then Theme.Accent else Theme.PanelDark
	end
end

-- The reveal card for a new blaster.
function FoundryView.showCard(refs: ForgeRefs, level: number, ore: string?, previousLevel: number, previousOre: string?)
	local info = OreData.ById[ore or ""]
	local rarity = info and Rarity.ById[info.Rarity]
	refs.CardName.Text = BlasterData.displayName(level, ore)
	refs.CardName.TextColor3 = if info then info.Color:Lerp(Color3.new(1, 1, 1), 0.3) else Theme.Accent
	refs.CardLevel.Text = `Blaster level {level}` .. (if rarity then `  -  {rarity.Name} look` else "")
	refs.CardDamage.Text = FoundryView.damageText(previousLevel, previousOre, level, ore)
	refs.Card.Visible = true
	refs.RingHolder.Visible = false
	local strikeHolder = refs.Strike.Parent :: Frame
	strikeHolder.Visible = false
	refs.StrikeHint.Visible = false
	local leaveHolder = refs.Leave.Parent :: Frame
	leaveHolder.Visible = false
	refs.Pips.Visible = false
	refs.Sub.Visible = false
	refs.Banner.Visible = false
	refs.Feedback.TextTransparency = 1
end

---------------------------------------------------------------- the Pop look (UIConfig.LightUI)
--[[
	While the light UI is on (it ships on), the panel wears the bright Pop
	look of the Robux Shop (UI/Pop; owner 2026-10-21: "new, modern,
	colourful, clean items, Roblox style"): an orange header band (the
	window's colour) with shine stripes and studs over a dark studded body;
	the ingot rows painted in their rarity's colour (Pop.rarityPaint) with
	the live 3D ingot, the count and an orange TAKE (rows the next level
	can't use are shaded); the bright NEXT BLASTER card with the live
	blaster of the chosen look in a light burst, the recipe in a dark well
	and a big gold FORGE (grey while it can't). The same instances, names and
	refs as the dark build (the controller and the specs drive both). The
	hammer moment keeps the light skin.
]]

-- The rows: the picture where the old icon was, its light burst behind it.
local function popRowLayout(refs: Refs, row: Row)
	local l = layoutOf(refs)
	local size = l.RowH - 6
	local picture = row.Frame:FindFirstChild("Picture") :: ImageLabel?
	if picture then
		picture.Position = UDim2.fromOffset(4, 3)
		picture.Size = UDim2.fromOffset(size, size)
	end
	local burst = row.Frame:FindFirstChild("Burst") :: Frame?
	if burst then
		burst.Position = UDim2.fromOffset(4 + size / 2, 3 + size / 2)
	end
	local labels: { GuiObject } = { row.Name, row.Chip, row.Detail, row.Count, row.Take }
	for _, label in labels do
		popEdge(label)
	end
end

-- A new ingot row in the Pop look (painted by setRows).
local function popRow(row: Row)
	local frame = row.Frame
	popCard(frame, "Slate", 12, false)
	row.Icon.Visible = false
	Pop.model(frame, "item_Ingot_" .. row.Ore, 50, ingotModel(row.Ore), { Name = "Picture", ZIndex = 5 }, INGOT_FROM)
	-- a row the next level can't use is shaded (its words and TAKE ALL stay bright)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 4,
	}, frame)
	UIKit.corner(shade, 12)
	popText(row.Name)
	popChip(row.Chip, PopTheme.Well)
	popText(row.Detail)
	popText(row.Count, PopTheme.Heavy)
	popButton(row.Take, "Orange")
end

-- The NEXT BLASTER card and the header pieces for the layout (normal / compact).
local function popLayout(refs: Refs)
	local l = layoutOf(refs)
	local band = refs.Panel:FindFirstChild("PopHeader") :: Frame?
	if band then
		band.Size = UDim2.new(1, -8, 0, HEADER - 8)
	end
	local closeHolder = refs.Close.Parent :: Frame
	closeHolder.Position = UDim2.new(1, -PAD, 0, math.max(4, (HEADER - l.Close) // 2))
	refs.Close.TextSize = math.floor(l.Close * 0.6)
	popEdge(refs.Close)
	-- the TAKE switch fits the header band; on phones its buttons reach a
	-- finger's 72 units (44 pt) above and below their faces (the words stay centred)
	for _, button in { refs.TakeOne, refs.TakeEvery } do
		local faceH = (button.Parent :: Frame).Size.Y.Offset
		local extra = if refs.Compact then math.max(0, 72 - faceH) else 0
		button.Position = UDim2.fromOffset(0, -extra / 2)
		button.Size = UDim2.new(1, 0, 1, extra)
	end
	-- the picture right of the name, the damage and the look picker
	local pic = if refs.Compact then 130 else 116
	local picture = refs.Card:FindFirstChild("Picture") :: ImageLabel?
	if picture then
		picture.Position = UDim2.new(1, -10, 0, 34)
		picture.Size = UDim2.fromOffset(pic, pic)
	end
	local burst = refs.Card:FindFirstChild("Burst") :: Frame?
	if burst then
		burst.Position = UDim2.new(1, -10 - pic / 2, 0, 34 + pic / 2)
	end
	local cardW = l.Width - l.Left - PAD * 3
	refs.BlasterName.Size = UDim2.new(1, -(28 + pic + 4), 0, 34)
	refs.Damage.Size = UDim2.new(1, -(28 + pic + 4), 0, 22)
	refs.LookRow.Size = UDim2.new(1, -(24 + pic + 4), 0, l.Arrow)
	local lookRoom = cardW - (24 + pic + 4) - (l.Arrow * 2 + 56)
	refs.LookName.TextSize = FoundryView.fitTextSize(refs.LookName.Text, lookRoom, 19)
	-- the recipe (ingots, coins, what it uses) in a dark well
	local well = refs.Card:FindFirstChild("PopWell") :: Frame?
	if well then
		well.Position = UDim2.fromOffset(8, 102 + l.Arrow)
		well.Size = UDim2.new(1, -16, 0, 116)
	end
	refs.Forge.TextSize = if refs.Compact then 40 else 36
	local labels: { GuiObject } =
		{ refs.BlasterName, refs.Damage, refs.LookName, refs.Ingots, refs.Coins, refs.Uses, refs.Reason, refs.Forge }
	for _, label in labels do
		popEdge(label)
	end
	for _, row in refs.Rows do
		popRowLayout(refs, row)
	end
end

local function popSkin(refs: Refs)
	refs.Gui:SetAttribute("PopSkin", true)
	local panel = refs.Panel
	-- the window: a black frame round a dark studded body, the bright header band
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	local body = panel:FindFirstChildOfClass("UIGradient")
	if body then
		body.Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom)
	end
	local outline = panel:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = PopTheme.Outline
		outline.Thickness = 4
	end
	local round = panel:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0, PopTheme.WindowCorner)
	end
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") then
			child.ZIndex = 4
		end
	end
	Pop.studs(panel, PopTheme.WindowCorner, 0.5, 36, 1)
	local band = UIKit.new("Frame", {
		Name = "PopHeader",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, HEADER - 8),
		ClipsDescendants = true,
		ZIndex = 2,
	}, panel)
	Pop.face(band, FoundryView.PopPaints.Header, 6, false)
	local bandBorder = band:FindFirstChild("Border") :: UIStroke?
	if bandBorder then
		bandBorder.Thickness = 3
	end
	Pop.studs(band, 6, 0.35, 40, 2)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 2,
	}, band)
	for i, s in { { 0.62, 46 }, { 0.70, 22 }, { 0.80, 14 } } do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0),
			Rotation = 32,
			Size = UDim2.new(0, s[2], 2.4, 0),
			ZIndex = 2,
		}, band)
	end
	local title = panel:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		popText(title)
		title.TextSize = 36
		popEdge(title)
		Pop.shadow(title).ZIndex = 3
	end
	popButton(refs.Close, PopTheme.Close)
	refs.Close.FontFace = PopTheme.Heavy
	-- the TAKE [ONE | ALL] switch (setTakeMode paints the picked side)
	local modeLabel = refs.TakeMode:FindFirstChild("Label")
	if modeLabel and modeLabel:IsA("TextLabel") then
		popText(modeLabel)
	end
	popButton(refs.TakeOne, FoundryView.PopPaints.Switch)
	popButton(refs.TakeEvery, "Slate")
	-- the ingot list
	popText(refs.StockHeader)
	refs.List.ScrollBarImageColor3 = Color3.fromRGB(220, 224, 236)
	popEdge(refs.PenNote)
	refs.PenNote.TextColor3 = Color3.fromRGB(150, 220, 255)
	popText(refs.Empty)
	-- the NEXT BLASTER card: bright, the live blaster in a light burst
	local card = refs.Card
	popCard(card, FoundryView.PopPaints.Card, 12, true)
	local cardTitle = card:FindFirstChild("CardTitle")
	if cardTitle and cardTitle:IsA("TextLabel") then
		popText(cardTitle)
	end
	popChip(refs.Badge, Color3.fromRGB(255, 186, 30))
	popEdge(refs.BlasterName)
	popText(refs.Damage)
	popButton(refs.LookPrev, FoundryView.PopPaints.Arrows)
	popButton(refs.LookNext, FoundryView.PopPaints.Arrows)
	local swatch = refs.LookSwatch:FindFirstChildOfClass("UIStroke")
	if swatch then
		swatch.Color = PopTheme.Outline
		swatch.Thickness = 2.5
	end
	popText(refs.LookName)
	local well = UIKit.new("Frame", {
		Name = "PopWell",
		BackgroundColor3 = PopTheme.Well,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, card)
	UIKit.corner(well, 10)
	Pop.border(well, 3)
	Pop.studs(well, 10, 0.6, 36, 4)
	popEdge(refs.Ingots)
	popEdge(refs.Coins)
	popText(refs.Uses)
	popButton(refs.Forge, "Yellow")
	refs.Forge.FontFace = PopTheme.Heavy
	popText(refs.Reason)
	popText(refs.Soon, PopTheme.Heavy)
	Pop.model(card, "blaster", 116, nil, { Name = "Picture", AnchorPoint = Vector2.new(1, 0), ZIndex = 5 }, BLASTER_FROM)
	-- the footer
	popText(refs.Hint)
	for _, child in refs.PadHint:GetChildren() do
		if child:IsA("TextLabel") then
			popText(child)
		end
	end
	popLayout(refs)
	FoundryView.setTakeMode(refs, refs.TakeAllMode)
end

local plainSetRows = FoundryView.setRows
FoundryView.setRows = function(refs: Refs, rows: { OreRow }, total: number): { Row }
	local created = plainSetRows(refs, rows, total)
	if not isPop(refs) then
		return created
	end
	for _, row in created do
		popRow(row)
		popRowLayout(refs, row)
	end
	for index, info in rows do
		local row = refs.Rows[info.Ore]
		if row and index <= FoundryView.MaxRows then
			-- painted in the ore's rarity; the dark build's greys would tint the paint
			row.Frame.BackgroundColor3 = Color3.new(1, 1, 1)
			if row.Frame:GetAttribute("PopRarity") ~= info.Rarity then
				row.Frame:SetAttribute("PopRarity", info.Rarity)
				Pop.repaint(row.Frame, Pop.rarityPaint(info.Rarity), false)
			end
			local shade = row.Frame:FindFirstChild("Shade") :: Frame?
			if shade then
				shade.Visible = not info.Usable
			end
			row.Name.TextColor3 = PopTheme.Ink
			row.Chip.BackgroundColor3 = PopTheme.Well
			row.Detail.TextColor3 = if info.Usable then PopTheme.Ink else Color3.fromRGB(255, 160, 150)
			popEdge(row.Take)
		end
	end
	return created
end

local plainSetForgeEnabled = FoundryView.setForgeEnabled
FoundryView.setForgeEnabled = function(refs: Refs, enabled: boolean)
	plainSetForgeEnabled(refs, enabled)
	if isPop(refs) then
		local holder = refs.Forge.Parent :: Frame
		holder.BackgroundColor3 = Color3.new(1, 1, 1)
		Pop.repaint(holder, if enabled then "Yellow" else PopTheme.Gray)
		refs.Forge.TextColor3 = PopTheme.Ink
	end
end

local plainSetTakeMode = FoundryView.setTakeMode
FoundryView.setTakeMode = function(refs: Refs, all: boolean)
	plainSetTakeMode(refs, all)
	if isPop(refs) then
		local function paint(button: TextButton, on: boolean)
			local holder = button.Parent :: Frame
			holder.BackgroundColor3 = Color3.new(1, 1, 1)
			Pop.repaint(holder, if on then FoundryView.PopPaints.Switch else "Slate")
			button.TextColor3 = PopTheme.Ink
			button.TextTransparency = if on then 0 else 0.25
		end
		paint(refs.TakeOne, not all)
		paint(refs.TakeEvery, all)
	end
end

local plainSetCard = FoundryView.setCard
FoundryView.setCard = function(refs: Refs, status: FoundryLogic.Status, state: any)
	plainSetCard(refs, status, state)
	if not isPop(refs) then
		return
	end
	refs.Reason.TextColor3 = if status.Ready then Color3.fromRGB(190, 255, 150) else PopTheme.Ink
	local picture = refs.Card:FindFirstChild("Picture") :: ImageLabel?
	local soon = status.Recipe == nil
	if picture then
		-- the live blaster this forge would make (built again only when the level or the look changes)
		picture.Visible = not soon
		local view = picture:FindFirstChild("View")
		local key = `{status.Level}|{status.Skin or ""}`
		if not soon and view and view:IsA("ViewportFrame") and view:GetAttribute("Key") ~= key then
			local model = blasterModel(status.Level, status.Skin)
			if model then
				Pop.show(view, model, BLASTER_FROM)
				view:SetAttribute("Key", key)
			end
		end
	end
	local well = refs.Card:FindFirstChild("PopWell") :: Frame?
	if well then
		well.Visible = not soon
	end
	local l = layoutOf(refs)
	local pic = if refs.Compact then 130 else 116
	local lookRoom = l.Width - l.Left - PAD * 3 - (24 + pic + 4) - (l.Arrow * 2 + 56)
	-- (narrow: the ore's name alone, bigger; the arrows and the swatch say it is the look)
	local words = refs.LookName.Text
	if FoundryView.fitTextSize(words, lookRoom, 19) < 16 and string.sub(words, 1, 6) == "Look: " then
		refs.LookName.Text = string.sub(words, 7)
	end
	refs.LookName.TextSize = FoundryView.fitTextSize(refs.LookName.Text, lookRoom, 19)
	popEdge(refs.LookName)
end

local plainSetCompact = FoundryView.setCompact
FoundryView.setCompact = function(refs: Refs, compact: boolean)
	plainSetCompact(refs, compact)
	if isPop(refs) then
		popLayout(refs)
	end
end

local darkBuild = FoundryView.build
FoundryView.build = function(): Refs
	local refs = darkBuild()
	if UIConfig.lightUI() then
		popSkin(refs)
	end
	return refs
end

local darkBuildForge = FoundryView.buildForge
FoundryView.buildForge = function(touch: boolean): ForgeRefs
	local refs = darkBuildForge(touch)
	if UIConfig.lightUI() then
		LightSkin.apply(refs.Gui)
	end
	return refs
end

return FoundryView
