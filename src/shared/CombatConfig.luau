--!strict

--[[
	CombatConfig.luau
	-----------------
	Single source of truth for all combat-related constants: attack types,
	damage values, cooldowns, defense stats, and base HP calculations.
]]

export type AttackType = "AirStrike" | "MissileStrike" | "NavalBombardment" | "GroundAssault"

export type AttackSpec = {
	name: string,
	attackType: AttackType,
	damage: number,
	cost: number, -- cash cost to launch
	cooldown: number, -- seconds between uses
	requiredBuilding: string, -- modelName from TycoonConfig that must be unlocked
	travelTime: number, -- seconds for projectile to reach target
	description: string,
	warningTime: number, -- seconds of warning before impact
}

export type DefenseBonus = {
	baseHP: number, -- HP added to base when this building is unlocked
	shieldBonus: number, -- shield points added
	antiAirRating: number, -- % reduction to air attack damage (0-100)
	missileInterceptChance: number, -- chance to intercept incoming missiles (0-1)
	radarRange: number, -- extra warning time in seconds (0 = none)
}

-- ── Attack Definitions ───────────────────────────────────────────────────────

local Attacks: { [AttackType]: AttackSpec } = {
	GroundAssault = {
		name = "Ground Assault",
		attackType = "GroundAssault",
		damage = 10,
		cost = 200,
		cooldown = 30,
		requiredBuilding = "Barracks",
		travelTime = 8,
		description = "Deploy infantry and ground forces to raid an enemy base.",
		warningTime = 5,
	},
	AirStrike = {
		name = "Air Strike",
		attackType = "AirStrike",
		damage = 25,
		cost = 2_000,
		cooldown = 45,
		requiredBuilding = "FighterJetHangar",
		travelTime = 4,
		description = "Scramble fighter jets to bomb an enemy base from above.",
		warningTime = 3,
	},
	NavalBombardment = {
		name = "Naval Bombardment",
		attackType = "NavalBombardment",
		damage = 35,
		cost = 5_000,
		cooldown = 60,
		requiredBuilding = "AircraftCarrierDock",
		travelTime = 6,
		description = "Rain shells from your carrier group onto an enemy position.",
		warningTime = 4,
	},
	MissileStrike = {
		name = "Missile Strike",
		attackType = "MissileStrike",
		damage = 60,
		cost = 15_000,
		cooldown = 120,
		requiredBuilding = "NuclearSilo",
		travelTime = 5,
		description = "Launch an ICBM at the enemy base. Devastating but expensive.",
		warningTime = 6,
	},
}

-- ── Defense Stats Per Building ───────────────────────────────────────────────
-- Keyed by modelName from TycoonConfig.

local DefenseStats: { [string]: DefenseBonus } = {
	CommandCenter = { baseHP = 100, shieldBonus = 0, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	Barracks = { baseHP = 30, shieldBonus = 0, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	MotorPool = { baseHP = 25, shieldBonus = 0, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	RadarStation = { baseHP = 15, shieldBonus = 0, antiAirRating = 0, missileInterceptChance = 0, radarRange = 5 },
	SAMSite = { baseHP = 20, shieldBonus = 10, antiAirRating = 50, missileInterceptChance = 0, radarRange = 0 },
	Helipad = { baseHP = 20, shieldBonus = 0, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	Armory = { baseHP = 30, shieldBonus = 15, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	TankDepot = { baseHP = 40, shieldBonus = 10, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	DroneHangar = { baseHP = 25, shieldBonus = 0, antiAirRating = 20, missileInterceptChance = 0, radarRange = 3 },
	FighterJetHangar = { baseHP = 35, shieldBonus = 0, antiAirRating = 30, missileInterceptChance = 0, radarRange = 0 },
	SubmarinePen = { baseHP = 40, shieldBonus = 20, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	AircraftCarrierDock = { baseHP = 50, shieldBonus = 15, antiAirRating = 20, missileInterceptChance = 0, radarRange = 0 },
	StealthBomberBay = { baseHP = 35, shieldBonus = 0, antiAirRating = 0, missileInterceptChance = 0, radarRange = 0 },
	NuclearSilo = { baseHP = 60, shieldBonus = 25, antiAirRating = 0, missileInterceptChance = 0.3, radarRange = 0 },
	SpaceCommand = { baseHP = 80, shieldBonus = 50, antiAirRating = 40, missileInterceptChance = 0.5, radarRange = 10 },
}

-- ── Constants ────────────────────────────────────────────────────────────────

local BASE_HP = 100 -- starting HP (CommandCenter)
local SHIELD_REGEN_RATE = 2 -- shield points recovered per second when not under attack
local SHIELD_REGEN_DELAY = 10 -- seconds after last hit before shield starts regenerating
local BASE_RESPAWN_TIME = 30 -- seconds to rebuild after destruction
local DESTRUCTION_CASH_PENALTY = 0.25 -- lose 25% of cash when base is destroyed
local ATTACK_REWARD_MULTIPLIER = 0.1 -- attacker gets 10% of damage dealt as cash

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function calculateMaxHP(unlockedItems: { string }): number
	local total = 0
	for _, itemName in unlockedItems do
		local stats = DefenseStats[itemName]
		if stats then
			total += stats.baseHP
		end
	end
	return math.max(total, BASE_HP)
end

local function calculateMaxShield(unlockedItems: { string }): number
	local total = 0
	for _, itemName in unlockedItems do
		local stats = DefenseStats[itemName]
		if stats then
			total += stats.shieldBonus
		end
	end
	return total
end

local function calculateAntiAir(unlockedItems: { string }): number
	local best = 0
	for _, itemName in unlockedItems do
		local stats = DefenseStats[itemName]
		if stats and stats.antiAirRating > best then
			best = stats.antiAirRating
		end
	end
	return best
end

local function calculateMissileIntercept(unlockedItems: { string }): number
	local best = 0
	for _, itemName in unlockedItems do
		local stats = DefenseStats[itemName]
		if stats and stats.missileInterceptChance > best then
			best = stats.missileInterceptChance
		end
	end
	return best
end

local function calculateRadarBonus(unlockedItems: { string }): number
	local best = 0
	for _, itemName in unlockedItems do
		local stats = DefenseStats[itemName]
		if stats and stats.radarRange > best then
			best = stats.radarRange
		end
	end
	return best
end

-- ── Module ───────────────────────────────────────────────────────────────────

return table.freeze({
	Attacks = table.freeze(Attacks),
	DefenseStats = table.freeze(DefenseStats),

	BASE_HP = BASE_HP,
	SHIELD_REGEN_RATE = SHIELD_REGEN_RATE,
	SHIELD_REGEN_DELAY = SHIELD_REGEN_DELAY,
	BASE_RESPAWN_TIME = BASE_RESPAWN_TIME,
	DESTRUCTION_CASH_PENALTY = DESTRUCTION_CASH_PENALTY,
	ATTACK_REWARD_MULTIPLIER = ATTACK_REWARD_MULTIPLIER,

	calculateMaxHP = calculateMaxHP,
	calculateMaxShield = calculateMaxShield,
	calculateAntiAir = calculateAntiAir,
	calculateMissileIntercept = calculateMissileIntercept,
	calculateRadarBonus = calculateRadarBonus,
})
