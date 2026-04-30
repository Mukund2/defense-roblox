--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TycoonConfig = require(ReplicatedStorage.TycoonConfig) :: any

-- Folder containing real models inserted from the Roblox catalog
local TycoonModels = ServerStorage:FindFirstChild("TycoonModels")

-- ── Types ─────────────────────────────────────────────────────────────────────

type TycoonItemCategory = "Building" | "Vehicle" | "Aircraft" | "Naval" | "Strategic"

-- ── Constants ─────────────────────────────────────────────────────────────────

local PAD_SPACING = 150 -- studs between pad origins in the X axis
local PAD_BASE_POSITION = Vector3.new(0, 0, 0) -- first pad anchor

-- Grid layout for spawned buildings relative to a pad origin.
-- Items are placed in rows of GRID_COLS, each cell is CELL_SIZE studs wide.
local GRID_COLS = 3
local CELL_SIZE = 40 -- studs per cell (fits within 150 stud pad spacing)
local CELL_DEPTH = 40 -- studs deep per row

-- Category colour palette (BrickColor names)
local CATEGORY_COLOR: { [TycoonItemCategory]: BrickColor } = {
	Building = BrickColor.new("Medium stone grey"),
	Vehicle = BrickColor.new("Bright green"),
	Aircraft = BrickColor.new("Bright blue"),
	Naval = BrickColor.new("Dark blue"),
	Strategic = BrickColor.new("Bright red"),
}

-- Button colour (neon green)
local BUTTON_COLOR = BrickColor.new("Lime green")
local BUTTON_MATERIAL = Enum.Material.Neon
local BUTTON_SIZE = Vector3.new(14, 1.5, 14)
local BUTTON_HEIGHT_OFFSET = 1 -- elevate slightly above ground

-- Parent folder name inside Workspace for all tycoon parts
local TYCOON_FOLDER_PREFIX = "Tycoon_Pad_"

-- ── Internal helpers ──────────────────────────────────────────────────────────

--- Return the workspace origin CFrame for a given pad number (1-indexed).
local function padOriginCFrame(padNumber: number): CFrame
	local offset = Vector3.new((padNumber - 1) * PAD_SPACING, 0, 0)
	return CFrame.new(PAD_BASE_POSITION + offset)
end

--- Return (or create) the folder that holds all parts for a pad.
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

--- Calculate the CFrame for the Nth item in the grid (0-indexed slot).
local function itemCFrame(padOrigin: CFrame, slotIndex: number): CFrame
	local col = slotIndex % GRID_COLS
	local row = math.floor(slotIndex / GRID_COLS)
	local localOffset = Vector3.new(
		(col - GRID_COLS / 2 + 0.5) * CELL_SIZE,
		0,
		(row + 1) * CELL_DEPTH -- rows extend away from the pad in +Z
	)
	return padOrigin + localOffset
end

--- Look up the order index of an item name in TycoonConfig.Ordered (1-indexed).
--- Returns 0 if not found.
local function itemOrder(itemName: string): number
	for i, item in ipairs(TycoonConfig.Ordered) do
		if item.modelName == itemName then
			return i
		end
	end
	return 0
end

--- Return the next item in TycoonConfig.Ordered that is NOT in unlockedItems.
--- Returns nil if everything is unlocked.
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

--- Create a BillboardGui label for a purchase button.
local function createButtonGui(parent: Part, itemName: string, cost: number, incomePerSecond: number, description: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ButtonGui"
	billboard.Size = UDim2.new(0, 350, 0, 120)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = parent

	-- Item name label (top 30%)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0.3, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = itemName
	label.Parent = billboard

	-- Cost label with green background frame (middle 35%)
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

	-- Income boost label (bottom 30%)
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

--- Spawn the building for an unlocked item. Uses real model from ServerStorage if available,
--- otherwise falls back to a placeholder Part.
local function spawnBuildingPart(folder: Folder, item: any, cf: CFrame)
	-- Try to clone a real model from ServerStorage.TycoonModels
	if TycoonModels then
		local template = TycoonModels:FindFirstChild(item.modelName)
		if template then
			local model = template:Clone()
			model.Name = item.modelName

			-- Anchor all parts, disable collision, and remove broken scripts
			for _, desc in model:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
				end
			end
			-- Strip internal scripts/PackageLinks from marketplace models
			-- that cause require() errors at runtime
			for _, desc in model:GetDescendants() do
				if desc:IsA("BaseScript") or desc.ClassName == "PackageLink" then
					desc:Destroy()
				end
			end

			-- Position the model so its BOTTOM sits at ground level (cf.Y).
			-- Marketplace models have arbitrary positions and no PrimaryPart.
			-- Strategy: PivotTo target first, then measure bottom and shift up.
			if model:IsA("Model") then
				-- Ensure a PrimaryPart exists for PivotTo
				if not model.PrimaryPart then
					for _, desc in model:GetDescendants() do
						if desc:IsA("BasePart") then
							model.PrimaryPart = desc
							break
						end
					end
				end

				if model.PrimaryPart then
					-- Step 1: Pivot model so PrimaryPart is at the target CFrame
					model:PivotTo(cf)

					-- Step 2: Find how far below cf.Y the bottom extends
					local minY = math.huge
					for _, desc in model:GetDescendants() do
						if desc:IsA("BasePart") then
							local partBottom = desc.Position.Y - desc.Size.Y / 2
							if partBottom < minY then
								minY = partBottom
							end
						end
					end

					-- Step 3: Shift the entire model up so bottom sits at ground (cf.Y)
					local shiftUp = cf.Position.Y - minY
					if math.abs(shiftUp) > 0.1 then
						model:PivotTo(model:GetPivot() + Vector3.new(0, shiftUp, 0))
					end
				end
			elseif model:IsA("BasePart") then
				model.CFrame = cf + Vector3.new(0, model.Size.Y / 2, 0)
			end

			-- Name tag above the model — offset based on actual model height
			local _, placedSize = model:GetBoundingBox()
			local tagHeight = placedSize.Y + 3

			local nameGui = Instance.new("BillboardGui")
			nameGui.Name = "NameGui"
			nameGui.Size = UDim2.new(0, 200, 0, 40)
			nameGui.StudsOffset = Vector3.new(0, tagHeight, 0)
			nameGui.AlwaysOnTop = false
			if model:IsA("Model") and model.PrimaryPart then
				nameGui.Adornee = model.PrimaryPart
				nameGui.Parent = model.PrimaryPart
			else
				nameGui.Parent = model
			end

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, 0, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			nameLabel.TextScaled = true
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.Text = item.name
			nameLabel.TextStrokeTransparency = 0.5
			nameLabel.Parent = nameGui

			model.Parent = folder
			return model
		end
	end

	-- Fallback: placeholder Part
	local category: TycoonItemCategory = item.category
	local color = CATEGORY_COLOR[category] or BrickColor.new("Medium stone grey")

	local size: Vector3
	if category == "Building" then
		size = Vector3.new(16, 12, 16)
	elseif category == "Vehicle" then
		size = Vector3.new(12, 5, 20)
	elseif category == "Aircraft" then
		size = Vector3.new(20, 4, 14)
	elseif category == "Naval" then
		size = Vector3.new(24, 8, 40)
	elseif category == "Strategic" then
		size = Vector3.new(10, 20, 10)
	else
		size = Vector3.new(12, 8, 12)
	end

	local part = Instance.new("Part")
	part.Name = item.modelName
	part.Anchored = true
	part.Size = size
	part.BrickColor = color
	part.Material = Enum.Material.SmoothPlastic

	local heightAdjust = if category == "Aircraft" then 10 else size.Y / 2
	part.CFrame = cf + Vector3.new(0, heightAdjust, 0)

	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "NameGui"
	nameGui.Size = UDim2.new(0, 160, 0, 40)
	nameGui.StudsOffset = Vector3.new(0, size.Y / 2 + 2, 0)
	nameGui.AlwaysOnTop = false
	nameGui.Parent = part

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = item.name
	nameLabel.Parent = nameGui

	part.Parent = folder
	return part
end

--- Create a purchase button Part for a given item.
local function spawnPurchaseButton(folder: Folder, item: any, cf: CFrame): Part
	local button = Instance.new("Part")
	button.Name = "PurchaseButton_" .. item.modelName
	button.Anchored = true
	button.Size = BUTTON_SIZE
	button.BrickColor = BUTTON_COLOR
	button.Material = BUTTON_MATERIAL
	button.CFrame = cf + Vector3.new(0, BUTTON_HEIGHT_OFFSET, 0)
	createButtonGui(button, item.name, item.cost, item.incomePerSecond, item.description)

	-- PointLight inside the button
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = 2
	pointLight.Range = 25
	pointLight.Color = Color3.fromRGB(80, 255, 80)
	pointLight.Parent = button

	-- Particle emitter (green rising particles)
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

	-- Vertical beacon (tall semi-transparent green pillar)
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.Size = Vector3.new(2, 40, 2)
	beacon.BrickColor = BrickColor.new("Lime green")
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.7
	beacon.CFrame = cf + Vector3.new(0, 20 + BUTTON_HEIGHT_OFFSET, 0)
	beacon.Parent = folder

	-- Tag so client can identify which item this button belongs to
	button:SetAttribute("TycoonItem", item.modelName)

	-- Also store as StringValue for server-side reads
	local tag = Instance.new("StringValue")
	tag.Name = "ItemName"
	tag.Value = item.modelName
	tag.Parent = button

	button.Parent = folder
	return button
end

-- ── Public API ────────────────────────────────────────────────────────────────

local TycoonBuilder = {}

--- Set up the base platform and spawn the Command Center for a pad.
--- Also spawns the first purchase button.
function TycoonBuilder.SetupTycoonPad(padNumber: number, _player: Player)
	local folder = getOrCreatePadFolder(padNumber)
	local origin = padOriginCFrame(padNumber)

	local platWidth = 130
	local platDepth = 250
	local platCenterZ = 100

	-- ── Phase 1B: Terrain & Environment ─────────────────────────────────────

	-- Surrounding grass platform (slightly larger, underneath)
	local grass = Instance.new("Part")
	grass.Name = "GrassPlatform"
	grass.Anchored = true
	grass.Size = Vector3.new(platWidth + 40, 3, platDepth + 40)
	grass.BrickColor = BrickColor.new("Bright green")
	grass.Material = Enum.Material.LeafyGrass
	grass.CFrame = origin + Vector3.new(0, -2.5, platCenterZ)
	grass.Parent = folder

	-- Concrete base platform (building area)
	local base = Instance.new("Part")
	base.Name = "BasePlatform"
	base.Anchored = true
	base.Size = Vector3.new(platWidth, 2, platDepth)
	base.BrickColor = BrickColor.new("Medium stone grey")
	base.Material = Enum.Material.Concrete
	base.CFrame = origin + Vector3.new(0, -1, platCenterZ)
	base.Parent = folder

	-- Water body behind the base (for naval units)
	local water = Instance.new("Part")
	water.Name = "WaterBody"
	water.Anchored = true
	water.Size = Vector3.new(platWidth + 40, 2, 120)
	water.BrickColor = BrickColor.new("Bright blue")
	water.Material = Enum.Material.Water
	water.CFrame = origin + Vector3.new(0, -2, platCenterZ + platDepth / 2 + 70)
	water.CanCollide = false
	water.Parent = folder

	-- Runway strip along -X side
	local runway = Instance.new("Part")
	runway.Name = "Runway"
	runway.Anchored = true
	runway.Size = Vector3.new(platWidth - 10, 1, 16)
	runway.BrickColor = BrickColor.new("Really black")
	runway.Material = Enum.Material.SmoothPlastic
	runway.CFrame = origin + Vector3.new(0, 0.01, -15)
	runway.Parent = folder

	-- Runway center line markings (white dashes)
	for dash = 0, 7 do
		local mark = Instance.new("Part")
		mark.Name = "RunwayMark_" .. dash
		mark.Anchored = true
		mark.Size = Vector3.new(12, 0.1, 1)
		mark.BrickColor = BrickColor.new("White")
		mark.Material = Enum.Material.SmoothPlastic
		mark.CFrame = origin + Vector3.new(-87.5 + dash * 25, 0.55, -15)
		mark.Parent = folder
	end

	-- ── Perimeter fence posts (2 sides: -X and +X edges) ────────────────────
	local fenceZ_start = platCenterZ - platDepth / 2 + 20
	local fenceZ_end = platCenterZ + platDepth / 2 - 20
	local fenceCount = 10
	local fenceSpacing = (fenceZ_end - fenceZ_start) / (fenceCount - 1)

	for side = -1, 1, 2 do
		local xPos = side * (platWidth / 2 - 2)
		for p = 0, fenceCount - 1 do
			local zPos = fenceZ_start + p * fenceSpacing
			-- Vertical post
			local post = Instance.new("Part")
			post.Name = "FencePost"
			post.Anchored = true
			post.Size = Vector3.new(1, 4, 1)
			post.BrickColor = BrickColor.new("Dark stone grey")
			post.Material = Enum.Material.Metal
			post.CFrame = origin + Vector3.new(xPos, 2, zPos)
			post.Parent = folder

			-- Horizontal bar connecting to next post
			if p < fenceCount - 1 then
				local bar = Instance.new("Part")
				bar.Name = "FenceBar"
				bar.Anchored = true
				bar.Size = Vector3.new(1, 0.5, fenceSpacing)
				bar.BrickColor = BrickColor.new("Dark stone grey")
				bar.Material = Enum.Material.Metal
				bar.CFrame = origin + Vector3.new(xPos, 3.5, zPos + fenceSpacing / 2)
				bar.Parent = folder
			end
		end
	end

	-- ── Decorative trees (on the grass border area) ─────────────────────────
	local treePositions = {
		Vector3.new(-platWidth / 2 - 10, 0, platCenterZ - platDepth / 3),
		Vector3.new(platWidth / 2 + 10, 0, platCenterZ - platDepth / 3),
		Vector3.new(-platWidth / 2 - 10, 0, platCenterZ),
		Vector3.new(platWidth / 2 + 10, 0, platCenterZ),
		Vector3.new(-platWidth / 2 - 10, 0, platCenterZ + platDepth / 3),
		Vector3.new(platWidth / 2 + 10, 0, platCenterZ + platDepth / 3),
	}
	for t, treeOff in treePositions do
		-- Brown trunk
		local trunk = Instance.new("Part")
		trunk.Name = "TreeTrunk_" .. t
		trunk.Anchored = true
		trunk.Size = Vector3.new(2, 6, 2)
		trunk.BrickColor = BrickColor.new("Reddish brown")
		trunk.Material = Enum.Material.Wood
		trunk.CFrame = origin + treeOff + Vector3.new(0, 2, 0)
		trunk.Parent = folder

		-- Green canopy (sphere)
		local canopy = Instance.new("Part")
		canopy.Name = "TreeCanopy_" .. t
		canopy.Anchored = true
		canopy.Shape = Enum.PartType.Ball
		canopy.Size = Vector3.new(8, 8, 8)
		canopy.BrickColor = BrickColor.new("Forest green")
		canopy.Material = Enum.Material.Grass
		canopy.CFrame = origin + treeOff + Vector3.new(0, 9, 0)
		canopy.Parent = folder
	end

	-- ── Rock clusters at corners ────────────────────────────────────────────
	local rockCorners = {
		Vector3.new(-platWidth / 2 + 10, 0, platCenterZ - platDepth / 2 + 10),
		Vector3.new(platWidth / 2 - 10, 0, platCenterZ - platDepth / 2 + 10),
		Vector3.new(-platWidth / 2 + 10, 0, platCenterZ + platDepth / 2 - 10),
		Vector3.new(platWidth / 2 - 10, 0, platCenterZ + platDepth / 2 - 10),
	}
	for c, cornerOff in rockCorners do
		-- 3 rocks per cluster
		local rockSizes = {
			Vector3.new(4, 3, 4),
			Vector3.new(3, 2, 3),
			Vector3.new(2, 2, 2),
		}
		local rockOffsets = {
			Vector3.new(0, 1.5, 0),
			Vector3.new(3, 1, 2),
			Vector3.new(-2, 1, 1),
		}
		for r = 1, 3 do
			local rock = Instance.new("Part")
			rock.Name = "Rock_" .. c .. "_" .. r
			rock.Anchored = true
			rock.Size = rockSizes[r]
			rock.BrickColor = BrickColor.new("Medium stone grey")
			rock.Material = Enum.Material.Slate
			rock.CFrame = origin + cornerOff + rockOffsets[r]
			rock.Parent = folder
		end
	end

	-- ── Helipad marking (near slot index 5, the Helipad building) ───────────
	local helipadCF = itemCFrame(origin, 4) -- slot 4 = order 5 (Helipad)
	local helipadBase = Instance.new("Part")
	helipadBase.Name = "HelipadMarking"
	helipadBase.Anchored = true
	helipadBase.Size = Vector3.new(20, 0.2, 20)
	helipadBase.BrickColor = BrickColor.new("Medium stone grey")
	helipadBase.Material = Enum.Material.Concrete
	helipadBase.CFrame = helipadCF + Vector3.new(0, 0.1, 0)
	helipadBase.Parent = folder

	-- "H" made of two vertical bars and one horizontal bar (yellow)
	local hBarV1 = Instance.new("Part")
	hBarV1.Name = "HelipadH_V1"
	hBarV1.Anchored = true
	hBarV1.Size = Vector3.new(2, 0.15, 10)
	hBarV1.BrickColor = BrickColor.new("Bright yellow")
	hBarV1.Material = Enum.Material.SmoothPlastic
	hBarV1.CFrame = helipadCF + Vector3.new(-3, 0.25, 0)
	hBarV1.Parent = folder

	local hBarV2 = Instance.new("Part")
	hBarV2.Name = "HelipadH_V2"
	hBarV2.Anchored = true
	hBarV2.Size = Vector3.new(2, 0.15, 10)
	hBarV2.BrickColor = BrickColor.new("Bright yellow")
	hBarV2.Material = Enum.Material.SmoothPlastic
	hBarV2.CFrame = helipadCF + Vector3.new(3, 0.25, 0)
	hBarV2.Parent = folder

	local hBarH = Instance.new("Part")
	hBarH.Name = "HelipadH_H"
	hBarH.Anchored = true
	hBarH.Size = Vector3.new(8, 0.15, 2)
	hBarH.BrickColor = BrickColor.new("Bright yellow")
	hBarH.Material = Enum.Material.SmoothPlastic
	hBarH.CFrame = helipadCF + Vector3.new(0, 0.25, 0)
	hBarH.Parent = folder

	-- ── SpawnLocation ───────────────────────────────────────────────────────
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

	-- Invisible walls around the platform edges to prevent falling off
	local wallHeight = 20
	local wallThickness = 2
	local walls = {
		{ offset = Vector3.new(0, wallHeight / 2, platCenterZ - platDepth / 2), size = Vector3.new(platWidth, wallHeight, wallThickness) }, -- -Z
		{ offset = Vector3.new(0, wallHeight / 2, platCenterZ + platDepth / 2), size = Vector3.new(platWidth, wallHeight, wallThickness) }, -- +Z
		{ offset = Vector3.new(-platWidth / 2, wallHeight / 2, platCenterZ), size = Vector3.new(wallThickness, wallHeight, platDepth) }, -- -X
		{ offset = Vector3.new(platWidth / 2, wallHeight / 2, platCenterZ), size = Vector3.new(wallThickness, wallHeight, platDepth) }, -- +X
	}
	for i, wallDef in walls do
		local wall = Instance.new("Part")
		wall.Name = "Wall_" .. i
		wall.Anchored = true
		wall.Size = wallDef.size
		wall.CFrame = origin + wallDef.offset
		wall.Transparency = 1
		wall.CanCollide = true
		wall.Parent = folder
	end

	-- Spawn free tier-1 Command Center
	local ccItem = TycoonConfig.Items["CommandCenter"]
	if ccItem then
		local ccCF = itemCFrame(origin, 0)
		spawnBuildingPart(folder, ccItem, ccCF)
	end

	-- Spawn the first purchasable button (Barracks, order 2)
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

	-- Position the button in the grid slot for this item (order is 1-indexed, slot is 0-indexed)
	local slotIndex = nextItem.order - 1
	local cf = itemCFrame(origin, slotIndex)
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

	-- Spawn building placeholder
	local item = TycoonConfig.Items[itemName]
	if item then
		local slotIndex = itemOrder(itemName) - 1
		local cf = itemCFrame(origin, slotIndex)
		spawnBuildingPart(folder, item, cf)
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
