--!strict
--[[
	Ragdoll (R6)
	============

	A drop-in ragdoll system for R6 characters.

	Core idea
	---------
	R6 limbs are blocks. When you let those blocks collide with the world during
	a ragdoll they snag on edges, jitter, and clip through seams — the classic
	"ragdoll caught on a corner and vibrating" look.

	Instead of colliding with the blocky limbs, this system welds an invisible
	**collision sphere** inside each limb and turns the limb's own collision off.
	Spheres can't catch on a corner, so the body tumbles and settles smoothly and
	naturally. The visible limbs ride along (the joints are swapped from rigid
	`Motor6D`s to floppy `BallSocketConstraint`s), so the character still looks
	right while the hidden spheres do all the colliding.

	Usage
	-----
		local Ragdoll = require(ReplicatedStorage.Ragdoll)

		local ragdoll = Ragdoll.new(character)
		ragdoll:Activate()    -- go limp
		ragdoll:Deactivate()  -- stand back up
		ragdoll:Destroy()     -- clean up references

	The module is purely physical: it touches joints, collisions and the
	Humanoid state, but never destroys the original rig, so activation is fully
	reversible.
]]

local Ragdoll = {}
Ragdoll.__index = Ragdoll

export type Config = {
	-- Sphere diameter is `min(limb.Size) * SphereScale`. The limb's smallest
	-- dimension keeps the sphere snug inside the limb so it rolls cleanly
	-- without ballooning past the silhouette.
	SphereScale: number,
	-- Render the collision spheres for debugging.
	ShowSpheres: boolean,
	-- Joint swing/twist limits keep the pose from folding into a knot.
	BallSocketUpperAngle: number,
	BallSocketTwistLower: number,
	BallSocketTwistUpper: number,
	-- CollisionGroup applied to the spheres so they ignore each other (and,
	-- if you configure it, the player). Empty string leaves the default group.
	CollisionGroup: string,
}

local DEFAULT_CONFIG: Config = {
	SphereScale = 1,
	ShowSpheres = false,
	BallSocketUpperAngle = 45,
	BallSocketTwistLower = -45,
	BallSocketTwistUpper = 45,
	CollisionGroup = "",
}

-- The six R6 limbs that get a collision sphere.
local R6_LIMBS = {
	"Head",
	"Torso",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
}

-- The five R6 joints to convert. All live inside the Torso. "RootJoint" (in the
-- HumanoidRootPart) is deliberately left alone: it anchors the rig, and breaking
-- it makes the character fly apart instead of crumple.
local R6_JOINTS = {
	"Neck",
	"Left Shoulder",
	"Right Shoulder",
	"Left Hip",
	"Right Hip",
}

export type Ragdoll = typeof(setmetatable(
	{} :: {
		Character: Model,
		Humanoid: Humanoid,
		Config: Config,
		Active: boolean,
		_sockets: { BallSocketConstraint },
		_attachments: { Attachment },
		_motors: { Motor6D },
		_spheres: { BasePart },
		_welds: { WeldConstraint },
	},
	Ragdoll
))

-- Build a ragdoll controller for an R6 `character`. Does not change anything
-- until `:Activate()` is called.
function Ragdoll.new(character: Model, config: Config?): Ragdoll
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Ragdoll.new: character has no Humanoid")
	assert(humanoid.RigType == Enum.HumanoidRigType.R6, "Ragdoll.new: character is not R6")

	local merged: Config = table.clone(DEFAULT_CONFIG)
	if config then
		for key, value in config :: any do
			(merged :: any)[key] = value
		end
	end

	local self = setmetatable({
		Character = character,
		Humanoid = humanoid,
		Config = merged,
		Active = false,
		_sockets = {},
		_attachments = {},
		_motors = {},
		_spheres = {},
		_welds = {},
	}, Ragdoll)

	return self
end

-- Weld an invisible, collidable sphere inside a limb and turn the limb's own
-- collision off. The sphere is what actually touches the world.
function Ragdoll._attachSphere(self: Ragdoll, limb: BasePart)
	local size = limb.Size
	local diameter = math.min(size.X, size.Y, size.Z) * self.Config.SphereScale

	local sphere = Instance.new("Part")
	sphere.Name = "CollisionSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(diameter, diameter, diameter)
	sphere.Massless = true
	sphere.CanCollide = true
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Transparency = self.Config.ShowSpheres and 0.6 or 1
	sphere.Color = Color3.fromRGB(255, 80, 80)
	sphere.CFrame = limb.CFrame

	if self.Config.CollisionGroup ~= "" then
		sphere.CollisionGroup = self.Config.CollisionGroup
	end

	-- The limb stops colliding; the sphere takes over.
	limb.CanCollide = false

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = sphere
	weld.Parent = sphere

	sphere.Parent = limb

	table.insert(self._spheres, sphere)
	table.insert(self._welds, weld)
end

-- Swap a rigid Motor6D for a BallSocketConstraint so the joint goes floppy.
-- The Motor6D is only disabled (not destroyed) so it can be restored verbatim.
function Ragdoll._convertJoint(self: Ragdoll, motor: Motor6D)
	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return
	end

	local socketAttachment = Instance.new("Attachment")
	socketAttachment.Name = motor.Name .. "_Socket0"
	socketAttachment.CFrame = motor.C0
	socketAttachment.Parent = part0

	local boneAttachment = Instance.new("Attachment")
	boneAttachment.Name = motor.Name .. "_Socket1"
	boneAttachment.CFrame = motor.C1
	boneAttachment.Parent = part1

	local socket = Instance.new("BallSocketConstraint")
	socket.Name = motor.Name .. "_Ragdoll"
	socket.Attachment0 = socketAttachment
	socket.Attachment1 = boneAttachment
	socket.LimitsEnabled = true
	socket.UpperAngle = self.Config.BallSocketUpperAngle
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = self.Config.BallSocketTwistLower
	socket.TwistUpperAngle = self.Config.BallSocketTwistUpper
	socket.MaxFrictionTorque = 0
	socket.Parent = part1

	motor.Enabled = false

	table.insert(self._motors, motor)
	table.insert(self._sockets, socket)
	table.insert(self._attachments, socketAttachment)
	table.insert(self._attachments, boneAttachment)
end

-- Go limp. Idempotent: calling it while already active is a no-op.
function Ragdoll.Activate(self: Ragdoll)
	if self.Active then
		return
	end
	self.Active = true

	local character = self.Character
	local humanoid = self.Humanoid

	-- Hand control to the physics solver and stop the Humanoid from fighting it.
	-- Disabling the engine's own Ragdoll / FallingDown / GettingUp states keeps
	-- vanilla balance from tipping the character over or trying to stand it back
	-- up while our sphere ragdoll is in control.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	local torso = character:FindFirstChild("Torso")

	-- Convert the five torso joints.
	if torso then
		for _, jointName in R6_JOINTS do
			local motor = torso:FindFirstChild(jointName)
			if motor and motor:IsA("Motor6D") then
				self:_convertJoint(motor)
			end
		end
	end

	-- Give every limb a collision sphere and disable its block collision.
	for _, limbName in R6_LIMBS do
		local limb = character:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			self:_attachSphere(limb)
		end
	end
end

-- Stand back up: undo everything `:Activate()` did.
function Ragdoll.Deactivate(self: Ragdoll)
	if not self.Active then
		return
	end
	self.Active = false

	for _, socket in self._sockets do
		socket:Destroy()
	end
	for _, attachment in self._attachments do
		attachment:Destroy()
	end
	for _, weld in self._welds do
		weld:Destroy()
	end
	for _, sphere in self._spheres do
		sphere:Destroy()
	end

	-- Re-enable the original joints.
	for _, motor in self._motors do
		motor.Enabled = true
	end

	-- Re-collide every limb the spheres were standing in for.
	for _, limbName in R6_LIMBS do
		local limb = self.Character:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			limb.CanCollide = true
		end
	end

	table.clear(self._sockets)
	table.clear(self._attachments)
	table.clear(self._welds)
	table.clear(self._spheres)
	table.clear(self._motors)

	-- Stand the rig upright before handing control back. With the motors
	-- re-enabled the whole body is rigid relative to the HumanoidRootPart, so
	-- snapping the root upright snaps the character upright too. Without this the
	-- root is still lying at a ragdolled angle and the Humanoid topples the
	-- moment it tries to stand.
	local character = self.Character
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = root.Position
		-- Keep only the yaw of the current facing so the character stands up
		-- facing roughly where it was, never pitched or rolled.
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
		root.CFrame = CFrame.lookAt(position, position + flat.Unit)
	end

	-- Clear leftover ragdoll momentum so nothing carries the body over once the
	-- joints are rigid again.
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local humanoid = self.Humanoid
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

-- Tear down any active ragdoll state and drop references.
function Ragdoll.Destroy(self: Ragdoll)
	self:Deactivate()
end

return Ragdoll
