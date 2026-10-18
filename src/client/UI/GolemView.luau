--[[
	The golem inventory (pure builder + pure helpers; GolemController fills
	it in) and the 2D golem portrait every golem screen uses.

	One ScreenGui "TerraForgeGolems":
	  header    MY GOLEMS, how many you have (12 / 60), CAPSULES (opens the
	            capsule view), the X button
	  equipped  the 3 slots (portrait, name, bonus; "Empty slot"), the total
	            bonus of the equipped golems, EQUIP BEST
	  grid      every golem you own as a card (portrait in its rarity color,
	            name, bonus, an E badge when equipped, a LOCKED chip when
	            locked; golems bought with Robux come locked):
	            equipped first, then the best (GolemConfig.score), then the
	            oldest. Golems of a kind this version doesn't know show "???".
	  detail    the selected golem: its portrait (the controller adds the 3D
	            model in the ViewportFrame "Model" over it), name, rarity,
	            bonus, lore and EQUIP / UNEQUIP, LOCK / UNLOCK, DELETE.
	            In delete mode it becomes the delete bar: how many are picked,
	            + ALL COMMON / + ALL UNCOMMON, DELETE n, CANCEL; a confirm box
	            asks before anything is deleted (and warns when a golem
	            bought with Robux is among them).
	  footer    the control hint or the server's last answer
	The compact layout (phones, TVs) has 44 pt buttons and drops the lore
	when the screen is short. Cards are pooled per golem Id.

	portrait(parent, kind, size): a golem drawn from frames, face on, like
	GolemBuilder's (big head under a stone brow, glowing eyes, body with its
	core and ore vein, rock fists, the shoulder boulder and crystal, legs,
	the kind's accessory; Legendary and Mythic float over a glowing aura),
	so cards and the preview renders need no 3D.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local UIKit = require(script.Parent.UIKit)
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
		Detail = 280,
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
		Slot = 210,
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
	local closed = gear == "KnightHelm"
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

---------------------------------------------------------------- building

local function holderOf(button: TextButton): Frame
	return button.Parent :: Frame
end

-- A button's look: enabled in its colors, or greyed out.
function GolemView.style(button: TextButton, enabled: boolean, color: Color3, dark: Color3)
	button.BackgroundColor3 = if enabled then color else Theme.PanelLight
	holderOf(button).BackgroundColor3 = if enabled then dark else Theme.PanelDark
	button.TextColor3 = if enabled then Theme.Text else Theme.TextDim
end

local function newCard(refs: Refs, card: Card, m: Metrics): CardRefs
	local button = UIKit.new("TextButton", {
		Name = "Golem" .. card.Id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		LayoutOrder = card.Order,
		Size = UDim2.fromOffset(m.Cell.X, m.Cell.Y),
	}, refs.Grid)
	UIKit.corner(button, 12)
	local stroke = UIKit.stroke(button, 3, card.Color)
	-- a soft rarity glow behind the portrait
	local back = UIKit.new("Frame", {
		Name = "Back",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(m.Cell.X - 16, m.Cell.X - 22),
		BackgroundColor3 = card.Color,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
	}, button)
	UIKit.corner(back, 10)
	local size = m.Cell.X - 30
	local portrait = GolemView.portrait(button, card.Kind, size)
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 8)
	local name = UIKit.label(button, card.Name, m.Small, {
		Name = "GolemName",
		Position = UDim2.new(0, 6, 1, -44),
		Size = UDim2.new(1, -12, 0, 20),
		TextWrapped = false,
		TextColor3 = card.Color,
	})
	local bonus = UIKit.label(button, card.Bonus, m.Small - 2, {
		Name = "Bonus",
		Position = UDim2.new(0, 6, 1, -24),
		Size = UDim2.new(1, -12, 0, 18),
		TextWrapped = false,
		TextColor3 = Theme.TextDim,
	})
	local equipped = UIKit.chip(button, "E", Theme.Good, {
		Name = "EquippedBadge",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(26, 24),
		TextSize = 16,
		ZIndex = 3,
	})
	-- a state, not a button: "LOCKED"
	local lock = UIKit.chip(button, "LOCKED", Theme.Info, {
		Name = "LockBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(62, 22),
		TextSize = 13,
		ZIndex = 3,
	})
	local check = UIKit.chip(button, "", Theme.PanelDark, {
		Name = "Check",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(30, 30),
		TextSize = 20,
		ZIndex = 4,
		Visible = false,
	})
	local refsCard: CardRefs = {
		Button = button,
		Portrait = portrait,
		Name = name,
		Bonus = bonus,
		Equipped = equipped,
		Lock = lock,
		Check = check,
		Stroke = stroke,
		Kind = card.Kind,
	}
	refs.Cards[card.Id] = refsCard
	return refsCard
end

local function slot(parent: Instance, index: number, m: Metrics): SlotRefs
	local frame = UIKit.new("Frame", {
		Name = "Slot" .. index,
		LayoutOrder = index,
		Size = UDim2.fromOffset(m.Slot, m.Strip - 30),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, parent)
	UIKit.corner(frame, 10)
	local stroke = UIKit.stroke(frame, 2)
	local holder = UIKit.new("Frame", {
		Name = "Holder",
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.fromOffset(m.Strip - 34, m.Strip - 34),
		BackgroundTransparency = 1,
	}, frame)
	local name = UIKit.label(frame, "Empty slot", m.Small, {
		Name = "GolemName",
		Position = UDim2.fromOffset(m.Strip - 26, 8),
		Size = UDim2.new(1, -(m.Strip - 20), 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextColor3 = Theme.TextDim,
	})
	local bonus = UIKit.label(frame, "", m.Small - 1, {
		Name = "Bonus",
		Position = UDim2.fromOffset(m.Strip - 26, 32),
		Size = UDim2.new(1, -(m.Strip - 20), 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Good,
	})
	return { Frame = frame, Stroke = stroke, Holder = holder, Name = name, Bonus = bonus, Kind = nil }
end

local function closeButton(parent: Instance): TextButton
	return UIKit.button(parent, "X", Theme.Bad, Theme.BadDark, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
	})
end

function GolemView.build(compact: boolean?): Refs
	local isCompact = compact == true
	local m = metrics(isCompact)
	local gui = UIKit.screen("TerraForgeGolems", 16)
	gui.Enabled = false
	gui:SetAttribute("TerraForge", true)

	local panel = UIKit.panel(gui, {
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
	})
	local title = UIKit.label(panel, "MY GOLEMS", m.Title, {
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.TitleFont,
		TextColor3 = Theme.Accent,
		TextWrapped = false,
	})
	local count = UIKit.chip(panel, "0 / 60", Theme.PanelLight, {
		Name = "Count",
		TextSize = m.Small + 1,
	})
	local capsules = UIKit.button(panel, "CAPSULES", Theme.Info, rgb(50, 110, 170), {
		Name = "Capsules",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 20,
	})
	local deleteMode = UIKit.button(panel, "DELETE...", Theme.Bad, Theme.BadDark, {
		Name = "DeleteMode",
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 19,
	})
	local close = closeButton(panel)

	-- the equipped strip
	local strip = UIKit.new("Frame", { Name = "Strip", BackgroundTransparency = 1 }, panel)
	local stripLabel = UIKit.label(strip, "EQUIPPED (3 SLOTS)", m.Small, {
		Name = "Label",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(3 * m.Slot + 2 * GAP, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})
	local slotRow = UIKit.new("Frame", {
		Name = "Slots",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.fromOffset(3 * m.Slot + 2 * GAP, m.Strip - 30),
		BackgroundTransparency = 1,
	}, strip)
	UIKit.list(slotRow, Enum.FillDirection.Horizontal, GAP)
	local slots = {}
	for i = 1, GolemConfig.EquipSlots do
		table.insert(slots, slot(slotRow, i, m))
	end
	local totals = UIKit.label(strip, "", m.Small, {
		Name = "Totals",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Good,
		-- never runs out of its box (fitText shrinks it first)
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local equipBest = UIKit.button(strip, "EQUIP BEST", Theme.Good, Theme.GoodDark, {
		Name = "EquipBest",
		TextSize = 20,
	})

	-- the grid of owned golems
	local grid = UIKit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
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
	local empty = UIKit.label(panel, "No golems yet. Open a capsule at the CAPSULES stall in town!", m.Text, {
		Name = "Empty",
		TextColor3 = Theme.TextDim,
		Visible = false,
	})

	-- the detail column
	local detail = UIKit.new("Frame", {
		Name = "Detail",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, panel)
	UIKit.corner(detail, 12)
	UIKit.stroke(detail, 2)
	local detailHolder = UIKit.new("Frame", {
		Name = "PortraitHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	}, detail)
	local viewport = UIKit.new("ViewportFrame", {
		Name = "Model",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Ambient = rgb(170, 160, 150),
		LightColor = rgb(255, 240, 220),
		LightDirection = Vector3.new(-0.4, -1, 0.6),
		Visible = false,
		ZIndex = 3,
	}, detail)
	local detailName = UIKit.label(detail, "", m.Text + 6, {
		Name = "GolemName",
		FontFace = Theme.TitleFont,
		TextWrapped = false,
	})
	local detailRarity = UIKit.chip(detail, "", Theme.PanelLight, {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = m.Small,
	})
	local detailBonus = UIKit.label(detail, "", m.Text, {
		Name = "Bonus",
		TextColor3 = Theme.Good,
		TextWrapped = false,
	})
	local detailLore = UIKit.label(detail, "", m.Small - 1, {
		Name = "Lore",
		TextColor3 = Theme.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local equip = UIKit.button(detail, "EQUIP", Theme.Good, Theme.GoodDark, { Name = "Equip", TextSize = 20 })
	local lock = UIKit.button(detail, "LOCK", Theme.Info, rgb(50, 110, 170), { Name = "Lock", TextSize = 18 })
	local delete = UIKit.button(detail, "DELETE", Theme.Bad, Theme.BadDark, { Name = "Delete", TextSize = 18 })

	-- delete mode: the bar that replaces the detail column
	local deleteBar = UIKit.new("Frame", {
		Name = "DeleteBar",
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
		Visible = false,
	}, panel)
	UIKit.corner(deleteBar, 12)
	UIKit.stroke(deleteBar, 2, Theme.Bad)
	local deleteText = UIKit.label(deleteBar, "", m.Text, {
		Name = "Text",
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local pickCommon = UIKit.button(deleteBar, "+ ALL COMMON", Theme.PanelLight, Theme.PanelDark, { Name = "PickCommon", TextSize = 17 })
	local pickUncommon =
		UIKit.button(deleteBar, "+ ALL UNCOMMON", Theme.PanelLight, Theme.PanelDark, { Name = "PickUncommon", TextSize = 17 })
	local deleteConfirm = UIKit.button(deleteBar, "DELETE 0", Theme.Bad, Theme.BadDark, { Name = "DeleteConfirm", TextSize = 20 })
	local deleteCancel = UIKit.button(deleteBar, "CANCEL", Theme.PanelLight, Theme.PanelDark, { Name = "DeleteCancel", TextSize = 20 })

	-- the confirm box (over everything)
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
	local box = UIKit.panel(confirm, {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(if isCompact then 640 else 520, if isCompact then 280 else 230),
		ZIndex = 21,
	})
	local confirmText = UIKit.label(box, "", m.Text + 2, {
		Name = "Text",
		Position = UDim2.fromOffset(24, 20),
		Size = UDim2.new(1, -48, 1, -(m.Button + 56)),
		ZIndex = 22,
	})
	local confirmYes = UIKit.button(box, "DELETE", Theme.Bad, Theme.BadDark, {
		Name = "Yes",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -10, 1, -18),
		Size = UDim2.fromOffset(if isCompact then 220 else 180, m.Button),
		TextSize = 22,
		ZIndex = 22,
	})
	local confirmNo = UIKit.button(box, "KEEP", Theme.Good, Theme.GoodDark, {
		Name = "No",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 10, 1, -18),
		Size = UDim2.fromOffset(if isCompact then 220 else 180, m.Button),
		TextSize = 22,
		ZIndex = 22,
	})
	for _, b in { confirmYes, confirmNo } do
		holderOf(b).ZIndex = 22
	end

	local status = UIKit.label(panel, "", m.Small, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		TextWrapped = false,
		TextColor3 = Theme.Info,
		Visible = false,
	})
	local hint = UIKit.label(panel, "", m.Small, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		TextWrapped = false,
	})

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

	-- header
	local h = m.Header
	place(refs.Title, PAD + 4, 0, 260, h)
	refs.Title.TextSize = m.Title
	place(refs.Count, PAD + 4 + 236, (h - 28) / 2, 92, 28)
	local closeHolder = holderOf(refs.Close)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -PAD, 0, (h - m.Close) / 2 + 3)
	closeHolder.Size = UDim2.fromOffset(m.Close, m.Close)
	local capsHolder = holderOf(refs.Capsules)
	capsHolder.AnchorPoint = Vector2.new(1, 0)
	capsHolder.Position = UDim2.new(1, -(PAD + m.Close + GAP), 0, (h - m.Button) / 2 + 3)
	capsHolder.Size = UDim2.fromOffset(if compact then 190 else 160, m.Button)
	local deleteHolder = holderOf(refs.DeleteMode)
	deleteHolder.AnchorPoint = Vector2.new(1, 0)
	deleteHolder.Position = UDim2.new(1, -(PAD + m.Close + 2 * GAP + (if compact then 190 else 160)), 0, (h - m.Button) / 2 + 3)
	deleteHolder.Size = UDim2.fromOffset(if compact then 170 else 136, m.Button)

	-- equipped strip
	local stripY = h
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

	-- body: grid on the left, detail on the right
	local bodyY = stripY + m.Strip + 6
	local footer = m.Footer
	local bodyH = height - bodyY - footer - 8
	local detailX = width - PAD - m.Detail
	local gridW = detailX - PAD - GAP
	place(refs.Grid, PAD, bodyY, gridW, bodyH)
	-- as many whole columns as fit, the cards widened to fill the row (no
	-- empty gap before the detail column; the scroll bar keeps its room)
	local cellPad = refs.GridLayout.CellPadding.X.Offset
	local usable = gridW - refs.Grid.ScrollBarThickness - 4
	local columns = math.max(1, math.floor((usable + cellPad) / (m.Cell.X + cellPad)))
	local cellW = math.max(m.Cell.X, math.floor((usable - (columns - 1) * cellPad) / columns))
	refs.GridLayout.CellSize = UDim2.fromOffset(cellW, m.Cell.Y)
	place(refs.Empty, PAD + 20, bodyY + 20, gridW - 40, bodyH - 40)
	place(refs.Detail, detailX, bodyY, m.Detail, bodyH)
	place(refs.DeleteBar, detailX, bodyY, m.Detail, bodyH)

	-- detail column: portrait (when there is room), name, rarity, bonus,
	-- lore (when there is room), buttons
	local inner = m.Detail - 24
	local buttonH = m.Button
	local texts = 30 + 6 + 24 + 6 + 24 -- name, rarity, bonus
	local spare = bodyH - (8 + texts + 10 + buttonH + 12)
	local portrait = math.min(math.max(0, spare - 46), if compact then 150 else 140)
	if portrait < 56 then
		portrait = 0 -- short screens: the grid's portraits are enough
	end
	local loreH = spare - portrait - (if portrait > 0 then 6 else 0)
	refs.DetailHolder.Position = UDim2.new(0.5, 0, 0, 8)
	refs.DetailHolder.Size = UDim2.fromOffset(portrait, portrait)
	refs.Viewport.Position = UDim2.new(0.5, 0, 0, 0)
	refs.Viewport.Size = UDim2.fromOffset(if portrait > 0 then portrait + 30 else 0, if portrait > 0 then portrait + 16 else 0)
	local y = 8 + (if portrait > 0 then portrait + 6 else 0)
	place(refs.DetailName, 12, y, inner, 30)
	y += 36
	refs.DetailRarity.Position = UDim2.new(0.5, 0, 0, y)
	refs.DetailRarity.Size = UDim2.fromOffset(150, 24)
	y += 30
	place(refs.DetailBonus, 12, y, inner, 24)
	y += 30
	refs.DetailLore.Visible = loreH >= 34
	place(refs.DetailLore, 12, y, inner, math.max(0, loreH - 6))
	local buttonsY = bodyH - buttonH - 10
	local equipW = math.floor((inner - GAP) * 0.42)
	local sideW = math.floor((inner - equipW - 2 * GAP) / 2)
	placeButton(refs.Equip, 12, buttonsY, equipW, buttonH)
	placeButton(refs.Lock, 12 + equipW + GAP, buttonsY, sideW, buttonH)
	placeButton(refs.Delete, 12 + equipW + 2 * GAP + sideW, buttonsY, sideW, buttonH)

	-- delete bar: the text, then two rows of buttons
	local by = bodyH - 2 * (buttonH + GAP) - 2
	place(refs.DeleteText, 12, 10, inner, math.max(30, by - 18))
	local half = math.floor((inner - GAP) / 2)
	placeButton(refs.PickCommon, 12, by, half, buttonH)
	placeButton(refs.PickUncommon, 12 + half + GAP, by, half, buttonH)
	placeButton(refs.DeleteConfirm, 12, by + buttonH + GAP, half, buttonH)
	placeButton(refs.DeleteCancel, 12 + half + GAP, by + buttonH + GAP, half, buttonH)
	GolemView.fitButtons(refs)

	-- footer
	refs.Hint.Position = UDim2.new(0.5, 0, 1, -4)
	refs.Hint.Size = UDim2.new(1, -40, 0, math.max(footer - 4, 20))
	refs.Hint.Visible = not compact
	refs.Status.Position = UDim2.new(0.5, 0, 1, if compact then -10 else -4)
	refs.Status.Size = UDim2.new(1, -40, 0, 22)
	refs.Compact = compact
end

---------------------------------------------------------------- filling in

-- The detail column for a card (nil: nothing selected).
function GolemView.setDetail(refs: Refs, card: Card?)
	local holder = refs.DetailHolder
	if refs.DetailKind ~= (if card then card.Kind else nil) then
		holder:ClearAllChildren()
		refs.DetailKind = if card then card.Kind else nil
		local size = holder.Size.X.Offset
		if card and size > 0 then
			GolemView.portrait(holder, card.Kind, size)
		end
	end
	if not card then
		refs.DetailName.Text = "Pick a golem"
		refs.DetailName.TextColor3 = Theme.TextDim
		refs.DetailRarity.Visible = false
		refs.DetailBonus.Text = ""
		refs.DetailLore.Text = "Tap a golem to see it. Equip up to 3: their bonuses add up."
		for _, b in { refs.Equip, refs.Lock, refs.Delete } do
			holderOf(b).Visible = false
		end
		return
	end
	refs.DetailName.Text = card.Name
	refs.DetailName.TextColor3 = card.Color
	TechShopView.fitText(refs.DetailName, refs.DetailName.Size.X.Offset, 30, if refs.Compact then 28 else 26, 16)
	refs.DetailRarity.Visible = true
	refs.DetailRarity.Text = string.upper(card.Rarity)
	refs.DetailRarity.BackgroundColor3 = card.Color
	refs.DetailBonus.Text = if card.Known then card.Bonus else "No bonus in this version"
	refs.DetailLore.Text = card.Lore
	TechShopView.fitText(refs.DetailLore, refs.DetailLore.Size.X.Offset, refs.DetailLore.Size.Y.Offset, if refs.Compact then 17 else 15, 11)
	for _, b in { refs.Equip, refs.Lock, refs.Delete } do
		holderOf(b).Visible = true
	end
	refs.Equip.Text = if card.Equipped then "UNEQUIP" else "EQUIP"
	GolemView.style(
		refs.Equip,
		card.Known,
		if card.Equipped then Theme.Accent else Theme.Good,
		if card.Equipped then Theme.AccentDark else Theme.GoodDark
	)
	refs.Lock.Text = if card.Locked then "UNLOCK" else "LOCK"
	GolemView.style(refs.Lock, true, Theme.Info, rgb(50, 110, 170))
	GolemView.style(refs.Delete, card.Known and not card.Locked, Theme.Bad, Theme.BadDark)
	GolemView.fitButtons(refs)
end

-- Fits the texts of the detail and delete buttons into their buttons.
function GolemView.fitButtons(refs: Refs)
	local big = if refs.Compact then 22 else 20
	for _, b in { refs.Equip, refs.Lock, refs.Delete, refs.PickCommon, refs.PickUncommon, refs.DeleteConfirm, refs.DeleteCancel } do
		local holder = holderOf(b)
		TechShopView.fitText(b :: any, holder.Size.X.Offset - 12, holder.Size.Y.Offset - 6, if b == refs.Equip then big else big - 2, 11)
	end
end

-- The equipped strip.
function GolemView.setEquipped(refs: Refs, equipped: { Card }, totals: string)
	for i, s in refs.Slots do
		local card = equipped[i]
		local kind = if card then card.Kind else nil
		if s.Kind ~= kind then
			s.Holder:ClearAllChildren()
			s.Kind = kind
			if card then
				GolemView.portrait(s.Holder, card.Kind, s.Holder.Size.X.Offset)
			end
		end
		if card then
			s.Name.Text = card.Name
			s.Name.TextColor3 = card.Color
			s.Bonus.Text = card.Bonus
		else
			s.Name.Text = "Empty slot"
			s.Name.TextColor3 = Theme.TextDim
			s.Bonus.Text = ""
		end
		s.Stroke.Color = if card then card.Color else Theme.Outline
		s.Stroke.Thickness = if card then 3 else 2
		local m = metrics(refs.Compact)
		TechShopView.fitText(s.Name, m.Slot - (m.Strip - 20), 22, if refs.Compact then 18 else 16, 11)
	end
	refs.Totals.Text = totals
	local size = refs.Totals.Size
	TechShopView.fitText(refs.Totals, size.X.Offset, size.Y.Offset, if refs.Compact then 18 else 16, 11)
end

--[[
	Shows `cards` in the grid (pooled per Id: a card is rebuilt only when its
	kind changed), marks the selected one and, in delete mode, the picked
	ones. Cards of golems that are gone are destroyed.
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
		cr.Name.Text = card.Name
		cr.Name.TextColor3 = card.Color
		TechShopView.fitText(cr.Name, m.Cell.X - 12, 20, m.Small, 10)
		cr.Bonus.Text = card.Bonus
		TechShopView.fitText(cr.Bonus, m.Cell.X - 12, 18, m.Small - 2, 9)
		cr.Equipped.Visible = card.Equipped
		local deleting = picked ~= nil
		cr.Lock.Visible = card.Locked
		cr.Check.Visible = deleting and not card.Locked and card.Known
		local isPicked = deleting and (picked :: { [number]: boolean })[card.Id] == true
		cr.Check.Text = if isPicked then "X" else ""
		cr.Check.BackgroundColor3 = if isPicked then Theme.Bad else Theme.PanelDark
		local chosen = card.Id == selected
		cr.Stroke.Thickness = if chosen or isPicked then 5 else 3
		cr.Stroke.Color = if isPicked then Theme.Bad elseif chosen then Color3.new(1, 1, 1) else card.Color
		cr.Button.BackgroundColor3 = if chosen then Theme.PanelLight else Theme.PanelDark
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
	refs.Count.BackgroundColor3 = if full then Theme.Bad else Theme.PanelLight
end

-- Delete mode on / off (the bar replaces the detail column).
function GolemView.setDeleteMode(refs: Refs, on: boolean, picked: number)
	refs.DeleteBar.Visible = on
	refs.Detail.Visible = not on
	refs.DeleteText.Text = if picked == 0
		then "Tap the golems you want to delete. Locked golems are safe."
		else `{picked} golem{if picked == 1 then "" else "s"} picked.`
	refs.DeleteConfirm.Text = `DELETE {picked}`
	GolemView.style(refs.DeleteConfirm, picked > 0, Theme.Bad, Theme.BadDark)
	GolemView.fitButtons(refs)
end

function GolemView.showConfirm(refs: Refs, text: string)
	refs.ConfirmText.Text = text
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
