ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Casino Terminal"
ENT.Author = "NewPuncher"
ENT.Category = "Map Sweepers"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Converted")
	self:NetworkVar("Bool", 1, "ReportBought")
	
	self:NetworkVar("Int", 0, "Income")
	self:NetworkVar("Int", 1, "UniqueReward")
	self:NetworkVar("Int", 2, "RGGDisplayType")
	self:NetworkVar("Int", 3, "NextIncomeTime")
	self:NetworkVar("Int", 4, "ID")
end

function ENT:Initialize()
	self:SetupDataTables()
	
end

function ENT:GetSharedMultiplier()
	if SERVER then
		return jcms.runprogress_GetDifficulty()
	else
		return self:GetMultiplier()
	end
end

function ENT:CalcBaseIncomeAmount()
	local Multi = self:GetSharedMultiplier()
	return math.ceil(math.Clamp(60 + ((self:GetID() - 1 ) *15) * Multi,20,750))
end

function ENT:GetReportPrice()
	local Multi = self:GetSharedMultiplier()
	return math.ceil(math.Clamp(1000 + ((self:GetID() - 1 ) *500) * Multi,1000,10000))
end