--[[
	WeatherBonus: every weather gives ore something (owner 2026-11-07, his pick:
	one bonus per weather, wherever you mine, the mines too). Pure: both sides
	compute it from the server's time, like the weather itself (WeatherLogic).
	A bonus lasts from the weather's first second to its last; a rainbow's starts
	when the rain is over. Bonuses (server) applies them; UI/BoostView puts the
	luck ones in the odds a paid boost shows.

	  Rain      Twin    a dropped ore has this much more chance of a twin
	  Storm     Luck    x ore luck (and so the secret ores' chance), under the luck
	                    cap: nothing on top of Hexa Lucky or Server Luck
	  Hail      Damage  x blaster damage
	  Snow      Clean   the dirt is this many times thinner (CleaningPatterns.thin;
	                    par stays the clump's, so the score never gets harder)
	  Wind      Reach   x an Ore Magnet's pull (within the radius cap); without a
	                    magnet, x your pick-up reach (owner: "i bez magnetu")
	  Heatwave  Machine x the processing machines' speed (ProcessingService jobs:
	                    furnaces, crushers, the Cleaning Plant, Polisher, Extractor;
	                    belts, droppers, the train and the Iron Box unchanged)
	  Rainbow   Secret  x the secret ores' chance
]]

local WeatherLogic = require(script.Parent.WeatherLogic)

local WeatherBonus = {}

export type Entry = {
	Kind: string,
	Tag: string, -- the chip's word
	Text: string, -- the toast when it starts
	Color: Color3,
	Twin: number?,
	Luck: number?,
	Damage: number?,
	Clean: number?,
	Reach: number?,
	Machine: number?,
	Secret: number?,
}

WeatherBonus.List = {
	Rain = { Kind = "Rain", Tag = "RAIN", Text = "Rain: +20% double ore", Color = Color3.fromRGB(90, 170, 255), Twin = 0.2 },
	Storm = {
		Kind = "Storm",
		Tag = "STORM",
		Text = "Storm: ore luck x1.5 (not on top of Hexa or Server Luck)",
		Color = Color3.fromRGB(170, 120, 255),
		Luck = 1.5,
	},
	Hail = { Kind = "Hail", Tag = "HAIL", Text = "Hail: rocks break 25% faster", Color = Color3.fromRGB(170, 220, 240), Damage = 1.25 },
	Snow = {
		Kind = "Snow",
		Tag = "SNOW",
		Text = "Snow: the dirt on your ore is thinner",
		Color = Color3.fromRGB(210, 235, 255),
		Clean = 1.3,
	},
	Wind = {
		Kind = "Wind",
		Tag = "WIND",
		Text = "Wind: ore flies to you from further away, even without a magnet",
		Color = Color3.fromRGB(130, 230, 170),
		Reach = 2,
	},
	Heatwave = {
		Kind = "Heatwave",
		Tag = "HEAT",
		Text = "Heatwave: furnaces, crushers and plants 25% faster",
		Color = Color3.fromRGB(255, 160, 70),
		Machine = 1.25,
	},
	Rainbow = {
		Kind = "Rainbow",
		Tag = "RAINBOW",
		Text = "Rainbow: secret ore chance x2",
		Color = Color3.fromRGB(255, 120, 230),
		Secret = 2,
	},
} :: { [string]: Entry }

-- The bonus at server time `now` (`force` = the WeatherForce attribute), nil in clear weather.
function WeatherBonus.at(now: number, force: any?): Entry?
	local state = WeatherLogic.at(now, force)
	if state.Kind ~= "Clear" then
		return WeatherBonus.List[state.Kind]
	end
	return if state.Rainbow > 0 then WeatherBonus.List.Rainbow else nil
end

-- Seconds until the weather at `now` is over (0 when it isn't known).
function WeatherBonus.left(now: number, force: any?): number
	local state = WeatherLogic.at(now, force)
	local event = state.Event
	if not event then
		return 0
	end
	if state.Kind ~= "Clear" then
		return math.max(0, event.Start + event.Length - now)
	end
	local gone = WeatherLogic.rainbowEnd(event)
	return if gone then math.max(0, gone - now) else 0
end

return WeatherBonus
