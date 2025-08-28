GuildRecipes = GuildRecipes or {}

---@class GuildRecipes
local m = GuildRecipes

if m.Tradeskills then return end

---@class TradeskillGui
---@field show fun( tab: string? )
---@field hide fun()
---@field toggle fun()
---@field is_visible fun(): boolean
---@field update fun()

local M = {}

local _G = getfenv()

---@return TradeskillGui
---@nodiscard
function M.new()
	local popup
	local selected_tradeskill = "All tradeskills"
	local selected
	local offset = 0
	local frame_items = {}
	local search_result = {}

	local function save_position( self )
		local point, _, relative_point, x, y = self:GetPoint()

		m.db.frame_tradeskills.position = {
			point = point,
			relative_point = relative_point,
			x = x,
			y = y
		}
	end

	local function refresh()
		for i = 1, 5 do
			if search_result[ i ] then
				frame_items[ i ].set_item( search_result[ i + offset ] )
				frame_items[ i ].set_selected( selected == i + offset )
			else
				frame_items[ i ]:Hide()
			end
		end

		local max = math.max( 0, getn( search_result ) - 5 )
		local value = math.min( max, popup.scroll_bar:GetValue() )

		if value == 0 then
			_G[ "GuildTradeskillsScrollBarScrollUpButton" ]:Disable()
		else
			_G[ "GuildTradeskillsScrollBarScrollUpButton" ]:Enable()
		end

		if value == max then
			_G[ "GuildTradeskillsScrollBarScrollDownButton" ]:Disable()
		else
			_G[ "GuildTradeskillsScrollBarScrollDownButton" ]:Enable()
		end
	end

	local function initialize_dropdown_skill()
		local info = {}

		info.text = "All tradeskills"
		info.value = info.text
		info.arg1 = info.text
		info.notCheckable = true
		info.func = function( value )
			UIDropDownMenu_SetText( value, popup.dropdown_skill )
			selected_tradeskill = value
		end
		UIDropDownMenu_AddButton( info )

		for key, opt in pairs( m.TRADE_SKILL_LOCALIZATION ) do
			info.text = opt.enUS
			info.value = key
			info.arg1 = key
			UIDropDownMenu_AddButton( info )
		end
	end

	local function do_search( search_str )
		search_result = {}

		local function search( skill )
			if m.db.tradeskills[ skill ] then
				for id, item in m.db.tradeskills[ skill ] do
					if item.n and string.find( string.upper( item.n ), string.upper( search_str ), nil, true ) then
						table.insert( search_result, {
							id = id,
							name = item.n,
							players = item.p,
							quality = item.q,
							skill = skill
						} )
					end
				end
			end
		end

		if not selected_tradeskill or selected_tradeskill == "All tradeskills" then
			for key in m.db.tradeskills do
				search( key )
			end
		else
			search( selected_tradeskill )
		end

		table.sort( search_result, function( a, b )
			return a.name < b.name
		end )

		local max = math.max( 0, getn( search_result ) - 5 )
		popup.scroll_bar:SetMinMaxValues( 0, max )
		popup.scroll_bar:SetValue( 0 )

		refresh()
	end

	local function show_recipe( item, index )
		if selected == index then
			popup.crafters.clear()
			popup.info.clear()
			selected = nil
			return
		else
			popup.crafters.set( item )
			selected = index
		end

		if item.skill == "Enchanting" then
			item.link = m.make_enchant_link( item.id, item.name )
			popup.info.set( item )
			refresh()
			return
		end

		---@diagnostic disable-next-line: undefined-global
		if GetSpellInfoAtlasLootDB then
			---@diagnostic disable-next-line: undefined-global
			local recipe = m.find( item.id, GetSpellInfoAtlasLootDB[ "craftspells" ], "craftItem" )

			if recipe then
				recipe.link = m.make_item_link( item.id, item.name, item.quality )
				popup.info.set( recipe )
			else
				popup.info.clear( item.name .. " was not found in AtlasLoot database." )
			end
		else
			popup.info.clear( "AtlasLoot is required to view recipes." )
		end

		refresh()
	end

	local function create_item( parent, index )
		---@class FrameItem: Button
		local frame = m.FrameBuilder.new()
				:type( "Button" )
				:parent( parent )
				:width( 382 )
				:height( 16 )
				:frame_style( "NONE" )
				:build()

		frame.slot_index = index
		frame:Hide()
		frame:SetHighlightTexture( "Interface\\QuestFrame\\UI-QuestTitleHighlight" )
		frame:SetScript( "OnMouseUp", function()
			show_recipe( frame.item, frame.slot_index + offset )
		end )

		local selected_tex = frame:CreateTexture( nil, "BACKGROUND" )
		selected_tex:SetTexture( "Interface\\QuestFrame\\UI-QuestLogTitleHighlight" )
		selected_tex:SetAllPoints( frame )
		selected_tex:SetVertexColor( 0.3, 0.3, 1, 1 )
		selected_tex:Hide()

		---@type Button
		local text_item = m.GuiElements.create_text_in_container( frame, nil, "Button" )
		text_item:SetPoint( "Left", frame, "Left", 5, 0 )
		text_item:SetHeight( 16 )
		text_item:EnableMouse( true )

		text_item:SetScript( "OnEnter", function()
			GameTooltip:SetOwner( this, "ANCHOR_RIGHT" )
			GameTooltip:SetHyperlink( string.format( "%s:%d", frame.item.skill == "Enchanting" and "enchant" or "item", frame.item.id ) )
			frame:LockHighlight()
		end )

		text_item:SetScript( "OnLeave", function()
			GameTooltip:Hide()
			frame:UnlockHighlight()
		end )

		text_item:SetScript( "OnClick", function()
			if IsShiftKeyDown() and frame.item then
				if ChatFrameEditBox:IsVisible() then
					if frame.item.skill == "Enchanting" then
						ChatFrameEditBox:Insert( m.make_enchant_link( frame.item.id, frame.item.name ) )
					else
						ChatFrameEditBox:Insert( m.make_item_link( frame.item.id, frame.item.name, frame.item.quality ) )
					end
					return
				end
			end
			show_recipe( frame.item, frame.slot_index + offset )
		end )

		local text_tradeskill = frame:CreateFontString( nil, "ARTWORK", "GRFontNormal" )
		text_tradeskill:SetPoint( "Right", frame, "Right", -5, 0 )
		text_tradeskill:SetHeight( 16 )
		text_tradeskill:SetJustifyH( "Right" )

		---@param select boolean
		frame.set_selected = function( select )
			if select then
				selected_tex:Show()
			else
				selected_tex:Hide()
			end
		end

		frame.set_item = function( item )
			frame.item = item
			if item.skill == "Enchanting" then
				text_item:SetText( string.format( "|cFF%s%s|r", "80B0FF", item.name ) )
			else
				text_item:SetText( m.get_item_name_colorized( item ) )
			end

			if not selected_tradeskill or selected_tradeskill == "All tradeskills" then
				text_tradeskill:SetText( item.skill )
			else
				text_tradeskill:SetText( "" )
			end

			frame:Show()
		end

		return frame
	end

	local function create_reagent( parent, index )
		---@class ReagentFrame: Button
		local frame = CreateFrame( "Button", "GuildTradeskillsReagent" .. index, parent, "QuestItemTemplate" )
		local x = mod( index, 3 ) == 0 and 320 or (mod( index, 3 ) - 1) * 160
		local y = -5 - ((math.ceil( index / 3 ) - 1) * 52)

		frame:SetScale( 0.8 )
		frame:SetPoint( "TopLeft", parent.label_reagents, "BottomLeft", x, y )
		frame:Hide()
		frame.reagent_id = nil

		frame:SetScript( "OnEnter", function()
			if frame.reagent_id then
				GameTooltip:SetOwner( this, "ANCHOR_LEFT" )
				GameTooltip:SetHyperlink( string.format( "item:%d", frame.reagent_id ) )
			end
		end )
		frame:SetScript( "OnLeave", function()
			GameTooltip:Hide()
		end )

		return frame
	end

	local function create_crafters_frame( parent )
		local frame = m.FrameBuilder.new()
				:parent( parent )
				:point( "TopLeft", parent.border_results, "BottomLeft", 0, -5 )
				:point( "Right", parent.btn_search, "Right", 0, 0 )
				:height( 70 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 1 )
				:build()

		local label_crafters = frame:CreateFontString( nil, "ARTWORK", "GRFontHighlight" )
		label_crafters:SetPoint( "TopLeft", frame, "TopLeft", 10, -10 )

		local text_crafters = frame:CreateFontString( nil, "ARTWORK", "GRFontHighlight" )
		text_crafters:SetPoint( "TopLeft", frame, "TopLeft", 10, -25 )
		text_crafters:SetWidth( 300 )
		text_crafters:SetJustifyH( "Left" )

		local btn_reagents = m.GuiElements.create_button( frame, "Show reagents", 80, function()
			if this:GetText() == "Show reagents" then
				m.db.frame_tradeskills.show_reagents = true
				this:SetText( "Hide reagents" )
				parent.info:Show()
				parent:SetHeight( 465 )
			else
				m.db.frame_tradeskills.show_reagents = false
				this:SetText( "Show reagents" )
				parent.info:Hide()
				parent:SetHeight( 235 )
			end
		end )
		btn_reagents:SetPoint( "BottomRight", frame, "BottomRight", -8, 10 )
		btn_reagents:Hide()
		frame.btn_reagents = btn_reagents

		frame.clear = function()
			label_crafters:SetText( "" )
			text_crafters:SetText( "" )
			btn_reagents:Hide()
		end

		frame.set = function( item )
			---@diagnostic disable-next-line: undefined-global
			local have_alts = GuildAlts.version and true or false
			local players = ""

			for player_id in string.gmatch(item.players, "([^,]+)") do
				local player = m.db.players[ tonumber(player_id) ]
				local color = m.guild_member_online( player ) and "FFFFFF" or "AAAAAA"
				local main
				if have_alts then
					---@diagnostic disable-next-line: undefined-global
					main = GuildAlts.get_main( player )
					if main then
						local main_color = m.guild_member_online( main ) and "FFFFFF" or "AAAAAA"
						main = string.format( "|cFF%s(%s)|r", main_color, main )
					end
				end
				players = players .. string.format( "|cFF%s%s|r%s, ", color, player, main or "" )
			end

			label_crafters:SetText( string.format( "%s is craftable by:", m.get_item_name_colorized( item ) ) )
			text_crafters:SetText( string.match( players, "(.-), $" ) )
			btn_reagents:Show()
		end

		return frame
	end

	local function create_info_frame( parent )
		local frame = m.FrameBuilder.new()
				:parent( parent )
				:point( "TopLeft", parent.crafters, "BottomLeft", 0, -5 )
				:point( "Right", parent.btn_search, "Right", 0, 0 )
				:height( 224 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 1 )
				:build()

		---@class CraftInfoFrame: Frame
		local info = CreateFrame( "Frame", nil, frame )
		info:SetWidth( 380 )
		info:SetHeight( 1 )
		frame.info = info

		local scroll_frame = CreateFrame( "ScrollFrame", "GuildTradeskillsInfoScrollFrame", frame, "UIPanelScrollFrameTemplate" )
		scroll_frame:SetPoint( "TopLeft", frame, "TopLeft", 5, -5 )
		scroll_frame:SetPoint( "BottomRight", frame, "BottomRight", -20, 5 )

		_G[ "GuildTradeskillsInfoScrollFrameScrollBar" ]:ClearAllPoints()
		_G[ "GuildTradeskillsInfoScrollFrameScrollBar" ]:SetPoint( "TopLeft", scroll_frame, "TopRight", 0, -16 )
		_G[ "GuildTradeskillsInfoScrollFrameScrollBar" ]:SetPoint( "Bottom", scroll_frame, "Bottom", 0, 15 )

		scroll_frame:SetScrollChild( info )


		local frame_icon = CreateFrame( "Button", nil, info )
		frame_icon:SetPoint( "TopLeft", info, "TopLeft", 5, -5 )
		frame_icon:SetWidth( 32 )
		frame_icon:SetHeight( 32 )
		frame_icon:SetScript( "OnClick", function()
			if IsShiftKeyDown() then
				if ChatFrameEditBox:IsVisible() then
					local chat_type = ChatFrameEditBox.chatType
					local recipe = frame.recipe

					SendChatMessage( string.format( "Crafting of %s requires the following reagents:", recipe.link ), chat_type )
					for _, reagent in recipe.reagent_data do
						SendChatMessage( string.format( "%s (%d)", reagent.link, reagent.count ), chat_type )
					end
					return
				end
			end
		end )

		local icon = info:CreateTexture( nil, "ARTWORK" )
		icon:SetAllPoints( frame_icon )

		local text_name = info:CreateFontString( nil, "ARTWORK", "GRFontNormal" )
		text_name:SetPoint( "TopLeft", info, "TopLeft", 45, -5 )
		text_name:SetJustifyH( "Left" )

		local text_stats = info:CreateFontString( nil, "ARTWORK", "GRFontHighlightSmall" )
		text_stats:SetPoint( "TopLeft", text_name, "BottomLeft", 0, 0 )
		text_stats:SetJustifyH( "Left" )

		local text_info = info:CreateFontString( nil, "ARTWORK", "GRFontHighlightSmall" )
		text_info:SetPoint( "TopLeft", text_stats, "BottomLeft", 0, 0 )
		text_info:SetWidth( 330 )
		text_info:SetJustifyH( "Left" )
		text_info:SetTextColor( 0, 1, 0, 1 )

		local label_reagents = frame:CreateFontString( nil, "ARTWORK", "GRFontHighlightSmall" )
		label_reagents:SetPoint( "Top", text_info, "Bottom", 0, -10 )
		label_reagents:SetPoint( "Left", info, "Left", 5, 0 )
		label_reagents:SetText( "Reagents:" )
		info.label_reagents = label_reagents

		for i = 1, 8 do
			create_reagent( info, i )
		end

		---@param text string?
		frame.clear = function( text )
			frame.recipe = nil
			icon:SetTexture( nil )
			text_name:SetText( "" )
			text_stats:SetText( "" )
			text_info:SetText( "" )
			label_reagents:SetText( text or "" )

			for i = 1, 8 do
				local reagent = getglobal( "GuildTradeskillsReagent" .. i )
				reagent:Hide()
			end

			scroll_frame:UpdateScrollChildRect()

			if ((_G[ "GuildTradeskillsInfoScrollFrameScrollBarScrollUpButton" ]:IsEnabled() == 0) and (_G[ "GuildTradeskillsInfoScrollFrameScrollBarScrollDownButton" ]:IsEnabled() == 0)) then
				_G[ "GuildTradeskillsInfoScrollFrameScrollBar" ]:Hide()
			else
				_G[ "GuildTradeskillsInfoScrollFrameScrollBar" ]:Show()
			end
		end

		local function set_reagent( slot, reagent_id, reagent_name, reagent_texture, reagent_count )
			local reagent = getglobal( "GuildTradeskillsReagent" .. slot )
			local f_name = getglobal( "GuildTradeskillsReagent" .. slot .. "Name" )
			local f_count = getglobal( "GuildTradeskillsReagent" .. slot .. "Count" )
			local player_reagent_count = m.find_item_count_bag( 0, 4, reagent_name )

			reagent.reagent_id = reagent_id

			if not reagent_texture or not reagent_name then
				m.get_item_info( reagent_id, function( item_info )
					f_name:SetText( item_info.name )
					SetItemButtonTexture( reagent, item_info.texture )
				end )
			else
				f_name:SetText( reagent_name )
				SetItemButtonTexture( reagent, reagent_texture )
			end

			if (player_reagent_count < reagent_count) then
				SetItemButtonTextureVertexColor( reagent, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b );
				f_name:SetTextColor( GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b );
			else
				SetItemButtonTextureVertexColor( reagent, 1.0, 1.0, 1.0 );
				f_name:SetTextColor( HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b );
			end

			f_count:SetText( player_reagent_count .. " /" .. reagent_count )
			reagent:Show()
		end

		frame.refresh = function()
			if frame.recipe then
				frame.set( frame.recipe )
			end
		end

		frame.set = function( recipe )
			if not recipe then return end
			recipe.reagent_data = {}
			frame.recipe = recipe

			for i = 1, 8 do
				local reagent = getglobal( "GuildTradeskillsReagent" .. i )
				reagent:Hide()
			end

			if recipe.skill == "Enchanting" then
				icon:SetTexture( m.Enchants[ recipe.id ].icon )

				m.scan_tooltip( string.format( "enchant:%d", recipe.id ), function( lines )
					local stats = ""
					local desc = ""
					local reagents = {}

					if lines then
						for i, line in ipairs( lines ) do
							if i > 1 then
								if string.find( line, "Reagents:" ) then
									line = string.gsub( line, "Reagents: ", "" )
									for reagent in string.gmatch( line, "([^,]+)" ) do
										local name, count = string.match( reagent, "^%s?(.-)%s*%((%d+)%)" )
										local texture, link, quality
										name = m.clean_string( name and name or reagent )
										if m.Reagents[ name ] then
											_, link, quality, _, _, _, _, _, texture = GetItemInfo( m.Reagents[ name ] )
										else
											texture = "Interface\\Icons\\INV_Misc_QuestionMark"
										end

										table.insert( reagents, {
											id = m.Reagents[ name ],
											name = name,
											link = m.Reagents[ name ] and m.make_item_link( m.Reagents[ name ], name, quality ) or name,
											count = tonumber( count ) or 1,
											icon = texture
										} )
									end
								else
									if getn( reagents ) > 0 then
										desc = desc .. line .. "\n"
									else
										stats = stats .. line .. "\n"
									end
								end
							end
						end
					else
						m.debug( "Unable to parse tooltip" )
					end

					text_name:SetText( recipe.name )
					text_stats:SetText( stats ~= "" and stats or "\n\n" )
					text_info:SetText( desc )
					label_reagents:SetText( "Reagents:" )

					for i, reagent_data in pairs( reagents ) do
						set_reagent( i, reagent_data.id, reagent_data.name, reagent_data.icon, reagent_data.count )
						frame.recipe.reagent_data[ i ] = reagent_data
					end
				end )
			else
				m.get_item_info( recipe.craftItem, function( item_info )
					local item = {
						name = item_info.name,
						id = recipe.craftItem,
						quality = item_info.quality,
						icon = item_info.texture,
						data = {}
					}

					m.tooltip:ClearLines()
					m.tooltip:SetHyperlink( "item:" .. item.id )
					m.tooltip:Show()

					local num_lines = m.tooltip:NumLines()
					local stats = ""
					local desc = ""
					for i = 1, num_lines do
						local line = _G[ "GuildRecipesTooltipTextLeft" .. i ]:GetText()
						if string.find( line, "^%s*$" ) then
							break
						end
						if string.find( line, "Use:" ) or string.find( line, "Equip:" ) then
							desc = desc .. line .. "\n"
						elseif i > 1 and desc == "" then
							stats = stats .. line .. "\n"
						end
					end

					icon:SetTexture( item.icon )
					text_name:SetText( m.get_item_name_colorized( item ) )
					text_stats:SetText( stats ~= "" and stats or "\n\n" )
					text_info:SetText( desc )
					label_reagents:SetText( "Reagents:" )

					for i, reagent_data in recipe.reagents do
						local reagent_count = reagent_data[ 2 ] or 1
						m.get_item_info( reagent_data[ 1 ], function( reagent_info, data )
							set_reagent( data.i, reagent_info.id, reagent_info.name, reagent_info.texture, reagent_count )
							frame.recipe.reagent_data[ data.i ] = {
								id = reagent_info.id,
								name = reagent_info.name,
								link = m.make_item_link( reagent_info.id, reagent_info.name, reagent_info.quality ),
								count = reagent_count
							}
						end, { i = i } )
					end
				end )
			end

			scroll_frame:UpdateScrollChildRect()

			if ((_G[ "GuildTradeskillsInfoScrollFrameScrollBarScrollUpButton" ]:IsEnabled() == 0) and (_G[ "GuildTradeskillsInfoScrollFrameScrollBarScrollDownButton" ]:IsEnabled() == 0)) then
				_G[ "GuildTradeskillsInfoScrollFrameScrollBar" ]:Hide()
			else
				_G[ "GuildTradeskillsInfoScrollFrameScrollBar" ]:Show()
			end
		end

		frame.clear()
		return frame
	end

	local function create_frame()
		---@class TradeskillFrame: Frame
		local frame = m.FrameBuilder.new()
				:name( "GuildRecipesFrame" )
				:title( string.format( "Guild Recipes v%s", m.version ) )
				:frame_style( "TOOLTIP" )
				:frame_level( 100 )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 0.9 )
				:close_button()
				:width( 427 )
				:height( 235 )
				:movable()
				:esc()
				:hidden()
				:on_drag_stop( save_position )
				:build()

		if m.db.frame_tradeskills.position then
			local p = m.db.frame_tradeskills.position
			frame:ClearAllPoints()
			frame:SetPoint( p.point, UIParent, p.relative_point, p.x, p.y )
		end

		local label_search = frame:CreateFontString( nil, "ARTWORK", "GRFontNormal" )
		label_search:SetPoint( "TopLeft", frame, "TopLeft", 12, -35 )
		label_search:SetTextColor( 1, 1, 1 )
		label_search:SetJustifyH( "Left" )
		label_search:SetText( "Search" )

		local input_search = CreateFrame( "EditBox", "GuildTradeskillsInputSearch", frame, "InputBoxTemplate" )
		frame.search = input_search
		input_search:SetPoint( "TopLeft", frame, "TopLeft", 60, -29 )
		input_search:SetWidth( 180 )
		input_search:SetHeight( 22 )
		input_search:SetAutoFocus( false )
		input_search:SetScript( "OnEscapePressed", function()
			input_search:ClearFocus()
		end )
		input_search:SetScript( "OnEnterPressed", function()
			do_search( input_search:GetText() )
		end )

		local dropdown_skill = CreateFrame( "Frame", "GuildTradeskillsSkillDropdown", frame, "UIDropDownMenuTemplate" )
		frame.dropdown_skill = dropdown_skill
		dropdown_skill:SetPoint( "TopLeft", input_search, "TopRight", -5, 1 )
		dropdown_skill:SetScale( 0.9 )

		local btn_search = m.GuiElements.create_button( frame, "Search", 60, function()
			do_search( input_search:GetText() )
		end )
		btn_search:SetPoint( "TopLeft", dropdown_skill, "TopRight", -5, 0 )
		btn_search:SetHeight( 25 )
		frame.btn_search = btn_search

		UIDropDownMenu_Initialize( dropdown_skill, initialize_dropdown_skill )
		UIDropDownMenu_SetWidth( 90, dropdown_skill )
		UIDropDownMenu_SetText( "All tradeskills", dropdown_skill )

		local border_results = m.FrameBuilder.new()
				:parent( frame )
				:point( "TopLeft", label_search, "BottomLeft", -2, -10 )
				:point( "Right", btn_search, "Right", 0, 0 )
				:height( 92 )
				:frame_style( "TOOLTIP" )
				:backdrop( { bgFile = "Interface/Buttons/WHITE8x8" } )
				:backdrop_color( 0, 0, 0, 1 )
				:build()

		border_results:EnableMouseWheel( true )
		border_results:SetScript( "OnMouseWheel", function()
			local value = frame.scroll_bar:GetValue() - arg1
			frame.scroll_bar:SetValue( value )
		end )
		frame.border_results = border_results

		local scroll_bar = CreateFrame( "Slider", "GuildTradeskillsScrollBar", border_results, "UIPanelScrollBarTemplate" )
		scroll_bar:SetPoint( "TopRight", border_results, "TopRight", -5, -20 )
		scroll_bar:SetPoint( "Bottom", border_results, "Bottom", 0, 20 )
		scroll_bar:SetMinMaxValues( 0, 0 )
		scroll_bar:SetValueStep( 1 )
		scroll_bar:SetScript( "OnValueChanged", function()
			offset = arg1
			refresh()
		end )
		frame.scroll_bar = scroll_bar

		for i = 1, 5 do
			local item = create_item( border_results, i )
			item:SetPoint( "TopLeft", border_results, "TopLeft", 4, ((i - 1) * -17) - 4 )
			table.insert( frame_items, item )
		end

		frame.crafters = create_crafters_frame( frame )
		frame.info = create_info_frame( frame )
		if not m.db.frame_tradeskills.show_reagents then
			frame.info:Hide()
		else
			frame:SetHeight( 465 )
			frame.crafters.btn_reagents:SetText( "Hide reagents" )
		end

		return frame
	end

	local function show()
		if not popup then
			popup = create_frame()
		end

		popup:Show()
		popup.info.refresh()
		--popup.search:SetFocus()
	end

	local function hide()
		if popup then
			popup:Hide()
		end
	end

	local function toggle()
		if popup and popup:IsVisible() then
			popup:Hide()
		else
			show()
		end
	end

	local function is_visible()
		return popup and popup:IsVisible() or false
	end

	local function update()
		popup.info.refresh()
	end

	---@type TradeskillGui
	return {
		show = show,
		hide = hide,
		toggle = toggle,
		is_visible = is_visible,
		update = update,
	}
end

m.Tradeskills = M
return M
