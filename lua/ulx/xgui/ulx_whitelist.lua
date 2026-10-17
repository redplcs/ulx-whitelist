--[[
	ULX Whitelist: the Whitelist tab in XGUI.

	XGUI loads this file on clients from lua/ulx/xgui/. The list comes from
	lua/ulx/xgui/server/sv_ulx_whitelist.lua. Every change runs the matching
	ULX command, so access checks, logging and kicks work exactly as they do
	from chat or the console.
]]

local ACCESS = "ulx whitelisted"
local SEARCH_HINT = "Search..."

xgui.prepareDataType( "whitelist" )

local wl = xlib.makepanel{ parent=xgui.null }
local filter = ""

local function can( access )
	local ply = LocalPlayer()
	if not IsValid( ply ) then return false end
	local ok, allowed = pcall( ply.query, ply, access ) -- ULib errors if the player isn't authed yet.
	return ok and allowed == true
end

local function displayName( entry )
	return entry.name ~= "" and entry.name or "<unknown>"
end

local function accessText( entry )
	if entry.denied then return "Denied" end
	if not entry.via then return "Personal entry" end
	if entry.via == entry.group then return "Group " .. entry.group end
	return string.format( "Group %s (through %s)", entry.group, entry.via )
end

local function looksLikeSteamID( text )
	text = text:upper()
	return text:match( "^STEAM_[01]:[01]:%d+$" ) or text:match( "^7656119%d%d%d%d%d%d%d%d%d%d$" )
		or text:match( "^%[?U:1:%d+%]?$" )
end


------------------------------ Header ------------------------------
wl.search = xlib.maketextbox{ x=5, y=6, w=175, text=SEARCH_HINT, selectall=true, parent=wl }
local txtCol = wl.search:GetTextColor() or Color( 0, 0, 0, 255 )
local hintColor = Color( txtCol.r, txtCol.g, txtCol.b, 196 )
local textColor = Color( txtCol.r, txtCol.g, txtCol.b, 255 )
wl.search:SetTextColor( hintColor )

wl.enabled = xlib.makecheckbox{ x=195, y=9, label="Whitelist enabled", repconvar="ulx_whitelist_enabled", parent=wl,
	tooltip="When off, anyone can join. Changing it needs the ulx whitelist_enabled access." }


------------------------------ Lists ------------------------------
wl.players = xlib.makelistview{ x=5, y=30, w=420, h=305, multiselect=false, parent=wl }
wl.players:AddColumn( "Name" )
wl.players:AddColumn( "SteamID" )
wl.players:AddColumn( "Access" )

wl.groups = xlib.makelistview{ x=430, y=30, w=147, h=305, multiselect=false, parent=wl }
wl.groups:AddColumn( "Groups with access" )


------------------------------ Footer ------------------------------
wl.steamid = xlib.maketextbox{ x=5, y=340, w=170, selectall=true, parent=wl,
	tooltip="STEAM_0:X:Y, a SteamID64 or [U:1:N]" }
wl.add = xlib.makebutton{ x=180, y=340, w=60, label="Add", parent=wl }
wl.remove = xlib.makebutton{ x=245, y=340, w=70, label="Remove", disabled=true, parent=wl }
wl.info = xlib.makelabel{ x=325, y=344, label="", parent=wl }


------------------------------ Filling the lists ------------------------------
local function matches( entry )
	if filter == "" then return true end
	for _, text in ipairs( { entry.name, entry.id, accessText( entry ) } ) do
		if text:lower():find( filter, 1, true ) then return true end
	end
	return false
end

local function selectedEntry()
	local id = wl.players:GetSelectedLine()
	local line = id and wl.players:GetLine( id )
	return line and line.entry
end

-- Only personal entries keyed by SteamID can be removed with ulx unwhitelistid.
local function canRemove( entry )
	return entry ~= nil and not entry.denied and not entry.via and entry.id:find( "^STEAM_" ) ~= nil
		and can( "ulx unwhitelistid" )
end

local function updateButtons()
	wl.add:SetDisabled( not can( "ulx whitelistid" ) )
	wl.steamid:SetDisabled( not can( "ulx whitelistid" ) )
	wl.enabled:SetDisabled( not can( "ulx whitelist_enabled" ) )
	wl.remove:SetDisabled( not canRemove( selectedEntry() ) )
end

function wl.rebuild()
	wl.players:Clear()
	wl.groups:Clear()

	local data = xgui.data.whitelist
	if not ( data and data.allowed ) then
		wl.info:SetText( "" )
		updateButtons()
		return
	end

	local entries = {}
	for _, entry in ipairs( data.allowed ) do entries[ #entries + 1 ] = entry end
	for _, entry in ipairs( data.denied or {} ) do
		local copy = table.Copy( entry )
		copy.denied = true
		entries[ #entries + 1 ] = copy
	end

	local shown = 0
	for _, entry in ipairs( entries ) do
		if matches( entry ) then
			local line = wl.players:AddLine( displayName( entry ), entry.id, accessText( entry ) )
			line.entry = entry
			if entry.via then
				line:SetTooltip( "Access comes from the group. Change it on the Groups tab, or right-click to deny this player." )
			end
			shown = shown + 1
		end
	end

	for _, group in ipairs( data.groups or {} ) do
		local text = group.name
		if group.name == "user" then
			text = "user (everyone)"
		elseif group.via then
			text = string.format( "%s (through %s)", group.name, group.via )
		end
		wl.groups:AddLine( text ):SetTooltip( text )
	end

	local info = string.format( "%d can join, %d denied", #data.allowed, #( data.denied or {} ) )
	if shown < #entries then info = string.format( "%s (showing %d)", info, shown ) end
	wl.info:SetText( info )
	wl.info:SizeToContents()

	updateButtons()
end


------------------------------ Actions ------------------------------
local function confirmRemove( entry )
	Derma_Query( string.format( "Remove %s (%s) from the whitelist?\nIf this was their only access, they will be kicked.", displayName( entry ), entry.id ),
		"XGUI WARNING",
		"Remove", function() RunConsoleCommand( "ulx", "unwhitelistid", entry.id ) end,
		"Cancel", function() end )
end

local function confirmDeny( entry )
	Derma_Query( string.format( "Deny %s (%s) access to the server?\nThey will be kicked if they are online.", displayName( entry ), entry.id ),
		"XGUI WARNING",
		"Deny", function() RunConsoleCommand( "ulx", "userdenyid", entry.id, ACCESS ) end,
		"Cancel", function() end )
end

wl.players.OnRowSelected = function()
	updateButtons()
end

wl.players.OnRowRightClick = function( self, lineID, line )
	local entry = line.entry
	if not entry then return end

	local menu = DermaMenu()
	menu:SetSkin( xgui.settings.skin )
	menu:AddOption( "Copy SteamID", function() SetClipboardText( entry.id ) end )
	if canRemove( entry ) then
		menu:AddOption( "Remove from whitelist", function() confirmRemove( entry ) end )
	end
	if can( "ulx userdenyid" ) then
		if entry.denied then
			menu:AddOption( "Lift the deny", function() RunConsoleCommand( "ulx", "userdenyid", entry.id, ACCESS, "1" ) end )
		else
			menu:AddOption( "Deny access", function() confirmDeny( entry ) end )
		end
	end
	menu:Open()
end

wl.remove.DoClick = function()
	local entry = selectedEntry()
	if canRemove( entry ) then confirmRemove( entry ) end
end

local function addFromTextbox()
	local text = wl.steamid:GetValue():Trim()
	if text == "" then return end
	if not looksLikeSteamID( text ) then
		Derma_Message( "Enter a SteamID: STEAM_0:X:Y, a SteamID64 (7656119...) or [U:1:N].", "XGUI NOTICE", "OK" )
		return
	end
	RunConsoleCommand( "ulx", "whitelistid", text )
	wl.steamid:SetText( "" )
end
wl.add.DoClick = addFromTextbox
wl.steamid.OnEnter = addFromTextbox

wl.search.OnChange = function( pnl )
	local text = pnl:GetText()
	if text == "" then
		pnl:SetText( SEARCH_HINT )
		pnl:SelectAll()
		pnl:SetTextColor( hintColor )
		filter = ""
	elseif text == SEARCH_HINT then
		filter = ""
	else
		pnl:SetTextColor( textColor )
		filter = text:lower()
	end
	wl.rebuild()
end


------------------------------ Updates ------------------------------
xgui.hookEvent( "whitelist", "clear", wl.rebuild, "ulxWhitelistClear" )
xgui.hookEvent( "whitelist", "process", wl.rebuild, "ulxWhitelistProcess" )
hook.Add( "UCLChanged", "ULXWhitelist.XGUI", updateButtons )
wl.rebuild() -- For autorefresh

xgui.addModule( "Whitelist", wl, "icon16/door_in.png", "ulx whitelistshow", "Players who can join while the whitelist is on" )