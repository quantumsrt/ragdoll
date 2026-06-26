--!strict
--[[
	RagdollToggle (client)
	======================

	Press R to toggle your own ragdoll. The actual state change happens on the
	server (authoritative physics); this just fires the request.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local toggleEvent = ReplicatedStorage:WaitForChild("ToggleRagdoll") :: RemoteEvent

local TOGGLE_KEY = Enum.KeyCode.R

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		-- nil tells the server to flip whatever the current state is.
		toggleEvent:FireServer(nil)
	end
end)
