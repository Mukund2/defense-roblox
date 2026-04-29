--!strict
-- TycoonClient.client.luau
-- Main client controller: claims tycoon pad, relays server remotes to HUD,
-- detects purchase button touches, and plays unlock effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ── Remote references ────────────────────────────────────────────────────────
-- Remotes module is the single source of truth; it blocks until the server
-- has created all remotes so no extra WaitForChild calls are needed here.
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes", 30) :: ModuleScript)

local ClaimTycoon  = Remotes.ClaimTycoon
local UpdateMoney  = Remotes.UpdateMoney
local UpdateIncome = Remotes.UpdateIncome
local UnlockItem   = Remotes.UnlockItem
local PurchaseItem = Remotes.PurchaseItem

-- ── HUD API (loaded after StarterGui scripts have run) ───────────────────────
-- TycoonHUD exposes its API through a BindableFunction or shared table.
-- We use a simple polling wait since the HUD LocalScript runs in the same
-- PlayerGui and sets _G.TycoonHUD when ready.
local HUD: {
	UpdateMoney: (amount: number) -> (),
	UpdateIncome: (rate: number) -> (),
	ShowUnlockNotification: (itemName: string, description: string) -> (),
	UpdateBaseLevel: (level: number) -> (),
} | nil = nil

task.spawn(function()
	-- Wait up to 10 s for the HUD module to register itself.
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		local api = _G.TycoonHUD :: any
		if api then
			HUD = api
			break
		end
		task.wait(0.1)
	end
end)

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Plays a brief expanding + fading sphere at the given CFrame.
local function playUnlockEffect(cframe: CFrame)
	local part = Instance.new("Part")
	part.Size = Vector3.new(4, 4, 4)
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(74, 124, 89) -- military green
	part.Transparency = 0.2
	part.Parent = workspace

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(part, info, {
		Size = Vector3.new(20, 20, 20),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

-- Returns the root part of the local character if available.
local function getCharacterRoot(): BasePart?
	local character = LocalPlayer.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Tracks which buttons have already been touched this frame to debounce.
local recentPurchases: { [string]: number } = {}
local PURCHASE_COOLDOWN = 2 -- seconds

local function onButtonTouched(button: BasePart, character: Model)
	local itemName = button:GetAttribute("TycoonItem") :: string?
	if not itemName or itemName == "" then return end

	local now = os.clock()
	local lastTime = recentPurchases[itemName]
	if lastTime and (now - lastTime) < PURCHASE_COOLDOWN then return end

	-- Verify the touching part belongs to the local character.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	recentPurchases[itemName] = now
	PurchaseItem:FireServer(itemName)
end

-- Connects Touched listeners to every part inside a purchase button model/part.
local function connectButton(button: Instance, character: Model)
	if button:IsA("BasePart") then
		button.Touched:Connect(function(hit: BasePart)
			if hit:IsDescendantOf(character) then
				onButtonTouched(button, character)
			end
		end)
	end
	for _, child in button:GetChildren() do
		connectButton(child, character)
	end
end

-- ── Character setup ──────────────────────────────────────────────────────────

local function onCharacterAdded(character: Model)
	-- Wait for humanoid so the character is fully loaded.
	character:WaitForChild("HumanoidRootPart", 10)

	-- Claim a tycoon pad.
	ClaimTycoon:FireServer()

	-- Connect purchase button detection.
	-- Purchase buttons live inside Tycoon_Pad_N folders in workspace.
	-- We scan all tycoon folders and watch for new children.
	local function scanForButtons(folder: Instance)
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") and child.Name:sub(1, 15) == "PurchaseButton_" then
				connectButton(child, character)
			end
		end
		folder.ChildAdded:Connect(function(child: Instance)
			if child:IsA("BasePart") and child.Name:sub(1, 15) == "PurchaseButton_" then
				connectButton(child, character)
			end
		end)
	end

	-- Scan existing tycoon folders
	for _, child in workspace:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 11) == "Tycoon_Pad_" then
			scanForButtons(child)
		end
	end

	-- Watch for new tycoon folders (other players joining)
	workspace.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Folder") and child.Name:sub(1, 11) == "Tycoon_Pad_" then
			scanForButtons(child)
		end
	end)
end

-- Handle character already present (studio Play Solo) or future spawns.
if LocalPlayer.Character then
	task.spawn(onCharacterAdded, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- ── Remote listeners ─────────────────────────────────────────────────────────

-- Tracks the running base level so we can pass it to UpdateBaseLevel.
local currentBaseLevel = 0

UpdateMoney.OnClientEvent:Connect(function(amount: number)
	if HUD then
		HUD.UpdateMoney(amount)
	end
end)

UpdateIncome.OnClientEvent:Connect(function(rate: number)
	if HUD then
		HUD.UpdateIncome(rate)
	end
end)

UnlockItem.OnClientEvent:Connect(function(itemName: string, description: string)
	-- Play unlock effect above the player.
	local root = getCharacterRoot()
	if root then
		playUnlockEffect(root.CFrame * CFrame.new(0, 8, 0))
	end

	-- Increment base level and notify HUD.
	currentBaseLevel += 1
	if HUD then
		HUD.ShowUnlockNotification(itemName, description or "")
		HUD.UpdateBaseLevel(currentBaseLevel)
	end
end)
