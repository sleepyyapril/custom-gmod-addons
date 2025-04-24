local assert = assert
local type = type
local string = string
local tonumber = tonumber
local player = player
local table = table

-- cmd_parse function that takes an input string and returns a parsing function
-- it returns a function that can be used to get an argument from a command.
-- argument types are currently limited to greedystring, string and number.

--[[
	usage (for 3 arguments):

	local parse_func = cmd_parse(some_full_message)
	local specific_arg = parse_func("string")
	local specific_arg2 = parse_func("number")
	local specific_arg3 = parse_func("greedystring")
]]

local supported_types = {
	["string"] = true,
	["greedystring"] = true,
	["number"] = true,
	["players"] = true,
	["player"] = true,
	["steamid"] = true
}

function aprils_utils.is_supported_type(type_str)
	assert(type(type_str) == "string")
	return supported_types[type_str]
end

function aprils_utils.cmd_parse(type_str)
	assert(type(type_str) == "string")
	local current_character = 1

	local function count(n)
		local old = current_character
		current_character = n + 1
		return old, n
	end

	local function parse_as(as)
		if current_character > #type_str then return nil end

		if as == "greedystring" then
			return string.sub(type_str, count(#type_str))
		elseif as == "string" then
			local next_space = string.find(type_str, " ", current_character) or #type_str
			return string.TrimRight(string.sub(type_str, count(next_space)))
		elseif as == "number" then
			local next_space = string.find(type_str, " ", current_character) or #type_str
			return tonumber(string.sub(type_str, count(next_space)))
		elseif as == "players" then
			local next_space = string.find(type_str, " ", current_character) or #type_str
			local target_str = string.TrimRight(string.sub(type_str, count(next_space)))
			local targets = {}

			for _, target in player.Iterator() do
				if target:SteamID() == target_str or target:GetName():sub(1, #target_str):lower() == target_str:lower() then
					table.insert(targets, target)
				end
			end

			if #targets > 0 then
				return targets
			else
				return
			end
		elseif as == "player" then
			local next_space = string.find(type_str, " ", current_character) or #type_str
			local target_str = string.TrimRight(string.sub(type_str, count(next_space)))

			for _, target in player.Iterator() do
				if  target:SteamID() == target_str or target:GetName():sub(1, #target_str):lower() == target_str:lower() then
					return target
				end
			end

			return
		elseif as == "steamid" then
			local next_space = string.find(type_str, " ", current_character) or #type_str
			local target_str = string.TrimRight(string.sub(type_str, count(next_space)))

			return player.GetBySteamID(target_str)
		else
			return
		end
	end

	return parse_as
end
