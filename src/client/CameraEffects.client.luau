--!strict
-- CameraEffects.client.luau
-- Plays a brief cinematic flyover when the player first joins, then returns
-- control to the default Roblox camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ── Configuration ─────────────────────────────────────────────────────────────
local FLYOVER_DURATION = 3.0 -- seconds for the full sweep
local OVERVIEW_HEIGHT = 180 -- studs above world origin for the start position
local OVERVIEW_OFFSET = 160 -- horizontal offset so we look across the base

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Attempt to locate this player's tycoon pad in workspace.
-- The server names tycoon folders as "Tycoon_Pad_N" (1-indexed pad number).
-- We scan for any folder matching that prefix and look for BasePlatform inside.
local function findTycoonPadCFrame(): CFrame
	-- Wait briefly for tycoon folders to appear (server may still be building)
	task.wait(0.5)

	-- Scan workspace for Tycoon_Pad_N folders and find BasePlatform inside
	for _, child in workspace:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, 11) == "Tycoon_Pad_" then
			local basePlatform = child:FindFirstChild("BasePlatform")
			if basePlatform and basePlatform:IsA("BasePart") then
				return basePlatform.CFrame
			end
		end
	end

	-- Last resort: use the world origin. The flyover still looks nice.
	return CFrame.new(0, 0, 0)
end

-- ── Flyover sequence ──────────────────────────────────────────────────────────

local function runFlyover()
	-- Switch to scriptable so we have full control.
	Camera.CameraType = Enum.CameraType.Scriptable

	local padCFrame = findTycoonPadCFrame()
	local padPos = padCFrame.Position

	-- Start position: high and offset, looking down toward the pad.
	local startPos = Vector3.new(padPos.X + OVERVIEW_OFFSET, padPos.Y + OVERVIEW_HEIGHT, padPos.Z + OVERVIEW_OFFSET)

	-- End position: lower and closer, almost at pad level.
	local endPos = Vector3.new(padPos.X + 20, padPos.Y + 35, padPos.Z + 20)

	Camera.CFrame = CFrame.lookAt(startPos, padPos)

	-- Animate via RunService heartbeat lerp for a smooth, frame-rate-independent sweep.
	local elapsed = 0
	local connection: RBXScriptConnection

	connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local alpha = math.clamp(elapsed / FLYOVER_DURATION, 0, 1)
		-- Ease-in-out cubic for a cinematic feel.
		local t = alpha < 0.5 and 4 * alpha * alpha * alpha or 1 - (-2 * alpha + 2) ^ 3 / 2

		local currentPos = startPos:Lerp(endPos, t)
		-- Look-at target also lerps slightly inward so the camera pans naturally.
		local lookTarget = Vector3.new(padPos.X, padPos.Y + 5, padPos.Z)
		Camera.CFrame = CFrame.lookAt(currentPos, lookTarget)

		if alpha >= 1 then
			connection:Disconnect()
			-- Hand control back to the player.
			Camera.CameraType = Enum.CameraType.Custom
		end
	end)
end

-- ── Entry point ───────────────────────────────────────────────────────────────
-- Only run once, on the very first character load (i.e. when the player joins).
local hasFired = false

local function onCharacterAdded(_character: Model)
	if hasFired then
		return
	end
	hasFired = true

	-- Small delay so the world has a chance to load before we start the sweep.
	task.wait(0.5)
	runFlyover()
end

if LocalPlayer.Character then
	-- Character already exists in Studio Play Solo.
	task.spawn(onCharacterAdded, LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
