--[[
	Flora wayfinding: the MINE / UPGRADE / EXPLORE / BUILD signpost by the
	bridge, the NEXT AREA sign with its closed rope gate, and the plank
	boardwalk that runs from the east coast out over the sea toward the
	Sky package's NextIsland (LOBBY_PLAN 6.5 items 5-7).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local WorldLayout = require(Shared.Config.WorldLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

-- what sits on the outer coast moves out with it (bigger plots; 0 at 12 cells)
local COAST_SHIFT = WorldLayout.PlotGrid.CoastShift

local Signs = {}

-- Boards top to bottom: text, icon, a small yaw (radians) toward where it leads.
-- (big boards: the concept's foreground signpost reads from the hero camera)
Signs.Boards = {
	{ Text = "MINE", Icon = "Pickaxe", Y = 13.3, Yaw = 0.12 },
	{ Text = "UPGRADE", Icon = "Gear", Y = 10.0, Yaw = -0.08 },
	{ Text = "EXPLORE", Icon = "Compass", Y = 6.7, Yaw = 0.05 },
	{ Text = "BUILD", Icon = "House", Y = 3.4, Yaw = -0.1 },
}
Signs.BoardHeight = 3.0
Signs.BoardTextWidth = 8.0
Signs.BoardIconWidth = 3.0

--[[
	The big foreground signpost at the bridge's south-west foot: a thick
	post on the viewer's left (frame +X) with a hanging lantern on an arm
	(neon, no light), four double-sided boards reaching to the right, each
	with its icon on a square board next to the post (icons on both
	faces); gold letters with a solid dark outline that read from the hero
	camera.
]]
function Signs.signpost(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("Signpost")
	local frame = LobbyLayout.frame(piece)
	local m = Style.model("Signpost", parent)
	local postX = 5.4
	local post = frame * CFrame.new(postX, 0, 0)
	-- stone foot, post, cap and a lantern hanging from a short arm
	Style.block(m, post * CFrame.new(0, 0.35, 0), Vector3.new(3.0, 0.7, 3.0), Style.vary(C.StoneDark, rng, 0.04), nil, Style.solid())
	Style.block(m, post * CFrame.new(0.15, 0.95, 0.1), Vector3.new(2.3, 0.5, 2.3), Style.vary(C.Stone, rng, 0.04), nil, Style.tiny())
	local height = 15.4
	local main = Style.block(m, post * CFrame.new(0, height / 2, 0), Vector3.new(1.6, height, 1.6), C.WoodDark, nil, Style.decor())
	main.Name = "Post"
	Style.block(m, post * CFrame.new(0, height + 0.2, 0), Vector3.new(2.1, 0.4, 2.1), C.Wood, nil, Style.tiny())
	Style.block(m, post * CFrame.new(0.4, height - 0.5, -1.1), Vector3.new(0.4, 0.4, 2.4), C.WoodDark, nil, Style.tiny())
	Style.lantern(m, post * CFrame.new(0.4, height - 0.7, -2.0), { Kind = "Hanging", Color = C.LampAmber })
	-- the boards
	local iconW, textW, h = Signs.BoardIconWidth, Signs.BoardTextWidth, Signs.BoardHeight
	local total = iconW + textW
	for _, b in Signs.Boards do
		local pivot = post * CFrame.new(-0.8, b.Y, 0) * CFrame.Angles(0, b.Yaw, 0)
		-- one frame block behind both boards shows as a rim on both faces
		Style.block(
			m,
			pivot * CFrame.new(-total / 2 - 0.05, 0, 0),
			Vector3.new(total + 0.4, h + 0.4, 0.4),
			C.SignFrame,
			nil,
			Style.decor({ CastShadow = false })
		)
		local iconCf = pivot * CFrame.new(-iconW / 2 - 0.05, 0, 0)
		local iconBoard = Style.block(m, iconCf, Vector3.new(iconW - 0.1, h - 0.1, 0.6), C.SignBoard, nil, Style.tiny())
		iconBoard.Name = "IconBoard"
		for _, turn in { 0, math.pi } do
			Style.icon(m, iconCf * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -0.32 - 0.15), b.Icon, 2.6, C.SignText)
		end
		local board = Style.sign(m, pivot * CFrame.new(-iconW - textW / 2 - 0.05, 0, 0), b.Text, textW - 0.1, h - 0.1, {
			Kind = "Wood",
			DoubleSided = true,
			Frame = false,
			Depth = 0.6,
			StrokeColor = C.TextShadow,
			StrokeTransparency = 0,
		})
		board.Name = b.Text .. "Board"
	end
	-- flowers at the foot
	Style.flowers(m, (frame * CFrame.new(1.4, 0, 1.4)).Position, C.FlowerYellow, rng, 4, 1.1)
	return m
end

--[[
	NEXT AREA: a wooden sign on two posts with an arrow board pointing east,
	two lantern posts, and a closed rope gate with a SOON plank where the
	path meets the boardwalk.
]]
function Signs.nextArea(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("NextArea")
	local frame = LobbyLayout.frame(piece)
	local m = Style.model("NextArea", parent)
	for _, x in { -5.6, 5.6 } do
		Style.block(m, frame * CFrame.new(x, 4.75, 0), Vector3.new(1, 9.5, 1), C.WoodDark)
		Style.block(m, frame * CFrame.new(x, 9.65, 0), Vector3.new(1.4, 0.3, 1.4), C.Wood, nil, Style.tiny())
		Style.block(m, frame * CFrame.new(x, 0.3, 0), Vector3.new(1.8, 0.6, 1.8), Style.vary(C.StoneDark, rng, 0.04), nil, Style.tiny())
	end
	local board = Style.sign(m, frame * CFrame.new(0, 7.7, -0.75), "NEXT AREA", 11, 3, { Kind = "Wood", StrokeTransparency = 0 })
	board.Name = "NextAreaSign"
	-- arrow plank under the right end (viewer's right = frame -X = east)
	local arrowCf = frame * CFrame.new(-2.6, 5.15, -0.75)
	Style.block(m, arrowCf, Vector3.new(5.2, 1.7, 0.5), C.SignBoard, nil, Style.decor())
	Style.block(m, arrowCf * CFrame.new(0, 0, 0.1), Vector3.new(5.5, 2, 0.4), C.SignFrame, nil, Style.tiny())
	Style.icon(m, arrowCf * CFrame.new(0, 0, -0.45), "Arrow", 3.4, C.SignText)
	-- lantern posts either side (one light)
	Style.lantern(
		m,
		frame * CFrame.new(6.4, 0, -1.4) * CFrame.Angles(0, -math.pi / 2, 0),
		{ Kind = "Post", Height = 7, Color = C.LampAmber }
	)
	Style.lantern(m, frame * CFrame.new(-6.4, 0, -1.4) * CFrame.Angles(0, math.pi / 2, 0), {
		Kind = "Post",
		Color = C.LampAmber,
		Height = 7,
		Light = true,
		Range = 16,
	})
	-- bushes and flowers along the posts' line (the ToNextArea path runs 2 studs in front)
	Style.bush(m, (frame * CFrame.new(3.4, 0, 1)).Position, C.LeafGreen, rng, 2.2)
	Style.bush(m, (frame * CFrame.new(-3.2, 0, 1.1)).Position, C.LeafGreenDark, rng, 2)
	Kit.flowerPatch(m, (frame * CFrame.new(1.2, 0, 0.6)).Position, C.FlowerYellow, rng, 3)
	Kit.flowerPatch(m, (frame * CFrame.new(-1.3, 0, 0.7)).Position, C.FlowerPurple, rng, 3)
	-- closed rope gate where the boardwalk starts (players come from the west)
	local gate = Style.model("RopeGate", m)
	local gx, gz = 168 + COAST_SHIFT, -115
	local postTop = 3.2
	for _, dz in { -2.8, 2.8 } do
		Style.block(gate, CFrame.new(gx, postTop / 2, gz + dz), Vector3.new(0.8, postTop, 0.8), C.WoodDark)
		Style.block(gate, CFrame.new(gx, postTop + 0.15, gz + dz), Vector3.new(1.1, 0.3, 1.1), C.Wood, nil, Style.tiny())
		-- rope from the post top sagging to the middle
		local a = Vector3.new(gx, postTop - 0.3, gz + dz)
		local b = Vector3.new(gx, postTop - 1, gz)
		Style.block(
			gate,
			CFrame.lookAt((a + b) / 2, b),
			Vector3.new(0.3, 0.3, (b - a).Magnitude + 0.2),
			C.AwningRed,
			nil,
			Style.decor({ CastShadow = false })
		)
	end
	local soon = Style.sign(gate, CFrame.lookAt(Vector3.new(gx - 0.1, 1.45, gz), Vector3.new(gx - 10, 1.45, gz)), "SOON", 2.8, 1.2, {
		Kind = "Wood",
		DoubleSided = true,
		Frame = false,
		Depth = 0.3,
		Font = Style.LabelFont,
	})
	soon.Name = "SoonPlank"
	return m
end

--[[
	Boardwalk: a 6-wide plank deck from the end of the ToNextArea path at
	x 166 (+ the coast shift) on the ground, up a short flight of plank
	steps over the rim rocks of the east cliff, then on posts over the sea
	to a landing at x ~240 where NextIsland's bridge stub is. It runs along
	the path's line z = -115, so it continues the path and stays clear of
	the east bases' yards, which start at z > -112 there.
]]
Signs.Boardwalk = {
	Z = -115,
	Width = 6,
	StartX = 166 + COAST_SHIFT,
	StepX = 169 + COAST_SHIFT, -- first step (the rope gate stands at x 168 + COAST_SHIFT)
	StepCount = 6,
	StepRun = 1,
	StepRise = 0.8,
	EndX = 240,
	TopY = 0.45,
	PostsFromX = 188 + COAST_SHIFT, -- the rim rocks hide the posts before this
}

function Signs.boardwalk(parent: Instance, rng: Rng.Rng)
	local bw = Signs.Boardwalk
	local m = Style.model("NextAreaBoardwalk", parent)
	local z, w = bw.Z, bw.Width
	local function deck(x0: number, x1: number, top: number, width: number?)
		local cx = (x0 + x1) / 2
		local cf = CFrame.lookAt(Vector3.new(cx, top, z), Vector3.new(cx + 1, top, z))
		local parts = Style.planks(m, cf, Vector3.new(width or w, 0.6, x1 - x0), rng, { PlankWidth = 1.5 })
		parts[1].Name = "Deck"
	end
	-- on the ground at the end of the path
	deck(bw.StartX, bw.StepX, bw.TopY)
	-- plank steps up over the rim rocks (solid blocks down to the ground)
	local top = bw.TopY
	local x = bw.StepX
	for _ = 1, bw.StepCount do
		top += bw.StepRise
		local step = Style.block(
			m,
			CFrame.new(x + bw.StepRun / 2, top / 2, z),
			Vector3.new(bw.StepRun + 0.05, top, w),
			Style.vary(if top % 1.6 < 0.8 then C.Plank else C.WoodLight, rng, 0.04),
			nil,
			Style.solid()
		)
		step.Name = "Deck"
		x += bw.StepRun
	end
	local high = top
	local landingX = bw.EndX - 4
	deck(x, landingX, high)
	-- landing where the island's bridge stub meets it
	deck(landingX, bw.EndX + 4, high, w + 4)
	-- posts into the sea (they double as rail posts), cross beams; a lamp every 3rd post
	local seaY = -23
	local railH = 2.6
	local px = bw.PostsFromX
	local i = 0
	while px <= bw.EndX + 3 do
		local lampSide = if i % 3 == 0 then (if i % 2 == 0 then 1 else -1) else 0
		for _, side in { -1, 1 } do
			local pz = z + side * (w / 2 + (if px > landingX then 2 else 0) + 0.3)
			local postTop = high + railH + (if side == lampSide then 1.4 else 0)
			local h = postTop - seaY
			Style.block(m, CFrame.new(px, seaY + h / 2, pz), Vector3.new(0.8, h, 0.8), Style.vary(C.WoodDark, rng, 0.04))
			if side == lampSide then
				Kit.lampBox(m, CFrame.new(px, postTop, pz), 0.8, false)
			end
		end
		Style.block(m, CFrame.new(px, high - 1.1, z), Vector3.new(0.7, 0.7, w + 1.2), C.WoodDark, nil, Style.tiny())
		px += 7
		i += 1
	end
	-- entrance posts with lamps at the foot of the steps, rails along the deck
	for _, side in { -1, 1 } do
		-- on the deck edge: the east bases' yards begin just north of it (z > -112)
		local rz = z + side * (w / 2 - 0.35)
		Style.block(m, CFrame.new(bw.StepX + 0.4, (bw.TopY + 3) / 2, rz), Vector3.new(0.8, bw.TopY + 3, 0.8), C.WoodDark)
		Kit.lampBox(m, CFrame.new(bw.StepX + 0.4, bw.TopY + 3, rz), 0.8, false)
		local x0, x1 = x, landingX
		local sz = z + side * (w / 2 + 0.3) -- over the sea: in line with the posts
		Style.block(m, CFrame.new(x0 + 0.4, high + railH / 2, sz), Vector3.new(0.8, railH, 0.8), C.WoodDark)
		Style.block(
			m,
			CFrame.new((x0 + x1) / 2, high + railH - 0.2, sz),
			Vector3.new(x1 - x0, 0.4, 0.4),
			C.Wood,
			nil,
			Style.decor({ CastShadow = false })
		)
	end
	return m
end

function Signs.build(parent: Instance, rng: Rng.Rng)
	Signs.signpost(parent, Kit.sub(rng))
	Signs.nextArea(parent, Kit.sub(rng))
	Signs.boardwalk(parent, Kit.sub(rng))
end

return Signs
