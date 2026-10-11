-- Every .luau file in src/ must compile with the real Luau compiler
-- (catches syntax errors like "ambiguous syntax" that the type checker misses).
return function(T, Loader)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")

	local function walk(dir: string, out: { string })
		for _, entry in fs.readDir(dir) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				walk(path, out)
			elseif entry:match("%.luau$") then
				table.insert(out, path)
			end
		end
	end

	local files = {}
	walk(Loader.root .. "/src", files)
	table.sort(files)
	T.test("compile: all " .. #files .. " source files", function()
		for _, path in files do
			local ok, err = pcall(luau.compile, fs.readFile(path))
			T.truthy(ok, path .. ": " .. tostring(err))
		end
	end)
end
