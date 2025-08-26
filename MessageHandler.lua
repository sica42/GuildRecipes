GuildRecipes = GuildRecipes or {}

---@class GuildRecipes
local m = GuildRecipes

if m.MessageHandler then return end

---@type MessageCommand
local MessageCommand = {
	RequestTradeskills = "RTS",
	Tradeskill = "TS",
	Ping = "PING",
	Pong = "PONG",
	VersionCheck = "VERSIONCHECK",
	Version = "VERSION",
}

---@alias MessageCommand
---| "RTS"
---| "TS"
---| "PING"
---| "PONG"
---| "VERSIONCHECK"
---| "VERSION"

---@class MessageHandler
---@field send_tradeskill fun( tradeskill: string )
---@field request_tradeskills fun()
---@field version_check fun()

local M = {}

---@param ace_timer AceTimer
---@param ace_serializer AceSerializer
---@param ace_comm AceComm
function M.new( ace_timer, ace_serializer, ace_comm )
	local pinging = false
	local best_ping = nil
	local var_names = {
		n = "name",
		q = "quality",
		t = "icon",
		c = "count",
		p = "price",
		pl = "players",
		d = "data",
		x = "deleted",
		f = "from",
		i = "items",
		m = "message",
		ts = "timestamp",
		lu = "last_update",
		ilu = "inventory_last_update",
		tlu = "tradeskills_last_update",
	}
	setmetatable( var_names, { __index = function( _, key ) return key end } );

	---@param t table
	local function decode( t )
		local l = {}
		for key, value in pairs( t ) do
			if type( value ) == "table" then
				value = decode( value )
			end
			if key == "t" then
				value = "Interface\\Icons\\" .. value
			end
			l[ var_names[ key ] ] = value
		end
		return l
	end

	---@param command MessageCommand
	---@param data table?
	local function broadcast( command, data )
		m.debug( string.format( "Broadcasting %s", command ) )

		ace_comm:SendCommMessage( m.prefix, command .. "::" .. ace_serializer.Serialize( M, data ), "GUILD", nil, "NORMAL" )
	end

	local function send_tradeskill( tradeskill )
		local data = {
			tradeskill = tradeskill,
			recipes = {}
		}

		for _, skill in m.db.tradeskills[ tradeskill ] do
			table.insert( data.recipes, {
				id = skill.id,
				pl = skill.players
			} )
		end

		broadcast( MessageCommand.Tradeskill, data )
	end

	local function send_tradeskills()
		for tradeskill in m.db.tradeskills do
			send_tradeskill( tradeskill )
		end
	end

	local function request_tradeskills()
		pinging = true
		best_ping = nil
		broadcast( MessageCommand.Ping )
	end

	local function version_check()
		broadcast( MessageCommand.VersionCheck )
	end

	---@param command string
	---@param data table
	---@param sender string
	local function on_command( command, data, sender )
		if command == MessageCommand.Tradeskill then
			--
			-- Receive tradeskill
			--
			m.debug( string.format( "Receiving %s from %s.", data.tradeskill, sender ) )
			local tradeskill = data.tradeskill
			m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

			for _, v in data.recipes do
				if v.id then
					local item_link
					if m.db.tradeskills[ tradeskill ][ v.id ] and m.db.tradeskills[ tradeskill ][ v.id ].link then
						item_link = m.db.tradeskills[ tradeskill ][ v.id ].link
					else
						if tradeskill == "Enchanting" then
							if v and v.id then
								local name = m.Enchants[ v.id ] and m.Enchants[ v.id ].name
								if not name then
									m.error( string.format( "Unknown enchantment received (%d)", v.id ) )
								else
									item_link = m.make_enchant_link( v.id, name )
								end
							else
								m.debug( "empty enchant data??" )
							end
						else
							m.get_item_info( v.id, function( item_info, players )
								if item_info then
									local link = m.make_item_link( item_info.id, item_info.name, item_info.quality )
									if link then
										m.update_tradeskill_item( tradeskill, link, players )
									end
								else
									m.debug( "No item_info for " .. tostring( v.id ) )
								end
							end, v.players )
						end
					end

					if item_link then
						m.update_tradeskill_item( tradeskill, item_link, v.players )
					end
				end
			end

			m.db.tradeskills_last_update = m.get_server_timestamp()
		elseif command == MessageCommand.RequestTradeskills and data.player == m.player then
			--
			-- Request for tradeskills
			--
			send_tradeskills()
		elseif command == MessageCommand.Ping then
			--
			-- Recive ping
			--
			broadcast( MessageCommand.Pong, {
				tlu = m.db.tradeskills_last_update,
			} )
		elseif command == MessageCommand.Pong and pinging then
			--
			-- Receive pong
			--
			m.debug( m.dump( data ) )
			if not best_ping or (data and data[ "tradeskills_last_update" ] > best_ping.last_update) then
				best_ping = {
					player = sender,
					last_update = data and data[ "tradeskills_last_update" ] or m.get_server_timestamp()
				}
				m.debug( data.ping .. "=" .. m.dump( best_ping[ data.ping ] ) )
			end

			if ace_timer:TimeLeft( M[ "ping_timer" ] ) == 0 then
				M[ "ping_timer" ] = ace_timer.ScheduleTimer( M, function()
					if pinging then
						pinging = false
						broadcast( MessageCommand.RequestTradeskills, { player = best_ping.player } )
					end
				end, 1 )
			end
		elseif command == MessageCommand.VersionCheck then
			--
			-- Receive version request
			--
			broadcast( MessageCommand.Version, { requester = sender, version = m.version, class = m.player_class } )
		elseif command == MessageCommand.Version then
			--
			-- Receive version
			--
			if data.requester == m.player then
				m.info( string.format( "%s [v%s]", m.colorize_player_by_class( sender, data.class ), data.version ), true )
			end
		end
	end

	local function on_comm_received( prefix, data_str, _, sender )
		if prefix ~= m.prefix or sender == m.player then return end

		local command = string.match( data_str, "^(.-)::" )
		data_str = string.gsub( data_str, "^.-::", "" )

		m.debug( "Received " .. command )

		local success, data = ace_serializer.Deserialize( M, data_str )
		if success then
			if data then
				data = decode( data )
			end

			on_command( command, data, sender )
		else
			m.error( "Corrupt data in addon message!" )
		end
	end

	ace_comm.RegisterComm( M, m.prefix, on_comm_received )

	---@type MessageHandler
	return {
		send_tradeskill = send_tradeskill,
		request_tradeskills = request_tradeskills,
		version_check = version_check
	}
end

m.MessageHandler = M
return M
