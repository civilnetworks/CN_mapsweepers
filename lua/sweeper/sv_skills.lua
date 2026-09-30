--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Server: XP, levels, saving, applying bonuses, handling purchases.
--]]

local S = sweeper

util.AddNetworkString("sweeper_sync")
util.AddNetworkString("sweeper_action")
util.AddNetworkString("sweeper_open")

S.cvar_xpmul = CreateConVar("jcms_implant_xpmul", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, "XP multiplier for class levels.", 0, 100)
S.cvar_resetOnGameOver = CreateConVar("jcms_implant_reset_on_gameover", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
	"1 = all class levels, skills and specializations are wiped when the run ends (mission failed). 0 = keep them forever.", 0, 1)
S.resetCount = S.resetCount or 0

S.data = S.data or {}   -- [sid64][class] = { xp = n, level = n, skills = { [id] = rank } }
S.dirty = S.dirty or {} -- [sid64][class] = true

local ACTION_BUY, ACTION_RESPEC, ACTION_SPEC = 1, 2, 3

-- // Storage (sv.db) {{{
sql.Query([[CREATE TABLE IF NOT EXISTS sweeper (
	sid64 TEXT NOT NULL,
	class TEXT NOT NULL,
	xp INTEGER NOT NULL DEFAULT 0,
	level INTEGER NOT NULL DEFAULT 1,
	skills TEXT NOT NULL DEFAULT '{}',
	PRIMARY KEY (sid64, class)
)]])
-- Added for specializations; errors harmlessly if the column already exists.
do
	local hasSpecs = false
	for i, col in ipairs(sql.Query("PRAGMA table_info(sweeper)") or {}) do
		if col.name == "specs" then hasSpecs = true end
	end
	if not hasSpecs then
		sql.Query("ALTER TABLE sweeper ADD COLUMN specs TEXT NOT NULL DEFAULT '{}'")
	end
end

local function blankClassData()
	return { xp = 0, level = 1, skills = {}, specs = {} }
end

-- Keep only valid specialization picks (right tier, level reached, previous tier picked)
local function cleanSpecs(class, level, raw)
	local clean = {}
	for tier = 1, #S.specLevels do
		local id = raw and (raw[tier] or raw[tostring(tier)])
		local spec = id and S.GetSpec(class, id)
		if not (spec and spec.tier == tier and level >= S.specLevels[tier]) then break end
		clean[tier] = id
	end
	return clean
end

-- Specialization upgrades only belong to a picked spec: anything else is refunded (returns how many ranks)
function S.DropUnpickedSpecSkills(class, cd)
	local picked = {}
	for tier, id in pairs(cd.specs or {}) do picked[id] = true end
	local refunded = 0
	for id, rank in pairs(cd.skills or {}) do
		local sk = S.byId[class] and S.byId[class][id]
		if sk and sk.spec and not picked[sk.spec] then
			refunded = refunded + (tonumber(rank) or 0)
			cd.skills[id] = nil
		end
	end
	return refunded
end

function S.Load(ply)
	local sid64 = ply:SteamID64()
	if not sid64 then return end

	local tbl = {}
	for i, class in ipairs(S.classes) do
		tbl[class] = blankClassData()
	end

	local rows = sql.Query("SELECT class, xp, level, skills, specs FROM sweeper WHERE sid64 = " .. sql.SQLStr(sid64))
	if istable(rows) then
		for i, row in ipairs(rows) do
			if tbl[row.class] then
				local skills = util.JSONToTable(row.skills or "{}") or {}
				-- Drop skills that no longer exist / clamp ranks, in case the tree was edited.
				local clean = {}
				for id, rank in pairs(skills) do
					local sk = S.byId[row.class][id]
					if sk then clean[id] = math.Clamp(math.floor(tonumber(rank) or 0), 0, sk.max) end
				end

				local cd = tbl[row.class]
				cd.level = math.Clamp(tonumber(row.level) or 1, 1, S.maxLevel)
				cd.xp = math.max(0, tonumber(row.xp) or 0)
				cd.skills = clean

				-- If the tree was edited and they now have more spent than earned, refund everything.
				if S.ChipsetsAvailable(cd) < 0 then
					cd.skills = {}
				end

				cd.specs = cleanSpecs(row.class, cd.level, util.JSONToTable(row.specs or "{}"))
				S.DropUnpickedSpecSkills(row.class, cd)
			end
		end
	end

	S.data[sid64] = tbl
end

function S.SaveClass(sid64, class)
	local cd = S.data[sid64] and S.data[sid64][class]
	if not cd then return end

	sql.Query(string.format("REPLACE INTO sweeper (sid64, class, xp, level, skills, specs) VALUES (%s, %s, %d, %d, %s, %s)",
		sql.SQLStr(sid64), sql.SQLStr(class), math.floor(cd.xp), math.floor(cd.level),
		sql.SQLStr(util.TableToJSON(cd.skills)), sql.SQLStr(util.TableToJSON(cd.specs or {}))))

	if S.dirty[sid64] then S.dirty[sid64][class] = nil end
end

function S.MarkDirty(sid64, class)
	S.dirty[sid64] = S.dirty[sid64] or {}
	S.dirty[sid64][class] = true
end

function S.SaveAllDirty()
	for sid64, classes in pairs(S.dirty) do
		for class in pairs(classes) do
			S.SaveClass(sid64, class)
		end
	end
	S.dirty = {}
end

timer.Create("sweeper_autosave", 30, 0, S.SaveAllDirty)
hook.Add("ShutDown", "sweeper_save", S.SaveAllDirty)
-- // }}}

-- // Access {{{
function S.GetClassData(ply, class)
	if not IsValid(ply) or ply:IsBot() then return nil end
	local sid64 = ply:SteamID64()
	if not S.data[sid64] then S.Load(ply) end
	return S.data[sid64] and S.data[sid64][class]
end

-- The class whose skills are currently active on this player (nil if none)
function S.GetActiveClass(ply)
	local class = ply:GetNWString("jcms_class", "")
	if S.IsSkillClass(class) and jcms and jcms.team_JCorp_player and jcms.team_JCorp_player(ply) then
		return class
	end
end

function S.Sync(ply)
	if not IsValid(ply) or ply:IsBot() then return end
	local tbl = S.data[ply:SteamID64()]
	if not tbl then return end

	net.Start("sweeper_sync")
		net.WriteTable(tbl)
	net.Send(ply)
end
-- // }}}

-- // Applying bonuses {{{
local function rebuildShieldTimer(ply, data, totals)
	local rate = data.shieldRegen * (1 + (totals.regen or 0))
	local delay = data.shieldDelay * (1 - (totals.delay or 0))
	local timerIdentifier = "jcms_ShieldRegen" .. ply:EntIndex() -- same name as the gamemode's timer, so we replace it

	-- Mirrors the gamemode's own shield regen timer (sh_classes.lua), with our modified rate/delay.
	timer.Create(timerIdentifier, 1 / rate, 0, function()
		if IsValid(ply) and ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE then
			if (ply:Armor() < ply:GetMaxArmor()) and (not ply.jcms_lastDamaged or CurTime() - ply.jcms_lastDamaged > delay) then
				local newValue = ply:Armor() + 1
				ply:SetArmor(newValue)

				if newValue == ply:GetMaxArmor() then
					if not ply:GetNoDraw() then
						local ed = EffectData()
						ed:SetEntity(ply)
						ed:SetFlags(2)
						ed:SetColor(jcms.util_colorIntegerSweeperShield)
						util.Effect("jcms_shieldeffect", ed)
					end
					ply:EmitSound("items/suitchargeok1.wav", 50, 130, 0.5)
				end
			end
		else
			timer.Remove(timerIdentifier)
		end
	end)
end

-- Applies the DIFFERENCE between two stat totals, so buying a rank mid-mission works
-- and other gamemode upgrades to health/shield/etc are left intact.
function S.ApplyDelta(ply, class, old, new)
	local data = jcms.classes[class]
	if not data then return end

	local dHP = (new.hp or 0) - (old.hp or 0)
	if dHP ~= 0 then
		local newMax = math.max(1, ply:GetMaxHealth() + dHP)
		ply:SetMaxHealth(newMax)
		ply:SetHealth(math.Clamp(ply:Health() + math.max(dHP, 0), 1, newMax))
	end

	local dArmor = (new.armor or 0) - (old.armor or 0)
	if dArmor ~= 0 then
		local newMax = math.max(0, ply:GetMaxArmor() + dArmor)
		ply:SetMaxArmor(newMax)
		ply:SetArmor(math.Clamp(ply:Armor() + math.max(dArmor, 0), 0, newMax))
	end

	local speedRatio = (1 + (new.speed or 0)) / (1 + (old.speed or 0))
	if speedRatio ~= 1 then
		ply:SetWalkSpeed(ply:GetWalkSpeed() * speedRatio)
		ply:SetRunSpeed(ply:GetRunSpeed() * speedRatio)
		ply:SetSlowWalkSpeed(ply:GetSlowWalkSpeed() * speedRatio)
	end

	local dJump = (new.jump or 0) - (old.jump or 0)
	if dJump ~= 0 then
		ply:SetJumpPower(ply:GetJumpPower() + dJump)
	end

	local dmgRatio = (1 + (new.dmg or 0)) / (1 + (old.dmg or 0))
	if dmgRatio ~= 1 then
		ply.jcms_dmgMult = (ply.jcms_dmgMult or 1) * dmgRatio
	end

	if (new.regen or 0) ~= (old.regen or 0) or (new.delay or 0) ~= (old.delay or 0) then
		rebuildShieldTimer(ply, data, new)
	end

	ply.sweeperTotals = new
	ply.sweeperClass = class
end

hook.Add("MapSweepersClassApplied", "sweeper_apply", function(ply, class, data)
	ply.sweeperTotals = nil
	ply.sweeperClass = nil
	if not S.IsSkillClass(class) or ply:IsBot() then return end

	-- The gamemode sets health/shield AFTER this hook runs, so wait one tick.
	timer.Simple(0, function()
		if not IsValid(ply) or S.GetActiveClass(ply) ~= class then return end
		local cd = S.GetClassData(ply, class)
		if not cd then return end

		S.ApplyDelta(ply, class, {}, S.ComputeStats(class, cd.skills, cd.specs, ply))
		ply:SetHealth(ply:GetMaxHealth())
		ply:SetArmor(ply:GetMaxArmor())

		if jcms.director then
			ply.sweeperParticipated = class
		end
	end)
end)

-- Recalculate and apply this player's stats right now (used when a stim starts or runs out)
function S.RefreshStats(ply)
	if not (IsValid(ply) and ply:IsPlayer()) then return end
	local class = S.GetActiveClass(ply)
	if not class or ply.sweeperClass ~= class then return end
	local cd = S.GetClassData(ply, class)
	if not cd then return end
	S.ApplyDelta(ply, class, ply.sweeperTotals or {}, S.ComputeStats(class, cd.skills, cd.specs, ply))
end

local function currentTotals(ply)
	if ply.sweeperClass and ply.sweeperClass == S.GetActiveClass(ply) then
		return ply.sweeperTotals
	end
end
S.GetPlayerTotals = currentTotals

local meleeHoldTypes = { melee = true, melee2 = true, knife = true, fist = true }
local pistolHoldTypes = { pistol = true, revolver = true }

local function activeHoldType(ply)
	local wep = ply:GetActiveWeapon()
	return IsValid(wep) and wep:GetHoldType() or ""
end

local function isMeleeDamage(ply, dmg)
	return bit.band(dmg:GetDamageType(), bit.bor(DMG_CLUB, DMG_SLASH)) ~= 0 or meleeHoldTypes[activeHoldType(ply)] == true
end

-- Damage taken / turret damage dealt
hook.Add("EntityTakeDamage", "sweeper_damage", function(ent, dmg)
	-- Resistances
	if ent:IsPlayer() then
		local t = currentTotals(ent)
		if t then
			local mul = 1 - (t.resist or 0)
			if (t.blast or 0) ~= 0 and dmg:IsExplosionDamage() then
				mul = mul * (1 - t.blast)
			end
			if (t.fire or 0) ~= 0 and bit.band(dmg:GetDamageType(), bit.bor(DMG_BURN, DMG_SLOWBURN)) ~= 0 then
				mul = mul * (1 - t.fire)
			end
			if (t.sprintResist or 0) > 0 and ent:GetVelocity():Length2DSqr() > 250 * 250 then
				mul = mul * (1 - t.sprintResist)
			end
			if (t.closeResist or 0) > 0 then
				local src = dmg:GetAttacker()
				if IsValid(src) and src ~= ent and src:GetPos():DistToSqr(ent:GetPos()) < 400 * 400 then
					mul = mul * (1 - t.closeResist)
				end
			end
			if mul ~= 1 then
				dmg:ScaleDamage(math.max(mul, 0.1))
			end
		end
	end

	local attacker, inflictor = dmg:GetAttacker(), dmg:GetInflictor()
	if not (IsValid(attacker) and attacker:IsPlayer()) or ent == attacker then return end
	local t = currentTotals(attacker)
	if not t then return end

	-- Deployables: turrets report their owner as the attacker and themselves as the inflictor.
	local fromDeployable = IsValid(inflictor) and inflictor ~= attacker and not inflictor:IsWeapon() and inflictor.jcms_owner == attacker
	if fromDeployable then
		if (t.deploy or 0) > 0 then dmg:ScaleDamage(1 + t.deploy) end
		return
	end

	local mul = 1
	if dmg:IsExplosionDamage() then
		mul = mul + (t.blastDmg or 0)
	elseif isMeleeDamage(attacker, dmg) then
		mul = mul + (t.meleeDmg or 0)
	else
		if (t.pistolDmg or 0) > 0 and dmg:IsBulletDamage() and pistolHoldTypes[activeHoldType(attacker)] then
			mul = mul + t.pistolDmg
		end
		if (t.rangeDmg or 0) > 0 and attacker:GetPos():DistToSqr(ent:GetPos()) > S.rangeDmgDistance ^ 2 then
			mul = mul + t.rangeDmg
		end
	end
	if (t.crouchDmg or 0) > 0 and attacker:Crouching() then
		mul = mul + t.crouchDmg
	end
	if (t.airDmg or 0) > 0 and not attacker:OnGround() and attacker:WaterLevel() < 2 then
		mul = mul + t.airDmg
	end
	if (t.lowHpDmg or 0) > 0 and attacker:Health() < attacker:GetMaxHealth() * 0.5 then
		mul = mul + t.lowHpDmg
	end
	if mul ~= 1 then dmg:ScaleDamage(mul) end
end)

hook.Add("ScaleNPCDamage", "sweeper_headshot", function(npc, hitgroup, dmg)
	if hitgroup ~= HITGROUP_HEAD then return end
	local attacker = dmg:GetAttacker()
	if not (IsValid(attacker) and attacker:IsPlayer()) then return end
	local t = currentTotals(attacker)
	if t and (t.headshot or 0) > 0 then
		dmg:ScaleDamage(1 + t.headshot)
	end
end)
-- // }}}

-- // XP {{{
function S.AddXP(ply, class, amount, reason)
	local cd = S.GetClassData(ply, class)
	if not cd or cd.level >= S.maxLevel then return end

	local stats = S.ComputeStats(class, cd.skills, cd.specs, ply)
	amount = math.floor(amount * S.cvar_xpmul:GetFloat() * (1 + (stats.xp or 0)))
	if amount <= 0 then return end

	cd.xp = cd.xp + amount
	local oldLevel = cd.level
	while cd.level < S.maxLevel and cd.xp >= S.XPToNext(cd.level) do
		cd.xp = cd.xp - S.XPToNext(cd.level)
		cd.level = cd.level + 1
	end
	if cd.level >= S.maxLevel then cd.xp = 0 end

	S.MarkDirty(ply:SteamID64(), class)

	if cd.level > oldLevel then
		S.SaveClass(ply:SteamID64(), class)
		ply:ChatPrint(string.format("[%s] Level %d reached! +%d %s.", S.classNames[class], cd.level, cd.level - oldLevel,
			(cd.level - oldLevel) == 1 and S.pointName or S.pointNamePlural))
		ply:EmitSound("buttons/button5.wav", 60, 120, 0.6)
	end

	S.Sync(ply)
end

hook.Add("MapSweepersDeathNPC", "sweeper_kill", function(npc, attacker, inflictor)
	if not IsValid(attacker) or not attacker:IsPlayer() then return end
	local class = S.GetActiveClass(attacker)
	if not class then return end
	attacker.sweeperParticipated = class -- counts them for mission-end XP

	local xp = math.Clamp(math.floor((IsValid(npc) and npc:GetMaxHealth() or 50) / 10), 3, 50)
	S.AddXP(attacker, class, xp, "kill")

	local t = currentTotals(attacker)
	if t and attacker:Alive() then
		if (t.killHeal or 0) > 0 then
			S.GrantKillHealth(attacker, t.killHeal)
		end
		if (t.killShield or 0) > 0 then
			S.GrantKillShield(attacker, t.killShield)
		end
		if (t.meleeKillHeal or 0) > 0 and meleeHoldTypes[activeHoldType(attacker)] then
			S.GrantKillHealth(attacker, t.meleeKillHeal)
		end
		if (t.killCash or 0) > 0 then
			attacker:SetNWInt("jcms_cash", attacker:GetNWInt("jcms_cash", 0) + t.killCash)
		end
	end
end)

-- Mission-end XP. jcms.mission_End only exists once the gamemode has loaded.
hook.Add("Initialize", "sweeper_wrapMissionEnd", function()
	if not (jcms and jcms.mission_End) or jcms.skills_missionEndWrapped then return end
	jcms.skills_missionEndWrapped = true

	local original = jcms.mission_End
	function jcms.mission_End(victory, aliveTeams, ...)
		local resetsBefore = S.resetCount
		local rtn = { original(victory, aliveTeams, ...) }

		-- The run just ended and everything was wiped: don't hand out XP into the fresh run.
		if S.resetCount ~= resetsBefore then
			for i, ply in ipairs(player.GetHumans()) do ply.sweeperParticipated = nil end
			return unpack(rtn)
		end

		local ok, err = pcall(function()
			for i, ply in ipairs(player.GetHumans()) do
				local class = ply.sweeperParticipated
				if class then
					local xp = victory and 250 or 75
					if victory and ply:GetNWBool("jcms_evacuated") then
						xp = xp + 100
					end
					S.AddXP(ply, class, xp, "mission")
					ply.sweeperParticipated = nil
				end
			end
		end)
		if not ok then ErrorNoHalt("[sweeper] mission XP error: " .. tostring(err) .. "\n") end

		return unpack(rtn)
	end
end)
-- // }}}

-- // Run reset (game over) {{{
-- Wipes every player's levels, skills and specializations (online and offline).
function S.ResetAll(reason)
	sql.Query("DELETE FROM sweeper")
	S.dirty = {}
	S.resetCount = S.resetCount + 1

	for i, ply in ipairs(player.GetHumans()) do
		local sid64 = ply:SteamID64()
		local old = S.data[sid64]

		-- Remove bonuses from anyone currently alive with skills applied
		local class = ply.sweeperClass
		if class and ply.sweeperTotals and S.GetActiveClass(ply) == class and ply:Alive() then
			S.ApplyDelta(ply, class, ply.sweeperTotals, {})
		end

		S.Load(ply) -- loads blank data since the table is now empty
		ply.sweeperParticipated = nil
		S.Sync(ply)

		if old then
			ply:ChatPrint("[Implants] " .. (reason or "The run is over.") .. " All class levels, " .. S.pointNamePlural .. " and specializations have been reset.")
		end
	end

	if S.GroupReset then S.GroupReset() end
end

-- The gamemode calls jcms.runprogress_Reset() when a mission is failed (winstreak -> 0),
-- and on dedicated servers after being empty for 1.5 hours.
hook.Add("Initialize", "sweeper_wrapRunReset", function()
	if not (jcms and jcms.runprogress_Reset) or jcms.sweeper_runResetWrapped then return end
	jcms.sweeper_runResetWrapped = true

	local original = jcms.runprogress_Reset
	function jcms.runprogress_Reset(...)
		local rtn = { original(...) }

		if S.cvar_resetOnGameOver:GetBool() then
			local ok, err = pcall(S.ResetAll, "Mission failed - the run is over.")
			if not ok then ErrorNoHalt("[sweeper] reset error: " .. tostring(err) .. "\n") end
		end

		return unpack(rtn)
	end
end)

-- Admin: wipe everyone manually
concommand.Add("jcms_implant_resetall", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	S.ResetAll("An admin reset the run.")
	print("[Implants] All class progress wiped.")
end, nil, "Admin: wipe all class levels, skills and specializations for everyone.")
-- // }}}

-- // Networking / player lifecycle {{{
hook.Add("PlayerInitialSpawn", "sweeper_load", function(ply)
	if not ply:IsBot() then S.Load(ply) end
end)

hook.Add("jcms_PlayerNetReady", "sweeper_sync", function(ply)
	S.Sync(ply)
end)

hook.Add("PlayerDisconnected", "sweeper_saveOnLeave", function(ply)
	if ply:IsBot() then return end
	local sid64 = ply:SteamID64()
	if S.dirty[sid64] then
		for class in pairs(S.dirty[sid64]) do S.SaveClass(sid64, class) end
	end
	S.data[sid64] = nil
	S.dirty[sid64] = nil
end)

-- F4 opens the skill tree
hook.Add("ShowSpare2", "sweeper_open", function(ply)
	net.Start("sweeper_open")
	net.Send(ply)
end)

net.Receive("sweeper_action", function(len, ply)
	if not IsValid(ply) then return end
	if (ply.sweeperNextAction or 0) > CurTime() then return end
	ply.sweeperNextAction = CurTime() + 0.15

	local action = net.ReadUInt(2)
	local class = net.ReadString()
	if not S.IsSkillClass(class) then return end

	local cd = S.GetClassData(ply, class)
	if not cd then return end

	local isActive = (S.GetActiveClass(ply) == class) and ply:Alive() and ply.sweeperClass == class
	local oldTotals = S.ComputeStats(class, cd.skills, cd.specs, ply)

	if action == ACTION_BUY then
		local id = net.ReadString()
		local ok, reason = S.CanBuy(class, cd, id)
		if not ok then
			ply:ChatPrint("[Implants] " .. reason)
			return
		end
		cd.skills[id] = (cd.skills[id] or 0) + 1

	elseif action == ACTION_SPEC then
		local tier = net.ReadUInt(2)
		local id = net.ReadString()
		local ok, reason = S.CanPickSpec(class, cd, tier, id, jcms and jcms.director ~= nil)
		if not ok then
			ply:ChatPrint("[Implants] " .. reason)
			return
		end
		cd.specs = cd.specs or {}
		cd.specs[tier] = id
		-- Changing a lower tier doesn't clear higher tiers; they stay valid.
		ply:ChatPrint(string.format("[Implants] %s Tier %d specialization: %s", S.classNames[class], tier, S.GetSpec(class, id).name))
		local refunded = S.DropUnpickedSpecSkills(class, cd)
		if refunded > 0 then
			ply:ChatPrint(string.format("[Implants] Refunded %d %s from the old specialization's upgrades.", refunded,
				refunded == 1 and S.pointName or S.pointNamePlural))
		end

	elseif action == ACTION_RESPEC then
		if S.ChipsetsSpent(cd.skills) == 0 then return end
		cd.skills = {}
		ply:ChatPrint(string.format("[Implants] %s tree reset. All %s refunded.", S.classNames[class], S.pointNamePlural))
	else
		return
	end

	S.SaveClass(ply:SteamID64(), class)

	if isActive then
		S.ApplyDelta(ply, class, oldTotals, S.ComputeStats(class, cd.skills, cd.specs, ply))
	end

	S.Sync(ply)
end)
-- // }}}

-- // Admin tools {{{
-- Logs every hit you take for a few seconds: what hit you, for how much, and whether it landed.
-- Run it, take some fire, then read your console.
concommand.Add("sweeper_damagetrace", function(ply, cmd, args)
	local target = IsValid(ply) and ply or player.GetAll()[1]
	if not IsValid(target) then print("[Implants] No players.") return end
	local secs = math.Clamp(tonumber(args[1]) or 15, 3, 60)

	local id = "sweeper_damagetrace"
	local function say(text)
		if S.PrintConsole then S.PrintConsole(IsValid(ply) and ply or nil, text) else print(text) end
	end

	hook.Add("EntityTakeDamage", id, function(ent, dmg)
		if ent ~= target then return end
		target.jcms_traceIn = { dmg = dmg:GetDamage(), armor = target:Armor(), hp = target:Health() }
	end)
	hook.Add("PostEntityTakeDamage", id, function(ent, dmg, took)
		if ent ~= target then return end
		local before = target.jcms_traceIn or { dmg = dmg:GetDamage(), armor = target:Armor(), hp = target:Health() }
		local attacker = dmg:GetAttacker()
		say(string.format("[dmg] %s (%s) dealt %.1f -> %.1f | took: %s | HP %d->%d  Shield %d->%d",
			IsValid(attacker) and attacker:GetClass() or "world",
			IsValid(attacker) and attacker:IsPlayer() and "player" or "npc/world",
			before.dmg, dmg:GetDamage(), tostring(took),
			before.hp, target:Health(), before.armor, target:Armor()))

		-- If the number arrives at 0, it was multiplied away before we ever saw it. Show the chain.
		if IsValid(attacker) and attacker:IsNPC() and jcms then
			say(string.format("      attacker dmgMult=%s  dontScaleDmg=%s  npc_GetScaledDamage=%s  jcms_damage_mul=%s",
				tostring(attacker.jcms_dmgMult),
				tostring(attacker.jcms_dontScaleDmg),
				tostring(jcms.npc_GetScaledDamage and jcms.npc_GetScaledDamage()),
				tostring(jcms.cvar_damage_mul and jcms.cvar_damage_mul:GetFloat())))
		end

		target.jcms_traceIn = nil
	end)

	timer.Create(id, secs, 1, function()
		hook.Remove("EntityTakeDamage", id)
		hook.Remove("PostEntityTakeDamage", id)
		say("[Implants] Damage trace finished.")
	end)
	say(string.format("[Implants] Tracing damage on %s for %ds. Go get shot, then read this console.", target:Nick(), secs))
end, nil, "Logs incoming damage for a few seconds (Implants addon).")

-- "Why am I not taking damage?" - prints everything in this addon (and the engine) that can block damage.
concommand.Add("sweeper_damageinfo", function(ply, cmd, args)
	local target = ply
	if not IsValid(target) then
		target = player.GetAll()[1]
		if not IsValid(target) then print("[Implants] No players.") return end
	end

	local out = {}
	local function line(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
	line("--- Implants damage check for %s ---", target:Nick())
	line("Health %d / %d, Shield %d / %d", target:Health(), target:GetMaxHealth(), target:Armor(), target:GetMaxArmor())
	line("takedamage flag: %s (0 = the engine is ignoring ALL damage)", tostring(target:GetInternalVariable("m_takedamage")))
	line("God mode: %s", tostring(target:HasGodMode()))
	line("Buddha (sv_cheats): %s", tostring(target:GetInternalVariable("m_debugOverlays")))
	line("No-target (enemies ignore you): %s", tostring(target:GetNWBool("sweeper_cloaked", false) or (target.sweeperDecoyHideUntil or 0) > CurTime()))
	line("  cloaked=%s  decoy hide left=%.1fs", tostring(target.sweeperCloaked), math.max(0, (target.sweeperDecoyHideUntil or 0) - CurTime()))
	line("Second Wind invulnerable for: %.1fs", math.max(0, (target.jcms_modSecondWindUntil or 0) - CurTime()))
	line("Iron Skin %.1fs, Challenge %.1fs, Aegis Dome HP %d",
		math.max(0, target:GetNWFloat("sweeper_ironSkinUntil", 0) - CurTime()),
		math.max(0, target:GetNWFloat("sweeper_challengeUntil", 0) - CurTime()),
		target:GetNWInt("sweeper_domeHP", 0))
	local t = S.GetPlayerTotals and S.GetPlayerTotals(target)
	if t then
		line("Stat totals: resist %.2f, blast %.2f, fire %.2f, sprintResist %.2f, closeResist %.2f",
			t.resist or 0, t.blast or 0, t.fire or 0, t.sprintResist or 0, t.closeResist or 0)
		line("             hp +%d, shield +%d, damage +%d%%", t.hp or 0, t.armor or 0, (t.dmg or 0) * 100)
	else
		line("Stat totals: none (no implant class active)")
	end

	-- Whether the numbers above are the PVE ones or the scaled-down PVP ones
	local pvp = S.PvpScaling and S.PvpScaling()
	if pvp then
		line("PVP scaling: ACTIVE - implants/specs at defense %.0f%%, offense %.0f%%, utility %.0f%%, deploy %.0f%%",
			pvp.defense * 100, pvp.offense * 100, pvp.utility * 100, pvp.deploy * 100)
		line("             caps: resist %.0f%%, close/sprint %.0f%% each", pvp.resistCap * 100, pvp.closeCap * 100)
	else
		line("PVP scaling: off (full implant values - %s)",
			(S.pvpScale and S.pvpScale.enabled) and "not a PVP mission" or "disabled in S.pvpScale")
	end
	line("Class: %s   Mission running: %s", target:GetNWString("jcms_class", "none"), tostring(jcms and jcms.director ~= nil))

	-- Gamemode-side things that can zero NPC damage before any implant ever sees it.
	if jcms then
		local dmgMul = jcms.cvar_damage_mul and jcms.cvar_damage_mul:GetFloat()
		local diff = jcms.runprogress_GetDifficulty and jcms.runprogress_GetDifficulty()
		local scaled = jcms.npc_GetScaledDamage and jcms.npc_GetScaledDamage()
		line("jcms_damage_mul: %s   <- 0 means NPCs can never hurt Sweepers", tostring(dmgMul))
		line("Run difficulty: %s   NPC damage scale: %s   <- 0 here kills all NPC damage too", tostring(diff), tostring(scaled))
		line("jcms_friendlyfire_multiplier: %s", tostring(jcms.cvar_ffmul and jcms.cvar_ffmul:GetFloat()))
	end
	line("Bubble shield (jcms_shield, eats a whole hit each): %d", target:GetNWInt("jcms_shield", 0))
	line("Sweeper shield (jcms_sweeperShield): %d", target:GetNWInt("jcms_sweeperShield", 0))
	line("Anti-rad charges: %d", target:GetNWInt("jcms_antirad", 0))
	line("Gamemode damage immunity left: %.1fs", math.max(0, (target.jcms_damageImmunityEnd or 0) - CurTime()))
	if S.mods then line("Modifiers: %s", table.concat(S.mods.list or {}, ", ")) end
	line("Domes / bulwarks nearby can also soak hits from outside them.")

	local msg = table.concat(out, "\n")
	if S.PrintConsole then S.PrintConsole(IsValid(ply) and ply or nil, msg) else print(msg) end
end, nil, "Prints what could be blocking damage on you (Implants addon).")

local function adminOnly(ply)
	return not IsValid(ply) or ply:IsAdmin()
end

local function findTarget(ply, arg)
	if arg and arg ~= "" then
		for i, p in ipairs(player.GetHumans()) do
			if string.find(string.lower(p:Nick()), string.lower(arg), 1, true) then return p end
		end
		return nil
	end
	return IsValid(ply) and ply or nil
end

-- jcms_implant_givexp <amount> [class] [player name]
concommand.Add("jcms_implant_givexp", function(ply, cmd, args)
	if not adminOnly(ply) then return end
	local target = findTarget(ply, args[3])
	if not IsValid(target) then print("[Implants] No target.") return end

	local class = S.IsSkillClass(args[2] or "") and args[2] or S.GetActiveClass(target) or target:GetNWString("jcms_desiredclass", "infantry")
	S.AddXP(target, class, (tonumber(args[1]) or 0) / math.max(S.cvar_xpmul:GetFloat(), 0.0001), "admin")
	print(string.format("[Implants] Gave XP to %s (%s)", target:Nick(), class))
end, nil, "Admin: jcms_implant_givexp <amount> [class] [player]")

-- jcms_implant_setlevel <level> [class] [player name]
concommand.Add("jcms_implant_setlevel", function(ply, cmd, args)
	if not adminOnly(ply) then return end
	local target = findTarget(ply, args[3])
	if not IsValid(target) then print("[Implants] No target.") return end

	local class = S.IsSkillClass(args[2] or "") and args[2] or S.GetActiveClass(target) or target:GetNWString("jcms_desiredclass", "infantry")
	local cd = S.GetClassData(target, class)
	if not cd then return end

	cd.level = math.Clamp(math.floor(tonumber(args[1]) or 1), 1, S.maxLevel)
	cd.xp = 0
	if S.ChipsetsAvailable(cd) < 0 then cd.skills = {} end
	cd.specs = cleanSpecs(class, cd.level, cd.specs)
	S.SaveClass(target:SteamID64(), class)
	S.Sync(target)
	print(string.format("[Implants] %s %s is now level %d", target:Nick(), class, cd.level))
end, nil, "Admin: jcms_implant_setlevel <level> [class] [player]")
-- // }}}

-- Handle a Lua refresh while players are connected
for i, ply in ipairs(player.GetHumans()) do
	if not S.data[ply:SteamID64()] then S.Load(ply) end
	S.Sync(ply)
end
