--[[
	Map Sweepers - Implants & Class Levels (addon)
	Salvage Crate: the carryable objective for the Salvage Run mission (sh_mission_salvage.lua).

	Press E to pick it up and carry it in front of you like any prop - the engine's own +USE
	carry does the holding, so it bumps into doorways and drops if you shove it into something.
	Press E again to let go. While you're carrying, you're slowed, you can't shoot, and every
	hostile nearby wants you specifically.

	Carry state is tracked by the OnPlayerPhysicsPickup / OnPlayerPhysicsDrop hooks in
	sh_mission_salvage.lua, which is what sets and clears our Carrier.
--]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Salvage Crate"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Carrier")
end

local function cfg()
	local c = sweeper and sweeper.salvageMission
	return c or { carryAggroRange = 1400, crateMass = 35, hitForceMul = 1, hitForceMax = 60000 }
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/items/item_item_crate.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:SetMass(cfg().crateMass)
			phys:Wake()
		end

		-- base_anim ignores damage by default, which also means nothing can shove it.
		-- Turn damage on so hits reach OnTakeDamage; it still has no health to lose.
		self:SetSaveValue("m_takedamage", 2)

		self.nextAggro = 0
		self.nextUse = 0
		self.jcms_homePos = self:GetPos()
		self:NextThink(CurTime() + 0.25)
	end

	-- Indestructible cargo that still gets knocked around: bullets, buckshot, the stunstick,
	-- explosions, anything. We apply the impulse ourselves and never touch its health.
	function ENT:OnTakeDamage(dmg)
		-- Don't fight the carry controller while someone's holding it.
		if IsValid(self:GetCarrier()) then return end

		local phys = self:GetPhysicsObject()
		if not IsValid(phys) then return end

		local force = dmg:GetDamageForce()

		-- Melee and a few weapons don't fill in a force, so build one from the hit direction.
		if force:LengthSqr() < 1 then
			local dir = self:WorldSpaceCenter() - dmg:GetDamagePosition()
			if dir:LengthSqr() < 1 then
				local attacker = dmg:GetAttacker()
				dir = IsValid(attacker) and (self:WorldSpaceCenter() - attacker:WorldSpaceCenter()) or self:GetForward()
			end
			dir:Normalize()
			force = dir * math.max(10, dmg:GetDamage()) * 300
		end

		force = force * (cfg().hitForceMul or 1)

		-- Keep a rocket from launching it into orbit.
		local cap = cfg().hitForceMax or 60000
		if force:LengthSqr() > cap * cap then
			force:Normalize()
			force:Mul(cap)
		end

		phys:Wake()
		phys:ApplyForceOffset(force, dmg:GetDamagePosition())
	end

	-- If something flings it out of the map, put it back where it started.
	function ENT:Rescue()
		local home = self.jcms_homePos
		if not home then return end

		self:SetPos(home + Vector(0, 0, 8))
		self:SetAngles( Angle(0, math.random(0, 359), 0) )

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:SetVelocity(vector_origin)
			phys:SetAngleVelocity(vector_origin)
			phys:Wake()
		end
	end

	-- Plain Source +USE carry: E picks it up, E lets go. Nothing beyond handing the crate to
	-- the engine's own pickup controller.
	function ENT:Use(activator)
		if CurTime() < self.nextUse then return end
		if not (IsValid(activator) and activator:IsPlayer() and activator:Alive()) then return end
		if jcms.team_JCorp_player and not jcms.team_JCorp_player(activator) then return end

		self.nextUse = CurTime() + 0.3

		local carrier = self:GetCarrier()
		if IsValid(carrier) then
			if activator == carrier then activator:DropObject() end
			return
		end

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:Wake() end

		activator:PickupObject(self)
	end

	-- Everything hostile within range wants the person holding the crate.
	function ENT:AggroOnCarrier()
		local carrier = self:GetCarrier()
		if not IsValid(carrier) then return end

		for i, npc in ipairs(ents.FindInSphere(carrier:GetPos(), cfg().carryAggroRange)) do
			if npc:IsNPC() and npc:Health() > 0 and jcms.team_NPC(npc) then
				if npc.AddEntityRelationship then npc:AddEntityRelationship(carrier, D_HT, 90) end
				npc:SetEnemy(carrier)
				npc:UpdateEnemyMemory(carrier, carrier:GetPos())
			end
		end
	end

	function ENT:Think()
		local ct = CurTime()
		self:NextThink(ct + 0.25)

		local carrier = self:GetCarrier()
		if IsValid(carrier) then
			if not (carrier:IsPlayer() and carrier:Alive()) then
				-- The engine drops it on death, but clear our own bookkeeping either way.
				carrier:SetNWEntity("sweeper_carrying", NULL)
				self:SetCarrier(NULL)
			elseif ct > self.nextAggro then
				self.nextAggro = ct + 1
				self:AggroOnCarrier()
			end
		else
			local pos = self:GetPos()
			if not util.IsInWorld(pos) or pos.z < -16000 then
				self:Rescue()
			end
		end

		return true
	end

	function ENT:OnRemove()
		local carrier = self:GetCarrier()
		if IsValid(carrier) and carrier:IsPlayer() then
			carrier:SetNWEntity("sweeper_carrying", NULL)
		end
	end
else
	local matGlow = Material("sprites/light_glow02_add")

	function ENT:Draw()
		self:DrawModel()
	end

	-- Glow only. No floating labels - the HUD tag already names it.
	function ENT:DrawTranslucent()
		if IsValid(self:GetCarrier()) then return end

		local top = self:WorldSpaceCenter() + Vector(0, 0, 22)
		render.SetMaterial(matGlow)
		local pulse = 26 + math.sin(CurTime() * 3) * 6
		render.DrawSprite(top, pulse, pulse, Color(255, 200, 80, 180))
	end
end
