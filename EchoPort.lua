--[[ 
A couple small snippets of code in this addon are originally from  other sources, 
and are noted as such.
	   
License:
	This addon is free software; you can redistribute it and/or
	modify it under the terms of the GNU Lesser General Public
	License as published by the Free Software Foundation; either
	version 2.1 of the License, or (at your option) any later version.

	This addon is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	Lesser General Public License for more details.

	You should have received a copy of the GNU Lesser General Public
	License along with this addon; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
	
Astrolabe (c) James Carrothers
TomTom (c) James Whitehead II
  ]]
EchoPortSVar = {}
BINDING_HEADER_EchoPortHeader = "EchoPort"

local sqrt = sqrt
local time = time

local _L =
	{
		["Demonic Circle: Summon"] = GetSpellInfo(48018)
	}

local CurrentPort =
	{
		active = false,
		startTime = 0,
		facing = 0,
		curPing = {
			x = 0,
			y = 0
		},
		offset = {
			x = 0,
			y = 0
		}
	}

-- From Astrolabe
local MinimapZoomDistance =
	{
		inside = {
			[0] = 300,
			[1] = 240,
			[2] = 180,
			[3] = 120,
			[4] = 80,
			[5] = 50
		},
		outside = {
			[0] = 466 + 2/3,
			[1] = 400,
			[2] = 333 + 1/3,
			[3] = 266 + 2/6,
			[4] = 200,
			[5] = 133 + 1/3
		}
	}

function EchoPort_OnLoad(self)
	SLASH_EchoPort1 = "/ep"
	SlashCmdList["EchoPort"] =
		function(msg)
			EchoPort_SlashCommandHandler(self, msg)
		end

	self:RegisterEvent"ADDON_LOADED"
	self:RegisterEvent"MINIMAP_UPDATE_ZOOM"
	self:RegisterEvent"PLAYER_DEAD"
	self:RegisterEvent"ZONE_CHANGED_NEW_AREA"
	
	self.outside = false
	EchoPort_FacingArrow.defaultScale = 0.35
	EchoPort_DistanceText.format = "%d yard"
	EchoPort_DurationText.format = "%d seconds left"
	EchoPort_EnabledText.duration = 2
	EchoPort_EnabledText.elapsed = 0
	
	-- [[ Member method initialization ]]
	-- EchoPort:ClearPort()
	self.ClearPort =
		function(self)
			CurrentPort.active = false
			CurrentPort.startTime = 0
			CurrentPort.facing = 0
			CurrentPort.curPing.x = 0
			CurrentPort.curPing.y = 0
			CurrentPort.offset.x = 0
			CurrentPort.offset.y = 0
			EchoPort_DurationText:Hide()
			EchoPort_DistanceText:Hide()
			EchoPort_DirectionArrowImage:Hide()
			EchoPort_NoPortImage:Show()
			EchoPort_FacingArrowImage:Hide()
		end
	
	-- EchoPort:ColorGradient(perc, ...)
	self.ColorGradient =
		function(self, perc, ...)
			-- From TomTom
			local num = select("#", ...)
			local hexes = type(select(1, ...)) == "string"
			
			if ( perc == 1 ) then
				return select(num - 2, ...), select(num - 1, ...), select(num, ...)
			end
			
			num = num / 3
			
			local segment, relperc = math.modf(perc * (num - 1))
			local r1, g1, b1, r2, g2, b2
			r1, g1, b1 = select((segment * 3) + 1, ...), select((segment * 3) + 2, ...), select((segment * 3) + 3, ...)
			r2, g2, b2 = select((segment * 3) + 4, ...), select((segment * 3) + 5, ...), select((segment * 3) + 6, ...)
			
			if ( ( not r2 ) or ( not g2 ) or ( not b2 ) ) then
				return r1, g1, b1
			else
				return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
			end
		end
	
	-- EchoPort:Enable(enable)
	self.Enable =
		function(self, enable)
			if ( enable ) then
				self:RegisterEvent"COMBAT_LOG_EVENT_UNFILTERED"
				self:RegisterEvent"MINIMAP_PING"
				if ( not self:IsVisible() ) then
					EchoPort_EnabledText.elapsed = 0
					UIFrameFadeIn(EchoPort_EnabledText, 0, 0, 1)
					EchoPort_FadeFrame:SetScript("OnUpdate", function(self, elapsed) EchoPort_FadeFrame_OnUpdate(elapsed) end)
				end
				self:Show()
			else
				self:UnregisterEvent"COMBAT_LOG_EVENT_UNFILTERED"
				self:UnregisterEvent"MINIMAP_PING"
				self:Hide()
			end
		end
		
	-- EchoPort:GetDistance()
	self.GetDistance =
		function(self)
			local x, y
			
			if ( self.outside ) then
				x = ( CurrentPort.curPing.x + CurrentPort.offset.x ) * MinimapZoomDistance.outside[Minimap:GetZoom()]
				y = ( CurrentPort.curPing.y + CurrentPort.offset.y ) * MinimapZoomDistance.outside[Minimap:GetZoom()]
			else
				x = ( CurrentPort.curPing.x + CurrentPort.offset.x ) * MinimapZoomDistance.inside[Minimap:GetZoom()]
				y = ( CurrentPort.curPing.y + CurrentPort.offset.y ) * MinimapZoomDistance.inside[Minimap:GetZoom()]
			end
			
			return sqrt(x * x + y * y)
		end
		
	-- EchoPort:LoadOptions()
	self.LoadOptions =
		function(self)
			CreateFrame("CheckButton", "EchoPort_OptionsShowTimerCheck", EchoPort_Options, "OptionsCheckButtonTemplate")
			EchoPort_OptionsShowTimerCheck:SetPoint("TOPLEFT", EchoPort_OptionsTitle, "BOTTOMLEFT", 0, -10)
			EchoPort_OptionsShowTimerCheck:SetScript("OnClick", function(self)
																	EchoPortSVar.showTimer = self:GetChecked()
																	EchoPort:ReloadFrame()
																end)
			EchoPort_OptionsShowTimerCheck:SetChecked(EchoPortSVar.showTimer)
			EchoPort_OptionsShowTimerCheckText:SetText"|cffffffffShow Timer|r"
			
			CreateFrame("CheckButton", "EchoPort_OptionsShowDirectionArrowCheck", EchoPort_Options, "OptionsCheckButtonTemplate")
			EchoPort_OptionsShowDirectionArrowCheck:SetPoint("TOP", EchoPort_OptionsShowTimerCheck, "BOTTOM")
			EchoPort_OptionsShowDirectionArrowCheck:SetScript("OnClick", function(self)
																			 EchoPortSVar.showDirArrow = self:GetChecked()
																			 EchoPort:ReloadFrame()
																		 end)
			EchoPort_OptionsShowDirectionArrowCheck:SetChecked(EchoPortSVar.showDirArrow)
			EchoPort_OptionsShowDirectionArrowCheckText:SetText"|cffffffffShow Direction Arrow|r"
			
			CreateFrame("CheckButton", "EchoPort_OptionsShowFacingArrowCheck", EchoPort_Options, "OptionsCheckButtonTemplate")
			EchoPort_OptionsShowFacingArrowCheck:SetPoint("TOP", EchoPort_OptionsShowDirectionArrowCheck, "BOTTOM")
			EchoPort_OptionsShowFacingArrowCheck:SetScript("OnClick", function(self)
																			 EchoPortSVar.showFacingArrow = self:GetChecked()
																			 EchoPort:ReloadFrame()
																		 end)
			EchoPort_OptionsShowFacingArrowCheck:SetChecked(EchoPortSVar.showFacingArrow)
			EchoPort_OptionsShowFacingArrowCheckText:SetText"|cffffffffShow Facing Arrow|r"
			
			CreateFrame("CheckButton", "EchoPort_OptionsGhostModeCheck", EchoPort_Options, "OptionsCheckButtonTemplate")
			EchoPort_OptionsGhostModeCheck:SetPoint("TOP", EchoPort_OptionsShowFacingArrowCheck, "BOTTOM")
			EchoPort_OptionsGhostModeCheck:SetScript("OnClick", function(self)
																			 EchoPortSVar.ghostMode = self:GetChecked()
																			 EchoPort:ReloadFrame()
																		 end)
			EchoPort_OptionsGhostModeCheck:SetChecked(EchoPortSVar.ghostMode)
			EchoPort_OptionsGhostModeCheckText:SetText"|cffffffffGhost Mode|r"
			
			
			CreateFrame("Slider", "EchoPort_OptionsDirectionArrowScale", EchoPort_Options, "OptionsSliderTemplate")
			EchoPort_OptionsDirectionArrowScale:SetPoint("LEFT", EchoPort_OptionsShowTimerCheck, "RIGHT", 175, -10)
			EchoPort_OptionsDirectionArrowScale:SetScript("OnValueChanged", function(self)
																			 EchoPortSVar.dirArrowScale = self:GetValue()
																			 EchoPort_OptionsDirectionArrowScaleNum:SetText(string.format("%1.1f", EchoPortSVar.dirArrowScale))
																			 EchoPort:ReloadFrame()
																		 end)
			EchoPort_OptionsDirectionArrowScale:SetMinMaxValues(0.5, 1.5)
			EchoPort_OptionsDirectionArrowScale:SetValueStep(0.1)
			EchoPort_OptionsDirectionArrowScale:CreateFontString("EchoPort_OptionsDirectionArrowScaleNum", "ARTWORK", "GameFontNormalSmall")
			EchoPort_OptionsDirectionArrowScaleNum:SetPoint("TOP", EchoPort_OptionsDirectionArrowScale, "BOTTOM")
			EchoPort_OptionsDirectionArrowScaleLow:SetText"0.5"
			EchoPort_OptionsDirectionArrowScaleHigh:SetText"1.5"
			EchoPort_OptionsDirectionArrowScaleText:SetText"Direction Arrow Scale"
			EchoPort_OptionsDirectionArrowScale:SetValue(EchoPortSVar.dirArrowScale)
			EchoPort_OptionsDirectionArrowScaleNum:SetText(string.format("%1.1f", EchoPortSVar.dirArrowScale))
			
			CreateFrame("Slider", "EchoPort_OptionsFacingArrowScale", EchoPort_Options, "OptionsSliderTemplate")
			EchoPort_OptionsFacingArrowScale:SetPoint("TOP", EchoPort_OptionsDirectionArrowScale, "BOTTOM", 0, -25)
			EchoPort_OptionsFacingArrowScale:SetScript("OnValueChanged", function(self)
																			 EchoPortSVar.facingArrowScale = self:GetValue()
																			 EchoPort_OptionsFacingArrowScaleNum:SetText(string.format("%1.1f", EchoPortSVar.facingArrowScale))
																			 EchoPort:ReloadFrame()
																		 end)
			EchoPort_OptionsFacingArrowScale:SetMinMaxValues(0.5, 1.5)
			EchoPort_OptionsFacingArrowScale:SetValueStep(0.1)
			EchoPort_OptionsFacingArrowScale:CreateFontString("EchoPort_OptionsFacingArrowScaleNum", "ARTWORK", "GameFontNormalSmall")
			EchoPort_OptionsFacingArrowScaleNum:SetPoint("TOP", EchoPort_OptionsFacingArrowScale, "BOTTOM")
			EchoPort_OptionsFacingArrowScaleLow:SetText"0.5"
			EchoPort_OptionsFacingArrowScaleHigh:SetText"1.5"
			EchoPort_OptionsFacingArrowScaleText:SetText"Facing Arrow Scale"
			EchoPort_OptionsFacingArrowScale:SetValue(EchoPortSVar.facingArrowScale)
			EchoPort_OptionsFacingArrowScaleNum:SetText(string.format("%1.1f", EchoPortSVar.facingArrowScale))
			
			EchoPort_Options.name = "EchoPort"
			InterfaceOptions_AddCategory(EchoPort_Options)
		end
		
	-- EchoPort:ReloadFrame()
	self.ReloadFrame =
		function(self)
			if ( EchoPortSVar.showTimer and CurrentPort.active ) then
				EchoPort_DurationText:Show()
			else
				EchoPort_DurationText:Hide()
			end
			
			if ( EchoPortSVar.showDirArrow ) then
				EchoPort_DirectionArrow:Show()
			else
				EchoPort_DirectionArrow:Hide()
			end
			
			if ( EchoPortSVar.showFacingArrow ) then
				EchoPort_FacingArrow:Show()
			else
				EchoPort_FacingArrow:Hide()
			end
			
			EchoPort_DirectionArrow:SetScale(EchoPortSVar.dirArrowScale)
			EchoPort_FacingArrow:SetScale(EchoPortSVar.facingArrowScale * EchoPort_FacingArrow.defaultScale)
			
			EchoPort_DistanceText:SetPoint("TOP", EchoPort_DirectionArrow, "BOTTOM")
			
			if ( EchoPortSVar.ghostMode ) then
				self:SetAlpha(0.75)
			else
				self:SetAlpha(1.0)
			end
		end
		
	-- EchoPort:SetDistanceColor(text, dist)
	self.SetDistanceColor =
		function(self, text, dist)
			if ( dist < 20 ) then
				text:SetTextColor(0, 1, 0) -- Green
			elseif ( dist < 30 ) then
				text:SetTextColor(1, 1, 0) -- Yellow
			elseif ( dist < 40 ) then
				text:SetTextColor(0.8, 0.35, 0) -- Orange
			elseif ( dist >= 40 ) then
				text:SetTextColor(1, 0, 0) -- Red
			end
		end
		
	-- [[ Event handler initialization ]]
	-- EchoPort:ADDON_LOADED(...)
	self.ADDON_LOADED =
		function(self, ...)
			local arg1 = select(1, ...)
		
			if ( arg1 == "EchoPort" ) then
				if ( not EchoPortSVar.loaded ) then
					self:SetPoint"CENTER"
					EchoPortSVar.locked = false
					EchoPortSVar.showTimer = true
					EchoPortSVar.showDirArrow = true
					EchoPortSVar.showFacingArrow = true
					EchoPortSVar.dirArrowScale = 1
					EchoPortSVar.facingArrowScale = 1
					EchoPortSVar.ghostMode = false
					EchoPortSVar.loaded = true	
				end
				
				if ( not EchoPortSVar.locked ) then
					self:EnableMouse(true)
					self:RegisterForDrag"LeftButton"
				end
				
				self:LoadOptions()
				self:ReloadFrame()
			end
		end
		
	-- EchoPort:COMBAT_LOG_EVENT_UNFILTERED(...)
	self.COMBAT_LOG_EVENT_UNFILTERED =
		function(self, ...)
			if ( ( select(5, ...) == UnitName("player") ) and ( select(2, ...) == "SPELL_CREATE" ) and ( select(11, ...) == _L["Demonic Circle: Summon"] ) ) then
				CurrentPort.active = true
				CurrentPort.startTime = time()
				CurrentPort.facing = GetPlayerFacing()
				CurrentPort.curPing.x = 0
				CurrentPort.curPing.y = 0
				CurrentPort.offset.x = 0
				CurrentPort.offset.y = 0
				
				if ( EchoPortSVar.showTimer ) then
					EchoPort_DurationText:Show()
				end
				
				EchoPort_DistanceText:Show()
				EchoPort_NoPortImage:Hide()
				EchoPort_DirectionArrowImage:Show()
				EchoPort_FacingArrowImage:Show()
				
				Minimap:PingLocation(0, 0)
			end
		end
			
	-- EchoPort:MINIMAP_PING(...)
	self.MINIMAP_PING =
		function(self, ...)
			local newX, newY = Minimap:GetPingPosition()
			local offX = CurrentPort.curPing.x - newX
			local offY = CurrentPort.curPing.y - newY
			
			CurrentPort.offset.x = CurrentPort.offset.x + offX
			CurrentPort.offset.y = CurrentPort.offset.y + offY
			CurrentPort.curPing.x = newX
			CurrentPort.curPing.y = newY
		end
			
	-- EchoPort:MINIMAP_UPDATE_ZOOM(...)
	self.MINIMAP_UPDATE_ZOOM =
		function(self, ...)
			-- From Astrolabe
			local curZoom = Minimap:GetZoom()
			
			if ( GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") ) then
				if ( curZoom < 2 ) then
					Minimap:SetZoom(curZoom + 1)
				else
					Minimap:SetZoom(curZoom - 1)
				end
			end
			
			if ( ( GetCVar("minimapZoom") + 0 ) == Minimap:GetZoom() ) then
				self.outside = true
			else
				self.outside = false
			end
			
			Minimap:SetZoom(curZoom)
		end
			
	-- EchoPort:PLAYER_DEAD(...)
	self.PLAYER_DEAD =
		function(self, ...)
			self:ClearPort()
		end
			
	-- EchoPort:ZONE_CHANGED_NEW_AREA(...)
	self.ZONE_CHANGED_NEW_AREA =
		function(self, ...)
			self:ClearPort()
		end
end

function EchoPort_OnEvent(self, event, ...)
	if ( self[event] and ( type(self[event]) == "function" ) ) then
		self[event](self, ...)
	end
end

function EchoPort_OnUpdate(self, elapsed)
	if ( CurrentPort.active ) then
		local secsToGo = 360 - (time() - CurrentPort.startTime)
		
		if ( secsToGo < 0 ) then
			self:ClearPort()
		else
			if ( EchoPortSVar.showTimer ) then
				EchoPort_DurationText:SetText(string.format(EchoPort_DurationText.format, secsToGo))
			end
			
			local x, y = Minimap:GetPingPosition()
			CurrentPort.curPing.x = x
			CurrentPort.curPing.y = y
			local dist = self:GetDistance()
			
			if ( ( ( dist - 1 ) >= 0 ) and ( ( dist - 1 ) < 1 ) ) then
				EchoPort_DistanceText:SetText(string.format(EchoPort_DistanceText.format, dist))
			else
				EchoPort_DistanceText:SetText(string.format(EchoPort_DistanceText.format.."s", dist))
			end
			
			self:SetDistanceColor(EchoPort_DistanceText, dist)
			
			-- From TomTom
			if ( EchoPortSVar.showDirArrow ) then
				local angle = atan2(-(CurrentPort.curPing.x + CurrentPort.offset.x), (CurrentPort.curPing.y + CurrentPort.offset.y)) / 360 * (math.pi * 2)
				local player = GetPlayerFacing()
				angle = angle - player

				local perc = math.abs((math.pi - math.abs(angle)) / math.pi)
				if perc > 1 then perc = 2 - perc end

				local gr, gg, gb, mr, mg, mb, br, bg, bb
				if ( EchoPortSVar.ghostMode ) then
					gr,gg,gb = 1, 1, 1
					mr,mg,mb = 1, 1, 1
					br,bg,bb = 1, 1, 1
				else
					gr,gg,gb = 0, 1, 0
					mr,mg,mb = 1, 1, 0
					br,bg,bb = 1, 0, 0
				end
				local r,g,b = self:ColorGradient(perc, br, bg, bb, mr, mg, mb, gr, gg, gb)		
				EchoPort_DirectionArrowImage:SetVertexColor(r,g,b)
				
				local cell = floor(angle / (math.pi * 2) * 108 + 0.5) % 108
				local column = cell % 9
				local row = floor(cell / 9)

				local xstart = (column * 56) / 512
				local ystart = (row * 42) / 512
				local xend = ((column + 1) * 56) / 512
				local yend = ((row + 1) * 42) / 512

				EchoPort_DirectionArrowImage:SetTexCoord(xstart,xend,ystart,yend)
			end
			
			if ( EchoPortSVar.showFacingArrow ) then
				local angle2 = CurrentPort.facing - GetPlayerFacing()
				local cell = floor(angle2 / (math.pi * 2) * 108 + 0.5) % 108
				local column = cell % 9
				local row = floor(cell / 9)

				local xstart = (column * 56) / 512
				local ystart = (row * 42) / 512
				local xend = ((column + 1) * 56) / 512
				local yend = ((row + 1) * 42) / 512
				
				EchoPort_FacingArrowImage:SetTexCoord(xstart,xend,ystart,yend)
			end
		end
	end
end

function EchoPort_SlashCommandHandler(self, msg)
	local cmd = strlower(msg:match("(%S*).*"))
	
	if ( cmd == "toggle" ) then
		if self:IsVisible() then
			self:Enable(false)
		else
			self:Enable(true)
		end
	elseif ( cmd == "on" ) then
		self:Enable(true)
	elseif ( cmd == "lock" ) then
		self:RegisterForDrag""
		self:EnableMouse(false)
		EchoPortSVar.locked = true
	elseif ( cmd == "unlock" ) then
		self:EnableMouse(true)
		self:RegisterForDrag"LeftButton"
		EchoPortSVar.locked = false
	end
end

function EchoPort_FadeFrame_OnUpdate(elapsed)
	EchoPort_EnabledText.elapsed = EchoPort_EnabledText.elapsed + elapsed
	if ( EchoPort_EnabledText.elapsed >= EchoPort_EnabledText.duration ) then
		UIFrameFadeOut(EchoPort_EnabledText, 2, 1, 0)
		EchoPort_FadeFrame:SetScript("OnUpdate", nil)
	end
end
