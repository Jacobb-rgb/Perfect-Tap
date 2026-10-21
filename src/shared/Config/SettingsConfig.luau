--[[
	The player's settings (the side menu's SETTINGS panel): music volume,
	sound volume, camera shake on/off, gamepad rumble on/off. Saved per player
	in data.Settings (SettingsService), sent back in the State snapshot
	(snapshot.Settings) and applied on the client (SettingsController):

	  Music   0..1  the SoundService SoundGroup MusicGroup ("TerraForgeMusic"):
	                every music track plays through it
	  Sfx     0..1  the SoundGroup SfxGroup ("TerraForgeSfx", Effects/Sfx) and
	                the other game sounds that use it
	  Shake   bool  camera shake (Effects/CameraShake.setEnabled)
	  Rumble  bool  gamepad rumble (MiningController.setRumble)
	  FastSpin bool the Spin & Win wheel's Fast Spin box (WheelController:
	                WheelConfig.FastSpinSeconds instead of SpinSeconds; set
	                on the wheel screen, not a row of the SETTINGS panel)

	sanitize() turns anything (an old save, a client's request) into a whole,
	valid record: volumes are clamped to 0..1 and snapped to whole percent,
	unknown keys are dropped, missing or broken values take the default.
]]

export type Settings = { Music: number, Sfx: number, Shake: boolean, Rumble: boolean, FastSpin: boolean }

local SettingsConfig = {}

SettingsConfig.Defaults = { Music = 0.6, Sfx = 0.8, Shake = true, Rumble = true, FastSpin = false } :: Settings
SettingsConfig.Step = 0.1 -- the - / + buttons and gamepad left / right
SettingsConfig.MusicGroup = "TerraForgeMusic"
SettingsConfig.SfxGroup = "TerraForgeSfx"
-- the client sends the record this long after the last change (a slider drag
-- sends one request, not one per frame), and at once when the panel closes
SettingsConfig.SaveDelay = 1.5
SettingsConfig.Volumes = { "Music", "Sfx" }
SettingsConfig.Toggles = { "Shake", "Rumble" }

local function volume(value: any, default: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	return math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100
end

local function toggle(value: any, default: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return default
end

-- A whole, valid settings record from anything (never the same table).
function SettingsConfig.sanitize(raw: any): Settings
	local d = SettingsConfig.Defaults
	if type(raw) ~= "table" then
		return { Music = d.Music, Sfx = d.Sfx, Shake = d.Shake, Rumble = d.Rumble, FastSpin = d.FastSpin }
	end
	return {
		Music = volume(raw.Music, d.Music),
		Sfx = volume(raw.Sfx, d.Sfx),
		Shake = toggle(raw.Shake, d.Shake),
		Rumble = toggle(raw.Rumble, d.Rumble),
		FastSpin = toggle(raw.FastSpin, d.FastSpin),
	}
end

-- A saved record with some keys changed on top (the changes a client made
-- before the saved record reached it); a whole, valid record.
function SettingsConfig.merge(saved: any, changed: { [string]: any }): Settings
	local raw = table.clone(SettingsConfig.sanitize(saved)) :: { [string]: any }
	for key, value in changed do
		raw[key] = value
	end
	return SettingsConfig.sanitize(raw)
end

function SettingsConfig.equal(a: Settings, b: Settings): boolean
	return a.Music == b.Music and a.Sfx == b.Sfx and a.Shake == b.Shake and a.Rumble == b.Rumble and a.FastSpin == b.FastSpin
end

-- One step up or down (dir = 1 / -1), snapped to the step grid.
function SettingsConfig.stepVolume(value: number, dir: number): number
	local steps = math.floor(value / SettingsConfig.Step + 0.5) + (if dir > 0 then 1 else -1)
	return volume(steps * SettingsConfig.Step, value)
end

-- "60%"
function SettingsConfig.percent(value: number): string
	return tostring(math.floor(math.clamp(value, 0, 1) * 100 + 0.5)) .. "%"
end

return SettingsConfig
