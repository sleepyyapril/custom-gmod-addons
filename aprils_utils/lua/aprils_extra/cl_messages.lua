local color_utils = include("aprilslib/color.lua")

local function find_hex_codes(message)
    local new_message_data = {}
    local positions = {}
    local ignore_positions = {}
    local start = 1

    while true do
        local start_pos, end_pos = string.find(message, "&#%w%w%w%w%w%w", start)

        if start_pos == nil then
            break
        end

        if message:sub(start) == nil then
            break
        end

        table.insert(positions, {
            start_pos = start_pos,
            end_pos = end_pos,
            text = message:sub(start_pos + 1, end_pos)
        })

        start = end_pos + 1
    end
    
    local last_end = 1

    for _, data in ipairs(positions) do
        if last_end > #message then return end
        local text = message:sub(last_end, data.start_pos)
        local new_color = color_utils.from_hex(data.text:sub(2, #data.text))
        local filtered_text = text:sub(1, #text - 1)

        if filtered_text ~= nil and #filtered_text ~= 0 then
            table.insert(new_message_data, filtered_text)
        end

        table.insert(new_message_data, new_color)
        last_end = data.end_pos + 1
    end

    local next_text = message:sub(last_end, #message)

    if next_text ~= nil and #next_text ~= 0 then
        table.insert(new_message_data, next_text)
    end

    return new_message_data
end

net.Receive("autils_sendtranslatedtext", function(len, ply)
    local message = net.ReadString()
    local chat_data = find_hex_codes(message)
    local sanitized = {}
    
    for _, value in ipairs(chat_data) do
        if type(value) ~= "string" then
            table.insert(sanitized, value)
            continue
        end

        table.insert(sanitized, value:Replace("!&!#", "&#"))
    end

    chat.AddText(unpack(chat_data))
end)