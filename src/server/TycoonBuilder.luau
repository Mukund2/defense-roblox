--!strict

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig = require(ReplicatedStorage.TycoonConfig) :: any
local BuildingBehaviors = require(script.Parent:WaitForChild("BuildingBehaviors")) :: any

-- ── Types ─────────────────────────────────────────────────────────────────────

type TycoonItemCategory = "Building" | "Vehicle" | "Aircraft" | "Naval" | "Strategic"

-- ── Constants ─────────────────────────────────────────────────────────────────

local PAD_SPACING = 500 -- kept for reference; actual positions use PAD_POSITIONS
local TYCOON_FOLDER_PREFIX = "Tycoon_Pad_"

-- Circular layout: 4 bases at compass points around the central spawn
local PAD_POSITIONS = {
	Vector3.new(0, 0, 300),    -- North
	Vector3.new(300, 0, 0),    -- East
	Vector3.new(0, 0, -300),   -- South
	Vector3.new(-300, 0, 0),   -- West
}

-- Button styling (flat circular pads)
local BUTTON_COLOR = BrickColor.new("Lime green")
local BUTTON_MATERIAL = Enum.Material.Neon
local BUTTON_DIAMETER = 10
local BUTTON_HEIGHT = 1
local BUTTON_HEIGHT_OFFSET = 0.5

-- Drop-in animation constants
local DROP_HEIGHT = 30
local DROP_DURATION = 0.5

-- ── Fixed building positions (offset from pad origin) ─────────────────────────
-- Layout follows a military base progression from spawn (low Z) to deep base (high Z).
-- X=0 is center. Negative X is left, positive X is right.

local BUILDING_POSITIONS: { [string]: Vector3 } = {
	CommandCenter        = Vector3.new(0, 0, 40),
	Barracks             = Vector3.new(-35, 0, 80),
	MotorPool            = Vector3.new(35, 0, 80),
	RadarStation         = Vector3.new(-35, 0, 120),
	SAMSite              = Vector3.new(35, 0, 120),
	Helipad              = Vector3.new(-35, 0, 160),
	Armory               = Vector3.new(35, 0, 160),
	TankDepot            = Vector3.new(-35, 0, 200),
	DroneHangar          = Vector3.new(35, 0, 200),
	FighterJetHangar     = Vector3.new(0, 0, 240),
	SubmarinePen         = Vector3.new(-35, 0, 280),
	AircraftCarrierDock  = Vector3.new(35, 0, 280),
	StealthBomberBay     = Vector3.new(-35, 0, 320),
	NuclearSilo          = Vector3.new(35, 0, 320),
	SpaceCommand         = Vector3.new(0, 0, 360),
}

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function padOriginCFrame(padNumber: number): CFrame
	return CFrame.new(PAD_POSITIONS[padNumber] or Vector3.new(0, 0, 0))
end

local function getOrCreatePadFolder(padNumber: number): Folder
	local folderName = TYCOON_FOLDER_PREFIX .. tostring(padNumber)
	local existing = workspace:FindFirstChild(folderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = workspace
	return folder
end

local function itemOrder(itemName: string): number
	for i, item in ipairs(TycoonConfig.Ordered) do
		if item.modelName == itemName then
			return i
		end
	end
	return 0
end

local function nextUnlockable(unlockedItems: { string }): any?
	local unlockedSet: { [string]: boolean } = {}
	for _, name in unlockedItems do
		unlockedSet[name] = true
	end
	for _, item in ipairs(TycoonConfig.Ordered) do
		if not unlockedSet[item.modelName] then
			return item
		end
	end
	return nil
end

--- Get the world CFrame for a building, given the pad origin and model name.
local function buildingCFrame(padOrigin: CFrame, modelName: string): CFrame
	local pos = BUILDING_POSITIONS[modelName]
	if pos then
		return padOrigin + pos
	end
	-- Fallback: shouldn't happen, but place at center
	return padOrigin + Vector3.new(0, 0, 50)
end

-- ── Drop-in animation ─────────────────────────────────────────────────────────
-- Drops a model from above with bounce easing and transparency fade.

local function dropInAnimation(model: Model, targetCF: CFrame)
	-- Collect all BaseParts in the model
	local parts: { BasePart } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end

	-- Also include PrimaryPart if it's a BasePart at top level
	if model.PrimaryPart and not table.find(parts, model.PrimaryPart) then
		table.insert(parts, model.PrimaryPart)
	end

	-- Calculate model-relative offsets from the target position
	-- The model is already built at targetCF, so we shift it UP and make it transparent
	local offsets: { [BasePart]: CFrame } = {}
	for _, part in parts do
		offsets[part] = part.CFrame
		-- Move part up by DROP_HEIGHT
		part.CFrame = part.CFrame + Vector3.new(0, DROP_HEIGHT, 0)
		part.Transparency = 1
	end

	-- Tween each part down to its target and fade in
	local tweenInfo = TweenInfo.new(DROP_DURATION, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(DROP_DURATION * 0.6, Enum.EasingStyle.Linear)

	for _, part in parts do
		local targetPartCF = offsets[part]
		-- Determine the final transparency (some parts like Glass might already be semi-transparent)
		-- We default to 0 unless the part name suggests transparency
		local finalTransparency = 0
		if part.Material == Enum.Material.Glass then
			finalTransparency = 0.3
		end

		local moveTween = TweenService:Create(part, tweenInfo, {
			CFrame = targetPartCF,
		})
		local fadeTween = TweenService:Create(part, fadeInfo, {
			Transparency = finalTransparency,
		})
		moveTween:Play()
		fadeTween:Play()
	end

	-- Dust/impact particle effect on landing
	task.delay(DROP_DURATION, function()
		local dustPart = Instance.new("Part")
		dustPart.Name = "DustEffect"
		dustPart.Anchored = true
		dustPart.CanCollide = false
		dustPart.Transparency = 1
		dustPart.Size = Vector3.new(1, 1, 1)
		dustPart.CFrame = targetCF
		dustPart.Parent = workspace

		local dust = Instance.new("ParticleEmitter")
		dust.Color = ColorSequence.new(Color3.fromRGB(180, 160, 130))
		dust.Rate = 0
		dust.Lifetime = NumberRange.new(0.8, 1.2)
		dust.Speed = NumberRange.new(8, 15)
		dust.SpreadAngle = Vector2.new(60, 60)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(1, 0),
		})
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Parent = dustPart

		-- Burst particles
		dust:Emit(25)

		task.delay(1.5, function()
			dustPart:Destroy()
		end)
	end)
end

-- ── Billboard GUI helpers ─────────────────────────────────────────────────────

local function createButtonGui(parent: Part, itemName: string, cost: number, incomePerSecond: number, _description: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ButtonGui"
	billboard.Size = UDim2.new(0, 350, 0, 120)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0.3, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = itemName
	label.Parent = billboard

	local costFrame = Instance.new("Frame")
	costFrame.Name = "CostFrame"
	costFrame.Size = UDim2.new(0.7, 0, 0.3, 0)
	costFrame.Position = UDim2.new(0.15, 0, 0.3, 0)
	costFrame.BackgroundColor3 = Color3.fromRGB(30, 120, 30)
	costFrame.BackgroundTransparency = 0.3
	costFrame.Parent = billboard
	local costCorner = Instance.new("UICorner")
	costCorner.CornerRadius = UDim.new(0, 6)
	costCorner.Parent = costFrame

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, 0, 1, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.TextColor3 = Color3.new(1, 0.85, 0)
	costLabel.TextScaled = true
	costLabel.Font = Enum.Font.GothamBold
	costLabel.Text = "$" .. tostring(cost)
	costLabel.Parent = costFrame

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "IncomeLabel"
	incomeLabel.Size = UDim2.new(1, 0, 0.3, 0)
	incomeLabel.Position = UDim2.new(0, 0, 0.65, 0)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
	incomeLabel.TextScaled = true
	incomeLabel.Font = Enum.Font.GothamBold
	incomeLabel.Text = "+$" .. tostring(incomePerSecond) .. "/sec"
	incomeLabel.Parent = billboard
end

local function createNameGui(parent: Instance, text: string, heightOffset: number)
	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "NameGui"
	nameGui.Size = UDim2.new(0, 200, 0, 40)
	nameGui.StudsOffset = Vector3.new(0, heightOffset, 0)
	nameGui.AlwaysOnTop = false
	nameGui.Parent = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = text
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Parent = nameGui
end

-- ── Building construction functions ───────────────────────────────────────────
-- Each function creates a Model with multiple Parts and returns it.
-- The Model's PrimaryPart bottom sits at ground level (Y=0 relative to the model).

local function makePart(model: Model, name: string, size: Vector3, cf: CFrame, color: BrickColor, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.Size = size
	p.CFrame = cf
	p.BrickColor = color
	p.Material = material
	p.Parent = model
	return p
end

local function makeWedge(model: Model, name: string, size: Vector3, cf: CFrame, color: BrickColor, material: Enum.Material): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = true
	w.Size = size
	w.CFrame = cf
	w.BrickColor = color
	w.Material = material
	w.Parent = model
	return w
end

local function buildCommandCenter(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "CommandCenter"
	-- Main body: olive green box 20x10x16
	local body = makePart(m, "Body", Vector3.new(20, 10, 16), origin + Vector3.new(0, 5, 0),
		BrickColor.new("Olive"), Enum.Material.Concrete)
	m.PrimaryPart = body
	-- Flat dark roof
	makePart(m, "Roof", Vector3.new(22, 1, 18), origin + Vector3.new(0, 10.5, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	-- Antenna on roof
	makePart(m, "Antenna", Vector3.new(0.5, 6, 0.5), origin + Vector3.new(8, 14, 6),
		BrickColor.new("Medium stone grey"), Enum.Material.Metal)
	-- Door (dark inset)
	makePart(m, "Door", Vector3.new(4, 6, 0.5), origin + Vector3.new(0, 3, -8.2),
		BrickColor.new("Really black"), Enum.Material.SmoothPlastic)
	return m
end

local function buildBarracks(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Barracks"
	-- Long tan building 24x8x12
	local body = makePart(m, "Body", Vector3.new(24, 8, 12), origin + Vector3.new(0, 4, 0),
		BrickColor.new("Brick yellow"), Enum.Material.Concrete)
	m.PrimaryPart = body
	-- Triangular roof using two wedges
	makeWedge(m, "RoofLeft", Vector3.new(24, 4, 6), origin * CFrame.new(-0, 12, -3) * CFrame.Angles(0, 0, 0),
		BrickColor.new("Reddish brown"), Enum.Material.Wood)
	makeWedge(m, "RoofRight", Vector3.new(24, 4, 6), origin * CFrame.new(0, 12, 3) * CFrame.Angles(0, math.rad(180), 0),
		BrickColor.new("Reddish brown"), Enum.Material.Wood)
	-- Windows (small dark rectangles on front)
	for i = -2, 2 do
		makePart(m, "Window_" .. tostring(i), Vector3.new(2, 2, 0.3), origin + Vector3.new(i * 5, 5, -6.2),
			BrickColor.new("Really black"), Enum.Material.Glass)
	end
	return m
end

local function buildMotorPool(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "MotorPool"
	-- Open-sided garage: 3 walls, no front. Olive green. 20x8x16
	-- Back wall
	local back = makePart(m, "BackWall", Vector3.new(20, 8, 1), origin + Vector3.new(0, 4, 8),
		BrickColor.new("Olive"), Enum.Material.Concrete)
	m.PrimaryPart = back
	-- Left wall
	makePart(m, "LeftWall", Vector3.new(1, 8, 16), origin + Vector3.new(-10, 4, 0),
		BrickColor.new("Olive"), Enum.Material.Concrete)
	-- Right wall
	makePart(m, "RightWall", Vector3.new(1, 8, 16), origin + Vector3.new(10, 4, 0),
		BrickColor.new("Olive"), Enum.Material.Concrete)
	-- Flat roof
	makePart(m, "Roof", Vector3.new(22, 0.5, 18), origin + Vector3.new(0, 8.25, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	-- Floor (concrete)
	makePart(m, "Floor", Vector3.new(20, 0.3, 16), origin + Vector3.new(0, 0.15, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	return m
end

local function buildRadarStation(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "RadarStation"
	-- Thin tower 2x20x2
	local tower = makePart(m, "Tower", Vector3.new(3, 20, 3), origin + Vector3.new(0, 10, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Metal)
	m.PrimaryPart = tower
	-- Rotating dish: flat cylinder on top
	local dish = Instance.new("Part")
	dish.Name = "Dish"
	dish.Anchored = true
	dish.CanCollide = true
	dish.Shape = Enum.PartType.Cylinder
	dish.Size = Vector3.new(1, 10, 10)
	dish.CFrame = origin * CFrame.new(0, 22, 0) * CFrame.Angles(0, 0, math.rad(90))
	dish.BrickColor = BrickColor.new("White")
	dish.Material = Enum.Material.Metal
	dish.Parent = m
	-- Base platform
	makePart(m, "Base", Vector3.new(8, 1, 8), origin + Vector3.new(0, 0.5, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Concrete)
	return m
end

local function buildSAMSite(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "SAMSite"
	-- Low platform 10x2x10
	local platform = makePart(m, "Platform", Vector3.new(12, 2, 12), origin + Vector3.new(0, 1, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Concrete)
	m.PrimaryPart = platform
	-- Angled launcher tube (rotated 45 degrees)
	local launcher = makePart(m, "Launcher", Vector3.new(2, 8, 2),
		origin * CFrame.new(0, 5, 0) * CFrame.Angles(math.rad(-45), 0, 0),
		BrickColor.new("Olive"), Enum.Material.Metal)
	launcher.CanCollide = true
	-- Missile tip (small red part)
	makePart(m, "Missile", Vector3.new(1, 3, 1),
		origin * CFrame.new(0, 8.5, -3.5) * CFrame.Angles(math.rad(-45), 0, 0),
		BrickColor.new("Bright red"), Enum.Material.Metal)
	return m
end

local function buildHelipad(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Helipad"
	-- Flat concrete pad 20x0.5x20
	local pad = makePart(m, "Pad", Vector3.new(20, 0.5, 20), origin + Vector3.new(0, 0.25, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	m.PrimaryPart = pad
	-- "H" marking made of 3 yellow parts
	makePart(m, "H_Left", Vector3.new(2, 0.15, 10), origin + Vector3.new(-3, 0.6, 0),
		BrickColor.new("Bright yellow"), Enum.Material.SmoothPlastic)
	makePart(m, "H_Right", Vector3.new(2, 0.15, 10), origin + Vector3.new(3, 0.6, 0),
		BrickColor.new("Bright yellow"), Enum.Material.SmoothPlastic)
	makePart(m, "H_Mid", Vector3.new(8, 0.15, 2), origin + Vector3.new(0, 0.6, 0),
		BrickColor.new("Bright yellow"), Enum.Material.SmoothPlastic)
	-- Corner lights
	for _, xSign in ipairs({ -1, 1 }) do
		for _, zSign in ipairs({ -1, 1 }) do
			local light = makePart(m, "Light", Vector3.new(1, 2, 1),
				origin + Vector3.new(xSign * 9, 1, zSign * 9),
				BrickColor.new("Bright yellow"), Enum.Material.Neon)
			light.CanCollide = true
		end
	end
	return m
end

local function buildArmory(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Armory"
	-- Reinforced brick building 14x10x14
	local body = makePart(m, "Body", Vector3.new(14, 10, 14), origin + Vector3.new(0, 5, 0),
		BrickColor.new("Reddish brown"), Enum.Material.Brick)
	m.PrimaryPart = body
	-- Metal reinforcement strips
	makePart(m, "Strip1", Vector3.new(14.5, 0.5, 14.5), origin + Vector3.new(0, 3, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	makePart(m, "Strip2", Vector3.new(14.5, 0.5, 14.5), origin + Vector3.new(0, 7, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	-- Flat metal roof
	makePart(m, "Roof", Vector3.new(15, 0.5, 15), origin + Vector3.new(0, 10.25, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	-- Heavy door
	makePart(m, "Door", Vector3.new(5, 7, 0.5), origin + Vector3.new(0, 3.5, -7.2),
		BrickColor.new("Dark stone grey"), Enum.Material.DiamondPlate)
	return m
end

local function buildTankDepot(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "TankDepot"
	-- Wide garage with thick walls. Dark green. 24x8x20
	-- Back wall (thick)
	local back = makePart(m, "BackWall", Vector3.new(24, 8, 2), origin + Vector3.new(0, 4, 10),
		BrickColor.new("Earth green"), Enum.Material.Concrete)
	m.PrimaryPart = back
	-- Left wall
	makePart(m, "LeftWall", Vector3.new(2, 8, 20), origin + Vector3.new(-12, 4, 0),
		BrickColor.new("Earth green"), Enum.Material.Concrete)
	-- Right wall
	makePart(m, "RightWall", Vector3.new(2, 8, 20), origin + Vector3.new(12, 4, 0),
		BrickColor.new("Earth green"), Enum.Material.Concrete)
	-- Roof
	makePart(m, "Roof", Vector3.new(26, 1, 22), origin + Vector3.new(0, 8.5, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	-- Floor
	makePart(m, "Floor", Vector3.new(24, 0.3, 20), origin + Vector3.new(0, 0.15, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	return m
end

local function buildDroneHangar(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "DroneHangar"
	-- Curved roof using a horizontal cylinder. White/gray. 16x10x16
	-- Base walls
	makePart(m, "LeftWall", Vector3.new(1, 6, 16), origin + Vector3.new(-8, 3, 0),
		BrickColor.new("White"), Enum.Material.SmoothPlastic)
	makePart(m, "RightWall", Vector3.new(1, 6, 16), origin + Vector3.new(8, 3, 0),
		BrickColor.new("White"), Enum.Material.SmoothPlastic)
	makePart(m, "BackWall", Vector3.new(16, 6, 1), origin + Vector3.new(0, 3, 8),
		BrickColor.new("White"), Enum.Material.SmoothPlastic)
	-- Curved roof (cylinder lying on its side along Z axis)
	local roof = Instance.new("Part")
	roof.Name = "CurvedRoof"
	roof.Anchored = true
	roof.CanCollide = true
	roof.Shape = Enum.PartType.Cylinder
	roof.Size = Vector3.new(18, 18, 18)
	roof.CFrame = origin * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.rad(90))
	roof.BrickColor = BrickColor.new("Medium stone grey")
	roof.Material = Enum.Material.Metal
	roof.Parent = m
	m.PrimaryPart = roof
	-- Floor
	makePart(m, "Floor", Vector3.new(16, 0.3, 16), origin + Vector3.new(0, 0.15, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	return m
end

local function buildFighterJetHangar(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "FighterJetHangar"
	-- Very large hangar with wide opening. 30x12x24
	local back = makePart(m, "BackWall", Vector3.new(30, 12, 2), origin + Vector3.new(0, 6, 12),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	m.PrimaryPart = back
	makePart(m, "LeftWall", Vector3.new(2, 12, 24), origin + Vector3.new(-15, 6, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	makePart(m, "RightWall", Vector3.new(2, 12, 24), origin + Vector3.new(15, 6, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	-- Large roof
	makePart(m, "Roof", Vector3.new(32, 1, 26), origin + Vector3.new(0, 12.5, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	-- Floor
	makePart(m, "Floor", Vector3.new(30, 0.3, 24), origin + Vector3.new(0, 0.15, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	-- Red stripe on front edge
	makePart(m, "Stripe", Vector3.new(30, 1, 0.5), origin + Vector3.new(0, 0.5, -12),
		BrickColor.new("Bright red"), Enum.Material.Neon)
	return m
end

local function buildSubmarinePen(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "SubmarinePen"
	-- Dark building near water. 20x8x30
	local body = makePart(m, "Body", Vector3.new(20, 8, 30), origin + Vector3.new(0, 4, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Concrete)
	m.PrimaryPart = body
	-- Roof
	makePart(m, "Roof", Vector3.new(22, 0.5, 32), origin + Vector3.new(0, 8.25, 0),
		BrickColor.new("Really black"), Enum.Material.Metal)
	-- Water channel inside (blue strip on floor)
	makePart(m, "Channel", Vector3.new(8, 0.2, 30), origin + Vector3.new(0, 0.1, 0),
		BrickColor.new("Bright blue"), Enum.Material.Glass)
	-- Caution stripes at entrance
	makePart(m, "CautionL", Vector3.new(1, 8, 0.5), origin + Vector3.new(-10, 4, -15),
		BrickColor.new("Bright yellow"), Enum.Material.Neon)
	makePart(m, "CautionR", Vector3.new(1, 8, 0.5), origin + Vector3.new(10, 4, -15),
		BrickColor.new("Bright yellow"), Enum.Material.Neon)
	return m
end

local function buildAircraftCarrierDock(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "AircraftCarrierDock"
	-- Large dock structure 16x6x30
	local body = makePart(m, "Body", Vector3.new(16, 6, 30), origin + Vector3.new(0, 3, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
	m.PrimaryPart = body
	-- Crane arm on top
	makePart(m, "CraneBase", Vector3.new(3, 10, 3), origin + Vector3.new(6, 11, 10),
		BrickColor.new("Bright yellow"), Enum.Material.Metal)
	makePart(m, "CraneArm", Vector3.new(1, 1, 16), origin + Vector3.new(6, 16.5, 2),
		BrickColor.new("Bright yellow"), Enum.Material.Metal)
	-- Bollards (mooring posts)
	for i = -2, 2 do
		makePart(m, "Bollard_" .. tostring(i), Vector3.new(1, 2, 1), origin + Vector3.new(-8.5, 7, i * 7),
			BrickColor.new("Dark stone grey"), Enum.Material.Metal)
	end
	return m
end

local function buildStealthBomberBay(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "StealthBomberBay"
	-- Bunker-style, partially underground look. 20x6x20
	local body = makePart(m, "Body", Vector3.new(20, 6, 20), origin + Vector3.new(0, 1, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Concrete)
	m.PrimaryPart = body
	-- Earth berm around edges (simulates buried look)
	makePart(m, "BermLeft", Vector3.new(3, 4, 22), origin + Vector3.new(-11.5, 0, 0),
		BrickColor.new("Reddish brown"), Enum.Material.Slate)
	makePart(m, "BermRight", Vector3.new(3, 4, 22), origin + Vector3.new(11.5, 0, 0),
		BrickColor.new("Reddish brown"), Enum.Material.Slate)
	makePart(m, "BermBack", Vector3.new(26, 4, 3), origin + Vector3.new(0, 0, 11.5),
		BrickColor.new("Reddish brown"), Enum.Material.Slate)
	-- Heavy blast door at front
	makePart(m, "BlastDoor", Vector3.new(12, 5, 1), origin + Vector3.new(0, 1.5, -10),
		BrickColor.new("Medium stone grey"), Enum.Material.DiamondPlate)
	return m
end

local function buildNuclearSilo(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "NuclearSilo"
	-- Cylindrical silo. Red warning stripes. 10x20x10
	local silo = Instance.new("Part")
	silo.Name = "Silo"
	silo.Anchored = true
	silo.CanCollide = true
	silo.Shape = Enum.PartType.Cylinder
	silo.Size = Vector3.new(20, 10, 10)
	silo.CFrame = origin * CFrame.new(0, 10, 0) * CFrame.Angles(0, 0, math.rad(90))
	silo.BrickColor = BrickColor.new("Medium stone grey")
	silo.Material = Enum.Material.Metal
	silo.Parent = m
	m.PrimaryPart = silo
	-- Red warning stripe rings
	local stripe1 = Instance.new("Part")
	stripe1.Name = "Stripe1"
	stripe1.Anchored = true
	stripe1.CanCollide = false
	stripe1.Shape = Enum.PartType.Cylinder
	stripe1.Size = Vector3.new(1, 10.5, 10.5)
	stripe1.CFrame = origin * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.rad(90))
	stripe1.BrickColor = BrickColor.new("Bright red")
	stripe1.Material = Enum.Material.Neon
	stripe1.Parent = m
	local stripe2 = Instance.new("Part")
	stripe2.Name = "Stripe2"
	stripe2.Anchored = true
	stripe2.CanCollide = false
	stripe2.Shape = Enum.PartType.Cylinder
	stripe2.Size = Vector3.new(1, 10.5, 10.5)
	stripe2.CFrame = origin * CFrame.new(0, 14, 0) * CFrame.Angles(0, 0, math.rad(90))
	stripe2.BrickColor = BrickColor.new("Bright red")
	stripe2.Material = Enum.Material.Neon
	stripe2.Parent = m
	-- Base pad
	makePart(m, "Base", Vector3.new(14, 1, 14), origin + Vector3.new(0, 0.5, 0),
		BrickColor.new("Dark stone grey"), Enum.Material.Concrete)
	-- Warning sign
	makePart(m, "Sign", Vector3.new(4, 3, 0.5), origin + Vector3.new(8, 2, 0),
		BrickColor.new("Bright yellow"), Enum.Material.SmoothPlastic)
	return m
end

local function buildSpaceCommand(origin: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "SpaceCommand"
	-- Tallest building, futuristic. White with blue accents. 16x25x16
	local body = makePart(m, "Body", Vector3.new(16, 25, 16), origin + Vector3.new(0, 12.5, 0),
		BrickColor.new("White"), Enum.Material.SmoothPlastic)
	m.PrimaryPart = body
	-- Blue accent stripes (vertical)
	makePart(m, "AccentLeft", Vector3.new(0.5, 25, 16.5), origin + Vector3.new(-4, 12.5, 0),
		BrickColor.new("Bright blue"), Enum.Material.Neon)
	makePart(m, "AccentRight", Vector3.new(0.5, 25, 16.5), origin + Vector3.new(4, 12.5, 0),
		BrickColor.new("Bright blue"), Enum.Material.Neon)
	-- Satellite dome on top (sphere)
	local dome = Instance.new("Part")
	dome.Name = "Dome"
	dome.Anchored = true
	dome.CanCollide = true
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(8, 8, 8)
	dome.CFrame = origin + Vector3.new(0, 29, 0)
	dome.BrickColor = BrickColor.new("Bright blue")
	dome.Material = Enum.Material.Glass
	dome.Parent = m
	-- Antenna on dome
	makePart(m, "Antenna", Vector3.new(0.5, 8, 0.5), origin + Vector3.new(0, 37, 0),
		BrickColor.new("Medium stone grey"), Enum.Material.Metal)
	-- Blue glow ring at base
	makePart(m, "GlowRing", Vector3.new(18, 0.5, 18), origin + Vector3.new(0, 0.25, 0),
		BrickColor.new("Bright blue"), Enum.Material.Neon)
	return m
end

-- ── Builder dispatch table ────────────────────────────────────────────────────

local BUILDERS: { [string]: (origin: CFrame) -> Model } = {
	CommandCenter       = buildCommandCenter,
	Barracks            = buildBarracks,
	MotorPool           = buildMotorPool,
	RadarStation        = buildRadarStation,
	SAMSite             = buildSAMSite,
	Helipad             = buildHelipad,
	Armory              = buildArmory,
	TankDepot           = buildTankDepot,
	DroneHangar         = buildDroneHangar,
	FighterJetHangar    = buildFighterJetHangar,
	SubmarinePen        = buildSubmarinePen,
	AircraftCarrierDock = buildAircraftCarrierDock,
	StealthBomberBay    = buildStealthBomberBay,
	NuclearSilo         = buildNuclearSilo,
	SpaceCommand        = buildSpaceCommand,
}

-- ── Spawn building / button helpers ───────────────────────────────────────────

local function spawnBuildingModel(folder: Folder, item: any, cf: CFrame, animate: boolean?): Model
	local builder = BUILDERS[item.modelName]
	local model: Model
	if builder then
		model = builder(cf)
	else
		-- Unknown building fallback: simple box
		model = Instance.new("Model")
		model.Name = item.modelName
		local box = makePart(model, "Body", Vector3.new(12, 8, 12), cf + Vector3.new(0, 4, 0),
			BrickColor.new("Medium stone grey"), Enum.Material.Concrete)
		model.PrimaryPart = box
	end

	-- Measure model height for name tag offset
	local maxY = 0
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local top = desc.Position.Y + desc.Size.Y / 2
			if top > maxY then
				maxY = top
			end
		end
	end
	local tagHeight = maxY - cf.Position.Y + 3
	if model.PrimaryPart then
		createNameGui(model.PrimaryPart, item.name, tagHeight)
	end

	model.Parent = folder

	-- Drop-in animation if requested
	if animate then
		dropInAnimation(model, cf)
	end

	-- Start building behavior (radar spin, SAM scan, lights, etc.)
	local padNumStr = folder.Name:match("Tycoon_Pad_(%d+)")
	local padNum = padNumStr and tonumber(padNumStr) or 1
	BuildingBehaviors.StartBehavior(padNum, model, item.modelName, item.incomePerSecond)

	return model
end

local function spawnPurchaseButton(folder: Folder, item: any, cf: CFrame): Part
	-- Place button slightly in front of the building position (Z - 5)
	local buttonCF = cf + Vector3.new(0, 0, -5)

	-- Flat cylinder (circle on the ground)
	local button = Instance.new("Part")
	button.Name = "PurchaseButton_" .. item.modelName
	button.Anchored = true
	button.Shape = Enum.PartType.Cylinder
	-- Cylinder axis is along X; rotate so flat face is up
	button.Size = Vector3.new(BUTTON_HEIGHT, BUTTON_DIAMETER, BUTTON_DIAMETER)
	button.CFrame = (buttonCF + Vector3.new(0, BUTTON_HEIGHT_OFFSET, 0)) * CFrame.Angles(0, 0, math.rad(90))
	button.BrickColor = BUTTON_COLOR
	button.Material = BUTTON_MATERIAL
	createButtonGui(button, item.name, item.cost, item.incomePerSecond, item.description)

	-- PointLight
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = 2
	pointLight.Range = 25
	pointLight.Color = Color3.fromRGB(80, 255, 80)
	pointLight.Parent = button

	-- Particle emitter
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(80, 255, 80))
	particles.Rate = 8
	particles.Lifetime = NumberRange.new(1.5)
	particles.Speed = NumberRange.new(3)
	particles.SpreadAngle = Vector2.new(15, 15)
	particles.EmissionDirection = Enum.NormalId.Top
	particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	particles.Parent = button

	-- Small arrow above button (no tall beacon)
	local arrow = Instance.new("Part")
	arrow.Name = "Beacon"
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.Size = Vector3.new(1.5, 1.5, 1.5)
	arrow.BrickColor = BrickColor.new("Lime green")
	arrow.Material = Enum.Material.Neon
	arrow.Transparency = 0.3
	arrow.Shape = Enum.PartType.Ball
	arrow.CFrame = buttonCF + Vector3.new(0, 6 + BUTTON_HEIGHT_OFFSET, 0)
	arrow.Parent = folder

	-- Tag for identification
	button:SetAttribute("TycoonItem", item.modelName)
	local tag = Instance.new("StringValue")
	tag.Name = "ItemName"
	tag.Value = item.modelName
	tag.Parent = button

	button.Parent = folder
	return button
end

-- ── Canyon / Mesa walls around the outer map edge ─────────────────────────────

local function spawnCanyonWalls(folder: Folder)
	local RING_RADIUS = 500
	local SEGMENT_COUNT = 48
	local WALL_HEIGHT = 60
	local WALL_THICKNESS = 50

	local canyonColors = {
		BrickColor.new("Reddish brown"),
		BrickColor.new("Dark taupe"),
		BrickColor.new("Brown"),
	}

	for i = 1, SEGMENT_COUNT do
		local angle = (i / SEGMENT_COUNT) * math.pi * 2
		local x = math.cos(angle) * RING_RADIUS
		local z = math.sin(angle) * RING_RADIUS

		-- Vary height for a natural look
		local heightVariation = math.sin(angle * 3) * 15 + math.cos(angle * 5) * 10
		local segmentHeight = WALL_HEIGHT + heightVariation
		local color = canyonColors[((i - 1) % #canyonColors) + 1]

		-- Main canyon wall segment
		local arcLength = (2 * math.pi * RING_RADIUS) / SEGMENT_COUNT
		local wall = Instance.new("Part")
		wall.Name = "CanyonWall_" .. tostring(i)
		wall.Anchored = true
		wall.CanCollide = true
		wall.Size = Vector3.new(arcLength + 15, segmentHeight, WALL_THICKNESS)
		wall.CFrame = CFrame.new(Vector3.new(x, segmentHeight / 2, z)) * CFrame.Angles(0, angle + math.rad(90), 0)
		wall.BrickColor = color
		wall.Material = Enum.Material.Slate
		wall.Parent = folder

		-- Peak on top for jagged silhouette
		local peakHeight = segmentHeight * 0.3 + math.random() * 10
		local peak = Instance.new("Part")
		peak.Name = "CanyonPeak_" .. tostring(i)
		peak.Anchored = true
		peak.CanCollide = true
		peak.Size = Vector3.new(arcLength * 0.5, peakHeight, WALL_THICKNESS * 0.6)
		peak.CFrame = CFrame.new(Vector3.new(x, segmentHeight + peakHeight / 2, z)) * CFrame.Angles(0, angle + math.rad(90), 0)
		peak.BrickColor = color
		peak.Material = Enum.Material.Slate
		peak.Parent = folder
	end

	-- Mesa/plateau formations scattered between bases for visual interest
	local mesaDefs = {
		{ pos = Vector3.new(150, 0, 150),  size = Vector3.new(40, 25, 35) },
		{ pos = Vector3.new(-150, 0, -150), size = Vector3.new(35, 30, 40) },
		{ pos = Vector3.new(180, 0, -120),  size = Vector3.new(30, 20, 30) },
		{ pos = Vector3.new(-180, 0, 120),  size = Vector3.new(45, 22, 35) },
		{ pos = Vector3.new(100, 0, -200),  size = Vector3.new(35, 18, 30) },
		{ pos = Vector3.new(-100, 0, 200),  size = Vector3.new(30, 28, 40) },
	}

	for i, mesa in ipairs(mesaDefs) do
		local color = canyonColors[((i - 1) % #canyonColors) + 1]

		-- Mesa base (wide at bottom)
		local base = Instance.new("Part")
		base.Name = "Mesa_" .. tostring(i)
		base.Anchored = true
		base.CanCollide = true
		base.Size = mesa.size
		base.CFrame = CFrame.new(mesa.pos + Vector3.new(0, mesa.size.Y / 2, 0))
		base.BrickColor = color
		base.Material = Enum.Material.Slate
		base.Parent = folder

		-- Flat top (slightly wider, gives mesa look)
		local top = Instance.new("Part")
		top.Name = "MesaTop_" .. tostring(i)
		top.Anchored = true
		top.CanCollide = true
		top.Size = Vector3.new(mesa.size.X + 6, 3, mesa.size.Z + 6)
		top.CFrame = CFrame.new(mesa.pos + Vector3.new(0, mesa.size.Y + 1.5, 0))
		top.BrickColor = BrickColor.new("Bright green")
		top.Material = Enum.Material.Grass
		top.Parent = folder
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

local TycoonBuilder = {}

-- Shared world terrain (created once for the whole server)
local sharedWorldCreated = false

local function createSharedWorld()
	if sharedWorldCreated then
		return
	end
	sharedWorldCreated = true

	-- ── Bright sunny day lighting ──────────────────────────────────────
	local Lighting = game:GetService("Lighting")
	Lighting.Ambient = Color3.fromRGB(140, 140, 140)
	Lighting.Brightness = 3
	Lighting.ClockTime = 14 -- 2 PM sunny
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
	Lighting.FogEnd = 100000 -- effectively no fog
	Lighting.FogStart = 100000
	-- Remove any Atmosphere if present
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then atmo:Destroy() end
	-- Remove any BloomEffect or ColorCorrection that might be causing haze
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("PostEffect") then
			effect:Destroy()
		end
	end

	local sharedFolder = Instance.new("Folder")
	sharedFolder.Name = "SharedWorld"
	sharedFolder.Parent = workspace

	-- ── Desert ground plane ──────────────────────────────────────────────
	-- Large circular-ish ground covering the entire play area
	local groundSize = 1200
	local ground = Instance.new("Part")
	ground.Name = "WorldGround"
	ground.Anchored = true
	ground.CanCollide = true
	ground.Size = Vector3.new(groundSize, 4, groundSize)
	ground.BrickColor = BrickColor.new("Bright green")
	ground.Material = Enum.Material.Grass
	ground.CFrame = CFrame.new(Vector3.new(0, -4, 0))
	ground.Parent = sharedFolder

	-- ── Central spawn area ───────────────────────────────────────────────
	-- Flat concrete circle at origin (using a cylinder rotated flat)
	local spawnCircle = Instance.new("Part")
	spawnCircle.Name = "CentralSpawnPlatform"
	spawnCircle.Anchored = true
	spawnCircle.CanCollide = true
	spawnCircle.Shape = Enum.PartType.Cylinder
	-- Cylinder: height along X, diameter along Y/Z
	spawnCircle.Size = Vector3.new(2, 80, 80) -- 2 thick, radius ~40
	spawnCircle.CFrame = CFrame.new(Vector3.new(0, -1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	spawnCircle.BrickColor = BrickColor.new("Medium stone grey")
	spawnCircle.Material = Enum.Material.Concrete
	spawnCircle.Parent = sharedFolder

	-- SpawnLocation at center
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CentralSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(Vector3.new(0, 0.5, 0))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Parent = sharedFolder

	-- ── "MILITARY BASE TYCOON" sign on a tall pole ──────────────────────
	local signPole = Instance.new("Part")
	signPole.Name = "SignPole"
	signPole.Anchored = true
	signPole.CanCollide = true
	signPole.Size = Vector3.new(2, 30, 2)
	signPole.CFrame = CFrame.new(Vector3.new(0, 15, 0))
	signPole.BrickColor = BrickColor.new("Dark stone grey")
	signPole.Material = Enum.Material.Metal
	signPole.Parent = sharedFolder

	local signBoard = Instance.new("Part")
	signBoard.Name = "SignBoard"
	signBoard.Anchored = true
	signBoard.CanCollide = false
	signBoard.Size = Vector3.new(20, 6, 1)
	signBoard.CFrame = CFrame.new(Vector3.new(0, 33, 0))
	signBoard.BrickColor = BrickColor.new("Olive")
	signBoard.Material = Enum.Material.Metal
	signBoard.Parent = sharedFolder

	local signGui = Instance.new("BillboardGui")
	signGui.Name = "TitleGui"
	signGui.Size = UDim2.new(0, 600, 0, 120)
	signGui.StudsOffset = Vector3.new(0, 1, 0)
	signGui.AlwaysOnTop = false
	signGui.Parent = signBoard

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "MILITARY BASE TYCOON"
	titleLabel.TextStrokeTransparency = 0
	titleLabel.TextStrokeColor3 = Color3.fromRGB(40, 30, 0)
	titleLabel.Parent = signGui

	-- ── Directional arrows on the ground pointing to each base ──────────
	local arrowDirs = {
		{ dir = Vector3.new(0, 0, 1),   label = "NORTH BASE" },
		{ dir = Vector3.new(1, 0, 0),   label = "EAST BASE" },
		{ dir = Vector3.new(0, 0, -1),  label = "SOUTH BASE" },
		{ dir = Vector3.new(-1, 0, 0),  label = "WEST BASE" },
	}

	for i, arrow in ipairs(arrowDirs) do
		-- Arrow shaft (long rectangle)
		local shaft = Instance.new("Part")
		shaft.Name = "ArrowShaft_" .. tostring(i)
		shaft.Anchored = true
		shaft.CanCollide = false
		shaft.Size = Vector3.new(3, 0.2, 20)
		local shaftPos = arrow.dir * 30
		shaft.CFrame = CFrame.new(shaftPos + Vector3.new(0, 0.1, 0)) * CFrame.lookAt(Vector3.zero, arrow.dir)
		shaft.BrickColor = BrickColor.new("Bright yellow")
		shaft.Material = Enum.Material.Neon
		shaft.Parent = sharedFolder

		-- Arrow label
		local arrowGui = Instance.new("BillboardGui")
		arrowGui.Name = "ArrowLabel_" .. tostring(i)
		arrowGui.Size = UDim2.new(0, 200, 0, 40)
		arrowGui.StudsOffset = Vector3.new(0, 3, 0)
		arrowGui.AlwaysOnTop = false
		arrowGui.Parent = shaft

		local arrowLabel = Instance.new("TextLabel")
		arrowLabel.Size = UDim2.new(1, 0, 1, 0)
		arrowLabel.BackgroundTransparency = 1
		arrowLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		arrowLabel.TextScaled = true
		arrowLabel.Font = Enum.Font.GothamBold
		arrowLabel.Text = arrow.label
		arrowLabel.TextStrokeTransparency = 0.5
		arrowLabel.Parent = arrowGui
	end

	-- (flags and sandbags removed — cluttered the spawn area)

	-- ── Roads connecting center to each base pad ────────────────────────
	for i, padPos in ipairs(PAD_POSITIONS) do
		local direction = padPos.Unit
		local distance = padPos.Magnitude
		local midpoint = direction * (distance / 2)

		local road = Instance.new("Part")
		road.Name = "Road_" .. tostring(i)
		road.Anchored = true
		road.CanCollide = true
		road.Size = Vector3.new(12, 0.5, distance)
		road.CFrame = CFrame.new(midpoint + Vector3.new(0, -1.5, 0)) * CFrame.lookAt(Vector3.zero, direction)
		road.BrickColor = BrickColor.new("Dark stone grey")
		road.Material = Enum.Material.SmoothPlastic
		road.Parent = sharedFolder

		-- Road center line dashes
		local dashCount = math.floor(distance / 20)
		for d = 0, dashCount - 1 do
			local t = (d + 0.5) / dashCount
			local dashPos = direction * (t * distance)
			local dash = Instance.new("Part")
			dash.Name = "RoadDash_" .. tostring(i) .. "_" .. tostring(d)
			dash.Anchored = true
			dash.CanCollide = false
			dash.Size = Vector3.new(1, 0.1, 8)
			dash.CFrame = CFrame.new(dashPos + Vector3.new(0, -1.2, 0)) * CFrame.lookAt(Vector3.zero, direction)
			dash.BrickColor = BrickColor.new("White")
			dash.Material = Enum.Material.SmoothPlastic
			dash.Parent = sharedFolder
		end
	end

	-- ── Canyon walls around outer edge ───────────────────────────────────
	spawnCanyonWalls(sharedFolder)
end

--- Create the shared world (ground, roads, canyon walls) immediately on server start.
function TycoonBuilder.CreateSharedWorld()
	createSharedWorld()
end

-- ── Claim Pad System ──────────────────────────────────────────────────────────

--- Creates the unclaimed glowing claim pad for a base slot.
function TycoonBuilder.CreateClaimPad(padNumber: number)
	-- Ensure shared world exists
	createSharedWorld()

	local folder = getOrCreatePadFolder(padNumber)
	local origin = padOriginCFrame(padNumber)

	-- Glowing circle on the ground
	local claimPad = Instance.new("Part")
	claimPad.Name = "ClaimPad"
	claimPad.Anchored = true
	claimPad.CanCollide = true
	claimPad.Size = Vector3.new(20, 1, 20)
	claimPad.CFrame = origin + Vector3.new(0, 0.5, 0)
	claimPad.BrickColor = BrickColor.new("Lime green")
	claimPad.Material = Enum.Material.Neon
	claimPad.Parent = folder

	-- Particle emitter for glow effect
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(80, 255, 80))
	particles.Rate = 15
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Speed = NumberRange.new(2, 5)
	particles.SpreadAngle = Vector2.new(30, 30)
	particles.EmissionDirection = Enum.NormalId.Top
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = claimPad

	-- PointLight for glow
	local glow = Instance.new("PointLight")
	glow.Brightness = 3
	glow.Range = 30
	glow.Color = Color3.fromRGB(80, 255, 80)
	glow.Parent = claimPad

	-- "TAP TO CLAIM" BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ClaimGui"
	billboard.Size = UDim2.new(0, 400, 0, 100)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = claimPad

	local claimLabel = Instance.new("TextLabel")
	claimLabel.Size = UDim2.new(1, 0, 1, 0)
	claimLabel.BackgroundTransparency = 1
	claimLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
	claimLabel.TextScaled = true
	claimLabel.Font = Enum.Font.GothamBold
	claimLabel.Text = "TAP TO CLAIM"
	claimLabel.TextStrokeTransparency = 0
	claimLabel.TextStrokeColor3 = Color3.fromRGB(0, 40, 0)
	claimLabel.Parent = billboard

	-- Vertical beacon so it's visible from afar
	local beacon = Instance.new("Part")
	beacon.Name = "ClaimBeacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.Size = Vector3.new(3, 80, 3)
	beacon.BrickColor = BrickColor.new("Lime green")
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.6
	beacon.CFrame = origin + Vector3.new(0, 40, 0)
	beacon.Parent = folder
end

--- Claims a pad for a player: removes the claim pad, spawns the initial base platform.
function TycoonBuilder.ClaimPad(padNumber: number, _player: Player)
	local folder = getOrCreatePadFolder(padNumber)

	-- Remove the claim pad and beacon
	local claimPad = folder:FindFirstChild("ClaimPad")
	if claimPad then
		claimPad:Destroy()
	end
	local claimBeacon = folder:FindFirstChild("ClaimBeacon")
	if claimBeacon then
		claimBeacon:Destroy()
	end

	-- Spawn a small concrete starting platform
	local origin = padOriginCFrame(padNumber)
	local platform = Instance.new("Part")
	platform.Name = "BasePlatform"
	platform.Anchored = true
	platform.CanCollide = true
	platform.Size = Vector3.new(30, 2, 30)
	platform.CFrame = origin + Vector3.new(0, -1, 0)
	platform.BrickColor = BrickColor.new("Medium stone grey")
	platform.Material = Enum.Material.Concrete
	platform.Parent = folder

	-- Drop in the Command Center with animation
	local ccItem = TycoonConfig.Items["CommandCenter"]
	if ccItem then
		local ccCF = buildingCFrame(origin, "CommandCenter")
		spawnBuildingModel(folder, ccItem, ccCF, true)
	end

	-- Create the cash collector pad
	TycoonBuilder.CreateCashCollector(padNumber)

	-- Show the first purchasable button
	local startUnlocked = { "CommandCenter" }
	TycoonBuilder.SpawnPurchaseButtons(padNumber, startUnlocked)
end

--- Set up the base platform, environment, and free Command Center.
--- Called after claiming (or for legacy direct setup).
function TycoonBuilder.SetupTycoonPad(padNumber: number, player: Player)
	-- Create the shared world map (once)
	createSharedWorld()

	local folder = getOrCreatePadFolder(padNumber)
	local origin = padOriginCFrame(padNumber)

	-- ── Concrete base platform ────────────────────────────────────────────
	local base = Instance.new("Part")
	base.Name = "BasePlatform"
	base.Anchored = true
	base.CanCollide = true
	base.Size = Vector3.new(100, 2, 400)
	base.BrickColor = BrickColor.new("Medium stone grey")
	base.Material = Enum.Material.Concrete
	base.CFrame = origin + Vector3.new(0, -1, 200)
	base.Parent = folder

	-- ── SpawnLocation ─────────────────────────────────────────────────────
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TycoonSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = origin + Vector3.new(0, 0.5, 10)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.TeamColor = BrickColor.new("Medium stone grey")
	spawn.Neutral = true
	spawn.Parent = folder

	-- Create the cash collector pad
	TycoonBuilder.CreateCashCollector(padNumber)

	-- ── Show the first purchasable button (nothing pre-built) ────────────
	local startUnlocked: { string } = {}
	TycoonBuilder.SpawnPurchaseButtons(padNumber, startUnlocked)
end

--- Show only the next purchasable button (linear progression).
--- Removes any existing purchase buttons first.
function TycoonBuilder.SpawnPurchaseButtons(padNumber: number, unlockedItems: { string })
	local folder = getOrCreatePadFolder(padNumber)
	local origin = padOriginCFrame(padNumber)

	-- Remove old buttons and their beacons
	for _, child in folder:GetChildren() do
		if child.Name:sub(1, 15) == "PurchaseButton_" or child.Name == "Beacon" then
			child:Destroy()
		end
	end

	local nextItem = nextUnlockable(unlockedItems)
	if nextItem == nil then
		return -- all items unlocked
	end

	-- Place button at the building's designated position
	local cf = buildingCFrame(origin, nextItem.modelName)
	spawnPurchaseButton(folder, nextItem, cf)
end

--- Remove the purchase button for itemName, spawn its building with drop-in animation, then show next button.
function TycoonBuilder.UnlockItem(padNumber: number, itemName: string, unlockedItems: { string })
	local folder = getOrCreatePadFolder(padNumber)
	local origin = padOriginCFrame(padNumber)

	-- Remove button for this item
	local buttonName = "PurchaseButton_" .. itemName
	local existingButton = folder:FindFirstChild(buttonName)
	if existingButton then
		existingButton:Destroy()
	end

	-- Remove beacon too
	for _, child in folder:GetChildren() do
		if child.Name == "Beacon" then
			child:Destroy()
		end
	end

	-- Spawn building at its designated position with drop-in animation
	local item = TycoonConfig.Items[itemName]
	if item then
		local cf = buildingCFrame(origin, item.modelName)
		spawnBuildingModel(folder, item, cf, true)
	end

	-- Show next purchase button
	TycoonBuilder.SpawnPurchaseButtons(padNumber, unlockedItems)
end

-- ── Cash Collector Pad ────────────────────────────────────────────────────────

--- Creates the cash collector pad near the entrance of a base.
function TycoonBuilder.CreateCashCollector(padNumber: number)
	local folder = getOrCreatePadFolder(padNumber)
	local origin = padOriginCFrame(padNumber)

	-- Position near the entrance (front of the base)
	local collectorCF = origin + Vector3.new(15, 0, 10)

	local collector = Instance.new("Part")
	collector.Name = "CashCollector_" .. tostring(padNumber)
	collector.Anchored = true
	collector.CanCollide = true
	collector.Shape = Enum.PartType.Cylinder
	-- Flat cylinder on the ground
	collector.Size = Vector3.new(1, 5, 5)
	collector.CFrame = (collectorCF + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	collector.BrickColor = BrickColor.new("Bright yellow")
	collector.Material = Enum.Material.SmoothPlastic
	collector.Parent = folder

	-- CashAmount NumberValue for TycoonManager to update
	local cashValue = Instance.new("NumberValue")
	cashValue.Name = "CashAmount"
	cashValue.Value = 0
	cashValue.Parent = collector

	-- PointLight for visibility
	local glow = Instance.new("PointLight")
	glow.Brightness = 2
	glow.Range = 10
	glow.Color = Color3.fromRGB(255, 215, 0)
	glow.Parent = collector

	-- Particle emitter (subtle gold sparkle)
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
	particles.Rate = 2
	particles.Lifetime = NumberRange.new(1, 1.5)
	particles.Speed = NumberRange.new(1, 3)
	particles.SpreadAngle = Vector2.new(20, 20)
	particles.EmissionDirection = Enum.NormalId.Top
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = collector

	-- BillboardGui showing the accumulated cash
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CollectorGui"
	billboard.Size = UDim2.new(0, 150, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = collector

	local cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.Size = UDim2.new(1, 0, 1, 0)
	cashLabel.BackgroundTransparency = 1
	cashLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	cashLabel.TextScaled = true
	cashLabel.Font = Enum.Font.GothamBold
	cashLabel.Text = "$0"
	cashLabel.TextStrokeTransparency = 0
	cashLabel.TextStrokeColor3 = Color3.fromRGB(80, 60, 0)
	cashLabel.Parent = billboard

	-- Update the label whenever CashAmount changes
	cashValue.Changed:Connect(function(newValue: number)
		cashLabel.Text = "$" .. tostring(math.floor(newValue))
	end)
end

--- Returns the world position of a building for a given pad.
function TycoonBuilder.GetBuildingWorldPosition(padNumber: number, buildingName: string): Vector3?
	local pos = BUILDING_POSITIONS[buildingName]
	if not pos then
		return nil
	end
	local origin = padOriginCFrame(padNumber)
	return (origin + pos).Position
end

--- Destroy all parts belonging to a tycoon pad.
function TycoonBuilder.CleanupTycoon(padNumber: number)
	-- Stop all building behavior loops first
	BuildingBehaviors.StopAllBehaviors(padNumber)

	local folderName = TYCOON_FOLDER_PREFIX .. tostring(padNumber)
	local folder = workspace:FindFirstChild(folderName)
	if folder then
		folder:Destroy()
	end
end

return TycoonBuilder
