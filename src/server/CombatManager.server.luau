--!strict

--[[
	CombatManager.server.luau
	-------------------------
	Server-side combat orchestrator. Handles attack requests, damage calculation,
	shield management, base HP, and destruction/respawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig")) :: any
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) :: any
local TycoonConfig = require(ReplicatedStorage:WaitForChild("TycoonConfig")) :: any

-- ── Types ────────────────────────────────────────────────────────────────────

type BaseState = {
	player: Player,
	padNumber: number,
	hp: number,
	maxHP: number,
	shield: number,
	maxShield: number,
	lastHitTime: number,
	destroyed: boolean,
	cooldowns: { [string]: number }, -- attackType → timestamp of last use
	unlockedItems: { string },
}

-- ── State ────────────────────────────────────────────────────────────────────

local bases: { [number]: BaseState } = {} -- keyed by pad number
local playerToPad: { [Player]: number } = {}

-- ── Public API (called by TycoonManager) ────────────────────────────────────

local CombatAPI = {}

function CombatAPI.RegisterBase(player: Player, padNumber: number, unlockedItems: { string })
	local maxHP = CombatConfig.calculateMaxHP(unlockedItems)
	local maxShield = CombatConfig.calculateMaxShield(unlockedItems)

	bases[padNumber] = {
		player = player,
		padNumber = padNumber,
		hp = maxHP,
		maxHP = maxHP,
		shield = maxShield,
		maxShield = maxShield,
		lastHitTime = 0,
		destroyed = false,
		cooldowns = {},
		unlockedItems = unlockedItems,
	}
	playerToPad[player] = padNumber

	-- Send initial HP/shield to client
	Remotes.BaseDamaged:FireClient(player, maxHP, maxHP, 0, "")
	if maxShield > 0 then
		Remotes.UpdateShield:FireClient(player, maxShield, maxShield)
	end
end

function CombatAPI.UnregisterBase(player: Player)
	local pad = playerToPad[player]
	if pad then
		bases[pad] = nil
	end
	playerToPad[player] = nil
end

function CombatAPI.OnBuildingUnlocked(player: Player, unlockedItems: { string })
	local pad = playerToPad[player]
	if not pad then
		return
	end
	local base = bases[pad]
	if not base then
		return
	end

	base.unlockedItems = unlockedItems
	local newMaxHP = CombatConfig.calculateMaxHP(unlockedItems)
	local newMaxShield = CombatConfig.calculateMaxShield(unlockedItems)

	-- Heal proportionally when max HP increases
	local hpRatio = if base.maxHP > 0 then base.hp / base.maxHP else 1
	base.maxHP = newMaxHP
	base.hp = math.floor(hpRatio * newMaxHP)

	base.maxShield = newMaxShield
	base.shield = math.min(base.shield, newMaxShield)

	Remotes.BaseDamaged:FireClient(player, base.hp, base.maxHP, 0, "")
	if newMaxShield > 0 then
		Remotes.UpdateShield:FireClient(player, base.shield, base.maxShield)
	end
end

-- ── Internal: Damage Calculation ─────────────────────────────────────────────

local function applyDamage(targetBase: BaseState, rawDamage: number, attackType: string): number
	if targetBase.destroyed then
		return 0
	end

	local damage = rawDamage

	-- Anti-air defense reduces AirStrike damage
	if attackType == "AirStrike" then
		local antiAir = CombatConfig.calculateAntiAir(targetBase.unlockedItems)
		damage = damage * (1 - antiAir / 100)
	end

	-- Missile intercept chance
	if attackType == "MissileStrike" then
		local interceptChance = CombatConfig.calculateMissileIntercept(targetBase.unlockedItems)
		if math.random() < interceptChance then
			-- Intercepted! No damage
			return 0
		end
	end

	damage = math.floor(damage)

	-- Shield absorbs damage first
	if targetBase.shield > 0 then
		local shieldAbsorb = math.min(targetBase.shield, damage)
		targetBase.shield -= shieldAbsorb
		damage -= shieldAbsorb
		Remotes.UpdateShield:FireClient(targetBase.player, targetBase.shield, targetBase.maxShield)
	end

	-- Remaining damage hits HP
	if damage > 0 then
		targetBase.hp = math.max(0, targetBase.hp - damage)
	end

	targetBase.lastHitTime = os.clock()

	-- Notify target
	Remotes.BaseDamaged:FireClient(
		targetBase.player,
		targetBase.hp,
		targetBase.maxHP,
		rawDamage,
		attackType
	)

	-- Check for destruction
	if targetBase.hp <= 0 then
		targetBase.destroyed = true
		Remotes.BaseDestroyed:FireClient(targetBase.player, "enemy")

		-- Respawn after delay
		task.delay(CombatConfig.BASE_RESPAWN_TIME, function()
			if bases[targetBase.padNumber] and bases[targetBase.padNumber].destroyed then
				targetBase.hp = targetBase.maxHP
				targetBase.shield = targetBase.maxShield
				targetBase.destroyed = false
				Remotes.BaseDamaged:FireClient(targetBase.player, targetBase.hp, targetBase.maxHP, 0, "")
				Remotes.UpdateShield:FireClient(targetBase.player, targetBase.shield, targetBase.maxShield)
			end
		end)
	end

	return rawDamage -- return raw damage for reward calculation
end

-- ── Shield Regeneration Loop ─────────────────────────────────────────────────

task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, base in bases do
			if not base.destroyed and base.shield < base.maxShield then
				if (now - base.lastHitTime) >= CombatConfig.SHIELD_REGEN_DELAY then
					base.shield = math.min(base.maxShield, base.shield + CombatConfig.SHIELD_REGEN_RATE)
					Remotes.UpdateShield:FireClient(base.player, base.shield, base.maxShield)
				end
			end
		end
	end
end)

-- ── Attack Request Handler ───────────────────────────────────────────────────

local function onLaunchAttack(attacker: Player, attackType: string, targetPadNumber: number)
	local attackerPad = playerToPad[attacker]
	if not attackerPad then
		Remotes.AttackResult:FireClient(attacker, false, "You don't have a base.")
		return
	end

	local attackerBase = bases[attackerPad]
	if not attackerBase or attackerBase.destroyed then
		Remotes.AttackResult:FireClient(attacker, false, "Your base is destroyed.")
		return
	end

	-- Validate attack type
	local spec = CombatConfig.Attacks[attackType]
	if not spec then
		Remotes.AttackResult:FireClient(attacker, false, "Invalid attack type.")
		return
	end

	-- Can't attack own base
	if targetPadNumber == attackerPad then
		Remotes.AttackResult:FireClient(attacker, false, "Cannot attack your own base!")
		return
	end

	-- Validate target exists
	local targetBase = bases[targetPadNumber]
	if not targetBase then
		Remotes.AttackResult:FireClient(attacker, false, "No base at that location.")
		return
	end

	if targetBase.destroyed then
		Remotes.AttackResult:FireClient(attacker, false, "Target base is already destroyed.")
		return
	end

	-- Check required building
	local hasBuilding = false
	for _, item in attackerBase.unlockedItems do
		if item == spec.requiredBuilding then
			hasBuilding = true
			break
		end
	end
	if not hasBuilding then
		local itemConfig = TycoonConfig.Items[spec.requiredBuilding]
		local buildingName = if itemConfig then itemConfig.name else spec.requiredBuilding
		Remotes.AttackResult:FireClient(attacker, false, "Requires " .. buildingName .. "!")
		return
	end

	-- Check cooldown
	local now = os.clock()
	local lastUsed = attackerBase.cooldowns[attackType] or 0
	local remaining = spec.cooldown - (now - lastUsed)
	if remaining > 0 then
		Remotes.AttackResult:FireClient(attacker, false, string.format("Cooldown: %ds remaining", math.ceil(remaining)))
		return
	end

	-- Check funds (use TycoonManager's state via a callback)
	-- We'll fire a BindableEvent to check/deduct funds
	local fundsOk = false
	if _G.CombatDeductFunds then
		fundsOk = _G.CombatDeductFunds(attacker, spec.cost)
	end
	if not fundsOk then
		Remotes.AttackResult:FireClient(attacker, false, "Insufficient funds! ($" .. tostring(spec.cost) .. " needed)")
		return
	end

	-- Set cooldown
	attackerBase.cooldowns[attackType] = now

	-- Calculate warning time (target's radar bonus adds extra warning)
	local radarBonus = CombatConfig.calculateRadarBonus(targetBase.unlockedItems)
	local warningTime = spec.warningTime + radarBonus

	-- Warn the target
	Remotes.AttackWarning:FireClient(targetBase.player, attackType, attacker.Name, warningTime + spec.travelTime)

	-- Notify ALL clients about the attack for visual effects
	for _, player in Players:GetPlayers() do
		Remotes.AttackLaunched:FireClient(player, attackType, attackerPad, targetPadNumber, spec.travelTime)
	end

	-- Confirm to attacker
	Remotes.AttackResult:FireClient(attacker, true, spec.name .. " launched!")

	-- Apply damage after travel time
	task.delay(spec.travelTime, function()
		if not bases[targetPadNumber] then
			return
		end
		local dealt = applyDamage(targetBase, spec.damage, attackType)

		-- Reward attacker
		if dealt > 0 and _G.CombatRewardFunds then
			local reward = math.floor(dealt * CombatConfig.ATTACK_REWARD_MULTIPLIER * spec.cost)
			if reward > 0 then
				_G.CombatRewardFunds(attacker, reward)
			end
		end

		print(string.format(
			"[Combat] %s's %s hit %s's base for %d damage (HP: %d/%d)",
			attacker.Name, spec.name, targetBase.player.Name,
			dealt, targetBase.hp, targetBase.maxHP
		))
	end)

	print(string.format(
		"[Combat] %s launched %s at pad %d (cost: $%d, ETA: %ds)",
		attacker.Name, spec.name, targetPadNumber, spec.cost, spec.travelTime
	))
end

-- ── Wire up events ───────────────────────────────────────────────────────────

Remotes.LaunchAttack.OnServerEvent:Connect(onLaunchAttack)

-- Expose API globally for TycoonManager to call
_G.CombatAPI = CombatAPI
