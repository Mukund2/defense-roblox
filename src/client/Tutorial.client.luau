--!strict
-- Tutorial.client.luau
-- Quick 2-step onboarding toast. Non-intrusive, auto-dismisses.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

if LocalPlayer:GetAttribute("TutorialComplete") then
	return
end

local COLOR = {
	BG = Color3.fromRGB(20, 25, 35),
	GREEN = Color3.fromRGB(74, 124, 89),
	AMBER = Color3.fromRGB(200, 155, 60),
	WHITE = Color3.fromRGB(240, 240, 240),
	GRAY = Color3.fromRGB(160, 170, 180),
}

local steps = {
	{
		title = "WELCOME, COMMANDER",
		text = "Walk to the glowing green pad to build structures. Each one earns income and strengthens your base.",
	},
	{
		title = "ATTACK & DEFEND",
		text = "Press F to launch strikes on enemy bases. Press B to open the shop. Good luck!",
	},
}

-- ── UI ───────────────────────────────────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Tutorial"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 50
ScreenGui.Parent = PlayerGui

-- Toast card (bottom-center, no overlay)
local Card = Instance.new("Frame")
Card.AnchorPoint = Vector2.new(0.5, 1)
Card.Position = UDim2.new(0.5, 0, 1, 100) -- starts off-screen
Card.Size = UDim2.new(0, 420, 0, 90)
Card.BackgroundColor3 = COLOR.BG
Card.BackgroundTransparency = 0.08
Card.BorderSizePixel = 0
Card.ZIndex = 50
Card.Parent = ScreenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = Card

local stroke = Instance.new("UIStroke")
stroke.Color = COLOR.GREEN
stroke.Thickness = 1.5
stroke.Parent = Card

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.Parent = Card

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 20)
Title.BackgroundTransparency = 1
Title.Text = ""
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = COLOR.AMBER
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 51
Title.Parent = Card

local Body = Instance.new("TextLabel")
Body.Position = UDim2.new(0, 0, 0, 24)
Body.Size = UDim2.new(1, 0, 0, 36)
Body.BackgroundTransparency = 1
Body.Text = ""
Body.Font = Enum.Font.GothamMedium
Body.TextSize = 13
Body.TextColor3 = COLOR.WHITE
Body.TextWrapped = true
Body.TextXAlignment = Enum.TextXAlignment.Left
Body.ZIndex = 51
Body.Parent = Card

local StepDots = Instance.new("TextLabel")
StepDots.AnchorPoint = Vector2.new(1, 1)
StepDots.Position = UDim2.new(1, 0, 1, 0)
StepDots.Size = UDim2.new(0, 40, 0, 16)
StepDots.BackgroundTransparency = 1
StepDots.Text = ""
StepDots.Font = Enum.Font.GothamMedium
StepDots.TextSize = 10
StepDots.TextColor3 = COLOR.GRAY
StepDots.TextXAlignment = Enum.TextXAlignment.Right
StepDots.ZIndex = 51
StepDots.Parent = Card

-- ── Flow ─────────────────────────────────────────────────────────────────────

local slideIn = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local slideOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function showStep(index: number)
	local step = steps[index]
	Title.Text = step.title
	Body.Text = step.text
	StepDots.Text = tostring(index) .. "/" .. tostring(#steps)

	TweenService:Create(Card, slideIn, { Position = UDim2.new(0.5, 0, 1, -20) }):Play()
end

local function hideCard(): ()
	local tween = TweenService:Create(Card, slideOut, { Position = UDim2.new(0.5, 0, 1, 100) })
	tween:Play()
	tween.Completed:Wait()
end

local function closeTutorial()
	LocalPlayer:SetAttribute("TutorialComplete", true)
	hideCard()
	ScreenGui:Destroy()
end

-- Auto-play both steps then dismiss
task.wait(2) -- initial delay
showStep(1)
task.wait(5) -- show step 1 for 5s
hideCard()
task.wait(0.5)
showStep(2)
task.wait(5) -- show step 2 for 5s
closeTutorial()
