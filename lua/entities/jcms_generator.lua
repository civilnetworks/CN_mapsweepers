AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Generator"
ENT.Author = "boblikut"
ENT.Category = "Map Sweepers"

function ENT:Initialize()
	if SERVER then
		self.hp = 1
		self:SetModel("models/props_c17/substation_circuitbreaker01a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		local phys = self:GetPhysicsObject()
		if phys:IsValid() then
			phys:EnableMotion(false)
		end
		self:SetColor(Color(255,0,0))
	end
end

function ENT:StartTouch( ent )
	if ent:GetClass() == "jcms_energy_block" then
		ent:Remove()
		BroadcastLua('surface.PlaySound("weapons/airboat/airboat_gun_energy"..math.random(1,2)..".wav")')
		self.hp = self.hp - 1
		if self.hp <= 0 then
			self:EmitSound("ambient/energy/force_field_loop1.wav", SNDLVL_180dB, 100, 1, CHAN_STREAM, SND_CHANGE_VOL)
			self:SetNWBool("working", true)
		end
	end
end