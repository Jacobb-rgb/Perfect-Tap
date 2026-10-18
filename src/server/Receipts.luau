--[[
	Receipts gate (docs/COMPLIANCE.md 2.6): ONE switch for every Robux
	product and game pass. Nothing in the game grants a purchase until step
	8's MonetizationService is in (ProcessReceipt for developer products,
	UserOwnsGamePassAsync on join and PromptGamePassPurchaseFinished for
	passes). Until then a product whose id is live in MonetizationConfig is
	still never prompted: every prompt path turns "Prompt" into
	"ComingSoon" while ready() is false, so nobody pays Robux for nothing:
	- BoostService.promptPurchase (the Triple / Hexa Lucky packs, the Mythic
	  enchant passes Heartfire / Starbreaker),
	- CapsuleService (Royal capsules; its setReceiptsReady / receiptsReady
	  are this same switch).

	- setReady(true) is called by step 8 once its handlers are connected.
	  It also sets the ReplicatedStorage attribute
	  MonetizationConfig.ReceiptsAttribute, which the client cards read
	  (CapsuleView, BoostView, EnchantView: "Coming soon" while it isn't true).

	The gate only blocks in-game prompts. Game passes are also sold on the
	game page's Store tab (website and app) with no prompt at all, and
	nothing grants a pass before step 8. So create the passes and products
	to get their ids, but keep every game pass Off Sale (Creator Dashboard
	-> Monetization -> Passes -> Sales) until step 8 is live and calls
	Receipts.setReady(true); the same for a developer product if the
	Dashboard offers to list it on the Store tab (docs/COMPLIANCE.md 2.6a,
	section 3 and the section 4 checklist).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)

local Receipts = {}

Receipts.Attribute = MonetizationConfig.ReceiptsAttribute

local ready = false

local function defaultPublish(value: boolean)
	ReplicatedStorage:SetAttribute(Receipts.Attribute, value)
end
-- Swappable for the Lune tests.
local publish: (value: boolean) -> () = defaultPublish

-- Does step 8 grant receipts and passes yet?
function Receipts.ready(): boolean
	return ready
end

-- Step 8: true once ProcessReceipt and the pass grants are connected.
function Receipts.setReady(value: boolean)
	ready = value == true
	publish(ready)
end

-- What a prompt path answers: "Prompt" becomes "ComingSoon" while not ready.
function Receipts.gate(status: string): string
	if status == "Prompt" and not ready then
		return "ComingSoon"
	end
	return status
end

-- Internals for the Lune tests only.
Receipts._test = {
	setPublisher = function(fn: (boolean) -> ())
		publish = fn
	end,
	reset = function()
		ready = false
		publish = defaultPublish
	end,
}

return Receipts
