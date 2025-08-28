GuildRecipes = GuildRecipes or {}

---@class GuildRecipes
local m = GuildRecipes

if m.MessageHandler then return end

---@type MessageCommand
local MessageCommand = {
	RequestTradeskill = "RTS",
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
---@field request_tradeskill fun( tradeskill: string )
---@field request_tradeskills fun()
---@field version_check fun()

local M = {}

---@param ace_timer AceTimer
---@param ace_serializer AceSerializer
---@param ace_comm AceComm
function M.new( ace_timer, ace_serializer, ace_comm )
	local pinging = false
	local best_ping = {}
	local var_names = {
		n = "name",
		q = "quality",
		c = "count",
		p = "players",
		d = "data",
		i = "items",
		ts = "tradeskill",
		h = "hashes",
		lu = "last_update",
		--tlu = "tradeskills_last_update",
		Alc = "Alchemy",
		Bla = "Blacksmithing",
		Eng = "Engineering",
		Enc = "Enchanting",
		Lea = "Leatherworking",
		Tai = "Tailoring",
		Jew = "Jewelcrafting",

	}
	setmetatable( var_names, { __index = function( _, key ) return key end } );

	---@param t table
	local function decode( t )
		local l = {}
		for key, value in pairs( t ) do
			if type( value ) == "table" then
				value = decode( value )
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
		m.debug( string.format( "Sending %s", tradeskill ) )
		local data = {
			tradeskill = tradeskill,
			recipes = {}
		}

		for id, item in m.db.tradeskills[ tradeskill ] do
			local players = {}
			for _, p in pairs( m.comma_separated_to_table( item.p ) ) do
				table.insert( players, m.db.players[ tonumber( p ) ] )
			end

			table.insert( data.recipes, {
				id = id,
				p = players
			} )
		end

		broadcast( MessageCommand.Tradeskill, data )
	end

	local function send_tradeskills()
		for tradeskill in m.db.tradeskills do
			send_tradeskill( tradeskill )
		end
	end

	local function request_tradeskill( tradeskill )
		pinging = true
		best_ping = {}

		broadcast( MessageCommand.Ping, {
			[string.sub( tradeskill, 1, 3 )] = m.tradeskill_hash( tradeskill )
		} )
	end

	local function request_tradeskills()
		pinging = true
		best_ping = {}
		local hashes = {}

		for tradeskill in pairs(m.TRADE_SKILL_LOCALIZATION) do
			hashes[ string.sub( tradeskill, 1, 3 ) ] = m.tradeskill_hash( tradeskill )
		end

		broadcast( MessageCommand.Ping, hashes )
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
					---@type Item
					local item = nil
					if m.db.tradeskills[ tradeskill ][ v.id ] then
						item = {
							id = v.id,
							name = m.db.tradeskills[ tradeskill ][ v.id ].n,
							quality = m.db.tradeskills[ tradeskill ][ v.id ].q
						}
					else
						if tradeskill == "Enchanting" then
							if v and v.id then
								local name = m.Enchants[ v.id ] and m.Enchants[ v.id ].name
								if not name then
									m.error( string.format( "Unknown enchantment received (%d)", v.id ) )
								else
									item = {
										id = v.id,
										name = name,
									}
								end
							else
								m.debug( "empty enchant data??" )
							end
						else
							m.debug( "Fetching item info for " .. tostring( v.id ) )
							m.get_item_info( v.id, function( item_info, players )
								if item_info then
									local i = {
										id = item_info.id,
										name = item_info.name,
										quality = item_info.quality
									}

									m.update_tradeskill_item( tradeskill, i, players )
								else
									m.debug( "No item_info for " .. tostring( v.id ) )
								end
							end, v.players )
						end
					end

					if item then
						--m.debug( "got item" )
						m.update_tradeskill_item( tradeskill, item, v.players )
					end
				end
			end

			m.db.tradeskills_last_update[ tradeskill ] = m.get_server_timestamp()
		elseif command == MessageCommand.RequestTradeskill and data.player == m.player then
			--
			-- Request for tradeskill
			--
			m.debug(m.dump(data))
			send_tradeskill( data.tradeskill )
		elseif command == MessageCommand.Ping and sender ~= m.player then
			--
			-- Recive ping
			--
			for tradeskill, hash in (data or {}) do
				local local_hash = m.tradeskill_hash( tradeskill )
				if local_hash == hash then
					data[ tradeskill ] = nil
				else
					data[ tradeskill ] = m.db.tradeskills_last_update[ tradeskill ] or 0
				end
			end

			m.debug( m.dump( data ) )
			broadcast( MessageCommand.Pong, data )
		elseif command == MessageCommand.Pong and pinging then
			--
			-- Receive pong
			--
			m.debug( m.dump( data ) )
			for tradeskill, last_update in pairs( data or {} ) do
				if not best_ping[ tradeskill ] or (last_update > best_ping[ tradeskill ].last_update) then
					best_ping[ tradeskill ] = {
						player = sender,
						last_update = last_update
					}
				end
			end

			if ace_timer:TimeLeft( M[ "ping_timer" ] ) == 0 then
				M[ "ping_timer" ] = ace_timer.ScheduleTimer( M, function()
					if pinging then
						m.debug( "Ping timeout, requesting tradeskills from best pings." )
						pinging = false
						for tradeskill, ping_info in pairs( best_ping ) do
							m.debug( string.format( "Requesting %s from %s (last update: %d)", tradeskill, ping_info.player, ping_info.last_update ) )
							broadcast( MessageCommand.RequestTradeskill, {
								player = ping_info.player,
								ts = tradeskill
							} )
						end
					end
				end, 2 )
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
		request_tradeskill = request_tradeskill,
		request_tradeskills = request_tradeskills,
		version_check = version_check
	}
end

m.MessageHandler = M
return M
