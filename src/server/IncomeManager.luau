--!strict

export type IncomeState = {
	rate: number,
	active: boolean,
}

-- Internal per-player state. Keyed by Player instance.
local incomeStates: { [Player]: IncomeState } = {}

-- Callback invoked each tick so TycoonManager can update balances without a
-- circular dependency. Set via IncomeManager.SetTickCallback before starting
-- any income loops.
local tickCallback: ((player: Player, amount: number) -> ())? = nil

local IncomeManager = {}

--- Register the function that should be called every tick with the earned amount.
--- Must be set before StartIncome is called.
function IncomeManager.SetTickCallback(callback: (player: Player, amount: number) -> ())
	tickCallback = callback
end

--- Start an income coroutine for a player at the given rate (per second).
--- If a loop is already running for this player it is stopped first.
function IncomeManager.StartIncome(player: Player, initialRate: number)
	-- Stop any existing loop cleanly before creating a new one.
	IncomeManager.StopIncome(player)

	local state: IncomeState = {
		rate = initialRate,
		active = true,
	}
	incomeStates[player] = state

	task.spawn(function()
		while state.active do
			task.wait(1)
			-- Re-check after the wait in case the player left mid-sleep.
			if not state.active then
				break
			end
			local cb = tickCallback
			if cb then
				cb(player, state.rate)
			end
		end
	end)
end

--- Update the income rate for a running player loop.
--- Safe to call even if no loop is active (will be a no-op).
function IncomeManager.UpdateRate(player: Player, newRate: number)
	local state = incomeStates[player]
	if state then
		state.rate = newRate
	end
end

--- Stop and remove the income loop for a player.
function IncomeManager.StopIncome(player: Player)
	local state = incomeStates[player]
	if state then
		state.active = false
		incomeStates[player] = nil
	end
end

--- Returns the current income rate for a player, or 0 if none is registered.
function IncomeManager.GetRate(player: Player): number
	local state = incomeStates[player]
	if state then
		return state.rate
	end
	return 0
end

return IncomeManager
