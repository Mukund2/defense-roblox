--!strict

--[[
	Remotes.luau
	------------
	Single source of truth for all RemoteEvents and RemoteFunctions used by
	the tycoon game.  Require this module on both the server and the client —
	it will create the Remotes folder and its children when running on the
	server, and simply retrieve them when running on the client.

	Usage (server):
		local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
		Remotes.UpdateMoney:FireClient(player, 1234)

	Usage (client):
		local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
		Remotes.UpdateMoney.OnClientEvent:Connect(function(amount) ... end)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

-- ── Types ──────────────────────────────────────────────────────────────────

export type RemotesType = {
	-- Client → Server
	ClaimTycoon: RemoteEvent, -- Fired when a player clicks a base pad to claim it.
	PurchaseItem: RemoteEvent, -- Fired when a player activates a purchase button.
	--   args: itemName: string

	-- Server → Client
	UpdateMoney: RemoteEvent, -- Tells the client their current cash balance.
	--   args: amount: number
	UpdateIncome: RemoteEvent, -- Tells the client their current income rate.
	--   args: perSecond: number
	UnlockItem: RemoteEvent, -- Tells the client a tycoon item was just unlocked.
	--   args: itemName: string

	-- Client → Server (with response)
	GetPlayerData: RemoteFunction, -- Client requests its full save data snapshot.
	--   returns: { money: number, income: number, unlockedItems: {string} }
}

-- ── Helpers ────────────────────────────────────────────────────────────────

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	if IS_SERVER then
		local existing = parent:FindFirstChild(name)
		if existing then
			return existing
		end
		local instance = Instance.new(className)
		instance.Name = name
		instance.Parent = parent
		return instance
	else
		-- Client: wait for the server to create the remote
		local existing = parent:WaitForChild(name, 10)
		assert(existing, `Remote "{name}" not found on the client after 10s — make sure the server has initialised Remotes first.`)
		return existing
	end
end

-- ── Folder ────────────────────────────────────────────────────────────────

local FOLDER_NAME = "RemoteEvents"

local folder: Folder
if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
else
	-- Block until the server has created the folder (handles race conditions).
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 10) :: Folder
	assert(folder, FOLDER_NAME .. " folder not found in ReplicatedStorage after 10 seconds.")
end

-- ── Remote construction ───────────────────────────────────────────────────

local Remotes: RemotesType = table.freeze({
	ClaimTycoon = getOrCreate(folder, "RemoteEvent", "ClaimTycoon") :: RemoteEvent,
	PurchaseItem = getOrCreate(folder, "RemoteEvent", "PurchaseItem") :: RemoteEvent,
	UpdateMoney = getOrCreate(folder, "RemoteEvent", "UpdateMoney") :: RemoteEvent,
	UpdateIncome = getOrCreate(folder, "RemoteEvent", "UpdateIncome") :: RemoteEvent,
	UnlockItem = getOrCreate(folder, "RemoteEvent", "UnlockItem") :: RemoteEvent,
	GetPlayerData = getOrCreate(folder, "RemoteFunction", "GetPlayerData") :: RemoteFunction,
})

return Remotes
