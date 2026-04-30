--!strict
-- RemoteBoot.server.luau
-- Ensures the RemoteEvents folder and all remotes are created immediately
-- when the server starts, before any client scripts try to access them.
-- This eliminates the race condition where the client loads faster than
-- TycoonManager (which has multiple heavy requires).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage:WaitForChild("Remotes"))
