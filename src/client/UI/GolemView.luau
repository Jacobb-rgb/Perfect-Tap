--[[
	The golem inventory (pure builder + pure helpers; GolemController fills
	it in) and the 2D golem portrait every golem screen uses.

	One ScreenGui "TerraForgeGolems" in the bright Pop look of the Robux Shop
	(owner 2026-10-21: "new, modern, colourful, clean items, Roblox style"):
	a purple header band (the Golems colour) over a dark studded body.
	  header    MY GOLEMS, how many you have (12 / 60), DELETE..., CAPSULES
	            (opens the capsule view), the red X
	  equipped  the 3 slots as bright rarity cards (the golem's live 3D
	            picture, name, bonus; "Empty slot"), the total bonus of the
	            equipped golems, EQUIP BEST
	  grid      every golem you own as a painted rarity card on a dark well
	            (light rays behind its live 3D picture, the name, the bonus
	            chip, an E chip when equipped, a LOCKED chip when locked;
	            golems bought with Robux come locked; the picked one has a gold
	            outline): equipped first, then the best (GolemConfig.score),
	            then the oldest. Golems of a kind this version doesn't know
	            show "???" and their drawn portrait.
	  detail    the selected golem as a big painted card: its picture (the
	            controller turns the 3D model in the ViewportFrame "Model"),
	            name, rarity chip, bonus chip, lore and EQUIP (green) /
	            UNEQUIP (grey), LOCK / UNLOCK (blue), DELETE (red).
	            In delete mode it becomes the delete bar: how many are picked,
	            + ALL COMMON / + ALL UNCOMMON, DELETE n, CANCEL (golems that
	            can't be deleted are shaded); a confirm box asks before
	            anything is deleted (and warns when a golem bought with Robux
	            is among them).
	  footer    the control hint or the server's last answer
	The compact layout (phones, TVs) has 44 pt buttons and drops the lore
	when the screen is short. Cards are pooled per golem Id (one live picture
	each). The window never wears the LightSkin (it would recolour the Pop
	faces); Roblox's touch controls hide while it is open.

	portrait(parent, kind, size): a golem drawn from frames, face on, like
	GolemBuilder's (big head under a stone brow, glowing eyes, body with its
	core and ore vein, rock fists, the shoulder boulder and crystal, legs,
	the kind's accessory; Legendary and Mythic float over a glowing aura):
	the picture of a kind this version has no model for.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local PopTheme = require(Shared.Config.PopTheme)
local PictureModels = require(Shared.Builders.PictureModels)
local UIKit = require(script.Parent.UIKit)
local Pop = require(script.Parent.Pop)
local TouchControls = require(script.Parent.Parent.Util.TouchControls)
local TechShopView = require(script.Parent.TechShopView)

local GolemView = {}

GolemView.PhoneScale = TechShopView.PhoneScale
GolemView.MinTouch = TechShopView.MinTouch
GolemView.Separator = "  •  "

export type Card = {
	Id: number,
	Kind: string,
	Known: boolean, -- a kind this version knows
	Name: string,
	Rarity: string,
	Color: Color3, -- rarity color
	Bonus: string, -- "+10% Income" ("" when unknown)
	Lore: string,
	Equipped: boolean,
	Locked: boolean,
	Paid: boolean, -- bought with Robux (saved Paid = true)
	Order: number,
}

export type CardRefs = {
	Button: TextButton,
	Portrait: Frame,
	Name: TextLabel,
	Bonus: TextLabel,
	Equipped: TextLabel,
	Lock: TextLabel,
	Check: TextLabel,
	Stroke: UIStroke,
	Shade: Frame, -- delete mode: this golem can't be deleted
	Kind: string,
}

export type SlotRefs = {
	Frame: Frame,
	Stroke: UIStroke,
	Holder: Frame,
	Name: TextLabel,
	Bonus: TextLabel,
	Kind: string?,
}

export type Refs = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Count: TextLabel,
	Capsules: TextButton,
	DeleteMode: TextButton,
	Close: TextButton,
	Strip: Frame,
	StripLabel: TextLabel,
	Slots: { SlotRefs },
	Totals: TextLabel,
	EquipBest: TextButton,
	GridWell: Frame,
	Grid: ScrollingFrame,
	GridLayout: UIGridLayout,
	Empty: TextLabel,
	Cards: { [number]: CardRefs },
	Detail: Frame,
	DetailHolder: Frame,
	Viewport: ViewportFrame,
	DetailName: TextLabel,
	DetailRarity: TextLabel,
	DetailBonus: TextLabel,
	DetailLore: TextLabel,
	Equip: TextButton,
	Lock: TextButton,
	Delete: TextButton,
	DeleteBar: Frame,
	DeleteText: TextLabel,
	PickCommon: TextButton,
	PickUncommon: TextButton,
	DeleteConfirm: TextButton,
	DeleteCancel: TextButton,
	Confirm: Frame,
	ConfirmBox: Frame,
	ConfirmText: TextLabel,
	ConfirmYes: TextButton,
	ConfirmNo: TextButton,
	Status: TextLabel,
	Hint: TextLabel,
	DetailKind: string?,
	Compact: boolean,
}

local rgb = Color3.fromRGB
local DARK = rgb(26, 22, 26)
local BRASS = rgb(214, 170, 74)
local STEEL = rgb(178, 184, 196)
local GLASS = rgb(170, 230, 255)
local LEAF = rgb(96, 200, 92)
local LEAF_DARK = rgb(52, 120, 56)
local PLUME = rgb(214, 52, 60)
local LAMP_YELLOW = rgb(255, 196, 40)
local LAMP_LIGHT = rgb(255, 244, 190)
local GOLD = rgb(255, 196, 56)
local UNKNOWN = rgb(120, 116, 112)

type Metrics = {
	Width: number,
	Height: number,
	Header: number,
	Strip: number,
	Footer: number,
	Button: number,
	Close: number,
	Cell: Vector2,
	Detail: number, -- detail column width
	Slot: number, -- equipped slot width
	Title: number,
	Text: number,
	Small: number,
}

local PAD = 16
local GAP = 10

local METRICS: { [string]: Metrics } = {
	Normal = {
		Width = 920,
		Height = 590,
		Header = 70,
		Strip = 108,
		Footer = 30,
		Button = 50,
		Close = 54,
		Cell = Vector2.new(128, 152),
		Detail = 300,
		Slot = 196,
		Title = 32,
		Text = 18,
		Small = 15,
	},
	-- phones and TVs: at uiScale 0.62 a 72-unit button is about 44 pt
	Compact = {
		Width = 1180,
		Height = 600,
		Header = 84,
		Strip = 104,
		Footer = 8,
		Button = 72,
		Close = 72,
		Cell = Vector2.new(140, 164),
		Detail = 330,
		Slot = 224, -- (an 11-letter word of a name, DRAGONSCALE, is 8 pt on a 568x320 phone)
		Title = 34,
		Text = 20,
		Small = 17,
	},
}

local function metrics(compact: boolean): Metrics
	return if compact then METRICS.Compact else METRICS.Normal
end

---------------------------------------------------------------- pure helpers

local function num(v: any): number
	return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else 0
end

local function golemsOf(state: any): { [string]: any }
	local golems = if type(state) == "table" then state.Golems else nil
	return if type(golems) == "table" then golems else {}
end

-- Golem Bond from the snapshot's bonuses (State.Bonuses.GolemBond).
local function bondOf(state: any): number
	local bonuses = if type(state) == "table" then state.Bonuses else nil
	return if type(bonuses) == "table" then math.max(0, num(bonuses.GolemBond)) else 0
end

-- One card for an owned entry.
function GolemView.card(entry: any, equipped: boolean, bondPct: number?): Card?
	if type(entry) ~= "table" or type(entry.Id) ~= "number" then
		return nil
	end
	local kind = if type(entry.Kind) == "string" then entry.Kind else "?"
	local golem = GolemConfig.ById[kind]
	local rarity = if golem then Rarity.ById[golem.Rarity] else nil
	return {
		Id = entry.Id,
		Kind = kind,
		Known = golem ~= nil,
		Name = if golem then golem.Name else "???",
		Rarity = if golem then golem.Rarity else "Unknown",
		Color = if rarity then rarity.Color else UNKNOWN,
		Bonus = if golem then GolemConfig.describe(kind, bondPct) else "",
		Lore = if golem then golem.Lore else "A golem from a newer update. Rejoin to see it.",
		Equipped = equipped,
		Locked = entry.Locked == true,
		Paid = entry.Paid == true,
		Order = 0,
	}
end

-- Every owned golem as a card, sorted (see the header), with Order set.
function GolemView.cards(state: any): { Card }
	local golems = golemsOf(state)
	local owned = if type(golems.Owned) == "table" then golems.Owned else {}
	local equippedList = if type(golems.Equipped) == "table" then golems.Equipped else {}
	local bond = bondOf(state)
	local list: { Card } = {}
	for _, entry in owned do
		local card = GolemView.card(entry, false, bond)
		if card then
			card.Equipped = table.find(equippedList, card.Id) ~= nil
			table.insert(list, card)
		end
	end
	table.sort(list, function(a: Card, b: Card): boolean
		if a.Equipped ~= b.Equipped then
			return a.Equipped
		end
		local sa, sb = GolemConfig.score(a.Kind), GolemConfig.score(b.Kind)
		if sa ~= sb then
			return sa > sb
		end
		return a.Id < b.Id
	end)
	for i, card in list do
		card.Order = i
	end
	return list
end

-- The equipped golems in slot order (known kinds only, at most EquipSlots).
function GolemView.equipped(state: any): { Card }
	local golems = golemsOf(state)
	local equippedList = if type(golems.Equipped) == "table" then golems.Equipped else {}
	local bond = bondOf(state)
	local out: { Card } = {}
	for _, id in equippedList do
		local entry = GolemConfig.find(golems, id)
		if entry and GolemConfig.ById[entry.Kind] and #out < GolemConfig.EquipSlots then
			local card = GolemView.card(entry, true, bond)
			if card then
				table.insert(out, card)
			end
		end
	end
	return out
end

-- "+16% Income  •  +10% Mining speed" for the equipped golems (Golem Bond included).
function GolemView.totals(state: any): string
	local stats = GolemConfig.stats(golemsOf(state), bondOf(state))
	local parts = {}
	for _, bonusType in { "Income", "MiningSpeed", "Luck", "SellValue", "WalkSpeed" } do
		local info = GolemConfig.BonusTypes[bonusType]
		local value = stats[info.Stat]
		if value and value > 0 then
			local percent = string.format("%.1f", value * 100):gsub("%.0$", "")
			table.insert(parts, `+{percent}% {info.Label}`)
		end
	end
	if #parts == 0 then
		return "Equip golems to get their bonuses"
	end
	return table.concat(parts, GolemView.Separator)
end

-- How many golems the player has / may have.
function GolemView.countText(state: any): string
	return `{GolemConfig.count(golemsOf(state))} / {GolemConfig.InventoryCap}`
end

-- Ids of every unlocked, unequipped golem of a rarity (the delete helpers).
function GolemView.pickRarity(cards: { Card }, rarityId: string): { number }
	local ids = {}
	for _, card in cards do
		if card.Known and card.Rarity == rarityId and not card.Locked and not card.Equipped then
			table.insert(ids, card.Id)
		end
	end
	return ids
end

-- The confirm text for deleting `ids` (cards = the current list).
function GolemView.confirmText(cards: { Card }, picked: { [number]: boolean }): string
	local n, equipped, paid = 0, 0, 0
	for _, card in cards do
		if picked[card.Id] then
			n += 1
			if card.Equipped then
				equipped += 1
			end
			if card.Paid then
				paid += 1
			end
		end
	end
	local text = `Delete {n} golem{if n == 1 then "" else "s"}? This can't be undone.`
	if equipped > 0 then
		text ..= ` ({equipped} of them {if equipped == 1 then "is" else "are"} equipped.)`
	end
	if paid > 0 then
		local which = if n == 1 then "This golem was" elseif paid == 1 then "1 of them was" else `{paid} of them were`
		text ..= ` {which} bought with Robux: Robux are not refunded.`
	end
	return text
end

---------------------------------------------------------------- followers (GolemController)

-- The follower kinds per slot from the EquippedAttribute ("A,B,C"): slot i
-- = the i-th kind (at most EquipSlots; unknown kinds leave their slot empty).
function GolemView.followerKinds(attribute: any): { [number]: string }
	local out: { [number]: string } = {}
	if type(attribute) ~= "string" or attribute == "" then
		return out
	end
	for i, kind in string.split(attribute, ",") do
		if i > GolemConfig.EquipSlots then
			break
		end
		if GolemConfig.ById[kind] then
			out[i] = kind
		end
	end
	return out
end

--[[
	Which follower models stay when the kinds change (`have` -> `want`, both
	slot -> kind): keep[newSlot] = the old slot whose model moves there (the
	same kind in the same slot first, then the same kind anywhere), and the
	slots that need a new model. An Equip / Unequip builds at most one model.
]]
function GolemView.matchFollowers(have: { [number]: string }, want: { [number]: string }): ({ [number]: number }, { number })
	local keep: { [number]: number } = {}
	local used: { [number]: boolean } = {}
	local build: { number } = {}
	local slots = GolemConfig.EquipSlots
	for slot = 1, slots do
		if want[slot] ~= nil and have[slot] == want[slot] then
			keep[slot] = slot
			used[slot] = true
		end
	end
	for slot = 1, slots do
		local kind = want[slot]
		if kind ~= nil and keep[slot] == nil then
			local found: number? = nil
			for old = 1, slots do
				if not used[old] and have[old] == kind then
					found = old
					break
				end
			end
			if found then
				keep[slot] = found
				used[found] = true
			else
				table.insert(build, slot)
			end
		end
	end
	return keep, build
end

---------------------------------------------------------------- the portrait

local function rect(
	parent: Instance,
	name: string,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	color: Color3,
	z: number,
	round: number?
): Frame
	local frame = UIKit.new("Frame", {
		Name = name,
		Position = UDim2.fromScale(x0, y0),
		Size = UDim2.fromScale(x1 - x0, y1 - y0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	if round then
		UIKit.new("UICorner", { CornerRadius = UDim.new(round, 0) }, frame)
	end
	return frame
end

-- A diamond (a square turned 45 degrees) centered on (x, y).
local function diamond(parent: Instance, name: string, x: number, y: number, s: number, color: Color3, z: number): Frame
	local frame = rect(parent, name, x - s / 2, y - s / 2, x + s / 2, y + s / 2, color, z, 0.15)
	frame.Rotation = 45
	return frame
end

local function shade(c: Color3, amount: number): Color3
	return c:Lerp(DARK, amount)
end

local function tint(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

type Face = { Body: Color3, Trim: Color3, Glow: Color3 }

local PORTRAIT_GEAR: { [string]: (Frame, Face) -> () } = {}

PORTRAIT_GEAR.None = function(p, c)
	rect(p, "Chip", 0.3, 0.07, 0.45, 0.15, c.Trim, 2, 0.2).Rotation = 15
end

PORTRAIT_GEAR.Goggles = function(p, c)
	rect(p, "Strap", 0.16, 0.14, 0.84, 0.21, shade(c.Trim, 0.3), 7)
	for i, x in { 0.27, 0.57 } do
		rect(p, "Goggle" .. i, x, 0.08, x + 0.16, 0.24, BRASS, 8, 0.5)
		rect(p, "Lens" .. i, x + 0.03, 0.11, x + 0.13, 0.21, GLASS, 9, 0.5)
	end
end

PORTRAIT_GEAR.PotHelmet = function(p, _c)
	rect(p, "Pot", 0.19, 0.02, 0.81, 0.19, STEEL, 7, 0.12)
	rect(p, "PotRim", 0.13, 0.16, 0.87, 0.22, shade(STEEL, 0.2), 8, 0.3)
	rect(p, "PotHandle", 0.81, 0.07, 0.92, 0.11, shade(STEEL, 0.3), 7)
end

PORTRAIT_GEAR.CrystalBack = function(p, c)
	diamond(p, "Crystal1", 0.15, 0.2, 0.16, c.Glow, 1)
	diamond(p, "Crystal2", 0.86, 0.24, 0.13, c.Glow, 1)
	diamond(p, "Crystal3", 0.32, 0.06, 0.11, tint(c.Glow, 0.2), 1)
	diamond(p, "Crystal4", 0.72, 0.05, 0.1, tint(c.Glow, 0.2), 1)
end

PORTRAIT_GEAR.SquireHelm = function(p, _c)
	rect(p, "Helm", 0.15, 0.05, 0.85, 0.24, STEEL, 7, 0.14)
	rect(p, "NoseGuard", 0.47, 0.22, 0.53, 0.4, shade(STEEL, 0.15), 8)
	rect(p, "Plume", 0.45, -0.05, 0.55, 0.08, PLUME, 6, 0.4)
end

PORTRAIT_GEAR.Hood = function(p, c)
	rect(p, "Hood", 0.11, 0.06, 0.89, 0.63, c.Trim, 2, 0.26)
	rect(p, "HoodPeak", 0.3, 0.03, 0.7, 0.13, shade(c.Trim, 0.15), 7, 0.4)
	diamond(p, "Rune", 0.5, 0.2, 0.07, c.Glow, 8)
end

PORTRAIT_GEAR.Leaf = function(p, _c)
	rect(p, "Stem", 0.485, 0.03, 0.515, 0.13, LEAF_DARK, 6)
	rect(p, "Leaf1", 0.5, 0.0, 0.69, 0.07, LEAF, 7, 0.5).Rotation = -18
	rect(p, "Leaf2", 0.35, 0.03, 0.5, 0.08, LEAF, 7, 0.5).Rotation = 18
end

PORTRAIT_GEAR.Horns = function(p, c)
	for i, k in { { 0.2, -20 }, { 0.7, 20 } } do
		rect(p, "HornBase" .. i, k[1], 0.06, k[1] + 0.1, 0.17, c.Trim, 2, 0.2).Rotation = k[2]
		rect(p, "HornTip" .. i, k[1] + (if i == 1 then -0.01 else 0.03), -0.01, k[1] + (if i == 1 then 0.06 else 0.1), 0.08, c.Glow, 2, 0.3).Rotation = k[2]
			* 1.6
	end
end

PORTRAIT_GEAR.Visor = function(p, _c)
	rect(p, "VisorFrame", 0.22, 0.24, 0.78, 0.53, BRASS, 5, 0.2)
	local glass = rect(p, "VisorGlass", 0.26, 0.28, 0.74, 0.49, GLASS, 9, 0.18)
	glass.BackgroundTransparency = 0.5
	rect(p, "Valve", 0.43, 0.06, 0.57, 0.13, BRASS, 6, 0.3)
end

PORTRAIT_GEAR.LampHelmet = function(p, _c)
	rect(p, "Helmet", 0.15, 0.04, 0.85, 0.21, LAMP_YELLOW, 7, 0.22)
	rect(p, "Brim", 0.12, 0.18, 0.88, 0.23, shade(LAMP_YELLOW, 0.2), 8, 0.3)
	rect(p, "Lamp", 0.43, 0.06, 0.57, 0.18, LAMP_LIGHT, 9, 0.5)
end

PORTRAIT_GEAR.KnightHelm = function(p, c)
	rect(p, "Helm", 0.15, 0.1, 0.85, 0.62, tint(c.Trim, 0.15), 5, 0.14)
	rect(p, "Slit", 0.27, 0.33, 0.73, 0.43, DARK, 6, 0.2)
	rect(p, "Crest", 0.46, 0.0, 0.54, 0.14, c.Glow, 4, 0.3)
end

PORTRAIT_GEAR.Halo = function(p, c)
	local ring = rect(p, "Halo", 0.3, -0.04, 0.7, 0.06, c.Glow, 6, 0.5)
	ring.BackgroundTransparency = 1
	UIKit.new("UIStroke", { Thickness = 3, Color = c.Glow, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
end

PORTRAIT_GEAR.Crown = function(p, _c)
	rect(p, "CrownBand", 0.3, 0.06, 0.7, 0.13, GOLD, 7, 0.2)
	for i, x in { 0.34, 0.5, 0.66 } do
		diamond(p, "CrownPoint" .. i, x, if i == 2 then 0.045 else 0.065, 0.08, GOLD, 6)
	end
	diamond(p, "CrownGem", 0.5, 0.095, 0.045, rgb(255, 90, 120), 8)
end

---------------------------------------------------------------- the limited Dragonforge gear (GolemGearLimited)

local IVORY = rgb(244, 230, 200)
local SHELL = rgb(252, 240, 214)

-- bat wings behind the body: a membrane and a glowing bone on each side
local function dragonWings(p: Frame, reach: number, membrane: Color3, bone: Color3)
	for i, side in { -1, 1 } do
		local x = 0.5 + side * (0.24 + reach / 2)
		local wing = rect(p, "Wing" .. i, x - reach / 2, 0.24, x + reach / 2, 0.58, membrane, 1, 0.12)
		wing.Rotation = side * 24
		local edge = rect(p, "WingBone" .. i, x - reach / 2, 0.22, x + reach / 2, 0.26, bone, 1, 0.5)
		edge.Rotation = side * 24
	end
end

-- ivory horns growing out of the head's sides and up
local function dragonHorns(p: Frame, color: Color3)
	for i, k in { { 0.08, -35 }, { 0.8, 35 } } do
		rect(p, "HornBase" .. i, k[1], 0.14, k[1] + 0.12, 0.22, color, 3, 0.3).Rotation = k[2]
		rect(p, "HornTip" .. i, k[1] + (if i == 1 then 0.0 else 0.06), 0.02, k[1] + (if i == 1 then 0.06 else 0.12), 0.16, color, 3, 0.4)
	end
end

local function dragonTail(p: Frame, c: Face)
	rect(p, "Tail", 0.74, 0.86, 0.96, 0.92, c.Trim, 1, 0.5).Rotation = -18
	diamond(p, "TailTip", 0.96, 0.83, 0.09, c.Glow, 2)
end

local function dragonSnout(p: Frame, c: Face)
	rect(p, "Snout", 0.36, 0.45, 0.64, 0.55, tint(c.Body, 0.08), 7, 0.3)
end

PORTRAIT_GEAR.DragonHorns = function(p, c)
	dragonWings(p, 0.22, c.Trim:Lerp(c.Glow, 0.4), c.Glow)
	dragonHorns(p, IVORY)
	dragonSnout(p, c)
	dragonTail(p, c)
end

PORTRAIT_GEAR.DragonEgg = function(p, c)
	dragonWings(p, 0.15, c.Glow:Lerp(c.Trim, 0.35), c.Glow:Lerp(c.Trim, 0.35))
	rect(p, "Shell", 0.18, -0.02, 0.82, 0.22, SHELL, 7, 0.5)
	for i, x in { 0.32, 0.5, 0.68 } do
		diamond(p, "ShellPoint" .. i, x, 0.22, 0.08, SHELL, 7)
	end
	rect(p, "Spot1", 0.3, 0.05, 0.38, 0.1, rgb(240, 120, 40), 8, 0.5)
	rect(p, "Spot2", 0.6, 0.02, 0.66, 0.07, rgb(240, 120, 40), 8, 0.5)
	dragonTail(p, c)
end

PORTRAIT_GEAR.DragonHelm = function(p, c)
	rect(p, "Helm", 0.15, 0.1, 0.85, 0.62, c.Trim, 5, 0.14)
	rect(p, "Slit", 0.27, 0.36, 0.73, 0.44, DARK, 6, 0.2)
	rect(p, "Jaw", 0.25, 0.27, 0.75, 0.36, shade(c.Trim, 0.2), 7, 0.25)
	rect(p, "Crest", 0.46, 0.0, 0.54, 0.14, c.Glow, 4, 0.3)
	dragonHorns(p, GOLD)
	rect(p, "Shield", 0.0, 0.6, 0.22, 0.84, shade(c.Trim, 0.1), 8, 0.3)
	diamond(p, "ShieldEye", 0.11, 0.71, 0.08, c.Glow, 9)
end

PORTRAIT_GEAR.DragonWings = function(p, c)
	dragonWings(p, 0.3, c.Trim:Lerp(c.Glow, 0.45), c.Glow)
	dragonHorns(p, IVORY)
	dragonSnout(p, c)
end

PORTRAIT_GEAR.DragonCrown = function(p, c)
	dragonWings(p, 0.34, rgb(160, 28, 36), GOLD)
	rect(p, "CrownBand", 0.28, 0.06, 0.72, 0.14, GOLD, 7, 0.2)
	for i, k in { { 0.34, 0.1 }, { 0.5, 0.13 }, { 0.66, 0.1 } } do
		diamond(p, "Flame" .. i, k[1], 0.06 - k[2] * 0.3, k[2], if i == 2 then rgb(255, 214, 70) else rgb(255, 120, 24), 6)
	end
	rect(p, "Gem", 0.47, 0.08, 0.53, 0.12, c.Glow, 8, 0.4)
end

--[[
	A golem drawn from frames inside a square Frame of `size` design units
	(UDim2 offset; the caller positions it). An unknown kind draws a grey
	golem with a "?" face.
]]
function GolemView.portrait(parent: Instance, kind: string, size: number): Frame
	local golem = GolemConfig.ById[kind]
	local p = UIKit.new("Frame", {
		Name = "Portrait",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, parent)
	local c: Face = if golem
		then { Body = golem.Body, Trim = golem.Trim, Glow = golem.Glow }
		else { Body = UNKNOWN, Trim = shade(UNKNOWN, 0.35), Glow = rgb(230, 230, 230) }
	local gear = if golem then golem.Accessory else "None"
	local closed = gear == "KnightHelm" or gear == "DragonHelm"
	local premium = golem ~= nil and GolemConfig.order(kind) >= Rarity.ById.Legendary.Order
	-- the shadow under the feet (Legendary+: the glowing aura they float on)
	local shadow = rect(p, "Shadow", 0.2, 0.9, 0.8, 0.98, DARK, 1, 0.5)
	shadow.BackgroundTransparency = 0.55
	if premium then
		local aura = rect(p, "Aura", 0.06, 0.88, 0.94, 1.0, c.Glow, 1, 0.5)
		aura.BackgroundTransparency = 0.35
	end
	-- legs, body, arms, rock fists, chest core and its ore vein
	rect(p, "Leg1", 0.33, 0.8, 0.46, 0.95, c.Trim, 2, 0.2)
	rect(p, "Leg2", 0.54, 0.8, 0.67, 0.95, c.Trim, 2, 0.2)
	local body = rect(p, "Body", 0.27, 0.56, 0.73, 0.86, c.Body, 3, 0.16)
	UIKit.new("UIStroke", { Thickness = 1.5, Color = shade(c.Body, 0.45), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	local arm = c.Body:Lerp(c.Trim, 0.3)
	rect(p, "Arm1", 0.15, 0.58, 0.28, 0.78, arm, 2, 0.3)
	rect(p, "Arm2", 0.72, 0.58, 0.85, 0.78, arm, 2, 0.3)
	rect(p, "Fist1", 0.12, 0.72, 0.29, 0.87, c.Trim, 3, 0.22).Rotation = -14
	rect(p, "Fist2", 0.71, 0.72, 0.88, 0.87, c.Trim, 3, 0.22).Rotation = 14
	diamond(p, "Core", 0.5, 0.7, 0.09, c.Glow, 4)
	rect(p, "Vein", 0.37, 0.59, 0.395, 0.69, c.Glow, 4).Rotation = -32
	-- a boulder on the left shoulder, the ore's crystal on the right
	rect(p, "Boulder", 0.12, 0.49, 0.32, 0.62, c.Trim, 5, 0.25).Rotation = 24
	rect(p, "Crystal", 0.75, 0.4, 0.83, 0.6, tint(c.Glow, 0.1), 5, 0.15).Rotation = 22
	-- the big head under a heavy stone brow, the eyes in its shadow
	local head = rect(p, "Head", 0.17, 0.12, 0.83, 0.6, tint(c.Body, 0.05), 4, 0.16)
	UIKit.new("UIStroke", { Thickness = 1.5, Color = shade(c.Body, 0.45), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, head)
	if not closed then
		local under = rect(p, "BrowShadow", 0.22, 0.3, 0.78, 0.47, shade(c.Body, 0.4), 5, 0.4)
		under.BackgroundTransparency = 0.2
		if gear ~= "Visor" then
			rect(p, "Brow", 0.14, 0.23, 0.86, 0.33, shade(c.Trim, 0.1), 6, 0.35)
		end
	end
	if golem then
		local eyeTop = if closed then 0.345 else 0.35
		local eyeBottom = if closed then 0.415 else 0.44
		rect(p, "Eye1", 0.32, eyeTop, 0.44, eyeBottom, c.Glow, 7, 0.15)
		rect(p, "Eye2", 0.56, eyeTop, 0.68, eyeBottom, c.Glow, 7, 0.15)
	else
		local mark = UIKit.label(p, "?", math.floor(size * 0.22), {
			Name = "Unknown",
			Position = UDim2.fromScale(0.25, 0.27),
			Size = UDim2.fromScale(0.5, 0.23),
			ZIndex = 7,
		})
		mark.TextColor3 = c.Glow
	end
	local addGear = PORTRAIT_GEAR[gear] or PORTRAIT_GEAR.None
	addGear(p, c)
	return p
end

---------------------------------------------------------------- the Pop pieces
--[[
	The bright Pop look of the Robux Shop (owner 2026-10-21: "every window
	new, modern, colourful, clean items, Roblox style"), built here so
	Pop.luau stays as it is; CapsuleView uses them too.
	  popButton  a painted button in a holder frame: the holder carries the
	             paint, the black border, the light rim and the studs; the
	             TextButton on top keeps its own Text (controllers write "..."
	             into it) in white with a black edge (a UIGradient on the
	             button itself would tint its word)
	  solidChip  a round chip that IS its TextLabel (a ref's Text / Visible):
	             a solid colour with a soft top light, a black ring, a white
	             word with a black edge
	  glowCard   a painted Frame with light rays, a soft glow, studs and
	             sparkles behind its picture (Pop.card as a plain Frame)
	  picture    a golem's live 3D picture (PictureModels "golem_<Kind>"; the
	             preview draws the rendered icon), or the drawn portrait for a
	             kind this version doesn't know
	  chrome     the window: a black frame, the bright header band in the
	             window's colour (shine, diagonal stripes, studs) over the dark
	             studded body (Pop.window), laid out again by every layout
]]

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

local function apply(instance: Instance, props: { [string]: any }?)
	if props then
		local target: any = instance
		for key, value in props do
			target[key] = value
		end
	end
end

GolemView.WindowPaint = "Purple" -- the golem windows' colour (LightSkin.BandRoles: Golems)
GolemView.SelectColor = rgb(255, 214, 40) -- the gold outline of the picked card
GolemView.BonusColor = PopTheme.Money -- bonuses: the shop's green amounts
GolemView.ChipDark = rgb(30, 32, 40) -- dark chips (bonuses, the count)
GolemView.ButtonCorner = 8
GolemView.CardCorner = 10
-- an empty equipped slot and the delete mode's bar
GolemView.EmptyPaint = { Top = rgb(78, 82, 98), Bottom = rgb(48, 50, 62), Edge = PopTheme.Outline } :: Pop.Paint
GolemView.DeletePaint = { Top = rgb(132, 36, 48), Bottom = rgb(72, 18, 28), Edge = PopTheme.Outline } :: Pop.Paint

-- the paint each Pop button shows while enabled (style() greys it)
local buttonPaints: { [TextButton]: Pop.Paint } = setmetatable({}, { __mode = "k" }) :: any

-- A painted Pop button (see above). Size / Position / AnchorPoint / LayoutOrder /
-- Visible / ZIndex go to the holder, the rest to the button.
function GolemView.popButton(parent: Instance, text: string, paint: string | Pop.Paint, props: { [string]: any }?): TextButton
	local name = if props and type(props.Name) == "string" then props.Name else text
	local holder = UIKit.new("Frame", {
		Name = name .. "Holder",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 52),
		ZIndex = 3,
	}, parent)
	Pop.face(holder, paint, GolemView.ButtonCorner)
	Pop.studs(holder, GolemView.ButtonCorner, 0.45, 28, 2)
	local button = UIKit.new("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = PopTheme.Font,
		Selectable = true,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = PopTheme.Ink,
		TextSize = 22,
		ZIndex = 4,
	}, holder)
	Pop.edge(button, 2.5)
	buttonPaints[button] = Pop.paint(paint)
	if props then
		for key, value in props do
			if
				key == "Size"
				or key == "Position"
				or key == "AnchorPoint"
				or key == "LayoutOrder"
				or key == "Visible"
				or key == "ZIndex"
			then
				(holder :: any)[key] = value
			elseif key ~= "Name" then
				(button :: any)[key] = value
			end
		end
	end
	return button
end

-- A Pop button's enabled paint (repainted now when `enabled`).
function GolemView.setPaint(button: TextButton, paint: string | Pop.Paint, enabled: boolean?)
	buttonPaints[button] = Pop.paint(paint)
	GolemView.style(button, enabled ~= false, Color3.new(), Color3.new())
end

-- A button's look: its paint when enabled, else grey with a dimmer word.
-- (`color` / `dark`: the old look's colours, kept for the callers' signature.)
function GolemView.style(button: TextButton, enabled: boolean, _color: Color3, _dark: Color3)
	local holder = button.Parent
	local paint = buttonPaints[button]
	if paint and holder and holder:IsA("GuiObject") then
		Pop.repaint(holder, if enabled then paint else PopTheme.Gray)
	end
	button.TextColor3 = if enabled then PopTheme.Ink else rgb(214, 218, 228)
end

-- The black edge of a Pop word sized for its text (after a fitText).
function GolemView.fitEdge(label: TextLabel | TextButton)
	local edge = label:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Thickness = Pop.edgeFor(label.TextSize)
	end
end

-- A round chip that is its TextLabel (see above), `color` its face.
function GolemView.solidChip(parent: Instance, text: string, color: Color3, size: Vector2, props: { [string]: any }?): TextLabel
	local chip = UIKit.new("TextLabel", {
		Name = "Chip",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		FontFace = PopTheme.Font,
		Size = UDim2.fromOffset(size.X, size.Y),
		Text = text,
		TextColor3 = PopTheme.Ink,
		TextSize = math.floor(size.Y * 0.64),
		TextWrapped = false,
		ZIndex = 6,
	}, parent)
	UIKit.corner(chip, math.floor(size.Y / 2))
	-- the soft top light (it shades the word a little too, like the old buttons)
	UIKit.new("UIGradient", { Name = "Light", Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(206, 206, 206)), Rotation = 90 }, chip)
	Pop.edge(chip, Pop.edgeFor(chip.TextSize))
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, chip)
	UIKit.corner(ring, math.floor(size.Y / 2))
	Pop.border(ring, 2)
	apply(chip, props)
	return chip
end

-- Sets a chip's size (and its round corners).
function GolemView.sizeChip(chip: TextLabel, w: number, h: number)
	chip.Size = UDim2.fromOffset(w, h)
	local radius = UDim.new(0, math.floor(h / 2))
	local corner = chip:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = radius
	end
	local ring = chip:FindFirstChild("Ring")
	local ringCorner = if ring then ring:FindFirstChildOfClass("UICorner") else nil
	if ringCorner then
		ringCorner.CornerRadius = radius
	end
end

-- The light burst behind a card's picture: the rays texture (or bars), a big
-- soft glow, the studs, a few sparkles (Pop.card's, on any frame).
function GolemView.burst(frame: GuiObject, paint: string | Pop.Paint, size: Vector2, centre: UDim2)
	local p = Pop.paint(paint)
	local short = math.min(size.X, size.Y)
	local long = math.max(size.X, size.Y, 120)
	local rays = Pop.fx(frame, "fx_rays", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageTransparency = 0.35,
		Position = centre,
		Size = UDim2.fromOffset(long * 2.2, long * 2.2),
		ZIndex = 2,
	})
	if not rays then
		Pop.rays(frame, centre, 10, long, 0.6, 2)
	end
	local glow = Pop.fx(frame, "fx_glow", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		ImageColor3 = p.Top:Lerp(Color3.new(1, 1, 1), 0.6),
		ImageTransparency = 0.3,
		Position = centre,
		Size = UDim2.fromOffset(math.floor(short * 1.1), math.floor(short * 1.1)),
		ZIndex = 2,
	})
	if not glow then
		for i, k in { 0.62, 0.42 } do
			local disc = UIKit.new("Frame", {
				Name = "Glow" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = if i == 1 then 0.8 else 0.7,
				BorderSizePixel = 0,
				Position = centre,
				Size = UDim2.fromOffset(math.floor(short * k), math.floor(short * k)),
				ZIndex = 2,
			}, frame)
			UIKit.corner(disc, 999)
		end
	end
	Pop.studs(frame, GolemView.CardCorner, 0.5, 44, 3)
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
	-- a few sparkles (fixed spots per size: the same every build)
	local seed = (math.floor(size.X) * 31 + math.floor(size.Y) * 17) % 997 + 1
	local function next01(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for _ = 1, 3 do
		local sx = 0.12 + next01() * 0.76
		local sy = 0.08 + next01() * 0.5
		Pop.sparkle(frame, UDim2.fromScale(sx, sy), math.floor(14 + next01() * 14), 3, 0.15 + next01() * 0.3)
	end
end

-- Moves a card's rays and glow to `centre` (its picture moved).
function GolemView.aimBurst(frame: Instance, centre: UDim2)
	for _, name in { "Rays", "Glow", "Glow1", "Glow2" } do
		local piece = frame:FindFirstChild(name)
		if piece and piece:IsA("GuiObject") then
			piece.Position = centre
		end
	end
end

-- A painted card Frame with the light burst behind `rayCenter` (default upper middle).
function GolemView.glowCard(parent: Instance, paint: string | Pop.Paint, size: Vector2, props: { [string]: any }?, rayCenter: UDim2?): Frame
	local frame = UIKit.new("Frame", {
		Name = "Card",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 2,
	}, parent)
	Pop.face(frame, paint, GolemView.CardCorner, false)
	apply(frame, props)
	GolemView.burst(frame, paint, size, rayCenter or UDim2.fromScale(0.5, 0.4))
	return frame
end

-- Repaints a card (and its glow's tint).
function GolemView.repaintCard(frame: GuiObject, paint: string | Pop.Paint)
	local p = Pop.paint(paint)
	Pop.repaint(frame, p, false)
	local glow = frame:FindFirstChild("Glow")
	if glow and glow:IsA("ImageLabel") then
		glow.ImageColor3 = p.Top:Lerp(Color3.new(1, 1, 1), 0.6)
	end
end

-- A golem's picture `size` units square (see above).
function GolemView.picture(parent: Instance, kind: string, size: number, props: { [string]: any }?): GuiObject
	if GolemConfig.ById[kind] then
		local model, from = PictureModels.build("golem_" .. kind)
		if model then
			return Pop.model(parent, "golem_" .. kind, size, model, props, from)
		end
	end
	local drawn = GolemView.portrait(parent, kind, size)
	apply(drawn, props)
	return drawn
end

-- A rarity's paint (unknown: slate) and its chip's deep colour.
function GolemView.rarityPaint(rarity: string?): Pop.Paint
	return Pop.rarityPaint(if rarity and Rarity.ById[rarity] then rarity else nil)
end

function GolemView.rarityChip(rarity: string?): Color3
	return GolemView.rarityPaint(rarity).Bottom:Lerp(PopTheme.Outline, 0.3)
end

--[[
	The window chrome on `panel` (see above): the body, the header band in
	`paint` and the white title with its 3D shadow (Title / TitleShadow).
	Children of the panel go on top at ZIndex 3+. Returns the title.
]]
function GolemView.chrome(panel: Frame, title: string, paint: string | Pop.Paint): TextLabel
	panel.BackgroundColor3 = PopTheme.Outline
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	UIKit.corner(panel, PopTheme.WindowCorner)
	Pop.border(panel, 4)
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 1,
	}, panel)
	UIKit.corner(body, 4)
	UIKit.new("UIGradient", { Color = ColorSequence.new(PopTheme.Body, PopTheme.BodyBottom), Rotation = 90 }, body)
	Pop.studs(body, 4, 0.5, 36, 1)
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 1,
	}, body)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, shade)
	local band = UIKit.new("Frame", {
		Name = "Band",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
	}, panel)
	Pop.face(band, paint, 4, false)
	local border = band:FindFirstChild("Border") :: UIStroke
	border.Thickness = 3
	Pop.studs(band, 4, 0.35, 40, 3)
	UIKit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.42, 0),
		ZIndex = 2,
	}, band)
	for i = 1, 3 do
		UIKit.new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = PopTheme.Stripe,
			BorderSizePixel = 0,
			Rotation = 32,
			ZIndex = 2,
		}, band)
	end
	local label = Pop.text(panel, title, 32, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	})
	Pop.shadow(label)
	GolemView.layoutChrome(panel, 70)
	return label
end

local STRIPES = { { 0.62, 46 }, { 0.70, 22 }, { 0.80, 14 } }

-- Places the chrome for a header `h` units tall.
function GolemView.layoutChrome(panel: Frame, h: number)
	local body = panel:FindFirstChild("Body") :: Frame?
	if body then
		body.Position = UDim2.fromOffset(4, h)
		body.Size = UDim2.new(1, -8, 1, -(h + 4))
	end
	local band = panel:FindFirstChild("Band") :: Frame?
	if band then
		band.Position = UDim2.fromOffset(4, 4)
		band.Size = UDim2.new(1, -8, 0, h - 8)
		for i, s in STRIPES do
			local stripe = band:FindFirstChild("Stripe" .. i) :: Frame?
			if stripe then
				stripe.Position = UDim2.new(s[1], (i - 1) * 40, 0.5, 0)
				stripe.Size = UDim2.new(0, s[2], 0, math.floor(h * 2.4))
			end
		end
	end
end

-- Places a title and its 3D shadow (Pop.shadow) in one go.
function GolemView.placeTitle(title: TextLabel, x: number, y: number, w: number, h: number, size: number)
	title.Position = UDim2.fromOffset(x, y)
	title.Size = UDim2.fromOffset(w, h)
	title.TextSize = size
	GolemView.fitEdge(title)
	local parent = title.Parent
	local shadow = if parent then parent:FindFirstChild(title.Name .. "Shadow") else nil
	if shadow and shadow:IsA("TextLabel") then
		shadow.Position = UDim2.fromOffset(x, y + 4)
		shadow.Size = UDim2.fromOffset(w, h)
		shadow.TextSize = size
		shadow.Text = title.Text
		shadow.Visible = title.Visible
		local stroke = shadow:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = Pop.edgeFor(size)
		end
	end
end

-- A small white word with a black edge (Pop.text) for the layouts to place.
function GolemView.text(parent: Instance, text: string, size: number, props: { [string]: any }?): TextLabel
	local label = Pop.text(parent, text, size, {
		Name = "Text",
		TextWrapped = false,
		ZIndex = 5,
	})
	apply(label, props)
	return label
end

---------------------------------------------------------------- the pixel reels
--[[
	The pixel look (owner 2026-10-22, the Roblox UI reels in
	docs/art/ui_pixel_refs: "make the inventory exactly like this"): every
	golem is a square reel card in its rarity's paint (the black outline, a
	darker lip, the light edge, the lattice) with a turning sunburst behind
	its big picture, its name in pixel letters on top and a short pixel
	bonus line at the bottom ("+16% MINING"); the picked card wears a thick
	gold outline and a white ring. Short words (titles, buttons, tags) are
	pixel and shrink to fit; sentences (lore, hints, totals) stay round.
	Only this window's pieces: the shared ones above (CapsuleView uses them)
	keep their look.
]]

GolemView.RayFade = 0.55 -- the sunburst's transparency
GolemView.PickColor = Color3.new(1, 1, 1) -- the picked card's inner ring
-- the short words of the card's bonus line (GolemConfig.BonusTypes labels)
GolemView.ShortBonus = {
	Income = "INCOME",
	["Mining speed"] = "MINING",
	["Ore luck"] = "LUCK",
	["Sell value"] = "SELL",
	["Walk speed"] = "SPEED",
} :: { [string]: string }

-- "+16% Mining speed" -> "+16% MINING" (the reels' short bottom line).
function GolemView.shortBonus(bonus: string): string
	local value, label = string.match(bonus, "^(%S+)%s+(.+)$")
	if not value or not label then
		return string.upper(bonus)
	end
	return `{value} {GolemView.ShortBonus[label] or string.upper(label)}`
end

-- A short word in the pixel font, shrunk to fit its box (Pop.fit).
local function pixel(label: TextLabel | TextButton, size: number)
	local l: any = label
	l.FontFace = PopTheme.Pixel
	l.TextWrapped = false
	Pop.fit(l, size)
end

-- A pixel word sized to leave a margin inside `width` (and at most `size`).
local function fitWord(label: TextLabel | TextButton, size: number, width: number)
	local l: any = label
	local s = size
	while s > 10 and Pop.textWidth(l.Text, s) > width - 12 do
		s -= 1
	end
	Pop.fit(l, s)
end

-- A sentence in the round font at `size` (no shrink-to-fit; fitText sizes it). Round
-- for good (Pop.round): a short status or hint filled in later stays round.
local function round(label: TextLabel, size: number)
	local cut = label.TextTruncate -- (Pop.round clears it; a sentence here is still cut, never spilled)
	Pop.round(label, size)
	label.TextTruncate = cut
end

--[[
	Long names (review 2026-10-22: "HEARTSTONE COLOSSUS" shrank to 5 pt on
	phones): a card's or a slot's name is pixel letters on two lines when
	one line would be smaller than GolemView.NameMin, the size chosen so
	the longer half fits its line. Design units; on phones the UI scale is
	0.62, so 13 units are 8 pt.
]]
GolemView.NameMin = 10 -- PC
GolemView.NameMinCompact = 13 -- phones and TVs
GolemView.NameTwo = 2 -- two lines are at most this much bigger than NameMin (the picture keeps its room)
GolemView.NameLine = 1.1 -- a pixel line's height in em (Press Start 2P is 1 em: room to spare)

local function letters(text: string): number
	return utf8.len(text) or #text
end

-- The letters of the longer line when `text` is split at its best space (all of it: no space).
local function halfLetters(text: string): number
	local words = string.split(text, " ")
	local best = letters(text)
	for i = 1, #words - 1 do
		local a = letters(table.concat(words, " ", 1, i))
		local b = letters(table.concat(words, " ", i + 1))
		best = math.min(best, math.max(a, b))
	end
	return best
end

--[[
	The pixel TextSize (at most `max`) at which `text` fills `width` design
	units on `lines` lines (1 or 2; two lines stay under `floor` + NameTwo).
]]
function GolemView.nameSize(text: string, max: number, width: number, lines: number, floor: number): number
	local widest = if lines > 1 then halfLetters(text) else letters(text)
	local top = if lines > 1 then math.min(max, floor + GolemView.NameTwo) else max
	return math.max(1, math.min(top, math.floor(width / math.max(1, widest))))
end

--[[
	(size, lines) for a name in `width` design units: one line when it is at
	least `floor` there (or it has no space), else two lines when that is bigger.
]]
function GolemView.nameFit(text: string, max: number, width: number, floor: number): (number, number)
	local one = GolemView.nameSize(text, max, width, 1, floor)
	if one >= floor or not string.find(text, " ", 1, true) then
		return one, 1
	end
	local two = GolemView.nameSize(text, max, width, 2, floor)
	if two > one then
		return two, 2
	end
	return one, 1
end

-- The box height `lines` pixel lines of `size` need.
function GolemView.nameHeight(size: number, lines: number): number
	return math.ceil(lines * size * GolemView.NameLine) + 2
end

--[[
	Shows a pixel name at `size` on `lines` lines: TextScaled under a
	constraint that never lets it grow past `size` (Roblox only shrinks it
	if the font runs wider than the estimate), cut with "..." as a last resort.
]]
local function setName(label: TextLabel, size: number, lines: number)
	label.FontFace = PopTheme.Pixel
	label.TextWrapped = lines > 1
	label.TextScaled = true
	label.TextSize = size
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label:SetAttribute("NameLines", lines)
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not limit then
		limit = UIKit.new("UITextSizeConstraint", { Name = "Fit" }, label)
	end
	local l = limit :: UITextSizeConstraint
	l.MinTextSize = 1
	l.MaxTextSize = size
	l.MinTextSize = math.min(size, PopTheme.PixelMin)
	local edge = label:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.LineJoinMode = Enum.LineJoinMode.Miter
	end
end

-- Keeps a pixel word off a button's lip and its sides.
local function padWord(object: GuiObject, side: number, lip: number)
	local pad = object:FindFirstChildOfClass("UIPadding") or UIKit.new("UIPadding", {}, object)
	local p = pad :: UIPadding
	p.PaddingLeft = UDim.new(0, side)
	p.PaddingRight = UDim.new(0, side)
	p.PaddingTop = UDim.new(0, 2)
	p.PaddingBottom = UDim.new(0, lip)
end

-- A Pop button (GolemView.popButton) with a pixel word.
local function reelButton(parent: Instance, text: string, paint: string | Pop.Paint, props: { [string]: any }?): TextButton
	local button = GolemView.popButton(parent, text, paint, props)
	button:SetAttribute("WordSize", button.TextSize)
	pixel(button, button.TextSize)
	padWord(button, 6, 6)
	local holder = holderOf(button)
	Pop.gleam(holder, 2)
	Pop.fxTag(holder, "Press")
	return button
end

-- A small tag with a pixel word (EQUIPPED, LOCKED, the rarity, the count).
local function reelTag(parent: Instance, text: string, color: Color3, size: Vector2, props: { [string]: any }?): TextLabel
	local chip = GolemView.solidChip(parent, text, color, size, props)
	pixel(chip, math.floor(size.Y * 0.8))
	padWord(chip, 5, 2)
	return chip
end

--[[
	Paints `frame` as a reel card: the paint with its lip and light edge, the
	lattice, and the sunburst (Pop.rays, turning) with a soft glow behind
	`centre` (inside the lattice's clip). The frame's Size must be set first
	(the lip and the lattice follow it).
]]
local function reelFace(frame: GuiObject, paint: string | Pop.Paint, corner: number, centre: UDim2, reach: number)
	Pop.face(frame, paint, corner)
	local clip = Pop.studs(frame, corner, 0.45, 30, 2) :: Frame
	Pop.rays(clip, centre, 8, reach, GolemView.RayFade, 2)
	local short = math.min(frame.Size.X.Offset, frame.Size.Y.Offset, 220)
	for i, k in { 0.7, 0.46 } do
		local disc = UIKit.new("Frame", {
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = if i == 1 then 0.82 else 0.72,
			BorderSizePixel = 0,
			Position = centre,
			Size = UDim2.fromOffset(math.floor(short * k), math.floor(short * k)),
			ZIndex = 2,
		}, clip)
		UIKit.corner(disc, 999)
	end
	local rim = frame:FindFirstChild("Rim") :: Frame?
	if rim then
		rim.ZIndex = 3
	end
end

-- Moves a reel card's sunburst and glow to `centre` (its picture moved).
local function aimReel(frame: Instance, centre: UDim2)
	local clip = frame:FindFirstChild("Lattice")
	if not clip then
		return
	end
	-- (the clip sits 3 units inside the card)
	local at = centre - UDim2.fromOffset(3, 3)
	for _, name in { "Rays", "Glow1", "Glow2" } do
		local piece = clip:FindFirstChild(name)
		if piece and piece:IsA("GuiObject") then
			piece.Position = at
		end
	end
end

-- Repaints a reel card (keeping its lip).
local function repaintReel(frame: GuiObject, paint: string | Pop.Paint)
	Pop.repaint(frame, paint)
end

-- The window's header band in the reels' look: the lattice and a gleam (no shine stripes).
local function reelBand(panel: Frame)
	local band = panel:FindFirstChild("Band")
	if not band or not band:IsA("Frame") then
		return
	end
	for _, child in band:GetChildren() do
		if child.Name == "Shine" or string.sub(child.Name, 1, 6) == "Stripe" then
			child:Destroy()
		end
	end
	Pop.gleam(band, 3)
end

-- The grid card's rows: the pixel name on top, the bonus line at the bottom.
local CARD_TITLE = 26
local CARD_LINE = 22

local function nameMin(m: Metrics): number
	return if m == METRICS.Compact then GolemView.NameMinCompact else GolemView.NameMin
end

-- The biggest a grid card's name gets (Pop.fit's size for it) and a slot's.
local function cardNameMax(m: Metrics): number
	return math.floor((m.Small + 5) * PopTheme.PixelScale + 0.5)
end

local function slotNameMax(m: Metrics): number
	return math.floor((m.Small + 3) * PopTheme.PixelScale + 0.5)
end

-- (size, lines) of a grid card's name in a cell `cellW` wide (the name box is 10 narrower; 2 to spare).
local function cardName(text: string, cellW: number, m: Metrics): (number, number)
	return GolemView.nameFit(text, cardNameMax(m), cellW - 12, nameMin(m))
end

---------------------------------------------------------------- building

local function newCard(refs: Refs, card: Card, m: Metrics): CardRefs
	local w, h = m.Cell.X, m.Cell.Y
	local button = UIKit.new("TextButton", {
		Name = "Golem" .. card.Id,
		AutoButtonColor = false,
		ClipsDescendants = true,
		LayoutOrder = card.Order,
		Selectable = true,
		Size = UDim2.fromOffset(w, h),
		Text = "",
		ZIndex = 2,
	}, refs.Grid)
	local lip = Pop.lipUnits(h)
	-- (a long name takes two lines: the picture moves down under it)
	local nameText = string.upper(card.Name)
	local cellW = math.max(w, refs.GridLayout.CellSize.X.Offset)
	local nameSize, nameLines = cardName(nameText, cellW, m)
	local nameH = if nameLines > 1 then GolemView.nameHeight(nameSize, nameLines) else CARD_TITLE - 6
	local picTop = math.max(CARD_TITLE, 5 + nameH + 1)
	local size = math.min(w - 18, h - picTop - CARD_LINE - lip - 2)
	reelFace(
		button,
		GolemView.rarityPaint(if card.Known then card.Rarity else nil),
		GolemView.CardCorner,
		UDim2.new(0.5, 0, 0, picTop + size / 2),
		math.floor(math.max(w, h) * 0.8)
	)
	Pop.fxTag(button, "Press")
	local stroke = button:FindFirstChild("Border") :: UIStroke
	local portrait = UIKit.new("Frame", {
		Name = "Portrait",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, picTop),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 4,
	}, button)
	local picture = GolemView.picture(portrait, card.Kind, size, { ZIndex = 4 })
	Pop.fxTag(picture, "Lean")
	local name = GolemView.text(button, nameText, m.Small + 5, {
		Name = "GolemName",
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.new(1, -10, 0, nameH),
		ZIndex = 6,
	})
	setName(name, nameSize, nameLines)
	local bonus = GolemView.text(button, GolemView.shortBonus(card.Bonus), m.Small + 2, {
		Name = "Bonus",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(lip + 2)),
		Size = UDim2.new(1, -10, 0, CARD_LINE - 4),
		TextColor3 = GolemView.BonusColor,
		ZIndex = 6,
	})
	-- tilted tags beside the picture (the reels' price tags)
	local equipped = reelTag(button, "E", Pop.paint("Green").Bottom, Vector2.new(30, 26), {
		Name = "EquippedBadge",
		Position = UDim2.fromOffset(6, picTop + 2),
		Rotation = -10,
		ZIndex = 7,
	})
	-- a state, not a button: "LOCKED"
	local lock = reelTag(button, "LOCKED", Pop.paint("Blue").Bottom, Vector2.new(70, 22), {
		Name = "LockBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, picTop + 4),
		Rotation = 10,
		ZIndex = 7,
	})
	local check = reelTag(button, "", GolemView.ChipDark, Vector2.new(32, 32), {
		Name = "Check",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, picTop + 2),
		Visible = false,
		ZIndex = 8,
	})
	-- the picked card: a white ring inside the gold outline
	local ring = UIKit.new("Frame", {
		Name = "Pick",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		Visible = false,
		ZIndex = 7,
	}, button)
	UIKit.corner(ring, GolemView.CardCorner - 4)
	UIKit.new("UIStroke", {
		Name = "Ring",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = GolemView.PickColor,
		Thickness = 3,
	}, ring)
	-- delete mode: a golem that can't be deleted (locked, unknown) is shaded
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 7,
	}, button)
	UIKit.corner(shade, PopTheme.Corner)
	local refsCard: CardRefs = {
		Button = button,
		Portrait = portrait,
		Name = name,
		Bonus = bonus,
		Equipped = equipped,
		Lock = lock,
		Check = check,
		Stroke = stroke,
		Shade = shade,
		Kind = card.Kind,
	}
	refs.Cards[card.Id] = refsCard
	return refsCard
end

local function slot(parent: Instance, index: number, m: Metrics): SlotRefs
	local h = m.Strip - 30
	local pic = m.Strip - 34
	-- a wide reel card: the picture on its sunburst at the left, the pixel name and bonus right of it
	local frame = UIKit.new("Frame", {
		Name = "Slot" .. index,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = index,
		Size = UDim2.fromOffset(m.Slot, h),
		ZIndex = 4,
	}, parent)
	reelFace(frame, GolemView.EmptyPaint, GolemView.CardCorner, UDim2.fromOffset(4 + pic / 2, h / 2), math.floor(h * 1.1))
	local stroke = frame:FindFirstChild("Border") :: UIStroke
	local holder = UIKit.new("Frame", {
		Name = "Holder",
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.fromOffset(pic, pic),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, frame)
	local lip = Pop.lipUnits(h)
	-- (the name and bonus column runs close to the edge: a long name gets its letters' room)
	local textX = pic + 4
	local name = GolemView.text(frame, "EMPTY", m.Small + 3, {
		Name = "GolemName",
		Position = UDim2.fromOffset(textX, 8),
		Size = UDim2.new(1, -(textX + 4), 0, math.floor((h - lip) / 2) - 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(214, 218, 228),
		ZIndex = 6,
	})
	local bonus = GolemView.text(frame, "", m.Small + 1, {
		Name = "Bonus",
		Position = UDim2.fromOffset(textX, math.floor((h - lip) / 2) + 2),
		Size = UDim2.new(1, -(textX + 4), 0, math.floor((h - lip) / 2) - 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GolemView.BonusColor,
		ZIndex = 6,
	})
	return { Frame = frame, Stroke = stroke, Holder = holder, Name = name, Bonus = bonus, Kind = nil }
end

function GolemView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local m = metrics(isCompact)
	local gui = UIKit.screen("TerraForgeGolems", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)
	gui:SetAttribute("PopSkin", true) -- the Pop look: no LightSkin (it would recolour the faces)

	local panel = UIKit.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(m.Width, m.Height),
		Active = true,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, gui)
	local title = GolemView.chrome(panel, "MY GOLEMS", GolemView.WindowPaint)
	reelBand(panel)
	local count = reelTag(panel, "0 / 60", GolemView.ChipDark, Vector2.new(96, 30), {
		Name = "Count",
		ZIndex = 6,
	})
	local capsules = reelButton(panel, "EGGS", "Yellow", {
		Name = "Capsules",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 20,
	})
	local deleteMode = reelButton(panel, "DELETE...", "Red", {
		Name = "DeleteMode",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 19,
	})
	local close = reelButton(panel, "X", PopTheme.Close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		FontFace = PopTheme.Heavy,
		TextSize = 34,
		ZIndex = 6,
	})

	-- the equipped strip: three bright slots
	local strip = UIKit.new("Frame", { Name = "Strip", BackgroundTransparency = 1, ZIndex = 3 }, panel)
	local stripLabel = GolemView.text(strip, "EQUIPPED (3 SLOTS)", m.Small, {
		Name = "Label",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(3 * m.Slot + 2 * GAP, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local slotRow = UIKit.new("Frame", {
		Name = "Slots",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.fromOffset(3 * m.Slot + 2 * GAP, m.Strip - 30),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, strip)
	UIKit.list(slotRow, Enum.FillDirection.Horizontal, GAP)
	local slots = {}
	for i = 1, GolemConfig.EquipSlots do
		table.insert(slots, slot(slotRow, i, m))
	end
	local totals = GolemView.text(strip, "", m.Small, {
		Name = "Totals",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = GolemView.BonusColor,
		-- never runs out of its box (fitText shrinks it first)
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	round(totals, m.Small)
	local equipBest = reelButton(strip, "EQUIP BEST", "Green", {
		Name = "EquipBest",
		TextSize = 20,
	})

	-- the grid of owned golems on a dark studded well
	local gridWell = Pop.well(panel, { Name = "GridWell", ZIndex = 3 })
	local grid = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = rgb(220, 224, 236),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		ZIndex = 4,
	}, panel)
	local gridLayout = UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(m.Cell.X, m.Cell.Y),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 10),
	}, grid)
	local empty = GolemView.text(panel, "No golems yet. Open a capsule at the CAPSULES stall in town!", m.Text, {
		Name = "Empty",
		TextWrapped = true,
		Visible = false,
	})
	round(empty, m.Text)

	-- the detail: a big painted card of the picked golem
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(m.Detail, 420),
		ZIndex = 3,
	}, panel)
	reelFace(detail, GolemView.EmptyPaint, GolemView.CardCorner, UDim2.new(0.5, 0, 0, 120), math.floor(m.Detail * 0.9))
	local detailHolder = UIKit.new("Frame", {
		Name = "PortraitHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, detail)
	local viewport = UIKit.new("ViewportFrame", {
		Name = "Model",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Ambient = rgb(170, 170, 180),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, 0.6),
		Visible = false,
		ZIndex = 4,
	}, detail)
	local detailName = GolemView.text(detail, "", m.Text + 10, {
		Name = "GolemName",
		ZIndex = 6,
	})
	local detailRarity = reelTag(detail, "", GolemView.ChipDark, Vector2.new(150, 26), {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
	})
	local detailBonus = reelTag(detail, "", GolemView.ChipDark, Vector2.new(200, 28), {
		Name = "Bonus",
		TextColor3 = GolemView.BonusColor,
	})
	local detailLore = GolemView.text(detail, "", m.Small - 1, {
		Name = "Lore",
		BackgroundColor3 = PopTheme.Outline,
		BackgroundTransparency = 0.5,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = rgb(236, 238, 244),
	})
	round(detailLore, m.Small - 1)
	UIKit.corner(detailLore, 8)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, detailLore)
	local equip = reelButton(detail, "EQUIP", "Green", { Name = "Equip", TextSize = 20, ZIndex = 6 })
	local lock = reelButton(detail, "LOCK", "Blue", { Name = "Lock", TextSize = 18, ZIndex = 6 })
	local delete = reelButton(detail, "DELETE", "Red", { Name = "Delete", TextSize = 18, ZIndex = 6 })

	-- delete mode: a deep red bar replaces the detail card
	local deleteBar = UIKit.new("Frame", {
		Name = "DeleteBar",
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, panel)
	Pop.face(deleteBar, GolemView.DeletePaint, GolemView.CardCorner)
	Pop.studs(deleteBar, GolemView.CardCorner, 0.55, 44, 2)
	local deleteText = GolemView.text(deleteBar, "", m.Text, {
		Name = "Text",
		TextWrapped = true,
	})
	round(deleteText, m.Text)
	local pickCommon = reelButton(deleteBar, "+ ALL COMMON", "Slate", { Name = "PickCommon", TextSize = 17 })
	local pickUncommon = reelButton(deleteBar, "+ ALL UNCOMMON", "Green", { Name = "PickUncommon", TextSize = 17 })
	local deleteConfirm = reelButton(deleteBar, "DELETE 0", "Red", { Name = "DeleteConfirm", TextSize = 20 })
	local deleteCancel = reelButton(deleteBar, "CANCEL", PopTheme.Gray, { Name = "DeleteCancel", TextSize = 20 })

	-- the confirm box (over everything): a small red Pop window
	local confirm = UIKit.new("Frame", {
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Active = true,
	}, panel)
	UIKit.corner(confirm, PopTheme.WindowCorner)
	local box = UIKit.new("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Active = true,
		ZIndex = 21,
	}, confirm)
	GolemView.chrome(box, "DELETE GOLEMS?", "Red")
	reelBand(box)
	local confirmText = GolemView.text(box, "", m.Text + 2, {
		Name = "Text",
		TextWrapped = true,
		ZIndex = 5,
	})
	round(confirmText, m.Text + 2)
	local confirmYes = reelButton(box, "DELETE", "Red", {
		Name = "Yes",
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 22,
		ZIndex = 6,
	})
	local confirmNo = reelButton(box, "KEEP", "Green", {
		Name = "No",
		AnchorPoint = Vector2.new(0, 1),
		TextSize = 22,
		ZIndex = 6,
	})

	local status = GolemView.text(panel, "", m.Small, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.Info,
		Visible = false,
	})
	local hint = GolemView.text(panel, "", m.Small, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = rgb(200, 205, 218),
	})
	-- (sentences: the round font)
	round(status, m.Small)
	round(hint, m.Small)

	local refs: Refs = {
		Gui = gui,
		Panel = panel,
		Title = title,
		Count = count,
		Capsules = capsules,
		DeleteMode = deleteMode,
		Close = close,
		Strip = strip,
		StripLabel = stripLabel,
		Slots = slots,
		Totals = totals,
		EquipBest = equipBest,
		GridWell = gridWell,
		Grid = grid,
		GridLayout = gridLayout,
		Empty = empty,
		Cards = {},
		Detail = detail,
		DetailHolder = detailHolder,
		Viewport = viewport,
		DetailName = detailName,
		DetailRarity = detailRarity,
		DetailBonus = detailBonus,
		DetailLore = detailLore,
		Equip = equip,
		Lock = lock,
		Delete = delete,
		DeleteBar = deleteBar,
		DeleteText = deleteText,
		PickCommon = pickCommon,
		PickUncommon = pickUncommon,
		DeleteConfirm = deleteConfirm,
		DeleteCancel = deleteCancel,
		Confirm = confirm,
		ConfirmBox = box,
		ConfirmText = confirmText,
		ConfirmYes = confirmYes,
		ConfirmNo = confirmNo,
		Status = status,
		Hint = hint,
		DetailKind = nil,
		Compact = isCompact,
	}
	GolemView.layout(refs, isCompact, math.huge, math.huge)
	GolemView.setDetail(refs, nil)
	-- like every window: Roblox's touch controls hide while it is open
	TouchControls.follow(gui)
	return refs
end

---------------------------------------------------------------- layout

local function place(object: GuiObject, x: number, y: number, w: number, h: number)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
end

local function placeButton(button: TextButton, x: number, y: number, w: number, h: number)
	local holder = holderOf(button)
	holder.AnchorPoint = Vector2.new(0, 0)
	place(holder, x, y, w, h)
end

--[[
	Fits the panel into `maxWidth` x `maxHeight` design units (the screen at
	the HUD's scale): the normal or compact metrics, shrunk to the space
	(never narrower than three cards plus the detail column).
]]
function GolemView.layout(refs: Refs, compact: boolean, maxWidth: number, maxHeight: number)
	local m = metrics(compact)
	local width = math.min(m.Width, maxWidth - 2 * 8)
	local height = math.min(m.Height, maxHeight - 2 * 6)
	width = math.max(width, 3 * (m.Cell.X + 8) + m.Detail + 3 * PAD + 12)
	height = math.max(height, 380)
	refs.Panel.Size = UDim2.fromOffset(width, height)

	-- header: the band, the title and its count, DELETE... / CAPSULES / X
	local h = m.Header
	GolemView.layoutChrome(refs.Panel, h)
	local titleSize = m.Title + 4
	local titleW = math.ceil(TechShopView.textWidth(refs.Title.Text, titleSize)) + 8
	GolemView.placeTitle(refs.Title, PAD + 4, 4, titleW, h - 12, titleSize)
	GolemView.sizeChip(refs.Count, if compact then 108 else 96, if compact then 34 else 30)
	refs.Count.TextSize = if compact then 20 else 18
	refs.Count.Position = UDim2.fromOffset(PAD + 4 + titleW + 8, math.floor((h - refs.Count.Size.Y.Offset) / 2))
	local closeHolder = holderOf(refs.Close)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -(PAD - 4), 0, math.floor((h - m.Close) / 2))
	closeHolder.Size = UDim2.fromOffset(m.Close, m.Close)
	refs.Close.TextSize = math.floor(m.Close * 0.62)
	local capsW = if compact then 190 else 160
	local capsHolder = holderOf(refs.Capsules)
	capsHolder.AnchorPoint = Vector2.new(1, 0)
	capsHolder.Position = UDim2.new(1, -(PAD - 4 + m.Close + GAP), 0, math.floor((h - m.Button) / 2))
	capsHolder.Size = UDim2.fromOffset(capsW, m.Button)
	local deleteHolder = holderOf(refs.DeleteMode)
	deleteHolder.AnchorPoint = Vector2.new(1, 0)
	deleteHolder.Position = UDim2.new(1, -(PAD - 4 + m.Close + 2 * GAP + capsW), 0, math.floor((h - m.Button) / 2))
	deleteHolder.Size = UDim2.fromOffset(if compact then 170 else 136, m.Button)

	-- equipped strip
	local stripY = h + 6
	place(refs.Strip, PAD, stripY, width - 2 * PAD, m.Strip)
	local slotsWidth = 3 * m.Slot + 2 * GAP
	local rightX = slotsWidth + GAP + 4
	local rightW = width - 2 * PAD - rightX
	local bestH = if compact then m.Button else 46
	if compact then
		-- phones / TVs: EQUIP BEST is as tall as the slot row, so the totals
		-- line goes on the strip's title row, right of "EQUIPPED (3 SLOTS)"
		-- (one line; never under the button)
		local label = refs.Strip:FindFirstChild("Label")
		local labelEnd = if label and label:IsA("TextLabel")
			then math.ceil(TechShopView.textWidth(label.Text, label.TextSize)) + 16
			else 220
		local totalsW = width - 2 * PAD - labelEnd
		refs.Totals.TextWrapped = false
		refs.Totals.TextXAlignment = Enum.TextXAlignment.Right
		place(refs.Totals, labelEnd, 0, totalsW, 22)
		TechShopView.fitText(refs.Totals, totalsW, 22, m.Small, 11)
		bestH = math.min(bestH, m.Strip - 30)
		placeButton(refs.EquipBest, rightX, 26, math.min(rightW, 220), bestH)
	else
		refs.Totals.TextWrapped = true
		refs.Totals.TextXAlignment = Enum.TextXAlignment.Left
		place(refs.Totals, rightX, 4, rightW, m.Strip - bestH - 14)
		TechShopView.fitText(refs.Totals, rightW, m.Strip - bestH - 14, m.Small, 11)
		placeButton(refs.EquipBest, rightX, m.Strip - bestH - 4, math.min(rightW, 220), bestH)
	end
	GolemView.fitEdge(refs.Totals)

	-- body: the grid on its well on the left, the detail card on the right
	local bodyY = stripY + m.Strip + 6
	local footer = m.Footer
	local bodyH = height - bodyY - footer - 8
	local detailX = width - PAD - m.Detail
	local gridW = detailX - PAD - GAP
	place(refs.GridWell, PAD - 4, bodyY - 4, gridW + 8, bodyH + 8)
	place(refs.Grid, PAD, bodyY, gridW, bodyH)
	-- as many whole columns as fit, the cards widened to fill the row (no
	-- empty gap before the detail column; the scroll bar keeps its room)
	local cellPad = refs.GridLayout.CellPadding.X.Offset
	local usable = gridW - refs.Grid.ScrollBarThickness - 4
	local columns = math.max(1, math.floor((usable + cellPad) / (m.Cell.X + cellPad)))
	local cellW = math.max(m.Cell.X, math.floor((usable - (columns - 1) * cellPad) / columns))
	refs.GridLayout.CellSize = UDim2.fromOffset(cellW, m.Cell.Y)
	-- (the names follow the cells' width; a card keeps the lines it was built with)
	for _, c in refs.Cards do
		local lines = c.Name:GetAttribute("NameLines")
		local n = if type(lines) == "number" then lines else 1
		setName(c.Name, GolemView.nameSize(c.Name.Text, cardNameMax(m), cellW - 12, n, nameMin(m)), n)
	end
	place(refs.Empty, PAD + 20, bodyY + 20, gridW - 40, bodyH - 40)
	place(refs.Detail, detailX, bodyY - 4, m.Detail, bodyH + 8)
	place(refs.DeleteBar, detailX, bodyY - 4, m.Detail, bodyH + 8)

	-- detail card: the picture (when there is room), name, rarity, bonus,
	-- lore (when there is room), buttons
	local inner = m.Detail - 24
	local buttonH = m.Button
	local texts = 30 + 6 + 26 + 6 + 28 -- name, rarity, bonus
	local spare = bodyH - (8 + texts + 10 + buttonH + 12)
	local portrait = math.min(math.max(0, spare - 46), if compact then 150 else 140)
	if portrait < 56 then
		portrait = 0 -- short screens: the grid's pictures are enough
	end
	local loreH = spare - portrait - (if portrait > 0 then 6 else 0)
	-- (the reels: the pixel name on top, the picture on its sunburst under it)
	place(refs.DetailName, 12, 10, inner, 30)
	local picY = 46
	refs.DetailHolder.Position = UDim2.new(0.5, 0, 0, picY)
	refs.DetailHolder.Size = UDim2.fromOffset(portrait, portrait)
	refs.Viewport.Position = UDim2.new(0.5, 0, 0, picY - 8)
	refs.Viewport.Size = UDim2.fromOffset(if portrait > 0 then portrait + 30 else 0, if portrait > 0 then portrait + 16 else 0)
	aimReel(refs.Detail, UDim2.new(0.5, 0, 0, if portrait > 0 then picY + portrait / 2 else 30))
	local y = picY + (if portrait > 0 then portrait + 6 else 0)
	refs.DetailRarity.Position = UDim2.new(0.5, 0, 0, y)
	GolemView.sizeChip(refs.DetailRarity, 150, 26)
	refs.DetailRarity.TextSize = 17
	y += 32
	place(refs.DetailBonus, 12, y, inner, 28)
	GolemView.sizeChip(refs.DetailBonus, inner, 28)
	y += 34
	refs.DetailLore.Visible = loreH >= 34
	place(refs.DetailLore, 12, y, inner, math.max(0, loreH - 6))
	local buttonsY = bodyH + 8 - buttonH - 12
	-- (three equal buttons: the pixel words get the same room)
	local sideW = math.floor((inner - 2 * GAP) / 3)
	local equipW = inner - 2 * GAP - 2 * sideW
	placeButton(refs.Equip, 12, buttonsY, equipW, buttonH)
	placeButton(refs.Lock, 12 + equipW + GAP, buttonsY, sideW, buttonH)
	placeButton(refs.Delete, 12 + equipW + 2 * GAP + sideW, buttonsY, sideW, buttonH)

	-- delete bar: the text, then two rows of buttons
	local by = bodyH + 8 - 2 * (buttonH + GAP) - 4
	place(refs.DeleteText, 12, 12, inner, math.max(30, by - 20))
	local half = math.floor((inner - GAP) / 2)
	placeButton(refs.PickCommon, 12, by, half, buttonH)
	placeButton(refs.PickUncommon, 12 + half + GAP, by, half, buttonH)
	placeButton(refs.DeleteConfirm, 12, by + buttonH + GAP, half, buttonH)
	placeButton(refs.DeleteCancel, 12 + half + GAP, by + buttonH + GAP, half, buttonH)
	GolemView.fitButtons(refs)

	-- the confirm box
	local boxW, boxH = if compact then 660 else 540, if compact then 330 else 270
	local band = if compact then 64 else 56
	refs.ConfirmBox.Size = UDim2.fromOffset(boxW, boxH)
	GolemView.layoutChrome(refs.ConfirmBox, band)
	local boxTitle = refs.ConfirmBox:FindFirstChild("Title") :: TextLabel
	GolemView.placeTitle(boxTitle, 18, 4, boxW - 36, band - 12, if compact then 34 else 30)
	place(refs.ConfirmText, 24, band + 12, boxW - 48, boxH - band - m.Button - 44)
	local confirmW = if compact then 220 else 180
	for _, b in { refs.ConfirmYes, refs.ConfirmNo } do
		local holder = holderOf(b)
		holder.Size = UDim2.fromOffset(confirmW, m.Button)
	end
	holderOf(refs.ConfirmYes).Position = UDim2.new(0.5, -10, 1, -16)
	holderOf(refs.ConfirmNo).Position = UDim2.new(0.5, 10, 1, -16)

	-- footer
	refs.Hint.Position = UDim2.new(0.5, 0, 1, -4)
	refs.Hint.Size = UDim2.new(1, -40, 0, math.max(footer - 4, 20))
	refs.Hint.Visible = not compact
	refs.Status.Position = UDim2.new(0.5, 0, 1, if compact then -10 else -4)
	refs.Status.Size = UDim2.new(1, -40, 0, 22)
	refs.Compact = compact
	GolemView.fitButtons(refs)
end

---------------------------------------------------------------- filling in

-- The detail card for a card (nil: nothing picked).
function GolemView.setDetail(refs: Refs, card: Card?)
	local holder = refs.DetailHolder
	if refs.DetailKind ~= (if card then card.Kind else nil) then
		holder:ClearAllChildren()
		refs.DetailKind = if card then card.Kind else nil
		local size = holder.Size.X.Offset
		if card and size > 0 then
			if card.Known then
				-- (the game turns the live model in Viewport over it; the
				-- preview draws this picture's rendered icon)
				local still = UIKit.new("ImageLabel", {
					Name = "Picture",
					BackgroundTransparency = 1,
					Image = "",
					Size = UDim2.fromOffset(size, size),
					ZIndex = 4,
				}, holder)
				still:SetAttribute("Icon", "golem_" .. card.Kind)
			else
				GolemView.portrait(holder, card.Kind, size)
			end
		end
	end
	if not card then
		repaintReel(refs.Detail, GolemView.EmptyPaint)
		refs.DetailName.Text = "PICK A GOLEM"
		refs.DetailName.TextColor3 = rgb(214, 218, 228)
		refs.DetailRarity.Visible = false
		refs.DetailBonus.Visible = false
		refs.DetailBonus.Text = ""
		refs.DetailLore.Text = "Tap a golem to see it. Equip up to 3: their bonuses add up."
		for _, b in { refs.Equip, refs.Lock, refs.Delete } do
			holderOf(b).Visible = false
		end
		return
	end
	repaintReel(refs.Detail, GolemView.rarityPaint(if card.Known then card.Rarity else nil))
	refs.DetailName.Text = string.upper(card.Name)
	refs.DetailName.TextColor3 = PopTheme.Ink
	Pop.fit(refs.DetailName, if refs.Compact then 34 else 32)
	refs.DetailRarity.Visible = true
	refs.DetailRarity.Text = string.upper(card.Rarity)
	refs.DetailRarity.BackgroundColor3 = GolemView.rarityChip(if card.Known then card.Rarity else nil)
	refs.DetailBonus.Visible = true
	refs.DetailBonus.Text = if card.Known then string.upper(card.Bonus) else "NO BONUS YET"
	fitWord(refs.DetailBonus, if refs.Compact then 24 else 22, refs.DetailBonus.Size.X.Offset)
	refs.DetailLore.Text = card.Lore
	TechShopView.fitText(
		refs.DetailLore,
		refs.DetailLore.Size.X.Offset - 16,
		refs.DetailLore.Size.Y.Offset - 10,
		if refs.Compact then 17 else 15,
		11
	)
	GolemView.fitEdge(refs.DetailLore)
	for _, b in { refs.Equip, refs.Lock, refs.Delete } do
		holderOf(b).Visible = true
	end
	-- EQUIP green, UNEQUIP grey, LOCK / UNLOCK blue, DELETE red (grey when it can't)
	refs.Equip.Text = if card.Equipped then "UNEQUIP" else "EQUIP"
	GolemView.setPaint(refs.Equip, if card.Equipped then "Slate" else "Green", card.Known)
	refs.Lock.Text = if card.Locked then "UNLOCK" else "LOCK"
	GolemView.style(refs.Lock, true, Color3.new(), Color3.new())
	GolemView.style(refs.Delete, card.Known and not card.Locked, Color3.new(), Color3.new())
	GolemView.fitButtons(refs)
end

-- Fits the texts of the detail and delete buttons into their buttons.
function GolemView.fitButtons(refs: Refs)
	-- (pixel words shrink to fit their button with a margin: fitWord)
	local big = if refs.Compact then 28 else 26
	for _, b in { refs.Equip, refs.Lock, refs.Delete, refs.PickCommon, refs.PickUncommon, refs.DeleteConfirm, refs.DeleteCancel } do
		fitWord(b, if b == refs.Equip then big else big - 2, holderOf(b).Size.X.Offset)
		local edge = b:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Thickness = 2.5
		end
	end
	for _, b in { refs.Capsules, refs.DeleteMode, refs.EquipBest, refs.ConfirmYes, refs.ConfirmNo } do
		local word = b:GetAttribute("WordSize")
		fitWord(b, (if type(word) == "number" then word else 20) + 6, holderOf(b).Size.X.Offset)
	end
end

-- A slot's name on one line, or two (a long name) with the bonus line under them.
local function placeSlotName(s: SlotRefs, m: Metrics)
	local h = s.Frame.Size.Y.Offset
	local inner = h - Pop.lipUnits(h)
	local x = s.Name.Position.X.Offset
	local width = s.Frame.Size.X.Offset - x - 4
	local size, lines = GolemView.nameFit(s.Name.Text, slotNameMax(m), width - 2, nameMin(m))
	local half = math.floor(inner / 2)
	if lines > 1 then
		local nameH = GolemView.nameHeight(size, lines)
		s.Name.Position = UDim2.fromOffset(x, 3)
		s.Name.Size = UDim2.new(1, -(x + 4), 0, nameH)
		s.Bonus.Position = UDim2.fromOffset(x, 3 + nameH)
		s.Bonus.Size = UDim2.new(1, -(x + 4), 0, math.max(14, inner - 2 - (3 + nameH)))
	else
		s.Name.Position = UDim2.fromOffset(x, 8)
		s.Name.Size = UDim2.new(1, -(x + 4), 0, half - 6)
		s.Bonus.Position = UDim2.fromOffset(x, half + 2)
		s.Bonus.Size = UDim2.new(1, -(x + 4), 0, half - 6)
	end
	setName(s.Name, size, lines)
end

-- The equipped strip: a bright rarity card per golem, its live picture, name and bonus.
function GolemView.setEquipped(refs: Refs, equipped: { Card }, totals: string)
	local m = metrics(refs.Compact)
	for i, s in refs.Slots do
		local card = equipped[i]
		local kind = if card then card.Kind else nil
		if s.Kind ~= kind then
			s.Holder:ClearAllChildren()
			s.Kind = kind
			if card then
				GolemView.picture(s.Holder, card.Kind, s.Holder.Size.X.Offset, { ZIndex = 4 })
			end
		end
		if card then
			repaintReel(s.Frame, GolemView.rarityPaint(card.Rarity))
			s.Name.Text = string.upper(card.Name)
			s.Name.TextColor3 = PopTheme.Ink
			s.Bonus.Text = GolemView.shortBonus(card.Bonus)
		else
			repaintReel(s.Frame, GolemView.EmptyPaint)
			s.Name.Text = "EMPTY"
			s.Name.TextColor3 = rgb(214, 218, 228)
			s.Bonus.Text = ""
		end
		s.Stroke.Color = PopTheme.Outline
		s.Stroke.Thickness = PopTheme.Edge
		placeSlotName(s, m)
		Pop.fit(s.Bonus, m.Small + 1)
	end
	refs.Totals.Text = totals
	local size = refs.Totals.Size
	TechShopView.fitText(refs.Totals, size.X.Offset, size.Y.Offset, if refs.Compact then 18 else 16, 11)
	GolemView.fitEdge(refs.Totals)
end

--[[
	Shows `cards` in the grid (pooled per Id: a card is rebuilt only when its
	kind changed), marks the selected one (a gold outline) and, in delete
	mode, the picked ones (red, an X); golems that can't be deleted are
	shaded there. Cards of golems that are gone are destroyed.
]]
function GolemView.setCards(refs: Refs, cards: { Card }, selected: number?, picked: { [number]: boolean }?)
	local m = metrics(refs.Compact)
	local seen: { [number]: boolean } = {}
	for _, card in cards do
		seen[card.Id] = true
		local c: CardRefs? = refs.Cards[card.Id]
		if c and c.Kind ~= card.Kind then
			c.Button:Destroy()
			refs.Cards[card.Id] = nil
			c = nil
		end
		local cr: CardRefs = c or newCard(refs, card, m)
		cr.Button.LayoutOrder = card.Order
		cr.Button.Size = UDim2.fromOffset(m.Cell.X, m.Cell.Y)
		cr.Name.Text = string.upper(card.Name)
		cr.Bonus.Text = GolemView.shortBonus(card.Bonus)
		cr.Bonus.Visible = card.Bonus ~= ""
		cr.Equipped.Visible = card.Equipped
		local deleting = picked ~= nil
		cr.Lock.Visible = card.Locked
		local deletable = card.Known and not card.Locked
		cr.Check.Visible = deleting and deletable
		cr.Shade.Visible = deleting and not deletable
		local isPicked = deleting and (picked :: { [number]: boolean })[card.Id] == true
		cr.Check.Text = if isPicked then "X" else ""
		cr.Check.BackgroundColor3 = if isPicked then Pop.paint("Red").Bottom else GolemView.ChipDark
		local chosen = card.Id == selected
		cr.Stroke.Thickness = if chosen or isPicked then 6 else PopTheme.Edge
		cr.Stroke.Color = if isPicked then Pop.paint("Red").Top elseif chosen then GolemView.SelectColor else PopTheme.Outline
		local ring = cr.Button:FindFirstChild("Pick")
		if ring and ring:IsA("GuiObject") then
			ring.Visible = chosen and not deleting
		end
	end
	for id, c in refs.Cards do
		if not seen[id] then
			c.Button:Destroy()
			refs.Cards[id] = nil
		end
	end
	refs.Empty.Visible = #cards == 0
end

function GolemView.setCount(refs: Refs, text: string, full: boolean)
	refs.Count.Text = text
	refs.Count.BackgroundColor3 = if full then Pop.paint("Red").Bottom else GolemView.ChipDark
end

-- Delete mode on / off (the bar replaces the detail card).
function GolemView.setDeleteMode(refs: Refs, on: boolean, picked: number)
	refs.DeleteBar.Visible = on
	refs.Detail.Visible = not on
	refs.DeleteText.Text = if picked == 0
		then "Tap the golems you want to delete. Locked golems are safe."
		else `{picked} golem{if picked == 1 then "" else "s"} picked.`
	local size = refs.DeleteText.Size
	TechShopView.fitText(refs.DeleteText, size.X.Offset, size.Y.Offset, if refs.Compact then 34 else 30, 14)
	GolemView.fitEdge(refs.DeleteText)
	refs.DeleteConfirm.Text = `DELETE {picked}`
	GolemView.style(refs.DeleteConfirm, picked > 0, Color3.new(), Color3.new())
	GolemView.fitButtons(refs)
end

function GolemView.showConfirm(refs: Refs, text: string)
	refs.ConfirmText.Text = text
	local size = refs.ConfirmText.Size
	TechShopView.fitText(refs.ConfirmText, size.X.Offset, size.Y.Offset, if refs.Compact then 26 else 22, 14)
	GolemView.fitEdge(refs.ConfirmText)
	refs.Confirm.Visible = true
end

function GolemView.hideConfirm(refs: Refs)
	refs.Confirm.Visible = false
end

-- The footer's message line (nil: back to the hint).
function GolemView.setStatus(refs: Refs, text: string?, color: Color3?)
	refs.Status.Visible = text ~= nil
	refs.Hint.Visible = text == nil and not refs.Compact
	if text then
		refs.Status.Text = text
		refs.Status.TextColor3 = color or Theme.Info
	end
end

function GolemView.setHint(refs: Refs, text: string)
	refs.Hint.Text = text
end

-- The HUD menu button's height (design units) at a HUD scale: at the
-- phone floor (0.62) 72 units are 44 pt.
GolemView.MenuWidth = 84
function GolemView.menuHeight(uiScale: number): number
	return if uiScale < 0.8 then 72 else 64
end

--[[
	The GOLEMS button for the HUD's right-side menu (HudController.refs().Menu,
	under BUILD), with the toggle key in its corner: a key chip ("Key", for
	keyboards) and the gamepad glyph ("Glyph", an ImageLabel); menuLayout
	shows the one that fits the input.
]]
function GolemView.menuButton(menu: Instance, key: string?): TextButton
	local button = UIKit.button(menu, "GOLEMS", Theme.Info, rgb(50, 110, 170), {
		Name = "Golems",
		LayoutOrder = 30,
		Size = UDim2.fromOffset(GolemView.MenuWidth, 64),
		TextSize = 17,
	})
	UIKit.chip(button, key or "P", Theme.PanelDark, {
		Name = "Key",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(20, 18),
		TextSize = 13,
		ZIndex = 3,
		Visible = false,
	})
	UIKit.new("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -8),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Visible = false,
	}, button)
	return button
end

-- The menu button for a HUD scale and the input in use ("Keyboard",
-- "Gamepad" with the glyph image, or "Touch": no key shown).
function GolemView.menuLayout(button: TextButton, uiScale: number, input: string, glyph: string?)
	holderOf(button).Size = UDim2.fromOffset(GolemView.MenuWidth, GolemView.menuHeight(uiScale))
	local key = button:FindFirstChild("Key")
	if key and key:IsA("GuiObject") then
		key.Visible = input == "Keyboard"
	end
	local image = button:FindFirstChild("Glyph")
	if image and image:IsA("ImageLabel") then
		image.Image = glyph or ""
		image.Visible = input == "Gamepad" and image.Image ~= ""
	end
end

-- Every button a finger or a gamepad uses (tests: 44 pt at the phone scale).
function GolemView.touchTargets(refs: Refs): { GuiObject }
	local list: { GuiObject } = {}
	for _, b in
		{
			refs.Close,
			refs.Capsules,
			refs.DeleteMode,
			refs.EquipBest,
			refs.Equip,
			refs.Lock,
			refs.Delete,
			refs.PickCommon,
			refs.PickUncommon,
			refs.DeleteConfirm,
			refs.DeleteCancel,
			refs.ConfirmYes,
			refs.ConfirmNo,
		}
	do
		table.insert(list, holderOf(b))
	end
	for _, c in refs.Cards do
		table.insert(list, c.Button)
	end
	return list
end

return GolemView
