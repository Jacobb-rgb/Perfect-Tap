--[[
	The blaster weapon case (the Kenney Blaster Kit crate silhouette in a
	blaster's Ore Glow look): the case the Blaster Vault sells and the one the
	crate-opening cinematic bursts open.

	Built at the origin: bottom center, the long side along Z, the front (the
	latches) facing +X, the lid hinged along its back (-X) edge. Two Models:
	  Base   the body with an ore-coloured band, feet, corner caps, straps,
	         handles, glowing latches, the ore pattern (lava cracks for hot
	         ores, a galaxy of stars and neon outlines for the rest), the
	         glowing seam ("Seam") and the glowing inside ("Inside", shows
	         when the lid opens)
	  Lid    the lid with a raised panel, straps, corner caps, the glowing
	         diamond emblem and, from level 4, ore crystals (more with the level)
	Sizes scale with `size` (1 = a 7 stud long case). About 60-90 parts.
	Pure: only Instance creation (Lune previews and the client both build it).
]]

local Geo = require(script.Parent.Geo)
local BlasterData = require(script.Parent.Parent.Config.BlasterData)

local CaseBuilder = {}

export type Case = {
	Base: Model,
	Lid: Model,
	Seam: BasePart,
	Inside: BasePart,
	HingeOffset: CFrame, -- the hinge line in the case's frame (rotate the lid about its local Z)
	Height: number, -- the closed case's height
	BaseHeight: number,
	Glow: Color3,
	Body: Color3,
}

local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass

local TINY = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

-- Hot ores get the lava look, the rest the galaxy look.
CaseBuilder.HotOres = {
	[""] = true,
	Coal = true,
	Copper = true,
	Emberite = true,
	Gold = true,
	RoyalAurum = true,
	Bronze = true,
	Sunstone = true,
	VolcanicCore = true,
	PhoenixFeather = true,
}

local function block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return Geo.block(parent, cf, size, color, material or SMOOTH, table.clone(TINY))
end

local function glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3): Part
	return Geo.block(parent, cf, size, color, NEON, table.clone(TINY))
end

-- A small neon crystal (a column and a turned cube tip).
local function shard(parent: Instance, base: Vector3, up: Vector3, s: number, length: number, color: Color3)
	local hint = if math.abs(up.X) > 0.9 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local right = (hint - up * hint:Dot(up)).Unit
	local cf = CFrame.fromMatrix(base, right, up) * CFrame.Angles(0, math.pi / 4, 0)
	glow(parent, cf * CFrame.new(0, length * 0.35, 0), Vector3.new(s, length * 0.7, s), color)
	glow(
		parent,
		cf * CFrame.new(0, length * 0.82, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4),
		Vector3.new(s * 0.7, s * 0.7, s * 0.7),
		color
	)
end

-- The look of a case: (body, panel, glow, hot).
function CaseBuilder.look(oreId: string?): (Color3, Color3, Color3, boolean)
	local id = oreId or ""
	local color, glowColor = BlasterData.skin(id)
	local hot = CaseBuilder.HotOres[id] == true
	local body, panel
	if hot then
		body = Color3.fromRGB(34, 28, 30):Lerp(color, 0.08)
		panel = Color3.fromRGB(48, 42, 44)
	else
		local h, s = color:ToHSV()
		body = Color3.fromHSV(h, math.max(s, 0.25) * 0.75 + 0.2, 0.26)
		panel = Color3.fromHSV(h, math.max(s, 0.25) * 0.7 + 0.15, 0.4)
	end
	-- very bright glows (gold, white ores) keep their colour instead of blooming white
	local luma = 0.299 * glowColor.R + 0.587 * glowColor.G + 0.114 * glowColor.B
	if luma > 0.7 then
		glowColor = glowColor:Lerp(color, 0.4)
	end
	return body, panel, glowColor, hot
end

-- Lava cracks (hot) or a galaxy (stars + an outline) on one face; face = its center frame (Z out), hw x hh half size.
local function pattern(parent: Instance, face: CFrame, hw: number, hh: number, hot: boolean, glowColor: Color3, seed: number, s: number)
	local r = seed
	local function rand(): number
		r = (r * 16807) % 2147483647
		return r / 2147483647
	end
	if hot then
		for _ = 1, 3 do
			local x, y = (rand() - 0.5) * hw * 1.4, (rand() - 0.5) * hh * 1.2
			local a = rand() * math.pi * 2
			for _ = 1, 3 do
				a += (rand() - 0.5) * 1.5
				local len = (0.35 + rand() * 0.3) * hh * 1.6
				local nx = math.clamp(x + math.cos(a) * len, -hw * 0.9, hw * 0.9)
				local ny = math.clamp(y + math.sin(a) * len, -hh * 0.85, hh * 0.85)
				local dx, dy = nx - x, ny - y
				local l = math.sqrt(dx * dx + dy * dy)
				if l > 0.05 then
					glow(
						parent,
						face * CFrame.new((x + nx) / 2, (y + ny) / 2, 0.02) * CFrame.Angles(0, 0, math.atan2(dy, dx)),
						Vector3.new(l + 0.08 * s, 0.08 * s, 0.05),
						glowColor
					)
				end
				x, y = nx, ny
			end
		end
	else
		local t = 0.06 * s
		for _, sy in { -1, 1 } do
			glow(parent, face * CFrame.new(0, sy * (hh - 0.12 * s), 0.02), Vector3.new(hw * 2 - 0.24 * s, t, 0.05), glowColor)
		end
		for _, sx in { -1, 1 } do
			glow(parent, face * CFrame.new(sx * (hw - 0.12 * s), 0, 0.02), Vector3.new(t, hh * 2 - 0.24 * s, 0.05), glowColor)
		end
		for _ = 1, 5 do
			local d = (0.08 + rand() * 0.08) * s
			glow(
				parent,
				face * CFrame.new((rand() - 0.5) * hw * 1.6, (rand() - 0.5) * hh * 1.4, 0.02) * CFrame.Angles(0, 0, math.pi / 4),
				Vector3.new(d, d, 0.05),
				glowColor:Lerp(Color3.new(1, 1, 1), 0.5)
			)
		end
	end
end

--[[
	Builds a case for blaster `level` in the look of `oreId` ("" = rusty),
	`size` x a 7 stud long case, at `cf` (its bottom center). Returns Case.
]]
function CaseBuilder.build(parent: Instance, cf: CFrame, level: number, oreId: string?, size: number?): Case
	local s = (size or 1)
	local L, W = 7 * s, 3.85 * s
	local hb, hl = 1.47 * s, 0.98 * s
	local body, panel, glowColor, hot = CaseBuilder.look(oreId)
	local STEEL = Color3.fromRGB(62, 66, 78)
	local DARK = Color3.fromRGB(26, 27, 32)
	local base = Instance.new("Model")
	base.Name = "Base"
	base.Parent = parent
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	lid.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the base: feet, a dark bottom band, the body, the ore band, the inside, the seam
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(base, at(sx * (W / 2 - 0.35 * s), 0.07 * s, sz * (L / 2 - 0.45 * s)), Vector3.new(0.6 * s, 0.14 * s, 0.7 * s), DARK)
		end
	end
	block(base, at(0, 0.24 * s, 0), Vector3.new(W, 0.2 * s, L), DARK)
	block(base, at(0, 0.34 * s + (hb - 0.34 * s) / 2, 0), Vector3.new(W - 0.1 * s, hb - 0.34 * s, L - 0.1 * s), body)
	local band = glow(base, at(0, hb * 0.5, 0), Vector3.new(W + 0.02, 0.12 * s, L + 0.02), glowColor:Lerp(body, 0.3))
	band.Name = "Band"
	local inside =
		glow(base, at(0, hb - 0.03 * s, 0), Vector3.new(W - 0.5 * s, 0.06 * s, L - 0.5 * s), glowColor:Lerp(Color3.new(1, 1, 1), 0.35))
	inside.Name = "Inside"
	local seam = glow(base, at(0, hb + 0.02 * s, 0), Vector3.new(W + 0.06 * s, 0.08 * s, L + 0.06 * s), glowColor)
	seam.Name = "Seam"
	-- the ore pattern on the front and the back
	for i, sx in { 1, -1 } do
		local face = at(sx * (W / 2 - 0.05 * s + 0.03), hb * 0.62, 0) * CFrame.Angles(0, sx * math.pi / 2, 0)
		pattern(base, face, L * 0.36, hb * 0.26, hot, glowColor, level * 97 + i * 13 + 7, s)
	end
	-- corner caps, straps, latches, end handles
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(
				base,
				at(sx * (W / 2 - 0.12 * s), (hb + 0.34 * s) / 2, sz * (L / 2 - 0.12 * s)),
				Vector3.new(0.42 * s, hb - 0.3 * s, 0.42 * s),
				STEEL,
				METAL
			)
		end
	end
	for _, sz in { -1, 1 } do
		block(base, at(0, (hb + 0.34 * s) / 2, sz * 2.3 * s), Vector3.new(W + 0.08 * s, hb - 0.3 * s, 0.36 * s), STEEL, METAL)
		glow(base, at(W / 2 + 0.06 * s, hb * 0.72, sz * 1.5 * s), Vector3.new(0.12 * s, 0.32 * s, 0.6 * s), glowColor)
		block(base, at(W / 2 + 0.05 * s, hb * 0.72, sz * 1.5 * s), Vector3.new(0.08 * s, 0.45 * s, 0.8 * s), DARK)
		block(base, at(0, hb * 0.66, sz * (L / 2 + 0.12 * s)), Vector3.new(1.4 * s, 0.22 * s, 0.22 * s), DARK, METAL)
		for _, sx in { -1, 1 } do
			block(base, at(sx * 0.6 * s, hb * 0.66, sz * (L / 2 + 0.06 * s)), Vector3.new(0.18 * s, 0.4 * s, 0.14 * s), DARK, METAL)
		end
	end
	-- the lid: body, raised panel, straps, corner caps, the emblem
	local y0 = hb + 0.06 * s
	block(lid, at(0, y0 + hl * 0.36, 0), Vector3.new(W, hl * 0.72, L), panel)
	block(lid, at(0, y0 + hl * 0.72 + 0.1 * s, 0), Vector3.new(W - 1.1 * s, 0.24 * s, L - 2.2 * s), body)
	for _, sz in { -1, 1 } do
		block(lid, at(0, y0 + hl * 0.4, sz * 2.3 * s), Vector3.new(W + 0.08 * s, hl * 0.8 + 0.06 * s, 0.36 * s), STEEL, METAL)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(
				lid,
				at(sx * (W / 2 - 0.12 * s), y0 + hl * 0.36, sz * (L / 2 - 0.12 * s)),
				Vector3.new(0.44 * s, hl * 0.72 + 0.04 * s, 0.44 * s),
				STEEL,
				METAL
			)
			if level >= 4 then
				glow(
					lid,
					at(sx * (W / 2 - 0.12 * s), y0 + hl * 0.74, sz * (L / 2 - 0.12 * s)),
					Vector3.new(0.46 * s, 0.06 * s, 0.46 * s),
					glowColor
				)
			end
		end
	end
	local top = y0 + hl * 0.72 + 0.22 * s
	local emblem = at(0, top + 0.02 * s, 0)
	for i = 0, 3 do
		local a = i * math.pi / 2
		glow(
			lid,
			emblem * CFrame.Angles(0, math.pi / 4 + a, 0) * CFrame.new(0.55 * s, 0, 0),
			Vector3.new(0.08 * s, 0.05 * s, 1.18 * s),
			glowColor
		)
	end
	block(lid, emblem * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.7 * s, 0.04 * s, 0.7 * s), body:Lerp(glowColor, 0.25), GLASS)
	glow(lid, emblem * CFrame.new(0, 0.02 * s, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.3 * s, 0.04 * s, 0.3 * s), glowColor)
	-- ore crystals on the emblem: more and bigger with the level
	if level >= 4 then
		local up = cf.UpVector
		local p = emblem.Position
		shard(lid, p, up, 0.3 * s, (0.7 + 0.1 * level) * s, glowColor)
		if level >= 7 then
			local side = cf.LookVector
			shard(lid, p + side * 0.3 * s, (up + side * 0.7).Unit, 0.22 * s, 0.6 * s, glowColor)
			shard(lid, p - side * 0.3 * s, (up - side * 0.7).Unit, 0.22 * s, 0.55 * s, glowColor)
		end
		if level >= 10 then
			local right = cf.RightVector
			shard(lid, p + right * 0.3 * s, (up + right * 0.7).Unit, 0.2 * s, 0.5 * s, glowColor)
			shard(lid, p - right * 0.3 * s, (up - right * 0.7).Unit, 0.2 * s, 0.45 * s, glowColor)
		end
	end
	return {
		Base = base,
		Lid = lid,
		Seam = seam,
		Inside = inside,
		HingeOffset = CFrame.new(-W / 2, y0, 0),
		Height = top + 0.05 * s,
		BaseHeight = hb,
		Glow = glowColor,
		Body = body,
	}
end

return CaseBuilder
