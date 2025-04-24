AddCSLuaFile()

function load_file(path)
    path = string.TrimRight(path, ".lua") .. ".lua"

    local name = string.GetFileFromFilename(path)
    local realm = string.sub(name, 1, 3)

    if realm == "cl_" then
        if CLIENT then
            include(path)
        else
            AddCSLuaFile(path)
        end
    elseif realm == "sh_" or (realm  ~= "sv_" and realm ~= "cl_") then
        if SERVER then
            AddCSLuaFile(path)
        end

        include(path)
    elseif realm == "sv_" then
        if SERVER then
            include(path)
        end
    end
end

function load_directory(dir)
    local files, dirs = file.Find(dir .. "/*", "LUA")

    for i = 1, #files do
        load_file(dir .. "/" .. files[i])
    end

    for i = 1, #dirs do
        load_directory(dir .. "/" .. dirs[i])
    end
end

return {
    load_directory = load_directory,
    load_file = load_file
}