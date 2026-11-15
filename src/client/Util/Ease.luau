--[[
	Ease: Roblox's easing curves for posed animations (owner 2026-11-15: "use
	TweenService with appropriate easing styles and directions ... no basic
	linear animations"). A posed animation (the egg opening: HatchStage poses
	every frame from its clock, so a skip or a frame drop never breaks it)
	can't hold a Tween, so it asks TweenService for the value of the curve at
	its own moment: TweenService:GetValue(alpha, style, direction). The Lune
	specs and the previews have no TweenService: there the same curves are
	worked out here (the standard definitions TweenService uses; the specs
	hold them to TweenService's own numbers).

	  Ease.get(alpha, "Back", "Out")      0..1 -> eased (Back may overshoot)
	  Ease.span(t, from, length, style, direction)
	                                      the eased progress of `t` through
	                                      [from, from + length] (0 before, 1 after)
]]

local Ease = {}

export type Style = "Linear" | "Sine" | "Quad" | "Cubic" | "Quart" | "Quint" | "Exponential" | "Circular" | "Back"
export type Direction = "In" | "Out" | "InOut"

local PI = math.pi
local BACK = 1.70158 -- TweenService's Back overshoot

local function inCurve(style: Style, x: number): number
	if style == "Linear" then
		return x
	elseif style == "Sine" then
		return 1 - math.cos(x * PI / 2)
	elseif style == "Quad" then
		return x * x
	elseif style == "Cubic" then
		return x * x * x
	elseif style == "Quart" then
		return x * x * x * x
	elseif style == "Quint" then
		return x * x * x * x * x
	elseif style == "Exponential" then
		return if x <= 0 then 0 else 2 ^ (10 * x - 10)
	elseif style == "Circular" then
		return 1 - math.sqrt(math.max(0, 1 - x * x))
	elseif style == "Back" then
		return (BACK + 1) * x * x * x - BACK * x * x
	end
	return x
end

-- The curve worked out (the specs and previews; Roblox asks TweenService).
function Ease.pure(alpha: number, style: Style, direction: Direction): number
	local x = math.clamp(if alpha == alpha then alpha else 0, 0, 1)
	if direction == "In" then
		return inCurve(style, x)
	elseif direction == "Out" then
		return 1 - inCurve(style, 1 - x)
	end
	if x < 0.5 then
		return inCurve(style, 2 * x) / 2
	end
	return 1 - inCurve(style, 2 - 2 * x) / 2
end

-- TweenService in Roblox (nil in the Lune specs and the previews: their services are stubs).
local service: any = nil
do
	local ok, found = pcall(function(): any
		local ts = game:GetService("TweenService")
		if typeof(ts) == "Instance" then
			return ts
		end
		return nil
	end)
	if ok then
		service = found
	end
end

-- Off: the curves worked out here everywhere (the specs compare both).
Ease.UseTweenService = service ~= nil

function Ease.get(alpha: number, style: Style, direction: Direction): number
	local x = math.clamp(if alpha == alpha then alpha else 0, 0, 1)
	if Ease.UseTweenService and service then
		local ok, value = pcall(function(): number
			return service:GetValue(x, (Enum.EasingStyle :: any)[style], (Enum.EasingDirection :: any)[direction])
		end)
		if ok and type(value) == "number" then
			return value
		end
	end
	return Ease.pure(x, style, direction)
end

-- The eased progress of `t` through [from, from + length]: 0 before it, 1 after it.
function Ease.span(t: number, from: number, length: number, style: Style, direction: Direction): number
	if t <= from then
		return 0
	end
	if length <= 0 or t >= from + length then
		return 1
	end
	return Ease.get((t - from) / length, style, direction)
end

return Ease
