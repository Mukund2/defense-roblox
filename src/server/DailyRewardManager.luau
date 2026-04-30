--!strict

--[[
	DailyRewardManager.luau
	-----------------------
	Handles daily login reward streaks.  Stores lastDailyReward (unix timestamp)
	and dailyStreak (1-7) inside the player's DataStore entry via DataManager.

	The server checks on join whether 24+ hours have elapsed since the last
	claim.  If so it fires ShowDailyReward to the client.  When the client
	clicks CLAIM the server validates again, awards cash, and updates the
	streak/timestamp.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent.DataManager) :: any
local Remotes = require(ReplicatedStorage.Remotes) :: any

-- ── Reward table (day 1-7, repeats) ─────────────────────────────────────────

local REWARDS: { number } = { 500, 1000, 2000, 3000, 5000, 8000, 15000 }
local STREAK_LENGTH = 7
local COOLDOWN_SECONDS = 24 * 60 * 60 -- 24 hours

-- ── State ───────────────────────────────────────────────────────────────────

-- In-memory cache so we don't hit the DataStore on every claim check.
local cache: { [Player]: { lastClaim: number, streak: number } } = {}

-- Callback that TycoonManager sets so we can award cash through the canonical path.
local addCashCallback: ((player: Player, amount: number) -> ())?

-- ── Module ──────────────────────────────────────────────────────────────────

local DailyRewardManager = {}

--- TycoonManager calls this once at init to provide the "give cash" function.
function DailyRewardManager.SetAddCashCallback(cb: (player: Player, amount: number) -> ())
	addCashCallback = cb
end

--- Called from onPlayerAdded (after data is loaded).
--- `data` is the full PlayerData table returned by DataManager.LoadData.
function DailyRewardManager.CheckAndShowReward(player: Player, data: any)
	local lastClaim: number = data.lastDailyReward or 0
	local streak: number = data.dailyStreak or 0

	cache[player] = { lastClaim = lastClaim, streak = streak }

	local now = os.time()
	local elapsed = now - lastClaim
	local canClaim = elapsed >= COOLDOWN_SECONDS

	-- Determine which day to show (1-indexed).
	local displayDay = streak -- last completed day
	if canClaim then
		-- Next day in cycle (wraps after 7).
		displayDay = (streak % STREAK_LENGTH) + 1
	end

	local rewardAmount = REWARDS[displayDay] or REWARDS[1]

	-- Always show the calendar so the player sees their streak,
	-- but only enable the CLAIM button when canClaim is true.
	task.delay(2, function()
		if player.Parent then -- still in game
			Remotes.ShowDailyReward:FireClient(player, displayDay, rewardAmount, canClaim)
		end
	end)
end

--- Called when the client fires ClaimDailyReward.
function DailyRewardManager.ClaimReward(player: Player)
	local entry = cache[player]
	if not entry then
		return
	end

	local now = os.time()
	local elapsed = now - entry.lastClaim

	if elapsed < COOLDOWN_SECONDS then
		warn("[DailyRewardManager] " .. player.Name .. " tried to claim too early.")
		return
	end

	-- Advance streak (wrap after 7).
	local newStreak = (entry.streak % STREAK_LENGTH) + 1
	local reward = REWARDS[newStreak] or REWARDS[1]

	-- Update cache
	entry.lastClaim = now
	entry.streak = newStreak

	-- Persist to DataStore via DataManager
	-- We piggy-back onto the player's existing data key.
	local ok, err = pcall(function()
		local DataStoreService = game:GetService("DataStoreService")
		local ds = DataStoreService:GetDataStore("MilitaryBaseTycoon_v1")
		local key = "player_" .. tostring(player.UserId)
		ds:UpdateAsync(key, function(old: any)
			if old == nil then
				old = {}
			end
			old.lastDailyReward = now
			old.dailyStreak = newStreak
			return old
		end)
	end)
	if not ok then
		warn("[DailyRewardManager] Failed to persist daily reward for " .. player.Name .. ": " .. tostring(err))
	end

	-- Award cash through TycoonManager's canonical path.
	if addCashCallback then
		addCashCallback(player, reward)
	end

	-- Notify client.
	Remotes.DailyRewardClaimed:FireClient(player, reward)

	print(string.format("[DailyRewardManager] %s claimed day %d reward: $%d", player.Name, newStreak, reward))
end

--- Returns the current daily reward data for save purposes.
function DailyRewardManager.GetData(player: Player): (number, number)
	local entry = cache[player]
	if entry then
		return entry.lastClaim, entry.streak
	end
	return 0, 0
end

--- Cleanup on player leave.
function DailyRewardManager.OnPlayerRemoving(player: Player)
	cache[player] = nil
end

return DailyRewardManager
