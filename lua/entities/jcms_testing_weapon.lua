AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Author = "boblikut"

function ENT:Initialize()
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)

    local phys = self:GetPhysicsObject()
    if phys:IsValid() then
        phys:Wake()
    end
	
	if SERVER then
		self:SetUseType( SIMPLE_USE )
		if !jcms.director then return end
		local tags = jcms.director.tags_entdict
		if !tags then return end
		tags[self] = { id = "testing_weapon"..self:EntIndex(), name = "#jcms.testing_weapon", moving = false, active = self:IsValid() }
		for i, ply in ipairs(jcms.GetAliveSweepers()) do
		  if !IsValid(ply) then
			continue
		  end
		  
		  if not jcms.director.tags_perplayer[ ply ] then
			jcms.director.tags_perplayer[ ply ] = {}
		  end

		  jcms.director.tags_perplayer[ ply ][ self ] = true
		end
	end
end

function ENT:Use(activator, caller)
    if IsValid(activator) and activator:IsPlayer() then
        if self.wep_class then
			activator.jcms_canGetWeapons = true
			local class = self.wep_class
			timer.Simple(0.1, function() 
				activator:Give(class)
			end)
            timer.Simple(0.2, function() 
				activator.jcms_canGetWeapons = false
			end)
            activator:EmitSound("items/ammo_pickup.wav")
        end
		if !jcms.director then return end
		local missionData = jcms.director.missionData
		if !missionData then return end
		local testing_data = missionData.testing_data
		local is_exists = false
		for k, v in ipairs(testing_data) do
			if !v.ply and v.testing_weapon == self.wep_class and self.kills == v.npc_killed then
				v.ply = activator
				is_exists = true
				break
			end
		end
		if !is_exists then
			testing_data[#testing_data + 1] = {
				npc_killed = 0,
				testing_weapon = self.wep_class,
				ply = activator,
				testing_weapon_name = self.PrintName
			}
		end
		self:Remove()
    end
end
