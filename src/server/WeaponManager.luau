--!strict

--[[
	WeaponManager.luau
	------------------
	Creates and gives weapon tools to players based on their unlocked buildings.

	Weapon progression:
	  1. Military Rifle  (default, given on claim)     — balanced auto rifle
	  2. Sniper Rifle    (requires SAMSite, tier 5)    — high damage, slow fire, long range
	  3. Shotgun         (requires Armory, tier 7)      — close range, high damage, spread
	  4. RPG             (requires DroneHangar, tier 9) — explosive, very slow, area damage
]]

local WeaponManager = {}

-- Weapon definitions
local WEAPONS = {
	{
		name = "Military Rifle",
		requiredBuilding = nil, -- given by default
		damage = 15,
		fireRate = 0.15,
		range = 200,
		handleSize = Vector3.new(0.5, 0.5, 3),
		handleColor = Color3.fromRGB(50, 50, 50),
		toolTip = "Military Rifle — Full auto, balanced",
	},
	{
		name = "Sniper Rifle",
		requiredBuilding = "SAMSite",
		damage = 65,
		fireRate = 1.2,
		range = 500,
		handleSize = Vector3.new(0.4, 0.4, 4),
		handleColor = Color3.fromRGB(30, 60, 30),
		toolTip = "Sniper Rifle — High damage, long range",
	},
	{
		name = "Shotgun",
		requiredBuilding = "Armory",
		damage = 45,
		fireRate = 0.6,
		range = 40,
		handleSize = Vector3.new(0.6, 0.5, 2.5),
		handleColor = Color3.fromRGB(80, 50, 30),
		toolTip = "Shotgun — Devastating at close range",
	},
	{
		name = "RPG",
		requiredBuilding = "DroneHangar",
		damage = 100,
		fireRate = 2.5,
		range = 300,
		handleSize = Vector3.new(0.8, 0.8, 3.5),
		handleColor = Color3.fromRGB(60, 80, 60),
		toolTip = "RPG — Explosive, area damage",
	},
}

--- Build a gun-shaped Handle Part.
local function createHandle(size: Vector3, color: Color3): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Color = color
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	return handle
end

--- Check if a player has a specific weapon in backpack or character.
local function hasWeapon(player: Player, weaponName: string): boolean
	local backpack = player:FindFirstChild("Backpack")
	if backpack and backpack:FindFirstChild(weaponName) then
		return true
	end
	local character = player.Character
	if character and character:FindFirstChild(weaponName) then
		return true
	end
	return false
end

--- Give a specific weapon tool to a player.
local function giveWeapon(player: Player, weaponDef: typeof(WEAPONS[1]))
	if hasWeapon(player, weaponDef.name) then
		return
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = weaponDef.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = weaponDef.toolTip

	-- Store weapon stats as attributes
	tool:SetAttribute("Damage", weaponDef.damage)
	tool:SetAttribute("FireRate", weaponDef.fireRate)
	tool:SetAttribute("Range", weaponDef.range)
	tool:SetAttribute("WeaponType", weaponDef.name)

	local handle = createHandle(weaponDef.handleSize, weaponDef.handleColor)
	handle.Parent = tool

	tool.Grip = CFrame.new(0, 0, -0.5)

	tool.Parent = backpack
end

-- Track which items each player has unlocked (for respawn re-give)
local playerUnlockedItems: { [Player]: { string } } = {}

--- Give the default Military Rifle tool to a player.
function WeaponManager.GiveDefaultWeapon(player: Player)
	giveWeapon(player, WEAPONS[1])

	-- Re-give all unlocked weapons on respawn
	player.CharacterAdded:Connect(function()
		task.defer(function()
			giveWeapon(player, WEAPONS[1])
			local items = playerUnlockedItems[player]
			if items then
				WeaponManager.UpdateWeapons(player, items)
			end
		end)
	end)
end

--- Give all weapons the player has unlocked based on their buildings.
function WeaponManager.UpdateWeapons(player: Player, unlockedItems: { string })
	-- Cache for respawn
	playerUnlockedItems[player] = unlockedItems

	local unlockedSet: { [string]: boolean } = {}
	for _, item in unlockedItems do
		unlockedSet[item] = true
	end

	for _, weaponDef in WEAPONS do
		if weaponDef.requiredBuilding == nil then
			giveWeapon(player, weaponDef)
		elseif unlockedSet[weaponDef.requiredBuilding] then
			giveWeapon(player, weaponDef)
		end
	end
end

--- Clean up player data on leave.
function WeaponManager.OnPlayerRemoving(player: Player)
	playerUnlockedItems[player] = nil
end

return WeaponManager
