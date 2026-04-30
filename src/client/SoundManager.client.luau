--!strict
-- SoundManager.client.luau
-- Manages all game audio: background music, purchase/unlock SFX, and
-- proximity beeps near purchase buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes", 30) :: ModuleScript)

-- ── Asset IDs ────────────────────────────────────────────────────────────────
-- Using Roblox built-in / known-working asset IDs only.

local PURCHASE_SFX_ID = "rbxassetid://7112275565" -- Cash Register (Kaching) from Creator Store
local UNLOCK_SFX_ID = "rbxassetid://7112275565" -- Same kaching for unlock
local BEEP_SFX_ID = "rbxassetid://6042053626" -- UI click/beep

-- Background music disabled — no approved asset available.
-- To enable: find a music ID on Creator Store, set it below.
-- local MUSIC_ID = "rbxassetid://XXXXXXXXXX"

-- ── SFX Sounds ───────────────────────────────────────────────────────────────
-- Keep SFX as children of a folder under the SoundService for clean organisation.

local sfxFolder = Instance.new("Folder")
sfxFolder.Name = "SFX"
sfxFolder.Parent = SoundService

local function createSFX(name: string, assetId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = assetId
	sound.Volume = volume
	sound.Looped = false
	sound.Parent = sfxFolder
	return sound
end

local purchaseSound = createSFX("Purchase", PURCHASE_SFX_ID, 0.5)
local unlockSound = createSFX("Unlock", UNLOCK_SFX_ID, 0.6)
local beepSound = createSFX("Beep", BEEP_SFX_ID, 0.2)

-- Extra SFX stubs for Phase 3 (placeholders using beep until real assets arrive)
local explosionSound = createSFX("Explosion", BEEP_SFX_ID, 0.7)
local sirenSound = createSFX("Siren", BEEP_SFX_ID, 0.5)

-- ── Playback helpers ─────────────────────────────────────────────────────────

local function playSFX(sound: Sound)
	-- Clone so overlapping plays don't cut each other off.
	local clone = sound:Clone()
	clone.Parent = sound.Parent
	clone:Play()
	clone.Ended:Once(function()
		clone:Destroy()
	end)
end

-- ── Public API via _G ────────────────────────────────────────────────────────

_G.SoundManager = {
	PlayPurchase = function()
		playSFX(purchaseSound)
	end,
	PlayUnlock = function()
		playSFX(unlockSound)
	end,
	PlayClick = function()
		playSFX(beepSound)
	end,
	PlayExplosion = function()
		playSFX(explosionSound)
	end,
	PlaySiren = function()
		playSFX(sirenSound)
	end,
}

-- ── Game event listeners ─────────────────────────────────────────────────────

-- Play a subtle coin sound on every 5th income tick.
local incomeTicks = 0

Remotes.UpdateMoney.OnClientEvent:Connect(function(_amount: number)
	incomeTicks += 1
	if incomeTicks % 10 == 0 then
		playSFX(beepSound)
	end
end)

-- Play unlock fanfare when a new item is unlocked.
Remotes.UnlockItem.OnClientEvent:Connect(function(_itemName: string, _description: string)
	playSFX(unlockSound)
end)

-- ── Proximity beep for purchase buttons ──────────────────────────────────────

local PROXIMITY_DISTANCE = 20 -- studs
local PROXIMITY_INTERVAL = 0.5 -- seconds

local function getCharacterRoot(): BasePart?
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local lastBeepTime = 0

task.spawn(function()
	while true do
		task.wait(PROXIMITY_INTERVAL)

		local root = getCharacterRoot()
		if not root then
			continue
		end

		local now = os.clock()
		-- Debounce so we don't spam beeps
		if (now - lastBeepTime) < 1.0 then
			continue
		end

		local rootPos = root.Position
		local foundNearby = false

		-- Scan tycoon pad folders for purchase buttons
		for _, child in workspace:GetChildren() do
			if not child:IsA("Folder") or child.Name:sub(1, 11) ~= "Tycoon_Pad_" then
				continue
			end
			for _, button in child:GetChildren() do
				if button:IsA("BasePart") and button.Name:sub(1, 15) == "PurchaseButton_" then
					local dist = (button.Position - rootPos).Magnitude
					if dist <= PROXIMITY_DISTANCE then
						foundNearby = true
						break
					end
				end
			end
			if foundNearby then
				break
			end
		end

		if foundNearby then
			playSFX(beepSound)
			lastBeepTime = os.clock()
		end
	end
end)
