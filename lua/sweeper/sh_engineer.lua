--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Engineer specialization mechanics.

	T1 Technician     Deployables +50% HP. Turrets get 2x ammo, a regenerating shield, and take 30% less damage.
	T1 Medic          Heal aura: 3 HP/s to nearby allies. Spawns with the medkit (weapon_medkit) - Medic only.
	T2 Mechanic       Hold E on a deployable to repair it and refill turret ammo.
	T2 Field Surgeon  Shield aura: 2 shield/s to nearby allies, and puts out burning allies.
	T3 Drone Master   Your turrets fire 25% faster and see 25% further. Run 2 Combat Drones at once.
	T3 Guardian       [G] Lifeline: once per mission: revive a fallen teammate next to you. Auras are doubled.

	Tuning values are in S.engineer below.
--]]

local S = sweeper

S.engineer = {
	auraRadius = 300,          -- ~6 metres
	medicHealPerSec = 5,
	medicMedkit = "weapon_medkit",  -- SWEP Medics spawn with. Medic-only: nobody else can carry or pick it up.
	-- Medkit overheal. The SWEP itself stops at full health, so these are applied on top of it.
	medkitOverhealMul   = 1.5,   -- medkit healing reaches 150% of the target's max health
	medkitOvershieldMul = 1.5,   -- a Field Surgeon's medkit also overcharges shield to 150%
	medkitOverhealRate  = 12,    -- HP (and shield) per second once the target is already full
	medkitRange         = 128,   -- how far the medkit counts as pointed at someone
	medkitWindow        = 0.4,   -- how long one press keeps topping up, so held fire is smooth
	surgeonShieldPerSec = 2.5,
	guardianAuraMul = 3,

	technicianHealthMul = 1.5,
	technicianAmmoMul = 2,
	technicianDamageTaken = 0.7,
	technicianShield = 60,     -- turret shield points
	technicianShieldRegen = 8, -- per second
	technicianShieldDelay = 4, -- seconds after being hit

	mechanicRange = 130,
	mechanicRepair = 5,        -- per tick (x2.5 for Engineers via the gamemode's repair function)
	mechanicAmmoFrac = 0.05,   -- of max clip per tick
	mechanicTick = 0.4,

	dronemasterFireRateMul = 0.8, -- time between shots x0.8 = 25% faster
	dronemasterRangeMul = 1.25,
	dronemasterMaxCombatDrones = 2,

	-- Abilities
	overclockCooldown = 45,      -- Technician: Overclock
	overclockDuration = 8,
	overclockFireRate = 2,       -- turrets fire this much faster

	triageCooldown = 30,         -- Medic: Triage Pulse
	triageHeal = 50,
	triageRadius = 450,

	quickDeployCooldown = 45,    -- Mechanic: Quick Deploy
	quickDeployLifetime = 30,
	quickDeployKind = "smg",

	barrierBurstCooldown = 40,   -- Field Surgeon: Barrier Burst
	barrierBurstDuration = 10,
	barrierBurstMul = 1.5,       -- shields overcharged to 150% of max
	barrierBurstRadius = 450,

	swarmCooldown = 60,          -- Architect: Drone Swarm
	swarmDrones = 3,
	swarmLifetime = 20,
}

-- Things Engineers deploy
S.deployableClasses = {
	jcms_turret = true,
	jcms_turret_smrls = true,
	jcms_tesla = true,
	jcms_shieldcharger = true,
	sweeper_drone = true,
	sweeper_structure = true,
}

-- // Lifeline active ability {{{
S.abilities.guardian = {
	name = "Lifeline",
	oncePerMission = true,
}

if SERVER then
	local function findFallenTeammate(ply)
		local best, bestTime
		for i, other in ipairs(player.GetAll()) do
			if other ~= ply
				and other:GetNWInt("jcms_desiredteam", 0) == 1
				and not other:GetNWBool("jcms_evacuated", false)
				and (not other:Alive() or other:GetObserverMode() ~= OBS_MODE_NONE)
				and other:GetNWInt("jcms_pvpTeam", -1) == ply:GetNWInt("jcms_pvpTeam", -1) then
				local t = other:GetNWFloat("jcms_lastDeathTime", 0)
				if not bestTime or t < bestTime then
					best, bestTime = other, t
				end
			end
		end
		return best
	end

	local function findSpotNear(ply)
		local base = ply:GetPos()
		local fwd = ply:GetForward()
		fwd.z = 0
		fwd:Normalize()
		local tries = { fwd * 60, -fwd * 60, ply:GetRight() * 60, -ply:GetRight() * 60 }
		for i, off in ipairs(tries) do
			local tr = util.TraceHull({
				start = base + Vector(0, 0, 8),
				endpos = base + off + Vector(0, 0, 8),
				mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72),
				filter = ply,
				mask = MASK_PLAYERSOLID,
			})
			if not tr.Hit then return tr.HitPos end
		end
		return base + Vector(0, 0, 8)
	end

	S.abilities.guardian.activate = function(ply)
		if not jcms.director or jcms.director.gameover then
			return false, "Lifeline (revive) only works during a mission."
		end

		local target = findFallenTeammate(ply)
		if not IsValid(target) then
			return false, "No fallen teammates to revive."
		end

		local pos = findSpotNear(ply)
		jcms.playerspawn_RespawnAs(target, "sweeper", pos, true)
		local ang = ply:EyeAngles()
		target:SetEyeAngles(Angle(0, ang.y, 0))

		local ed = EffectData()
		ed:SetColor(jcms.util_GetColorIntegerPvP(target))
		ed:SetFlags(0)
		ed:SetEntity(target)
		util.Effect("jcms_spawneffect", ed)
		if jcms.net_SendRespawnEffect then jcms.net_SendRespawnEffect(target) end

		ply:EmitSound("items/smallmedkit1.wav", 80, 90)
		target:EmitSound("ambient/machines/teleport1.wav", 80, 110)

		for i, p in ipairs(player.GetHumans()) do
			if jcms.team_pvpSameTeam(p, ply) then
				p:ChatPrint(string.format("[Guardian] %s revived %s!", ply:Nick(), target:Nick()))
			end
		end
		return true
	end
end
-- }}}

if SERVER then
	local E = S.engineer

	-- // Deployables: Technician + Architect {{{
	local function applyDeployablePerks(ent, owner)
		if not (IsValid(ent) and IsValid(owner) and owner:IsPlayer()) then return end
		if ent.sweeperPerksApplied then return end
		ent.sweeperPerksApplied = true

		local isTurret = ent:GetClass() == "jcms_turret"

		-- deployHp (Reinforced Chassis / Mastermind / Hardened Turrets)
		local t = S.GetPlayerTotals and S.GetPlayerTotals(owner)
		if t and (t.deployHp or 0) > 0 and ent:GetMaxHealth() > 0 then
			local max = math.floor(ent:GetMaxHealth() * (1 + t.deployHp))
			ent:SetMaxHealth(max)
			ent:SetHealth(max)
			if ent.UpdateTurretHealthFraction then ent:UpdateTurretHealthFraction() end
		end

		if S.PlayerHasSpec(owner, "technician") then
			local max = math.floor(ent:GetMaxHealth() * E.technicianHealthMul)
			if max > 0 then
				ent:SetMaxHealth(max)
				ent:SetHealth(max)
				if ent.UpdateTurretHealthFraction then ent:UpdateTurretHealthFraction() end
			end

			if isTurret and ent.GetTurretMaxClip then
				local clip = math.floor(ent:GetTurretMaxClip() * E.technicianAmmoMul)
				ent:SetTurretMaxClip(clip)
				ent:SetTurretClip(clip)
			end

			if isTurret or ent:GetClass() == "jcms_turret_smrls" then
				ent.sweeperDamageTakenMul = E.technicianDamageTaken
				if jcms.npc_SetupSweeperShields then
					jcms.npc_SetupSweeperShields(ent, E.technicianShield, E.technicianShieldRegen, E.technicianShieldDelay,
						jcms.util_GetColorIntegerPvP(owner))
				end
			end
		end

		if isTurret and S.PlayerHasSpec(owner, "dronemaster") then
			local origRate, origRadius = ent.TurretFirerate, ent.TurretRadius
			if origRate then
				ent.TurretFirerate = function(self, ...) return origRate(self, ...) * E.dronemasterFireRateMul end
			end
			if origRadius then
				ent.TurretRadius = function(self, ...) return origRadius(self, ...) * E.dronemasterRangeMul end
			end
		end
	end

	hook.Add("OnEntityCreated", "sweeper_engineerDeployables", function(ent)
		if not S.deployableClasses[ent:GetClass()] then return end
		-- Who ordered it? (set while an order is being placed, see sh_integration.lua)
		local creator = S.costCtxPly
		timer.Simple(0, function()
			if not IsValid(ent) then return end
			local owner = IsValid(ent.jcms_owner) and ent.jcms_owner or creator
			if IsValid(owner) and not IsValid(ent.jcms_owner) then
				ent.sweeperOwner = owner
			end
			applyDeployablePerks(ent, owner)
		end)
	end)

	hook.Add("EntityTakeDamage", "sweeper_technicianArmor", function(ent, dmg)
		local mul = ent.sweeperDamageTakenMul
		if mul then dmg:ScaleDamage(mul) end
	end)
	-- }}}

	-- // Auras: Medic + Field Surgeon (+ Lifeline doubles them) {{{
	timer.Create("sweeper_engineerAuras", 1, 0, function()
		for i, ply in ipairs(player.GetAll()) do
			local heal, shield = 0, 0
			if ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE then
				if S.PlayerHasSpec(ply, "medic") then heal = E.medicHealPerSec end
				if S.PlayerHasSpec(ply, "fieldsurgeon") then shield = E.surgeonShieldPerSec end
				if (heal > 0 or shield > 0) and S.PlayerHasSpec(ply, "guardian") then
					heal, shield = heal * S.Tune(ply, "guardianAuraMul", E.guardianAuraMul), shield * S.Tune(ply, "guardianAuraMul", E.guardianAuraMul)
				end
			end

			local auraBits = (heal > 0 and 1 or 0) + (shield > 0 and 2 or 0)
			if ply:GetNWInt("sweeper_aura", 0) ~= auraBits then
				ply:SetNWInt("sweeper_aura", auraBits)
			end

			if auraBits > 0 then
				for j, ally in ipairs(player.GetAll()) do
					if ally ~= ply and ally:Alive() and ally:GetObserverMode() == OBS_MODE_NONE
						and jcms.team_SameTeam(ply, ally)
						and ally:GetPos():DistToSqr(ply:GetPos()) <= S.Tune(ply, "auraRadius", E.auraRadius) ^ 2 then
						if heal > 0 and ally:Health() < ally:GetMaxHealth() then
							ally:SetHealth(math.min(ally:Health() + heal, ally:GetMaxHealth()))
						end
						if shield > 0 then
							if ally:Armor() < ally:GetMaxArmor() then
								ally:SetArmor(math.min(ally:Armor() + shield, ally:GetMaxArmor()))
							end
							if ally:IsOnFire() then ally:Extinguish() end
						end
					end
				end
			end
		end
	end)
	-- }}}

	-- // Mechanic: hold E to repair + reload deployables {{{
	local function needsWork(ent)
		if ent:Health() < ent:GetMaxHealth() then return true end
		if ent.GetTurretClip and ent:GetTurretClip() < ent:GetTurretMaxClip() then return true end
		return false
	end

	local function mechanicTarget(ply)
		if not (ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE) then return nil end
		if not S.PlayerHasSpec(ply, "mechanic") then return nil end
		local tr = ply:GetEyeTrace()
		local ent = tr.Entity
		if not (IsValid(ent) and S.deployableClasses[ent:GetClass()]) then return nil end
		if tr.StartPos:DistToSqr(tr.HitPos) > E.mechanicRange ^ 2 then return nil end
		if ent.GetHackedByRebels and ent:GetHackedByRebels() then return nil end
		if not jcms.team_SameTeam(ply, ent) and ent.jcms_owner ~= ply then return nil end
		return ent
	end

	timer.Create("sweeper_mechanic", E.mechanicTick, 0, function()
		for i, ply in ipairs(player.GetAll()) do
			if ply:KeyDown(IN_USE) then
				local ent = mechanicTarget(ply)
				if ent and needsWork(ent) then
					if ent:Health() < ent:GetMaxHealth() then
						jcms.util_PerformRepairs(ent, ply, S.Tune(ply, "mechanicRepair", E.mechanicRepair))
						if ent.UpdateTurretHealthFraction then ent:UpdateTurretHealthFraction() end
					end
					if ent.GetTurretClip then
						local max = ent:GetTurretMaxClip()
						if ent:GetTurretClip() < max then
							ent:SetTurretClip(math.min(max, ent:GetTurretClip() + math.max(1, math.ceil(max * E.mechanicAmmoFrac))))
						end
					end

					local ed = EffectData()
					ed:SetOrigin(ply:GetEyeTrace().HitPos)
					ed:SetMagnitude(1)
					ed:SetScale(1)
					ed:SetRadius(4)
					util.Effect("Sparks", ed, true, true)
				end
			end
		end
	end)

	-- While a deployable needs work, E repairs it instead of shoving it
	hook.Add("PlayerUse", "sweeper_mechanicNoShove", function(ply, ent)
		if S.deployableClasses[ent:GetClass()] and mechanicTarget(ply) == ent and needsWork(ent) then
			return false
		end
	end)
	-- }}}
end

-- // Client: show aura range around Medics / Field Surgeons {{{
if CLIENT then
	local colHeal = Color(80, 255, 120, 120)
	local colShield = Color(64, 180, 255, 120)

	hook.Add("PostDrawTranslucentRenderables", "sweeper_auraRings", function(depth, skybox)
		if skybox then return end
		local me = LocalPlayer()
		for i, ply in ipairs(player.GetAll()) do
			local bits = ply:GetNWInt("sweeper_aura", 0)
			if bits > 0 and ply:Alive() then
				if ply:GetPos():DistToSqr(me:GetPos()) < 2500 ^ 2 then
					local col = (bit.band(bits, 1) ~= 0) and colHeal or colShield
					local pulse = 0.85 + math.sin(CurTime() * 3) * 0.15
					cam.Start3D2D(ply:GetPos() + Vector(0, 0, 3), Angle(0, 0, 0), 1)
						surface.DrawCircle(0, 0, S.engineer.auraRadius * pulse, col.r, col.g, col.b, col.a)
						surface.DrawCircle(0, 0, S.engineer.auraRadius, col.r, col.g, col.b, 50)
					cam.End3D2D()
				end
			end
		end
	end)
end
-- }}}

-- // New Engineer abilities {{{
local E = S.engineer
S.abilities.technician   = { name = "Overclock",     cooldown = E.overclockCooldown }
S.abilities.medic        = { name = "Triage Pulse",  cooldown = E.triageCooldown }
S.abilities.mechanic     = { name = "Quick Deploy",  cooldown = E.quickDeployCooldown }
S.abilities.fieldsurgeon = { name = "Barrier Burst", cooldown = E.barrierBurstCooldown }
S.abilities.dronemaster    = { name = "Drone Swarm",   cooldown = E.swarmCooldown }

if SERVER then
	local function ownedBy(ent, ply)
		return ent.jcms_owner == ply or ent.sweeperOwner == ply
	end

	local function alliesNear(ply, radius)
		local out = {}
		for i, ally in ipairs(player.GetAll()) do
			if ally:Alive() and ally:GetObserverMode() == OBS_MODE_NONE and jcms.team_SameTeam(ply, ally)
				and ally:GetPos():DistToSqr(ply:GetPos()) <= radius ^ 2 then
				out[#out + 1] = ally
			end
		end
		return out
	end

	local function ring(pos, color)
		local ed = EffectData()
		ed:SetOrigin(pos)
		ed:SetColor(color or 0)
		util.Effect("cball_explode", ed, true, true)
	end

	-- // Technician: Overclock {{{
	-- Wrap every turret's fire rate once so Overclock can speed it up
	local function wrapTurret(ent)
		if ent.sweeperOCWrapped or not ent.TurretFirerate then return end
		ent.sweeperOCWrapped = true
		local orig = ent.TurretFirerate
		ent.TurretFirerate = function(self, ...)
			local rate = orig(self, ...)
			if (self.sweeperOverclockUntil or 0) > CurTime() and type(rate) == "number" then
				rate = rate / E.overclockFireRate
			end
			return rate
		end
	end

	S.abilities.technician.activate = function(ply)
		local untilT = CurTime() + S.Tune(ply, "overclockDuration", E.overclockDuration)
		local n = 0
		for class in pairs(S.deployableClasses) do
			for i, ent in ipairs(ents.FindByClass(class)) do
				if ownedBy(ent, ply) then
					ent.sweeperOverclockUntil = untilT
					ent:SetNWFloat("sweeper_overclockUntil", untilT)
					if class == "jcms_turret" then wrapTurret(ent) end
					ent:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", 70, 120)
					n = n + 1
				end
			end
		end
		if n == 0 then return false, "Overclock: you don't have any turrets or deployables out." end
		ply:SetNWFloat("sweeper_overclockUntil", untilT)
		ply:EmitSound("ambient/machines/thumper_startup1.wav", 70, 140)
		return true
	end

	hook.Add("EntityTakeDamage", "sweeper_overclockInvuln", function(ent, dmg)
		if (ent.sweeperOverclockUntil or 0) > CurTime() then return true end
	end)
	-- }}}

	-- // Medic: Triage Pulse {{{
	S.abilities.medic.activate = function(ply)
		for i, ally in ipairs(alliesNear(ply, S.Tune(ply, "triageRadius", E.triageRadius))) do
			ally:SetHealth(math.min(ally:GetMaxHealth(), ally:Health() + S.Tune(ply, "triageHeal", E.triageHeal)))
			if ally:IsOnFire() then ally:Extinguish() end
			ally:EmitSound("items/medshot4.wav", 65, 110)
		end
		ring(ply:GetPos() + Vector(0, 0, 10))
		ply:EmitSound("items/smallmedkit1.wav", 80, 90)
		return true
	end
	-- }}}

	-- // Mechanic: Quick Deploy {{{
	S.abilities.mechanic.activate = function(ply)
		if not jcms.spawnmenu_Turret then return false, "Quick Deploy isn't available." end
		local fwd = ply:GetForward()
		fwd.z = 0
		fwd:Normalize()
		local tr = util.TraceLine({ start = ply:GetPos() + Vector(0, 0, 32) + fwd * 50, endpos = ply:GetPos() + fwd * 50 - Vector(0, 0, 100), filter = ply, mask = MASK_SOLID_BRUSHONLY })
		if not tr.Hit then return false, "Quick Deploy: no room in front of you." end

		local before = {}
		for i, ent in ipairs(ents.FindByClass("jcms_turret")) do before[ent] = true end
		jcms.spawnmenu_Turret(E.quickDeployKind, ply, tr.HitPos, Angle(0, ply:EyeAngles().y, 0))

		for i, ent in ipairs(ents.FindByClass("jcms_turret")) do
			if not before[ent] then
				ent.sweeperTemporary = true
				ent:SetModelScale(0.8, 0)
				timer.Simple(S.Tune(ply, "quickDeployLifetime", E.quickDeployLifetime), function()
					if IsValid(ent) then
						local ed = EffectData()
						ed:SetOrigin(ent:WorldSpaceCenter())
						util.Effect("cball_explode", ed, true, true)
						ent:Remove()
					end
				end)
			end
		end
		return true
	end
	-- }}}

	-- // Field Surgeon: Barrier Burst {{{
	S.abilities.fieldsurgeon.activate = function(ply)
		local untilT = CurTime() + S.Tune(ply, "barrierBurstDuration", E.barrierBurstDuration)
		for i, ally in ipairs(alliesNear(ply, E.barrierBurstRadius)) do
			local over = math.floor(ally:GetMaxArmor() * S.Tune(ply, "barrierBurstMul", E.barrierBurstMul))
			ally:SetArmor(math.max(ally:Armor(), over))
			ally:SetNWFloat("sweeper_overshieldUntil", untilT)
			ally:EmitSound("items/suitchargeok1.wav", 65, 120)
			local who = ally
			timer.Create("sweeper_overshield" .. ally:EntIndex(), S.Tune(ply, "barrierBurstDuration", E.barrierBurstDuration), 1, function()
				if IsValid(who) and who:Armor() > who:GetMaxArmor() then who:SetArmor(who:GetMaxArmor()) end
			end)
		end
		ring(ply:GetPos() + Vector(0, 0, 10))
		return true
	end
	-- }}}

	-- // Architect: Drone Swarm {{{
	S.abilities.dronemaster.activate = function(ply)
		if not (S.SpawnSkillDrone and S.callins and S.callins.skills_drone_combat) then return false, "Drone Swarm isn't available." end
		local cfg = table.Copy(S.callins.skills_drone_combat)
		cfg.lifetime = S.Tune(ply, "swarmLifetime", E.swarmLifetime)
		for d = 1, S.Tune(ply, "swarmDrones", E.swarmDrones) do
			timer.Simple((d - 1) * 0.2, function()
				if IsValid(ply) and ply:Alive() then S.SpawnSkillDrone(ply, "combat", cfg, true) end
			end)
		end
		ply:SetNWFloat("sweeper_swarmUntil", CurTime() + S.Tune(ply, "swarmLifetime", E.swarmLifetime))
		return true
	end
	-- }}}


	-- // Medic: the medkit {{{
	-- Medics get the medkit SWEP on every spawn. It stays Medic-only: other classes have it taken off them
	-- and can't pick one up off the ground. The gamemode keeps weapon_medkit out of the shop, so this perk is
	-- the only way to get one.
	local function medkitAlive(ply)
		return ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE
	end
	local medkitWarned = false
	local function medkitOK()
		if weapons.Get(E.medicMedkit) then return true end
		if not medkitWarned then
			medkitWarned = true
			ErrorNoHalt("[sweeper] Medic medkit: the weapon '" .. tostring(E.medicMedkit) .. "' isn't installed on this server, so Medics get nothing. Install it, or change S.engineer.medicMedkit.\n")
		end
		return false
	end

	local function giveMedkit(ply)
		if not (IsValid(ply) and medkitAlive(ply) and S.PlayerHasSpec(ply, "medic")) then return end
		if ply:HasWeapon(E.medicMedkit) or not medkitOK() then return end
		-- The gamemode deletes weapons given without this flag *during* Give
		local old = ply.jcms_canGetWeapons
		ply.jcms_canGetWeapons = true
		ply:Give(E.medicMedkit, true)
		ply.jcms_canGetWeapons = old
	end
	S.GiveMedicMedkit = giveMedkit

	local function stripMedkit(ply)
		if IsValid(ply) and ply:HasWeapon(E.medicMedkit) and not S.PlayerHasSpec(ply, "medic") then
			ply:StripWeapon(E.medicMedkit)
		end
	end

	local function refreshMedkit(ply)
		stripMedkit(ply)
		giveMedkit(ply)
	end

	hook.Add("MapSweepersClassApplied", "sweeper_medicMedkit", function(ply)
		-- the gamemode hands out the class loadout right after this hook
		timer.Simple(0.3, function() if IsValid(ply) then refreshMedkit(ply) end end)
	end)
	hook.Add("PlayerSpawn", "sweeper_medicMedkit", function(ply)
		timer.Simple(0.5, function() if IsValid(ply) then refreshMedkit(ply) end end)
	end)

	-- Nobody else picks one up, and a Medic's medkit doesn't get left lying around when they die
	hook.Add("PlayerCanPickupWeapon", "sweeper_medicMedkit", function(ply, wep)
		if IsValid(wep) and wep:GetClass() == E.medicMedkit and not S.PlayerHasSpec(ply, "medic") then
			return false
		end
	end)
	hook.Add("DoPlayerDeath", "sweeper_medicMedkit", function(ply)
		if IsValid(ply) and ply:HasWeapon(E.medicMedkit) then ply:StripWeapon(E.medicMedkit) end
	end)

	-- Picking Medic (or dropping it) between missions: sort everyone out on a slow tick
	timer.Create("sweeper_medicMedkit", 3, 0, function()
		for i, ply in ipairs(player.GetAll()) do
			if medkitAlive(ply) then refreshMedkit(ply) end
		end
	end)
	-- }}}

	-- // Medic: medkit overheal {{{
	-- The medkit SWEP stops at full health, so the overheal has to be ours. We don't touch the
	-- weapon (it's a Workshop addon): we watch for a Medic holding fire with one out, work out who
	-- they're pointing it at, and top that target up past their maximum while they keep at it.
	--
	-- A Field Surgeon's medkit overcharges the target's shield the same way - that spec's Barrier
	-- Burst already overshields to 150%, so its medkit matches.
	local MEDKIT_TICK = 0.1

	local function medkitTarget(ply)
		-- Secondary fire is a self-heal on most medkits.
		if ply:KeyDown(IN_ATTACK2) then return ply end
		if not ply:KeyDown(IN_ATTACK) then return nil end

		local tr = ply:GetEyeTrace()
		local ent = tr.Entity
		if IsValid(ent) and ent:IsPlayer() and ent:Alive()
			and ply:GetShootPos():DistToSqr(tr.HitPos) <= E.medkitRange ^ 2
			and (not jcms.team_JCorp_player or jcms.team_JCorp_player(ent)) then
			return ent
		end

		return ply -- pointing at nothing: treat it as healing yourself
	end

	-- Only kicks in once the weapon itself has run out of room, and never lowers anything.
	local function topUp(current, maximum, mul, add)
		local cap = math.floor(maximum * mul)
		if current < maximum or current >= cap then return nil end
		return math.min(cap, current + add)
	end

	timer.Create("sweeper_medkitOverheal", MEDKIT_TICK, 0, function()
		local ct = CurTime()
		local add = math.max(1, math.ceil(E.medkitOverhealRate * MEDKIT_TICK))

		-- Who is being medkitted right now
		for i, ply in ipairs(player.GetAll()) do
			if medkitAlive(ply) and S.PlayerHasSpec(ply, "medic") then
				local wep = ply:GetActiveWeapon()
				if IsValid(wep) and wep:GetClass() == E.medicMedkit then
					local target = medkitTarget(ply)
					if IsValid(target) then
						target.sweeperMedkitUntil = ct + E.medkitWindow
						target.sweeperMedkitBy = ply
					end
				end
			end
		end

		-- ...and the top-up itself
		for i, ply in ipairs(player.GetAll()) do
			if (ply.sweeperMedkitUntil or 0) > ct and ply:Alive() then
				local hp = topUp(ply:Health(), ply:GetMaxHealth(), E.medkitOverhealMul, add)
				-- MarkOverheal restarts the decay clock, so overheal only drains once the medkit
				-- has been off them for a minute (see S.overheal in sh_tree.lua).
				if hp then ply:SetHealth(hp) S.MarkOverheal(ply) end

				local healer = ply.sweeperMedkitBy
				if IsValid(healer) and S.PlayerHasSpec(healer, "fieldsurgeon") then
					local sh = topUp(ply:Armor(), ply:GetMaxArmor(), E.medkitOvershieldMul, add)
					if sh then ply:SetArmor(sh) S.MarkOverheal(ply) end
				end
			end
		end
	end)
	-- }}}

	hook.Add("MapSweepersClassApplied", "sweeper_engineerAbilityReset", function(ply)
		ply:SetNWFloat("sweeper_overclockUntil", 0)
		ply:SetNWFloat("sweeper_swarmUntil", 0)
		ply:SetNWFloat("sweeper_overshieldUntil", 0)
	end)
end
-- }}}
