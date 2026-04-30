--!strict

--[[
	QuestGUI/init.client.luau
	-------------------------
	Displays 3 daily quests with progress bars.  Toggle with Q key or
	the on-screen button.  Completed quests show a CLAIM button.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
}

local SLIDE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BAR_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
ScreenGui.Name = "QuestGUI"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 15
ScreenGui.Parent = PlayerGui

-- ── Toggle button (bottom-right, above SHOP) ────────────────────────────────

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "QuestToggle"
ToggleBtn.AnchorPoint = Vector2.new(1, 1)
ToggleBtn.Position = UDim2.new(1, -16, 1, -64)
ToggleBtn.Size = UDim2.new(0, 80, 0, 40)
ToggleBtn.BackgroundColor3 = COLOR.AMBER
ToggleBtn.Text = "QUESTS"
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 14
ToggleBtn.TextColor3 = COLOR.WHITE
ToggleBtn.BorderSizePixel = 0
ToggleBtn.ZIndex = 2
ToggleBtn.Parent = ScreenGui
applyCorner(ToggleBtn, 8)
applyStroke(ToggleBtn, COLOR.STROKE_GREEN, 1)

-- ── Quest panel (slides in from right) ──────────────────────────────────────

local PANEL_WIDTH = 300
local PANEL_HEIGHT = 340

local Panel = Instance.new("Frame")
Panel.Name = "QuestPanel"
Panel.AnchorPoint = Vector2.new(1, 0.5)
Panel.Position = UDim2.new(1, PANEL_WIDTH + 20, 0.5, 0) -- start off-screen
Panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
Panel.BackgroundColor3 = COLOR.BG_DARK
Panel.BackgroundTransparency = 0.05
Panel.BorderSizePixel = 0
Panel.ZIndex = 10
Panel.Visible = false
Panel.Parent = ScreenGui
applyCorner(Panel, 12)
applyStroke(Panel, COLOR.GREEN, 2)

-- Title
local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.AnchorPoint = Vector2.new(0.5, 0)
Title.Position = UDim2.new(0.5, 0, 0, 12)
Title.Size = UDim2.new(1, -24, 0, 24)
Title.BackgroundTransparency = 1
Title.Text = "DAILY QUESTS"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextColor3 = COLOR.AMBER
Title.ZIndex = 11
Title.Parent = Panel

-- Close button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.AnchorPoint = Vector2.new(1, 0)
CloseBtn.Position = UDim2.new(1, -8, 0, 8)
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.BackgroundColor3 = COLOR.BG_PANEL
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.TextColor3 = COLOR.GRAY
CloseBtn.BorderSizePixel = 0
CloseBtn.ZIndex = 12
CloseBtn.Parent = Panel
applyCorner(CloseBtn, 6)

-- ── Quest rows container ────────────────────────────────────────────────────

local QuestsContainer = Instance.new("Frame")
QuestsContainer.Name = "QuestsContainer"
QuestsContainer.AnchorPoint = Vector2.new(0.5, 0)
QuestsContainer.Position = UDim2.new(0.5, 0, 0, 44)
QuestsContainer.Size = UDim2.new(1, -24, 1, -56)
QuestsContainer.BackgroundTransparency = 1
QuestsContainer.ZIndex = 11
QuestsContainer.Parent = Panel

local QuestsLayout = Instance.new("UIListLayout")
QuestsLayout.FillDirection = Enum.FillDirection.Vertical
QuestsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
QuestsLayout.Padding = UDim.new(0, 8)
QuestsLayout.Parent = QuestsContainer

-- ── Quest row template builder ──────────────────────────────────────────────

type QuestRowUI = {
	frame: Frame,
	descLabel: TextLabel,
	progressLabel: TextLabel,
	rewardLabel: TextLabel,
	barFill: Frame,
	claimBtn: TextButton,
}

local questRows: { QuestRowUI } = {}

local function createQuestRow(index: number): QuestRowUI
	local ROW_HEIGHT = 88

	local frame = Instance.new("Frame")
	frame.Name = "Quest" .. tostring(index)
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.BackgroundColor3 = COLOR.BG_PANEL
	frame.BorderSizePixel = 0
	frame.ZIndex = 12
	frame.LayoutOrder = index
	frame.Parent = QuestsContainer
	applyCorner(frame, 8)
	applyStroke(frame, COLOR.STROKE_GREEN, 1)

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Desc"
	descLabel.AnchorPoint = Vector2.new(0, 0)
	descLabel.Position = UDim2.new(0, 10, 0, 6)
	descLabel.Size = UDim2.new(1, -20, 0, 18)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = "Loading..."
	descLabel.Font = Enum.Font.GothamMedium
	descLabel.TextSize = 13
	descLabel.TextColor3 = COLOR.WHITE
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.ZIndex = 13
	descLabel.Parent = frame

	-- Progress text (e.g. "2,000 / 5,000")
	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "Progress"
	progressLabel.AnchorPoint = Vector2.new(0, 0)
	progressLabel.Position = UDim2.new(0, 10, 0, 26)
	progressLabel.Size = UDim2.new(0.6, -10, 0, 14)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = "0 / 0"
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextSize = 11
	progressLabel.TextColor3 = COLOR.GRAY
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.ZIndex = 13
	progressLabel.Parent = frame

	-- Reward label
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "Reward"
	rewardLabel.AnchorPoint = Vector2.new(1, 0)
	rewardLabel.Position = UDim2.new(1, -10, 0, 26)
	rewardLabel.Size = UDim2.new(0.4, -10, 0, 14)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = "+$0"
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 12
	rewardLabel.TextColor3 = COLOR.AMBER
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
	rewardLabel.ZIndex = 13
	rewardLabel.Parent = frame

	-- Progress bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0, 44)
	barBg.Size = UDim2.new(1, -20, 0, 10)
	barBg.BackgroundColor3 = COLOR.BG_DARK
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 13
	barBg.Parent = frame
	applyCorner(barBg, 4)

	-- Progress bar fill
	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = COLOR.GREEN
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 14
	barFill.Parent = barBg
	applyCorner(barFill, 4)

	-- Claim button (hidden until quest complete)
	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimBtn"
	claimBtn.AnchorPoint = Vector2.new(0.5, 1)
	claimBtn.Position = UDim2.new(0.5, 0, 1, -6)
	claimBtn.Size = UDim2.new(1, -20, 0, 24)
	claimBtn.BackgroundColor3 = COLOR.GREEN
	claimBtn.Text = "CLAIM REWARD"
	claimBtn.Font = Enum.Font.GothamBold
	claimBtn.TextSize = 12
	claimBtn.TextColor3 = COLOR.WHITE
	claimBtn.BorderSizePixel = 0
	claimBtn.ZIndex = 14
	claimBtn.Visible = false
	claimBtn.Parent = frame
	applyCorner(claimBtn, 6)

	claimBtn.MouseButton1Click:Connect(function()
		claimBtn.Text = "CLAIMING..."
		claimBtn.BackgroundColor3 = COLOR.GRAY_DARK
		Remotes.ClaimQuestReward:FireServer(index)
	end)

	return {
		frame = frame,
		descLabel = descLabel,
		progressLabel = progressLabel,
		rewardLabel = rewardLabel,
		barFill = barFill,
		claimBtn = claimBtn,
	}
end

-- Create 3 quest rows
for i = 1, 3 do
	questRows[i] = createQuestRow(i)
end

-- ── Update quests from server data ──────────────────────────────────────────

local function updateQuestRow(index: number, questData: any)
	local row = questRows[index]
	if not row then
		return
	end

	row.descLabel.Text = questData.description or ""
	row.rewardLabel.Text = "+" .. FormatNumber.money(questData.reward or 0)

	local progress: number = questData.progress or 0
	local target: number = questData.target or 1
	local claimed: boolean = questData.claimed or false

	-- Format progress text based on quest type
	if questData.questType == "earn" then
		row.progressLabel.Text = FormatNumber.money(progress) .. " / " .. FormatNumber.money(target)
	else
		row.progressLabel.Text = tostring(math.floor(progress)) .. " / " .. tostring(math.floor(target))
	end

	-- Progress bar
	local ratio = if target > 0 then math.clamp(progress / target, 0, 1) else 0
	TweenService:Create(row.barFill, BAR_TWEEN, {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()

	-- Bar color
	if claimed then
		row.barFill.BackgroundColor3 = COLOR.GRAY_DARK
	elseif ratio >= 1 then
		row.barFill.BackgroundColor3 = COLOR.GREEN_LIGHT
	else
		row.barFill.BackgroundColor3 = COLOR.GREEN
	end

	-- Claim button visibility
	if claimed then
		row.claimBtn.Visible = true
		row.claimBtn.Text = "CLAIMED"
		row.claimBtn.BackgroundColor3 = COLOR.GRAY_DARK
		row.claimBtn.Active = false
	elseif progress >= target then
		row.claimBtn.Visible = true
		row.claimBtn.Text = "CLAIM REWARD"
		row.claimBtn.BackgroundColor3 = COLOR.GREEN
		row.claimBtn.Active = true
	else
		row.claimBtn.Visible = false
	end
end

-- ── Toggle logic ────────────────────────────────────────────────────────────

local isOpen = false

local function openPanel()
	if isOpen then
		return
	end
	isOpen = true
	Panel.Visible = true
	TweenService:Create(Panel, SLIDE_IN, {
		Position = UDim2.new(1, -16, 0.5, 0),
	}):Play()
end

local function closePanel()
	if not isOpen then
		return
	end
	isOpen = false
	local tween = TweenService:Create(Panel, SLIDE_OUT, {
		Position = UDim2.new(1, PANEL_WIDTH + 20, 0.5, 0),
	})
	tween:Play()
	tween.Completed:Once(function()
		if not isOpen then
			Panel.Visible = false
		end
	end)
end

local function togglePanel()
	if isOpen then
		closePanel()
	else
		openPanel()
	end
end

-- ── Connections ─────────────────────────────────────────────────────────────

ToggleBtn.MouseButton1Click:Connect(togglePanel)
CloseBtn.MouseButton1Click:Connect(closePanel)

-- Q key toggle
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		togglePanel()
	end
end)

-- Server sends quest data
Remotes.UpdateQuests.OnClientEvent:Connect(function(quests: { any })
	for i, questData in quests do
		updateQuestRow(i, questData)
	end
end)

-- Server confirms quest completion
Remotes.QuestCompleted.OnClientEvent:Connect(function(questIndex: number, reward: number)
	local row = questRows[questIndex]
	if row then
		row.claimBtn.Text = "CLAIMED " .. FormatNumber.money(reward) .. "!"
		row.claimBtn.BackgroundColor3 = COLOR.GREEN_LIGHT
		row.claimBtn.Active = false

		task.delay(1.5, function()
			row.claimBtn.Text = "CLAIMED"
			row.claimBtn.BackgroundColor3 = COLOR.GRAY_DARK
		end)
	end
end)
