--!strict

--[[
	FormatNumber.luau
	-----------------
	Utility module for formatting currency values shown in the tycoon UI.

	Examples:
		FormatNumber.money(0)           --> "$0"
		FormatNumber.money(1500)        --> "$1,500"
		FormatNumber.money(1000000)     --> "$1.00M"
		FormatNumber.money(2500000000)  --> "$2.50B"
		FormatNumber.money(1000000000000) --> "$1.00T"

	FormatNumber.plain(1234567)         --> "1,234,567"  (no $ prefix)
	FormatNumber.income(25)             --> "+$25/sec"
--]]

-- ── Types ──────────────────────────────────────────────────────────────────

export type FormatNumberType = {
	money: (amount: number) -> string,
	plain: (amount: number) -> string,
	income: (perSecond: number) -> string,
}

-- ── Helpers ────────────────────────────────────────────────────────────────

-- Inserts thousands-separator commas into an integer string.
local function addCommas(intStr: string): string
	-- Walk backwards through the string, inserting a comma every 3 digits.
	local result = {}
	local len = #intStr
	for i = 1, len do
		local fromRight = len - i  -- 0-indexed distance from the right
		if fromRight > 0 and fromRight % 3 == 0 then
			table.insert(result, ",")
		end
		table.insert(result, intStr:sub(i, i))
	end
	return table.concat(result)
end

-- Formats a non-negative integer with commas.  Handles the integer portion
-- of a number (no decimals).  Returns "0" for zero.
local function formatInteger(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	return addCommas(s)
end

-- ── Core formatter ─────────────────────────────────────────────────────────

--[[
	Formats `amount` as a dollar string.
	- < 1,000,000          → "$1,234"          (full integer with commas)
	- ≥ 1,000,000          → "$1.23M"
	- ≥ 1,000,000,000      → "$1.23B"
	- ≥ 1,000,000,000,000  → "$1.23T"
--]]
local function money(amount: number): string
	amount = math.floor(amount) -- cents aren't a thing in tycoon cash

	local sign = amount < 0 and "-" or ""
	local abs = math.abs(amount)

	if abs >= 1_000_000_000_000 then
		return sign .. "$" .. string.format("%.2f", abs / 1_000_000_000_000) .. "T"
	elseif abs >= 1_000_000_000 then
		return sign .. "$" .. string.format("%.2f", abs / 1_000_000_000) .. "B"
	elseif abs >= 1_000_000 then
		return sign .. "$" .. string.format("%.2f", abs / 1_000_000) .. "M"
	else
		return sign .. "$" .. formatInteger(abs)
	end
end

--[[
	Formats `amount` as a plain integer string with commas but no $ sign.
	Useful for counts, scores, etc.
--]]
local function plain(amount: number): string
	local sign = amount < 0 and "-" or ""
	return sign .. formatInteger(math.abs(amount))
end

--[[
	Formats an income rate for display in the UI.
	E.g. income(25) → "+$25/sec"
--]]
local function income(perSecond: number): string
	return "+" .. money(perSecond) .. "/sec"
end

-- ── Module ─────────────────────────────────────────────────────────────────

local FormatNumber: FormatNumberType = table.freeze({
	money = money,
	plain = plain,
	income = income,
})

return FormatNumber
