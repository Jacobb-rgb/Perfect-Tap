--[[
	Exports the world animations showreel (tools/lune/lib/world_motion_preview.luau):
	golems hopping / jumping on equip, the blaster hit flash, the ore popping
	out of a rock, the sell cash burst, frame by frame from the game's own code
	(Effects/WorldMotionLogic and the real builders).

	  lune run tools/lune/export_world_motion.luau [fps=30]
	  node tools/preview/render_world_anim.mjs            # -> build/preview/svet_animace.mp4 + svet_animace.jpg
	-> build/preview/world_motion.json
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")

local root = process.cwd
Loader.init(root)

local Preview = require("./lib/world_motion_preview")
local fps = tonumber(process.args[1]) or 30
local t0 = os.clock()
local data = Preview.build(Loader, { fps = fps })

fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/world_motion.json", serde.encode("json", data))
local dynamic = 0
for _, frame in data.frames do
	dynamic = math.max(dynamic, #frame.p)
end
print(
	string.format(
		"Exported world_motion: %d frames (%.1f s), %d scenes, %d groups, at most %d moving parts a frame (%.1f s)",
		#data.frames,
		data.duration,
		#data.scenes,
		#data.groups,
		dynamic,
		os.clock() - t0
	)
)
