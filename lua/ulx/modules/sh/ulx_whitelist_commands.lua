--[[
	ULX Whitelist: commands.

	ULX loads this file on the server and on clients from lua/ulx/modules/sh/,
	so the commands appear in autocomplete and XGUI. The callbacks run on the
	server only and use ULXWhitelist from lua/ulx/modules/ulx_whitelist.lua.

	ulx whitelist <player>          !whitelist
	ulx whitelistid <steamid>       !whitelistid
	ulx unwhitelist <player>        !unwhitelist
	ulx unwhitelistid <steamid>     !unwhitelistid
	ulx whitelistcheck <steamid>    !whitelistcheck

	<steamid> can be STEAM_0:X:Y, STEAM_1:X:Y, a SteamID64 or [U:1:N].
]]

local CATEGORY_NAME = "Whitelist"
local STEAMID_HINT = "SteamID or SteamID64"
local BAD_STEAMID = "Invalid SteamID. Use STEAM_0:X:Y, a SteamID64 (7656119...) or [U:1:N]."

-- The server part is a server module, so ULX has loaded it before this file.
if SERVER and not ULXWhitelist then
	MsgN( "[ULX Whitelist] ERROR: lua/ulx/modules/ulx_whitelist.lua did not load. Whitelist commands will not work." )
end

-- Sends a message to the caller only: chat for players, console for the server.
local function reply( calling_ply, msg, isError )
	if calling_ply == nil then MsgN( msg ) return end -- Never broadcast by accident.
	if isError then
		ULib.tsayError( calling_ply, msg, true )
	else
		ULib.tsay( calling_ply, msg, true )
	end
end

-- Registers a ULX command that hides its chat line. unsafe commands, like ULX's
-- own user management, cannot be run from config files or other ULib exec calls.
-- The ulxWhitelist mark lets the server spot name clashes with other addons.
local function register( command, fn, sayCommand, unsafe )
	local cmd = ulx.command( CATEGORY_NAME, command, fn, sayCommand, true, false, unsafe )
	cmd.ulxWhitelist = true
	return cmd
end

local function grant( calling_ply, steamid, target_ply )
	if not ULXWhitelist.Grant( steamid ) then
		reply( calling_ply, ULXWhitelist.DisplayName( steamid ) .. " is already on the whitelist.", true )
		return false
	end

	if target_ply then
		ulx.fancyLogAdmin( calling_ply, true, "#A added #T to the whitelist", target_ply )
	else
		ulx.fancyLogAdmin( calling_ply, true, "#A added #s to the whitelist", ULXWhitelist.DisplayName( steamid ) )
	end
end

local function revoke( calling_ply, steamid, target_ply )
	local name = ULXWhitelist.DisplayName( steamid )
	local changed = ULXWhitelist.Revoke( steamid )

	if changed then
		if target_ply then
			ulx.fancyLogAdmin( calling_ply, true, "#A removed #T from the whitelist", target_ply )
		else
			ulx.fancyLogAdmin( calling_ply, true, "#A removed #s from the whitelist", name )
		end
	end

	local allowed, reason = ULXWhitelist.CheckSteamID( steamid )
	if allowed then
		reply( calling_ply, string.format( "%s can still join through %s. To block them: ulx userdenyid %s \"%s\"",
			name, reason, steamid, ULXWhitelist.ACCESS ), true )
	elseif not changed then
		reply( calling_ply, name .. " is not on the whitelist.", true )
		return false
	else
		local ply = player.GetBySteamID( steamid )
		if IsValid( ply ) and ULXWhitelist.Enforce( ply ) then
			reply( calling_ply, name .. " was kicked from the server." )
		end
	end
end

local function toSteamID( calling_ply, id )
	local steamid = ULXWhitelist.NormalizeSteamID( id )
	if not steamid then reply( calling_ply, BAD_STEAMID, true ) end
	return steamid
end

local function notBot( calling_ply, target_ply )
	if target_ply:IsBot() then
		reply( calling_ply, "Bots cannot be whitelisted.", true )
		return false
	end
	return true
end


------------------------------ Whitelist ------------------------------
function ulx.whitelist( calling_ply, target_ply )
	if not notBot( calling_ply, target_ply ) then return false end
	return grant( calling_ply, target_ply:SteamID(), target_ply )
end
local whitelist = register( "ulx whitelist", ulx.whitelist, "!whitelist", true )
whitelist:addParam{ type=ULib.cmds.PlayerArg }
whitelist:defaultAccess( ULib.ACCESS_SUPERADMIN )
whitelist:help( "Adds a connected player to the whitelist." )


------------------------------ Whitelist ID ------------------------------
function ulx.whitelistid( calling_ply, id )
	local steamid = toSteamID( calling_ply, id )
	if not steamid then return false end
	return grant( calling_ply, steamid )
end
local whitelistid = register( "ulx whitelistid", ulx.whitelistid, "!whitelistid", true )
whitelistid:addParam{ type=ULib.cmds.StringArg, hint=STEAMID_HINT }
whitelistid:defaultAccess( ULib.ACCESS_SUPERADMIN )
whitelistid:help( "Adds a SteamID to the whitelist." )


------------------------------ Unwhitelist ------------------------------
function ulx.unwhitelist( calling_ply, target_ply )
	if not notBot( calling_ply, target_ply ) then return false end
	return revoke( calling_ply, target_ply:SteamID(), target_ply )
end
local unwhitelist = register( "ulx unwhitelist", ulx.unwhitelist, "!unwhitelist", true )
unwhitelist:addParam{ type=ULib.cmds.PlayerArg }
unwhitelist:defaultAccess( ULib.ACCESS_SUPERADMIN )
unwhitelist:help( "Removes a connected player from the whitelist." )


------------------------------ Unwhitelist ID ------------------------------
function ulx.unwhitelistid( calling_ply, id )
	local steamid = toSteamID( calling_ply, id )
	if not steamid then return false end
	return revoke( calling_ply, steamid )
end
local unwhitelistid = register( "ulx unwhitelistid", ulx.unwhitelistid, "!unwhitelistid", true )
unwhitelistid:addParam{ type=ULib.cmds.StringArg, hint=STEAMID_HINT }
unwhitelistid:defaultAccess( ULib.ACCESS_SUPERADMIN )
unwhitelistid:help( "Removes a SteamID from the whitelist." )


------------------------------ Whitelist Check ------------------------------
function ulx.whitelistcheck( calling_ply, id )
	local steamid = toSteamID( calling_ply, id )
	if not steamid then return false end

	local allowed, reason = ULXWhitelist.CheckSteamID( steamid )
	local state = ULXWhitelist.IsEnabled() and "" or " The whitelist is currently off."
	reply( calling_ply, string.format( "%s %s: %s.%s", ULXWhitelist.DisplayName( steamid ),
		allowed and "can join" or "cannot join", reason, state ) )
end
local whitelistcheck = register( "ulx whitelistcheck", ulx.whitelistcheck, "!whitelistcheck" )
whitelistcheck:addParam{ type=ULib.cmds.StringArg, hint=STEAMID_HINT }
whitelistcheck:defaultAccess( ULib.ACCESS_ADMIN )
whitelistcheck:help( "Shows whether a SteamID can join and why." )