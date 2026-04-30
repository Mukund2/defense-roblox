--!strict
-- LeaderboardManager.luau
-- ModuleScript that creates and updates the standard Roblox leaderstats
-- folder on each player, exposing Cash, Income, and Level columns on
-- the in-game leaderboard.

local LeaderboardManager = {}

--- Creates the leaderstats folder and its value children for the given player.
function LeaderboardManager.Setup(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = leaderstats

	local income = Instance.new("IntValue")
	income.Name = "Income"
	income.Value = 0
	income.Parent = leaderstats

	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = 1
	level.Parent = leaderstats
end

--- Updates the Cash leaderstat for the given player.
function LeaderboardManager.UpdateCash(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local cash = leaderstats:FindFirstChild("Cash") :: IntValue?
	if cash then
		cash.Value = amount
	end
end

--- Updates the Income leaderstat for the given player.
function LeaderboardManager.UpdateIncome(player: Player, rate: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local incomeVal = leaderstats:FindFirstChild("Income") :: IntValue?
	if incomeVal then
		incomeVal.Value = rate
	end
end

--- Updates the Level leaderstat for the given player.
function LeaderboardManager.UpdateLevel(player: Player, level: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local levelVal = leaderstats:FindFirstChild("Level") :: IntValue?
	if levelVal then
		levelVal.Value = level
	end
end

return LeaderboardManager
