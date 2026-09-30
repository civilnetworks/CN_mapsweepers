--[[
	Map Sweepers - Implants & Class Levels (addon)
	Deployable structures from call-ins (see sh_callins.lua). One entity, four kinds:

	  decoy    Decoy Beacon   (Recon)     hologram sweeper that pulls every nearby enemy's aggro
	  heal     Healing Station(Engineer)  pad that heals sweepers standing on it. It has a pool of healing
	                                     (cfg.charge, 200 HP) instead of a timer: every point it heals comes
	                                     out of that pool, and it shuts down when the pool is empty.
	  ammo     Ammo Cache     (Infantry)   restock box with a charge pool: press E for ammo until it's empty
	  stim     Stim Crate     (Infantry)   the same box in purple: press E for a random stim until it's empty
	  bulwark  Bulwark        (Sentinel)  big dome: enemy fire from outside is absorbed, your team can shoot out
	  totem    Taunt Totem    (Sentinel)  draws enemies to it and shocks anything close

	Tuning is in S.callins in sh_callins.lua. The entity reads it from self.cfg.
--]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Sweeper Structure"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

local KINDS = {
	decoy   = { model = "models/player/combine_super_soldier.mdl", color = Color(90, 180, 255) },
	heal    = { model = "models/hunter/tubes/circle2x2.mdl",       color = Color(90, 255, 140) },
	ammo    = { model = "models/items/item_item_crate.mdl",        color = Color(255, 190, 90) },
	stim    = { model = "models/items/item_item_crate.mdl",        color = Color(190, 130, 255) },
	bulwark = { model = "models/props_combine/combine_emitter01.mdl", color = Color(110, 190, 255) },
	totem   = { model = "models/props_combine/combine_light001a.mdl", color = Color(255, 150, 50) },
}

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Kind")
	self:NetworkVar("Float", 0, "ExpireTime")
	self:NetworkVar("Float", 1, "Radius")
	self:NetworkVar("Float", 2, "ShockRadius")
	self:NetworkVar("Int", 0, "DomeHP")
	self:NetworkVar("Int", 1, "DomeMaxHP")
	self:NetworkVar("Int", 2, "Charge")      -- healing left in a Healing Station
	self:NetworkVar("Int", 3, "MaxCharge")
end

local function isEnemy(ent)
	return IsValid(ent) and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and (not jcms.team_NPC or jcms.team_NPC(ent))
end

if SERVER then
	function ENT:Initialize()
		self.cfg = self.cfg or {}
		local kind = KINDS[self:GetKind()] or KINDS.decoy
		self:SetModel(kind.model)

		if self:GetKind() == "heal" then
			self:SetModelScale(0.75, 0)
			self:SetMaterial("models/debug/debugwhite")
			self:SetColor(Color(40, 120, 70))
		elseif self:GetKind() == "ammo" then
			self:SetMaterial("models/debug/debugwhite")
			self:SetColor(Color(150, 110, 40))
			self:SetUseType(SIMPLE_USE)
		elseif self:GetKind() == "stim" then
			self:SetMaterial("models/debug/debugwhite")
			self:SetColor(Color(110, 60, 160))
			self:SetUseType(SIMPLE_USE)
		elseif self:GetKind() == "decoy" then
			-- A hologram of whoever called it in, rather than a generic body: at a glance it reads as one
			-- of your own squad, which is the whole point of a decoy. The model is networked with the
			-- entity, so the client needs nothing extra to draw it.
			local owner = self.jcms_owner
			if IsValid(owner) and owner:IsPlayer() then
				local mdl = owner:GetModel()
				-- A playermodel in use is already precached, but a bad or missing one would leave an
				-- ERROR sign standing in the field, so fall back to the KINDS model instead.
				if isstring(mdl) and mdl ~= "" and util.IsValidModel(mdl) then
					self:SetModel(mdl)
					self:SetSkin(owner:GetSkin() or 0)
					for i = 0, self:GetNumBodyGroups() - 1 do
						self:SetBodygroup(i, owner:GetBodygroup(i))
					end
				end
			end

			self:SetMaterial("models/debug/debugwhite")
			self:SetRenderMode(RENDERMODE_TRANSALPHA)
			self:SetColor(Color(90, 180, 255, 140))

			-- Not every playermodel carries the HL2 player anim set, and LookupSequence returns -1
			-- rather than nil for a miss, so `or 0` would have happily passed -1 straight through.
			local seq = self:LookupSequence("idle_all_01")
			if not seq or seq < 0 then seq = self:LookupSequence("idle_subtle") end
			if not seq or seq < 0 then seq = 0 end
			self:ResetSequence(seq)
		end

		local mins = self:OBBMins()
		self:SetPos(self:GetPos() - Vector(0, 0, mins.z))
		self:SetAngles(Angle(0, self.faceYaw or 0, 0))

		if self:GetKind() == "decoy" then
			self:SetSolid(SOLID_BBOX)
			self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
			self:SetMoveType(MOVETYPE_NONE)
		else
			self:PhysicsInit(SOLID_VPHYSICS)
			self:SetMoveType(MOVETYPE_NONE)
			local phys = self:GetPhysicsObject()
			if IsValid(phys) then phys:EnableMotion(false) end
		end

		self:SetMaxHealth(self.cfg.health or 400)
		self:SetHealth(self:GetMaxHealth())
		-- No lifetime = no timer (the Healing Station runs on its charge instead)
		self:SetExpireTime(self.cfg.lifetime and (CurTime() + self.cfg.lifetime) or 0)
		local kind = self:GetKind()
		if kind == "heal" or kind == "ammo" or kind == "stim" then
			self:SetMaxCharge(self.cfg.charge or 200)
			self:SetCharge(self:GetMaxCharge())
		end
		self:SetRadius(self.cfg.radius or 300)
		self:SetShockRadius(self.cfg.shockRadius or 0)
		if self:GetKind() == "bulwark" then
			self:SetDomeMaxHP(self.cfg.domeHealth or 2000)
			self:SetDomeHP(self:GetDomeMaxHP())
		end

		-- Decoy / totem: an invisible target that enemies can "see" and shoot at
		if self:GetKind() == "decoy" or self:GetKind() == "totem" then
			local eye = ents.Create("jcms_bullseye")
			if IsValid(eye) then
				eye:SetPos(self:WorldSpaceCenter() + Vector(0, 0, 10))
				eye:SetParent(self)
				eye:Spawn()
				eye.DamageTarget = self
				self.bullseye = eye
			end
		end

		self.nextTick = 0
	end

	function ENT:Break(spent)
		if self.broken then return end
		self.broken = true
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter())
		util.Effect(spent and "cball_bounce" or "cball_explode", ed, true, true)
		if spent then
			-- used up rather than destroyed
			self:EmitSound("items/suitchargeno1.wav", 75, 90)
		else
			self:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 80, 90)
		end
		self:Remove()
	end

	function ENT:OnRemove()
		if IsValid(self.bullseye) then self.bullseye:Remove() end
	end

	function ENT:OnTakeDamage(dmg)
		local attacker = dmg:GetAttacker()
		if IsValid(attacker) and attacker:IsPlayer() then return end -- no friendly fire
		self:SetHealth(self:Health() - dmg:GetDamage())
		if self:Health() <= 0 then self:Break() end
	end

	-- Ammo Cache / Stim Crate: press E for a helping, taken out of the box's charge.
	function ENT:Use(activator)
		local kind = self:GetKind()
		if kind ~= "ammo" and kind ~= "stim" then return end
		if not (IsValid(activator) and activator:IsPlayer() and activator:Alive()) then return end
		if jcms.team_JCorp_player and not jcms.team_JCorp_player(activator) then return end
		if (self.nextUse or 0) > CurTime() or self:GetCharge() <= 0 then return end
		self.nextUse = CurTime() + 0.5

		local gave, cost = false, 1

		if kind == "ammo" then
			cost = math.min(self.cfg.perUse or 200, self:GetCharge())
			gave = jcms.util_TryGiveAmmo and jcms.util_TryGiveAmmo(activator, cost) or false
			if gave then self:EmitSound("items/ammopickup.wav", 70, 110) end
		else
			-- One charge = one random stim. S.GiveStim uses the stim's own duration, so the
			-- "Potent Mix" team upgrade still lengthens it the same as a crate pickup did.
			cost = math.min(self.cfg.perUse or 1, self:GetCharge())
			local id = sweeper.RandomStim and sweeper.RandomStim()
			gave = id and sweeper.GiveStim and sweeper.GiveStim(activator, id) or false
			if gave then self:EmitSound("items/smallmedkit1.wav", 70, 130) end
		end

		if gave then
			self:SetCharge(math.max(self:GetCharge() - cost, 0))
			if self:GetCharge() <= 0 then self:Break(true) end
		else
			activator:EmitSound("buttons/button10.wav", 60, 120)
		end
	end

	function ENT:Aggro()
		local eye = self.bullseye
		if not IsValid(eye) then return end
		for i, npc in ipairs(ents.FindInSphere(self:GetPos(), self:GetRadius())) do
			if isEnemy(npc) and npc:IsNPC() then
				npc:AddEntityRelationship(eye, D_HT, 99)
				if npc.SetEnemy then npc:SetEnemy(eye) end
				if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(eye, eye:GetPos()) end
			end
		end
	end

	function ENT:Think()
		local ct = CurTime()
		local expire = self:GetExpireTime()
		if expire > 0 and ct >= expire then
			self:Break()
			return
		end

		local kind = self:GetKind()
		if ct >= self.nextTick then
			if kind == "heal" then
				self.nextTick = ct + 0.25
				local perTick = (self.cfg.healPerSec or 4) * 0.25
				self.healCarry = (self.healCarry or 0) + perTick
				local amount = math.floor(self.healCarry)
				if amount > 0 then
					self.healCarry = self.healCarry - amount
					local charge = self:GetCharge()
					for i, ply in ipairs(player.GetAll()) do
						if charge <= 0 then break end
						if ply:Alive() and ply:Health() < ply:GetMaxHealth()
							and ply:GetPos():DistToSqr(self:GetPos()) <= self:GetRadius() ^ 2
							and (not jcms.team_SameTeam or not IsValid(self.jcms_owner) or jcms.team_SameTeam(self.jcms_owner, ply)) then
							-- every point of healing comes out of the station's charge
							local heal = math.min(amount, charge, ply:GetMaxHealth() - ply:Health())
							if heal > 0 then
								ply:SetHealth(ply:Health() + heal)
								charge = charge - heal
								if not self.healSoundAt or ct - self.healSoundAt > 1 then
									self.healSoundAt = ct
									self:EmitSound("items/medshot4.wav", 60, 120, 0.4)
								end
							end
						end
					end
					if charge ~= self:GetCharge() then self:SetCharge(math.max(charge, 0)) end
					if self:GetCharge() <= 0 then
						self:Break(true)
						return
					end
				end

			elseif kind == "decoy" then
				self.nextTick = ct + 0.5
				self:Aggro()

			elseif kind == "totem" then
				self.nextTick = ct + 1
				self:Aggro()
				-- Shock anything close
				local shockR = self.cfg.shockRadius or 200
				for i, ent in ipairs(ents.FindInSphere(self:GetPos(), shockR)) do
					if isEnemy(ent) then
						local dmg = DamageInfo()
						dmg:SetAttacker(IsValid(self.jcms_owner) and self.jcms_owner or self)
						dmg:SetInflictor(self)
						dmg:SetDamage(self.cfg.shockDamage or 20)
						dmg:SetDamageType(DMG_SHOCK)
						dmg:SetDamagePosition(ent:WorldSpaceCenter())
						ent:TakeDamageInfo(dmg)

						local ed = EffectData()
						ed:SetEntity(ent)
						ed:SetMagnitude(3)
						ed:SetScale(1)
						util.Effect("TeslaHitBoxes", ed, true, true)
					end
				end
				self:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", 65, 110, 0.6)
			else
				self.nextTick = ct + 1
			end
		end

		self:NextThink(ct)
		return true
	end
end

if CLIENT then
	local matGlow = Material("sprites/light_glow02_add")

	-- Every kind gets the restock box's label: a title, an optional USE prompt, and the "what's left"
	-- lines under it - a charge pool where there is one, otherwise the lifetime countdown.
	local LABELS = {
		decoy   = { title = "Decoy Beacon" },
		bulwark = { title = "Bulwark",         shield = true },
		totem   = { title = "Taunt Totem" },
		heal    = { title = "Healing Station", pool = "Health Inside: %d" },
		ammo    = { title = "Ammo Cache",      pool = "Ammo Inside: %d",   use = true },
		stim    = { title = "Stim Crate",      pool = "Stims Inside: %d",  use = true },
	}

	-- nil means there's nothing left to report, so the label is skipped entirely
	local function labelLines(ent, def)
		if def.pool then
			local charge = ent:GetCharge()
			if charge <= 0 then return nil end
			return { string.format(def.pool, charge) }
		end

		local left = ent:GetExpireTime() - CurTime()
		if left <= 0 then return nil end

		local lines = {}
		if def.shield then lines[1] = string.format("Shield Inside: %d", ent:GetDomeHP()) end
		lines[#lines + 1] = string.format("Time Left: %.1fs", left)
		return lines
	end

	-- One pass of the label. The gamemode draws it twice: dark, then bright and additive a unit up.
	local function labelPass(def, lines, binding, bright)
		local cTitle = bright and jcms.color_bright or jcms.color_dark
		local cSub = bright and jcms.color_bright_alt or jcms.color_dark_alt

		draw.SimpleText(def.title, "jcms_hud_small", 0, -16, cTitle, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		local bth = 0
		if binding then
			local _, h = draw.SimpleText(binding, "jcms_hud_big", 0, bright and -1 or 0, cSub, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			bth = h
		end
		for i, line in ipairs(lines) do
			draw.SimpleText(line, "jcms_medium", 0, bth - 4 + (i - 1) * 16, cSub, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	end

	function ENT:Draw()
		local kind = self:GetKind()
		if kind == "decoy" then
			-- flickering hologram
			local a = 110 + math.sin(CurTime() * 20 + self:EntIndex()) * 30
			render.SetBlend(a / 255)
			render.SetColorModulation(0.35, 0.7, 1)
			self:DrawModel()
			render.SetColorModulation(1, 1, 1)
			render.SetBlend(1)
		else
			self:DrawModel()
		end
	end

	function ENT:DrawTranslucent()
		local kind = self:GetKind()
		local col = (KINDS[kind] or KINDS.decoy).color
		local pos, r = self:GetPos(), self:GetRadius()

		if kind == "bulwark" then
			local frac = math.Clamp(self:GetDomeHP() / math.max(self:GetDomeMaxHP(), 1), 0, 1)
			local center = pos + Vector(0, 0, 10)
			render.SetColorMaterial()
			render.DrawSphere(center, r, 32, 32, Color(col.r, col.g, col.b, 20 + 25 * frac))
			render.DrawSphere(center, -r, 32, 32, Color(col.r, col.g, col.b, 12 + 18 * frac))
			render.DrawWireframeSphere(center, r, 16, 16, Color(col.r, col.g, col.b, 40 + 100 * frac), true)
		elseif kind ~= "decoy" then
			-- The decoy gets nothing here. It's meant to pass for a sweeper standing in the open, and a
			-- glow hovering in its chest gave it away instantly - the hologram is the effect now.
			-- No ground ring either: the glow and the label say where it is well enough. The Bulwark keeps
			-- its dome above because that dome IS the effect, not a marker drawn around it.
			render.SetMaterial(matGlow)
			local pulse = 40 + math.sin(CurTime() * 4) * 12
			render.DrawSprite(self:WorldSpaceCenter() + Vector(0, 0, kind == "heal" and 10 or 30), pulse, pulse, Color(col.r, col.g, col.b, 180))
		end

		-- Label in the gamemode restock box's own layout (jcms_restock.lua): a billboard facing the
		-- player, drawn twice - dark, then bright and additive one unit up, so it matches the HUD.
		local def = LABELS[kind]
		if not def or LocalPlayer():GetPos():DistToSqr(pos) >= 1200 ^ 2 then return end

		local lines = labelLines(self, def)
		if not lines then return end

		local binding = def.use and ("[ " .. tostring(input.LookupBinding("+use") or "USE"):upper() .. " ]") or nil

		local v = self:WorldSpaceCenter()
		v.z = v.z + 32
		local a = (EyePos() - v):Angle()
		a:RotateAroundAxis(a:Right(), -90)
		a:RotateAroundAxis(a:Up(), 90)

		cam.Start3D2D(v, a, 1 / 8)
			labelPass(def, lines, binding, false)
		cam.End3D2D()

		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		v:Add(a:Up())
		cam.Start3D2D(v, a, 1 / 8)
			labelPass(def, lines, binding, true)
		cam.End3D2D()
		render.OverrideBlend(false)
	end
end
