--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig = require(ReplicatedStorage.TycoonConfig) :: any

-- ── Types ─────────────────────────────────────────────────────────────────────

type TycoonItemCategory = "Building" | "Vehicle" | "Aircraft" | "Naval" | "Strategic"

-- ── Constants ─────────────────────────────────────────────────────────────────

local PAD_SPACING = 300 -- studs between pad origins in the X axis
local PAD_BASE_POSITION = Vector3.new(0, 0, 0) -- first pad anchor

-- Grid layout for spawned buildings relative to a pad origin.
-- Items are placed in rows of GRID_COLS, each cell is CELL_SIZE studs wide.
local GRID_COLS = 4
local CELL_SIZE = 24 -- studs per cell
local CELL_DEPTH = 20 -- studs deep per row

-- Category colour palette (BrickColor names)
local CATEGORY_COLOR: { [TycoonItemCategory]: BrickColor } = {
	Building = BrickColor.new("Medium stone grey"),
	Vehicle = BrickColor.new("Bright green"),
	Aircraft = BrickColor.new("Bright blue"),
	Naval = BrickColor.new("Dark blue"),
	Strategic = BrickColor.new("Bright red"),
}

-- Button colour (neon cyan)
local BUTTON_COLOR = BrickColor.new("Cyan")
local BUTTON_MATERIAL = Enum.Material.Neon
local BUTTON_SIZE = Vector3.new(8, 0.5, 8)
local BUTTON_HEIGHT_OFFSET = 0.5 -- elevate slightly above ground

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
local function createButtonGui(parent: Part, itemName: string, cost: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ButtonGui"
	billboard.Size = UDim2.new(0, 200, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = itemName
	label.Parent = billboard

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, 0, 0.5, 0)
	costLabel.Position = UDim2.new(0, 0, 0.5, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.TextColor3 = Color3.new(1, 0.85, 0)
	costLabel.TextScaled = true
	costLabel.Font = Enum.Font.Gotham
	costLabel.Text = "$" .. tostring(cost)
	costLabel.Parent = billboard
end

--- Spawn the building placeholder Part for an unlocked item.
local function spawnBuildingPart(folder: Folder, item: any, cf: CFrame)
	local category: TycoonItemCategory = item.category
	local color = CATEGORY_COLOR[category] or BrickColor.new("Medium stone grey")

	-- Size varies slightly by category for visual variety
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

	-- Aircraft float above ground
	local heightAdjust = if category == "Aircraft" then 10 else size.Y / 2
	part.CFrame = cf + Vector3.new(0, heightAdjust, 0)

	-- Name tag
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
	createButtonGui(button, item.name, item.cost)

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

	-- Base platform
	local base = Instance.new("Part")
	base.Name = "BasePlatform"
	base.Anchored = true
	base.Size = Vector3.new(200, 2, 200)
	base.BrickColor = BrickColor.new("Sand green")
	base.Material = Enum.Material.Grass
	base.CFrame = origin + Vector3.new(0, -1, 50) -- centre the platform around the play area
	base.Parent = folder

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

	-- Remove old buttons
	for _, child in folder:GetChildren() do
		if child.Name:sub(1, 15) == "PurchaseButton_" then
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
