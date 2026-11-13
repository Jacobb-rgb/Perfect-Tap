--!strict
--[[
	MeshKit: the owner's own 3D models (made with Meshy, 2026-11-13), uploaded under the owner's
	account (docs/plans/MESHY_MODELS_PLAN.md).

	The templates are MeshParts in ReplicatedStorage.Shared.Assets.MeshAssets, written by
	tools/lune/import_meshes.luau from the owner's Studio import (Config/MeshUpload says whether it
	exists). Scripts cannot set a MeshPart's MeshId or a SurfaceAppearance's maps at runtime, so
	every builder clones a template. For an asset without an upload (or before the upload),
	MeshKit.template returns nil and the builder keeps its part-built look.

	  MeshKit.template(name)                  the template MeshPart, or nil
	  MeshKit.has(name)                       boolean
	  MeshKit.box(name)                       the mesh's own size (its proportions), or nil
	  MeshKit.part(name, size, cf, opts?)     a clone stretched to `size`, its box centred at cf
	  MeshKit.fit(name, box, cf, opts?)       a clone scaled evenly to fit inside `box`
	  MeshKit.scaled(name, scale, cf, opts?)  a clone at `scale` times its own size
	  MeshKit.ground(cf, size)                cf of a box of `size` standing on `cf` (its bottom centre)
	  MeshKit.frame(p)                        the frame a clone's model stands in (cf of part())
	  MeshKit.place(p, cf)                    moves a clone so its model stands in cf
	  MeshKit.waitReady(timeout)              clients: wait for the templates to replicate (init)
	opts: Name, Anchored (true), CanCollide, CanQuery, CanTouch (false each), CastShadow (true),
	Massless, Transparency. Every clone keeps the attribute Asset = name (previews load the .glb).

	The import's turn: Studio's 3D Importer turns every model half round about Y (glTF's +Z front
	becomes Roblox's -Z front; seen on 2026-11-13 in how it laid out a floor's tiles), so an
	uploaded template carries the attribute ImportYaw (degrees, 180; tools/lune/import_meshes.luau)
	and every clone turns back by it: its PivotOffset holds the turn, so the clone's pivot is the
	processed model's frame. PivotTo / GetPivot (and a Model whose PrimaryPart it is) keep it; code
	that moves a clone by its CFrame uses MeshKit.place / MeshKit.frame instead.
]]

local MeshCatalog = require(script.Parent.Parent.Config.MeshCatalog)
local MeshUpload = require(script.Parent.Parent.Config.MeshUpload)

local MeshKit = {}

export type Opts = {
	Name: string?,
	Anchored: boolean?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Massless: boolean?,
	Transparency: number?,
}

local Shared: Instance = script.Parent.Parent
local index: { [string]: MeshPart }? = nil

local function load(): { [string]: MeshPart }
	if index then
		return index
	end
	local found: { [string]: MeshPart } = {}
	local holder = Shared:FindFirstChild("Assets")
	local folder = if holder then holder:FindFirstChild("MeshAssets") else nil
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("MeshPart") then
				found[child.Name] = child
			end
		end
		index = found
	end
	return found
end

-- Forget the looked-up templates (specs that mount stand-in templates call this).
function MeshKit.reset()
	index = nil
end

-- Clients call this once before building: the uploaded templates replicate with ReplicatedStorage.
function MeshKit.waitReady(timeout: number?)
	if not MeshUpload.Uploaded or index then
		return
	end
	local holder = Shared:WaitForChild("Assets", timeout or 10)
	if holder then
		holder:WaitForChild("MeshAssets", timeout or 10)
	end
	load()
end

function MeshKit.template(name: string): MeshPart?
	return load()[name]
end

function MeshKit.has(name: string): boolean
	return MeshKit.template(name) ~= nil
end

-- The mesh's own size: the template's, else the processed file's (MeshCatalog).
function MeshKit.box(name: string): Vector3?
	local t = load()[name]
	if t then
		return t.Size
	end
	local entry = MeshCatalog.Assets[name]
	return if entry then entry.Box else nil
end

local function apply(p: MeshPart, opts: Opts?)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	if opts then
		if opts.Name then
			p.Name = opts.Name
		end
		if opts.Anchored ~= nil then
			p.Anchored = opts.Anchored
		end
		if opts.CanCollide ~= nil then
			p.CanCollide = opts.CanCollide
		end
		if opts.CanQuery ~= nil then
			p.CanQuery = opts.CanQuery
		end
		if opts.CanTouch ~= nil then
			p.CanTouch = opts.CanTouch
		end
		if opts.CastShadow ~= nil then
			p.CastShadow = opts.CastShadow
		end
		if opts.Massless ~= nil then
			p.Massless = opts.Massless
		end
		if opts.Transparency ~= nil then
			p.Transparency = opts.Transparency
		end
	end
end

-- The frame the clone's model stands in: its CFrame with the import's turn (its pivot).
function MeshKit.frame(p: BasePart): CFrame
	return p.CFrame * p.PivotOffset
end

-- Moves a clone so its model stands in `cf` (keeps the import's turn).
function MeshKit.place(p: BasePart, cf: CFrame)
	p.CFrame = cf * p.PivotOffset:Inverse()
end

function MeshKit.part(name: string, size: Vector3, cf: CFrame, opts: Opts?): MeshPart?
	local t = load()[name]
	if not t then
		return nil
	end
	local p = t:Clone()
	apply(p, opts)
	p.Size = size
	local yaw = t:GetAttribute("ImportYaw")
	p.PivotOffset = if type(yaw) == "number" and yaw ~= 0 then CFrame.Angles(0, math.rad(yaw), 0) else CFrame.identity
	MeshKit.place(p, cf)
	p:SetAttribute("Asset", name)
	return p
end

function MeshKit.fit(name: string, box: Vector3, cf: CFrame, opts: Opts?): MeshPart?
	local own = MeshKit.box(name)
	if not own then
		return nil
	end
	local s = math.min(box.X / own.X, box.Y / own.Y, box.Z / own.Z)
	return MeshKit.part(name, own * s, cf, opts)
end

function MeshKit.scaled(name: string, scale: number, cf: CFrame, opts: Opts?): MeshPart?
	local own = MeshKit.box(name)
	if not own then
		return nil
	end
	return MeshKit.part(name, own * scale, cf, opts)
end

-- The CFrame of a box of `size` whose bottom centre stands on `cf`.
function MeshKit.ground(cf: CFrame, size: Vector3): CFrame
	return cf * CFrame.new(0, size.Y / 2, 0)
end

return MeshKit
