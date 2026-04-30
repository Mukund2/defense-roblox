--!strict
-- Tutorial.client.luau
-- Simple onboarding flow for first-time players. Shows 4 steps with
-- arrow indicators and dismissable prompts.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Skip tutorial if player has seen it before (tracked via attribute)
if LocalPlayer:GetAttribute("TutorialComplete") then
	return
end

-- ── Design Tokens ────────────────────────────────────────────────────────────
local COLOR = {
	BG = Color3.fromRGB(14, 18, 26),
	GREEN = Color3.fromRGB(74, 124, 89),
	AMBER = Color3.fromRGB(200, 155, 60),
	WHITE = Color3.fromRGB(240, 240, 240),
	GRAY = Color3.fromRGB(160, 170, 180),
}

-- ── Tutorial Steps ───────────────────────────────────────────────────────────
local steps = {
	{
		title = "WELCOME, COMMANDER",
		text = "You've been assigned to build a military base from the ground up. Your Command Center is already operational.",
		delay = 3,
	},
	{
		title = "BUILD YOUR BASE",
		text = "Walk to the glowing green pad to construct your next building. Each structure earns income and strengthens your defenses.",
		delay = 0,
	},
	{
		title = "EARN & UPGRADE",
		text = "You earn $5/sec from your Command Center. Unlock all 15 tiers to build the ultimate military fortress!",
		delay = 0,
	},
	{
		title = "ATTACK & DEFEND",
		text = "Press F to open the Attack Panel. Launch strikes against enemy bases and defend yours with shields and SAM sites!",
		delay = 0,
	},
}

-- ── UI Construction ──────────────────────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Tutorial"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 50
ScreenGui.Parent = PlayerGui

-- Semi-transparent overlay
local Overlay = Instance.new("Frame")
Overlay.Size = UDim2.new(1, 0, 1, 0)
Overlay.BackgroundColor3 = Color3.new(0, 0, 0)
Overlay.BackgroundTransparency = 0.6
Overlay.BorderSizePixel = 0
Overlay.ZIndex = 1
Overlay.Parent = ScreenGui

-- Tutorial card
local Card = Instance.new("Frame")
Card.AnchorPoint = Vector2.new(0.5, 0.5)
Card.Position = UDim2.new(0.5, 0, 0.5, 0)
Card.Size = UDim2.new(0, 500, 0, 200)
Card.BackgroundColor3 = COLOR.BG
Card.BackgroundTransparency = 0.05
Card.BorderSizePixel = 0
Card.ZIndex = 10
Card.Parent = ScreenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = Card

local stroke = Instance.new("UIStroke")
stroke.Color = COLOR.GREEN
stroke.Thickness = 2
stroke.Parent = Card

-- Step counter
local StepLabel = Instance.new("TextLabel")
StepLabel.Position = UDim2.new(0, 20, 0, 12)
StepLabel.Size = UDim2.new(0, 80, 0, 20)
StepLabel.BackgroundTransparency = 1
StepLabel.Text = "1 / 4"
StepLabel.Font = Enum.Font.GothamMedium
StepLabel.TextSize = 11
StepLabel.TextColor3 = COLOR.GRAY
StepLabel.TextXAlignment = Enum.TextXAlignment.Left
StepLabel.ZIndex = 11
StepLabel.Parent = Card

-- Title
local Title = Instance.new("TextLabel")
Title.AnchorPoint = Vector2.new(0.5, 0)
Title.Position = UDim2.new(0.5, 0, 0, 40)
Title.Size = UDim2.new(1, -40, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = ""
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.TextColor3 = COLOR.AMBER
Title.ZIndex = 11
Title.Parent = Card

-- Body text
local Body = Instance.new("TextLabel")
Body.AnchorPoint = Vector2.new(0.5, 0)
Body.Position = UDim2.new(0.5, 0, 0, 80)
Body.Size = UDim2.new(1, -40, 0, 60)
Body.BackgroundTransparency = 1
Body.Text = ""
Body.Font = Enum.Font.GothamMedium
Body.TextSize = 14
Body.TextColor3 = COLOR.WHITE
Body.TextWrapped = true
Body.ZIndex = 11
Body.Parent = Card

-- Next button
local NextBtn = Instance.new("TextButton")
NextBtn.AnchorPoint = Vector2.new(0.5, 1)
NextBtn.Position = UDim2.new(0.5, 0, 1, -16)
NextBtn.Size = UDim2.new(0, 140, 0, 36)
NextBtn.BackgroundColor3 = COLOR.GREEN
NextBtn.Text = "CONTINUE"
NextBtn.Font = Enum.Font.GothamBold
NextBtn.TextSize = 14
NextBtn.TextColor3 = COLOR.WHITE
NextBtn.BorderSizePixel = 0
NextBtn.ZIndex = 11
NextBtn.Parent = Card

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = NextBtn

-- Skip button
local SkipBtn = Instance.new("TextButton")
SkipBtn.AnchorPoint = Vector2.new(1, 0)
SkipBtn.Position = UDim2.new(1, -12, 0, 12)
SkipBtn.Size = UDim2.new(0, 50, 0, 20)
SkipBtn.BackgroundTransparency = 1
SkipBtn.Text = "SKIP"
SkipBtn.Font = Enum.Font.GothamMedium
SkipBtn.TextSize = 11
SkipBtn.TextColor3 = COLOR.GRAY
SkipBtn.ZIndex = 11
SkipBtn.Parent = Card

-- ── Tutorial Flow ────────────────────────────────────────────────────────────

local currentStep = 0
local finished = false

local function showStep(index: number)
	if index < 1 or index > #steps then
		return
	end
	currentStep = index
	local step = steps[index]
	StepLabel.Text = tostring(index) .. " / " .. tostring(#steps)
	Title.Text = step.title
	Body.Text = step.text
	NextBtn.Text = if index == #steps then "GET STARTED" else "CONTINUE"

	-- Animate card in
	Card.Position = UDim2.new(0.5, 0, 0.6, 0)
	Card.BackgroundTransparency = 0.3
	local tweenIn = TweenService:Create(Card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundTransparency = 0.05,
	})
	tweenIn:Play()
end

local function closeTutorial()
	if finished then
		return
	end
	finished = true
	LocalPlayer:SetAttribute("TutorialComplete", true)

	local tweenOut = TweenService:Create(Overlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
	local cardOut = TweenService:Create(Card, TweenInfo.new(0.3), {
		Position = UDim2.new(0.5, 0, 0.4, 0),
		BackgroundTransparency = 1,
	})
	tweenOut:Play()
	cardOut:Play()
	tweenOut.Completed:Connect(function()
		ScreenGui:Destroy()
	end)
end

NextBtn.MouseButton1Click:Connect(function()
	if currentStep >= #steps then
		closeTutorial()
	else
		showStep(currentStep + 1)
	end
end)

SkipBtn.MouseButton1Click:Connect(function()
	closeTutorial()
end)

-- Start after initial delay
task.wait(steps[1].delay)
showStep(1)
