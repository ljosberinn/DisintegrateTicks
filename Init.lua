-- only Evokers, see classID here: https://wago.tools/db2/ChrSpecialization
if select(3, UnitClass("player")) ~= 13 then
	return
end

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

---@class DisintegrateTicksFrame
local frame = CreateFrame("Frame")
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

function frame:RegisterSpecSpecificEvents()
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
	frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
end

function frame:UnregisterSpecSpecificEvents()
	frame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	frame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
	frame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
end

function frame:CreateTick()
	local tick = frame.castBarInformation.anchor:CreateTexture(nil, "OVERLAY")

	tick:SetColorTexture(1, 1, 1, 1)
	tick:Hide()

	return tick
end

function frame:RebuildTickMarks()
	self.maxTicks = C_SpellBook.IsSpellKnown(1219723) and 5 or 4
	self.baseDuration = 3 * (C_SpellBook.IsSpellKnown(369913) and 0.8 or 1)
	self.maxTickMarks = self.maxTicks - 2
	self.maxChainedTickMarks = self.maxTickMarks + 1

	local offset = self.castBarInformation.width / (self.maxTicks - 1)

	for i = 1, self.maxTickMarks do
		if not self.ticks[i] or self.ticks[i]:GetParent() ~= frame.castBarInformation.anchor then
			self.ticks[i] = self:CreateTick()
		end

		self.ticks[i]:SetSize(2, self.castBarInformation.height * 0.9)
		self.ticks[i]:ClearAllPoints()
		self.ticks[i]:SetPoint("CENTER", frame.castBarInformation.anchor, "RIGHT", -(i * offset), 0)
		self.ticks[i]:Hide()
	end

	for i = 1, self.maxChainedTickMarks do
		if not self.chainedTicks[i] or self.chainedTicks[i]:GetParent() ~= frame.castBarInformation.anchor then
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

			-- only devastation. see ID columns here: https://wago.tools/db2/ChrSpecialization
			if currentSpecId == 1467 then
				self:RegisterSpecSpecificEvents()
				self:RebuildTickMarks()
			else
				self:UnregisterSpecSpecificEvents()
			end
		elseif event == "TRAIT_CONFIG_UPDATED" then
			self:RebuildTickMarks()
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
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
							frame.castBarInformation.anchor,
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

	frame.castBarInformation.width = lockToPlayerFrame and 150 or 208
	frame.castBarInformation.height = lockToPlayerFrame and 10 or 11
	frame:RebuildTickMarks()
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
		frame.castBarInformation.width = width
		frame.castBarInformation.height = height

		frame:RebuildTickMarks()

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

				if newWidth == frame.castBarInformation.width and newHeight == frame.castBarInformation.height then
					return
				end

				frame.castBarInformation.width = newWidth
				frame.castBarInformation.height = newHeight

				frame:RebuildTickMarks()

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

	local castBarEnabled = true

	-- first boot doesn't have them yet
	if BCDMDB then
		local profileCount = 0

		for _, profile in pairs(BCDMDB.profiles) do
			profileCount = profileCount + 1

			-- no point looking beyond
			if profileCount > 2 then
				break
			end
		end

		if profileCount == 1 then
			for _, profile in pairs(BCDMDB.profiles) do
				castBarEnabled = profile.CastBar.Enabled
			end
		end
	end

	hooksecurefunc(BetterCooldownManager, "OnEnable", function()
		local function HookAndAdjustCastBar()
			if BCDM_CastBar == nil then
				return
			end

			frame.castBarInformation.anchor = BCDM_CastBar.Status

			local width, height = BCDM_CastBar:GetSize()
			frame.castBarInformation.width = width
			frame.castBarInformation.height = height

			frame:RebuildTickMarks()

			local delayTimer = nil

			hooksecurefunc(BCDM_CastBar, "SetSize", function(self, newWidth, newHeight)
				if delayTimer ~= nil then
					delayTimer:Cancel()
					delayTimer = nil
				end

				delayTimer = C_Timer.NewTimer(1, function()
					if newWidth == frame.castBarInformation.width and newHeight == frame.castBarInformation.height then
						return
					end

					frame.castBarInformation.width = newWidth
					frame.castBarInformation.height = newHeight

					frame:RebuildTickMarks()

					delayTimer = nil
				end)
			end)
		end

		if castBarEnabled then
			HookAndAdjustCastBar()
		else
			local initialized = false

			hooksecurefunc(BCDM_CastBar, "Show", function()
				if initialized then
					return
				end

				initialized = true

				HookAndAdjustCastBar()
			end)
		end
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

	local castBarEnabled = true

	-- first boot doesn't have them yet
	if UnhaltedUFDB then
		local profileCount = 0

		for _, profile in pairs(UnhaltedUFDB.profiles) do
			profileCount = profileCount + 1

			-- no point looking beyond
			if profileCount > 2 then
				break
			end
		end

		if profileCount == 1 then
			for _, profile in pairs(UnhaltedUFDB.profiles) do
				castBarEnabled = profile.player.CastBar.Enabled
			end
		end
	end

	hooksecurefunc(UnhaltedUnitFrames, "OnEnable", function()
		local function HookAndAdjustCastBar()
			if UUF_Player_CastBar == nil then
				return
			end

			frame.castBarInformation.anchor = UUF_Player_CastBar

			local width, height = UUF_Player_CastBar:GetSize()
			frame.castBarInformation.width = width
			frame.castBarInformation.height = height

			frame:RebuildTickMarks()

			local delayTimer = nil

			hooksecurefunc(UUF_Player_CastBar, "SetSize", function(self, newWidth, newHeight)
				if delayTimer ~= nil then
					delayTimer:Cancel()
					delayTimer = nil
				end

				delayTimer = C_Timer.NewTimer(1, function()
					if newWidth == frame.castBarInformation.width and newHeight == frame.castBarInformation.height then
						return
					end

					frame.castBarInformation.width = newWidth
					frame.castBarInformation.height = newHeight

					frame:RebuildTickMarks()

					delayTimer = nil
				end)
			end)
		end

		if castBarEnabled then
			HookAndAdjustCastBar()
		else
			local initialized = false

			hooksecurefunc(UUF_Player_CastBar, "Show", function()
				if initialized then
					return
				end

				initialized = true

				HookAndAdjustCastBar()
			end)
		end
	end)
end
