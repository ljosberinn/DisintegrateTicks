-- only Evokers, see classID here: https://wago.tools/db2/ChrSpecialization
if select(3, UnitClass("player")) ~= 13 then
	return
end

---@class DisintegrateTicksFrame : Frame
---@field ticks Texture[]
---@field chainedTicks Texture[]
---@field maxTickMarks number
---@field maxChainedTickMarks number
---@field channeling boolean
---@field chaining boolean
---@field castBarDimensions table<'width' | 'height', number>
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
frame.castBarDimensions = {
	width = 0,
	height = 0,
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
	local tick = PlayerCastingBarFrame:CreateTexture(nil, "OVERLAY")

	tick:SetColorTexture(1, 1, 1, 1)
	tick:SetSize(2, self.castBarDimensions.height * 0.9)
	tick:Hide()

	return tick
end

function frame:RebuildTickMarks()
	self.maxTicks = C_SpellBook.IsSpellKnown(1219723) and 5 or 4
	self.baseDuration = 3 * (C_SpellBook.IsSpellKnown(369913) and 0.8 or 1)
	self.maxTickMarks = self.maxTicks - 2
	self.maxChainedTickMarks = self.maxTickMarks + 1

	local offset = self.castBarDimensions.width / (self.maxTicks - 1)

	for i = 1, self.maxTickMarks do
		if not self.ticks[i] then
			self.ticks[i] = self:CreateTick()
		end

		self.ticks[i]:ClearAllPoints()
		self.ticks[i]:SetPoint("CENTER", PlayerCastingBarFrame, "RIGHT", -(i * offset), 0)
		self.ticks[i]:Hide()
	end

	for i = 1, self.maxChainedTickMarks do
		if not self.chainedTicks[i] then
			self.chainedTicks[i] = self:CreateTick()
		end

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

				local initialOffset = self.castBarDimensions.width * relativeInitialTickDuration
				local offset = (self.castBarDimensions.width - initialOffset) / (self.maxTicks - 1)

				for i = 1, self.maxChainedTickMarks do
					self.chainedTicks[i]:ClearAllPoints()

					if i == 1 then
						if initialOffset > 0 then
							self.chainedTicks[i]:Show()
						else
							self.chainedTicks[i]:Hide()
						end

						self.chainedTicks[i]:SetPoint("CENTER", PlayerCastingBarFrame, "RIGHT", -initialOffset, 0)
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

	frame.castBarDimensions.width = lockToPlayerFrame and 150 or 208
	frame.castBarDimensions.height = lockToPlayerFrame and 10 or 11
	frame:RebuildTickMarks()
end)
