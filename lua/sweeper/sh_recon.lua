--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Recon specialization mechanics.

	T1 Scout         Enemies you aim at are outlined for your whole team (6s).
	                 [G/H/J] Recon Pulse: sonar pulse that outlines every enemy within 2500 units for the
	                 whole team for 8s, through walls. 40s cooldown.
	T1 Infiltrator   Ambush: +40% damage to enemies that aren't targeting you.
	                 [G] Decoy: drop a hologram of yourself. Enemies nearby lose track of you and go after it
	                 for 8s (or until they shoot it down). 25s cooldown.
	T2 Gunslinger    Each kill = +1 Quickdraw stack (max 5): reload 10% faster per stack, 30s after your last kill.
	                 [G/H] Deadeye: lock on to every enemy on your screen and one-shot them. 45s cooldown.
	T2 Stalker  Weak Point: enemies you shoot are marked for 5s; your whole team deals +15% damage to them.
	                 [G/H] One Shot, One Kill: for 6s, any enemy below 35% HP dies to your next hit.
	                 Every execute resets the 6s timer. 45s cooldown.
	T3 Phantom       Triple jump. Nearby allies move 10% faster.
	                 [G] Phantom Cloak: 6s invisible. Shooting does NOT break it, and every kill adds +2s
	                 (up to 15s left on the clock). 35s cooldown.
	T3 Bounty Hunter Hits (perk, like the Hitman workshop class): new enemies sometimes become marked
	                 targets for 60s. The whole team sees them through walls, and WHOEVER kills one gets
	                 2x its bounty as bonus cash (+XP).
	                 [G] Execution: 6s of 5x damage and 2.5x fire rate. 45s cooldown.

	Tuning values are in S.recon below.
--]]

local S = sweeper

S.recon = {
	spotRange = 4000,
	spotDuration = 6,
	spotInterval = 0.25,

	pulseRange = 2500,           -- Scout's Recon Pulse
	pulseDuration = 8,
	pulseCooldown = 40,

	cloakAlpha = 18,             -- Phantom Cloak: 0 = fully invisible, 255 = normal

	ambushBonus = 0.40,          -- Infiltrator: damage bonus vs enemies not currently targeting you

	decoyDuration = 8,           -- Infiltrator's Decoy
	decoyCooldown = 25,
	decoyHealth = 150,           -- damage enemies must deal to shoot it down early
	decoyRadius = 1200,          -- enemies within this range go after the decoy
	decoyStealth = 1.5,          -- seconds enemies can't target you right after you drop it (so they switch)
	decoyPopDamage = 0,          -- damage when it pops (0 = harmless pop)
	decoyPopRadius = 200,

	hitChance = 0.30,       -- chance a newly spawned enemy becomes a target (when the Bounty Hunter has none)
	hitDuration = 60,
	hitRange = 10000,       -- target must spawn within this distance of the Bounty Hunter
	hitMinBounty = 20,      -- only enemies worth at least this much
	hitCashMul = 2,         -- bonus cash = enemy's bounty x this
	hitMinCash = 40,
	hitXP = 60,

	executionDuration = 6,
	executionCooldown = 45,
	executionDamageMul = 5,
	executionFireRate = 2.5,     -- fire rate multiplier

	quickdrawMaxStacks = 5,
	quickdrawPerStack = 0.10,    -- reload speed per stack (0.10 = +10%)
	quickdrawDuration = 30,      -- stacks last this long after your last kill

	autoAimCooldown = 45,
	autoAimRange = 4000,
	autoAimMaxTargets = 12,
	autoAimCone = 0.72,          -- cos of the max angle from your crosshair (~44 degrees = roughly your screen)
	autoAimLockTime = 0.35,      -- lock-on delay before the first shot
	autoAimShotDelay = 0.12,     -- time between shots
	autoAimBossHealth = 1500,    -- enemies with this much max health or more are bosses...
	autoAimBossDamage = 400,     -- ...and take this much instead of dying instantly

	jumpBlast = false,           -- the gamemode's recon air jump explodes under you (damage + boom). false = no blast, just the jump

	weakPointDuration = 5,
	weakPointDamageMul = 1.15,

	oneShotDuration = 6,
	oneShotCooldown = 45,
	oneShotThreshold = 0.35,     -- fraction of max HP
	oneShotBossImmune = true,    -- bosses (autoAimBossHealth+ max HP) can't be executed

	phantomCloakDuration = 6,
	phantomCloakCooldown = 35,
	phantomCloakPerKill = 2,     -- seconds added per kill while cloaked
	phantomCloakMaxLeft = 15,    -- the timer can't go above this many seconds remaining

	phantomExtraJumps = 1,
	phantomAuraRadius = 300,
	phantomSpeedMul = 1.10,
}

local R = S.recon


-- // Cloak (Phantom) + Decoy (Infiltrator) {{{
S.abilities.scout = { name = "Recon Pulse", cooldown = R.pulseCooldown }
S.abilities.infiltrator = { name = "Decoy", cooldown = R.decoyCooldown }
S.abilities.phantom = { name = "Phantom Cloak", cooldown = R.phantomCloakCooldown }

if SERVER then
	-- The gamemode resets "no target" every tick; keep it on while cloaked.
	local plyMeta = FindMetaTable("Player")
	if not S._wrappedSetNoTarget and plyMeta.SetNoTarget then
		local orig = plyMeta.SetNoTarget
		S._wrappedSetNoTarget = true
		plyMeta.SetNoTarget = function(self, b, ...)
			if self.sweeperCloaked or (self.sweeperDecoyHideUntil or 0) > CurTime() then b = true end
			return orig(self, b, ...)
		end
	end

	local function setCloakVisuals(ply, cloaked)
		local alpha = cloaked and R.cloakAlpha or 255
		local mode = cloaked and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL
		ply:SetRenderMode(mode)
		ply:SetColor(Color(255, 255, 255, alpha))
		ply:DrawShadow(not cloaked)
		for i, wep in ipairs(ply:GetWeapons()) do
			wep:SetRenderMode(mode)
			wep:SetColor(Color(255, 255, 255, alpha))
		end
	end

	function S.Uncloak(ply)
		if not ply.sweeperCloaked then return end
		ply.sweeperCloaked = false
		ply.sweeperCloakKind = nil
		ply:SetNWBool("sweeper_cloaked", false)
		ply:SetNWBool("sweeper_phantomCloak", false)
		ply:SetNoTarget(ply:GetObserverMode() ~= OBS_MODE_NONE)
		setCloakVisuals(ply, false)
		ply:EmitSound("npc/turret_floor/active.wav", 65, 90, 0.6)
		timer.Remove("sweeper_cloak" .. ply:EntIndex())
	end

	local function cloak(ply, duration, kind)
		if ply.sweeperCloaked then return false, "You're already cloaked." end
		duration = duration or R.phantomCloakDuration

		ply.sweeperCloaked = true
		ply.sweeperCloakKind = kind or "infiltrator"
		ply:SetNWBool("sweeper_phantomCloak", kind == "phantom")
		ply:SetNWBool("sweeper_cloaked", true)
		ply:SetNWFloat("sweeper_cloakEnd", CurTime() + duration)
		ply:SetNoTarget(true)
		setCloakVisuals(ply, true)
		ply:EmitSound("npc/scanner/scanner_nearmiss1.wav", 70, 80, 0.8)

		-- Enemies currently chasing us lose track
		for i, npc in ipairs(ents.FindInSphere(ply:GetPos(), 6000)) do
			if npc:IsNPC() and npc.GetEnemy and npc:GetEnemy() == ply then
				npc:SetEnemy(NULL)
				if npc.ClearEnemyMemory then npc:ClearEnemyMemory(ply) end
			end
		end

		timer.Create("sweeper_cloak" .. ply:EntIndex(), duration, 1, function()
			if IsValid(ply) then S.Uncloak(ply) end
		end)
		return true
	end

	S.abilities.phantom.activate = function(ply) return cloak(ply, R.phantomCloakDuration, "phantom") end


	-- // Infiltrator: Decoy {{{
	-- A hologram of you (same model, skin, bodygroups and gun) plus an invisible npc_bullseye that enemy NPCs
	-- are told to hate and chase. npc_bullseye is on the gamemode's "invalid NPC" list, so turrets and the
	-- director ignore it. Enemy damage to it is counted by us and blocked, so it never "dies" as an NPC.
	S.decoys = S.decoys or {}

	local function decoyAnim(holo, ply)
		local wep = ply:GetActiveWeapon()
		local hold = IsValid(wep) and wep.GetHoldType and wep:GetHoldType() or "ar2"
		for i, name in ipairs({ "idle_" .. hold, "idle_ar2", "idle_smg1", "idle_all_01", "idle_passive" }) do
			local seq = holo:LookupSequence(name)
			if seq and seq >= 0 then return name, seq end
		end
	end

	function S.PopDecoy(ply, shotDown)
		local d = S.decoys[ply]
		if not d then return end
		S.decoys[ply] = nil
		if IsValid(ply) then ply:SetNWFloat("sweeper_decoyUntil", 0) end

		local pos = IsValid(d.holo) and d.holo:GetPos() or d.pos
		local ed = EffectData()
		ed:SetOrigin(pos + Vector(0, 0, 40))
		util.Effect("cball_explode", ed)
		sound.Play(shotDown and "npc/scanner/scanner_electric2.wav" or "npc/scanner/cbot_energyexplosion1.wav", pos, 75, 110, 0.8)

		if S.Tune(ply, "decoyPopDamage", R.decoyPopDamage) > 0 and IsValid(ply) then
			for i, ent in ipairs(ents.FindInSphere(pos, R.decoyPopRadius)) do
				if ent ~= d.bull and (ent:IsNPC() or ent:IsNextBot()) and jcms.team_NPC(ent) then
					local dmg = DamageInfo()
					dmg:SetDamage(S.Tune(ply, "decoyPopDamage", R.decoyPopDamage))
					dmg:SetDamageType(DMG_SHOCK)
					dmg:SetAttacker(ply)
					dmg:SetInflictor(ply)
					dmg:SetDamagePosition(pos)
					ent:TakeDamageInfo(dmg)
				end
			end
		end

		if IsValid(d.bull) then d.bull:Remove() end
		if IsValid(d.gun) then d.gun:Remove() end
		if IsValid(d.holo) then d.holo:Remove() end
	end

	local function dropDecoy(ply)
		if S.decoys[ply] then S.PopDecoy(ply, false) end

		local pos = ply:GetPos()
		local tr = util.TraceLine({ start = pos + Vector(0, 0, 8), endpos = pos - Vector(0, 0, 400), filter = ply, mask = MASK_PLAYERSOLID_BRUSHONLY })
		if tr.Hit then pos = tr.HitPos end

		-- Hologram
		local holo = ents.Create("prop_dynamic")
		if not IsValid(holo) then return false, "Couldn't place a decoy here." end
		holo:SetModel(ply:GetModel())
		local animName = decoyAnim(holo, ply)
		if animName then holo:SetKeyValue("DefaultAnim", animName) end
		holo:SetPos(pos)
		holo:SetAngles(Angle(0, ply:EyeAngles().y, 0))
		holo:SetSkin(ply:GetSkin())
		for i = 0, ply:GetNumBodyGroups() - 1 do holo:SetBodygroup(i, ply:GetBodygroup(i)) end
		holo:Spawn()
		holo:SetSolid(SOLID_NONE)
		holo:SetMoveType(MOVETYPE_NONE)
		holo:SetRenderMode(RENDERMODE_TRANSALPHA)
		holo:SetRenderFX(kRenderFxHologram)
		holo:SetColor(Color(120, 190, 255, 170))
		holo:DrawShadow(false)
		if animName then holo:Fire("SetAnimation", animName) end

		-- Gun in its hands
		local gun
		local wep = ply:GetActiveWeapon()
		local wmdl = IsValid(wep) and wep:GetModel()
		if wmdl and wmdl ~= "" then
			gun = ents.Create("prop_dynamic")
			if IsValid(gun) then
				gun:SetModel(wmdl)
				gun:SetPos(pos)
				gun:Spawn()
				gun:SetSolid(SOLID_NONE)
				gun:SetParent(holo)
				gun:AddEffects(EF_BONEMERGE)
				gun:SetRenderMode(RENDERMODE_TRANSALPHA)
				gun:SetRenderFX(kRenderFxHologram)
				gun:SetColor(Color(120, 190, 255, 170))
				gun:DrawShadow(false)
			end
		end

		-- What the enemies actually shoot at
		local bull = ents.Create("npc_bullseye")
		if not IsValid(bull) then holo:Remove() if IsValid(gun) then gun:Remove() end return false, "Couldn't place a decoy here." end
		bull:SetPos(pos + Vector(0, 0, 40))
		bull:SetKeyValue("health", "99999")
		bull:Spawn()
		bull:Activate()
		bull:SetHealth(99999)
		bull:SetCollisionBounds(Vector(-14, -14, -38), Vector(14, 14, 30))
		bull:SetCollisionGroup(COLLISION_GROUP_WEAPON) -- bullets hit it, players walk through it
		bull:SetParent(holo)

		local d = { owner = ply, holo = holo, gun = gun, bull = bull, pos = pos, hp = R.decoyHealth, untilT = CurTime() + S.Tune(ply, "decoyDuration", R.decoyDuration) }
		bull.sweeperDecoy = d
		S.decoys[ply] = d
		ply:SetNWFloat("sweeper_decoyUntil", d.untilT)

		-- You slip away: brief no-target, and anyone chasing you switches to the decoy
		ply.sweeperDecoyHideUntil = CurTime() + R.decoyStealth
		ply:SetNoTarget(true)
		timer.Create("sweeper_decoyHide" .. ply:EntIndex(), R.decoyStealth, 1, function()
			if IsValid(ply) and not ply.sweeperCloaked then
				ply:SetNoTarget(ply:GetObserverMode() ~= OBS_MODE_NONE)
			end
		end)
		for i, npc in ipairs(ents.FindInSphere(pos, R.decoyRadius * 2)) do
			if npc:IsNPC() and npc.GetEnemy and npc:GetEnemy() == ply then
				if npc.ClearEnemyMemory then npc:ClearEnemyMemory(ply) end
				if npc.AddEntityRelationship then
					npc:AddEntityRelationship(bull, D_HT, 99)
					npc:SetEnemy(bull)
					npc:UpdateEnemyMemory(bull, bull:GetPos())
				end
			end
		end

		sound.Play("npc/scanner/scanner_nearmiss1.wav", pos, 75, 70, 0.9)
		ply:EmitSound("buttons/combine_button1.wav", 60, 130, 0.6)
		return true
	end
	S.abilities.infiltrator.activate = dropDecoy

	-- Keep enemies in range on the decoy until it pops
	timer.Create("sweeper_decoyTick", 0.25, 0, function()
		local ct = CurTime()
		for ply, d in pairs(S.decoys) do
			if not IsValid(ply) or not IsValid(d.bull) or not IsValid(d.holo) or ct >= d.untilT then
				S.PopDecoy(ply, false)
			else
				local bull = d.bull
				for i, npc in ipairs(ents.FindInSphere(bull:GetPos(), R.decoyRadius)) do
					if npc ~= bull and npc:IsNPC() and npc:Health() > 0 and jcms.team_NPC(npc) and npc.AddEntityRelationship then
						npc:AddEntityRelationship(bull, D_HT, 99)
						if npc:GetEnemy() ~= bull then
							npc:SetEnemy(bull)
							npc:UpdateEnemyMemory(bull, bull:GetPos())
						end
					end
				end
			end
		end
	end)

	-- Enemy hits wear it down (players can't hurt it); the damage never reaches the bullseye itself
	hook.Add("EntityTakeDamage", "sweeper_decoyDamage", function(ent, dmg)
		local d = ent.sweeperDecoy
		if not d then return end
		local attacker = dmg:GetAttacker()
		if not (IsValid(attacker) and attacker:IsPlayer()) then
			d.hp = d.hp - dmg:GetDamage()
			if IsValid(d.holo) then
				d.holo:SetColor(Color(255, 255, 255, 220))
				timer.Simple(0.08, function()
					if IsValid(d.holo) then d.holo:SetColor(Color(120, 190, 255, 170)) end
				end)
			end
			if d.hp <= 0 and IsValid(d.owner) then S.PopDecoy(d.owner, true) end
		end
		return true
	end)

	hook.Add("PlayerDeath", "sweeper_decoyDeath", function(ply) S.PopDecoy(ply, false) end)
	hook.Add("PlayerDisconnected", "sweeper_decoyLeave", function(ply) S.PopDecoy(ply, false) end)
	hook.Add("MapSweepersClassApplied", "sweeper_decoyReset", function(ply)
		S.PopDecoy(ply, false)
		ply.sweeperDecoyHideUntil = nil
	end)
	-- }}}

	-- Phantom: kills while cloaked add time
	hook.Add("MapSweepersDeathNPC", "sweeper_phantomCloakKill", function(npc, attacker)
		if not (IsValid(attacker) and attacker:IsPlayer()) then return end
		if not (attacker.sweeperCloaked and attacker.sweeperCloakKind == "phantom") then return end

		local ct = CurTime()
		local left = math.max(0, attacker:GetNWFloat("sweeper_cloakEnd", ct) - ct)
		local newLeft = math.min(left + S.Tune(attacker, "phantomCloakPerKill", R.phantomCloakPerKill), S.Tune(attacker, "phantomCloakMaxLeft", R.phantomCloakMaxLeft))
		attacker:SetNWFloat("sweeper_cloakEnd", ct + newLeft)
		timer.Create("sweeper_cloak" .. attacker:EntIndex(), newLeft, 1, function()
			if IsValid(attacker) then S.Uncloak(attacker) end
		end)
		attacker:EmitSound("npc/scanner/scanner_nearmiss2.wav", 55, 140, 0.5)

		-- Keep enemies from locking on after the kill
		for i, other in ipairs(ents.FindInSphere(attacker:GetPos(), 3000)) do
			if other:IsNPC() and other.GetEnemy and other:GetEnemy() == attacker then
				other:SetEnemy(NULL)
				if other.ClearEnemyMemory then other:ClearEnemyMemory(attacker) end
			end
		end
	end)

	-- Attacking breaks a normal cloak (not the Phantom one)
	hook.Add("KeyPress", "sweeper_cloakBreak", function(ply, key)
		if ply.sweeperCloaked and ply.sweeperCloakKind ~= "phantom" and (key == IN_ATTACK or key == IN_ATTACK2) then
			S.Uncloak(ply)
		end
	end)

	-- Keep weapons invisible when switching while cloaked
	hook.Add("PlayerSwitchWeapon", "sweeper_cloakWeapon", function(ply, old, new)
		if ply.sweeperCloaked and IsValid(new) then
			new:SetRenderMode(RENDERMODE_TRANSALPHA)
			new:SetColor(Color(255, 255, 255, R.cloakAlpha))
		end
	end)

	hook.Add("PlayerDeath", "sweeper_cloakDeath", function(ply) S.Uncloak(ply) end)
	hook.Add("MapSweepersClassApplied", "sweeper_cloakReset", function(ply)
		ply.sweeperCloaked = false
		ply:SetNWBool("sweeper_cloaked", false)
	end)

	-- The director shouldn't point enemies at cloaked players
	function S.InstallCloakDirector()
		if not jcms or not jcms.director_PickClosestPlayer or S.Wrapped(jcms, "PickClosest") then return end
		local orig = jcms.director_PickClosestPlayer
		S._wrappedPickClosest = function(v, fromList, ...)
			local list = {}
			for i, ply in ipairs(fromList or player.GetAll()) do
				if not ply.sweeperCloaked then list[#list + 1] = ply end
			end
			return orig(v, list, ...)
		end
		jcms.director_PickClosestPlayer = S._wrappedPickClosest
		S.MarkWrapped(jcms, "PickClosest")
	end
	hook.Add("Initialize", "sweeper_cloakDirector", S.InstallCloakDirector)
	S.InstallCloakDirector()
end
-- }}}

if SERVER then
	-- // Infiltrator: Ambush (passive) {{{
	-- Enemies that aren't already onto you take extra damage: an enemy whose current target is
	-- someone or something else, or nothing at all. The Decoy pulls aggro away, so the ability sets
	-- this up on purpose - and it rewards opening on a crowd that hasn't noticed you.
	hook.Add("EntityTakeDamage", "sweeper_infiltratorAmbush", function(ent, dmg)
		local attacker = dmg:GetAttacker()
		if not (IsValid(attacker) and attacker:IsPlayer() and ent ~= attacker and not ent:IsPlayer()) then return end
		if not (ent:IsNPC() or ent:IsNextBot()) then return end
		if not S.PlayerHasSpec(attacker, "infiltrator") then return end

		local target = ent.GetEnemy and ent:GetEnemy()
		if IsValid(target) and target == attacker then return end -- already fighting you: no bonus

		dmg:ScaleDamage(1 + S.Tune(attacker, "ambushBonus", R.ambushBonus))
	end)
	-- }}}

	-- // Scout spotting {{{
	util.AddNetworkString("sweeper_spot")

	local function isEnemyNPC(ent)
		return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and jcms.team_NPC(ent)
	end

	timer.Create("sweeper_scoutSpot", R.spotInterval, 0, function()
		local ct = CurTime()
		for i, ply in ipairs(player.GetAll()) do
			if ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE and S.PlayerHasSpec(ply, "scout") then
				local start = ply:EyePos()
				local tr = util.TraceHull({
					start = start,
					endpos = start + ply:GetAimVector() * R.spotRange,
					mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10),
					filter = ply,
					mask = MASK_SHOT,
				})
				local ent = tr.Entity
				if isEnemyNPC(ent) and (ent.sweeperSpottedUntil or 0) < ct + R.spotDuration * 0.5 then
					ent.sweeperSpottedUntil = ct + R.spotDuration
					net.Start("sweeper_spot")
						net.WriteEntity(ent)
						net.WriteFloat(ct + R.spotDuration)
						net.WriteInt(ply:GetNWInt("jcms_pvpTeam", -1), 8)
					net.Broadcast()
				end
			end
		end
	end)
	-- }}}

	-- // Scout: Recon Pulse (ability) {{{
	util.AddNetworkString("sweeper_pulse")

	S.abilities.scout.activate = function(ply)
		local origin = ply:WorldSpaceCenter()
		local ct = CurTime()
		local untilTime = ct + S.Tune(ply, "pulseDuration", R.pulseDuration)
		local found = {}
		for i, ent in ipairs(ents.FindInSphere(origin, S.Tune(ply, "pulseRange", R.pulseRange))) do
			if isEnemyNPC(ent) then
				ent.sweeperSpottedUntil = math.max(ent.sweeperSpottedUntil or 0, untilTime)
				found[#found + 1] = ent
				if #found >= 255 then break end
			end
		end

		ply:SetNWFloat("sweeper_pulseUntil", untilTime)
		ply:EmitSound("npc/scanner/scanner_scan2.wav", 80, 90)
		ply:EmitSound("buttons/combine_button_locked.wav", 70, 140, 0.6)

		net.Start("sweeper_pulse")
			net.WriteVector(origin)
			net.WriteFloat(untilTime)
			net.WriteInt(ply:GetNWInt("jcms_pvpTeam", -1), 8)
			net.WriteUInt(#found, 8)
			for i, ent in ipairs(found) do net.WriteEntity(ent) end
		net.Broadcast()

		ply:ChatPrint(string.format("[Recon Pulse] %d enem%s spotted.", #found, #found == 1 and "y" or "ies"))
		return true
	end

	hook.Add("MapSweepersClassApplied", "sweeper_pulseReset", function(ply)
		ply:SetNWFloat("sweeper_pulseUntil", 0)
	end)
	-- }}}

	-- // Phantom: speed aura {{{
	timer.Create("sweeper_phantomAura", 0.5, 0, function()
		local sources = {}
		for i, ply in ipairs(player.GetAll()) do
			if ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE and S.PlayerHasSpec(ply, "phantom") then
				sources[#sources + 1] = ply
			end
		end

		for i, ally in ipairs(player.GetAll()) do
			local hasted = false
			if ally:Alive() and ally:GetObserverMode() == OBS_MODE_NONE then
				for j, src in ipairs(sources) do
					if src ~= ally and jcms.team_SameTeam(src, ally)
						and src:GetPos():DistToSqr(ally:GetPos()) <= R.phantomAuraRadius ^ 2 then
						hasted = true
						break
					end
				end
			end
			if ally:GetNWBool("sweeper_hasted", false) ~= hasted then
				ally:SetNWBool("sweeper_hasted", hasted)
			end
		end
	end)
	-- }}}
end

-- // Bounty Hunter (id "bountyhunter"): Hits (perk) + Execution (ability) {{{
-- These are called "hits", NOT contracts: "New Contract" in sh_group.lua is the mission reroll vote, and the
-- two used to share the net message name "sweeper_contract", so each one ate the other's messages.
S.abilities.bountyhunter = { name = "Execution", cooldown = R.executionCooldown }

local HIT_SPAWNED, HIT_EXPIRED, HIT_COMPLETED = 1, 2, 3

-- All current hit targets that `viewer` can see (same team)
function S.GetHitTargets(viewer)
	local list, ct = {}, CurTime()
	local myTeam = IsValid(viewer) and viewer:GetNWInt("jcms_pvpTeam", -1) or -1
	for i, ply in ipairs(player.GetAll()) do
		local target = ply:GetNWEntity("sweeper_hit")
		if IsValid(target) and ply:GetNWFloat("sweeper_hitEnd", 0) > ct then
			local team = ply:GetNWInt("jcms_pvpTeam", -1)
			if myTeam == -1 or team == -1 or team == myTeam then
				list[#list + 1] = { target = target, owner = ply }
			end
		end
	end
	return list
end

if SERVER then
	util.AddNetworkString("sweeper_hit")

	local function sendHit(to, status, cash, killerName)
		net.Start("sweeper_hit")
			net.WriteUInt(status, 2)
			net.WriteUInt(math.Clamp(cash or 0, 0, 65535), 16)
			net.WriteString(killerName or "")
		net.Send(to)
	end

	local function clearHit(ply)
		ply.sweeperHit = nil
		ply:SetNWEntity("sweeper_hit", NULL)
		ply:SetNWFloat("sweeper_hitEnd", 0)
	end

	local function sameTeam(a, b)
		local ta, tb = a:GetNWInt("jcms_pvpTeam", -1), b:GetNWInt("jcms_pvpTeam", -1)
		return ta == -1 or tb == -1 or ta == tb
	end

	-- New enemies can become a Hitman's target (same rules as the Hitman workshop class)
	hook.Add("MapSweepersNPCSpawned", "sweeper_hitSpawn", function(npc)
		if math.random() > R.hitChance then return end
		timer.Simple(0, function() -- bounty is set right after spawning
			if not (IsValid(npc) and npc:Health() > 0) then return end
			if (tonumber(npc.jcms_bounty) or 0) < R.hitMinBounty then return end

			for i, ply in ipairs(player.GetAll()) do
				if ply:Alive() and S.PlayerHasSpec(ply, "bountyhunter") and not IsValid(ply.sweeperHit)
					and npc:GetPos():DistToSqr(ply:GetPos()) <= R.hitRange ^ 2 then
					ply.sweeperHit = npc
					ply:SetNWEntity("sweeper_hit", npc)
					ply:SetNWFloat("sweeper_hitEnd", CurTime() + R.hitDuration)
					sendHit(ply, HIT_SPAWNED)
					break
				end
			end
		end)
	end)

	-- Whoever kills a target gets the bonus pay
	hook.Add("MapSweepersDeathNPC", "sweeper_hitKill", function(npc, attacker)
		for i, ply in ipairs(player.GetAll()) do
			if ply.sweeperHit == npc then
				local killer = attacker
				if IsValid(killer) and not killer:IsPlayer() and IsValid(killer.jcms_owner) then killer = killer.jcms_owner end -- turrets, drones

				if IsValid(killer) and killer:IsPlayer() and sameTeam(killer, ply) then
					local cash = math.max(R.hitMinCash, math.floor((tonumber(npc.jcms_bounty) or 0) * S.Tune(ply, "hitCashMul", R.hitCashMul)))
					if jcms.giveCash then jcms.giveCash(killer, cash) else killer:SetNWInt("jcms_cash", killer:GetNWInt("jcms_cash", 0) + cash) end
					local class = S.GetActiveClass and S.GetActiveClass(killer)
					if class and S.AddXP then S.AddXP(killer, class, R.hitXP, "hit") end

					-- Tell the whole team who cashed in
					local rf = {}
					for j, p in ipairs(player.GetHumans()) do
						if sameTeam(p, ply) then rf[#rf + 1] = p end
					end
					sendHit(rf, HIT_COMPLETED, cash, killer:Nick())
				else
					sendHit(ply, HIT_EXPIRED)
				end
				clearHit(ply)
			end
		end
	end)

	-- Expire old targets (or ones that vanished)
	timer.Create("sweeper_hitExpire", 1, 0, function()
		local ct = CurTime()
		for i, ply in ipairs(player.GetAll()) do
			if ply.sweeperHit ~= nil then
				if not IsValid(ply.sweeperHit) or ct > ply:GetNWFloat("sweeper_hitEnd", 0)
					or not S.PlayerHasSpec(ply, "bountyhunter") then
					if IsValid(ply) then sendHit(ply, HIT_EXPIRED) end
					clearHit(ply)
				end
			end
		end
	end)

	-- // Execution: 5x damage, 2.5x fire rate {{{
	S.abilities.bountyhunter.activate = function(ply)
		ply:SetNWFloat("sweeper_execUntil", CurTime() + S.Tune(ply, "executionDuration", R.executionDuration))
		ply:EmitSound("weapons/357/357_spin1.wav", 75, 80)
		ply:EmitSound("npc/strider/charging.wav", 60, 150, 0.5)
		return true
	end

	local function executing(ply)
		return IsValid(ply) and ply:IsPlayer() and ply:GetNWFloat("sweeper_execUntil", 0) > CurTime()
	end

	hook.Add("EntityTakeDamage", "sweeper_executionDamage", function(ent, dmg)
		local attacker = dmg:GetAttacker()
		if executing(attacker) and ent ~= attacker and not ent:IsPlayer() then
			dmg:ScaleDamage(R.executionDamageMul)
		end
	end)

	local reloadActs = { [ACT_VM_RELOAD] = true, [ACT_VM_RELOAD_SILENCED] = true, [ACT_SHOTGUN_RELOAD_START] = true }
	-- Fire-rate bonuses from any ability. Add more with: S.fireRateSources[name] = function(ply) return mul end
	S.fireRateSources = S.fireRateSources or {}
	S.fireRateSources.execution = function(ply) return executing(ply) and R.executionFireRate or 1 end

	function S.FireRateMul(ply)
		local mul = 1
		for name, fn in pairs(S.fireRateSources) do
			local ok, m = pcall(fn, ply)
			if ok and m then mul = mul * m end
		end
		return mul
	end

	hook.Add("Tick", "sweeper_executionFireRate", function()
		local ct = CurTime()
		for i, ply in ipairs(player.GetAll()) do
			local fireMul = ply:Alive() and S.FireRateMul(ply) or 1
			if fireMul > 1 then
				local wep = ply:GetActiveWeapon()
				if IsValid(wep) then
					local nf = wep:GetNextPrimaryFire()
					local vm = ply:GetViewModel()
					local reloading = IsValid(vm) and reloadActs[vm:GetSequenceActivity(vm:GetSequence())]
					-- A new shot pushed the next-fire time forward: shorten the wait
					if nf > ct and nf ~= ply.jcms_execLastNF and not reloading then
						local newNF = ct + (nf - ct) / fireMul
						wep:SetNextPrimaryFire(newNF)
						ply.jcms_execLastNF = newNF
					end
				end
			end
		end
	end)

	hook.Add("MapSweepersClassApplied", "sweeper_executionReset", function(ply)
		ply:SetNWFloat("sweeper_execUntil", 0)
		clearHit(ply)
	end)
	-- }}}
end

if CLIENT then
	-- Uses the "Map Sweepers: Hitman" workshop addon's sounds if it's installed, otherwise HL2 sounds.
	local function pickSound(custom, fallback)
		return file.Exists("sound/" .. custom, "GAME") and custom or fallback
	end
	local sounds = {
		[HIT_SPAWNED]   = { "jcms/hitman/target_spawned.ogg",   "buttons/blip1.wav",     "Bounty Spawned" },
		[HIT_EXPIRED]   = { "jcms/hitman/target_expired.ogg",   "buttons/button10.wav",  "Bounty Expired" },
		[HIT_COMPLETED] = { "jcms/hitman/target_completed.ogg", "buttons/button14.wav",  "Bounty Completed" },
	}

	net.Receive("sweeper_hit", function()
		local status = net.ReadUInt(2)
		local cash = net.ReadUInt(16)
		local killer = net.ReadString()
		local info = sounds[status]
		if not info then return end
		surface.PlaySound(pickSound(info[1], info[2]))
		local msg = info[3]
		if status == HIT_COMPLETED then
			msg = msg .. string.format(" by %s  (+%d J, +%d XP)", killer, cash, R.hitXP)
		end
		chat.AddText(Color(255, 0, 0), "[ BOUNTY HUNTER ] ", Color(255, 128, 128), msg)
	end)

	-- Targets glow red through walls for the whole team
	local glow = Color(255, 0, 0)
	hook.Add("PreDrawHalos", "sweeper_hitGlow", function()
		local list = S.GetHitTargets(LocalPlayer())
		if #list == 0 then return end
		local ents_ = {}
		for i, c in ipairs(list) do ents_[#ents_ + 1] = c.target end
		halo.Add(ents_, glow, 2, 2, 5, true, true)
	end)

	-- Bounty markers, drawn like the gamemode's locators
	S.AddHud("hitMarkers", "2d", function(me)
		for i, c in ipairs(S.GetHitTargets(me)) do
			local target = c.target
			local pos = (target:WorldSpaceCenter() + Vector(0, 0, target:OBBMaxs().z * 0.6)):ToScreen()
			if pos.visible then
				local col = jcms.color_alert
				S.HudMarkerText("X", "jcms_medium", pos.x, pos.y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				S.HudMarkerText("BOUNTY", "jcms_small_bolder", pos.x, pos.y - 14, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
				S.HudMarkerText(S.HudDistance(EyePos():Distance(target:WorldSpaceCenter())), "jcms_small", pos.x, pos.y + 14, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			end
		end
	end)

	-- Execution: tint in the HUD's main colour while active
	S.AddHud("executionTint", "tint", function(me)
		local left = me:GetNWFloat("sweeper_execUntil", 0) - CurTime()
		if left > 0 then
			S.HudTint(jcms.color_bright, 16 + math.sin(CurTime() * 10) * 6)
		end
	end)
end
-- }}}

-- // Shared movement: Phantom haste + triple jump {{{
hook.Add("SetupMove", "sweeper_phantomHaste", function(ply, mv, cmd)
	if ply:GetNWBool("sweeper_hasted", false) then
		mv:SetMaxSpeed(mv:GetMaxSpeed() * R.phantomSpeedMul)
		mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * R.phantomSpeedMul)
	end
end)

function S.InstallReconJumps()
	local recon = jcms and jcms.classes and jcms.classes.recon
	if not recon or not recon.SetupMove or S.Wrapped(recon, "ReconMove") then return end

	local orig = recon.SetupMove
	S._wrappedReconMove = function(ply, mv, cmd, ...)
		if ply:OnGround() then
			ply.sweeperExtraJumpsUsed = 0
		elseif not ply.jcms_CanJump and mv:KeyPressed(IN_JUMP)
			and (ply.sweeperExtraJumpsUsed or 0) < R.phantomExtraJumps
			and ply:GetMoveType() == MOVETYPE_WALK
			and S.PlayerHasSpec(ply, "phantom") then
			-- Give back the air jump; the gamemode's own double-jump code then performs it.
			ply.sweeperExtraJumpsUsed = (ply.sweeperExtraJumpsUsed or 0) + 1
			ply.jcms_CanJump = true
			ply.jcms_HasJumped = true
		end
		if SERVER and not R.jumpBlast then
			-- The air-jump blast only happens when the gamemode's ground trace (util.TraceEntity) hits something,
			-- so while its jump code runs we hand it a trace that hit nothing: no explosion, sound, effect or damage.
			-- The jump itself is untouched.
			local realTrace = util.TraceEntity
			util.TraceEntity = function(tr, ent, ...)
				local res = realTrace(tr, ent, ...)
				if ent == ply and res then res.Hit = false res.Entity = NULL end
				return res
			end
			local r = table.Pack(pcall(orig, ply, mv, cmd, ...))
			util.TraceEntity = realTrace
			if not r[1] then error(r[2], 0) end
			return unpack(r, 2, r.n)
		end
		return orig(ply, mv, cmd, ...)
	end
	recon.SetupMove = S._wrappedReconMove
	S.MarkWrapped(recon, "ReconMove")
end
hook.Add("Initialize", "sweeper_reconJumps", S.InstallReconJumps)
S.InstallReconJumps()
-- }}}

-- // Client visuals {{{
if CLIENT then
	S.spotted = S.spotted or {}

	-- Recon Pulse: spot everything it found + an expanding ring from where it was sent
	local pulses = {}
	net.Receive("sweeper_pulse", function()
		local origin = net.ReadVector()
		local untilTime = net.ReadFloat()
		local team = net.ReadInt(8)
		local count = net.ReadUInt(8)
		local list = {}
		for i = 1, count do list[i] = net.ReadEntity() end

		local me = LocalPlayer()
		local myTeam = IsValid(me) and me:GetNWInt("jcms_pvpTeam", -1) or -1
		if team ~= -1 and myTeam ~= -1 and team ~= myTeam then return end
		for i, ent in ipairs(list) do
			if IsValid(ent) then S.spotted[ent] = math.max(S.spotted[ent] or 0, untilTime) end
		end
		table.insert(pulses, { pos = origin, t = CurTime() })
		if IsValid(me) and me:GetPos():DistToSqr(origin) > 200 ^ 2 then
			surface.PlaySound("npc/scanner/scanner_scan2.wav")
		end
	end)

	hook.Add("PostDrawTranslucentRenderables", "sweeper_pulseRing", function(depth, skybox)
		if skybox or #pulses == 0 then return end
		local ct = CurTime()
		local col = (jcms and jcms.color_bright_alt) or Color(64, 180, 255)
		for i = #pulses, 1, -1 do
			local p = pulses[i]
			local f = (ct - p.t) / 1.2
			if f >= 1 then
				table.remove(pulses, i)
			else
				local r = R.pulseRange * math.ease.OutCubic(f)
				local a = 255 * (1 - f)
				cam.Start3D2D(p.pos + Vector(0, 0, -30), Angle(0, 0, 0), 1)
					surface.DrawCircle(0, 0, r, col.r, col.g, col.b, a)
					surface.DrawCircle(0, 0, r * 0.97, col.r, col.g, col.b, a * 0.5)
				cam.End3D2D()
			end
		end
	end)

	net.Receive("sweeper_spot", function()
		local ent = net.ReadEntity()
		local untilTime = net.ReadFloat()
		local team = net.ReadInt(8)
		local me = LocalPlayer()
		local myTeam = IsValid(me) and me:GetNWInt("jcms_pvpTeam", -1) or -1
		if team ~= -1 and myTeam ~= -1 and team ~= myTeam then return end
		if IsValid(ent) then
			S.spotted[ent] = untilTime
		end
	end)

	local spotList = {}
	hook.Add("PreDrawHalos", "sweeper_scoutSpot", function()
		local ct = CurTime()
		table.Empty(spotList)
		for ent, untilTime in pairs(S.spotted) do
			if not IsValid(ent) or ct > untilTime or ent:Health() <= 0 then
				S.spotted[ent] = nil
			else
				spotList[#spotList + 1] = ent
			end
		end
		if #spotList > 0 then
			halo.Add(spotList, Color(255, 140, 0), 2, 2, 1, true, true)
		end
	end)

	-- Cloaked players are drawn nearly invisible (clientside, so nothing the server resets can undo it)
	local CLOAK_BLEND = 0.06
	hook.Add("PrePlayerDraw", "sweeper_cloakDraw", function(ply)
		if ply:GetNWBool("sweeper_cloaked", false) then
			render.SetBlend(CLOAK_BLEND)
			ply.sweeperCloakBlend = true
		end
	end)
	hook.Add("PostPlayerDraw", "sweeper_cloakDraw", function(ply)
		if ply.sweeperCloakBlend then
			render.SetBlend(1)
			ply.sweeperCloakBlend = nil
		end
	end)

	-- Their held weapon too
	local function cloakedWeaponDraw(self)
		render.SetBlend(CLOAK_BLEND)
		self:DrawModel()
		render.SetBlend(1)
	end
	timer.Create("sweeper_cloakWeapons", 0.1, 0, function()
		for i, ply in ipairs(player.GetAll()) do
			local cloaked = ply:GetNWBool("sweeper_cloaked", false)
			for j, wep in ipairs(ply:GetWeapons()) do
				if cloaked and wep.RenderOverride ~= cloakedWeaponDraw then
					wep.sweeperOldRender = wep.RenderOverride
					wep.RenderOverride = cloakedWeaponDraw
				elseif not cloaked and wep.RenderOverride == cloakedWeaponDraw then
					wep.RenderOverride = wep.sweeperOldRender
					wep.sweeperOldRender = nil
				end
			end
		end
	end)

	-- Your own cloak: see-through viewmodel + screen tint + timer
	hook.Add("PreDrawViewModel", "sweeper_cloakVM", function(vm, ply, wep)
		if IsValid(ply) and ply:GetNWBool("sweeper_cloaked", false) then
			render.SetBlend(0.25)
		end
	end)
	hook.Add("PostDrawViewModel", "sweeper_cloakVM", function(vm, ply, wep)
		render.SetBlend(1)
	end)

	S.AddHud("cloakTint", "tint", function(ply)
		if ply:GetNWBool("sweeper_cloaked", false) then
			S.HudTint(jcms.color_bright_alt, 18)
		end
	end)
end
-- }}}

-- // Gunslinger: Quickdraw stacks + Deadeye {{{
S.abilities.gunslinger = { name = "Deadeye", cooldown = R.autoAimCooldown }

local reloadActs = {
	[ACT_VM_RELOAD] = true,
	[ACT_VM_RELOAD_SILENCED] = true,
	[ACT_VM_RELOAD_EMPTY or -1] = true,
	[ACT_SHOTGUN_RELOAD_START] = true,
	[ACT_SHOTGUN_RELOAD_FINISH] = true,
}

function S.QuickdrawStacks(ply)
	if ply:GetNWFloat("sweeper_qdExpire", 0) < CurTime() then return 0 end
	return ply:GetNWInt("sweeper_qdStacks", 0)
end

if SERVER then
	util.AddNetworkString("sweeper_autoaim")

	local function isEnemyNPC(ent)
		return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and jcms.team_NPC(ent)
	end

	-- Kills add a stack and restart the 30s timer
	hook.Add("MapSweepersDeathNPC", "sweeper_quickdraw", function(npc, attacker)
		if not (IsValid(attacker) and attacker:IsPlayer()) then return end
		if not S.PlayerHasSpec(attacker, "gunslinger") then return end
		attacker:SetNWInt("sweeper_qdStacks", math.min(S.QuickdrawStacks(attacker) + 1, R.quickdrawMaxStacks))
		attacker:SetNWFloat("sweeper_qdExpire", CurTime() + R.quickdrawDuration)
	end)

	hook.Add("MapSweepersClassApplied", "sweeper_quickdrawReset", function(ply)
		ply:SetNWInt("sweeper_qdStacks", 0)
		ply:SetNWFloat("sweeper_qdExpire", 0)
	end)

	-- Faster reloads: when a reload animation starts, play it faster and let the gun fire sooner.
	-- Works with HL2 guns and most SWEPs that use the normal reload animation/timing.
	hook.Add("Tick", "sweeper_quickdrawReload", function()
		for i, ply in ipairs(player.GetAll()) do
			local stacks = ply:Alive() and S.QuickdrawStacks(ply) or 0
			local vm = ply:GetViewModel()
			local wep = ply:GetActiveWeapon()
			if stacks > 0 and IsValid(vm) and IsValid(wep) then
				local seq, cycle = vm:GetSequence(), vm:GetCycle()
				local isReload = reloadActs[vm:GetSequenceActivity(seq)] == true
				local newReload = isReload and (ply.jcms_qdSeq ~= seq or cycle < (ply.jcms_qdCycle or 0) or ply.jcms_qdWep ~= wep)

				if newReload then
					local speed = 1 + stacks * R.quickdrawPerStack
					local ct = CurTime()
					vm:SetPlaybackRate(speed)

					local nf = wep:GetNextPrimaryFire()
					if nf > ct then wep:SetNextPrimaryFire(ct + (nf - ct) / speed) end
					local ns = wep:GetNextSecondaryFire()
					if ns > ct then wep:SetNextSecondaryFire(ct + (ns - ct) / speed) end
					ply.jcms_qdBoosted = true
				elseif not isReload and ply.jcms_qdBoosted then
					vm:SetPlaybackRate(1)
					ply.jcms_qdBoosted = nil
				end

				ply.jcms_qdSeq = isReload and seq or nil
				ply.jcms_qdCycle = cycle
				ply.jcms_qdWep = wep
			elseif ply.jcms_qdBoosted and IsValid(vm) then
				vm:SetPlaybackRate(1)
				ply.jcms_qdBoosted = nil
			end
		end
	end)

	-- Deadeye
	local function findTargets(ply)
		local eye = ply:EyePos()
		local aim = ply:GetAimVector()
		local list = {}

		for i, ent in ipairs(ents.FindInSphere(eye, R.autoAimRange)) do
			if isEnemyNPC(ent) then
				local pos = ent:WorldSpaceCenter()
				local dir = pos - eye
				local dist = dir:Length()
				dir:Normalize()
				local dot = dir:Dot(aim)
				if dot >= R.autoAimCone then
					local tr = util.TraceLine({ start = eye, endpos = pos, filter = { ply, ent }, mask = MASK_SHOT_HULL })
					local blocker = tr.Entity
					if not tr.Hit or (IsValid(blocker) and (blocker:IsNPC() or blocker:IsNextBot() or blocker:IsPlayer())) then
						table.insert(list, { ent = ent, dot = dot, dist = dist })
					end
				end
			end
		end

		-- Closest to your crosshair first
		table.sort(list, function(a, b) return a.dot > b.dot end)
		local out = {}
		for i = 1, math.min(#list, S.Tune(ply, "autoAimMaxTargets", R.autoAimMaxTargets)) do out[i] = list[i].ent end
		return out
	end

	local function aimPoint(ent)
		local bone = ent:LookupBone("ValveBiped.Bip01_Head1")
		local pos = bone and ent:GetBonePosition(bone)
		return (pos and pos ~= ent:GetPos()) and pos or ent:WorldSpaceCenter()
	end

	local function shoot(ply, ent)
		if not (IsValid(ply) and ply:Alive() and isEnemyNPC(ent)) then return end
		local wep = ply:GetActiveWeapon()
		local target = aimPoint(ent)

		ply:SetEyeAngles((target - ply:EyePos()):Angle())

		-- Tracer + muzzle sound
		local ed = EffectData()
		ed:SetStart(ply:GetShootPos() + ply:GetRight() * 6 - Vector(0, 0, 4))
		ed:SetOrigin(target)
		ed:SetScale(6000)
		util.Effect("Tracer", ed)
		local snd = IsValid(wep) and wep.Primary and type(wep.Primary.Sound) == "string" and wep.Primary.Sound or "weapons/357/357_fire2.wav"
		ply:EmitSound(snd, 90, 100)
		ply:ViewPunch(Angle(-2, 0, 0))

		local boss = ent:GetMaxHealth() >= R.autoAimBossHealth
		local dmg = DamageInfo()
		dmg:SetAttacker(ply)
		dmg:SetInflictor(IsValid(wep) and wep or ply)
		dmg:SetDamageType(DMG_BULLET)
		dmg:SetDamagePosition(target)
		dmg:SetDamageForce((target - ply:EyePos()):GetNormalized() * 8000)
		dmg:SetDamage(boss and S.Tune(ply, "autoAimBossDamage", R.autoAimBossDamage) or (math.max(ent:Health(), ent:GetMaxHealth()) * 4 + 200))
		ply.sweeperAutoAimShot = true
		ent:TakeDamageInfo(dmg)
		ply.sweeperAutoAimShot = nil
	end

	S.abilities.gunslinger.activate = function(ply)
		local targets = findTargets(ply)
		if #targets == 0 then
			return false, "Deadeye: no enemies on your screen."
		end

		net.Start("sweeper_autoaim")
			net.WriteEntity(ply)
			net.WriteFloat(CurTime() + R.autoAimLockTime + #targets * R.autoAimShotDelay + 0.3)
			net.WriteUInt(#targets, 8)
			for i, ent in ipairs(targets) do net.WriteEntity(ent) end
		net.Send(ply)
		ply:EmitSound("buttons/blip2.wav", 70, 140)

		for i, ent in ipairs(targets) do
			timer.Simple(R.autoAimLockTime + (i - 1) * R.autoAimShotDelay, function()
				shoot(ply, ent)
			end)
		end
		return true
	end
end

if CLIENT then
	local locks, lockUntil = {}, 0
	net.Receive("sweeper_autoaim", function()
		net.ReadEntity()
		lockUntil = net.ReadFloat()
		locks = {}
		for i = 1, net.ReadUInt(8) do locks[i] = net.ReadEntity() end
		surface.PlaySound("buttons/blip2.wav")
	end)

	-- Deadeye lock-on brackets (HUD main colour, dark outline like the gamemode's markers)
	local function bracket(x, y, s, len, t)
		surface.DrawRect(x - s, y - s, len, t) surface.DrawRect(x - s, y - s, t, len)
		surface.DrawRect(x + s - len, y - s, len, t) surface.DrawRect(x + s - t, y - s, t, len)
		surface.DrawRect(x - s, y + s - t, len, t) surface.DrawRect(x - s, y + s - len, t, len)
		surface.DrawRect(x + s - len, y + s - t, len, t) surface.DrawRect(x + s - t, y + s - len, t, len)
	end
	S.AddHud("deadeyeLocks", "2d", function(ply)
		if CurTime() >= lockUntil then return end
		local pulse = (math.sin(RealTime() * 20) + 1) / 2
		local col, dark = jcms.color_bright, jcms.color_dark
		for i, ent in ipairs(locks) do
			if IsValid(ent) and ent:Health() > 0 then
				local sp = ent:WorldSpaceCenter():ToScreen()
				if sp.visible then
					local s = 18 + pulse * 4
					surface.SetDrawColor(dark)
					bracket(sp.x + 1, sp.y + 1, s, 9, 2)
					surface.SetDrawColor(col)
					bracket(sp.x, sp.y, s, 9, 2)
					S.HudMarkerText("LOCKED", "jcms_small_bolder", sp.x, sp.y + s + 3, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end
			end
		end
	end)
end
-- }}}

-- // Stalker: Weak Point (perk) + One Shot, One Kill (ability) {{{
S.abilities.stalker = { name = "One Shot, One Kill", cooldown = R.oneShotCooldown }

local function enemyNPC(ent)
	return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and (not jcms.team_NPC or jcms.team_NPC(ent))
end

if SERVER then
	util.AddNetworkString("sweeper_execute")

	S.abilities.stalker.activate = function(ply)
		ply:SetNWFloat("sweeper_oneShotUntil", CurTime() + R.oneShotDuration)
		ply:EmitSound("weapons/sniper/sniper_zoomin.wav", 70, 90)
		ply:EmitSound("buttons/blip2.wav", 60, 70)
		return true
	end

	local function oneShotActive(ply)
		return IsValid(ply) and ply:IsPlayer() and ply:GetNWFloat("sweeper_oneShotUntil", 0) > CurTime()
	end

	hook.Add("EntityTakeDamage", "sweeper_stalker", function(ent, dmg)
		if not enemyNPC(ent) then return end
		local attacker = dmg:GetAttacker()
		if IsValid(attacker) and not attacker:IsPlayer() and IsValid(attacker.jcms_owner) then attacker = attacker.jcms_owner end
		if not (IsValid(attacker) and attacker:IsPlayer()) then return end
		local ct = CurTime()

		-- Weak Point: bonus damage for the marker's team
		if ent:GetNWFloat("sweeper_weakUntil", 0) > ct then
			local markTeam = ent:GetNWInt("sweeper_weakTeam", -1)
			local myTeam = attacker:GetNWInt("jcms_pvpTeam", -1)
			if markTeam == -1 or myTeam == -1 or markTeam == myTeam then
				dmg:ScaleDamage(R.weakPointDamageMul)
			end
		end

		-- Stalker hits mark (or refresh) the weak point
		if S.PlayerHasSpec(attacker, "stalker") then
			ent:SetNWFloat("sweeper_weakUntil", ct + R.weakPointDuration)
			ent:SetNWInt("sweeper_weakTeam", attacker:GetNWInt("jcms_pvpTeam", -1))
		end

		-- One Shot, One Kill: execute wounded enemies, reset the timer
		if oneShotActive(attacker) and dmg:GetAttacker() == attacker then
			local maxHP = math.max(ent:GetMaxHealth(), 1)
			local boss = maxHP >= R.autoAimBossHealth
			if ent:Health() <= maxHP * S.Tune(attacker, "oneShotThreshold", R.oneShotThreshold) and not (boss and R.oneShotBossImmune) then
				dmg:SetDamage(math.max(ent:Health(), maxHP) * 4 + 200)
				attacker:SetNWFloat("sweeper_oneShotUntil", ct + R.oneShotDuration)
				attacker:EmitSound("player/headshot" .. math.random(1, 2) .. ".wav", 75, 90)
				net.Start("sweeper_execute")
					net.WriteVector(ent:WorldSpaceCenter())
				net.Send(attacker)
			end
		end
	end)

	hook.Add("MapSweepersClassApplied", "sweeper_oneShotReset", function(ply)
		ply:SetNWFloat("sweeper_oneShotUntil", 0)
	end)
end

if CLIENT then
	local popups = {}
	net.Receive("sweeper_execute", function()
		table.insert(popups, { pos = net.ReadVector(), t = CurTime() })
	end)

	S.AddHud("stalkerMarkers", "2d", function(me)
		local ct = CurTime()
		local weakCol = jcms.color_alert1
		local myTeam = me:GetNWInt("jcms_pvpTeam", -1)

		-- Weak Point markers (small diamond over marked enemies)
		for i, ent in ipairs(ents.FindInSphere(me:GetPos(), 4000)) do
			if (ent:IsNPC() or ent:IsNextBot()) and ent:GetNWFloat("sweeper_weakUntil", 0) > ct and ent:Health() > 0 then
				local markTeam = ent:GetNWInt("sweeper_weakTeam", -1)
				if markTeam == -1 or myTeam == -1 or markTeam == myTeam then
					local sp = (ent:WorldSpaceCenter() + Vector(0, 0, ent:OBBMaxs().z * 0.55)):ToScreen()
					if sp.visible then
						local r = 7
						draw.NoTexture()
						surface.SetDrawColor(weakCol)
						surface.DrawPoly({ { x = sp.x, y = sp.y - r }, { x = sp.x + r, y = sp.y }, { x = sp.x, y = sp.y + r }, { x = sp.x - r, y = sp.y } })
						surface.SetDrawColor(jcms.color_dark)
						surface.DrawPoly({ { x = sp.x, y = sp.y - 3 }, { x = sp.x + 3, y = sp.y }, { x = sp.x, y = sp.y + 3 }, { x = sp.x - 3, y = sp.y } })
					end
				end
			end
		end

		-- One Shot, One Kill: "EXECUTED" popups + a thin tint while active
		for i = #popups, 1, -1 do
			local p = popups[i]
			local age = ct - p.t
			if age > 1.2 then
				table.remove(popups, i)
			else
				local sp = p.pos:ToScreen()
				if sp.visible then
					local a = surface.GetAlphaMultiplier()
					surface.SetAlphaMultiplier(a * (1 - age / 1.2))
					S.HudMarkerText("EXECUTED", "jcms_medium", sp.x, sp.y - age * 40, jcms.color_bright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					surface.SetAlphaMultiplier(a)
				end
			end
		end
	end)

	S.AddHud("oneShotTint", "tint", function(me)
		if me:GetNWFloat("sweeper_oneShotUntil", 0) > CurTime() then
			S.HudTint(jcms.color_alert2, 10)
		end
	end)
end
-- }}}
