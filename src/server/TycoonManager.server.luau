--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig = require(ReplicatedStorage.TycoonConfig) :: any
local Remotes = require(ReplicatedStorage.Remotes) :: any
local DataManager = require(script.Parent.DataManager) :: any
local TycoonBuilder = require(script.Parent.TycoonBuilder) :: any
local IncomeManager = require(script.Parent.IncomeManager) :: any
local UnitManager = require(script.Parent.UnitManager) :: any
local LeaderboardManager = require(script.Parent.LeaderboardManager) :: any
local DailyRewardManager = require(script.Parent.DailyRewardManager) :: any
local QuestManager = require(script.Parent.QuestManager) :: any

-- ── Types ─────────────────────────────────────────────────────────────────────

type TycoonState = {
	pad: number,
	balance: number,
	incomePerSecond: number,
	unlockedItems: { string },
	lastSave: number,
	lastDailyReward: number,
	dailyStreak: number,
}

-- ── State ─────────────────────────────────────────────────────────────────────

local tycoons: { [Player]: TycoonState } = {}

-- Track which pads are in use so we can assign the next free one.
local padInUse: { [number]: boolean } = {
	[1] = false,
	[2] = false,
	[3] = false,
	[4] = false,
}

local MAX_PADS = 4

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getFreePad(): number?
	for i = 1, MAX_PADS do
		if not padInUse[i] then
			return i
		end
	end
	return nil
end

local function isUnlocked(unlockedItems: { string }, itemName: string): boolean
	for _, name in unlockedItems do
		if name == itemName then
			return true
		end
	end
	return false
end

--- Return the item that should be next in sequence (lowest order not yet unlocked).
local function nextItemInSequence(unlockedItems: { string }): any?
	for _, item in ipairs(TycoonConfig.Ordered) do
		if not isUnlocked(unlockedItems, item.modelName) then
			return item
		end
	end
	return nil
end

local function fireUpdateMoney(player: Player, balance: number)
	Remotes.UpdateMoney:FireClient(player, balance)
end

-- ── Cash helper (shared by daily rewards, quests, and income) ─────────────────

local function addCash(player: Player, amount: number)
	local state = tycoons[player]
	if not state then
		return
	end
	state.balance += amount
	fireUpdateMoney(player, state.balance)
	LeaderboardManager.UpdateCash(player, state.balance)
end

-- Wire the cash callback into DailyRewardManager and QuestManager.
DailyRewardManager.SetAddCashCallback(addCash)
QuestManager.SetAddCashCallback(addCash)

-- ── Income tick callback ───────────────────────────────────────────────────────

IncomeManager.SetTickCallback(function(player: Player, amount: number)
	local state = tycoons[player]
	if not state then
		return
	end
	state.balance += amount
	state.lastSave = state.lastSave -- keep reference (actual save is on leave)
	fireUpdateMoney(player, state.balance)
	LeaderboardManager.UpdateCash(player, state.balance)

	-- Track quest progress for "earn" quests.
	QuestManager.OnIncome(player, amount)
end)

-- ── Player join ───────────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	local padNumber = getFreePad()
	if padNumber == nil then
		warn("[TycoonManager] No free pads for " .. player.Name .. ". Server is full.")
		player:Kick("The server is full — all tycoon pads are occupied. Please try again later.")
		return
	end

	padInUse[padNumber] = true

	-- Load persistent data
	local data = DataManager.LoadData(player)

	local state: TycoonState = {
		pad = padNumber,
		balance = data.balance,
		incomePerSecond = data.incomePerSecond,
		unlockedItems = data.unlockedItems,
		lastSave = os.time(),
		lastDailyReward = data.lastDailyReward or 0,
		dailyStreak = data.dailyStreak or 0,
	}
	tycoons[player] = state

	-- Setup leaderboard stats
	LeaderboardManager.Setup(player)
	LeaderboardManager.UpdateCash(player, state.balance)
	LeaderboardManager.UpdateIncome(player, state.incomePerSecond)
	LeaderboardManager.UpdateLevel(player, #state.unlockedItems)

	-- Build the tycoon in the world
	TycoonBuilder.SetupTycoonPad(padNumber, player)

	-- Teleport the player to their pad once it's built
	local PAD_SPACING = 150
	local spawnCF = CFrame.new(Vector3.new((padNumber - 1) * PAD_SPACING, 5, 10))
	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if rootPart then
		rootPart.CFrame = spawnCF
	end

	-- Respawn player on their pad if they fall below the map
	local function onCharacterAdded(newCharacter: Model)
		local hrp = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if hrp then
			hrp.CFrame = spawnCF
		end
		local humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			task.spawn(function()
				while humanoid and humanoid.Health > 0 do
					if hrp and hrp.Position.Y < -50 then
						hrp.CFrame = spawnCF
						hrp.AssemblyLinearVelocity = Vector3.zero
					end
					task.wait(0.5)
				end
			end)
		end
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	-- Register the pad with UnitManager so it knows the world-space center.
	local padCenter = CFrame.new(Vector3.new((padNumber - 1) * 150, 0, 0))
	UnitManager.RegisterPad(padNumber, player, padCenter)

	-- Re-spawn all previously unlocked buildings (skip CommandCenter — already placed by SetupTycoonPad)
	for _, itemName in state.unlockedItems do
		if itemName ~= "CommandCenter" then
			TycoonBuilder.UnlockItem(padNumber, itemName, state.unlockedItems)
		end
	end

	-- Re-spawn units for all previously unlocked items that have associated units.
	for _, itemName in state.unlockedItems do
		local item = TycoonConfig.Items[itemName]
		if item then
			local unitSpec = require(ReplicatedStorage.UnitConfig).ByTier[item.order]
			if unitSpec then
				UnitManager.SpawnUnit(padNumber, unitSpec.name)
			end
		end
	end

	-- Show the correct next purchase button
	TycoonBuilder.SpawnPurchaseButtons(padNumber, state.unlockedItems)

	-- Start income loop
	IncomeManager.StartIncome(player, state.incomePerSecond)

	-- Send initial state to the client
	fireUpdateMoney(player, state.balance)
	Remotes.UpdateIncome:FireClient(player, state.incomePerSecond)

	-- Register base with combat system
	task.defer(function()
		if _G.CombatAPI then
			_G.CombatAPI.RegisterBase(player, padNumber, state.unlockedItems)
		end
	end)

	-- Daily rewards: check if player can claim
	DailyRewardManager.CheckAndShowReward(player, data)

	-- Daily quests: generate or restore quests for today
	QuestManager.Setup(player)

	-- Set initial quest level progress based on already unlocked items
	QuestManager.OnLevelChange(player, #state.unlockedItems)

	print(
		string.format(
			"[TycoonManager] %s joined → pad %d | $%d | %d ips",
			player.Name,
			padNumber,
			state.balance,
			state.incomePerSecond
		)
	)
end

-- ── Player leave ──────────────────────────────────────────────────────────────

local function onPlayerRemoving(player: Player)
	local state = tycoons[player]
	if not state then
		return
	end

	-- Stop the income loop first so no more ticks fire
	IncomeManager.StopIncome(player)

	-- Pull latest daily reward data before saving.
	local lastDR, drStreak = DailyRewardManager.GetData(player)

	-- Persist data
	DataManager.SaveData(player, {
		balance = state.balance,
		incomePerSecond = state.incomePerSecond,
		unlockedItems = state.unlockedItems,
		totalEarned = 0, -- totalEarned tracked separately if needed
		lastDailyReward = lastDR,
		dailyStreak = drStreak,
	})

	-- Unregister from combat
	if _G.CombatAPI then
		_G.CombatAPI.UnregisterBase(player)
	end

	-- Clean up daily reward and quest state
	DailyRewardManager.OnPlayerRemoving(player)
	QuestManager.OnPlayerRemoving(player)

	-- Clean up units and the world
	UnitManager.DespawnAllUnits(state.pad)
	TycoonBuilder.CleanupTycoon(state.pad)

	-- Free the pad
	padInUse[state.pad] = false

	tycoons[player] = nil

	print(string.format("[TycoonManager] %s left → pad %d freed | saved $%d", player.Name, state.pad, state.balance))
end

-- ── Purchase handler ──────────────────────────────────────────────────────────

local function onPurchaseRequest(player: Player, itemName: string)
	local state = tycoons[player]
	if not state then
		warn("[TycoonManager] Purchase from unregistered player: " .. player.Name)
		return
	end

	-- Validate: item must exist in config
	local item = TycoonConfig.Items[itemName]
	if not item then
		warn(string.format("[TycoonManager] %s requested unknown item '%s'", player.Name, tostring(itemName)))
		return
	end

	-- Validate: must be next in sequence (linear progression)
	local nextItem = nextItemInSequence(state.unlockedItems)
	if nextItem == nil or nextItem.modelName ~= itemName then
		warn(
			string.format(
				"[TycoonManager] %s tried to skip progression (wanted '%s', next is '%s')",
				player.Name,
				itemName,
				if nextItem then nextItem.modelName else "none"
			)
		)
		return
	end

	-- Validate: sufficient funds
	if state.balance < item.cost then
		-- Silently reject; the client UI should prevent this but we guard server-side
		return
	end

	-- Deduct cost
	state.balance -= item.cost

	-- Record unlock
	table.insert(state.unlockedItems, itemName)

	-- Update income rate
	state.incomePerSecond += item.incomePerSecond
	IncomeManager.UpdateRate(player, state.incomePerSecond)

	-- Update the world
	TycoonBuilder.UnlockItem(state.pad, itemName, state.unlockedItems)

	-- Spawn the associated unit if this item's order tier maps to one.
	local unitSpec = require(ReplicatedStorage.UnitConfig).ByTier[item.order]
	if unitSpec then
		UnitManager.SpawnUnit(state.pad, unitSpec.name)
	end

	-- Update leaderboard
	LeaderboardManager.UpdateCash(player, state.balance)
	LeaderboardManager.UpdateIncome(player, state.incomePerSecond)
	LeaderboardManager.UpdateLevel(player, #state.unlockedItems)

	-- Notify combat system about new building
	if _G.CombatAPI then
		_G.CombatAPI.OnBuildingUnlocked(player, state.unlockedItems)
	end

	-- Track quest progress for "buy" and "level" quests.
	QuestManager.OnPurchase(player)
	QuestManager.OnLevelChange(player, #state.unlockedItems)

	-- Notify client
	Remotes.UnlockItem:FireClient(player, item.name, item.description)
	Remotes.UpdateIncome:FireClient(player, state.incomePerSecond)
	fireUpdateMoney(player, state.balance)

	print(
		string.format(
			"[TycoonManager] %s purchased '%s' for $%d | balance: $%d | ips: %d",
			player.Name,
			itemName,
			item.cost,
			state.balance,
			state.incomePerSecond
		)
	)
end

-- ── Combat integration ────────────────────────────────────────────────────────
-- CombatManager.server.luau uses _G.CombatAPI (set by that script).
-- We expose fund deduction/reward callbacks via _G so CombatManager can call them.

_G.CombatDeductFunds = function(player: Player, amount: number): boolean
	local state = tycoons[player]
	if not state then
		return false
	end
	if state.balance < amount then
		return false
	end
	state.balance -= amount
	fireUpdateMoney(player, state.balance)
	LeaderboardManager.UpdateCash(player, state.balance)
	return true
end

_G.CombatRewardFunds = function(player: Player, amount: number)
	local state = tycoons[player]
	if not state then
		return
	end
	state.balance += amount
	fireUpdateMoney(player, state.balance)
	LeaderboardManager.UpdateCash(player, state.balance)
end

-- ── GetPlayerData handler ─────────────────────────────────────────────────────

Remotes.GetPlayerData.OnServerInvoke = function(player: Player)
	local state = tycoons[player]
	if not state then
		return { money = 0, income = 0, unlockedItems = { "CommandCenter" } }
	end
	return {
		money = state.balance,
		income = state.incomePerSecond,
		unlockedItems = table.clone(state.unlockedItems),
	}
end

-- ── Wire up events ────────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

Remotes.PurchaseItem.OnServerEvent:Connect(onPurchaseRequest)
Remotes.ClaimDailyReward.OnServerEvent:Connect(function(player: Player)
	DailyRewardManager.ClaimReward(player)
end)
Remotes.ClaimQuestReward.OnServerEvent:Connect(function(player: Player, questIndex: unknown)
	if type(questIndex) == "number" then
		QuestManager.ClaimReward(player, questIndex)
	end
end)

-- Handle players who joined before this script loaded (Studio play-solo edge case)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
