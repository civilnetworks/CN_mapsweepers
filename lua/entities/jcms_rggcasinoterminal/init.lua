--models/props_phx/rt_screen.mdl
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_phx/rt_screen.mdl")
    self:SetModelScale(2, 0)
    
	self:SetColor(Color(127,0,255))
	self:SetSolid(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	self:DrawShadow(false)
	
	self:SetRGGDisplayType(math.random(1,3))
	self:SetNWFloat("DMult",jcms.runprogress_GetDifficulty())
end

function ENT:ConvertToJCorp()
	self:SetConverted(true)
	self:SetColor(Color(255,0,0))
	self:SetRGGDisplayType(math.random(1,3))
	self:SetIncome(self:CalcBaseIncomeAmount())
end

function ENT:Think()
	if self:GetConverted() then
		if not self.IncomeTimer then	
			self.IncomeTimer = CurTime() + 30
		end
		
		if not self.NextIncomeTime then
			self:SetNextIncomeTime(self.IncomeTimer)
		end
		
		if CurTime() >= self.IncomeTimer then
			self.IncomeTimer = CurTime() + 30
			
			for _, ply in pairs(player.GetAll()) do
				if ply:Alive() and IsValid(ply) then
					ply:SetNWInt("jcms_cash", ply:GetNWInt("jcms_cash", 0) + self:GetIncome())
					jcms.net_SendCashEarn(ply,self:GetIncome())
				end
			end
		end
	end
	
	self:NextThink(CurTime())
end