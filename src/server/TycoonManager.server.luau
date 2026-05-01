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
local WeaponManager = require(script.Parent.WeaponManager) :: any
local VehicleManager = require(script.Parent.VehicleManager) :: any

-- ── Types ─────────────────────────────────────────────────────────────────────

type TycoonState = {
	pad: number,
	balance: number,
	pendingCash: number,
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

-- Must match TycoonBuilder's PAD_POSITIONS (circular layout)
local PAD_POSITIONS = {
	Vector3.new(0, 0, 400),    -- North
	Vector3.new(400, 0, 0),    -- East
	Vector3.new(0, 0, -400),   -- South
	Vector3.new(-400, 0, 0),   -- West
}

local function padOrigin(padNumber: number): Vector3
	return PAD_POSITIONS[padNumber] or Vector3.new(0, 0, 0)
end

-- Cash collector debounce per player (tick of last collection).
local lastCollectTime: { [Player]: number } = {}
local COLLECT_DEBOUNCE = 0.5

-- Claim pad touch connections (cleaned up once a player claims).
local claimPadConnections: { [number]: RBXScriptConnection } = {}

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

-- ── Create the world terrain immediately (ground, roads, canyon walls) ────────
TycoonBuilder.CreateSharedWorld()

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
-- Income now accumulates into pendingCash instead of directly into balance.
-- Player must step on the CashCollector pad to collect.

IncomeManager.SetTickCallback(function(player: Player, amount: number)
	local state = tycoons[player]
	if not state then
		return
	end
	state.pendingCash += amount

	-- Send pending cash to client so collector pad label updates.
	Remotes.UpdatePendingCash:FireClient(player, state.pendingCash)

	-- Track quest progress for "earn" quests.
	QuestManager.OnIncome(player, amount)
end)

-- ── Cash Collector helper ────────────────────────────────────────────────────

local function collectPendingCash(player: Player)
	local state = tycoons[player]
	if not state or state.pendingCash <= 0 then
		return
	end

	-- Debounce: only collect once per COLLECT_DEBOUNCE seconds.
	local now = tick()
	local lastTime = lastCollectTime[player]
	if lastTime and (now - lastTime) < COLLECT_DEBOUNCE then
		return
	end
	lastCollectTime[player] = now

	local amount = state.pendingCash
	state.pendingCash = 0
	state.balance += amount

	fireUpdateMoney(player, state.balance)
	LeaderboardManager.UpdateCash(player, state.balance)
	Remotes.CollectCash:FireClient(player, amount)
	Remotes.UpdatePendingCash:FireClient(player, 0)
end

-- ── Setup Cash Collector touch detection for a claimed pad ───────────────────

local function setupCashCollector(padNumber: number, player: Player)
	local workspace = game:GetService("Workspace")
	local tycoonFolder = workspace:FindFirstChild("Tycoon_Pad_" .. tostring(padNumber))
	if not tycoonFolder then
		return
	end

	-- Look for CashCollector part inside the tycoon folder (any depth).
	local collector = tycoonFolder:FindFirstChild("CashCollector", true) :: BasePart?
	if not collector then
		return
	end

	collector.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent :: Model?
		if not character then
			return
		end
		local hitPlayer = Players:GetPlayerFromCharacter(character)
		if hitPlayer == player then
			collectPendingCash(player)
		end
	end)
end

-- ── Setup tycoon after claiming a pad ────────────────────────────────────────

local function setupTycoonForPlayer(player: Player, padNumber: number)
	-- Load persistent data
	local data = DataManager.LoadData(player)

	local state: TycoonState = {
		pad = padNumber,
		balance = data.balance,
		pendingCash = 0,
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

	-- Teleport the player to their claimed pad
	local padPos = padOrigin(padNumber)
	local padSpawnCF = CFrame.new(padPos + Vector3.new(0, 5, -15))

	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if rootPart then
		rootPart.CFrame = padSpawnCF
	end

	-- Respawn player on their pad if they fall below the map
	local function onCharacterAdded(newCharacter: Model)
		local hrp = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if hrp then
			hrp.CFrame = padSpawnCF
		end
		local humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.WalkSpeed = 32
			task.spawn(function()
				while humanoid and humanoid.Health > 0 do
					if hrp and hrp.Position.Y < -50 then
						hrp.CFrame = padSpawnCF
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
	local padCenter = CFrame.new(padPos)
	UnitManager.RegisterPad(padNumber, player, padCenter)

	-- Re-spawn all previously unlocked buildings
	for _, itemName in state.unlockedItems do
		TycoonBuilder.UnlockItem(padNumber, itemName, state.unlockedItems)
	end

	-- Units disabled — placeholder rectangles wandering around look bad.
	-- TODO: Replace with proper rigged soldier/vehicle models.

	-- Re-spawn drivable vehicles for previously unlocked vehicle buildings.
	for _, itemName in state.unlockedItems do
		local vehicleType = VehicleManager.GetBuildingVehicleType(itemName)
		if vehicleType then
			local buildingPos = TycoonBuilder.GetBuildingWorldPosition(padNumber, itemName)
			if buildingPos then
				VehicleManager.SpawnVehicle(player, vehicleType, buildingPos + Vector3.new(15, 0, 0))
			end
		end
	end

	-- Show the correct next purchase button
	TycoonBuilder.SpawnPurchaseButtons(padNumber, state.unlockedItems)

	-- Setup cash collector touch detection
	setupCashCollector(padNumber, player)

	-- Start income loop
	IncomeManager.StartIncome(player, state.incomePerSecond)

	-- Send initial state to the client
	fireUpdateMoney(player, state.balance)
	Remotes.UpdateIncome:FireClient(player, state.incomePerSecond)
	Remotes.UpdatePendingCash:FireClient(player, state.pendingCash)

	-- Register base with combat system
	task.defer(function()
		if _G.CombatAPI then
			_G.CombatAPI.RegisterBase(player, padNumber, state.unlockedItems)
		end
	end)

	-- Give the player their weapons (default + any unlocked by buildings)
	WeaponManager.GiveDefaultWeapon(player)
	WeaponManager.UpdateWeapons(player, state.unlockedItems)

	-- Daily rewards: check if player can claim
	DailyRewardManager.CheckAndShowReward(player, data)

	-- Daily quests: generate or restore quests for today
	QuestManager.Setup(player)

	-- Set initial quest level progress based on already unlocked items
	QuestManager.OnLevelChange(player, #state.unlockedItems)

	print(
		string.format(
			"[TycoonManager] %s claimed pad %d | $%d | %d ips",
			player.Name,
			padNumber,
			state.balance,
			state.incomePerSecond
		)
	)
end

-- ── Claim Pad helpers ────────────────────────────────────────────────────────

local function removeAllClaimPads()
	for padNum, conn in claimPadConnections do
		conn:Disconnect()
		claimPadConnections[padNum] = nil
	end
	-- Remove claim pad parts from workspace
	local workspace = game:GetService("Workspace")
	for i = 1, MAX_PADS do
		local claimPart = workspace:FindFirstChild("ClaimPad_" .. tostring(i))
		if claimPart then
			claimPart:Destroy()
		end
	end
end

local function createClaimPadsForPlayer(player: Player)
	local workspace = game:GetService("Workspace")

	for i = 1, MAX_PADS do
		if padInUse[i] then
			continue
		end

		-- Create claim pad via TycoonBuilder if available, otherwise build one here.
		local padPos = padOrigin(i)
		local claimPart = Instance.new("Part")
		claimPart.Name = "ClaimPad_" .. tostring(i)
		claimPart.Size = Vector3.new(20, 2, 20)
		claimPart.Position = padPos + Vector3.new(0, 1, 0)
		claimPart.Anchored = true
		claimPart.CanCollide = true
		claimPart.BrickColor = BrickColor.new("Lime green")
		claimPart.Material = Enum.Material.Neon

		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Face = Enum.NormalId.Top
		surfaceGui.Parent = claimPart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "TAP TO CLAIM"
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = surfaceGui

		claimPart.Parent = workspace

		-- Touch detection for this claim pad
		local conn = claimPart.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent :: Model?
			if not character then
				return
			end
			local hitPlayer = Players:GetPlayerFromCharacter(character)
			if not hitPlayer then
				return
			end
			-- Only allow players who don't already have a pad
			if tycoons[hitPlayer] then
				return
			end
			-- Only allow the specific player we created pads for (or any unclaimed player)
			if padInUse[i] then
				return
			end

			-- Claim this pad
			padInUse[i] = true

			-- Remove all claim pads for this player
			removeAllClaimPads()

			-- Re-create claim pads for other unclaimed players (if any)
			-- This is handled by other players' own claim pad sets

			-- Setup the tycoon
			setupTycoonForPlayer(hitPlayer, i)
		end)

		claimPadConnections[i] = conn
	end
end

-- ── Player join ───────────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	local hasFree = getFreePad() ~= nil
	if not hasFree then
		player:Kick("Server full — try again later.")
		return
	end

	LeaderboardManager.Setup(player)

	local spawnCF = CFrame.new(Vector3.new(0, 5, 0))
	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if rootPart then rootPart.CFrame = spawnCF end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.WalkSpeed = 32 end

	player.CharacterAdded:Connect(function(nc: Model)
		if tycoons[player] then return end
		local hrp = nc:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if hrp then hrp.CFrame = spawnCF end
		local hum = nc:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then hum.WalkSpeed = 32 end
	end)

	createClaimPadsForPlayer(player)
	print("[TycoonManager] " .. player.Name .. " joined — pick a base!")
end

-- ── Player leave ──────────────────────────────────────────────────────────────

local function onPlayerRemoving(player: Player)
	local state = tycoons[player]
	if not state then
		-- Player never claimed a pad; just clean up
		lastCollectTime[player] = nil
		return
	end

	-- Stop the income loop first so no more ticks fire
	IncomeManager.StopIncome(player)

	-- Collect any remaining pending cash into balance before saving
	if state.pendingCash > 0 then
		state.balance += state.pendingCash
		state.pendingCash = 0
	end

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

	-- Clean up daily reward, quest, and weapon state
	DailyRewardManager.OnPlayerRemoving(player)
	QuestManager.OnPlayerRemoving(player)
	WeaponManager.OnPlayerRemoving(player)

	-- Clean up vehicles, units, and the world
	VehicleManager.DespawnAllVehicles(player)
	UnitManager.DespawnAllUnits(state.pad)
	TycoonBuilder.CleanupTycoon(state.pad)

	-- Free the pad
	padInUse[state.pad] = false

	-- Clean up debounce tracking
	lastCollectTime[player] = nil

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

	-- Spawn a drivable vehicle if this building unlocks one.
	local vehicleType = VehicleManager.GetBuildingVehicleType(itemName)
	if vehicleType then
		local buildingPos = TycoonBuilder.GetBuildingWorldPosition(state.pad, itemName)
		if buildingPos then
			-- Spawn the vehicle offset to the side of the building
			local spawnPos = buildingPos + Vector3.new(15, 0, 0)
			VehicleManager.SpawnVehicle(player, vehicleType, spawnPos)
		end
	end

	-- Give any new weapons unlocked by this building
	WeaponManager.UpdateWeapons(player, state.unlockedItems)

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
		return { money = 0, income = 0, unlockedItems = {} }
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

-- ClaimTycoon remote handler (alternative to touch-based claiming)
Remotes.ClaimTycoon.OnServerEvent:Connect(function(player: Player, padNumber: unknown)
	-- Validate
	if tycoons[player] then
		return -- already claimed
	end
	if type(padNumber) ~= "number" then
		return
	end
	local padNum = math.floor(padNumber :: number)
	if padNum < 1 or padNum > MAX_PADS then
		return
	end
	if padInUse[padNum] then
		return
	end

	-- Claim the pad
	padInUse[padNum] = true
	removeAllClaimPads()
	setupTycoonForPlayer(player, padNum)
end)

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
