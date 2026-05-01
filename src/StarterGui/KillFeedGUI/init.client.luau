--!strict

--[[
	KillFeedGUI
	-----------
	Displays "PlayerA eliminated PlayerB" messages in the top-right corner.
	Military color scheme — amber text on dark translucent background.
	Max 5 visible, each fades after 5 seconds.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Constants ────────────────────────────────────────────────────────────────

local MAX_ENTRIES = 5
local DISPLAY_TIME = 5
local FADE_TIME = 0.5
local ENTRY_HEIGHT = 28
local ENTRY_PADDING = 4

local COLOR_BG = Color3.fromRGB(20, 20, 20)
local COLOR_AMBER = Color3.fromRGB(255, 191, 0)
local COLOR_WHITE = Color3.fromRGB(230, 230, 230)

-- ── GUI construction ─────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KillFeedGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 90
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "KillFeedContainer"
container.Size = UDim2.new(0, 350, 0, (ENTRY_HEIGHT + ENTRY_PADDING) * MAX_ENTRIES)
container.Position = UDim2.new(1, -360, 0, 10)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- ── State ────────────────────────────────────────────────────────────────────

local entries: { Frame } = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function repositionEntries()
	for i, entry in entries do
		local yPos = (i - 1) * (ENTRY_HEIGHT + ENTRY_PADDING)
		entry.Position = UDim2.new(0, 0, 0, yPos)
	end
end

local function addKillEntry(killerName: string, victimName: string)
	-- Create entry frame
	local entry = Instance.new("Frame")
	entry.Name = "KillEntry"
	entry.Size = UDim2.new(1, 0, 0, ENTRY_HEIGHT)
	entry.BackgroundColor3 = COLOR_BG
	entry.BackgroundTransparency = 0.3
	entry.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = entry

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = entry

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.RichText = true

	-- Format: killerName in amber, "eliminated" in white, victimName in amber
	local killerColor = string.format(
		'<font color="rgb(%d,%d,%d)">%s</font>',
		math.round(COLOR_AMBER.R * 255),
		math.round(COLOR_AMBER.G * 255),
		math.round(COLOR_AMBER.B * 255),
		killerName
	)
	local victimColor = string.format(
		'<font color="rgb(%d,%d,%d)">%s</font>',
		math.round(COLOR_AMBER.R * 255),
		math.round(COLOR_AMBER.G * 255),
		math.round(COLOR_AMBER.B * 255),
		victimName
	)
	label.Text = killerColor .. " eliminated " .. victimColor
	label.TextColor3 = COLOR_WHITE
	label.Parent = entry

	-- Insert at top
	table.insert(entries, 1, entry)

	-- Remove oldest if over max
	if #entries > MAX_ENTRIES then
		local old = entries[MAX_ENTRIES + 1]
		table.remove(entries, MAX_ENTRIES + 1)
		old:Destroy()
	end

	repositionEntries()
	entry.Parent = container

	-- Fade out after DISPLAY_TIME
	task.delay(DISPLAY_TIME, function()
		local tweenInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(entry, tweenInfo, { BackgroundTransparency = 1 })
		tween:Play()

		-- Also fade the text
		local textLabel = entry:FindFirstChild("Text") :: TextLabel?
		if textLabel then
			TweenService:Create(textLabel, tweenInfo, { TextTransparency = 1 }):Play()
		end

		tween.Completed:Wait()

		-- Remove from entries table
		local idx = table.find(entries, entry)
		if idx then
			table.remove(entries, idx)
		end
		entry:Destroy()
		repositionEntries()
	end)
end

-- ── Listen for kill feed events ──────────────────────────────────────────────

Remotes.KillFeed.OnClientEvent:Connect(function(killerName: unknown, victimName: unknown)
	if type(killerName) ~= "string" or type(victimName) ~= "string" then
		return
	end
	addKillEntry(killerName :: string, victimName :: string)
end)
