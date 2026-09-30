include("shared.lua")

function ENT:Draw()
	self:DrawModel()
end


local FlashColors = {Color(255,255,0,127),Color(127,0,255,127)}
local JCorpSplashTexts = {
	"Wait, why the fuck are we mining J?",
	"Totally Legitmiate Place of Business! TM",
	"Crushing your hopes and dreams with our offices!",
}

function ENT:MouseHovering(MX,MY,X,Y,W,H)
	local ply = LocalPlayer()
	return (MX>=X and MY>=Y and MX<=X+W and MY<=Y+H) and ply:Alive() and IsValid(ply) and self:GetPos():Distance(ply:GetPos()) <= 200 
end

function ENT:GetMultiplier() -- cache this value so we not running it every frame innit
	if not self.cacheMultiplier then
		self.cacheMultiplier = self:GetNWFloat("DMult",1)
	end
	return self.cacheMultiplier
end

local useBind = input.LookupBinding("+use")
local useKey = input.GetKeyCode(useBind)

local lastUseState = false

function ENT:DrawTranslucent()
	if not IsValid(self) then return end

	local DisplayType = self:GetRGGDisplayType() or 1
	local Converted = self:GetConverted() or false
	
	local pos = self:LocalToWorld(Vector(15, 0, 65))
	local ang = self:LocalToWorldAngles(Angle(0, 0, 0))
	ang:RotateAroundAxis(ang:Right(), -90)
	ang:RotateAroundAxis(ang:Up(), 90)
	
	local RouletteNumbers = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24}

	
	if not self.ClockTime then
		self.ClockTime = 0
	end
	
	function GetNextRouletteNumbs()
	
		if not self.RouletteCurrentPosition then
			self.RouletteCurrentPosition = 1 -- start at 0 (not confusing yes!)
		end
		
		if not self.NextNumberShift then
			self.NextNumberShift = 0
		end
		
		self.NextNumberShift = self.NextNumberShift + FrameTime()
		
		if self.NextNumberShift >= 0.15 then
			self.RouletteCurrentPosition = self.RouletteCurrentPosition + 1
			if self.RouletteCurrentPosition > #RouletteNumbers then
				self.RouletteCurrentPosition = 1
			end
			self.NextNumberShift = 0
		end
		
		local wrappedValues = {}
		
		for i = -4, 4 do
			local index = ((self.RouletteCurrentPosition  + i - 1) % #RouletteNumbers) + 1
			table.insert(wrappedValues, RouletteNumbers[index])
		end
		
		return wrappedValues
	end
	
	local useKeyDown = LocalPlayer():KeyDown(IN_USE) and not gui.IsGameUIVisible()
	
	
	-- RGG Screens
	cam.Start3D2D(pos, ang, 0.2)
	if not Converted then
		self.ClockTime = self.ClockTime + FrameTime()
		
		if self.ClockTime >= 10 then
			self.ClockTime = 0
		end
		
        draw.SimpleTextOutlined(
            "R.G.G",
            "jcms_hud_big",
            math.Rand(-2,2), math.Rand(-1,1),
            Color(127, 0, 255,127),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(15, 15, 15,15)
        )
   
		if DisplayType == 1 then -- Slots
			draw.SimpleTextOutlined(
				"PLAY SLOTS TODAY!",
				"jcms_hud_medium",
				math.Rand(-2,2), 65 + math.Rand(-1,1),
				Color(127, 0, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			
			draw.SimpleTextOutlined(
				"$$ WIN BIG PRIZES! $$",
				"jcms_hud_medium",
				math.Rand(-2,2), 125 + math.Rand(-1,1),
				Color(127, 0, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			
			if self.ClockTime >= 2 then
				draw.SimpleTextOutlined(
				self.ClockTime <= 3.5 and math.floor(math.Rand(1,9)) or "7",
				"jcms_hud_big",
				-115+ math.Rand(-2,2), 225 + math.Rand(-1,1),
				self.ClockTime <= 7 and Color(127, 0, 255,127) or Color(255, 255, 0,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			
			draw.SimpleTextOutlined(
				self.ClockTime <= 4.5 and math.floor(math.Rand(1,9)) or "7",
				"jcms_hud_big",
				math.Rand(-2,2), 225 + math.Rand(-1,1),
				self.ClockTime <= 7.5 and Color(127, 0, 255,127) or Color(255, 255, 0,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			
			draw.SimpleTextOutlined(
				self.ClockTime <= 5.5 and math.floor(math.Rand(1,9)) or "7",
				"jcms_hud_big",
				115 + math.Rand(-2,2), 225 + math.Rand(-1,1),
				self.ClockTime <= 8 and Color(127, 0, 255,127) or Color(255, 255, 0,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			end
		elseif DisplayType == 2 then -- Triple or Nothing Tuesdays
			
			if not self.NextFlash then
				self.NextFlash = 0
				self.FlashIndex = 1
				self.FlashColor = Color(255,255,0,127)
			end

			self.NextFlash = self.NextFlash + FrameTime()
			
			if self.NextFlash >= 0.2 then
				self.NextFlash = 0
				self.FlashIndex = self.FlashIndex + 1
				
				if self.FlashIndex > 2 then 
					self.FlashIndex = 1
				end
				
				self.FlashColor = FlashColors[self.FlashIndex]
			end
		
			draw.SimpleTextOutlined(
				"TRIPLE OR NOTHING",
				"jcms_hud_medium",
				math.Rand(-2,2), 65 + math.Rand(-1,1),
				Color(127, 0, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			draw.SimpleTextOutlined(
				"TUESDAYS ARE BACK!",
				"jcms_hud_medium",
				math.Rand(-2,2), 110 + math.Rand(-1,1),
				Color(127, 0, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			if math.floor(self.ClockTime) % 2 == 0 then
				draw.SimpleTextOutlined(
				"$$$$",
				"jcms_hud_big",
				math.Rand(-2,2), 200 + math.Rand(-1,1),
				FlashColors[self.FlashIndex],
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			else
				draw.SimpleTextOutlined(
					"X3 X3 X3",
					"jcms_hud_big",
					math.Rand(-2,2), 200 + math.Rand(-1,1),
					FlashColors[self.FlashIndex],
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER,
					1,
					Color(15, 15, 15,15)
				)
			end
		else -- Roulette 
			draw.SimpleTextOutlined(
				"ALWAYS BET ON",
				"jcms_hud_medium",
				math.Rand(-2,2), 65 + math.Rand(-1,1),
				Color(127, 0, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			
			draw.SimpleTextOutlined(
				"GREEN!!",
				"jcms_hud_big",
				math.Rand(-2,2), 140 + math.Rand(-1,1),
				Color(127, 0, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			
			local Values = GetNextRouletteNumbs()
			for i, val in pairs(Values) do
				draw.SimpleTextOutlined(
					val,
					"jcms_hud_medium",
					(-260 + (65*(i-1))) + math.Rand(-2,2), 220 + math.Rand(-1,1),
					val == 0 and Color(0,255,0,127) or val % 2 == 0 and Color(255, 0, 0,127) or Color(80,80,80,127),
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER,
					1,
					Color(15, 15, 15,15)
				)
			end
		end
	else -- J Corp Screen
		draw.SimpleTextOutlined(
			"J-Corp",
			"jcms_hud_big",
			-270, 0,
			Color(255, 0, 0,127),
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER,
			1,
			Color(15, 15, 15,15)
		)
		draw.SimpleTextOutlined(
			JCorpSplashTexts[DisplayType],
			"jcms_small",
			-270, 50,
			Color(255, 0, 0,127),
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER,
			1,
			Color(15, 15, 15,15)
		)
		
		-- UNIQUE REWARD
		
		local CurrentRewardInfo = jcms.np_upgradeinfo[self:GetUniqueReward() or 1] or jcms.np_upgradeinfo[1]
		
		draw.SimpleTextOutlined(
			CurrentRewardInfo.Name,
			"jcms_big",
			-270, 80,
			Color(255, 0, 0,127),
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER,
			1,
			Color(15, 15, 15,15)
		)
		
		for i, descText in pairs(CurrentRewardInfo.DescriptionLines) do
			draw.SimpleTextOutlined(
			descText,
			"jcms_medium",
			-270, 110+((i-1)*20),
			Color(255, 0, 0,127),
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER,
			1,
			Color(15, 15, 15,15)
		)
		end
		
		local ply = LocalPlayer()
		
		local BuyPosX, BuyPosY = 170, 75
		local BuyBW, BuyBH = 100,20
		local MX,MY = jcms.terminal_GetCursor(pos, ang:Up())
		MX,MY = (MX / 32) * 5, (MY / 32) * 5
		
		local HoveringOnBuyButton = self:MouseHovering(MX,MY,BuyPosX,BuyPosY,BuyBW,BuyBH) 
		
		-- BUY UPGRADE
		if useKeyDown and not lastUseState and HoveringOnBuyButton and not jcms.np_has_upgradetag(ply,self:GetUniqueReward()) then
			
			if ply:GetNWInt("jcms_cash",0) >= CurrentRewardInfo.Cost then
				self:EmitSound("buttons/button15.wav")
				net.Start("jcms_np_upg")
				net.WriteUInt(self:GetUniqueReward(),4)
				net.SendToServer()
			else
				self:EmitSound("buttons/button8.wav")
			end
		end

		
		if ply:Alive() and IsValid(ply) then
			if not jcms.np_has_upgradetag(ply,self:GetUniqueReward()) then
			draw.SimpleTextOutlined(
				CurrentRewardInfo.Cost.." J",
				"jcms_medium",
				220,60,
				Color(255, 0, 0,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			draw.RoundedBox(
				0,
				BuyPosX,BuyPosY,
				BuyBW,
				BuyBH,
				HoveringOnBuyButton and Color(255,0,0,200) or Color(255,0,0,40)
			)
			draw.SimpleTextOutlined(
				"BUY",
				"jcms_medium",
				220,85,
				Color(255, 255, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			else
			draw.SimpleTextOutlined(
				"SOLD.",
				"jcms_medium",
				220,85,
				Color(255, 0, 0,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			end
		end
		
		-- BUSINESS REPORT
		local ReportPrice = self:GetReportPrice()
		
		local ReportsX, ReportsY = 170, 235
		local ReportsBW, ReportsBH = 100,20
		
		local HoveringOnBusinessReport = self:MouseHovering(MX,MY,ReportsX,ReportsY,ReportsBW,ReportsBH) 
		
		if self:GetReportBought() then
		draw.SimpleTextOutlined(
			"BUSINESS REPORT SENT",
			"jcms_hud_small",
			-275, 245,
			Color(255, 0, 0,127),
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER,
			1,
			Color(15, 15, 15,15)
		)
		
		else
		draw.SimpleTextOutlined(
			"SEND BUSINESS REPORT: "..ReportPrice.." J",
			"jcms_hud_small",
			-275, 245,
			Color(255, 0, 0,127),
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER,
			1,
			Color(15, 15, 15,15)
		)
		
		draw.RoundedBox(
				0,
				ReportsX,ReportsY,
				ReportsBW,
				ReportsBH,
				HoveringOnBusinessReport and Color(255,0,0,200) or Color(255,0,0,40)
			)
		
		draw.SimpleTextOutlined(
				"BUY",
				"jcms_medium",
				220,245,
				Color(255, 255, 255,127),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER,
				1,
				Color(15, 15, 15,15)
			)
			
		end
		
		if useKeyDown and not lastUseState and HoveringOnBusinessReport and not self:GetReportBought() then
			
		 
			if ply:GetNWInt("jcms_cash",0) >= ReportPrice then
				self:EmitSound("buttons/button5.wav")
				net.Start("jcms_np_buyreport")
				net.WriteEntity(self)
				net.SendToServer()
			else
				self:EmitSound("buttons/button8.wav")
			end
		end
		
		
		
		
		-- INCOME
		
		draw.SimpleTextOutlined(
			"Income: "..(self:GetIncome() or 0) .. " J",
			"jcms_hud_small",
			-275, 275,
			Color(255, 0, 0,127),
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER,
			1,
			Color(15, 15, 15,15)
		)
		
		local NextIncomeTime = self:GetNextIncomeTime() or 1
		
		draw.RoundedBox(
			3,
			-275,290,
			math.Clamp((( NextIncomeTime - CurTime() )/30) * 560,0,560),
			10,
			Color(255,0,0,127)
		)
		
	end
	
	lastUseState = useKeyDown
	
    cam.End3D2D()
end