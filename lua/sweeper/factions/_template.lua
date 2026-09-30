--[[
	Map Sweepers - Implants & Class Levels (addon)
	FACTION TEMPLATE

	HOW TO USE
	  1. Copy this file in the same folder (lua/sweeper/factions/) and give it a name that does NOT start
	     with "_", e.g. "mercenary.lua". Files starting with "_" (like this one) are never loaded.
	  2. Change FACTION below to your faction's id (lowercase, no spaces), and fill in the name, colour and enemies.
	  3. Optional: add an icon at materials/jcms/factions/<FACTION>.png (same size/style as the gamemode's
	     antlion.png / combine.png). Without it the lobby shows a missing texture where the icon goes.
	  4. Restart the map. Check with "jcms_mission payload <FACTION>" (admin console command).

	WHERE YOUR FACTION SHOWS UP
	  Missions whose faction is "any" roll a random faction, so yours can come up there. In the gamemode today
	  those are Payload and Violence Flashpoints. Missions tied to one faction (e.g. Thumper Sabotage = Combine)
	  never use it. Hell / Eschaton only include custom factions if the server cvar jcms_customfactions_hell is on.

	HOW ENEMIES FIGHT
	  The gamemode sets relationships from each NPC's faction: your enemies hate the Sweepers and any other
	  faction, and like each other. You don't need to set relationships yourself, even for npc_citizen etc.

	Nothing in the gamemode is edited: everything is added from the gamemode's "MapSweepersReady" hook.
--]]

local FACTION = "example"                    -- faction id (also used in enemy ids below)
local NAME    = "Example Faction"            -- shown in the lobby, mission board, stats
local COLOR   = Color(230, 140, 40)          -- faction colour (spawn portals, HUD, lobby)

-- The gamemode's danger levels, as plain numbers. Faction files load from lua/autorun BEFORE the gamemode
-- runs, so the jcms table doesn't exist yet and jcms.NPC_DANGER_* would be an error here. install() below
-- checks these still match the gamemode.
local DANGER_FODDER, DANGER_STRONG, DANGER_BOSS, DANGER_RAREBOSS = 1, 2, 3, 4


-- // ENEMIES ========================================================================================
-- Every enemy is one entry. The key becomes the enemy id: FACTION .. "_" .. key (e.g. example_grunt).
--
-- REQUIRED
--   class        NPC class to spawn ("npc_combine_s", "npc_metropolice", "npc_citizen", "npc_vj_...", ...)
--   danger       DANGER_FODDER / _STRONG / _BOSS / _RAREBOSS
--                (with the "jcms." in front - the bare NPC_DANGER_* names are nil and crash the director)
--                  FODDER = the bulk of every wave, STRONG = mixed in, BOSS = one per boss wave,
--                  RAREBOSS = only at high difficulty
--   cost         wave budget this enemy uses (metrocop 0.85, soldier 1, elite ~2, bosses 5+)
--   swarmWeight  how often it is picked for a wave, relative to the others (0 = never in waves)
--   bounty       J credits for the kill (metrocop 40, soldier ~50, bosses 300+)
--
-- OPTIONAL
--   portalSpawnWeight  chance to come through mid-mission spawn portals (0 or nil = never)
--   swarmLimit         max of this enemy per wave
--   portalScale        size of its spawn portal effect (default 1)
--   model / skin       override the model or skin
--   weapons            { weapon_class = weight, ... }  picks one at random (use `weapon = "class"` for a fixed one)
--   proficiency        WEAPON_PROFICIENCY_POOR / _AVERAGE / _GOOD / _VERY_GOOD / _PERFECT
--   airUnit / aerial   flying enemies (aerial = spawns in the air and uses flying paths)
--   hullSize           HULL_* for big ground NPCs (hunters, guards) so they pick fitting nodes
--   anonymous          true = doesn't count toward the director's enemy stats
--   noArenaMode        true = never used in the arena terminal mode
--   check              function(director) return true/false  -- only allowed when this returns true
--
-- HOOKS (all optional)
--   preSpawn(npc, pos, data)            before Spawn(): keyvalues like citizentype, spawnflags
--   postSpawn(npc, pos, data)           after Spawn(): health, keyvalues like manhacks / NumGrenades, shields
--   think(npc, state)                   runs with the director's NPC think
--   scaleDamage(npc, hitGroup, dmg)     change damage this NPC TAKES (e.g. armour)
--   takeDamage(npc, dmg)                react to taking damage
--   damageEffect(npc, target, dmg)      react to DEALING damage (e.g. ignite the target)
--   onKilled(npc, attacker, inflictor)  on death (drops, explosions, ...)
--   timedEvent(npc, data) + timerMin, timerMax   runs once, a random time after spawning
local ENEMIES = {

	grunt = {
		class = "npc_metropolice",
		danger = DANGER_FODDER,
		cost = 0.8,
		swarmWeight = 1,
		portalSpawnWeight = 1,
		bounty = 35,
		weapons = { weapon_pistol = 2, weapon_smg1 = 3 },
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	rifleman = {
		class = "npc_combine_s",
		danger = DANGER_FODDER,
		cost = 1,
		swarmWeight = 0.8,
		portalSpawnWeight = 0.8,
		bounty = 50,
		weapons = { weapon_ar2 = 2, weapon_shotgun = 1 },
		proficiency = WEAPON_PROFICIENCY_GOOD,
		postSpawn = function(npc)
			npc:SetKeyValue("NumGrenades", "2")
		end,
	},

	heavy = {
		class = "npc_combine_s",
		model = "models/combine_super_soldier.mdl",
		danger = DANGER_STRONG,
		cost = 2.2,
		swarmWeight = 0.3,
		swarmLimit = 3,
		portalSpawnWeight = 0.2,
		bounty = 90,
		weapon = "weapon_ar2",
		proficiency = WEAPON_PROFICIENCY_VERY_GOOD,
		postSpawn = function(npc)
			npc:SetMaxHealth(200)
			npc:SetHealth(200)
		end,
		-- takes 30% less damage everywhere except the head
		scaleDamage = function(npc, hitGroup, dmg)
			if hitGroup ~= HITGROUP_HEAD then dmg:ScaleDamage(0.7) end
		end,
	},

	boss = {
		class = "npc_antlionguard",
		danger = DANGER_BOSS,
		cost = 6,
		swarmWeight = 1,
		swarmLimit = 1,
		bounty = 350,
		hullSize = HULL_LARGE,
		portalScale = 2,
		postSpawn = function(npc)
			npc:SetColor(COLOR)
		end,
		onKilled = function(npc, attacker, inflictor)
			local ed = EffectData()
			ed:SetOrigin(npc:WorldSpaceCenter())
			util.Effect("Explosion", ed)
		end,
	},
}

-- // BESTIARY (client, optional) ======================================================================
-- Entries for the in-game bestiary. health/bounty are just what the page displays.
local BESTIARY = {
	grunt    = { title = "Grunt",    desc = "Cheap, numerous, poorly trained.", mdl = "models/police.mdl", health = 40 },
	rifleman = { title = "Rifleman", desc = "The backbone of the faction.",      mdl = "models/combine_soldier.mdl", health = 50 },
	heavy    = { title = "Heavy",    desc = "Armoured. Aim for the head.",        mdl = "models/combine_super_soldier.mdl", health = 200 },
	boss     = { title = "Warbeast", desc = "The faction's boss.",                mdl = "models/antlion_guard.mdl", health = 500 },
}

-- // MAP PREFABS (server, optional) ===================================================================
-- Things placed around the map when a mission against this faction starts (like Combine floor turrets).
-- Leave empty for none. Each entry works like the gamemode's prefabs/types/combine.lua:
--   check(area) -> bool, areaWeight(area) -> number (optional), stamp(area, data) spawns the thing.
local PREFABS = {
	--[[
	crate = {
		weight = 1,
		check = function(area) return jcms.mapgen_ValidArea(area) and jcms.mapgen_AreaFlat(area) end,
		stamp = function(area, data)
			local e = ents.Create("prop_physics")
			e:SetModel("models/props_junk/wood_crate001a.mdl")
			e:SetPos(area:GetCenter() + Vector(0, 0, 24))
			e:Spawn()
		end,
	},
	--]]
}
local PREFAB_COUNT = 2 -- how many to place (scaled by map size and difficulty, like the Combine's)

-- // SUB-FACTIONS (optional) ==========================================================================
-- Helldivers-style variants of this faction (see sh_subfactions.lua). Ids here are the enemy KEYS above.
local SUBFACTIONS = {
	--[[
	{ id = FACTION .. "_heavyarmor", name = "Heavy Armour Division",
	  desc = "Mostly Heavies, fewer Grunts.",
	  weights = { heavy = 4, grunt = 0.4 }, limits = { heavy = 5 } },
	--]]
}

-- ===================================================================================================
-- Nothing below needs changing.
-- ===================================================================================================
local function id(key) return FACTION .. "_" .. key end

local function install()
	if not (jcms and jcms.factions) then return end

	-- The danger numbers above must match the gamemode's
	local gmDanger = { [DANGER_FODDER] = jcms.NPC_DANGER_FODDER, [DANGER_STRONG] = jcms.NPC_DANGER_STRONG,
		[DANGER_BOSS] = jcms.NPC_DANGER_BOSS, [DANGER_RAREBOSS] = jcms.NPC_DANGER_RAREBOSS }
	for mine, theirs in pairs(gmDanger) do
		if theirs ~= nil and theirs ~= mine then
			ErrorNoHalt("[" .. FACTION .. "] danger level " .. mine .. " no longer matches the gamemode (" .. tostring(theirs) .. "). Update the DANGER_* numbers at the top of this file.\n")
		end
	end
	if SERVER and not jcms.npc_types then return end

	-- Faction entry (both realms: lobby, colours, mission board)
	jcms.factions[FACTION] = jcms.factions[FACTION] or { name = FACTION, color = COLOR }

	-- Enemies (server only: the gamemode's enemy table lives on the server)
	if SERVER then
		for key, data in pairs(ENEMIES) do
			local copy = table.Copy(data)
			copy.faction = FACTION
			if copy.danger == nil then
				-- An enemy with no danger crashes the director ("attempt to compare nil with number" in
				-- director_MakeQueue). Use the DANGER_* locals from the top of this file.
				copy.danger = jcms.NPC_DANGER_FODDER
				ErrorNoHalt("[" .. FACTION .. "] enemy '" .. tostring(key) .. "' has no danger set - write jcms.NPC_DANGER_FODDER / _STRONG / _BOSS / _RAREBOSS. Using FODDER for now.\n")
			end
			jcms.npc_types[id(key)] = copy
			if copy.model then util.PrecacheModel(copy.model) end
		end
	end

	-- Sub-factions: translate enemy keys into full ids
	if sweeper and sweeper.subfactions and #SUBFACTIONS > 0 then
		local list = {}
		for i, sf in ipairs(SUBFACTIONS) do
			local c = table.Copy(sf)
			for _, field in ipairs({ "weights", "limits" }) do
				if c[field] then
					local t = {}
					for k, v in pairs(c[field]) do t[ENEMIES[k] and id(k) or k] = v end
					c[field] = t
				end
			end
			list[#list + 1] = c
		end
		sweeper.subfactions[FACTION] = list
	end

	if SERVER then
		-- Commander: places this faction's prefabs at mission start
		jcms.npc_commanders = jcms.npc_commanders or {}
		jcms.npc_commanders[FACTION] = jcms.npc_commanders[FACTION] or {
			placePrefabs = function(c, data)
				if not next(PREFABS) then return end
				local count = math.ceil(jcms.mapgen_AdjustCountForMapSize(PREFAB_COUNT) * jcms.runprogress_GetDifficulty())
				jcms.mapgen_PlaceFactionPrefabs(count, FACTION)
			end,
		}
		if jcms.prefabs then
			for key, p in pairs(PREFABS) do
				local copy = table.Copy(p)
				copy.faction = FACTION
				jcms.prefabs[id(key)] = copy
			end
		end
		if file.Exists("materials/jcms/factions/" .. FACTION .. ".png", "GAME") then
			resource.AddFile("materials/jcms/factions/" .. FACTION .. ".png")
		end
	else
		-- Names (the gamemode looks up "jcms.<faction>" and "jcms.bestiary_<enemy id>")
		language.Add("jcms." .. FACTION, NAME)
		for key, b in pairs(BESTIARY) do
			language.Add("jcms.bestiary_" .. id(key), b.title)
			language.Add("jcms.bestiary_" .. id(key) .. "_desc", b.desc)
			if jcms.bestiary and ENEMIES[key] then
				jcms.bestiary[id(key)] = {
					danger = ENEMIES[key].danger, faction = FACTION,
					bounty = ENEMIES[key].bounty, health = b.health,
					mdl = b.mdl,
				}
			end
		end
	end
end

hook.Add("MapSweepersReady", "jcms_faction_" .. FACTION, install)
install() -- Lua refresh / loaded after the gamemode was already ready
