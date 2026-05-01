--!strict

--[[
	DamageHandler.server.luau
	-------------------------
	Server-authoritative damage system for FPS combat. Validates shots,
	applies damage, awards kill bounties, and broadcasts kill feed events.

	Supports multiple weapon types with different damage values.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) :: any

-- ── Weapon stats (server authority) ─────────────────────────────────────────

local WEAPON_STATS: { [string]: { damage: number, range: number } } = {
	["Military Rifle"] = { damage = 15, range = 200 },
	["Sniper Rifle"]   = { damage = 65, range = 500 },
	["Shotgun"]        = { damage = 45, range = 40 },
	["RPG"]            = { damage = 100, range = 300 },
}

local KILL_REWARD = 500

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function getCharacterFromPlayer(p: Player): Model?
	return p.Character
end

local function getEquippedWeapon(p: Player): (Tool?, string?)
	local character = getCharacterFromPlayer(p)
	if not character then
		return nil, nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and WEAPON_STATS[child.Name] then
			return child :: Tool, child.Name
		end
	end
	return nil, nil
end

local function getShooterPosition(p: Player): Vector3?
	local character = getCharacterFromPlayer(p)
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	return hrp.Position
end

-- ── Shot handler ─────────────────────────────────────────────────────────────

Remotes.ShootPlayer.OnServerEvent:Connect(function(shooter: Player, hitPosition: unknown, targetPartName: unknown)
	-- Type validation
	if typeof(hitPosition) ~= "Vector3" then
		return
	end
	local hitPos = hitPosition :: Vector3

	-- Validate shooter has a weapon equipped
	local _, weaponName = getEquippedWeapon(shooter)
	if not weaponName then
		return
	end

	local stats = WEAPON_STATS[weaponName]
	if not stats then
		return
	end

	-- Get shooter position for range check
	local shooterPos = getShooterPosition(shooter)
	if not shooterPos then
		return
	end

	-- Range check (add tolerance for network latency)
	local distance = (hitPos - shooterPos).Magnitude
	if distance > stats.range + 30 then
		return
	end

	-- Server-side raycast to verify the shot
	local shooterCharacter = getCharacterFromPlayer(shooter)
	if not shooterCharacter then
		return
	end

	local shooterHead = shooterCharacter:FindFirstChild("Head") :: BasePart?
	if not shooterHead then
		return
	end

	local direction = (hitPos - shooterHead.Position).Unit * stats.range
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { shooterCharacter }

	local rayResult = workspace:Raycast(shooterHead.Position, direction, rayParams)
	if not rayResult then
		return
	end

	-- Check if we hit a character
	local hitPart = rayResult.Instance
	local hitModel = hitPart.Parent
	if hitModel and hitModel:IsA("Accessory") then
		hitModel = hitModel.Parent
	end
	if not hitModel or not hitModel:IsA("Model") then
		return
	end

	local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local victim = Players:GetPlayerFromCharacter(hitModel)
	if not victim or victim == shooter then
		return
	end

	-- Apply damage
	humanoid:TakeDamage(stats.damage)

	-- Check for kill
	if humanoid.Health <= 0 then
		-- Award kill bounty
		if _G.CombatRewardFunds then
			_G.CombatRewardFunds(shooter, KILL_REWARD)
		end

		-- Broadcast kill feed to all clients
		Remotes.KillFeed:FireAllClients(shooter.Name, victim.Name)

		print(
			string.format(
				"[DamageHandler] %s eliminated %s with %s (+$%d bounty)",
				shooter.Name,
				victim.Name,
				weaponName,
				KILL_REWARD
			)
		)
	end
end)

print("[DamageHandler] FPS combat system loaded — multi-weapon support active")
