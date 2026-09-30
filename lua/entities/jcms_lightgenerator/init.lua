AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_vehicles/generatortrailer01.mdl")
    
	self:SetSolid(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	self:DrawShadow(false)
	
	self:SetColor(Color(255,0,0))
end

function ENT:Think()
	if self:GetIsPowered() and (not self.ChargeSound or not self.ChargeSound:IsPlaying()) then
			
		self.ChargeSound = CreateSound(self, "ambient/machines/diesel_engine_idle1.wav")
		self.ChargeSound:PlayEx(1, 110)
		self.ChargeSound:SetSoundLevel(100)
	end
	
	if self:GetIsPowered() and not self.GeneratorLight then
		self.GeneratorLight = ents.Create("light_dynamic")
		self.GeneratorLight:SetPos(self:GetPos())
        self.GeneratorLight:SetParent(self) -- Follow this entity
        self.GeneratorLight:SetKeyValue("_light", "255 200 100 255") -- R G B Brightness
        self.GeneratorLight:SetKeyValue("distance", "300") -- Light radius
        self.GeneratorLight:SetKeyValue("brightness", "2")
        self.GeneratorLight:Spawn()
        self.GeneratorLight:Activate()

        -- Turn the light on
        self.GeneratorLight:Fire("TurnOn", "", 0)
	end
end
