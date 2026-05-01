--!strict

--[[
	VehicleController.client.luau (LocalScript)
	---------------------------------------------
	Detects when the player sits in a VehicleSeat that belongs to a vehicle
	(identified by the "VehicleType" attribute on the vehicle Model).

	Responsibilities:
	  - Show/hide a speed HUD while driving
	  - Handle mouse click → fire weapon (Tank shell, Jet missile)
	  - Send pitch input for jets (W/S mapped to pitch)
	  - Camera follow for jets
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) :: any

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ── State ────────────────────────────────────────────────────────────────────

local currentVehicleType: string? = nil
local currentSeat: VehicleSeat? = nil
local currentModel: Model? = nil
local isDriving = false

-- Connections to clean up when exiting vehicle
local vehicleConnections: { RBXScriptConnection } = {}

-- ── HUD ──────────────────────────────────────────────────────────────────────

local screenGui: ScreenGui
local speedLabel: TextLabel
local vehicleTypeLabel: TextLabel
local crosshair: Frame

local function createHUD()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "VehicleHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	-- Speed indicator (bottom center)
	local speedFrame = Instance.new("Frame")
	speedFrame.Name = "SpeedFrame"
	speedFrame.Size = UDim2.new(0, 200, 0, 60)
	speedFrame.Position = UDim2.new(0.5, -100, 1, -80)
	speedFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	speedFrame.BackgroundTransparency = 0.4
	speedFrame.BorderSizePixel = 0
	speedFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = speedFrame

	speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "Speed"
	speedLabel.Size = UDim2.new(1, 0, 0.6, 0)
	speedLabel.Position = UDim2.new(0, 0, 0, 0)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Text = "0 SPD"
	speedLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	speedLabel.TextScaled = true
	speedLabel.Font = Enum.Font.Code
	speedLabel.Parent = speedFrame

	vehicleTypeLabel = Instance.new("TextLabel")
	vehicleTypeLabel.Name = "VehicleType"
	vehicleTypeLabel.Size = UDim2.new(1, 0, 0.4, 0)
	vehicleTypeLabel.Position = UDim2.new(0, 0, 0.6, 0)
	vehicleTypeLabel.BackgroundTransparency = 1
	vehicleTypeLabel.Text = ""
	vehicleTypeLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	vehicleTypeLabel.TextScaled = true
	vehicleTypeLabel.Font = Enum.Font.Gotham
	vehicleTypeLabel.Parent = speedFrame

	-- Crosshair (center, only for armed vehicles)
	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.Size = UDim2.new(0, 30, 0, 30)
	crosshair.Position = UDim2.new(0.5, -15, 0.5, -15)
	crosshair.BackgroundTransparency = 1
	crosshair.Visible = false
	crosshair.Parent = screenGui

	-- Crosshair lines
	local function makeLine(size: UDim2, pos: UDim2): Frame
		local line = Instance.new("Frame")
		line.Size = size
		line.Position = pos
		line.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
		line.BorderSizePixel = 0
		line.Parent = crosshair
		return line
	end

	makeLine(UDim2.new(0, 2, 0, 10), UDim2.new(0.5, -1, 0, 0))    -- top
	makeLine(UDim2.new(0, 2, 0, 10), UDim2.new(0.5, -1, 1, -10))   -- bottom
	makeLine(UDim2.new(0, 10, 0, 2), UDim2.new(0, 0, 0.5, -1))     -- left
	makeLine(UDim2.new(0, 10, 0, 2), UDim2.new(1, -10, 0.5, -1))   -- right
end

createHUD()

-- ── Vehicle enter/exit ───────────────────────────────────────────────────────

local function cleanupVehicle()
	for _, conn in vehicleConnections do
		conn:Disconnect()
	end
	vehicleConnections = {}

	isDriving = false
	currentVehicleType = nil
	currentSeat = nil
	currentModel = nil

	screenGui.Enabled = false
	crosshair.Visible = false

	-- Reset camera
	camera.CameraType = Enum.CameraType.Custom

	-- Reset pitch
	Remotes.VehiclePitch:FireServer(0)
end

local function onSeated(isSeated: boolean, seat: Seat?)
	if isSeated and seat and seat:IsA("VehicleSeat") then
		local model = seat:FindFirstAncestorOfClass("Model")
		if not model then
			return
		end

		local vType = model:GetAttribute("VehicleType")
		if type(vType) ~= "string" then
			return
		end

		currentVehicleType = vType :: string
		currentSeat = seat :: VehicleSeat
		currentModel = model
		isDriving = true

		-- Show HUD
		screenGui.Enabled = true
		vehicleTypeLabel.Text = vType :: string

		-- Show crosshair for armed vehicles
		local isArmed = (vType == "Tank" or vType == "FighterJet" or vType == "Helicopter" or vType == "Drone")
		crosshair.Visible = isArmed

		-- Speed update loop
		local speedConn = RunService.Heartbeat:Connect(function(_dt: number)
			if not isDriving or not currentModel or not currentModel.PrimaryPart then
				return
			end
			local velocity = currentModel.PrimaryPart.AssemblyLinearVelocity
			local speed = math.floor(velocity.Magnitude)
			speedLabel.Text = tostring(speed) .. " SPD"
		end)
		table.insert(vehicleConnections, speedConn)

		-- Jet camera and pitch controls
		if vType == "FighterJet" or vType == "Helicopter" or vType == "Drone" then
			-- Camera follow from behind
			local camConn = RunService.RenderStepped:Connect(function(_dt: number)
				if not isDriving or not currentModel or not currentModel.PrimaryPart then
					return
				end
				local body = currentModel.PrimaryPart
				local behindOffset = body.CFrame * CFrame.new(0, 6, 20)
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CFrame = CFrame.lookAt(behindOffset.Position, body.Position + body.CFrame.LookVector * -20)
			end)
			table.insert(vehicleConnections, camConn)

			-- Pitch input via keyboard
			local pitchConn = RunService.Heartbeat:Connect(function(_dt: number)
				if not isDriving then
					return
				end
				local pitchInput = 0
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then
					pitchInput += 1 -- pitch up
				end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then
					pitchInput -= 1 -- pitch down
				end
				Remotes.VehiclePitch:FireServer(pitchInput)
			end)
			table.insert(vehicleConnections, pitchConn)
		end

		-- Mouse click to fire weapon
		if isArmed then
			local mouseConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
				if gameProcessed then
					return
				end
				if not isDriving then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					local mouse = player:GetMouse()
					local targetPos = mouse.Hit.Position
					Remotes.VehicleShoot:FireServer(currentVehicleType, targetPos)
				end
			end)
			table.insert(vehicleConnections, mouseConn)
		end

	elseif not isSeated and isDriving then
		cleanupVehicle()
	end
end

-- ── Character wiring ─────────────────────────────────────────────────────────

local function onCharacterAdded(character: Model)
	-- Clean up if we were in a vehicle
	if isDriving then
		cleanupVehicle()
	end

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	humanoid.Seated:Connect(function(isSeated: boolean, seat: Seat?)
		onSeated(isSeated, seat)
	end)
end

-- Wire up current character
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
