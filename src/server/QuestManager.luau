--!strict

--[[
	QuestManager.luau
	-----------------
	Generates 3 daily quests per player.  Quests reset every calendar day
	(UTC).  Progress is tracked in-memory during the session.  Completed
	quests can be claimed for a cash reward.

	Quest types:
		1. "earn"     — accumulate $X of income this session
		2. "buy"      — purchase N buildings this session
		3. "level"    — reach base level N (total unlocked items)

	TycoonManager calls OnIncome / OnPurchase / OnLevelChange whenever the
	relevant event occurs.  This module updates progress and fires
	UpdateQuests to the client.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Remotes) :: any

-- ── Types ───────────────────────────────────────────────────────────────────

export type Quest = {
	questType: string, -- "earn" | "buy" | "level"
	description: string,
	target: number,
	progress: number,
	reward: number,
	claimed: boolean,
}

-- ── Quest templates ─────────────────────────────────────────────────────────

type QuestTemplate = {
	questType: string,
	descriptionFmt: string, -- use %s for the formatted target
	targets: { number },
	rewards: { number },
}

local TEMPLATES: { QuestTemplate } = {
	{
		questType = "earn",
		descriptionFmt = "Earn %s from income",
		targets = { 2000, 5000, 10000, 20000, 50000 },
		rewards = { 1000, 2000, 3000, 4000, 5000 },
	},
	{
		questType = "buy",
		descriptionFmt = "Purchase %s buildings",
		targets = { 1, 2, 3, 5 },
		rewards = { 1000, 2000, 3000, 5000 },
	},
	{
		questType = "level",
		descriptionFmt = "Reach base level %s",
		targets = { 3, 5, 7, 10, 13 },
		rewards = { 1500, 2500, 3500, 4500, 5000 },
	},
}

-- ── State ───────────────────────────────────────────────────────────────────

local playerQuests: { [Player]: { Quest } } = {}
local playerSeed: { [Player]: number } = {} -- deterministic per UTC day

-- Callback for awarding cash.
local addCashCallback: ((player: Player, amount: number) -> ())?

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function utcDay(): number
	return math.floor(os.time() / 86400)
end

--- Simple seeded pseudo-random to pick quest variants deterministically per
--- player per day so reconnecting gives the same quests.
local function seededRandom(seed: number, min: number, max: number): number
	-- LCG-style hash; good enough for quest selection.
	local hash = (seed * 1103515245 + 12345) % 2147483648
	return min + (hash % (max - min + 1))
end

local function formatTarget(questType: string, target: number): string
	if questType == "earn" then
		return "$" .. tostring(target)
	end
	return tostring(target)
end

local function generateQuests(player: Player): { Quest }
	local day = utcDay()
	local baseSeed = day * 100000 + player.UserId

	local quests: { Quest } = {}

	-- Pick one quest per type to guarantee variety.
	for i, template in TEMPLATES do
		local seed = baseSeed + i
		local idx = seededRandom(seed, 1, #template.targets)
		local target = template.targets[idx]
		local reward = template.rewards[idx]

		local desc = string.format(template.descriptionFmt, formatTarget(template.questType, target))

		table.insert(quests, {
			questType = template.questType,
			description = desc,
			target = target,
			progress = 0,
			reward = reward,
			claimed = false,
		})
	end

	return quests
end

local function sendUpdate(player: Player)
	local quests = playerQuests[player]
	if not quests then
		return
	end

	-- Serialize for the remote.
	local payload: { any } = {}
	for _, q in quests do
		table.insert(payload, {
			questType = q.questType,
			description = q.description,
			target = q.target,
			progress = q.progress,
			reward = q.reward,
			claimed = q.claimed,
		})
	end

	Remotes.UpdateQuests:FireClient(player, payload)
end

-- ── Module ──────────────────────────────────────────────────────────────────

local QuestManager = {}

function QuestManager.SetAddCashCallback(cb: (player: Player, amount: number) -> ())
	addCashCallback = cb
end

--- Called from onPlayerAdded after data is loaded.
function QuestManager.Setup(player: Player)
	playerSeed[player] = utcDay()
	playerQuests[player] = generateQuests(player)

	-- Send initial state after a small delay so the client GUI is ready.
	task.delay(3, function()
		if player.Parent then
			sendUpdate(player)
		end
	end)
end

--- Called whenever the player earns income (per tick).
function QuestManager.OnIncome(player: Player, amount: number)
	local quests = playerQuests[player]
	if not quests then
		return
	end

	local changed = false
	for _, q in quests do
		if q.questType == "earn" and not q.claimed then
			q.progress = math.min(q.progress + amount, q.target)
			changed = true
		end
	end

	if changed then
		sendUpdate(player)
	end
end

--- Called whenever the player purchases a building.
function QuestManager.OnPurchase(player: Player)
	local quests = playerQuests[player]
	if not quests then
		return
	end

	local changed = false
	for _, q in quests do
		if q.questType == "buy" and not q.claimed then
			q.progress = math.min(q.progress + 1, q.target)
			changed = true
		end
	end

	if changed then
		sendUpdate(player)
	end
end

--- Called when the player's base level (unlocked item count) changes.
function QuestManager.OnLevelChange(player: Player, level: number)
	local quests = playerQuests[player]
	if not quests then
		return
	end

	local changed = false
	for _, q in quests do
		if q.questType == "level" and not q.claimed then
			q.progress = math.min(level, q.target)
			changed = true
		end
	end

	if changed then
		sendUpdate(player)
	end
end

--- Called when the client fires ClaimQuestReward with a quest index (1-3).
function QuestManager.ClaimReward(player: Player, questIndex: number)
	local quests = playerQuests[player]
	if not quests then
		return
	end

	if type(questIndex) ~= "number" or questIndex < 1 or questIndex > #quests then
		warn("[QuestManager] Invalid quest index from " .. player.Name .. ": " .. tostring(questIndex))
		return
	end

	local q = quests[questIndex]
	if q.claimed then
		warn("[QuestManager] " .. player.Name .. " tried to re-claim quest " .. tostring(questIndex))
		return
	end

	if q.progress < q.target then
		warn("[QuestManager] " .. player.Name .. " tried to claim incomplete quest " .. tostring(questIndex))
		return
	end

	q.claimed = true

	-- Award cash.
	if addCashCallback then
		addCashCallback(player, q.reward)
	end

	-- Notify client.
	Remotes.QuestCompleted:FireClient(player, questIndex, q.reward)
	sendUpdate(player)

	print(string.format("[QuestManager] %s claimed quest %d reward: $%d", player.Name, questIndex, q.reward))
end

--- Cleanup on player leave.
function QuestManager.OnPlayerRemoving(player: Player)
	playerQuests[player] = nil
	playerSeed[player] = nil
end

return QuestManager
