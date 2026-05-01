--!strict

--[[
	BuildingBehaviors.luau
	----------------------
	Adds visual life to buildings after they're placed. Each building type
	gets an idle animation loop that makes it look "active":

	- RadarStation: dish rotates continuously
	- SAMSite: launcher scans back and forth, fires at incoming attacks
	- Helipad: corner lights blink
	- DroneHangar: status light pulses
	- NuclearSilo: warning light rotates
	- SpaceCommand: dome light pulses, antenna rotates

	Call StartBehavior(model) after placing a building to activate it.
	Call StopAllBehaviors(padNumber) when cleaning up.
]]

local TweenService = game:GetService("TweenService")

type CleanupFn = () -> ()

-- Track active behavior loops per pad so we can clean them up
local activeBehaviors: { [number]: { CleanupFn } } = {}

local BuildingBehaviors = {}

-- ── Radar Station: rotating dish ─────────────────────────────────────────────

local function radarBehavior(model: Model): CleanupFn
	local dish = model:FindFirstChild("Dish") or model:FindFirstChild("RadarDish")
	if not dish or not dish:IsA("BasePart") then
		return function() end
	end

	local running = true
	local baseCF = dish.CFrame
	local angle = 0

	task.spawn(function()
		while running do
			angle += 2 -- degrees per frame
			if angle >= 360 then
				angle -= 360
			end
			dish.CFrame = baseCF * CFrame.Angles(0, math.rad(angle), 0)
			task.wait()
		end
	end)

	return function()
		running = false
	end
end

-- ── SAM Site: launcher scans and fires ──────────────────────────────────────

local function samBehavior(model: Model): CleanupFn
	local launcher = model:FindFirstChild("Launcher")
	if not launcher or not launcher:IsA("BasePart") then
		return function() end
	end

	local running = true
	local baseCF = launcher.CFrame
	local time = 0

	-- Add a status light that blinks green (active scanning)
	local statusLight = Instance.new("PointLight")
	statusLight.Color = Color3.fromRGB(0, 255, 0)
	statusLight.Brightness = 2
	statusLight.Range = 15
	statusLight.Parent = launcher

	task.spawn(function()
		while running do
			time += 0.02
			-- Scan back and forth (rotate on Y axis)
			local scanAngle = math.sin(time * 0.8) * 45
			launcher.CFrame = baseCF * CFrame.Angles(0, math.rad(scanAngle), 0)

			-- Blink the status light
			statusLight.Brightness = 1.5 + math.sin(time * 3) * 0.5

			task.wait()
		end
	end)

	return function()
		running = false
		statusLight:Destroy()
	end
end

-- ── SAM Site: fire interceptor missile at incoming attack ────────────────────

function BuildingBehaviors.FireInterceptor(model: Model, targetPosition: Vector3)
	local launcher = model:FindFirstChild("Launcher")
	if not launcher or not launcher:IsA("BasePart") then
		return
	end

	-- Create a small missile Part that flies toward the target
	local missile = Instance.new("Part")
	missile.Size = Vector3.new(0.5, 0.5, 2)
	missile.Color = Color3.fromRGB(255, 100, 30)
	missile.Material = Enum.Material.Neon
	missile.Anchored = true
	missile.CanCollide = false
	missile.CastShadow = false
	missile.CFrame = launcher.CFrame

	-- Trail
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, -1)
	a0.Parent = missile
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, 1)
	a1.Parent = missile
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 150, 50), Color3.fromRGB(100, 100, 100))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = missile

	missile.Parent = workspace

	-- Animate toward target
	local startPos = launcher.Position + Vector3.new(0, 3, 0)
	local travelTime = 1.5

	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < travelTime do
			local t = (os.clock() - startTime) / travelTime
			local pos = startPos:Lerp(targetPosition, t)
			pos += Vector3.new(0, math.sin(t * math.pi) * 20, 0) -- arc upward
			local nextT = math.min(t + 0.01, 1)
			local nextPos = startPos:Lerp(targetPosition, nextT)
			missile.CFrame = CFrame.new(pos, nextPos)
			task.wait()
		end

		-- Explosion at intercept point
		local explosion = Instance.new("Part")
		explosion.Shape = Enum.PartType.Ball
		explosion.Size = Vector3.new(4, 4, 4)
		explosion.Color = Color3.fromRGB(255, 200, 50)
		explosion.Material = Enum.Material.Neon
		explosion.Anchored = true
		explosion.CanCollide = false
		explosion.CastShadow = false
		explosion.Position = targetPosition
		explosion.Parent = workspace

		local light = Instance.new("PointLight")
		light.Brightness = 5
		light.Range = 30
		light.Color = Color3.fromRGB(255, 200, 50)
		light.Parent = explosion

		TweenService:Create(explosion, TweenInfo.new(0.5), {
			Size = Vector3.new(15, 15, 15),
			Transparency = 1,
		}):Play()
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()

		missile:Destroy()
		task.delay(0.6, function()
			explosion:Destroy()
		end)
	end)
end

-- ── Helipad: blinking corner lights ──────────────────────────────────────────

local function helipadBehavior(model: Model): CleanupFn
	-- Find lights (if any corners have PointLights)
	local lights: { PointLight } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("PointLight") then
			table.insert(lights, desc)
		end
	end

	if #lights == 0 then
		return function() end
	end

	local running = true
	task.spawn(function()
		while running do
			for _, l in lights do
				l.Enabled = true
			end
			task.wait(0.8)
			for _, l in lights do
				l.Enabled = false
			end
			task.wait(0.8)
		end
	end)

	return function()
		running = false
	end
end

-- ── Nuclear Silo: pulsing warning light ──────────────────────────────────────

local function siloBehavior(model: Model): CleanupFn
	-- Add a rotating red warning light
	local silo = model.PrimaryPart
	if not silo then
		return function() end
	end

	local warningLight = Instance.new("PointLight")
	warningLight.Color = Color3.fromRGB(255, 50, 50)
	warningLight.Brightness = 0
	warningLight.Range = 20
	warningLight.Parent = silo

	local running = true
	local time = 0

	task.spawn(function()
		while running do
			time += 0.03
			warningLight.Brightness = 1 + math.sin(time * 2) * 1
			task.wait()
		end
	end)

	return function()
		running = false
		warningLight:Destroy()
	end
end

-- ── Space Command: dome glow pulse ──────────────────────────────────────────

local function spaceCommandBehavior(model: Model): CleanupFn
	local dome = model:FindFirstChild("Dome")
	if not dome or not dome:IsA("BasePart") then
		return function() end
	end

	local running = true
	local time = 0

	task.spawn(function()
		while running do
			time += 0.02
			dome.Transparency = 0.4 + math.sin(time * 1.5) * 0.15
			task.wait()
		end
	end)

	return function()
		running = false
	end
end

-- ── Generic: add ambient light to any building ──────────────────────────────

local function addAmbientLight(model: Model): CleanupFn
	local primary = model.PrimaryPart
	if not primary then
		return function() end
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 200)
	light.Brightness = 0.8
	light.Range = 20
	light.Parent = primary

	return function()
		light:Destroy()
	end
end

-- ── Income visualization: floating $ signs ──────────────────────────────────
-- Every building periodically spawns a green "$" BillboardGui that floats
-- upward and fades out, showing it's actively generating income.

local function incomeVisualization(model: Model, incomePerSecond: number): CleanupFn
	local primary = model.PrimaryPart
	if not primary then
		return function() end
	end

	local running = true
	-- Spawn a $ sign every few seconds (faster for higher income buildings)
	local interval = math.clamp(5 / math.max(incomePerSecond, 1), 1, 5)

	task.spawn(function()
		task.wait(math.random() * interval) -- stagger so they don't all sync
		while running do
			-- Create a floating $ Part with BillboardGui
			local floater = Instance.new("Part")
			floater.Size = Vector3.new(0.5, 0.5, 0.5)
			floater.Transparency = 1
			floater.Anchored = true
			floater.CanCollide = false
			floater.CastShadow = false
			-- Start from ground level in front of the building so player sees it
			floater.Position = primary.Position + Vector3.new(
				(math.random() - 0.5) * 8,
				1,
				-primary.Size.Z / 2 - 3 + (math.random() - 0.5) * 4
			)
			floater.Parent = workspace

			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.new(0, 80, 0, 40)
			gui.AlwaysOnTop = true
			gui.Parent = floater

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Text = "+$" .. tostring(incomePerSecond)
			label.TextColor3 = Color3.fromRGB(80, 255, 80)
			label.TextStrokeTransparency = 0
			label.TextStrokeColor3 = Color3.fromRGB(0, 40, 0)
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.Parent = gui

			-- Float upward and fade
			local startPos = floater.Position
			local startTime = os.clock()
			local duration = 2

			task.spawn(function()
				while os.clock() - startTime < duration do
					local t = (os.clock() - startTime) / duration
					floater.Position = startPos + Vector3.new(0, t * 14, 0)
					label.TextTransparency = t
					label.TextStrokeTransparency = 0.3 + t * 0.7
					task.wait()
				end
				floater:Destroy()
			end)

			task.wait(interval)
		end
	end)

	return function()
		running = false
	end
end

-- ── Public API ──────────────────────────────────────────────────────────────

function BuildingBehaviors.StartBehavior(padNumber: number, model: Model, buildingName: string, incomePerSecond: number?)
	if not activeBehaviors[padNumber] then
		activeBehaviors[padNumber] = {}
	end

	-- Specific building behavior
	local cleanup: CleanupFn
	if buildingName == "RadarStation" then
		cleanup = radarBehavior(model)
	elseif buildingName == "SAMSite" then
		cleanup = samBehavior(model)
	elseif buildingName == "Helipad" then
		cleanup = helipadBehavior(model)
	elseif buildingName == "NuclearSilo" then
		cleanup = siloBehavior(model)
	elseif buildingName == "SpaceCommand" then
		cleanup = spaceCommandBehavior(model)
	else
		cleanup = addAmbientLight(model)
	end
	table.insert(activeBehaviors[padNumber], cleanup)

	-- ALL buildings get income visualization (floating $ signs)
	local income = incomePerSecond or 0
	if income > 0 then
		local incomeCleanup = incomeVisualization(model, income)
		table.insert(activeBehaviors[padNumber], incomeCleanup)
	end
end

function BuildingBehaviors.StopAllBehaviors(padNumber: number)
	local behaviors = activeBehaviors[padNumber]
	if behaviors then
		for _, cleanup in behaviors do
			cleanup()
		end
		activeBehaviors[padNumber] = nil
	end
end

return BuildingBehaviors
