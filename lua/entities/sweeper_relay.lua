--[[
	Map Sweepers - Implants & Class Levels (addon)
	Comms Relay: the objective entity for the Relay Network mission (sh_mission_relay.lua).

	Press E to start it transmitting. While it transmits it pulls enemies to itself and they try to smash it.
	If they break it, the transmission is lost and it reboots, ready to be started again.
--]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Comms Relay"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.STATE_IDLE, ENT.STATE_SENDING, ENT.STATE_DONE, ENT.STATE_REBOOT = 0, 1, 2, 3

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "RelayState")
	self:NetworkVar("Float", 0, "Progress")     -- 0-1 of this relay's transmission
	self:NetworkVar("Float", 1, "ReadyAt")      -- while rebooting: when it can be started again
end

local function cfg()
	local c = sweeper and sweeper.relayMission
	return c or { transmitTime = 60, health = 900, aggroRange = 1500, rebootTime = 10 }
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/props_lab/reciever01b.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end

		self:SetMaxHealth(cfg().health)
		self:SetHealth(cfg().health)
		self:SetRelayState(self.STATE_IDLE)
		self:SetProgress(0)

		-- base_anim ignores damage by default, so the swarm could never break it.
		self:SetSaveValue("m_takedamage", 2)

		self.jcms_useCount = 0
		self.jcms_thinkCount = 0
		self:NextThink(CurTime() + 0.25)
	end

	function ENT:MakeBullseye()
		if IsValid(self.bullseye) then return end
		local eye = ents.Create("jcms_bullseye")
		if not IsValid(eye) then return end
		eye:SetPos(self:WorldSpaceCenter() + Vector(0, 0, 10))
		eye.DamageTarget = self -- set before Spawn: the bullseye removes itself without one
		eye:Spawn()
		eye:SetParent(self)
		self.bullseye = eye
	end

	function ENT:OnRemove()
		if IsValid(self.bullseye) then self.bullseye:Remove() end
	end

	function ENT:Use(activator)
		self.jcms_useCount = (self.jcms_useCount or 0) + 1
		if not (IsValid(activator) and activator:IsPlayer() and activator:Alive()) then return end
		if jcms.team_JCorp_player and not jcms.team_JCorp_player(activator) then return end

		local state = self:GetRelayState()
		if state == self.STATE_DONE then
			activator:EmitSound("buttons/button10.wav", 60, 120)
			return
		elseif state == self.STATE_SENDING then
			activator:ChatPrint("[Relay] Already transmitting - keep it alive.")
			return
		elseif state == self.STATE_REBOOT then
			activator:ChatPrint(string.format("[Relay] Rebooting: %.0fs.", math.max(0, self:GetReadyAt() - CurTime())))
			return
		end

		self:SetRelayState(self.STATE_SENDING)
		self:MakeBullseye()
		self:EmitSound("ambient/machines/combine_terminal_idle4.wav", 80, 110)
		self:EmitSound("buttons/button14.wav", 75, 100)

		if jcms.net_SendTip then jcms.net_SendTip("all", true, "#jcms.skills_relay_started", 0) end
		if jcms.director_PvpObjectiveCompleted then
			-- counts as objective progress in PvP scoring, same as a terminal hack
			jcms.director_PvpObjectiveCompleted(activator, self:GetPos(), false)
		end
	end

	function ENT:Break()
		self:SetRelayState(self.STATE_REBOOT)
		self:SetProgress(0)
		self:SetReadyAt(CurTime() + cfg().rebootTime)
		self:SetHealth(self:GetMaxHealth())
		if IsValid(self.bullseye) then self.bullseye:Remove() end

		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter())
		ed:SetMagnitude(3)
		ed:SetScale(2)
		util.Effect("cball_explode", ed, true, true)
		self:EmitSound("ambient/energy/zap9.wav", 90, 90)
		if jcms.net_SendTip then jcms.net_SendTip("all", true, "#jcms.skills_relay_lost", 0) end
	end

	function ENT:OnTakeDamage(dmg)
		if self:GetRelayState() ~= self.STATE_SENDING then return end
		local attacker = dmg:GetAttacker()
		if IsValid(attacker) and attacker:IsPlayer() then return end -- sweepers can't break their own relay

		self:SetHealth(self:Health() - dmg:GetDamage())
		if self:Health() <= 0 then self:Break() end
	end

	function ENT:Aggro()
		local eye = self.bullseye
		if not IsValid(eye) then return end
		for i, npc in ipairs(ents.FindInSphere(self:GetPos(), cfg().aggroRange)) do
			if npc:IsNPC() and npc:Health() > 0 and jcms.team_NPC(npc) and npc.AddEntityRelationship then
				npc:AddEntityRelationship(eye, D_HT, 80)
				if not IsValid(npc:GetEnemy()) then
					npc:SetEnemy(eye)
					npc:UpdateEnemyMemory(eye, eye:GetPos())
				end
			end
		end
	end

	function ENT:Think()
		local ct = CurTime()

		-- Always reschedule FIRST. Bailing out of Think without touching NextThink is how a
		-- scripted entity quietly stops ticking.
		self:NextThink(ct + 0.25)
		self.jcms_thinkCount = (self.jcms_thinkCount or 0) + 1

		local state = self:GetRelayState()
		if state == self.STATE_SENDING then
			local p = self:GetProgress() + 0.25 / math.max(1, cfg().transmitTime)
			if p >= 1 then
				self:SetProgress(1)
				self:SetRelayState(self.STATE_DONE)
				if IsValid(self.bullseye) then self.bullseye:Remove() end
				self:EmitSound("ambient/machines/thumper_startup1.wav", 85, 130)
				if jcms.net_SendTip then jcms.net_SendTip("all", true, "#jcms.skills_relay_done", 0) end
			else
				self:SetProgress(p)
				if (self.nextAggro or 0) < ct then
					self.nextAggro = ct + 1
					self:Aggro()
				end
				if (self.nextBeep or 0) < ct then
					self.nextBeep = ct + 2
					self:EmitSound("buttons/blip1.wav", 65, 90 + p * 60, 0.5)
				end
			end
		elseif state == self.STATE_REBOOT and ct >= self:GetReadyAt() then
			self:SetRelayState(self.STATE_IDLE)
			self:EmitSound("buttons/button15.wav", 70, 110)
		end

		return true
	end
else
	local matGlow = Material("sprites/light_glow02_add")

	function ENT:Draw()
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
		local state = self:GetRelayState()
		local col = (state == self.STATE_DONE and Color(90, 255, 140))
			or (state == self.STATE_SENDING and Color(255, 190, 60))
			or (state == self.STATE_REBOOT and Color(255, 80, 60))
			or Color(120, 200, 255)
		local top = self:WorldSpaceCenter() + Vector(0, 0, 40)

		render.SetMaterial(matGlow)
		local pulse = 30 + math.sin(CurTime() * (state == self.STATE_SENDING and 8 or 3)) * 8
		render.DrawSprite(top, pulse, pulse, Color(col.r, col.g, col.b, 200))

		local me = LocalPlayer()
		if not (IsValid(me) and me:GetPos():DistToSqr(self:GetPos()) < 1200 ^ 2) then return end

		local ang = (self:GetPos() - EyePos()):Angle()
		cam.Start3D2D(top + Vector(0, 0, 18), Angle(0, ang.y - 90, 90), 0.15)
			local label = (state == self.STATE_DONE and "RELAY ONLINE")
				or (state == self.STATE_SENDING and string.format("TRANSMITTING  %d%%", math.floor(self:GetProgress() * 100)))
				or (state == self.STATE_REBOOT and string.format("REBOOTING  %.0fs", math.max(0, self:GetReadyAt() - CurTime())))
				or "PRESS E TO TRANSMIT"
			draw.SimpleText(label, "DermaLarge", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			if state == self.STATE_SENDING then
				-- progress bar + how much punishment it has left
				local w, h = 260, 16
				surface.SetDrawColor(20, 20, 20, 200)
				surface.DrawRect(-w / 2, 24, w, h)
				surface.SetDrawColor(col)
				surface.DrawRect(-w / 2 + 2, 26, (w - 4) * math.Clamp(self:GetProgress(), 0, 1), h - 4)
				local hp = math.Clamp(self:Health() / math.max(1, self:GetMaxHealth()), 0, 1)
				surface.SetDrawColor(255, 70, 70, 220)
				surface.DrawRect(-w / 2, 46, w * hp, 5)
			end
		cam.End3D2D()
	end
end
