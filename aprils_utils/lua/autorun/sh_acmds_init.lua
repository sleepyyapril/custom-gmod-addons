aprils_utils = aprils_utils or {}
aprils_utils.groups = aprils_utils.groups or {}
aprils_utils.registry = aprils_utils.registry or {}

alib = alib or {}
alib.loader = include("aprilslib/loader.lua")
alib.color = include("aprilslib/color.lua")

if SERVER then
    util.AddNetworkString("autils_sendcolortable")
    util.AddNetworkString("autils_sendtranslatedtext")
end

--! EXTRA - REQUIRED BY ALL
alib.loader.load_file("aprils_extra/sh_player_meta.lua")
alib.loader.load_file("aprils_extra/cl_messages.lua")

--! PERMISSIONS - REQUIRED BY COMMANDS
alib.loader.load_file("aprils_permissions/sv_permissions.lua")

--! COMMANDS
alib.loader.load_file("aprils_cmds/sh_acmds_config.lua")
alib.loader.load_file("aprils_cmds/handlers/sv_parser.lua")
alib.loader.load_file("aprils_cmds/handlers/sv_command_handler.lua")

hook.Call("autils:ready")