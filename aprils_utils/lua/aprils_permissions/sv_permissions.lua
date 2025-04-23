local function has_access_single(ply, access, is_table)
    if type(access) == "function" then
        return access(ply)
    end

    if type(access) ~= "string" and not is_table then
        return true
    elseif type(access) ~= "string" and is_table then
        return false
    end

    local jobTable = ply:getJobTable()

    if access:StartsWith("%") then
        return access:sub(2):lower() == jobTable.command:lower()
    elseif access:StartsWith("#") then
        return access:sub(2):lower() == jobTable.category:lower()
    else
        return access == ply:GetUserGroup()
    end
end

function aprils_utils.create_grouping(group_id, group_data)
    assert(type(group_id) == "string", "Group ID must be a string!")
    assert(type(group_data) == "table", "Group data must be a table!")
    local valid_group = {}

    for _, individual_perm in ipairs(group_data) do
        if type(individual_perm) == "string" or type(individual_perm) == "function" then
            table.insert(valid_group, individual_perm)
        end
    end

    aprils_utils.groups[group_id:lower()] = group_data
end

function aprils_utils.has_access(ply, access, require_all_true)
    if type(access) ~= "table" and (type(access) == "string" and access:StartsWith("&")) or type(access) == "function" then
        return has_access_single(ply, access)
    end

    if type(access) == "string" and access:StartsWith("&") then
        if aprils_utils.groups[access:sub(2):lower()] then
            access = aprils_utils.groups[access:sub(2):lower()]
        else
            return has_access_single(ply, access)
        end
    end

    local values = #access
    local values_true = 0

    for _, value in ipairs(access) do
        local result = has_access_single(ply, value, true)

        if result then
            values_true = values_true + 1
        end
    end

    if require_all_true and (values_true == values) then
        return true
    end

    if not require_all_true and (values_true > 0) then
        return true
    end

    return false
end