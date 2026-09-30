AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:RestoreFog()
    local fog = self.fogController
    if self.hasFogController then
        fog:SetKeyValue("fogstart", self.originalFog.FogStart or "0")
        fog:SetKeyValue("fogend", self.originalFog.FogEnd or "2000")
        fog:SetKeyValue("fogcolor", self.originalFog.FogColor or "255 255 255")
        fog:SetKeyValue("fogmaxdensity", self.originalFog.FogMaxDensity or "1")
        fog:SetKeyValue("useskyboxfog", self.originalFog.UseSkyboxFog or "0")
		fog:SetKeyValue("skyfogstart", self.originalFog.SkyFogStart or "0")
        fog:SetKeyValue("skyfogend", self.originalFog.SkyFogEnd or "2000")
        fog:SetKeyValue("skyfogcolor", self.originalFog.SkyFogColor or "255 255 255")
	else
		if IsValid(fog) then
			fog:Remove()
			self.fogController = nil
		end
    end
end

function ENT:RestoreSky()
	local currentSky = GetConVar("sv_skyname"):GetString()
	for side, col in pairs(self.OriginalSkyColors) do
		Material("skybox/" .. currentSky .. side):SetVector("$color", col)
	end
	
	if self.SunEnv then
		self.SunEnv:Fire("TurnOn")
	end
end

function ENT:LerpSky(Alpha)
	local sides = {"rt", "lf", "ft", "bk", "up", "dn"}
	local currentSky = GetConVar("sv_skyname"):GetString()

	for _, side in ipairs(sides) do
		local mat = Material("skybox/" .. currentSky .. side)
		local OGCol = self.OriginalSkyColors[side]
		
		if not IsValid(OGCol) then continue end
		
		local LValue = LerpVector(Alpha, Vector(0.05,0.05,0.05),OGCol)
		mat:SetVector("$color", LValue) -- darken
	end
end

function ENT:ModifySky(strength)
	local sides = {"rt", "lf", "ft", "bk", "up", "dn"}
	local currentSky = GetConVar("sv_skyname"):GetString()

	for _, side in ipairs(sides) do
		local mat = Material("skybox/" .. currentSky .. side)
		if not self.OriginalSkyColors[side] then
			self.OriginalSkyColors[side] = mat:GetVector("$color") -- cache
		end
		mat:SetVector("$color", strength or Vector(0.05, 0.05, 0.05)) -- darken
	end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function ENT:OnRemove()
	
	engine.LightStyle(0, "m") -- might screw up some maps but oh well mr garrington newtron we humbly request for getting lightstyle string or something

	if self.fogController then
		self:RestoreFog()
	end
	self:RestoreSky()
end

function ENT:Initialize()

	engine.LightStyle(0, "a") -- activate darkness
	
	if not self.OriginalSkyColors then
		self.OriginalSkyColors = {}
	end

	self:ModifySky()
	
	local fog = ents.FindByClass("env_fog_controller")[1] 
	self.hasFogController = IsValid(fog)
	if not fog then 
		fog = ents.Create("env_fog_controller")
	end
	self.fogController = fog 
	
	self.originalFog = {}
	
	local SunEnv = ents.FindByClass("env_sun")[1] 
	if IsValid(SunEnv) then
		self.SunEnv = SunEnv
		SunEnv:Fire("TurnOff")
	end
	
	if IsValid(fog) then
        local kv = fog:GetKeyValues()
        self.originalFog = {
            FogStart = kv.fogstart,
            FogEnd = kv.fogend,
            FogColor = kv.fogcolor,
            FogMaxDensity = kv.fogmaxdensity,
            UseSkyboxFog = kv.useskyboxfog,
			FogColor2 = kv.fogcolor2
        }
	else
		self.originalFog = {
            FogStart = "0",
            FogEnd = "600",
            FogColor = "0 0 0",
            FogMaxDensity = "1",
			FogColor2 = "0 0 0"
        }
    end
	
    fog:SetKeyValue("fogcolor", "0 0 0")
    fog:SetKeyValue("fogstart", "0")
	local FEnd = tonumber(self.originalFog.FogEnd) * 0.25
	if FEnd <= 1 then
		FEnd = "600"
	end
	
	
    fog:SetKeyValue("fogend", FEnd)
    fog:SetKeyValue("fogmaxdensity", "1")
	fog:SetKeyValue("fogcolor2", "0 0 0")
    fog:Spawn()
    fog:Fire("TurnOn", "", 0)
	fog:Activate()
	
	self:AdjustLighting()
end

function ENT:Draw()
end