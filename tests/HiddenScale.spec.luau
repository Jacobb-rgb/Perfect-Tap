-- A UIScale put away at 0 reads back as 1e-07 in Roblox (the owner's Studio trace 2026-11-07:
-- the HUD stayed invisible after every egg opening): "hidden" is HiddenScale.is, never "== 0".
return function(T, Loader)
	local fs = require("@lune/fs")

	T.test("HiddenScale: 0 and Roblox's 1e-07 are hidden, a real scale isn't", function()
		local HiddenScale = Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Util.HiddenScale")
		T.truthy(HiddenScale.is(0), "0")
		T.truthy(HiddenScale.is(1.0000000116860974e-07), "what Roblox reads back")
		T.falsy(HiddenScale.is(0.62), "the HUD's smallest scale (HudController.uiScale)")
		T.falsy(HiddenScale.is(1), "1")
		T.falsy(HiddenScale.is(-1), "no scale at all")
	end)

	T.test("HiddenScale: no client code tests a UIScale against exactly 0 any more", function()
		local found: { string } = {}
		local function walk(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					walk(path)
				elseif entry:match("%.luau$") then
					for number, line in fs.readFile(path):split("\n") do
						if line:match("[Ss]cale%.Scale%s*[=~]=%s*0%f[^%d%.]") then
							table.insert(found, `{path}:{number}`)
						end
					end
				end
			end
		end
		walk("src/client")
		T.eq(table.concat(found, " "), "", "use HiddenScale.is")
		local boost = fs.readFile("src/client/Controllers/BoostController.luau")
		T.truthy(boost:find("HiddenScale.is(guiScale.Scale)", 1, true), "the boost chips wait while the HUD is away")
	end)
end
