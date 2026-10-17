--[[
	ULX Whitelist: server side.

	While the whitelist is enabled, only players with the "ulx whitelisted"
	ULib access can join. The check runs in the CheckPassword hook, so
	rejected players are turned away before they download any content.

	ULX loads this file on the server from lua/ulx/modules/, after ULib and
	ULX. The chat and console commands are defined in
	lua/ulx/modules/sh/ulx_whitelist.lua.
]]

if not SERVER then return end

ULXWhitelist = ULXWhitelist or {}
local WL = ULXWhitelist

WL.VERSION = "1.0.0"

-- Access that lets a player join while the whitelist is on.
-- Grant it to a whole group with: ulx groupallow <group> "ulx whitelisted"
WL.ACCESS = "ulx whitelisted"

-- Admins who can run this command are told about rejected connections.
WL.MANAGE_ACCESS = "ulx whitelistid"

-- Commands registered by lua/ulx/modules/sh/ulx_whitelist.lua.
WL.COMMANDS = {
	"ulx whitelist",
	"ulx whitelistid",
	"ulx unwhitelist",
	"ulx unwhitelistid",
	"ulx whitelistcheck",
	"ulx whitelistshow",
}

local LOG_PREFIX = "[ULX Whitelist] "
local DEFAULT_MESSAGE = "You are not on this server's whitelist."
local NOTIFY_COOLDOWN = 60 -- Seconds between admin notifications about the same SteamID.
local SWEEP_TIMER = "ULXWhitelist.Sweep"
local SWEEP_DELAY = 1 -- Seconds. Groups bursts of permission changes into one sweep.


--------------------------------------------------------------------------------
-- Settings
--
-- ulx.convar creates the cvar ulx_<name> and the setting command "ulx <name>",
-- registers an access string for changing it, and ULX writes changes made in
-- game to data/ulx/config.txt so they survive a restart.
--------------------------------------------------------------------------------

local cvEnabled = ulx.convar( "whitelist_enabled", "1",
	"<0/1> - Only players with the ulx whitelisted access can join.", ULib.ACCESS_SUPERADMIN )

local cvMessage = ulx.convar( "whitelist_message", DEFAULT_MESSAGE,
	"<text> - Message shown to players who are not whitelisted.", ULib.ACCESS_SUPERADMIN )

local cvKick = ulx.convar( "whitelist_kick", "1",
	"<0/1> - Kick connected players who lose whitelist access while the whitelist is on.", ULib.ACCESS_SUPERADMIN )

local cvNotify = ulx.convar( "whitelist_notify", "1",
	"<0/1> - Tell admins who can whitelist players about rejected connections.", ULib.ACCESS_SUPERADMIN )

-- Admins and superadmins can join out of the box. ULib applies these defaults
-- only the first time it sees the access string, so changes made later in
-- XGUI or with ulx groupallow / groupdeny are kept. Keep the description text
-- unchanged between versions: when it changes and no group has the access,
-- ULib grants the defaults again.
ULib.ucl.registerAccess( WL.ACCESS, ULib.ACCESS_ADMIN,
	"Lets a player join while the whitelist is enabled", "Whitelist" )


--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Prints to the server console and appends to the ULX log file.
function WL.Log( fmt, ... )
	local msg = LOG_PREFIX .. string.format( fmt, ... )
	MsgN( msg )
	if ulx.logString then ulx.logString( msg ) end
end

function WL.IsEnabled()
	if not cvEnabled then return true end -- Fail closed.
	return cvEnabled:GetBool()
end

function WL.GetMessage()
	local msg = cvMessage and cvMessage:GetString() or ""
	if msg == "" then return DEFAULT_MESSAGE end
	return msg
end

local function kickEnabled()
	return not cvKick or cvKick:GetBool()
end

local function notifyEnabled()
	return not cvNotify or cvNotify:GetBool()
end

local function hasValue( t, value )
	for _, v in pairs( t ) do
		if v == value then return true end
	end
	return false
end

-- Same test ULib.ucl.query applies to an allow list: a plain entry or an access tag.
local function allows( allowList, access )
	return type( allowList ) == "table" and ( hasValue( allowList, access ) or allowList[ access ] ~= nil )
end

local function denies( denyList, access )
	return type( denyList ) == "table" and hasValue( denyList, access )
end

--[[
	WL.NormalizeSteamID( input ) -> "STEAM_0:X:Y" or nil

	Accepts STEAM_0:X:Y, STEAM_1:X:Y, a SteamID64 (7656119...) and [U:1:N],
	and returns the STEAM_0 form ULib uses as a user ID.
]]
function WL.NormalizeSteamID( input )
	if type( input ) ~= "string" then return nil end
	local s = input:match( "^%s*(.-)%s*$" ):upper()

	-- STEAM_X:Y:Z
	local y, z = s:match( "^STEAM_[01]:([01]):(%d+)$" )
	if y then
		local account = #z <= 10 and tonumber( z )
		if not account or account > 2147483647 or ( account == 0 and y == "0" ) then return nil end
		return string.format( "STEAM_0:%s:%d", y, account )
	end

	-- SteamID64. Too large for a Lua number, so let the engine convert it and check the round trip.
	if s:match( "^7656119%d%d%d%d%d%d%d%d%d%d$" ) then
		local steamid = util.SteamIDFrom64( s )
		if steamid and steamid ~= "STEAM_0:0:0" and util.SteamIDTo64( steamid ) == s then
			return steamid
		end
		return nil
	end

	-- SteamID3: [U:1:N]
	local n = s:match( "^%[?U:1:(%d+)%]?$" )
	if n then
		local account = #n <= 10 and tonumber( n )
		if not account or account < 1 or account > 4294967295 then return nil end
		return string.format( "STEAM_0:%d:%d", account % 2, math.floor( account / 2 ) )
	end

	return nil
end

-- Finds the ULib user entry for a SteamID the way ULib.ucl.probe does when the
-- player connects: by UniqueID, then IP, then SteamID. Returns info, key.
local function findUser( steamid, ip )
	local users = ULib.ucl.users
	local ids = { util.CRC( "gm_" .. steamid .. "_gm" ) }
	if ip and ip ~= "" then ids[ #ids + 1 ] = ip end
	ids[ #ids + 1 ] = steamid

	for _, id in ipairs( ids ) do
		if users[ id ] then return users[ id ], id end
	end
end

-- IP of a connected player with this SteamID, if any.
local function onlineIP( steamid )
	local ply = player.GetBySteamID( steamid )
	if IsValid( ply ) then return ULib.splitPort( ply:IPAddress() ) end
end

function WL.DisplayName( steamid )
	local ply = player.GetBySteamID( steamid )
	if IsValid( ply ) then return string.format( "%s (%s)", ply:Nick(), steamid ) end

	local info = findUser( steamid )
	if info and type( info.name ) == "string" and info.name ~= "" then
		return string.format( "%s (%s)", info.name, steamid )
	end
	return steamid
end


--------------------------------------------------------------------------------
-- Access check
--------------------------------------------------------------------------------

local function userGroupOf( info )
	local group = info and info.group
	if type( group ) ~= "string" or group == "" then return ULib.ACCESS_ALL end
	return group
end

-- Returns the group in the inheritance chain of group that grants the
-- whitelist access, or nil.
local function grantingGroup( group )
	local visited = {}
	while group and not visited[ group ] do
		visited[ group ] = true
		local groupInfo = ULib.ucl.groups[ group ]
		if not groupInfo then
			-- ULib creates a missing group when such a player connects, inheriting from "user".
			group = ULib.ACCESS_ALL
		elseif allows( groupInfo.allow, WL.ACCESS ) then
			return group
		else
			group = ULib.ucl.groupInheritsFrom( group )
		end
	end
end

-- Decides access for one ULib user entry, or for an unknown SteamID when info
-- is nil. Returns allowed, reason, and the granting group when a group grants it.
local function evaluate( info )
	if info then
		if denies( info.deny, WL.ACCESS ) then return false, "explicitly denied" end
		if allows( info.allow, WL.ACCESS ) then return true, "personal whitelist entry" end
	end

	local group = userGroupOf( info )
	local granting = grantingGroup( group )
	if granting then return true, string.format( "group '%s'", granting ), granting end
	return false, string.format( "not whitelisted (group '%s')", group )
end

--[[
	WL.CheckSteamID( steamid, ip ) -> allowed, reason

	Decides whether a SteamID (STEAM_0:X:Y) has the whitelist access without
	a player entity, following the same rules as ULib.ucl.query: the user's
	deny list wins, then their allow list, then their group and the groups it
	inherits from. SteamIDs ULib does not know are treated as members of
	"user". ip is optional; for a connected player it is looked up.
]]
function WL.CheckSteamID( steamid, ip )
	local allowed, reason = evaluate( findUser( steamid, ip or onlineIP( steamid ) ) )
	return allowed, reason
end

local function byName( a, b )
	local an, bn = a.name:lower(), b.name:lower()
	if an ~= bn then return an < bn end
	return a.id < b.id
end

--[[
	WL.List() -> list

	Everyone ULib knows who can join, using the same rules as WL.CheckSteamID.
	Players ULib does not know are not listed; they can join only when
	list.everyone is true.

	list.everyone  true if the "user" group has the access
	list.groups    { name, via } for each group with the access, sorted by name;
	               via is the group it inherits the access from, or nil
	list.allowed   { id, name, group, via } for each user who can join;
	               via is the granting group, or nil for a personal entry
	list.denied    { id, name, group } for each user who is explicitly denied
]]
function WL.List()
	local list = { everyone = grantingGroup( ULib.ACCESS_ALL ) ~= nil, groups = {}, allowed = {}, denied = {} }

	for name in pairs( ULib.ucl.groups ) do
		local granting = grantingGroup( name )
		if granting then
			list.groups[ #list.groups + 1 ] = { name = name, via = granting ~= name and granting or nil }
		end
	end
	table.sort( list.groups, function( a, b ) return a.name < b.name end )

	for id, info in pairs( ULib.ucl.users ) do
		local allowed, _, granting = evaluate( info )
		local entry = {
			id = id,
			name = type( info.name ) == "string" and info.name or "",
			group = userGroupOf( info ),
			via = granting,
		}
		if allowed then
			list.allowed[ #list.allowed + 1 ] = entry
		elseif denies( info.deny, WL.ACCESS ) then
			list.denied[ #list.denied + 1 ] = entry
		end
	end
	table.sort( list.allowed, byName )
	table.sort( list.denied, byName )

	return list
end

-- Used by the CheckPassword hook. Returns allowed, reason, steamid.
function WL.CheckConnection( steamID64, ipAddress )
	if not ( ULib and ULib.ucl and ULib.ucl.users and ULib.ucl.groups ) then
		return false, "ULib is not loaded"
	end

	local steamid = WL.NormalizeSteamID( steamID64 )
	if not steamid then return false, "invalid SteamID" end

	local ip = ipAddress and ULib.splitPort( ipAddress ) or ""
	local allowed, reason = WL.CheckSteamID( steamid, ip )
	return allowed, reason, steamid
end


--------------------------------------------------------------------------------
-- Managing the whitelist (used by the ULX commands)
--------------------------------------------------------------------------------

-- ULib 2.72 saves a user without a group with the group name "nil". A user
-- without a group is in "user" anyway, so say so before ULib saves the entry.
local function fixMissingGroup( key )
	local info = ULib.ucl.users[ key ]
	if info and ( type( info.group ) ~= "string" or info.group == "" ) then
		info.group = ULib.ACCESS_ALL
	end
end

--[[
	WL.Grant( steamid ) -> changed

	Adds the whitelist access to the SteamID's own ULib entry, creating the
	entry if needed, and clears an explicit deny. Returns false if the
	SteamID already had a personal whitelist entry.
]]
function WL.Grant( steamid )
	local _, key = findUser( steamid, onlineIP( steamid ) )
	if key then
		fixMissingGroup( key )
		return ULib.ucl.userAllow( key, WL.ACCESS ) == true
	end

	-- Unknown to ULib: keep the current group of a connected player, otherwise "user".
	local group = ULib.ACCESS_ALL
	local ply = player.GetBySteamID( steamid )
	if IsValid( ply ) then
		local current = ply:GetUserGroup()
		if current ~= "" and ULib.ucl.groups[ current ] then group = current end
	end

	ULib.ucl.addUser( steamid, { WL.ACCESS }, {}, group )
	return true
end

--[[
	WL.Revoke( steamid ) -> changed

	Removes the whitelist access from the SteamID's own ULib entry. The
	player may still have access through their group; WL.CheckSteamID tells.
]]
function WL.Revoke( steamid )
	local info, key = findUser( steamid, onlineIP( steamid ) )
	if not ( info and allows( info.allow, WL.ACCESS ) ) then return false end

	fixMissingGroup( key )
	return ULib.ucl.userAllow( key, WL.ACCESS, true ) == true
end


--------------------------------------------------------------------------------
-- Kicking players who lose access
--------------------------------------------------------------------------------

WL.kicked = WL.kicked or setmetatable( {}, { __mode = "k" } )

--[[
	WL.Enforce( ply ) -> kicked

	Kicks a connected player who no longer has the whitelist access, if both
	the whitelist and ulx whitelist_kick are on. Players ULib has not
	authenticated yet are left alone: CheckPassword already let them in.
]]
function WL.Enforce( ply )
	if not IsValid( ply ) or ply:IsBot() or ply:IsListenServerHost() then return false end
	if not WL.IsEnabled() or not kickEnabled() then return false end
	if WL.kicked[ ply ] then return true end
	if not ULib.ucl.authed[ ply:UniqueID() ] then return false end

	local ok, allowed = pcall( ULib.ucl.query, ply, WL.ACCESS )
	if not ok or allowed then return false end

	WL.kicked[ ply ] = true
	WL.Log( "Kicked %s (%s): no longer whitelisted", ply:Nick(), ply:SteamID() )
	ULib.kick( ply, WL.GetMessage() )
	return true
end

function WL.Sweep()
	if not WL.IsEnabled() or not kickEnabled() then return end
	for _, ply in ipairs( player.GetHumans() ) do
		WL.Enforce( ply )
	end
end

function WL.ScheduleSweep()
	timer.Create( SWEEP_TIMER, SWEEP_DELAY, 1, WL.Sweep )
end


--------------------------------------------------------------------------------
-- Notifying admins about rejected connections
--------------------------------------------------------------------------------

WL.notified = WL.notified or {}

function WL.NotifyAdmins( name, steamid )
	if not notifyEnabled() then return end

	local now = SysTime()
	for id, time in pairs( WL.notified ) do
		if now - time >= NOTIFY_COOLDOWN then WL.notified[ id ] = nil end
	end

	local key = steamid or name
	if WL.notified[ key ] then return end
	WL.notified[ key ] = now

	local msg = string.format( "%sRejected connection: %s (%s)", LOG_PREFIX, name, steamid or "invalid SteamID" )
	for _, ply in ipairs( player.GetHumans() ) do
		if ULib.ucl.authed[ ply:UniqueID() ] and ULib.ucl.query( ply, WL.MANAGE_ACCESS ) then
			ULib.tsay( ply, msg )
		end
	end
end


--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function onCheckPassword( steamID64, ipAddress, svPassword, clPassword, name )
	if not WL.IsEnabled() then return end
	name = tostring( name )

	local ok, allowed, reason, steamid = pcall( WL.CheckConnection, steamID64, ipAddress )
	if not ok then
		-- Fail closed: an error must never let an unknown player in.
		WL.Log( "Rejected %s (%s): error while checking access: %s", name, tostring( steamID64 ), tostring( allowed ) )
		return false, WL.GetMessage()
	end

	-- Return nothing for allowed players, so other hooks and sv_password still apply.
	if allowed then return end

	WL.Log( "Rejected %s (%s): %s", name, steamid or tostring( steamID64 ), reason )
	pcall( WL.NotifyAdmins, name, steamid )
	return false, WL.GetMessage()
end
hook.Add( "CheckPassword", "ULXWhitelist", onCheckPassword )

hook.Add( ULib.HOOK_UCLCHANGED, "ULXWhitelist", function()
	WL.ScheduleSweep()
end )

cvars.AddChangeCallback( "ulx_whitelist_enabled", function( _, _, newValue )
	if tobool( newValue ) then WL.ScheduleSweep() end
end, "ULXWhitelist" )

-- Runs after ULX has executed data/ulx/config.txt, so the settings are final.
hook.Add( ulx.HOOK_ULXDONELOADING, "ULXWhitelist", function()
	for _, cmd in ipairs( WL.COMMANDS ) do
		local obj = ULib.cmds.translatedCmds[ cmd ]
		if not obj then
			WL.Log( "WARNING: command '%s' is missing. Check that lua/ulx/modules/sh/ulx_whitelist.lua is installed.", cmd )
		elseif not obj.ulxWhitelist then
			WL.Log( "WARNING: command '%s' is registered by another addon (for example Wordlist Kicker for ULX). Remove one of them.", cmd )
		end
	end

	WL.Log( "v%s loaded. Whitelist is %s.", WL.VERSION, WL.IsEnabled() and "ON" or "OFF" )
end )
