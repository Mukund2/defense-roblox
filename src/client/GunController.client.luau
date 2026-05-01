--!strict

--[[
	GunController.client.luau
	-------------------------
	Handles FPS gun input for all weapon types: raycasting, visual effects,
	fire-rate limiting, and crosshair display. Supports multiple weapons
	with different stats read from Tool attributes.

	Weapon types supported:
	  - Military Rifle: standard auto-fire hitscan
	  - Sniper Rifle: slow, long range, zoom on equip
	  - Shotgun: multi-pellet spread
	  - RPG: fires visible projectile with explosion
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) :: any

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ── State ────────────────────────────────────────────────────────────────────

local equippedTool: Tool? = nil
local lastFireTick: number = 0
local FIRE_RATE: number = 0.15
local MAX_RANGE: number = 200
local CURRENT_DAMAGE: number = 15
local WEAPON_TYPE: string = "Military Rifle"

-- ── Crosshair ────────────────────────────────────────────────────────────────

local crosshairGui = Instance.new("ScreenGui")
crosshairGui.Name = "CrosshairGui"
crosshairGui.ResetOnSpawn = false
crosshairGui.IgnoreGuiInset = true
crosshairGui.DisplayOrder = 100
crosshairGui.Enabled = false
crosshairGui.Parent = player:WaitForChild("PlayerGui")

local crosshairLabel = Instance.new("TextLabel")
crosshairLabel.Name = "Crosshair"
crosshairLabel.Size = UDim2.fromOffset(30, 30)
crosshairLabel.Position = UDim2.new(0.5, -15, 0.5, -15)
crosshairLabel.BackgroundTransparency = 1
crosshairLabel.Text = "+"
crosshairLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
crosshairLabel.TextStrokeTransparency = 0.3
crosshairLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
crosshairLabel.TextSize = 28
crosshairLabel.Font = Enum.Font.GothamBold
crosshairLabel.Parent = crosshairGui

-- Weapon name indicator
local weaponLabel = Instance.new("TextLabel")
weaponLabel.Name = "WeaponName"
weaponLabel.Size = UDim2.new(0, 200, 0, 24)
weaponLabel.Position = UDim2.new(0.5, -100, 1, -60)
weaponLabel.BackgroundTransparency = 1
weaponLabel.Text = ""
weaponLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
weaponLabel.TextStrokeTransparency = 0.5
weaponLabel.TextSize = 14
weaponLabel.Font = Enum.Font.GothamBold
weaponLabel.Parent = crosshairGui

-- ── Visual FX helpers ────────────────────────────────────────────────────────

local function createLaserTrace(from: Vector3, to: Vector3, color: Color3?)
	local distance = (to - from).Magnitude
	local midpoint = (from + to) / 2
	local traceColor = color or Color3.fromRGB(255, 220, 50)

	local trace = Instance.new("Part")
	trace.Name = "LaserTrace"
	trace.Anchored = true
	trace.CanCollide = false
	trace.CanQuery = false
	trace.CanTouch = false
	trace.Material = Enum.Material.Neon
	trace.Color = traceColor
	trace.Size = Vector3.new(0.05, 0.05, distance)
	trace.CFrame = CFrame.lookAt(midpoint, to)
	trace.Parent = workspace

	task.delay(0.1, function()
		trace:Destroy()
	end)
end

local function createMuzzleFlash(position: Vector3, size: number?)
	local flashSize = size or 0.4
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 50)
	flash.Size = Vector3.new(flashSize, flashSize, flashSize)
	flash.Shape = Enum.PartType.Ball
	flash.Position = position
	flash.Parent = workspace

	task.delay(0.05, function()
		flash:Destroy()
	end)
end

local function createExplosionEffect(position: Vector3)
	-- Visual explosion (no damage — server handles damage)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	-- Orange flash
	local flash = Instance.new("Part")
	flash.Name = "RPGFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 120, 0)
	flash.Size = Vector3.new(4, 4, 4)
	flash.Shape = Enum.PartType.Ball
	flash.Position = position
	flash.Parent = workspace

	task.delay(0.2, function()
		flash:Destroy()
	end)
end

local function fireClientRPGProjectile(from: Vector3, to: Vector3)
	local direction = (to - from).Unit
	local projectile = Instance.new("Part")
	projectile.Name = "RPGRocket"
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.CanTouch = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(255, 100, 0)
	projectile.Size = Vector3.new(0.3, 0.3, 1.5)
	projectile.CFrame = CFrame.lookAt(from, from + direction)
	projectile.Parent = workspace

	-- Trail
	local att0 = Instance.new("Attachment")
	att0.Parent = projectile
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0, 0.75)
	att1.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 0.2
	trail.MinLength = 0.1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 100, 0))
	trail.Parent = projectile

	local speed = 150
	local maxDist = (to - from).Magnitude + 10
	local traveled = 0

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if not projectile.Parent then
			conn:Disconnect()
			return
		end
		local step = direction * speed * dt
		traveled += step.Magnitude
		projectile.CFrame = projectile.CFrame + step

		if traveled >= maxDist then
			conn:Disconnect()
			createExplosionEffect(projectile.Position)
			projectile:Destroy()
		end
	end)

	task.delay(3, function()
		if projectile.Parent then
			conn:Disconnect()
			projectile:Destroy()
		end
	end)
end

-- ── Shooting logic ───────────────────────────────────────────────────────────

local function getGunTipPosition(): Vector3?
	if not equippedTool then
		return nil
	end
	local handle = equippedTool:FindFirstChild("Handle") :: BasePart?
	if not handle then
		return nil
	end
	return handle.CFrame.Position + handle.CFrame.LookVector * 1.5
end

local function shoot()
	local now = tick()
	if (now - lastFireTick) < FIRE_RATE then
		return
	end
	lastFireTick = now

	local character = player.Character
	if not character then
		return
	end

	local gunTip = getGunTipPosition()
	if not gunTip then
		return
	end

	-- Ray from camera center into the world
	local viewportSize = camera.ViewportSize
	local screenCenter = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
	local unitRay = camera:ViewportPointToRay(screenCenter.X, screenCenter.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	-- Shotgun: fire multiple pellets with spread
	local pelletCount = if WEAPON_TYPE == "Shotgun" then 6 else 1
	local spreadAngle = if WEAPON_TYPE == "Shotgun" then 8 else 0

	for _ = 1, pelletCount do
		local rayDir = unitRay.Direction

		-- Apply spread
		if spreadAngle > 0 then
			local spreadX = (math.random() - 0.5) * 2 * math.rad(spreadAngle)
			local spreadY = (math.random() - 0.5) * 2 * math.rad(spreadAngle)
			rayDir = (CFrame.new(Vector3.zero, rayDir) * CFrame.Angles(spreadY, spreadX, 0)).LookVector
		end

		local rayResult = workspace:Raycast(unitRay.Origin, rayDir * MAX_RANGE, rayParams)

		local hitPosition: Vector3
		local hitPart: BasePart? = nil

		if rayResult then
			hitPosition = rayResult.Position
			hitPart = rayResult.Instance
		else
			hitPosition = unitRay.Origin + rayDir * MAX_RANGE
		end

		-- Visual effects per weapon type
		if WEAPON_TYPE == "RPG" then
			createMuzzleFlash(gunTip, 0.8)
			fireClientRPGProjectile(gunTip, hitPosition)
		elseif WEAPON_TYPE == "Sniper Rifle" then
			createMuzzleFlash(gunTip, 0.6)
			createLaserTrace(gunTip, hitPosition, Color3.fromRGB(100, 200, 255))
		elseif WEAPON_TYPE == "Shotgun" then
			createMuzzleFlash(gunTip, 0.3)
			createLaserTrace(gunTip, hitPosition, Color3.fromRGB(255, 180, 50))
		else
			createMuzzleFlash(gunTip)
			createLaserTrace(gunTip, hitPosition)
		end

		-- Check if we hit another player
		if hitPart then
			local hitModel = hitPart.Parent
			if hitModel and hitModel:IsA("Accessory") then
				hitModel = hitModel.Parent
			end
			if hitModel and hitModel:IsA("Model") then
				local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
					if hitPlayer and hitPlayer ~= player then
						Remotes.ShootPlayer:FireServer(hitPosition, hitPart:GetFullName())
					end
				end
			end
		end
	end
end

-- ── Tool equip / unequip ─────────────────────────────────────────────────────

local WEAPON_NAMES = {
	["Military Rifle"] = true,
	["Sniper Rifle"] = true,
	["Shotgun"] = true,
	["RPG"] = true,
}

local function onChildAdded(child: Instance)
	if not child:IsA("Tool") then
		return
	end
	if not WEAPON_NAMES[child.Name] then
		return
	end

	local tool = child :: Tool

	tool.Equipped:Connect(function()
		equippedTool = tool
		crosshairGui.Enabled = true

		-- Read weapon stats from attributes
		local fireRate = tool:GetAttribute("FireRate")
		if typeof(fireRate) == "number" then
			FIRE_RATE = fireRate
		end
		local range = tool:GetAttribute("Range")
		if typeof(range) == "number" then
			MAX_RANGE = range
		end
		local damage = tool:GetAttribute("Damage")
		if typeof(damage) == "number" then
			CURRENT_DAMAGE = damage
		end
		local weaponType = tool:GetAttribute("WeaponType")
		if typeof(weaponType) == "string" then
			WEAPON_TYPE = weaponType
		else
			WEAPON_TYPE = tool.Name
		end

		-- Update crosshair style per weapon
		if WEAPON_TYPE == "Sniper Rifle" then
			crosshairLabel.Text = "[ + ]"
			crosshairLabel.TextSize = 22
			crosshairLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
		elseif WEAPON_TYPE == "Shotgun" then
			crosshairLabel.Text = "(+)"
			crosshairLabel.TextSize = 32
			crosshairLabel.TextColor3 = Color3.fromRGB(255, 180, 50)
		elseif WEAPON_TYPE == "RPG" then
			crosshairLabel.Text = "[X]"
			crosshairLabel.TextSize = 26
			crosshairLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		else
			crosshairLabel.Text = "+"
			crosshairLabel.TextSize = 28
			crosshairLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		end

		weaponLabel.Text = WEAPON_TYPE
	end)

	tool.Unequipped:Connect(function()
		equippedTool = nil
		crosshairGui.Enabled = false
	end)
end

-- Watch backpack and character for tools
local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(onChildAdded)
for _, child in backpack:GetChildren() do
	onChildAdded(child)
end

local function onCharacterAdded(character: Model)
	character.ChildAdded:Connect(onChildAdded)
	for _, child in character:GetChildren() do
		onChildAdded(child)
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- ── Input ────────────────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if equippedTool then
			shoot()
		end
	end
end)

-- Support holding down mouse button for auto-fire (rifle/shotgun)
local mouseDown = false

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDown = true
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDown = false
	end
end)

RunService.Heartbeat:Connect(function()
	if mouseDown and equippedTool then
		shoot()
	end
end)
