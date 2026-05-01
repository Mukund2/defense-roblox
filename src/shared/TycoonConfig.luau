--!strict

export type TycoonItemCategory = "Building" | "Vehicle" | "Aircraft" | "Naval" | "Strategic"

export type TycoonItem = {
	name: string,
	cost: number,
	incomePerSecond: number,
	description: string,
	modelName: string,
	category: TycoonItemCategory,
	order: number,
}

export type TycoonConfigType = {
	Items: { [string]: TycoonItem },
	Ordered: { TycoonItem },
}

local Items: { [string]: TycoonItem } = {
	CommandCenter = {
		name = "Command Center",
		cost = 100,
		incomePerSecond = 5,
		description = "The heart of your military base. All operations route through here.",
		modelName = "CommandCenter",
		category = "Building",
		order = 1,
	},
	Barracks = {
		name = "Barracks",
		cost = 500,
		incomePerSecond = 3,
		description = "Sleeping quarters and training facilities for your infantry forces. Unlocks ground troop deployment.",
		modelName = "Barracks",
		category = "Building",
		order = 2,
	},
	MotorPool = {
		name = "Motor Pool",
		cost = 1_500,
		incomePerSecond = 5,
		description = "Vehicle depot for light wheeled assets. Unlocks Humvee patrol units.",
		modelName = "MotorPool",
		category = "Building",
		order = 3,
	},
	RadarStation = {
		name = "Radar Station",
		cost = 3_000,
		incomePerSecond = 4,
		description = "Long-range surveillance array. Provides early-warning detection across the entire base perimeter.",
		modelName = "RadarStation",
		category = "Building",
		order = 4,
	},
	SAMSite = {
		name = "SAM Site",
		cost = 5_000,
		incomePerSecond = 8,
		description = "Surface-to-Air Missile battery. Provides a layered anti-air defense envelope over the base.",
		modelName = "SAMSite",
		category = "Building",
		order = 5,
	},
	Helipad = {
		name = "Helipad",
		cost = 10_000,
		incomePerSecond = 12,
		description = "Reinforced landing platform and refueling station. Unlocks the AH-64 Apache attack helicopter.",
		modelName = "Helipad",
		category = "Building",
		order = 6,
	},
	Armory = {
		name = "Armory",
		cost = 15_000,
		incomePerSecond = 10,
		description = "Secure weapons and ammunition storage vault. Boosts operational readiness across all units.",
		modelName = "Armory",
		category = "Building",
		order = 7,
	},
	TankDepot = {
		name = "Tank Depot",
		cost = 25_000,
		incomePerSecond = 18,
		description = "Heavy armor maintenance and staging facility. Unlocks the M1 Abrams main battle tank.",
		modelName = "TankDepot",
		category = "Building",
		order = 8,
	},
	DroneHangar = {
		name = "Drone Hangar",
		cost = 40_000,
		incomePerSecond = 25,
		description = "Unmanned aerial vehicle operations center. Unlocks the MQ-9 Reaper long-range strike drone.",
		modelName = "DroneHangar",
		category = "Building",
		order = 9,
	},
	FighterJetHangar = {
		name = "Fighter Jet Hangar",
		cost = 75_000,
		incomePerSecond = 40,
		description = "Full-spectrum air superiority facility. Unlocks the F-22 Raptor stealth air superiority fighter.",
		modelName = "FighterJetHangar",
		category = "Building",
		order = 10,
	},
	SubmarinePen = {
		name = "Submarine Pen",
		cost = 120_000,
		incomePerSecond = 55,
		description = "Hardened underground submarine berth. Unlocks the Virginia-class fast-attack submarine.",
		modelName = "SubmarinePen",
		category = "Naval",
		order = 11,
	},
	AircraftCarrierDock = {
		name = "Aircraft Carrier Dock",
		cost = 200_000,
		incomePerSecond = 80,
		description = "Deep-water naval installation. Unlocks the Nimitz-class supercarrier — mobile sovereign territory.",
		modelName = "AircraftCarrierDock",
		category = "Naval",
		order = 12,
	},
	StealthBomberBay = {
		name = "Stealth Bomber Bay",
		cost = 350_000,
		incomePerSecond = 100,
		description = "Climate-controlled precision hangar for low-observable strategic assets. Unlocks the B-2 Spirit bomber.",
		modelName = "StealthBomberBay",
		category = "Building",
		order = 13,
	},
	NuclearSilo = {
		name = "Nuclear Silo",
		cost = 500_000,
		incomePerSecond = 150,
		description = "Hardened ICBM launch facility buried beneath the base. The ultimate deterrent. Handle with care.",
		modelName = "NuclearSilo",
		category = "Strategic",
		order = 14,
	},
	SpaceCommand = {
		name = "Space Command",
		cost = 1_000_000,
		incomePerSecond = 200,
		description = "Orbital operations center commanding a constellation of military satellites. Final tier — true global dominance.",
		modelName = "SpaceCommand",
		category = "Strategic",
		order = 15,
	},
}

-- Build a sorted array once at load time so callers don't need to sort themselves.
local Ordered: { TycoonItem } = {}
for _, item in Items do
	table.insert(Ordered, item)
end
table.sort(Ordered, function(a, b)
	return a.order < b.order
end)

local TycoonConfig: TycoonConfigType = table.freeze({
	Items = table.freeze(Items),
	Ordered = table.freeze(Ordered),
})

return TycoonConfig
