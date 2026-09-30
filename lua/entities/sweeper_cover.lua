--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Sentinel Deployable Cover. Spawned by the skills_cover call-in.
--]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Deployable Cover"
ENT.Spawnable = false

ENT.Model = "models/props_combine/combine_barricade_short01a.mdl"

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "ExpireTime")
end

if SERVER then
	function ENT:Initialize()
		self.cfg = self.cfg or {}
		self:SetModel(self.Model)

		-- Turn the barricade so its long side faces where the player was looking
		local mins, maxs = self:OBBMins(), self:OBBMaxs()
		local yaw = self.faceYaw or 0
		if (maxs.x - mins.x) > (maxs.y - mins.y) then
			yaw = yaw + 90
		end
		self:SetAngles(Angle(0, yaw, 0))

		-- Sit on the ground
		self:SetPos(self:GetPos() - Vector(0, 0, mins.z))

		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end

		self:SetMaxHealth(self.cfg.health or 600)
		self:SetHealth(self:GetMaxHealth())
		self:SetExpireTime(CurTime() + (self.cfg.lifetime or 120))
	end

	function ENT:Break()
		if self.broken then return end
		self.broken = true
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter())
		ed:SetMagnitude(2)
		ed:SetScale(2)
		util.Effect("Sparks", ed, true, true)
		self:EmitSound("physics/metal/metal_box_break1.wav", 80, 90)
		self:Remove()
	end

	function ENT:OnTakeDamage(dmg)
		local attacker = dmg:GetAttacker()
		local owner = self.jcms_owner
		-- Friendly fire doesn't wear it down
		if IsValid(attacker) and IsValid(owner) and (attacker == owner or
			(attacker:IsPlayer() and jcms.team_SameTeam(attacker, owner))) then
			return
		end

		self:SetHealth(self:Health() - dmg:GetDamage())

		-- Darken as it takes damage
		local frac = math.Clamp(self:Health() / self:GetMaxHealth(), 0, 1)
		local v = 90 + 165 * frac
		self:SetColor(Color(v, v, v))

		if self:Health() <= 0 then
			self:Break()
		end
	end

	function ENT:Think()
		if CurTime() >= self:GetExpireTime() then
			self:Break()
			return
		end
		self:NextThink(CurTime() + 0.5)
		return true
	end
end

if CLIENT then
	function ENT:Draw()
		self:DrawModel()
	end
end
