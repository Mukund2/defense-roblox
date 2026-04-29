--!strict
-- TycoonHUD/init.client.luau
-- Builds the full military-themed HUD via Instance.new() and exposes an API
-- through _G.TycoonHUD for TycoonClient to call.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FormatNumber = require(ReplicatedStorage:WaitForChild("FormatNumber", 30) :: ModuleScript)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ── Design tokens ─────────────────────────────────────────────────────────────
local COLOR = {
	BG_DARK      = Color3.fromRGB(20, 25, 35),
	BG_PANEL     = Color3.fromRGB(14, 18, 26),
	GREEN        = Color3.fromRGB(74, 124, 89),   -- military green
	GREEN_LIGHT  = Color3.fromRGB(100, 180, 120),
	GREEN_DIM    = Color3.fromRGB(50, 85, 60),
	AMBER        = Color3.fromRGB(200, 155, 60),
	WHITE        = Color3.fromRGB(240, 240, 240),
	GRAY         = Color3.fromRGB(160, 170, 180),
	STROKE_GREEN = Color3.fromRGB(60, 100, 72),
	TRANSPARENT  = Color3.fromRGB(0, 0, 0),
}

local MAX_BASE_LEVEL = 15

-- ── Utility constructors ──────────────────────────────────────────────────────

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
	pad.PaddingLeft   = UDim.new(0, h)
	pad.PaddingRight  = UDim.new(0, h)
	pad.PaddingTop    = UDim.new(0, v)
	pad.PaddingBottom = UDim.new(0, v)
	pad.Parent = parent
end

local function newLabel(
	parent: Instance,
	name: string,
	text: string,
	font: Enum.Font,
	textSize: number,
	textColor: Color3,
	bgColor: Color3?,
	bgTransparency: number?
): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.Text = text
	lbl.Font = font
	lbl.TextSize = textSize
	lbl.TextColor3 = textColor
	lbl.BackgroundColor3 = bgColor or COLOR.TRANSPARENT
	lbl.BackgroundTransparency = bgTransparency or 1
	lbl.BorderSizePixel = 0
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Parent = parent
	return lbl
end

-- ── Root ScreenGui ────────────────────────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TycoonHUD"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

-- ═════════════════════════════════════════════════════════════════════════════
-- TOP BAR — money display
-- ═════════════════════════════════════════════════════════════════════════════

local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.AnchorPoint = Vector2.new(0.5, 0)
TopBar.Position = UDim2.new(0.5, 0, 0, 14)
TopBar.Size = UDim2.new(0, 320, 0, 62)
TopBar.BackgroundColor3 = COLOR.BG_DARK
TopBar.BackgroundTransparency = 0.12
TopBar.BorderSizePixel = 0
TopBar.Parent = ScreenGui
applyCorner(TopBar, 8)
applyStroke(TopBar, COLOR.STROKE_GREEN, 1)
applyPadding(TopBar, 10, 0)

-- Layout inside TopBar
local TopBarLayout = Instance.new("UIListLayout")
TopBarLayout.FillDirection = Enum.FillDirection.Horizontal
TopBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TopBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TopBarLayout.Padding = UDim.new(0, 8)
TopBarLayout.Parent = TopBar

-- Dollar icon
local DollarIcon = newLabel(
	TopBar, "DollarIcon", "$",
	Enum.Font.GothamBold, 28, COLOR.GREEN,
	COLOR.TRANSPARENT, 1
)
DollarIcon.Size = UDim2.new(0, 28, 1, 0)

-- Money amount
local MoneyLabel = newLabel(
	TopBar, "MoneyLabel", "0",
	Enum.Font.GothamBold, 26, COLOR.WHITE,
	COLOR.TRANSPARENT, 1
)
MoneyLabel.Size = UDim2.new(0, 160, 1, 0)

-- Income rate
local IncomeLabel = newLabel(
	TopBar, "IncomeLabel", "+$0/sec",
	Enum.Font.GothamMedium, 14, COLOR.GREEN_LIGHT,
	COLOR.TRANSPARENT, 1
)
IncomeLabel.Size = UDim2.new(0, 90, 1, 0)

-- ═════════════════════════════════════════════════════════════════════════════
-- BOTTOM-LEFT PANEL — base level
-- ═════════════════════════════════════════════════════════════════════════════

local BottomPanel = Instance.new("Frame")
BottomPanel.Name = "BottomPanel"
BottomPanel.AnchorPoint = Vector2.new(0, 1)
BottomPanel.Position = UDim2.new(0, 16, 1, -16)
BottomPanel.Size = UDim2.new(0, 210, 0, 70)
BottomPanel.BackgroundColor3 = COLOR.BG_DARK
BottomPanel.BackgroundTransparency = 0.12
BottomPanel.BorderSizePixel = 0
BottomPanel.Parent = ScreenGui
applyCorner(BottomPanel, 8)
applyStroke(BottomPanel, COLOR.STROKE_GREEN, 1)
applyPadding(BottomPanel, 10, 8)

local BaseLevelLayout = Instance.new("UIListLayout")
BaseLevelLayout.FillDirection = Enum.FillDirection.Vertical
BaseLevelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
BaseLevelLayout.Padding = UDim.new(0, 5)
BaseLevelLayout.Parent = BottomPanel

local BaseLevelLabel = newLabel(
	BottomPanel, "BaseLevelLabel", "BASE LEVEL: 0 / " .. MAX_BASE_LEVEL,
	Enum.Font.GothamMedium, 13, COLOR.GRAY,
	COLOR.TRANSPARENT, 1
)
BaseLevelLabel.Size = UDim2.new(1, 0, 0, 18)
BaseLevelLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Progress bar container
local BarContainer = Instance.new("Frame")
BarContainer.Name = "BarContainer"
BarContainer.Size = UDim2.new(1, 0, 0, 12)
BarContainer.BackgroundColor3 = COLOR.BG_PANEL
BarContainer.BorderSizePixel = 0
BarContainer.Parent = BottomPanel
applyCorner(BarContainer, 4)
applyStroke(BarContainer, COLOR.GREEN_DIM, 1)

local ProgressFill = Instance.new("Frame")
ProgressFill.Name = "ProgressFill"
ProgressFill.Size = UDim2.new(0, 0, 1, 0)   -- width updated via UpdateBaseLevel
ProgressFill.BackgroundColor3 = COLOR.GREEN
ProgressFill.BorderSizePixel = 0
ProgressFill.Parent = BarContainer
applyCorner(ProgressFill, 4)

-- ═════════════════════════════════════════════════════════════════════════════
-- NOTIFICATION POPUP — item unlocked
-- ═════════════════════════════════════════════════════════════════════════════

local NotifFrame = Instance.new("Frame")
NotifFrame.Name = "NotifFrame"
NotifFrame.AnchorPoint = Vector2.new(0.5, 0)
NotifFrame.Position = UDim2.new(0.5, 0, 0, -160)  -- starts off-screen above
NotifFrame.Size = UDim2.new(0, 360, 0, 130)
NotifFrame.BackgroundColor3 = COLOR.BG_PANEL
NotifFrame.BackgroundTransparency = 0.08
NotifFrame.BorderSizePixel = 0
NotifFrame.ZIndex = 10
NotifFrame.Parent = ScreenGui
applyCorner(NotifFrame, 8)
applyStroke(NotifFrame, COLOR.GREEN, 2)
applyPadding(NotifFrame, 16, 12)

local NotifLayout = Instance.new("UIListLayout")
NotifLayout.FillDirection = Enum.FillDirection.Vertical
NotifLayout.VerticalAlignment = Enum.VerticalAlignment.Center
NotifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
NotifLayout.Padding = UDim.new(0, 6)
NotifLayout.Parent = NotifFrame

-- "ITEM UNLOCKED" header
local NotifHeader = newLabel(
	NotifFrame, "NotifHeader", "ITEM UNLOCKED",
	Enum.Font.GothamBold, 13, COLOR.AMBER,
	COLOR.TRANSPARENT, 1
)
NotifHeader.Size = UDim2.new(1, 0, 0, 18)
NotifHeader.TextXAlignment = Enum.TextXAlignment.Center

-- Item name
local NotifItemName = newLabel(
	NotifFrame, "NotifItemName", "",
	Enum.Font.GothamBold, 22, COLOR.WHITE,
	COLOR.TRANSPARENT, 1
)
NotifItemName.Size = UDim2.new(1, 0, 0, 28)
NotifItemName.TextXAlignment = Enum.TextXAlignment.Center

-- Description
local NotifDesc = newLabel(
	NotifFrame, "NotifDesc", "",
	Enum.Font.GothamMedium, 12, COLOR.GRAY,
	COLOR.TRANSPARENT, 1
)
NotifDesc.Size = UDim2.new(1, 0, 0, 38)
NotifDesc.TextWrapped = true
NotifDesc.TextXAlignment = Enum.TextXAlignment.Center

-- ═════════════════════════════════════════════════════════════════════════════
-- HUD API
-- ═════════════════════════════════════════════════════════════════════════════

-- Shared tween info constants
local MONEY_TWEEN_INFO  = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NOTIF_TWEEN_INFO  = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local NOTIF_OUT_INFO    = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local LEVEL_TWEEN_INFO  = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Notification queue to prevent overlapping popups.
local notifQueue: { { itemName: string, description: string } } = {}
local notifBusy = false

-- Displayed money value (used as the tween start point).
local displayedMoney = 0

-- Counts money up (or down) from the current displayed value to the new value.
local function UpdateMoney(amount: number)
	-- We animate by tweening a proxy NumberValue.
	local proxy = Instance.new("NumberValue")
	proxy.Value = displayedMoney

	local tween = TweenService:Create(proxy, MONEY_TWEEN_INFO, { Value = amount })
	proxy.Changed:Connect(function(v: number)
		MoneyLabel.Text = FormatNumber.money(v)
	end)
	tween.Completed:Connect(function()
		MoneyLabel.Text = FormatNumber.money(amount)
		displayedMoney = amount
		proxy:Destroy()
	end)
	tween:Play()
end

local function UpdateIncome(rate: number)
	IncomeLabel.Text = FormatNumber.income(rate)
end

-- Slides the notification frame in from the top, waits, then slides it back.
local function showNotifImmediate(itemName: string, description: string)
	notifBusy = true
	NotifItemName.Text = itemName
	NotifDesc.Text = description

	-- Slide in to vertical center of screen (slightly above center looks best).
	local slideInTween = TweenService:Create(NotifFrame, NOTIF_TWEEN_INFO, {
		Position = UDim2.new(0.5, 0, 0.28, 0),
	})
	slideInTween:Play()
	slideInTween.Completed:Wait()

	task.wait(3)

	-- Slide out back above screen.
	local slideOutTween = TweenService:Create(NotifFrame, NOTIF_OUT_INFO, {
		Position = UDim2.new(0.5, 0, 0, -160),
	})
	slideOutTween:Play()
	slideOutTween.Completed:Wait()

	notifBusy = false

	-- Process next queued notification if any.
	if #notifQueue > 0 then
		local next = table.remove(notifQueue, 1)
		task.spawn(showNotifImmediate, next.itemName, next.description)
	end
end

local function ShowUnlockNotification(itemName: string, description: string)
	if notifBusy then
		table.insert(notifQueue, { itemName = itemName, description = description })
	else
		task.spawn(showNotifImmediate, itemName, description)
	end
end

local function UpdateBaseLevel(level: number)
	local clamped = math.clamp(level, 0, MAX_BASE_LEVEL)
	BaseLevelLabel.Text = "BASE LEVEL: " .. tostring(clamped) .. " / " .. MAX_BASE_LEVEL

	local targetWidth = clamped / MAX_BASE_LEVEL
	local fillTween = TweenService:Create(ProgressFill, LEVEL_TWEEN_INFO, {
		Size = UDim2.new(targetWidth, 0, 1, 0),
	})
	fillTween:Play()
end

-- ── Publish API ───────────────────────────────────────────────────────────────
-- TycoonClient polls _G.TycoonHUD until it's set.
_G.TycoonHUD = {
	UpdateMoney            = UpdateMoney,
	UpdateIncome           = UpdateIncome,
	ShowUnlockNotification = ShowUnlockNotification,
	UpdateBaseLevel        = UpdateBaseLevel,
}
