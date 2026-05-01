--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig = require(ReplicatedStorage.TycoonConfig) :: any

-- ── Types ─────────────────────────────────────────────────────────────────────

type TycoonItemCategory = "Building" | "Vehicle" | "Aircraft" | "Naval" | "Strategic"

-- ── Constants ─────────────────────────────────────────────────────────────────

local PAD_SPACING = 150
local PAD_BASE_POSITION = Vector3.new(0, 0, 0)

-- Platform dimensions
local PLAT_WIDTH = 130
local PLAT_DEPTH = 400

-- Button styling
local BUTTON_COLOR = BrickColor.new("Lime green")
local BUTTON_MATERIAL = Enum.Material.Neon
local BUTTON_SIZE = Vector3.new(14, 1.5, 14)
local BUTTON_HEIGHT_OFFSET = 1

local TYCOON_FOLDER_PREFIX = "Tycoon_Pad_"

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
	local offset = Vector3.new((padNumber - 1) * PAD_SPACING, 0, 0)
	return CFrame.new(PAD_BASE_POSITION + offset)
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
	-- Yellow circle border (4 arc segments using thin parts)
	-- "H" marking made of 3 yellow parts
	makePart(m, "H_Left", Vector3.new(2, 0.15, 10), origin + Vector3.new(-3, 0.6, 0),
		BrickColor.new("Bright yellow"), Enum.Material.SmoothPlastic)
	makePart(m, "H_Right", Vector3.new(2, 0.15, 10), origin + Vector3.new(3, 0.6, 0),
		BrickColor.new("Bright yellow"), Enum.Material.SmoothPlastic)
	makePart(m, "H_Mid", Vector3.new(8, 0.15, 2), origin + Vector3.new(0, 0.6, 0),
		BrickColor.new("Bright yellow"), Enum.Material.SmoothPlastic)
	-- Corner lights
	for _, xSign in ipairs({-1, 1}) do
		for _, zSign in ipairs({-1, 1}) do
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
	-- Sunken main structure (only top half visible)
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

local function spawnBuildingModel(folder: Folder, item: any, cf: CFrame): Model
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
	return model
end

local function spawnPurchaseButton(folder: Folder, item: any, cf: CFrame): Part
	-- Place button slightly in front of the building position (Z - 5)
	local buttonCF = cf + Vector3.new(0, 0, -5)

	local button = Instance.new("Part")
	button.Name = "PurchaseButton_" .. item.modelName
	button.Anchored = true
	button.Size = BUTTON_SIZE
	button.BrickColor = BUTTON_COLOR
	button.Material = BUTTON_MATERIAL
	button.CFrame = buttonCF + Vector3.new(0, BUTTON_HEIGHT_OFFSET, 0)
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

	-- Vertical beacon
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.Size = Vector3.new(2, 40, 2)
	beacon.BrickColor = BrickColor.new("Lime green")
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.7
	beacon.CFrame = buttonCF + Vector3.new(0, 20 + BUTTON_HEIGHT_OFFSET, 0)
	beacon.Parent = folder

	-- Tag for identification
	button:SetAttribute("TycoonItem", item.modelName)
	local tag = Instance.new("StringValue")
	tag.Name = "ItemName"
	tag.Value = item.modelName
	tag.Parent = button

	button.Parent = folder
	return button
end

-- ── Mountains around the perimeter ────────────────────────────────────────────

local function spawnMountains(folder: Folder, origin: CFrame)
	local halfW = PLAT_WIDTH / 2 + 30 -- beyond the grass border
	local depthCenter = PLAT_DEPTH / 2 + 10
	local mountainDefs = {
		-- Left side mountains (along -X edge)
		{ offset = Vector3.new(-halfW - 15, 15, 40),   size = Vector3.new(30, 35, 40) },
		{ offset = Vector3.new(-halfW - 20, 20, 120),  size = Vector3.new(35, 45, 50) },
		{ offset = Vector3.new(-halfW - 12, 18, 200),  size = Vector3.new(28, 40, 45) },
		{ offset = Vector3.new(-halfW - 18, 22, 300),  size = Vector3.new(32, 48, 40) },
		-- Right side mountains (along +X edge)
		{ offset = Vector3.new(halfW + 15, 15, 60),    size = Vector3.new(30, 35, 45) },
		{ offset = Vector3.new(halfW + 20, 22, 160),   size = Vector3.new(35, 50, 50) },
		{ offset = Vector3.new(halfW + 12, 18, 260),   size = Vector3.new(28, 40, 40) },
		{ offset = Vector3.new(halfW + 18, 20, 350),   size = Vector3.new(32, 45, 45) },
		-- Back mountains (along +Z edge, behind the base)
		{ offset = Vector3.new(-30, 22, depthCenter + PLAT_DEPTH / 2 + 15), size = Vector3.new(50, 50, 30) },
		{ offset = Vector3.new(30, 18, depthCenter + PLAT_DEPTH / 2 + 20),  size = Vector3.new(45, 40, 35) },
		-- Front mountains (along -Z edge, in front of spawn)
		{ offset = Vector3.new(-25, 15, -30),  size = Vector3.new(40, 35, 25) },
		{ offset = Vector3.new(25, 18, -35),   size = Vector3.new(45, 40, 30) },
		{ offset = Vector3.new(0, 12, -40),    size = Vector3.new(30, 30, 20) },
	}

	local mountainColors = {
		BrickColor.new("Medium stone grey"),
		BrickColor.new("Dark stone grey"),
		BrickColor.new("Reddish brown"),
	}

	for i, def in ipairs(mountainDefs) do
		local color = mountainColors[((i - 1) % #mountainColors) + 1]
		local mountain = Instance.new("Part")
		mountain.Name = "Mountain_" .. tostring(i)
		mountain.Anchored = true
		mountain.CanCollide = true
		mountain.Size = def.size
		mountain.CFrame = origin + def.offset
		mountain.BrickColor = color
		mountain.Material = Enum.Material.Slate
		mountain.Parent = folder

		-- Add a smaller peak on top for a more natural look
		local peak = Instance.new("Part")
		peak.Name = "MountainPeak_" .. tostring(i)
		peak.Anchored = true
		peak.CanCollide = true
		peak.Size = Vector3.new(def.size.X * 0.5, def.size.Y * 0.4, def.size.Z * 0.5)
		peak.CFrame = origin + def.offset + Vector3.new(0, def.size.Y * 0.5 + peak.Size.Y * 0.3, 0)
		peak.BrickColor = color
		peak.Material = Enum.Material.Slate
		peak.Parent = folder
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

local TycoonBuilder = {}

--- Set up the base platform, environment, mountains, and free Command Center.
function TycoonBuilder.SetupTycoonPad(padNumber: number, _player: Player)
	local folder = getOrCreatePadFolder(padNumber)
	local origin = padOriginCFrame(padNumber)

	local platCenterZ = PLAT_DEPTH / 2 + 10 -- center the platform so spawn is near front

	-- ── Surrounding grass platform ────────────────────────────────────────
	local grass = Instance.new("Part")
	grass.Name = "GrassPlatform"
	grass.Anchored = true
	grass.CanCollide = true
	grass.Size = Vector3.new(PLAT_WIDTH + 50, 3, PLAT_DEPTH + 50)
	grass.BrickColor = BrickColor.new("Bright green")
	grass.Material = Enum.Material.LeafyGrass
	grass.CFrame = origin + Vector3.new(0, -2.5, platCenterZ)
	grass.Parent = folder

	-- ── Concrete base platform ────────────────────────────────────────────
	local base = Instance.new("Part")
	base.Name = "BasePlatform"
	base.Anchored = true
	base.CanCollide = true
	base.Size = Vector3.new(PLAT_WIDTH, 2, PLAT_DEPTH)
	base.BrickColor = BrickColor.new("Medium stone grey")
	base.Material = Enum.Material.Concrete
	base.CFrame = origin + Vector3.new(0, -1, platCenterZ)
	base.Parent = folder

	-- ── Runway strip along the front ──────────────────────────────────────
	local runway = Instance.new("Part")
	runway.Name = "Runway"
	runway.Anchored = true
	runway.CanCollide = true
	runway.Size = Vector3.new(PLAT_WIDTH - 10, 1, 16)
	runway.BrickColor = BrickColor.new("Really black")
	runway.Material = Enum.Material.SmoothPlastic
	runway.CFrame = origin + Vector3.new(0, 0.01, -5)
	runway.Parent = folder

	-- Runway center line markings
	for dash = 0, 7 do
		local mark = Instance.new("Part")
		mark.Name = "RunwayMark_" .. dash
		mark.Anchored = true
		mark.CanCollide = false
		mark.Size = Vector3.new(12, 0.1, 1)
		mark.BrickColor = BrickColor.new("White")
		mark.Material = Enum.Material.SmoothPlastic
		mark.CFrame = origin + Vector3.new(-52.5 + dash * 15, 0.55, -5)
		mark.Parent = folder
	end

	-- ── Water body behind the base (for naval) ────────────────────────────
	local water = Instance.new("Part")
	water.Name = "WaterBody"
	water.Anchored = true
	water.CanCollide = false
	water.Size = Vector3.new(PLAT_WIDTH + 50, 2, 120)
	water.BrickColor = BrickColor.new("Bright blue")
	water.Material = Enum.Material.Glass
	water.Transparency = 0.3
	water.CFrame = origin + Vector3.new(0, -2, platCenterZ + PLAT_DEPTH / 2 + 70)
	water.Parent = folder

	-- ── Perimeter fence posts ─────────────────────────────────────────────
	local fenceZStart = 20
	local fenceZEnd = PLAT_DEPTH - 20
	local fenceCount = 14
	local fenceSpacing = (fenceZEnd - fenceZStart) / (fenceCount - 1)

	for side = -1, 1, 2 do
		local xPos = side * (PLAT_WIDTH / 2 - 2)
		for p = 0, fenceCount - 1 do
			local zPos = fenceZStart + p * fenceSpacing
			local post = Instance.new("Part")
			post.Name = "FencePost"
			post.Anchored = true
			post.CanCollide = true
			post.Size = Vector3.new(1, 4, 1)
			post.BrickColor = BrickColor.new("Dark stone grey")
			post.Material = Enum.Material.Metal
			post.CFrame = origin + Vector3.new(xPos, 2, zPos)
			post.Parent = folder

			if p < fenceCount - 1 then
				local bar = Instance.new("Part")
				bar.Name = "FenceBar"
				bar.Anchored = true
				bar.CanCollide = false
				bar.Size = Vector3.new(1, 0.5, fenceSpacing)
				bar.BrickColor = BrickColor.new("Dark stone grey")
				bar.Material = Enum.Material.Metal
				bar.CFrame = origin + Vector3.new(xPos, 3.5, zPos + fenceSpacing / 2)
				bar.Parent = folder
			end
		end
	end

	-- ── Decorative trees on the grass border ──────────────────────────────
	local treePositions = {
		Vector3.new(-PLAT_WIDTH / 2 - 12, 0, 60),
		Vector3.new(PLAT_WIDTH / 2 + 12, 0, 60),
		Vector3.new(-PLAT_WIDTH / 2 - 12, 0, 160),
		Vector3.new(PLAT_WIDTH / 2 + 12, 0, 160),
		Vector3.new(-PLAT_WIDTH / 2 - 12, 0, 260),
		Vector3.new(PLAT_WIDTH / 2 + 12, 0, 260),
		Vector3.new(-PLAT_WIDTH / 2 - 12, 0, 340),
		Vector3.new(PLAT_WIDTH / 2 + 12, 0, 340),
	}
	for t, treeOff in treePositions do
		local trunk = Instance.new("Part")
		trunk.Name = "TreeTrunk_" .. t
		trunk.Anchored = true
		trunk.CanCollide = true
		trunk.Size = Vector3.new(2, 6, 2)
		trunk.BrickColor = BrickColor.new("Reddish brown")
		trunk.Material = Enum.Material.Wood
		trunk.CFrame = origin + treeOff + Vector3.new(0, 3, 0)
		trunk.Parent = folder

		local canopy = Instance.new("Part")
		canopy.Name = "TreeCanopy_" .. t
		canopy.Anchored = true
		canopy.CanCollide = false
		canopy.Shape = Enum.PartType.Ball
		canopy.Size = Vector3.new(8, 8, 8)
		canopy.BrickColor = BrickColor.new("Forest green")
		canopy.Material = Enum.Material.Grass
		canopy.CFrame = origin + treeOff + Vector3.new(0, 10, 0)
		canopy.Parent = folder
	end

	-- ── Mountains around the perimeter ────────────────────────────────────
	spawnMountains(folder, origin)

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

	-- ── Spawn free tier-1 Command Center ──────────────────────────────────
	local ccItem = TycoonConfig.Items["CommandCenter"]
	if ccItem then
		local ccCF = buildingCFrame(origin, "CommandCenter")
		spawnBuildingModel(folder, ccItem, ccCF)
	end

	-- ── Spawn the first purchasable button ────────────────────────────────
	local startUnlocked = { "CommandCenter" }
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

--- Remove the purchase button for itemName, spawn its building, then show next button.
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

	-- Spawn building at its designated position
	local item = TycoonConfig.Items[itemName]
	if item then
		local cf = buildingCFrame(origin, item.modelName)
		spawnBuildingModel(folder, item, cf)
	end

	-- Show next purchase button
	TycoonBuilder.SpawnPurchaseButtons(padNumber, unlockedItems)
end

--- Destroy all parts belonging to a tycoon pad.
function TycoonBuilder.CleanupTycoon(padNumber: number)
	local folderName = TYCOON_FOLDER_PREFIX .. tostring(padNumber)
	local folder = workspace:FindFirstChild(folderName)
	if folder then
		folder:Destroy()
	end
end

return TycoonBuilder
