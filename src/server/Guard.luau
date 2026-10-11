--[[
	Validators for values that come from clients. Never trust anything a
	client sends: types, NaN/inf, sizes, and instances from other places.
]]

local Guard = {}

function Guard.number(value: any, min: number, max: number): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil -- NaN or infinite
	end
	if value < min or value > max then
		return nil
	end
	return value
end

function Guard.integer(value: any, min: number, max: number): number?
	local n = Guard.number(value, min, max)
	if n and n == math.floor(n) then
		return n
	end
	return nil
end

function Guard.string(value: any, maxLength: number): string?
	if type(value) ~= "string" or #value > maxLength then
		return nil
	end
	return value
end

function Guard.boolean(value: any): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

-- A finite Vector3 with a sane magnitude.
function Guard.vector3(value: any, maxMagnitude: number): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local v = value :: Vector3
	for _, c in { v.X, v.Y, v.Z } do
		if c ~= c or c == math.huge or c == -math.huge then
			return nil
		end
	end
	if v.Magnitude > maxMagnitude then
		return nil
	end
	return v
end

function Guard.unitVector(value: any): Vector3?
	local v = Guard.vector3(value, 1.5)
	if not v or v.Magnitude < 0.5 then
		return nil
	end
	return v.Unit
end

-- An Instance of the given class that is a descendant of `container`.
function Guard.instance(value: any, className: string, container: Instance?): Instance?
	if typeof(value) ~= "Instance" then
		return nil
	end
	local instance = value :: Instance
	if not instance:IsA(className) then
		return nil
	end
	if container and not instance:IsDescendantOf(container) then
		return nil
	end
	return instance
end

-- Plain table (array or map) with at most `maxEntries` entries, no metatable.
function Guard.table(value: any, maxEntries: number): { [any]: any }?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local count = 0
	for _ in value do
		count += 1
		if count > maxEntries then
			return nil
		end
	end
	return value
end

function Guard.rootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

return Guard
