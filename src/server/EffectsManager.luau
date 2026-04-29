--!strict

--[[
	EffectsManager.luau
	--------------------
	Server-side visual effects attached directly to unit Parts.  Effects are
	kept intentionally lightweight — Trail/ParticleEmitter instances only — so
	they replicate to all clients automatically without any extra RemoteEvent
	overhead.

	Each function returns the created Instance(s) so callers can Destroy them
	during unit despawn if needed (though destroying the parent Part also works).
--]]

-- Re-export the category type so callers don't need to import UnitConfig separately.
export type UnitCategory = "Infantry" | "Vehicle" | "Aircraft" | "Naval"

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

--- Create a small invisible Attachment at a local offset on a BasePart.
local function makeAttachment(parent: BasePart, offset: Vector3, name: string): Attachment
	local att = Instance.new("Attachment")
	att.Position = offset
	att.Name = name
	att.Parent = parent
	return att
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module
-- ─────────────────────────────────────────────────────────────────────────────

local EffectsManager = {}

--[[
	TrailEffect(part)
	-----------------
	Attach a white semi-transparent contrail to an aircraft Part.  Two
	Attachments are placed at the rear wingtips so the trail spreads slightly,
	resembling real wing-tip vortex condensation trails.
--]]
function EffectsManager.TrailEffect(part: BasePart): Trail
	local halfZ = part.Size.Z / 2
	local halfX = part.Size.X / 2 * 0.6

	local att0 = makeAttachment(part, Vector3.new(-halfX, 0, halfZ), "TrailAtt0")
	local att1 = makeAttachment(part, Vector3.new(halfX, 0, halfZ), "TrailAtt1")

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 2.5
	trail.MinLength = 0.1
	trail.MaxLength = 200
	trail.FaceCamera = true
	trail.LightEmission = 0.3
	trail.LightInfluence = 0.6
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.4, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 220, 255)),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = part

	return trail
end

--[[
	WakeEffect(part)
	----------------
	Attach a blue-white wake trail behind a naval unit's hull.  A single wide
	trail running from bow to stern simulates the ship's wake on the water
	surface.
--]]
function EffectsManager.WakeEffect(part: BasePart): Trail
	local halfZ = part.Size.Z / 2
	local halfX = part.Size.X / 2 * 0.5

	-- Place attachments at the rear of the hull, slightly below centre (water-line).
	local att0 = makeAttachment(part, Vector3.new(-halfX, -part.Size.Y * 0.3, halfZ), "WakeAtt0")
	local att1 = makeAttachment(part, Vector3.new(halfX, -part.Size.Y * 0.3, halfZ), "WakeAtt1")

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 3.0
	trail.MinLength = 0.1
	trail.MaxLength = 300
	trail.FaceCamera = false -- wake lies on the water plane
	trail.LightEmission = 0.1
	trail.LightInfluence = 0.8
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 240, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 200, 230)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 150, 200)),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.Parent = part

	return trail
end

--[[
	DustEffect(part)
	----------------
	Attach a ParticleEmitter at the base of a ground vehicle Part that emits
	brown dust/dirt particles whenever the unit is moving.  The emitter is
	always active at a low rate; the calling code can adjust Rate or Enabled
	based on actual movement if desired.
--]]
function EffectsManager.DustEffect(part: BasePart): ParticleEmitter
	-- Attach at the bottom-centre of the part (ground contact point).
	local att = makeAttachment(part, Vector3.new(0, -part.Size.Y / 2, 0), "DustAtt")

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DustEmitter"
	emitter.Parent = att -- parent to attachment so it follows the part

	emitter.Enabled = true
	emitter.Rate = 8 -- particles per second; low enough to not be overwhelming
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-45, 45)
	emitter.LightEmission = 0
	emitter.LightInfluence = 1

	-- Drift particles slightly upward and let gravity pull them back.
	emitter.VelocityInheritance = 0.3
	emitter.LockedToPart = false

	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 110, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 130, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 160, 130)),
	})

	return emitter
end

--[[
	ApplyEffectsForCategory(part, category)
	-----------------------------------------
	Convenience function: given a unit Part and its UnitCategory string, applies
	the appropriate effect(s) and returns them in a table for later cleanup.
--]]
function EffectsManager.ApplyEffectsForCategory(part: BasePart, category: string): { Instance }
	local effects: { Instance } = {}

	if category == "Aircraft" then
		table.insert(effects, EffectsManager.TrailEffect(part))
	elseif category == "Naval" then
		table.insert(effects, EffectsManager.WakeEffect(part))
	elseif category == "Vehicle" or category == "Infantry" then
		table.insert(effects, EffectsManager.DustEffect(part))
	end

	return effects
end

return EffectsManager
