--[[
	ULX Whitelist: data for the Whitelist tab in XGUI.

	XGUI includes this file on the server from lua/ulx/xgui/server/. It sends
	ULXWhitelist.List() to players with the "ulx whitelistshow" access and
	sends it again when ULib permissions change. The tab itself is
	lua/ulx/xgui/ulx_whitelist.lua.
]]

local VIEW_ACCESS = "ulx whitelistshow"
local REFRESH_TIMER = "ULXWhitelist.XGUIRefresh"
local REFRESH_DELAY = 1 -- Seconds. Groups bursts of permission changes into one update.

local lastSent -- The last list sent, as JSON, so unchanged lists are not sent again.

local function getData()
	if not ULXWhitelist then return {} end
	local list = ULXWhitelist.List()
	return { everyone = list.everyone, groups = list.groups, allowed = list.allowed, denied = list.denied }
end

local function refresh()
	if not ( ULXWhitelist and xgui.sendDataTable ) then return end

	local json = util.TableToJSON( getData() )
	if json == lastSent then return end
	lastSent = json

	-- One call per player: xgui.sendDataTable stops at the first player who isn't ready.
	for _, ply in ipairs( player.GetHumans() ) do
		if ULib.ucl.authed[ ply:UniqueID() ] and ULib.ucl.query( ply, VIEW_ACCESS ) then
			xgui.sendDataTable( ply, "whitelist" )
		end
	end
end

local function init()
	xgui.addDataType( "whitelist", getData, VIEW_ACCESS, 0, 0 )

	-- UCLChanged also fires when players join or leave, which can change names in the list.
	hook.Add( ULib.HOOK_UCLCHANGED, "ULXWhitelist.XGUI", function()
		timer.Create( REFRESH_TIMER, REFRESH_DELAY, 1, refresh )
	end )
end

xgui.addSVModule( "ulx_whitelist", init )