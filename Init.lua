---@type string
local addonName = ...

---@class CastBarInformation
---@field width number
---@field height number
---@field anchor Frame

---@class DisintegrateTicksFrame : Frame
---@field private ticks Texture[]
---@field private maxTicks number
---@field private channeling boolean
---@field private chaining boolean
---@field private lastStart number
---@field private firstTick number
---@field private prevEndTime number|nil
---@field private prevHastedTickInterval number|nil
---@field private massDisintegrateStacks number
---@field private lastGainedStack number
---@field private hasTipTheScalesActive boolean
---@field private lastKnownHaste number
---@field castBarInformation CastBarInformation
---@field RegisterSpecSpecificEvents fun(self: DisintegrateTicksFrame)
---@field UnregisterSpecSpecificEvents fun(self: DisintegrateTicksFrame)
---@field CreateTick fun(self: DisintegrateTicksFrame, name: string): Texture
---@field HideTicks fun(self: DisintegrateTicksFrame)
---@field UpdateTicks fun(self: DisintegrateTicksFrame, castBarFrame: Frame, duration: number)
---@field QueryTalentsAndHide fun(self: DisintegrateTicksFrame)
---@field AdjustDimensions fun(self: DisintegrateTicksFrame, width: number, height: number)
---@field UpdateAnchor fun(self: DisintegrateTicksFrame, newAnchor: Frame)
---@field KnowsMassDisintegrate fun(self: DisintegrateTicksFrame): boolean
---@field OnEvent fun(self: DisintegrateTicksFrame, event: WowEvent, ...: any)

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	-- only Evokers, see classID here: https://wago.tools/db2/ChrSpecialization
	if select(3, UnitClass("player")) ~= Constants.UICharacterClasses.Evoker then
		return
	end

	DisintegrateTicksSaved = DisintegrateTicksSaved or {}

	if DisintegrateTicksSaved.MassDisintegrateClipWarning == nil then
		DisintegrateTicksSaved.MassDisintegrateClipWarning = {
			text = "DON'T CLIP",
			fontSize = 18,
			point = "TOP",
			x = 0,
			y = 150,
			color = { 1, 1, 1, 1 },
			enabled = false,
		}
	end

	if DisintegrateTicksSaved.Color == nil then
		DisintegrateTicksSaved.Color = { 1, 1, 1, 1 }
	end

	---@class DisintegrateTicksFrame
	local frame = CreateFrame("Frame", "DisintegrateTicksFrame")
	frame.ticks = {}
	frame.maxTicks = 4
	frame.channeling = false
	frame.chaining = false
	frame.lastStart = 0
	frame.firstTick = 0
	frame.prevHastedTickInterval = nil
	frame.massDisintegrateStacks = 0
	frame.lastGainedStack = 0
	frame.hasTipTheScalesActive = false
	frame.lastKnownHaste = 0
	frame.castBarInformation = {
		width = 0,
		height = 0,
		anchor = PlayerCastingBarFrame,
	}
	frame.Warning = frame:CreateFontString(nil, "OVERLAY")
	frame.Warning:SetFont("Fonts\\FRIZQT__.TTF", DisintegrateTicksSaved.MassDisintegrateClipWarning.fontSize, "OUTLINE")
	frame.Warning:SetText(DisintegrateTicksSaved.MassDisintegrateClipWarning.text)
	frame.Warning:SetTextColor(
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[1],
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[2],
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[3],
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[4]
	)

	frame.Warning:Hide()

	function frame:RegisterSpecSpecificEvents()
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		self:RegisterEvent("TRAIT_CONFIG_UPDATED")
		self:RegisterEvent("PLAYER_DEAD")
		self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
		self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
	end

	function frame:UnregisterSpecSpecificEvents()
		self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
		self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
		self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
		self:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
		self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		self:UnregisterEvent("PLAYER_DEAD")
		self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
		self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
	end

	---@param spellId number
	---@return boolean
	function frame:IsEmpower(spellId)
		return spellId == 357208 -- fire breath
			or spellId == 382266 -- font of magic fire breath
			or spellId == 359073 -- eternity surge
			or spellId == 382411 -- font of magic eternity surge
	end

	function frame:CreateTick(name)
		local tick = self.castBarInformation.anchor:CreateTexture(name, "OVERLAY")

		tick:SetColorTexture(
			DisintegrateTicksSaved.Color[1],
			DisintegrateTicksSaved.Color[2],
			DisintegrateTicksSaved.Color[3],
			DisintegrateTicksSaved.Color[4]
		)
		tick:Hide()

		return tick
	end

	function frame:HideTicks()
		for _, tick in next, self.ticks do
			tick:Hide()
		end
	end

	function frame:GetHaste(actualDuration)
		if actualDuration ~= nil then
			local baseDuration = 3.0

			if C_SpellBook.IsSpellKnown(369913) then
				baseDuration = baseDuration * 0.8
			end

			local hasteMultiplier = baseDuration / actualDuration
			self.lastKnownHaste = (hasteMultiplier - 1) * 100

			return hasteMultiplier
		end

		return 1 + self.lastKnownHaste / 100
	end

	function frame:GetTickInterval()
		local base = 1

		-- azure celerity reduces tick interval by 25%
		if C_SpellBook.IsSpellKnown(1219723) then
			base = base * 0.75
		end

		-- natural convergence reduces total cast time (and thus tick interval) by 20%
		if C_SpellBook.IsSpellKnown(369913) then
			base = base * 0.8
		end

		return base
	end

	function frame:UpdateTicks(castBarFrame, duration)
		self:HideTicks()

		local hastedTickInterval = self:GetTickInterval() / self:GetHaste()
		local pixelsPerSecond = self.castBarInformation.width / duration

		for i = 1, self.maxTicks do
			local tick = self.ticks[i]

			if tick == nil or tick:GetParent() ~= castBarFrame then
				tick = self:CreateTick("DisintegrateTick" .. i)
				self.ticks[i] = tick
			end

			tick:SetSize(2, self.castBarInformation.height * 0.95)
			tick:ClearAllPoints()

			local tickTime = i * hastedTickInterval

			if self.chaining then
				local interval = (duration - self.firstTick) / (self.maxTicks - 1)
				tickTime = self.firstTick + (i - 1) * interval
			end

			tick:SetPoint("CENTER", castBarFrame, "LEFT", (duration - tickTime) * pixelsPerSecond, 0)

			if tickTime < duration * 0.99 then
				tick:Show()
			else
				tick:Hide()
			end
		end
	end

	function frame:SetTickColor(r, g, b, a)
		DisintegrateTicksSaved.Color[1] = r > 1 and r / 255 or r
		DisintegrateTicksSaved.Color[2] = g > 1 and g / 255 or g
		DisintegrateTicksSaved.Color[3] = b > 1 and b / 255 or b
		a = a or 1
		DisintegrateTicksSaved.Color[4] = a > 1 and a / 100 or a

		local color = CreateColor(
			DisintegrateTicksSaved.Color[1],
			DisintegrateTicksSaved.Color[2],
			DisintegrateTicksSaved.Color[3],
			DisintegrateTicksSaved.Color[4]
		)

		for i = 1, #self.ticks do
			self.ticks[i]:SetColorTexture(color.r, color.g, color.b, color.a)
		end

		print(
			"DisintegrateTicks: the color of all ticks is now",
			color:WrapTextInColorCode("whatever this text appears as"),
			"."
		)
	end

	function frame:ToggleMassDisintegrateClipWarning()
		DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled =
			not DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled

		print(
			"DisintegrateTicks: Mass Disintegrate Clip Warning is now",
			DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled and "enabled" or "disabled"
		)

		self:MaybeUpdateWarningPosition()
	end

	function frame:SetClipWarningFontSize(nextSize)
		if nextSize == nil then
			nextSize = 18
		end

		if nextSize ~= DisintegrateTicksSaved.MassDisintegrateClipWarning.fontSize then
			DisintegrateTicksSaved.MassDisintegrateClipWarning.fontSize = nextSize

			self.Warning:SetFont(self.Warning:GetFont(), nextSize)

			print("DisintegrateTicks: the font size is now", nextSize)
		end
	end

	function frame:SetClipWarningText(text)
		if text == nil then
			text = "DON'T CLIP"
		end

		if text ~= DisintegrateTicksSaved.MassDisintegrateClipWarning.text then
			DisintegrateTicksSaved.MassDisintegrateClipWarning.text = text

			self.Warning:SetText(text)

			print("DisintegrateTicks: the text is now", text)
		end
	end

	function frame:MaybeUpdateWarningPosition()
		if DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled then
			self.Warning:ClearAllPoints()
			self.Warning:SetPoint(
				DisintegrateTicksSaved.MassDisintegrateClipWarning.point,
				self.castBarInformation.anchor,
				"CENTER",
				DisintegrateTicksSaved.MassDisintegrateClipWarning.x,
				DisintegrateTicksSaved.MassDisintegrateClipWarning.y
			)
		end
	end

	function frame:SetClipWarningPosition(point, x, y)
		if point ~= "TOP" and point ~= "BOTTOM" and point ~= nil then
			print('DisintegrateTicks: Point must be either "TOP", "BOTTOM" or nil. Mind the quotes.')
			return
		end

		point = point or "TOP"
		x = x or 0
		y = y or 150

		if
			point ~= DisintegrateTicksSaved.MassDisintegrateClipWarning.point
			or x ~= DisintegrateTicksSaved.MassDisintegrateClipWarning.x
			or y ~= DisintegrateTicksSaved.MassDisintegrateClipWarning.y
		then
			DisintegrateTicksSaved.MassDisintegrateClipWarning.point = point
			DisintegrateTicksSaved.MassDisintegrateClipWarning.x = x
			DisintegrateTicksSaved.MassDisintegrateClipWarning.y = y

			self:MaybeUpdateWarningPosition()

			print("DisintegrateTicks: Set clip warning position to", point, "at x=", x, ", y=", y)
		end
	end

	function frame:SetClipWarningColor(r, g, b, a)
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[1] = r > 1 and r / 255 or r
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[2] = g > 1 and g / 255 or g
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[3] = b > 1 and b / 255 or b
		a = a or 1
		DisintegrateTicksSaved.MassDisintegrateClipWarning.color[4] = a > 1 and a / 100 or a

		local color = CreateColor(
			DisintegrateTicksSaved.MassDisintegrateClipWarning.color[1],
			DisintegrateTicksSaved.MassDisintegrateClipWarning.color[2],
			DisintegrateTicksSaved.MassDisintegrateClipWarning.color[3],
			DisintegrateTicksSaved.MassDisintegrateClipWarning.color[4]
		)

		self.Warning:SetTextColor(color.r, color.g, color.b, color.a)

		print(
			"DisintegrateTicks: the color of the clip warning is now",
			color:WrapTextInColorCode("whatever this text appears as"),
			"."
		)
	end

	function frame:QueryTalentsAndHide()
		self.maxTicks = C_SpellBook.IsSpellKnown(1219723) and 5 or 4
		self:HideTicks()
	end

	function frame:AdjustDimensions(width, height)
		width = math.ceil(width)
		height = math.ceil(height)

		if width ~= self.castBarInformation.width or height ~= self.castBarInformation.height then
			self.castBarInformation.width = width
			self.castBarInformation.height = height
			self:QueryTalentsAndHide()
		end
	end

	function frame:UpdateAnchor(newAnchor)
		if self.castBarInformation.anchor == newAnchor then
			return
		end

		self.castBarInformation.anchor = newAnchor
		self:QueryTalentsAndHide()
		self:MaybeUpdateWarningPosition()
	end

	function frame:KnowsMassDisintegrate()
		return C_SpellBook.IsSpellKnownOrInSpellBook(436335)
	end

	function frame:OnEvent(event, ...)
		if event == "LOADING_SCREEN_DISABLED" then
			self:QueryTalentsAndHide()
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			---@type number
			local currentSpecId = PlayerUtil.GetCurrentSpecID()

			-- only devastation and preservation. see ID columns here: https://wago.tools/db2/ChrSpecialization
			if currentSpecId == 1467 or currentSpecId == 1468 then
				self:RegisterSpecSpecificEvents()
				self:QueryTalentsAndHide()
			else
				self:UnregisterSpecSpecificEvents()
			end
		elseif event == "PLAYER_DEAD" then
			self.massDisintegrateStacks = 0
		elseif event == "TRAIT_CONFIG_UPDATED" then
			self:QueryTalentsAndHide()
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			local unit, castGuid, spellId = ...

			if self.hasTipTheScalesActive and self:IsEmpower(spellId) and self:KnowsMassDisintegrate() then
				self.hasTipTheScalesActive = false
				self.massDisintegrateStacks = self.massDisintegrateStacks + 1
				self.lastGainedStack = GetTime()
			end
		elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
			local unit, castGuid, spellId, complete, interruptedBy, castBarId = ...

			if not complete or not self:IsEmpower(spellId) == nil or not self:KnowsMassDisintegrate() then
				return
			end

			self.massDisintegrateStacks = self.massDisintegrateStacks + 1
			self.lastGainedStack = GetTime()
		elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
			if select(3, ...) ~= 356995 then
				return
			end

			local endTimeMS = select(5, UnitChannelInfo("player"))

			if endTimeMS ~= nil then
				self.prevEndTime = endTimeMS / 1000
			end
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
			-- ignore other channels such as Fishing or quest-related casts
			if select(3, ...) ~= 356995 then
				return
			end

			local _, _, _, startTimeMS, endTimeMS = UnitChannelInfo("player")
			local startTime = startTimeMS / 1000

			-- e.g. casting hover during disint triggers another channel start
			-- but the end time will be within a server tick of the already-ongoing cast
			if startTime - self.lastStart < 0.5 then
				return
			end

			self.lastStart = startTime

			if DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled and self.massDisintegrateStacks > 0 then
				local expired = GetTime() - self.lastGainedStack > 15

				if expired then
					self.massDisintegrateStacks = 0
				else
					self.Warning:Show()
					self.massDisintegrateStacks = self.massDisintegrateStacks - 1

					if self.castBarInformation.anchor.Text ~= nil then
						self.castBarInformation.anchor.Text:SetText(C_Spell.GetSpellName(436335))
					end
				end
			else
				self.Warning:Hide()
			end

			local nextEndTime = endTimeMS / 1000
			local hastedTickInterval = self:GetTickInterval() / self:GetHaste(nextEndTime - startTime)

			self.firstTick = 0

			if self.channeling and self.prevEndTime and self.prevHastedTickInterval then
				local remaining = self.prevEndTime - startTime
				-- modulo gives time to the next tick that would've fired, not just the last
				self.firstTick = math.max(0, math.fmod(remaining, self.prevHastedTickInterval))
			end

			self.prevEndTime = nextEndTime
			self.prevHastedTickInterval = hastedTickInterval
			self.chaining = self.channeling
			self.channeling = true

			self:UpdateTicks(self.castBarInformation.anchor, nextEndTime - startTime)
		elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
			local spellId = ...

			if not self.hasTipTheScalesActive and self:IsEmpower(spellId) then
				self.hasTipTheScalesActive = true
			end
		elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
			local spellId = ...

			if self.hasTipTheScalesActive and self:IsEmpower(spellId) then
				self.hasTipTheScalesActive = false
			end
		elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			if select(3, ...) ~= 356995 then
				return
			end

			self.Warning:Hide()
			self:HideTicks()
			self.channeling = false
			self.chaining = false
		end
	end

	frame:MaybeUpdateWarningPosition()
	frame:SetScript("OnEvent", frame.OnEvent)

	frame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
	frame:RegisterEvent("LOADING_SCREEN_DISABLED")
	frame:RegisterSpecSpecificEvents()

	hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", function(editModeManagerSelf)
		local lockToPlayerFrame = PlayerCastingBarFrame:IsAttachedToPlayerFrame()

		frame:AdjustDimensions(lockToPlayerFrame and 150 or 208, lockToPlayerFrame and 10 or 11)
	end)

	if
		C_AddOns.DoesAddOnExist("NephUI")
		and C_AddOns.IsAddOnLoadable("NephUI")
		and C_AddOns.IsAddOnLoaded("NephUI")
		and LibStub
	then
		local ace = LibStub("AceAddon-3.0", true)

		if not ace then
			return
		end

		local ok, NephUI = pcall(ace.GetAddon, ace, "NephUI", true)

		if not ok or not NephUI then
			return
		end

		local function SetupNephUICastBar()
			if frame.castBarInformation.anchor == NephUICastBar.status then
				return
			end

			frame.castBarInformation.anchor = NephUICastBar.status
			local width, height = NephUICastBar:GetSize()
			frame:AdjustDimensions(width, height)

			-- fake restart the channel with a blank slate if the first cast initializing the bar was a channel
			if frame.channeling then
				frame.channeling = false
				local script = frame:GetScript("OnEvent")
				script(frame, "UNIT_SPELLCAST_CHANNEL_START")
			end

			local delayTimer = nil

			hooksecurefunc(NephUI, "UpdateCastBarLayout", function()
				if NephUICastBar == nil then
					return
				end

				if delayTimer ~= nil then
					delayTimer:Cancel()
					delayTimer = nil
				end

				delayTimer = C_Timer.NewTimer(1, function()
					local newWidth, newHeight = NephUICastBar:GetSize()

					frame:AdjustDimensions(newWidth, newHeight)

					delayTimer = nil
				end)
			end)
		end

		-- never saw this branch in practice but just to be safe
		if NephUICastBar ~= nil then
			SetupNephUICastBar()
			return
		end

		-- this will get called on each spell cast start
		hooksecurefunc(NephUI.CastBars, "GetCastBar", function()
			if NephUICastBar == nil then
				return
			end

			SetupNephUICastBar()
		end)
	end

	if
		C_AddOns.DoesAddOnExist("BetterCooldownManager")
		and C_AddOns.IsAddOnLoadable("BetterCooldownManager")
		and C_AddOns.IsAddOnLoaded("BetterCooldownManager")
		and LibStub
	then
		local ace = LibStub("AceAddon-3.0", true)

		if not ace then
			return
		end

		local ok, BetterCooldownManager = pcall(ace.GetAddon, ace, "BetterCooldownManager", true)

		if not ok or not BetterCooldownManager then
			return
		end

		hooksecurefunc(BetterCooldownManager, "OnEnable", function()
			hooksecurefunc(BCDM_CastBar, "Show", function(self)
				local width, height = self:GetSize()

				frame:AdjustDimensions(width, height)
				frame:UpdateAnchor(self.Status)
			end)
		end)
	end

	if
		C_AddOns.DoesAddOnExist("UnhaltedUnitFrames")
		and C_AddOns.IsAddOnLoadable("UnhaltedUnitFrames")
		and C_AddOns.IsAddOnLoaded("UnhaltedUnitFrames")
		and LibStub
	then
		local ace = LibStub("AceAddon-3.0", true)

		if not ace then
			return
		end

		local ok, UnhaltedUnitFrames = pcall(ace.GetAddon, ace, "UnhaltedUnitFrames", true)

		if not ok or not UnhaltedUnitFrames then
			return
		end

		hooksecurefunc(UnhaltedUnitFrames, "OnEnable", function()
			hooksecurefunc(UUF_Player_CastBar, "Show", function(self)
				local width, height = self:GetSize()

				frame:AdjustDimensions(width, height)
				frame:UpdateAnchor(self)
			end)
		end)
	end

	if
		C_AddOns.DoesAddOnExist("MidnightSimpleUnitFrames")
		and C_AddOns.IsAddOnLoadable("MidnightSimpleUnitFrames")
		and C_AddOns.IsAddOnLoaded("MidnightSimpleUnitFrames")
	then
		---@type FunctionContainer|nil
		local ticker = nil
		local attempts = 0
		local maxAttempts = 5

		-- addon is a mess, can't properly detect where/when this gets created and it takes ages to load

		ticker = C_Timer.NewTicker(1, function()
			attempts = attempts + 1

			if attempts > maxAttempts and ticker ~= nil then
				ticker:Cancel()
				ticker = nil
				return
			end

			if MSUF_PlayerCastbar == nil then
				return
			end

			if ticker ~= nil then
				ticker:Cancel()
				ticker = nil
			end

			hooksecurefunc(MSUF_PlayerCastbar, "Show", function(self)
				local width, height = self:GetSize()

				frame:AdjustDimensions(width, height)
				frame:UpdateAnchor(self.statusBar)
			end)
		end)
	end

	if
		C_AddOns.DoesAddOnExist("ActionBarsEnhanced")
		and C_AddOns.IsAddOnLoadable("ActionBarsEnhanced")
		and C_AddOns.IsAddOnLoaded("ActionBarsEnhanced")
	then
		PlayerCastingBarFrame:HookScript("OnSizeChanged", function(self)
			if frame.castBarInformation.anchor ~= self then
				return
			end

			local width, height = self:GetSize()

			frame:AdjustDimensions(width, height)
		end)
	end

	if
		C_AddOns.DoesAddOnExist("EnhanceQOL")
		and C_AddOns.IsAddOnLoadable("EnhanceQOL")
		and C_AddOns.IsAddOnLoaded("EnhanceQOL")
	then
		if EQOLPlayerCastBar then
			hooksecurefunc(EQOLPlayerCastBar, "Show", function(self)
				local width, height = self:GetSize()
				frame:AdjustDimensions(width, height)
				frame:UpdateAnchor(self)
			end)
		end

		if EQOLUFPlayerHealthCast then
			hooksecurefunc(EQOLUFPlayerHealthCast, "Show", function(self)
				local width, height = self:GetSize()
				frame:AdjustDimensions(width, height)
				frame:UpdateAnchor(self)
			end)
		end
	end

	if
		C_AddOns.DoesAddOnExist("Ayije_CDM")
		and C_AddOns.IsAddOnLoadable("Ayije_CDM")
		and C_AddOns.IsAddOnLoaded("Ayije_CDM")
		and Ayije_CastBar
	then
		hooksecurefunc(Ayije_CastBar, "Show", function(self)
			local width, height = self:GetSize()
			frame:AdjustDimensions(width, height)
			frame:UpdateAnchor(self.castBar)
		end)
	end

	if
		C_AddOns.DoesAddOnExist("AzortharionUI")
		and C_AddOns.IsAddOnLoadable("AzortharionUI")
		and C_AddOns.IsAddOnLoaded("AzortharionUI")
	then
		---@type FunctionContainer|nil
		local ticker = nil
		local attempts = 0
		local maxAttempts = 5

		ticker = C_Timer.NewTicker(1, function()
			attempts = attempts + 1

			if attempts > maxAttempts and ticker ~= nil then
				ticker:Cancel()
				ticker = nil
				return
			end

			if AUI_Castbar_player == nil then
				return
			end

			if ticker ~= nil then
				ticker:Cancel()
				ticker = nil
			end

			hooksecurefunc(AUI_Castbar_player, "Show", function(self)
				local width, height = self._castbar:GetSize()
				frame:AdjustDimensions(width, height)
				frame:UpdateAnchor(self._castbar)
			end)
		end)
	end

	if
		C_AddOns.DoesAddOnExist("EllesmereUI")
		and C_AddOns.IsAddOnLoadable("EllesmereUI")
		and C_AddOns.IsAddOnLoaded("EllesmereUI")
	then
		---@type FunctionContainer|nil
		local ticker = nil
		local attempts = 0
		local maxAttempts = 5

		ticker = C_Timer.NewTicker(1, function()
			attempts = attempts + 1

			if attempts > maxAttempts and ticker ~= nil then
				ticker:Cancel()
				ticker = nil
				return
			end

			if ERB_CastBarFrame == nil then
				return
			end

			if ticker ~= nil then
				ticker:Cancel()
				ticker = nil
			end

			hooksecurefunc(ERB_CastBarFrame, "Show", function(self)
				local width, height = self._bar:GetSize()
				frame:AdjustDimensions(width, height)
				frame:UpdateAnchor(self._bar)
			end)
		end)
	end
end)
