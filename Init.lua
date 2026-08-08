---@type string
local addonName = ...

---@class CastBarHandle
---@field id string
---@field anchor Frame
---@field textFrame FontString|nil
---@field width number
---@field height number
---@field priority number
---@field ticks Texture[]
---@field isActive (fun(self: CastBarHandle): boolean)|nil provider-specific check beyond `:IsShown()`

---@class CastBarProvider
---@field id string
---@field addon string|nil
---@field priority number
---@field isEnabled fun(): boolean
---@field register fun(registry: CastBarRegistry, frame: DisintegrateTicksFrame)

---@class CastBarRegistry
---@field providers CastBarProvider[]
---@field handles table<string, CastBarHandle>
---@field RegisterProvider fun(self: CastBarRegistry, provider: CastBarProvider)
---@field EnsureHandle fun(self: CastBarRegistry, id: string, anchor: Frame, priority: number, textFrame: FontString|nil): CastBarHandle
---@field GetHandle fun(self: CastBarRegistry, id: string): CastBarHandle|nil
---@field SyncDimensions fun(self: CastBarRegistry, id: string, anchor: Frame)
---@field GetVisibleBars fun(self: CastBarRegistry): CastBarHandle[]
---@field GetPrimaryHandle fun(self: CastBarRegistry): CastBarHandle|nil
---@field ResolveWithRetry fun(self: CastBarRegistry, resolve: fun(): Frame|nil, callback: fun(anchor: Frame), maxAttempts: number?, interval: number?)
---@field frame DisintegrateTicksFrame

---@class DisintegrateTicksFrame : Frame
---@field private maxTicks number
---@field private activeChannelDuration number|nil
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
---@field primaryHandle CastBarHandle|nil
---@field RegisterSpecSpecificEvents fun(self: DisintegrateTicksFrame)
---@field UnregisterSpecSpecificEvents fun(self: DisintegrateTicksFrame)
---@field CreateTick fun(self: DisintegrateTicksFrame, handle: CastBarHandle): Texture
---@field HideTicks fun(self: DisintegrateTicksFrame, handle: CastBarHandle|nil)
---@field UpdateHandleTicks fun(self: DisintegrateTicksFrame, handle: CastBarHandle, duration: number)
---@field UpdateTicksAll fun(self: DisintegrateTicksFrame, duration: number)
---@field QueryTalentsAndHide fun(self: DisintegrateTicksFrame)
---@field UpdateHandleDimensions fun(self: DisintegrateTicksFrame, id: string, width: number, height: number)
---@field RefreshPrimaryHandle fun(self: DisintegrateTicksFrame)
---@field OnCastBarShown fun(self: DisintegrateTicksFrame, id: string, anchor: Frame, textFrame: FontString|nil, priority: number)
---@field OnCastBarHidden fun(self: DisintegrateTicksFrame, id: string)
---@field KnowsMassDisintegrate fun(self: DisintegrateTicksFrame): boolean
---@field OnEvent fun(self: DisintegrateTicksFrame, event: WowEvent, ...: any)

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	-- only Evokers, see classID here: https://wago.tools/db2/ChrSpecialization
	if select(3, UnitClass("player")) ~= Constants.UICharacterClasses.Evoker then
		return
	end

	---@type CastBarRegistry
	local CastBarRegistry = {
		providers = {},
		handles = {},
	}

	function CastBarRegistry:RegisterProvider(provider)
		table.insert(self.providers, provider)

		if provider.isEnabled() then
			provider.register(self, self.frame)
		elseif provider.addon ~= nil then
			EventUtil.ContinueOnAddOnLoaded(provider.addon, function()
				if provider.isEnabled() then
					provider.register(self, self.frame)
				end
			end)
		end
	end

	---@return CastBarHandle
	function CastBarRegistry:EnsureHandle(id, anchor, priority, textFrame)
		local handle = self.handles[id]

		if handle == nil then
			handle = {
				id = id,
				anchor = anchor,
				textFrame = textFrame,
				width = 0,
				height = 0,
				priority = priority,
				ticks = {},
			}
			self.handles[id] = handle
		else
			handle.anchor = anchor
			handle.textFrame = textFrame
			handle.priority = priority
		end

		return handle
	end

	---@return CastBarHandle|nil
	function CastBarRegistry:GetHandle(id)
		return self.handles[id]
	end

	function CastBarRegistry:SyncDimensions(id, anchor)
		local handle = self:GetHandle(id)

		if handle == nil or anchor == nil then
			return
		end

		local width, height = anchor:GetSize()

		self.frame:UpdateHandleDimensions(id, math.ceil(width), math.ceil(height))
	end

	-- all currently shown bars, highest priority first. two providers may resolve to the
	-- same physical frame (e.g. ActionBarsEnhanced restyling the default bar), so dedupe by
	-- frame pointer to avoid stacking duplicate ticks on top of each other.
	---@return CastBarHandle[]
	function CastBarRegistry:GetVisibleBars()
		---@type CastBarHandle[]
		local candidates = {}

		for _, handle in pairs(self.handles) do
			if handle.anchor ~= nil and handle.anchor:IsShown() then
				if handle.isActive == nil or handle.isActive(handle) then
					table.insert(candidates, handle)
				end
			end
		end

		table.sort(candidates, function(a, b)
			if a.priority == b.priority then
				return a.id < b.id
			end

			return a.priority > b.priority
		end)

		---@type CastBarHandle[]
		local visible = {}
		local seen = {}

		for _, handle in ipairs(candidates) do
			if not seen[handle.anchor] then
				seen[handle.anchor] = true
				table.insert(visible, handle)
			end
		end

		return visible
	end

	---@return CastBarHandle|nil
	function CastBarRegistry:GetPrimaryHandle()
		local visible = self:GetVisibleBars()

		if visible[1] ~= nil then
			return visible[1]
		end

		local bestFallback = nil

		for _, handle in pairs(self.handles) do
			if handle.anchor ~= nil and (not bestFallback or handle.priority > bestFallback.priority) then
				bestFallback = handle
			end
		end

		return bestFallback
	end

	function CastBarRegistry:ResolveWithRetry(resolve, callback, maxAttempts, interval)
		maxAttempts = maxAttempts or 5
		interval = interval or 1

		local immediate = resolve()

		if immediate ~= nil then
			callback(immediate)
			return
		end

		local attempts = 0
		---@type FunctionContainer|nil
		local ticker = nil

		ticker = C_Timer.NewTicker(interval, function()
			attempts = attempts + 1

			local anchor = resolve()

			if anchor ~= nil then
				if ticker ~= nil then
					ticker:Cancel()
				end

				callback(anchor)
				return
			end

			if attempts >= maxAttempts and ticker ~= nil then
				ticker:Cancel()
			end
		end)
	end

	local massDisintegrateName = C_Spell.GetSpellName(436335)


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
	CastBarRegistry.frame = frame
	frame.maxTicks = 4
	frame.activeChannelDuration = nil
	frame.channeling = false
	frame.chaining = false
	frame.lastStart = 0
	frame.firstTick = 0
	frame.prevHastedTickInterval = nil
	frame.massDisintegrateStacks = 0
	frame.lastGainedStack = 0
	frame.hasTipTheScalesActive = false
	frame.lastKnownHaste = 0
	frame.primaryHandle = nil
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

	function frame:CreateTick(handle)
		local tick = handle.anchor:CreateTexture(nil, "OVERLAY")

		tick:SetColorTexture(
			DisintegrateTicksSaved.Color[1],
			DisintegrateTicksSaved.Color[2],
			DisintegrateTicksSaved.Color[3],
			DisintegrateTicksSaved.Color[4]
		)
		tick:Hide()

		return tick
	end

	-- omitting the handle hides the ticks of every registered bar
	function frame:HideTicks(handle)
		if handle ~= nil then
			for _, tick in next, handle.ticks do
				tick:Hide()
			end

			return
		end

		for _, registered in pairs(CastBarRegistry.handles) do
			for _, tick in next, registered.ticks do
				tick:Hide()
			end
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

	function frame:UpdateHandleTicks(handle, duration)
		if handle.anchor == nil or handle.width <= 0 or duration == nil or duration <= 0 then
			return
		end

		self:HideTicks(handle)

		local hastedTickInterval = self:GetTickInterval() / self:GetHaste()
		local pixelsPerSecond = handle.width / duration

		for i = 1, self.maxTicks do
			local tick = handle.ticks[i]

			-- the bar frame may have been recreated by its provider, reparent by recreating
			if tick == nil or tick:GetParent() ~= handle.anchor then
				tick = self:CreateTick(handle)
				handle.ticks[i] = tick
			end

			tick:SetSize(2, handle.height * 0.95)
			tick:ClearAllPoints()

			local tickTime = i * hastedTickInterval

			if self.chaining then
				local interval = (duration - self.firstTick) / (self.maxTicks - 1)
				tickTime = self.firstTick + (i - 1) * interval
			end

			tick:SetPoint("CENTER", handle.anchor, "LEFT", (duration - tickTime) * pixelsPerSecond, 0)

			if tickTime < duration * 0.99 then
				tick:Show()
			else
				tick:Hide()
			end
		end
	end

	function frame:UpdateTicksAll(duration)
		if duration == nil or duration <= 0 then
			return
		end

		self.activeChannelDuration = duration

		self:HideTicks()

		for _, handle in ipairs(CastBarRegistry:GetVisibleBars()) do
			self:UpdateHandleTicks(handle, duration)
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

		for _, handle in pairs(CastBarRegistry.handles) do
			for _, tick in next, handle.ticks do
				tick:SetColorTexture(color.r, color.g, color.b, color.a)
			end
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
		local anchor = self.primaryHandle and self.primaryHandle.anchor

		if DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled and anchor ~= nil then
			self.Warning:ClearAllPoints()
			self.Warning:SetPoint(
				DisintegrateTicksSaved.MassDisintegrateClipWarning.point,
				anchor,
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

	function frame:UpdateHandleDimensions(id, width, height)
		local handle = CastBarRegistry:GetHandle(id)

		if handle == nil then
			return
		end

		if width ~= handle.width or height ~= handle.height then
			handle.width = width
			handle.height = height

			if self.channeling and self.activeChannelDuration ~= nil then
				self:UpdateHandleTicks(handle, self.activeChannelDuration)
			else
				self:HideTicks(handle)
			end
		end
	end

	function frame:RefreshPrimaryHandle()
		local primary = CastBarRegistry:GetPrimaryHandle()

		if primary ~= nil and self.primaryHandle ~= primary then
			self.primaryHandle = primary
			self:MaybeUpdateWarningPosition()
		end
	end

	function frame:OnCastBarShown(id, anchor, textFrame, priority)
		CastBarRegistry:EnsureHandle(id, anchor, priority, textFrame)
		CastBarRegistry:SyncDimensions(id, anchor)
		self:RefreshPrimaryHandle()

		if self.channeling and self.activeChannelDuration ~= nil then
			local handle = CastBarRegistry:GetHandle(id)

			if handle ~= nil then
				self:UpdateHandleTicks(handle, self.activeChannelDuration)
			end
		end
	end

	function frame:OnCastBarHidden(id)
		local handle = CastBarRegistry:GetHandle(id)

		if handle ~= nil then
			self:HideTicks(handle)
		end

		self:RefreshPrimaryHandle()
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

			if spellId == 358267 then
				self:RefreshPrimaryHandle()
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

			self:RefreshPrimaryHandle()

			if self.massDisintegrateStacks > 0 then
				local expired = GetTime() - self.lastGainedStack > 15

				if expired then
					self.massDisintegrateStacks = 0
				else
					local textFrame = self.primaryHandle and self.primaryHandle.textFrame

					if textFrame ~= nil then
						textFrame:SetText(massDisintegrateName)
					end

					if DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled then
						self.Warning:Show()
					end

					self.massDisintegrateStacks = self.massDisintegrateStacks - 1
				end

				if not DisintegrateTicksSaved.MassDisintegrateClipWarning.enabled then
					self.Warning:Hide()
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

			self:UpdateTicksAll(nextEndTime - startTime)
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
			self.activeChannelDuration = nil
		end
	end

	frame:MaybeUpdateWarningPosition()
	frame:SetScript("OnEvent", frame.OnEvent)

	frame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
	frame:RegisterEvent("LOADING_SCREEN_DISABLED")
	frame:RegisterSpecSpecificEvents()

	local function RegisterBlizzardCastBarProvider()
		local blizzardId = "blizzard"
		local overlayId = "blizzard_overlay"

		local handle = CastBarRegistry:EnsureHandle(blizzardId, PlayerCastingBarFrame, 10, PlayerCastingBarFrame.Text)

		-- a replacement bar may keep the frame shown while CastingBarMixin suppresses it,
		-- see CastingBarMixin:UpdateShownState in Blizzard's CastingBarFrame.lua
		---@class BlizzardCastBar : Frame
		---@field showCastbar boolean|nil
		handle.isActive = function(self)
			local anchor = self.anchor
			---@cast anchor BlizzardCastBar
			return anchor.showCastbar ~= false and GameRulesUtil.ShouldShowPlayerCastBar()
		end

		frame:OnCastBarShown(blizzardId, PlayerCastingBarFrame, PlayerCastingBarFrame.Text, 10)

		PlayerCastingBarFrame:HookScript("OnShow", function(self)
			frame:OnCastBarShown(blizzardId, self, self.Text, 10)
		end)

		PlayerCastingBarFrame:HookScript("OnHide", function()
			frame:OnCastBarHidden(blizzardId)
		end)

		PlayerCastingBarFrame:HookScript("OnSizeChanged", function(self)
			CastBarRegistry:SyncDimensions(blizzardId, self)
		end)

		hooksecurefunc(PlayerCastingBarFrame, "SetLook", function(self)
			CastBarRegistry:SyncDimensions(blizzardId, self)
		end)

		hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", function()
			CastBarRegistry:SyncDimensions(blizzardId, PlayerCastingBarFrame)
			frame:RefreshPrimaryHandle()
		end)

		EventRegistry:RegisterCallback("OverlayPlayerCastBar.OnShow", function()
			frame:OnCastBarShown(
				overlayId,
				OverlayPlayerCastingBarFrame,
				OverlayPlayerCastingBarFrame.Text,
				12
			)
		end, frame)

		EventRegistry:RegisterCallback("OverlayPlayerCastBar.OnHide", function()
			frame:OnCastBarHidden(overlayId)
		end, frame)
	end

	CastBarRegistry:RegisterProvider({
		id = "blizzard",
		addon = nil,
		priority = 10,
		isEnabled = function()
			return true
		end,
		register = function(registry, owner)
			RegisterBlizzardCastBarProvider()
		end,
	})

	---@class ThirdPartyCastBarFrame : Frame
	---@field statusBar Frame|nil
	---@field castBar Frame|nil
	---@field _castbar Frame|nil
	---@field _bar Frame|nil
	---@field Text FontString|nil

	---@class ThirdPartyCastBar
	---@field id string
	---@field addon string
	---@field priority number
	---@field container fun(): ThirdPartyCastBarFrame|nil the frame the addon shows/hides
	---@field anchor fun(container: ThirdPartyCastBarFrame): Frame|nil the status bar ticks attach to
	---@field text (fun(container: ThirdPartyCastBarFrame): FontString|nil)|nil

	---@type ThirdPartyCastBar[]
	local thirdPartyCastBars = {
		{
			id = "msuf",
			addon = "MidnightSimpleUnitFrames",
			priority = 50,
			container = function()
				return MSUF_PlayerCastbar
			end,
			anchor = function(container)
				return container.statusBar
			end,
		},
		{
			id = "eqol_castbar",
			addon = "EnhanceQOL",
			priority = 40,
			container = function()
				return EQOLPlayerCastBar
			end,
			anchor = function(container)
				return container
			end,
			text = function(container)
				return container.Text
			end,
		},
		{
			id = "eqol_uf",
			addon = "EnhanceQOL",
			priority = 40,
			container = function()
				return EQOLUFPlayerHealthCast
			end,
			anchor = function(container)
				return container
			end,
			text = function(container)
				return container.Text
			end,
		},
		{
			id = "ayije_cdm",
			addon = "Ayije_CDM",
			priority = 45,
			container = function()
				return Ayije_CastBar
			end,
			anchor = function(container)
				return container.castBar
			end,
		},
		{
			id = "azortharion",
			addon = "AzortharionUI",
			priority = 45,
			container = function()
				return AUI_Castbar_player
			end,
			anchor = function(container)
				return container._castbar
			end,
		},
		{
			id = "ellesmere",
			addon = "EllesmereUI",
			priority = 45,
			container = function()
				return ERB_CastBarFrame
			end,
			anchor = function(container)
				return container._bar
			end,
		},
	}

	for _, castBar in ipairs(thirdPartyCastBars) do
		CastBarRegistry:RegisterProvider({
			id = castBar.id,
			addon = castBar.addon,
			priority = castBar.priority,
			isEnabled = function()
				local loadedOrLoading = C_AddOns.IsAddOnLoaded(castBar.addon)
				return loadedOrLoading
			end,
			register = function(registry, owner)
				-- some of these globals are created well after their addon finished loading
				local function Resolve()
					local container = castBar.container()

					if container == nil or castBar.anchor(container) == nil then
						return nil
					end

					return container
				end

				local function Retry(container)
					local function Sync()
						local anchor = castBar.anchor(container)

						if anchor == nil then
							return
						end

						owner:OnCastBarShown(
							castBar.id,
							anchor,
							castBar.text ~= nil and castBar.text(container) or nil,
							castBar.priority
						)
					end

					local function OnHide()
						owner:OnCastBarHidden(castBar.id)
					end

					Sync()

					-- OnShow/OnHide also covers SetShown and parent visibility changes,
					-- fall back to the plain methods for frames without script handlers
					if container.HookScript ~= nil then
						container:HookScript("OnShow", Sync)
						container:HookScript("OnHide", OnHide)
					else
						hooksecurefunc(container, "Show", Sync)
						hooksecurefunc(container, "Hide", OnHide)
					end
				end

				registry:ResolveWithRetry(Resolve, Retry)
			end,
		})
	end
end)
