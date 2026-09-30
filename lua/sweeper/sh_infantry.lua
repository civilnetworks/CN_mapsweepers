--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Infantry specialization mechanics.

	T1 Commando         Regain 1 grenade every 45s (up to 3 carried).
	T1 Ranger           Long-range kills refill half a magazine into your reserve ammo.
	T2 Grenadier        (stats only)
	T2 Quartermaster    Drops an ammo pack at your feet every 60s during a mission.
	T3 Field Commander  Rally aura: nearby allies deal +10% damage and regain 2 shield/s.
	T3 Shock Trooper    Kills stack +3% damage (max 10 stacks, reset 8s after your last kill).
	                    Dropping below 30% HP triggers Adrenaline: +25% speed, -25% damage taken for 5s (60s cooldown).

	Tuning values are in S.infantry below.
--]]

local S = sweeper

S.infantry = {
	commandoGrenadeInterval = 45,
	commandoMaxGrenades = 6,
	commandoGrenadeRegen = false, -- old Commando perk (1 grenade per interval); Combat Cocktail replaced it

	rangerRefillFrac = 0.5,        -- of a full magazine

	scavengerAmmoCash = 60,        -- Scavenger implant: ammo worth this much "ammo cash" per box (a full restock box is 400)
	scavengerBoxLife = 30,         -- seconds before an untouched box disappears

	qmInterval = 60,
	qmAmmoCash = 200,

	commanderRadius = 300,
	commanderDamageMul = 1.10,
	commanderShieldPerSec = 2,

	shockStackDamage = 0.03,
	shockMaxStacks = 10,
	shockStackDuration = 8,
	adrenalineThreshold = 0.30,
	adrenalineDuration = 5,
	adrenalineCooldown = 60,
	adrenalineSpeedMul = 1.25,
	adrenalineDamageTaken = 0.75,

	-- Abilities
	breachCooldown = 30,          -- Commando: Combat Stim (cooldown kept under the old name)
	breachGrenades = 3,           -- unused now the ability is Combat Stim; left for the Bandolier upgrade's old saves
	breachBuffDuration = 5,
	commandoStimDuration = 15,    -- Commando: base Combat Stim duration
	commandoStimCount = 1,        -- ...and how many random stims it rolls (Overdose adds more)
	cocktailDamagePerStim = 0.03, -- Combat Cocktail perk: +3% damage per stim running on you
	breachDamageMul = 1.30,

	focusCooldown = 40,           -- Ranger: Marksman's Focus
	focusDuration = 8,
	focusRangeDamageMul = 1.50,   -- at long range (S.rangeDmgDistance)
	focusZoom = 0.8,              -- FOV multiplier while focused

	clusterBomblets = 3,          -- Grenadier perk: Cluster Charge
	clusterDamage = 30,
	clusterRadius = 130,
	clusterMinDamage = 25,        -- explosion must do at least this much to split
	blastWalkerHeal = 0.25,       -- Grenadier perk: your own blasts heal you for this much of their damage

	barrageCooldown = 40,         -- Grenadier: Airburst Barrage
	barrageShells = 5,
	barrageDamage = 90,
	barrageRadius = 220,
	barrageSpread = 220,
	barrageDelay = 0.35,
	barrageRange = 5000,

	resupplyCooldown = 60,        -- Quartermaster: Resupply Drop
	resupplyRadius = 450,
	resupplyMags = 3,             -- magazines of reserve ammo per weapon

	battleCryCooldown = 50,       -- Field Commander: Battle Cry
	battleCryDuration = 8,
	battleCryRadius = 600,
	battleCryDamageMul = 1.25,
	battleCryFireRate = 1.25,

	overdriveCooldown = 40,       -- Shock Trooper: Overdrive
	overdriveDuration = 5,
	overdrivePerKill = 1,         -- seconds added per kill while active
	overdriveMax = 12,
}

local I = S.infantry

-- // Scavenger implant: ammo boxes dropped by kills {{{
-- Walk over it (or press E) to grab it. Any sweeper can take it; it gives ammo for the guns you carry,
-- using the gamemode's own restock logic (jcms.util_TryGiveAmmo).
do
	local ENT = {}
	ENT.Type = "anim"
	ENT.Base = "base_anim"
	ENT.PrintName = "Ammo Box"
	ENT.Spawnable = false

	function ENT:Initialize()
		self:SetModel("models/items/boxmrounds.mdl")
		if SERVER then
			self:PhysicsInit(SOLID_VPHYSICS)
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			self:SetUseType(SIMPLE_USE)
			self:SetTrigger(true)
			self:UseTriggerBounds(true, 24)
			local phys = self:GetPhysicsObject()
			if IsValid(phys) then phys:Wake() end
			self.jcms_dieAt = CurTime() + I.scavengerBoxLife
		end
	end

	if SERVER then
		function ENT:TryGive(ply)
			if self.jcms_taken or not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return end
			if jcms and jcms.team_JCorp_player and not jcms.team_JCorp_player(ply) then return end
			if not (jcms and jcms.util_TryGiveAmmo) then return end
			if jcms.util_TryGiveAmmo(ply, I.scavengerAmmoCash) then
				self.jcms_taken = true
				self:EmitSound("items/ammopickup.wav", 70, 110)
				self:Remove()
			end
		end
		function ENT:StartTouch(ent) self:TryGive(ent) end
		function ENT:Use(activator) self:TryGive(activator) end
		function ENT:Think()
			if CurTime() > (self.jcms_dieAt or math.huge) then self:Remove() return end
			self:NextThink(CurTime() + 1)
			return true
		end
	else
		function ENT:Draw()
			self:DrawModel()
		end
	end

	scripted_ents.Register(ENT, "sweeper_ammodrop")
end

if SERVER then
	hook.Add("MapSweepersDeathNPC", "sweeper_scavengerAmmo", function(npc, attacker)
		if not (IsValid(npc) and IsValid(attacker) and attacker:IsPlayer()) then return end
		local t = S.GetPlayerTotals and S.GetPlayerTotals(attacker)
		local chance = t and t.ammoDrop or 0
		if chance <= 0 or math.random() >= chance then return end
		local box = ents.Create("sweeper_ammodrop")
		if not IsValid(box) then return end
		box:SetPos(npc:WorldSpaceCenter() + Vector(0, 0, 12))
		box:SetAngles(Angle(0, math.random(0, 359), 0))
		box:Spawn()
		local phys = box:GetPhysicsObject()
		if IsValid(phys) then phys:SetVelocity(VectorRand() * 60 + Vector(0, 0, 120)) end
	end)
end
-- }}}

local function alive(ply)
	return ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE
end

-- // Infantry ammo conservation: switch it off when you stop being Infantry {{{
-- Not one of our perks - this is the Infantry class's own ~50% ammo conservation
-- (classes/types/infantry.lua). For a scripted weapon it REPLACES the weapon's TakePrimaryAmmo /
-- TakeAmmo with a version that rolls to skip the ammo, and stamps wep.jcms_infantryOwner = ply.
-- That replacement only undoes itself when the weapon changes hands (owner ~= jcms_infantryOwner),
-- so swapping Infantry for another class while keeping the gun left the conservation running on
-- the new class for the life of that weapon.
--
-- The fix is the gamemode's own escape hatch rather than an edit: clear the stamp, then call the
-- patched function once with 0. It takes the "someone else owns this" branch, which puts the
-- original function back and returns 0 - after that the weapon is stock again. Clearing the stamp
-- alone would leave the patch in place until the next shot, and a swap back to Infantry would then
-- wrap the patched function a second time.
local function clearAmmoConservation(ply)
	if not (IsValid(ply) and ply:IsPlayer()) then return end

	for i, wep in ipairs(ply:GetWeapons()) do
		if IsValid(wep) and wep.jcms_infantryOwner == ply then
			wep.jcms_infantryOwner = nil

			-- TFA and the generic path patch TakePrimaryAmmo, Serious Sam weapons patch TakeAmmo
			if isfunction(wep.TakePrimaryAmmo) then pcall(wep.TakePrimaryAmmo, wep, 0) end
			if isfunction(wep.TakeAmmo) then pcall(wep.TakeAmmo, wep, 0) end
		end

		-- Vanilla weapons conserve through class.Think and this counter instead; it stops with the
		-- class, but a stale value would restore one clip's worth on the way out.
		if IsValid(wep) then wep.lastClip1 = nil end
	end
end
S.ClearAmmoConservation = clearAmmoConservation

if SERVER then
	hook.Add("MapSweepersClassApplied", "sweeper_infantryAmmoCleanup", function(ply, class)
		if class ~= "infantry" then clearAmmoConservation(ply) end
	end)
else
	-- The client patches its own copy of the weapon (class.Think runs for the local player), and
	-- class_Apply is server-side, so the class change is picked up from the networked class here.
	hook.Add("Think", "sweeper_infantryAmmoCleanup", function()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end

		local class = ply:GetNWString("jcms_class", "")
		if class == ply.sweeperAmmoClass then return end
		ply.sweeperAmmoClass = class
		if class ~= "infantry" then clearAmmoConservation(ply) end
	end)
end
-- }}}

if SERVER then
	-- // Commando: grenade regen {{{
	-- REPLACED by the Combat Cocktail perk. Kept behind a flag rather than deleted: flip
	-- S.infantry.commandoGrenadeRegen to true to bring the old perk back alongside it.
	SetGlobalFloat("sweeper_commandoNext", CurTime() + I.commandoGrenadeInterval)
	timer.Create("sweeper_commandoGrenades", I.commandoGrenadeInterval, 0, function()
		if not I.commandoGrenadeRegen then return end
		SetGlobalFloat("sweeper_commandoNext", CurTime() + I.commandoGrenadeInterval)
		for i, ply in ipairs(player.GetAll()) do
			if alive(ply) and S.PlayerHasSpec(ply, "commando") and ply:GetAmmoCount("Grenade") < I.commandoMaxGrenades then
				if not ply:HasWeapon("weapon_frag") then
					-- The gamemode deletes weapons given without this flag *during* Give, which crashes the game
					local old = ply.jcms_canGetWeapons
					ply.jcms_canGetWeapons = true
					ply:Give("weapon_frag", true)
					ply.jcms_canGetWeapons = old
				end
				ply:GiveAmmo(1, "Grenade")
			end
		end
	end)
	-- }}}

	-- // Ranger: long-range kill ammo refill + Shock Trooper stacks {{{
	hook.Add("MapSweepersDeathNPC", "sweeper_infantryKills", function(npc, attacker)
		if not (IsValid(attacker) and attacker:IsPlayer()) then return end

		if S.PlayerHasSpec(attacker, "ranger") and IsValid(npc)
			and attacker:GetPos():DistToSqr(npc:GetPos()) > S.rangeDmgDistance ^ 2 then
			local wep = attacker:GetActiveWeapon()
			local ammoType = IsValid(wep) and wep:GetPrimaryAmmoType() or -1
			if ammoType >= 0 and wep:GetMaxClip1() > 0 then
				attacker:GiveAmmo(math.max(1, math.floor(wep:GetMaxClip1() * I.rangerRefillFrac)), ammoType, true)
			end
		end

		if S.PlayerHasSpec(attacker, "shocktrooper") then
			local stacks = attacker:GetNWInt("sweeper_shockStacks", 0)
			attacker:SetNWInt("sweeper_shockStacks", math.min(stacks + 1, S.Tune(attacker, "shockMaxStacks", I.shockMaxStacks)))
			attacker:SetNWFloat("sweeper_shockExpire", CurTime() + I.shockStackDuration)
		end
	end)
	-- }}}

	-- // Quartermaster: ammo pack drops {{{
	SetGlobalFloat("sweeper_qmNext", CurTime() + I.qmInterval)
	timer.Create("sweeper_quartermaster", I.qmInterval, 0, function()
		SetGlobalFloat("sweeper_qmNext", CurTime() + I.qmInterval)
		if not jcms.director or jcms.director.gameover then return end
		for i, ply in ipairs(player.GetAll()) do
			if alive(ply) and S.PlayerHasSpec(ply, "quartermaster") then
				-- Straight into your reserves rather than a box on the floor. util_TryGiveAmmo is
				-- what the restock crate itself uses, so the amount per tick is unchanged.
				if jcms.util_TryGiveAmmo and jcms.util_TryGiveAmmo(ply, I.qmAmmoCash) then
					ply:EmitSound("items/ammo_pickup.wav", 70, 110)
				end
			end
		end
	end)
	-- }}}

	-- // Field Commander: rally aura {{{
	timer.Create("sweeper_commanderAura", 0.5, 0, function()
		local commanders = {}
		for i, ply in ipairs(player.GetAll()) do
			local isCmd = alive(ply) and S.PlayerHasSpec(ply, "fieldcommander")
			if isCmd then commanders[#commanders + 1] = ply end
			if ply:GetNWBool("sweeper_commanding", false) ~= isCmd then
				ply:SetNWBool("sweeper_commanding", isCmd)
			end
		end

		for i, ally in ipairs(player.GetAll()) do
			local rallied = false
			if alive(ally) then
				for j, cmd in ipairs(commanders) do
					if cmd ~= ally and jcms.team_SameTeam(cmd, ally)
						and cmd:GetPos():DistToSqr(ally:GetPos()) <= I.commanderRadius ^ 2 then
						rallied = true
						break
					end
				end
			end
			if ally:GetNWBool("sweeper_rallied", false) ~= rallied then
				ally:SetNWBool("sweeper_rallied", rallied)
			end
		end
	end)

	timer.Create("sweeper_commanderShield", 1, 0, function()
		for i, ply in ipairs(player.GetAll()) do
			if alive(ply) and ply:GetNWBool("sweeper_rallied", false) and ply:Armor() < ply:GetMaxArmor() then
				ply:SetArmor(math.min(ply:Armor() + I.commanderShieldPerSec, ply:GetMaxArmor()))
			end
		end
	end)
	-- }}}

	-- // Damage: rally bonus, shock stacks, adrenaline {{{
	hook.Add("EntityTakeDamage", "sweeper_infantryDamage", function(ent, dmg)
		local attacker = dmg:GetAttacker()
		if IsValid(attacker) and attacker:IsPlayer() and ent ~= attacker and not ent:IsPlayer() then
			local mul = 1
			if attacker:GetNWBool("sweeper_rallied", false) then
				mul = mul * I.commanderDamageMul
			end
			local stacks = attacker:GetNWInt("sweeper_shockStacks", 0)
			if stacks > 0 then
				mul = mul * (1 + stacks * I.shockStackDamage)
			end
			if mul ~= 1 then dmg:ScaleDamage(mul) end
		end

		if ent:IsPlayer() and ent:GetNWFloat("sweeper_adrenalineUntil", 0) > CurTime() then
			dmg:ScaleDamage(I.adrenalineDamageTaken)
		end
	end)

	hook.Add("PostEntityTakeDamage", "sweeper_adrenaline", function(ent)
		if not (IsValid(ent) and ent:IsPlayer() and ent:Alive()) then return end
		if ent:Health() > ent:GetMaxHealth() * I.adrenalineThreshold then return end
		if CurTime() < (ent.sweeperAdrenalineReadyAt or 0) then return end
		if not S.PlayerHasSpec(ent, "shocktrooper") then return end

		ent.sweeperAdrenalineReadyAt = CurTime() + I.adrenalineCooldown
		ent:SetNWFloat("sweeper_adrenalineReady", ent.sweeperAdrenalineReadyAt)
		ent:SetNWFloat("sweeper_adrenalineUntil", CurTime() + I.adrenalineDuration)
		ent:EmitSound("player/heartbeat1.wav", 75, 130)
		ent:EmitSound("items/suitchargeok1.wav", 70, 80)
	end)

	-- Shock stacks run out
	timer.Create("sweeper_shockDecay", 0.5, 0, function()
		local ct = CurTime()
		for i, ply in ipairs(player.GetAll()) do
			if ply:GetNWInt("sweeper_shockStacks", 0) > 0 and ct > ply:GetNWFloat("sweeper_shockExpire", 0) then
				ply:SetNWInt("sweeper_shockStacks", 0)
			end
		end
	end)

	hook.Add("MapSweepersClassApplied", "sweeper_infantryReset", function(ply)
		ply:SetNWInt("sweeper_shockStacks", 0)
		ply:SetNWFloat("sweeper_adrenalineUntil", 0)
		ply.sweeperAdrenalineReadyAt = 0
		ply:SetNWFloat("sweeper_adrenalineReady", 0)
	end)
	-- }}}
end

-- Adrenaline speed (shared so movement is predicted)
hook.Add("SetupMove", "sweeper_adrenalineMove", function(ply, mv, cmd)
	if ply:GetNWFloat("sweeper_adrenalineUntil", 0) > CurTime() then
		mv:SetMaxSpeed(mv:GetMaxSpeed() * I.adrenalineSpeedMul)
		mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * I.adrenalineSpeedMul)
	end
end)

-- // Client visuals {{{
if CLIENT then
	-- Shock / Adrenaline / Rally icons are drawn in cl_hudicons.lua; this just tints the screen.
	S.AddHud("adrenalineTint", "tint", function(ply)
		if ply:GetNWFloat("sweeper_adrenalineUntil", 0) > CurTime() then
			S.HudTint(jcms.color_alert1, 14)
		end
	end)

	-- Field Commander's aura range as a gold ring
	hook.Add("PostDrawTranslucentRenderables", "sweeper_commanderRing", function(depth, skybox)
		if skybox then return end
		local me = LocalPlayer()
		for i, ply in ipairs(player.GetAll()) do
			if ply:Alive() and ply:GetNWBool("sweeper_commanding", false)
				and ply:GetPos():DistToSqr(me:GetPos()) < 2500 ^ 2 then
				cam.Start3D2D(ply:GetPos() + Vector(0, 0, 3), Angle(0, 0, 0), 1)
					surface.DrawCircle(0, 0, I.commanderRadius, 255, 210, 80, 70)
				cam.End3D2D()
			end
		end
	end)
end
-- }}}

-- // Infantry abilities + Grenadier perk {{{
S.abilities.commando       = { name = "Combat Stim",       cooldown = I.breachCooldown }
S.abilities.ranger         = { name = "Marksman's Focus",  cooldown = I.focusCooldown }
S.abilities.grenadier      = { name = "Airburst Barrage",  cooldown = I.barrageCooldown }
S.abilities.quartermaster  = { name = "Resupply Drop",     cooldown = I.resupplyCooldown }
S.abilities.fieldcommander = { name = "Battle Cry",        cooldown = I.battleCryCooldown }
S.abilities.shocktrooper   = { name = "Overdrive",         cooldown = I.overdriveCooldown }

local function until_(ply, nw) return IsValid(ply) and ply:IsPlayer() and ply:GetNWFloat(nw, 0) > CurTime() end

if SERVER then
	local function isEnemy(ent)
		return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and jcms.team_NPC(ent)
	end

	local function aimTrace(ply, range)
		return util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * range, filter = ply, mask = MASK_SHOT })
	end

	-- Our own blasts (bomblets, barrage) never hurt players
	S.friendlyBlast = false
	local function blast(pos, attacker, dmg, radius)
		local ed = EffectData()
		ed:SetOrigin(pos)
		util.Effect("Explosion", ed, true, true)
		S.friendlyBlast = true
		util.BlastDamage(IsValid(attacker) and attacker or game.GetWorld(), IsValid(attacker) and attacker or game.GetWorld(), pos, radius, dmg)
		S.friendlyBlast = false
	end

	hook.Add("EntityTakeDamage", "sweeper_infantryAbilities", function(ent, dmg)
		if S.friendlyBlast and ent:IsPlayer() then return true end

		local attacker = dmg:GetAttacker()
		local isBlast = dmg:IsDamageType(DMG_BLAST)

		-- Grenadier: Blast Walker (your own explosions heal instead of hurting)
		if ent:IsPlayer() and attacker == ent and isBlast and S.PlayerHasSpec(ent, "grenadier") then
			ent:SetHealth(math.min(ent:GetMaxHealth(), ent:Health() + math.ceil(dmg:GetDamage() * I.blastWalkerHeal)))
			return true
		end

		if not (IsValid(attacker) and attacker:IsPlayer()) or ent:IsPlayer() then return end
		local mul = 1

		if until_(attacker, "sweeper_breachUntil") then mul = mul * I.breachDamageMul end
		if until_(attacker, "sweeper_battleCryUntil") then mul = mul * I.battleCryDamageMul end
		if until_(attacker, "sweeper_focusUntil")
			and attacker:GetPos():DistToSqr(ent:GetPos()) > S.rangeDmgDistance ^ 2 then
			mul = mul * S.Tune(attacker, "focusRangeDamageMul", I.focusRangeDamageMul)
		end

		-- Commando perk, Combat Cocktail: every stim running on you adds damage. Counts stims from
		-- any source - the ability, a Stim Crate box, a teammate's drop.
		if S.PlayerHasSpec(attacker, "commando") then
			local stims = S.CountStims and S.CountStims(attacker) or 0
			if stims > 0 then
				mul = mul * (1 + stims * I.cocktailDamagePerStim)
			end
		end

		if mul ~= 1 then dmg:ScaleDamage(mul) end

		-- Grenadier: Cluster Charge (your explosions split into bomblets, once per explosion)
		if isBlast and not S.friendlyBlast and isEnemy(ent) and dmg:GetDamage() >= I.clusterMinDamage
			and S.PlayerHasSpec(attacker, "grenadier") then
			local inflictor = dmg:GetInflictor()
			local key = IsValid(inflictor) and inflictor:EntIndex() or 0
			local ct = CurTime()
			attacker.sweeperClusters = attacker.sweeperClusters or {}
			if (attacker.sweeperClusters[key] or 0) < ct then
				attacker.sweeperClusters[key] = ct + 1
				local center = dmg:GetDamagePosition()
				if center:IsZero() then center = ent:WorldSpaceCenter() end
				for b = 1, S.Tune(attacker, "clusterBomblets", I.clusterBomblets) do
					timer.Simple(0.25 + b * 0.15, function()
						local offset = VectorRand() * math.Rand(60, 150)
						offset.z = math.abs(offset.z) * 0.3
						blast(center + offset, attacker, I.clusterDamage, I.clusterRadius)
					end)
				end
			end
		end
	end)

	-- Battle Cry fire rate (uses the shared fire-rate system in sh_recon.lua)
	S.fireRateSources = S.fireRateSources or {}
	S.fireRateSources.battlecry = function(ply) return until_(ply, "sweeper_battleCryUntil") and I.battleCryFireRate or 1 end

	-- Ranger: no spread while focused
	hook.Add("EntityFireBullets", "sweeper_focusSpread", function(ent, data)
		if until_(ent, "sweeper_focusUntil") then
			data.Spread = Vector(0, 0, 0)
			return true
		end
	end)

	-- // Commando: Combat Stim {{{
	-- Rolls random stims rather than handing out the whole shelf. The Overdose upgrade adds
	-- +1 stim and +15% duration per rank (t_commandoStimCount / t_commandoStimDurationMul).
	S.abilities.commando.activate = function(ply)
		local count = math.floor(S.Tune(ply, "commandoStimCount", I.commandoStimCount))
		-- t_ keys add rather than multiply, so the duration bonus is read off a base of 0.
		local dur = I.commandoStimDuration * (1 + S.Tune(ply, "commandoStimDurationMul", 0))

		local ids = S.RandomStims(count)
		if #ids == 0 then return false, "No stims are configured." end

		-- One chat line for the roll instead of one per stim.
		local quiet = ply.sweeperQuietStims
		ply.sweeperQuietStims = true
		local names = {}
		for i, id in ipairs(ids) do
			if S.GiveStim(ply, id, dur) then
				local st = S.stimById[id]
				names[#names + 1] = st and st.name or id
			end
		end
		ply.sweeperQuietStims = quiet

		if #names == 0 then return false, "Couldn't apply a stim." end

		ply:SetNWFloat("sweeper_commandoStimUntil", CurTime() + dur) -- drives the HUD icon
		ply:EmitSound("items/smallmedkit1.wav", 75, 120)
		ply:ChatPrint(string.format("[Combat Stim] %s (%ds)", table.concat(names, ", "), math.Round(dur)))
		return true
	end
	-- }}}

	-- // Ranger: Marksman's Focus {{{
	S.abilities.ranger.activate = function(ply)
		ply:SetNWFloat("sweeper_focusUntil", CurTime() + S.Tune(ply, "focusDuration", I.focusDuration))
		ply:EmitSound("weapons/sniper/sniper_zoomin.wav", 70, 100)
		return true
	end
	-- }}}

	-- // Grenadier: Airburst Barrage {{{
	S.abilities.grenadier.activate = function(ply)
		local tr = aimTrace(ply, I.barrageRange)
		if not tr.Hit or tr.HitSky then return false, "Airburst Barrage: aim at the ground or a wall." end
		local target = tr.HitPos

		sound.Play("weapons/mortar/mortar_shell_incomming1.wav", target, 90, 100)
		for i = 1, S.Tune(ply, "barrageShells", I.barrageShells) do
			timer.Simple(0.8 + i * I.barrageDelay, function()
				local offset = VectorRand() * math.Rand(0, I.barrageSpread)
				offset.z = 0
				local pos = target + offset
				local down = util.TraceLine({ start = pos + Vector(0, 0, 200), endpos = pos - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY })
				blast((down.Hit and down.HitPos or pos) + Vector(0, 0, 8), ply, I.barrageDamage, I.barrageRadius)
			end)
		end
		return true
	end
	-- }}}

	-- // Quartermaster: Resupply Drop {{{
	S.abilities.quartermaster.activate = function(ply)
		local count = 0
		for i, ally in ipairs(player.GetAll()) do
			if alive(ally) and jcms.team_SameTeam(ply, ally) and ally:GetPos():DistToSqr(ply:GetPos()) <= S.Tune(ply, "resupplyRadius", I.resupplyRadius) ^ 2 then
				for j, wep in ipairs(ally:GetWeapons()) do
					local ammo = wep:GetPrimaryAmmoType()
					if ammo >= 0 then
						local clip = math.max(wep:GetMaxClip1(), 1)
						ally:GiveAmmo(clip * S.Tune(ply, "resupplyMags", I.resupplyMags), ammo, true)
					end
				end
				ally:SetArmor(math.max(ally:Armor(), ally:GetMaxArmor()))
				ally:EmitSound("items/ammo_pickup.wav", 70, 100)
				count = count + 1
			end
		end
		ply:EmitSound("items/ammocrate_open.wav", 80, 100)
		local ed = EffectData()
		ed:SetOrigin(ply:GetPos())
		util.Effect("cball_explode", ed, true, true)
		return true
	end
	-- }}}

	-- // Field Commander: Battle Cry {{{
	S.abilities.fieldcommander.activate = function(ply)
		local untilT = CurTime() + S.Tune(ply, "battleCryDuration", I.battleCryDuration)
		for i, ally in ipairs(player.GetAll()) do
			if alive(ally) and jcms.team_SameTeam(ply, ally) and ally:GetPos():DistToSqr(ply:GetPos()) <= S.Tune(ply, "battleCryRadius", I.battleCryRadius) ^ 2 then
				ally:SetNWFloat("sweeper_battleCryUntil", untilT)
			end
		end
		ply:EmitSound("npc/combine_soldier/vo/overwatchrequestreinforcement.wav", 90, 90)
		ply:EmitSound("ambient/alarms/warningbell1.wav", 80, 120, 0.6)
		return true
	end
	-- }}}

	-- // Shock Trooper: Overdrive {{{
	S.abilities.shocktrooper.activate = function(ply)
		local untilT = CurTime() + I.overdriveDuration
		ply:SetNWFloat("sweeper_adrenalineUntil", untilT)
		ply:SetNWFloat("sweeper_overdriveUntil", untilT)
		ply:EmitSound("player/heartbeat1.wav", 75, 150)
		ply:EmitSound("items/suitchargeok1.wav", 70, 70)
		return true
	end

	hook.Add("MapSweepersDeathNPC", "sweeper_overdriveKill", function(npc, attacker)
		if not until_(attacker, "sweeper_overdriveUntil") then return end
		local ct = CurTime()
		local newUntil = math.min(attacker:GetNWFloat("sweeper_overdriveUntil", ct) + I.overdrivePerKill, ct + S.Tune(attacker, "overdriveMax", I.overdriveMax))
		attacker:SetNWFloat("sweeper_overdriveUntil", newUntil)
		attacker:SetNWFloat("sweeper_adrenalineUntil", newUntil)
	end)
	-- }}}

	hook.Add("MapSweepersClassApplied", "sweeper_infantryAbilityReset", function(ply)
		for i, nw in ipairs({ "breachUntil", "commandoStimUntil", "focusUntil", "battleCryUntil", "overdriveUntil" }) do
			ply:SetNWFloat("sweeper_" .. nw, 0)
		end
	end)
end

if CLIENT then
	-- Marksman's Focus zoom
	local zoom = 1
	hook.Add("CalcView", "sweeper_focusZoom", function(ply, pos, ang, fov)
		local target = until_(ply, "sweeper_focusUntil") and I.focusZoom or 1
		zoom = Lerp(FrameTime() * 8, zoom, target)
		if math.abs(zoom - 1) < 0.001 then return end
		return { fov = fov * zoom }
	end)

	S.AddHud("battleCryTint", "tint", function(ply)
		if until_(ply, "sweeper_battleCryUntil") then
			S.HudTint(jcms.color_alert1, 10)
		end
	end)

	-- Marksman's Focus letterbox (not a colour tint, so it always shows)
	S.AddHud("focusBars", "2d", function(ply)
		if until_(ply, "sweeper_focusUntil") then
			-- thin vignette bars
			surface.SetDrawColor(0, 0, 0, 120)
			surface.DrawRect(0, 0, ScrW(), ScrH() * 0.06)
			surface.DrawRect(0, ScrH() * 0.94, ScrW(), ScrH() * 0.06)
		end
	end)
end
-- }}}
