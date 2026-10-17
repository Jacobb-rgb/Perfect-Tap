--[[
	Exports the pieces of the "new blaster" crate-opening animation for the
	video renderer (tools/preview/anim.html, tools/preview/render_anim.mjs):
	the Kenney weapon case (base and lid apart, so the lid can swing open) and
	the revealed blaster, each as its own part list.

	  lune run tools/lune/export_anim.luau [level] [oreId]   (default: 10 Heartstone)
	-> build/preview/anim_crate.json
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")

local root = process.cwd
Loader.init(root)

local Concepts = require("./lib/blaster_concepts")
local Kenney = require("./lib/blaster_kenney")
Concepts.init(Loader)

local CF = Loader.CFrame
local C3 = roblox.Color3

local level = tonumber(process.args[1]) or 10
local oreId = process.args[2] or "Heartstone"

local OreData = Loader.requirePath("ReplicatedStorage.Shared.Config.OreData")
local BlasterData = Loader.requirePath("ReplicatedStorage.Shared.Config.BlasterData")
local BlasterBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.BlasterBuilder")
local look = BlasterBuilder.look(level, oreId)
local ore = OreData.ById[oreId]

local CRATE_SCALE = 7 -- Kenney meters -> studs

-- The case in the rarity colors: a deep body, dark steel lid and trims.
local hue, sat = look.Body:ToHSV()
local CRATE = {
	body = C3.fromHSV(hue, math.max(sat, 0.3) * 0.7 + 0.2, 0.32),
	light = C3.fromRGB(46, 48, 58),
	mid = C3.fromRGB(66, 70, 82),
	dark = C3.fromRGB(26, 27, 32),
}

local function collect(model: any)
	local scene = Export.collect(model)
	return { parts = scene.parts }
end

local function crate(part: string)
	local model = roblox.Instance.new("Model")
	Kenney.shape(Loader, model, "crate-medium:" .. part, CRATE_SCALE, function(region)
		return CRATE[region.role]
	end)
	return model
end

local base = crate("base")
local lid = crate("lid")
local gun, anchors = Kenney.gun(Loader, level, oreId)
-- the gun centered on its bounding box (it spins around its middle)
local holder = roblox.Instance.new("Model")
Concepts.present(gun, CF.identity, 1.25, holder)

local shapes = require("./lib/kenney_blaster_shapes") :: any
local b = shapes["crate-medium:base"].bounds
local lb = shapes["crate-medium:lid"].bounds

local out = {
	base = collect(base),
	lid = collect(lid),
	gun = collect(holder),
	meta = {
		crate = {
			length = (b[2] - b[1]) * CRATE_SCALE,
			width = (b[6] - b[5]) * CRATE_SCALE,
			baseTop = b[4] * CRATE_SCALE,
			top = lb[4] * CRATE_SCALE,
			hingeX = lb[5] * CRATE_SCALE, -- the lid swings up around its -X edge
			hingeY = lb[3] * CRATE_SCALE,
		},
		glow = look.Glow:ToHex(),
		body = look.Body:ToHex(),
		level = level,
		rarity = if ore then string.upper(ore.Rarity) else "COMMON",
		name = string.upper(BlasterData.displayName(level, oreId)),
		magma = (require("./lib/blaster_glow") :: any).Magma[oreId] == true,
		muzzle = { anchors.muzzle.X, anchors.muzzle.Y, anchors.muzzle.Z },
	},
}

fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/anim_crate.json", serde.encode("json", out))
print(
	string.format("Exported anim_crate: base %d, lid %d, gun %d parts (%s)", #out.base.parts, #out.lid.parts, #out.gun.parts, out.meta.name)
)
