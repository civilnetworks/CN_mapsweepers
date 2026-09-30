--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Engineer drones (Combat / Repair). Spawned by the skills_drone_* call-ins.
--]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Engineer Drone"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

local MODELS = {
	combat = "models/combine_scanner.mdl",
	repair = "models/shield_scanner.mdl",
}

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "DroneType")
	self:NetworkVar("Entity", 0, "DroneOwner")
	self:NetworkVar("Entity", 1, "BeamTarget1")
	self:NetworkVar("Entity", 2, "BeamTarget2")
	self:NetworkVar("Entity", 3, "BeamTarget3")
	self:NetworkVar("Float", 0, "ExpireTime")
end

if SERVER then
	function ENT:Initialize()
		self.cfg = self.cfg or {}
		self:SetModel(MODELS[self:GetDroneType()] or MODELS.combat)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionBounds(Vector(-14, -14, -12), Vector(14, 14, 12))
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON) -- bullets hit it, players walk through

		self:SetMaxHealth(self.cfg.health or 150)
		self:SetHealth(self:GetMaxHealth())
		self:SetExpireTime(CurTime() + (self.cfg.lifetime or 180))

		self.orbitOffset = math.Rand(0, math.pi * 2)
		self.nextFire = 0
		self.nextSearch = 0
		self.nextHeal = 0
		self.burstLeft = 0

		local seq = self:LookupSequence("idle")
		if seq and seq >= 0 then self:ResetSequence(seq) end
	end

	local function isEnemyOf(owner, ent)
		if not jcms.team_GoodTarget(ent) or ent:IsPlayer() then return false end
		if not (ent:IsNPC() or ent:IsNextBot()) then return false end
		if IsValid(owner) and jcms.team_SameTeam(owner, ent) then return false end
		return true
	end

	function ENT:CanSee(pos, ent)
		local tr = util.TraceLine({
			start = self:GetPos(),
			endpos = pos,
			filter = { self, self.jcms_owner },
			mask = MASK_SHOT,
		})
		return tr.Entity == ent or tr.Fraction > 0.98
	end

	function ENT:FindTarget()
		local owner = self.jcms_owner
		local best, bestDist = nil, math.huge
		local myPos = self:GetPos()
		for i, ent in ipairs(ents.FindInSphere(myPos, self.cfg.range or 1200)) do
			if isEnemyOf(owner, ent) then
				local d = ent:WorldSpaceCenter():DistToSqr(myPos)
				if d < bestDist and self:CanSee(ent:WorldSpaceCenter(), ent) then
					best, bestDist = ent, d
				end
			end
		end
		return best
	end

	function ENT:Die()
		local ed = EffectData()
		ed:SetOrigin(self:GetPos())
		util.Effect("Explosion", ed, true, true)
		self:Remove()
	end

	function ENT:OnTakeDamage(dmg)
		local attacker = dmg:GetAttacker()
		-- Friendly fire doesn't hurt drones
		if IsValid(attacker) and IsValid(self.jcms_owner) and (attacker == self.jcms_owner or
			(attacker:IsPlayer() and jcms.team_SameTeam(attacker, self.jcms_owner))) then
			return
		end

		self:SetHealth(self:Health() - dmg:GetDamage())
		if self:Health() <= 0 and not self.dying then
			self.dying = true
			self:Die()
		end
	end

	function ENT:MoveToOwner()
		local owner = self.jcms_owner
		if not (IsValid(owner) and owner:Alive()) then return end

		local t = CurTime() * 0.8 + self.orbitOffset
		local anchor = owner:GetPos() + Vector(0, 0, 95)
		local desired = anchor + Vector(math.cos(t) * 55, math.sin(t) * 55, math.sin(t * 2) * 8)

		-- Don't go through walls/ceilings
		local tr = util.TraceHull({
			start = owner:EyePos(),
			endpos = desired,
			mins = Vector(-12, -12, -10), maxs = Vector(12, 12, 10),
			filter = { self, owner },
			mask = MASK_SOLID_BRUSHONLY,
		})
		desired = tr.HitPos

		local pos = self:GetPos()
		if pos:DistToSqr(desired) > 1500 ^ 2 then
			self:SetPos(desired) -- owner teleported or fell far: catch up instantly
		else
			self:SetPos(LerpVector(0.12, pos, desired))
		end
	end

	function ENT:ThinkCombat()
		local ct = CurTime()
		if ct >= self.nextSearch then
			self.nextSearch = ct + 0.4
			self.target = self:FindTarget()
		end

		local target = self.target
		if IsValid(target) and isEnemyOf(self.jcms_owner, target) then
			local aimPos = target:WorldSpaceCenter()
			local dir = (aimPos - self:GetPos()):GetNormalized()
			self:SetAngles(LerpAngle(0.3, self:GetAngles(), dir:Angle()))

			if ct >= self.nextFire and self:CanSee(aimPos, target) then
				if self.burstLeft <= 0 then
					self.burstLeft = 4
				end
				self.burstLeft = self.burstLeft - 1
				self.nextFire = ct + (self.burstLeft <= 0 and 0.45 or (self.cfg.fireDelay or 0.12))

				self:FireBullets({
					Attacker = IsValid(self.jcms_owner) and self.jcms_owner or self,
					Src = self:GetPos() + dir * 16,
					Dir = dir,
					Spread = Vector(0.02, 0.02, 0),
					Damage = self.cfg.damage or 20,
					Force = 10,
					Num = 1,
					Tracer = 1,
					TracerName = "AR2Tracer",
					IgnoreEntity = self.jcms_owner,
				})
				self:EmitSound("NPC_FloorTurret.Shoot", 70, 125, 0.5)
			end
		else
			self.target = nil
			local owner = self.jcms_owner
			if IsValid(owner) then
				self:SetAngles(LerpAngle(0.1, self:GetAngles(), Angle(0, owner:EyeAngles().y, 0)))
			end
		end
	end

	function ENT:ThinkRepair()
		local ct = CurTime()
		if ct < self.nextHeal then return end
		self.nextHeal = ct + 0.5

		local owner = self.jcms_owner
		local myPos = self:GetPos()
		local range = self.cfg.range or 400
		local beams = {}

		for i, ent in ipairs(ents.FindInSphere(myPos, range)) do
			if #beams >= 3 then break end

			if ent == self then
				-- skip
			elseif ent:IsPlayer() then
				if ent:Alive() and ent:GetObserverMode() == OBS_MODE_NONE and ent:Health() < ent:GetMaxHealth()
					and (ent == owner or (IsValid(owner) and jcms.team_SameTeam(owner, ent)))
					and self:CanSee(ent:WorldSpaceCenter(), ent) then
					ent:SetHealth(math.min(ent:Health() + (self.cfg.healPlayers or 3), ent:GetMaxHealth()))
					table.insert(beams, ent)
				end
			elseif IsValid(owner) and ent.jcms_owner == owner and ent:GetClass() ~= "sweeper_drone"
				and ent:GetMaxHealth() > 0 and ent:Health() > 0 and ent:Health() < ent:GetMaxHealth() then
				ent:SetHealth(math.min(ent:Health() + (self.cfg.repairDeployables or 8), ent:GetMaxHealth()))
				table.insert(beams, ent)
			end
		end

		self:SetBeamTarget1(beams[1] or NULL)
		self:SetBeamTarget2(beams[2] or NULL)
		self:SetBeamTarget3(beams[3] or NULL)

		if IsValid(owner) then
			self:SetAngles(LerpAngle(0.3, self:GetAngles(), Angle(0, owner:EyeAngles().y, 0)))
		end
	end

	function ENT:Think()
		if CurTime() >= self:GetExpireTime() then
			self:EmitSound("npc/scanner/scanner_siren2.wav", 70, 140, 0.5)
			local ed = EffectData()
			ed:SetOrigin(self:GetPos())
			util.Effect("cball_explode", ed, true, true)
			self:Remove()
			return
		end

		self:MoveToOwner()
		if self:GetDroneType() == "repair" then
			self:ThinkRepair()
		else
			self:ThinkCombat()
		end

		self:NextThink(CurTime() + 0.05)
		return true
	end
end

if CLIENT then
	local matBeam = Material("jcms/beam_heal.png", "smooth")
	local matGlow = Material("sprites/light_glow02_add")
	local colCombat = Color(255, 60, 40)
	local colRepair = Color(80, 255, 120)

	function ENT:Draw()
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
		local repair = self:GetDroneType() == "repair"
		local col = repair and colRepair or colCombat

		render.SetMaterial(matGlow)
		render.DrawSprite(self:GetPos(), 24, 24, col)

		if repair then
			render.SetMaterial(matBeam)
			local start = self:GetPos()
			local scroll = CurTime() * 2
			for i, target in ipairs({ self:GetBeamTarget1(), self:GetBeamTarget2(), self:GetBeamTarget3() }) do
				if IsValid(target) then
					local endPos = target:WorldSpaceCenter()
					render.DrawBeam(start, endPos, 6, scroll, scroll + start:Distance(endPos) / 64, col)
				end
			end
		end
	end
end
