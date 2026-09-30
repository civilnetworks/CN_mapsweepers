--[[
	Map Sweepers - Implants & Class Levels (addon)
	SUB-FACTIONS (Helldivers 2 style)

	Each main faction can have sub-factions. When a mission is rolled, there's a chance it also rolls a
	sub-faction of that mission's faction. The mission still fights the main faction, but the sub-faction
	changes the mix: e.g. Civil Protection = mostly Metro Police, more scanners, every cop carries manhacks.

	It rolls together with the mission modifiers (new map, New Contract, admin reroll) and shows next to them:
	TEAM UPGRADES tab, chat, and the HUD line above the compass.

	HOW A SUB-FACTION WORKS
	  weights   { [npcType] = multiplier }  multiplies that enemy's spawn weight (waves AND portals)
	  limits    { [npcType] = number }      replaces its max-per-wave (swarmLimit)
	  borrow    { npcType, ... }            enemies from ANOTHER faction that join this mission
	  members   { npcType, ... }            enemies that BELONG to this sub-faction: they only ever spawn
	                                        while it's the active one, and are switched off otherwise
	                                        (including when no sub-faction rolled).
	  only      true                        ONLY the enemies you listed spawn - every other enemy of this
	                                        faction is switched off for the mission. Bosses are left alone
	                                        (mission bosses still need to spawn) unless onlyBosses = true.
	  keep      { npcType, ... }            with `only`: extra enemies to leave switched on
	  onlyBosses true                       with `only`: switch off this faction's bosses too
	  onSpawn   function(npc, npcType)      extra setup for enemies as they spawn
	The gamemode's enemy table values are swapped in when the mission starts and put back when it ends.

	PER-FACTION RULES (S.subfactionRules below)
	  always    true   this faction ALWAYS rolls a sub-faction (ignores jcms_subfaction_chance)
	  exclusive true   every sub-faction of this faction behaves as if it had only = true
	Use these for a faction whose enemies are meant to come only from its sub-factions.

	Adding your own (also works for custom factions from other addons):
	  sweeper.subfactions.<faction> = { { id = "...", name = "...", desc = "...", weights = {...} }, ... }

	Convars:  jcms_subfaction_chance 0.5  (chance a mission rolls a sub-faction)
	Admin:    jcms_subfaction_set <id|none>, jcms_subfaction_list
--]]

local S = sweeper

-- // Definitions {{{
S.subfactions = S.subfactions or {}

-- Per-faction rules: S.subfactionRules["automatons"] = { always = true, exclusive = true }
S.subfactionRules = S.subfactionRules or {}

S.subfactions.combine = {
	{ id = "civilprotection", name = "Civil Protection",
	  desc = "Mostly Metro Police, more scanners, and every cop carries manhacks.",
	  weights = { combine_metrocop = 4, combine_scanner = 3, combine_soldier = 0.35, combine_elite = 0.3, combine_suppressor = 0.5, combine_sniper = 0.5 },
	  limits = { combine_scanner = 3 },
	  onSpawn = function(npc, t) if t == "combine_metrocop" then npc:SetKeyValue("manhacks", "1") end end },
	{ id = "novaprospekt", name = "Nova Prospekt Garrison",
	  desc = "Elite-heavy: more Elites, Suppressors and Snipers, no Metro Police. Soldiers carry extra grenades.",
	  weights = { combine_elite = 3, combine_suppressor = 2.5, combine_sniper = 2, combine_metrocop = 0 },
	  onSpawn = function(npc, t) if t == "combine_soldier" or t == "combine_elite" then npc:SetKeyValue("NumGrenades", "3") end end },
	{ id = "synthdivision", name = "Synth Division",
	  desc = "Hunters hunt in packs (up to 4 per wave), guided by scanners.",
	  weights = { combine_hunter = 6, combine_scanner = 2 }, limits = { combine_hunter = 4, combine_scanner = 2 } },
}

S.subfactions.antlion = {
	{ id = "workerhive", name = "Worker Hive",
	  desc = "Acid-spitting Workers swarm the map; fewer Drones.",
	  weights = { antlion_worker = 5, antlion_drone = 0.5 } },
	{ id = "cyberswarm", name = "Cyber Swarm",
	  desc = "Cyber-augmented bugs: far more Cyberbugs, and Cyberguards show up more.",
	  weights = { antlion_cyberbug = 5, antlion_cyberguard = 2 }, limits = { antlion_cyberguard = 3 } },
	{ id = "reaperbrood", name = "Reaper Brood",
	  desc = "Reapers stalk the squad in numbers.",
	  weights = { antlion_reaper = 5, antlion_waster = 0.6 } },
	{ id = "guardnest", name = "Guard Nest",
	  desc = "More Antlion Guards, and more of them per wave.",
	  weights = { antlion_guard = 2, antlion_burrowerguard = 2 }, limits = { antlion_guard = 5, antlion_burrowerguard = 5 } },
}

S.subfactions.rebel = {
	{ id = "vortcollective", name = "Vortigaunt Collective",
	  desc = "Vortigaunts lead the resistance, with Dog backing them up.",
	  weights = { rebel_vortigaunt = 4, rebel_dog = 2 }, limits = { rebel_dog = 3 } },
	{ id = "breachercell", name = "Breacher Cell",
	  desc = "Breachers and Teleporters: fast, close-range assaults.",
	  weights = { rebel_breacher = 3, rebel_teleporter = 2.5, rebel_fighter = 0.6 } },
	{ id = "odessamilitia", name = "Odessa's Militia",
	  desc = "Odessa's RPG crews: more Odessa rocketeers per wave.",
	  weights = { rebel_odessa = 4 }, limits = { rebel_odessa = 4 } },
	{ id = "vanguard", name = "Vanguard",
	  desc = "The resistance's best: more Vanguards, fewer regular fighters.",
	  weights = { rebel_vanguard = 4, rebel_fighter = 0.6 }, limits = { rebel_vanguard = 4 } },
}

S.subfactions.zombie = {
	{ id = "fastinfection", name = "Fast Infection",
	  desc = "Fast Zombies and Crawlers everywhere; fewer slow Husks.",
	  weights = { zombie_fast = 3, zombie_crawler = 2.5, zombie_husk = 0.5 } },
	{ id = "toxicplague", name = "Toxic Plague",
	  desc = "Poison Zombies and Boomers.",
	  weights = { zombie_poison = 3, zombie_boomer = 3 } },
	{ id = "zombineoutbreak", name = "Zombine Outbreak",
	  desc = "Infected Combine soldiers (Zombines) with grenades.",
	  weights = { zombie_combine = 5 } },
	{ id = "creepspread", name = "Creep Spread",
	  desc = "Creepers and Polyps spread across the map.",
	  weights = { zombie_creeper = 3, zombie_polyp = 2 }, limits = { zombie_creeper = 8, zombie_polyp = 3 } },
}

S.subfactions.automaton = {
	{ id = "jetbrigade", name = "Jet Brigade",
	  desc = "",
	  weights = { } },
	{ id = "incinerationcorps", name = "Incineration Corps",
	  desc = "",
	  weights = { } },
	{ id = "cyborglegion", name = "Cyborg Legion",
	  desc = "",
	  weights = { } },
}

function S.GetSubfaction(id)
	if not id or id == "" then return nil end
	for faction, list in pairs(S.subfactions) do
		for i, sf in ipairs(list) do
			if sf.id == id then return sf, faction end
		end
	end
end
-- }}}

-- ============================================================================================
if SERVER then
	S.cvar_subChance = CreateConVar("jcms_subfaction_chance", "0.5", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Chance (0-1) that a mission rolls a sub-faction of its enemy faction.", 0, 1)

	local function tellAll(msg)
		S.ChatPrintAll(msg)
	end

	local function missionFaction()
		return game.GetWorld():GetNWString("jcms_missionfaction", "")
	end

	-- Called right after the modifiers roll (sh_modifiers.lua)
	function S.RollSubfaction(silent)
		S.mods.subfaction = ""
		local list = S.subfactions[missionFaction()]
		-- skip sub-factions built around Episode-only enemies when the server doesn't mount the Episodes
		local pool = {}
		local hasEp = not (jcms and jcms.HasEpisodes) or jcms.HasEpisodes()
		for i, sf in ipairs(list or {}) do
			local ok = true
			if not hasEp and jcms and jcms.npc_types then
				ok = false
				for t, mul in pairs(sf.weights or {}) do
					local d = jcms.npc_types[t]
					if mul > 1 and d and not d.episodes then ok = true break end
				end
			end
			if ok then pool[#pool + 1] = sf end
		end
		local rules = S.subfactionRules[missionFaction()] or {}
		local chance = rules.always and 1 or S.cvar_subChance:GetFloat()
		if S.ModsAllowed and S.ModsAllowed() and #pool > 0 and math.random() < chance then
			S.mods.subfaction = pool[math.random(#pool)].id
		end
		if not silent and S.mods.subfaction ~= "" then
			local sf = S.GetSubfaction(S.mods.subfaction)
			tellAll(string.format("[Sub-Faction] %s: %s", sf.name, sf.desc))
		end
	end

	-- Swap the sub-faction's numbers into the gamemode's enemy table for the mission, and back afterwards
	local saved = nil
	function S.SubfactionApply()
		S.SubfactionRestore()
		if not (jcms and jcms.npc_types) then return end

		local sf, faction = S.GetSubfaction(S.mods.subfaction)
		local current = (jcms.director and jcms.director.faction) or missionFaction()
		-- The mission's faction changed since the roll (e.g. an admin used jcms_mission): drop it
		if sf and current ~= faction then
			S.mods.subfaction = ""
			sf, faction = nil, nil
		end

		saved = {}
		local function rememberOff(t)
			local data = jcms.npc_types[t]
			if not data then return end
			if not saved[t] then
				saved[t] = { swarmWeight = data.swarmWeight, portalSpawnWeight = data.portalSpawnWeight, swarmLimit = data.swarmLimit, faction = data.faction }
			end
			data.swarmLimit = 0
			data.portalSpawnWeight = nil
		end

		-- Enemies that belong to a sub-faction (its `members`) are off unless that sub-faction is the
		-- active one. That also covers missions where no sub-faction rolled at all.
		for i, other in ipairs(S.subfactions[current] or {}) do
			if not sf or other.id ~= sf.id then
				for j, t in ipairs(other.members or {}) do rememberOff(t) end
			end
		end

		if not sf then return end

		-- this sub-faction's own members are switched back on (they were off by default)
		for i, t in ipairs(sf.members or {}) do
			local data = jcms.npc_types[t]
			if data and saved[t] then
				data.swarmLimit = saved[t].swarmLimit
				data.portalSpawnWeight = saved[t].portalSpawnWeight
			end
		end

		local function remember(t, data)
			if not saved[t] then
				saved[t] = { swarmWeight = data.swarmWeight, portalSpawnWeight = data.portalSpawnWeight, swarmLimit = data.swarmLimit, faction = data.faction }
			end
		end
		for t, mul in pairs(sf.weights or {}) do
			local data = jcms.npc_types[t]
			if data then
				remember(t, data)
				if mul <= 0 then
					-- 0 = this enemy doesn't show up at all. The gamemode can't handle a weight of 0 in its
					-- random pick (shared.lua util_GetShuffledByWeight -> "table index is nil"), so instead
					-- set its per-wave limit to 0, which the director already skips, and keep it out of portals.
					data.swarmLimit = 0
					data.portalSpawnWeight = nil
				else
					data.swarmWeight = (data.swarmWeight or 1) * mul
					if data.portalSpawnWeight then data.portalSpawnWeight = data.portalSpawnWeight * mul end
				end
			end
		end
		for t, lim in pairs(sf.limits or {}) do
			local data = jcms.npc_types[t]
			if data then remember(t, data) data.swarmLimit = lim end
		end
		for i, t in ipairs(sf.borrow or {}) do
			local data = jcms.npc_types[t]
			if data then remember(t, data) data.faction = faction end
		end

		-- `only` (or the faction's `exclusive` rule): switch off everything the sub-faction didn't ask for
		local rules = S.subfactionRules[faction] or {}
		if sf.only or rules.exclusive then
			local allowed = {}
			for t, mul in pairs(sf.weights or {}) do if mul > 0 then allowed[t] = true end end
			for t in pairs(sf.limits or {}) do allowed[t] = true end
			for i, t in ipairs(sf.borrow or {}) do allowed[t] = true end
			for i, t in ipairs(sf.keep or {}) do allowed[t] = true end
			for i, t in ipairs(sf.members or {}) do allowed[t] = true end

			-- Bosses stay unless the sub-faction says otherwise: boss missions need one to spawn.
			local isBoss = {}
			for t, data in pairs(jcms.npc_types) do
				isBoss[t] = data.danger == jcms.NPC_DANGER_BOSS or data.danger == jcms.NPC_DANGER_RAREBOSS
			end

			local turnOff, left = {}, 0
			for t, data in pairs(jcms.npc_types) do
				if data.faction == faction and not allowed[t] then
					if isBoss[t] and not sf.onlyBosses then
						left = left + 1
					else
						turnOff[#turnOff + 1] = t
					end
				elseif data.faction == faction then
					left = left + 1
				end
			end

			-- Never leave the director with (almost) nothing to spawn
			if left >= 2 then
				for i, t in ipairs(turnOff) do
					local data = jcms.npc_types[t]
					remember(t, data)
					data.swarmLimit = 0
					data.portalSpawnWeight = nil
				end
			else
				ErrorNoHalt("[sweeper] sub-faction '" .. tostring(sf.id) .. "' has only = true but would leave " ..
					left .. " enemy types enabled. Ignoring `only` for this mission - list more enemies or use `keep`.\n")
			end
		end
	end

	function S.SubfactionRestore()
		if not saved or not (jcms and jcms.npc_types) then saved = nil return end
		for t, v in pairs(saved) do
			local data = jcms.npc_types[t]
			if data then
				data.swarmWeight, data.portalSpawnWeight, data.swarmLimit, data.faction = v.swarmWeight, v.portalSpawnWeight, v.swarmLimit, v.faction
			end
		end
		saved = nil
	end

	hook.Add("MapSweepersNPCSpawned", "sweeper_subfaction", function(npc, npcType)
		if not (S.mods and S.mods.inMission) or not IsValid(npc) then return end
		local sf = S.GetSubfaction(S.mods.subfaction)
		if sf and sf.onSpawn then
			local ok, err = pcall(sf.onSpawn, npc, npcType)
			if not ok then ErrorNoHalt("[sweeper] sub-faction onSpawn: " .. tostring(err) .. "\n") end
		end
	end)

	-- Guard: an enemy type with a "weapons" table that has no usable entry (empty, all weights 0,
	-- or from another addon) makes the gamemode call npc:Give(nil) and the spawn fails
	-- (sv_npcs.lua:205 "bad argument #1 to 'Give'"). Warn once with the enemy's name and spawn it unarmed-safe.
	local warnedWeapons = {}
	local function weaponsUsable(w)
		if not istable(w) then return true end
		for k, v in pairs(w) do
			if isstring(k) and isnumber(v) and v > 0 then return true end
		end
		return false
	end

	function S.InstallNPCWeaponGuard()
		if not (jcms and jcms.npc_Spawn and jcms.util_ChooseByWeight) then return end
		-- Safety net: the gamemode's weighted shuffle loops forever-then-errors if any entry's weight is 0,
		-- negative or NaN (ChooseByWeight returns nil -> "table index is nil"). Drop those entries first;
		-- they could never be picked anyway.
		if jcms.util_GetShuffledByWeight and not S._wrappedShuffled then
			S._wrappedShuffled = true
			local origShuffle = jcms.util_GetShuffledByWeight
			jcms.util_GetShuffledByWeight = function(t, ...)
				if istable(t) then
					local clean, dirty = {}, false
					for k, v in pairs(t) do
						if isnumber(v) and v > 0 and v == v and v < math.huge then clean[k] = v else dirty = true end
					end
					if dirty then return origShuffle(clean, ...) end
				end
				return origShuffle(t, ...)
			end
		end
		if not S._wrappedChooseByWeight then
			S._wrappedChooseByWeight = true
			local orig = jcms.util_ChooseByWeight
			jcms.util_ChooseByWeight = function(t, ...)
				local r = orig(t, ...)
				if r == nil and istable(t) then
					-- rounding edge case: fall back to any entry with a positive weight
					for k, v in pairs(t) do if isnumber(v) and v > 0 then return k end end
				end
				return r
			end
		end
		if not S._wrappedNPCSpawn then
			S._wrappedNPCSpawn = true
			local orig = jcms.npc_Spawn
			jcms.npc_Spawn = function(kind, ...)
				local data = jcms.npc_types and jcms.npc_types[kind]
				if data and data.weapons ~= nil and not weaponsUsable(data.weapons) then
					if not warnedWeapons[kind] then
						warnedWeapons[kind] = true
						ErrorNoHalt("[sweeper] enemy type '" .. tostring(kind) .. "' has a 'weapons' table with no usable weapon; spawning it without one.\n")
					end
					local saved = data.weapons
					data.weapons = nil
					local ok, a, b, c = pcall(orig, kind, ...)
					data.weapons = saved
					if not ok then error(a, 0) end
					return a, b, c
				end
				return orig(kind, ...)
			end
		end
	end
	S.InstallNPCWeaponGuard()
	hook.Add("InitPostEntity", "sweeper_npcweaponguard", S.InstallNPCWeaponGuard)
	hook.Add("Initialize", "sweeper_npcweaponguard", S.InstallNPCWeaponGuard)

	hook.Add("ShutDown", "sweeper_subfaction", function() S.SubfactionRestore() end)

	concommand.Add("jcms_subfaction_set", function(ply, cmd, args)
		if IsValid(ply) and not ply:IsAdmin() then return end
		if jcms and jcms.director then print("[Sub-Faction] Only in the lobby.") return end
		local id = args[1] or ""
		if id == "none" then id = "" end
		if id ~= "" and not S.GetSubfaction(id) then print("[Sub-Faction] unknown id: " .. id) return end
		S.mods.subfaction = id
		if S.ModSync then S.ModSync() end
	end)

	concommand.Add("jcms_subfaction_list", function(ply)
		local lines = {}
		for faction, list in pairs(S.subfactions) do
			for i, sf in ipairs(list) do
				lines[#lines + 1] = string.format("%-10s %-18s %s - %s", faction, sf.id, sf.name, sf.desc)
			end
		end
		local msg = table.concat(lines, "\n")
		S.PrintConsole(ply, msg)
	end)
end
