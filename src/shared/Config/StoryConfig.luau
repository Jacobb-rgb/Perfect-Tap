--[[
	The story of the Kingdom of Kaldrum (step 7, docs/DESIGN_V2_NOTES.md
	"Story draft"). Journal pages are read at the Guild board in town and in
	the artifact collection book.

	- The Prologue is always open.
	- Every artifact collection (ArtifactConfig.Collections) unlocks one
	  chapter when it is complete. ArtifactAction ("ReadChapter",
	  { Collection }) marks it read (data.Artifacts.Chapters[collection] = true),
	  so the "new chapter" badge goes away.
	- Later updates add a region, a collection and its chapter here (Number
	  keeps counting up).
]]

export type Page = { Title: string, Text: string }
export type Chapter = {
	Collection: string, -- ArtifactConfig collection id that unlocks it
	Number: number,
	Title: string,
	Pages: { Page },
}

local StoryConfig = {}

StoryConfig.Prologue = {
	Title = "The Apprentice",
	Pages = {
		{
			Title = "Welcome to Emberfall",
			Text = "The Forgekeepers' Guild has lit the Great Forge again. You arrive with a rusty old blaster, a borrowed train and a head full of questions.",
		},
		{
			Title = "A Kingdom Under the Rock",
			Text = "The miners say a kingdom once stood here. Break enough rocks and you may find what it left behind: coins, crowns, cogs, and stranger things.",
		},
		{
			Title = "The Guild's Request",
			Text = "Bring every relic you find to the Guild. Each complete collection fills a page of Kaldrum's lost history, and the Guild rewards those who restore it.",
		},
	},
}

StoryConfig.Chapters = {
	{
		Collection = "CrownOfKaldrum",
		Number = 1,
		Title = "The Ember Kings",
		Pages = {
			{
				Title = "A City Around a Fire",
				Text = "Long ago Terra was the Kingdom of Kaldrum. Its capital was built in a ring around the Heartstone, a living ember that glowed at the core of the world.",
			},
			{
				Title = "The Crown and the Flame",
				Text = "The Ember Kings ruled from a throne carved over the Heartstone. At every coronation the scepter was raised over the stone, and the stone glowed brighter for its new king.",
			},
			{
				Title = "Coins for Miners",
				Text = "Kaldrum paid its miners in copper coins stamped with a flame. Every family had a forge, and every forge was lit from the Heartstone's warmth.",
			},
			{
				Title = "The Last Coronation",
				Text = "The last Ember King was crowned on a stormy night. The scribes wrote that the Heartstone flickered, just once, as the crown touched his head.",
			},
		},
	},
	{
		Collection = "RoyalRailway",
		Number = 2,
		Title = "Rails Under the Mountain",
		Pages = {
			{
				Title = "The Second Wonder",
				Text = "Kaldrum's smiths built three wonders. The second was the Royal Railway: tunnels and bridges that carried ore from every mine to the capital's forges.",
			},
			{
				Title = "Golden Spikes",
				Text = "The king hammered the first golden spike himself. Within a hundred years the rails reached every corner of the kingdom, and no miner walked home alone.",
			},
			{
				Title = "The Ember Express",
				Text = "The royal train, the Ember Express, ran on a single Heartstone spark. Children waved at it from the cliffs; golem porters loaded it in silence.",
			},
			{
				Title = "The Night Train",
				Text = "On the night of the Shattering the last train left the capital full of families. The Guild still searches for where it stopped.",
			},
		},
	},
	{
		Collection = "Golemworks",
		Number = 3,
		Title = "The Sleeping Helpers",
		Pages = {
			{
				Title = "Stone That Walks",
				Text = "The third wonder was the golem: a helper of stone and ore, with a Heartstone spark for a heart. Golems carried, dug, guarded and, some say, told jokes.",
			},
			{
				Title = "Master Orvald",
				Text = "Master Orvald of the Golemworks shaped his golems small and kind: big heads, short legs, bright eyes. He said a helper should never look frightening.",
			},
			{
				Title = "Dormant Cores",
				Text = "When the Heartstone cracked, every golem in Kaldrum froze. Their hearts curled up into dormant cores, sealed in stone capsules, waiting for warmth.",
			},
			{
				Title = "Waking Them Up",
				Text = "The capsules you open in Emberfall hold those very cores. Each golem you wake is one of Kaldrum's helpers, home again after a very long sleep.",
			},
		},
	},
	{
		Collection = "HeartstoneLore",
		Number = 4,
		Title = "The Shattering",
		Pages = {
			{
				Title = "A Star That Fell",
				Text = "The sky-watchers' maps tell the oldest secret: the Heartstone was not born in Terra. It fell from the stars, and Kaldrum grew up around its glow.",
			},
			{
				Title = "Too Much Fire",
				Text = "Kaldrum asked more and more of the Heartstone: brighter forges, faster trains, stronger Sunlances. The royal scribe wrote that the stone had begun to tire.",
			},
			{
				Title = "The Shattering",
				Text = "One night the Heartstone cracked. Kaldrum sank into the rock, its shards scattered into glowing ores, its rails were buried and its golems fell asleep.",
			},
			{
				Title = "The Forgekeepers' Oath",
				Text = "A few smiths survived and swore an oath: keep the fire, share the ore, wake what sleeps. Their Guild still keeps that promise in Emberfall.",
			},
			{
				Title = "A Heart That Still Beats",
				Text = "The fragment you found still beats. If shards can glow and golems can wake, perhaps the Heartstone can be whole again. The Guild will need your help.",
			},
		},
	},
} :: { Chapter }

StoryConfig.ByCollection = {} :: { [string]: Chapter }
for _, chapter in StoryConfig.Chapters do
	StoryConfig.ByCollection[chapter.Collection] = chapter
end

return StoryConfig
