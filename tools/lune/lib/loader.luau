--[[
	Runs Terra Forge ModuleScripts outside Roblox (in Lune) for tests,
	map baking and preview renders.

	It builds a virtual instance tree from default.project.json using Rojo's
	file rules, so game code can keep using `require(script.Parent.X)` and
	`game:GetService("ReplicatedStorage"):WaitForChild("Shared")`.
	Real Roblox datatypes (Instance, Vector3, CFrame, ...) come from
	@lune/roblox, so builders create real instances that can be saved into
	a place file.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")
local task = require("@lune/task")

local Loader = {}

local patched = false

-- Lune quirk: implementMethod/implementProperty must run from the main script
-- (not while a module is being required), so this runs inside Loader.init().
local function applyPatches()
	if patched then
		return
	end
	patched = true
	-- Methods that Lune does not implement but game builders may use.
	roblox.implementMethod("Model", "GetPivot", function(self)
		local primary = self.PrimaryPart
		if primary then
			return primary.CFrame
		end
		local pivot = self:GetAttribute("__Pivot")
		return pivot or roblox.CFrame.new()
	end)
	roblox.implementMethod("BasePart", "GetPivot", function(self)
		return self.CFrame
	end)
	roblox.implementMethod("Model", "PivotTo", function(self, target)
		local current = self:GetPivot()
		local delta = target * current:Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = delta * d.CFrame
			end
		end
		if not self.PrimaryPart then
			self:SetAttribute("__Pivot", target)
		end
	end)
	roblox.implementMethod("BasePart", "PivotTo", function(self, target)
		self.CFrame = target
	end)

	-- Fake RBXScriptSignal so UI builders can :Connect() without failing.
	local function fakeSignal()
		return {
			Connect = function()
				return { Disconnect = function() end, Connected = true }
			end,
			Once = function()
				return { Disconnect = function() end, Connected = true }
			end,
			Wait = function() end,
		}
	end
	for _, pair in
		{
			{ "GuiButton", "Activated" },
			{ "GuiButton", "MouseButton1Click" },
			{ "GuiButton", "MouseButton1Down" },
			{ "GuiButton", "MouseButton1Up" },
			{ "GuiObject", "MouseEnter" },
			{ "GuiObject", "MouseLeave" },
			{ "GuiObject", "InputBegan" },
			{ "GuiObject", "InputChanged" },
			{ "GuiObject", "InputEnded" },
			{ "TextBox", "FocusLost" },
			{ "TextBox", "Focused" },
			{ "BasePart", "Touched" },
			{ "ProximityPrompt", "Triggered" },
			{ "ProximityPrompt", "PromptShown" },
			{ "ProximityPrompt", "PromptHidden" },
			{ "ProximityPrompt", "PromptButtonHoldBegan" },
			{ "ProximityPrompt", "PromptButtonHoldEnded" },
			{ "Instance", "Changed" },
			{ "Instance", "AncestryChanged" },
			{ "Instance", "Destroying" },
			{ "Instance", "ChildAdded" },
			{ "Instance", "ChildRemoved" },
			{ "Instance", "DescendantAdded" },
		}
	do
		pcall(roblox.implementProperty, pair[1], pair[2], function()
			return fakeSignal()
		end)
	end
	roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
		return fakeSignal()
	end)
	roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
		return fakeSignal()
	end)
end

---------------------------------------------------------------------------
-- Virtual tree
---------------------------------------------------------------------------

type VNode = {
	Name: string,
	ClassName: string,
	Parent: VNode?,
	Children: { [string]: VNode },
	ChildList: { VNode },
	Source: string?, -- file path for scripts
}

local NodeMeta = {}

local nodeMethods = {}

function nodeMethods.FindFirstChild(self, name: string)
	return rawget(self, "Children")[name]
end

function nodeMethods.WaitForChild(self, name: string)
	local child = rawget(self, "Children")[name]
	if not child then
		error(`[loader] {nodeMethods.GetFullName(self)} has no child "{name}"`, 2)
	end
	return child
end

function nodeMethods.GetChildren(self)
	return table.clone(rawget(self, "ChildList"))
end

function nodeMethods.GetDescendants(self)
	local out = {}
	local function walk(n)
		for _, c in rawget(n, "ChildList") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function nodeMethods.IsA(self, className: string)
	local cn = rawget(self, "ClassName")
	if cn == className or className == "Instance" then
		return true
	end
	if className == "LuaSourceContainer" or className == "BaseScript" then
		return cn == "ModuleScript" or cn == "Script" or cn == "LocalScript"
	end
	return false
end

function nodeMethods.GetFullName(self)
	local parts = {}
	local n = self
	while n do
		table.insert(parts, 1, rawget(n, "Name"))
		n = rawget(n, "Parent")
	end
	return table.concat(parts, ".")
end

function nodeMethods.GetService(self, name: string)
	local child = rawget(self, "Children")[name]
	if child then
		return child
	end
	-- services not mapped in the project get an empty stub
	return Loader._newNode(name, name, self)
end

NodeMeta.__index = function(self, key)
	local method = nodeMethods[key]
	if method then
		return method
	end
	local child = rawget(self, "Children")[key]
	if child then
		return child
	end
	error(`[loader] {key} is not a valid member of {nodeMethods.GetFullName(self)}`, 2)
end
NodeMeta.__tostring = function(self)
	return rawget(self, "Name")
end

function Loader._newNode(name: string, className: string, parent: VNode?): VNode
	local node = setmetatable({
		Name = name,
		ClassName = className,
		Parent = parent,
		Children = {},
		ChildList = {},
		Source = nil,
	}, NodeMeta) :: any
	if parent then
		rawget(parent, "Children")[name] = node
		table.insert(rawget(parent, "ChildList"), node)
	end
	return node
end

local function isFile(path: string): boolean
	return fs.isFile(path)
end

local SCRIPT_RULES = {
	{ ".server.luau", "Script" },
	{ ".client.luau", "LocalScript" },
	{ ".server.lua", "Script" },
	{ ".client.lua", "LocalScript" },
	{ ".luau", "ModuleScript" },
	{ ".lua", "ModuleScript" },
}

local function scriptKind(fileName: string): (string?, string?)
	for _, rule in SCRIPT_RULES do
		local suffix = rule[1]
		if #fileName > #suffix and fileName:sub(-#suffix) == suffix then
			return fileName:sub(1, #fileName - #suffix), rule[2]
		end
	end
	return nil, nil
end

local function mountDirectory(dirPath: string, node: VNode)
	local entries = fs.readDir(dirPath)
	table.sort(entries)
	for _, entry in entries do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			-- folder or init-script folder
			local className = "Folder"
			local initSource = nil
			for _, initName in { "init.server.luau", "init.client.luau", "init.luau", "init.server.lua", "init.client.lua", "init.lua" } do
				if isFile(full .. "/" .. initName) then
					local _, kind = scriptKind(initName)
					className = kind :: string
					initSource = full .. "/" .. initName
					break
				end
			end
			local child = Loader._newNode(entry, className, node)
			rawset(child, "Source", initSource)
			mountDirectory(full, child)
		else
			local name, kind = scriptKind(entry)
			if name and kind and name ~= "init" and not name:find("%.spec$") then
				local child = Loader._newNode(name, kind, node)
				rawset(child, "Source", full)
			end
		end
	end
end

local function mountProjectNode(projectNode: any, name: string, parent: VNode?, root: string): VNode
	local className = projectNode["$className"] or "Folder"
	local node = Loader._newNode(name, className, parent)
	local path = projectNode["$path"]
	if path then
		local full = root .. "/" .. path
		if fs.isDir(full) then
			for _, initName in { "init.server.luau", "init.client.luau", "init.luau" } do
				if isFile(full .. "/" .. initName) then
					local _, kind = scriptKind(initName)
					rawset(node, "ClassName", kind)
					rawset(node, "Source", full .. "/" .. initName)
					break
				end
			end
			mountDirectory(full, node)
		elseif isFile(full) then
			local _, kind = scriptKind(full)
			rawset(node, "ClassName", kind or "ModuleScript")
			rawset(node, "Source", full)
		end
	end
	for key, value in projectNode do
		if type(key) == "string" and key:sub(1, 1) ~= "$" and type(value) == "table" then
			mountProjectNode(value, key, node, root)
		end
	end
	return node
end

---------------------------------------------------------------------------
-- Module loading
---------------------------------------------------------------------------

local moduleCache: { [any]: any } = {}
local loading: { [any]: boolean } = {}

Loader.root = "."
Loader.game = nil :: any

-- Lune 0.8.9 bug: CFrame.lookAt negates the Z of the look direction.
-- Rebuild it the way Roblox does (right = look x up, up = right x look).
local function lookAt(at, target, upHint)
	local Vector3 = roblox.Vector3
	local up = upHint or Vector3.new(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, if look.Y > 0 then 1 else -1))
	end
	right = right.Unit
	local newUp = right:Cross(look).Unit
	return roblox.CFrame.fromMatrix(at, right, newUp, -look)
end
local CFrameShim = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })
Loader.CFrame = CFrameShim

local function baseEnvironment()
	return {
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrameShim,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Rect = roblox.Rect,
		Enum = roblox.Enum,
		Font = roblox.Font,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray,
		Faces = roblox.Faces,
		Axes = roblox.Axes,
		-- (no tweens run in Lune: a TweenInfo is its numbers, for the specs that drive a controller on fakes)
		TweenInfo = {
			new = function(time: number?, style: any?, direction: any?, repeats: number?, reverses: boolean?, delay: number?)
				return {
					Time = time or 1,
					EasingStyle = style,
					EasingDirection = direction,
					RepeatCount = repeats or 0,
					Reverses = reverses == true,
					DelayTime = delay or 0,
				}
			end,
		},
		task = task,
		tick = os.clock,
		time = os.clock,
		warn = function(...)
			print("[warn]", ...)
		end,
	}
end

function Loader.require(node: any): any
	if type(node) ~= "table" or getmetatable(node) ~= NodeMeta then
		error("[loader] require() expects a virtual ModuleScript, got " .. tostring(node), 2)
	end
	local cached = moduleCache[node]
	if cached ~= nil then
		return cached
	end
	local source = rawget(node, "Source")
	if not source or rawget(node, "ClassName") ~= "ModuleScript" then
		error("[loader] not a ModuleScript: " .. nodeMethods.GetFullName(node), 2)
	end
	if loading[node] then
		error("[loader] circular require: " .. nodeMethods.GetFullName(node), 2)
	end
	loading[node] = true
	local env = baseEnvironment()
	env.script = node
	env.game = Loader.game
	env.workspace = Loader.game and nodeMethods.GetService(Loader.game, "Workspace")
	env.require = Loader.require
	local code = fs.readFile(source)
	local bytecode = luau.compile(code)
	local fn = luau.load(bytecode, { debugName = nodeMethods.GetFullName(node), environment = env })
	local result = fn()
	loading[node] = nil
	moduleCache[node] = if result == nil then false else result
	return result
end

-- Load the project. `root` is the repository root.
function Loader.init(root: string)
	applyPatches()
	Loader.root = root
	local project = serde.decode("json", fs.readFile(root .. "/default.project.json"))
	Loader.game = mountProjectNode(project.tree, "game", nil, root)
	return Loader
end

-- Resolve "ReplicatedStorage.Shared.Config.OreData" to a virtual node.
function Loader.find(path: string): any
	local node = Loader.game
	for segment in path:gmatch("[^%.]+") do
		node = rawget(node, "Children")[segment]
		if not node then
			error("[loader] path not found: " .. path, 2)
		end
	end
	return node
end

function Loader.requirePath(path: string): any
	return Loader.require(Loader.find(path))
end

-- Every ModuleScript under a path (used by tests to at least compile+run all of them).
function Loader.listModules(path: string): { any }
	local out = {}
	for _, d in nodeMethods.GetDescendants(Loader.find(path)) do
		if rawget(d, "ClassName") == "ModuleScript" then
			table.insert(out, d)
		end
	end
	return out
end

function Loader.fullName(node: any): string
	return nodeMethods.GetFullName(node)
end

Loader.roblox = roblox

return Loader
