--[[
	Close-up camera for the cleaning minigame (pure math, unit tested).

	Fits the ore into the part of the screen the UI leaves free: widens the
	view when the ore wouldn't fit (small phones) and tilts the camera so the
	ore sits in the middle of the free area. On a normal PC screen this
	changes almost nothing.
]]

local CameraFit = {}

CameraFit.BaseFov = 40
CameraFit.MaxFov = 62

export type Input = {
	ViewportHeight: number, -- pixels, whole screen
	InsetTop: number, -- pixels taken by the Roblox top bar
	FreeTop: number, -- design units from the top of the UI area that the UI covers
	FreeBottom: number, -- design units from the bottom that the UI covers
	UiScale: number,
	Outline: { Vector2 }, -- ore outline in face units
	FaceScale: number, -- studs per face unit
	CamPoint: CFrame, -- default close-up camera (aims 0.1 stud above the ore point)
	OrePoint: Vector3,
}

function CameraFit.compute(input: Input): (CFrame, number)
	local height = input.ViewportHeight
	if height < 50 then
		return input.CamPoint, CameraFit.BaseFov
	end
	local top = input.InsetTop + input.FreeTop * input.UiScale
	local bottom = height - input.FreeBottom * input.UiScale
	local free = math.max(bottom - top, height * 0.35)
	local minV, maxV = math.huge, -math.huge
	for _, p in input.Outline do
		minV = math.min(minV, p.Y)
		maxV = math.max(maxV, p.Y)
	end
	local extent = (maxV - minV) * input.FaceScale + 0.3 -- a little room for the tool and the glow
	local mid = (maxV + minV) * 0.5 * input.FaceScale
	local distance = (input.CamPoint.Position - input.OrePoint).Magnitude
	local tanHalf = math.max(math.tan(math.rad(CameraFit.BaseFov / 2)), (height / 2) * extent / (free * distance))
	local fov = math.clamp(2 * math.deg(math.atan(tanHalf)), CameraFit.BaseFov, CameraFit.MaxFov)
	local focal = (height / 2) / math.tan(math.rad(fov / 2))
	-- tilt up (positive pitch) to move the ore down the screen, and the other way round
	local pitch = math.atan((mid - 0.1) / distance) + math.atan(((top + bottom) / 2 - height / 2) / focal)
	return input.CamPoint * CFrame.Angles(pitch, 0, 0), fov
end

-- Screen position (pixels) of a point, for checks: where something ends up on screen.
function CameraFit.screenPoint(camera: CFrame, fov: number, width: number, height: number, point: Vector3): (number, number)
	local relative = camera:PointToObjectSpace(point)
	local focal = (height / 2) / math.tan(math.rad(fov / 2))
	return width / 2 + focal * (relative.X / -relative.Z), height / 2 - focal * (relative.Y / -relative.Z)
end

return CameraFit
