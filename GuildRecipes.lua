---@class GuildRecipes
GuildRecipes = GuildRecipes or {}

---@class GuildRecipes
local m = GuildRecipes

---@diagnostic disable-next-line: undefined-global
local lib_stub = LibStub

GuildRecipes.name = "GuildRecipes"
GuildRecipes.prefix = "GRECIPES"
GuildRecipes.tagcolor = "FFDD7744"
GuildRecipes.events = {}
GuildRecipes.debug_enabled = false

BINDING_HEADER_GUILDRECIPES = "GuildRecipes"

---@class Item
---@field id integer
---@field name string
---@field icon string
---@field link string?
---@field quality integer

---@alias NotAceTimer any
---@alias TimerId number

---@class AceTimer
---@field ScheduleTimer fun( self: NotAceTimer, callback: function, delay: number, ... ): TimerId
---@field ScheduleRepeatingTimer fun( self: NotAceTimer, callback: function, delay: number, arg: any ): TimerId
---@field CancelTimer fun( self: NotAceTimer, timer_id: number )
---@field TimeLeft fun( self: NotAceTimer, timer_id: number )

---@class AceSerializer
---@field Serialize fun( self: any, ... ): string
---@field Deserialize fun( self: any, str: string ): any

---@class AceComm
---@field RegisterComm fun( self: any, prefix: string, method: function? )
---@field SendCommMessage fun( self: any, prefix: string, text: string, distribution: string, target: string?, prio: "BULK"|"NORMAL"|"ALERT"?, callbackFn: function?, callbackArg: any? )

function GuildRecipes:init()
	self.frame = CreateFrame( "Frame" )
	self.frame:SetScript( "OnEvent", function()
		if m.events[ event ] then
			m.events[ event ]()
		end
	end )

	for k, _ in pairs( m.events ) do
		m.frame:RegisterEvent( k )
	end
end

function GuildRecipes.events.ADDON_LOADED()
	if arg1 == m.name then
		---@type AceTimer
		m.ace_timer = lib_stub( "AceTimer-3.0" )

		---@type AceSerializer
		m.ace_serializer = lib_stub( "AceSerializer-3.0" )

		---@type AceComm
		m.ace_comm = lib_stub( "AceComm-3.0" )

		---@type MessageHandler
		m.msg = m.MessageHandler.new( m.ace_timer, m.ace_serializer, m.ace_comm )

		---@type TradeskillGui
		m.tsgui = m.Tradeskills.new()

		---@type SlashCommand
		m.slash_command = m.SlashCommand.new( m.name, { "gr", "GuildRecipes" } )

		m.version = GetAddOnMetadata( m.name, "Version" )
		m.info( string.format( "(v%s) Loaded", m.version ) )
	end
end

function GuildRecipes.events.PLAYER_LOGIN()
	-- Initialize DB
	GuildRecipesDB = GuildRecipesDB or {}
	m.db = GuildRecipesDB
	m.db.tradeskills = m.db.tradeskills or {}
	m.db.frame_tradeskills = m.db.frame_tradeskills or {}

	m.player = UnitName( "player" )
	m.player_class = UnitClass( "player" )
	m.slash_command.init()

	m.tooltip = CreateFrame( "GameTooltip", "GuildRecipesTooltip", nil, "GameTooltipTemplate" )
	m.tooltip:SetOwner( WorldFrame, "ANCHOR_NONE" )

	m.update_data()
end

function GuildRecipes.events.TRADE_SKILL_SHOW()
	local reverse = m.build_reverse_trade_map( GetLocale() )
	local tradeskill = reverse[ GetTradeSkillLine() ]
	local skills = {
		Alchemy = true,
		Blacksmithing = true,
		Engineering = true,
		Leatherworking = true,
		Tailoring = true,
		Jewelcrafting = true,
	}

	if skills[ tradeskill ] then
		local num = GetNumTradeSkills()

		for i = 1, GetNumTradeSkills() do
			local _, type = GetTradeSkillInfo( i )
			if type == "header" then
				num = num - 1
			end
		end

		m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

		if m.count_recipes( m.db.tradeskills[ tradeskill ], m.player ) ~= num then
			for i = 1, GetNumTradeSkills() do
				local _, type = GetTradeSkillInfo( i )
				if type ~= "header" then
					local item_link = GetTradeSkillItemLink( i )
					m.update_tradeskill_item( tradeskill, item_link, { m.player } )
				end
			end

			m.db.tradeskills_last_update = m.get_server_timestamp()
			m.msg.send_tradeskill( tradeskill )
		end
	end
end

function GuildRecipes.events.CRAFT_SHOW()
	local reverse = m.build_reverse_trade_map( GetLocale() )
	local tradeskill = reverse[ GetCraftName() ]

	if tradeskill == "Enchanting" then
		local num = GetNumCrafts()

		m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

		if m.count_recipes( m.db.tradeskills[ tradeskill ], m.player ) ~= num then
			for i = 1, GetNumCrafts() do
				local item_link = GetCraftItemLink( i )
				m.update_tradeskill_item( tradeskill, item_link, { m.player } )
			end

			m.db.tradeskills_last_update = m.get_server_timestamp()
			m.msg.send_tradeskill( tradeskill )
		end
	end
end

function GuildRecipes.events.UNIT_INVENTORY_CHANGED()
	if arg1 == "player" and m.tsgui.is_visible() then
		m.tsgui.update()
	end
end

---@param tradeskill string
---@param item_link ItemLink
---@param players string[]
function GuildRecipes.update_tradeskill_item( tradeskill, item_link, players )
	local id, name = m.parse_item_link( item_link )

	if id then
		if m.db.tradeskills[ tradeskill ][ id ] then
			if not players then
				m.debug( "ERROR, no players for: " .. tostring( item_link ) )
				return
			end
			for _, p in pairs( players ) do
				if not m.find( p, m.db.tradeskills[ tradeskill ][ id ].players ) then
					table.insert( m.db.tradeskills[ tradeskill ][ id ].players, p )
				end
			end
		else
			m.db.tradeskills[ tradeskill ][ id ] = {
				id = id,
				link = item_link,
				name = name,
				players = players
			}
		end
	end
end

function GuildRecipes.update_data()
	local now = m.get_server_timestamp()

	-- Request tradeskills if older then 2 days
	if not m.db.tradeskills_last_update or now >= m.db.tradeskills_last_update + 172800 then
		m.db.tradeskills_last_update = now
		m.msg.request_tradeskills()
	end
end

---@param bag_start integer
---@param bag_end integer
---@param name string
---@return integer
function GuildRecipes.find_item_count_bag( bag_start, bag_end, name )
	local count = 0
	for bag = bag_start, bag_end do
		local slots = GetContainerNumSlots( bag )
		for slot = 1, slots do
			local _, item_count = GetContainerItemInfo( bag, slot )
			if item_count and item_count > 0 then
				local _, item_name = m.parse_item_link( GetContainerItemLink( bag, slot ) )
				if item_name == name then
					count = count + item_count
				end
			end
		end
	end
	return count
end

GuildRecipes:init()
