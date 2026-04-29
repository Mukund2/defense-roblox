--!strict

local DataStoreService = game:GetService("DataStoreService")

local DATASTORE_NAME = "MilitaryBaseTycoon_v1"
local MAX_RETRIES = 3
local RETRY_DELAY = 1

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

export type PlayerData = {
	balance: number,
	incomePerSecond: number,
	unlockedItems: { string },
	totalEarned: number,
}

local DEFAULT_DATA: PlayerData = {
	balance = 0,
	incomePerSecond = 5,
	unlockedItems = { "CommandCenter" },
	totalEarned = 0,
}

local function deepCopy(original: { [string]: any }): { [string]: any }
	local copy: { [string]: any } = {}
	for key, value in original do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local DataManager = {}

function DataManager.LoadData(player: Player): PlayerData
	local key = "player_" .. tostring(player.UserId)
	local result: PlayerData? = nil
	local success = false

	for attempt = 1, MAX_RETRIES do
		local ok, data = pcall(function()
			return dataStore:GetAsync(key)
		end)

		if ok then
			success = true
			if data ~= nil then
				-- Merge saved data onto default so new fields are always present
				local merged = deepCopy(DEFAULT_DATA) :: PlayerData
				if data.balance ~= nil then
					merged.balance = data.balance
				end
				if data.incomePerSecond ~= nil then
					merged.incomePerSecond = data.incomePerSecond
				end
				if data.unlockedItems ~= nil then
					merged.unlockedItems = data.unlockedItems
				end
				if data.totalEarned ~= nil then
					merged.totalEarned = data.totalEarned
				end
				result = merged
			end
			break
		else
			warn(
				string.format(
					"[DataManager] LoadData attempt %d failed for %s: %s",
					attempt,
					player.Name,
					tostring(data)
				)
			)
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY)
			end
		end
	end

	if not success then
		warn("[DataManager] All load attempts failed for " .. player.Name .. ". Using default data.")
	end

	return result or deepCopy(DEFAULT_DATA) :: PlayerData
end

function DataManager.SaveData(player: Player, data: PlayerData): boolean
	local key = "player_" .. tostring(player.UserId)

	-- Snapshot the data table so the UpdateAsync transform closure captures a stable copy
	local snapshot: PlayerData = {
		balance = data.balance,
		incomePerSecond = data.incomePerSecond,
		unlockedItems = table.clone(data.unlockedItems),
		totalEarned = data.totalEarned,
	}

	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(_oldData: any)
				return snapshot
			end)
		end)

		if ok then
			return true
		else
			warn(
				string.format(
					"[DataManager] SaveData attempt %d failed for %s: %s",
					attempt,
					player.Name,
					tostring(err)
				)
			)
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY)
			end
		end
	end

	warn("[DataManager] All save attempts failed for " .. player.Name)
	return false
end

return DataManager
