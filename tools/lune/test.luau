--[[
	Terra Forge unit test runner (Lune).
	  lune run tools/lune/test.luau [filter]

	1. Loads every ModuleScript in ReplicatedStorage.Shared and the server
	   World builders, so syntax/runtime errors at load time are caught.
	   (Modules whose first line is "-- @lune-skip" need real Roblox services.)
	2. Runs every tests/*.spec.luau file. A spec returns function(T, Loader).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("./lib/loader")

local root = process.cwd
Loader.init(root)
local filter = process.args[1]

local passed, failed = 0, 0
local failures = {}

local T = {}

local function fail(message: string)
	error(message, 3)
end

function T.eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		fail(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`)
	end
end

function T.near(actual: number, expected: number, epsilon: number?, label: string?)
	if math.abs(actual - expected) > (epsilon or 1e-6) then
		fail(`{label or "value"}: expected ~{expected}, got {actual}`)
	end
end

function T.truthy(value: any, label: string?)
	if not value then
		fail(`{label or "value"} should be truthy, got {tostring(value)}`)
	end
end

function T.falsy(value: any, label: string?)
	if value then
		fail(`{label or "value"} should be falsy, got {tostring(value)}`)
	end
end

function T.lt(a: number, b: number, label: string?)
	if not (a < b) then
		fail(`{label or "value"}: expected {a} < {b}`)
	end
end

function T.le(a: number, b: number, label: string?)
	if not (a <= b) then
		fail(`{label or "value"}: expected {a} <= {b}`)
	end
end

function T.test(name: string, fn: () -> ())
	if filter and not name:lower():find(filter:lower(), 1, true) then
		return
	end
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, `  FAIL {name}\n      {err}`)
	end
end

-- 1) load all shared modules
local function loadAll(path: string)
	for _, node in Loader.listModules(path) do
		local source = rawget(node, "Source")
		local firstLine = (fs.readFile(source):match("^[^\n]*") or "")
		if not firstLine:find("@lune%-skip") then
			T.test("load " .. Loader.fullName(node), function()
				Loader.require(node)
			end)
		end
	end
end
loadAll("ReplicatedStorage.Shared")
T.test("load WorldBuilder", function()
	Loader.requirePath("ServerScriptService.Server.World.WorldBuilder")
end)

-- 2) spec files
local testDir = root .. "/tests"
if fs.isDir(testDir) then
	local files = fs.readDir(testDir)
	table.sort(files)
	for _, file in files do
		if file:match("%.spec%.luau$") then
			local chunk = require(("../../tests/" .. file:gsub("%.luau$", "")) :: any)
			chunk(T, Loader)
		end
	end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	print(table.concat(failures, "\n"))
	process.exit(1)
end
