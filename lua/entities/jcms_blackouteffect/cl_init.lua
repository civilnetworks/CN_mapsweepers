include("shared.lua")

function ENT:OnRemove()
	timer.Simple(0.5,function()
		render.RedownloadAllLightmaps(true, true)
	end)
end

local LastGeneratorCount = -1

function ENT:Think()
	--print("thinking")
	local GenCount = self:GetGeneratorsActive()
	--print(GenCount)
	if GenCount ~= LastGeneratorCount then
		LastGeneratorCount = GenCount
		self:AdjustLighting()
	end
end

function ENT:Draw()
end