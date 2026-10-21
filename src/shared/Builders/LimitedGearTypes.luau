--[[
	The types the limited edition costumes share (GolemGearLimited and every
	Builders/LimitedGear/<Set>.luau; a module of its own so the set modules
	need not require GolemGearLimited, which requires them).
]]

local GolemConfig = require(script.Parent.Parent.Config.GolemConfig)

-- (GolemBuilder's Ctx: the golem being built)
export type Ctx = {
	Model: Model,
	At: (x: number, y: number, z: number) -> CFrame,
	V: (x: number, y: number, z: number) -> Vector3,
	Look: GolemConfig.Golem,
	S: number, -- the scale (studs per unit)
	Glow: Color3, -- the glow for Neon parts
	Top: number, -- the top of the head (unscaled units)
	Room: () -> number, -- parts the gear may still add (the budget minus the aura)
}

-- GolemBuilder's part helpers.
export type Kit = {
	part: (
		parent: Instance,
		name: string,
		cf: CFrame,
		size: Vector3,
		color: Color3,
		material: Enum.Material?,
		shape: Enum.PartType?
	) -> Part,
	upright: (
		parent: Instance,
		name: string,
		cf: CFrame,
		height: number,
		diameter: number,
		color: Color3,
		material: Enum.Material?
	) -> Part,
	facing: (parent: Instance, name: string, cf: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?) -> Part,
	wedge: (parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?) -> BasePart,
	darker: (c: Color3, amount: number) -> Color3,
	lighter: (c: Color3, amount: number) -> Color3,
}

-- The shard being built (see the header).
export type Shard = {
	Top: Model,
	Bottom: Model,
	Center: CFrame,
	Color: Color3,
	Glow: Color3,
	Room: () -> number,
}

export type Tools = {
	P: (c: Ctx, x: number, y: number, z: number) -> Vector3,
	seg: (
		parent: Instance,
		name: string,
		a: Vector3,
		b: Vector3,
		w: number,
		d: number,
		color: Color3,
		material: Enum.Material?
	) -> Part,
	tri: (
		parent: Instance,
		name: string,
		a: Vector3,
		b: Vector3,
		p: Vector3,
		thick: number,
		color: Color3,
		material: Enum.Material?,
		room: number?
	) -> number,
	ellipsoid: (parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?) -> Part,
	redress: (c: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material) -> (),
	recolor: (c: Ctx, name: string, color: Color3, material: Enum.Material) -> (),
	embers: (p: BasePart, color: Color3, rate: number, size: number?) -> ParticleEmitter,
	light: (p: BasePart, color: Color3, range: number, brightness: number) -> PointLight,
}

export type SetModule = {
	Faces: { [string]: string },
	accessories: (kit: Kit, tools: Tools) -> { [string]: (Ctx) -> number },
	shard: ((kit: Kit, tools: Tools, s: Shard) -> ())?,
}

return {}
