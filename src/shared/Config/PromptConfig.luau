--[[
	The keys and the look of every ProximityPrompt (owner playtest
	2026-10-20: every prompt on E, in Roblox's own stock prompt look). Each
	prompt in src/ is made by PromptConfig.make, so its keys come from here
	and nowhere else (tests/PromptKeys.spec.luau checks it).

	  Role    keyboard  gamepad  used by
	  Main    E         Y        shops, stalls, counters, machines: "Put In",
	                             "Clean Ore", "Load Train", "Place Ore"...
	  Second  G         B        the second prompt on the same spot: "Open
	                             Pen", "Send Train", "Take Ore
	                             Back", "Keep List", "Change Sort"
	  Panel   T         L3       the client's "Train" panel prompt at a station

	Taken elsewhere: F / gamepad X is Grab / Drop (InteractController), Q /
	RB Throw. Gamepad Y stays the main prompt button because Roblox's own
	default (X) is Grab. B is also every panel's close key; that is safe
	because an open panel suppresses the prompts (PromptController).

	Prompts sharing one attachment stack Slot * SlotHeight pixels apart
	(UIOffset); the stock prompt draws them one under the other.
]]

export type Role = "Main" | "Second" | "Panel"

export type Keys = { Keyboard: Enum.KeyCode, Gamepad: Enum.KeyCode }

export type Spec = {
	Role: Role?, -- which keys (default "Main")
	Name: string?,
	ActionText: string?,
	ObjectText: string?,
	Hold: number?, -- HoldDuration in seconds (default 0)
	Distance: number?, -- MaxActivationDistance in studs (default 10)
	Sight: boolean?, -- RequiresLineOfSight (default false)
	Slot: number?, -- UIOffset = (0, Slot * SlotHeight) (default 0)
	Exclusivity: Enum.ProximityPromptExclusivity?, -- default OnePerButton
	Enabled: boolean?, -- default true
	Parent: Instance?, -- set last; leave it out to tag or attribute the prompt first
}

local PromptConfig = {}

PromptConfig.Keys = {
	Main = { Keyboard = Enum.KeyCode.E, Gamepad = Enum.KeyCode.ButtonY } :: Keys,
	Second = { Keyboard = Enum.KeyCode.G, Gamepad = Enum.KeyCode.ButtonB } :: Keys,
	Panel = { Keyboard = Enum.KeyCode.T, Gamepad = Enum.KeyCode.ButtonL3 } :: Keys,
}

PromptConfig.SlotHeight = 72 -- UIOffset pixels between stacked prompts on one attachment
PromptConfig.Distance = 10 -- the default MaxActivationDistance

-- The keys of a role (nil = "Main").
function PromptConfig.keys(role: Role?): Keys
	if role == "Second" then
		return PromptConfig.Keys.Second
	elseif role == "Panel" then
		return PromptConfig.Keys.Panel
	end
	return PromptConfig.Keys.Main
end

-- A new ProximityPrompt in the stock Roblox look with the role's keys.
function PromptConfig.make(spec: Spec): ProximityPrompt
	local keys = PromptConfig.keys(spec.Role)
	local prompt = Instance.new("ProximityPrompt")
	if spec.Name then
		prompt.Name = spec.Name
	end
	if spec.ActionText then
		prompt.ActionText = spec.ActionText
	end
	if spec.ObjectText then
		prompt.ObjectText = spec.ObjectText
	end
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.KeyboardKeyCode = keys.Keyboard
	prompt.GamepadKeyCode = keys.Gamepad
	prompt.HoldDuration = spec.Hold or 0
	prompt.MaxActivationDistance = spec.Distance or PromptConfig.Distance
	prompt.RequiresLineOfSight = spec.Sight == true
	prompt.UIOffset = Vector2.new(0, (spec.Slot or 0) * PromptConfig.SlotHeight)
	if spec.Exclusivity then
		prompt.Exclusivity = spec.Exclusivity
	end
	if spec.Enabled ~= nil then
		prompt.Enabled = spec.Enabled
	end
	if spec.Parent then
		prompt.Parent = spec.Parent
	end
	return prompt
end

return PromptConfig
