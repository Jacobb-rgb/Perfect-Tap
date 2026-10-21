--[[
	Quest giver NPCs (prototype, not wired into the map yet): original
	characters built from Roblox parts in the style of Kenney's Mini
	Characters (a big friendly head on a chunky body, short legs, stubby
	arms, flat colors, no meshes, no lights), each "mega cool" dressed for
	its area of the forge / mine world (the owner, 2026-10-21: NPCs around
	the map who give quests for artifacts and rare ores).

	Proportions (studs, feet at 0, front = local -Z): boots 0-0.46, legs to
	1.62, hips to 2.18, chest to 3.68, a 1.92 x 1.84 x 1.8 head to 5.52 (a
	player's R15 avatar is ~5.2 tall: the NPCs stand a little taller), gear
	and hats to ~7. Part names follow R15 where a part exists (Head,
	UpperTorso, LowerTorso, LeftArm/RightArm, LeftHand/RightHand,
	LeftLeg/RightLeg, LeftFoot/RightFoot; robed NPCs have a Robe instead of
	legs and hips).

	The server builds only the anchor; each client dresses the anchors near
	it (docs/plans/QUEST_NPC_PLAN.md 1.3 and 5.1):

	  anchor(outfitId, feet?) the NPC Model with ONE part, "Root" (its
	                          PrimaryPart): an invisible box around the
	                          body at `feet` (the feet center; front = the
	                          CFrame's LookVector). Root never collides, is
	                          never queried or touched (players walk through
	                          the NPC; mouse aim and grab rays pass it) and
	                          carries the CollectionService tag
	                          MovementConfig.BeamIgnoreTag. Attachments on
	                          Root (from the outfit's Height constant, so
	                          they need no outfit parts):
	                            NameplatePoint    over the top of the gear
	                                              (the name BillboardGui)
	                            QuestMarkerPoint  over the nameplate (the
	                                              quest marker)
	                            PromptPoint       chest height in front (the
	                                              ProximityPrompt, made with
	                                              PromptConfig.make)
	                          Attributes: Npc (outfit id), DisplayName,
	                          Title, Area, Paint (a PopTheme.Paints key),
	                          Height (studs, feet to the top of the gear),
	                          RootHeight (Root's center over the feet).
	  dress(model)            adds the outfit parts (at most MaxParts - 1)
	                          and the quest pad (a flat disc in the NPC's
	                          Pop paint with a glowing rim) into an anchor
	                          model, standing on Root; undresses first.
	                          Every part: anchored, CanCollide / CanTouch /
	                          CanQuery off, Massless; only the big body
	                          parts cast shadows. Returns the parts added.
	  undress(model)          removes every part but Root.
	  build(outfitId, feet?)  anchor + dress (previews, specs, portraits).
	  Outfits / ById          the quest givers in lineup order (Id, Name,
	                          Title, Area, Floor = a MineFloors Id or nil
	                          for the lobby, Paint = a PopTheme.Paints key
	                          (one source for the nameplate title, the pad,
	                          the marker and the dialog band), Accent = that
	                          paint's Top color, Height = the dressed top of
	                          the gear; tests/NpcBuilder.spec checks it).
	  partCount(model)        BaseParts in a model.

	Animation contract (QuestController, client only, see the plan 5.1):
	  - a part with the attribute Group belongs to a rigid group that moves
	    as one (workspace:BulkMoveTo over the group's parts, never one part
	    at a time);
	  - Group = NpcBuilder.HeadGroup ("Head"): the head and everything worn
	    on it (face, hair, beard, hat, helmet, hood, goggles, mask); it
	    turns about the vertical axis through (0, NeckY, 0) of the feet;
	  - every other Group is a floating group (its parts also carry
	    Float = true: the scholar's book, his relic shards, the bubbles, the
	    heartstone with its stones, each rune stone with its glyph); it
	    bobs up and down as one;
	  - no part changes Size at run time (an idle "breath" is a small bob
	    of the whole model, not a scale).
	An unknown id dresses a plain townsperson (never errors).

	Pure: only creates Instances (the Lune tests and preview renders use it).
]]

local MovementConfig = require(script.Parent.Parent.Config.MovementConfig)
local PopTheme = require(script.Parent.Parent.Config.PopTheme)

local NpcBuilder = {}

export type Outfit = {
	Id: string,
	Name: string,
	Title: string,
	Area: string,
	Floor: string?, -- MineFloors Id; nil = the lobby
	Paint: string, -- a PopTheme.Paints key (unique per NPC)
	Accent: Color3, -- = PopTheme.Paints[Paint].Top (filled in below)
	Height: number, -- feet to the top of the dressed gear (the spec checks it)
}

NpcBuilder.MaxParts = 70
NpcBuilder.RootHeight = 2.8
NpcBuilder.RootSize = Vector3.new(2.6, 5.6, 2)
NpcBuilder.NameplateGap = 0.7 -- the nameplate point over the top of the gear
NpcBuilder.MarkerGap = 1.6 -- the marker point over the nameplate point
NpcBuilder.HeadTop = 5.52
NpcBuilder.NeckY = 3.68 -- the head group turns about (0, NeckY, 0)
NpcBuilder.HeadGroup = "Head"
NpcBuilder.PlainHeight = 5.75 -- the plain townsperson (unknown ids)
NpcBuilder.PadSize = Vector3.new(0.14, 4.1, 4.1) -- the quest pad (a flat cylinder: height, diameter)
NpcBuilder.PadRim = 0.36 -- the glowing rim around the pad (extra diameter)

local rgb = Color3.fromRGB

local OUTFITS: { { [string]: any } } = {
	{ Id = "Scholar", Name = "Archivist Quill", Title = "Relic Scholar", Area = "Lobby", Paint = "Purple", Height = 6.85 },
	{ Id = "GemPolisher", Name = "Misty Gleam", Title = "Gem Polisher", Area = "Lobby", Paint = "Pink", Height = 6.61 },
	{
		Id = "Explorer",
		Name = "Pip Farwander",
		Title = "Deep Explorer",
		Area = "Quarry",
		Floor = "Quarry",
		Paint = "Orange",
		Height = 6.48,
	},
	{
		Id = "LavaSmith",
		Name = "Brakka Emberhand",
		Title = "Lava Smith",
		Area = "EmberCaves",
		Floor = "EmberCaves",
		Paint = "Red",
		Height = 6.27,
	},
	{
		Id = "CrystalMiner",
		Name = "Sela Shardwell",
		Title = "Crystal Miner",
		Area = "DeepHollow",
		Floor = "DeepHollow",
		Paint = "Teal",
		Height = 6.9,
	},
	{
		Id = "PalaceGuard",
		Name = "Captain Aurel",
		Title = "Palace Guard",
		Area = "SunkenPalace",
		Floor = "SunkenPalace",
		Paint = "Yellow",
		Height = 7.34,
	},
	{
		Id = "StormEngineer",
		Name = "Volta Sparkwright",
		Title = "Storm Engineer",
		Area = "StormglassRift",
		Floor = "StormglassRift",
		Paint = "Blue",
		Height = 6.99,
	},
	{
		Id = "CoreShaman",
		Name = "Ashka",
		Title = "Core Shaman",
		Area = "HeartstoneCore",
		Floor = "HeartstoneCore",
		Paint = "Green",
		Height = 6.88,
	},
}

NpcBuilder.Outfits = {} :: { Outfit }
NpcBuilder.ById = {} :: { [string]: Outfit }
for _, spec in OUTFITS do
	local paint = PopTheme.Paints[spec.Paint] or PopTheme.Paints.Slate
	local outfit: Outfit = {
		Id = spec.Id,
		Name = spec.Name,
		Title = spec.Title,
		Area = spec.Area,
		Floor = spec.Floor,
		Paint = spec.Paint,
		Accent = paint.Top,
		Height = spec.Height,
	}
	table.insert(NpcBuilder.Outfits, outfit)
	NpcBuilder.ById[outfit.Id] = outfit
end

-- The Pop paint of an outfit id (Slate for unknown ids).
function NpcBuilder.paintOf(outfitId: string): PopTheme.Paint
	local outfit = NpcBuilder.ById[outfitId]
	return outfit and PopTheme.Paints[outfit.Paint] or PopTheme.Paints.Slate
end

---------------------------------------------------------------- body plan

local SHOULDER_Y = 3.42
local ARM = Vector3.new(0.7, 1.32, 0.76)
local HAND = Vector3.new(0.62, 0.62, 0.66)
local HEAD = Vector3.new(1.92, 1.84, 1.8)
local HEAD_Y = 4.6 -- head center (bottom 3.68, top 5.52)
local FACE_Z = -HEAD.Z / 2 -- the face plane

local DARK = rgb(34, 28, 38)
local WHITE = rgb(255, 255, 255)
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass

type Ctx = {
	Model: Model,
	Base: CFrame,
	Top: number, -- highest local Y of any part so far (not Root)
	ShoulderX: number,
	Group: string?, -- the rigid group new parts join (nil = none)
}

-- One part at a local CFrame (relative to the feet; -Z = front): decor
-- flags, no shadow; joins ctx.Group.
local function add(ctx: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Shape = shape or Enum.PartType.Block
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = ctx.Base * cf
	if ctx.Group then
		p:SetAttribute("Group", ctx.Group)
	end
	p.Parent = ctx.Model
	-- the box's highest point over the feet
	local half = size / 2
	local up = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
	ctx.Top = math.max(ctx.Top, cf.Position.Y + up)
	return p
end

-- A big body part: casts a shadow.
local function solid(ctx: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = add(ctx, name, cf, size, color, material)
	p.CastShadow = true
	return p
end

local function glow(ctx: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3): Part
	return add(ctx, name, cf, size, color, NEON)
end

-- A cylinder whose axis runs along `cf`'s Y (upright at an unrotated cf).
local function upright(ctx: Ctx, name: string, cf: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material?): Part
	return add(
		ctx,
		name,
		cf * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(height, diameter, diameter),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A cylinder whose axis runs along `cf`'s Z (discs facing the front).
local function facing(ctx: Ctx, name: string, cf: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?): Part
	return add(
		ctx,
		name,
		cf * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(length, diameter, diameter),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function ball(ctx: Ctx, name: string, position: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	return add(ctx, name, CFrame.new(position), Vector3.new(diameter, diameter, diameter), color, material, Enum.PartType.Ball)
end

-- A thin rod from a to b (hoses, straps, handles).
local function rod(ctx: Ctx, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?): Part
	local length = (b - a).Magnitude
	return add(ctx, name, CFrame.lookAt((a + b) / 2, b), Vector3.new(thickness, thickness, length), color, material)
end

-- A floating part of the group `group` (it bobs with the group's other parts).
local function float(p: Part, group: string): Part
	p:SetAttribute("Float", true)
	p:SetAttribute("Group", group)
	return p
end

type Look = {
	Skin: Color3,
	Shirt: Color3,
	Pants: Color3?,
	Boots: Color3?,
	Bulk: number?, -- chest width factor (1 = 2.0 studs)
	Robe: Color3?, -- a long robe instead of legs and hips
	Hem: Color3?, -- the robe's hem band
}

-- Legs (or a robe), the chest and the head; sets the shoulder width.
local function body(ctx: Ctx, look: Look)
	local bulk = look.Bulk or 1
	if look.Robe then
		solid(ctx, "Robe", CFrame.new(0, 1.17, 0), Vector3.new(2.15, 2.1, 1.3), look.Robe)
		add(ctx, "Hem", CFrame.new(0, 0.15, 0), Vector3.new(2.35, 0.3, 1.45), look.Hem or look.Robe)
	else
		local pants = look.Pants or look.Shirt
		for _, side in { -1, 1 } do
			local name = if side > 0 then "Right" else "Left"
			add(ctx, name .. "Foot", CFrame.new(side * 0.48, 0.23, -0.1), Vector3.new(0.84, 0.46, 1.12), look.Boots or DARK)
			solid(ctx, name .. "Leg", CFrame.new(side * 0.48, 1.04, 0), Vector3.new(0.74, 1.16, 0.8), pants)
		end
		solid(ctx, "LowerTorso", CFrame.new(0, 1.9, 0), Vector3.new(1.9, 0.56, 1.06), pants)
	end
	solid(ctx, "UpperTorso", CFrame.new(0, 2.93, 0), Vector3.new(2 * bulk, 1.5, 1.12), look.Shirt)
	ctx.Group = NpcBuilder.HeadGroup
	solid(ctx, "Head", CFrame.new(0, HEAD_Y, 0), HEAD, look.Skin)
	ctx.Group = nil
	ctx.ShoulderX = bulk + 0.36
end

-- The rotation of an arm from its shoulder: `pitch` swings it forward,
-- `out` lifts it sideways.
local function shoulder(ctx: Ctx, side: number, pitch: number, out: number): CFrame
	return CFrame.new(side * ctx.ShoulderX, SHOULDER_Y, 0) * CFrame.Angles(pitch, 0, side * out)
end

-- One arm (sleeve + hand). Returns the hand center (in the arm's frame).
local function arm(
	ctx: Ctx,
	side: number,
	pitch: number,
	out: number,
	sleeve: Color3,
	hand: Color3,
	armSize: Vector3?,
	handSize: Vector3?
): CFrame
	local name = if side > 0 then "Right" else "Left"
	local s = armSize or ARM
	local pivot = shoulder(ctx, side, pitch, out)
	solid(ctx, name .. "Arm", pivot * CFrame.new(0, -s.Y / 2 + 0.1, 0), s, sleeve)
	local h = pivot * CFrame.new(0, -(s.Y + 0.2), 0)
	add(ctx, name .. "Hand", h, handSize or HAND, hand)
	return h
end

-- A point along an arm from its shoulder (cuffs, bracers, gauntlets).
local function along(ctx: Ctx, side: number, pitch: number, out: number, down: number): CFrame
	return shoulder(ctx, side, pitch, out) * CFrame.new(0, -down, 0)
end

type Face = {
	Brows: Color3?,
	BrowTilt: number?, -- + = a slight frown, - = lifted
	Mouth: string?, -- "Flat" | "Smile" | "Grin" | nil (none: a beard or a mask covers it)
	MouthY: number?, -- the mouth's height (default under the eyes)
	MouthZ: number?, -- the mouth's front (default the face plane)
	ShineZ: number?, -- where the eye shines sit (default just in front of the eyes)
}

-- Round dot eyes with a white shine, optional brows and a mouth: a flat
-- line, a smile (turned-up corners) or an open grin with teeth. All of it
-- joins the head group.
local function face(ctx: Ctx, spec: Face)
	ctx.Group = NpcBuilder.HeadGroup
	local eyeY = HEAD_Y + 0.08
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		facing(ctx, name .. "Eye", CFrame.new(side * 0.4, eyeY, FACE_Z - 0.02), 0.06, 0.34, DARK)
		add(
			ctx,
			name .. "EyeShine",
			CFrame.new(side * 0.4 + 0.07, eyeY + 0.07, spec.ShineZ or FACE_Z - 0.06),
			Vector3.new(0.11, 0.11, 0.02),
			WHITE
		)
		if spec.Brows then
			add(
				ctx,
				name .. "Brow",
				CFrame.new(side * 0.42, HEAD_Y + 0.4, FACE_Z - 0.03) * CFrame.Angles(0, 0, side * (spec.BrowTilt or 0.12)),
				Vector3.new(0.46, 0.12, 0.06),
				spec.Brows
			)
		end
	end
	local y = spec.MouthY or HEAD_Y - 0.42
	local z = spec.MouthZ or FACE_Z - 0.02
	if spec.Mouth == "Flat" then
		add(ctx, "Mouth", CFrame.new(0, y, z), Vector3.new(0.4, 0.09, 0.05), DARK)
	elseif spec.Mouth == "Smile" then
		add(ctx, "Mouth", CFrame.new(0, y, z), Vector3.new(0.32, 0.09, 0.05), DARK)
		for _, side in { -1, 1 } do
			add(
				ctx,
				(if side > 0 then "Right" else "Left") .. "MouthCorner",
				CFrame.new(side * 0.21, y + 0.05, z) * CFrame.Angles(0, 0, side * 0.65),
				Vector3.new(0.18, 0.09, 0.05),
				DARK
			)
		end
	elseif spec.Mouth == "Grin" then
		add(ctx, "Mouth", CFrame.new(0, y - 0.04, z), Vector3.new(0.62, 0.28, 0.05), rgb(96, 30, 44))
		add(ctx, "Teeth", CFrame.new(0, y + 0.05, z - 0.02), Vector3.new(0.52, 0.09, 0.03), WHITE)
	end
	ctx.Group = nil
end

---------------------------------------------------------------- the quest givers

-- Archivist Quill, Relic Scholar (lobby, artifact quests): a long royal
-- purple robe with a gold stripe and hem, a plum mantle and a tall gold
-- collar, a long white beard, gold spectacles, a tall two-step archivist's
-- hat with a gold band and a violet relic gem, an open relic book floating
-- at his raised right hand with a glowing relic over its pages, relic
-- shards drifting round him and a magnifying glass in his left hand.
local function scholar(ctx: Ctx)
	local robe = rgb(124, 70, 204)
	local plum = rgb(76, 38, 124)
	local gold = rgb(242, 192, 70)
	local beard = rgb(240, 238, 230)
	local violet = rgb(222, 128, 255)
	local skin = rgb(238, 198, 166)
	body(ctx, { Skin = skin, Shirt = robe, Robe = robe, Hem = gold })
	for _, side in { -1, 1 } do
		add(ctx, (if side > 0 then "Right" else "Left") .. "Foot", CFrame.new(side * 0.44, 0.13, -0.66), Vector3.new(0.62, 0.26, 0.5), plum)
	end
	add(ctx, "RobeStripe", CFrame.new(0, 1.2, -0.66), Vector3.new(0.36, 1.9, 0.06), gold)
	add(ctx, "Sash", CFrame.new(0, 2.2, 0), Vector3.new(2.12, 0.34, 1.22), gold)
	solid(ctx, "Mantle", CFrame.new(0, 3.48, 0.02), Vector3.new(2.6, 0.46, 1.36), plum)
	-- right hand raised palm-up to the book, left hand holds the glass
	local right = arm(ctx, 1, 0.95, 0.35, robe, skin)
	local left = arm(ctx, -1, 0.55, 0.08, robe, skin)
	add(ctx, "RightCuff", along(ctx, 1, 0.95, 0.35, 1.08), Vector3.new(0.82, 0.24, 0.88), gold)
	add(ctx, "LeftCuff", along(ctx, -1, 0.55, 0.08, 1.08), Vector3.new(0.82, 0.24, 0.88), gold)
	-- the head group: eyes behind the spectacles, bushy white brows, beard
	-- and moustache, side hair, the collar behind the head and the hat
	face(ctx, { ShineZ = FACE_Z - 0.11 })
	ctx.Group = NpcBuilder.HeadGroup
	add(ctx, "Collar", CFrame.new(0, 4.1, 1.0) * CFrame.Angles(0.3, 0, 0), Vector3.new(2.4, 1.2, 0.2), gold)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(
			ctx,
			name .. "Brow",
			CFrame.new(side * 0.42, HEAD_Y + 0.5, FACE_Z - 0.04) * CFrame.Angles(0, 0, side * -0.18),
			Vector3.new(0.54, 0.18, 0.08),
			beard
		)
		add(ctx, name .. "Hair", CFrame.new(side * 0.98, HEAD_Y + 0.05, 0.2), Vector3.new(0.18, 0.9, 1.3), beard)
		facing(ctx, name .. "SpecRim", CFrame.new(side * 0.42, HEAD_Y + 0.1, FACE_Z - 0.03), 0.06, 0.6, gold)
		facing(ctx, name .. "SpecLens", CFrame.new(side * 0.42, HEAD_Y + 0.1, FACE_Z - 0.07), 0.04, 0.44, rgb(200, 240, 255), GLASS).Transparency =
			0.35
	end
	add(ctx, "SpecBridge", CFrame.new(0, HEAD_Y + 0.14, FACE_Z - 0.05), Vector3.new(0.3, 0.07, 0.05), gold)
	add(ctx, "Beard", CFrame.new(0, 3.82, FACE_Z - 0.14), Vector3.new(1.4, 1.0, 0.34), beard)
	add(ctx, "Moustache", CFrame.new(0, 4.3, FACE_Z - 0.2), Vector3.new(1.1, 0.24, 0.22), beard)
	upright(ctx, "HatBrim", CFrame.new(0, 5.6, 0), 0.16, 2.3, robe)
	upright(ctx, "HatCrown", CFrame.new(0, 6.02, 0), 0.7, 1.62, robe)
	upright(ctx, "HatBand", CFrame.new(0, 5.8, 0), 0.22, 1.66, gold)
	upright(ctx, "HatTop", CFrame.new(0, 6.6, 0.05), 0.5, 1.22, plum)
	glow(ctx, "HatGem", CFrame.new(0, 5.82, -0.84) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.3, 0.3, 0.08), violet)
	ctx.Group = nil
	-- the floating relic book over the right hand, pages tilted to the front
	local book = CFrame.new(right.Position + Vector3.new(0.15, 0.75, -0.2)) * CFrame.Angles(-0.6, -0.3, 0)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		local tilt = CFrame.Angles(0, 0, side * 0.2)
		float(add(ctx, "Book" .. name .. "Cover", book * CFrame.new(side * 0.44, 0, 0) * tilt, Vector3.new(0.86, 0.08, 1.12), plum), "Book")
		float(
			add(
				ctx,
				"Book" .. name .. "Page",
				book * CFrame.new(side * 0.4, 0.07, 0) * tilt,
				Vector3.new(0.76, 0.08, 1.0),
				rgb(250, 238, 206)
			),
			"Book"
		)
	end
	float(glow(ctx, "BookRune", book * CFrame.new(0.4, 0.13, 0) * CFrame.Angles(0, 0, 0.2), Vector3.new(0.4, 0.04, 0.5), gold), "Book")
	float(
		glow(
			ctx,
			"BookRelic",
			book * CFrame.new(0, 0.75, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
			Vector3.new(0.36, 0.36, 0.36),
			violet
		),
		"Book"
	)
	-- relic shards drifting round him (each its own group)
	for i, spot in { Vector3.new(-1.75, 5.4, 0.3), Vector3.new(1.85, 6.0, 0.7), Vector3.new(-2.05, 3.7, -0.5) } do
		float(
			glow(
				ctx,
				"Shard" .. i,
				CFrame.new(spot) * CFrame.Angles(0.6 * i, 0.8, 0.5),
				Vector3.new(0.24, 0.42, 0.24),
				if i == 2 then gold else violet
			),
			"Shard" .. i
		)
	end
	-- the magnifying glass held up in the left hand
	local grip = left.Position
	add(ctx, "GlassHandle", CFrame.new(grip + Vector3.new(0, 0.3, -0.12)), Vector3.new(0.16, 0.8, 0.16), rgb(110, 62, 40))
	facing(ctx, "GlassRim", CFrame.new(grip + Vector3.new(0, 1.05, -0.12)) * CFrame.Angles(0, 0.35, 0), 0.12, 0.8, gold)
	facing(
		ctx,
		"GlassLens",
		CFrame.new(grip + Vector3.new(0, 1.05, -0.12)) * CFrame.Angles(0, 0.35, 0),
		0.14,
		0.62,
		rgb(170, 240, 250),
		GLASS
	).Transparency =
		0.3
end

-- Misty Gleam, Gem Polisher (lobby, cleaning quests): a white work suit
-- with aqua overalls, big yellow rubber gloves, aqua rubber boots, twin
-- aqua spray tanks on her back with glowing bands and a hose to the spray
-- wand in her right hand, soap bubbles drifting from its nozzle, pink hair
-- in a bun with an aqua headband, a jeweler's loupe glowing over her right
-- eye and a big happy grin, a pink polishing cloth at her hip.
local function gemPolisher(ctx: Ctx)
	local white = rgb(240, 244, 248)
	local aqua = rgb(40, 186, 200)
	local aquaDark = rgb(26, 128, 150)
	local yellow = rgb(255, 208, 48)
	local pink = rgb(255, 120, 172)
	local skin = rgb(240, 192, 152)
	local glowAqua = rgb(50, 226, 214)
	body(ctx, { Skin = skin, Shirt = white, Pants = aqua, Boots = aquaDark })
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "BootCuff",
			CFrame.new(side * 0.48, 0.6, -0.02),
			Vector3.new(0.9, 0.22, 0.9),
			white
		)
	end
	add(ctx, "Bib", CFrame.new(0, 2.72, -0.58), Vector3.new(1.3, 1.1, 0.08), aqua)
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "Strap",
			CFrame.new(side * 0.55, 3.42, -0.58),
			Vector3.new(0.28, 0.66, 0.08),
			aqua
		)
	end
	add(ctx, "Cloth", CFrame.new(-0.7, 1.78, -0.58) * CFrame.Angles(0, 0, 0.12), Vector3.new(0.5, 0.64, 0.06), pink)
	-- right arm points the spray wand forward, left hand on the hip
	local glove = Vector3.new(0.74, 0.72, 0.78)
	local right = arm(ctx, 1, 0.95, 0.12, white, yellow, nil, glove)
	arm(ctx, -1, -0.12, 0.3, white, yellow, nil, glove)
	add(ctx, "RightGloveCuff", along(ctx, 1, 0.95, 0.12, 1.14), Vector3.new(0.84, 0.3, 0.88), yellow)
	add(ctx, "LeftGloveCuff", along(ctx, -1, -0.12, 0.3, 1.14), Vector3.new(0.84, 0.3, 0.88), yellow)
	-- the spray wand straight ahead of the right fist
	-- (aimed forward and out to her right, so the wand shows its length from the front)
	local hand = right.Position
	local muzzle = hand + Vector3.new(0, 0.12, 0)
	local dir = Vector3.new(0.6, 0.12, -0.8).Unit
	local aim = CFrame.lookAt(muzzle, muzzle + dir)
	add(ctx, "WandGrip", CFrame.new(hand + Vector3.new(0, -0.1, -0.05)), Vector3.new(0.24, 0.6, 0.24), DARK)
	add(ctx, "WandTube", aim * CFrame.new(0, 0, -0.75), Vector3.new(0.16, 0.16, 1.3), rgb(190, 200, 210), METAL)
	add(ctx, "WandNozzle", aim * CFrame.new(0, 0, -1.5), Vector3.new(0.34, 0.34, 0.3), aqua)
	glow(ctx, "WandTip", aim * CFrame.new(0, 0, -1.67), Vector3.new(0.22, 0.22, 0.06), glowAqua)
	local bubbles = {
		{ At = Vector3.new(1.75, 0.55, -1.55), D = 0.5 },
		{ At = Vector3.new(1.9, 1.15, -1.2), D = 0.36 },
		{ At = Vector3.new(1.6, 1.55, -1.05), D = 0.62 },
	}
	for i, b in bubbles do
		local bubble = float(ball(ctx, "Bubble" .. i, hand + b.At, b.D, rgb(190, 240, 255), GLASS), "Bubble" .. i)
		bubble.Transparency = 0.35
	end
	-- the twin tanks and the hose to the wand
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		local x = side * 0.42
		local tank = upright(ctx, name .. "Tank", CFrame.new(x, 2.95, 1.05), 1.75, 0.74, aqua)
		tank.CastShadow = true
		upright(ctx, name .. "TankCap", CFrame.new(x, 3.92, 1.05), 0.24, 0.48, white)
		upright(ctx, name .. "TankBand", CFrame.new(x, 2.55, 1.05), 0.14, 0.78, glowAqua, NEON)
	end
	local elbow = Vector3.new(1.5, 1.75, 0.35)
	rod(ctx, "HoseFront", hand + Vector3.new(0, -0.35, 0.05), elbow, 0.16, DARK)
	rod(ctx, "HoseBack", elbow, Vector3.new(0.42, 2.0, 1.25), 0.16, DARK)
	-- the head group: face with a grin, blush, hair, headband and the loupe
	face(ctx, { Brows = pink, BrowTilt = -0.1, Mouth = "Grin" })
	ctx.Group = NpcBuilder.HeadGroup
	for _, side in { -1, 1 } do
		facing(
			ctx,
			(if side > 0 then "Right" else "Left") .. "Blush",
			CFrame.new(side * 0.7, HEAD_Y - 0.22, FACE_Z - 0.01),
			0.04,
			0.28,
			rgb(255, 150, 160)
		)
	end
	add(ctx, "HairTop", CFrame.new(0, 5.62, 0.06), Vector3.new(2.02, 0.36, 1.94), pink)
	add(ctx, "HairBack", CFrame.new(0, 4.78, 0.8), Vector3.new(2.0, 1.4, 0.36), pink)
	ball(ctx, "HairBun", Vector3.new(0, 6.14, 0.35), 0.95, pink)
	add(ctx, "Headband", CFrame.new(0, 5.4, -0.02), Vector3.new(2.04, 0.22, 1.9), aqua)
	add(ctx, "LoupeArm", CFrame.new(0.42, 5.05, FACE_Z - 0.12), Vector3.new(0.08, 0.5, 0.08), DARK)
	facing(ctx, "LoupeBody", CFrame.new(0.4, HEAD_Y + 0.08, FACE_Z - 0.18), 0.36, 0.52, DARK)
	facing(ctx, "LoupeLens", CFrame.new(0.4, HEAD_Y + 0.08, FACE_Z - 0.38), 0.05, 0.38, rgb(190, 110, 255), NEON)
	ctx.Group = nil
end

-- Pip Farwander, Deep Explorer (the Mine Station in the quarry, mining and
-- ore quests): a brown wide-brim hat with brass goggles, a red scarf with a
-- tail, a bright orange field jacket with a glowing brass compass on its
-- chest, olive cargo trousers, tall brown boots, a belt with pouches, a
-- ginger braid and a smile, an amber lantern held out in front in his left
-- hand, a pickaxe resting on his right shoulder, and a big pack with a
-- bedroll and a rope coil.
local function explorer(ctx: Ctx)
	local skin = rgb(214, 158, 116)
	local jacket = rgb(250, 140, 38)
	local jacketDark = rgb(204, 96, 24)
	local olive = rgb(96, 106, 70)
	local brown = rgb(110, 66, 40)
	local red = rgb(228, 50, 54)
	local sand = rgb(232, 210, 156)
	local hat = rgb(132, 86, 50)
	local hatDark = rgb(96, 60, 36)
	local brass = rgb(214, 170, 74)
	local ginger = rgb(206, 98, 40)
	local pack = rgb(122, 94, 58)
	local amber = rgb(255, 176, 44)
	local steel = rgb(206, 212, 226)
	body(ctx, { Skin = skin, Shirt = jacket, Pants = olive, Boots = brown })
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(ctx, name .. "BootCuff", CFrame.new(side * 0.48, 0.68, -0.02), Vector3.new(0.88, 0.24, 0.9), rgb(140, 88, 52))
		add(ctx, name .. "Pouch", CFrame.new(side * 0.66, 1.9, -0.6), Vector3.new(0.44, 0.42, 0.3), brown)
	end
	add(ctx, "Pocket", CFrame.new(0.5, 3.0, -0.58), Vector3.new(0.5, 0.44, 0.06), jacketDark)
	add(ctx, "Belt", CFrame.new(0, 2.14, 0), Vector3.new(1.98, 0.24, 1.12), brown)
	add(ctx, "Buckle", CFrame.new(0, 2.14, -0.58), Vector3.new(0.34, 0.22, 0.06), brass)
	add(ctx, "Scarf", CFrame.new(0, 3.74, 0), Vector3.new(1.56, 0.36, 1.3), red)
	add(ctx, "ScarfTail", CFrame.new(0.5, 3.3, -0.7) * CFrame.Angles(-0.2, 0, -0.15), Vector3.new(0.36, 0.86, 0.12), red)
	-- the glowing compass on the chest strap
	facing(ctx, "Compass", CFrame.new(-0.5, 3.0, -0.62), 0.12, 0.62, brass)
	glow(ctx, "CompassNeedle", CFrame.new(-0.5, 3.0, -0.7) * CFrame.Angles(0, 0, 0.6), Vector3.new(0.08, 0.44, 0.04), red)
	-- left hand holds the lantern out in front, right hand the pickaxe on the shoulder
	local left = arm(ctx, -1, 0.9, 0.55, jacket, skin)
	local right = arm(ctx, 1, 0.9, 0.25, jacket, skin)
	local hang = left.Position
	add(ctx, "LanternBail", CFrame.new(hang + Vector3.new(0, -0.32, 0)), Vector3.new(0.1, 0.36, 0.1), brown)
	add(ctx, "LanternCap", CFrame.new(hang + Vector3.new(0, -0.56, 0)), Vector3.new(0.68, 0.18, 0.68), brass)
	glow(ctx, "LanternGlow", CFrame.new(hang + Vector3.new(0, -0.95, 0)), Vector3.new(0.52, 0.62, 0.52), amber)
	add(ctx, "LanternBase", CFrame.new(hang + Vector3.new(0, -1.33, 0)), Vector3.new(0.68, 0.16, 0.68), brass)
	-- the pickaxe: the handle from the right fist up over the shoulder, the
	-- head across behind it (seen beside his head from the front)
	local fist = right.Position
	local head = Vector3.new(1.62, 4.95, 0.9)
	local up = (head - fist).Unit
	rod(ctx, "PickHandle", fist - up * 0.35, head + up * 0.12, 0.2, rgb(150, 96, 56))
	local across = CFrame.lookAt(head, head + up) -- the head's frame: Z along the handle
	add(ctx, "PickBladeIn", across * CFrame.new(-0.46, 0.06, 0) * CFrame.Angles(0, 0, -0.22), Vector3.new(1.0, 0.3, 0.3), steel, METAL)
	add(ctx, "PickBladeOut", across * CFrame.new(0.46, 0.06, 0) * CFrame.Angles(0, 0, 0.22), Vector3.new(1.0, 0.3, 0.3), steel, METAL)
	-- the head group: smiling face, hair, braid and the explorer's hat with goggles
	face(ctx, { Brows = ginger, BrowTilt = -0.1, Mouth = "Smile" })
	ctx.Group = NpcBuilder.HeadGroup
	add(ctx, "HairBack", CFrame.new(0, 4.95, 0.78), Vector3.new(1.98, 1.0, 0.36), ginger)
	add(ctx, "Braid", CFrame.new(-0.55, 4.0, 0.95) * CFrame.Angles(0.2, 0, 0.1), Vector3.new(0.38, 1.1, 0.38), ginger)
	add(ctx, "BraidTie", CFrame.new(-0.6, 3.45, 1.06) * CFrame.Angles(0.2, 0, 0.1), Vector3.new(0.44, 0.16, 0.44), red)
	upright(ctx, "HatBrim", CFrame.new(0, 5.58, 0), 0.14, 2.8, hat)
	solid(ctx, "HatCrown", CFrame.new(0, 6.0, 0.04), Vector3.new(1.72, 0.76, 1.56), hat)
	add(ctx, "HatDent", CFrame.new(0, 6.42, 0.04), Vector3.new(1.2, 0.12, 0.9), hatDark)
	add(ctx, "HatBand", CFrame.new(0, 5.78, 0.04), Vector3.new(1.76, 0.2, 1.6), sand)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		facing(ctx, name .. "GoggleRim", CFrame.new(side * 0.4, 5.86, -0.8), 0.22, 0.56, brass)
		facing(ctx, name .. "GoggleLens", CFrame.new(side * 0.4, 5.86, -0.92), 0.04, 0.42, rgb(110, 210, 240), GLASS)
	end
	ctx.Group = nil
	-- the pack: bedroll and rope coil
	solid(ctx, "Pack", CFrame.new(0, 2.9, 1.05), Vector3.new(1.7, 1.9, 0.88), pack)
	add(ctx, "PackFlap", CFrame.new(0, 3.7, 1.05), Vector3.new(1.76, 0.52, 0.96), rgb(96, 72, 44))
	add(ctx, "Bedroll", CFrame.new(0, 4.12, 1.22), Vector3.new(1.95, 0.62, 0.62), rgb(176, 84, 50), nil, Enum.PartType.Cylinder)
	facing(ctx, "Rope", CFrame.new(-0.98, 2.55, 1.0) * CFrame.Angles(0, math.pi / 2, 0), 0.26, 0.86, rgb(214, 186, 130))
end

-- Brakka Emberhand, Lava Smith (Ember Caves, Emberite and smelting
-- quests): a broad smith with bare arms in huge iron gauntlets with
-- glowing ember bands and knuckles, a bright cream leather apron over a
-- dark shirt, a glowing ingot buckle, an iron pauldron with a glowing
-- trim, a horned iron helmet with ember horn tips, a big braided red beard
-- with gold rings round a laughing grin, and a giant forge hammer resting
-- on his right shoulder, its big head glowing.
local function lavaSmith(ctx: Ctx)
	local skin = rgb(178, 112, 78)
	local iron = rgb(60, 58, 68)
	local ironLight = rgb(112, 110, 124)
	local apron = rgb(244, 222, 172)
	local apronTrim = rgb(236, 182, 64)
	local shirt = rgb(70, 44, 34)
	local beard = rgb(200, 70, 34)
	local bone = rgb(240, 222, 192)
	local ember = rgb(255, 146, 34)
	local hot = rgb(255, 212, 70)
	body(ctx, { Skin = skin, Shirt = shirt, Pants = rgb(54, 46, 46), Boots = iron, Bulk = 1.18 })
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "ToeCap",
			CFrame.new(side * 0.48, 0.28, -0.6),
			Vector3.new(0.88, 0.4, 0.2),
			ironLight,
			METAL
		)
	end
	add(ctx, "Belt", CFrame.new(0, 2.16, 0), Vector3.new(2.42, 0.34, 1.2), rgb(52, 34, 26))
	glow(ctx, "Buckle", CFrame.new(0, 2.16, -0.62), Vector3.new(0.56, 0.28, 0.08), hot)
	add(ctx, "ApronBib", CFrame.new(0, 2.98, -0.6), Vector3.new(1.5, 1.24, 0.08), apron)
	add(ctx, "ApronSkirt", CFrame.new(0, 1.42, -0.6), Vector3.new(1.76, 1.3, 0.08), apron)
	add(ctx, "ApronHem", CFrame.new(0, 0.82, -0.61), Vector3.new(1.8, 0.14, 0.08), apronTrim)
	solid(ctx, "Pauldron", CFrame.new(-1.62, 3.72, 0) * CFrame.Angles(0, 0, 0.28), Vector3.new(1.06, 0.38, 1.26), iron, METAL)
	add(ctx, "PauldronTrim", CFrame.new(-1.68, 3.5, 0) * CFrame.Angles(0, 0, 0.32), Vector3.new(1.08, 0.12, 1.3), ember, NEON)
	-- bare arms in the gauntlets: right fist on the hammer, left fist at the side
	local bigArm = Vector3.new(0.82, 1.32, 0.84)
	local fistSize = Vector3.new(0.86, 0.76, 0.86)
	local right = arm(ctx, 1, 0.85, 0.15, skin, ironLight, bigArm, fistSize)
	arm(ctx, -1, -0.05, 0.2, skin, ironLight, bigArm, fistSize)
	for _, spec in { { 1, 0.85, 0.15 }, { -1, -0.05, 0.2 } } do
		local side, pitch, out = spec[1], spec[2], spec[3]
		local name = if side > 0 then "Right" else "Left"
		add(ctx, name .. "Gauntlet", along(ctx, side, pitch, out, 1.0), Vector3.new(0.98, 0.72, 0.98), iron, METAL)
		glow(ctx, name .. "GauntletBand", along(ctx, side, pitch, out, 0.84), Vector3.new(1.02, 0.14, 1.02), ember)
		glow(ctx, name .. "Knuckles", along(ctx, side, pitch, out, 1.6) * CFrame.new(0, 0, -0.42), Vector3.new(0.7, 0.2, 0.06), hot)
	end
	-- the forge hammer on the right shoulder: the handle from the fist up
	-- over the shoulder, the big head across behind it, glowing
	local fist = right.Position
	local top = Vector3.new(1.98, 4.92, 0.78)
	local up = (top - fist).Unit
	rod(ctx, "HammerHandle", fist - up * 0.4, top, 0.26, rgb(92, 60, 40))
	add(ctx, "HammerGrip", CFrame.lookAt(fist, fist + up), Vector3.new(0.32, 0.32, 0.6), rgb(52, 34, 26))
	solid(ctx, "HammerHead", CFrame.new(top), Vector3.new(1.4, 0.92, 0.92), iron, METAL)
	glow(
		ctx,
		"HammerRune",
		CFrame.new(top + Vector3.new(0, 0, -0.47)) * CFrame.Angles(0, 0, math.pi / 4),
		Vector3.new(0.42, 0.42, 0.04),
		hot
	)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(ctx, name .. "HammerFace", CFrame.new(top + Vector3.new(side * 0.76, 0, 0)), Vector3.new(0.14, 1.04, 1.04), ironLight, METAL)
		glow(ctx, name .. "HammerGlow", CFrame.new(top + Vector3.new(side * 0.84, 0, 0)), Vector3.new(0.04, 0.7, 0.7), ember)
	end
	-- the head group: face with a laughing grin in the beard, braids, the horned helmet
	face(ctx, { Brows = beard, BrowTilt = 0.2, Mouth = "Grin", MouthY = 4.1, MouthZ = FACE_Z - 0.31 })
	ctx.Group = NpcBuilder.HeadGroup
	add(ctx, "Beard", CFrame.new(0, 3.86, FACE_Z - 0.12), Vector3.new(1.7, 0.9, 0.34), beard)
	add(ctx, "Moustache", CFrame.new(0, 4.32, FACE_Z - 0.22), Vector3.new(1.3, 0.24, 0.2), beard)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(ctx, name .. "Braid", CFrame.new(side * 0.42, 3.15, FACE_Z - 0.12), Vector3.new(0.32, 0.8, 0.32), beard)
		add(ctx, name .. "BraidRing", CFrame.new(side * 0.42, 2.92, FACE_Z - 0.12), Vector3.new(0.4, 0.16, 0.4), rgb(236, 186, 70), METAL)
	end
	solid(ctx, "Helmet", CFrame.new(0, 5.5, 0.02), Vector3.new(2.04, 0.76, 1.94), iron, METAL)
	add(ctx, "HelmetRim", CFrame.new(0, 5.17, 0.02), Vector3.new(2.14, 0.2, 2.04), ironLight, METAL)
	add(ctx, "HelmetCrest", CFrame.new(0, 5.9, 0.02), Vector3.new(0.32, 0.26, 1.8), ironLight, METAL)
	add(ctx, "NoseGuard", CFrame.new(0, 4.92, FACE_Z - 0.08), Vector3.new(0.24, 0.62, 0.1), ironLight, METAL)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(ctx, name .. "Horn", CFrame.new(side * 1.2, 5.55, 0) * CFrame.Angles(0, 0, side * -0.55), Vector3.new(0.42, 0.7, 0.44), bone)
		glow(
			ctx,
			name .. "HornTip",
			CFrame.new(side * 1.48, 6.0, 0) * CFrame.Angles(0, 0, side * -0.25),
			Vector3.new(0.26, 0.5, 0.28),
			ember
		)
	end
	ctx.Group = nil
end

-- Sela Shardwell, Crystal Miner (Deep Hollow, crystal ore quests): slate
-- crystal armor with warm gold plates, glowing magenta crystals growing
-- from both pauldrons, a crystal core in the chest plate, a miner's helmet
-- with a crown of three glowing crystals and a warm gold head lamp, a teal
-- bandana, a black ponytail and a calm smile, glowing vials on the belt, a
-- crystal pack on her back and a cluster of glowing crystals held up in
-- her left hand.
local function crystalMiner(ctx: Ctx)
	local skin = rgb(162, 106, 74)
	local slate = rgb(64, 78, 104)
	local plate = rgb(230, 180, 84)
	local suit = rgb(38, 72, 88)
	local crystal = rgb(236, 44, 176)
	local crystal2 = rgb(150, 70, 255)
	local lamp = rgb(255, 214, 90)
	local hair = rgb(30, 28, 40)
	body(ctx, { Skin = skin, Shirt = slate, Pants = suit, Boots = slate })
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(ctx, name .. "KneeGuard", CFrame.new(side * 0.48, 1.08, -0.44), Vector3.new(0.78, 0.46, 0.2), plate, METAL)
		upright(ctx, name .. "Vial", CFrame.new(side * 0.66, 1.95, -0.6), 0.5, 0.28, crystal, NEON)
	end
	add(ctx, "Belt", CFrame.new(0, 2.16, 0), Vector3.new(1.98, 0.26, 1.12), rgb(36, 40, 52))
	add(ctx, "ChestPlate", CFrame.new(0, 3.02, -0.58), Vector3.new(1.5, 1.0, 0.1), plate, METAL)
	glow(ctx, "CoreCrystal", CFrame.new(0, 3.02, -0.66) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.46, 0.46, 0.12), crystal)
	-- pauldrons with crystal clusters
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		solid(
			ctx,
			name .. "Pauldron",
			CFrame.new(side * 1.46, 3.72, 0) * CFrame.Angles(0, 0, side * -0.22),
			Vector3.new(1.0, 0.4, 1.2),
			plate,
			METAL
		)
		local cluster = {
			{ At = Vector3.new(side * 1.5, 4.3, 0.1), Size = Vector3.new(0.34, 1.0, 0.34), Tilt = side * -0.35 },
			{ At = Vector3.new(side * 1.8, 4.1, -0.25), Size = Vector3.new(0.26, 0.72, 0.26), Tilt = side * -0.7 },
			{ At = Vector3.new(side * 1.3, 4.15, 0.42), Size = Vector3.new(0.24, 0.62, 0.24), Tilt = side * -0.1 },
		}
		for i, c in cluster do
			local cf = CFrame.new(c.At) * CFrame.Angles(0, math.pi / 4, c.Tilt)
			glow(ctx, name .. "ShoulderCrystal" .. i, cf, c.Size, if i == 2 then crystal2 else crystal)
		end
	end
	-- left hand raises a crystal cluster, right arm relaxed
	local left = arm(ctx, -1, 1.05, 0.15, suit, slate, nil, Vector3.new(0.7, 0.68, 0.74))
	arm(ctx, 1, -0.05, 0.14, suit, slate, nil, Vector3.new(0.7, 0.68, 0.74))
	add(ctx, "LeftBracer", along(ctx, -1, 1.05, 0.15, 0.95), Vector3.new(0.8, 0.5, 0.86), plate, METAL)
	add(ctx, "RightBracer", along(ctx, 1, -0.05, 0.14, 0.95), Vector3.new(0.8, 0.5, 0.86), plate, METAL)
	local held = left.Position
	local shards = {
		{ Name = "HeldCrystal", At = Vector3.new(0, 0.84, -0.05), Size = Vector3.new(0.46, 1.3, 0.46), Tilt = 0.08, Color = crystal },
		{ Name = "HeldCrystal2", At = Vector3.new(-0.24, 0.5, 0.06), Size = Vector3.new(0.3, 0.7, 0.3), Tilt = 0.32, Color = crystal2 },
		{ Name = "HeldCrystal3", At = Vector3.new(0.24, 0.46, -0.1), Size = Vector3.new(0.26, 0.56, 0.26), Tilt = -0.3, Color = crystal2 },
	}
	for _, s in shards do
		glow(ctx, s.Name, CFrame.new(held + s.At) * CFrame.Angles(0, math.pi / 4, 0) * CFrame.Angles(0, 0, s.Tilt), s.Size, s.Color)
	end
	add(ctx, "Scarf", CFrame.new(0, 3.76, 0), Vector3.new(1.6, 0.3, 1.28), rgb(36, 196, 184))
	-- the head group: smiling face, ponytail, the helmet with lamp and crystal crown
	face(ctx, { Brows = hair, BrowTilt = 0.05, Mouth = "Smile" })
	ctx.Group = NpcBuilder.HeadGroup
	add(ctx, "HairBack", CFrame.new(0, 4.9, 0.82), Vector3.new(1.96, 0.9, 0.3), hair)
	add(ctx, "Ponytail", CFrame.new(0, 4.35, 1.12) * CFrame.Angles(0.35, 0, 0), Vector3.new(0.42, 1.1, 0.42), hair)
	solid(ctx, "Helmet", CFrame.new(0, 5.48, 0.02), Vector3.new(2.04, 0.72, 1.94), slate, METAL)
	add(ctx, "HelmetBrim", CFrame.new(0, 5.16, -0.98), Vector3.new(2.0, 0.14, 0.42), plate, METAL)
	add(ctx, "LampHousing", CFrame.new(0, 5.46, -1.06), Vector3.new(0.56, 0.46, 0.3), plate, METAL)
	glow(ctx, "LampLens", CFrame.new(0, 5.46, -1.22), Vector3.new(0.38, 0.3, 0.05), lamp)
	glow(ctx, "CrestCrystal", CFrame.new(0, 6.3, 0.15) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.42, 1.2, 0.42), crystal)
	for _, side in { -1, 1 } do
		glow(
			ctx,
			(if side > 0 then "Right" else "Left") .. "CrestCrystal",
			CFrame.new(side * 0.45, 6.05, 0.2) * CFrame.Angles(0, math.pi / 4, side * -0.4),
			Vector3.new(0.3, 0.8, 0.3),
			crystal2
		)
	end
	ctx.Group = nil
	-- the crystal pack
	solid(ctx, "Pack", CFrame.new(0, 2.95, 1.0), Vector3.new(1.4, 1.5, 0.62), rgb(46, 52, 66))
	glow(ctx, "PackCrystal1", CFrame.new(-0.5, 4.0, 1.25) * CFrame.Angles(0, math.pi / 4, 0.3), Vector3.new(0.5, 1.4, 0.5), crystal)
	glow(ctx, "PackCrystal2", CFrame.new(0.52, 3.86, 1.25) * CFrame.Angles(0, math.pi / 4, -0.35), Vector3.new(0.4, 1.0, 0.4), crystal2)
end

-- Captain Aurel, Palace Guard (Sunken Palace, Flawless gold and palace
-- relic quests): gold armor over royal violet, a violet tabard with an aqua
-- gem, a long violet cape, layered gold pauldrons and greaves, an
-- open-faced gold helmet with cheek guards and a tall aqua plume running
-- front to back, a gold trident with a glowing aqua gem in the right hand
-- and a round violet shield with a gold rim on the left arm.
local function palaceGuard(ctx: Ctx)
	local skin = rgb(116, 74, 52)
	local gold = rgb(236, 184, 58)
	local goldDark = rgb(184, 132, 40)
	local violet = rgb(96, 60, 162)
	local violetDark = rgb(60, 38, 110)
	local aqua = rgb(20, 186, 196)
	local plume = rgb(44, 196, 204)
	body(ctx, { Skin = skin, Shirt = gold, Pants = violetDark, Boots = goldDark })
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "Greave",
			CFrame.new(side * 0.48, 0.86, -0.04),
			Vector3.new(0.82, 0.64, 0.88),
			gold,
			METAL
		)
	end
	add(ctx, "Belt", CFrame.new(0, 2.16, 0), Vector3.new(2.02, 0.24, 1.14), goldDark)
	add(ctx, "Tabard", CFrame.new(0, 1.85, -0.6), Vector3.new(1.1, 1.6, 0.08), violet)
	glow(ctx, "ChestGem", CFrame.new(0, 3.08, -0.6) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.42, 0.42, 0.1), aqua)
	solid(ctx, "Cape", CFrame.new(0, 2.2, 0.8) * CFrame.Angles(-0.08, 0, 0), Vector3.new(2.1, 3.2, 0.14), violet)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		solid(
			ctx,
			name .. "Pauldron",
			CFrame.new(side * 1.45, 3.74, 0) * CFrame.Angles(0, 0, side * -0.22),
			Vector3.new(1.02, 0.38, 1.26),
			gold,
			METAL
		)
		add(
			ctx,
			name .. "PauldronLow",
			CFrame.new(side * 1.64, 3.42, 0) * CFrame.Angles(0, 0, side * -0.38),
			Vector3.new(0.9, 0.26, 1.18),
			goldDark,
			METAL
		)
	end
	local gauntlet = Vector3.new(0.68, 0.66, 0.72)
	local right = arm(ctx, 1, 0.5, 0.25, violet, gold, nil, gauntlet)
	local left = arm(ctx, -1, 0.42, 0.12, violet, gold, nil, gauntlet)
	-- the head group: face, the helmet with its plume
	face(ctx, { Brows = rgb(40, 28, 24), BrowTilt = 0.1, Mouth = "Flat" })
	ctx.Group = NpcBuilder.HeadGroup
	solid(ctx, "Helmet", CFrame.new(0, 5.46, 0.02), Vector3.new(2.04, 0.74, 1.94), gold, METAL)
	add(ctx, "HelmetBand", CFrame.new(0, 5.12, 0.02), Vector3.new(2.12, 0.18, 2.02), goldDark, METAL)
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "CheekGuard",
			CFrame.new(side * 1.02, 4.62, -0.3),
			Vector3.new(0.16, 0.9, 1.0),
			gold,
			METAL
		)
	end
	add(ctx, "CrestBase", CFrame.new(0, 5.94, 0.02), Vector3.new(0.34, 0.28, 1.9), goldDark, METAL)
	add(ctx, "PlumeFront", CFrame.new(0, 6.42, -0.62) * CFrame.Angles(-0.4, 0, 0), Vector3.new(0.42, 0.9, 0.7), plume)
	add(ctx, "PlumeTop", CFrame.new(0, 6.72, 0.12), Vector3.new(0.48, 1.1, 1.0), plume)
	add(ctx, "PlumeBack", CFrame.new(0, 6.3, 0.98) * CFrame.Angles(0.65, 0, 0), Vector3.new(0.44, 0.95, 0.9), plume)
	add(ctx, "PlumeTail", CFrame.new(0, 5.4, 1.32) * CFrame.Angles(0.2, 0, 0), Vector3.new(0.4, 1.3, 0.42), rgb(28, 150, 170))
	ctx.Group = nil
	-- the trident, upright in the right hand
	local tx, tz = right.Position.X, right.Position.Z - 0.05
	add(ctx, "TridentShaft", CFrame.new(tx, 2.95, tz), Vector3.new(0.2, 5.7, 0.2), gold, METAL)
	add(ctx, "TridentBar", CFrame.new(tx, 5.85, tz), Vector3.new(1.2, 0.2, 0.22), gold, METAL)
	glow(ctx, "TridentGem", CFrame.new(tx, 5.85, tz - 0.16) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.34, 0.34, 0.14), aqua)
	for i, x in { -0.5, 0, 0.5 } do
		local h = if x == 0 then 1.1 else 0.8
		add(ctx, "TridentProng" .. i, CFrame.new(tx + x, 5.95 + h / 2, tz), Vector3.new(0.18, h, 0.18), gold, METAL)
		add(
			ctx,
			"TridentTip" .. i,
			CFrame.new(tx + x, 5.95 + h + 0.08, tz) * CFrame.Angles(0, 0, math.pi / 4),
			Vector3.new(0.3, 0.3, 0.12),
			gold,
			METAL
		)
	end
	-- the shield on the left forearm, turned a little outward
	local shield = CFrame.new(left.Position + Vector3.new(-0.32, 0.45, -0.25)) * CFrame.Angles(0, 0.45, 0)
	facing(ctx, "ShieldRim", shield, 0.18, 2.0, gold, METAL)
	facing(ctx, "ShieldFace", shield * CFrame.new(0, 0, -0.06), 0.14, 1.7, violet)
	glow(ctx, "ShieldGem", shield * CFrame.new(0, 0, -0.16) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.5, 0.5, 0.08), aqua)
end

-- Volta Sparkwright, Storm Engineer (Stormglass Rift, storm ore and
-- machine quests): a navy jumpsuit with hazard yellow bands and a glowing
-- electric blue lightning bolt, a yellow hard hat with two lightning rods
-- tipped with glowing yellow balls and cyan goggles, electric blue hair and
-- a wide grin, a tesla coil pack with copper rings, an electric blue storm
-- orb and yellow arcs, a big yellow power glove with a blue core raised
-- high, and a giant wrench over her left shoulder.
local function stormEngineer(ctx: Ctx)
	local skin = rgb(240, 200, 168)
	local navy = rgb(40, 54, 100)
	local yellow = rgb(255, 202, 40)
	local dark = rgb(38, 38, 48)
	local copper = rgb(214, 124, 62)
	local spark = rgb(60, 168, 255) -- the electric blue glows
	local second = rgb(255, 214, 40) -- the yellow second glow
	local hair = rgb(64, 150, 255)
	local steel = rgb(196, 202, 214)
	body(ctx, { Skin = skin, Shirt = navy, Pants = navy, Boots = dark })
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(ctx, name .. "ShinBand", CFrame.new(side * 0.48, 0.86, 0), Vector3.new(0.78, 0.2, 0.84), yellow)
		add(ctx, name .. "Pouch", CFrame.new(side * 0.7, 1.9, -0.6), Vector3.new(0.42, 0.48, 0.3), rgb(150, 90, 50))
	end
	add(ctx, "Belt", CFrame.new(0, 2.15, 0), Vector3.new(2.04, 0.3, 1.14), dark)
	add(ctx, "Collar", CFrame.new(0, 3.72, 0), Vector3.new(1.6, 0.24, 1.22), yellow)
	-- the lightning bolt on the chest
	glow(ctx, "BoltTop", CFrame.new(0.1, 3.24, -0.58) * CFrame.Angles(0, 0, -0.45), Vector3.new(0.2, 0.52, 0.06), spark)
	glow(ctx, "BoltMid", CFrame.new(0, 3.02, -0.58), Vector3.new(0.42, 0.14, 0.06), spark)
	glow(ctx, "BoltLow", CFrame.new(-0.1, 2.78, -0.58) * CFrame.Angles(0, 0, -0.45), Vector3.new(0.2, 0.52, 0.06), spark)
	-- the power glove raised high
	local right = arm(ctx, 1, 0.1, 2.75, navy, yellow, nil, Vector3.new(0.92, 0.92, 0.92))
	add(ctx, "GloveCuff", along(ctx, 1, 0.1, 2.75, 1.12), Vector3.new(0.86, 0.3, 0.9), dark)
	glow(ctx, "GloveCore", right * CFrame.new(0, 0, -0.47), Vector3.new(0.3, 0.3, 0.06), spark)
	-- the giant wrench over the left shoulder: the handle from the fist,
	-- the open jaw beside her head
	local left = arm(ctx, -1, 0.7, 0.2, navy, dark)
	local fist = left.Position
	local jaw = Vector3.new(-1.86, 5.0, 0.5)
	local up = (jaw - fist).Unit
	rod(ctx, "WrenchHandle", fist - up * 0.35, jaw, 0.26, steel, METAL)
	local head = CFrame.lookAt(jaw, jaw + up) -- Z along the handle
	add(ctx, "WrenchHead", head * CFrame.new(0, 0, -0.12), Vector3.new(0.98, 0.3, 0.4), steel, METAL)
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "WrenchJaw",
			head * CFrame.new(side * 0.36, 0, -0.5),
			Vector3.new(0.26, 0.3, 0.6),
			steel,
			METAL
		)
	end
	-- the head group: face with a grin, hair, the hard hat, rods and goggles
	face(ctx, { Brows = hair, BrowTilt = -0.12, Mouth = "Grin" })
	ctx.Group = NpcBuilder.HeadGroup
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "HairTuft",
			CFrame.new(side * 1.04, 4.95, 0.2) * CFrame.Angles(0, 0, side * -0.45),
			Vector3.new(0.3, 0.6, 0.7),
			hair
		)
	end
	add(ctx, "HairBack", CFrame.new(0, 4.85, 0.92), Vector3.new(1.6, 0.7, 0.3), hair)
	solid(ctx, "HardHat", CFrame.new(0, 5.5, 0.02), Vector3.new(2.04, 0.7, 1.94), yellow)
	add(ctx, "HatBrim", CFrame.new(0, 5.18, -0.1), Vector3.new(2.3, 0.14, 2.3), yellow)
	add(ctx, "HatRidge", CFrame.new(0, 5.9, 0.02), Vector3.new(0.38, 0.2, 1.9), rgb(230, 170, 30))
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		add(
			ctx,
			name .. "Rod",
			CFrame.new(side * 0.66, 6.3, 0.25) * CFrame.Angles(0, 0, side * -0.25),
			Vector3.new(0.12, 1.0, 0.12),
			dark,
			METAL
		)
		glow(ctx, name .. "RodTip", CFrame.new(side * 0.79, 6.82, 0.25), Vector3.new(0.34, 0.34, 0.34), second).Shape = Enum.PartType.Ball
		facing(ctx, name .. "GoggleRim", CFrame.new(side * 0.38, 5.52, -0.98), 0.14, 0.54, dark)
		facing(ctx, name .. "Goggle", CFrame.new(side * 0.38, 5.52, -1.06), 0.04, 0.4, rgb(110, 210, 255), GLASS)
	end
	ctx.Group = nil
	-- the tesla coil pack and its storm orb
	solid(ctx, "Pack", CFrame.new(0, 2.85, 1.0), Vector3.new(1.5, 1.2, 0.84), dark)
	add(ctx, "PackStripe", CFrame.new(0, 2.45, 1.0), Vector3.new(1.54, 0.2, 0.88), yellow)
	upright(ctx, "CoilColumn", CFrame.new(0, 4.5, 1.4), 2.2, 0.46, copper, METAL)
	for i, y in { 4.0, 4.5, 5.0 } do
		upright(ctx, "CoilRing" .. i, CFrame.new(0, y, 1.4), 0.14, 1.0 - i * 0.08, copper, METAL)
	end
	ball(ctx, "StormOrb", Vector3.new(0, 6.02, 1.42), 0.86, spark, NEON)
	for _, side in { -1, 1 } do
		glow(
			ctx,
			(if side > 0 then "Right" else "Left") .. "Arc",
			CFrame.new(side * 0.62, 6.0, 1.42) * CFrame.Angles(0, 0, side * 0.7),
			Vector3.new(0.08, 0.5, 0.08),
			second
		)
	end
end

-- Ashka, Core Shaman (Heartstone Core, Mythic ore and core relic quests):
-- a deep jade hooded robe with glowing mint runes, a bone mask with glowing
-- mint eyes and a small pink mark, mint glowing beads, wide sleeves, a dark
-- staff with a stone claw holding the one pink floating heartstone circled
-- by mint stones, and three rune stones with mint glyphs floating at her
-- raised right hand.
local function coreShaman(ctx: Ctx)
	local robe = rgb(34, 104, 92)
	local robeDark = rgb(20, 62, 58)
	local pink = rgb(255, 56, 140)
	local mint = rgb(70, 240, 164)
	local bone = rgb(236, 226, 204)
	local stone = rgb(74, 64, 84)
	local wraps = rgb(42, 52, 52)
	body(ctx, { Skin = rgb(28, 18, 38), Shirt = robe, Robe = robe, Hem = robeDark })
	glow(ctx, "RuneLeft", CFrame.new(-0.42, 1.15, -0.67) * CFrame.Angles(0, 0, 0.22), Vector3.new(0.12, 1.5, 0.05), mint)
	glow(ctx, "RuneRight", CFrame.new(0.42, 1.15, -0.67) * CFrame.Angles(0, 0, -0.22), Vector3.new(0.12, 1.5, 0.05), mint)
	add(ctx, "Sash", CFrame.new(0, 2.2, 0), Vector3.new(2.12, 0.3, 1.24), stone)
	solid(ctx, "Mantle", CFrame.new(0, 3.5, 0.02), Vector3.new(2.6, 0.54, 1.44), robeDark)
	for i, x in { -0.42, 0, 0.42 } do
		ball(ctx, "Bead" .. i, Vector3.new(x, if x == 0 then 3.02 else 3.1, -0.76), 0.28, mint, NEON)
	end
	-- the head group: the hood round the head, the bone mask in its shadow
	ctx.Group = NpcBuilder.HeadGroup
	add(ctx, "HoodTop", CFrame.new(0, 5.66, 0.06), Vector3.new(2.24, 0.4, 2.12), robeDark)
	add(ctx, "HoodBack", CFrame.new(0, 4.6, 1.04), Vector3.new(2.24, 2.0, 0.26), robeDark)
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "HoodSide",
			CFrame.new(side * 1.08, 4.64, 0.1),
			Vector3.new(0.24, 1.92, 2.0),
			robeDark
		)
	end
	add(ctx, "HoodBrim", CFrame.new(0, 5.42, -0.98), Vector3.new(2.24, 0.32, 0.34), robeDark)
	add(ctx, "HoodPeak", CFrame.new(0, 6.02, 0.62) * CFrame.Angles(-0.5, 0, 0), Vector3.new(0.9, 0.55, 0.8), robeDark)
	for i, x in { -0.62, 0, 0.62 } do
		local h = if x == 0 then 0.9 else 0.6
		glow(
			ctx,
			"CrownCrystal" .. i,
			CFrame.new(x, 5.86 + h / 2, -0.62) * CFrame.Angles(0, math.pi / 4, x * -0.5),
			Vector3.new(0.24, h, 0.24),
			mint
		)
	end
	add(ctx, "Mask", CFrame.new(0, 4.7, FACE_Z - 0.04), Vector3.new(1.3, 1.04, 0.1), bone)
	add(ctx, "MaskChin", CFrame.new(0, 4.18, FACE_Z - 0.04) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.66, 0.66, 0.1), bone)
	for _, side in { -1, 1 } do
		local name = if side > 0 then "Right" else "Left"
		glow(
			ctx,
			name .. "Eye",
			CFrame.new(side * 0.3, 4.78, FACE_Z - 0.1) * CFrame.Angles(0, 0, side * 0.3),
			Vector3.new(0.36, 0.16, 0.04),
			mint
		)
		add(ctx, name .. "CheekMark", CFrame.new(side * 0.42, 4.42, FACE_Z - 0.1), Vector3.new(0.08, 0.26, 0.04), rgb(58, 120, 104))
	end
	glow(ctx, "MaskMark", CFrame.new(0, 5.06, FACE_Z - 0.1) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.18, 0.18, 0.04), pink)
	ctx.Group = nil
	-- wide sleeves: left hand on the staff, right hand raised to the rune stones
	local sleeve = Vector3.new(0.9, 1.32, 0.94)
	local left = arm(ctx, -1, 0.3, 0.14, robe, wraps, sleeve)
	local right = arm(ctx, 1, 0.65, 0.65, robe, wraps, sleeve)
	add(ctx, "LeftCuff", along(ctx, -1, 0.3, 0.14, 1.12), Vector3.new(1.02, 0.3, 1.06), robeDark)
	add(ctx, "RightCuff", along(ctx, 1, 0.65, 0.65, 1.12), Vector3.new(1.02, 0.3, 1.06), robeDark)
	-- the staff and its floating heartstone (one group with its stones)
	local sx, sz = left.Position.X, left.Position.Z - 0.25
	add(ctx, "StaffShaft", CFrame.new(sx, 2.75, sz), Vector3.new(0.22, 5.5, 0.22), rgb(70, 46, 46))
	for _, side in { -1, 1 } do
		add(
			ctx,
			(if side > 0 then "Right" else "Left") .. "StaffClaw",
			CFrame.new(sx + side * 0.26, 5.75, sz) * CFrame.Angles(0, 0, side * -0.4),
			Vector3.new(0.16, 0.8, 0.16),
			stone
		)
	end
	float(
		glow(ctx, "Heartstone", CFrame.new(sx, 6.4, sz) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.42, 0.95, 0.42), pink),
		"Heartstone"
	)
	float(
		glow(ctx, "HeartstoneCore", CFrame.new(sx, 6.4, sz) * CFrame.Angles(math.pi / 4, math.pi / 4, 0), Vector3.new(0.5, 0.5, 0.5), pink),
		"Heartstone"
	)
	for i = 1, 3 do
		local a = i * math.pi * 2 / 3 + 0.4
		float(
			glow(
				ctx,
				"OrbitStone" .. i,
				CFrame.new(sx + math.cos(a) * 0.7, 6.4 + (i - 2) * 0.18, sz + math.sin(a) * 0.7) * CFrame.Angles(a, a, 0),
				Vector3.new(0.18, 0.18, 0.18),
				mint
			),
			"Heartstone"
		)
	end
	-- three rune stones rising beside the right hand (each stone with its glyph)
	local hand = right.Position
	for i, spot in { Vector3.new(0.55, -0.45, -0.5), Vector3.new(0.85, 0.65, 0.15), Vector3.new(0.45, 1.75, 0.6) } do
		local cf = CFrame.new(hand + spot) * CFrame.Angles(0.1 * i, -0.35, 0.15 * (i - 2))
		float(add(ctx, "RuneStone" .. i, cf, Vector3.new(0.6, 0.8, 0.18), stone), "Rune" .. i)
		float(glow(ctx, "RuneGlyph" .. i, cf * CFrame.new(0, 0, -0.1), Vector3.new(0.18, 0.44, 0.04), mint), "Rune" .. i)
	end
end

-- A plain townsperson (unknown ids).
local function plain(ctx: Ctx)
	local skin = rgb(236, 190, 150)
	body(ctx, { Skin = skin, Shirt = rgb(186, 98, 48), Pants = rgb(60, 54, 70), Boots = rgb(70, 46, 34) })
	arm(ctx, 1, 0, 0.1, rgb(186, 98, 48), skin)
	arm(ctx, -1, 0, 0.1, rgb(186, 98, 48), skin)
	face(ctx, { Brows = rgb(80, 50, 30), Mouth = "Smile" })
	ctx.Group = NpcBuilder.HeadGroup
	add(ctx, "Hair", CFrame.new(0, 5.6, 0.08), Vector3.new(2.0, 0.3, 1.9), rgb(80, 50, 30))
	ctx.Group = nil
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	Scholar = scholar,
	GemPolisher = gemPolisher,
	Explorer = explorer,
	LavaSmith = lavaSmith,
	CrystalMiner = crystalMiner,
	PalaceGuard = palaceGuard,
	StormEngineer = stormEngineer,
	CoreShaman = coreShaman,
}

-- The quest pad under the feet: a flat disc in the NPC's Pop paint (Bottom)
-- on a slightly wider glowing rim (Top), both flush with the ground (0 to
-- PadSize.X), the boots standing in it.
local function pad(ctx: Ctx, paint: PopTheme.Paint)
	local h = NpcBuilder.PadSize.X
	upright(ctx, "PadRim", CFrame.new(0, h * 0.4, 0), h * 0.8, NpcBuilder.PadSize.Y + NpcBuilder.PadRim, paint.Top, NEON)
	upright(ctx, "Pad", CFrame.new(0, h / 2, 0), h, NpcBuilder.PadSize.Y, paint.Bottom)
end

---------------------------------------------------------------- build

function NpcBuilder.partCount(model: Instance): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function point(root: Part, name: string, y: number, z: number?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = CFrame.new(0, y - NpcBuilder.RootHeight, z or 0)
	a.Parent = root
	return a
end

-- The feet frame of a model built by anchor (nil without its Root).
local function feetOf(model: Model): CFrame?
	local root = model:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return root.CFrame * CFrame.new(0, -NpcBuilder.RootHeight, 0)
end

function NpcBuilder.anchor(outfitId: string, base: CFrame?): Model
	local feet = base or CFrame.new()
	local outfit = NpcBuilder.ById[outfitId]
	local model = Instance.new("Model")
	model.Name = "Npc_" .. outfitId

	-- the invisible body box (PrimaryPart): no collision, no queries, no touch
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Massless = true
	root.Transparency = 1
	root.Size = NpcBuilder.RootSize
	root.CFrame = feet * CFrame.new(0, NpcBuilder.RootHeight, 0)
	root:AddTag(MovementConfig.BeamIgnoreTag)
	root.Parent = model
	model.PrimaryPart = root
	local height = if outfit then outfit.Height else NpcBuilder.PlainHeight
	local nameplate = height + NpcBuilder.NameplateGap
	point(root, "NameplatePoint", nameplate)
	point(root, "QuestMarkerPoint", nameplate + NpcBuilder.MarkerGap)
	point(root, "PromptPoint", 3.0, -1.0)

	model:SetAttribute("Npc", outfitId)
	model:SetAttribute("DisplayName", if outfit then outfit.Name else "Townsperson")
	model:SetAttribute("Title", if outfit then outfit.Title else "")
	model:SetAttribute("Area", if outfit then outfit.Area else "Lobby")
	model:SetAttribute("Paint", if outfit then outfit.Paint else "Slate")
	model:SetAttribute("Height", height)
	model:SetAttribute("RootHeight", NpcBuilder.RootHeight)
	return model
end

function NpcBuilder.undress(model: Model)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Root" then
			child:Destroy()
		end
	end
end

function NpcBuilder.dress(model: Model): number
	local feet = feetOf(model)
	if not feet then
		return 0
	end
	NpcBuilder.undress(model)
	local id = model:GetAttribute("Npc")
	local outfitId = if type(id) == "string" then id else ""
	local ctx: Ctx = { Model = model, Base = feet, Top = 0, ShoulderX = 1.36, Group = nil }
	local build = BUILDERS[outfitId] or plain
	build(ctx)
	pad(ctx, NpcBuilder.paintOf(outfitId))
	return NpcBuilder.partCount(model) - 1
end

function NpcBuilder.build(outfitId: string, base: CFrame?): Model
	local model = NpcBuilder.anchor(outfitId, base)
	NpcBuilder.dress(model)
	return model
end

return NpcBuilder
