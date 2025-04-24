local common = (function()
local string_format = string.format
local string_gsub = string.gsub
local string_char = string.char
local string_byte = string.byte
local table_insert = table.insert
local type = type

local common = {
    VERSION = "2.5",
    NULL = {}
}
common.MAJOR_VERSION = tonumber(common.VERSION:match("(%d+)%.%d+"))

local STATES = {
    CONNECTED = 0,
    CONNECTING = 1,
    NOT_CONNECTED = 2,
    DISCONNECTED = 3,
}
common.STATES = STATES

local STATES_NAMES = {}; do
    for k, v in pairs(STATES) do
        STATES_NAMES[v] = k
    end
end
common.STATES_NAMES = STATES_NAMES

do
    local hex = function(c)
        return string_format("%02X", string_byte(c))
    end
    function common.StringToHex(text)
        return (string_gsub(text, ".", hex))
    end

    local unhex = function(cc)
        return string_char(tonumber(cc, 16))
    end
    function common.StringFromHex(text)
        return (string_gsub(text, "..", unhex))
    end
end

local SetPrivate, GetPrivate; do
    local PRIVATE_KEY = "___PRIVATE___ANNOYING_KEY_TO_STOP_PLAYING_WITH___"

    function SetPrivate(conn, key, value)
        local private = conn[PRIVATE_KEY]
        if not private then
            private = {}
            conn[PRIVATE_KEY] = private
        end
        private[key] = value
    end

    ---@return any
    function GetPrivate(conn, key)
        local private = conn[PRIVATE_KEY]
        if not private then return nil end
        return private[key]
    end
end
common.SetPrivate, common.GetPrivate = SetPrivate, GetPrivate

local ERROR_META = {
    __tostring = function(s)
        return string.format("(%s) %s", s.code or "?", s.message or "unknown error")
    end
}
common.ERROR_META = ERROR_META

common.SQLError = function(msg)
    return setmetatable({
        message = msg,
    }, ERROR_META)
end

common.CROSS_SYNTAXES = (function()
return {
    sqlite = {
        CROSS_NOW = "(CAST(strftime('%s', 'now') AS INTEGER))",
        -- INTEGER PRIMARY KEY auto increments in SQLite, see https://www.sqlite.org/autoinc.html
        CROSS_PRIMARY_AUTO_INCREMENTED = "INTEGER PRIMARY KEY",
        CROSS_COLLATE_BINARY = "COLLATE BINARY",
        CROSS_CURRENT_DATE = "DATE('now')",
        CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER))",
        CROSS_INT_TYPE = "INTEGER",
        CROSS_JSON_TYPE = "TEXT",
    },
    mysql = {
        CROSS_NOW = "(UNIX_TIMESTAMP())",
        CROSS_PRIMARY_AUTO_INCREMENTED = "BIGINT AUTO_INCREMENT PRIMARY KEY",
        CROSS_COLLATE_BINARY = "BINARY",
        CROSS_CURRENT_DATE = "CURDATE()",
        CROSS_OS_TIME_TYPE = "INT UNSIGNED NOT NULL DEFAULT (UNIX_TIMESTAMP())",
        CROSS_INT_TYPE = "BIGINT",
        CROSS_JSON_TYPE = "JSON",
    },
}

end)()

local EMPTY_PARAMS = {}
local EMPTY_OPS = {
    params = EMPTY_PARAMS,
}

---@param query string|nil
---@param opts table|nil
---@param is_async boolean|nil
---@return table
common.CheckQuery = function(query, opts, is_async)
    if type(query) ~= "string" then
        error("query must be a string", 4)
    end

    if opts == nil then
        return EMPTY_OPS
    end

    if type(opts) ~= "table" then
        error("opts must be a table", 4)
    end

    local params = opts.params
    if params == nil then
        opts.params = EMPTY_PARAMS
    elseif type(params) ~= "table" then
        error("params must be a table", 4)
    end

    if not opts.sync then
        if is_async and type(opts.callback) ~= "function" then
            error("callback must be a function", 4)
        end
    end

    return opts
end

local COMMON_META = {}

function COMMON_META:StateName() return STATES_NAMES[self:State()] end

function COMMON_META:IsConnected() return self:State() == STATES.CONNECTED end

function COMMON_META:IsConnecting() return self:State() == STATES.CONNECTING end

function COMMON_META:IsDisconnected() return self:State() == STATES.DISCONNECTED end

function COMMON_META:IsNotConnected() return self:State() == STATES.NOT_CONNECTED end

common.COMMON_META = COMMON_META

local function errorf(err, ...)
    return error(string_format(err, ...))
end
common.errorf = errorf

local function errorlevelf(level, err, ...)
    return error(string_format(err, ...))
end
common.errorlevelf = errorlevelf

common.HandleNoEscape = function(v)
    local v_type = type(v)
    if v_type == "string" then
        return "'" .. v .. "'"
    elseif v_type == "number" then
        return v
    elseif v_type == "boolean" then
        return v and "TRUE" or "FALSE"
    else
        return errorf("invalid type '%s' was passed to escape '%s'", v_type, v)
    end
end

local PARAMS_PATTERN = "{[%s]*(%d+)[%s]*}"

local HandleQueryParams; do
    local fquery_params, fquery_new_params, escape_function
    local has_matches = false
    local gsub_f = function(key, opts)
        local raw_value = fquery_params[tonumber(key)]
        if raw_value == nil then
            return errorf("missing parameter for query: %s", key)
        end

        has_matches = true

        if raw_value == common.NULL then
            return "NULL"
        end


        table_insert(fquery_new_params, raw_value)

        return (escape_function(raw_value))
    end

    local EMPTY_QUERY_PARAMS = {}
    ---@return string
    ---@return table
    function HandleQueryParams(query, params, escape_func)
        fquery_new_params = {}
        fquery_params = params
        escape_function = escape_func
        has_matches = false

        -- We don't return the query immediately as that could cause hidden bugs. We must ensure that if the developer is using
        -- placeholders, they are checked for missing parameters.
        if fquery_params == nil then
            fquery_params = EMPTY_QUERY_PARAMS
        elseif type(fquery_params) ~= "table" then
            errorlevelf(4, "params must be a table, got %s", type(fquery_params))
        end

        local new_query = (string_gsub(query, PARAMS_PATTERN, gsub_f))

        -- if nothing matched, just return params as s
        if not has_matches then
            return query, params
        end

        return new_query, fquery_new_params
    end
end
common.HandleQueryParams = HandleQueryParams

return common

end)(); local _COMMON_MAIN_ = common;
local RunMigrations = (function()
local fmt = string.format

local function is_ascii(s)
    return not s:match("[\128-\255]") -- Match any byte outside the ASCII range (0-127)
end

local function preprocess(text, defines)
    for k, v in pairs(defines) do
        defines[k:upper()] = v
    end

    local output = {}
    local state_stack = {}
    local active = true

    for line in text:gmatch("([^\n]*)\n?") do
        local macro = line:match("^%s*%-%-@ifdef%s+(%w+)")
        if macro then
            macro = macro:upper()
            table.insert(state_stack, active)
            active = active and (defines[macro] == true)
        elseif line:match("^%s*%-%-@else%s*$") then
            if #state_stack == 0 then
                return error("Unexpected --@else without matching --@ifdef")
            end
            local parentActive = state_stack[#state_stack]
            active = parentActive and not active
        elseif line:match("^%s*%-%-@endif%s*$") then
            if #state_stack == 0 then
                return error("Unexpected --@endif without matching --@ifdef")
            end
            active = table.remove(state_stack)
        else
            if active then
                table.insert(output, line)
            end
        end
    end

    if #state_stack > 0 then
        return error("Missing --@endif: " .. #state_stack .. " --@ifdef directives were not closed")
    end

    return table.concat(output, "\n")
end

local function RunMigrations(conn, migrations, ...)
    local addon_name = conn.options.addon_name

    assert(type(migrations) == "table", "migrations must be an array sorted by version")
    assert(type(addon_name) == "string", "addon_name must be supplied to connection options")
    assert(addon_name ~= "", "addon_name cannot be empty")
    assert(is_ascii(addon_name), "addon_name must be ascii only")

    local TABLE_NAME = fmt("goobie_sql_migrations_version_%s", addon_name)

    local current_version = 0
    local old_version = 0

    do
        local err = conn:RunSync(fmt([[
            CREATE TABLE IF NOT EXISTS %s (
                `id` TINYINT PRIMARY KEY,
                `version` MEDIUMINT UNSIGNED NOT NULL
            )
        ]], TABLE_NAME))
        if err then
            return error(fmt("Failed to create migrations table: %s", err))
        end
    end

    local first_run = false
    do
        local err, res = conn:FetchOneSync(fmt([[
            SELECT `version` FROM %s
        ]], TABLE_NAME))
        if err then
            return error(fmt("Failed to fetch migrations version: %s", err))
        end
        -- if nothing was returned, then the table didn't exist
        if res then
            local version = tonumber(res.version)
            if type(version) == "number" then
                current_version = version
            else
                return error(fmt("Migrations table is corrupted, version is not a number"))
            end
        else
            first_run = true
        end
    end

    old_version = current_version

    -- make sure that migrations has UP, DOWN and version
    for _, migration in ipairs(migrations) do
        assert(type(migration) == "table", "migrations must be an array of tables")
        assert(type(migration.UP) == "function" or type(migration.UP) == "string",
            "migration `UP` must be a function or string")
        assert(type(migration.DOWN) == "function" or type(migration.DOWN) == "string",
            "migration `DOWN` must be a function or string")
    end

    local function process(query)
        local defines = {}
        if conn:IsMySQL() then
            defines["mysql"] = true
        else
            defines["sqlite"] = true
        end
        query = preprocess(query, defines)
        local err = conn:RunSync(query, { raw = true })
        if err then
            return error(tostring(err))
        end
    end

    local applied_migrations = {}
    local function revert_migrations(...)
        for idx, migration in ipairs(applied_migrations) do
            local success
            if type(migration.DOWN) == "function" then
                success = ProtectedCall(migration.DOWN, process, conn, ...)
            else
                success = ProtectedCall(process, migration.DOWN)
            end
            if not success then
                return error("failed to revert #" .. idx .. " migration")
            end
        end
    end

    for idx, migration in ipairs(migrations) do
        if idx <= current_version then
            goto _continue_
        end

        local success
        if type(migration.UP) == "function" then
            success = ProtectedCall(migration.UP, process, conn, ...)
        else
            success = ProtectedCall(process, migration.UP)
        end
        if not success then
            revert_migrations(...)
            return error("failed to apply migration: " .. idx)
        end

        applied_migrations[idx] = migration
        current_version = idx
        ::_continue_::
    end

    conn:RunSync(fmt([[
        REPLACE INTO %s (`id`, `version`) VALUES (1, %d);
    ]], TABLE_NAME, current_version))

    return old_version, current_version, first_run
end

return RunMigrations

end)()

local goobie_sql = {
    NULL = common.NULL,
    STATES = common.STATES,

    VERSION = common.VERSION,
    MAJOR_VERSION = common.MAJOR_VERSION,
}

local goobie_sqlite
local goobie_mysql

function goobie_sql.NewConn(opts, on_connected)
    if type(opts) ~= "table" then
        return error("opts must be a table")
    end

    local conn
    if opts.driver == "mysql" then
        if goobie_mysql == nil then
            goobie_mysql = (function()
local common = _COMMON_MAIN_
local ConnBegin = (function()
local common = _COMMON_MAIN_

local coroutine = coroutine

local CheckQuery = common.CheckQuery

local Txn = {}
local Txn_MT = { __index = Txn }

-- mysql does not support begin/commit/rollback using prepared statements
local IS_RAW = { raw = true }

local function NewTransaction(conn, co, traceback)
    return setmetatable({
        conn = conn,
        conn_id = conn:ID(),
        co = co,
        traceback = traceback,
        open = true,
    }, Txn_MT)
end

local TxnQuery, TxnFinalize

local function TxnResume(txn, ...)
    local co = txn.co
    local err

    local co_status = coroutine.status(co)
    if co_status == "dead" then
        if txn.open then
            err = "transaction was left open!" .. txn.traceback
        end
    else
        local success, co_err = coroutine.resume(co, ...)
        if success then
            if coroutine.status(co) == "dead" and txn.open then
                err = "transaction was left open!" .. txn.traceback
            end
        else
            err = co_err .. "\n" .. debug.traceback(co)
        end
    end

    if err then
        ErrorNoHalt(err, "\n")
        TxnFinalize(txn, "rollback", true)
    end
end

function TxnQuery(txn, query_type, query, opts)
    opts = CheckQuery(query, opts)

    if not txn.open then
        return error("transaction is closed")
    end

    local conn = txn.conn
    -- we need to set locked to false to make sure queries are not queued
    -- it's not an issue if it errors or not because TxnResume will handle it anyway

    opts.callback = function(err, res)
        TxnResume(txn, err, res)
    end

    common.SetPrivate(conn, "locked", false)
    conn[query_type](conn, query, opts)
    common.SetPrivate(conn, "locked", true)

    return coroutine.yield()
end

function TxnFinalize(txn, action, failed)
    if not txn.open then
        return
    end

    local conn = txn.conn
    common.SetPrivate(conn, "locked", false)

    local err
    -- if the connection dropped/lost/reconnected, we don't want to send a query
    -- because we are not in a transaction anymore
    if conn:IsConnected() and txn.conn_id == conn:ID() then
        if failed then
            conn:Run("ROLLBACK;", IS_RAW) -- we don't care about the result
        else
            if action == "commit" then
                err = TxnQuery(txn, "Run", "COMMIT;", IS_RAW)
            elseif action == "rollback" then
                err = TxnQuery(txn, "Run", "ROLLBACK;", IS_RAW)
            end
        end

        common.SetPrivate(conn, "locked", false) -- TxnQuery will set it back to true
    end

    txn.open = false

    -- cleanup

    common.SetPrivate(conn, "txn", nil)
    txn.conn = nil
    txn.co = nil
    common.SetPrivate(conn, "locked", false)
    common.GetPrivate(conn, "ConnProcessQueue")(conn)

    return err
end

function Txn:IsOpen() return self.open end

function Txn:Ping()
    if not self.open then
        return error("transaction is closed")
    end
    return self.conn:Ping(function(err, latency)
        TxnResume(self, err, latency)
    end)
end

function Txn:Run(query, opts)
    return TxnQuery(self, "Run", query, opts)
end

function Txn:Execute(query, opts)
    return TxnQuery(self, "Execute", query, opts)
end

function Txn:FetchOne(query, opts)
    return TxnQuery(self, "FetchOne", query, opts)
end

function Txn:Fetch(query, opts)
    return TxnQuery(self, "Fetch", query, opts)
end

function Txn:Commit()
    return TxnFinalize(self, "commit")
end

function Txn:Rollback()
    return TxnFinalize(self, "rollback")
end

local function ConnBegin(conn, callback, sync)
    if type(callback) ~= "function" then
        return error("callback must be a function")
    end

    local traceback = debug.traceback("", 2)
    local callback_done = false
    conn:Run("START TRANSACTION;", {
        raw = true,
        callback = function(err)
            callback_done = true

            common.SetPrivate(conn, "locked", true)

            local co = coroutine.create(callback)
            local txn = NewTransaction(conn, co, traceback)
            common.SetPrivate(conn, "txn", txn)

            if err then
                txn.open = false
                TxnResume(txn, err)
            else
                TxnResume(txn, nil, txn)
            end

            -- this is a nice way to make it easier to use sync transactions lol
            if sync then
                while txn.open do
                    conn:Poll()
                end
            end
        end,
    })

    if sync then
        while not callback_done do
            conn:Poll()
        end
    end
end


return ConnBegin

end)()

local MAJOR_VERSION = common.MAJOR_VERSION
local goobie_mysql; if MAJOR_VERSION then
    local goobie_mysql_version = "goobie_mysql_" .. MAJOR_VERSION
    if not util.IsBinaryModuleInstalled(goobie_mysql_version) then
        common.errorf(
            "'%s' module doesn't exist, get it from https://github.com/Srlion/goobie-sql/releases/tag/%s",
            goobie_mysql_version, common.VERSION)
    end

    require("goobie_mysql_" .. MAJOR_VERSION)
    goobie_mysql = _G["goobie_mysql_" .. MAJOR_VERSION]
else
    _G["require"]("goobie_mysql")
    goobie_mysql = _G["goobie_mysql"]
end
if goobie_mysql.lua_loaded then return goobie_mysql end -- lua part loaded already
goobie_mysql.lua_loaded = true

local type = type
local tostring = tostring
local CheckQuery = common.CheckQuery
local table_HasValue = table.HasValue
local table_concat = table.concat
local table_insert = table.insert
local string_format = string.format
local errorf = common.errorf
local string_gsub = string.gsub

local CROSS_SYNTAXES = common.CROSS_SYNTAXES.mysql

goobie_mysql.ERROR_META = common.ERROR_META

local Conn = goobie_mysql.CONN_META

local QUERIES = {
    Run = Conn.Run,
    Execute = Conn.Execute,
    FetchOne = Conn.FetchOne,
    Fetch = Conn.Fetch,
}

for k, v in pairs(common.COMMON_META) do
    Conn[k] = v
end

local function ConnSyncOP(conn, op)
    local done
    local err, res
    op(function(e, r)
        done = true
        err, res = e, r
    end)
    while not done do
        conn:Poll()
    end
    return err, res
end

local function ConnQueueTask(conn, func, p1, p2, p3)
    if common.GetPrivate(conn, "locked") then
        local txn = common.GetPrivate(conn, "txn")
        if txn and txn.open and coroutine.running() == txn.co then
            return error("you can't run queries on a `connection` inside an open transaction's coroutine", 2)
        end
        local queue = common.GetPrivate(conn, "queue")
        queue[#queue + 1] = { func, p1, p2, p3 }
    else
        func(conn, p1, p2, p3)
    end
end

local function ConnProcessQueue(conn)
    if common.GetPrivate(conn, "locked") then return end -- we can't process if connection is query locked

    ---@type table
    local queue = common.GetPrivate(conn, "queue")
    local queue_len = #queue
    if queue_len == 0 then return end

    common.SetPrivate(conn, "queue", {}) -- make sure to clear the queue to avoid conflicts

    for i = 1, queue_len do
        local task = queue[i]
        -- we call QueueTask again because a task can be a Transaction Begin
        local func = task[1]
        ConnQueueTask(conn, func, task[2], task[3], task[4])
    end
end

function Conn:IsMySQL() return true end

function Conn:IsSQLite() return false end

function Conn:StartSync()
    local err = ConnSyncOP(self, function(cb)
        self:Start(cb)
    end)
    if err then
        return error(tostring(err))
    end
end

function Conn:DisconnectSync()
    local err = ConnSyncOP(self, function(cb)
        self:Disconnect(cb)
    end)
    return err
end

function Conn:PingSync()
    local done, err, res
    self:Ping(function(e, r)
        done = true
        err, res = e, r
    end)
    while not done do
        self:Poll()
    end
    return err, res
end

local ESCAPE_TYPES = {
    ["string"] = true,
    ["number"] = true,
    ["boolean"] = true,
}
local function escape_function(value)
    if ESCAPE_TYPES[type(value)] then
        return "?"
    else
        return errorf("invalid type '%s' was passed to escape '%s'", type(value), value)
    end
end
local function prepare_query(query, opts, is_async)
    opts = CheckQuery(query, opts, is_async)
    query = string_gsub(query, "{([%w_]+)}", CROSS_SYNTAXES)
    local params = opts.params
    if not opts.raw then -- raw queries can't be escaped in sqlx, hopefully they expose an escape function
        query, params = common.HandleQueryParams(query, params, escape_function)
    end
    opts.params = params
    return query, opts
end

local function create_query_method(query_type)
    local query_func = QUERIES[query_type]

    Conn[query_type] = function(self, query, opts)
        query, opts = prepare_query(query, opts, true)
        if opts.sync then
            return ConnSyncOP(self, function(cb)
                opts.callback = cb
                ConnQueueTask(self, query_func, query, opts)
            end)
        else
            ConnQueueTask(self, query_func, query, opts)
        end
    end

    Conn[query_type .. "Sync"] = function(self, query, opts)
        query, opts = prepare_query(query, opts)
        return ConnSyncOP(self, function(cb)
            opts.callback = cb
            ConnQueueTask(self, query_func, query, opts)
        end)
    end
end

create_query_method("Run")
create_query_method("Execute")
create_query_method("Fetch")
create_query_method("FetchOne")

-- someone could ask, why the hell is this function synchronous? because for obvious reasons,
-- you use this function when setting up your server, so it's not a big deal if it's synchronous
function Conn:TableExists(name)
    if type(name) ~= "string" then
        return error("table name must be a string")
    end
    local err, data = self:FetchOneSync("SHOW TABLES LIKE '" .. name .. "'")
    if err then
        return nil, err
    end
    return data ~= nil
end

do
    local query_count = 0
    local query_parts = {}

    local function insert_to_query(str)
        query_count = query_count + 1
        query_parts[query_count] = str
    end

    local function ConnUpsertQuery(conn, tbl_name, opts, sync)
        if type(tbl_name) ~= "string" then
            return error("table name must be a string")
        end

        query_count = 0

        -- mysql doesn't use primary keys, so we don't need to check for them to keep consistency with sqlite
        if not opts.primary_keys then
            return error("upsert query must have primary_keys")
        end

        local inserts = opts.inserts
        local updates = opts.updates
        local no_escape_columns = opts.no_escape_columns

        local params = { nil, nil, nil, nil, nil, nil }
        local values = { nil, nil, nil, nil, nil, nil }

        -- INSERT INTO `tbl_name`(`column1`, ...) VALUES(?, ?, ...) ON DUPLICATE KEY UPDATE `column1`=VALUES(`column1`), ...
        insert_to_query("INSERT INTO`")
        insert_to_query(tbl_name)
        insert_to_query("`(")

        for column, value in pairs(inserts) do
            insert_to_query("`" .. column .. "`")
            insert_to_query(",")
            if no_escape_columns and table_HasValue(no_escape_columns, column) then
                table_insert(values, common.HandleNoEscape(value))
            else
                table_insert(values, "?")
                table_insert(params, value)
            end
        end
        query_count = query_count - 1 -- remove last comma

        insert_to_query(")VALUES(")
        insert_to_query(table_concat(values, ","))
        insert_to_query(")ON DUPLICATE KEY UPDATE")

        -- basically, if there are no updates, we just update the first column with itself
        if updates == nil or #updates == 0 then
            local next_key = next(inserts)
            updates = { next_key }
        end

        for i = 1, #updates do
            local column = updates[i]
            insert_to_query(string_format("`%s`=VALUES(`%s`)", column, column))
            insert_to_query(",")
        end
        query_count = query_count - 1 -- remove last comma

        local query = table_concat(query_parts, nil, 1, query_count)

        if opts.return_query then
            return query, params
        end

        opts.params = params

        if sync then
            local err, res = conn:ExecuteSync(query, opts)
            return err, res
        else
            local err, res = conn:Execute(query, opts)
            return err, res
        end
    end

    function Conn:UpsertQuery(tbl_name, opts)
        return ConnUpsertQuery(self, tbl_name, opts, false)
    end

    function Conn:UpsertQuerySync(tbl_name, opts)
        return ConnUpsertQuery(self, tbl_name, opts, true)
    end
end

function Conn:Begin(callback)
    return ConnBegin(self, callback, false)
end

function Conn:BeginSync(callback)
    return ConnBegin(self, callback, true)
end

local RealNewConn = goobie_mysql.NewConn
function goobie_mysql.NewConn(opts)
    local conn = RealNewConn(opts)
    common.SetPrivate(conn, "queue", {})
    common.SetPrivate(conn, "ConnProcessQueue", ConnProcessQueue)
    return conn
end

return goobie_mysql

end)()
            if not goobie_mysql then
                return error("failed to load mysql binary module")
            end
        end
        conn = goobie_mysql.NewConn(opts)
    elseif opts.driver == "sqlite" then
        if goobie_sqlite == nil then
            goobie_sqlite = (function()
local common = _COMMON_MAIN_
local ConnBeginSync = (function()
local setmetatable = setmetatable

local Txn = {}
local Txn_MT = { __index = Txn }

local function NewTransaction(conn)
    local txn = setmetatable({
        open = true,
        conn = conn,
        options = conn.options,
    }, Txn_MT)
    return txn
end

function Txn:IsOpen() return self.open end

function Txn:PingSync()
    return self.conn:PingSync()
end

function Txn:Ping(callback)
    return self.conn:Ping(callback)
end

function Txn:Run(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:RunSync(query, opts)
end

function Txn:Execute(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:ExecuteSync(query, opts)
end

function Txn:Fetch(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:FetchSync(query, opts)
end

function Txn:FetchOne(query, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    opts = opts or {}
    opts.sync = true
    return self.conn:FetchOneSync(query, opts)
end

function Txn:TableExists(name)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:TableExists(name)
end

function Txn:UpsertQuery(tbl_name, opts)
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    return self.conn:UpsertQuerySync(tbl_name, opts)
end

function Txn:Commit()
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    self.open = false
    local err = self.conn:RunSync("COMMIT TRANSACTION")
    if err then
        self.conn:RunSync("ROLLBACK TRANSACTION")
    end
    return err
end

function Txn:Rollback()
    if not self:IsOpen() then
        return error("transaction is closed")
    end
    self.open = false
    local err = self.conn:RunSync("ROLLBACK TRANSACTION")
    return err
end

local function ConnBeginSync(conn, callback)
    local status, err

    local txn = NewTransaction(conn)
    -- if creating the transaction fails, do not rollback
    local should_rollback = true
    -- this probably will only error when you try to begin a transaction inside another transaction
    err = conn:RunSync("BEGIN TRANSACTION")
    if err then
        txn.open = false
        should_rollback = false
    end

    status, err = pcall(callback, err, txn)
    if status ~= true then
        if should_rollback and txn:IsOpen() then
            txn:Rollback()
        end
        ErrorNoHaltWithStack(err)
        return
    end

    if txn:IsOpen() then
        ErrorNoHaltWithStack("transactions was left open!\n")
        txn:Rollback()
    end
end

return ConnBeginSync

end)()

local STATES = common.STATES

local type = type
local tostring = tostring
local tonumber = tonumber
local setmetatable = setmetatable
local table_insert = table.insert
local string_format = string.format
local table_HasValue = table.HasValue
local table_concat = table.concat
local errorf = common.errorf
local CheckQuery = common.CheckQuery
local string_gsub = string.gsub

local CROSS_SYNTAXES = common.CROSS_SYNTAXES.sqlite

local goobie_sqlite = {}

local Conn = {}
for k, v in pairs(common.COMMON_META) do
    Conn[k] = v
end

function Conn:IsMySQL() return false end

function Conn:IsSQLite() return true end

function Conn:State() return common.GetPrivate(self, "state") end

-- we delay async start in sqlite to be close as possible to mysql behaviour
function Conn:Start(callback)
    if type(callback) ~= "function" then
        return error("callback needs to be a function")
    end

    if self:State() == STATES.CONNECTING then
        return
    end

    common.SetPrivate(self, "state", STATES.CONNECTING)

    timer.Simple(0, function()
        common.SetPrivate(self, "state", STATES.CONNECTED)
        callback()
    end)
end

function Conn:StartSync()
    common.SetPrivate(self, "state", STATES.CONNECTED)
end

function Conn:Disconnect(callback)
    if type(callback) ~= "function" then
        return error("callback needs to be a function")
    end
    common.SetPrivate(self, "state", STATES.DISCONNECTED)
    callback()
end

function Conn:DisconnectSync()
    common.SetPrivate(self, "state", STATES.DISCONNECTED)
end

function Conn:ID() return 1 end

function Conn:Host() return "localhost" end

function Conn:Port() return 0 end

function Conn:Ping(callback)
    if type(callback) ~= "function" then
        return error("callback needs to be a function")
    end
    callback(nil, 0)
end

function Conn:PingSync()
    return nil, 0
end

local sqlite_SQLStr = sql.SQLStr
local escape_function = function(value)
    local value_type = type(value)
    if value_type == "string" then
        return (sqlite_SQLStr(value))
    elseif value_type == "number" then
        return tostring(value)
    elseif value_type == "boolean" then
        return value and "TRUE" or "FALSE"
    else
        return errorf("invalid type '%s' was passed to escape '%s'", value_type, value)
    end
end
local function prepare_query(query, opts, is_async)
    opts = CheckQuery(query, opts, is_async)
    query = string_gsub(query, "{([%w_]+)}", CROSS_SYNTAXES)
    local params = opts.params
    if not opts.raw then
        query, params = common.HandleQueryParams(query, params, escape_function)
    end
    opts.params = params
    return query, opts
end

local sqlite_Query = sql.Query
local sqlite_LastError = sql.LastError
local function raw_query(query)
    local res = sqlite_Query(query)
    if res == false then
        local last_error = sqlite_LastError()
        local err = common.SQLError(last_error)
        return err
    end
    return nil, res
end

local function ConnProcessQuery(conn, query, opts, async, exec_func)
    query, opts = prepare_query(query, opts, async)
    if opts.sync then
        async = false
    end
    local err, res = exec_func(query)
    if err then
        local on_error = conn.on_error
        if on_error then
            ProtectedCall(on_error, err)
        end
    end
    if async then
        if opts.callback then
            opts.callback(err, res)
        end
    else
        return err, res
    end
end

function Conn:RunSync(query, opts)
    return ConnProcessQuery(self, query, opts, false, raw_query)
end

function Conn:Run(query, opts)
    return ConnProcessQuery(self, query, opts, true, raw_query)
end

do
    local function internal_execute(query)
        local err = raw_query(query)
        if err then return err end
        local info = sqlite_Query("SELECT last_insert_rowid() AS `last_insert_id`, changes() AS `rows_affected`;")
        info = info[1]
        local res = {
            last_insert_id = tonumber(info.last_insert_id),
            rows_affected = tonumber(info.rows_affected),
        }
        return nil, res
    end

    function Conn:ExecuteSync(query, opts)
        return ConnProcessQuery(self, query, opts, false, internal_execute)
    end

    function Conn:Execute(query, opts)
        return ConnProcessQuery(self, query, opts, true, internal_execute)
    end
end

do
    local function internal_fetch(query)
        local err, res = raw_query(query)
        if err then return err end
        return nil, res or {}
    end

    function Conn:FetchSync(query, opts)
        return ConnProcessQuery(self, query, opts, false, internal_fetch)
    end

    function Conn:Fetch(query, opts)
        return ConnProcessQuery(self, query, opts, true, internal_fetch)
    end
end

do
    local function internal_fetch_one(query)
        local err, res = raw_query(query)
        if err then return err end
        return nil, res and res[1] or nil
    end

    function Conn:FetchOneSync(query, opts)
        return ConnProcessQuery(self, query, opts, false, internal_fetch_one)
    end

    function Conn:FetchOne(query, opts)
        return ConnProcessQuery(self, query, opts, true, internal_fetch_one)
    end
end

function Conn:TableExists(name)
    if type(name) ~= "string" then
        return error("table name must be a string")
    end
    local err, res = raw_query("SELECT name FROM sqlite_master WHERE name=" .. sqlite_SQLStr(name) .. " AND type='table'")
    if err then
        return nil, err
    end
    return res ~= nil
end

do
    local query_count = 0
    local query_parts = {}

    local function insert_to_query(str)
        query_count = query_count + 1
        query_parts[query_count] = str
    end

    local function ConnUpsertQuery(conn, tbl_name, opts, sync)
        if type(tbl_name) ~= "string" then
            return error("table name must be a string")
        end

        query_count = 0

        local primary_keys = opts.primary_keys
        local inserts = opts.inserts
        local updates = opts.updates
        local no_escape_columns = opts.no_escape_columns
        local binary_columns = opts.binary_columns

        local values = { nil, nil, nil, nil, nil, nil }

        insert_to_query("INSERT INTO`")
        insert_to_query(tbl_name)
        insert_to_query("`(")

        for column, value in pairs(inserts) do
            insert_to_query("`" .. column .. "`")
            insert_to_query(",")
            if no_escape_columns and table_HasValue(no_escape_columns, column) then
                table_insert(values, common.HandleNoEscape(value))
            elseif binary_columns and table_HasValue(binary_columns, column) then
                value = common.StringToHex(value)
                table_insert(values, "X'" .. value .. "'")
            else
                table_insert(values, sqlite_SQLStr(value))
            end
        end
        query_count = query_count - 1 -- remove last comma

        insert_to_query(")VALUES(")
        insert_to_query(table_concat(values, ","))
        insert_to_query(")ON CONFLICT(")

        for i = 1, #primary_keys do
            insert_to_query("`" .. primary_keys[i] .. "`")
            insert_to_query(",")
        end
        query_count = query_count - 1 -- remove last comma

        if updates == nil or #updates == 0 then
            insert_to_query(")DO NOTHING")
        else
            insert_to_query(")DO UPDATE SET ")

            for i = 1, #updates do
                local column = updates[i]
                insert_to_query(string_format("`%s`=excluded.`%s`", column, column))
                insert_to_query(",")
            end

            query_count = query_count - 1 -- remove last comma
        end

        local query = table_concat(query_parts, nil, 1, query_count)

        if opts.return_query then
            return query, {}
        end

        if sync then
            local err, res = conn:ExecuteSync(query, opts)
            return err, res
        else
            local err, res = conn:Execute(query, opts)
            return err, res
        end
    end

    function Conn:UpsertQuery(tbl_name, opts)
        return ConnUpsertQuery(self, tbl_name, opts, false)
    end

    function Conn:UpsertQuerySync(tbl_name, opts)
        return ConnUpsertQuery(self, tbl_name, opts, true)
    end
end

function Conn:BeginSync(callback)
    return ConnBeginSync(self, callback)
end

Conn.Begin = Conn.BeginSync

function goobie_sqlite.NewConn(opts)
    local conn = setmetatable({}, {
        __index = Conn,
        __tostring = function()
            return "Goobie SQLite Connection"
        end
    })
    common.SetPrivate(conn, "state", STATES.NOT_CONNECTED)
    return conn
end

return goobie_sqlite

end)()
        end
        conn = goobie_sqlite.NewConn(opts)
    else
        return error("invalid driver '%s'", opts.driver)
    end

    conn.options = opts
    conn.on_error = opts.on_error

    if on_connected then
        conn:Start(on_connected)
    else
        conn:StartSync()
    end

    conn.RunMigrations = RunMigrations

    return conn
end

return goobie_sql
