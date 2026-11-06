--[[
	BarrelSpin: the minigun's barrels turn while it fires (owner 2026-10-31:
	"když minigun střílí na krystaly, ať se točí ten kotouč, jako kdyby
	střílel"). A blaster built as a minigun hangs its barrels on a Motor6D
	(BlasterBuilder.SpinMotor) on its Handle; this turns that motor's
	Transform about the barrels' axis (its Z), on this client only:

	  set(tool, on)   your gun: BlasterFx.start / stop (the trigger)
	  poke(tool)      another player's gun: each BlastHit of theirs keeps it
	                  turning for Hold seconds (FxController)

	The barrels spin up to Full radians a second over SpinUp seconds, the
	shots getting faster with them (BlasterFeel.Shots, Effects/BlasterShots),
	and run down over SpinDown when the firing ends (they stay where they
	stop: six barrels look the same at any angle). One Stepped connection
	while any gun turns, none otherwise; a gun put away or destroyed is dropped.
	Reduce motion: the barrels turn slower (ReducedFull).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterBuilder = require(Shared.Builders.BlasterBuilder)
local BlasterFeel = require(Shared.Config.BlasterFeel)
local Motion = require(script.Parent.Parent.UI.Motion)

local BarrelSpin = {}

BarrelSpin.Full = BlasterFeel.barrelSpeed() -- radians a second at full spin (4 turns: a barrel per shot)
BarrelSpin.ReducedFull = 6 -- with Reduce motion
BarrelSpin.SpinUp = BlasterFeel.Shots.SpinUp -- seconds to full spin
BarrelSpin.SpinDown = BlasterFeel.Shots.SpinDown -- seconds to a stop
BarrelSpin.Hold = 0.4 -- seconds another player's gun keeps turning after their last hit

type Spin = { Motor: Motor6D, Angle: number, Speed: number, Until: number, On: boolean }

local spins: { [Tool]: Spin } = {}
local connection: RBXScriptConnection? = nil

-- The next spin speed (radians a second) from `speed`, spinning up toward `full` while `on`.
function BarrelSpin.speed(speed: number, on: boolean, dt: number, full: number): number
	if on then
		return math.min(full, speed + full * dt / BarrelSpin.SpinUp)
	end
	return math.max(0, speed - full * dt / BarrelSpin.SpinDown)
end

-- The tool's barrel motor (nil: not a minigun).
function BarrelSpin.motorOf(tool: Instance): Motor6D?
	local handle = tool:FindFirstChild("Handle")
	local motor = if handle then handle:FindFirstChild(BlasterBuilder.SpinMotor) else nil
	return if motor and motor:IsA("Motor6D") then motor else nil
end

local function step(dt: number)
	local now = os.clock()
	local full = if Motion.reduced() then BarrelSpin.ReducedFull else BarrelSpin.Full
	local any = false
	for tool, spin in spins do
		if not spin.Motor.Parent or not tool.Parent then
			spins[tool] = nil
			continue
		end
		local on = spin.On or now < spin.Until
		spin.Speed = BarrelSpin.speed(spin.Speed, on, dt, full)
		if spin.Speed > 0 then
			spin.Angle = (spin.Angle + spin.Speed * dt) % (math.pi * 2)
			spin.Motor.Transform = CFrame.Angles(0, 0, spin.Angle)
			any = true
		elseif on then
			any = true
		else
			spins[tool] = nil
		end
	end
	local current = connection
	if not any and current then
		connection = nil
		current:Disconnect()
	end
end

local function spinOf(tool: Tool): Spin?
	local spin = spins[tool]
	if not spin then
		local motor = BarrelSpin.motorOf(tool)
		if not motor then
			return nil
		end
		spin = { Motor = motor, Angle = 0, Speed = 0, Until = 0, On = false }
		spins[tool] = spin
	end
	if not connection then
		-- (Stepped: after the Animator, like the moves; it never touches this motor anyway)
		connection = RunService.Stepped:Connect(function(_time: number, dt: number)
			step(dt)
		end)
	end
	return spin
end

-- Your gun: turning while `on` (the trigger is down), running down when it comes up.
function BarrelSpin.set(tool: Tool?, on: boolean)
	if not tool then
		return
	end
	local spin = if on then spinOf(tool) else spins[tool]
	if spin then
		spin.On = on
	end
end

-- Another player's gun fired (their BlastHit): it turns for Hold seconds more.
function BarrelSpin.poke(tool: Tool?)
	if not tool then
		return
	end
	local spin = spinOf(tool)
	if spin then
		spin.Until = os.clock() + BarrelSpin.Hold
	end
end

return BarrelSpin
