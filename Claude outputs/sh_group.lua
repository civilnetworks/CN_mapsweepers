--[[
	Map Sweepers - Implants & Class Levels (addon)
	Team Upgrades: squad-wide upgrades, bought with the squad's V Tokens by VOTE at the start of each match.

	HOW IT WORKS
	- V Tokens go into one squad pool:
	    * Finishing a map (mission victory) adds tokens (more with a bigger squad / evacuations).
	    * Hacking a terminal has a chance to turn up V Tokens.
	- At the start of each match (in the lobby, before the mission) a vote begins if the pool can
	  afford any upgrade. The TEAM UPGRADES tab glows while the vote is running.
	  Everyone picks one upgrade (or SAVE TOKENS). The winner is bought from the pool and helps
	  EVERY sweeper. If the pool can still afford something, another vote starts.
	- The vote ends early once everyone has voted, and is settled right away if the mission launches.
	- Upgrades and tokens last the whole run and are wiped on game over
	  (same convar as Implants: jcms_implant_reset_on_gameover).
	- Disabled in PvP.

	ARMORY ACCESS (weapon unlocks)  -- OFF by default: jcms_team_weaponlocks 1 turns it on
	- One Team Upgrade with 5 ranks. Every rank unlocks the next batch of weapons in the shop.
	- Weapons that aren't unlocked yet are hidden from the shop (lobby loadout + in-mission buying).
	- Until a fixed list is set up, the batches are RANDOM each run: every shop weapon except the
	  "free" ones is shuffled into 5 batches when the run starts (and re-shuffled after game over).
	- To use a fixed list, fill in "ranks" in data/sweeper/weapon_unlocks.json (created on first
	  start). Weapons in "free" are always in the shop.

	NEW CONTRACT (mission reroll)
	- In the lobby anyone can propose a New Contract (TEAM UPGRADES tab, or "jcms_newcontract").
	  The squad votes yes/no; if yes wins, 20 V Tokens leave the pool and the mission is rerolled.
	- Rerolls per map: 3 at win streak 0-15, 2 at 16-29, 1 at 30-59, none at 60+ (S.contractConfig).
	- Boss missions, special maps and PvP can't be rerolled.

	Tuning: S.groupUpgrades below, plus the convars in the server section.
	Admin: jcms_team_reset, jcms_team_setrank <id> <rank>,
	       jcms_givetokens <amount>, jcms_team_startvote
	       jcms_weaponplan (prints this run's batches), jcms_weaponplan_reroll
--]]

local S = sweeper

S.tokenName = "V Token"
S.tokenNamePlural = "V Tokens"
S.VOTE_SKIP = "skip"

-- The Team Upgrades tab is laid out in these sections, in this order. Each row below carries a
-- section = "<id>"; anything without one falls into "squad". A section with no rows draws no header,
-- so retiring a whole group of upgrades needs no change here.
S.groupSections = {
	{ id = "squad",    name = "SQUAD UPGRADES",  sub = "Flat bonuses every sweeper carries, all mission long." },
	{ id = "callin",   name = "CALL-INS",        sub = "Better versions of the call-ins your classes bring." },
	{ id = "ability",  name = "CLASS ABILITIES", sub = "The subclass powers you fire off with G, H and J." },
	{ id = "defense",  name = "DEFENSES",        sub = "Turrets, mines and the cover you put down." },
	{ id = "orbital",  name = "ORBITAL STRIKES", sub = "Everything that falls out of the sky." },
	{ id = "vehicle",  name = "VEHICLES",        sub = "The VTOL, the tank and the APC." },
	{ id = "armory",   name = "ARMORY",          sub = "Weapon access for the whole squad." },
}

S.groupUpgrades = {
	-- id, name, stats given PER RANK, price of each rank in V Tokens, description
	-- section picks which block of the Team Upgrades tab the card sits in (see S.groupSections)
	{ id = "g_hp",       name = "Squad Vitality",     stats = { hp = 10 },               costs = { 10, 25, 40 }, desc = "+10 max health per rank for every sweeper." },
	{ id = "g_armor",    name = "Reinforced Plating", stats = { armor = 10 },            costs = { 10, 25, 40 }, desc = "+10 max shield per rank for every sweeper." },
	{ id = "g_regen",    name = "Shield Capacitors",  stats = { regen = 0.10 },          costs = { 10, 25, 40 }, desc = "Shields recharge 10% faster per rank." },
	{ id = "g_dmg",      name = "Munitions Budget",   stats = { dmg = 0.04 },            costs = { 15, 30, 50 }, desc = "+4% damage per rank for every sweeper." },
	{ id = "g_resist",   name = "Hardened Suits",     stats = { resist = 0.04 },         costs = { 15, 30, 50 }, desc = "-4% damage taken per rank for every sweeper." },
	{ id = "g_orders",   name = "Logistics Contract", stats = { orderCost = 0.05 },      costs = { 15, 30, 45 }, desc = "Call-ins cost 5% less per rank." },
	{ id = "g_cooldown", name = "Priority Uplink",    stats = { orderCooldown = 0.06 },  costs = { 15, 30, 45 }, desc = "Call-in cooldowns 6% shorter per rank." },
	{ id = "g_deploy",   name = "Turret Contracts",   stats = { deploy = 0.06 },         section = "defense", costs = { 10, 25, 40 }, desc = "Turrets and deployables deal +6% damage per rank." },
	{ id = "g_xp",       name = "Training Program",   stats = { xp = 0.10 },             costs = { 10, 20, 35 }, desc = "+10% class XP per rank for every sweeper." },
	{ id = "g_funds",    name = "Emergency Fund",     startCash = 60,                    costs = { 20, 35, 55 }, desc = "+60 J starting cash per rank for every sweeper, every mission." },

	-- // CALL-IN UPGRADES: effects are in sh_callins.lua, tuning in S.callinUpgrades //
	{ id = "g_multiblast", name = "MultiBlast Mine: Cluster Payload", callin = true, section = "defense", costs = { 10, 20, 30 },
	  desc = "Every MultiBlast blast fires a spread-out cluster of mini mines (2 / 3 / 4 by rank). They explode a moment later.",
	  nowText = function(r) return string.format("Now: %d mini mines per blast", 1 + r) end },
	{ id = "g_jumppad",  name = "Jump Pad: Overcharged Springs", callin = true, section = "callin", costs = { 5, 10, 15 },
	  desc = "Jump Pads launch you 50% higher and with 75% more forward force per rank. Overclocked pads also throw you forward.",
	  nowText = function(r) return string.format("Now: +%d%% height, +%d%% force", r * 50, r * 75) end },

	-- Class call-ins (this addon's own - see sh_callins.lua)
	{ id = "g_drones",   name = "Drones: Reinforced Frames", callin = true, section = "callin", costs = { 8, 15, 25 },
	  desc = "Engineer drones last 25% longer, have 30% more health and Combat Drones deal 15% more damage per rank.",
	  nowText = function(r) return string.format("Now: +%d%% uptime, +%d%% HP, +%d%% drone damage", r * 25, r * 30, r * 15) end },
	{ id = "g_healstation", name = "Healing Station: Bigger Reservoir", callin = true, section = "callin", costs = { 6, 12, 20 },
	  desc = "Healing Stations hold +100 healing and heal 1 HP/s faster per rank.",
	  nowText = function(r) return string.format("Now: +%d healing, +%d HP/s", r * 100, r) end },
	{ id = "g_stims",    name = "Stim Crate: Potent Mix", callin = true, section = "callin", costs = { 6, 12, 20 },
	  desc = "Stim Crates hold +1 dose per rank, and stims last 50% longer per rank.",
	  nowText = function(r) return string.format("Now: +%d doses, +%d%% duration", r, r * 50) end },
	{ id = "g_ammocache", name = "Ammo Cache: Deep Reserves", callin = true, section = "callin", costs = { 6, 12 },
	  desc = "Ammo Caches hold +600 ammo and give +50 per use per rank.",
	  nowText = function(r) return string.format("Now: +%d ammo held, +%d per use", r * 600, r * 50) end },
	{ id = "g_uav",      name = "UAV: Deep Scan", callin = true, section = "callin", costs = { 6, 12 },
	  desc = "UAV Scans last +10s and reach +500 units per rank.",
	  nowText = function(r) return string.format("Now: +%ds, +%d units", r * 10, r * 500) end },
	{ id = "g_cluster",  name = "Cluster Bomb: Dense Pattern", callin = true, section = "callin", costs = { 6, 12, 20 },
	  desc = "Cluster Bombs drop +4 bomblets and their blasts are 15% wider per rank.",
	  nowText = function(r) return string.format("Now: +%d bomblets, +%d%% blast", r * 4, r * 15) end },
	{ id = "g_emp",      name = "EMP Burst: Overload", callin = true, section = "callin", costs = { 6, 12, 20 },
	  desc = "EMP Bursts reach +150 units, hit for +100 damage and scramble enemies for +2s per rank.",
	  nowText = function(r) return string.format("Now: +%d range, +%d damage, +%ds", r * 150, r * 100, r * 2) end },
	{ id = "g_structures", name = "Field Fortifications", callin = true, section = "defense", costs = { 8, 15, 25 },
	  desc = "Deployable Cover, Bulwark, Taunt Totem and Decoy Beacon get +25% health per rank, and Bulwark domes absorb +500 more.",
	  nowText = function(r) return string.format("Now: +%d%% structure HP, +%d dome HP", r * 25, r * 500) end },

	-- Orbitals: the gamemode's own air and orbital orders. Carpet Bombing and the Strafing Run are
	-- wrapped in sh_callins.lua; the rest are in sh_orbitals.lua, tuning in S.orbitals.
	{ id = "g_carpet",   name = "Carpet Bomb: Wide Pattern", callin = true, section = "orbital", costs = { 10, 25, 40 },
	  desc = "Carpet Bombing drops over a 25% wider area per rank, with +4 bombs per rank.",
	  nowText = function(r) return string.format("Now: %d%% wider pattern, +%d bombs", r * 25, r * 4) end },
	{ id = "g_daisy",    name = "Carpet Bomb: Daisy Cutter", callin = true, section = "orbital", costs = { 8, 16, 28 },
	  desc = "Carpet Bombing blasts reach +100 units, drop +4 more bombs, and the run carries on +400 units past your mark, per rank.",
	  nowText = function(r) return string.format("Now: %d blast radius, %d bombs, run +%d units", 400 + r * 100, 20 + r * 4, r * 400) end },
	{ id = "g_rapid",    name = "Shelling: Rapid Battery", callin = true, section = "orbital", costs = { 8, 16, 28 },
	  desc = "Shelling opens 25% sooner and keeps going: +15 more shells per rank.",
	  nowText = function(r) return string.format("Now: %d%% faster to open, %d shells", math.min(75, r * 25), 60 + r * 15) end },
	{ id = "g_beam",     name = "Orbital Beam: Focusing Array", callin = true, section = "orbital", costs = { 10, 20, 35 },
	  desc = "The Orbital Beam is 16 units wider and sweeps 75 units/s faster per rank - easier to hold on a target, and more passes per firing.",
	  nowText = function(r) return string.format("Now: %d beam radius, %d sweep speed", 32 + r * 16, 350 + r * 75) end },
	{ id = "g_strafe",   name = "Strafing Run: Explosive Rounds", callin = true, section = "orbital", costs = { 20 },
	  desc = "Strafing Run bullets explode where they hit: +75 damage in a 150-unit blast on top of the bullet damage.",
	  nowText = function(r) return "Now: explosive rounds" end },

	-- ...and the three that apply to every orbital at once
	{ id = "g_dangerclose", name = "Orbitals: Danger Close", callin = true, section = "orbital", costs = { 10, 20 },
	  desc = "Your own orbitals hurt sweepers 50% less per rank. At rank 2 they can't hurt the squad at all.",
	  nowText = function(r) return r >= 2 and "Now: no friendly damage" or "Now: -50% friendly damage" end },
	{ id = "g_requisition", name = "Orbitals: Requisition", callin = true, section = "orbital", costs = { 8, 16, 28 },
	  desc = "Every orbital order costs 10% less per rank.",
	  nowText = function(r) return string.format("Now: -%d%% orbital cost", r * 10) end },
	{ id = "g_salvo",    name = "Orbitals: Second Salvo", callin = true, section = "orbital", costs = { 12, 24 },
	  desc = "Each orbital has a 20% chance per rank to fire a second time, free, a few seconds later.",
	  nowText = function(r) return string.format("Now: %d%% chance of a free second salvo", r * 20) end },

	-- Vehicles (the gamemode's own VTOL / Tank / APC - effects are in sh_vehicles.lua, tuning in S.vehicles)
	{ id = "g_vtol",     name = "DS-2 VTOL: Extended Belts", callin = true, section = "vehicle", costs = { 8, 16, 28 },
	  desc = "The VTOL's machinegun carries +200 rounds per rank. At rank 3 its rocket pods come online - right click fires a homing salvo.",
	  nowText = function(r)
		  return r >= 3 and string.format("Now: %d rounds, rocket pods online", 400 + r * 200)
			  or string.format("Now: %d rounds", 400 + r * 200)
	  end },
	{ id = "g_tank",     name = "LHT-6 Tank: Autoloader", callin = true, section = "vehicle", costs = { 10, 20, 35 },
	  desc = "The tank's main gun cycles 12% faster per rank, and its micro-missiles reload 15% faster per rank.",
	  nowText = function(r)
		  return string.format("Now: %.2fs cannon, %.2fs missiles",
			  2.5 * math.max(0.5, 1 - 0.12 * r), 0.4 * math.max(0.45, 1 - 0.15 * r))
	  end },
	{ id = "g_apc",      name = "APC: Reactive Plating", callin = true, section = "vehicle", costs = { 8, 16, 28 },
	  desc = "The APC's shield holds 3 seconds longer and recharges 2.5 seconds sooner per rank, and it drives 6% faster per rank.",
	  nowText = function(r)
		  return string.format("Now: %ds shield, %.1fs recharge, +%d%% speed",
			  8 + r * 3, math.max(6, 15 - r * 2.5), r * 6)
	  end },
}

-- Call-in upgrade tuning (per rank)
S.callinUpgrades = {
	carpetRadiusPerRank = 0.25,  -- bomb spread + line length
	carpetBombsPerRank = 4,
	multiblastBombletsBase = 1,      -- rank 1 = 2, rank 2 = 3, rank 3 = 4 mini mines
	multiblastBombletsPerRank = 1,
	multiblastBombletRadius = 110,
	multiblastBombletDamage = 60,
	multiblastScatterMin = 140,      -- how far the mini mines are thrown (units)
	multiblastScatterMax = 320,
	multiblastFuseMin = 1.2,         -- a mini mine goes off on its own after this long
	multiblastFuseMax = 1.8,
	jumpHeightPerRank = 0.50,        -- rank 3 = +150% height
	jumpForcePerRank = 0.75,         -- rank 3 = +225% forward push
	jumpOverclockForwardPerRank = 150, -- overclocked pads normally launch straight up; add forward push per rank

	-- Class call-ins
	dronesLifetimePerRank = 0.25,
	dronesHealthPerRank = 0.30,
	dronesDamagePerRank = 0.15,
	healStationChargePerRank = 100,
	healStationRatePerRank = 1,
	stimDosesPerRank = 1,
	stimDurationPerRank = 0.50,
	ammoCacheChargePerRank = 600,
	ammoCachePerUsePerRank = 50,
	uavDurationPerRank = 10,
	uavRadiusPerRank = 500,
	structureHealthPerRank = 0.25,
	bulwarkDomePerRank = 500,
	clusterBombletsPerRank = 4,
	clusterRadiusPerRank = 0.15,
	empRadiusPerRank = 150,
	empDamagePerRank = 100,
	empScramblePerRank = 2,
}

-- // NEW CONTRACT: the squad votes to reroll this map's mission for V Tokens {{{
-- Rerolls per map depend on the win streak (higher streak = fewer). Boss missions, special maps and PvP can't be rerolled.
S.contractConfig = {
	cost = 20,          -- V Tokens per reroll
	voteTime = 25,      -- seconds
	-- rerolls allowed per map: the last row whose minStreak <= current win streak
	chances = {
		{ minStreak = 0, rerolls = 3 },
		{ minStreak = 16, rerolls = 2 },
		{ minStreak = 30, rerolls = 1 },
		{ minStreak = 60, rerolls = 0 },
	},
}

function S.ContractMaxRerolls(streak)
	local n = 0
	for i, row in ipairs(S.contractConfig.chances) do
		if (streak or 0) >= row.minStreak then n = row.rerolls end
	end
	return n
end
-- }}}

S.groupById = {}
for i, up in ipairs(S.groupUpgrades) do
	S.groupById[up.id] = up
end

-- Shared state. The server owns it; clients get a copy.
--   ranks[id] = current rank
--   pool      = squad V Tokens
--   vote      = nil, or { endsAt = CurTime, options = { id, ... }, tally = { [id] = count } }
S.group = S.group or { ranks = {}, pool = 0 }
S.WEAPON_UPGRADE = "g_weapons"
S.WEAPON_RANKS = 5
-- weaponPlan[rank] = { class, class, ... } : which weapons each Armory Access rank unlocks this run
S.group.weaponPlan = S.group.weaponPlan or {}

-- Always in the shop (never locked). Server can override this in data/sweeper/weapon_unlocks.json.
S.weaponFreeDefaults = { "weapon_pistol", "weapon_smg1", "weapon_frag", "weapon_crowbar", "weapon_stunstick" }

S.cvar_groupCostMul = CreateConVar("jcms_team_costmul", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"Multiplier for Team Upgrade prices (in V Tokens).", 0, 100)

function S.GroupRank(id)
	return tonumber(S.group.ranks[id]) or 0
end

-- Price of the NEXT rank in V Tokens, or nil when maxed
function S.GroupNextCost(id)
	local up = S.groupById[id]
	if not up then return nil end
	local base = up.costs[S.GroupRank(id) + 1]
	if not base then return nil end
	return math.max(1, math.Round(base * S.cvar_groupCostMul:GetFloat()))
end

function S.GroupPool()
	return tonumber(S.group.pool) or 0
end

function S.GroupCanAfford(id)
	local cost = S.GroupNextCost(id)
	return cost ~= nil and cost <= S.GroupPool()
end

local function isPVP()
	return jcms and jcms.util_IsPVP and jcms.util_IsPVP() or false
end

-- // Armory Access helpers {{{
function S.WeaponName(class)
	local stored = weapons.GetStored(class)
	if stored and stored.PrintName and stored.PrintName ~= "" then
		return CLIENT and language.GetPhrase(stored.PrintName) or stored.PrintName
	end
	local nice = { weapon_357 = ".357 Magnum", weapon_ar2 = "Pulse Rifle", weapon_shotgun = "Shotgun", weapon_crossbow = "Crossbow",
		weapon_rpg = "RPG", weapon_smg1 = "SMG", weapon_pistol = "Pistol", weapon_frag = "Grenade", weapon_slam = "SLAM" }
	return nice[class] or class
end

-- Which Armory Access rank unlocks this weapon (nil = not locked this run)
function S.WeaponUnlockRank(class)
	for r, list in ipairs(S.group.weaponPlan or {}) do
		for i, c in ipairs(list) do
			if c == class then return r end
		end
	end
end

-- RETIRED. Armory Access used to lock the shop behind a V Token upgrade, which meant two systems
-- gated the same shop: it and the per-run gun unlocks in sh_gunprogress.lua both wrapped
-- net_SendWeaponPrices, net_SendWeapon and the two purchase functions, so a weapon had to pass BOTH
-- to be buyable and neither could tell the player which one was blocking it. Winning missions is the
-- single ladder now. The convar and the machinery below stay so every call site keeps working - the
-- gate is simply always open, and the upgrade is no longer in the list above.
S.cvar_weaponLocks = CreateConVar("jcms_team_weaponlocks", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"Legacy: the Armory Access upgrade was retired. Weapons unlock by winning missions (sweeper_gununlocks).", 0, 1)
function S.WeaponLocksEnabled()
	return false
end

function S.IsWeaponLocked(class)
	if isPVP() or not S.WeaponLocksEnabled() then return false end
	local r = S.WeaponUnlockRank(class)
	return r ~= nil and r > S.GroupRank(S.WEAPON_UPGRADE)
end

function S.WeaponPlanCount()
	local n = 0
	for r, list in ipairs(S.group.weaponPlan or {}) do n = n + #list end
	return n
end
-- }}}

-- Stat bonuses from all team upgrades (added in S.ComputeStats)
function S.GetGroupStats()
	local totals = {}
	if isPVP() then return totals end
	for i, up in ipairs(S.groupUpgrades) do
		local rank = S.GroupRank(up.id)
		if rank > 0 and up.stats then
			for k, v in pairs(up.stats) do
				totals[k] = (totals[k] or 0) + v * rank
			end
		end
	end
	return totals
end

function S.GetGroupStartCash()
	if isPVP() then return 0 end
	local total = 0
	for i, up in ipairs(S.groupUpgrades) do
		if up.startCash then
			total = total + up.startCash * S.GroupRank(up.id)
		end
	end
	return total
end

-- // Server {{{
if SERVER then
	util.AddNetworkString("sweeper_group_sync")
	util.AddNetworkString("sweeper_group_vote")
	util.AddNetworkString("sweeper_vtoken")

	S.cvar_tokensVictory = CreateConVar("jcms_vtokens_victory", "10", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"V Tokens the squad gets for finishing a map.", 0, 1000)
	S.cvar_tokensPerPlayer = CreateConVar("jcms_vtokens_perplayer", "4", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Extra V Tokens per additional sweeper who played the map.", 0, 1000)
	S.cvar_tokensEvac = CreateConVar("jcms_vtokens_evac", "2", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Extra V Tokens per sweeper who evacuated.", 0, 1000)
	S.cvar_tokensTerminalChance = CreateConVar("jcms_vtokens_terminal_chance", "0.35", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Chance (0-1) that hacking a terminal turns up V Tokens (1-3).", 0, 1)
	S.cvar_voteTime = CreateConVar("jcms_team_votetime", "40", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"How long a Team Upgrade vote lasts, in seconds.", 10, 300)
	util.AddNetworkString("sweeper_contract")
	cvars.AddChangeCallback("jcms_team_weaponlocks", function()
		timer.Simple(0, function() if S.RefreshWeaponShop then S.RefreshWeaponShop() end end)
	end, "sweeper_weaponlocks")

	local saveFile = "sweeper/group_" .. (game.SinglePlayer() and "solo" or "multiplayer") .. ".json"

	function S.GroupSave()
		file.CreateDir("sweeper")
		file.Write(saveFile, util.TableToJSON({ ranks = S.group.ranks, pool = S.group.pool, weaponPlan = S.group.weaponPlan }))
	end

	function S.GroupLoad()
		local txt = file.Read(saveFile, "DATA")
		local tbl = txt and util.JSONToTable(txt)
		S.group = { ranks = {}, pool = 0, weaponPlan = {} }
		if not tbl then return end
		if type(tbl.weaponPlan) == "table" then
			for r = 1, S.WEAPON_RANKS do
				local list = {}
				for i, c in ipairs(tbl.weaponPlan[r] or tbl.weaponPlan[tostring(r)] or {}) do
					if type(c) == "string" then list[#list + 1] = c end
				end
				S.group.weaponPlan[r] = list
			end
		end

		for id, up in pairs(S.groupById) do
			S.group.ranks[id] = math.Clamp(math.floor(tonumber(tbl.ranks and tbl.ranks[id]) or 0), 0, #up.costs)
		end
		S.group.pool = math.max(0, math.floor(tonumber(tbl.pool) or 0))
	end

	local function syncPayload()
		local v = S.group.vote
		return {
			ranks = S.group.ranks,
			pool = S.GroupPool(),
			weaponPlan = S.group.weaponPlan,
			vote = v and { endsAt = v.endsAt, options = v.options, tally = v.tally } or nil,
			contract = S.ContractPayload and S.ContractPayload() or nil,
		}
	end

	function S.GroupSync(ply)
		net.Start("sweeper_group_sync")
			net.WriteTable(syncPayload())
		if IsValid(ply) then net.Send(ply) else net.Broadcast() end
	end

	local function tellAll(msg, snd)
		local lines = S.TextChunks(msg)
		for i, p in ipairs(player.GetHumans()) do
			for j, line in ipairs(lines) do p:ChatPrint(line) end
			if snd then p:EmitSound(snd, 60, 110) end
		end
	end

	-- Re-apply stats to everyone who is alive in a mission (ranks changed)
	function S.GroupReapply()
		for i, ply in ipairs(player.GetHumans()) do
			local class = ply.sweeperClass
			if class and ply.sweeperTotals and S.GetActiveClass(ply) == class and ply:Alive() then
				local cd = S.GetClassData(ply, class)
				if cd then
					S.ApplyDelta(ply, class, ply.sweeperTotals, S.ComputeStats(class, cd.skills, cd.specs, ply))
				end
			end
		end
	end

	-- // V Tokens (squad pool) {{{
	-- `why` is shown in chat and in the popup
	function S.AddPoolTokens(amount, why)
		amount = math.floor(amount)
		if amount == 0 then return end
		S.group.pool = math.max(0, S.GroupPool() + amount)
		S.GroupSave()
		S.GroupSync()

		if amount > 0 then
			net.Start("sweeper_vtoken")
				net.WriteUInt(math.min(amount, 65535), 16)
				net.WriteString(why or "")
			net.Broadcast()
		end
	end

	-- Who played this mission (any class, not just the 4 with Implants)
	hook.Add("MapSweepersClassApplied", "sweeper_vtokensPlayed", function(ply)
		if jcms.director and not ply:IsBot() then
			ply.sweeperPlayedMission = true
		end
	end)

	-- Finishing a map
	function S.InstallTokenMissionEnd()
		if not (jcms and jcms.mission_End) or S.Wrapped(jcms, "TokenMissionEnd") then return end
		local orig = jcms.mission_End
		S._wrappedTokenMissionEnd = function(victory, aliveTeams, ...)
			-- Read before the gamemode clears the evac flags
			local evacuated = {}
			for i, ply in ipairs(player.GetHumans()) do
				evacuated[ply] = ply:GetNWBool("jcms_evacuated", false)
			end
			local resetsBefore = S.resetCount

			local rtn = { orig(victory, aliveTeams, ...) }

			local ok, err = pcall(function()
				local runEnded = S.resetCount ~= resetsBefore
				local played, evacs = 0, 0
				for i, ply in ipairs(player.GetHumans()) do
					if ply.sweeperPlayedMission then
						played = played + 1
						if evacuated[ply] then evacs = evacs + 1 end
					end
					ply.sweeperPlayedMission = nil
				end

				if victory and not runEnded and not isPVP() and played > 0 then
					local amount = S.cvar_tokensVictory:GetInt()
						+ (played - 1) * S.cvar_tokensPerPlayer:GetInt()
						+ evacs * S.cvar_tokensEvac:GetInt()
					S.AddPoolTokens(amount, evacs > 0 and "Map finished + evacuation bonus" or "Map finished")
					tellAll(string.format("[Team Upgrades] Map finished! The squad earned %d %s (pool: %d).",
						amount, S.tokenNamePlural, S.GroupPool()))
				end
			end)
			if not ok then ErrorNoHalt("[sweeper] V Token reward error: " .. tostring(err) .. "\n") end

			return unpack(rtn)
		end
		jcms.mission_End = S._wrappedTokenMissionEnd
		S.MarkWrapped(jcms, "TokenMissionEnd")
	end

	-- Terminals: each one can hold V Tokens, found when it's hacked open
	function S.InstallTokenTerminals()
		if not (jcms and jcms.terminal_Unlock) or S.Wrapped(jcms, "TerminalUnlock") then return end
		local orig = jcms.terminal_Unlock
		S._wrappedTerminalUnlock = function(ent, hacker, intrusive, ...)
			-- Locked Terminals modifier: the first finished hack only opens a second layer (sh_modifiers.lua)
			if S.ModTerminalLayer and S.ModTerminalLayer(ent, hacker, intrusive) then return end
			local firstUnlock = IsValid(ent) and ent:GetNWBool("jcms_terminal_locked", false) and not ent.sweeperTokenRolled
			local rtn = { orig(ent, hacker, intrusive, ...) }

			if firstUnlock and jcms.director and not isPVP() then
				ent.sweeperTokenRolled = true

				local finder = hacker
				if IsValid(finder) and not finder:IsPlayer() then finder = finder.jcms_owner end -- auto-hack device

				if IsValid(finder) and finder:IsPlayer() and math.random() < (S.TerminalTokenChance and S.TerminalTokenChance() or S.cvar_tokensTerminalChance:GetFloat()) then
					local amount = math.random(1, 3)
					ent:EmitSound("items/battery_pickup.wav", 75, 90)
					S.AddPoolTokens(amount, finder:Nick() .. " found them in a terminal")
					tellAll(string.format("[Team Upgrades] %s found %d %s in a terminal!", finder:Nick(), amount,
						amount == 1 and S.tokenName or S.tokenNamePlural))
				end
			end

			return unpack(rtn)
		end
		jcms.terminal_Unlock = S._wrappedTerminalUnlock
		S.MarkWrapped(jcms, "TerminalUnlock")
	end
	-- }}}

	-- // Voting {{{
	local function affordableOptions()
		local out = {}
		for i, up in ipairs(S.groupUpgrades) do
			local usable = not up.weapons or (S.WeaponLocksEnabled() and S.WeaponPlanCount() > 0) -- locks off / nothing to unlock = don't offer it
			if usable and S.GroupCanAfford(up.id) then table.insert(out, up.id) end
		end
		return out
	end

	local function eligibleVoters()
		local out = {}
		for i, p in ipairs(player.GetHumans()) do
			if p.sweeperNetReady then table.insert(out, p) end
		end
		return out
	end

	local function recount()
		local v = S.group.vote
		if not v then return end
		v.tally = {}
		for i, p in ipairs(player.GetHumans()) do
			local choice = v.ballots[p:SteamID64()]
			if choice then v.tally[choice] = (v.tally[choice] or 0) + 1 end
		end
	end

	function S.StartGroupVote()
		if S.group.vote or isPVP() then return false end
		local options = affordableOptions()
		if #options == 0 then return false end

		S.group.vote = {
			endsAt = CurTime() + S.cvar_voteTime:GetFloat(),
			options = options,
			ballots = {}, -- [sid64] = option id
			tally = {},
		}
		for i, p in ipairs(player.GetAll()) do
			p:SetNWString("sweeper_vote", "")
		end
		S.GroupSync()
		tellAll(string.format("[Team Upgrades] VOTE STARTED! The squad has %d %s. Open the TEAM UPGRADES tab to vote (%ds).",
			S.GroupPool(), S.tokenNamePlural, S.cvar_voteTime:GetInt()), "buttons/blip1.wav")
		return true
	end

	function S.EndGroupVote()
		local v = S.group.vote
		if not v then return end
		S.group.vote = nil
		S.lastVoteEnd = CurTime()
		recount()

		-- Most votes wins; ties are picked at random. No votes = save the tokens.
		local best, winners = 0, {}
		for id, count in pairs(v.tally) do
			if count > best then
				best, winners = count, { id }
			elseif count == best then
				table.insert(winners, id)
			end
		end
		local winner = #winners > 0 and winners[math.random(#winners)] or nil

		for i, p in ipairs(player.GetAll()) do
			p:SetNWString("sweeper_vote", "")
		end

		local up = winner and S.groupById[winner]
		if not up then
			S.voteChainDone = true
			tellAll(string.format("[Team Upgrades] Vote over: the squad is saving its %s (%d).", S.tokenNamePlural, S.GroupPool()))
			S.GroupSync()
			return
		end

		local cost = S.GroupNextCost(up.id)
		if not cost or cost > S.GroupPool() then -- shouldn't happen, but be safe
			S.GroupSync()
			return
		end

		S.group.pool = S.GroupPool() - cost
		S.group.ranks[up.id] = S.GroupRank(up.id) + 1

		tellAll(string.format("[Team Upgrades] Vote over: %s is now rank %d/%d! (%d votes, %d %s left)",
			up.name, S.GroupRank(up.id), #up.costs, best, S.GroupPool(), S.tokenNamePlural), "buttons/button9.wav")

		-- Armory Access: open up the next batch of weapons
		if up.weapons then
			local names = {}
			for i, c in ipairs(S.group.weaponPlan[S.GroupRank(up.id)] or {}) do names[#names + 1] = S.WeaponName(c) end
			if #names > 0 then
				tellAll("[Team Upgrades] New weapons in the shop: " .. table.concat(names, ", "))
			end
			S.RefreshWeaponShop()
		end

		-- Emergency Fund pays out right away if you're still in the lobby
		if up.startCash and not jcms.director then
			for i, p in ipairs(player.GetAll()) do
				p:SetNWInt("jcms_cash", p:GetNWInt("jcms_cash", 0) + up.startCash)
			end
		end

		S.GroupReapply()
		S.GroupSave()
		S.GroupSync()
	end

	net.Receive("sweeper_group_vote", function(len, ply)
		if not IsValid(ply) then return end
		if (ply.sweeperNextGroup or 0) > CurTime() then return end
		ply.sweeperNextGroup = CurTime() + 0.15

		local id = net.ReadString()
		local v = S.group.vote
		if not v then return end

		local valid = id == S.VOTE_SKIP
		for i, opt in ipairs(v.options) do
			if opt == id then valid = true end
		end
		if not valid then return end

		v.ballots[ply:SteamID64()] = id
		ply:SetNWString("sweeper_vote", id)
		recount()

		-- Everyone has voted: end early (short pause so the last vote shows)
		local all = true
		for i, p in ipairs(eligibleVoters()) do
			if not v.ballots[p:SteamID64()] then all = false break end
		end
		if all then
			v.endsAt = math.min(v.endsAt, CurTime() + 2)
		end

		S.GroupSync()
	end)

	-- Start votes at the start of each match (lobby), end them on time or when the mission launches
	local wasInMission = jcms and jcms.director ~= nil
	S.lobbyStart = S.lobbyStart or CurTime()
	timer.Create("sweeper_groupVote", 1, 0, function()
		if not jcms then return end
		local inMission = jcms.director ~= nil

		if inMission and not wasInMission then
			-- Mission launched: settle any running vote now
			if S.group.vote then S.EndGroupVote() end
		elseif wasInMission and not inMission then
			-- Back in the lobby: a new match is starting
			S.lobbyStart = CurTime()
			S.voteChainDone = false
		end
		wasInMission = inMission

		local v = S.group.vote
		if v then
			if CurTime() >= v.endsAt then S.EndGroupVote() end
			return
		end

		if inMission or S.voteChainDone or isPVP() then return end
		local voters = eligibleVoters()
		if #voters == 0 then return end
		if CurTime() - math.max(S.lobbyStart, S.firstReadyAt or 0) < 8 then return end -- let people load in
		if CurTime() - (S.lastVoteEnd or -100) < 4 then return end

		if not S.StartGroupVote() then
			S.voteChainDone = true -- nothing affordable
		end
	end)
	-- }}}

	-- // New Contract (mission reroll vote) {{{
	S.contract = S.contract or { used = 0, max = 0 }

	local function currentStreak()
		if jcms and jcms.runprogress and jcms.runprogress.winstreak then return jcms.runprogress.winstreak end
		return jcms and jcms.util_GetCurrentWinstreak and jcms.util_GetCurrentWinstreak() or 0
	end

	-- Why the mission can't be rerolled right now (nil = it can)
	function S.ContractBlocked()
		if not jcms then return "Not available" end
		if isPVP() then return "Not available in PvP" end
		if jcms.director or jcms.mission_generating then return "Only in the lobby" end
		if jcms.inSpecialMap then return "This map's mission can't be rerolled" end
		if jcms.mission_IsBossMission and jcms.mission_IsBossMission() then return "Boss missions can't be rerolled" end
		if S.contract.used >= S.contract.max then
			return S.contract.max == 0 and "No rerolls at this win streak" or "No rerolls left on this map"
		end
		return nil
	end

	function S.ContractPayload()
		local c = S.contract
		local v = c.vote
		return {
			used = c.used, max = c.max, cost = S.contractConfig.cost,
			blocked = S.ContractBlocked(),
			vote = v and { endsAt = v.endsAt, yes = v.yes, no = v.no, by = v.by } or nil,
		}
	end

	function S.ContractNewMap()
		S.contract.used = 0
		S.contract.max = S.ContractMaxRerolls(currentStreak())
		S.contract.vote = nil
		S.GroupSync()
	end

	local function contractRecount()
		local v = S.contract.vote
		if not v then return end
		v.yes, v.no = 0, 0
		for i, p in ipairs(player.GetHumans()) do
			local b = v.ballots[p:SteamID64()]
			if b == true then v.yes = v.yes + 1 elseif b == false then v.no = v.no + 1 end
		end
	end

	function S.ContractStartVote(ply)
		if S.contract.vote then return false, "A New Contract vote is already running." end
		local why = S.ContractBlocked()
		if why then return false, why .. "." end
		if S.GroupPool() < S.contractConfig.cost then
			return false, string.format("The squad needs %d %s for a New Contract.", S.contractConfig.cost, S.tokenNamePlural)
		end

		S.contract.vote = {
			endsAt = CurTime() + S.contractConfig.voteTime,
			by = IsValid(ply) and ply:Nick() or "Someone",
			ballots = {}, yes = 0, no = 0,
		}
		if IsValid(ply) then S.contract.vote.ballots[ply:SteamID64()] = true end
		contractRecount()
		S.GroupSync()
		tellAll(string.format("[New Contract] %s wants to reroll the mission for %d %s (%d/%d rerolls used). Vote in the TEAM UPGRADES tab (%ds).",
			S.contract.vote.by, S.contractConfig.cost, S.tokenNamePlural, S.contract.used, S.contract.max, S.contractConfig.voteTime), "buttons/blip1.wav")
		return true
	end

	function S.ContractEndVote()
		local v = S.contract.vote
		if not v then return end
		S.contract.vote = nil
		contractRecount()

		if v.yes <= v.no then
			tellAll(string.format("[New Contract] Vote failed (%d yes / %d no). Keeping the current mission.", v.yes, v.no))
			S.GroupSync()
			return
		end

		local why = S.ContractBlocked()
		if why or S.GroupPool() < S.contractConfig.cost then
			tellAll("[New Contract] Vote passed, but the mission can't be rerolled now" .. (why and (": " .. why) or ".") )
			S.GroupSync()
			return
		end

		-- Reroll, trying for a different mission / faction than the current one
		local world = game.GetWorld()
		local oldType, oldFaction = world:GetNWString("jcms_missiontype", ""), world:GetNWString("jcms_missionfaction", "")
		for attempt = 1, 8 do
			jcms.mission_Randomize()
			if world:GetNWString("jcms_missiontype", "") ~= oldType or world:GetNWString("jcms_missionfaction", "") ~= oldFaction then break end
		end

		S.group.pool = S.GroupPool() - S.contractConfig.cost
		S.contract.used = S.contract.used + 1
		S.GroupSave()
		S.GroupSync()

		net.Start("sweeper_contract")
			net.WriteString(world:GetNWString("jcms_missiontype", ""))
			net.WriteString(world:GetNWString("jcms_missionfaction", ""))
			net.WriteUInt(S.contract.max - S.contract.used, 4)
		net.Broadcast()
		for i, p in ipairs(player.GetHumans()) do p:EmitSound("ambient/levels/labs/coinslot1.wav", 60, 100) end
	end

	-- action: 1 = propose, 2 = vote yes, 3 = vote no
	net.Receive("sweeper_contract", function(len, ply)
		if not IsValid(ply) then return end
		if (ply.sweeperNextContract or 0) > CurTime() then return end
		ply.sweeperNextContract = CurTime() + 0.3
		local action = net.ReadUInt(2)

		if action == 1 then
			local ok, msg = S.ContractStartVote(ply)
			if not ok and msg then ply:ChatPrint("[New Contract] " .. msg) end
			return
		end

		local v = S.contract.vote
		if not v then return end
		v.ballots[ply:SteamID64()] = (action == 2)
		contractRecount()

		local all = true
		for i, p in ipairs(eligibleVoters()) do
			if v.ballots[p:SteamID64()] == nil then all = false break end
		end
		if all then v.endsAt = math.min(v.endsAt, CurTime() + 1.5) end
		S.GroupSync()
	end)

	concommand.Add("jcms_newcontract", function(ply)
		local ok, msg = S.ContractStartVote(ply)
		if not ok and msg then
			if IsValid(ply) then ply:ChatPrint("[New Contract] " .. msg) else print("[New Contract] " .. msg) end
		end
	end, nil, "Start a New Contract vote (reroll the lobby's mission for V Tokens).")

	-- New map (back in the lobby) = fresh rerolls; the vote ends on time or when the mission launches
	local contractInMission = jcms and jcms.director ~= nil
	local lastBlocked
	timer.Create("sweeper_contract", 1, 0, function()
		if not jcms then return end
		local inMission = jcms.director ~= nil
		if contractInMission and not inMission then
			timer.Simple(0.5, S.ContractNewMap) -- after the gamemode picks the new mission
		elseif inMission and not contractInMission then
			S.contract.vote = nil
			S.GroupSync()
		end
		contractInMission = inMission

		local v = S.contract.vote
		if v and CurTime() >= v.endsAt then S.ContractEndVote() end

		local b = S.ContractBlocked() or ""
		if b ~= lastBlocked then
			lastBlocked = b
			S.GroupSync()
		end
	end)
	hook.Add("InitPostEntity", "sweeper_contract", function()
		timer.Simple(2, S.ContractNewMap)
	end)
	if S._groupLoaded then S.ContractNewMap() end -- Lua refresh
	-- }}}

	-- Game over: wipe upgrades and the token pool
	function S.GroupReset()
		local had = S.GroupPool() > 0
		for id, rank in pairs(S.group.ranks) do
			if (tonumber(rank) or 0) > 0 then had = true end
		end

		S.group.ranks, S.group.pool, S.group.vote = {}, 0, nil
		S.BuildWeaponPlan() -- new run, new random weapon batches
		S.RefreshWeaponShop()
		S.GroupReapply()
		S.GroupSave()
		S.GroupSync()
		if had then
			tellAll("[Team Upgrades] The run is over. All team upgrades, weapon unlocks and " .. S.tokenNamePlural .. " have been reset.")
		end
	end

	-- Starting cash: add Emergency Fund
	function S.InstallGroupCash()
		if not (jcms and jcms.runprogress_GetStartingCash) or S.Wrapped(jcms, "StartCash") then return end
		local orig = jcms.runprogress_GetStartingCash
		S._wrappedStartCash = function(...)
			local cash = orig(...)
			if isPVP() then return cash end
			return cash + S.GetGroupStartCash()
		end
		jcms.runprogress_GetStartingCash = S._wrappedStartCash
		S.MarkWrapped(jcms, "StartCash")
	end

	-- // Armory Access: weapon batches, hiding locked guns from the shop {{{
	local configFile = "sweeper/weapon_unlocks.json"
	S.weaponConfig = S.weaponConfig or { free = table.Copy(S.weaponFreeDefaults), ranks = {} }

	function S.LoadWeaponConfig()
		local txt = file.Read(configFile, "DATA")
		local tbl = txt and util.JSONToTable(txt)
		-- Missing, broken, or the old per-weapon list format: write a fresh config
		if type(tbl) ~= "table" or (tbl.free == nil and tbl.ranks == nil) then
			S.weaponConfig = {
				_help = "free: always in the shop. ranks: 5 lists of weapon classes, one per Armory Access rank. Leave ranks empty for random batches each run.",
				free = table.Copy(S.weaponFreeDefaults),
				ranks = { {}, {}, {}, {}, {} },
			}
			file.CreateDir("sweeper")
			file.Write(configFile, util.TableToJSON(S.weaponConfig, true))
			return
		end
		S.weaponConfig = { _help = tbl._help, free = {}, ranks = {} }
		for i, c in ipairs(tbl.free or {}) do
			if type(c) == "string" then table.insert(S.weaponConfig.free, c) end
		end
		for r = 1, S.WEAPON_RANKS do
			local list = {}
			for i, c in ipairs((tbl.ranks or {})[r] or {}) do
				if type(c) == "string" then list[#list + 1] = c end
			end
			S.weaponConfig.ranks[r] = list
		end
	end

	-- Decide which weapons each rank unlocks for this run
	function S.BuildWeaponPlan()
		local plan = {}
		local fixed = false
		for r = 1, S.WEAPON_RANKS do
			if #(S.weaponConfig.ranks[r] or {}) > 0 then fixed = true end
		end

		if fixed then
			for r = 1, S.WEAPON_RANKS do plan[r] = table.Copy(S.weaponConfig.ranks[r] or {}) end
		else
			-- Random: every weapon in the shop except the free ones, shuffled into 5 batches
			local free = {}
			for i, c in ipairs(S.weaponConfig.free or {}) do free[c] = true end
			local pool = {}
			for class, price in pairs((jcms and jcms.weapon_prices) or {}) do
				if (tonumber(price) or 0) > 0 and not free[class] then pool[#pool + 1] = class end
			end
			table.sort(pool) -- stable order before shuffling
			for i = #pool, 2, -1 do
				local j = math.random(i)
				pool[i], pool[j] = pool[j], pool[i]
			end
			for r = 1, S.WEAPON_RANKS do plan[r] = {} end
			for i, class in ipairs(pool) do
				table.insert(plan[(i - 1) % S.WEAPON_RANKS + 1], class)
			end
		end

		S.group.weaponPlan = plan
		S.GroupSave()
	end

	-- Re-send every shop price (the wrapped sender hides locked ones)
	function S.RefreshWeaponShop()
		if not (jcms and jcms.net_SendWeapon and jcms.weapon_prices) then return end
		local seen = {}
		for r, list in ipairs(S.group.weaponPlan or {}) do
			for i, class in ipairs(list) do
				if not seen[class] then
					seen[class] = true
					jcms.net_SendWeapon(class, tonumber(jcms.weapon_prices[class]) or 0, "all")
				end
			end
		end
	end

	function S.InstallWeaponLocks()
		if not jcms then return end

		if jcms.net_SendWeaponPrices and not S.Wrapped(jcms, "SendPrices") then
			local orig = jcms.net_SendWeaponPrices
			S._wrappedSendPrices = function(weps, to, ...)
				if type(weps) == "table" then
					local filtered = {}
					for class, price in pairs(weps) do
						if not S.IsWeaponLocked(class) then filtered[class] = price end
					end
					weps = filtered
				end
				return orig(weps, to, ...)
			end
			jcms.net_SendWeaponPrices = S._wrappedSendPrices
			S.MarkWrapped(jcms, "SendPrices")
		end

		if jcms.net_SendWeapon and not S.Wrapped(jcms, "SendWeapon") then
			local orig = jcms.net_SendWeapon
			S._wrappedSendWeapon = function(class, cost, to, ...)
				if S.IsWeaponLocked(class) then cost = 0 end
				return orig(class, cost, to, ...)
			end
			jcms.net_SendWeapon = S._wrappedSendWeapon
			S.MarkWrapped(jcms, "SendWeapon")
		end

		local function blockLocked(fname)
			local current = jcms[fname]
			S._wrappedBuy = S._wrappedBuy or {}
			if not current or S.Wrapped(jcms, "Buy_" .. fname) then return end
			local wrapped = function(ply, class, ...)
				if S.IsWeaponLocked(class) then
					if IsValid(ply) then
						ply:ChatPrint(string.format("[Team Upgrades] %s is locked. The squad unlocks it with Armory Access (%s) in TEAM UPGRADES.",
							S.WeaponName(class), S.tokenNamePlural))
					end
					return false
				end
				return current(ply, class, ...)
			end
			S._wrappedBuy[fname] = wrapped
			S.MarkWrapped(jcms, "Buy_" .. fname)
			jcms[fname] = wrapped
		end
		blockLocked("spawnmenu_PurchaseLoadoutGun")
		blockLocked("spawnmenu_PurchaseAndGiveGun")
	end

	-- Clients may have received prices before the lock list loaded: re-send the locked ones as hidden
	hook.Add("jcms_PlayerNetReady", "sweeper_weaponLocks", function(ply)
		timer.Simple(0.5, function()
			if not IsValid(ply) or not (jcms and jcms.net_SendWeapon) then return end
			for r, list in ipairs(S.group.weaponPlan or {}) do
				for i, class in ipairs(list) do
					if S.IsWeaponLocked(class) then jcms.net_SendWeapon(class, 0, ply) end
				end
			end
		end)
	end)
	-- }}}

	local function installAll()
		S.InstallWeaponLocks()
		S.InstallGroupCash()
		S.InstallTokenMissionEnd()
		S.InstallTokenTerminals()
	end

	hook.Add("Initialize", "sweeper_group", function()
		S.LoadWeaponConfig()
		S.GroupLoad()
		installAll()
	end)
	hook.Add("InitPostEntity", "sweeper_group", function()
		installAll()
		-- The gamemode loads weapon prices on InitPostEntity; roll this run's weapon batches after that
		timer.Simple(1, function()
			if S.WeaponPlanCount() == 0 then S.BuildWeaponPlan() end
			S.RefreshWeaponShop()
			S.GroupSync()
		end)
	end)

	hook.Add("jcms_PlayerNetReady", "sweeper_group", function(ply)
		ply.sweeperNetReady = true
		if not ply:IsBot() then S.firstReadyAt = S.firstReadyAt or CurTime() end
		ply:SetNWString("sweeper_vote", "")
		S.GroupSync(ply)
	end)

	-- // Admin {{{
	local function isAdmin(ply) return not IsValid(ply) or ply:IsAdmin() end

	concommand.Add("jcms_team_reset", function(ply)
		if not isAdmin(ply) then return end
		S.GroupReset()
		print("[Team Upgrades] Reset.")
	end, nil, "Admin: wipe all team upgrades and the V Token pool.")

	concommand.Add("jcms_team_setrank", function(ply, cmd, args)
		if not isAdmin(ply) then return end
		local up = S.groupById[args[1] or ""]
		if not up then
			local ids = {}
			for i, u in ipairs(S.groupUpgrades) do table.insert(ids, u.id) end
			print("[Team Upgrades] Unknown id. Valid: " .. table.concat(ids, ", "))
			return
		end
		S.group.ranks[up.id] = math.Clamp(math.floor(tonumber(args[2]) or 0), 0, #up.costs)
		if up.weapons then S.RefreshWeaponShop() end
		S.GroupReapply()
		S.GroupSave()
		S.GroupSync()
		print(string.format("[Team Upgrades] %s set to rank %d", up.name, S.group.ranks[up.id]))
	end, nil, "Admin: jcms_team_setrank <id> <rank>")

	concommand.Add("jcms_givetokens", function(ply, cmd, args)
		if not isAdmin(ply) then return end
		S.AddPoolTokens(tonumber(args[1]) or 0, "Admin")
		print(string.format("[Team Upgrades] Squad pool: %d %s", S.GroupPool(), S.tokenNamePlural))
	end, nil, "Admin: jcms_givetokens <amount> - add (or remove) V Tokens from the squad pool.")

	concommand.Add("jcms_team_startvote", function(ply)
		if not isAdmin(ply) then return end
		if S.group.vote then print("[Team Upgrades] A vote is already running.") return end
		S.voteChainDone = false
		if not S.StartGroupVote() then print("[Team Upgrades] The squad can't afford any upgrade.") end
	end, nil, "Admin: start a Team Upgrade vote now.")
	-- }}}

	-- // Admin: Armory Access {{{
	concommand.Add("jcms_weaponplan", function(ply)
		if IsValid(ply) and not ply:IsAdmin() then return end
		local rank = S.GroupRank(S.WEAPON_UPGRADE)
		for r, list in ipairs(S.group.weaponPlan or {}) do
			print(string.format("  Rank %d %s: %s", r, r <= rank and "(UNLOCKED)" or "", table.concat(list, ", ")))
		end
	end, nil, "Admin: show which weapons each Armory Access rank unlocks this run.")

	concommand.Add("jcms_weaponplan_reroll", function(ply)
		if IsValid(ply) and not ply:IsAdmin() then return end
		S.LoadWeaponConfig()
		S.BuildWeaponPlan()
		S.RefreshWeaponShop()
		S.GroupSync()
		print("[Team Upgrades] Weapon batches re-rolled (or reloaded from weapon_unlocks.json).")
	end, nil, "Admin: re-roll the random weapon batches / reload weapon_unlocks.json.")
	-- }}}

	-- Lua refresh
	if jcms and jcms.runprogress_GetStartingCash then
		if not S._groupLoaded then S.LoadWeaponConfig() S.GroupLoad() end
		installAll()
		for i, ply in ipairs(player.GetHumans()) do ply.sweeperNetReady = true end
		S.GroupSync()
	end
	S._groupLoaded = true
end
-- }}}

-- // Client {{{
if CLIENT then
	local colText   = Color(235, 235, 235)
	local colDim    = Color(120, 120, 120)
	local colToken  = Color(190, 140, 255)
	local function colBright() return (jcms and jcms.color_bright) or Color(255, 0, 0) end
	local function colDark()   return (jcms and jcms.color_dark) or Color(30, 12, 12) end
	local function colAlt()    return (jcms and jcms.color_bright_alt) or Color(64, 180, 255) end

	-- Map Sweepers menu look (same toolkit as the Implants menu): cut-corner panels/buttons, jcms_* fonts,
	-- theme colours, striped + noise fills. V Token things keep their purple so they stand out.
	local function colDarkAlt() return (jcms and jcms.color_dark_alt) or Color(10, 20, 30) end
	local function colPulse()   return (jcms and jcms.color_pulsing) or colBright() end
	local function fnt(name, fallback) return (jcms and jcms.color_bright) and name or fallback end
	local tokenDark = Color(30, 10, 50)
	local function polyFilled(x, y, w, h, pad)
		if jcms and jcms.hud_DrawFilledPolyButton then return jcms.hud_DrawFilledPolyButton(x, y, w, h, pad) end
		surface.DrawRect(x, y, w, h)
	end
	local function polyHollow(x, y, w, h, pad)
		if jcms and jcms.hud_DrawHollowPolyButton then return jcms.hud_DrawHollowPolyButton(x, y, w, h, pad) end
		surface.DrawOutlinedRect(x, y, w, h)
	end
	local function striped(x, y, w, h, sc, off)
		if jcms and jcms.hud_DrawStripedRect and w > 0 then jcms.hud_DrawStripedRect(x, y, w, h, sc or 32, off or 0) end
	end
	local function noise(x, y, w, h)
		if jcms and jcms.hud_DrawNoiseRect and w > 0 then jcms.hud_DrawNoiseRect(x, y, w, h) else surface.DrawRect(x, y, w, h) end
	end
	-- Cut-corner panel: dark body, optional tint, outline
	local function panelBox(w, h, outline, tint, pad)
		local dark = colDark()
		pad = pad or 10
		surface.SetDrawColor(dark.r, dark.g, dark.b, 200)
		polyFilled(0, 0, w, h, pad)
		if tint then surface.SetDrawColor(tint) polyFilled(0, 0, w, h, pad) end
		surface.SetDrawColor(outline)
		polyHollow(0, 0, w, h, pad)
	end
	-- Token-coloured button: filled when active, outlined otherwise, brighter on hover
	local function tokenButton(self, w, h, text, active)
		local hov = self:IsHovered()
		local font = fnt("jcms_small_bolder", "sweeper_small")
		if active then
			surface.SetDrawColor(colToken)
			polyFilled(0, 0, w, h, math.min(w / 4, 8))
			draw.SimpleText(text, font, w / 2 - 1, h / 2 - 1, tokenDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			if hov then surface.SetDrawColor(colToken.r, colToken.g, colToken.b, 50) polyFilled(0, 0, w, h, math.min(w / 4, 8)) end
			surface.SetDrawColor(colToken)
			polyHollow(0, 0, w, h, math.min(w / 4, 8))
			draw.SimpleText(text, font, w / 2 - 1, h / 2 - 1, colToken, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return true
	end
	-- Section header like the gamemode's separators: title + striped rule
	local function paintSection(w, h, title, sub)
		local bright = colBright()
		surface.SetFont(fnt("jcms_medium", "sweeper_title"))
		local tw = surface.GetTextSize(title)
		draw.SimpleText(title, fnt("jcms_medium", "sweeper_title"), 2, 0, bright)
		surface.SetDrawColor(bright.r, bright.g, bright.b, 50)
		striped(tw + 14, 9, w - tw - 16, 8, 32)
		draw.SimpleText(sub, fnt("jcms_small", "sweeper_small"), w - 2, h - 2, ColorAlpha(bright, 120), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end

	local function tokenStr(n)
		return string.format("%d %s", n, n == 1 and S.tokenName or S.tokenNamePlural)
	end

	local function myVote()
		local me = LocalPlayer()
		return IsValid(me) and me:GetNWString("sweeper_vote", "") or ""
	end

	local function voteOpen()
		local v = S.group.vote
		return v and v.endsAt > CurTime() - 1 and v or nil
	end

	-- Draws a small "V" token badge centred at x, y
	local function drawToken(x, y, r)
		draw.NoTexture()
		surface.SetDrawColor(colToken)
		local poly = {}
		for i = 0, 5 do
			local a = math.rad(i * 60 - 90)
			poly[#poly + 1] = { x = x + math.cos(a) * r, y = y + math.sin(a) * r }
		end
		surface.DrawPoly(poly)
		draw.SimpleText("V", fnt("jcms_small_bolder", "sweeper_small"), x, y, tokenDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	net.Receive("sweeper_group_sync", function()
		local tbl = net.ReadTable()
		local hadVote = S.group and S.group.vote ~= nil
		local hadContractVote = S.group and S.group.contract and S.group.contract.vote ~= nil
		S.group = { ranks = tbl.ranks or {}, pool = tbl.pool or 0, vote = tbl.vote, weaponPlan = tbl.weaponPlan or {}, contract = tbl.contract }
		if not (tbl.contract and tbl.contract.vote) then S.contractMyBallot = nil end
		if tbl.contract and tbl.contract.vote and not hadContractVote then
			S.contractVoteStartedAt = RealTime()
			surface.PlaySound("buttons/blip1.wav")
		end
		S.clVersion = (S.clVersion or 0) + 1 -- refresh cached stat totals

		if tbl.vote and not hadVote then
			S.voteStartedAt = RealTime()
			surface.PlaySound("buttons/blip1.wav")
		end
		if IsValid(S.lobbyMenu) and S.lobbyMenu.Refresh then S.lobbyMenu:Refresh() end
		if IsValid(S.menu) and S.menu.Refresh then S.menu:Refresh() end
		if IsValid(S.groupMenu) and S.groupMenu.Refresh then S.groupMenu:Refresh() end
	end)

	local function contractVote()
		local c = S.group and S.group.contract
		local v = c and c.vote
		return v and v.endsAt > CurTime() - 1 and v or nil
	end

	-- Reroll done: tell everyone what the new mission is (names are localized on the client)
	net.Receive("sweeper_contract", function()
		local mtype, faction, left = net.ReadString(), net.ReadString(), net.ReadUInt(4)
		local mname = language.GetPhrase("jcms." .. mtype)
		if mname == "jcms." .. mtype then mname = mtype end
		local fname = language.GetPhrase("jcms." .. faction)
		if fname == "jcms." .. faction then fname = faction end
		chat.AddText(colToken, "[New Contract] ", color_white, "Contract signed! New mission: ", colToken, mname,
			color_white, " vs ", colToken, fname, color_white, string.format("  (%d reroll%s left on this map)", left, left == 1 and "" or "s"))
	end)

	-- Glow around the TEAM UPGRADES lobby tab while a vote runs (called from cl_skills.lua)
	function S.PaintGroupTabGlow(x, y, w, h)
		local cv = contractVote()
		if not voteOpen() and not cv then return end
		local voted = (not voteOpen() or myVote() ~= "") and (not cv or S.contractMyBallot ~= nil)
		local pulse = (math.sin(RealTime() * (voted and 3 or 6)) + 1) / 2
		local strength = voted and 0.35 or 1

		for i = 1, 6 do
			local a = (70 - i * 10) * (0.4 + pulse * 0.6) * strength
			surface.SetDrawColor(colToken.r, colToken.g, colToken.b, a)
			polyHollow(x - i, y - i, w + i * 2, h + i * 2, 8 + i)
		end
		surface.SetDrawColor(colToken.r, colToken.g, colToken.b, (40 + pulse * 60) * strength)
		polyFilled(x, y, w, h, 8)

		if not voted then
			draw.SimpleText("VOTE!", fnt("jcms_small_bolder", "sweeper_small"), x + w - 4, y + h + 2, ColorAlpha(colToken, 150 + pulse * 105), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
		end
	end

	-- "+10 V TOKENS" popup
	local popups = {}
	net.Receive("sweeper_vtoken", function()
		local amount = net.ReadUInt(16)
		local why = net.ReadString()
		table.insert(popups, { amount = amount, why = why, t = CurTime() })
		surface.PlaySound("items/battery_pickup.wav")
	end)

	-- Pop-ups float in the gamemode's top HUD panel, in the HUD's alternate colour
	S.AddHud("vtokens", "top", function(ply, hudAlpha)
		if #popups == 0 then return end
		local ct = CurTime()
		local y = 560
		for i = #popups, 1, -1 do
			local p = popups[i]
			local age = ct - p.t
			if age > 4 then
				table.remove(popups, i)
			else
				local a = age > 3 and (4 - age) or 1
				local rise = math.min(age, 0.3) / 0.3
				local py = y - (1 - rise) * 60
				surface.SetAlphaMultiplier(hudAlpha * a)
				S.HudGlowText(string.format("+%d SQUAD %s", p.amount, string.upper(p.amount == 1 and S.tokenName or S.tokenNamePlural)),
					"jcms_hud_medium", 0, py, jcms.color_bright_alt, jcms.color_dark_alt, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				if p.why ~= "" then
					S.HudGlowText(string.upper(p.why), "jcms_hud_small", 0, py + 72, jcms.color_bright_alt, jcms.color_dark_alt, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 6)
				end
				y = y + 140
			end
		end
		surface.SetAlphaMultiplier(hudAlpha)
	end)

	local function sendVote(id)
		net.Start("sweeper_group_vote")
			net.WriteString(id)
		net.SendToServer()
	end

	-- Builds the Team Upgrades page inside `root`
	function S.BuildGroupMenu(root)
		root:Clear()
		S.groupMenu = root

		root.Paint = function(self, w, h)
			local bright = colBright()
			-- See-through like the gamemode's lobby tabs, with the pulsing cut-corner outline
			surface.SetDrawColor(colPulse())
			polyHollow(0, 0, w, h, 16)

			local big = fnt("jcms_big", "sweeper_title")
			surface.SetFont(big)
			local tw, th = surface.GetTextSize("TEAM UPGRADES")
			surface.SetDrawColor(bright.r, bright.g, bright.b, 30)
			noise(12, 6, tw + 16, th)
			draw.SimpleText("TEAM UPGRADES", big, 20, 6, bright)

			-- Squad pool badge (top right)
			local pool = S.GroupPool()
			local poolText = "SQUAD POOL: " .. string.upper(tokenStr(pool))
			local med = fnt("jcms_medium", "sweeper_med")
			surface.SetFont(med)
			local pw = surface.GetTextSize(poolText) + 44
			local px, py, ph = w - 16 - pw, 10, 30
			surface.SetDrawColor(colToken)
			polyHollow(px, py, pw, ph, 8)
			drawToken(px + 16, py + ph / 2, 9)
			draw.SimpleText(poolText, med, px + 30, py + ph / 2 - 1, colToken, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			local v = voteOpen()
			local small = fnt("jcms_small", "sweeper_small")
			if not v then
				draw.SimpleText("Earned by finishing maps and hacking terminals", small, w - 16, py + ph + 4, ColorAlpha(bright, 110), TEXT_ALIGN_RIGHT)
			end

			if jcms and jcms.util_IsPVP and jcms.util_IsPVP() then
				draw.SimpleText("TEAM UPGRADES ARE DISABLED IN PVP.", fnt("jcms_small_bolder", "sweeper_small"), 20, 46, bright)
			elseif v then
				local pulse = (math.sin(RealTime() * 5) + 1) / 2
				local left = math.max(0, math.ceil(v.endsAt - CurTime()))
				draw.SimpleText(string.format("VOTE IN PROGRESS  -  %ds  -  %s", left,
					myVote() ~= "" and "VOTE CAST" or "PICK AN UPGRADE"),
					fnt("jcms_small_bolder", "sweeper_med"), 20, 46, ColorAlpha(colToken, 170 + 85 * pulse))
			else
				draw.SimpleText("The squad votes on an upgrade at the start of each match.", small, 20, 46, ColorAlpha(bright, 200))
			end
			surface.SetDrawColor(bright.r, bright.g, bright.b, 50)
			striped(16, 64, w - 32, 3, 32)
			return true
		end

		-- SAVE TOKENS vote button (only during a vote)
		local skip = root:Add("DButton")
		skip:SetText("")
		skip:SetSize(170, 24)
		skip:SetPos(root:GetWide() - 16 - 170, 44)
		skip.Paint = function(self, w, h)
			local v = voteOpen()
			if not v then return true end
			local n = v.tally and v.tally[S.VOTE_SKIP] or 0
			return tokenButton(self, w, h, string.format("SAVE TOKENS (%d)", n), myVote() == S.VOTE_SKIP)
		end
		skip.DoClick = function()
			if not voteOpen() then return end
			sendVote(S.VOTE_SKIP)
			surface.PlaySound("buttons/button14.wav")
		end

		local scroll = root:Add("DScrollPanel")
		scroll:SetPos(12, 76)
		scroll:SetSize(root:GetWide() - 24, root:GetTall() - 88)

		-- Match the gamemode's own scrollbars (thin grip, no buttons, no track)
		local vbar = scroll:GetVBar()
		if IsValid(vbar) then
			vbar.Paint = function() return true end
			vbar:SetHideButtons(true)
			if jcms and jcms.paint_ScrollGrip then vbar.btnGrip.Paint = jcms.paint_ScrollGrip end
		end

		local cols, gap = 2, 10
		local cardW = math.floor((scroll:GetWide() - 16 - gap * (cols - 1)) / cols)
		local cardH = 112

		local function isOption(id)
			local v = voteOpen()
			if not v then return false end
			for i, opt in ipairs(v.options or {}) do
				if opt == id then return true end
			end
			return false
		end

		-- // NEW CONTRACT strip (reroll the mission) {{{
		local function sendContract(action)
			net.Start("sweeper_contract")
				net.WriteUInt(action, 2)
			net.SendToServer()
		end
		if S.group.contract and S.group.contract.vote == nil then S.contractMyBallot = nil end

		local strip = scroll:Add("DPanel")
		strip:SetPos(0, 0)
		strip:SetSize(scroll:GetWide() - 16, 64)
		strip.Paint = function(self, w, h)
			local c = S.group.contract or { used = 0, max = 0, cost = S.contractConfig.cost }
			local v = contractVote()
			local bright, alt = colBright(), colAlt()
			local pulse = (math.sin(RealTime() * 5) + 1) / 2
			local small = fnt("jcms_small", "sweeper_small")
			local outline = v and colToken or (c.blocked and ColorAlpha(bright, 45) or alt)
			panelBox(w, h, outline, v and ColorAlpha(colToken, 20 + 20 * pulse) or nil, 10)

			draw.SimpleText("NEW CONTRACT", fnt("jcms_medium", "sweeper_med"), 12, 3, v and colToken or bright)
			draw.SimpleText(string.format("Reroll this map's mission for %d %s.  Rerolls: %d / %d this map (fewer at higher win streaks).",
				c.cost or S.contractConfig.cost, S.tokenNamePlural, c.used or 0, c.max or 0), small, 12, 28, ColorAlpha(bright, 190))
			if v then
				draw.SimpleText(string.format("%s proposed it  -  %ds left  -  %d yes / %d no", v.by or "?", math.max(0, math.ceil(v.endsAt - CurTime())), v.yes or 0, v.no or 0),
					small, 12, 45, colToken)
			elseif c.blocked then
				draw.SimpleText(c.blocked, small, 12, 45, ColorAlpha(bright, 90))
			elseif S.GroupPool() < (c.cost or 0) then
				draw.SimpleText(string.format("need %d more %s", (c.cost or 0) - S.GroupPool(), S.tokenNamePlural), small, 12, 45, ColorAlpha(bright, 90))
			else
				draw.SimpleText("Anyone can propose it; the squad votes (majority yes).", small, 12, 45, alt)
			end
			return true
		end

		local function stripButton(x, wBtn, label, onClick, visible)
			local b = strip:Add("DButton")
			b:SetText("")
			b:SetSize(wBtn, 26)
			b:SetPos(x, 19)
			b.Paint = function(self, w, h)
				if not visible() then return true end
				return tokenButton(self, w, h, label(), self.isActive and self.isActive())
			end
			b.DoClick = function(self)
				if not visible() then return end
				onClick(self)
			end
			return b
		end

		local sw = strip:GetWide()
		local canPropose = function()
			local c = S.group.contract
			return c and not contractVote() and not c.blocked and S.GroupPool() >= (c.cost or 0)
		end
		stripButton(sw - 10 - 190, 190, function() return string.format("PROPOSE  (%d %s)", S.contractConfig.cost, S.tokenNamePlural) end,
			function() sendContract(1) S.contractMyBallot = true surface.PlaySound("buttons/button14.wav") end, canPropose)
		local yes = stripButton(sw - 10 - 190, 90, function() local v = contractVote() return string.format("YES (%d)", v and v.yes or 0) end,
			function() sendContract(2) S.contractMyBallot = true surface.PlaySound("buttons/button14.wav") end, function() return contractVote() ~= nil end)
		yes.isActive = function() return S.contractMyBallot == true end
		local no = stripButton(sw - 10 - 90, 90, function() local v = contractVote() return string.format("NO (%d)", v and v.no or 0) end,
			function() sendContract(3) S.contractMyBallot = false surface.PlaySound("buttons/button14.wav") end, function() return contractVote() ~= nil end)
		no.isActive = function() return S.contractMyBallot == false end
		-- }}}

		-- // MISSION MODIFIERS panel (sh_modifiers.lua) {{{
		local modPanel = scroll:Add("DPanel")
		modPanel:SetPos(0, 72)
		modPanel:SetSize(scroll:GetWide() - 16, 140)
		modPanel.Paint = function(self, w, h)
			local list = (S.mods and S.mods.list) or {}
			local bright, alt = colBright(), colAlt()
			local small, bold = fnt("jcms_small", "sweeper_small"), fnt("jcms_small_bolder", "sweeper_med")
			local hasWeather = (S.mods and ((S.mods.plannedWeather or "") ~= "" or (S.mods.weather or "") ~= ""))
			panelBox(w, h, (#list > 0 or hasWeather) and alt or ColorAlpha(bright, 60), nil, 10)
			draw.SimpleText("MISSION MODIFIERS", fnt("jcms_medium", "sweeper_med"), 12, 3, bright)
			draw.SimpleText("Rolled with each mission, weather too. Negative ones pay bonus " .. S.tokenNamePlural .. " on victory. New Contract rerolls them.",
				small, w - 12, 9, ColorAlpha(bright, 110), TEXT_ALIGN_RIGHT)
			local y = 32
			local sf, sfFaction = S.GetSubfaction and S.GetSubfaction(S.mods and S.mods.subfaction)
			if sf then
				local fc = (jcms and jcms.factions_GetColor) and jcms.factions_GetColor(sfFaction) or bright
				draw.SimpleText("SUB-FACTION  " .. string.upper(sf.name), bold, 12, y, fc)
				draw.SimpleText(sf.desc, small, 230, y + 1, ColorAlpha(bright, 190))
				y = y + 18
			end
			-- Weather: the rolled forecast before the mission, what's actually running during it
			local wClass = (S.mods and S.mods.inMission and (S.mods.weather or "") ~= "") and S.mods.weather or (S.mods and S.mods.plannedWeather or "")
			if wClass ~= "" then
				local def = S.weatherEffects and S.weatherEffects[wClass]
				local wname = S.WeatherName and S.WeatherName(wClass) or wClass
				local tier = S.WeatherTier and S.WeatherTier(wClass) or 1
				surface.SetDrawColor(alt)
				polyFilled(12, y + 3, 6, 11, 2)
				draw.SimpleText(string.format("WEATHER  %s  (T%d)", string.upper(wname), tier), bold, 24, y, alt)
				draw.SimpleText(def and def.desc or "No effect.", small, 230, y + 1, ColorAlpha(bright, 190))
				y = y + 18
			end
			if #list == 0 then
				draw.SimpleText((sf or hasWeather) and "No modifiers this mission." or "None this mission.", small, 12, y + 1, ColorAlpha(bright, 90))
				return true
			end
			for i, id in ipairs(list) do
				if i > 4 then break end
				local m = S.modById and S.modById[id]
				if m then
					local col = S.modKindColors[m.kind]()
					surface.SetDrawColor(col)
					polyFilled(12, y + 3, 6, 11, 2)
					draw.SimpleText(string.upper(S.modKindLabel[m.kind] .. "  " .. m.name), bold, 24, y, col)
					local extra = m.desc
					if m.reward and m.reward > 0 then extra = extra .. string.format("  (+%d %s on victory)", m.reward, S.tokenNamePlural) end
					if m.doubleVictory then extra = extra .. "  (double victory " .. S.tokenNamePlural .. ")" end
					if id == "armoryloan" and S.mods.loan ~= "" then extra = extra .. "  Loaned: " .. S.WeaponName(S.mods.loan) end
					draw.SimpleText(extra, small, 230, y + 1, ColorAlpha(bright, 190))
					y = y + 18
				end
			end
			return true
		end
		-- }}}

		-- Cards flow in a 2-column grid, one headed block per S.groupSections entry, in that order
		local cy, idx = 220, 0
		local function sectionHeader(title, sub)
			if idx > 0 then cy = cy + cardH + gap end -- move below the last row of cards
			idx = 0
			local hdr = scroll:Add("DPanel")
			hdr:SetPos(0, cy + 4)
			hdr:SetSize(scroll:GetWide() - 16, 30)
			hdr:SetTall(40)
			hdr.Paint = function(self, w, h)
				paintSection(w, h, title, sub)
				return true
			end
			cy = cy + 50
		end

		-- Group the cards by section, keeping each section's rows in the order they appear in
		-- S.groupUpgrades. Anything whose section isn't declared is swept into a block at the end
		-- rather than dropped, so a typo in a new row shows up on screen instead of vanishing.
		local function visible(up)
			return not up.weapons or S.WeaponLocksEnabled()
		end

		local shown, placed = {}, {}
		for si, sec in ipairs(S.groupSections) do
			for i, up in ipairs(S.groupUpgrades) do
				if (up.section or "squad") == sec.id and visible(up) then
					shown[#shown + 1] = { up = up, sec = sec }
					placed[up.id] = true
				end
			end
		end

		local strays = { id = "?", name = "OTHER UPGRADES", sub = "No section declared for these." }
		for i, up in ipairs(S.groupUpgrades) do
			if not placed[up.id] and visible(up) then
				shown[#shown + 1] = { up = up, sec = strays }
			end
		end

		local lastSection
		for i, row in ipairs(shown) do
			local up = row.up
			if row.sec ~= lastSection then
				lastSection = row.sec
				sectionHeader(row.sec.name, row.sec.sub)
			end
			local col = idx % cols
			if col == 0 and idx > 0 then cy = cy + cardH + gap end
			idx = idx + 1

			local card = scroll:Add("DButton")
			card:SetText("")
			card:SetPos(col * (cardW + gap), cy)
			card:SetSize(cardW, cardH)

			card.Paint = function(self, w, h)
				local bright, alt = colBright(), colAlt()
				local rank, maxRank = S.GroupRank(up.id), #up.costs
				local cost = S.GroupNextCost(up.id)
				local maxed = cost == nil
				local v = voteOpen()
				local option = isOption(up.id)
				local mine = myVote() == up.id
				local pulse = (math.sin(RealTime() * 5) + 1) / 2

				local hov = option and self:IsHovered()
				local tint, outline
				if maxed then
					tint, outline = ColorAlpha(bright, 35), bright
				elseif mine then
					tint, outline = ColorAlpha(colToken, 70), colToken
				elseif option then
					tint, outline = hov and ColorAlpha(colToken, 40) or nil, ColorAlpha(colToken, 120 + 135 * pulse)
				elseif rank > 0 then
					outline = alt
				else
					outline = ColorAlpha(bright, v and 40 or 110)
				end
				panelBox(w, h, outline, tint, 10)
				if option or maxed then -- double outline for emphasis
					surface.SetDrawColor(outline)
					polyHollow(1, 1, w - 2, h - 2, 9)
				end

				local dim = v and not option and not maxed
				draw.SimpleText(string.upper(up.name), fnt("jcms_small_bolder", "sweeper_med"), 12, 7, dim and ColorAlpha(bright, 80) or bright)

				-- Rank pips: angled pieces like the gamemode's stat bars
				local pw, pg = 14, 3
				local px = w - 12 - maxRank * (pw + pg)
				surface.SetDrawColor(ColorAlpha(bright, dim and 80 or 255))
				for r = 1, maxRank do
					local x = px + (r - 1) * (pw + pg)
					if r <= rank then polyFilled(x, 9, pw, 11, 3) else polyHollow(x, 9, pw, 11, 3) end
				end

				-- Description, wrapped to 2 lines so it never runs off the card
				if self.descW ~= w then
					self.descW = w
					self.descLines = {}
					surface.SetFont(fnt("jcms_small", "sweeper_small"))
					local line = ""
					for word in string.gmatch(up.desc, "%S+") do
						local test = (line == "") and word or (line .. " " .. word)
						if surface.GetTextSize(test) > w - 20 and line ~= "" then
							table.insert(self.descLines, line)
							line = word
						else
							line = test
						end
					end
					if line ~= "" then table.insert(self.descLines, line) end
					if #self.descLines > 2 then
						self.descLines = { self.descLines[1], self.descLines[2] .. " ..." }
						self:SetTooltip(up.desc)
					end
				end
				for li, text in ipairs(self.descLines) do
					draw.SimpleText(text, fnt("jcms_small", "sweeper_small"), 12, 28 + (li - 1) * 15, ColorAlpha(bright, dim and 70 or 190))
				end

				local nowText
				if up.weapons then
					local n = 0
					for r = 1, rank do n = n + #((S.group.weaponPlan or {})[r] or {}) end
					nowText = rank > 0 and string.format("Now: %d weapons unlocked (list below)", n) or "Not bought yet"
				elseif up.startCash then
					nowText = rank > 0 and string.format("Now: +%d J starting cash", up.startCash * rank) or "Not bought yet"
				elseif up.nowText then
					nowText = rank > 0 and up.nowText(rank) or "Not bought yet"
				else
					local totals = {}
					for k, val in pairs(up.stats) do totals[k] = val * rank end
					nowText = rank > 0 and ("Now: " .. S.FormatStats(totals)) or "Not bought yet"
				end
				draw.SimpleText(nowText, fnt("jcms_small", "sweeper_small"), 12, 60, rank > 0 and alt or ColorAlpha(bright, 90))

				-- Bottom line: price / vote count
				local med, small = fnt("jcms_small_bolder", "sweeper_med"), fnt("jcms_small", "sweeper_small")
				surface.SetDrawColor(bright.r, bright.g, bright.b, dim and 20 or 40)
				striped(12, h - 36, w - 24, 2, 32)
				if maxed then
					surface.SetDrawColor(bright)
					polyFilled(12, h - 28, 100, 20, 6)
					draw.SimpleText("MAX RANK", med, 62, h - 18, colDark(), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				else
					local afford = cost <= S.GroupPool()
					drawToken(21, h - 18, 8)
					draw.SimpleText(string.format("RANK %d:  %s", rank + 1, string.upper(tokenStr(cost))), med, 34, h - 18,
						afford and colToken or ColorAlpha(colToken, 90), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

					if v and option then
						local n = v.tally and v.tally[up.id] or 0
						local text = mine and string.format("YOUR VOTE  (%d)", n) or string.format("CLICK TO VOTE  (%d)", n)
						surface.SetFont(med)
						local bw = surface.GetTextSize(text) + 20
						surface.SetDrawColor(colToken)
						if mine then
							polyFilled(w - 12 - bw, h - 28, bw, 20, 6)
							draw.SimpleText(text, med, w - 12 - bw / 2, h - 18, tokenDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						else
							surface.SetAlphaMultiplier(0.6 + 0.4 * pulse)
							polyHollow(w - 12 - bw, h - 28, bw, 20, 6)
							draw.SimpleText(text, med, w - 12 - bw / 2, h - 18, colToken, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
							surface.SetAlphaMultiplier(1)
						end
					elseif not afford then
						draw.SimpleText(string.format("need %d more", cost - S.GroupPool()), small, w - 12, h - 18, ColorAlpha(bright, 90), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					end
				end
				return true
			end

			card.DoClick = function()
				if isOption(up.id) then
					sendVote(up.id)
					surface.PlaySound("buttons/button14.wav")
				else
					surface.PlaySound("buttons/button10.wav")
				end
			end
		end

		-- // Armory Access: what each rank unlocks {{{
		if not S.WeaponLocksEnabled() then
			function root:Refresh() end
			return
		end
		local wy = cy + cardH + gap + 6

		local header = scroll:Add("DPanel")
		header:SetPos(0, wy)
		header:SetSize(scroll:GetWide() - 16, 30)
		header:SetTall(40)
		header.Paint = function(self, w, h)
			paintSection(w, h, "ARMORY ACCESS", "Weapons each rank unlocks this run (random until a list is set). Locked ones are hidden from the shop.")
			return true
		end
		wy = wy + 46

		local rowH = 54
		for r = 1, 5 do
			local rowPnl = scroll:Add("DPanel")
			rowPnl:SetPos(0, wy + (r - 1) * (rowH + 6))
			rowPnl:SetSize(scroll:GetWide() - 16, rowH)
			rowPnl.Paint = function(self, w, h)
				local bright = colBright()
				local unlocked = S.GroupRank("g_weapons") >= r
				local list = (S.group.weaponPlan or {})[r] or {}

				local alt = colAlt()
				local small = fnt("jcms_small", "sweeper_small")
				panelBox(w, h, unlocked and alt or ColorAlpha(bright, 60), unlocked and ColorAlpha(alt, 25) or nil, 8)

				if unlocked then
					surface.SetDrawColor(alt)
					polyFilled(8, 8, 76, h - 16, 6)
					draw.SimpleText("RANK " .. r, fnt("jcms_small_bolder", "sweeper_med"), 46, h / 2 - 8, colDarkAlt(), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					draw.SimpleText("UNLOCKED", small, 46, h / 2 + 8, colDarkAlt(), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				else
					surface.SetDrawColor(bright.r, bright.g, bright.b, 90)
					polyHollow(8, 8, 76, h - 16, 6)
					draw.SimpleText("RANK " .. r, fnt("jcms_small_bolder", "sweeper_med"), 46, h / 2 - 8, bright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					draw.SimpleText("LOCKED", small, 46, h / 2 + 8, ColorAlpha(bright, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end

				if #list == 0 then
					draw.SimpleText("No weapons in this batch yet", small, 96, h / 2, ColorAlpha(bright, 90), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					return true
				end

				-- Weapon names (kill icons where the weapon has one)
				local x = 96
				surface.SetFont(small)
				for i, class in ipairs(list) do
					local name = S.WeaponName(class)
					local tw = surface.GetTextSize(name)
					local slotW = math.max(tw, 64) + 14
					if x + slotW > w - 8 then
						draw.SimpleText("+" .. (#list - i + 1) .. " more", small, x, h / 2, ColorAlpha(bright, 110), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						break
					end
					if killicon and killicon.Exists and killicon.Exists(class) then
						pcall(killicon.Draw, x + slotW / 2 - 7, 16, class, unlocked and 255 or 90)
					end
					draw.SimpleText(name, small, x + slotW / 2 - 7, h - 6, unlocked and bright or ColorAlpha(bright, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
					x = x + slotW
				end
				return true
			end
		end
		-- }}}

		function root:Refresh() end -- everything paints from live data
	end
end
-- }}}
