--!strict
-- CombatEffects.client.luau
-- Visual effects for combat: missile trails, explosions, screen shake,
-- attack warning sirens, and projectile animations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes", 30) :: ModuleScript)

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ── Constants ────────────────────────────────────────────────────────────────

local PAD_SPACING = 300
local EXPLOSION_COLORS = {
	Color3.fromRGB(255, 120, 30), -- orange
	Color3.fromRGB(255, 60, 20), -- red-orange
	Color3.fromRGB(255, 200, 50), -- yellow
}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function padOrigin(padNumber: number): Vector3
	return Vector3.new((padNumber - 1) * PAD_SPACING, 0, 150)
end

-- Screen shake effect
local function screenShake(intensity: number, duration: number)
	task.spawn(function()
		local cam = Camera
		if not cam then
			return
		end
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			local t = (os.clock() - startTime) / duration
			local fade = 1 - t -- intensity fades over time
			local offset = CFrame.new(
				(math.random() - 0.5) * intensity * fade,
				(math.random() - 0.5) * intensity * fade,
				0
			)
			cam.CFrame = cam.CFrame * offset
			task.wait()
		end
	end)
end

-- Create explosion effect at position
local function createExplosion(position: Vector3, scale: number)
	-- Fireball sphere
	local fireball = Instance.new("Part")
	fireball.Shape = Enum.PartType.Ball
	fireball.Size = Vector3.new(4, 4, 4) * scale
	fireball.CFrame = CFrame.new(position)
	fireball.Anchored = true
	fireball.CanCollide = false
	fireball.CastShadow = false
	fireball.Material = Enum.Material.Neon
	fireball.Color = EXPLOSION_COLORS[1]
	fireball.Parent = Workspace

	-- Light
	local light = Instance.new("PointLight")
	light.Brightness = 5
	light.Range = 60 * scale
	light.Color = EXPLOSION_COLORS[3]
	light.Parent = fireball

	-- Expand and fade
	local expandInfo = TweenInfo.new(0.6, Enum.EasingStyle.Expo, Enum.EasingDirection.Out)
	local expandTween = TweenService:Create(fireball, expandInfo, {
		Size = Vector3.new(30, 30, 30) * scale,
		Transparency = 1,
	})
	local lightTween = TweenService:Create(light, expandInfo, { Brightness = 0 })

	expandTween:Play()
	lightTween:Play()

	-- Smoke ring
	local smoke = Instance.new("Part")
	smoke.Shape = Enum.PartType.Ball
	smoke.Size = Vector3.new(2, 2, 2) * scale
	smoke.CFrame = CFrame.new(position + Vector3.new(0, 5, 0))
	smoke.Anchored = true
	smoke.CanCollide = false
	smoke.CastShadow = false
	smoke.Material = Enum.Material.SmoothPlastic
	smoke.Color = Color3.fromRGB(80, 80, 80)
	smoke.Transparency = 0.3
	smoke.Parent = Workspace

	local smokeTween = TweenService:Create(smoke, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(50, 50, 50) * scale,
		Transparency = 1,
		CFrame = CFrame.new(position + Vector3.new(0, 30, 0)),
	})
	smokeTween:Play()

	expandTween.Completed:Connect(function()
		fireball:Destroy()
	end)
	smokeTween.Completed:Connect(function()
		smoke:Destroy()
	end)
end

-- Create missile/projectile that flies from A to B
local function createProjectile(
	from: Vector3,
	to: Vector3,
	travelTime: number,
	attackType: string
)
	local projectile = Instance.new("Part")
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CastShadow = false

	if attackType == "MissileStrike" then
		projectile.Size = Vector3.new(1, 1, 4)
		projectile.Color = Color3.fromRGB(200, 200, 200)
		projectile.Material = Enum.Material.Metal
	elseif attackType == "AirStrike" then
		projectile.Size = Vector3.new(2, 1, 5)
		projectile.Color = Color3.fromRGB(100, 110, 100)
		projectile.Material = Enum.Material.SmoothPlastic
	elseif attackType == "NavalBombardment" then
		projectile.Size = Vector3.new(1, 1, 2)
		projectile.Color = Color3.fromRGB(60, 60, 60)
		projectile.Material = Enum.Material.Metal
	else
		projectile.Size = Vector3.new(1, 2, 1)
		projectile.Color = Color3.fromRGB(50, 70, 50)
		projectile.Material = Enum.Material.SmoothPlastic
	end

	-- Start position (with arc for missiles)
	local arcHeight = if attackType == "MissileStrike" then 200 else 80
	local startPos = from + Vector3.new(0, 20, 0)
	local midPos = (from + to) / 2 + Vector3.new(0, arcHeight, 0)
	local endPos = to + Vector3.new(0, 5, 0)

	projectile.CFrame = CFrame.new(startPos, midPos)
	projectile.Parent = Workspace

	-- Trail effect
	local trail = Instance.new("Trail")
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, -projectile.Size.Z / 2)
	a0.Parent = projectile
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, projectile.Size.Z / 2)
	a1.Parent = projectile
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 1.5
	trail.MinLength = 0.1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), Color3.fromRGB(150, 150, 150))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = projectile

	-- Animate along arc
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < travelTime do
			local t = (os.clock() - startTime) / travelTime
			-- Quadratic bezier: (1-t)^2*P0 + 2*(1-t)*t*P1 + t^2*P2
			local p = (1 - t) * (1 - t) * startPos + 2 * (1 - t) * t * midPos + t * t * endPos
			local nextT = math.min(t + 0.01, 1)
			local nextP = (1 - nextT) * (1 - nextT) * startPos + 2 * (1 - nextT) * nextT * midPos + nextT * nextT * endPos
			projectile.CFrame = CFrame.new(p, nextP)
			task.wait()
		end

		-- Impact
		projectile:Destroy()

		-- Explosion at target
		local explosionScale = if attackType == "MissileStrike" then 2 else 1
		createExplosion(endPos, explosionScale)

		-- Screen shake if nearby
		local character = LocalPlayer.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local dist = (hrp.Position - endPos).Magnitude
				if dist < 300 then
					local shakeIntensity = math.clamp(1 - dist / 300, 0.1, 1) * (if attackType == "MissileStrike" then 2 else 1)
					screenShake(shakeIntensity, 0.5)
				end
			end
		end
	end)
end

-- ── Remote Listeners ─────────────────────────────────────────────────────────

Remotes.AttackLaunched.OnClientEvent:Connect(function(
	attackType: string,
	fromPad: number,
	toPad: number,
	travelTime: number
)
	local fromPos = padOrigin(fromPad)
	local toPos = padOrigin(toPad)
	createProjectile(fromPos, toPos, travelTime, attackType)
end)

-- Screen shake when our base takes damage
Remotes.BaseDamaged.OnClientEvent:Connect(function(_hp: number, _maxHP: number, damage: number, _attackType: string)
	if damage > 0 then
		screenShake(0.5, 0.3)
	end
end)

-- Big shake + flash on destruction
Remotes.BaseDestroyed.OnClientEvent:Connect(function(_attackerName: string)
	screenShake(2, 1.5)
end)
