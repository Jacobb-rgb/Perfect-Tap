--[[
	RockLabel: the name and HP over a mine rock (owner, 2026-10-17: "like
	The Forge", so players see at a glance what they mine and how long it takes).

	   Greystone              20 HP     name in the rock's color (MineFloors.labelColor)
	  [===============-------]          HP bar
	        Needs Lv 3                  note (only on the rock you aim at)
	Locked rocks show "Lv 5" in red (or "VIP" in gold) instead of the HP.

	Hangs above the rock (StudsOffsetWorldSpace = rock height + Gap) and is
	hidden behind walls. Far labels shrink and fade a little (RockLabel.fade),
	phones get smaller labels and fewer of them (screenScale, maxLabels), and
	a label that would cover a nearer one on screen is hidden (declutter).
	Pure: it only creates and changes Instances and does math (no services, no
	events), so the Lune tests and previews run it. UI/RockLabels.luau keeps
	the labels over the nearest rocks in the game.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Config"):WaitForChild("UITheme"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UIKit = require(script.Parent.UIKit)

local RockLabel = {}

export type Refs = {
	Gui: BillboardGui,
	Box: Frame,
	Scale: UIScale,
	Name: TextLabel,
	Hp: TextLabel,
	Bar: Frame,
	Fill: Frame,
	Note: TextLabel,
	Strokes: { UIStroke },
	Shown: { Hp: number, Max: number, Locked: number, Vip: boolean, Scale: number, Fade: number, Note: string },
}

export type Candidate = { Rock: any, Distance: number, Behind: boolean? }
export type Rect = { Key: any, X: number, Y: number, W: number, H: number, Shown: boolean? } -- center + size in pixels

RockLabel.MaxDistance = 45 -- labels show on rocks this close to the player
RockLabel.MaxLabels = 12
RockLabel.PhoneLabels = 8 -- small screens (fewer labels, less clutter)
RockLabel.Refresh = 0.25 -- seconds between picks of the nearest rocks
RockLabel.FocusDistance = 90 -- the aimed rock keeps its label (and note) up to here
RockLabel.CameraSlack = 25 -- the camera sits behind the player: cull a bit later than we pick
RockLabel.Gap = 0.8 -- studs between the rock's top and the label
-- seconds the HP fill glides to a lower value (rock Health replicates about 3x a second)
RockLabel.FillGlide = 0.28

-- the running fill glide of each label (cancelled when the bar snaps: a pooled label, a lock, a heal)
local glides: { [Frame]: Tween } = setmetatable({}, { __mode = "k" }) :: any

local function stopGlide(fill: Frame)
	local tween = glides[fill]
	if tween then
		glides[fill] = nil
		tween:Cancel()
	end
end
RockLabel.GrottoName = "Grotto Rock" -- rocks without a Floor (the VIP Grotto)

local WIDTH = 220
local HEIGHT = 64
local BODY = 36 -- pixels of name + bar (the note hangs below)
local BAR_HEIGHT = 9
local NEAR = 12 -- full size up to here
local FAR_SCALE = 0.62 -- size at MaxDistance (the nearest rocks stay the biggest and on top)
local FAR_FADE = 0.3
local BEHIND_PENALTY = 30 -- rocks behind the camera only get labels when nothing is in front
local HIDE_OVERLAP = 0.04 -- a label hides when this share of it covers a label with priority
local SHOW_OVERLAP = 0.01 -- ... and comes back below this (no flicker at the edge)
local PAD = 4 -- pixels kept free around a label (texts never touch)
local KINDS = { Small = true, Big = true, Crystal = true, Golden = true, Geode = true, Artifact = true, Giant = true }

---------------------------------------------------------------- pure helpers

-- The name and its color for a rock's Floor / Kind attributes (missing Floor = VIP Grotto rock).
function RockLabel.rockInfo(floor: any, kind: any): (string, Color3)
	local rockKind: MineFloors.RockKind = if type(kind) == "string" and KINDS[kind] then kind :: any else "Small"
	if type(floor) ~= "number" or not MineFloors.ByIndex[floor] then
		return RockLabel.GrottoName, MineFloors.LabelColors.Rock
	end
	return MineFloors.rockName(floor, rockKind), MineFloors.labelColor(floor, rockKind)
end

--[[
	Why the player can't blast a rock: the level they need (when their blaster
	is weaker than MinBlaster) and whether it is a VIP rock without the perk.
]]
function RockLabel.lockOf(level: number, minBlaster: any, vipOnly: any, hasVip: boolean): (number?, boolean)
	local vip = vipOnly == true and not hasVip
	local needed = if type(minBlaster) == "number" and minBlaster > level then minBlaster else nil
	return needed, vip
end

function RockLabel.hpText(hp: number, maxHp: number): string
	local max = math.max(1, maxHp)
	return Format.short(math.clamp(math.ceil(hp), 0, max)) .. " HP"
end

-- The rocks that get a label: in range, nearest first (rocks behind the camera last), at most `count`.
function RockLabel.pick(list: { Candidate }, count: number?, maxDistance: number?): { Candidate }
	local range = maxDistance or RockLabel.MaxDistance
	local inRange: { Candidate } = {}
	for _, candidate in list do
		if candidate.Distance <= range then
			table.insert(inRange, candidate)
		end
	end
	local function score(c: Candidate): number
		return c.Distance + (if c.Behind then BEHIND_PENALTY else 0)
	end
	table.sort(inRange, function(a, b)
		return score(a) < score(b)
	end)
	local limit = count or RockLabel.MaxLabels
	for i = #inRange, limit + 1, -1 do
		inRange[i] = nil
	end
	return inRange
end

-- Size and transparency by distance: full up to 12 studs, then smaller and a little faded.
function RockLabel.fade(distance: number, maxDistance: number?): (number, number)
	local far = maxDistance or RockLabel.MaxDistance
	local k = math.clamp((distance - NEAR) / math.max(1, far - NEAR), 0, 1)
	return 1 + (FAR_SCALE - 1) * k, FAR_FADE * k
end

-- Label size for the screen height (phones smaller, TVs a bit bigger: text >= 18 px at 1080p).
function RockLabel.screenScale(viewportHeight: number): number
	return math.clamp(viewportHeight / 900, 0.6, 1.15)
end

function RockLabel.maxLabels(viewportHeight: number): number
	return if viewportHeight < 500 then RockLabel.PhoneLabels else RockLabel.MaxLabels
end

-- The on-screen box of a label's name and bar at `scale` (center x, y = the label's anchor).
function RockLabel.rect(key: any, x: number, y: number, scale: number, shown: boolean?): Rect
	return {
		Key = key,
		X = x,
		Y = y - (HEIGHT / 2 - BODY / 2) * scale,
		W = (WIDTH + PAD * 2) * scale,
		H = (BODY + PAD * 2) * scale,
		Shown = shown,
	}
end

--[[
	Which labels to show when they overlap on screen. `rects` come in priority
	order (the aimed rock, then nearest first); a label is hidden when more than
	4 % of it lies on labels already shown (1 % to come back, so labels at the
	edge don't flicker): texts never sit on each other. Returns the set of shown keys.
]]
function RockLabel.declutter(rects: { Rect }): { [any]: boolean }
	local shown: { [any]: boolean } = {}
	local kept: { Rect } = {}
	for _, r in rects do
		local area = math.max(1, r.W * r.H)
		local covered = 0
		for _, k in kept do
			local w = math.min(r.X + r.W / 2, k.X + k.W / 2) - math.max(r.X - r.W / 2, k.X - k.W / 2)
			local h = math.min(r.Y + r.H / 2, k.Y + k.H / 2) - math.max(r.Y - r.H / 2, k.Y - k.H / 2)
			if w > 0 and h > 0 then
				covered = math.max(covered, w * h / area)
			end
		end
		local limit = if r.Shown == false then SHOW_OVERLAP else HIDE_OVERLAP
		if covered <= limit then
			shown[r.Key] = true
			table.insert(kept, r)
		end
	end
	return shown
end

---------------------------------------------------------------- builder

-- Builds the label for a rock `height` studs tall (call RockLabel.set for live HP).
function RockLabel.build(name: string, color: Color3, maxHp: number, height: number): Refs
	local gui = UIKit.new("BillboardGui", {
		Name = "RockLabel",
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		StudsOffsetWorldSpace = Vector3.new(0, height + RockLabel.Gap, 0),
		MaxDistance = RockLabel.MaxDistance + RockLabel.CameraSlack,
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		ClipsDescendants = false,
	}) :: BillboardGui
	local box = UIKit.new("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	local scale = UIKit.new("UIScale", { Name = "Scale", Scale = 1 }, box) :: UIScale
	-- long names ("Hollow Stone Boulder") shrink to fit instead of being cut
	local nameLabel = UIKit.label(box, name, 20, {
		Name = "RockName",
		Size = UDim2.new(0.68, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		TextWrapped = false,
		TextScaled = true,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 12 }, nameLabel)
	local hpLabel = UIKit.label(box, "", 17, {
		Name = "Hp",
		Size = UDim2.new(0.32, 0, 0, 24),
		Position = UDim2.fromScale(0.68, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(0, 27),
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		BackgroundColor3 = Theme.PanelDark,
		BorderSizePixel = 0,
	}, box) :: Frame
	UIKit.corner(bar, 5)
	local barStroke = UIKit.stroke(bar, 2)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
	}, bar) :: Frame
	UIKit.corner(fill, 5)
	local note = UIKit.label(box, "", 17, {
		Name = "Note",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Theme.Bad,
		TextWrapped = false,
		Visible = false,
	})
	local strokes: { UIStroke } = { barStroke }
	for _, label in { nameLabel, hpLabel, note } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			table.insert(strokes, stroke)
		end
	end
	local refs: Refs = {
		Gui = gui,
		Box = box,
		Scale = scale,
		Name = nameLabel,
		Hp = hpLabel,
		Bar = bar,
		Fill = fill,
		Note = note,
		Strokes = strokes,
		Shown = { Hp = -1, Max = -1, Locked = -1, Vip = false, Scale = 1, Fade = 0, Note = "" },
	}
	RockLabel.set(refs, maxHp, maxHp, nil)
	return refs
end

-- Points a pooled label at another rock: new name, color and height (HP is set next).
function RockLabel.retarget(refs: Refs, name: string, color: Color3, height: number)
	refs.Name.Text = name
	refs.Name.TextColor3 = color
	refs.Gui.StudsOffsetWorldSpace = Vector3.new(0, height + RockLabel.Gap, 0)
	refs.Shown.Hp, refs.Shown.Max, refs.Shown.Locked = -1, -1, -1
	RockLabel.setNote(refs, "")
end

-- Shows `hp` of `maxHp`, or "Lv N" in red when the player's blaster is too weak ("VIP" in gold for VIP rocks).
function RockLabel.set(refs: Refs, hp: number, maxHp: number, lockedLevel: number?, vipLocked: boolean?)
	local max = math.max(1, maxHp)
	local now = math.clamp(math.ceil(hp), 0, max)
	local locked = lockedLevel or 0
	local vip = vipLocked == true
	local shown = refs.Shown
	if shown.Hp == now and shown.Max == max and shown.Locked == locked and shown.Vip == vip then
		return
	end
	local wasHp, wasLocked, wasVip = shown.Hp, shown.Locked, shown.Vip
	shown.Hp, shown.Max, shown.Locked, shown.Vip = now, max, locked, vip
	if vip then
		refs.Hp.Text = "VIP"
		refs.Hp.TextColor3 = Theme.Coin
		stopGlide(refs.Fill)
		refs.Fill.Size = UDim2.fromScale(1, 1)
		refs.Fill.BackgroundColor3 = Theme.AccentDark
	elseif locked > 0 then
		refs.Hp.Text = "Lv " .. locked
		refs.Hp.TextColor3 = Theme.Bad
		stopGlide(refs.Fill)
		refs.Fill.Size = UDim2.fromScale(1, 1)
		refs.Fill.BackgroundColor3 = Theme.BadDark
	else
		refs.Hp.Text = RockLabel.hpText(now, max)
		refs.Hp.TextColor3 = Theme.Text
		local target = UDim2.fromScale(now / max, 1)
		-- damage glides down (Health arrives in steps); a fresh label or a heal snaps
		local glided = false
		stopGlide(refs.Fill)
		if wasHp >= 0 and wasLocked == 0 and not wasVip and now < wasHp and RockLabel.FillGlide > 0 then
			glided = pcall(function()
				local info = TweenInfo.new(RockLabel.FillGlide, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local tween = TweenService:Create(refs.Fill, info, { Size = target })
				glides[refs.Fill] = tween
				tween:Play()
			end)
		end
		if not glided then
			refs.Fill.Size = target
		end
		refs.Fill.BackgroundColor3 = Theme.Bad
	end
end

-- The line under the bar ("Needs Lv 3", "VIP only", "Get closer"); "" hides it.
function RockLabel.setNote(refs: Refs, text: string, color: Color3?)
	if refs.Shown.Note == text and (text == "" or color == nil or refs.Note.TextColor3 == color) then
		return
	end
	refs.Shown.Note = text
	refs.Note.Text = text
	refs.Note.Visible = text ~= ""
	refs.Note.TextColor3 = color or Theme.Bad
end

-- Size (UIScale) and transparency of the whole label; small changes are skipped.
function RockLabel.setLook(refs: Refs, scale: number, transparency: number)
	local s = math.floor(scale * 50 + 0.5) / 50
	local t = math.floor(transparency * 20 + 0.5) / 20
	local shown = refs.Shown
	if shown.Scale ~= s then
		shown.Scale = s
		refs.Scale.Scale = s
	end
	if shown.Fade ~= t then
		shown.Fade = t
		refs.Name.TextTransparency = t
		refs.Hp.TextTransparency = t
		refs.Note.TextTransparency = t
		refs.Bar.BackgroundTransparency = t
		refs.Fill.BackgroundTransparency = t
		for _, stroke in refs.Strokes do
			stroke.Transparency = t
		end
	end
end

return RockLabel
