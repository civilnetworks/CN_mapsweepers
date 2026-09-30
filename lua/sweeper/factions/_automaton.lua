local FACTION = "automatons"
local NAME    = "The Automatons"
local COLOR   = Color(190, 0, 0)

-- The gamemode's danger levels, as plain numbers. Faction files load from lua/autorun BEFORE the gamemode
-- runs, so the jcms table doesn't exist yet and jcms.NPC_DANGER_* would be an error here. install() below
-- checks these still match the gamemode.
local DANGER_FODDER, DANGER_STRONG, DANGER_BOSS, DANGER_RAREBOSS = 1, 2, 3, 4


local ENEMIES = {

	automatons_trooper = {
		class = "npc_vj_automaton_trooper",
		danger = DANGER_FODDER,
		cost = 1.4,
		swarmWeight = 1,
		portalSpawnWeight = 1,
		bounty = 30,
		weapon = "weapon_vj_fusion_smg",
		proficiency = WEAPON_PROFICIENCY_POOR,
	},

	automatons_brawler = {
		class = "npc_vj_brawler",
		danger = DANGER_FODDER,
		cost = 1.3,
		swarmWeight = 1,
		portalSpawnWeight = 0.8,
		bounty = 40,
		weapon = "weapon_vj_brawler",
		proficiency = WEAPON_PROFICIENCY_POOR,
	},

	automatons_commissar = {
		class = "npc_vj_commissar",
		danger = DANGER_FODDER,
		cost = 1.5,
		swarmWeight = 0.7,
		portalSpawnWeight = 0.75,
		bounty = 50,
		weapon = "weapon_vj_fusion_pistol",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_marauder = {
		class = "npc_vj_tmarauder",
		danger = DANGER_FODDER,
		cost = 1.8,
		swarmWeight = 0.7,
		portalSpawnWeight = 0.75,
		bounty = 50,
		weapon = "weapon_vj_fusion_smg",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_raider = {
		class = "npc_vj_mg_raider",
		danger = DANGER_FODDER,
		cost = 1.9,
		swarmWeight = 0.5,
		portalSpawnWeight = 0.75,
		portalScale = 1.2,
		bounty = 50,
		weapon = "weapon_vj_fusion_lmg",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_jet_trooper = {
		class = "npc_vj_jb_trooper",
		danger = DANGER_FODDER,
		cost = 1.3,
		swarmWeight = 0.7,
		portalSpawnWeight = 0.15,
		portalScale = 1.2,
		bounty = 60,
		weapon = "weapon_vj_fusion_smg",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_jet_commissar = {
		class = "npc_vj_jb_commissar",
		danger = DANGER_FODDER,
		cost = 1.7,
		swarmWeight = 0.6,
		portalSpawnWeight = 0.15,
		swarmLimit = 2,
		portalScale = 1.2,
		bounty = 50,
		weapon = "weapon_vj_fusion_pistol",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_jet_assault_raider = {
		class = "npc_vj_jb_assault_raider",
		danger = DANGER_FODDER,
		cost = 1.3,
		swarmWeight = 0.7,
		portalSpawnWeight = 0.15,
		portalScale = 1.2,
		bounty = 60,
		weapon = "weapon_vj_fusion_pistol",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_jet_mg_raider = {
		class = "npc_vj_jb_mg_raider",
		danger = DANGER_FODDER,
		cost = 1.8,
		swarmWeight = 0.6,
		portalSpawnWeight = 0.15,
		portalScale = 1.2,
		bounty = 60,
		weapon = "weapon_vj_fusion_lmg",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_pyro_trooper = {
		class = "npc_vj_jb_trooper",
		danger = DANGER_FODDER,
		cost = 1.5,
		swarmWeight = 0.7,
		portalSpawnWeight = 0.15,
		portalScale = 1.2,
		swarmLimit = 2,
		bounty = 55,
		weapon = "weapon_vj_port_flamer",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_rocket_raider = {
		class = "npc_vj_rocket_raider",
		danger = DANGER_STRONG,
		cost = 3,
		swarmWeight = 0.8,
		portalScale = 2.5,
		swarmLimit = 2,
		bounty = 150,
		weapon = "weapon_vj_port_launcher",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},
	
	automatons_incendiary_rocket_raider = {
		class = "npc_vj_incendiary_rocket_raider",
		danger = DANGER_STRONG,
		cost = 3,
		swarmWeight = 0.8,
		portalScale = 2.5,
		swarmLimit = 2,
		bounty = 150,
		weapon = "weapon_vj_port_launcher",
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},
	
	automatons_berserker = {
		class = "npc_vj_berserker",
		danger = DANGER_STRONG,
		cost = 2,
		swarmWeight = 0.5,
		portalScale = 3,
		swarmLimit = 3,
		bounty = 150,
		proficiency = WEAPON_PROFICIENCY_AVERAGE,
	},

	automatons_devestator = {
		class = "npc_vj_devastator",
		danger = DANGER_STRONG,
		cost = 2,
		swarmWeight = 1,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 180,
	},

	automatons_rocket_devestator = {
		class = "npc_vj_devastator_roc",
		danger = DANGER_STRONG,
		cost = 2,
		swarmWeight = 1,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 275,
	},

	automatons_heavy_devestator = {
		class = "npc_vj_devastator_hev",
		danger = DANGER_STRONG,
		cost = 4,
		swarmWeight = .7,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 250,
	},

	automatons_jet_devestator = {
		class = "npc_vj_jb_devastator",
		danger = DANGER_STRONG,
		cost = 2,
		swarmWeight = .8,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 200,
	},

	automatons_conflagration_devastator = {
		class = "npc_vj_devastator_ic",
		danger = DANGER_STRONG,
		cost = 2,
		swarmWeight = .8,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 280,
	},
	
	automatons_incendiary_devestator = {
		class = "npc_vj_devastator_ic_hev",
		danger = DANGER_STRONG,
		cost = 4,
		swarmWeight = 1,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 350,
	},

	automatons_cyborg_radical = {
		class = "npc_vj_cyborg_radical",
		danger = DANGER_STRONG,
		cost = 2,
		swarmWeight = 1.2,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 160,
		weapon = "weapon_vj_fusion_shotgun",
	},

	automatons_cyborg_agitator = {
		class = "npc_vj_cyborg_agitator",
		danger = DANGER_STRONG,
		cost = 2,
		swarmWeight = 1,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 175,
		weapon = "weapon_vj_fusion_charger",
	},

	automatons_scout_strider = {
		class = "npc_vj_strider_norm",
		danger = DANGER_STRONG,
		cost = 3,
		swarmWeight = 0.9,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 200,
	},

	automatons_reinforced_scout_strider = {
		class = "npc_vj_strider_re",
		danger = DANGER_STRONG,
		cost = 3,
		swarmWeight = 0.9,
		portalScale = 3,
		swarmLimit = 2,
		bounty = 350,
	},

	automatons_hulk = {
		class = "npc_vj_hulk_bruiser",
		danger = DANGER_BOSS,
		cost = 5,
		swarmWeight = 5,
		portalScale = 3.75,
		swarmLimit = 1,
		bounty = 600,
	},

	automatons_hulk_scorcher = {
		class = "npc_vj_hulk_scorcher",
		danger = DANGER_BOSS,
		cost = 4,
		swarmWeight = 5,
		portalScale = 3.75,
		swarmLimit = 2,
		bounty = 550,
	},

	automatons_hulk_obliterator = {
		class = "npc_vj_hulk_obliterator",
		danger = DANGER_BOSS,
		cost = 7,
		swarmWeight = 2,
		portalScale = 3.75,
		swarmLimit = 1,
		bounty = 800,
	},
	
	automatons_hulk_jet = {
		class = "npc_vj_jb_hulk_bruiser",
		danger = DANGER_BOSS,
		cost = 5,
		swarmWeight = 2,
		portalScale = 3.75,
		swarmLimit = 1,
		bounty = 620,
	},

	automatons_hulk_jet_scorcher = {
		class = "npc_vj_jb_hulk_scorcher",
		danger = DANGER_BOSS,
		cost = 5,
		swarmWeight = 2,
		portalScale = 3.75,
		swarmLimit = 1,
		bounty = 620,
	},

	automatons_hulk_firebomber = {
		class = "npc_vj_hulk_firebomber",
		danger = DANGER_BOSS,
		cost = 7,
		swarmWeight = 2,
		portalScale = 3.75,
		swarmLimit = 1,
		bounty = 650,
	},

	automatons_war_strider = {
		class = "npc_vj_war_strider",
		danger = DANGER_BOSS,
		cost = 6,
		swarmWeight = 4,
		portalScale = 4,
		swarmLimit = 1,
		bounty = 800,
	},

	automatons_shredder_tank = {
		class = "npc_vj_shredder_tank",
		danger = DANGER_BOSS,
		cost = 9,
		swarmWeight = 6.5,
		portalScale = 4,
		swarmLimit = 1,
		bounty = 900,
	},

	automatons_gunship = {
		class = "npc_vj_gunship",
		danger = DANGER_BOSS,
		cost = 8,
		aerial = true,
		swarmWeight = 2,
		portalScale = 3.75,
		swarmLimit = 2,
		bounty = 670,
	},

	automatons_anihilator_tank = {
		class = "npc_vj_annihiliator_tank",
		danger = DANGER_RAREBOSS,
		cost = 5,
		swarmWeight = 1.5,
		portalScale = 4,
		swarmLimit = 1,
		bounty = 900,
	},

	automatons_barrage_tank = {
		class = "npc_vj_barrager_tank",
		danger = DANGER_RAREBOSS,
		cost = 6,
		swarmWeight = 1.5,
		portalScale = 4,
		swarmLimit = 1,
		bounty = 850,
	},

	automatons_factory_strider = {
		class = "npc_vj_factory_strider",
		danger = DANGER_RAREBOSS,
		cost = 9,
		swarmWeight = 1,
		portalScale = 10,
		swarmLimit = 1,
		bounty = 1300,
	},

	automatons_vox_engine = {
		class = "npc_vj_vox_engine",
		danger = DANGER_RAREBOSS,
		cost = 10,
		swarmWeight = .6,
		portalScale = 10,
		swarmLimit = 1,
		bounty = 1300,
	},
	
}

-- // BESTIARY (client, optional) ======================================================================
-- Entries for the in-game bestiary. health/bounty are just what the page displays.
local BESTIARY = {
	automatons_trooper = { title = "Automaton Trooper",    desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/trooper.mdl", health = 85 },
	automatons_brawler = { title = "Automaton Brawler",    desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/brawler/trooper.mdl", health = 125 },
	automatons_commissar = { title = "Automaton Commissar",   desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/commissar/trooper.mdl", health = 85 },
	automatons_marauder = { title = "Automaton Marauder",    desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/marauder/trooper_tier2.mdl", health = 150 },
	automatons_raider = { title = "Automaton Raider",      desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/lmg_raider/trooper_tier2.mdl", health = 175 },
	automatons_rocket_raider = { title = "Rocket Raider",      desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/rocket_raider/trooper.mdl", health = 85 },
	automatons_berserker = { title = "Berserker", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/berserk/berserker.mdl", health = 300 },
	automatons_devestator = { title = "Devastator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/devs/devastator.mdl", health = 300 },
	automatons_rocket_devestator = { title = "Rocket Devastator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/devs/rocket_devastator.mdl", health = 300 },
	automatons_heavy_devestator = { title = "Heavy Devastator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/devs/heavy_devastator.mdl", health = 300 },
	automatons_hulk = { title = "Hulk Bruiser", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/hulk/bruiser/hulk.mdl", health = 500 },
	automatons_hulk_scorcher = { title = "Hulk Scorcher", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/hulk/scorch/hulk_scorcher.mdl", health = 500 },
	automatons_hulk_obliterator = { title = "Hulk Obliterator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/hulk/ob/hulk.mdl", health = 500 },
	automatons_jet_trooper = { title = "Jet Brigade Trooper", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/jb_assault_raider/trooper.mdl", health = 125 },
	automatons_jet_commissar = { title = "Jet Brigade Commissar", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/jb_commissar/trooper.mdl", health = 125 },
	automatons_jet_assault_raider = { title = "Jet Brigade Assault Raider", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/jb_trooper/trooper.mdl", health = 150 },
	automatons_jet_mg_raider = { title = "Jet Brigade MG Raider", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/jb_mg_raider/trooper.mdl", health = 125 },
	automatons_jet_devestator = { title = "Jet Brigade Devastator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/devs/jet/devastator.mdl", health = 300 },
	automatons_hulk_jet = { title = "Jet Brigade Hulk Bruiser", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/hulk/jb_bru/hulk.mdl", health = 500 },
	automatons_hulk_jet_scorcher = { title = "Jet Brigade Hulk Scorcher", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/hulk/jb_scorch/hulk_scorcher.mdl", health = 500 },
	automatons_pyro_trooper = { title = "Pyro Trooper", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/pyro_trooper/pyro_trooper.mdl", health = 175 },
	automatons_incendiary_rocket_raider = { title = "Incendiary Rocket Raider", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/automatons/incendiary_rocket_raider/pyro_trooper.mdl", health = 125 },
	automatons_conflagration_devastator = { title = "Conflagration Devastator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/devs/ic/devastator.mdl", health = 300 },
	automatons_incendiary_devestator = { title = "Incendiary MG Devastator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/devs/ic/heavy_devastator.mdl", health = 300 },
	automatons_hulk_firebomber = { title = "Hulk Firebomber", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/hulk/firebomber/hulk.mdl", health = 500 },
	automatons_cyborg_radical = { title = "Cyborg Radical", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/cyborg/cyborg_female.mdl", health = 250 },
	automatons_cyborg_agitator = { title = "Cyborg Agitator", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/agitator/cyborg_male.mdl", health = 250 },
	automatons_scout_strider = { title = "Scout Strider", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/scout/scout_strider.mdl", health = 250 },
	automatons_reinforced_scout_strider = { title = "Reinforced Scout Strider", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/scout/reinforced_scout_strider.mdl", health = 250 },
	automatons_shredder_tank = { title = "Shredder Tank", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/tanks/shredder_tank.mdl", health = 750 },
	automatons_anihilator_tank = { title = "Annihilator Tank", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/tanks/annihilator_tank.mdl", health = 750 },
	automatons_barrage_tank = { title = "Barrage Tank", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/tanks/barrager_tank.mdl", health = 750 },
	automatons_gunship = { title = "Gunship", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/ships/gunship.mdl", health = 300 },
	automatons_war_strider = { title = "War Strider", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/warstrider/war_strider.mdl", health = 750 },
	automatons_factory_strider = { title = "Factory Strider", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/factory/factory_strider.mdl", health = 3000 },
	automatons_vox_engine = { title = "Vox Engine", desc = "Cheap, numerous, poorly trained.", mdl = "models/vj_hd2/vox/vox_engine.mdl", health = 3000 },
}

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
local PREFAB_COUNT = 2

local SUBFACTIONS = {
	{id = "jb", name = "Jet Brigade",
	desc = "They are enhanced variants of various Automaton infantry, equipped with jump-packs that grant them increased mobility and aggressive capabilities.",
	weights = { automatons_jet_trooper = 1, automatons_jet_commissar = 1, automatons_jet_assault_raider = 1, automatons_jet_mg_raider = 1, automatons_jet_devestator =1, automatons_hulk_jet = 1, automatons_hulk_jet_scorcher = 1 }, 
	limits = { automatons_hulk_jet = 2, automatons_hulk_jet_scorcher = 1, }
	},

	{id = "ic", name = "Incineration Corps",
	desc = "They are identified by their red and white color scheme, and are equipped with incendiary weapons.",
	weights = { automatons_pyro_trooper = 1, automatons_incendiary_rocket_raider = 1, automatons_conflagration_devastator = 1, automatons_incendiary_devestator = 1, automatons_hulk_firebomber = 7 },
	limits = { automatons_incendiary_rocket_raider = 2, automatons_incendiary_devestator = 2, automatons_hulk_firebomber = 1 }
	},

	{id = "cl", name = "Cyborg Legion",
	desc = "They are descendants of the Cyborgs from the First Galactic War.",
	weights = { automatons_cyborg_radical = .8, automatons_cyborg_agitator = 1.5, automatons_vox_engine = 9},
	limits = { automatons_cyborg_agitator = 2, automatons_vox_engine = 1 }
	},
}

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
