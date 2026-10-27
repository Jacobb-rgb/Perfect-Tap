--[[
	Exports the weather reel (tools/lune/lib/weather_preview.luau): rain,
	storm, hail, snow, wind, heatwave and the rainbow over the lobby
	plaza, frame by frame from the game's own weather code.

	  lune run tools/lune/export_scene.luau world        # once: the lobby the reel plays over
	  lune run tools/lune/export_weather.luau [fps=24]
	  node tools/preview/render_weather.mjs               # -> build/preview/pocasi.mp4, pocasi.jpg, weather stills
	-> build/preview/weather_reel.json

	The close snow still (a player's camera on the plaza: the clear view round the lens):
	  lune run tools/lune/export_weather.luau 24 close
	  node tools/preview/render_weather.mjs close         # -> build/preview/shots/weather_snih_zblizka.jpg
	-> build/preview/weather_close.json
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./lib/loader")

local root = process.cwd
Loader.init(root)

local fps = tonumber(process.args[1]) or 24
local close = process.args[2] == "close"
local data = require("./lib/weather_preview").build(Loader, { fps = fps, close = close })
local name = if close then "weather_close" else "weather_reel"

fs.writeDir(root .. "/build/preview")
fs.writeFile(root .. "/build/preview/" .. name .. ".json", serde.encode("json", data))
print(string.format("Exported %s: %d frames (%.1f s), %d segments", name, #data.frames, data.duration, #data.segments))
