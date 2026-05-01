--!strict
-- CombatHUD/init.client.luau
-- Military-themed combat interface: base HP bar, shield bar, attack panel,
-- incoming attack warnings, and destruction overlay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes", 30) :: ModuleScript)
local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig", 30) :: ModuleScript)
local FormatNumber = require(ReplicatedStorage:WaitForChild("FormatNumber", 30) :: ModuleScript)
local TycoonConfig = require(ReplicatedStorage:WaitForChild("TycoonConfig", 30) :: ModuleScript)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ── Design Tokens ────────────────────────────────────────────────────────────
local COLOR = {
	BG_DARK = Color3.fromRGB(20, 25, 35),
	BG_PANEL = Color3.fromRGB(14, 18, 26),
	GREEN = Color3.fromRGB(74, 124, 89),
	GREEN_LIGHT = Color3.fromRGB(100, 180, 120),
	RED = Color3.fromRGB(200, 60, 60),
	RED_DIM = Color3.fromRGB(120, 40, 40),
	AMBER = Color3.fromRGB(200, 155, 60),
	WHITE = Color3.fromRGB(240, 240, 240),
	GRAY = Color3.fromRGB(160, 170, 180),
	BLUE_SHIELD = Color3.fromRGB(80, 140, 220),
	STROKE_GREEN = Color3.fromRGB(60, 100, 72),
	STROKE_RED = Color3.fromRGB(120, 50, 50),
}

-- ── Utility ──────────────────────────────────────────────────────────────────

local function applyCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function applyStroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

-- ── Root ScreenGui ───────────────────────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CombatHUD"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 5
ScreenGui.Parent = PlayerGui

-- ═════════════════════════════════════════════════════════════════════════════
-- HP BAR (top-center, below money bar)
-- ═════════════════════════════════════════════════════════════════════════════

local HPFrame = Instance.new("Frame")
HPFrame.Name = "HPFrame"
HPFrame.AnchorPoint = Vector2.new(0.5, 0)
HPFrame.Position = UDim2.new(0.5, 0, 0, 82)
HPFrame.Size = UDim2.new(0, 280, 0, 32)
HPFrame.BackgroundColor3 = COLOR.BG_DARK
HPFrame.BackgroundTransparency = 0.15
HPFrame.BorderSizePixel = 0
HPFrame.Visible = false
HPFrame.Parent = ScreenGui
applyCorner(HPFrame, 6)
applyStroke(HPFrame, COLOR.STROKE_RED, 1)

-- HP bar background
local HPBarBG = Instance.new("Frame")
HPBarBG.Name = "HPBarBG"
HPBarBG.Position = UDim2.new(0, 8, 0.5, -5)
HPBarBG.Size = UDim2.new(1, -16, 0, 10)
HPBarBG.BackgroundColor3 = COLOR.RED_DIM
HPBarBG.BorderSizePixel = 0
HPBarBG.Parent = HPFrame
applyCorner(HPBarBG, 3)

-- HP bar fill
local HPBarFill = Instance.new("Frame")
HPBarFill.Name = "HPBarFill"
HPBarFill.Size = UDim2.new(1, 0, 1, 0)
HPBarFill.BackgroundColor3 = COLOR.RED
HPBarFill.BorderSizePixel = 0
HPBarFill.Parent = HPBarBG
applyCorner(HPBarFill, 3)

-- Shield bar (overlaid, blue)
local ShieldBarFill = Instance.new("Frame")
ShieldBarFill.Name = "ShieldBarFill"
ShieldBarFill.Size = UDim2.new(0, 0, 1, 0)
ShieldBarFill.BackgroundColor3 = COLOR.BLUE_SHIELD
ShieldBarFill.BackgroundTransparency = 0.3
ShieldBarFill.BorderSizePixel = 0
ShieldBarFill.ZIndex = 2
ShieldBarFill.Parent = HPBarBG
applyCorner(ShieldBarFill, 3)

-- HP text
local HPLabel = Instance.new("TextLabel")
HPLabel.Name = "HPLabel"
HPLabel.Size = UDim2.new(1, 0, 1, 0)
HPLabel.BackgroundTransparency = 1
HPLabel.Text = "BASE HP: 100 / 100"
HPLabel.Font = Enum.Font.GothamBold
HPLabel.TextSize = 11
HPLabel.TextColor3 = COLOR.WHITE
HPLabel.ZIndex = 3
HPLabel.Parent = HPFrame

-- ═════════════════════════════════════════════════════════════════════════════
-- ATTACK PANEL (toggle with F key)
-- ═════════════════════════════════════════════════════════════════════════════

local AttackPanel = Instance.new("Frame")
AttackPanel.Name = "AttackPanel"
AttackPanel.AnchorPoint = Vector2.new(1, 0.5)
AttackPanel.Position = UDim2.new(1, -16, 0.5, 0)
AttackPanel.Size = UDim2.new(0, 260, 0, 360)
AttackPanel.BackgroundColor3 = COLOR.BG_DARK
AttackPanel.BackgroundTransparency = 0.08
AttackPanel.BorderSizePixel = 0
AttackPanel.Visible = false
AttackPanel.Parent = ScreenGui
applyCorner(AttackPanel, 8)
applyStroke(AttackPanel, COLOR.RED, 2)

-- Attack panel header
local AttackHeader = Instance.new("TextLabel")
AttackHeader.Name = "Header"
AttackHeader.Size = UDim2.new(1, 0, 0, 36)
AttackHeader.BackgroundTransparency = 1
AttackHeader.Text = "ATTACK PANEL [F]"
AttackHeader.Font = Enum.Font.GothamBold
AttackHeader.TextSize = 14
AttackHeader.TextColor3 = COLOR.RED
AttackHeader.Parent = AttackPanel

-- Attack panel layout
local AttackLayout = Instance.new("UIListLayout")
AttackLayout.FillDirection = Enum.FillDirection.Vertical
AttackLayout.Padding = UDim.new(0, 4)
AttackLayout.Parent = AttackPanel

local AttackPadding = Instance.new("UIPadding")
AttackPadding.PaddingLeft = UDim.new(0, 10)
AttackPadding.PaddingRight = UDim.new(0, 10)
AttackPadding.PaddingTop = UDim.new(0, 6)
AttackPadding.Parent = AttackPanel

-- Track local state
local currentHP = 100
local maxHP = 100
local currentShield = 0
local maxShield = 0
local unlockedItems: { string } = { "CommandCenter" }
local attackCooldowns: { [string]: number } = {}
local panelOpen = false

-- Target pad selector state
local selectedTargetPad: number? = nil

-- Create attack buttons for each attack type
local attackButtons: { [string]: { frame: Frame, button: TextButton, cooldownLabel: TextLabel } } = {}

local attackOrder = { "GroundAssault", "AirStrike", "NavalBombardment", "MissileStrike" }

for _, attackType in attackOrder do
	local spec = CombatConfig.Attacks[attackType]
	if not spec then
		continue
	end

	local row = Instance.new("Frame")
	row.Name = "Attack_" .. attackType
	row.Size = UDim2.new(1, 0, 0, 70)
	row.BackgroundColor3 = COLOR.BG_PANEL
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.Parent = AttackPanel
	applyCorner(row, 6)

	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft = UDim.new(0, 8)
	rowPad.PaddingTop = UDim.new(0, 4)
	rowPad.Parent = row

	-- Attack name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -70, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = spec.name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = COLOR.WHITE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	-- Damage + cost
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Position = UDim2.new(0, 0, 0, 18)
	statsLabel.Size = UDim2.new(1, -70, 0, 14)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = string.format("DMG: %d | Cost: %s", spec.damage, FormatNumber.money(spec.cost))
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextSize = 10
	statsLabel.TextColor3 = COLOR.GRAY
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Parent = row

	-- Cooldown label
	local cdLabel = Instance.new("TextLabel")
	cdLabel.Name = "CooldownLabel"
	cdLabel.Position = UDim2.new(0, 0, 0, 32)
	cdLabel.Size = UDim2.new(1, -70, 0, 14)
	cdLabel.BackgroundTransparency = 1
	cdLabel.Text = "Ready"
	cdLabel.Font = Enum.Font.GothamMedium
	cdLabel.TextSize = 10
	cdLabel.TextColor3 = COLOR.GREEN_LIGHT
	cdLabel.TextXAlignment = Enum.TextXAlignment.Left
	cdLabel.Parent = row

	-- Launch button
	local launchBtn = Instance.new("TextButton")
	launchBtn.Name = "LaunchBtn"
	launchBtn.AnchorPoint = Vector2.new(1, 0.5)
	launchBtn.Position = UDim2.new(1, -4, 0.5, 0)
	launchBtn.Size = UDim2.new(0, 58, 0, 30)
	launchBtn.BackgroundColor3 = COLOR.RED
	launchBtn.Text = "FIRE"
	launchBtn.Font = Enum.Font.GothamBold
	launchBtn.TextSize = 12
	launchBtn.TextColor3 = COLOR.WHITE
	launchBtn.BorderSizePixel = 0
	launchBtn.Parent = row
	applyCorner(launchBtn, 4)

	launchBtn.MouseButton1Click:Connect(function()
		-- For now, attack pad 2 (or next occupied pad)
		-- In a full implementation, a target selector would be shown
		local myPad = nil
		local targetPad = nil
		-- Find our pad and a valid target
		for padNum = 1, 4 do
			-- We'll just try attacking the next pad
			if targetPad == nil and padNum ~= selectedTargetPad then
				-- Default: cycle through pads
			end
		end
		-- Simple: attack the first pad that isn't ours
		-- The server will validate
		local padToAttack = selectedTargetPad or 2
		Remotes.LaunchAttack:FireServer(attackType, padToAttack)
	end)

	attackButtons[attackType] = {
		frame = row,
		button = launchBtn,
		cooldownLabel = cdLabel,
	}
end

-- Target selector (simple pad number buttons)
local TargetFrame = Instance.new("Frame")
TargetFrame.Name = "TargetSelector"
TargetFrame.Size = UDim2.new(1, 0, 0, 30)
TargetFrame.BackgroundTransparency = 1
TargetFrame.Parent = AttackPanel

local TargetLabel = Instance.new("TextLabel")
TargetLabel.Size = UDim2.new(0.4, 0, 1, 0)
TargetLabel.BackgroundTransparency = 1
TargetLabel.Text = "TARGET:"
TargetLabel.Font = Enum.Font.GothamBold
TargetLabel.TextSize = 11
TargetLabel.TextColor3 = COLOR.AMBER
TargetLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetLabel.Parent = TargetFrame

for i = 1, 4 do
	local padBtn = Instance.new("TextButton")
	padBtn.Name = "Pad" .. i
	padBtn.Position = UDim2.new(0.35 + (i - 1) * 0.16, 0, 0.1, 0)
	padBtn.Size = UDim2.new(0, 32, 0, 24)
	padBtn.BackgroundColor3 = if i == 2 then COLOR.RED else COLOR.BG_PANEL
	padBtn.Text = tostring(i)
	padBtn.Font = Enum.Font.GothamBold
	padBtn.TextSize = 12
	padBtn.TextColor3 = COLOR.WHITE
	padBtn.BorderSizePixel = 0
	padBtn.Parent = TargetFrame
	applyCorner(padBtn, 4)

	padBtn.MouseButton1Click:Connect(function()
		selectedTargetPad = i
		-- Update button colors
		for j = 1, 4 do
			local btn = TargetFrame:FindFirstChild("Pad" .. j) :: TextButton?
			if btn then
				btn.BackgroundColor3 = if j == i then COLOR.RED else COLOR.BG_PANEL
			end
		end
	end)
end
selectedTargetPad = 2 -- default target

-- ═════════════════════════════════════════════════════════════════════════════
-- WARNING OVERLAY (incoming attack)
-- ═════════════════════════════════════════════════════════════════════════════

local WarningFrame = Instance.new("Frame")
WarningFrame.Name = "WarningFrame"
WarningFrame.AnchorPoint = Vector2.new(0.5, 0)
WarningFrame.Position = UDim2.new(0.5, 0, 0, 120)
WarningFrame.Size = UDim2.new(0, 400, 0, 50)
WarningFrame.BackgroundColor3 = COLOR.RED
WarningFrame.BackgroundTransparency = 0.2
WarningFrame.BorderSizePixel = 0
WarningFrame.Visible = false
WarningFrame.ZIndex = 20
WarningFrame.Parent = ScreenGui
applyCorner(WarningFrame, 6)

local WarningLabel = Instance.new("TextLabel")
WarningLabel.Size = UDim2.new(1, 0, 1, 0)
WarningLabel.BackgroundTransparency = 1
WarningLabel.Text = "INCOMING ATTACK!"
WarningLabel.Font = Enum.Font.GothamBold
WarningLabel.TextSize = 18
WarningLabel.TextColor3 = COLOR.WHITE
WarningLabel.Parent = WarningFrame

-- ═════════════════════════════════════════════════════════════════════════════
-- TOGGLE WITH F KEY
-- ═════════════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		panelOpen = not panelOpen
		AttackPanel.Visible = panelOpen
	end
end)

-- ═════════════════════════════════════════════════════════════════════════════
-- REMOTE LISTENERS
-- ═════════════════════════════════════════════════════════════════════════════

Remotes.BaseDamaged.OnClientEvent:Connect(function(hp: number, mhp: number, damage: number, attackType: string)
	currentHP = hp
	maxHP = mhp
	HPLabel.Text = string.format("BASE HP: %d / %d", hp, mhp)
	local ratio = if mhp > 0 then hp / mhp else 1
	TweenService:Create(HPBarFill, TweenInfo.new(0.3), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()

	-- Color: green → yellow → red based on HP
	if ratio > 0.6 then
		HPBarFill.BackgroundColor3 = COLOR.GREEN
	elseif ratio > 0.3 then
		HPBarFill.BackgroundColor3 = COLOR.AMBER
	else
		HPBarFill.BackgroundColor3 = COLOR.RED
	end

	-- Flash red on damage
	if damage > 0 then
		HPFrame.BackgroundColor3 = COLOR.RED
		task.delay(0.3, function()
			HPFrame.BackgroundColor3 = COLOR.BG_DARK
		end)
	end
end)

Remotes.UpdateShield.OnClientEvent:Connect(function(shield: number, mShield: number)
	currentShield = shield
	maxShield = mShield
	local ratio = if mShield > 0 then shield / mShield else 0
	-- Shield bar overlays HP bar
	TweenService:Create(ShieldBarFill, TweenInfo.new(0.3), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
end)

Remotes.AttackWarning.OnClientEvent:Connect(function(attackType: string, attackerName: string, eta: number)
	WarningFrame.Visible = true
	WarningLabel.Text = string.format("INCOMING %s FROM %s! (%ds)", string.upper(attackType), attackerName, math.ceil(eta))

	-- Flash warning
	task.spawn(function()
		local endTime = os.clock() + eta
		while os.clock() < endTime and WarningFrame.Visible do
			WarningFrame.BackgroundTransparency = 0.1
			task.wait(0.3)
			WarningFrame.BackgroundTransparency = 0.5
			task.wait(0.3)
			local remaining = endTime - os.clock()
			if remaining > 0 then
				WarningLabel.Text = string.format("INCOMING %s FROM %s! (%ds)", string.upper(attackType), attackerName, math.ceil(remaining))
			end
		end
		WarningFrame.Visible = false
	end)
end)

Remotes.BaseDestroyed.OnClientEvent:Connect(function(_attackerName: string)
	-- Full screen red flash
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = COLOR.RED
	overlay.BackgroundTransparency = 0.3
	overlay.ZIndex = 100
	overlay.Parent = ScreenGui

	local destroyLabel = Instance.new("TextLabel")
	destroyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	destroyLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	destroyLabel.Size = UDim2.new(0, 500, 0, 60)
	destroyLabel.BackgroundTransparency = 1
	destroyLabel.Text = "BASE DESTROYED — REBUILDING..."
	destroyLabel.Font = Enum.Font.GothamBold
	destroyLabel.TextSize = 28
	destroyLabel.TextColor3 = COLOR.WHITE
	destroyLabel.TextStrokeTransparency = 0
	destroyLabel.ZIndex = 101
	destroyLabel.Parent = overlay

	task.delay(4, function()
		local fadeOut = TweenService:Create(overlay, TweenInfo.new(1), { BackgroundTransparency = 1 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			overlay:Destroy()
		end)
	end)
end)

Remotes.AttackResult.OnClientEvent:Connect(function(success: boolean, message: string)
	-- Show brief feedback near the attack panel
	if not success then
		-- Flash the message in red
		local feedback = Instance.new("TextLabel")
		feedback.AnchorPoint = Vector2.new(1, 0)
		feedback.Position = UDim2.new(1, -16, 0.5, 200)
		feedback.Size = UDim2.new(0, 260, 0, 30)
		feedback.BackgroundColor3 = COLOR.RED_DIM
		feedback.BackgroundTransparency = 0.3
		feedback.Text = message
		feedback.Font = Enum.Font.GothamBold
		feedback.TextSize = 12
		feedback.TextColor3 = COLOR.WHITE
		feedback.ZIndex = 15
		feedback.Parent = ScreenGui
		applyCorner(feedback, 4)

		task.delay(2.5, function()
			feedback:Destroy()
		end)
	end
end)

-- Cooldown update loop
task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for attackType, data in attackButtons do
			local spec = CombatConfig.Attacks[attackType]
			if not spec then
				continue
			end
			local lastUsed = attackCooldowns[attackType] or 0
			local remaining = spec.cooldown - (now - lastUsed)

			-- Check if player has the required building
			local hasBuilding = false
			for _, item in unlockedItems do
				if item == spec.requiredBuilding then
					hasBuilding = true
					break
				end
			end

			if not hasBuilding then
				data.cooldownLabel.Text = "LOCKED"
				data.cooldownLabel.TextColor3 = COLOR.GRAY
				data.button.BackgroundColor3 = COLOR.BG_PANEL
			elseif remaining > 0 then
				data.cooldownLabel.Text = string.format("Cooldown: %ds", math.ceil(remaining))
				data.cooldownLabel.TextColor3 = COLOR.AMBER
				data.button.BackgroundColor3 = COLOR.BG_PANEL
			else
				data.cooldownLabel.Text = "Ready"
				data.cooldownLabel.TextColor3 = COLOR.GREEN_LIGHT
				data.button.BackgroundColor3 = COLOR.RED
			end
		end
	end
end)

-- Track unlocked items from unlock events
Remotes.UnlockItem.OnClientEvent:Connect(function(itemName: string, _description: string)
	table.insert(unlockedItems, itemName)
end)

-- Track cooldowns from attack results
Remotes.AttackResult.OnClientEvent:Connect(function(success: boolean, _message: string)
	-- When an attack is launched successfully, we don't know which type
	-- The server handles cooldowns; client just needs rough tracking for UI
end)

-- Track attack launches for cooldown display
Remotes.AttackLaunched.OnClientEvent:Connect(function(attackType: string, fromPad: number, _toPad: number, _travelTime: number)
	-- If we launched it, track cooldown locally
	-- We'll check if fromPad matches our pad (approximate)
	-- For now, just mark cooldown whenever we get a success result
end)

-- Override attack result to track cooldowns
local originalHandler = Remotes.AttackResult.OnClientEvent
-- Use a simpler approach: track via LaunchAttack calls
local lastAttackType: string? = nil

-- Patch the launch buttons to track what we're attacking
for attackType, data in attackButtons do
	local originalClick = data.button.MouseButton1Click
	-- The click handler already fires LaunchAttack
	-- We just need to record the attack type on success
end

-- Listen for successful attacks to set cooldowns
Remotes.AttackResult.OnClientEvent:Connect(function(success: boolean, message: string)
	if success and lastAttackType then
		attackCooldowns[lastAttackType] = os.clock()
		lastAttackType = nil
	end
end)

-- Wrap launch button clicks to track attack type
for attackType, data in attackButtons do
	local btn = data.button
	-- Disconnect original and rewire
	-- Actually, just set lastAttackType before firing
	btn.MouseButton1Click:Connect(function()
		lastAttackType = attackType
	end)
end
