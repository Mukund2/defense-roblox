--!strict

--[[
	VehicleManager.luau (ModuleScript)
	-----------------------------------
	Spawns and manages drivable vehicles for the military tycoon.

	Vehicle types:
	  - Humvee      (tier 3 / MotorPool)       — ground, no weapon
	  - Tank        (tier 8 / TankDepot)        — ground, fires shells
	  - FighterJet  (tier 10 / FighterJetHangar)— air, fires missiles

	Ground vehicles use VehicleSeat built-in physics (MaxSpeed/Torque/TurnSpeed).
	The FighterJet uses BodyVelocity + BodyGyro driven by VehicleSeat.Throttle/Steer
	plus a pitch remote from the client.

	Vehicles are destroyable: when HP reaches 0 they explode and respawn after 15 s.
--]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) :: any

-- ── Types ────────────────────────────────────────────────────────────────────

type VehicleDef = {
	bodySize: Vector3,
	bodyColor: Color3,
	bodyMaterial: Enum.Material,
	maxSpeed: number,
	turnSpeed: number,
	torque: number,
	maxHP: number,
	hasWheels: boolean,
	hasTurret: boolean,
	hasWings: boolean,
	isAircraft: boolean,
	canShoot: boolean,
	projectileSpeed: number,
	projectileDamage: number,
	hasRotor: boolean,
}

type ActiveVehicle = {
	model: Model,
	seat: VehicleSeat,
	body: BasePart,
	vehicleType: string,
	owner: Player,
	padNumber: number,
	spawnPosition: Vector3,
	hp: number,
	maxHP: number,
	destroyed: boolean,
	cleanup: { RBXScriptConnection },
	-- jet-specific
	bodyVelocity: BodyVelocity?,
	bodyGyro: BodyGyro?,
	pitchInput: number,
}

-- ── Vehicle definitions ──────────────────────────────────────────────────────

local VEHICLE_DEFS: { [string]: VehicleDef } = {
	Humvee = {
		bodySize = Vector3.new(5, 3, 8),
		bodyColor = Color3.fromRGB(107, 142, 35), -- olive green
		bodyMaterial = Enum.Material.Metal,
		maxSpeed = 60,
		turnSpeed = 2,
		torque = 30,
		maxHP = 150,
		hasWheels = true,
		hasTurret = false,
		hasWings = false,
		isAircraft = false,
		canShoot = false,
		projectileSpeed = 0,
		projectileDamage = 0,
		hasRotor = false,
	},
	Tank = {
		bodySize = Vector3.new(6, 3, 10),
		bodyColor = Color3.fromRGB(0, 100, 0), -- dark green
		bodyMaterial = Enum.Material.Metal,
		maxSpeed = 35,
		turnSpeed = 1.2,
		torque = 60,
		maxHP = 400,
		hasWheels = true,
		hasTurret = true,
		hasWings = false,
		isAircraft = false,
		canShoot = true,
		projectileSpeed = 200,
		projectileDamage = 80,
		hasRotor = false,
	},
	FighterJet = {
		bodySize = Vector3.new(4, 2, 12),
		bodyColor = Color3.fromRGB(150, 150, 150), -- gray
		bodyMaterial = Enum.Material.SmoothPlastic,
		maxSpeed = 150,
		turnSpeed = 1.5,
		torque = 0, -- not used (BodyVelocity-driven)
		maxHP = 200,
		hasWheels = false,
		hasTurret = false,
		hasWings = true,
		isAircraft = true,
		canShoot = true,
		projectileSpeed = 300,
		projectileDamage = 60,
		hasRotor = false,
	},
	Helicopter = {
		bodySize = Vector3.new(4, 2.5, 8),
		bodyColor = Color3.fromRGB(85, 107, 47), -- dark olive
		bodyMaterial = Enum.Material.Metal,
		maxSpeed = 80,
		turnSpeed = 2,
		torque = 0,
		maxHP = 180,
		hasWheels = false,
		hasTurret = false,
		hasWings = false,
		isAircraft = true,
		canShoot = true,
		projectileSpeed = 250,
		projectileDamage = 40,
		hasRotor = true,
	},
	Drone = {
		bodySize = Vector3.new(2.5, 1, 5),
		bodyColor = Color3.fromRGB(60, 60, 60), -- dark gray
		bodyMaterial = Enum.Material.SmoothPlastic,
		maxSpeed = 100,
		turnSpeed = 2.5,
		torque = 0,
		maxHP = 80,
		hasWheels = false,
		hasTurret = false,
		hasWings = true,
		isAircraft = true,
		canShoot = true,
		projectileSpeed = 200,
		projectileDamage = 30,
		hasRotor = false,
	},
}

-- Maps building modelName → vehicle type
local BUILDING_TO_VEHICLE: { [string]: string } = {
	MotorPool = "Humvee",
	TankDepot = "Tank",
	FighterJetHangar = "FighterJet",
	Helipad = "Helicopter",
	DroneHangar = "Drone",
}

-- ── State ────────────────────────────────────────────────────────────────────

-- All active vehicles keyed by the Model instance
local activeVehicles: { [Model]: ActiveVehicle } = {}

-- Per-player list of vehicle models they own
local playerVehicles: { [Player]: { Model } } = {}

-- Jet pitch input per player (set by remote)
local jetPitchInputs: { [Player]: number } = {}

-- Shoot cooldown per player
local lastShootTime: { [Player]: number } = {}
local SHOOT_COOLDOWN = 0.5

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function weld(part0: BasePart, part1: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part0
end

local function createWheel(parent: Model, body: BasePart, offsetX: number, offsetZ: number): BasePart
	local wheel = Instance.new("Part")
	wheel.Name = "Wheel"
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Size = Vector3.new(1, 1.5, 1.5) -- cylinder: X=length, Y=diameter, Z=diameter
	wheel.Color = Color3.fromRGB(50, 50, 50) -- dark gray
	wheel.Material = Enum.Material.SmoothPlastic
	wheel.Anchored = false
	wheel.CanCollide = false
	wheel.Massless = true
	wheel.CFrame = body.CFrame * CFrame.new(offsetX, -body.Size.Y / 2, offsetZ)
	wheel.Parent = parent

	weld(body, wheel)
	return wheel
end

local function createTurret(parent: Model, body: BasePart): BasePart
	local turret = Instance.new("Part")
	turret.Name = "Turret"
	turret.Size = Vector3.new(2.5, 1.5, 4)
	turret.Color = Color3.fromRGB(0, 80, 0)
	turret.Material = Enum.Material.Metal
	turret.Anchored = false
	turret.CanCollide = false
	turret.Massless = true
	turret.CFrame = body.CFrame * CFrame.new(0, body.Size.Y / 2 + 0.75, -1)
	turret.Parent = parent

	-- Barrel
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.5, 0.5, 4)
	barrel.Color = Color3.fromRGB(40, 40, 40)
	barrel.Material = Enum.Material.Metal
	barrel.Anchored = false
	barrel.CanCollide = false
	barrel.Massless = true
	barrel.CFrame = turret.CFrame * CFrame.new(0, 0.3, -turret.Size.Z / 2 - 2)
	barrel.Parent = parent

	weld(turret, barrel)
	weld(body, turret)
	return turret
end

local function createWings(parent: Model, body: BasePart)
	-- Left wing
	local leftWing = Instance.new("Part")
	leftWing.Name = "LeftWing"
	leftWing.Size = Vector3.new(6, 0.3, 3)
	leftWing.Color = body.Color
	leftWing.Material = body.Material
	leftWing.Anchored = false
	leftWing.CanCollide = false
	leftWing.Massless = true
	leftWing.CFrame = body.CFrame * CFrame.new(-5, 0, 1) * CFrame.Angles(0, 0, math.rad(-5))
	leftWing.Parent = parent
	weld(body, leftWing)

	-- Right wing
	local rightWing = Instance.new("Part")
	rightWing.Name = "RightWing"
	rightWing.Size = Vector3.new(6, 0.3, 3)
	rightWing.Color = body.Color
	rightWing.Material = body.Material
	rightWing.Anchored = false
	rightWing.CanCollide = false
	rightWing.Massless = true
	rightWing.CFrame = body.CFrame * CFrame.new(5, 0, 1) * CFrame.Angles(0, 0, math.rad(5))
	rightWing.Parent = parent
	weld(body, rightWing)

	-- Tail fin
	local tail = Instance.new("Part")
	tail.Name = "TailFin"
	tail.Size = Vector3.new(0.3, 2, 2)
	tail.Color = body.Color
	tail.Material = body.Material
	tail.Anchored = false
	tail.CanCollide = false
	tail.Massless = true
	tail.CFrame = body.CFrame * CFrame.new(0, 1.2, body.Size.Z / 2 - 0.5)
	tail.Parent = parent
	weld(body, tail)
end

local function createRotor(parent: Model, body: BasePart)
	-- Main rotor hub
	local hub = Instance.new("Part")
	hub.Name = "RotorHub"
	hub.Size = Vector3.new(1, 0.5, 1)
	hub.Color = Color3.fromRGB(50, 50, 50)
	hub.Material = Enum.Material.Metal
	hub.Anchored = false
	hub.CanCollide = false
	hub.Massless = true
	hub.CFrame = body.CFrame * CFrame.new(0, body.Size.Y / 2 + 0.25, 0)
	hub.Parent = parent
	weld(body, hub)

	-- Rotor blade (long thin part)
	local blade = Instance.new("Part")
	blade.Name = "RotorBlade"
	blade.Size = Vector3.new(12, 0.15, 0.8)
	blade.Color = Color3.fromRGB(80, 80, 80)
	blade.Material = Enum.Material.Metal
	blade.Anchored = false
	blade.CanCollide = false
	blade.Massless = true
	blade.CFrame = hub.CFrame * CFrame.new(0, 0.3, 0)
	blade.Parent = parent
	weld(hub, blade)

	-- Tail rotor
	local tailRotor = Instance.new("Part")
	tailRotor.Name = "TailRotor"
	tailRotor.Size = Vector3.new(0.15, 2, 0.5)
	tailRotor.Color = Color3.fromRGB(80, 80, 80)
	tailRotor.Material = Enum.Material.Metal
	tailRotor.Anchored = false
	tailRotor.CanCollide = false
	tailRotor.Massless = true
	tailRotor.CFrame = body.CFrame * CFrame.new(0, 0.5, body.Size.Z / 2 + 0.3)
	tailRotor.Parent = parent
	weld(body, tailRotor)

	-- Tail boom
	local tailBoom = Instance.new("Part")
	tailBoom.Name = "TailBoom"
	tailBoom.Size = Vector3.new(0.8, 0.8, 4)
	tailBoom.Color = body.Color
	tailBoom.Material = body.Material
	tailBoom.Anchored = false
	tailBoom.CanCollide = false
	tailBoom.Massless = true
	tailBoom.CFrame = body.CFrame * CFrame.new(0, 0, body.Size.Z / 2 + 2)
	tailBoom.Parent = parent
	weld(body, tailBoom)
end

local function createHPGui(body: BasePart, hp: number, maxHP: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HPGui"
	billboard.Adornee = body
	billboard.AlwaysOnTop = false
	billboard.Size = UDim2.new(0, 100, 0, 16)
	billboard.StudsOffset = Vector3.new(0, body.Size.Y / 2 + 2.5, 0)
	billboard.Parent = body

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(hp / maxHP, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
	bar.BorderSizePixel = 0
	bar.Parent = bg

	local corner1 = Instance.new("UICorner")
	corner1.CornerRadius = UDim.new(0, 4)
	corner1.Parent = bg

	local corner2 = Instance.new("UICorner")
	corner2.CornerRadius = UDim.new(0, 4)
	corner2.Parent = bar
end

local function updateHPGui(body: BasePart, hp: number, maxHP: number)
	local billboard = body:FindFirstChild("HPGui") :: BillboardGui?
	if not billboard then
		return
	end
	local bg = billboard:FindFirstChild("BG")
	if not bg then
		return
	end
	local bar = bg:FindFirstChild("Bar") :: Frame?
	if not bar then
		return
	end
	local ratio = math.clamp(hp / maxHP, 0, 1)
	bar.Size = UDim2.new(ratio, 0, 1, 0)
	if ratio > 0.5 then
		bar.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
	elseif ratio > 0.25 then
		bar.BackgroundColor3 = Color3.fromRGB(255, 165, 0)
	else
		bar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	end
end

-- ── Vehicle construction ─────────────────────────────────────────────────────

local function buildVehicle(vehicleType: string, position: Vector3, owner: Player): (Model, VehicleSeat, BasePart)
	local def = VEHICLE_DEFS[vehicleType]
	assert(def, "Unknown vehicle type: " .. vehicleType)

	local model = Instance.new("Model")
	model.Name = vehicleType .. "_" .. owner.Name
	model:SetAttribute("VehicleType", vehicleType)
	model:SetAttribute("Owner", owner.Name)

	-- Body
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = def.bodySize
	body.Color = def.bodyColor
	body.Material = def.bodyMaterial
	body.Anchored = false
	body.CanCollide = true
	body.CFrame = CFrame.new(position + Vector3.new(0, def.bodySize.Y / 2 + 2, 0))
	body.Parent = model

	-- VehicleSeat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "VehicleSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.Transparency = 1
	seat.Anchored = false
	seat.CanCollide = false
	seat.Massless = true
	seat.CFrame = body.CFrame * CFrame.new(0, 0.5, 1)
	seat.Parent = model
	weld(body, seat)

	-- Ground vehicle physics via VehicleSeat
	if not def.isAircraft then
		seat.MaxSpeed = def.maxSpeed
		seat.TurnSpeed = def.turnSpeed
		seat.Torque = def.torque
	else
		-- Aircraft: disable VehicleSeat physics (we use BodyVelocity/BodyGyro)
		seat.MaxSpeed = 0
		seat.TurnSpeed = 0
		seat.Torque = 0
	end

	-- Wheels
	if def.hasWheels then
		local halfX = def.bodySize.X / 2 - 0.3
		local halfZ = def.bodySize.Z / 2 - 1
		createWheel(model, body, -halfX, -halfZ) -- front-left
		createWheel(model, body, halfX, -halfZ)  -- front-right
		createWheel(model, body, -halfX, halfZ)  -- rear-left
		createWheel(model, body, halfX, halfZ)   -- rear-right
	end

	-- Turret (Tank)
	if def.hasTurret then
		createTurret(model, body)
	end

	-- Wings (FighterJet)
	if def.hasWings then
		createWings(model, body)
	end

	-- Rotor (Helicopter)
	if def.hasRotor then
		createRotor(model, body)
	end

	-- HP bar
	createHPGui(body, def.maxHP, def.maxHP)

	model.PrimaryPart = body
	return model, seat, body
end

-- ── Jet physics ──────────────────────────────────────────────────────────────

local function setupJetPhysics(body: BasePart): (BodyVelocity, BodyGyro)
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = Vector3.zero
	bv.P = 1250
	bv.Parent = body

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	bg.CFrame = body.CFrame
	bg.P = 3000
	bg.D = 500
	bg.Parent = body

	return bv, bg
end

-- Forward declarations for mutual recursion between fireProjectile, destroyVehicle, registerVehicle
local destroyVehicle: (ActiveVehicle) -> ()
local registerVehicle: (Model, VehicleSeat, BasePart, string, Player, number, Vector3) -> ActiveVehicle

-- ── Projectile helper ────────────────────────────────────────────────────────

local function fireProjectile(origin: CFrame, direction: Vector3, speed: number, damage: number, owner: Player, isMissile: boolean)
	local projectile = Instance.new("Part")
	projectile.Name = if isMissile then "Missile" else "Shell"
	projectile.Size = if isMissile then Vector3.new(0.3, 0.3, 2) else Vector3.new(0.4, 0.4, 1.5)
	projectile.Color = if isMissile then Color3.fromRGB(255, 100, 0) else Color3.fromRGB(255, 255, 0)
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CFrame = origin
	projectile.Parent = workspace

	-- Trail effect
	local att0 = Instance.new("Attachment")
	att0.Parent = projectile
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0, 1)
	att1.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 0.3
	trail.MinLength = 0.1
	trail.Color = ColorSequence.new(if isMissile then Color3.fromRGB(255, 100, 0) else Color3.fromRGB(255, 200, 50))
	trail.Parent = projectile

	-- Move projectile via heartbeat
	local velocity = direction.Unit * speed
	local maxDistance = 500
	local traveled = 0

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt: number)
		if not projectile.Parent then
			conn:Disconnect()
			return
		end

		local step = velocity * dt
		traveled += step.Magnitude
		projectile.CFrame = projectile.CFrame + step

		-- Raycast for hits
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		-- Exclude owner's character and their vehicles
		local filterList: { Instance } = {}
		if owner.Character then
			table.insert(filterList, owner.Character)
		end
		local ownerVehicles = playerVehicles[owner]
		if ownerVehicles then
			for _, vModel in ownerVehicles do
				table.insert(filterList, vModel)
			end
		end
		table.insert(filterList, projectile)
		rayParams.FilterDescendantsInstances = filterList

		local result = workspace:Raycast(projectile.Position, step.Unit * 3, rayParams)
		if result then
			-- Create explosion
			local explosion = Instance.new("Explosion")
			explosion.Position = result.Position
			explosion.BlastRadius = if isMissile then 12 else 8
			explosion.BlastPressure = 0 -- we handle damage manually
			explosion.DestroyJointRadiusPercent = 0
			explosion.Parent = workspace

			-- Damage vehicles hit
			local hitPart = result.Instance
			local hitModel = hitPart:FindFirstAncestorOfClass("Model")
			if hitModel then
				local hitVehicle = activeVehicles[hitModel]
				if hitVehicle and not hitVehicle.destroyed then
					hitVehicle.hp -= damage
					updateHPGui(hitVehicle.body, hitVehicle.hp, hitVehicle.maxHP)
					if hitVehicle.hp <= 0 then
						destroyVehicle(hitVehicle)
					end
				end
			end

			-- Damage characters hit (humanoid)
			local humanoid = hitPart.Parent and hitPart.Parent:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local hitPlayer = Players:GetPlayerFromCharacter(hitPart.Parent :: Instance)
				if hitPlayer ~= owner then
					humanoid:TakeDamage(damage)
				end
			end

			conn:Disconnect()
			projectile:Destroy()
			return
		end

		if traveled >= maxDistance then
			conn:Disconnect()
			projectile:Destroy()
		end
	end)

	-- Safety cleanup after 5 seconds
	task.delay(5, function()
		if projectile.Parent then
			conn:Disconnect()
			projectile:Destroy()
		end
	end)
end

-- ── Destroy / respawn ────────────────────────────────────────────────────────

destroyVehicle = function(vehicle: ActiveVehicle)
	if vehicle.destroyed then
		return
	end
	vehicle.destroyed = true

	-- Kick occupant out
	local seat = vehicle.seat
	local occupant = seat.Occupant
	if occupant then
		local humanoid = occupant :: Humanoid
		-- Jump to unseat
		humanoid.Jump = true
	end

	-- Explosion effect
	local explosion = Instance.new("Explosion")
	explosion.Position = vehicle.body.Position
	explosion.BlastRadius = 15
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	-- Clean up connections
	for _, conn in vehicle.cleanup do
		conn:Disconnect()
	end
	vehicle.cleanup = {}

	-- Remove model
	if vehicle.model.Parent then
		vehicle.model:Destroy()
	end

	-- Remove from active vehicles
	activeVehicles[vehicle.model] = nil

	-- Respawn after 15 seconds
	task.delay(15, function()
		if not vehicle.owner.Parent then
			return -- player left
		end
		-- Respawn
		local newModel, newSeat, newBody = buildVehicle(vehicle.vehicleType, vehicle.spawnPosition, vehicle.owner)
		local newVehicle = registerVehicle(
			newModel, newSeat, newBody,
			vehicle.vehicleType, vehicle.owner,
			vehicle.padNumber, vehicle.spawnPosition
		)

		-- Re-add to player's vehicle list
		local pVehicles = playerVehicles[vehicle.owner]
		if pVehicles then
			table.insert(pVehicles, newModel)
		end

		newModel.Parent = workspace

		print(string.format("[VehicleManager] Respawned %s for %s", vehicle.vehicleType, vehicle.owner.Name))
		-- Suppress unused variable warning
		if newVehicle then end
	end)
end

-- ── Register vehicle ─────────────────────────────────────────────────────────

registerVehicle = function(
	model: Model, seat: VehicleSeat, body: BasePart,
	vehicleType: string, owner: Player,
	padNumber: number, spawnPosition: Vector3
): ActiveVehicle
	local def = VEHICLE_DEFS[vehicleType]

	local vehicle: ActiveVehicle = {
		model = model,
		seat = seat,
		body = body,
		vehicleType = vehicleType,
		owner = owner,
		padNumber = padNumber,
		spawnPosition = spawnPosition,
		hp = def.maxHP,
		maxHP = def.maxHP,
		destroyed = false,
		cleanup = {},
		bodyVelocity = nil,
		bodyGyro = nil,
		pitchInput = 0,
	}

	-- Jet physics setup
	if def.isAircraft then
		local bv, bg = setupJetPhysics(body)
		vehicle.bodyVelocity = bv
		vehicle.bodyGyro = bg

		-- Server loop to read VehicleSeat.Throttle/Steer and drive BodyVelocity/BodyGyro
		local jetConn = RunService.Heartbeat:Connect(function(dt: number)
			if vehicle.destroyed or not model.Parent then
				return
			end

			local throttle = seat.Throttle -- -1, 0, or 1
			local steer = seat.Steer       -- -1, 0, or 1
			local pitch = jetPitchInputs[owner] or 0

			-- Forward speed based on throttle
			local currentSpeed = bv.Velocity.Magnitude
			local targetSpeed = 0
			if throttle > 0 then
				targetSpeed = def.maxSpeed
			elseif throttle < 0 then
				targetSpeed = def.maxSpeed * 0.3 -- reverse/brake = slow forward
			else
				targetSpeed = math.max(0, currentSpeed - 30 * dt) -- decelerate
			end

			-- Smoothly interpolate speed
			local newSpeed = currentSpeed + (targetSpeed - currentSpeed) * math.min(1, dt * 3)

			-- Apply yaw (steer) and pitch to BodyGyro
			local currentCF = body.CFrame
			local yawDelta = -steer * def.turnSpeed * dt
			local pitchDelta = pitch * 1.5 * dt

			local newCF = currentCF * CFrame.Angles(pitchDelta, yawDelta, 0)
			bg.CFrame = newCF

			-- Set velocity along look direction
			bv.Velocity = newCF.LookVector * -newSpeed

			-- Minimum altitude
			if body.Position.Y < 20 and pitch >= 0 then
				local pos = body.Position
				body.CFrame = CFrame.new(Vector3.new(pos.X, 20, pos.Z)) * (body.CFrame - body.CFrame.Position)
			end
		end)

		table.insert(vehicle.cleanup, jetConn)
	end

	activeVehicles[model] = vehicle
	return vehicle
end

-- ── Public API ───────────────────────────────────────────────────────────────

local VehicleManager = {}

--[[
	SpawnVehicle(player, vehicleType, position)
	--------------------------------------------
	Creates a drivable vehicle of the given type near the specified position.
	The vehicle is owned by the player and will respawn on destruction.
]]
function VehicleManager.SpawnVehicle(player: Player, vehicleType: string, position: Vector3)
	local def = VEHICLE_DEFS[vehicleType]
	if not def then
		warn("[VehicleManager] Unknown vehicle type: " .. vehicleType)
		return
	end

	local model, seat, body = buildVehicle(vehicleType, position, player)
	local vehicle = registerVehicle(model, seat, body, vehicleType, player, 0, position)

	-- Track player vehicles
	if not playerVehicles[player] then
		playerVehicles[player] = {}
	end
	table.insert(playerVehicles[player], model)

	model.Parent = workspace

	print(string.format("[VehicleManager] Spawned %s for %s at %s", vehicleType, player.Name, tostring(position)))

	-- Suppress unused variable warning
	if vehicle then end
end

--[[
	GetBuildingVehicleType(buildingName)
	-------------------------------------
	Returns the vehicle type unlocked by a building, or nil if none.
]]
function VehicleManager.GetBuildingVehicleType(buildingName: string): string?
	return BUILDING_TO_VEHICLE[buildingName]
end

--[[
	DespawnAllVehicles(player)
	---------------------------
	Destroys all vehicles belonging to a player. Called on player leave.
]]
function VehicleManager.DespawnAllVehicles(player: Player)
	local vehicles = playerVehicles[player]
	if not vehicles then
		return
	end

	for _, model in vehicles do
		local vehicle = activeVehicles[model]
		if vehicle then
			vehicle.destroyed = true
			for _, conn in vehicle.cleanup do
				conn:Disconnect()
			end
			activeVehicles[model] = nil
		end
		if model.Parent then
			model:Destroy()
		end
	end

	playerVehicles[player] = nil
	jetPitchInputs[player] = nil
	lastShootTime[player] = nil

	print(string.format("[VehicleManager] Despawned all vehicles for %s", player.Name))
end

--[[
	DamageVehicle(model, damage)
	-----------------------------
	Applies damage to a vehicle. If HP drops to 0, the vehicle explodes.
]]
function VehicleManager.DamageVehicle(model: Model, damage: number)
	local vehicle = activeVehicles[model]
	if not vehicle or vehicle.destroyed then
		return
	end

	vehicle.hp -= damage
	updateHPGui(vehicle.body, vehicle.hp, vehicle.maxHP)

	if vehicle.hp <= 0 then
		destroyVehicle(vehicle)
	end
end

-- ── Remote handlers ──────────────────────────────────────────────────────────

-- VehicleShoot: Client fires vehicle weapon
Remotes.VehicleShoot.OnServerEvent:Connect(function(player: Player, vehicleType: unknown, targetPosition: unknown)
	if type(vehicleType) ~= "string" or typeof(targetPosition) ~= "Vector3" then
		return
	end

	-- Cooldown
	local now = tick()
	local last = lastShootTime[player]
	if last and (now - last) < SHOOT_COOLDOWN then
		return
	end
	lastShootTime[player] = now

	-- Find the player's vehicle they're sitting in
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.SeatPart then
		return
	end

	local seatPart = humanoid.SeatPart
	local vehicleModel = seatPart:FindFirstAncestorOfClass("Model")
	if not vehicleModel then
		return
	end

	local vehicle = activeVehicles[vehicleModel]
	if not vehicle or vehicle.destroyed then
		return
	end

	local def = VEHICLE_DEFS[vehicle.vehicleType]
	if not def or not def.canShoot then
		return
	end

	-- Determine fire origin and direction
	local fireOrigin: CFrame
	local fireDirection: Vector3

	if vehicle.vehicleType == "Tank" then
		local turret = vehicleModel:FindFirstChild("Turret")
		local barrel = vehicleModel:FindFirstChild("Barrel")
		local fireFrom = if barrel then (barrel :: BasePart) else if turret then (turret :: BasePart) else vehicle.body
		fireOrigin = fireFrom.CFrame * CFrame.new(0, 0, -fireFrom.Size.Z / 2 - 1)
		fireDirection = (targetPosition :: Vector3 - fireOrigin.Position).Unit
	else
		-- Jet: fire from nose
		fireOrigin = vehicle.body.CFrame * CFrame.new(0, 0, -vehicle.body.Size.Z / 2 - 1)
		fireDirection = vehicle.body.CFrame.LookVector * -1
	end

	local isMissile = (vehicle.vehicleType == "FighterJet")
	fireProjectile(fireOrigin, fireDirection, def.projectileSpeed, def.projectileDamage, player, isMissile)
end)

-- VehiclePitch: Client sends pitch input for jets
Remotes.VehiclePitch.OnServerEvent:Connect(function(player: Player, pitch: unknown)
	if type(pitch) ~= "number" then
		return
	end
	-- Clamp to -1, 0, or 1
	local p = math.clamp(pitch :: number, -1, 1)
	jetPitchInputs[player] = p
end)

-- SpawnVehicle: Client requests a vehicle spawn (validation done here)
Remotes.SpawnVehicle.OnServerEvent:Connect(function(player: Player, vehicleType: unknown)
	if type(vehicleType) ~= "string" then
		return
	end

	-- Validate the player has the required building
	local requiredBuilding: string? = nil
	for building, vType in BUILDING_TO_VEHICLE do
		if vType == vehicleType then
			requiredBuilding = building
			break
		end
	end

	if not requiredBuilding then
		return
	end

	-- Check player data to verify they've unlocked the building
	-- Use the GetPlayerData remote function approach
	local character = player.Character
	if not character then
		return
	end

	-- Simple respawn: spawn at last spawn position for existing vehicle of this type
	local vehicles = playerVehicles[player]
	if vehicles then
		for _, model in vehicles do
			local v = activeVehicles[model]
			if v and v.vehicleType == vehicleType and not v.destroyed then
				-- Already has one alive
				return
			end
		end
	end

	-- For now, spawn near the player
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	VehicleManager.SpawnVehicle(player, vehicleType :: string, rootPart.Position + Vector3.new(10, 0, 0))
end)

-- ── Player cleanup ───────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player: Player)
	VehicleManager.DespawnAllVehicles(player)
end)

return VehicleManager
