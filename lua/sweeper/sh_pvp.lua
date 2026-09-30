--[[
	Map Sweepers - Implants & Class Levels (addon)
	PVP rules: everyone plays at level 30 on a separate build, and the lobby runs on a 3 minute clock.

	WHY A SEPARATE BUILD
	PVP hands every player level 30 so nobody is fighting uphill against someone else's evening of
	coop. That means handing out 29 Chipsets, and if those were spent in the coop save a level-3
	player could spend 29 Chipsets in PVP and walk back into coop with a fully-spent tree. So PVP gets
	its own profile per class:

		coop profile   sweeper table, class = "recon"       - earned, levels up, what PVE uses
		PVP profile    sweeper table, class = "pvp_recon"   - always level 30, 29 Chipsets, PVP only

	The two never touch. Respeccing in PVP costs a coop player nothing, and PVP awards no XP at all
	(S.pvpRules.noXP), so nobody farms PVP rounds for coop levels.

	It works by wrapping four of our own functions rather than editing them, so the coop paths are
	byte-for-byte what they were:
		S.GetClassData  -> the PVP profile while PVP is on (this is what the buy/respec/spec handler,
		                   the HUD and the stat application all read, so one wrap covers the lot)
		S.Sync          -> sends the PVP profile, so the client menu edits the right build
		S.SaveClass     -> writes to the pvp_ rows
		S.AddXP         -> does nothing in PVP

	Level 30 is doing more work than it looks: Chipsets come from S.ChipsetsEarned(level) and the spec
	tiers gate on S.specLevels against level, so setting the level is all that's needed to open up the
	whole tree. No separate "unlock everything in PVP" path to keep in sync.

	Implant VALUES are scaled down in PVP separately, in sh_tree.lua (S.pvpScale) - coop stays tanky
	because late-winstreak enemies demand it, PVP gets the compressed numbers.

	THE LOBBY CLOCK
	The gamemode's own ready-up rules (1:30 when someone readies, 10s at half, instant at everyone)
	are replaced in the PVP lobby by: 3 minutes, or a short countdown once 75% have readied. Its
	writes to the mission start time are ignored while our clock is up - and only then, so the
	post-mission reset that returns everyone to the lobby still lands normally.

	Admin: sweeper_pvp_status
--]]

local S = sweeper

S.pvpRules = {
	enabled = true,

	level = 30,              -- everyone plays PVP at this level (S.maxLevel)

	lobbySeconds = 180,      -- 3 minutes in the PVP lobby...
	readyFraction = 0.75,    -- ...unless this share of the players have readied up
	readyDelay = 10,         -- countdown once that threshold is hit
	allReadyDelay = 0,       -- ...or this when literally everyone is ready

	noXP = true,             -- PVP pays nothing toward coop levels
	allWeapons = true,       -- every gun buyable in PVP, whatever the armory has unlocked
	startCash = 2000,        -- J to spend in a PVP match (nil = leave the gamemode's jcms_cash_start_pvp alone)

	-- Team Upgrades are off in PVP too. That one lives in sh_group.lua rather than here, because its
	-- S.GroupRank is the reader every call-in, orbital and vehicle goes through - see GroupRawRank.
}

-- The rules, but only while a PVP match or PVP lobby is actually up. jcms_pvpmode is a networked bool
-- on the world entity that pvp_SetEnabled flips, so this is true in the lobby too, not just in a
-- running mission - which is what lets the lobby clock and the menu work before anyone deploys.
function S.PvpRules()
	local r = S.pvpRules
	if not (r and r.enabled) then return nil end
	if not (jcms and jcms.util_IsPVP and jcms.util_IsPVP()) then return nil end
	return r
end

if not SERVER then return end

-- // The PVP profile {{{
S.pvpData = S.pvpData or {} -- [sid64][class] = { xp, level, skills, specs }

local function blankPvp(level)
	return { xp = 0, level = level, skills = {}, specs = {} }
end

-- Drops specs that no longer exist. The level check the coop loader does is pointless here (a PVP
-- profile is always level 30, which clears every tier), so this only guards against an edited tree.
local function cleanPvpSpecs(class, specs)
	local out = {}
	for tier, id in pairs(specs or {}) do
		tier = tonumber(tier)
		local spec = tier and S.GetSpec and S.GetSpec(class, id)
		if spec and spec.tier == tier then out[tier] = id end
	end
	return out
end

local function loadPvp(sid64)
	local level = S.pvpRules.level
	local tbl = {}
	for i, class in ipairs(S.classes) do tbl[class] = blankPvp(level) end

	-- Filtered in Lua rather than with LIKE 'pvp_%', because _ is a single-character wildcard in SQL
	-- LIKE and would also match a class called pvpXrecon.
	local rows = sql.Query("SELECT class, skills, specs FROM sweeper WHERE sid64 = " .. sql.SQLStr(sid64))
	for i, row in ipairs(istable(rows) and rows or {}) do
		local class = string.match(tostring(row.class or ""), "^pvp_(.+)$")
		local cd = class and tbl[class]
		if cd then
			local clean = {}
			for id, rank in pairs(util.JSONToTable(row.skills or "{}") or {}) do
				local sk = S.byId[class] and S.byId[class][id]
				if sk then clean[id] = math.Clamp(math.floor(tonumber(rank) or 0), 0, sk.max) end
			end
			cd.skills = clean
			cd.specs = cleanPvpSpecs(class, util.JSONToTable(row.specs or "{}") or {})

			-- Tree edited since they built this? Refund the lot rather than leave them over budget.
			if S.ChipsetsAvailable(cd) < 0 then cd.skills = {} end
			if S.DropUnpickedSpecSkills then S.DropUnpickedSpecSkills(class, cd) end
		end
	end

	return tbl
end

function S.GetPvpClassData(ply, class)
	if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return nil end
	local sid64 = ply:SteamID64()
	if not sid64 then return nil end

	if not S.pvpData[sid64] then S.pvpData[sid64] = loadPvp(sid64) end
	local cd = S.pvpData[sid64][class]
	if cd then
		-- Granted, never earned: re-asserted on every read so nothing can drift it.
		cd.level = S.pvpRules.level
		cd.xp = 0
	end
	return cd
end

function S.SavePvpClass(sid64, class)
	local cd = S.pvpData[sid64] and S.pvpData[sid64][class]
	if not cd then return end

	sql.Query(string.format("REPLACE INTO sweeper (sid64, class, xp, level, skills, specs) VALUES (%s, %s, 0, %d, %s, %s)",
		sql.SQLStr(sid64), sql.SQLStr("pvp_" .. class), math.floor(S.pvpRules.level),
		sql.SQLStr(util.TableToJSON(cd.skills or {})), sql.SQLStr(util.TableToJSON(cd.specs or {}))))

	if S.dirty[sid64] then S.dirty[sid64][class] = nil end
end

function S.InstallPvpProfiles()
	if S.Wrapped(S, "PvpProfiles") then return end

	local origGet = S.GetClassData
	S._wrappedPvpGetClassData = function(ply, class)
		if S.PvpRules() then return S.GetPvpClassData(ply, class) end
		return origGet(ply, class)
	end
	S.GetClassData = S._wrappedPvpGetClassData

	local origSync = S.Sync
	S._wrappedPvpSync = function(ply)
		if not S.PvpRules() then return origSync(ply) end
		if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return end
		local sid64 = ply:SteamID64()
		if not sid64 then return end
		if not S.pvpData[sid64] then S.pvpData[sid64] = loadPvp(sid64) end

		net.Start("sweeper_sync")
			net.WriteTable(S.pvpData[sid64])
		net.Send(ply)
	end
	S.Sync = S._wrappedPvpSync

	local origSave = S.SaveClass
	S._wrappedPvpSaveClass = function(sid64, class)
		if S.PvpRules() then return S.SavePvpClass(sid64, class) end
		return origSave(sid64, class)
	end
	S.SaveClass = S._wrappedPvpSaveClass

	local origXP = S.AddXP
	S._wrappedPvpAddXP = function(ply, class, amount, reason)
		local r = S.PvpRules()
		if r and r.noXP then return end
		return origXP(ply, class, amount, reason)
	end
	S.AddXP = S._wrappedPvpAddXP

	S.MarkWrapped(S, "PvpProfiles")
end

hook.Add("PlayerDisconnected", "sweeper_pvpProfile", function(ply)
	if ply:IsBot() then return end
	local sid64 = ply:SteamID64()
	if not sid64 then return end
	if S.PvpRules() and S.dirty[sid64] then
		for class in pairs(S.dirty[sid64]) do S.SavePvpClass(sid64, class) end
	end
	S.pvpData[sid64] = nil
end)

-- Flipping PVP on or off swaps which build every player is running, so their pending changes are
-- written under the OLD mode first, then everyone is resynced and restatted under the new one.
function S.InstallPvpToggle()
	if not (jcms and jcms.pvp_SetEnabled) or S.Wrapped(jcms, "PvpToggle") then return end
	local orig = jcms.pvp_SetEnabled

	S._wrappedPvpSetEnabled = function(state, ...)
		if S.SaveAllDirty then pcall(S.SaveAllDirty) end
		S.pvpClockHeld = false
		S.pvpClockDeadline = nil
		S.pvpClockReady = nil

		local rtn = { orig(state, ...) }

		for i, ply in ipairs(player.GetHumans()) do
			pcall(S.Sync, ply)
			if S.RefreshStats then pcall(S.RefreshStats, ply) end
		end

		-- The padlocks are drawn from a lock list the server pushes, so without this the shop keeps the
		-- previous mode's locks: PVP would still show guns locked, and coop would show none.
		if S.GunSendLocks then pcall(S.GunSendLocks) end
		if S.GroupSync then pcall(S.GroupSync) end

		return unpack(rtn)
	end

	jcms.pvp_SetEnabled = S._wrappedPvpSetEnabled
	S.MarkWrapped(jcms, "PvpToggle")
end
-- }}}

-- // The PVP lobby clock {{{
-- 3 minutes, or a short countdown once 75% have readied up.
--
-- The gamemode runs its own ready-up rules every tick in sv_missions.lua (1:30 when anyone readies,
-- 10s at half the lobby, instant at everyone, reset at nobody) and they'd fight ours - its "half the
-- lobby" rule in particular would start the match at 2 of 3 ready, well under 75%. So while our
-- clock is up, its writes to the mission start time are dropped. ONLY while our clock is up: the
-- same two functions are what returns everyone to the lobby after a match, and suppressing that
-- would leave a stale start time sitting there ready to fire off another mission immediately.
S.pvpClockHeld = false     -- true while our clock owns the mission start time
S.pvpClockDeadline = nil   -- absolute CurTime of the 3 minute deadline; armed once per lobby
S.pvpClockReady = nil      -- absolute CurTime the ready threshold wants to start at, anchored once
local settingOurs = false

function S.InstallPvpClock()
	if not (jcms and jcms.mission_SetStartDelay and jcms.mission_ResetStartTimer) then return end
	if S.Wrapped(jcms, "PvpClock") then return end

	local origSet = jcms.mission_SetStartDelay
	S._wrappedPvpSetStartDelay = function(delay, ...)
		if S.pvpClockHeld and not settingOurs and S.PvpRules() then return end
		return origSet(delay, ...)
	end
	jcms.mission_SetStartDelay = S._wrappedPvpSetStartDelay

	local origReset = jcms.mission_ResetStartTimer
	S._wrappedPvpResetStartTimer = function(...)
		if S.pvpClockHeld and not settingOurs and S.PvpRules() then return end
		return origReset(...)
	end
	jcms.mission_ResetStartTimer = S._wrappedPvpResetStartTimer

	S.MarkWrapped(jcms, "PvpClock")
end

local function ourDelay(seconds)
	settingOurs = true
	local ok, err = pcall(jcms.mission_SetStartDelay, seconds)
	settingOurs = false
	if not ok then ErrorNoHalt("[sweeper] pvp clock: " .. tostring(err) .. "\n") end
end

-- Counted the same way the gamemode counts it: desiredteam 0 or 1 is someone who could play, and
-- only desiredteam 1 can actually be ready.
function S.PvpLobbyCount()
	local total, ready = 0, 0
	for i, ply in ipairs(player.GetAll()) do
		local team = ply:GetNWInt("jcms_desiredteam", 0)
		if isnumber(team) and team <= 1 then
			total = total + 1
			if team == 1 and ply:GetNWBool("jcms_ready", false) then ready = ready + 1 end
		end
	end
	return total, ready
end

local function lobbyTick()
	local function release()
		S.pvpClockHeld = false
		S.pvpClockDeadline = nil
		S.pvpClockReady = nil
	end

	local r = S.PvpRules()
	if not r then return release() end

	-- Mission running, or one being built: the clock's job is done until we're back in the lobby, and
	-- the deadline is dropped so the next lobby arms a fresh three minutes.
	if jcms.director or jcms.mission_generating or (jcms.util_IsGameOngoing and jcms.util_IsGameOngoing()) then
		return release()
	end

	local total, ready = S.PvpLobbyCount()
	if total < 1 then return release() end

	local ct = CurTime()

	-- The 3 minute deadline is armed once, when the lobby starts, and then never moves. Readying up
	-- can only bring the start forward; un-readying falls back to this deadline rather than to a fresh
	-- three minutes, so a countdown can still be called off without anyone being able to hold a lobby
	-- open indefinitely by toggling ready.
	-- Armed once and only once per lobby. Deliberately NOT re-armed when it lapses: mission_SetStartDelay
	-- rounds up to the next whole second, so the start time can land a fraction past the deadline, and a
	-- "re-arm if lapsed" check fires in that gap and hands the lobby another three minutes. release()
	-- is what clears it, on mission start, an empty lobby, or PVP being switched off.
	if not S.pvpClockDeadline then
		S.pvpClockDeadline = ct + r.lobbySeconds
	end

	-- The ready countdown is ANCHORED to the moment the threshold was crossed. Recomputing it as
	-- "now + 10" on every tick looks right and never fires: the target slides forward exactly as fast
	-- as the clock advances, so the countdown sits at 10 seconds forever.
	local trigger
	if ready >= total then
		trigger = ct + r.allReadyDelay
	elseif (ready / total) >= r.readyFraction then
		trigger = ct + r.readyDelay
	end

	if trigger then
		-- Keep the earliest: going from 75% to everyone-ready should pull the start in, not push it back.
		S.pvpClockReady = math.min(S.pvpClockReady or trigger, trigger)
	else
		-- Dropped back under the threshold - fall back to the untouched 3 minute deadline.
		S.pvpClockReady = nil
	end

	local target = math.min(S.pvpClockReady or math.huge, S.pvpClockDeadline)

	-- Compared as absolute times, not as remaining seconds: mission_SetStartDelay rounds up to the
	-- next whole second, so a remaining-vs-remaining check can sit permanently ~1s out and rewrite
	-- the clock on every tick.
	local startAbs = jcms.util_GetMissionStartTime()
	if not jcms.util_IsGameTimerGoing() or math.abs(target - startAbs) > 1.5 then
		ourDelay(math.max(0, target - ct))
	end
	S.pvpClockHeld = true
end

timer.Create("sweeper_pvpLobbyClock", 0.5, 0, function()
	local ok, err = pcall(lobbyTick)
	if not ok then ErrorNoHalt("[sweeper] pvp lobby clock: " .. tostring(err) .. "\n") end
end)
-- }}}

-- // Weapons and cash {{{
-- Every gun is buyable in PVP. Switching the whole gun-unlock system off for the duration is one
-- lever instead of three: the purchase block, the lock list sent to clients and the padlocks drawn
-- over the icons all gate on S.GunProgressEnabled.
--
-- Each wrap carries its own marker rather than sharing one, because sh_gunprogress.lua loads AFTER
-- this file - the first pass at file scope finds these functions missing, and a shared marker would
-- record "done" and stop the Initialize pass from ever installing them.
function S.InstallPvpWeapons()
	local r = S.pvpRules
	if not (r and r.allWeapons) then return end

	if S.GunProgressEnabled and not S.Wrapped(S, "PvpGunProgress") then
		local orig = S.GunProgressEnabled
		S._wrappedPvpGunProgress = function(...)
			if S.PvpRules() then return false end
			return orig(...)
		end
		S.GunProgressEnabled = S._wrappedPvpGunProgress
		S.MarkWrapped(S, "PvpGunProgress")
	end

	-- ...and winning a PVP round doesn't open coop's next armory batch, for the same reason it pays
	-- no XP: PVP is a side arena, not progress.
	if S.GrantGunUnlocks and not S.Wrapped(S, "PvpGrantGuns") then
		local orig = S.GrantGunUnlocks
		S._wrappedPvpGrantGuns = function(...)
			if S.PvpRules() then return {} end
			return orig(...)
		end
		S.GrantGunUnlocks = S._wrappedPvpGrantGuns
		S.MarkWrapped(S, "PvpGrantGuns")
	end
end

-- Flat starting cash in PVP. The gamemode already branches to its own jcms_cash_start_pvp convar in
-- here, so this replaces that value rather than adding to it; leave startCash nil to defer to the
-- convar. sh_group.lua wraps this function too (Emergency Fund), which is fine - it returns the cash
-- untouched in PVP, and this wrap ignores the inner value there anyway, so the order doesn't matter.
function S.InstallPvpCash()
	if not (jcms and jcms.runprogress_GetStartingCash) or S.Wrapped(jcms, "PvpCash") then return end
	local orig = jcms.runprogress_GetStartingCash

	S._wrappedPvpStartCash = function(...)
		local cash = orig(...)
		local r = S.PvpRules()
		if r and isnumber(r.startCash) then return r.startCash end
		return cash
	end

	jcms.runprogress_GetStartingCash = S._wrappedPvpStartCash
	S.MarkWrapped(jcms, "PvpCash")
end
-- }}}

local function installAll()
	S.InstallPvpProfiles()
	S.InstallPvpToggle()
	S.InstallPvpClock()
	S.InstallPvpWeapons()
	S.InstallPvpCash()
end
hook.Add("Initialize", "sweeper_pvpRules", installAll)
hook.Add("InitPostEntity", "sweeper_pvpRules", installAll)
installAll()

concommand.Add("sweeper_pvp_status", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local say = function(text)
		if S.PrintConsole and IsValid(ply) then S.PrintConsole(ply, text) else print(text) end
	end

	local r = S.PvpRules()
	local total, ready = S.PvpLobbyCount()
	local lines = {
		"--- PVP rules ---",
		string.format("  PVP mode: %s     rules active: %s",
			(jcms and jcms.util_IsPVP and jcms.util_IsPVP()) and "ON" or "off",
			r and "yes" or (S.pvpRules.enabled and "no (not PVP)" or "no (disabled)")),
		string.format("  everyone plays at level %d, %d Chipsets, separate pvp_ build, XP %s",
			S.pvpRules.level, S.ChipsetsEarned(S.pvpRules.level), S.pvpRules.noXP and "OFF" or "on"),
		string.format("  all weapons: %s    starting cash: %s    Team Upgrades: %s",
			S.pvpRules.allWeapons and "yes" or "no",
			isnumber(S.pvpRules.startCash) and (S.pvpRules.startCash .. " J") or "gamemode convar",
			r and "OFF (S.GroupRank reports 0)" or "on (coop)"),
		string.format("  lobby: %d ready of %d (%.0f%%)  threshold %.0f%%  clock held by us: %s",
			ready, total, total > 0 and (ready / total * 100) or 0,
			S.pvpRules.readyFraction * 100, tostring(S.pvpClockHeld)),
		string.format("  time until start: %.1fs   timer going: %s",
			jcms and jcms.util_GetTimeUntilStart and jcms.util_GetTimeUntilStart() or -1,
			tostring(jcms and jcms.util_IsGameTimerGoing and jcms.util_IsGameTimerGoing())),
	}

	local scale = S.PvpScaling and S.PvpScaling()
	lines[#lines + 1] = scale
		and string.format("  stat scaling: defense %.0f%% offense %.0f%% utility %.0f%% deploy %.0f%% (resist cap %.0f%%)",
			scale.defense * 100, scale.offense * 100, scale.utility * 100, scale.deploy * 100, scale.resistCap * 100)
		or "  stat scaling: not active (coop values)"

	say(table.concat(lines, "\n"))
end, nil, "Admin: show the PVP implant rules and lobby clock state.")
