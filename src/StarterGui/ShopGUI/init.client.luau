--!strict
-- ShopGUI/init.client.luau
-- Full-screen military shop overlay built with Instance.new().
-- Toggle with "B" key or via _G.ShopGUI.Toggle().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local FormatNumber = require(ReplicatedStorage:WaitForChild("FormatNumber", 30) :: ModuleScript)
local TycoonConfig = require(ReplicatedStorage:WaitForChild("TycoonConfig", 30) :: ModuleScript)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes", 30) :: ModuleScript)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ── Design tokens (shared with TycoonHUD) ───────────────────────────────────
local COLOR = {
	BG_DARK = Color3.fromRGB(20, 25, 35),
	BG_PANEL = Color3.fromRGB(14, 18, 26),
	GREEN = Color3.fromRGB(74, 124, 89),
	GREEN_LIGHT = Color3.fromRGB(100, 180, 120),
	GREEN_DIM = Color3.fromRGB(50, 85, 60),
	AMBER = Color3.fromRGB(200, 155, 60),
	WHITE = Color3.fromRGB(240, 240, 240),
	GRAY = Color3.fromRGB(160, 170, 180),
	STROKE_GREEN = Color3.fromRGB(60, 100, 72),
	RED = Color3.fromRGB(200, 60, 60),
	RED_DIM = Color3.fromRGB(120, 50, 50),
	TRANSPARENT = Color3.fromRGB(0, 0, 0),
}

-- Category color bars
local CATEGORY_COLORS: { [string]: Color3 } = {
	Building = COLOR.GREEN,
	Vehicle = Color3.fromRGB(80, 130, 180),
	Aircraft = Color3.fromRGB(120, 100, 180),
	Naval = Color3.fromRGB(60, 140, 180),
	Strategic = COLOR.AMBER,
}

-- ── State ───────────────────────────────────────────────────────────────────
local currentMoney: number = 0
local unlockedItems: { [string]: boolean } = {}
local isOpen: boolean = false

-- ── Utility constructors ────────────────────────────────────────────────────

local function applyCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function applyStroke(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

local function applyPadding(parent: Instance, h: number, v: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, h)
	pad.PaddingRight = UDim.new(0, h)
	pad.PaddingTop = UDim.new(0, v)
	pad.PaddingBottom = UDim.new(0, v)
	pad.Parent = parent
end

-- ── Root ScreenGui ──────────────────────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ShopGUI"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 5
ScreenGui.Enabled = false
ScreenGui.Parent = PlayerGui

-- ── Backdrop (semi-transparent, click-to-close) ─────────────────────────────

local Backdrop = Instance.new("TextButton")
Backdrop.Name = "Backdrop"
Backdrop.Size = UDim2.new(1, 0, 1, 0)
Backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Backdrop.BackgroundTransparency = 0.45
Backdrop.BorderSizePixel = 0
Backdrop.Text = ""
Backdrop.AutoButtonColor = false
Backdrop.ZIndex = 1
Backdrop.Parent = ScreenGui

-- ── Main Panel ──────────────────────────────────────────────────────────────

local Panel = Instance.new("Frame")
Panel.Name = "Panel"
Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.Position = UDim2.new(0.5, 0, 0.5, 0)
Panel.Size = UDim2.new(0, 600, 0, 700)
Panel.BackgroundColor3 = COLOR.BG_DARK
Panel.BackgroundTransparency = 0.04
Panel.BorderSizePixel = 0
Panel.ZIndex = 2
Panel.Parent = ScreenGui
applyCorner(Panel, 10)
applyStroke(Panel, COLOR.STROKE_GREEN, 2)

-- ── Header ──────────────────────────────────────────────────────────────────

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 56)
Header.BackgroundColor3 = COLOR.BG_PANEL
Header.BackgroundTransparency = 0.3
Header.BorderSizePixel = 0
Header.ZIndex = 3
Header.Parent = Panel
applyCorner(Header, 10)

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Name = "Title"
HeaderTitle.Size = UDim2.new(1, -50, 1, 0)
HeaderTitle.Position = UDim2.new(0, 16, 0, 0)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Text = "MILITARY SHOP"
HeaderTitle.Font = Enum.Font.GothamBold
HeaderTitle.TextSize = 22
HeaderTitle.TextColor3 = COLOR.AMBER
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.ZIndex = 4
HeaderTitle.Parent = Header

-- Close button (X)
local CloseButton = Instance.new("TextButton")
CloseButton.Name = "CloseButton"
CloseButton.AnchorPoint = Vector2.new(1, 0)
CloseButton.Position = UDim2.new(1, -8, 0, 8)
CloseButton.Size = UDim2.new(0, 40, 0, 40)
CloseButton.BackgroundColor3 = COLOR.RED_DIM
CloseButton.BackgroundTransparency = 0.5
CloseButton.Text = "X"
CloseButton.Font = Enum.Font.GothamBold
CloseButton.TextSize = 18
CloseButton.TextColor3 = COLOR.WHITE
CloseButton.BorderSizePixel = 0
CloseButton.ZIndex = 5
CloseButton.Parent = Header
applyCorner(CloseButton, 6)

-- ── Scrolling item list ─────────────────────────────────────────────────────

local ITEM_HEIGHT = 80
local ITEM_PADDING = 6

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Name = "ItemList"
ScrollFrame.Position = UDim2.new(0, 0, 0, 60)
ScrollFrame.Size = UDim2.new(1, 0, 1, -60)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 6
ScrollFrame.ScrollBarImageColor3 = COLOR.GREEN_DIM
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, (#TycoonConfig.Ordered * (ITEM_HEIGHT + ITEM_PADDING)) + 12)
ScrollFrame.ZIndex = 3
ScrollFrame.Parent = Panel
applyPadding(ScrollFrame, 12, 6)

local ListLayout = Instance.new("UIListLayout")
ListLayout.FillDirection = Enum.FillDirection.Vertical
ListLayout.Padding = UDim.new(0, ITEM_PADDING)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = ScrollFrame

-- ── Item row references (for live updates) ──────────────────────────────────

type ItemRow = {
	frame: Frame,
	nameLabel: TextLabel,
	descLabel: TextLabel,
	costLabel: TextLabel,
	incomeLabel: TextLabel,
	buyButton: TextButton,
	statusLabel: TextLabel,
	categoryBar: Frame,
	itemKey: string,
}

local itemRows: { ItemRow } = {}

-- Determine the key name from TycoonConfig for a given item
local function getItemKey(item: typeof(TycoonConfig.Ordered[1])): string
	for key, val in TycoonConfig.Items do
		if val == item then
			return key
		end
	end
	return item.modelName
end

-- Get the previous item key in unlock order (nil for first item)
local function getPrevItemKey(order: number): string?
	for _, item in TycoonConfig.Ordered do
		if item.order == order - 1 then
			return getItemKey(item)
		end
	end
	return nil
end

-- Build each item row
for i, item in TycoonConfig.Ordered do
	local itemKey = getItemKey(item)
	local catColor = CATEGORY_COLORS[item.category] or COLOR.GREEN

	local Row = Instance.new("Frame")
	Row.Name = "Item_" .. itemKey
	Row.Size = UDim2.new(1, 0, 0, ITEM_HEIGHT)
	Row.BackgroundColor3 = COLOR.BG_PANEL
	Row.BackgroundTransparency = 0.15
	Row.BorderSizePixel = 0
	Row.LayoutOrder = item.order
	Row.ZIndex = 4
	Row.Parent = ScrollFrame
	applyCorner(Row, 6)

	-- Category color bar (left edge)
	local CatBar = Instance.new("Frame")
	CatBar.Name = "CatBar"
	CatBar.Size = UDim2.new(0, 4, 1, -8)
	CatBar.Position = UDim2.new(0, 4, 0, 4)
	CatBar.BackgroundColor3 = catColor
	CatBar.BorderSizePixel = 0
	CatBar.ZIndex = 5
	CatBar.Parent = Row
	applyCorner(CatBar, 2)

	-- Item name
	local NameLabel = Instance.new("TextLabel")
	NameLabel.Name = "ItemName"
	NameLabel.Size = UDim2.new(0, 240, 0, 22)
	NameLabel.Position = UDim2.new(0, 16, 0, 10)
	NameLabel.BackgroundTransparency = 1
	NameLabel.Text = item.name
	NameLabel.Font = Enum.Font.GothamBold
	NameLabel.TextSize = 16
	NameLabel.TextColor3 = COLOR.WHITE
	NameLabel.TextXAlignment = Enum.TextXAlignment.Left
	NameLabel.ZIndex = 5
	NameLabel.Parent = Row

	-- Description
	local DescLabel = Instance.new("TextLabel")
	DescLabel.Name = "Description"
	DescLabel.Size = UDim2.new(0, 300, 0, 16)
	DescLabel.Position = UDim2.new(0, 16, 0, 34)
	DescLabel.BackgroundTransparency = 1
	DescLabel.Text = item.description
	DescLabel.Font = Enum.Font.GothamMedium
	DescLabel.TextSize = 11
	DescLabel.TextColor3 = COLOR.GRAY
	DescLabel.TextXAlignment = Enum.TextXAlignment.Left
	DescLabel.TextTruncate = Enum.TextTruncate.AtEnd
	DescLabel.ZIndex = 5
	DescLabel.Parent = Row

	-- Cost label
	local CostLabel = Instance.new("TextLabel")
	CostLabel.Name = "Cost"
	CostLabel.Size = UDim2.new(0, 90, 0, 20)
	CostLabel.Position = UDim2.new(0, 16, 0, 54)
	CostLabel.BackgroundTransparency = 1
	CostLabel.Text = FormatNumber.money(item.cost)
	CostLabel.Font = Enum.Font.GothamBold
	CostLabel.TextSize = 14
	CostLabel.TextColor3 = COLOR.AMBER
	CostLabel.TextXAlignment = Enum.TextXAlignment.Left
	CostLabel.ZIndex = 5
	CostLabel.Parent = Row

	-- Income label
	local IncLabel = Instance.new("TextLabel")
	IncLabel.Name = "Income"
	IncLabel.Size = UDim2.new(0, 80, 0, 20)
	IncLabel.Position = UDim2.new(0, 110, 0, 54)
	IncLabel.BackgroundTransparency = 1
	IncLabel.Text = "+" .. FormatNumber.money(item.incomePerSecond) .. "/s"
	IncLabel.Font = Enum.Font.GothamMedium
	IncLabel.TextSize = 12
	IncLabel.TextColor3 = COLOR.GREEN_LIGHT
	IncLabel.TextXAlignment = Enum.TextXAlignment.Left
	IncLabel.ZIndex = 5
	IncLabel.Parent = Row

	-- Buy button / status
	local BuyButton = Instance.new("TextButton")
	BuyButton.Name = "BuyButton"
	BuyButton.AnchorPoint = Vector2.new(1, 0.5)
	BuyButton.Position = UDim2.new(1, -12, 0.5, 0)
	BuyButton.Size = UDim2.new(0, 90, 0, 36)
	BuyButton.BackgroundColor3 = COLOR.GREEN
	BuyButton.Text = "BUY"
	BuyButton.Font = Enum.Font.GothamBold
	BuyButton.TextSize = 15
	BuyButton.TextColor3 = COLOR.WHITE
	BuyButton.BorderSizePixel = 0
	BuyButton.ZIndex = 6
	BuyButton.Parent = Row
	applyCorner(BuyButton, 6)

	-- Status label (for locked / purchased messages, overlays buy button area)
	local StatusLabel = Instance.new("TextLabel")
	StatusLabel.Name = "StatusLabel"
	StatusLabel.AnchorPoint = Vector2.new(1, 0.5)
	StatusLabel.Position = UDim2.new(1, -12, 0.5, 0)
	StatusLabel.Size = UDim2.new(0, 130, 0, 36)
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.Text = ""
	StatusLabel.Font = Enum.Font.GothamMedium
	StatusLabel.TextSize = 12
	StatusLabel.TextColor3 = COLOR.GRAY
	StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
	StatusLabel.ZIndex = 6
	StatusLabel.Visible = false
	StatusLabel.Parent = Row

	-- Wire up purchase
	BuyButton.MouseButton1Click:Connect(function()
		if unlockedItems[itemKey] then
			return
		end
		if currentMoney < item.cost then
			-- Trigger insufficient funds feedback on HUD
			local hudApi = _G.TycoonHUD :: any
			if hudApi and hudApi.ShowInsufficientFunds then
				hudApi.ShowInsufficientFunds(item.cost - currentMoney)
			end
			return
		end
		Remotes.PurchaseItem:FireServer(itemKey)
	end)

	table.insert(itemRows, {
		frame = Row,
		nameLabel = NameLabel,
		descLabel = DescLabel,
		costLabel = CostLabel,
		incomeLabel = IncLabel,
		buyButton = BuyButton,
		statusLabel = StatusLabel,
		categoryBar = CatBar,
		itemKey = itemKey,
	})
end

-- ── Refresh all item row visuals ────────────────────────────────────────────

local function refreshItems()
	for _, row in itemRows do
		local item = TycoonConfig.Items[row.itemKey]
		if not item then
			continue
		end

		if unlockedItems[row.itemKey] then
			-- Already purchased
			row.buyButton.Visible = false
			row.statusLabel.Visible = true
			row.statusLabel.Text = "OWNED"
			row.statusLabel.TextColor3 = COLOR.GREEN_LIGHT
			row.nameLabel.TextColor3 = COLOR.GRAY
			row.frame.BackgroundTransparency = 0.5
			row.categoryBar.BackgroundTransparency = 0.5
		else
			-- Check if the previous item is unlocked (sequential unlock)
			local prevKey = getPrevItemKey(item.order)
			local prevUnlocked = (prevKey == nil) or (unlockedItems[prevKey] == true)

			if prevUnlocked then
				-- This is the next item to buy
				row.buyButton.Visible = true
				row.statusLabel.Visible = false
				row.nameLabel.TextColor3 = COLOR.WHITE
				row.frame.BackgroundTransparency = 0.15
				row.categoryBar.BackgroundTransparency = 0

				if currentMoney >= item.cost then
					-- Can afford
					row.buyButton.BackgroundColor3 = COLOR.GREEN
					row.buyButton.TextColor3 = COLOR.WHITE
					row.buyButton.Text = "BUY"
					row.costLabel.TextColor3 = COLOR.AMBER
				else
					-- Cannot afford
					row.buyButton.BackgroundColor3 = COLOR.GREEN_DIM
					row.buyButton.TextColor3 = COLOR.GRAY
					row.buyButton.Text = "BUY"
					row.costLabel.TextColor3 = COLOR.RED
				end
			else
				-- Locked (previous item not yet purchased)
				row.buyButton.Visible = false
				row.statusLabel.Visible = true
				local prevItem = if prevKey then TycoonConfig.Items[prevKey] else nil
				local prevName = if prevItem then prevItem.name else "???"
				row.statusLabel.Text = "Requires " .. prevName
				row.statusLabel.TextColor3 = COLOR.GRAY
				row.nameLabel.TextColor3 = Color3.fromRGB(100, 100, 110)
				row.frame.BackgroundTransparency = 0.55
				row.categoryBar.BackgroundTransparency = 0.6
				row.costLabel.TextColor3 = Color3.fromRGB(100, 100, 110)
			end
		end
	end
end

-- ── Toggle logic ────────────────────────────────────────────────────────────

local PANEL_IN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_OUT_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function openShop()
	if isOpen then
		return
	end
	isOpen = true
	refreshItems()
	Panel.Size = UDim2.new(0, 600, 0, 0)
	ScreenGui.Enabled = true
	local tween = TweenService:Create(Panel, PANEL_IN_INFO, {
		Size = UDim2.new(0, 600, 0, 700),
	})
	tween:Play()
end

local function closeShop()
	if not isOpen then
		return
	end
	isOpen = false
	local tween = TweenService:Create(Panel, PANEL_OUT_INFO, {
		Size = UDim2.new(0, 600, 0, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not isOpen then
			ScreenGui.Enabled = false
		end
	end)
end

local function toggleShop()
	if isOpen then
		closeShop()
	else
		openShop()
	end
end

-- Close on backdrop click
Backdrop.MouseButton1Click:Connect(closeShop)

-- Close on X button
CloseButton.MouseButton1Click:Connect(closeShop)

-- Toggle on B key
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		toggleShop()
	end
end)

-- ── Remote listeners ────────────────────────────────────────────────────────

Remotes.UpdateMoney.OnClientEvent:Connect(function(amount: number)
	currentMoney = amount
	if isOpen then
		refreshItems()
	end
end)

Remotes.UnlockItem.OnClientEvent:Connect(function(itemName: string)
	unlockedItems[itemName] = true
	if isOpen then
		refreshItems()
	end
end)

-- ── Initialize from server data ─────────────────────────────────────────────

task.spawn(function()
	local ok, data = pcall(function()
		return Remotes.GetPlayerData:InvokeServer()
	end)
	if ok and data then
		local playerData = data :: { money: number, income: number, unlockedItems: { string } }
		currentMoney = playerData.money or 0
		if playerData.unlockedItems then
			for _, itemName in playerData.unlockedItems do
				unlockedItems[itemName] = true
			end
		end
		refreshItems()
	end
end)

-- ── Expose API ──────────────────────────────────────────────────────────────

_G.ShopGUI = {
	Toggle = toggleShop,
	Open = openShop,
	Close = closeShop,
	IsOpen = function(): boolean
		return isOpen
	end,
}
