--[[
	Video frames of the six SECRET ores alive (owner 2026-10-29: "udělej to
	ještě mnohem mnohem víc cool, jak ty věci ..."): the vault of
	tools/lune/lib/secret_showcase.luau, every ore on its pedestal turning and
	bobbing like on a podium (PodiumController: 0.6 rad/s, 0.12 studs) with
	its moving parts posed by SecretOreFx (orbiting shards, the eye looking
	round and blinking, the clam breathing, the lightning flickering, the
	heart beating, the star's whirling disc) and its sparkles drawn as dots.
	The camera glides along the row, a moment at every ore, then pulls back.

	  lune run tools/lune/export_secret_spin.luau [fps=20] [tag=secretspin]
	then: node tools/preview/render_reel.mjs <tag>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Loader = require("./lib/loader")
local Export = require("./lib/export")
local Showcase = require("./lib/secret_showcase")

local root = process.cwd
Loader.init(root)
local fps = tonumber(process.args[1]) or 20
local tag = process.args[2] or "secretspin"
local CF = Loader.CFrame
local V3 = roblox.Vector3
local NEON = roblox.Enum.Material.Neon

local LightingConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.LightingConfig")
local SecretOreConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.SecretOreConfig")
local ItemBuilder = Loader.requirePath("ReplicatedStorage.Shared.Builders.ItemBuilder")
local SecretOreFx = Loader.requirePath("ReplicatedStorage.Shared.Builders.SecretOreFx")
local Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
Showcase.build(Loader, workspace, false, 0, true)
local function presetToJson(preset)
	local o = {}
	for group, values in preset do
		o[group] = {}
		for key, value in values do
			o[group][key] = if typeof(value) == "Color3" then { value.R, value.G, value.B } else value
		end
	end
	return o
end
fs.writeDir(root .. "/build/preview/" .. tag)
local scene = Export.collect(workspace)
local presets = {}
for name, preset in LightingConfig.Presets do
	presets[name] = presetToJson(preset)
end
scene.presets = presets
fs.writeFile(root .. "/build/preview/" .. tag .. "_base.json", serde.encode("json", scene))

local count = #SecretOreConfig.List
local EACH = 1.35 -- seconds at an ore
local WIDE = count * EACH
local total = WIDE + 1.8
local SPIN, BOB = 0.6, 0.12

-- the camera: from ore to ore along the row, then back to see them all
local function camAt(t: number): (any, any)
	local wideFrom, wideTo = V3.new(0, 7.2, 19.5), V3.new(0, 2.9, 0)
	local function near(k: number): (any, any)
		local cf = Showcase.itemFrame(Loader, k, count)
		local p = cf.Position + V3.new(0, 1.15, 0)
		return p + V3.new(-0.6, 1.1, 6.4), p
	end
	if t >= WIDE then
		local u = math.min((t - WIDE) / 1.0, 1)
		u = u * u * (3 - 2 * u)
		local fromA, toA = near(count)
		return fromA:Lerp(wideFrom, u), toA:Lerp(wideTo, u)
	end
	local x = t / EACH
	local k = math.floor(x) + 1
	local u = x - (k - 1)
	-- hold on the ore most of the time, glide to the next in the last 30 %
	local g = math.clamp((u - 0.7) / 0.3, 0, 1)
	g = g * g * (3 - 2 * g)
	local fromA, toA = near(k)
	if k < count and g > 0 then
		local fromB, toB = near(k + 1)
		return fromA:Lerp(fromB, g), toA:Lerp(toB, g)
	end
	return fromA, toA
end

local frames = math.floor(total * fps)
local shots = {}
for i = 0, frames - 1 do
	local t = i / fps
	local extra = roblox.Instance.new("Model")
	for k, secret in SecretOreConfig.List do
		local item = ItemBuilder.display(
			{ K = "Clean", O = secret.Ore, G = SecretOreConfig.Grade },
			Showcase.itemFrame(Loader, k, count),
			secret.Ore
		)
		local center = item:GetAttribute("Center")
		local base = CF.new(center)
		local rig = SecretOreFx.rig(item, base)
		-- like a podium: turn and bob the whole display round its middle
		local phase = k * 1.1
		local turned = base * CF.new(0, math.sin(t * 1.4 + phase) * BOB, 0) * CF.Angles(0, t * SPIN + phase, 0)
		local offsets = {}
		for _, d in item:GetDescendants() do
			if d:IsA("BasePart") then
				offsets[d] = base:ToObjectSpace(d.CFrame)
			end
		end
		for part, offset in offsets do
			part.CFrame = turned * offset
		end
		SecretOreFx.pose(rig, turned, t + k)
		-- (the preview draws an emitter as random dots that jump every frame: its own dots below instead)
		for _, d in item:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Parent = nil
			end
		end
		item.Parent = extra
		-- its rising rainbow sparkles (the emitter), as dots
		for j = 1, 10 do
			local u = ((t * 0.55 + j * 0.137 + k * 0.3) % 1)
			local a = j * 2.4 + k
			local r = 0.7 + 0.5 * ((j * 7) % 5) / 5
			local at = center + V3.new(math.cos(a) * r, -0.6 + 2.6 * u, math.sin(a) * r)
			Geo.ball(extra, at, 0.09 * math.sin(u * math.pi) + 0.02, SecretOreFx.Rainbow[(j + k) % 6 + 1], NEON, { CanCollide = false })
		end
	end
	local name = string.format("%04d", i)
	fs.writeFile(root .. "/build/preview/" .. tag .. "/fx_" .. name .. ".json", serde.encode("json", Export.collect(extra)))
	local from, to = camAt(t)
	shots[tag .. "_" .. name] = {
		scene = tag .. "_base",
		extra = tag .. "/fx_" .. name,
		width = 1600,
		height = 900,
		position = { 0, 7.2, 19.5 },
		target = { 0, 2.9, 0 },
		fov = 40,
		cam = { position = { from.X, from.Y, from.Z }, target = { to.X, to.Y, to.Z }, fov = 40 },
		preset = "Quarry",
		shadowExtent = 40,
		maxLights = 24,
	}
end
fs.writeFile(root .. "/build/preview/" .. tag .. "_shots.json", serde.encode("json", shots))
local cells = {}
for k, secret in SecretOreConfig.List do
	table.insert(cells, { frame = math.floor(((k - 1) * EACH + 0.4) * fps), caption = `{k} {secret.Ore}` })
end
fs.writeFile(
	root .. "/build/preview/" .. tag .. "_board.json",
	serde.encode("json", { title = "TAJNÉ RUDY v pohybu", fps = fps, cells = cells })
)
print(`{frames} frames at {fps} fps ({total} s)`)
