--[[
	EventBoardLogic: what the big iron billboard shows (owner 2026-11-07: events
	on a billboard in the world, never on the player's screen). Pure: the pages
	for a moment, the page shown now. Clients compute it all from the server's
	time, so no network but the Find of the Day's attributes.
]]

local ItemData = require(script.Parent.Parent.Config.ItemData)
local OreData = require(script.Parent.Parent.Config.OreData)
local Rarity = require(script.Parent.Parent.Config.Rarity)
local WeatherConfig = require(script.Parent.Parent.Config.WeatherConfig)
local WeatherBonus = require(script.Parent.Parent.Weather.WeatherBonus)
local WeatherLogic = require(script.Parent.Parent.Weather.WeatherLogic)
local FindOfDay = require(script.Parent.FindOfDay)

local EventBoardLogic = {}

EventBoardLogic.PageSeconds = 8 -- each page stays this long
EventBoardLogic.LookAhead = 48 -- weather slots searched for the next event

export type Page = { Id: string, Title: string, Big: string, Small: string, Color: Color3, BigColor: Color3? }

local GOLD = Color3.fromRGB(255, 196, 70)
local SKY = Color3.fromRGB(120, 210, 255)

-- 252 -> "4:12", 3700 -> "1:01:40"
function EventBoardLogic.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

-- The next weather event after `now`, nil if none within LookAhead slots.
function EventBoardLogic.nextWeather(now: number): WeatherLogic.Event?
	local slot = math.floor(now / WeatherConfig.Schedule.Slot)
	for k = slot, slot + EventBoardLogic.LookAhead do
		local event = WeatherLogic.event(k)
		if event and event.Start > now then
			return event
		end
	end
	return nil
end

-- The weather now and how long it lasts, with its bonus (WeatherBonus: a rainbow's after the
-- rain too); in clear weather when the next one comes.
function EventBoardLogic.weatherPage(now: number, force: any?): Page
	local bonus = WeatherBonus.at(now, force)
	if bonus then
		local left = WeatherBonus.left(now, force)
		return {
			Id = "Weather",
			Title = "WEATHER",
			Big = if left > 0 then `{bonus.Kind} {EventBoardLogic.clock(left)}` else bonus.Kind,
			Small = bonus.Text,
			Color = SKY,
			BigColor = bonus.Color,
		}
	end
	local after = EventBoardLogic.nextWeather(now)
	local small = if after then `Next: {after.Kind} in {EventBoardLogic.clock(after.Start - now)}` else ""
	return { Id = "Weather", Title = "WEATHER", Big = "Clear skies", Small = small, Color = SKY }
end

function EventBoardLogic.findPage(find: FindOfDay.Entry?, now: number): Page
	local ore = if find and find.Day == FindOfDay.day(now) then OreData.ById[find.Ore] else nil
	if not find or not ore then
		return {
			Id = "Find",
			Title = "FIND OF THE DAY",
			Big = "Nobody yet",
			Small = "Clean an ore: the day's best goes up here",
			Color = GOLD,
		}
	end
	-- (review 11-07: readable from the spawn on a phone) the ore big in its rarity's colour,
	-- the finder and the grade on a second big line
	local rarity = Rarity.ById[ore.Rarity]
	local grade = ItemData.GradeById[find.Grade]
	return {
		Id = "Find",
		Title = "FIND OF THE DAY",
		Big = ore.Name,
		Small = `{find.Name} · {if grade then grade.Name else find.Grade}`,
		Color = GOLD,
		BigColor = if rarity then rarity.Color else nil,
	}
end

-- Every page, in the order they rotate.
function EventBoardLogic.pages(now: number, force: any?, find: FindOfDay.Entry?): { Page }
	return { EventBoardLogic.findPage(find, now), EventBoardLogic.weatherPage(now, force) }
end

-- The page to show at `now` (all clients together: it follows the server's time).
function EventBoardLogic.pageAt(now: number, pages: { Page }): Page
	local index = math.floor(now / EventBoardLogic.PageSeconds) % #pages + 1
	return pages[index]
end

return EventBoardLogic
