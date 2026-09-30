--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Sentinel specialization mechanics.

	T1 Juggernaut  Immovable: no single hit can take more than 20% of your max health.
	T1 Brawler     Frenzy: melee kills stack +10% melee damage and +4% speed for 6s (5 stacks).
	T2 Bastion     Taunt: nearby enemies prefer to target you. It runs off a damage pool like the
	               Bullet Barrier it replaces - damage you take while taunting drains the pool, and
	               when it's spent the taunt drops and has to recharge.
	T2 Enforcer    Riot Control: your melee hits knock enemies off their feet, and every enemy Charge
	               hits takes 1.5s off its cooldown (up to 6s per charge).
	               Ability (Charge): dash forward; enemies you hit take damage and get knocked back.
	               Works in the air too, holding its height, so it combos off a jump. 12s cooldown.
	T3 Aegis       Kinetic Reclaim: 25% of the damage your Bullet Barrier or Dome absorbs comes back to
	               you as shield. Longer barrier + Ability (Aegis Dome): a shield bubble that moves with you for 10s. Enemy fire from
	               outside is absorbed (800 HP) before it reaches players or deployables inside, but everyone
	               inside can still shoot out. 40s cooldown.
	T3 Ravager     Melee hits heal you for 30% of the damage. Dropping below 35% HP triggers Rage:
	               +30% damage and +20% speed for 8s (45s cooldown).

	Tuning values are in S.sentinel below.
--]]

local S = sweeper

S.sentinel = {
	tauntRadius = 700,
	tauntInterval = 1,
	tauntPool = 600,            -- damage the taunt soaks before it collapses (the Bullet Barrier it replaces)
	tauntRegen = 40,            -- pool refilled per second while the taunt is switched off
	tauntCooldown = 12,         -- lockout after the pool is drained to nothing; the pool comes back full

	chargeCooldown = 12,
	chargeDuration = 0.5,
	chargeSpeed = 900,
	chargeAllowAir = true,        -- Charge can be used mid-air, so it combos off a jump
	chargeAirFlat = true,         -- ...and holds you level while airborne instead of sinking
	chargeHitRadius = 70,
	chargeDamage = 40,
	chargeKnockback = 450,

	juggerHitCap = 0.20,        -- Juggernaut: Immovable - biggest fraction of max HP one hit can take
	immovableVsPlayers = false, -- true = Immovable also caps hits from other players (see the hook)

	frenzyMaxStacks = 5,        -- Brawler: Frenzy
	frenzyPerStack = 0.10,      -- melee damage per stack
	frenzySpeedPerStack = 0.04,
	frenzyDuration = 6,         -- from your last melee kill

	riotKnockback = 260,        -- Enforcer: Riot Control - melee knocks enemies off their feet
	riotChargeRefund = 1.5,     -- seconds off Charge per enemy it hits
	riotRefundMax = 6,          -- ...and at most this much per charge

	reclaimFrac = 0.25,         -- Aegis: Kinetic Reclaim - absorbed damage returned as shield

	domeDuration = 10,
	domeCooldown = 40,
	domeRadius = 200,          -- ~3.8 metres
	domeHealth = 800,          -- damage it can absorb before breaking

	ravagerLifesteal = 0.30,
	rageThreshold = 0.35,       -- fraction of max HP
	rageDuration = 8,
	rageCooldown = 45,
	rageDamageMul = 1.30,
	rageSpeedMul = 1.20,

	-- Abilities
	ironSkinCooldown = 35,      -- Juggernaut: Iron Skin
	ironSkinDuration = 6,
	ironSkinDamageTaken = 0.30, -- -70%
	ironSkinSpeedMul = 0.70,    -- -30%

	poundCooldown = 20,         -- Brawler: Ground Pound
	poundDamage = 80,
	poundRadius = 260,
	poundKnockback = 500,
	poundJump = 420,
	poundSlam = 1400,

	challengeCooldown = 40,     -- Bastion: Challenge
	challengeDuration = 6,
	challengeRadius = 1050,     -- ~20 metres
	challengeDamageTaken = 0.5,

	bloodlustCooldown = 40,     -- Ravager: Bloodlust
	bloodlustPerKill = 5,       -- seconds added per melee kill
	bloodlustMax = 30,          -- Rage can't go above this many seconds left
}

local T = S.sentinel

local meleeHoldTypes = { melee = true, melee2 = true, knife = true, fist = true }
local function isMelee(ply, dmg)
	if bit.band(dmg:GetDamageType(), bit.bor(DMG_CLUB, DMG_SLASH)) ~= 0 then return true end
	local wep = ply:GetActiveWeapon()
	return IsValid(wep) and meleeHoldTypes[wep:GetHoldType()] == true
end

-- // Enforcer: Charge ability {{{
S.abilities.enforcer = { name = "Charge", cooldown = T.chargeCooldown }

if SERVER then
	S.abilities.enforcer.activate = function(ply)
		if not T.chargeAllowAir and not ply:OnGround() then
			return false, "You need to be on the ground to charge."
		end
		local dir = ply:GetAimVector()
		dir.z = 0
		dir:Normalize()

		ply:SetNWVector("sweeper_chargeDir", dir)
		ply:SetNWFloat("sweeper_chargeUntil", CurTime() + S.Tune(ply, "chargeDuration", T.chargeDuration))
		ply.sweeperChargeHit = {}
		ply.sweeperChargeRefund = 0
		ply:EmitSound("npc/combine_soldier/gear6.wav", 80, 80)
		ply:EmitSound("physics/body/body_medium_impact_hard6.wav", 75, 70)
		util.ScreenShake(ply:GetPos(), 4, 20, 0.5, 300)
		return true
	end

	hook.Add("Think", "sweeper_enforcerCharge", function()
		local ct = CurTime()
		for i, ply in ipairs(player.GetAll()) do
			if ply:GetNWFloat("sweeper_chargeUntil", 0) > ct and ply:Alive() then
				local dir = ply:GetNWVector("sweeper_chargeDir")
				local center = ply:WorldSpaceCenter() + dir * 40
				ply.sweeperChargeHit = ply.sweeperChargeHit or {}

				for j, ent in ipairs(ents.FindInSphere(center, T.chargeHitRadius)) do
					if ent ~= ply and not ply.sweeperChargeHit[ent] and (ent:IsNPC() or ent:IsNextBot())
						and ent:Health() > 0 and not jcms.team_SameTeam(ply, ent) then
						ply.sweeperChargeHit[ent] = true

						local dmg = DamageInfo()
						dmg:SetAttacker(ply)
						dmg:SetInflictor(ply)
						dmg:SetDamage(S.Tune(ply, "chargeDamage", T.chargeDamage))
						dmg:SetDamageType(DMG_CLUB)
						dmg:SetDamagePosition(ent:WorldSpaceCenter())
						dmg:SetDamageForce(dir * 20000 + Vector(0, 0, 8000))
						ent:TakeDamageInfo(dmg)

						if IsValid(ent) and ent:Health() > 0 then
							ent:SetGroundEntity(NULL)
							ent:SetVelocity(dir * T.chargeKnockback + Vector(0, 0, 220))
						end

						ent:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 80, 90)
						util.ScreenShake(ent:GetPos(), 6, 30, 0.4, 250)

						-- Riot Control: each enemy caught by the charge pays some of it back, capped
						-- per charge so a big crowd can't hand the whole cooldown straight back.
						local budget = S.Tune(ply, "riotRefundMax", T.riotRefundMax) - (ply.sweeperChargeRefund or 0)
						if budget > 0 and S.CutCooldown then
							local want = math.min(S.Tune(ply, "riotChargeRefund", T.riotChargeRefund), budget)
							ply.sweeperChargeRefund = (ply.sweeperChargeRefund or 0) + S.CutCooldown(ply, "enforcer", want)
						end
					end
				end
			end
		end
	end)
end

-- Movement during the charge (shared so it's predicted smoothly)
hook.Add("SetupMove", "sweeper_enforcerChargeMove", function(ply, mv, cmd)
	if ply:GetNWFloat("sweeper_chargeUntil", 0) > CurTime() then
		local dir = ply:GetNWVector("sweeper_chargeDir")
		local vel = dir * T.chargeSpeed

		if T.chargeAirFlat and not ply:OnGround() then
			-- An air charge holds its height: a dash you can aim, not a dive. Gravity picks up
			-- again the moment the charge ends. Rising (from a jump) is left alone so a
			-- jump-into-charge keeps its arc.
			vel.z = math.max(0, mv:GetVelocity().z)
		else
			vel.z = mv:GetVelocity().z
		end

		mv:SetVelocity(vel)
	end
end)
-- }}}

-- // Passives: Immovable (Juggernaut), Frenzy (Brawler), Riot Control (Enforcer), Kinetic Reclaim (Aegis) {{{
-- Frenzy stacks are read on both sides for the HUD, the same shape as Gunslinger's Quickdraw.
function S.FrenzyStacks(ply)
	if ply:GetNWFloat("sweeper_frenzyExpire", 0) < CurTime() then return 0 end
	return ply:GetNWInt("sweeper_frenzyStacks", 0)
end

if SERVER then
	-- Juggernaut: no single hit can take more than a set slice of your max health. Applied in its own
	-- hook, so a scaling added by another hook after this one isn't covered - in practice every
	-- scaling in the addon lands in this same pass.
	hook.Add("EntityTakeDamage", "sweeper_juggernautCap", function(ent, dmg)
		if not (ent:IsPlayer() and S.PlayerHasSpec(ent, "juggernaut")) then return end

		-- Not against other players. A flat ceiling per hit is a fine answer to a boss that hits for 400,
		-- but in PVP it makes damage upgrades worthless: past the cap every weapon and every point of
		-- +damage lands for exactly the same amount, so a maxed assassin needs as many shots as a fresh
		-- one. The PVP stat scaling in sh_tree.lua handles Juggernaut's bulk instead.
		if T.immovableVsPlayers == false and jcms and jcms.util_IsPVP and jcms.util_IsPVP() then
			local src = dmg:GetAttacker()
			if IsValid(src) and src:IsPlayer() and src ~= ent then return end
		end

		local cap = math.max(1, ent:GetMaxHealth() * S.Tune(ent, "juggerHitCap", T.juggerHitCap))
		if dmg:GetDamage() > cap then dmg:SetDamage(cap) end
	end)

	-- Brawler: melee kills stack Frenzy. Enforcer: melee hits throw enemies.
	hook.Add("MapSweepersDeathNPC", "sweeper_brawlerFrenzy", function(npc, attacker)
		if not (IsValid(attacker) and attacker:IsPlayer() and S.PlayerHasSpec(attacker, "brawler")) then return end
		-- Only melee kills stack. A timestamp rather than a flag, so a melee hit that didn't kill
		-- can't make the next gun kill count as melee.
		if CurTime() - (attacker.sweeperFrenzyMeleeAt or -1) > 0.2 then return end
		attacker.sweeperFrenzyMeleeAt = nil

		local stacks = math.min(S.FrenzyStacks(attacker) + 1, S.Tune(attacker, "frenzyMaxStacks", T.frenzyMaxStacks))
		attacker:SetNWInt("sweeper_frenzyStacks", stacks)
		attacker:SetNWFloat("sweeper_frenzyExpire", CurTime() + S.Tune(attacker, "frenzyDuration", T.frenzyDuration))
		attacker:EmitSound("npc/vort/vort_foot_hit" .. math.random(1, 3) .. ".wav", 70, 120, 0.5)
	end)

	hook.Add("EntityTakeDamage", "sweeper_sentinelMeleePassives", function(ent, dmg)
		local attacker = dmg:GetAttacker()
		if not (IsValid(attacker) and attacker:IsPlayer() and ent ~= attacker and not ent:IsPlayer()) then return end
		if not isMelee(attacker, dmg) then return end

		-- Frenzy's own bonus, and a note for the kill hook above that this hit was melee
		if S.PlayerHasSpec(attacker, "brawler") then
			attacker.sweeperFrenzyMeleeAt = CurTime()
			local stacks = S.FrenzyStacks(attacker)
			if stacks > 0 then dmg:ScaleDamage(1 + stacks * S.Tune(attacker, "frenzyPerStack", T.frenzyPerStack)) end
		end

		-- Riot Control: send them flying. Done here rather than through DamageForce so it lands on
		-- NPCs that ignore force, and only on things that survive the hit.
		if S.PlayerHasSpec(attacker, "enforcer") and (ent:IsNPC() or ent:IsNextBot()) then
			local kb = S.Tune(attacker, "riotKnockback", T.riotKnockback)
			timer.Simple(0, function()
				if not (IsValid(ent) and ent:Health() > 0 and IsValid(attacker)) then return end
				local dir = ent:WorldSpaceCenter() - attacker:WorldSpaceCenter()
				dir.z = 0
				if dir:LengthSqr() < 1 then dir = attacker:GetAimVector() end
				dir:Normalize()
				ent:SetGroundEntity(NULL)
				ent:SetVelocity(dir * kb + Vector(0, 0, 140))
			end)
		end
	end)

	-- Aegis: damage the gamemode's Bullet Barrier soaks comes partly back as shield. The Dome does the
	-- same where it absorbs (see the dome hook below) - the Dome is Aegis's own ability, so no check there.
	hook.Add("EntityTakeDamage", "sweeper_aegisReclaim", function(ent, dmg)
		if ent:GetClass() ~= "jcms_sentinelbarrier" or not ent.GetSentinel then return end
		local owner = ent:GetSentinel()
		if not (IsValid(owner) and owner:IsPlayer() and S.PlayerHasSpec(owner, "aegis")) then return end
		S.GrantKillShield(owner, math.ceil(dmg:GetDamage() * S.Tune(owner, "reclaimFrac", T.reclaimFrac)))
	end)

	hook.Add("MapSweepersClassApplied", "sweeper_frenzyReset", function(ply)
		ply:SetNWInt("sweeper_frenzyStacks", 0)
		ply:SetNWFloat("sweeper_frenzyExpire", 0)
		ply.sweeperFrenzyMeleeAt = nil
	end)
end

-- Frenzy speed (shared so movement stays predicted)
hook.Add("SetupMove", "sweeper_brawlerFrenzyMove", function(ply, mv, cmd)
	local stacks = S.FrenzyStacks(ply)
	if stacks <= 0 then return end
	local mul = 1 + stacks * S.Tune(ply, "frenzySpeedPerStack", T.frenzySpeedPerStack)
	mv:SetMaxSpeed(mv:GetMaxSpeed() * mul)
	mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * mul)
end)
-- }}}

-- // Aegis: mobile dome shield {{{
S.abilities.aegis = { name = "Aegis Dome", cooldown = T.domeCooldown }

-- Damage types the dome can't stop (they don't come "from outside")
local DOME_IGNORE = bit.bor(DMG_FALL, DMG_DROWN, DMG_RADIATION, DMG_NERVEGAS, DMG_SLOWBURN, DMG_POISON, DMG_PARALYZE, DMG_DROWNRECOVER)

function S.GetActiveDomes()
	local list = {}
	local ct = CurTime()
	for i, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ply:GetNWFloat("sweeper_domeUntil", 0) > ct and ply:GetNWInt("sweeper_domeHP", 0) > 0 then
			list[#list + 1] = ply
		end
	end
	return list
end

if SERVER then
	local function endDome(ply, broken)
		ply:SetNWFloat("sweeper_domeUntil", 0)
		ply:SetNWInt("sweeper_domeHP", 0)
		local ed = EffectData()
		ed:SetOrigin(ply:WorldSpaceCenter())
		ed:SetMagnitude(2)
		ed:SetScale(2)
		ed:SetRadius(T.domeRadius)
		util.Effect(broken and "cball_explode" or "cball_bounce", ed, true, true)
		ply:EmitSound(broken and "ambient/energy/zap9.wav" or "ambient/machines/thumper_shutdown1.wav", 80, broken and 90 or 140, 0.7)
	end

	S.abilities.aegis.activate = function(ply)
		ply:SetNWFloat("sweeper_domeUntil", CurTime() + S.Tune(ply, "domeDuration", T.domeDuration))
		ply:SetNWInt("sweeper_domeHP", S.Tune(ply, "domeHealth", T.domeHealth))
		ply:EmitSound("ambient/machines/thumper_startup1.wav", 80, 140, 0.8)
		timer.Create("sweeper_dome" .. ply:EntIndex(), S.Tune(ply, "domeDuration", T.domeDuration), 1, function()
			if IsValid(ply) and ply:GetNWInt("sweeper_domeHP", 0) > 0 then endDome(ply, false) end
		end)
		return true
	end

	local function isProtected(ent, owner)
		if ent:IsPlayer() then
			return ent:Alive() and (ent == owner or jcms.team_SameTeam(owner, ent))
		end
		local entOwner = ent.jcms_owner or ent.sweeperOwner
		return IsValid(entOwner) and entOwner:IsPlayer() and (entOwner == owner or jcms.team_SameTeam(owner, entOwner))
	end

	hook.Add("EntityTakeDamage", "sweeper_aegisDome", function(ent, dmg)
		if bit.band(dmg:GetDamageType(), DOME_IGNORE) ~= 0 then return end
		local attacker = dmg:GetAttacker()
		if not IsValid(attacker) or attacker == ent then return end

		for i, owner in ipairs(S.GetActiveDomes()) do
			if isProtected(ent, owner) and not jcms.team_SameTeam(owner, attacker) then
				local center = owner:WorldSpaceCenter()
				local r2 = T.domeRadius ^ 2
				local attackerPos = attacker:WorldSpaceCenter()
				if ent:WorldSpaceCenter():DistToSqr(center) <= r2 and attackerPos:DistToSqr(center) > r2 then
					-- Absorb it
					local hp = owner:GetNWInt("sweeper_domeHP", 0) - math.ceil(dmg:GetDamage())
					owner:SetNWInt("sweeper_domeHP", math.max(hp, 0))

					-- Kinetic Reclaim: part of what the bubble eats comes back as the owner's shield
					S.GrantKillShield(owner, math.ceil(dmg:GetDamage() * S.Tune(owner, "reclaimFrac", T.reclaimFrac)))

					-- Impact flash where the shot hit the bubble (rate-limited)
					if (owner.sweeperNextDomeFx or 0) < CurTime() then
						owner.sweeperNextDomeFx = CurTime() + 0.08
						local dir = (attackerPos - center):GetNormalized()
						local ed = EffectData()
						ed:SetOrigin(center + dir * T.domeRadius)
						ed:SetNormal(dir)
						util.Effect("AR2Impact", ed, true, true)
						sound.Play("ambient/energy/spark" .. math.random(1, 6) .. ".wav", center + dir * T.domeRadius, 65, 130, 0.5)
					end

					if hp <= 0 then
						timer.Remove("sweeper_dome" .. owner:EntIndex())
						endDome(owner, true)
					end
					return true -- block the damage completely
				end
			end
		end
	end)

	hook.Add("PlayerDeath", "sweeper_domeDeath", function(ply)
		if ply:GetNWFloat("sweeper_domeUntil", 0) > CurTime() then
			timer.Remove("sweeper_dome" .. ply:EntIndex())
			ply:SetNWFloat("sweeper_domeUntil", 0)
			ply:SetNWInt("sweeper_domeHP", 0)
		end
	end)
end

if CLIENT then
	hook.Add("PostDrawTranslucentRenderables", "sweeper_aegisDome", function(depth, skybox)
		if skybox or depth then return end
		for i, owner in ipairs(S.GetActiveDomes()) do
			local center = owner:WorldSpaceCenter()
			local frac = math.Clamp(owner:GetNWInt("sweeper_domeHP", 0) / T.domeHealth, 0, 1)
			local pulse = 0.85 + math.sin(CurTime() * 4) * 0.15

			render.SetColorMaterial()
			render.DrawSphere(center, T.domeRadius, 30, 30, Color(70, 160, 255, (25 + 35 * frac) * pulse))
			render.DrawSphere(center, -T.domeRadius, 30, 30, Color(70, 160, 255, (15 + 20 * frac) * pulse)) -- seen from inside
			render.DrawWireframeSphere(center, T.domeRadius, 16, 16, Color(120, 200, 255, 60 + 120 * frac), true)
		end
	end)

	-- Dome HP/time is shown as a HUD icon (cl_hudicons.lua)
end
-- }}}

if SERVER then
	-- // Bastion: taunt {{{
	-- The taunt runs off a damage pool, the same shape as the Bullet Barrier Bastion gives up: damage
	-- taken while taunting drains it, and at zero the taunt drops and locks out for tauntCooldown,
	-- after which the pool comes back full. Switching it off by hand instead refills it at tauntRegen/s.
	local function tauntMax(ply) return math.max(1, S.Tune(ply, "tauntPool", T.tauntPool)) end

	local function tauntSync(ply)
		ply:SetNWFloat("sweeper_tauntCharge", ply.sweeperTauntCharge or 0)
		ply:SetNWFloat("sweeper_tauntChargeMax", tauntMax(ply))
	end

	function S.TauntResetCharge(ply)
		ply.sweeperTauntCharge = tauntMax(ply)
		ply.sweeperTauntLocked = nil
		ply:SetNWFloat("sweeper_tauntReady", 0)
		tauntSync(ply)
	end

	function S.TauntLockedOut(ply)
		return ply:GetNWFloat("sweeper_tauntReady", 0) > CurTime()
	end

	local function breakTaunt(ply)
		ply.sweeperTauntCharge = 0
		ply.sweeperTauntLocked = true
		ply:SetNWBool("sweeper_tauntOn", false)
		ply:SetNWFloat("sweeper_tauntReady", CurTime() + S.Tune(ply, "tauntCooldown", T.tauntCooldown))
		tauntSync(ply)
		ply:EmitSound("physics/metal/metal_solid_impact_hard5.wav", 80, 70)
		ply:PrintMessage(HUD_PRINTCENTER, "TAUNT BROKEN")
	end

	-- Taunt switches OFF when you deselect Bastion or change class (it's toggled back on with the walk key)
	local function checkTauntOff(ply)
		local has = S.PlayerHasSpec(ply, "bastion")
		local class = ply:GetNWString("jcms_class", "")
		if ply.sweeperWasBastion and (not has or class ~= ply.sweeperBastionClass) then
			ply:SetNWBool("sweeper_tauntOn", false)
			S.TauntResetCharge(ply)
		end
		ply.sweeperWasBastion = has
		ply.sweeperBastionClass = class
	end
	S.CheckBastionTauntOff = checkTauntOff

	-- Damage taken while the taunt is up drains the pool
	hook.Add("PostEntityTakeDamage", "sweeper_bastionTauntDrain", function(ent, dmg, took)
		if not took or not (IsValid(ent) and ent:IsPlayer()) then return end
		if not ent:GetNWBool("sweeper_tauntOn", false) then return end
		if not S.PlayerHasSpec(ent, "bastion") then return end

		local max = tauntMax(ent)
		local charge = math.Clamp((ent.sweeperTauntCharge or max) - math.max(0, dmg:GetDamage()), 0, max)
		ent.sweeperTauntCharge = charge
		tauntSync(ent)
		if charge <= 0 then breakTaunt(ent) end
	end)

	local function tauntTick()
		for i, ply in ipairs(player.GetAll()) do
			checkTauntOff(ply)

			local max = tauntMax(ply)
			if ply.sweeperTauntCharge == nil then ply.sweeperTauntCharge = max end
			-- Lockout just ended: the pool comes back full, like the barrier coming off cooldown
			if ply.sweeperTauntLocked and not S.TauntLockedOut(ply) then
				S.TauntResetCharge(ply)
			end

			local isBastion = ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE and S.PlayerHasSpec(ply, "bastion")
				and ply:GetNWBool("sweeper_tauntOn", false) and not S.TauntLockedOut(ply)

			if not isBastion and not S.TauntLockedOut(ply) then
				local charge = math.min(max, (ply.sweeperTauntCharge or max) + S.Tune(ply, "tauntRegen", T.tauntRegen) * T.tauntInterval)
				ply.sweeperTauntCharge = charge
			end
			tauntSync(ply)

			local taunted = ply.sweeperTaunted or {}
			local nowTaunted = {}

			if isBastion then
				for j, npc in ipairs(ents.FindInSphere(ply:GetPos(), T.tauntRadius)) do
					if npc:IsNPC() and npc:Health() > 0 and jcms.team_NPC(npc) and npc.AddEntityRelationship then
						npc:AddEntityRelationship(ply, D_HT, 99)
						nowTaunted[npc] = true
						local enemy = npc.GetEnemy and npc:GetEnemy()
						if enemy ~= ply and npc:Visible(ply) then
							npc:SetEnemy(ply)
							npc:UpdateEnemyMemory(ply, ply:GetPos())
						end
					end
				end
			end

			-- NPCs that left the radius go back to normal priority
			for npc in pairs(taunted) do
				if not nowTaunted[npc] and IsValid(npc) and npc.AddEntityRelationship then
					npc:AddEntityRelationship(ply, D_HT, 0)
				end
			end
			ply.sweeperTaunted = nowTaunted
			ply:SetNWBool("sweeper_taunting", isBastion)
		end
	end
	timer.Create("sweeper_bastionTaunt", T.tauntInterval, 0, tauntTick)

	-- Respawning gives the pool back, so a death never leaves you locked out
	hook.Add("PlayerSpawn", "sweeper_bastionTauntSpawn", function(ply)
		timer.Simple(0, function() if IsValid(ply) then S.TauntResetCharge(ply) end end)
	end)
	-- }}}

	-- // Ravager: lifesteal + rage {{{
	hook.Add("EntityTakeDamage", "sweeper_ravager", function(ent, dmg)
		local attacker = dmg:GetAttacker()

		-- Rage damage bonus + melee lifesteal (as attacker)
		if IsValid(attacker) and attacker:IsPlayer() and ent ~= attacker and not ent:IsPlayer() then
			if attacker:GetNWFloat("sweeper_rageUntil", 0) > CurTime() then
				dmg:ScaleDamage(T.rageDamageMul)
			end
			if S.PlayerHasSpec(attacker, "ravager") and isMelee(attacker, dmg) and ent:Health() > 0 then
				local heal = math.floor(math.min(dmg:GetDamage(), ent:Health()) * T.ravagerLifesteal)
				if heal > 0 then
					S.GrantKillHealth(attacker, heal)
				end
			end
		end
	end)

	-- Rage trigger: checked after damage has been applied
	hook.Add("PostEntityTakeDamage", "sweeper_ravagerRage", function(ent, dmg, took)
		if not (IsValid(ent) and ent:IsPlayer() and ent:Alive()) then return end
		if ent:Health() > ent:GetMaxHealth() * T.rageThreshold then return end
		if CurTime() < (ent.sweeperRageReadyAt or 0) then return end
		if not S.PlayerHasSpec(ent, "ravager") then return end

		ent.sweeperRageReadyAt = CurTime() + T.rageCooldown
		ent:SetNWFloat("sweeper_rageReady", ent.sweeperRageReadyAt)
		ent:SetNWFloat("sweeper_rageUntil", CurTime() + T.rageDuration)
		ent:EmitSound("npc/antlion_guard/angry" .. math.random(1, 3) .. ".wav", 85, 110)
		util.ScreenShake(ent:GetPos(), 8, 40, 0.6, 200)
	end)

	hook.Add("MapSweepersClassApplied", "sweeper_sentinelReset", function(ply)
		ply:SetNWFloat("sweeper_rageUntil", 0)
		ply:SetNWFloat("sweeper_chargeUntil", 0)
		ply.sweeperRageReadyAt = 0
		ply:SetNWFloat("sweeper_rageReady", 0)
	end)
	-- }}}
end

-- Rage speed (shared)
hook.Add("SetupMove", "sweeper_ravagerRageMove", function(ply, mv, cmd)
	if ply:GetNWFloat("sweeper_rageUntil", 0) > CurTime() then
		mv:SetMaxSpeed(mv:GetMaxSpeed() * T.rageSpeedMul)
		mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * T.rageSpeedMul)
	end
end)

-- // Client visuals {{{
if CLIENT then
	S.AddHud("rageTint", "tint", function(ply)
		local rageLeft = ply:GetNWFloat("sweeper_rageUntil", 0) - CurTime()
		if rageLeft > 0 then
			S.HudTint(jcms.color_bright, 20 + math.sin(CurTime() * 8) * 10)
		end
	end)

	-- Bastion's taunt range as an orange ring on the ground
	hook.Add("PostDrawTranslucentRenderables", "sweeper_tauntRing", function(depth, skybox)
		if skybox then return end
		local me = LocalPlayer()
		for i, ply in ipairs(player.GetAll()) do
			if ply:Alive() and ply:GetNWBool("sweeper_taunting", false)
				and ply:GetPos():DistToSqr(me:GetPos()) < 2500 ^ 2 then
				-- The ring fades as the pool drains, so you can read it without looking at the HUD
				local max = ply:GetNWFloat("sweeper_tauntChargeMax", 0)
				local frac = max > 0 and math.Clamp(ply:GetNWFloat("sweeper_tauntCharge", 0) / max, 0, 1) or 1
				cam.Start3D2D(ply:GetPos() + Vector(0, 0, 4), Angle(0, 0, 0), 1)
					surface.DrawCircle(0, 0, T.tauntRadius, 255, 150, 40, 12 + 28 * frac)
				cam.End3D2D()
			end
		end
	end)
end
-- }}}

-- // New Sentinel abilities + Bastion taunt toggle {{{
S.abilities.juggernaut = { name = "Iron Skin",    cooldown = T.ironSkinCooldown }
S.abilities.brawler    = { name = "Ground Pound", cooldown = T.poundCooldown }
S.abilities.bastion    = { name = "Challenge",    cooldown = T.challengeCooldown }
S.abilities.ravager    = { name = "Bloodlust",    cooldown = T.bloodlustCooldown }

local function active(ply, nw) return IsValid(ply) and ply:IsPlayer() and ply:GetNWFloat(nw, 0) > CurTime() end

-- Iron Skin slows you down (shared so movement is predicted)
hook.Add("SetupMove", "sweeper_ironSkinMove", function(ply, mv, cmd)
	if active(ply, "sweeper_ironSkinUntil") then
		mv:SetMaxSpeed(mv:GetMaxSpeed() * S.Tune(ply, "ironSkinSpeedMul", T.ironSkinSpeedMul))
		mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * S.Tune(ply, "ironSkinSpeedMul", T.ironSkinSpeedMul))
	end
end)

-- Bastion: the walk key toggles Taunt instead of raising the barrier
function S.InstallBastionBarrier()
	local sen = jcms and jcms.classes and jcms.classes.sentinel
	if not (sen and sen.PerformBarrierLogic) or S.Wrapped(sen, "BastionBarrier") then return end
	local orig = sen.PerformBarrierLogic
	S._wrappedBastionBarrier = function(ply, isActive, ...)
		if S.PlayerHasSpec(ply, "bastion") then
			return orig(ply, false, ...)
		end
		return orig(ply, isActive, ...)
	end
	sen.PerformBarrierLogic = S._wrappedBastionBarrier
	S.MarkWrapped(sen, "BastionBarrier")
end
hook.Add("InitPostEntity", "sweeper_bastionBarrier", S.InstallBastionBarrier)
S.InstallBastionBarrier()

-- Bastion has no barrier, so the gamemode's Bullet Barrier bar is replaced (not hidden) by the same
-- bar reading the taunt pool: same geometry, same colours, same [ALT] prompt, so it reads identically.
-- Drawn inside the gamemode's own jcms.setup3d2dCentral("bottom") cam, since that's where it's called.
-- Checked every frame, so the real barrier bar comes back as soon as Bastion is swapped out.
if CLIENT then
	local function drawTauntBar(ply)
		local w, h = 500, 24
		local x, y = -w / 2, -200 - h
		local off = 6

		local ct = CurTime()
		local on = ply:GetNWBool("sweeper_tauntOn", false)
		local max = math.max(1, ply:GetNWFloat("sweeper_tauntChargeMax", 0))
		local charge = math.Clamp(ply:GetNWFloat("sweeper_tauntCharge", 0), 0, max)
		local readyAt = ply:GetNWFloat("sweeper_tauntReady", 0)
		local locked = readyAt > ct

		-- Active: drains left to right. Locked out: fills back up, dimmed, exactly like the barrier's
		-- cooldown. Off but charged: a full bar with the keybind under it.
		local frac
		if locked then
			local cd = math.max(0.01, S.Tune(ply, "tauntCooldown", T.tauntCooldown))
			frac = 1 - math.Clamp((readyAt - ct) / cd, 0, 1)
		else
			frac = charge / max
		end

		local lowPool = on and charge <= max * 0.25
		local colorDark = on and jcms.color_dark or jcms.color_dark_alt
		-- jcms.color_alert isn't theme-swapped (it's black in one branch), so the low-pool flash uses alert1
		local colorBright = on and (lowPool and (jcms.color_alert1 or jcms.color_bright) or jcms.color_bright) or jcms.color_bright_alt

		local str1 = ("[%s]"):format(tostring(input.LookupBinding("+walk") or "???"):upper())
		local str2 = "TAUNT"
		local str3 = ("%d DAMAGE LEFT"):format(math.ceil(charge))

		if locked then surface.SetAlphaMultiplier(0.3) end

		surface.SetDrawColor(colorDark)
		if on then
			draw.SimpleText(str3, "jcms_hud_medium", x + w / 2, y - 18, colorDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		else
			if not locked then
				draw.SimpleText(str1, "jcms_hud_medium", x + w / 2, y + h + 12, colorDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			end
			draw.SimpleText(str2, "jcms_hud_medium", x + w / 2, y - 12, colorDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
		surface.DrawRect(x, y, w, h)

		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
			surface.SetDrawColor(colorBright)
			surface.DrawRect(x, y - off, w * frac, h)
			if on then
				draw.SimpleText(str3, "jcms_hud_medium", x + w / 2, y - 18 - off, colorBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			elseif frac > 0 then
				if not locked then
					draw.SimpleText(str1, "jcms_hud_medium", x + w / 2, y + h + 12 - off, colorBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end
				draw.SimpleText(str2, "jcms_hud_medium", x + w / 2, y - 12 - off, colorBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			end
		render.OverrideBlend(false)

		if locked then surface.SetAlphaMultiplier(1) end
	end
	S.DrawTauntBar = drawTauntBar

	function S.InstallBastionBarrierHud()
		if not (jcms and jcms.draw_SentinelBarrier) or S.Wrapped(jcms, "BarrierHud") then return end
		local orig = jcms.draw_SentinelBarrier
		S._wrappedBarrierHud = function(...)
			local ply = jcms.locPly or LocalPlayer()
			if IsValid(ply) and S.PlayerHasSpec(ply, "bastion") then
				local ok, err = pcall(drawTauntBar, ply)
				if not ok then ErrorNoHalt("[sweeper] taunt bar: " .. tostring(err) .. "\n") end
				return
			end
			return orig(...)
		end
		jcms.draw_SentinelBarrier = S._wrappedBarrierHud
		S.MarkWrapped(jcms, "BarrierHud")
	end
	hook.Add("Initialize", "sweeper_bastionBarrierHud", S.InstallBastionBarrierHud)
	hook.Add("InitPostEntity", "sweeper_bastionBarrierHud", S.InstallBastionBarrierHud)
	S.InstallBastionBarrierHud()
end

if SERVER then
	hook.Add("KeyPress", "sweeper_bastionTauntToggle", function(ply, key)
		if key ~= IN_WALK or not ply:Alive() or not S.PlayerHasSpec(ply, "bastion") then return end

		-- Spent pool: nothing to switch on until it has recharged
		local ready = ply:GetNWFloat("sweeper_tauntReady", 0) - CurTime()
		if ready > 0 and not ply:GetNWBool("sweeper_tauntOn", false) then
			ply:EmitSound("buttons/button2.wav", 55, 80)
			ply:PrintMessage(HUD_PRINTCENTER, string.format("TAUNT RECHARGING (%ds)", math.ceil(ready)))
			return
		end

		local on = not ply:GetNWBool("sweeper_tauntOn", false)
		ply:SetNWBool("sweeper_tauntOn", on)
		ply:EmitSound(on and "buttons/button17.wav" or "buttons/button16.wav", 60, on and 110 or 90)
		ply:PrintMessage(HUD_PRINTCENTER, on and "TAUNT ON" or "TAUNT OFF")
	end)

	local function isEnemy(ent)
		return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and jcms.team_NPC(ent)
	end

	-- // Juggernaut: Iron Skin {{{
	S.abilities.juggernaut.activate = function(ply)
		ply:SetNWFloat("sweeper_ironSkinUntil", CurTime() + S.Tune(ply, "ironSkinDuration", T.ironSkinDuration))
		ply:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 5) .. ".wav", 80, 70)
		return true
	end
	-- }}}

	-- // Brawler: Ground Pound {{{
	-- Fall-damage immunity goes through the gamemode's own `ply.noFallDamage` flag rather than a
	-- GetFallDamage hook of our own: the gamemode registers one too and always returns a value, so
	-- two competing hooks would be decided by hash order, not by us. Its flag path also plays the
	-- soft landing sound and sends the greyed-out fracture icon, which a bare `return 0` skips.
	-- The previous value is saved and restored, in case a class or another addon already set it.
	local function poundFallImmunity(ply, on)
		if on then
			if ply.sweeperPoundFallSaved == nil then
				ply.sweeperPoundFallSaved = ply.noFallDamage or false
			end
			ply.noFallDamage = true
		elseif ply.sweeperPoundFallSaved ~= nil then
			ply.noFallDamage = ply.sweeperPoundFallSaved or nil
			ply.sweeperPoundFallSaved = nil
		end
	end

	S.PoundFallImmunity = poundFallImmunity

	local function poundImpact(ply)
		ply.sweeperPounding = nil

		-- Hold the immunity a moment longer: our Think can spot the landing before the engine has
		-- applied the fall damage for it, and dropping the flag first would let the hit through.
		timer.Simple(0.15, function()
			if IsValid(ply) then poundFallImmunity(ply, false) end
		end)
		local pos = ply:GetPos()
		local ed = EffectData()
		ed:SetOrigin(pos)
		ed:SetScale(S.Tune(ply, "poundRadius", T.poundRadius))
		util.Effect("ThumperDust", ed, true, true)
		util.ScreenShake(pos, 12, 40, 0.6, S.Tune(ply, "poundRadius", T.poundRadius) * 2)
		ply:EmitSound("physics/concrete/boulder_impact_hard" .. math.random(1, 4) .. ".wav", 90, 80)

		for i, ent in ipairs(ents.FindInSphere(pos, S.Tune(ply, "poundRadius", T.poundRadius))) do
			if isEnemy(ent) then
				local dmg = DamageInfo()
				dmg:SetAttacker(ply)
				dmg:SetInflictor(ply)
				dmg:SetDamage(S.Tune(ply, "poundDamage", T.poundDamage))
				dmg:SetDamageType(DMG_CLUB)
				dmg:SetDamagePosition(ent:WorldSpaceCenter())
				ent:TakeDamageInfo(dmg)

				if IsValid(ent) and ent:Health() > 0 then
					local push = (ent:GetPos() - pos):GetNormalized() * T.poundKnockback + Vector(0, 0, 250)
					if ent:IsNPC() then
						ent:SetVelocity(push)
						if ent.SetSchedule then ent:SetSchedule(SCHED_BIG_FLINCH) end
					else
						local phys = ent:GetPhysicsObject()
						if IsValid(phys) then phys:ApplyForceCenter(push * phys:GetMass()) end
					end
				end
			end
		end
	end

	S.abilities.brawler.activate = function(ply)
		ply.sweeperPounding = CurTime()
		poundFallImmunity(ply, true)
		if ply:OnGround() then
			ply:SetVelocity(Vector(0, 0, T.poundJump))
			timer.Simple(0.35, function()
				if IsValid(ply) and ply.sweeperPounding then
					ply:SetVelocity(Vector(0, 0, -T.poundSlam) - Vector(0, 0, ply:GetVelocity().z))
				end
			end)
		else
			ply:SetVelocity(Vector(0, 0, -T.poundSlam))
		end
		ply:EmitSound("npc/zombie/claw_miss1.wav", 75, 70)
		return true
	end

	hook.Add("Think", "sweeper_groundPound", function()
		local ct = CurTime()
		for i, ply in ipairs(player.GetAll()) do
			local started = ply.sweeperPounding
			if started then
				if not ply:Alive() or ct - started > 3 then
					ply.sweeperPounding = nil
					poundFallImmunity(ply, false)
				elseif ct - started > 0.4 and ply:OnGround() then
					poundImpact(ply)
				end
			end
		end
	end)

	-- Never leave the flag set across a life or a class change.
	hook.Add("PlayerSpawn", "sweeper_poundNoFall", function(ply)
		ply.sweeperPounding = nil
		poundFallImmunity(ply, false)
	end)
	-- }}}

	-- // Bastion: Challenge {{{
	local function challengeTick(ply)
		for i, npc in ipairs(ents.FindInSphere(ply:GetPos(), T.challengeRadius)) do
			if isEnemy(npc) and npc:IsNPC() then
				npc:AddEntityRelationship(ply, D_HT, 99)
				if npc.SetEnemy then npc:SetEnemy(ply) end
				if npc.UpdateEnemyMemory then npc:UpdateEnemyMemory(ply, ply:GetPos()) end
			end
		end
	end

	S.abilities.bastion.activate = function(ply)
		ply:SetNWFloat("sweeper_challengeUntil", CurTime() + S.Tune(ply, "challengeDuration", T.challengeDuration))
		ply:EmitSound("npc/combine_soldier/vo/overwatchtargetcontained.wav", 90, 80)
		ply:EmitSound("ambient/alarms/klaxon1.wav", 80, 110, 0.5)
		challengeTick(ply)
		local id = "sweeper_challenge" .. ply:EntIndex()
		timer.Create(id, 0.5, math.ceil(S.Tune(ply, "challengeDuration", T.challengeDuration) / 0.5), function()
			if IsValid(ply) and ply:Alive() and active(ply, "sweeper_challengeUntil") then
				challengeTick(ply)
			else
				timer.Remove(id)
			end
		end)
		return true
	end
	-- }}}

	-- // Ravager: Bloodlust {{{
	S.abilities.ravager.activate = function(ply)
		local untilT = CurTime() + T.rageDuration
		ply:SetNWFloat("sweeper_rageUntil", untilT)
		ply:SetNWFloat("sweeper_bloodlustUntil", untilT)
		ply:EmitSound("npc/antlion_guard/angry" .. math.random(1, 3) .. ".wav", 85, 120)
		util.ScreenShake(ply:GetPos(), 6, 40, 0.5, 200)
		return true
	end

	local meleeHold = { melee = true, melee2 = true, knife = true, fist = true }
	hook.Add("MapSweepersDeathNPC", "sweeper_bloodlustKill", function(npc, attacker, inflictor)
		if not active(attacker, "sweeper_bloodlustUntil") then return end
		local wep = attacker:GetActiveWeapon()
		local melee = (IsValid(wep) and meleeHold[wep:GetHoldType()]) or (IsValid(inflictor) and inflictor:IsWeapon() and meleeHold[inflictor:GetHoldType()])
		if not melee then return end
		local ct = CurTime()
		local newUntil = math.min(attacker:GetNWFloat("sweeper_rageUntil", ct) + S.Tune(attacker, "bloodlustPerKill", T.bloodlustPerKill), ct + S.Tune(attacker, "bloodlustMax", T.bloodlustMax))
		attacker:SetNWFloat("sweeper_rageUntil", newUntil)
		attacker:SetNWFloat("sweeper_bloodlustUntil", newUntil)
	end)
	-- }}}

	-- Damage taken: Iron Skin + Challenge
	hook.Add("EntityTakeDamage", "sweeper_sentinelAbilityDefense", function(ent, dmg)
		if not ent:IsPlayer() then return end
		local mul = 1
		if active(ent, "sweeper_ironSkinUntil") then mul = mul * T.ironSkinDamageTaken end
		if active(ent, "sweeper_challengeUntil") then mul = mul * S.Tune(ent, "challengeDamageTaken", T.challengeDamageTaken) end
		if mul ~= 1 then dmg:ScaleDamage(mul) end
	end)

	hook.Add("MapSweepersClassApplied", "sweeper_sentinelAbilityReset", function(ply)
		for i, nw in ipairs({ "ironSkinUntil", "challengeUntil", "bloodlustUntil" }) do
			ply:SetNWFloat("sweeper_" .. nw, 0)
		end
		ply.sweeperPounding = nil
		if S.CheckBastionTauntOff then S.CheckBastionTauntOff(ply) end
		if not S.PlayerHasSpec(ply, "bastion") then ply:SetNWBool("sweeper_tauntOn", false) end
		if S.TauntResetCharge then S.TauntResetCharge(ply) end
	end)
end

if CLIENT then
	S.AddHud("sentinelAbilityTint", "tint", function(ply)
		if active(ply, "sweeper_ironSkinUntil") then
			S.HudTint(jcms.color_bright_alt, 16)
		end
		if active(ply, "sweeper_challengeUntil") then
			S.HudTint(jcms.color_alert2, 12)
		end
	end)
end
-- }}}
