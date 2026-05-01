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
	LaunchAttack: RemoteEvent, -- Fired when a player launches an attack on another base.
	--   args: attackType: string, targetPadNumber: number

	-- Server → Client
	UpdateMoney: RemoteEvent, -- Tells the client their current cash balance.
	--   args: amount: number
	UpdateIncome: RemoteEvent, -- Tells the client their current income rate.
	--   args: perSecond: number
	UnlockItem: RemoteEvent, -- Tells the client a tycoon item was just unlocked.
	--   args: itemName: string
	AttackWarning: RemoteEvent, -- Warns the client of an incoming attack.
	--   args: attackType: string, attackerName: string, eta: number
	BaseDamaged: RemoteEvent, -- Tells the client their base took damage.
	--   args: currentHP: number, maxHP: number, damage: number, attackType: string
	BaseDestroyed: RemoteEvent, -- Tells the client their base was destroyed.
	--   args: attackerName: string
	AttackLaunched: RemoteEvent, -- Tells all clients about an attack for visual effects.
	--   args: attackType: string, fromPad: number, toPad: number, travelTime: number
	UpdateShield: RemoteEvent, -- Tells the client their shield status changed.
	--   args: currentShield: number, maxShield: number
	AttackResult: RemoteEvent, -- Tells the attacker the result of their attack.
	--   args: success: boolean, message: string

	-- Daily Rewards
	ShowDailyReward: RemoteEvent, -- Server tells client to show daily reward calendar.
	--   args: streakDay: number, rewardAmount: number, canClaim: boolean
	ClaimDailyReward: RemoteEvent, -- Client requests to claim today's daily reward.
	--   args: (none)
	DailyRewardClaimed: RemoteEvent, -- Server confirms daily reward was claimed.
	--   args: amount: number

	-- Daily Quests
	UpdateQuests: RemoteEvent, -- Server sends quest list with progress to client.
	--   args: quests: { { questType: string, description: string, target: number, progress: number, reward: number, claimed: boolean } }
	ClaimQuestReward: RemoteEvent, -- Client requests to claim a completed quest reward.
	--   args: questIndex: number
	QuestCompleted: RemoteEvent, -- Server confirms quest reward was claimed.
	--   args: questIndex: number, reward: number

	-- Cash Collector
	UpdatePendingCash: RemoteEvent, -- Server tells client their pending (uncollected) cash total.
	--   args: pendingCash: number
	CollectCash: RemoteEvent, -- Server tells client cash was collected (for feedback).
	--   args: amount: number

	-- Combat FPS
	ShootPlayer: RemoteEvent, -- Client tells server they shot at a position.
	--   args: hitPosition: Vector3, targetPart: string?
	KillFeed: RemoteEvent, -- Server tells all clients about a kill.
	--   args: killerName: string, victimName: string

	-- Vehicles
	SpawnVehicle: RemoteEvent, -- Client requests vehicle spawn.
	--   args: vehicleType: string
	VehicleShoot: RemoteEvent, -- Client fires vehicle weapon.
	--   args: vehicleType: string, targetPosition: Vector3
	VehiclePitch: RemoteEvent, -- Client sends pitch input for jets.
	--   args: pitch: number (-1, 0, or 1)

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
		local existing = parent:WaitForChild(name, 30)
		if not existing then
			error(`Remote "{name}" not found on the client after 30s — make sure the server has initialised Remotes first.`)
		end
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
	-- Block until the server has created the folder.
	-- Use a generous timeout to handle Studio play-solo race conditions where
	-- the server scripts may still be loading DataManager / DataStore.
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) :: Folder
	if not folder then
		error(FOLDER_NAME .. " folder not found in ReplicatedStorage after 30s — server scripts may have failed to load.")
	end
end

-- ── Remote construction ───────────────────────────────────────────────────

local Remotes: RemotesType = table.freeze({
	-- Tycoon
	ClaimTycoon = getOrCreate(folder, "RemoteEvent", "ClaimTycoon") :: RemoteEvent,
	PurchaseItem = getOrCreate(folder, "RemoteEvent", "PurchaseItem") :: RemoteEvent,
	UpdateMoney = getOrCreate(folder, "RemoteEvent", "UpdateMoney") :: RemoteEvent,
	UpdateIncome = getOrCreate(folder, "RemoteEvent", "UpdateIncome") :: RemoteEvent,
	UnlockItem = getOrCreate(folder, "RemoteEvent", "UnlockItem") :: RemoteEvent,
	GetPlayerData = getOrCreate(folder, "RemoteFunction", "GetPlayerData") :: RemoteFunction,
	-- Combat
	LaunchAttack = getOrCreate(folder, "RemoteEvent", "LaunchAttack") :: RemoteEvent,
	AttackWarning = getOrCreate(folder, "RemoteEvent", "AttackWarning") :: RemoteEvent,
	BaseDamaged = getOrCreate(folder, "RemoteEvent", "BaseDamaged") :: RemoteEvent,
	BaseDestroyed = getOrCreate(folder, "RemoteEvent", "BaseDestroyed") :: RemoteEvent,
	AttackLaunched = getOrCreate(folder, "RemoteEvent", "AttackLaunched") :: RemoteEvent,
	UpdateShield = getOrCreate(folder, "RemoteEvent", "UpdateShield") :: RemoteEvent,
	AttackResult = getOrCreate(folder, "RemoteEvent", "AttackResult") :: RemoteEvent,
	-- Daily Rewards
	ShowDailyReward = getOrCreate(folder, "RemoteEvent", "ShowDailyReward") :: RemoteEvent,
	ClaimDailyReward = getOrCreate(folder, "RemoteEvent", "ClaimDailyReward") :: RemoteEvent,
	DailyRewardClaimed = getOrCreate(folder, "RemoteEvent", "DailyRewardClaimed") :: RemoteEvent,
	-- Daily Quests
	UpdateQuests = getOrCreate(folder, "RemoteEvent", "UpdateQuests") :: RemoteEvent,
	ClaimQuestReward = getOrCreate(folder, "RemoteEvent", "ClaimQuestReward") :: RemoteEvent,
	QuestCompleted = getOrCreate(folder, "RemoteEvent", "QuestCompleted") :: RemoteEvent,
	-- Cash Collector
	UpdatePendingCash = getOrCreate(folder, "RemoteEvent", "UpdatePendingCash") :: RemoteEvent,
	CollectCash = getOrCreate(folder, "RemoteEvent", "CollectCash") :: RemoteEvent,
	-- Combat FPS
	ShootPlayer = getOrCreate(folder, "RemoteEvent", "ShootPlayer") :: RemoteEvent,
	KillFeed = getOrCreate(folder, "RemoteEvent", "KillFeed") :: RemoteEvent,
	-- Vehicles
	SpawnVehicle = getOrCreate(folder, "RemoteEvent", "SpawnVehicle") :: RemoteEvent,
	VehicleShoot = getOrCreate(folder, "RemoteEvent", "VehicleShoot") :: RemoteEvent,
	VehiclePitch = getOrCreate(folder, "RemoteEvent", "VehiclePitch") :: RemoteEvent,
})

return Remotes
