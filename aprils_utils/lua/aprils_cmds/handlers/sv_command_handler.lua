local error_hex = "&" .. aprils_utils.config.error_hex_color
local prefix = aprils_utils.config.command_prefix

--[[

    name: string
    access: string | function
    arguments:
        - name: string
        - argtype: string | greedystring | number | player | players | steamid
        - optional: boolean
    execute: (ply, ...) -> boolean

]]

function aprils_utils.register(cmd_data)
    assert(cmd_data.name ~= nil, "Command must have a name!")
    assert(cmd_data.execute ~= nil, string.format("Command `%s` must have an execute.", cmd_data.name))
    assert(aprils_utils.registry[cmd_data.name:lower()] == nil, string.format("Command %s already exists!", cmd_data.name:lower()))

    cmd_data.access = cmd_data.access or function(ply) return true end
    cmd_data.arguments = cmd_data.arguments or {}

    local count = 0
    local last_is_optional = false

    for _, arg_data in pairs(cmd_data.arguments) do
        count = count + 1

        if aprils_utils.is_supported_type(arg_data.argtype) ~= true then
            print(string.format("[aprils_utils/register] Argument type `%s` does not exist in registration of `%s`.", cmd_data.name, arg_type))
            return
        end

        if count ~= #cmd_data.arguments and arg_data.argtype == "greedystring" then
            print(string.format("[aprils_utils/register] Greedystring must come last for command `%s`.", cmd_data.name))
            return
        end

        if count ~= #cmd_data.arguments and cmd_data.optional and not last_is_optional then
            print(string.format("[aprils_utils/register] Optional arguments must come last for command `%s`.", cmd_data.name))
            return
        end

        last_is_optional = arg_data.optional
    end

    aprils_utils.registry[cmd_data.name:lower()] = cmd_data
end

local function send_usage(ply, data)
    local required_args = ""

    for _, argument in pairs(data.arguments) do
        local surround_with = argument.optional and "[]" or "<>"
        required_args = required_args .. " " .. string.format("%s%s (%s)%s", surround_with:sub(1, 1), argument.name, argument.argtype, surround_with:sub(2, 2))
    end

    ply:SendTranslatedText(error_hex .. "Invalid usage! Usage: &#ffffff" .. aprils_utils.config.command_prefix .. data.name .. required_args)
end

local function get_required_args(cmd_data)
    local required_count = 0

    for _, data in ipairs(cmd_data.arguments) do
        if not data.optional then
            required_count = required_count + 1
        end
    end

    return required_count
end

function aprils_utils.try_handle(ply, msg)
    if not msg:StartsWith(prefix) then
        return false
    end

    msg = string.Replace(msg, "%s+", " ")
    local command = msg:match("[%w_]+", #prefix + 1):lower()
    local cmd_data = aprils_utils.registry[command]

    if not cmd_data then
        return false
    end

    if not aprils_utils.has_access(ply, cmd_data.access, cmd_data.require_all_true) then
        ply:SendTranslatedText(error_hex .. "You do not have permission for this command.")
        return true
    end

    local required_args = get_required_args(cmd_data)
    local has_spaces = msg:find(" ", #prefix + #command)

    if (has_spaces == nil and required_args > 0) or (has_spaces and msg:sub(has_spaces + 1) or true) == nil then
        send_usage(ply, cmd_data)
        return true
    end

    if not has_spaces and #cmd_data.arguments == 0 then
        cmd_data.execute(ply, msg)
        return true
    end

    local args_str = has_spaces and msg:sub(has_spaces + 1) or ""
    local args = has_spaces and args_str:Split(" ") or {}

    if #args < required_args then
        send_usage(ply, cmd_data)
        return true
    end

    local arguments = {}
    local parse = aprils_utils.cmd_parse(args_str)

    -- useful for batch-registered commands, such as a radio system with channels
    if cmd_data.include_command then
        table.insert(arguments, cmd_data.name)
    end

    if cmd_data.include_message then
        table.insert(arguments, msg)
    end

    for index, arg_data in ipairs(cmd_data.arguments) do
        local arg_value = parse(arg_data.argtype)

        if not arg_value and not arg_data.optional then
            send_usage(ply, cmd_data)
            return true
        end

        if arg_data.optional and #args == index and not arg_value then
            send_usage(ply, cmd_data)
            return true
        end

        table.insert(arguments, arg_value)
    end

    cmd_data.execute(ply, unpack(arguments))
    return true
end