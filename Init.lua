---@type string
local addonName = ...

---@class CastBarInformation
---@field width number
---@field height number
---@field anchor Frame

---@class DisintegrateTicksFrame : Frame
---@field ticks Texture[]
---@field chainedTicks Texture[]
---@field maxTickMarks number
---@field maxChainedTickMarks number
---@field channeling boolean
---@field chaining boolean
---@field castBarInformation CastBarInformation
---@field RegisterSpecSpecificEvents fun(self: DisintegrateTicksFrame)
---@field UnregisterSpecSpecificEvents fun(self: DisintegrateTicksFrame)
---@field CreateTick fun(self: DisintegrateTicksFrame): Texture
---@field RebuildTickMarks fun(self: DisintegrateTicksFrame)
---@field GetHastedChannelDuration fun(self: DisintegrateTicksFrame): number

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	-- only Evokers, see classID here: https://wago.tools/db2/ChrSpecialization
	if select(3, UnitClass("player")) ~= 13 then
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
	frame.chainedTicks = {}
	frame.maxTickMarks = 2
	frame.maxChainedTickMarks = 3
	frame.channeling = false
	frame.chaining = false
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

	frame.empowers = {
		[357208] = true, -- fire breath
		[382266] = true, -- fire breath font of magic
		[359073] = true, -- eternity surge
		[382411] = true, -- eternity surge font of magic
	}
	frame.massDisintegrateStacks = 0
	frame.lastGainedStack = 0

	function frame:RegisterSpecSpecificEvents()
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		self:RegisterEvent("TRAIT_CONFIG_UPDATED")
		self:RegisterEvent("PLAYER_DEAD")
	end

	function frame:UnregisterSpecSpecificEvents()
		self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
		self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
		self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
		self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		self:UnregisterEvent("PLAYER_DEAD")
	end

	function frame:CreateTick()
		local tick = self.castBarInformation.anchor:CreateTexture(nil, "OVERLAY")

		tick:SetColorTexture(
			DisintegrateTicksSaved.Color[1],
			DisintegrateTicksSaved.Color[2],
			DisintegrateTicksSaved.Color[3],
			DisintegrateTicksSaved.Color[4]
		)
		tick:Hide()

		return tick
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

		for i = 1, #self.chainedTicks do
			self.chainedTicks[i]:SetColorTexture(color.r, color.g, color.b, color.a)
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

		if DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled then
			self:UpdateWarningPosition()
		end
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

	function frame:UpdateWarningPosition()
		self.Warning:ClearAllPoints()
		self.Warning:SetPoint(
			DisintegrateTicksSaved.MassDisintegrateClipWarning.position,
			self.castBarInformation.anchor,
			"CENTER",
			DisintegrateTicksSaved.MassDisintegrateClipWarning.x,
			DisintegrateTicksSaved.MassDisintegrateClipWarning.y
		)
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
			DisintegrateTicksSaved.MassDisintegrateClipWarning.position = point
			DisintegrateTicksSaved.MassDisintegrateClipWarning.x = x
			DisintegrateTicksSaved.MassDisintegrateClipWarning.y = y

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

	function frame:RebuildTickMarks()
		self.maxTicks = C_SpellBook.IsSpellKnown(1219723) and 5 or 4
		self.baseDuration = 3 * (C_SpellBook.IsSpellKnown(369913) and 0.8 or 1)
		self.maxTickMarks = self.maxTicks - 2
		self.maxChainedTickMarks = self.maxTickMarks + 1

		local offset = self.castBarInformation.width / (self.maxTicks - 1)

		for i = 1, self.maxTickMarks do
			if not self.ticks[i] or self.ticks[i]:GetParent() ~= self.castBarInformation.anchor then
				self.ticks[i] = self:CreateTick()
			end

			self.ticks[i]:SetSize(2, self.castBarInformation.height * 0.9)
			self.ticks[i]:ClearAllPoints()
			self.ticks[i]:SetPoint("CENTER", self.castBarInformation.anchor, "RIGHT", -(i * offset), 0)
			self.ticks[i]:Hide()
		end

		for i = 1, self.maxChainedTickMarks do
			if not self.chainedTicks[i] or self.chainedTicks[i]:GetParent() ~= self.castBarInformation.anchor then
				self.chainedTicks[i] = self:CreateTick()
			end

			self.chainedTicks[i]:SetSize(2, self.castBarInformation.height * 0.9)
			self.chainedTicks[i]:Hide()
		end
	end

	function frame:GetHastedChannelDuration()
		local haste = 1 + UnitSpellHaste("player") / 100

		return self.baseDuration / haste
	end

	---@param width number
	---@param height number
	function frame:AdjustDimensions(width, height)
		width = math.ceil(width)
		height = math.ceil(height)

		if width ~= self.castBarInformation.width or height ~= self.castBarInformation.height then
			self.castBarInformation.width = width
			self.castBarInformation.height = height
			self:RebuildTickMarks()
		end
	end

	---@param newAnchor Frame
	function frame:UpdateAnchor(newAnchor)
		if self.castBarInformation.anchor == newAnchor then
			return
		end

		self.castBarInformation.anchor = newAnchor
		self:RebuildTickMarks()
		self:UpdateWarningPosition()
	end

	if DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled then
		frame:UpdateWarningPosition()
	end

	frame:SetScript(
		"OnEvent",
		---@param self DisintegrateTicksFrame
		---@param event WowEvent
		function(self, event, ...)
			if event == "LOADING_SCREEN_DISABLED" then
				self:RebuildTickMarks()
			elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
				---@type number
				local currentSpecId = PlayerUtil.GetCurrentSpecID()

				-- only devastation and preservation. see ID columns here: https://wago.tools/db2/ChrSpecialization
				if currentSpecId == 1467 or currentSpecId == 1468 then
					self:RegisterSpecSpecificEvents()
					self:RebuildTickMarks()
				else
					self:UnregisterSpecSpecificEvents()
				end
			elseif event == "PLAYER_DEAD" then
				self.massDisintegrateStacks = 0
			elseif event == "TRAIT_CONFIG_UPDATED" then
				self:RebuildTickMarks()
			elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
				local spellId = select(3, ...)

				if self.empowers[spellId] == nil then
					return
				end

				-- mass disint check
				if not C_SpellBook.IsSpellKnownOrInSpellBook(436335) then
					return
				end

				self.massDisintegrateStacks = self.massDisintegrateStacks + 1
				self.lastGainedStack = GetTime()
			elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
				-- ignore other channels such as Fishing or quest-related casts
				if select(3, ...) ~= 356995 then
					return
				end

				if DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled and self.massDisintegrateStacks > 0 then
					local expired = GetTime() - self.lastGainedStack > 15

					if expired then
						self.massDisintegrateStacks = 0
					else
						self.Warning:Show()
						self.massDisintegrateStacks = self.massDisintegrateStacks - 1
					end
				else
					self.Warning:Hide()
				end

				if self.channeling then
					if not self.chaining then
						for i = 1, self.maxTickMarks do
							self.ticks[i]:Hide()
						end
					end

					-- local name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill, notInterruptible, spellID, isEmpowered, numEmpowerStages
					local _, _, _, startTimeMs, endTimeMs = UnitChannelInfo("player")

					local duration = (endTimeMs - startTimeMs) / 1000
					local relativeInitialTickDuration = 1 - (self:GetHastedChannelDuration() / duration)

					local initialOffset = self.castBarInformation.width * relativeInitialTickDuration
					local offset = (self.castBarInformation.width - initialOffset) / (self.maxTicks - 1)

					for i = 1, self.maxChainedTickMarks do
						self.chainedTicks[i]:ClearAllPoints()

						if i == 1 then
							if initialOffset > 0 then
								self.chainedTicks[i]:Show()
							else
								self.chainedTicks[i]:Hide()
							end

							self.chainedTicks[i]:SetPoint(
								"CENTER",
								self.castBarInformation.anchor,
								"RIGHT",
								-initialOffset,
								0
							)
						else
							self.chainedTicks[i]:SetPoint("CENTER", self.chainedTicks[i - 1], "CENTER", -offset, 0)
							self.chainedTicks[i]:Show()
						end
					end

					self.chaining = true
				else
					for i = 1, self.maxTickMarks do
						self.ticks[i]:Show()
					end

					self.channeling = true
				end
			elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
				self.Warning:Hide()

				for i = 1, #self.ticks do
					self.ticks[i]:Hide()
				end

				for i = 1, #self.chainedTicks do
					self.chainedTicks[i]:Hide()
				end

				self.channeling = false
				self.chaining = false
			end
		end
	)

	frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
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
			if frame.isChanneling then
				frame.isChanneling = false
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

		-- never saw this branch in sactice but just to be safe
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
		local function HookCastBarWhenPresent()
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
		end

		ticker = C_Timer.NewTicker(1, HookCastBarWhenPresent)
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
end)
