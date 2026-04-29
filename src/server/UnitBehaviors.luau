--!strict

--[[
	UnitBehaviors.luau
	------------------
	AI behavior patterns for all military unit types. Each exported function
	takes a Part and a center CFrame and drives the part's position/orientation
	each RunService.Heartbeat frame via smooth lerp.

	Every function returns a cleanup callback that disconnects the Heartbeat
	connection so callers can stop the behavior cleanly (e.g. on despawn).
--]]

local RunService = game:GetService("RunService")

-- Small random variation applied per-unit so groups of the same type don't
-- look identical.  Seeded once at module load; each call samples a fresh
-- offset within ±VARIATION_RANGE.
local VARIATION_RANGE = 0.15
local LERP_ALPHA = 0.12 -- Per-frame CFrame lerp factor (feel / responsiveness)

local function randomVariation(): number
	return (math.random() * 2 - 1) * VARIATION_RANGE
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Type
-- ─────────────────────────────────────────────────────────────────────────────

export type CleanupFn = () -> ()

-- ─────────────────────────────────────────────────────────────────────────────
-- Module
-- ─────────────────────────────────────────────────────────────────────────────

local UnitBehaviors = {}

--[[
	PatrolGround(part, center, speed, radius)
	-----------------------------------------
	Moves the part in a rectangular patrol loop around `center`.  Speed is in
	studs/second.  The rectangle has half-extents of (radius, radius/2) so it
	looks like a perimeter patrol rather than a square march.

	The part is kept at the ground plane Y of `center`.
--]]
function UnitBehaviors.PatrolGround(part: BasePart, center: CFrame, speed: number, radius: number): CleanupFn
	-- Build the four corners of the patrol rectangle in local XZ space.
	local hw = radius -- half-width  (X)
	local hd = radius * 0.6 -- half-depth  (Z) – rectangle, not square
	local corners: { Vector3 } = {
		Vector3.new(-hw, 0, -hd),
		Vector3.new(hw, 0, -hd),
		Vector3.new(hw, 0, hd),
		Vector3.new(-hw, 0, hd),
	}

	local baseY = center.Position.Y
	local totalPerimeter = 4 * (hw + hd) * 2 -- approximate, recalculated below

	-- Compute actual segment lengths so we can drive a single distance accumulator
	-- and find the interpolated position accurately.
	local segLengths: { number } = {}
	for i = 1, #corners do
		local next = corners[(i % #corners) + 1]
		segLengths[i] = (next - corners[i]).Magnitude
	end
	totalPerimeter = 0
	for _, l in segLengths do
		totalPerimeter += l
	end

	-- Per-unit phase offset so two Infantry squads don't start at the same corner.
	local phaseOffset = math.random() * totalPerimeter

	-- Small per-unit Y variation (soldiers aren't perfectly flat terrain walkers).
	local yVariation = randomVariation() * 0.5

	local distance = phaseOffset
	local connection: RBXScriptConnection

	connection = RunService.Heartbeat:Connect(function(dt: number)
		distance = (distance + speed * dt) % totalPerimeter

		-- Find which segment we're on.
		local accumulated = 0
		local targetPos = Vector3.zero
		for i = 1, #corners do
			local segEnd = corners[(i % #corners) + 1]
			local segLen = segLengths[i]
			if distance <= accumulated + segLen then
				local t = (distance - accumulated) / segLen
				targetPos = corners[i]:Lerp(segEnd, t)
				break
			end
			accumulated += segLen
		end

		-- Compute look-ahead direction for the next segment so the unit faces
		-- the direction of travel.
		local lookAheadDist = distance + 0.5
		if lookAheadDist >= totalPerimeter then
			lookAheadDist = lookAheadDist - totalPerimeter
		end
		local accumulated2 = 0
		local lookPos = targetPos
		for i = 1, #corners do
			local segEnd = corners[(i % #corners) + 1]
			local segLen = segLengths[i]
			if lookAheadDist <= accumulated2 + segLen then
				local t2 = (lookAheadDist - accumulated2) / segLen
				lookPos = corners[i]:Lerp(segEnd, t2)
				break
			end
			accumulated2 += segLen
		end

		local worldTarget = center:PointToWorldSpace(targetPos + Vector3.new(0, yVariation, 0))
		worldTarget = Vector3.new(worldTarget.X, baseY + yVariation, worldTarget.Z)

		local worldLook = center:PointToWorldSpace(lookPos + Vector3.new(0, yVariation, 0))
		worldLook = Vector3.new(worldLook.X, baseY + yVariation, worldLook.Z)

		local dir = (worldLook - worldTarget)
		local targetCF: CFrame
		if dir.Magnitude > 0.01 then
			targetCF = CFrame.lookAt(worldTarget, worldTarget + dir)
		else
			targetCF = CFrame.new(worldTarget)
		end

		part.CFrame = part.CFrame:Lerp(targetCF, LERP_ALPHA)
	end)

	return function()
		connection:Disconnect()
	end
end

--[[
	PatrolAir(part, center, speed, radius, height)
	------------------------------------------------
	Flies the part in an elliptical circuit at `height` studs above `center`.
	The part banks into turns (rolls on the X-axis proportional to angular
	velocity) to look more like a real aircraft rather than a flat plate gliding
	around.
--]]
function UnitBehaviors.PatrolAir(
	part: BasePart,
	center: CFrame,
	speed: number,
	radius: number,
	height: number
): CleanupFn
	-- Ellipse: X radius = radius, Z radius = radius * 0.65 (elongated circuit)
	local radiusX = radius
	local radiusZ = radius * 0.65

	-- Circumference approximation (Ramanujan) for the angular speed calculation.
	local a, b = radiusX, radiusZ
	local circumference = math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)))
	local angularSpeed = (speed / circumference) * (2 * math.pi) -- radians/second

	-- Per-unit random starting angle and small height wobble amplitude.
	local angle = math.random() * math.pi * 2
	local heightVariation = randomVariation() * 4 -- ±~0.6 studs

	-- Bank parameters: max roll is 25 degrees for fighters, less for drones.
	local maxBankRad = math.rad(25)

	local connection: RBXScriptConnection

	connection = RunService.Heartbeat:Connect(function(dt: number)
		local prevAngle = angle
		angle = angle + angularSpeed * dt

		-- Position on ellipse in center-local space.
		local localX = math.cos(angle) * radiusX
		local localZ = math.sin(angle) * radiusZ
		local localY = height + heightVariation * math.sin(angle * 1.7) -- gentle altitude wobble

		local worldPos = center:PointToWorldSpace(Vector3.new(localX, localY, localZ))

		-- Tangent direction (derivative of ellipse position).
		local dX = -math.sin(angle) * radiusX
		local dZ = math.cos(angle) * radiusZ
		local tangent = center:VectorToWorldSpace(Vector3.new(dX, 0, dZ)).Unit

		-- Banking: angular rate relative to max angular speed → bank fraction.
		local angularRate = angle - prevAngle -- radians this frame
		local bankFraction = math.clamp(angularRate / (angularSpeed * dt + 0.0001), -1, 1)
		local bankAngle = bankFraction * maxBankRad

		-- Build CFrame: look along tangent, then roll.
		local up = Vector3.new(0, 1, 0)
		local baseCF = CFrame.lookAt(worldPos, worldPos + tangent, up)
		local bankedCF = baseCF * CFrame.Angles(0, 0, -bankAngle)

		part.CFrame = part.CFrame:Lerp(bankedCF, LERP_ALPHA)
	end)

	return function()
		connection:Disconnect()
	end
end

--[[
	PatrolSea(part, center, speed, radius)
	---------------------------------------
	Drives naval units in large arcs around `center` at water level (Y = 0 by
	default, but uses center.Position.Y so mapmakers can raise the sea floor).

	Submarines periodically "dive" by tweening their Y down ~10 studs for a few
	seconds, then resurface.  Carriers move very slowly in a wide, gentle arc.
--]]
function UnitBehaviors.PatrolSea(
	part: BasePart,
	center: CFrame,
	speed: number,
	radius: number,
	isSub: boolean?
): CleanupFn
	local baseY = center.Position.Y -- water level
	local radiusX = radius
	local radiusZ = radius * 0.8

	local a, b = radiusX, radiusZ
	local circumference = math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)))
	local angularSpeed = (speed / circumference) * (2 * math.pi)

	local angle = math.random() * math.pi * 2

	-- Sub dive state
	local diveOffset = 0 -- current extra Y offset (negative when submerged)
	local DIVE_DEPTH = -10
	local DIVE_INTERVAL = 30 -- seconds between dives
	local DIVE_DURATION = 8 -- seconds submerged
	local timeSinceDive = math.random() * DIVE_INTERVAL -- stagger first dive
	local isDiving = false
	local diveTimer = 0

	local connection: RBXScriptConnection

	connection = RunService.Heartbeat:Connect(function(dt: number)
		angle = angle + angularSpeed * dt

		-- Sub dive logic
		if isSub then
			timeSinceDive = timeSinceDive + dt
			if not isDiving and timeSinceDive >= DIVE_INTERVAL then
				isDiving = true
				diveTimer = 0
				timeSinceDive = 0
			end
			if isDiving then
				diveTimer = diveTimer + dt
				if diveTimer < 2 then
					-- Descend over 2 seconds
					diveOffset = (diveTimer / 2) * DIVE_DEPTH
				elseif diveTimer < DIVE_DURATION - 2 then
					-- Hold depth
					diveOffset = DIVE_DEPTH
				elseif diveTimer < DIVE_DURATION then
					-- Ascend over final 2 seconds
					local t = (diveTimer - (DIVE_DURATION - 2)) / 2
					diveOffset = DIVE_DEPTH * (1 - t)
				else
					diveOffset = 0
					isDiving = false
				end
			end
		end

		local localX = math.cos(angle) * radiusX
		local localZ = math.sin(angle) * radiusZ
		local worldPos = center:PointToWorldSpace(Vector3.new(localX, 0, localZ))
		worldPos = Vector3.new(worldPos.X, baseY + diveOffset, worldPos.Z)

		-- Heading: tangent to the arc
		local dX = -math.sin(angle) * radiusX
		local dZ = math.cos(angle) * radiusZ
		local tangent = center:VectorToWorldSpace(Vector3.new(dX, 0, dZ))
		tangent = Vector3.new(tangent.X, 0, tangent.Z)

		local targetCF: CFrame
		if tangent.Magnitude > 0.01 then
			targetCF = CFrame.lookAt(worldPos, worldPos + tangent.Unit)
		else
			targetCF = CFrame.new(worldPos)
		end

		part.CFrame = part.CFrame:Lerp(targetCF, LERP_ALPHA * 0.6) -- naval units turn lazily
	end)

	return function()
		connection:Disconnect()
	end
end

--[[
	HoverStationary(part, center, height)
	--------------------------------------
	Apache-style stationary hover.  The part bobs up and down on a sine wave
	(~2 stud amplitude, ~4-second period) and drifts very slightly in XZ to
	simulate rotor wash without fully committing to a patrol route.
--]]
function UnitBehaviors.HoverStationary(part: BasePart, center: CFrame, height: number): CleanupFn
	local BOB_AMPLITUDE = 1.5 -- studs
	local BOB_PERIOD = 4 -- seconds per cycle
	local DRIFT_RADIUS = 3 -- studs of horizontal drift
	local bobPhase = math.random() * math.pi * 2
	local driftPhaseX = math.random() * math.pi * 2
	local driftPhaseZ = math.random() * math.pi * 2

	local elapsed = 0
	local connection: RBXScriptConnection

	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed = elapsed + dt

		local bobY = BOB_AMPLITUDE * math.sin((elapsed / BOB_PERIOD) * math.pi * 2 + bobPhase)
		local driftX = DRIFT_RADIUS * math.sin((elapsed / (BOB_PERIOD * 1.3)) * math.pi * 2 + driftPhaseX)
		local driftZ = DRIFT_RADIUS * math.cos((elapsed / (BOB_PERIOD * 1.7)) * math.pi * 2 + driftPhaseZ)

		local localPos = Vector3.new(driftX, height + bobY, driftZ)
		local worldPos = center:PointToWorldSpace(localPos)

		-- Very slight nose-up pitch to look like hovering, no hard facing direction
		local targetCF = CFrame.new(worldPos) * CFrame.Angles(math.rad(3), 0, 0)

		part.CFrame = part.CFrame:Lerp(targetCF, LERP_ALPHA)
	end)

	return function()
		connection:Disconnect()
	end
end

return UnitBehaviors
