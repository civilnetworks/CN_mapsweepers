ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Blackout Effect"
ENT.Author = "NewPuncher"
ENT.Category = "Map Sweepers"
ENT.Spawnable = false

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "GeneratorsActive")
	self:NetworkVar("Int", 1, "MaxGenerators")
end

function ENT:Initialize()
	--print("SHARED INIT!!")
	self:SetupDataTables()
	--self:SetNoDraw(true)
	
	if CLIENT then
		timer.Simple(0.5,function()
			self:AdjustLighting()
		end)
	end
end

local function InterpLightStyle(percentage)
    local minChar = string.byte("a")
    local maxChar = string.byte("m")
    local t = math.Clamp(percentage / 100, 0, 1)

    if t < 0.5 then
       return string.char(minChar)
    else
     
        local scaledT = (t - 0.5) / 0.5
        local charCode = math.floor(minChar + (maxChar - minChar) * scaledT + 0.5)
        return string.char(charCode)
    end
 
end

function ENT:AdjustLighting()
	if SERVER then
		local lightString = InterpLightStyle(self:GetGeneratorCompletion() * 100)
		--print(lightString)
		engine.LightStyle(0,lightString)
		
		
		
		if (self:GetGeneratorCompletion() * 100) <= 75 then
			local LerpAlpha = self:GetGeneratorCompletion()/0.75
			
			local LerpFogStart = Lerp(LerpAlpha, 0, self.originalFog.FogStart or 0)
			local LerpFogEnd   = Lerp(LerpAlpha, tonumber(self.originalFog.FogEnd or 600) * 0.25, self.originalFog.FogEnd)
			
			local r, g, b = string.match(self.originalFog.FogColor or "255 255 255", "(%d+) (%d+) (%d+)")
			r, g, b = tonumber(r), tonumber(g), tonumber(b)
			
			local LerpFogColor = Color(0,0,0):Lerp(Color(r,g,b), LerpAlpha)
			
			--local LerpSkyFogStart = Lerp(LerpAlpha, 0, self.originalFog.SkyFogStart or 0)
			--local LerpSkyFogEnd   = Lerp(LerpAlpha, (self.originalFog.SkyFogEnd or 2000) * 0.25, self.originalFog.FogEnd)
			
			local r2, g2, b2 = string.match(self.originalFog.FogColor2 or "255 255 255", "(%d+) (%d+) (%d+)")
			r2, g2, b2 = tonumber(r2), tonumber(g2), tonumber(b2)
			
			local LerpSkyFogColor = Color(0,0,0):Lerp(Color(r2,g2,b2), LerpAlpha)
			
			self.fogController:SetKeyValue("fogstart", LerpFogStart)
			self.fogController:SetKeyValue("fogend", LerpFogEnd)
			self.fogController:SetKeyValue("fogcolor", string.format("%d %d %d", LerpFogColor.r, LerpFogColor.g, LerpFogColor.b))
			
			--self.fogController:SetKeyValue("skyfogstart", LerpSkyFogStart)
			--self.fogController:SetKeyValue("skyfogend", LerpSkyFogEnd)
			self.fogController:SetKeyValue("fogcolor2", string.format("%d %d %d", LerpSkyFogColor.r, LerpSkyFogColor.g, LerpSkyFogColor.b))
		else -- More than 50% completion = restore old fog settings or something 
			self:RestoreFog()
		end
		
		local SkyLerpAlpha = math.Clamp(self:GetGeneratorCompletion()/1,0,1)
		self:LerpSky(SkyLerpAlpha)
	else
		--print("client redownloading")
		render.RedownloadAllLightmaps(true, true)
	end
	--net.Start("jcms_np_blackoutupdate")
	--net.Broadcast()
end



function ENT:GetGeneratorCompletion()
	if self:GetMaxGenerators() == 0 then 
	return 0 
	else
	return self:GetGeneratorsActive() / self:GetMaxGenerators()
	end
	
end