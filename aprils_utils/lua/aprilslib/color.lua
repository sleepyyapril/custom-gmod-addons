AddCSLuaFile()

local HEX_CHARACTERS = "0123456789ABCDEF"

local function convert(str)
    return "0x" .. str
end

local function from_hex(hex_code)
    hex_code = hex_code:gsub("#","")
    assert(hex_code ~= nil, "Hex code cannot be nil!")
    assert(#hex_code <= 6, "Invalid hexcode!")

    local red_hex = convert(hex_code:sub(1, 2))
    local green_hex = convert(hex_code:sub(3, 4))
    local blue_hex = convert(hex_code:sub(5, 6))
    local alpha_hex = (#hex_code > 6) and convert(hex_code:sub(7, 8)) or convert("ff")

    return Color(tonumber(red_hex), tonumber(green_hex), tonumber(blue_hex), tonumber(alpha_hex))
end

local function to_hex(color)
    assert(color ~= nil, "Color must be a color!")
    assert(IsColor(color), "Color must be a color!")

    local r = bit.tohex(color.r, 2)
    local g = bit.tohex(color.g, 2)
    local b = bit.tohex(color.b, 2)

    return "#" .. r .. g .. b
end

return {
    from_hex = from_hex,
    to_hex = to_hex
}