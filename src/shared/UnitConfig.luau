--!strict

export type UnitCategory = "Infantry" | "Vehicle" | "Aircraft" | "Naval"

export type UnitSpec = {
	name: string,
	displayName: string,
	category: UnitCategory,
	speed: number, -- studs per second
	patrolRadius: number, -- studs
	patrolHeight: number, -- studs (0 for ground/naval units)
	description: string,
	tier: number, -- tycoon order index that unlocks this unit
}

export type UnitConfigType = {
	Units: { [string]: UnitSpec },
	ByTier: { [number]: UnitSpec },
}

local Units: { [string]: UnitSpec } = {
	InfantrySquad = {
		name = "InfantrySquad",
		displayName = "Infantry Squad",
		category = "Infantry",
		speed = 14,
		patrolRadius = 40,
		patrolHeight = 0,
		description = "A four-man fireteam equipped with M4 carbines. The backbone of any ground defense.",
		tier = 2, -- Barracks
	},
	Humvee = {
		name = "Humvee",
		displayName = "Humvee",
		category = "Vehicle",
		speed = 38,
		patrolRadius = 80,
		patrolHeight = 0,
		description = "High Mobility Multipurpose Wheeled Vehicle. Fast recon and perimeter patrol in light armor.",
		tier = 3, -- Motor Pool
	},
	ApacheHelicopter = {
		name = "ApacheHelicopter",
		displayName = "Apache Helicopter",
		category = "Aircraft",
		speed = 70,
		patrolRadius = 120,
		patrolHeight = 60,
		description = "AH-64 Apache attack helicopter. Dual-engine rotary wing platform with 30mm cannon and Hellfire missiles.",
		tier = 6, -- Helipad
	},
	M1Abrams = {
		name = "M1Abrams",
		displayName = "M1 Abrams",
		category = "Vehicle",
		speed = 22,
		patrolRadius = 100,
		patrolHeight = 0,
		description = "M1A2 SEPv3 main battle tank. 120mm smoothbore cannon and composite armor make it the king of the battlefield.",
		tier = 8, -- Tank Depot
	},
	MQ9Reaper = {
		name = "MQ9Reaper",
		displayName = "MQ-9 Reaper",
		category = "Aircraft",
		speed = 100,
		patrolRadius = 200,
		patrolHeight = 150,
		description = "General Atomics MQ-9 Reaper UCAV. Persistent ISR and precision strike capability at standoff range.",
		tier = 9, -- Drone Hangar
	},
	F22Raptor = {
		name = "F22Raptor",
		displayName = "F-22 Raptor",
		category = "Aircraft",
		speed = 300,
		patrolRadius = 350,
		patrolHeight = 250,
		description = "Lockheed Martin F-22 Raptor. Fifth-generation supercruising stealth fighter — uncontested air superiority.",
		tier = 10, -- Fighter Jet Hangar
	},
	VirginiaClassSub = {
		name = "VirginiaClassSub",
		displayName = "Virginia-class Sub",
		category = "Naval",
		speed = 20,
		patrolRadius = 400,
		patrolHeight = 0,
		description = "SSN-774 Virginia-class fast-attack submarine. Nuclear-powered stealth beneath the waves, armed with Tomahawk cruise missiles.",
		tier = 11, -- Submarine Pen
	},
	NimitzCarrier = {
		name = "NimitzCarrier",
		displayName = "Nimitz Carrier",
		category = "Naval",
		speed = 15,
		patrolRadius = 600,
		patrolHeight = 0,
		description = "CVN-68 Nimitz-class supercarrier. 100,000-ton nuclear-powered floating airfield — a nation-state at sea.",
		tier = 12, -- Aircraft Carrier Dock
	},
	B2Spirit = {
		name = "B2Spirit",
		displayName = "B-2 Spirit",
		category = "Aircraft",
		speed = 220,
		patrolRadius = 500,
		patrolHeight = 300,
		description = "Northrop Grumman B-2 Spirit stealth bomber. Flying wing with a radar cross-section the size of a bird. Carries up to 80 Mk82 bombs.",
		tier = 13, -- Stealth Bomber Bay
	},
}

-- Pre-build a tier -> unit lookup so spawning code can quickly find which unit a tier unlocks.
local ByTier: { [number]: UnitSpec } = {}
for _, unit in Units do
	ByTier[unit.tier] = unit
end

local UnitConfig: UnitConfigType = table.freeze({
	Units = table.freeze(Units),
	ByTier = table.freeze(ByTier),
})

return UnitConfig
