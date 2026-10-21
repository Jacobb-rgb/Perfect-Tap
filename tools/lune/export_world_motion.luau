--[[
	Exports the world animations showreel (tools/lune/lib/world_motion_preview.luau):
	golems hopping / jumping on equip, the blaster hit flash, the ore popping
	out of a rock, the sell cash burst, frame by frame from the game's own code
	(Effects/WorldMotionLogic and the real builders).

	  lune run tools/lune/export_world_motion.luau [fps=30]
	  node tools/preview/render_world_anim.mjs            # -> build/preview/svet_animace.mp4 + svet_animace.jpg
	-> build/preview/world_motion.json

	The golem run reel (tools/lune/lib/golem_run_preview.luau: golems running after you):
	  lune run tools/lune/export_world_motion.luau 30 golem_run
	  node tools/preview/render_world_anim.mjs 1280 720 6000000 - golem_run golemove_beh
	-> build/preview/golem_run.json -> build/preview/golemove_beh.mp4 + golemove_beh.jpg
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")

local root = process.cwd
Loader.init(root)

local fps = tonumber(process.args[1]) or 30
local reel = process.args[2] or "world_motion"
local t0 = os.clock()
local data
if reel == "golem_run" then
	-- FOCUS=1..3: the camera close on one golem (checking its gait)
	data = require("./lib/golem_run_preview").build(Loader, { fps = fps, focus = tonumber(process.env.FOCUS or "") })
else
	reel = "world_motion"
	data = require("./lib/world_motion_preview").build(Loader, { fps = fps })
end

fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/" .. reel .. ".json", serde.encode("json", data))
if data.waveAt then
	print(string.format("the Pebble Golem waves at %.2f s", data.waveAt))
end
local dynamic = 0
for _, frame in data.frames do
	dynamic = math.max(dynamic, #frame.p)
end
print(
	string.format(
		"Exported %s: %d frames (%.1f s), %d scenes, %d groups, at most %d moving parts a frame (%.1f s)",
		reel,
		#data.frames,
		data.duration,
		#data.scenes,
		#data.groups,
		dynamic,
		os.clock() - t0
	)
)
