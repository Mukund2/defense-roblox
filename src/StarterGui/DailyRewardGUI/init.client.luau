--!strict

--[[
	DailyRewardGUI/init.client.luau
	-------------------------------
	Shows a 7-day reward calendar when the server fires ShowDailyReward.
	Past days show a checkmark, the current day is highlighted green with a
	CLAIM button, future days appear locked.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FormatNumber = require(ReplicatedStorage:WaitForChild("FormatNumber", 30) :: ModuleScript)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes", 30) :: ModuleScript) :: any

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ── Design tokens ────────────────────────────────────────────────────────────

local COLOR = {
	BG_DARK = Color3.fromRGB(20, 25, 35),
	BG_PANEL = Color3.fromRGB(14, 18, 26),
	GREEN = Color3.fromRGB(74, 124, 89),
	GREEN_LIGHT = Color3.fromRGB(100, 180, 120),
	GREEN_DIM = Color3.fromRGB(50, 85, 60),
	AMBER = Color3.fromRGB(200, 155, 60),
	WHITE = Color3.fromRGB(240, 240, 240),
	GRAY = Color3.fromRGB(160, 170, 180),
	GRAY_DARK = Color3.fromRGB(80, 85, 95),
	STROKE_GREEN = Color3.fromRGB(60, 100, 72),
	TRANSPARENT = Color3.fromRGB(0, 0, 0),
}

local REWARDS: { number } = { 500, 1000, 2000, 3000, 5000, 8000, 15000 }

-- ── Utility constructors ─────────────────────────────────────────────────────

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

-- ── Root ScreenGui ───────────────────────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DailyRewardGUI"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 20
ScreenGui.Parent = PlayerGui

-- ── Backdrop (dims background) ──────────────────────────────────────────────

local Backdrop = Instance.new("Frame")
Backdrop.Name = "Backdrop"
Backdrop.Size = UDim2.new(1, 0, 1, 0)
Backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Backdrop.BackgroundTransparency = 0.5
Backdrop.BorderSizePixel = 0
Backdrop.ZIndex = 1
Backdrop.Visible = false
Backdrop.Parent = ScreenGui

-- ── Main panel ──────────────────────────────────────────────────────────────

local Panel = Instance.new("Frame")
Panel.Name = "Panel"
Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.Position = UDim2.new(0.5, 0, 0.5, 0)
Panel.Size = UDim2.new(0, 620, 0, 280)
Panel.BackgroundColor3 = COLOR.BG_DARK
Panel.BackgroundTransparency = 0.05
Panel.BorderSizePixel = 0
Panel.ZIndex = 2
Panel.Visible = false
Panel.Parent = ScreenGui
applyCorner(Panel, 12)
applyStroke(Panel, COLOR.GREEN, 2)

-- ── Title ───────────────────────────────────────────────────────────────────

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.AnchorPoint = Vector2.new(0.5, 0)
Title.Position = UDim2.new(0.5, 0, 0, 16)
Title.Size = UDim2.new(1, -32, 0, 28)
Title.BackgroundTransparency = 1
Title.Text = "DAILY REWARDS"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 22
Title.TextColor3 = COLOR.AMBER
Title.ZIndex = 3
Title.Parent = Panel

-- ── Close button ────────────────────────────────────────────────────────────

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.AnchorPoint = Vector2.new(1, 0)
CloseBtn.Position = UDim2.new(1, -10, 0, 10)
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.BackgroundColor3 = COLOR.BG_PANEL
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.TextColor3 = COLOR.GRAY
CloseBtn.BorderSizePixel = 0
CloseBtn.ZIndex = 4
CloseBtn.Parent = Panel
applyCorner(CloseBtn, 6)

-- ── Day boxes container ─────────────────────────────────────────────────────

local DaysContainer = Instance.new("Frame")
DaysContainer.Name = "DaysContainer"
DaysContainer.AnchorPoint = Vector2.new(0.5, 0)
DaysContainer.Position = UDim2.new(0.5, 0, 0, 55)
DaysContainer.Size = UDim2.new(1, -40, 0, 130)
DaysContainer.BackgroundTransparency = 1
DaysContainer.ZIndex = 3
DaysContainer.Parent = Panel

local DaysLayout = Instance.new("UIListLayout")
DaysLayout.FillDirection = Enum.FillDirection.Horizontal
DaysLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
DaysLayout.VerticalAlignment = Enum.VerticalAlignment.Center
DaysLayout.Padding = UDim.new(0, 8)
DaysLayout.Parent = DaysContainer

-- Create 7 day boxes
local dayBoxes: { Frame } = {}
local dayLabels: { TextLabel } = {}
local rewardLabels: { TextLabel } = {}
local statusLabels: { TextLabel } = {}

for i = 1, 7 do
	local box = Instance.new("Frame")
	box.Name = "Day" .. tostring(i)
	box.Size = UDim2.new(0, 72, 0, 120)
	box.BackgroundColor3 = COLOR.BG_PANEL
	box.BorderSizePixel = 0
	box.ZIndex = 4
	box.LayoutOrder = i
	box.Parent = DaysContainer
	applyCorner(box, 8)
	applyStroke(box, COLOR.STROKE_GREEN, 1)

	-- Day header
	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.AnchorPoint = Vector2.new(0.5, 0)
	dayLabel.Position = UDim2.new(0.5, 0, 0, 8)
	dayLabel.Size = UDim2.new(1, -8, 0, 16)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "DAY " .. tostring(i)
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.TextSize = 11
	dayLabel.TextColor3 = COLOR.GRAY
	dayLabel.ZIndex = 5
	dayLabel.Parent = box

	-- Reward amount
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	rewardLabel.Position = UDim2.new(0.5, 0, 0.45, 0)
	rewardLabel.Size = UDim2.new(1, -8, 0, 24)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = FormatNumber.money(REWARDS[i])
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 14
	rewardLabel.TextColor3 = COLOR.AMBER
	rewardLabel.ZIndex = 5
	rewardLabel.Parent = box

	-- Status (checkmark / locked / current)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.new(0.5, 0, 1, -8)
	statusLabel.Size = UDim2.new(1, -8, 0, 20)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "LOCKED"
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 10
	statusLabel.TextColor3 = COLOR.GRAY_DARK
	statusLabel.ZIndex = 5
	statusLabel.Parent = box

	dayBoxes[i] = box
	dayLabels[i] = dayLabel
	rewardLabels[i] = rewardLabel
	statusLabels[i] = statusLabel
end

-- ── Claim button ────────────────────────────────────────────────────────────

local ClaimBtn = Instance.new("TextButton")
ClaimBtn.Name = "ClaimBtn"
ClaimBtn.AnchorPoint = Vector2.new(0.5, 1)
ClaimBtn.Position = UDim2.new(0.5, 0, 1, -16)
ClaimBtn.Size = UDim2.new(0, 200, 0, 44)
ClaimBtn.BackgroundColor3 = COLOR.GREEN
ClaimBtn.Text = "CLAIM"
ClaimBtn.Font = Enum.Font.GothamBold
ClaimBtn.TextSize = 20
ClaimBtn.TextColor3 = COLOR.WHITE
ClaimBtn.BorderSizePixel = 0
ClaimBtn.ZIndex = 4
ClaimBtn.Visible = false
ClaimBtn.Parent = Panel
applyCorner(ClaimBtn, 8)
applyStroke(ClaimBtn, COLOR.STROKE_GREEN, 1)

-- ── State ───────────────────────────────────────────────────────────────────

local isOpen = false
local canClaimNow = false

-- ── UI functions ────────────────────────────────────────────────────────────

local function hide()
	if not isOpen then
		return
	end
	isOpen = false

	local tween = TweenService:Create(Panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 620, 0, 0),
	})
	tween:Play()
	tween.Completed:Once(function()
		Panel.Visible = false
		Backdrop.Visible = false
		Panel.Size = UDim2.new(0, 620, 0, 280)
	end)
end

local function show(streakDay: number, _rewardAmount: number, canClaim: boolean)
	-- Don't show the panel if there's nothing to claim
	if not canClaim then
		return
	end
	canClaimNow = canClaim

	-- Update day boxes
	for i = 1, 7 do
		local box = dayBoxes[i]
		local statusLbl = statusLabels[i]
		local dayLbl = dayLabels[i]

		-- Find the UIStroke on the box to update its color
		local stroke = box:FindFirstChildOfClass("UIStroke")

		if canClaim and i == streakDay then
			-- Current day (claimable)
			box.BackgroundColor3 = COLOR.GREEN_DIM
			dayLbl.TextColor3 = COLOR.WHITE
			statusLbl.Text = "TODAY"
			statusLbl.TextColor3 = COLOR.GREEN_LIGHT
			if stroke then
				stroke.Color = COLOR.GREEN_LIGHT
				stroke.Thickness = 2
			end
		elseif i < streakDay or (not canClaim and i <= streakDay) then
			-- Past days (claimed)
			box.BackgroundColor3 = COLOR.BG_PANEL
			dayLbl.TextColor3 = COLOR.GRAY
			statusLbl.Text = "CLAIMED"
			statusLbl.TextColor3 = COLOR.GREEN
			if stroke then
				stroke.Color = COLOR.GREEN_DIM
				stroke.Thickness = 1
			end
		else
			-- Future days (locked)
			box.BackgroundColor3 = COLOR.BG_PANEL
			dayLbl.TextColor3 = COLOR.GRAY_DARK
			statusLbl.Text = "LOCKED"
			statusLbl.TextColor3 = COLOR.GRAY_DARK
			if stroke then
				stroke.Color = COLOR.STROKE_GREEN
				stroke.Thickness = 1
			end
		end
	end

	-- Show / hide claim button
	ClaimBtn.Visible = canClaim
	if canClaim then
		ClaimBtn.Text = "CLAIM " .. FormatNumber.money(REWARDS[streakDay] or 0)
	end

	-- Animate in
	Panel.Size = UDim2.new(0, 620, 0, 0)
	Panel.Visible = true
	Backdrop.Visible = true
	isOpen = true

	TweenService:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 620, 0, 280),
	}):Play()
end

-- ── Connections ─────────────────────────────────────────────────────────────

CloseBtn.MouseButton1Click:Connect(hide)
Backdrop.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		hide()
	end
end)

ClaimBtn.MouseButton1Click:Connect(function()
	if not canClaimNow then
		return
	end
	canClaimNow = false
	ClaimBtn.Text = "CLAIMING..."
	ClaimBtn.BackgroundColor3 = COLOR.GRAY_DARK
	Remotes.ClaimDailyReward:FireServer()
end)

-- Server tells us to show the calendar.
Remotes.ShowDailyReward.OnClientEvent:Connect(function(streakDay: number, rewardAmount: number, canClaim: boolean)
	show(streakDay, rewardAmount, canClaim)
end)

-- Server confirms the claim.
Remotes.DailyRewardClaimed.OnClientEvent:Connect(function(amount: number)
	ClaimBtn.Text = "CLAIMED " .. FormatNumber.money(amount) .. "!"
	ClaimBtn.BackgroundColor3 = COLOR.GREEN_LIGHT

	-- Auto-close after a moment.
	task.delay(1.5, function()
		hide()
	end)
end)
