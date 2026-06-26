--!strict
--[[
	RagdollService
	==============

	Wires the Ragdoll module up to every player's character:

	  * Sets up a collision group so collision spheres ignore one another
	    (players don't shove each other around while limp).
	  * Ragdolls a character automatically when its Humanoid dies.
	  * Listens for a RemoteEvent so clients / other server code can toggle
	    a ragdoll on demand (e.g. a "ragdoll" keybind or a knockback hit).
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ragdoll = require(ReplicatedStorage:WaitForChild("Ragdoll"))

local COLLISION_GROUP = "RagdollSpheres"

-- Spheres collide with the world but pass through other spheres.
local ok = pcall(function()
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
end)
if not ok then
	warn("RagdollService: collision group already registered")
end

-- One Ragdoll controller per character, keyed by the character model.
local controllers: { [Model]: Ragdoll.Ragdoll } = {}

local function getController(character: Model): Ragdoll.Ragdoll?
	local controller = controllers[character]
	if controller then
		return controller
	end
	if not character:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	controller = Ragdoll.new(character, {
		ShowSpheres = false,
		CollisionGroup = COLLISION_GROUP,
	})
	controllers[character] = controller
	return controller
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Limp on death.
	humanoid.Died:Connect(function()
		local controller = getController(character)
		if controller then
			controller:Activate()
		end
	end)

	character.Destroying:Connect(function()
		local controller = controllers[character]
		if controller then
			controller:Destroy()
			controllers[character] = nil
		end
	end)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Remote toggle so other code can ragdoll a player on demand.
local toggleEvent = Instance.new("RemoteEvent")
toggleEvent.Name = "ToggleRagdoll"
toggleEvent.Parent = ReplicatedStorage

toggleEvent.OnServerEvent:Connect(function(player: Player, enabled: boolean?)
	local character = player.Character
	if not character then
		return
	end
	local controller = getController(character)
	if not controller then
		return
	end
	if enabled == nil then
		enabled = not controller.Active
	end
	if enabled then
		controller:Activate()
	else
		controller:Deactivate()
	end
end)
