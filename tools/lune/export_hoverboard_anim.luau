--[[
	The hoverboard animation showreel (owner 2026-10-24: "add animations to
	the hoverboards and cool effects, e.g. lightning shooting out of them")
	for the video renderer (tools/preview/moves.html?scene=anim_hoverboard,
	render_anim.mjs) and the sheet (moves_sheet.mjs).

	The R15 block dummy rides the real board models with the game's code:
	Moves/BoardPose for the body, BoardPose.boardMount / flip and the
	HoverboardController bob / lean / roll formulas for the board, and the
	real HoverboardFx lightning (HoverboardBolts on the mounted board,
	flickered every FlickerEvery) drawn as short Neon sticks. Particles are
	not drawn (the renderer has none; they are in the earlier pictures).

	  lune run tools/lune/export_hoverboard_anim.luau [fps=30]
	-> build/preview/anim_hoverboard.json (same format as anim_moves.json)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local R15 = require("./lib/dummy_r15")

local root = process.cwd
Loader.init(root)

local CFrame, Vector3 = Loader.CFrame, roblox.Vector3
local MoveConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MoveConfig")
local HoverboardData = Loader.requirePath("ReplicatedStorage.Shared.Config.HoverboardData")
local HoverboardBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardBuilder")
local HoverboardFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardFx")
local HoverboardBolts = Loader.requirePath("ReplicatedStorage.Shared.Builders.HoverboardBolts")
local BoardPose = Loader.requirePath("ReplicatedStorage.Shared.Moves.BoardPose")

local fps = tonumber(process.args[1]) or 30
local DECK = HoverboardBuilder.DeckHeight
local BOB_HEIGHT, BOB_SPEED = 0.09, 2.6 -- HoverboardController
local GRAVITY, JUMP = 196.2, 50 -- Roblox defaults

local function hex(c: any): string
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end
local function cf12(cf: any): { number }
	local list = { cf:GetComponents() }
	for i, v in list do
		list[i] = round(v)
	end
	return list
end

---------------------------------------------------------------- groups: the dummy, the boards, the bolt sticks

local groups = {}
local groupIndex: { [string]: number } = {}
local function addGroup(name: string, parts: { any })
	table.insert(groups, { name = name, parts = parts })
	groupIndex[name] = #groups
end
for _, partName in R15.Order do
	local list = {}
	for _, piece in R15.pieces(partName) do
		table.insert(list, {
			piece.Shape,
			round(piece.Size.X),
			round(piece.Size.Y),
			round(piece.Size.Z),
			cf12(piece.CFrame),
			hex(piece.Color),
			piece.Material,
			0,
		})
	end
	if #list > 0 then
		addGroup(partName, list)
	end
end

local boards: { [string]: any } = {}
local sets: { [string]: any } = {}
for _, board in HoverboardData.List do
	local model = HoverboardBuilder.build(board.Id)
	local scene = Export.collect(model)
	local inverse = model.PrimaryPart.CFrame:Inverse()
	local list = {}
	for _, p in scene.parts do
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = table.unpack(p[5])
		local world = CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		table.insert(list, { p[1], p[2], p[3], p[4], cf12(inverse * world), p[6], p[7], p[8] })
	end
	addGroup("Board_" .. board.Id, list)
	boards[board.Id] = model
	local set = HoverboardFx.create(board.Id)
	HoverboardFx.mount(set, model)
	sets[board.Id] = set
end

-- bolt sticks: short Neon pieces laid along the bolt lines (the renderer can't stretch parts)
local ARC_STICK, STRIKE_STICK = 0.3, 1.2
local ARC_STICKS, STRIKE_STICKS = 70, 34
local function stickGroup(name: string, length: number, core: number, glow: number, color: any)
	addGroup(name, {
		{ 1, core, core, length, cf12(CFrame.identity), hex(color:Lerp(roblox.Color3.new(1, 1, 1), 0.7)), "Neon", 0 },
		{ 1, glow, glow, length, cf12(CFrame.identity), hex(color), "Neon", 0.6 },
	})
end
-- one stick set per board in the reel, in its glow colour
for _, boardId in { "RoyalPhoenix", "NeonComet", "TimberDrifter" } do
	local color = HoverboardData.get(boardId).Colors.Glow
	for i = 1, ARC_STICKS do
		stickGroup(`ArcStick_{boardId}_{i}`, ARC_STICK, HoverboardBolts.CoreWidth, HoverboardBolts.GlowWidth, color)
	end
	for i = 1, STRIKE_STICKS do
		stickGroup(`StrikeStick_{boardId}_{i}`, STRIKE_STICK, 0.16, 0.6, color)
	end
end

---------------------------------------------------------------- the script of the reel

type Seg = {
	Title: string,
	Subtitle: string,
	Board: string,
	Length: number,
	Mount: number?, -- hop on at this time (seconds into the segment)
	Speed: (number) -> number,
	Turn: (number) -> number,
	Jumps: { number }?,
	Surge: ((number) -> boolean)?,
	Camera: { Position: { number }, Target: { number }, Fov: number },
	Picks: { { number | string } },
}

local function ramp(a: number, b: number, from: number, to: number): (number) -> number
	return function(t: number): number
		return a + (b - a) * math.clamp((t - from) / (to - from), 0, 1)
	end
end
local function const(v: number): (number) -> number
	return function(): number
		return v
	end
end

local SIDE = { Position = { 9.5, 5.2, -6.5 }, Target = { 0, 3.2, 0 }, Fov = 42 }
local FRONT = { Position = { 4.5, 5.0, -10.5 }, Target = { 0, 3.0, 0 }, Fov = 42 }
local CLOSE = { Position = { 8, 4.8, -6.5 }, Target = { 0, 2.6, 0 }, Fov = 44 }
local HIGH = { Position = { 17, 9.5, -14 }, Target = { 0, 6.8, 0 }, Fov = 50 }

local SEGMENTS: { Seg } = {
	{
		Title = "NASKOČENÍ",
		Subtitle = "prkno přiletí zespodu s otočkou, udeří do něj blesk, hráč naskočí",
		Board = "RoyalPhoenix",
		Length = 2.6,
		Mount = 0.5,
		Speed = const(0),
		Turn = const(0),
		Camera = FRONT,
		Picks = { { 0.62, "blesk z nebe" }, { 0.8, "skok na prkno" }, { 1.3, "dopad" } },
	},
	{
		Title = "JÍZDA",
		Subtitle = "surfařský postoj, s rychlostí se přikrčí, v zatáčkách se naklání",
		Board = "RoyalPhoenix",
		Length = 3.6,
		Speed = ramp(0.1, 1, 0.2, 1.6),
		Turn = function(t: number): number
			return math.sin(t * 1.8) * math.clamp((t - 1.2) / 0.6, 0, 1)
		end,
		Camera = SIDE,
		Picks = { { 0.4, "klid" }, { 1.9, "plná rychlost" }, { 2.6, "zatáčka" } },
	},
	{
		Title = "SKOK + KICKFLIP",
		Subtitle = "při skoku se prkno pod nohama protočí, dopad s výbojem",
		Board = "RoyalPhoenix",
		Length = 3.2,
		Speed = const(0.8),
		Turn = const(0),
		Jumps = { 0.5, 1.9 },
		Camera = HIGH,
		Picks = { { 0.62, "odraz" }, { 0.75, "kickflip" }, { 1.05, "dopad" } },
	},
	{
		Title = "BLESKY",
		Subtitle = "z okrajů prkna šlehají blesky, nejvíc při plné rychlosti",
		Board = "RoyalPhoenix",
		Length = 2.6,
		Speed = const(1),
		Turn = const(0),
		Surge = function(t: number): boolean
			return t > 0.9 and t < 1.6
		end,
		Camera = CLOSE,
		Picks = { { 0.5, "jízda" }, { 1.1, "výboj" }, { 1.4, "výboj" } },
	},
	{
		Title = "NEON COMET",
		Subtitle = "azurové blesky",
		Board = "NeonComet",
		Length = 2.4,
		Mount = 0.2,
		Speed = ramp(0, 1, 0.9, 1.6),
		Turn = const(0),
		Camera = SIDE,
		Picks = { { 0.45, "blesk z nebe" }, { 1.2, "rozjezd" }, { 2.0, "plná rychlost" } },
	},
	{
		Title = "TIMBER DRIFTER",
		Subtitle = "prkna za mince mají blesků méně",
		Board = "TimberDrifter",
		Length = 2.4,
		Mount = 0.2,
		Speed = ramp(0, 1, 0.9, 1.6),
		Turn = const(0),
		Camera = SIDE,
		Picks = { { 0.45, "blesk z nebe" }, { 1.2, "rozjezd" }, { 2.0, "plná rychlost" } },
	},
}

---------------------------------------------------------------- frames

math.randomseed(7)
local function rand(): number
	return math.random()
end

local frames = {}
local segmentsOut = {}
local clock = 0
local RIDE_ROOT = R15.RootHeight + DECK -- HipHeight raised by the deck while riding

for index, seg in SEGMENTS do
	local set = sets[seg.Board]
	local boardModel = boards[seg.Board]
	local boardSpeed = HoverboardData.get(seg.Board).Speed
	table.insert(segmentsOut, {
		start = round(clock),
		stop = round(clock + seg.Length),
		title = seg.Title,
		subtitle = seg.Subtitle,
		move = seg.Board,
		number = `{index}/{#SEGMENTS}`,
		camera = { position = seg.Camera.Position, target = seg.Camera.Target, fov = seg.Camera.Fov },
		picks = seg.Picks,
	})
	local pitch, roll, air = 0, 0, 0
	local mountAt = if seg.Mount then seg.Mount else -10
	local landAt = -10
	local airAt: number? = nil
	local surgeUntil = if seg.Mount then mountAt + 1.0 else -10
	local strikeUntil = if seg.Mount then mountAt + 0.3 else -10
	local boltAt = 0
	local frameCount = math.floor(seg.Length * fps + 0.5)
	local dt = 1 / fps
	HoverboardBolts.hide(set.Bolts)
	for f = 0, frameCount - 1 do
		local t = f / fps
		local riding = t >= mountAt
		-- the HumanoidRootPart: standing before the hop on, raised by the deck after it, up in a jump
		local hrpY = R15.RootHeight
		if riding then
			hrpY = R15.RootHeight + DECK * math.clamp((t - mountAt) / 0.15, 0, 1)
		end
		local inAir = false
		for _, j in seg.Jumps or {} do
			local s = t - j
			local airTime = 2 * JUMP / GRAVITY
			if s >= 0 and s <= airTime then
				hrpY = RIDE_ROOT + JUMP * s - 0.5 * GRAVITY * s * s
				inAir = s > 0
			end
		end
		if inAir and not airAt then
			airAt = t
		elseif not inAir and airAt then
			landAt = t
			surgeUntil = t + 0.5
			airAt = nil
		end
		air += ((if inAir then 1 else 0) - air) * math.min(1, dt * (if inAir then 10 else 16))
		local speed01 = math.clamp(seg.Speed(t), 0, 1)
		local turn = math.clamp(seg.Turn(t), -1, 1)
		roll += (turn * 0.22 - roll) * math.min(1, dt * 6)
		pitch += (speed01 * 0.07 - pitch) * math.min(1, dt * 4)
		local hrp = CFrame.new(0, hrpY, 0)

		local row = {}
		for _ = 1, #groups do
			table.insert(row, 0)
		end
		-- the body
		local transforms: { [string]: any } = {}
		for _, joint in MoveConfig.Joints do
			transforms[joint] = CFrame.identity
		end
		local mount = if riding then math.clamp((t - mountAt) / BoardPose.MountTime, 0, 1) else 0
		if riding then
			local pose = BoardPose.evaluate({
				T = clock + t,
				Speed = speed01,
				Turn = roll / 0.22,
				Mount = mount,
				Air = air,
				Land = math.clamp(1 - (t - landAt) / BoardPose.LandTime, 0, 1),
			}, {})
			for joint, cf in pose do
				transforms[joint] = cf
			end
		end
		local parts = R15.solve(hrp, transforms)
		for name, cf in parts do
			local gi = groupIndex[name]
			if gi then
				row[gi] = cf12(cf)
			end
		end
		-- the board (HoverboardController.animate)
		if riding then
			-- HoverboardController.boardOffset: down by the HRP half height + the riding HipHeight
			local offset = CFrame.new(0, -RIDE_ROOT, 0)
			local bob = math.sin((clock + t) * BOB_SPEED) * BOB_HEIGHT * (1 - 0.5 * speed01)
			local rise, spin = 0, 0
			if mount < 1 then
				rise, spin = BoardPose.boardMount(mount)
			end
			local flip = if airAt and t - airAt < BoardPose.FlipTime then BoardPose.flip(t - airAt) else 0
			local boardCF = hrp * offset * CFrame.new(0, bob + rise, 0) * CFrame.Angles(pitch, spin, roll) * BoardPose.flipFrame(flip)
			row[groupIndex["Board_" .. seg.Board]] = cf12(boardCF)

			-- the lightning (HoverboardController: one flicker every FlickerEvery)
			if t >= boltAt then
				boltAt = t + HoverboardBolts.FlickerEvery
				local surge = if t < surgeUntil or (seg.Surge and seg.Surge(t)) then 0.6 else 0
				HoverboardFx.flicker(set, rand, speed01, surge)
				HoverboardFx.strike(set, rand, if t < strikeUntil then 1 else 0)
			end
			local function lay(bolt: any, prefix: string, stick: number, max: number, used: number): number
				if not bolt.Visible then
					return used
				end
				local points = bolt.Points
				for i = 1, #points - 1 do
					local a = boardCF * points[i].CFrame.Position
					local b = boardCF * points[i + 1].CFrame.Position
					local length = (b - a).Magnitude
					local n = math.max(1, math.ceil(length / stick - 0.15))
					for k = 1, n do
						used += 1
						if used > max then
							return used
						end
						local mid = a:Lerp(b, (k - 0.5) / n)
						row[groupIndex[prefix .. used]] = cf12(CFrame.lookAt(mid, b))
					end
				end
				return used
			end
			local used = 0
			for _, arc in set.Bolts.Arcs do
				used = lay(arc, `ArcStick_{seg.Board}_`, ARC_STICK, ARC_STICKS, used)
			end
			lay(set.Bolts.Strike, `StrikeStick_{seg.Board}_`, STRIKE_STICK, STRIKE_STICKS, 0)
		end
		table.insert(frames, row)
	end
	clock += seg.Length
end

local out = {
	fps = fps,
	duration = round(clock),
	brandNote = "hoverboardy: animace + blesky · náhled z herního kódu (BoardPose, HoverboardBolts)",
	sheetTitle = "TERRA FORGE: HOVERBOARDY",
	sheetSubtitle = "animace jízdy + blesky · náhled z herního kódu (BoardPose na R15 postavičce) · video: hoverboardy_animace.mp4",
	groups = groups,
	frames = frames,
	segments = segmentsOut,
}
fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/anim_hoverboard.json", serde.encode("json", out))
print(string.format("Exported anim_hoverboard: %d segments, %d frames (%.1f s)", #segmentsOut, #frames, clock))
