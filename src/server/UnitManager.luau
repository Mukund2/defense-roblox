--!strict

--[[
	UnitManager.luau (ModuleScript)
	-------------------------------
	Spawns and manages all military unit Parts for every active tycoon pad.

	Lifecycle:
	  • TycoonManager calls RegisterPad when a player claims a pad, then calls
	    SpawnUnit whenever an item is purchased whose `order` matches a UnitConfig
	    tier.  No RemoteEvent wiring is needed — everything is server-to-server.
	  • When a player leaves, TycoonManager calls DespawnAllUnits.

	Unit Parts are placeholder geometry only (no mesh/rig) — each is a single
	Anchored BasePart with a BillboardGui name tag.  AI movement is driven by
	UnitBehaviors.luau and visual effects by EffectsManager.luau.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig")) :: any
local UnitBehaviors = require(script.Parent:WaitForChild("UnitBehaviors")) :: any
local EffectsManager = require(script.Parent:WaitForChild("EffectsManager")) :: any

-- ─────────────────────────────────────────────────────────────────────────────
-- Types
-- ─────────────────────────────────────────────────────────────────────────────

type CleanupFn = () -> ()

type ActiveUnit = {
	part: BasePart,
	unitName: string,
	cleanup: CleanupFn,
	effects: { Instance },
}

-- padNumber → list of active units spawned on that pad
local activeUnits: { [number]: { ActiveUnit } } = {}

-- padNumber → the owner Player (set when a pad is claimed)
local padOwners: { [number]: Player } = {}

-- padNumber → base CFrame anchor point (where units patrol around)
local padCenters: { [number]: CFrame } = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Placeholder geometry specs
-- ─────────────────────────────────────────────────────────────────────────────

type PartSpec = {
	size: Vector3,
	color: Color3,
	material: Enum.Material,
}

-- Keyed by UnitConfig unit name.
local PART_SPECS: { [string]: PartSpec } = {
	InfantrySquad = {
		size = Vector3.new(2, 4, 1),
		color = Color3.fromRGB(85, 107, 47), -- olive green
		material = Enum.Material.SmoothPlastic,
	},
	Humvee = {
		size = Vector3.new(4, 2, 6),
		color = Color3.fromRGB(85, 107, 47),
		material = Enum.Material.Metal,
	},
	ApacheHelicopter = {
		size = Vector3.new(3, 2, 8),
		color = Color3.fromRGB(50, 50, 50),
		material = Enum.Material.Metal,
	},
	M1Abrams = {
		size = Vector3.new(5, 3, 8),
		color = Color3.fromRGB(100, 110, 60), -- olive/tan
		material = Enum.Material.Metal,
	},
	MQ9Reaper = {
		size = Vector3.new(8, 1, 4),
		color = Color3.fromRGB(120, 120, 120),
		material = Enum.Material.SmoothPlastic,
	},
	F22Raptor = {
		size = Vector3.new(4, 2, 10),
		color = Color3.fromRGB(130, 130, 130),
		material = Enum.Material.SmoothPlastic,
	},
	VirginiaClassSub = {
		size = Vector3.new(4, 4, 16),
		color = Color3.fromRGB(40, 40, 40),
		material = Enum.Material.Metal,
	},
	NimitzCarrier = {
		size = Vector3.new(10, 5, 30),
		color = Color3.fromRGB(110, 110, 115),
		material = Enum.Material.Metal,
	},
	B2Spirit = {
		size = Vector3.new(12, 1, 6),
		color = Color3.fromRGB(45, 45, 45),
		material = Enum.Material.SmoothPlastic,
	},
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────────────────────────────────────

--- Build and return the placeholder BasePart for a unit.
local function buildPart(unitName: string, spec: PartSpec, displayName: string): BasePart
	local part = Instance.new("Part")
	part.Name = unitName
	part.Size = spec.size
	part.Color = spec.color
	part.Material = spec.material
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = true

	-- BillboardGui name tag
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Adornee = part
	billboard.AlwaysOnTop = false
	billboard.Size = UDim2.new(0, 120, 0, 30)
	billboard.StudsOffset = Vector3.new(0, spec.size.Y / 2 + 1.5, 0)
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = displayName
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	return part :: BasePart
end

--- Compute the initial spawn CFrame for a unit given pad center and unit spec.
--- Units start offset from center so they don't all stack on the same point.
local function spawnCFrameFor(center: CFrame, unitSpec: any, padNumber: number): CFrame
	local category: string = unitSpec.category
	local height: number = unitSpec.patrolHeight

	-- Offset the spawn point by a deterministic amount per unit name and pad
	-- so multiple units don't overlap.
	local offsetAngle = (padNumber * 37 + unitSpec.tier * 13) % 360
	local offsetRad = math.rad(offsetAngle)
	local radius = unitSpec.patrolRadius * 0.5
	local offsetX = math.cos(offsetRad) * radius
	local offsetZ = math.sin(offsetRad) * radius

	local spawnY: number
	if category == "Aircraft" then
		spawnY = height
	else
		spawnY = center.Position.Y
	end

	local worldOffset = center:PointToWorldSpace(Vector3.new(offsetX, 0, offsetZ))
	return CFrame.new(Vector3.new(worldOffset.X, spawnY, worldOffset.Z))
end

--- Wire up the correct behavior coroutine for a unit and return a cleanup fn.
local function startBehavior(part: BasePart, unitSpec: any, center: CFrame): CleanupFn
	local name: string = unitSpec.name
	local category: string = unitSpec.category
	local speed: number = unitSpec.speed
	local radius: number = unitSpec.patrolRadius
	local height: number = unitSpec.patrolHeight

	-- Apache uses HoverStationary; all other aircraft use PatrolAir.
	if name == "ApacheHelicopter" then
		return UnitBehaviors.HoverStationary(part, center, height)
	elseif category == "Aircraft" then
		return UnitBehaviors.PatrolAir(part, center, speed, radius, height)
	elseif category == "Naval" then
		local isSub = (name == "VirginiaClassSub")
		return UnitBehaviors.PatrolSea(part, center, speed, radius, isSub)
	else
		-- Infantry and Vehicle: ground patrol
		return UnitBehaviors.PatrolGround(part, center, speed, radius)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

local UnitManager = {}

--[[
	RegisterPad(padNumber, owner, centerCFrame)
	--------------------------------------------
	Called when a player claims a tycoon pad.  Records ownership and the pad's
	world-space center so subsequent SpawnUnit calls know where to place units.
--]]
function UnitManager.RegisterPad(padNumber: number, owner: Player, centerCFrame: CFrame)
	padOwners[padNumber] = owner
	padCenters[padNumber] = centerCFrame
	if not activeUnits[padNumber] then
		activeUnits[padNumber] = {}
	end
	print(string.format("[UnitManager] Pad %d registered for player %s", padNumber, owner.Name))
end

--[[
	SpawnUnit(padNumber, unitName)
	------------------------------
	Creates the placeholder Part for `unitName` near pad `padNumber`, starts its
	AI behavior coroutine, and attaches the appropriate visual effects.

	Silently no-ops if the pad has not been registered or the unitName is not
	in UnitConfig.
--]]
function UnitManager.SpawnUnit(padNumber: number, unitName: string)
	local center = padCenters[padNumber]
	if not center then
		warn(string.format("[UnitManager] SpawnUnit: pad %d has no registered center", padNumber))
		return
	end

	local unitSpec = UnitConfig.Units[unitName]
	if not unitSpec then
		warn(string.format("[UnitManager] SpawnUnit: unknown unit '%s'", unitName))
		return
	end

	local spec = PART_SPECS[unitName]
	if not spec then
		warn(string.format("[UnitManager] SpawnUnit: no PartSpec for '%s' — using fallback", unitName))
		spec = {
			size = Vector3.new(3, 3, 3),
			color = Color3.fromRGB(100, 100, 100),
			material = Enum.Material.SmoothPlastic,
		}
	end

	-- Build the part and position it.
	local part = buildPart(unitName, spec, unitSpec.displayName)
	local spawnCF = spawnCFrameFor(center, unitSpec, padNumber)
	part.CFrame = spawnCF
	part.Parent = workspace

	-- Start the AI behavior loop.
	local cleanup = startBehavior(part, unitSpec, center)

	-- Apply visual effects.
	local effects = EffectsManager.ApplyEffectsForCategory(part, unitSpec.category)

	-- Track the unit.
	if not activeUnits[padNumber] then
		activeUnits[padNumber] = {}
	end
	table.insert(activeUnits[padNumber], {
		part = part,
		unitName = unitName,
		cleanup = cleanup,
		effects = effects,
	})

	print(string.format("[UnitManager] Spawned %s on pad %d", unitSpec.displayName, padNumber))
end

--[[
	DespawnAllUnits(padNumber)
	--------------------------
	Stops all behavior loops and destroys all unit Parts for `padNumber`.
	Called on player leave or when a pad is forcibly reset.
--]]
function UnitManager.DespawnAllUnits(padNumber: number)
	local units = activeUnits[padNumber]
	if not units then
		return
	end

	for _, activeUnit in units do
		-- Stop the behavior heartbeat connection.
		activeUnit.cleanup()
		-- Destroy the Part (also destroys child BillboardGui and Attachments).
		if activeUnit.part and activeUnit.part.Parent then
			activeUnit.part:Destroy()
		end
	end

	activeUnits[padNumber] = {}
	print(string.format("[UnitManager] Despawned all units on pad %d", padNumber))
end

--[[
	GetActiveUnitCount(padNumber)  ->  number
	------------------------------------------
	Returns how many units are currently alive on a pad (useful for UI/debug).
--]]
function UnitManager.GetActiveUnitCount(padNumber: number): number
	local units = activeUnits[padNumber]
	if not units then
		return 0
	end
	return #units
end

return UnitManager
