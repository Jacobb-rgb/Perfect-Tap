--[[
	SettingsService: saves the player's settings (SettingsConfig: music and
	sound volume, camera shake, gamepad rumble, the wheel's Fast Spin) in data.Settings and sends
	them back in the State snapshot (snapshot.Settings).

	- On load the saved record is made whole and valid (SettingsConfig.sanitize:
	  an old save without Settings, or a broken one, gets the defaults).
	- SettingsSave (Net, rate limited) carries the whole record
	  { Music, Sfx, Shake, Rumble, FastSpin }; the server keeps only what sanitize lets
	  through and writes it when it differs from the saved one (then
	  DataService.changed). Nothing else in the save can change here.
	- The client applies its settings itself at once (SettingsController);
	  the snapshot gives them back on the next join.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.SettingsConfig)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

local SettingsService = {}

-- The saved settings of a loaded save (a missing or broken record is
-- replaced by a whole, valid one).
function SettingsService.read(data: { [string]: any }): SettingsConfig.Settings
	local raw = data.Settings
	local clean = SettingsConfig.sanitize(raw)
	-- settings a newer build added stay in the save (docs/SAVE_AUDIT.md #1(b)):
	-- short keys with a boolean, a finite number or a short string
	local stored: { [string]: any } = table.clone(clean) :: any
	if type(raw) == "table" then
		local extra = 0
		for key, value in raw do
			if
				type(key) == "string"
				and #key <= 32
				and stored[key] == nil
				and (type(value) == "boolean" or (type(value) == "number" and value == value and math.abs(value) < math.huge) or (type(
					value
				) == "string" and #value <= 64))
				and extra < 16
			then
				stored[key] = value
				extra += 1
			end
		end
	end
	data.Settings = stored
	return clean
end

-- Writes a client's request. True when the save changed.
function SettingsService.apply(player: Player, raw: any): boolean
	local data = DataService.get(player)
	if not data or not Guard.table(raw, 8) then
		return false
	end
	local wanted = SettingsConfig.sanitize(raw)
	local saved = SettingsService.read(data)
	if SettingsConfig.equal(wanted, saved) then
		return false
	end
	-- (the settings a newer build added, kept by read, stay)
	local stored: { [string]: any } = table.clone(wanted) :: any
	if type(data.Settings) == "table" then
		for key, value in data.Settings do
			if stored[key] == nil then
				stored[key] = value
			end
		end
	end
	data.Settings = stored
	DataService.changed(player)
	return true
end

function SettingsService.init()
	DataService.onLoaded(function(_player: Player, data: { [string]: any })
		SettingsService.read(data)
	end)
	StateService.addProvider(function(_player: Player, data: { [string]: any }, snapshot: { [string]: any })
		snapshot.Settings = SettingsConfig.sanitize(data.Settings)
	end)
	Net.on("SettingsSave", function(player: Player, raw: any)
		SettingsService.apply(player, raw)
	end)
end

return SettingsService
