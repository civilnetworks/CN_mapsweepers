--[[
	Map Sweepers - Implants & Class Levels (addon)
	OFFENSIVE CALL-INS (everyone - no class locks)

	  skills_napalm     Napalm Strike      a bombing run that leaves a burning line of ground
	  skills_gas        Gas Strike         a flight drops gas canisters that burst into a bank of toxic cloud
	  skills_smoke      Smoke Screen       the same run, but smoke: enemies lose sight of you through it
	  skills_lance      Orbital Lance      a charged beam on one spot after a short warning
	  skills_cluster    Cluster Bomb       one bomb that splits into bomblets over a wide circle
	  skills_emp        EMP Burst          strips enemy shields and scrambles everything nearby

	Fire and gas only hurt enemies, never sweepers. Tuning is in the entries below.
--]]

local S = sweeper

S.callins = S.callins or {}

local NEW = {
	skills_napalm = {
		name = "Napalm Strike",
		desc = "A bombing run that sets a line of ground on fire for 15s. Burns enemies only.",
		cost = 400, cooldown = 60, category = "ORBITALS", slotPos = 9,
		bombs = 5, spacing = 170, arrival = 2,
		blastRadius = 150, blastDamage = 60,
		fireRadius = 150, fireDuration = 15, fireDps = 18,
	},
	skills_gas = {
		name = "Gas Strike",
		desc = "A flight drops 4 gas canisters scattered over the target. Each bursts into a toxic cloud that hangs for 18s, and the clouds stack where they overlap. Enemies only.",
		cost = 300, cooldown = 45, category = "ORBITALS", slotPos = 10,

		arrival = 2,         -- seconds before the FIRST canister comes down
		canisters = 4,       -- how many fall
		spread = 240,        -- how far from your mark they scatter
		stagger = 0.45,      -- seconds between one canister landing and the next. They drop one by one,
		                     -- each onto the spot its own cloud fills, so 4 at 0.45 = a 1.35s run.
		burstRadius = 70, burstDamage = 25, -- the canister's own impact. The gas is the real payload.

		-- Each canister's cloud. dps is PER CLOUD and the hazard loop ticks each zone separately, so
		-- they stack in the overlaps: the middle of a tight drop hurts several times what the edge does.
		radius = 190, duration = 18, dps = 8,

		-- Scatter shape, same as the Cluster Bomb below. scatterInner 0 lets one land dead on the mark.
		scatterJitter = 2.0,
		scatterInner = 0.0,
	},
	skills_smoke = {
		name = "Smoke Screen",
		desc = "A flight lays 5 smoke canisters one by one across the target. Enemies whose line of sight to you crosses the smoke lose track of you, and turrets can't see through it either. Does no damage.",
		cost = 200, cooldown = 40, category = "ORBITALS", slotPos = 4,

		-- Delivered exactly like the Gas Strike above: one canister at a time, each onto the spot
		-- its own bank will fill. More of them, spread wider, because cover wants to be continuous.
		arrival = 2,
		canisters = 5,
		spread = 260,
		stagger = 0.45,
		burstRadius = 0, burstDamage = 0, -- a smoke canister hits nobody

		radius = 230,        -- each bank's reach
		duration = 22,       -- and how long it hangs. Longer than the gas: this one is cover, not damage.

		scatterJitter = 2.0,
		scatterInner = 0.0,
	},
	skills_lance = {
		name = "Orbital Lance",
		desc = "The array charges on one spot for 3s, then fires a beam down it: 1500 damage in a tight radius.",
		cost = 600, cooldown = 120, category = "ORBITALS", slotPos = 11,
		delay = 3, radius = 260, damage = 1500,

		-- The column is the gamemode's own jcms_deathray, the entity behind the Orbital Beam order -
		-- same sky beam, same charge-up sound and screen presence. It is spawned standing still
		-- instead of under a jcms_deathraycontroller, which is what makes a lance a lance: the beam
		-- is fixed on the mark rather than roaming after targets.
		beamRadius = 90,     -- the column's width. The Orbital Beam order uses 32.
		beamDuration = 1.2,  -- how long it fires once charged. One stab, not a sweep.
		beamDps = 0,         -- the beam's OWN damage per second while it fires, and its per-hit
		beamDpsDirect = 0,   -- damage. Both 0 keeps every bit of the punch in the single blast, so
		                     -- raising `damage` is the only thing that changes how hard a lance hits.
	},
	skills_cluster = {
		name = "Cluster Bomb",
		desc = "One bomb that splits into 12 bomblets scattered at random over a wide circle. Good against a spread-out wave.",
		cost = 350, cooldown = 45, category = "ORBITALS", slotPos = 12,
		arrival = 2, bomblets = 12, spread = 420, blastRadius = 130, blastDamage = 90, stagger = 0.08,

		-- How scattered the bomblets are. Each one owns a sector of the circle so the whole area still
		-- gets covered, but everything about where and when it lands inside that is rolled fresh.
		scatterJitter = 2.0,   -- how far out of its own sector a bomblet may drift, in sectors.
		                       -- 0 = a perfectly even ring. 1 = it stays in its sector. 2+ = it can
		                       -- cross into its neighbours', so you get real clumps and gaps.
		scatterInner = 0.01,   -- closest a bomblet lands, as a fraction of spread
		timeJitter = 0.45,     -- seconds of random slop on each bomblet's delay, so they don't tick off in time
	},
	-- // Shelling variants {{{
	-- The gamemode's own Shelling is a long artillery barrage that WALKS across a wide area: dozens of
	-- shells, each landing a moment after the last, scattering further as the barrage drifts. These
	-- three borrow that delivery and swap the warhead for one of the hazard payloads, so where the
	-- Gas Strike and Smoke Screen put a tight bank of cloud exactly where you marked, these blanket a
	-- whole area in patches of it. Far more ground denied, far longer, for a lot more J.
	--
	-- Shell counts are deliberately nowhere near the gamemode's 50-60: every shell here leaves a
	-- lasting zone rather than just a crater. Each gas or smoke zone is 22 drawn puffs clientside and
	-- each gas zone ticks its own damage, so 9 is about two Smoke Screens' worth of both - fine, where
	-- 50 would be a slideshow and instant death. Fire zones are cheaper (14 puffs), so napalm affords more.
	skills_smokeshell = {
		name = "Smoke Shelling",
		desc = "A walking artillery barrage that blankets a wide area in smoke for 20s. Enemies lose track of anyone behind it and turrets can't see through it. Does no damage.",
		cost = 350, cooldown = 70, category = "ORBITALS", slotPos = 14,

		shells = 9,          -- impacts across the barrage
		arrival = 3,         -- seconds before the first shell lands
		walk = 260,          -- how far the barrage drifts as it goes
		radius = 700,        -- scatter at the start...
		radius2 = 1600,      -- ...and by the end, so it spreads as it walks
		delayMin = 0.5, delayMax = 1.3,  -- gap between shells
		flight = 1.5,        -- shell flight time, matched to the bolt effect

		burstRadius = 0, burstDamage = 0,     -- a smoke shell hurts nobody
		zoneRadius = 180, zoneDuration = 20,  -- each shell's bank of cover
	},
	skills_gasshell = {
		name = "Gas Shelling",
		desc = "A walking artillery barrage of gas shells. Each one leaves a toxic cloud for 16s, and they stack where they overlap - a whole area made uninhabitable. Enemies only.",
		cost = 500, cooldown = 90, category = "ORBITALS", slotPos = 15,

		shells = 9,
		arrival = 3,
		walk = 260,
		radius = 700, radius2 = 1600,
		delayMin = 0.5, delayMax = 1.3,
		flight = 1.5,

		burstRadius = 60, burstDamage = 20,   -- the shell itself is barely the point
		-- Lower per-cloud dps than the Gas Strike's 8, because a barrage lays down far more overlap
		zoneRadius = 170, zoneDuration = 16, zoneDps = 6,
	},
	skills_napalmshell = {
		name = "Napalm Shelling",
		desc = "A walking artillery barrage of incendiary shells that leaves a wide area burning for 14s. Sets enemies alight. Burns enemies only.",
		cost = 550, cooldown = 90, category = "ORBITALS", slotPos = 16,

		shells = 12,         -- fire zones are lighter to draw than gas or smoke, so more of them
		arrival = 3,
		walk = 300,
		radius = 700, radius2 = 1700,
		delayMin = 0.45, delayMax = 1.2,
		flight = 1.5,

		burstRadius = 110, burstDamage = 40,
		zoneRadius = 150, zoneDuration = 14, zoneDps = 16,
	},
	-- }}}
	skills_emp = {
		name = "EMP Burst",
		desc = "A twin EMP over the target: two pulses strip enemy shields, deal 240 shock damage each and scramble enemies for 8s (they lose track of you and stumble at 45% speed). The second pulse lands a moment later and reaches wider.",
		cost = 400, cooldown = 75, category = "ORBITALS", slotPos = 13,
		arrival = 1.5, radius = 650, damage = 240, scramble = 8, slowMul = 0.45,

		-- Double tap. The second pulse re-strips anything that recharged and refreshes the scramble,
		-- so the window is measured from the LAST pulse, not the first.
		pulses = 2,
		pulseGap = 0.7,

		-- How hard each pulse hits the screen. The blast is jcms_blast flag 5 stacked `blastLayers`
		-- deep, each layer tighter than the last and `blastLayerGap` behind it.
		blastLayers = 3,
		blastLayerGap = 0.05,
		blastDuration = 1.35,  -- multiplier on the effect's own ~1s life
		pulseRadiusMul = 1.15,   -- the follow-up rolls out wider
		pulseDamageMul = 1,      -- drop this to soften the second hit without touching the first
	},
}

for id, cfg in pairs(NEW) do S.callins[id] = cfg end

if CLIENT then
	for id, c in pairs(NEW) do
		language.Add("jcms." .. id, c.name)
		language.Add("jcms." .. id .. "_desc", c.desc)
	end
end

-- // Hazard zones: fire and gas {{{
-- One shared system. The server keeps the list and does the damage; clients get told where each zone is
-- and draw it. Zones only hurt enemies.
if SERVER then
	util.AddNetworkString("sweeper_hazard")
	util.AddNetworkString("sweeper_emp")

	local zones = {}

	local function isEnemy(ent)
		return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot())
			and ent:Health() > 0 and jcms and jcms.team_NPC and jcms.team_NPC(ent)
	end

	-- kind = "fire", "gas", or "smoke". Smoke does no damage at all - it blinds instead, further down.
	function S.SpawnHazard(kind, pos, radius, duration, dps, owner)
		zones[#zones + 1] = {
			kind = kind, pos = pos, radius = radius, dps = dps,
			untilT = CurTime() + duration, owner = owner, nextTick = 0,
		}
		net.Start("sweeper_hazard")
			net.WriteString(kind)
			net.WriteVector(pos)
			net.WriteUInt(math.Clamp(radius, 0, 2000), 11)
			net.WriteFloat(CurTime() + duration)
		net.Broadcast()
	end

	timer.Create("sweeper_hazards", 0.5, 0, function()
		local ct = CurTime()
		for i = #zones, 1, -1 do
			local z = zones[i]
			if ct >= z.untilT then
				table.remove(zones, i)
			elseif z.kind == "smoke" then
				-- Nothing to do: smoke deals no damage, so it never sweeps for targets here
			else
				local attacker = IsValid(z.owner) and z.owner or game.GetWorld()
				for j, ent in ipairs(ents.FindInSphere(z.pos, z.radius)) do
					if isEnemy(ent) then
						local dmg = DamageInfo()
						dmg:SetDamage(z.dps * 0.5)
						dmg:SetDamageType(z.kind == "gas" and DMG_NERVEGAS or DMG_BURN)
						dmg:SetAttacker(attacker)
						dmg:SetInflictor(attacker)
						dmg:SetDamagePosition(ent:WorldSpaceCenter())
						ent:TakeDamageInfo(dmg)
						if z.kind == "fire" and ent.Ignite and not ent:IsOnFire() then ent:Ignite(3) end
					end
				end
			end
		end
	end)

	-- // Smoke blinds {{{
	-- The gamemode's own jcms.smokeScreens list only ever gets read by jcms_turret and jcms_tesla, so
	-- registering there blinds turrets but does nothing to NPCs - which is why the gamemode's smoke
	-- order is pvpExclusive. This does the NPC half: any enemy whose line of sight to its target
	-- crosses a smoke ball loses that target, the same SetEnemy/ClearEnemyMemory the EMP scramble uses.

	-- True when the segment a->b touches live smoke. Unlike the gamemode's turret version this also
	-- counts a segment that STARTS or ENDS inside a ball, so standing in the cloud hides you too.
	local function smokeBlocks(a, b)
		local ct = CurTime()
		local delta = b - a
		for i = 1, #zones do
			local z = zones[i]
			if z.kind == "smoke" and ct < z.untilT then
				local f1, f2 = util.IntersectRayWithSphere(a, delta, z.pos, z.radius)
				if f1 and f2 and f2 > 0 and f1 < 1 then return true end
			end
		end
		return false
	end
	S.SmokeBlocks = smokeBlocks

	function S.SmokeActive()
		local ct = CurTime()
		for i = 1, #zones do
			if zones[i].kind == "smoke" and ct < zones[i].untilT then return true end
		end
		return false
	end

	timer.Create("sweeper_smokeBlind", 0.35, 0, function()
		if not S.SmokeActive() then return end

		for i, npc in ipairs(ents.FindByClass("npc_*")) do
			if IsValid(npc) and npc:IsNPC() and npc:Health() > 0 and jcms.team_NPC(npc) then
				local foe = npc.GetEnemy and npc:GetEnemy()
				if IsValid(foe) and (foe:IsPlayer() or (jcms.team_JCorp and jcms.team_JCorp(foe))) then
					if smokeBlocks(npc:EyePos(), foe:WorldSpaceCenter()) then
						npc:SetEnemy(NULL)
						if npc.ClearEnemyMemory then npc:ClearEnemyMemory(foe) end
					end
				end
			end
		end
	end)
	-- }}}

	-- a hazard on the ground below `pos`
	local function groundHazard(kind, pos, cfg, owner)
		local tr = util.TraceLine({ start = pos + Vector(0, 0, 32), endpos = pos - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
		local at = tr.Hit and (tr.HitPos + Vector(0, 0, 8)) or pos
		S.SpawnHazard(kind, at, cfg.fireRadius or cfg.radius or 150, cfg.fireDuration or cfg.duration or 15,
			cfg.fireDps or cfg.dps or 15, owner)
	end
	S.GroundHazard = groundHazard
end
-- }}}

-- // The call-ins {{{
if SERVER then
	local function pvpTeam(ply)
		return IsValid(ply) and ply:GetNWInt("jcms_pvpTeam", -1) or -1
	end

	local function cfgOf(id)
		return (S.CallinCfg and S.CallinCfg(id)) or S.callins[id]
	end

	local function enemiesNear(pos, range, max)
		local list = {}
		for i, ent in ipairs(ents.FindInSphere(pos, range)) do
			if not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0
				and jcms.team_NPC(ent) then
				list[#list + 1] = { ent = ent, d = ent:GetPos():DistToSqr(pos) }
			end
		end
		table.sort(list, function(a, b) return a.d < b.d end)
		local out = {}
		for i = 1, math.min(#list, max or 3) do out[i] = list[i].ent end
		return out
	end

	local function seeker(ply, from, target, damage, radius)
		local missile = ents.Create("jcms_micromissile")
		if not IsValid(missile) then return end
		missile:SetPos(from)
		missile.Damage = damage
		missile.Radius = radius
		missile.Proximity = 45
		missile.Target = target
		missile.jcms_owner = ply
		if IsValid(ply) then missile:SetNWInt("jcms_pvpTeam", pvpTeam(ply)) end
		missile:Spawn()
		return missile
	end
	S.SpawnSeeker = seeker
	S.EnemiesNear = enemiesNear 
	
	local function scatterPoints(pos, count, spread, jitter, inner)
		count = math.max(1, math.floor(count or 1))
		jitter = jitter or 2
		local sector = (math.pi * 2) / count
		local spin = math.Rand(0, math.pi * 2) -- the whole pattern starts somewhere different every call

		local slots = {}
		for i = 1, count do slots[i] = i end
		for i = count, 2, -1 do
			local j = math.random(i)
			slots[i], slots[j] = slots[j], slots[i]
		end

		local out = {}
		for i = 1, count do
			local ang = spin + (slots[i] - 1) * sector + math.Rand(-0.5, 0.5) * sector * jitter
			-- sqrt keeps them even over the area rather than bunched in the middle
			local dist = (spread or 0) * math.sqrt(math.Rand(inner or 0, 1))
			out[i] = pos + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 0)
		end
		return out
	end
	S.ScatterPoints = scatterPoints

	local defs = {}

	defs.skills_napalm = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = cfgOf("skills_napalm")
			local dir = IsValid(ply) and ply:GetAimVector() or Vector(1, 0, 0)
			dir.z = 0
			dir:Normalize()
			local last = pos + dir * cfg.spacing * (cfg.bombs - 1)

			if jcms.net_SendLocator then jcms.net_SendLocator("all", nil, "#jcms.skills_napalm", pos, jcms.LOCATOR_WARNING, cfg.arrival + 1) end
			if jcms.spawnmenu_Airstrike then jcms.spawnmenu_Airstrike {
				pos = pos, pos2 = last, count = cfg.bombs, arrival = cfg.arrival, radius = 40,
				blast_radius = cfg.blastRadius, blast_damage = cfg.blastDamage,
				callback = function(bomb) if IsValid(ply) then bomb.jcms_owner = ply end end,
			} end
			if jcms.util_JetSound then jcms.util_JetSound(pos) end

			for i = 1, cfg.bombs do
				local at = pos + dir * cfg.spacing * (i - 1)
				timer.Simple(cfg.arrival + i * 0.12, function()
					S.GroundHazard("fire", at, cfg, ply)
					sound.Play("ambient/fire/mtov_flame2.wav", at, 75, 100, 0.8)
				end)
			end
			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_napalm")
		end,
	}


	defs.skills_gas = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = cfgOf("skills_gas")
			local points = scatterPoints(pos, cfg.canisters or 4, cfg.spread, cfg.scatterJitter, cfg.scatterInner)
			local stagger = cfg.stagger or 0.45

			-- The warning has to cover the whole run, not just the first canister
			if jcms.net_SendLocator then
				local lastDrop = cfg.arrival + (#points - 1) * stagger
				jcms.net_SendLocator("all", nil, "#jcms.skills_gas", pos, jcms.LOCATOR_WARNING, lastDrop + 1)
			end
			if jcms.util_JetSound then jcms.util_JetSound(pos) end

			for i, at in ipairs(points) do
				-- One canister at a time, each falling onto the spot its own cloud will fill, so the
				-- bank builds up in front of you instead of appearing all at once.
				local drop = cfg.arrival + (i - 1) * stagger

				if jcms.spawnmenu_Airstrike then
					jcms.spawnmenu_Airstrike {
						pos = at, count = 1, arrival = drop, radius = 0,
						blast_radius = cfg.burstRadius or 70, blast_damage = cfg.burstDamage or 25,
						callback = function(bomb) if IsValid(ply) then bomb.jcms_owner = ply end end,
					}
				end

				-- ...and its cloud opens where that canister just hit
				timer.Simple(drop + 0.1, function()
					local from = at + Vector(0, 0, 32)
					local tr = util.TraceLine({ start = from, endpos = from - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
					local ground = tr.Hit and (tr.HitPos + Vector(0, 0, 8)) or at
					S.SpawnHazard("gas", ground, cfg.radius or 190, cfg.duration or 18, cfg.dps or 8, ply)
					sound.Play("ambient/levels/labs/electric_explosion4.wav", ground, 80, math.random(110, 130), 0.6)
				end)
			end

			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_gas")
		end,
	}


	-- The Gas Strike's delivery with the payload swapped: cover instead of poison.
	defs.skills_smoke = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = cfgOf("skills_smoke")
			local points = scatterPoints(pos, cfg.canisters or 5, cfg.spread, cfg.scatterJitter, cfg.scatterInner)
			local stagger = cfg.stagger or 0.45

			if jcms.net_SendLocator then
				local lastDrop = cfg.arrival + (#points - 1) * stagger
				jcms.net_SendLocator("all", nil, "#jcms.skills_smoke", pos, jcms.LOCATOR_TIMED, lastDrop + 1)
			end
			if jcms.util_JetSound then jcms.util_JetSound(pos) end

			for i, at in ipairs(points) do
				local drop = cfg.arrival + (i - 1) * stagger

				if jcms.spawnmenu_Airstrike then
					jcms.spawnmenu_Airstrike {
						pos = at, count = 1, arrival = drop, radius = 0,
						blast_radius = cfg.burstRadius or 0, blast_damage = cfg.burstDamage or 0,
						callback = function(bomb) if IsValid(ply) then bomb.jcms_owner = ply end end,
					}
				end

				timer.Simple(drop + 0.1, function()
					local from = at + Vector(0, 0, 32)
					local tr = util.TraceLine({ start = from, endpos = from - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
					local ground = tr.Hit and (tr.HitPos + Vector(0, 0, 8)) or at
					local radius, duration = cfg.radius or 230, cfg.duration or 22

					S.SpawnHazard("smoke", ground, radius, duration, 0, ply)

					-- ...and into the gamemode's own list, so its turrets and tesla coils are blind to
					-- anything behind this bank as well.
					if jcms.smokeScreens then
						table.insert(jcms.smokeScreens, { pos = ground, rad = radius, expires = CurTime() + duration })
					end

					local ed = EffectData()
					ed:SetMagnitude(12)
					ed:SetOrigin(ground)
					ed:SetNormal(Vector(0, 0, 1))
					ed:SetRadius(radius)
					ed:SetFlags(3)
					ed:SetColor(jcms.util_ColorInteger(Color(200, 200, 200, 255)))
					util.Effect("jcms_blast", ed)

					sound.Play("weapons/flaregun/fire.wav", ground, 110, math.random(80, 95), 0.8)
				end)
			end

			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_smoke")
		end,
	}


	-- // Shelling variants: Smoke, Gas, Napalm {{{
	-- One helper, three payloads. The delivery is the gamemode's own Shelling (sv_spawnmenu.lua): an
	-- airstrike given a second, offset aim point and a widening radius, so the barrage walks across the
	-- ground instead of landing in one circle. Its shootFunc is where a shell becomes a hazard: trace
	-- down from the shell to find what it actually hits, draw the incoming bolt, then after the flight
	-- time plant the zone and deal the shell's own (small) blast.
	local function shellBarrage(ply, pos, id, kind)
		local cfg = cfgOf(id)
		local shells = math.max(1, math.floor(cfg.shells or 9))
		local flight = cfg.flight or 1.5
		local team = pvpTeam(ply)
		if team == -1 then team = 1 end -- the bolt effect uses this as a colour index

		-- The barrage drifts, so warn over the whole footprint and for the whole run: arrival, plus the
		-- worst case of every gap being the longest, plus one shell's flight.
		local runFor = cfg.arrival + shells * (cfg.delayMax or 1.3) + flight
		if jcms.net_SendLocator then
			jcms.net_SendLocator("all", nil, "#jcms." .. id, pos,
				kind == "smoke" and jcms.LOCATOR_TIMED or jcms.LOCATOR_WARNING, runFor)
		end
		if jcms.util_JetSound then jcms.util_JetSound(pos) end

		local drift = VectorRand(-(cfg.walk or 260), cfg.walk or 260)
		drift.z = 0

		local function shootFunc(bombPos, norm, length)
			local tr = util.TraceLine {
				start = bombPos, endpos = bombPos + norm * (length + 1024),
				mask = MASK_PLAYERSOLID_BRUSHONLY,
			}

			-- The incoming shell, same effect the gamemode's Shelling uses
			local ed = EffectData()
			ed:SetStart(tr.StartPos)
			ed:SetOrigin(tr.HitPos)
			ed:SetFlags(3)
			ed:SetMagnitude(1.5)
			ed:SetMaterialIndex(team)
			util.Effect("jcms_bolt", ed)

			sound.EmitHint(SOUND_DANGER, tr.HitPos, (cfg.zoneRadius or 170) * 2, flight)

			local at = tr.HitPos
			timer.Simple(flight, function()
				-- The shell's own blast. Small on purpose: the payload is what this order is for.
				if (cfg.burstDamage or 0) > 0 then
					local dmg = DamageInfo()
					local src = IsValid(ply) and ply or game.GetWorld()
					dmg:SetInflictor(src)
					dmg:SetAttacker(src)
					dmg:SetDamage(cfg.burstDamage)
					dmg:SetDamageType(DMG_BLAST)
					dmg:SetReportedPosition(at)
					dmg:SetDamagePosition(at)
					util.BlastDamageInfo(dmg, at, cfg.burstRadius or 100)
					util.ScreenShake(at, 6, 30, math.Rand(0.3, 0.5), (cfg.burstRadius or 100) * 2, false)
				end

				-- ...and the zone it leaves behind, which is the actual point of the order
				local from = at + Vector(0, 0, 32)
				local down = util.TraceLine({ start = from, endpos = from - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
				local ground = down.Hit and (down.HitPos + Vector(0, 0, 8)) or at
				S.SpawnHazard(kind, ground, cfg.zoneRadius or 170, cfg.zoneDuration or 16, cfg.zoneDps or 0, ply)
			end)
		end

		if jcms.spawnmenu_Airstrike then
			jcms.spawnmenu_Airstrike {
				pos = pos,
				pos2 = pos + drift,
				delay = { cfg.delayMin or 0.5, cfg.delayMax or 1.3 },
				arrival = cfg.arrival or 3,
				count = shells,
				radius = cfg.radius or 700,
				radius2 = cfg.radius2 or 1600,
				shootFunc = shootFunc,
			}
		end

		jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms." .. id)
	end
	S.ShellBarrage = shellBarrage

	defs.skills_smokeshell = {
		argparser = "orbital_fixed",
		func = function(ply, pos) shellBarrage(ply, pos, "skills_smokeshell", "smoke") end,
	}
	defs.skills_gasshell = {
		argparser = "orbital_fixed",
		func = function(ply, pos) shellBarrage(ply, pos, "skills_gasshell", "gas") end,
	}
	defs.skills_napalmshell = {
		argparser = "orbital_fixed",
		func = function(ply, pos) shellBarrage(ply, pos, "skills_napalmshell", "fire") end,
	}
	-- }}}


	defs.skills_lance = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = cfgOf("skills_lance")
			if jcms.net_SendLocator then jcms.net_SendLocator("all", nil, "#jcms.skills_lance", pos, jcms.LOCATOR_WARNING, cfg.delay) end
			sound.Play("ambient/machines/combine_terminal_idle4.wav", pos, 90, 80, 1)

			-- The Orbital Beam's own beam entity, standing still on the mark. It charges for the same
			-- delay the warning locator counts down, fires for beamDuration, then removes itself
			-- (jcms_deathray:Think does that once beamTime passes prep + lifetime).
			local ray = ents.Create("jcms_deathray")
			if IsValid(ray) then
				ray:SetPos(pos)
				ray:SetBeamIsSky(true)
				ray:Spawn()

				ray:SetBeamRadius(cfg.beamRadius or 90)
				ray:SetBeamPrepTime(cfg.delay)
				ray:SetBeamLifeTime(cfg.beamDuration or 1.2)
				if jcms.util_GetPVPVectorColor then
					ray:SetBeamColour(jcms.util_GetPVPVectorColor(ply))
				end
				ray.DPS = cfg.beamDps or 0
				ray.DPS_DIRECT = cfg.beamDpsDirect or 0
				ray.jcms_owner = ply
			end

			timer.Simple(cfg.delay, function()
				local ed = EffectData()
				ed:SetOrigin(pos)
				ed:SetMagnitude(3)
				ed:SetScale(3)
				util.Effect("cball_explode", ed, true, true)
				util.ScreenShake(pos, 18, 60, 1.2, cfg.radius * 4)
				sound.Play("ambient/explosions/explode_7.wav", pos, 120, 90, 1)
				util.BlastDamage(IsValid(ply) and ply or game.GetWorld(), IsValid(ply) and ply or game.GetWorld(),
					pos, cfg.radius, cfg.damage)
			end)
			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_lance")
		end,
	}




	defs.skills_cluster = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = cfgOf("skills_cluster")
			if jcms.net_SendLocator then jcms.net_SendLocator("all", nil, "#jcms.skills_cluster", pos, jcms.LOCATOR_WARNING, cfg.arrival + 1) end
			if jcms.util_JetSound then jcms.util_JetSound(pos) end

			-- the carrier bomb, then the bomblets scattered around where it lands
			if jcms.spawnmenu_Airstrike then
				jcms.spawnmenu_Airstrike {
					pos = pos, count = 1, arrival = cfg.arrival, radius = 0,
					blast_radius = cfg.blastRadius, blast_damage = cfg.blastDamage,
					callback = function(bomb) if IsValid(ply) then bomb.jcms_owner = ply end end,
				}
			end

			local attacker = IsValid(ply) and ply or game.GetWorld()

			-- Scattered, shuffled and with the delays jittered, so no two runs land the same and it
			-- never reads as a neat ring walked around in order.
			local points = scatterPoints(pos, cfg.bomblets, cfg.spread, cfg.scatterJitter, cfg.scatterInner or 0.04)
			for i, p in ipairs(points) do
				local delay = cfg.arrival + 0.15 + i * (cfg.stagger or 0.08) + math.Rand(0, cfg.timeJitter or 0)
				timer.Simple(delay, function()
					local at = p + Vector(0, 0, 24)
					local tr = util.TraceLine({ start = at, endpos = at - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
					if tr.Hit then at = tr.HitPos + Vector(0, 0, 8) end

					local ed = EffectData()
					ed:SetOrigin(at)
					util.Effect("Explosion", ed, true, true)
					util.BlastDamage(attacker, attacker, at, cfg.blastRadius, cfg.blastDamage)
				end)
			end
			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_cluster")
		end,
	}

	-- One EMP detonation. `index` is which pulse this is: everything after the first uses the
	-- follow-up multipliers, so a double tap needs no second copy of this code.
	local function empPulse(ply, pos, cfg, index)
		local follow = (index or 1) > 1
		local radius = cfg.radius * (follow and (cfg.pulseRadiusMul or 1) or 1)
		local damage = cfg.damage * (follow and (cfg.pulseDamageMul or 1) or 1)

		local attacker = IsValid(ply) and ply or game.GetWorld()

		-- The gamemode's own electric explosion: jcms_blast flag 5. An additive flash, a shockwave
		-- sphere expanding to the radius we pass, crackling discharge beams and a dynamic light in the
		-- colour we pass. Same effect the Orbital Beam throws on a hit, so the EMP reads as part of
		-- this game rather than something hand-drawn on top of it.
		--
		-- Stacked several deep, each one tighter than the last and a frame or two behind it, because
		-- one on its own is a pop rather than a detonation. Layering multiplies what makes it read:
		-- overlapping flashes, one dynamic light per layer, and several times the discharge.
		local layers = math.max(1, math.floor(tonumber(cfg.blastLayers) or 3))
		local col = jcms.util_ColorInteger(Color(120, 200, 255))
		for i = 1, layers do
			local frac = 1 - (i - 1) * 0.28 -- 1.00, 0.72, 0.44...
			timer.Simple((i - 1) * (cfg.blastLayerGap or 0.05), function()
				local ed = EffectData()
				ed:SetOrigin(pos)
				ed:SetRadius(radius * frac)
				ed:SetNormal(Vector(0, 0, 1))
				ed:SetFlags(5)
				ed:SetMagnitude(cfg.blastDuration or 1.35) -- multiplier on the effect's own ~1s
				ed:SetColor(col)
				util.Effect("jcms_blast", ed, true, true)
			end)
		end

		sound.Play("ambient/energy/zap9.wav", pos, 120, 75, 1)
		sound.Play("ambient/energy/whiteflash.wav", pos, 115, 120, 0.9)

		util.ScreenShake(pos, 28, 120, 1.1, radius * 2)

		for i, ent in ipairs(ents.FindInSphere(pos, radius)) do
			if not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and jcms.team_NPC(ent) then
				-- shields first: an EMP is the answer to Shielded Enemies
				if ent:GetNWInt("jcms_sweeperShield", 0) > 0 then
					ent:SetNWInt("jcms_sweeperShield", 0)
					local sed = EffectData()
					sed:SetFlags(1)
					sed:SetColor(ent:GetNWInt("jcms_sweeperShield_colour", 255))
					sed:SetEntity(ent)
					util.Effect("jcms_shieldeffect", sed, true, true)
				end
				if ent:GetNWInt("jcms_shield", 0) > 0 then ent:SetNWInt("jcms_shield", 0) end

				local dmg = DamageInfo()
				dmg:SetDamage(damage)
				dmg:SetDamageType(DMG_SHOCK)
				dmg:SetAttacker(attacker)
				dmg:SetInflictor(attacker)
				dmg:SetDamagePosition(ent:WorldSpaceCenter())
				ent:TakeDamageInfo(dmg)

				-- scrambled: they lose you and stumble along at half speed
				if ent:IsNPC() then
					ent.sweeperEmpUntil = CurTime() + cfg.scramble
					ent.sweeperEmpRate = ent.sweeperEmpRate or ent:GetPlaybackRate()
					ent:SetPlaybackRate((cfg.slowMul or 0.5) * (ent.sweeperEmpRate or 1))
					if ent.SetEnemy then ent:SetEnemy(NULL) end
					if ent.ClearEnemyMemory then ent:ClearEnemyMemory() end
				end

				local ted = EffectData()
				ted:SetEntity(ent)
				ted:SetMagnitude(3)
				ted:SetScale(1)
				util.Effect("TeslaHitBoxes", ted, true, true)
			end
		end
	end

	defs.skills_emp = {
		argparser = "orbital_fixed",
		func = function(ply, pos)
			local cfg = cfgOf("skills_emp")
			if jcms.net_SendLocator then jcms.net_SendLocator("all", nil, "#jcms.skills_emp", pos, jcms.LOCATOR_WARNING, cfg.arrival) end
			sound.Play("ambient/energy/whiteflash.wav", pos, 90, 90, 0.8)

			local pulses = math.max(1, math.floor(tonumber(cfg.pulses) or 1))
			local gap = math.max(0.05, tonumber(cfg.pulseGap) or 0.7)

			-- One message for the whole strike, sent NOW rather than at detonation, so the client can
			-- animate each warhead coming down out of the sky before it cracks.
			net.Start("sweeper_emp")
				net.WriteVector(pos)
				net.WriteUInt(math.Clamp(cfg.radius, 0, 2000), 11)
				net.WriteFloat(CurTime() + cfg.arrival)
				net.WriteUInt(pulses, 3)
				net.WriteFloat(gap)
				net.WriteFloat(cfg.pulseRadiusMul or 1)
			net.Broadcast()

			for i = 1, pulses do
				timer.Simple(cfg.arrival + gap * (i - 1), function()
					local ok, err = pcall(empPulse, ply, pos, cfg, i)
					if not ok then ErrorNoHalt("[EMP Burst] pulse " .. i .. ": " .. tostring(err) .. "\n") end
				end)
			end

			jcms.net_NotifyGeneric(ply, jcms.NOTIFY_ORDERED, "#jcms.skills_emp")
		end,
	}

	-- put scrambled enemies back to normal when it wears off
	timer.Create("sweeper_empRecover", 1, 0, function()
		local ct = CurTime()
		for i, ent in ipairs(ents.FindByClass("npc_*")) do
			local untilT = ent.sweeperEmpUntil
			if untilT and ct >= untilT then
				ent.sweeperEmpUntil = nil
				if IsValid(ent) then ent:SetPlaybackRate(ent.sweeperEmpRate or 1) end
				ent.sweeperEmpRate = nil
			end
		end
	end)

	-- Team Upgrades for these two (the applier table lives in sh_callins.lua)
	S.callinUpgradeIds = S.callinUpgradeIds or {}
	S.callinUpgradeIds.skills_cluster = "g_cluster"
	S.callinUpgradeIds.skills_emp = "g_emp"
	S.callinUpgradeApply = S.callinUpgradeApply or {}
	S.callinUpgradeApply.g_cluster = function(cfg, rank, U)
		cfg.bomblets = (cfg.bomblets or 12) + (U.clusterBombletsPerRank or 0) * rank
		cfg.blastRadius = math.floor((cfg.blastRadius or 130) * (1 + (U.clusterRadiusPerRank or 0) * rank))
	end
	S.callinUpgradeApply.g_emp = function(cfg, rank, U)
		cfg.radius = (cfg.radius or 500) + (U.empRadiusPerRank or 0) * rank
		cfg.damage = (cfg.damage or 200) + (U.empDamagePerRank or 0) * rank
		cfg.scramble = (cfg.scramble or 6) + (U.empScramblePerRank or 0) * rank
	end

	function S.InstallOffensiveCallins()
		if not (jcms and jcms.orders and jcms.orders_argparser) then return end
		for id, def in pairs(defs) do
			local c = S.callins[id]
			if c and not jcms.orders[id] then
				jcms.orders[id] = {
					category = jcms["SPAWNCAT_" .. c.category] or jcms.SPAWNCAT_UTILITY,
					cost = c.cost,
					cooldown = c.cooldown,
					slotPos = c.slotPos,
					argparser = def.argparser,
					func = def.func,
				}
			end
		end
	end
	hook.Add("Initialize", "sweeper_offensive", S.InstallOffensiveCallins)
	hook.Add("InitPostEntity", "sweeper_offensive", S.InstallOffensiveCallins)
	S.InstallOffensiveCallins()
end
-- }}}

-- // Client: fire / gas clouds and the EMP shock {{{
-- No ground rings on any of it. The cloud sprites and the EMP flash say where the effect is; the
-- Orbital Lance needs nothing here at all now that it spawns a real jcms_deathray for its column.
if CLIENT then
	local zones, emps = {}, {}
	local matFire = Material("sprites/fire_center")
	local matGlow = Material("sprites/light_glow02_add")
	-- Opaque, not additive: smoke has to darken what's behind it, not glow through it
	local matSmoke = Material("particle/particle_smokegrenade")
	local matBeam = Material("trails/laser")

	-- The EMP strike: a warhead falls out of the sky, cracks, and throws a dome out along the ground.
	local empDescentHeight = 2600  -- how high up the warhead starts
	local empDescentTime = 0.6     -- how long the fall is shown. Must be under the order's arrival (1.5s).
	local empTrailLength = 950     -- the streak dragged out behind the head
	local empHold = 1.1            -- how long the impact takes to play out and fade
	local empArcs = 14             -- ground arcs thrown out from the centre...
	local empArcSegments = 6       -- ...and how many kinks each one has
	local empArcWidth = 26         -- ...and how thick they draw

	-- Seeing out of a gas bank you're standing in. Two things thin it out, and only for gas:
	--   gasInsideFloor  how much of its opacity is left at the dead centre of a bank. Walking in
	--                   fades from full at the edge down to this, so there's a gradient, not a switch.
	--   puffClearIn /   per puff, as multiples of its own half-size on screen: nearer than clearIn it
	--   puffFadeOver    isn't drawn at all, and it reaches full opacity fadeOver beyond that. This is
	--                   what kills the one or two puffs whose sprite would otherwise envelop the camera.
	-- Together these give roughly alpha 50 at the centre of a bank, 123 half way out, 227 at the edge
	-- and the full 245 from outside - so it still looks solid to everyone not standing in it.
	local gasInsideFloor = 0.30
	local puffClearIn = 0.90
	local puffFadeOver = 1.30

	-- One reusable Color, because per-puff alpha would otherwise allocate a table per puff per frame
	local drawColor = Color(255, 255, 255, 255)
	local function drawCol(r, g, b, a)
		drawColor.r, drawColor.g, drawColor.b, drawColor.a = r, g, b, a
		return drawColor
	end

	net.Receive("sweeper_hazard", function()
		local kind = net.ReadString()
		local pos = net.ReadVector()
		local radius = net.ReadUInt(11)
		local untilT = net.ReadFloat()

		-- fixed puff positions, so the cloud doesn't crawl around. Gas and smoke are the same cloud -
		-- more puffs, stacked taller - because both have to read as a bank you can see is there.
		-- Fire stays the sparser, flatter set.
		local bank = kind == "smoke" or kind == "gas"
		local puffs = {}
		for i = 1, (bank and 22 or 14) do
			local ang = math.Rand(0, math.pi * 2)
			local d = math.Rand(0, radius * (bank and 0.95 or 0.85))
			puffs[i] = {
				off = Vector(math.cos(ang) * d, math.sin(ang) * d, math.Rand(0, radius * (bank and 0.55 or 0.25))),
				size = radius * math.Rand(bank and 0.5 or 0.35, bank and 0.9 or 0.7),
				phase = math.Rand(0, 10),
			}
		end
		zones[#zones + 1] = { kind = kind, pos = pos, radius = radius, untilT = untilT, puffs = puffs }
	end)

	-- // EMP strike: a warhead out of the sky, then the dome {{{
	-- Built once on receipt rather than per frame, so the arcs don't jitter and the ground traces
	-- (which let each arc follow the terrain instead of sinking into it) happen a single time.
	local function buildStrike(pos, radius, hitAt)
		local arcs = {}
		for i = 1, empArcs do
			local ang = (i / empArcs) * math.pi * 2 + math.Rand(-0.35, 0.35)
			local dir = Vector(math.cos(ang), math.sin(ang), 0)
			local side = dir:Angle():Right()
			local len = radius * math.Rand(0.55, 1.0)

			local pts = { pos + Vector(0, 0, 14) }
			for s = 1, empArcSegments do
				local p = pos + dir * (len * s / empArcSegments)
					+ side * math.Rand(-1, 1) * radius * 0.11
					+ Vector(0, 0, 14)
				local tr = util.TraceLine({
					start = p + Vector(0, 0, 80), endpos = p - Vector(0, 0, 250), mask = MASK_SOLID_BRUSHONLY
				})
				pts[#pts + 1] = tr.Hit and (tr.HitPos + Vector(0, 0, 10)) or p
			end
			arcs[i] = pts
		end
		return { pos = pos, radius = radius, hitAt = hitAt, arcs = arcs }
	end

	net.Receive("sweeper_emp", function()
		local pos = net.ReadVector()
		local radius = net.ReadUInt(11)
		local hitAt = net.ReadFloat()
		local pulses = math.max(1, net.ReadUInt(3))
		local gap = net.ReadFloat()
		local radMul = net.ReadFloat()

		-- Every pulse of the strike arrives in this one message, each with its own impact time, so a
		-- double tap shows two warheads coming down one after the other.
		for i = 1, pulses do
			emps[#emps + 1] = buildStrike(pos, radius * (i > 1 and radMul or 1), hitAt + gap * (i - 1))
		end
	end)

	hook.Add("PostDrawTranslucentRenderables", "sweeper_hazards", function(depth, skybox)
		if skybox then return end
		local ct = CurTime()
		local eye = EyePos()

		for i = #zones, 1, -1 do
			local z = zones[i]
			if ct >= z.untilT then
				table.remove(zones, i)
			else
				local fire = z.kind == "fire"
				local col, mat, churn, sway, seeThrough
				if fire then
					col, mat, churn, sway = drawCol(255, 140, 40, 150), matFire, 6, 0.15
				else
					-- Gas and smoke are the same cloud drawn the same way, and differ only in colour:
					-- gas is green and thicker, smoke is grey and thinner. Both fade over their last
					-- two seconds so a bank doesn't blink off all at once.
					local fade = math.Clamp((z.untilT - ct) / 2, 0, 1)
					if z.kind == "smoke" then
						col = drawCol(205, 205, 210, 200 * fade)
					else
						-- Gas thins out near the camera, so standing in a bank leaves you a clear
						-- bubble to fight in instead of a green wall. Smoke doesn't get this - not
						-- being able to see out of it is the whole point of cover.
						col, seeThrough = drawCol(95, 225, 80, 245 * fade), true
					end
					mat, churn, sway = matSmoke, 0.8, 0.06
				end

				local baseA = col.a
				if seeThrough and z.radius > 0 then
					-- Thinner the deeper into the bank you are; untouched from the edge outwards
					baseA = baseA * Lerp(math.Clamp(eye:Distance(z.pos) / z.radius, 0, 1), gasInsideFloor, 1)
				end

				render.SetMaterial(mat)
				for j, p in ipairs(z.puffs) do
					local wobble = math.sin(ct * churn + p.phase) * sway
					local size = p.size * (1 + wobble)
					local at = z.pos + p.off + Vector(0, 0, math.sin(ct + p.phase) * 4)

					local a = baseA
					if seeThrough then
						-- A sprite covers roughly its own half-size on screen, so fade each puff by how
						-- far the eye is from it RELATIVE to that: a big puff has to be further off
						-- before it draws solid. Below `puffClearIn` it isn't drawn at all.
						local half = size * 0.5
						a = a * math.Clamp((at:Distance(eye) - half * puffClearIn) / (half * puffFadeOver), 0, 1)
					end

					if a >= 3 then
						col.a = a
						render.DrawSprite(at, size, size, col)
					end
				end
				-- No need to restore col.a: drawCol overwrites all four channels for the next zone.
			end
		end

		for i = #emps, 1, -1 do
			local e = emps[i]
			local dt = ct - e.hitAt -- negative while the warhead is still on its way down

			if dt > empHold then
				table.remove(emps, i)

			elseif dt < 0 then
				-- // Falling: a bright head with a streak dragged out behind it
				local fall = math.Clamp(1 + dt / empDescentTime, 0, 1)
				if fall > 0 then
					local from = e.pos + Vector(0, 0, empDescentHeight)
					local at = LerpVector(fall * fall, from, e.pos) -- squared, so it accelerates in
					local tail = at + Vector(0, 0, empTrailLength * (0.35 + 0.65 * fall))

					render.SetMaterial(matBeam)
					render.DrawBeam(tail, at, 30, 0, 1, Color(150, 220, 255, 90 + 140 * fall))
					render.SetMaterial(matGlow)
					local s = 80 + 70 * fall
					render.DrawSprite(at, s, s, Color(200, 240, 255, 255))
				end

			else
				-- // Impact
				local f = dt / empHold

				-- One-shot, the first frame this pulse lands: wash the screen for anyone near enough
				-- to be inside it. Scaled by distance so someone across the map isn't blinded by it.
				if not e.washed then
					e.washed = true
					local d = eye:Distance(e.pos)
					local near = 1 - math.Clamp(d / (e.radius * 2.2), 0, 1)
					if near > 0.02 and jcms.colormod_Add then
						jcms.colormod_Add(Color(150, 220, 255), 0.9 * near, 0, 0.04, 0.05, 0.5)
					end
				end

				-- The column it came down blows out for an instant, then is gone
				if f < 0.22 then
					local cf = 1 - f / 0.22
					render.SetMaterial(matBeam)
					render.DrawBeam(e.pos + Vector(0, 0, empDescentHeight), e.pos,
						90 + 340 * (1 - cf), 0, 1, Color(225, 248, 255, 255 * cf))
				end

				-- No dome drawn here: the shockwave is jcms_blast flag 5, fired server side in empPulse
				-- so it carries a dynamic light too. What's left on the client is the two things that
				-- effect doesn't do - the column it came down, and arcs out to the real blast radius.

				-- Arcs crawling out along the ground, revealed a segment at a time
				if f < 0.62 then
					local af = 1 - f / 0.62
					local reach = math.min(1, f / 0.22) -- they whip out faster than they fade
					render.SetMaterial(matBeam)
					for j, pts in ipairs(e.arcs) do
						local show = math.max(2, math.floor(#pts * reach))
						for k = 2, math.min(show, #pts) do
							render.DrawBeam(pts[k - 1], pts[k], empArcWidth * af, 0, 1,
								Color(210, 245, 255, 255 * af))
						end
					end
				end
			end
		end

	end)
end
-- }}}
