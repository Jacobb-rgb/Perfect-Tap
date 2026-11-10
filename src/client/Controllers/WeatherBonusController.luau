--[[
	WeatherBonusController: says once what a weather gives when it starts (a short
	toast; Weather/WeatherBonus, owner 2026-11-07: nothing stays on the screen; the
	running chip is BoostView's). Once a second, no network.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeatherBonus = require(Shared.Weather.WeatherBonus)

local WeatherBonusController = {}

-- What to say when the weather goes from `before` to `now` (nil: nothing).
function WeatherBonusController.word(before: WeatherBonus.Entry?, now: WeatherBonus.Entry?): string?
	if now and (not before or before.Kind ~= now.Kind) then
		return now.Text
	end
	return nil
end

function WeatherBonusController.init() end

function WeatherBonusController.start()
	task.spawn(function()
		Players.LocalPlayer:WaitForChild("PlayerGui")
		-- (a weather already running at the join says nothing: the chip shows it)
		local last = WeatherBonus.at(Workspace:GetServerTimeNow(), Workspace:GetAttribute("WeatherForce"))
		while true do
			task.wait(1)
			local now = WeatherBonus.at(Workspace:GetServerTimeNow(), Workspace:GetAttribute("WeatherForce"))
			local word = WeatherBonusController.word(last, now)
			last = now
			if word and now then
				require(script.Parent.HudController).toast(word, "Info", now.Color)
			end
		end
	end)
end

return WeatherBonusController
