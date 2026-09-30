--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Shared: New class-only call-ins.

	  skills_drone_combat  Combat Drone     (Engineer)  follows you and shoots enemies
	  skills_drone_repair  Repair Drone     (Engineer)  follows you, heals allies and repairs your turrets
	  skills_stimcrate     Stim Crate       (Infantry)  purple restock box with a charge pool, press E for a random stim
	  skills_ammocache     Ammo Cache       (Infantry)  restock box with a charge pool, press E for ammo
	  skills_uav           UAV Scan         (Recon)     outlines every enemy in a big area for the team
	  skills_cover         Deployable Cover (Sentinel)  a bullet-blocking barricade
	  skills_decoy         Decoy Beacon     (Recon)     hologram that pulls enemy aggro
	  skills_healstation   Healing Station  (Engineer)  pad that heals sweepers on it until its charge runs out
	  skills_bulwark       Bulwark          (Sentinel)  dome that absorbs enemy fire from outside
	  skills_totem         Taunt Totem      (Sentinel)  draws enemies in and shocks them
	  skills_precision     Precision Strike (everyone)  one cheap bomb
	  skills_strafe        Strafing Run     (everyone)  gunship strafes a line

	Which class gets which call-in is set in sh_classorders.lua (S.orderClasses).
	Costs/cooldowns/tuning are in S.callins below.
--]]

local S = sweeper

S.callins = {
	skills_drone_combat = {
		name = "Combat Drone",
		desc = "A drone that follows you and fires at nearby enemies. Lasts 60s.",
		cost = 700, cooldown = 60, category = "TURRETS", slotPos = 6,
		lifetime = 60, health = 150, damage = 6, fireDelay = 0.12, range = 1200,
	},
	skills_drone_repair = {
		name = "Repair Drone",
		desc = "A drone that follows you, heals nearby allies and repairs your turrets. Lasts 75s.",
		cost = 500, cooldown = 90, category = "TURRETS", slotPos = 7,
		lifetime = 75, health = 150, healPlayers = 3, repairDeployables = 8, range = 400,
	},
	skills_stimcrate = {
		name = "Stim Crate",
		desc = "A purple restock box the squad presses E on for a random combat stim. Holds 6 doses, no timer - it stays until it's empty.",
		cost = 450, cooldown = 150, category = "SUPPLIES", slotPos = 4,
		kind = "stim", health = 400, charge = 6, perUse = 1, radius = 80, maxPerPlayer = 1,
	},
	skills_ammocache = {
		name = "Ammo Cache",
		desc = "A restock box the squad presses E on for ammo. Holds 1600 ammo, no timer - it stays until it's empty.",
		cost = 400, cooldown = 90, category = "SUPPLIES", slotPos = 6,
		kind = "ammo", health = 400, charge = 1600, perUse = 200, radius = 80, maxPerPlayer = 1,
	},
	skills_uav = {
		name = "UAV Scan",
		desc = "Outlines every enemy near the target area for your whole team. Lasts 25s.",
		cost = 250, cooldown = 90, category = "UTILITY", slotPos = 4,
		duration = 25, radius = 2000,
	},
	skills_cover = {
		name = "Deployable Cover",
		desc = "Drops a bullet-blocking barricade. 600 HP, lasts 2 minutes. Max 2 at a time.",
		cost = 300, cooldown = 45, category = "DEFENSIVE", slotPos = 3,
		health = 600, lifetime = 120, maxPerPlayer = 2,
	},

	-- Class-only structures (sweeper_structure)
	skills_decoy = {
		name = "Decoy Beacon",
		desc = "A hologram sweeper that pulls the aggro of every enemy nearby. 300 HP, lasts 15s.",
		cost = 250, cooldown = 45, category = "UTILITY", slotPos = 5,
		kind = "decoy", health = 300, lifetime = 15, radius = 1200,
	},
	skills_healstation = {
		name = "Healing Station",
		desc = "A pad that heals sweepers standing on it for 4 HP/s. Holds 200 HP of healing - no timer, it stays until the charge is used up.",
		cost = 400, cooldown = 90, category = "SUPPLIES", slotPos = 5,
		kind = "heal", health = 500, charge = 200, radius = 150, healPerSec = 4, maxPerPlayer = 1,
	},
	skills_bulwark = {
		name = "Bulwark",
		desc = "A big shield dome for 20s. Enemy fire from outside is absorbed (2000 HP); your team can shoot out.",
		cost = 500, cooldown = 90, category = "DEFENSIVE", slotPos = 4,
		kind = "bulwark", health = 600, lifetime = 20, radius = 300, domeHealth = 2000,
	},
	skills_totem = {
		name = "Taunt Totem",
		desc = "Draws every enemy within ~47m to it and shocks anything close (20 dmg/s). 1000 HP, lasts 30s.",
		cost = 350, cooldown = 60, category = "DEFENSIVE", slotPos = 5,
		kind = "totem", health = 1000, lifetime = 30, radius = 2500, shockRadius = 200, shockDamage = 20,
	},

	-- Everyone
	skills_precision = {
		name = "Precision Strike",
		desc = "A single guided bomb on the target, with a wide blast.",
		cost = 300, cooldown = 30, category = "ORBITALS", slotPos = 7,
		-- 400 is the blast the gamemode gives each of its own Carpet Bombing bombs, so one Precision
		-- Strike now covers the same ground a single carpet bomb does.
		blastRadius = 400, blastDamage = 300,
	},
	skills_strafe = {
		name = "Strafing Run",
		desc = "A gunship strafes a fast line of shots through the target (from you toward it). Bigger blasts with the Team Upgrade.",
		cost = 200, cooldown = 15, category = "ORBITALS", slotPos = 8,
		length = 1400, bursts = 45, spread = 220,   -- bursts scatter up to `spread` units either side of the line
		bulletsPerBurst = 3, bulletDamage = 30,     -- normal hitscan bullets
		explosiveRadius = 150, explosiveDamage = 75, -- with the "Explosive Rounds" Team Upgrade (g_strafe)
	},
}


-- // Team Upgrades for these call-ins {{{
-- S.CallinCfg(id) returns the call-in's settings with the squad's Team Upgrade ranks applied. Spawn code
-- uses it instead of S.callins[id] directly, so an upgrade bought mid-mission counts on the next call-in.
S.callinUpgradeIds = {
	skills_drone_combat = "g_drones",
	skills_drone_repair = "g_drones",
	skills_healstation  = "g_healstation",
	skills_stimcrate    = "g_stims",
	skills_ammocache    = "g_ammocache",
	skills_uav          = "g_uav",
	skills_cover        = "g_structures",
	skills_bulwark      = "g_structures",
	skills_totem        = "g_structures",
	skills_decoy        = "g_structures",
}

S.callinUpgradeApply = S.callinUpgradeApply or {}
local upgradeApply = S.callinUpgradeApply
local builtinApply = {
	g_drones = function(cfg, rank, U)
		cfg.lifetime = math.floor((cfg.lifetime or 60) * (1 + (U.dronesLifetimePerRank or 0) * rank))
		cfg.health = math.floor((cfg.health or 150) * (1 + (U.dronesHealthPerRank or 0) * rank))
		if cfg.damage then cfg.damage = cfg.damage * (1 + (U.dronesDamagePerRank or 0) * rank) end
	end,
	g_healstation = function(cfg, rank, U)
		cfg.charge = (cfg.charge or 200) + (U.healStationChargePerRank or 0) * rank
		cfg.healPerSec = (cfg.healPerSec or 4) + (U.healStationRatePerRank or 0) * rank
	end,
	g_stims = function(cfg, rank, U)
		-- Doses in the box. (The same upgrade also lengthens each stim, in S.GiveStim.)
		cfg.charge = (cfg.charge or 6) + (U.stimDosesPerRank or 0) * rank
	end,
	g_ammocache = function(cfg, rank, U)
		cfg.charge = (cfg.charge or 1600) + (U.ammoCacheChargePerRank or 0) * rank
		cfg.perUse = (cfg.perUse or 200) + (U.ammoCachePerUsePerRank or 0) * rank
	end,
	g_uav = function(cfg, rank, U)
		cfg.duration = (cfg.duration or 25) + (U.uavDurationPerRank or 0) * rank
		cfg.radius = (cfg.radius or 2000) + (U.uavRadiusPerRank or 0) * rank
	end,
	g_structures = function(cfg, rank, U)
		cfg.health = math.floor((cfg.health or 400) * (1 + (U.structureHealthPerRank or 0) * rank))
		if cfg.domeHealth then cfg.domeHealth = cfg.domeHealth + (U.bulwarkDomePerRank or 0) * rank end
	end,
}
for id, fn in pairs(builtinApply) do upgradeApply[id] = fn end

function S.CallinCfg(id)
	local base = S.callins[id]
	if not base then return nil end
	local upId = S.callinUpgradeIds[id]
	local rank = (upId and S.GroupRank) and S.GroupRank(upId) or 0
	local apply = upId and upgradeApply[upId]
	if rank <= 0 or not apply then return base end

	local cfg = table.Copy(base)
	apply(cfg, rank, S.callinUpgrades or {})
	return cfg
end
-- }}}

-- // Language (names + descriptions on the spawn wheel) {{{
if CLIENT then
	for id, c in pairs(S.callins) do
		language.Add("jcms." .. id, c.name)
		language.Add("jcms." .. id .. "_desc", c.desc)
	end
end
-- }}}

-- // Server: register the orders with the gamemode {{{
if SERVER then
	util.AddNetworkString("sweeper_uav")

	local function pvpTeam(ply)
		return IsValid(ply) and ply:GetNWInt("jcms_pvpTeam", -1) or -1
	end

	local function spawnEffect(ply, ent)
		local ed = EffectData()
		ed:SetColor(jcms.util_GetColorIntegerPvP(ply))
		ed:SetFlags(0)
		ed:SetEntity(ent)
		util.Effect("jcms_spawneffect", ed)
	end

	-- noLimit = true for temporary drones from abilities (Drone Swarm): they don't replace your call-in drones
	local function spawnDrone(ply, droneType, cfg, noLimit)
		if not IsValid(ply) then return end

		-- Limit drones of each type per player (Architect can run 2 Combat Drones): replace the oldest
		local limit = noLimit and math.huge or 1
		if not noLimit and droneType == "combat" and S.PlayerHasSpec and S.PlayerHasSpec(ply, "dronemaster") then
			limit = (S.engineer and S.engineer.dronemasterMaxCombatDrones) or 2
		end
		local mine = {}
		for i, ent in ipairs(ents.FindByClass("sweeper_drone")) do
			if ent.jcms_owner == ply and ent:GetDroneType() == droneType and not ent.sweeperTemporary then
				table.insert(mine, ent)
			end
		end
		table.sort(mine, function(a, b) return a:GetExpireTime() < b:GetExpireTime() end)
		while #mine >= limit do
			table.remove(mine, 1):Remove()
		end

		local drone = ents.Create("sweeper_drone")
		drone:SetPos(ply:EyePos() + Vector(0, 0, 40))
		drone:SetDroneType(droneType)
		drone.jcms_owner = ply
		drone.cfg = cfg
		drone:SetNWInt("jcms_pvpTeam", pvpTeam(ply))
		drone:Spawn()
		drone:SetDroneOwner(ply)
		spawnEffect(ply, drone)
		drone:EmitSound("npc/scanner/scanner_siren1.wav", 70, 120, 0.6)

		if CPPI then drone:CPPISetOwner(game.GetWorld()) end
		drone.sweeperTemporary = noLimit or nil
		return drone
	end
	S.SpawnSkillDrone = spawnDrone

	local defs = {}

	defs.skills_drone_combat = {
		argparser = "sweeper_self",
		func = function(ply) spawnDrone(ply, "combat", S.CallinCfg("skills_drone_combat")) end,
	}

	defs.skills_drone_repair = {
		argparser = "sweeper_self",
		func = function(ply) spawnDrone(ply, "repair", S.CallinCfg("skills_drone_repair")) end,
	}

	defs.skills_uav = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = S.CallinCfg("skills_uav")
			net.Start("sweeper_uav")
				net.WriteVector(pos)
				net.WriteFloat(CurTime() + cfg.duration)
				net.WriteUInt(cfg.radius, 16)
				net.WriteInt(pvpTeam(ply), 8)
			net.Broadcast()

			sound.Play("npc/scanner/scanner_siren2.wav", pos + Vector(0, 0, 200), 90, 90, 0.8)
			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_uav")
		end,
	}

	defs.skills_cover = {
		argparser = "turret_static",
		func = function(ply, pos, angle)
			local cfg = S.CallinCfg("skills_cover")

			-- Limit covers per player: remove the oldest
			local mine = {}
			for i, ent in ipairs(ents.FindByClass("sweeper_cover")) do
				if ent.jcms_owner == ply then table.insert(mine, ent) end
			end
			table.sort(mine, function(a, b) return (a.jcms_spawnTime or 0) < (b.jcms_spawnTime or 0) end)
			while #mine >= cfg.maxPerPlayer do
				table.remove(mine, 1):Remove()
			end

			local cover = ents.Create("sweeper_cover")
			cover:SetPos(pos)
			cover.jcms_owner = ply
			cover.jcms_spawnTime = CurTime()
			cover.cfg = cfg
			cover.faceYaw = IsValid(ply) and ply:EyeAngles().y or angle.y
			cover:SetNWInt("jcms_pvpTeam", pvpTeam(ply))
			cover:Spawn()
			spawnEffect(ply, cover)
			cover:EmitSound("physics/metal/metal_barrel_impact_hard1.wav", 80, 90)

			if CPPI then cover:CPPISetOwner(game.GetWorld()) end
		end,
	}

	-- // New structures: Decoy Beacon, Healing Station, Bulwark, Taunt Totem {{{
	local function spawnStructure(ply, id, pos, angle)
		local cfg = S.CallinCfg(id) or S.callins[id]

		-- Structures with no timer (the Healing Station) would otherwise pile up: keep only the newest
		if cfg.maxPerPlayer then
			local mine = {}
			for i, other in ipairs(ents.FindByClass("sweeper_structure")) do
				if other.jcms_owner == ply and other:GetKind() == cfg.kind then mine[#mine + 1] = other end
			end
			while #mine >= cfg.maxPerPlayer do
				local old = table.remove(mine, 1)
				if IsValid(old) then old:Remove() end
			end
		end

		local ent = ents.Create("sweeper_structure")
		if not IsValid(ent) then return end
		ent:SetKind(cfg.kind)
		ent:SetPos(pos)
		ent.cfg = cfg
		ent.jcms_owner = ply
		ent.faceYaw = IsValid(ply) and ply:EyeAngles().y or (angle and angle.y) or 0
		ent:SetNWInt("jcms_pvpTeam", pvpTeam(ply))
		ent:Spawn()
		spawnEffect(ply, ent)
		ent:EmitSound("items/suitchargeok1.wav", 75, 90)
		if CPPI then ent:CPPISetOwner(game.GetWorld()) end
		jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms." .. id)
		return ent
	end

	S.SpawnSkillStructure = spawnStructure

	for i, id in ipairs({ "skills_decoy", "skills_healstation", "skills_ammocache", "skills_stimcrate", "skills_bulwark", "skills_totem" }) do
		defs[id] = {
			argparser = "turret_static",
			func = function(ply, pos, angle) spawnStructure(ply, id, pos, angle) end,
		}
	end

	-- Bulwark: soak up enemy fire coming from outside the dome
	hook.Add("EntityTakeDamage", "sweeper_bulwark", function(victim, dmg)
		if not (victim:IsPlayer() or (S.deployableClasses and S.deployableClasses[victim:GetClass()])) then return end
		local attacker = dmg:GetAttacker()
		if IsValid(attacker) and attacker:IsPlayer() then return end

		for i, dome in ipairs(ents.FindByClass("sweeper_structure")) do
			if dome:GetKind() == "bulwark" and dome:GetDomeHP() > 0 then
				local center, r2 = dome:GetPos(), dome:GetRadius() ^ 2
				local src = IsValid(attacker) and attacker:WorldSpaceCenter() or dmg:GetDamagePosition()
				if victim:WorldSpaceCenter():DistToSqr(center) <= r2 and src:DistToSqr(center) > r2 then
					local hp = dome:GetDomeHP() - math.ceil(dmg:GetDamage())
					dome:SetDomeHP(math.max(hp, 0))
					if hp <= 0 then
						dome:EmitSound("ambient/energy/powerdown2.wav", 80, 100)
					end
					return true
				end
			end
		end
	end)
	-- }}}

	-- // Precision Strike {{{
	defs.skills_precision = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = S.callins.skills_precision
			jcms.net_SendLocator("all", nil, "#jcms.skills_precision", pos, jcms.LOCATOR_TIMED, 1.5)
			jcms.spawnmenu_Airstrike {
				pos = pos, count = 1, arrival = 1.5, radius = 0,
				blast_radius = cfg.blastRadius, blast_damage = cfg.blastDamage,
				callback = function(bomb)
					bomb.jcms_owner = ply
					-- Big explosion effect when the bomb goes off (the damage is the bomb's own)
					bomb:CallOnRemove("sweeper_precisionFx", function(b)
						local p = b:GetPos()
						local ed = EffectData()
						ed:SetOrigin(p)
						ed:SetScale(1)
						ed:SetMagnitude(1)
						util.Effect("Explosion", ed, true, true)
						util.Effect("HelicopterMegaBomb", ed, true, true)
						local ring = EffectData()
						ring:SetOrigin(p)
						ring:SetScale(cfg.blastRadius)
						util.Effect("ThumperDust", ring, true, true)
						util.ScreenShake(p, 12, 120, 1.2, cfg.blastRadius * 3)
						util.Decal("Scorch", p + Vector(0, 0, 32), p - Vector(0, 0, 64), b)
						sound.Play("ambient/explosions/explode_" .. math.random(1, 4) .. ".wav", p, 140, 100)
					end)
				end,
			}
			jcms.util_JetSound(pos)
			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_precision")
		end,
	}
	-- }}}

	-- // Strafing Run {{{
	defs.skills_strafe = {
		argparser = "orbital_fixed",
		-- Carpet-bomb style line (jcms.spawnmenu_Airstrike), but every shot is HITSCAN like the gamemode's
		-- Shelling: an instant trace from the sky with a bolt effect, no physical bomb/bullet entities.
		func = function(ply, pos)
			local cfg = S.callins.skills_strafe
			local dif = pos - (IsValid(ply) and ply:GetPos() or pos - Vector(1, 0, 0))
			dif.z = 0
			dif:Normalize()
			dif:Mul(cfg.length / 2)

			local explosive = S.GroupRank and S.GroupRank("g_strafe") > 0

			local attacker = IsValid(ply) and ply or game.GetWorld()

			-- One burst = a few hitscan bullets (normal bullet tracers + dust). The Explosive Rounds upgrade adds a blast.
			local function shootFunc(skyPos, norm, length)
				local ground = util.TraceLine { start = skyPos, endpos = skyPos + norm * (length + 1024), mask = MASK_SOLID_BRUSHONLY }
				if ground.HitSky then return end
				local up = skyPos - ground.HitPos
				local gun = ground.HitPos + up:GetNormalized() * math.min(up:Length(), 1500) -- visible height, not the skybox

				for b = 1, cfg.bulletsPerBurst do
					local target = ground.HitPos + Vector(math.Rand(-40, 40), math.Rand(-40, 40), 0)
					local aim = (target - gun):GetNormalized()
					local tr = util.TraceLine { start = gun, endpos = gun + aim * 4000, mask = MASK_SHOT, filter = ply }
					if tr.Hit and not tr.HitSky then
						-- Normal bullet tracer
						local ed = EffectData()
						ed:SetStart(gun)
						ed:SetOrigin(tr.HitPos)
						ed:SetScale(9000)
						ed:SetFlags(0)
						util.Effect("Tracer", ed, true, true)

						-- Dust where it lands
						local dust = EffectData()
						dust:SetOrigin(tr.HitPos)
						dust:SetNormal(tr.HitNormal)
						dust:SetScale(explosive and 120 or 60)
						util.Effect("ThumperDust", dust, true, true)
						util.Decal("Impact.Concrete", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)

						-- Bullet damage to whatever it hit (same friendly-fire rules as the gamemode)
						if IsValid(tr.Entity) then
							local dmg = DamageInfo()
							dmg:SetAttacker(attacker)
							dmg:SetInflictor(attacker)
							dmg:SetDamage(cfg.bulletDamage)
							dmg:SetDamageType(DMG_BULLET)
							dmg:SetDamagePosition(tr.HitPos)
							dmg:SetDamageForce(aim * 3000)
							tr.Entity:TakeDamageInfo(dmg)
						end

						-- Explosive Rounds (Team Upgrade)
						if explosive then
							local fx = EffectData()
							fx:SetOrigin(tr.HitPos)
							fx:SetNormal(tr.HitNormal)
							fx:SetMagnitude(1)
							fx:SetRadius(cfg.explosiveRadius)
							fx:SetFlags(2)
							util.Effect("jcms_blast", fx)
							util.Effect("Explosion", fx)
							util.Decal("Scorch", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
							local dmg = DamageInfo()
							dmg:SetAttacker(attacker)
							dmg:SetInflictor(attacker)
							dmg:SetDamage(cfg.explosiveDamage)
							dmg:SetDamageType(DMG_BLAST)
							dmg:SetDamagePosition(tr.HitPos)
							util.BlastDamageInfo(dmg, tr.HitPos, cfg.explosiveRadius)
						end
					end
				end

				sound.Play("weapons/ar2/fire1.wav", ground.HitPos + Vector(0, 0, 300), 95, math.random(70, 85), 0.8)
				if explosive then
					sound.Play("weapons/explode" .. math.random(3, 5) .. ".wav", ground.HitPos, 90, math.random(95, 115), 0.8)
					util.ScreenShake(ground.HitPos, 6, 30, 0.4, cfg.explosiveRadius * 2, false)
				end
			end

			jcms.net_SendLocator("all", nil, "#jcms.skills_strafe", pos, jcms.LOCATOR_TIMED, 2)
			jcms.spawnmenu_Airstrike {
				pos = pos - dif,
				pos2 = pos + dif,
				delay = { 0.03, 0.06 },
				arrival = 2,
				count = cfg.bursts,
				radius = cfg.spread,
				radius2 = cfg.spread * 1.3,
				shootFunc = shootFunc,
			}
			jcms.util_JetSound(pos)
			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_strafe")
		end,
	}
	-- }}}

	-- // Mini mines for the MultiBlast Mine's "Cluster Payload" Team Upgrade {{{
	local function makeMine(ply, pos, angle, radius, damage, blasts, scale)
		local mine = ents.Create("jcms_landmine")
		mine:SetPos(pos)
		mine:SetAngles(angle)
		mine:SetBlinkScale(scale or 1.5)
		mine:SetBlinkPeriod(0.5)
		mine.Radius = radius
		mine.Damage = damage
		mine.BlastCount = blasts
		mine.BlastCooldown = 1.2
		mine.RequiredTargets = 1
		mine.Proximity = 110
		mine.jcms_owner = ply
		if IsValid(ply) then mine:SetNWInt("jcms_pvpTeam", ply:GetNWInt("jcms_pvpTeam", -1)) end
		if jcms.util_TryUpdateForPVP then jcms.util_TryUpdateForPVP(mine) end
		mine:Spawn()
		mine:SetColor(Color(255, 150, 60))
		local phys = mine:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		if CPPI then mine:CPPISetOwner(game.GetWorld()) end
		return mine
	end

	-- Fires `count` mini mines out of the mine in a spread-out ring. They fly in an arc, land, and explode on
	-- their own after a short fuse (sooner if an enemy walks up to one).
	-- everyBlast = true: a cluster is fired on EVERY blast (MultiBlast upgrade); otherwise only on the last one.
	-- Each volley is rotated so clusters from later blasts land between the earlier ones instead of on top of them.
	local GOLDEN = math.pi * (3 - math.sqrt(5)) -- ~137.5 degrees
	local function launchMini(ply, center, angle, dist, radius, damage, fuseMin, fuseMax)
		-- start just above the mine; aim at a ground spot `dist` away
		local start = center + Vector(0, 0, 24)
		local dir = Vector(math.cos(angle), math.sin(angle), 0)
		local target = center + dir * dist + Vector(0, 0, 40)
		local tr = util.TraceLine({ start = target, endpos = target - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit then target = tr.HitPos end
		-- don't launch through a wall: stop short of it
		local wall = util.TraceLine({ start = start, endpos = start + dir * dist, mask = MASK_SOLID_BRUSHONLY })
		if wall.Hit then
			local d = math.max(24, wall.Fraction * dist - 24)
			target = center + dir * d
			dist = d
		end

		local mini = makeMine(ply, start, AngleRand(), radius, damage, 1, 0.8)
		if not IsValid(mini) then return end
		mini.BlastCooldown = 0.2
		local phys = mini:GetPhysicsObject()
		if IsValid(phys) then
			phys:EnableMotion(true)
			phys:Wake()
			-- ballistic arc that lands at `target` after `t` seconds
			local g = math.abs(physenv.GetGravity().z)
			if g <= 0 then g = 600 end
			local t = 0.7 + dist / 900
			local dz = target.z - start.z
			local vel = dir * (dist / t)
			vel.z = (dz + 0.5 * g * t * t) / t
			phys:SetVelocity(vel)
			phys:AddAngleVelocity(VectorRand() * 400)
		end
		util.SpriteTrail(mini, 0, Color(255, 150, 60), true, 6, 0, 0.35, 0.1, "trails/laser")
		mini:EmitSound("weapons/grenade/tick1.wav", 70, 140)
		timer.Simple(math.Rand(fuseMin, fuseMax), function()
			if IsValid(mini) and (mini.blasts or 0) < (mini.BlastCount or 1) then
				mini:Detonate()
			end
		end)
	end

	function S.AddClusterScatter(mine, ply, count, radius, damage, everyBlast)
		if not IsValid(mine) or mine.sweeperCluster then return end
		mine.sweeperCluster = true
		local U = S.callinUpgrades or {}
		local volley = 0
		local origDetonate = mine.Detonate
		mine.Detonate = function(self, ...)
			local center = self:GetPos()
			local last = (self.blasts or 0) + 1 >= (self.BlastCount or 1)
			local r = origDetonate(self, ...)
			if everyBlast or (last and not self.sweeperScattered) then
				self.sweeperScattered = true
				volley = volley + 1
				local rot = volley * GOLDEN
				local distMin, distMax = U.multiblastScatterMin or 140, U.multiblastScatterMax or 320
				for b = 1, count do
					timer.Simple(0.05 * b, function()
						-- even spacing around the circle, alternating near/far rings so they don't bunch up
						local a = rot + (b / count) * math.pi * 2 + math.Rand(-0.15, 0.15)
						local ring = (b % 2 == 0) and 1 or 0
						local dist = Lerp(ring * 0.5 + math.Rand(0, 0.5), distMin, distMax)
						launchMini(ply, center, a, dist, radius, damage, U.multiblastFuseMin or 1.2, U.multiblastFuseMax or 1.8)
					end)
				end
				local ed = EffectData()
				ed:SetOrigin(center)
				util.Effect("ManhackSparks", ed, true, true)
			end
			return r
		end
	end
	-- }}}

	function S.InstallCallins()
		if not (jcms and jcms.orders and jcms.orders_argparser) then return end

		-- Drones spawn at the player, so no aiming is needed.
		jcms.orders_argparser.sweeper_self = jcms.orders_argparser.sweeper_self or function(ply, args)
			return true
		end

		for id, def in pairs(defs) do
			local c = S.callins[id]
			if not jcms.orders[id] then
				jcms.orders[id] = {
					category = jcms["SPAWNCAT_" .. c.category] or jcms.SPAWNCAT_UTILITY,
					cost = c.cost,
					cooldown = c.cooldown,
					slotPos = c.slotPos,
					argparser = def.argparser,
					func = def.func,
					pvpBlacklisted = (id == "skills_uav") or nil,
				}
			end
		end
	end

	hook.Add("Initialize", "sweeper_callins", S.InstallCallins)
	S.InstallCallins() -- Lua refresh

	-- // Team Upgrade: Carpet Bomb: Wide Pattern (g_carpet) {{{
	-- Wraps the gamemode's carpetbombing order. While it runs, its airstrike gets a wider bomb spread,
	-- a longer line and extra bombs. Nothing in the gamemode is edited.
	function S.InstallCarpetUpgrade()
		local order = jcms and jcms.orders and jcms.orders.carpetbombing
		if not order or S.Wrapped(order, "Carpet") then return end
		local orig = order.func
		S._wrappedCarpet = function(ply, pos, ...)
			local rank = S.GroupRank and S.GroupRank("g_carpet") or 0
			if rank <= 0 then return orig(ply, pos, ...) end

			local U = S.callinUpgrades
			local mul = 1 + U.carpetRadiusPerRank * rank
			local origAirstrike = jcms.spawnmenu_Airstrike
			jcms.spawnmenu_Airstrike = function(info)
				if info.radius then info.radius = info.radius * mul end
				if info.radius2 then info.radius2 = info.radius2 * mul end
				if info.pos2 then -- stretch the line around its middle
					local mid = (info.pos + info.pos2) / 2
					info.pos = mid + (info.pos - mid) * mul
					info.pos2 = mid + (info.pos2 - mid) * mul
				end
				info.count = (info.count or 1) + U.carpetBombsPerRank * rank
				return origAirstrike(info)
			end
			local ok, r = pcall(orig, ply, pos, ...)
			jcms.spawnmenu_Airstrike = origAirstrike
			if not ok then error(r, 0) end
			return r
		end
		order.func = S._wrappedCarpet
		S.MarkWrapped(order, "Carpet")
	end
	hook.Add("Initialize", "sweeper_carpetUpgrade", S.InstallCarpetUpgrade)
	hook.Add("InitPostEntity", "sweeper_carpetUpgrade", S.InstallCarpetUpgrade)
	S.InstallCarpetUpgrade()
	-- }}}

	-- // Team Upgrade: MultiBlast Mine: Cluster Payload (g_multiblast) {{{
	-- The gamemode's MultiBlast mine doesn't hand back the mine it makes, so while its order runs we catch the
	-- jcms_landmine it creates and make it fire a cluster of mini mines on every blast.
	function S.InstallMultiblastUpgrade()
		local order = jcms and jcms.orders and jcms.orders.mine_multiblast
		if not order or S.Wrapped(order, "Multiblast") then return end
		local orig = order.func
		S._wrappedMultiblast = function(ply, ...)
			local rank = S.GroupRank and S.GroupRank("g_multiblast") or 0
			if rank <= 0 then return orig(ply, ...) end

			local made = {}
			local origCreate = ents.Create
			ents.Create = function(class, ...)
				local e = origCreate(class, ...)
				if class == "jcms_landmine" then made[#made + 1] = e end
				return e
			end
			local ok, r = pcall(orig, ply, ...)
			ents.Create = origCreate
			if not ok then error(r, 0) end

			local U = S.callinUpgrades
			for i, mine in ipairs(made) do
				S.AddClusterScatter(mine, ply, U.multiblastBombletsBase + U.multiblastBombletsPerRank * rank,
					U.multiblastBombletRadius, U.multiblastBombletDamage, true)
			end
			return r
		end
		order.func = S._wrappedMultiblast
		S.MarkWrapped(order, "Multiblast")
	end
	hook.Add("Initialize", "sweeper_multiblastUpgrade", S.InstallMultiblastUpgrade)
	hook.Add("InitPostEntity", "sweeper_multiblastUpgrade", S.InstallMultiblastUpgrade)
	S.InstallMultiblastUpgrade()
	-- }}}
end

-- // Team Upgrade: Jump Pad: Overcharged Springs (g_jumppad) {{{
-- Shared (the launch is predicted), so both realms use the same numbers; ranks are synced to clients.
-- Same launch as the gamemode's jcms_jumppad, with the height and forward push scaled up.
function S.InstallJumpPadUpgrade()
	local stored = scripted_ents.GetStored("jcms_jumppad")
	local ENT = stored and stored.t
	if not ENT or not ENT.LaunchPlayer or S.Wrapped(ENT, "JumpPad") then return end
	local orig = ENT.LaunchPlayer
	S._wrappedJumpPad = function(self, ply, ...)
		local rank = S.GroupRank and S.GroupRank("g_jumppad") or 0
		if rank <= 0 or not self.GetOverclocked then return orig(self, ply, ...) end

		local U = S.callinUpgrades
		local up = 1 + U.jumpHeightPerRank * rank
		local fwd = 1 + U.jumpForcePerRank * rank

		self:JumpEffect()
		if SERVER then ply.noFallDamage = true end

		local isOverclocked = self:GetOverclocked()
		local vector = Vector(0, 0, (isOverclocked and (ply:Crouching() and 950 or 1300) or (ply:Crouching() and 260 or 580)) * up)
		local ev = ply:EyeAngles():Forward()
		ev:Mul(isOverclocked and ((U.jumpOverclockForwardPerRank or 0) * rank) or (128 * fwd))
		ev:Add(vector)

		if isOverclocked or self.jcms_isSingleUse then
			local oldVel = ply:GetVelocity()
			oldVel:Mul(0.8)
			ev:Sub(oldVel)
			if SERVER and self.BreakByBreach then self:BreakByBreach(-ev) end
		end
		ply:SetVelocity(ev)
	end
	ENT.LaunchPlayer = S._wrappedJumpPad
	S.MarkWrapped(ENT, "JumpPad")
end
hook.Add("Initialize", "sweeper_jumpPadUpgrade", S.InstallJumpPadUpgrade)
hook.Add("InitPostEntity", "sweeper_jumpPadUpgrade", S.InstallJumpPadUpgrade)
S.InstallJumpPadUpgrade()
-- }}}
-- }}}

-- // Client: UAV scan outlines {{{
if CLIENT then
	S.uavScans = S.uavScans or {}

	net.Receive("sweeper_uav", function()
		local scan = {
			pos = net.ReadVector(),
			endTime = net.ReadFloat(),
			radius = net.ReadUInt(16),
			team = net.ReadInt(8),
		}
		local me = LocalPlayer()
		local myTeam = IsValid(me) and me:GetNWInt("jcms_pvpTeam", -1) or -1
		if scan.team ~= -1 and myTeam ~= -1 and scan.team ~= myTeam then return end -- enemy team's UAV

		table.insert(S.uavScans, scan)
		surface.PlaySound("npc/scanner/scanner_blip1.wav")
	end)

	local function isEnemy(ent)
		if not (IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot())) then return false end
		if ent:Health() <= 0 then return false end
		if jcms and jcms.team_NPC and not jcms.team_NPC(ent) then return false end
		return true
	end

	local outlined = {}
	local nextScan = 0
	hook.Add("PreDrawHalos", "sweeper_uav", function()
		if #S.uavScans == 0 then return end
		local ct = CurTime()

		if ct >= nextScan then
			nextScan = ct + 0.25
			table.Empty(outlined)
			for i = #S.uavScans, 1, -1 do
				local scan = S.uavScans[i]
				if ct > scan.endTime then
					table.remove(S.uavScans, i)
				else
					for j, ent in ipairs(ents.FindInSphere(scan.pos, scan.radius)) do
						if isEnemy(ent) then outlined[#outlined + 1] = ent end
					end
				end
			end
		end

		if #outlined > 0 then
			local col = (jcms and jcms.color_alert1) or Color(255, 255, 0)
			halo.Add(outlined, col, 2, 2, 1, true, true)
		end
	end)

	-- "UAV SCAN ACTIVE" under the XP bar, in the gamemode's HUD panel
	S.AddHud("uav", "top", function(ply, alpha)
		local best = 0
		for i, scan in ipairs(S.uavScans) do
			best = math.max(best, scan.endTime - CurTime())
		end
		if best > 0 then
			S.HudGlowText(string.format("UAV SCAN ACTIVE  %ds  -  %d ENEMIES", math.ceil(best), #outlined),
				"jcms_hud_small", 0, 330, jcms.color_alert1, jcms.color_dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	end)
end
-- }}}
