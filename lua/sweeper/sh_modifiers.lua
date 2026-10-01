--[[
	Map Sweepers - Implants & Class Levels (addon)
	MISSION MODIFIERS + WEATHER EFFECTS

	MODIFIERS
	- Every time the gamemode picks a new mission (new map, New Contract reroll, admin reroll) 0-2 modifiers
	  are rolled for it. Higher win streaks roll more and nastier ones; boss missions always get one extra
	  negative. They show in the TEAM UPGRADES tab (lobby), in chat, and on the HUD during the mission.
	- POSITIVE ones help. NEGATIVE ones hurt but pay extra V Tokens on victory. MIXED are trade-offs.
	- Player stats (health, shields, damage, call-in cost...) go through the Implants stat system, so they
	  apply to the 4 Implant classes (Infantry, Recon, Engineer, Sentinel).
	- Disabled in PvP and on special maps.

	WEATHER (gWeather)
	- sh_weather.lua rolls the weather with the modifiers and spawns it at mission start (jcms_weather_roll 1).
	  With jcms_weather_roll 0, JWeather picks it instead. Either way, this file looks at which gWeather
	  entity is running and adds gameplay effects for it (see S.weatherEffects).

	Convars:  jcms_modifiers 1/0, jcms_modifiers_max 2, jcms_weather_effects 1/0,
	          jcms_modhud 1/0 (client)
	Admin:    jcms_mods_reroll, jcms_mods_set <id> [id...], jcms_mods_list
--]]

local S = sweeper

-- // Tuning {{{
S.modConfig = {
	-- how many modifiers a mission gets (weights for 0 / 1 / 2 / 3), before the max convar
	countWeightsLow  = { [0] = 3, [1] = 5, [2] = 2 },       -- win streak 0-15
	countWeightsHigh = { [0] = 1, [1] = 4, [2] = 4, [3] = 1 }, -- win streak 30+
	-- chance for each rolled modifier to be negative / positive (rest = mixed), by win streak
	negativeChance = function(streak) return math.Clamp(0.35 + streak * 0.006, 0.35, 0.7) end,
	positiveChance = function(streak) return math.Clamp(0.40 - streak * 0.005, 0.12, 0.40) end,
	shortFuseAfter = 15 * 60,     -- Short Fuse kicks in after this many seconds
	skiesInterval = 180,          -- Friendly Skies: free strike every N seconds
	reconSweepTime = 60,          -- Recon Sweep lasts this long
	reconSweepRange = 1500,
	scavengerChance = 0.15,
	adrenalineTime = 2,
	adrenalineSpeed = 1.15,
	volatileRadius = 130,
	volatileDamage = 25,
	medicsCap = 0.5,              -- Field Medics heal up to this fraction of max health
	toxicStillTime = 2,           -- Toxic Air: seconds standing still before it hurts

	scrambleRadius = 300,         -- Scrambled Comms: call-ins land up to this far off target
	regenDelay = 5,               -- Regenerating Foes: seconds without damage before enemies heal...
	regenPerSec = 0.05,           -- ...this fraction of their max health per second
	extractionPerSweeper = 1,     -- Extraction Bonus: V Tokens per sweeper still alive at the end of a win
	squadLinkRange = 400,         -- Squad Link: a teammate this close...
	squadLinkDamage = 1.10,       -- ...gives this damage multiplier
	secondWindTime = 3,           -- Second Wind: seconds of invulnerability after surviving on 1 HP
	hazardPayCash = 150,          -- Hazard Pay: cash for every sweeper per completed objective
}
-- }}}

-- // Modifier definitions {{{
--[[
	kind     "pos" | "neg" | "mix"
	stats    player stats for the Implant stat system (hpPct / armorPct = % of the class's base value)
	knobs    world numbers (multiplied together if several modifiers set the same one):
	         npcDamageMul, npcTakeMul, npcSpeedMul, npcLookMul, npcHealthMul, spawnCostMul, strongWeightMul,
	         bountyMul, ammoMul, explosiveMul, evacMul, headshotMul, bodyMul, weaponDiscount (0-1)
	         and (added together): npcShield, outdoorDps, stillOutdoorDps, npcOutdoorDps
	         gravity (lowest wins), fog / dark / brokenHud (true)
	reward   extra V Tokens on victory
	conflicts  ids that can't roll together with this one
--]]
S.modifiers = {
	-- POSITIVE ------------------------------------------------------------------------------
	{ id = "supplydrop", kind = "pos", name = "Supply Drop Season", desc = "Call-ins cost 25% less.",
	  stats = { orderCost = 0.25 }, conflicts = { "jamming", "firesale" } },
	{ id = "uplink", kind = "pos", name = "Priority Uplink", desc = "Call-in cooldowns are 30% shorter.",
	  stats = { orderCooldown = 0.30 }, conflicts = { "jamming" } },
	{ id = "bountyweek", kind = "pos", name = "Bounty Week", desc = "Enemies pay +50% cash.",
	  knobs = { bountyMul = 1.5 }, conflicts = { "bountyrush" } },
	{ id = "suits", kind = "pos", name = "Overcharged Suits", desc = "+25 max shield for every sweeper.",
	  stats = { armor = 25 }, conflicts = { "ironman", "fragile" } },
	{ id = "medics", kind = "pos", name = "Nano Machines", desc = "Health slowly regenerates up to 50%." },
	{ id = "stockpile", kind = "pos", name = "Stockpile", desc = "Ammo pickups and crates give double.",
	  knobs = { ammoMul = 2 }, conflicts = { "lowsupply", "drought" } },
	{ id = "reconsweep", kind = "pos", name = "Recon Sweep", desc = "For the first 60s, enemies near the squad are outlined for everyone." },
	{ id = "veteran", kind = "pos", name = "Veteran Training", desc = "+50% class XP this mission.",
	  stats = { xp = 0.5 } },
	{ id = "extralives", kind = "pos", name = "Extra Lives", desc = "+1 team respawn.", conflicts = { "norespawns" } },
	{ id = "adrenaline", kind = "pos", name = "Adrenaline Surge", desc = "Every kill gives 2s of +15% move speed." },
	{ id = "armoryloan", kind = "pos", name = "Armory Loan", desc = "One weapon the squad hasn't unlocked yet is in the shop this mission." },
	{ id = "luckyhacks", kind = "pos", name = "Lucky Hacks", desc = "Every hacked terminal gives V Tokens." },
	{ id = "rapidevac", kind = "pos", name = "Rapid Evac", desc = "The evac ship charges 50% faster.",
	  knobs = { evacMul = 0.5 } },
	{ id = "skies", kind = "pos", name = "Friendly Skies", desc = "A free Precision Strike hits the biggest enemy group every 3 minutes." },
	{ id = "ironrations", kind = "pos", name = "Blast Plating", desc = "Sweepers take 30% less explosive damage.",
	  stats = { blast = 0.30 } },
	{ id = "scavenger", kind = "pos", name = "Scavenger", desc = "Enemies sometimes drop a health vial or suit battery." },
	{ id = "extraction", kind = "pos", name = "Extraction Bonus", desc = "On a win, every sweeper still alive adds +1 V Token." },
	{ id = "hardlight", kind = "pos", name = "Hardlight Armor", desc = "Shields start recharging 50% sooner after taking damage.",
	  stats = { delay = 0.50 }, conflicts = { "ironman" } },
	{ id = "intelleak", kind = "pos", name = "Intel Leak", desc = "Objectives and terminals show on the compass from the start.",
	  conflicts = { "brokenhud" } },
	{ id = "squadlink", kind = "pos", name = "Squad Link", desc = "+10% damage while a teammate is within 400 units of you." },
	{ id = "secondwind", kind = "pos", name = "Second Wind", desc = "Once per life, a killing blow leaves you on 1 HP with 3s of invulnerability instead." },
	{ id = "hazardpay", kind = "pos", name = "Hazard Pay", desc = "Every completed objective pays each sweeper +150 cash." },

	-- NEGATIVE ------------------------------------------------------------------------------
	{ id = "fog", kind = "neg", name = "Dense Fog", desc = "Thick fog: you can't see far.", reward = 3,
	  knobs = { fog = true } },
	{ id = "blackout", kind = "neg", name = "Blackout", desc = "The map goes dark. Bring a flashlight.", reward = 4,
	  knobs = { dark = true } },
	{ id = "armored", kind = "neg", name = "Armored Foes", desc = "Enemies take 25% less damage.", reward = 4,
	  knobs = { npcTakeMul = 0.75 } },
	{ id = "berserkers", kind = "neg", name = "Berserkers", desc = "Enemies deal 25% more damage.", reward = 4,
	  knobs = { npcDamageMul = 1.25 } },
	{ id = "swift", kind = "neg", name = "Swift Hunters", desc = "Enemies move about 20% faster.", reward = 3,
	  knobs = { npcSpeedMul = 1.2 } },
	{ id = "reinforcements", kind = "neg", name = "Reinforcements", desc = "Enemy waves are 30% bigger.", reward = 3,
	  knobs = { spawnCostMul = 1 / 1.3 } },
	{ id = "elite", kind = "neg", name = "Elite Squads", desc = "Strong enemy types show up far more often.", reward = 4,
	  knobs = { strongWeightMul = 2.5 } },
	{ id = "jamming", kind = "neg", name = "Signal Jamming", desc = "Call-ins cost 30% more and recharge 30% slower.", reward = 3,
	  stats = { orderCost = -0.30, orderCooldown = -0.30 }, conflicts = { "supplydrop", "uplink" } },
	{ id = "lowsupply", kind = "neg", name = "Low Supply", desc = "Ammo pickups and crates give half.", reward = 3,
	  knobs = { ammoMul = 0.5 }, conflicts = { "stockpile", "drought" } },
	{ id = "fragile", kind = "neg", name = "Fragile Shields", desc = "Shields recharge 40% slower.", reward = 2,
	  stats = { regen = -0.40 }, conflicts = { "suits" } },
	{ id = "norespawns", kind = "neg", name = "No Respawns", desc = "Team respawns are disabled.", reward = 5,
	  conflicts = { "extralives" } },
	{ id = "volatile", kind = "neg", name = "Volatile Enemies", desc = "Enemies explode a moment after they die.", reward = 3 },
	{ id = "shielded", kind = "neg", name = "Shielded Enemies", desc = "Every enemy has a small regenerating shield.", reward = 3,
	  knobs = { npcShield = 20 } },
	{ id = "toxic", kind = "neg", name = "Toxic Air", desc = "Standing still outdoors slowly drains your health.", reward = 2,
	  knobs = { stillOutdoorDps = 3 } },
	{ id = "hunted", kind = "neg", name = "Hunted", desc = "Enemies always know where the squad is.", reward = 4 },
	{ id = "shortfuse", kind = "neg", name = "Short Fuse", desc = "After 15 minutes, enemies deal +50% damage and come 50% faster.", reward = 3 },
	{ id = "brokenhud", kind = "neg", name = "Broken HUD", desc = "No locators, and the compass keeps cutting out.", reward = 2,
	  knobs = { brokenHud = true } },
	{ id = "scrambled", kind = "neg", name = "Scrambled Comms", desc = "Strikes and drops land up to 300 units off target.", reward = 2 },
	{ id = "lockedterms", kind = "neg", name = "Locked Terminals", desc = "Terminals have two security layers: every hack has to be done twice.", reward = 2,
	  conflicts = { "luckyhacks" } },
	{ id = "drought", kind = "neg", name = "Ammo Drought", desc = "Enemies don't drop ammo, and ammo pickups and crates give 30% less.", reward = 3,
	  knobs = { ammoMul = 0.7 }, conflicts = { "stockpile", "lowsupply" } },
	{ id = "regenfoes", kind = "neg", name = "Regenerating Foes", desc = "Enemies heal back 5% of their health per second after 5s without taking damage.", reward = 3 },
	{ id = "glass", kind = "neg", name = "Glass Cannons", desc = "Sweepers deal +30% damage but have 30% less max health.", reward = 2,
	  stats = { dmg = 0.30, hpPct = -0.30 } },

	-- MIXED ---------------------------------------------------------------------------------
	{ id = "lowgrav", kind = "mix", name = "Low Gravity", desc = "Half gravity for everyone: big jumps, long falls.", reward = 1,
	  knobs = { gravity = 300 } },
	{ id = "bountyrush", kind = "mix", name = "Bounty Rush", desc = "Double kill cash, but enemies hit 25% harder.", reward = 1,
	  knobs = { bountyMul = 2, npcDamageMul = 1.25 }, conflicts = { "bountyweek" } },
	{ id = "swarm", kind = "mix", name = "Swarm", desc = "Twice as many enemies, each with half health.", reward = 2,
	  knobs = { spawnCostMul = 0.5, npcHealthMul = 0.5 } },
	{ id = "ironman", kind = "mix", name = "Ironman", desc = "No shields at all, but +50 max health.", reward = 2,
	  stats = { armorPct = -1, hp = 50 }, conflicts = { "suits", "fragile" } },
	{ id = "marksman", kind = "mix", name = "Marksman Contract", desc = "Headshots deal +50% damage, body shots 25% less.", reward = 1,
	  knobs = { headshotMul = 1.5, bodyMul = 0.75 } },
	{ id = "ordnance", kind = "mix", name = "Heavy Ordnance", desc = "All explosions deal +50% damage, sweepers included.", reward = 1,
	  knobs = { explosiveMul = 1.5 } },
	{ id = "highstakes", kind = "mix", name = "High Stakes", desc = "Enemies are tougher, but victory pays double V Tokens.",
	  knobs = { npcTakeMul = 0.85, npcDamageMul = 1.15 }, doubleVictory = true },
	{ id = "cloak", kind = "mix", name = "Cloak & Dagger", desc = "Enemies see 40% less far, but deal 40% more damage.", reward = 1,
	  knobs = { npcLookMul = 0.6, npcDamageMul = 1.4 } },
	{ id = "firesale", kind = "mix", name = "Fire Sale", desc = "Shop purchases refund 40%, but call-ins cost 40% more.", reward = 1,
	  knobs = { weaponDiscount = 0.4 }, stats = { orderCost = -0.40 }, conflicts = { "supplydrop" } },
	{ id = "bloodlust", kind = "mix", name = "Bloodlust", desc = "Kills heal 8 HP, but sweepers take 15% more damage.", reward = 1,
	  stats = { killHeal = 8, resist = -0.15 } },
}

S.modById = {}
for i, m in ipairs(S.modifiers) do S.modById[m.id] = m end

S.modKindColors = {
	pos = function() return (jcms and jcms.color_bright_alt) or Color(64, 180, 255) end,
	neg = function() return (jcms and jcms.color_bright) or Color(255, 0, 0) end,
	mix = function() return (jcms and jcms.color_alert1) or Color(255, 255, 0) end,
}
S.modKindLabel = { pos = "+", neg = "-", mix = "~" }
-- }}}

-- // Weather effects (by gWeather entity class) {{{
-- Same fields as a modifier (stats / knobs). name falls back to the entity's PrintName.
local W = {}
local clear = { desc = "No effect." }
for _, c in ipairs({ "gw_t1_sunny", "gw_t1_partlycloudy", "gw_t1_cloudy", "gw_t1_lightwind", "gw_t1_warmfront",
	"gw_t2_coldfront", "gw_t1_shootingstar", "gw_t1_night", }) do W[c] = clear end

W.gw_t1_auroraborealis = { desc = "There a pretty sky.", knobs = { bountyMul = 1.2, } }
W.gw_t1_heavyfog       = { desc = "Enemies see 40% less far.", knobs = { npcLookMul = 0.6 } }
W.gw_t1_lightrain      = { desc = "Fire damage to sweepers -25%.", stats = { fire = 0.25 } }
W.gw_t1_sleet          = { desc = "-5% move speed, fire damage to sweepers -25%.", stats = { speed = -0.05, fire = 0.25 } }
W.gw_t1_lightsnow      = { desc = "-5% move speed.", stats = { speed = -0.05 } }
W.gw_t1_drought        = { desc = "Shields recharge 15% slower.", stats = { regen = -0.15 } }
W.gw_t2_heavyrain      = { desc = "Enemies see 20% less far, fire damage to sweepers -40%.", stats = { fire = 0.4 }, knobs = { npcLookMul = 0.8 } }
W.gw_t2_tropicalstorm  = { desc = "Enemies see 25% less far, call-ins recharge 15% slower.", stats = { fire = 0.4, orderCooldown = -0.15 }, knobs = { npcLookMul = 0.75 } }
W.gw_t2_heavysnow      = { desc = "-10% move speed for everyone.", stats = { speed = -0.10 }, knobs = { npcSpeedMul = 0.9 } }
W.gw_t2_coldfreeze     = { desc = "-10% move speed, shields recharge 25% slower.", stats = { speed = -0.10, regen = -0.25 } }
W.gw_t2_heatwave       = { desc = "Shields recharge 25% slower.", stats = { regen = -0.25 } }
W.gw_t2_ashstorm       = { desc = "Enemies see 40% less far, shields recharge 10% slower.", stats = { regen = -0.10 }, knobs = { npcLookMul = 0.6 } }
W.gw_t2_haboob         = { desc = "Enemies see 40% less far.", knobs = { npcLookMul = 0.6 } }
W.gw_t2_bloodrain      = { desc = "Every kill heals 3 HP, enemies pay +10% cash.", stats = { killHeal = 3 }, knobs = { bountyMul = 1.1 } }
W.gw_t2_moderatewind   = { desc = "Call-ins recharge 10% slower.", stats = { orderCooldown = -0.10 } }
W.gw_t3_acidrain       = { desc = "Being outdoors burns everyone (3/s), enemies too.", knobs = { outdoorDps = 3, npcOutdoorDps = 3 } }
W.gw_t3_blizzard       = { desc = "-15% move speed, enemies slower and see 40% less far, shields recharge 20% slower.",	stats = { speed = -0.15, regen = -0.20 }, knobs = { npcSpeedMul = 0.85, npcLookMul = 0.6 } }
W.gw_t3_c1hurricane    = { desc = "Enemies see 30% less far, call-ins recharge 20% slower.", stats = { orderCooldown = -0.20 }, knobs = { npcLookMul = 0.7 } }
W.gw_t3_extheavyrain   = { desc = "-5% move speed, enemies see 30% less far.", stats = { speed = -0.05, fire = 0.5 }, knobs = { npcLookMul = 0.7 } }
W.gw_t3_severewind     = { desc = "Call-ins recharge 20% slower.", stats = { orderCooldown = -0.20 } }
W.gw_t4_c2hurricane    = { desc = "Enemies see 30% less far, call-ins recharge 25% slower.", stats = { orderCooldown = -0.25 }, knobs = { npcLookMul = 0.7 } }
W.gw_t4_derecho        = { desc = "Call-ins recharge 25% slower.", stats = { orderCooldown = -0.25 } }
W.gw_t4_hurricanewind  = { desc = "Call-ins recharge 25% slower.", stats = { orderCooldown = -0.25 } }
W.gw_t4_martianduststorm = { desc = "Enemies see 50% less far, shields recharge 15% slower.", stats = { regen = -0.15 }, knobs = { npcLookMul = 0.5 } }
W.gw_t4_supercell      = { desc = "Enemies see 25% less far, call-ins recharge 25% slower.", stats = { orderCooldown = -0.25 }, knobs = { npcLookMul = 0.75 } }
W.gw_t5_c3hurricane    = { desc = "Enemies see 35% less far, call-ins recharge 30% slower.", stats = { orderCooldown = -0.30 }, knobs = { npcLookMul = 0.65 } }
W.gw_t5_downburst      = { desc = "Call-ins recharge 30% slower.", stats = { orderCooldown = -0.30 } }
W.gw_t5_mhurricanewind = { desc = "Call-ins recharge 30% slower.", stats = { orderCooldown = -0.30 } }
W.gw_t5_portalstorm    = { desc = "20% more enemies, enemies pay +15% cash.", knobs = { spawnCostMul = 1 / 1.2, bountyMul = 1.15 } }
W.gw_t5_radiationstorm = { desc = "Being outdoors burns everyone (4/s), shields recharge 30% slower.", stats = { regen = -0.30 }, knobs = { outdoorDps = 4, npcOutdoorDps = 4 } }
W.gw_t6_arcticblast    = { desc = "-20% move speed, enemies 15% slower, shields recharge 40% slower.", stats = { speed = -0.20, regen = -0.40 }, knobs = { npcSpeedMul = 0.85 } }
W.gw_t6_c4hurricane    = { desc = "Enemies see 40% less far, call-ins recharge 35% slower.", stats = { orderCooldown = -0.35 }, knobs = { npcLookMul = 0.6 } }
W.gw_t6_firestorm      = { desc = "Shields recharge 30% slower, sweepers take +50% fire damage, outdoors burns (2/s).", stats = { regen = -0.30, fire = -0.5 }, knobs = { outdoorDps = 2 } }
W.gw_t6_unfathomablewind = { desc = "Call-ins recharge 40% slower.", stats = { orderCooldown = -0.40 } }
W.gw_t7_c5hurricane    = { desc = "Enemies see 50% less far, call-ins recharge 40% slower.", stats = { orderCooldown = -0.40 }, knobs = { npcLookMul = 0.5 } }
W.gw_t7_permian_extinction = { desc = "Outdoors burns everyone (6/s), +50% fire damage to sweepers.", stats = { fire = -0.5 }, knobs = { outdoorDps = 6, npcOutdoorDps = 6 } }
W.gw_t7_pyroclastic_flow = { desc = "Outdoors burns everyone (6/s), +50% fire damage to sweepers.", stats = { fire = -0.5 }, knobs = { outdoorDps = 6, npcOutdoorDps = 6 } }
W.gw_t7_space          = { desc = "Very low gravity, shields recharge 50% slower.", stats = { regen = -0.5 }, knobs = { gravity = 150 } }
S.weatherEffects = W
-- }}}

-- // Shared state + queries {{{
--   S.mods.list      rolled modifier ids for the current / upcoming mission
--   S.mods.inMission true while that mission is running
--   S.mods.weather   gWeather class running right now (or "")
--   S.mods.weatherName, S.mods.loan (Armory Loan weapon class)
S.mods = S.mods or { list = {}, inMission = false, weather = "", weatherName = "", loan = "" }

-- Replicated, so clients agree on stats (call-in prices etc.)
S.cvar_mods = CreateConVar("jcms_modifiers", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Roll mission modifiers (1/0).", 0, 1)
S.cvar_weatherFx = CreateConVar("jcms_weather_effects", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Give gWeather/JWeather weather gameplay effects (1/0).", 0, 1)

function S.ModListed(id)
	for i, m in ipairs(S.mods.list or {}) do
		if m == id then return true end
	end
	return false
end

-- Active = listed AND the mission is running
function S.ModActive(id)
	return S.mods.inMission and S.ModListed(id)
end

-- Weather is ON HOLD: no gameplay effects, no weather shown. Set to true to turn it back on
-- (and uncomment sh_weather.lua in lua/autorun/sh_sweeper.lua for the weather roll).
S.weatherEnabled = false

local function weatherDef()
	if not S.weatherEnabled then return nil end
	local w = S.mods.weather
	if not w or w == "" then return nil end
	if S.cvar_weatherFx and not S.cvar_weatherFx:GetBool() then return nil end
	return S.weatherEffects[w]
end
S.CurrentWeatherEffect = weatherDef

local addKnobs = { npcShield = true, outdoorDps = true, stillOutdoorDps = true, npcOutdoorDps = true }
local boolKnobs = { fog = true, dark = true, brokenHud = true }

-- Combined knob from active modifiers + weather (+ Short Fuse once it kicks in)
function S.ModKnob(name)
	local isAdd, isBool = addKnobs[name], boolKnobs[name]
	local v
	if name == "gravity" then v = nil
	elseif isBool then v = false
	elseif isAdd then v = 0
	else v = 1 end

	local function merge(val)
		if val == nil then return end
		if name == "gravity" then v = v and math.min(v, val) or val
		elseif isBool then v = v or val
		elseif isAdd then v = v + val
		elseif name == "weaponDiscount" then v = v * (1 - val) -- stored as "what you still pay"
		else v = v * val end
	end

	if S.mods.inMission then
		for i, id in ipairs(S.mods.list or {}) do
			local m = S.modById[id]
			if m and m.knobs then merge(m.knobs[name]) end
		end
		if S.ModListed("shortfuse") and SERVER and jcms and jcms.director and jcms.director_GetMissionTime
			and jcms.director_GetMissionTime() > S.modConfig.shortFuseAfter then
			if name == "npcDamageMul" then merge(1.5) elseif name == "spawnCostMul" then merge(1 / 1.5) end
		end
		local w = weatherDef()
		if w and w.knobs then merge(w.knobs[name]) end
	end

	if name == "weaponDiscount" then return 1 - v end
	return v
end

-- Player stats from modifiers + weather (added into S.ComputeStats, see sh_tree.lua)
function S.GetModifierStats(class)
	local out = {}
	local data = jcms and jcms.classes and jcms.classes[class]
	local function add(stats)
		for k, val in pairs(stats) do
			if k == "hpPct" then
				out.hp = (out.hp or 0) + math.Round((data and data.health or 100) * val)
			elseif k == "armorPct" then
				out.armor = (out.armor or 0) + math.Round((data and data.shield or 50) * val)
			else
				out[k] = (out[k] or 0) + val
			end
		end
	end
	for i, id in ipairs(S.mods.list or {}) do
		local m = S.modById[id]
		if m and m.stats then add(m.stats) end
	end
	local w = weatherDef()
	if w and w.stats then add(w.stats) end
	return out
end
-- }}}

-- Movement: Adrenaline Surge (shared so it's predicted)
hook.Add("SetupMove", "sweeper_modAdrenaline", function(ply, mv, cmd)
	if ply:GetNWFloat("sweeper_modAdren", 0) > CurTime() then
		local mul = S.modConfig.adrenalineSpeed
		mv:SetMaxSpeed(mv:GetMaxSpeed() * mul)
		mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * mul)
	end
end)

-- Armory Loan: the loaned weapon counts as unlocked (in the lobby too, so it can go in the loadout).
-- S.GunUnlocked lives in sh_gunprogress.lua, which this file loads BEFORE, so the install is retried
-- on the map hooks rather than only at file scope.
function S.InstallModWeaponLoan()
	if S.Wrapped(S, "LoanLock") then return end
	local orig = S.GunUnlocked
	if not orig then return end

	S._wrappedLoanLock = function(class, ...)
		if S.mods.loan ~= "" and S.mods.loan == class and S.ModListed("armoryloan") then return true end
		return orig(class, ...)
	end
	S.GunUnlocked = S._wrappedLoanLock
	S.MarkWrapped(S, "LoanLock")
end
hook.Add("Initialize", "sweeper_modWeaponLoan", S.InstallModWeaponLoan)
hook.Add("InitPostEntity", "sweeper_modWeaponLoan", S.InstallModWeaponLoan)
S.InstallModWeaponLoan()

-- ============================================================================================
if SERVER then
	util.AddNetworkString("sweeper_mods")
	util.AddNetworkString("sweeper_modspot")
	util.AddNetworkString("sweeper_modlight")

	local tokenVictoryCvar = GetConVar("jcms_vtokens_victory")
	S.cvar_modsMax = CreateConVar("jcms_modifiers_max", "2", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, "Most modifiers a mission can roll (boss missions get +1 negative on top).", 0, 5)

	local function tellAll(msg)
		S.ChatPrintAll(msg)
	end

	function S.ModSync(ply)
		net.Start("sweeper_mods")
			net.WriteTable({ list = S.mods.list, inMission = S.mods.inMission, weather = S.mods.weather,
				weatherName = S.mods.weatherName, loan = S.mods.loan, subfaction = S.mods.subfaction or "", plannedWeather = S.mods.plannedWeather or "" })
		if IsValid(ply) then net.Send(ply) else net.Broadcast() end
	end
	hook.Add("jcms_PlayerNetReady", "sweeper_mods", function(ply) timer.Simple(1, function() if IsValid(ply) then S.ModSync(ply) end end) end)
	hook.Add("PlayerInitialSpawn", "sweeper_mods", function(ply) timer.Simple(5, function() if IsValid(ply) then S.ModSync(ply) end end) end)

	local function streak()
		if jcms and jcms.runprogress and jcms.runprogress.winstreak then return jcms.runprogress.winstreak end
		return 0
	end

	local function pickWeighted(weights)
		local total = 0
		for k, w in pairs(weights) do total = total + w end
		local r = math.random() * total
		for k, w in pairs(weights) do
			r = r - w
			if r <= 0 then return k end
		end
		return 0
	end

	local function canAdd(list, m)
		for i, id in ipairs(list) do
			if id == m.id then return false end
			local other = S.modById[id]
			for _, c in ipairs(m.conflicts or {}) do if c == id then return false end end
			for _, c in ipairs(other and other.conflicts or {}) do if c == m.id then return false end end
		end
		return true
	end

	local function rollOne(list, kind)
		local pool = {}
		for i, m in ipairs(S.modifiers) do
			local allowed = m.id ~= "armoryloan" or (S.GunProgressEnabled and S.GunProgressEnabled())
			if m.kind == kind and allowed and canAdd(list, m) then pool[#pool + 1] = m end
		end
		if #pool == 0 then return false end
		list[#list + 1] = pool[math.random(#pool)].id
		return true
	end

	function S.ModsAllowed()
		if not jcms or not S.cvar_mods:GetBool() then return false end
		if jcms.util_IsPVP and jcms.util_IsPVP() then return false end
		if jcms.inSpecialMap then return false end
		return true
	end

	-- Armory Loan: pick a weapon the squad hasn't unlocked yet. It used to read the Armory Access
	-- weapon plan; that upgrade is retired, so the locked pool is now the gun-unlock set.
	local function pickLoan()
		S.mods.loan = ""
		if not S.ModListed("armoryloan") then return end
		if not (S.GunProgressEnabled and S.GunProgressEnabled() and S.GunUnlockOrder) then return end

		local locked = {}
		for i, class in ipairs(S.GunUnlockOrder()) do
			if S.GunUnlocked and not S.GunUnlocked(class) then locked[#locked + 1] = class end
		end
		if #locked > 0 then S.mods.loan = locked[math.random(#locked)] end

		-- The loan makes one locked gun buyable, and locked guns are drawn with a padlock on them now,
		-- so clients need to hear about it or the loaned gun sits there looking locked.
		if S.GunSendLocks then S.GunSendLocks() end
	end

	function S.RollModifiers(silent)
		local list = {}
		if S.ModsAllowed() then
			local st = streak()
			local weights = st >= 30 and S.modConfig.countWeightsHigh or S.modConfig.countWeightsLow
			if st > 15 and st < 30 then weights = { [0] = 2, [1] = 5, [2] = 3 } end
			local count = math.min(pickWeighted(weights), S.cvar_modsMax:GetInt())
			local negC, posC = S.modConfig.negativeChance(st), S.modConfig.positiveChance(st)
			for n = 1, count do
				local r = math.random()
				local kind = (r < negC and "neg") or (r < negC + posC and "pos") or "mix"
				if not rollOne(list, kind) then rollOne(list, "mix") end
			end
			if jcms.mission_IsBossMission and jcms.mission_IsBossMission() then
				rollOne(list, "neg")
			end
		end

		S.mods.list = list
		pickLoan()
		if S.RollSubfaction then S.RollSubfaction(silent) end -- sh_subfactions.lua
		if S.RollWeather then S.RollWeather(silent) end       -- sh_weather.lua
		if S.RefreshWeaponShop then S.RefreshWeaponShop() end
		S.ModSync()

		if not silent and #list > 0 then
			local parts = {}
			for i, id in ipairs(list) do
				local m = S.modById[id]
				parts[#parts + 1] = m.name .. " (" .. S.modKindLabel[m.kind] .. ")"
			end
			tellAll("[Mission Modifiers] This mission: " .. table.concat(parts, ", ") .. ". Details in the TEAM UPGRADES tab.")
		end
	end

	-- Every time the gamemode picks a new mission, roll new modifiers for it
	function S.InstallModRandomize()
		if not (jcms and jcms.mission_Randomize) or S.Wrapped(jcms, "ModRandomize") then return end
		local orig = jcms.mission_Randomize
		S._wrappedModRandomize = function(...)
			local r = { orig(...) }
			if not S._modRollQueued then
				-- New Contract calls Randomize a few times in a row: roll once, right after
				S._modRollQueued = true
				timer.Simple(0, function()
					S._modRollQueued = false
					if not (jcms and jcms.director) then S.RollModifiers() end
				end)
			end
			return unpack(r)
		end
		jcms.mission_Randomize = S._wrappedModRandomize
		S.MarkWrapped(jcms, "ModRandomize")
	end

	-- // Mission start / stop {{{
	local running = {}       -- ids that were started (so they can be stopped even if the list re-rolls)
	local state = {}         -- per-mission scratch data

	local function setLight(style)
		engine.LightStyle(0, style)
		net.Start("sweeper_modlight")
		net.Broadcast()
	end

	-- sv_gravity is the server's, not the mission's, so the value to put back has to outlive the
	-- mission. It used to be kept in `state`, which ModStart replaces on every mission: Low Gravity
	-- (or the space weather) dropped it to 300, the mission ended without restoring, and the next
	-- ModStart wiped the remembered 600 - so the whole server stayed at half gravity until a map
	-- change. That's why every class felt floaty, whatever the mission.
	local baseGravity = nil

	local function applyGravity()
		local g = S.ModKnob("gravity")
		local cv = GetConVar("sv_gravity")
		if not cv then return end

		if g then
			if not baseGravity then baseGravity = cv:GetFloat() end
			RunConsoleCommand("sv_gravity", tostring(g))
		elseif baseGravity then
			RunConsoleCommand("sv_gravity", tostring(baseGravity))
			baseGravity = nil
		end
	end

	-- Put gravity back whatever the modifier list says, for the end of a mission
	function S.ModRestoreGravity()
		if not baseGravity then return end
		RunConsoleCommand("sv_gravity", tostring(baseGravity))
		baseGravity = nil
	end

	function S.ModStart()
		S.mods.inMission = true
		if S.SubfactionApply then S.SubfactionApply() end
		running = table.Copy(S.mods.list or {})
		state = { startTime = CurTime(), nextSkies = CurTime() + S.modConfig.skiesInterval }
		S.modObjSeen = {}

		if S.ModListed("blackout") then setLight("b") state.dark = true end
		applyGravity()
		if S.WeatherStart then S.WeatherStart() end -- sh_weather.lua

		if S.ModListed("extralives") then
			timer.Simple(6, function()
				if not (jcms and jcms.director and jcms.director_InsertRespawnVector) then return end
				for i, p in ipairs(player.GetAll()) do
					if p:Alive() and p:GetObserverMode() == OBS_MODE_NONE then
						jcms.director_InsertRespawnVector(p:GetPos() + Vector(0, 0, 8), 1)
						if jcms.director_RecalculateRespawnCounts then jcms.director_RecalculateRespawnCounts() end
						break
					end
				end
			end)
		end

		if S.RefreshWeaponShop then S.RefreshWeaponShop() end
		if S.GroupReapply then timer.Simple(1, S.GroupReapply) end
		S.ModSync()

		local sfNow = S.GetSubfaction and S.GetSubfaction(S.mods.subfaction)
		if sfNow then tellAll("[Sub-Faction] Fighting: " .. sfNow.name .. ". " .. sfNow.desc) end
		if #running > 0 then
			local parts = {}
			for i, id in ipairs(running) do parts[#parts + 1] = S.modById[id].name end
			tellAll("[Mission Modifiers] Active: " .. table.concat(parts, ", ") .. ".")
		end
	end

	function S.ModStop()
		if S.SubfactionRestore then S.SubfactionRestore() end
		if S.WeatherStop then S.WeatherStop() end
		if state.dark then setLight("m") end
		S.mods.inMission = false
		S.mods.weather, S.mods.weatherName = "", ""

		-- The modifier list has to be cleared BEFORE this, or applyGravity still sees Low Gravity's
		-- knob and re-applies it instead of restoring - which is how the server ended up stuck at
		-- half gravity for every class, mission after mission.
		running, state = {}, {}
		applyGravity()
		S.ModSync()
	end

	local wasInMission = false
	timer.Create("sweeper_mods", 1, 0, function()
		if not jcms then return end
		local inMission = jcms.director ~= nil and not jcms.mission_generating
		if inMission and not wasInMission then
			S.ModStart()
		elseif wasInMission and not inMission then
			S.ModStop()
		end
		wasInMission = inMission
		if not inMission then return end

		local ct = CurTime()

		-- Weather: keep the rolled weather up (sh_weather.lua), then see which gWeather entity is running
		if S.WeatherKeep then S.WeatherKeep() end
		local wEnt = S.weatherEnabled and jcms.director.weatherControl or nil
		if S.weatherEnabled and not IsValid(wEnt) then
			for i, e in ipairs(ents.FindByClass("gw_t*")) do wEnt = e break end
		end
		local wClass = IsValid(wEnt) and wEnt:GetClass() or ""
		if wClass ~= S.mods.weather then
			S.mods.weather = wClass
			S.mods.weatherName = IsValid(wEnt) and (wEnt.PrintName or wClass) or ""
			applyGravity()
			if S.GroupReapply then S.GroupReapply() end
			S.ModSync()
			local w = S.weatherEffects[wClass]
			if wClass ~= "" and S.cvar_weatherFx:GetBool() then
				tellAll(string.format("[Weather] %s: %s", S.mods.weatherName, w and w.desc or "No effect."))
			end
		end

		-- Field Medics: +1 HP/s up to half health
		if S.ModActive("medics") then
			for i, p in ipairs(player.GetAll()) do
				if p:Alive() and p:GetObserverMode() == OBS_MODE_NONE and p:Health() < p:GetMaxHealth() * S.modConfig.medicsCap then
					p:SetHealth(p:Health() + 1)
				end
			end
		end

		-- Outdoor burns (weather) + Toxic Air (standing still outdoors)
		local outDps = S.ModKnob("outdoorDps")
		local stillDps = S.ModKnob("stillOutdoorDps")
		if outDps > 0 or stillDps > 0 then
			for i, p in ipairs(player.GetAll()) do
				if p:Alive() and p:GetObserverMode() == OBS_MODE_NONE and S.IsOutdoors(p:EyePos()) then
					local dps = outDps
					if stillDps > 0 then
						if p:GetVelocity():Length2DSqr() < 30 * 30 then
							p.jcms_modStillSince = p.jcms_modStillSince or ct
							if ct - p.jcms_modStillSince >= S.modConfig.toxicStillTime then dps = dps + stillDps end
						else
							p.jcms_modStillSince = nil
						end
					end
					if dps > 0 then
						local d = DamageInfo()
						d:SetDamage(dps)
						d:SetDamageType(DMG_ACID)
						d:SetAttacker(game.GetWorld())
						d:SetInflictor(game.GetWorld())
						p:TakeDamageInfo(d)
					end
				else
					p.jcms_modStillSince = nil
				end
			end
		end
		local npcDps = S.ModKnob("npcOutdoorDps")
		if npcDps > 0 and jcms.director.npcs then
			for i, npc in ipairs(jcms.director.npcs) do
				if IsValid(npc) and npc:Health() > 0 and S.IsOutdoors(npc:EyePos()) then
					local d = DamageInfo()
					d:SetDamage(npcDps)
					d:SetDamageType(DMG_ACID)
					d:SetAttacker(game.GetWorld())
					d:SetInflictor(game.GetWorld())
					npc:TakeDamageInfo(d)
				end
			end
		end

		-- Regenerating Foes: enemies that haven't been hurt for a while heal back up
		if S.ModActive("regenfoes") and jcms.director.npcs then
			local cfg = S.modConfig
			for i, npc in ipairs(jcms.director.npcs) do
				if IsValid(npc) and npc:Health() > 0 and npc:Health() < npc:GetMaxHealth()
					and ct - (npc.jcms_modLastHurt or 0) >= cfg.regenDelay then
					npc:SetHealth(math.min(npc:GetMaxHealth(), npc:Health() + math.max(1, math.Round(npc:GetMaxHealth() * cfg.regenPerSec))))
				end
			end
		end

		-- Enemy speed
		local spd = S.ModKnob("npcSpeedMul")
		if spd ~= 1 and jcms.director.npcs then
			for i, npc in ipairs(jcms.director.npcs) do
				if IsValid(npc) and npc:IsNPC() then npc:SetPlaybackRate(spd) end
			end
		end

		-- Recon Sweep: outline enemies near the squad for the first minute
		if S.ModActive("reconsweep") and ct - state.startTime <= S.modConfig.reconSweepTime and (ct - (state.lastSweep or 0)) >= 2 then
			state.lastSweep = ct
			local found, seen = {}, {}
			for i, p in ipairs(player.GetAll()) do
				if p:Alive() and p:GetObserverMode() == OBS_MODE_NONE then
					for j, e in ipairs(ents.FindInSphere(p:GetPos(), S.modConfig.reconSweepRange)) do
						if not seen[e] and not e.sweeperDecoy and (e:IsNPC() or e:IsNextBot()) and e:Health() > 0 and jcms.team_NPC(e) then
							seen[e] = true
							found[#found + 1] = e
							if #found >= 200 then break end
						end
					end
				end
			end
			net.Start("sweeper_modspot")
				net.WriteFloat(ct + 3)
				net.WriteUInt(#found, 8)
				for i, e in ipairs(found) do net.WriteEntity(e) end
			net.Broadcast()
		end

		-- Hunted: every enemy is told where the nearest sweeper is
		if S.ModActive("hunted") and (ct - (state.lastHunt or 0)) >= 5 and jcms.director.npcs then
			state.lastHunt = ct
			local alive = {}
			for i, p in ipairs(player.GetAll()) do
				if p:Alive() and p:GetObserverMode() == OBS_MODE_NONE and jcms.team_JCorp_player(p) then alive[#alive + 1] = p end
			end
			if #alive > 0 then
				for i, npc in ipairs(jcms.director.npcs) do
					if IsValid(npc) and npc:IsNPC() and npc:Health() > 0 then
						local best, bd
						for j, p in ipairs(alive) do
							local d = p:GetPos():DistToSqr(npc:GetPos())
							if not bd or d < bd then best, bd = p, d end
						end
						if best then
							npc:UpdateEnemyMemory(best, best:GetPos())
							if not IsValid(npc:GetEnemy()) then npc:SetEnemy(best) end
						end
					end
				end
			end
		end

		-- Friendly Skies: free Precision Strike on the biggest enemy group near the squad
		if S.ModActive("skies") and ct >= state.nextSkies and jcms.spawnmenu_Airstrike and jcms.director.npcs then
			state.nextSkies = ct + S.modConfig.skiesInterval
			local bestNpc, bestCount = nil, 0
			for i, npc in ipairs(jcms.director.npcs) do
				if IsValid(npc) and npc:Health() > 0 then
					local near = false
					for j, p in ipairs(player.GetAll()) do
						if p:Alive() and p:GetPos():DistToSqr(npc:GetPos()) < 3000 ^ 2 and p:GetPos():DistToSqr(npc:GetPos()) > 350 ^ 2 then near = true break end
					end
					if near then
						local c = 0
						for j, other in ipairs(ents.FindInSphere(npc:GetPos(), 400)) do
							if not other.sweeperDecoy and (other:IsNPC() or other:IsNextBot()) and other:Health() > 0 and jcms.team_NPC(other) then c = c + 1 end
						end
						if c > bestCount then bestNpc, bestCount = npc, c end
					end
				end
			end
			if IsValid(bestNpc) then
				local pos = bestNpc:GetPos()
				local owner = jcms.director_PickClosestPlayer and jcms.director_PickClosestPlayer(pos) or nil
				if jcms.net_SendLocator then jcms.net_SendLocator("all", nil, "Friendly Skies", pos, jcms.LOCATOR_TIMED, 1.5) end
				jcms.spawnmenu_Airstrike {
					pos = pos, count = 1, arrival = 1.5, radius = 0, blast_radius = 250, blast_damage = 300,
					callback = function(bomb) if IsValid(owner) then bomb.jcms_owner = owner end end,
				}
				if jcms.util_JetSound then jcms.util_JetSound(pos) end
				tellAll(string.format("[Friendly Skies] Strike inbound on a group of %d enemies!", bestCount))
			end
		end
	end)
	-- }}}

	-- // Outdoors check (gWeather's if it's installed) {{{
	local skyUp = Vector(0, 0, 32768)
	function S.IsOutdoors(pos)
		if gWeather and gWeather.IsOutside then
			local ok, r = pcall(gWeather.IsOutside, gWeather, pos)
			if ok then return r and true or false end
		end
		local tr = util.TraceLine({ start = pos, endpos = pos + skyUp, mask = MASK_SOLID_BRUSHONLY })
		return tr.HitSky
	end
	-- }}}

	-- // Damage {{{
	local function isEnemy(ent)
		return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and jcms and jcms.team_NPC and jcms.team_NPC(ent)
	end

	local function isSweeperSide(ent)
		if not IsValid(ent) then return false end
		if ent:IsPlayer() then return true end
		return IsValid(ent.jcms_owner) and ent.jcms_owner:IsPlayer()
	end

	hook.Add("EntityTakeDamage", "sweeper_mods", function(ent, dmg)
		if not S.mods.inMission then return end
		local attacker = dmg:GetAttacker()
		local mul = 1

		if dmg:IsExplosionDamage() then mul = mul * S.ModKnob("explosiveMul") end

		if ent:IsPlayer() and isEnemy(attacker) then
			mul = mul * S.ModKnob("npcDamageMul")
		elseif isEnemy(ent) and isSweeperSide(attacker) then
			mul = mul * S.ModKnob("npcTakeMul")
			if attacker:IsPlayer() and S.ModActive("squadlink") and S.ModSquadLinked(attacker) then
				mul = mul * S.modConfig.squadLinkDamage
			end
		end
		if isEnemy(ent) then ent.jcms_modLastHurt = CurTime() end

		if mul ~= 1 then dmg:ScaleDamage(mul) end
	end)

	hook.Add("ScaleNPCDamage", "sweeper_modMarksman", function(npc, hitgroup, dmg)
		if not S.ModActive("marksman") then return end
		local attacker = dmg:GetAttacker()
		if not (IsValid(attacker) and attacker:IsPlayer()) then return end
		dmg:ScaleDamage(hitgroup == HITGROUP_HEAD and S.ModKnob("headshotMul") or S.ModKnob("bodyMul"))
	end)
	-- }}}

	-- // Enemy spawns {{{
	hook.Add("MapSweepersNPCSpawned", "sweeper_mods", function(npc, enemyType, enemyData)
		if not S.mods.inMission or not IsValid(npc) then return end

		local bounty = S.ModKnob("bountyMul")
		if bounty ~= 1 and npc.jcms_bounty then npc.jcms_bounty = math.Round(npc.jcms_bounty * bounty) end

		local hpMul = S.ModKnob("npcHealthMul")
		if hpMul ~= 1 then
			npc:SetMaxHealth(math.max(1, math.Round(npc:GetMaxHealth() * hpMul)))
			npc:SetHealth(math.max(1, math.Round(npc:Health() * hpMul)))
		end

		local look = S.ModKnob("npcLookMul")
		if look ~= 1 and npc.SetMaxLookDistance and npc.GetMaxLookDistance then
			npc:SetMaxLookDistance(math.max(400, npc:GetMaxLookDistance() * look))
		end

		local shield = S.ModKnob("npcShield")
		if shield > 0 and jcms.npc_SetupSweeperShields then
			timer.Simple(0, function()
				if IsValid(npc) and npc:GetNWInt("jcms_sweeperShield_max", 0) <= 0 then
					local col = jcms.factions_GetColorInteger and jcms.factions_GetColorInteger(enemyData and enemyData.faction) or nil
					jcms.npc_SetupSweeperShields(npc, shield, 5, 3, col)
				end
			end)
		end
	end)

	-- Enemy counts: cheaper enemies = more of them
	function S.InstallModDirector()
		if not jcms then return end
		if jcms.npc_GetScaledCost and not S.Wrapped(jcms, "ModCost") then
			local orig = jcms.npc_GetScaledCost
			S._wrappedModCost = function(data, ...)
				local c = orig(data, ...)
				if S.mods.inMission and data and data.danger ~= jcms.NPC_DANGER_BOSS and data.danger ~= jcms.NPC_DANGER_RAREBOSS then
					c = c * S.ModKnob("spawnCostMul")
				end
				return c
			end
			jcms.npc_GetScaledCost = S._wrappedModCost
			S.MarkWrapped(jcms, "ModCost")
		end
		if jcms.npc_GetScaledSwarmWeight and not S.Wrapped(jcms, "ModWeight") then
			local orig = jcms.npc_GetScaledSwarmWeight
			S._wrappedModWeight = function(data, ...)
				local w = orig(data, ...)
				if S.mods.inMission and data and data.danger == jcms.NPC_DANGER_STRONG then
					w = w * S.ModKnob("strongWeightMul")
				end
				return w
			end
			jcms.npc_GetScaledSwarmWeight = S._wrappedModWeight
			S.MarkWrapped(jcms, "ModWeight")
		end

		-- No Respawns: no beacon / respawn point is ever found
		if jcms.director_FindRespawnBeacon and not S.Wrapped(jcms, "ModRespawn") then
			local orig = jcms.director_FindRespawnBeacon
			S._wrappedModRespawn = function(...)
				if S.ModActive("norespawns") then return nil end
				return orig(...)
			end
			jcms.director_FindRespawnBeacon = S._wrappedModRespawn
			S.MarkWrapped(jcms, "ModRespawn")
		end

		-- Rapid Evac: the evac charges faster
		if jcms.mission_DropEvac and not S.Wrapped(jcms, "ModEvac") then
			local orig = jcms.mission_DropEvac
			S._wrappedModEvac = function(...)
				local evac = orig(...)
				local mul = S.ModKnob("evacMul")
				if IsValid(evac) and mul ~= 1 and evac.SetMaxCharge and evac.GetMaxCharge then
					evac:SetMaxCharge(math.max(5, math.floor(evac:GetMaxCharge() * mul)))
				end
				return evac
			end
			jcms.mission_DropEvac = S._wrappedModEvac
			S.MarkWrapped(jcms, "ModEvac")
		end

		-- Fire Sale: shop purchases refund part of their price. Also marks purchases so ammo mods skip them.
		S._wrappedModBuy = S._wrappedModBuy or {}
		for i, fname in ipairs({ "spawnmenu_PurchaseAndGiveGun", "spawnmenu_PurchaseLoadoutGun" }) do
			local current = jcms[fname]
			if current and not S.Wrapped(jcms, "ModBuy_" .. fname) then
				local wrapped = function(ply, ...)
					local before = IsValid(ply) and ply:GetNWInt("jcms_cash", 0) or 0
					S.modInPurchase = true
					local r = table.Pack(pcall(current, ply, ...))
					S.modInPurchase = false
					if not r[1] then error(r[2], 0) end
					local discount = S.ModKnob("weaponDiscount")
					if IsValid(ply) and discount > 0 and S.ModActive("firesale") then
						local spent = before - ply:GetNWInt("jcms_cash", 0)
						if spent > 0 then
							ply:SetNWInt("jcms_cash", ply:GetNWInt("jcms_cash", 0) + math.floor(spent * discount))
						end
					end
					return unpack(r, 2, r.n)
				end
				S._wrappedModBuy[fname] = wrapped
				S.MarkWrapped(jcms, "ModBuy_" .. fname)
				jcms[fname] = wrapped
			end
		end
	end
	-- }}}


	-- // Squad Link: is a living teammate close by? (cached for half a second) {{{
	function S.ModSquadLinked(ply)
		local ct = CurTime()
		if ply.jcms_modLinkCheck and ct - ply.jcms_modLinkCheck < 0.5 then return ply.jcms_modLinked end
		ply.jcms_modLinkCheck = ct
		local linked = false
		local range = S.modConfig.squadLinkRange ^ 2
		local pos = ply:GetPos()
		for i, p in ipairs(player.GetAll()) do
			if p ~= ply and p:Alive() and p:GetObserverMode() == OBS_MODE_NONE and jcms.team_JCorp_player(p)
				and p:GetPos():DistToSqr(pos) <= range then
				linked = true
				break
			end
		end
		ply.jcms_modLinked = linked
		ply:SetNWBool("sweeper_modLinked", linked)
		return linked
	end
	-- }}}

	-- // Second Wind: once per life, a killing blow leaves you on 1 HP {{{
	-- Checked in the gamemode's HandlePlayerArmorReduction, which runs after every EntityTakeDamage hook and
	-- after shields have soaked their share, so the damage left over is what would really hit your health.
	function S.InstallModSecondWind()
		local gm = GAMEMODE or GM
		if not (gm and gm.HandlePlayerArmorReduction) or S.Wrapped(gm, "ModSecondWind") then return end
		local orig = gm.HandlePlayerArmorReduction
		gm.HandlePlayerArmorReduction = function(self, ply, dmginfo, ...)
			local r = { orig(self, ply, dmginfo, ...) }
			if S.ModActive("secondwind") and IsValid(ply) and ply:IsPlayer() and not ply.jcms_modSecondWindUsed
				and ply:Alive() and dmginfo:GetDamage() >= ply:Health() then
				ply.jcms_modSecondWindUsed = true
				ply.jcms_modSecondWindUntil = CurTime() + S.modConfig.secondWindTime
				ply:SetNWFloat("sweeper_modSecondWind", ply.jcms_modSecondWindUntil)
				dmginfo:SetDamage(math.max(0, ply:Health() - 1))
				ply:EmitSound("items/suitchargeok1.wav", 75, 80)
				ply:EmitSound("player/heartbeat1.wav", 60, 100, 0.8)
				ply:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 60), 0.6, 0.1)
				ply:ChatPrint("[Second Wind] You cheated death! 3s of invulnerability.")
			end
			return unpack(r)
		end
		S.MarkWrapped(gm, "ModSecondWind")
	end

	hook.Add("EntityTakeDamage", "sweeper_modSecondWind", function(ent, dmg)
		if ent:IsPlayer() and (ent.jcms_modSecondWindUntil or 0) > CurTime() then return true end
	end)
	hook.Add("PlayerSpawn", "sweeper_modSecondWind", function(ply)
		ply.jcms_modSecondWindUsed = nil
		ply.jcms_modSecondWindUntil = nil
	end)
	-- }}}

	-- // Scrambled Comms: strikes and drops land off target {{{
	-- Only for call-ins aimed at a spot (orbital_fixed / orbital_fixed_outdoors). Turrets, mines etc. still go
	-- where you put them. The new spot is never through a wall from the aimed one.
	function S.InstallModScramble()
		if not jcms or not jcms.orders_ForceUse or S.Wrapped(jcms, "ModScramble") then return end
		local orig = jcms.orders_ForceUse
		jcms.orders_ForceUse = function(ply, orderId, a1, ...)
			local data = jcms.orders and jcms.orders[orderId]
			if S.ModActive("scrambled") and data and isvector(a1)
				and (data.argparser == "orbital_fixed" or data.argparser == "orbital_fixed_outdoors") then
				local r = S.modConfig.scrambleRadius
				local ang = math.Rand(0, math.pi * 2)
				local dist = math.Rand(r * 0.35, r)
				local target = a1 + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 0)
				local tr = util.TraceLine({ start = a1 + Vector(0, 0, 16), endpos = target + Vector(0, 0, 16), mask = MASK_SOLID_BRUSHONLY })
				if not tr.Hit then
					if data.argparser == "orbital_fixed" then
						local down = util.TraceLine({ start = target + Vector(0, 0, 64), endpos = target - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
						if down.Hit and not down.StartSolid then target = down.HitPos end
					end
					a1 = target
					if IsValid(ply) then ply:ChatPrint("[Scrambled Comms] Coordinates garbled, it's landing " .. math.Round(dist) .. " units off!") end
				end
			end
			return orig(ply, orderId, a1, ...)
		end
		S.MarkWrapped(jcms, "ModScramble")
	end
	-- }}}

	-- // Locked Terminals: a finished hack only opens the second security layer {{{
	-- Called from the terminal_Unlock wrapper in sh_group.lua. Only real hacks (intrusive), done by a player;
	-- the Auto-Hacker call-in and PIN codes still open terminals in one go.
	function S.ModTerminalLayer(ent, hacker, intrusive)
		if not S.ModActive("lockedterms") or not intrusive then return false end
		if not (IsValid(ent) and IsValid(hacker) and hacker:IsPlayer()) then return false end
		if ent.jcms_modLayer2 or not ent:GetNWBool("jcms_terminal_locked", false) then return false end
		if not (jcms.terminal_modeTypes and jcms.terminal_ToHack) then return false end

		ent.jcms_modLayer2 = true
		local weighed = {}
		for modeType, mode in pairs(jcms.terminal_modeTypes) do
			if mode.weight and modeType ~= ent.jcms_hackType then weighed[modeType] = mode.weight end
		end
		if next(weighed) and jcms.util_ChooseByWeight then
			ent.jcms_hackType = jcms.util_ChooseByWeight(weighed) or ent.jcms_hackType
		end
		ent:EmitSound("buttons/combine_button_locked.wav", 75, 90)
		hacker:ChatPrint("[Locked Terminals] Second security layer! Hack it again.")
		timer.Simple(0.5, function()
			if IsValid(ent) and ent:GetNWBool("jcms_terminal_locked", false) then jcms.terminal_ToHack(ent) end
		end)
		return true
	end
	-- }}}

	-- // Ammo Drought: ammo dropped by dying enemies is removed {{{
	local recentDeaths = {}
	local ammoDrops = { item_box_buckshot = true, item_rpg_round = true, item_ammo_ar2_altfire = true }
	hook.Add("MapSweepersDeathNPC", "sweeper_modDrought", function(npc)
		if not (S.ModActive("drought") and IsValid(npc)) then return end
		recentDeaths[#recentDeaths + 1] = { pos = npc:WorldSpaceCenter(), t = CurTime() }
		if #recentDeaths > 64 then table.remove(recentDeaths, 1) end
	end)
	hook.Add("OnEntityCreated", "sweeper_modDrought", function(ent)
		if not S.ModActive("drought") then return end
		timer.Simple(0, function()
			if not IsValid(ent) then return end
			local cls = ent:GetClass()
			if not (ammoDrops[cls] or string.StartWith(cls, "item_ammo_")) or cls == "item_ammo_crate" then return end
			local pos, ct = ent:GetPos(), CurTime()
			for i = #recentDeaths, 1, -1 do
				local d = recentDeaths[i]
				if ct - d.t > 1.5 then break end
				if d.pos:DistToSqr(pos) < 200 * 200 then ent:Remove() return end
			end
		end)
	end)
	-- }}}

	-- // Intel Leak: every objective / terminal tag counts as already seen {{{
	function S.InstallModIntel()
		if not jcms or not jcms.director_TagIsVisible or S.Wrapped(jcms, "ModIntel") then return end
		local orig = jcms.director_TagIsVisible
		jcms.director_TagIsVisible = function(key, tagData, ply, ...)
			if S.ModActive("intelleak") then return true end
			return orig(key, tagData, ply, ...)
		end
		S.MarkWrapped(jcms, "ModIntel")
	end
	-- }}}

	-- // Hazard Pay: cash when an objective turns completed {{{
	-- The gamemode sends the objective list whenever it changes; we watch that list. Each objective pays once,
	-- and only if we saw it unfinished first (so objectives that start out "done" never pay).
	S.modObjSeen = S.modObjSeen or {}
	function S.InstallModHazardPay()
		if not jcms or not jcms.net_ShareMissionData or S.Wrapped(jcms, "ModHazard") then return end
		local orig = jcms.net_ShareMissionData
		jcms.net_ShareMissionData = function(objectives, ply, ...)
			if ply == nil and S.ModActive("hazardpay") and istable(objectives) then
				pcall(function()
					local counts = {}
					for i, obj in ipairs(objectives) do
						local t = tostring(obj.type)
						counts[t] = (counts[t] or 0) + 1
						local key = t .. "#" .. counts[t]
						local seen = S.modObjSeen[key]
						if not obj.completed then
							if seen == nil then S.modObjSeen[key] = "open" end
						elseif seen == "open" then
							S.modObjSeen[key] = "paid"
							local cash = S.modConfig.hazardPayCash
							for j, p in ipairs(team.GetPlayers(1)) do
								if jcms.giveCash then jcms.giveCash(p, cash) else p:SetNWInt("jcms_cash", p:GetNWInt("jcms_cash", 0) + cash) end
							end
							tellAll("[Hazard Pay] Objective complete: +" .. cash .. " cash for every sweeper.")
						elseif seen == nil then
							S.modObjSeen[key] = "done"
						end
					end
				end)
			end
			return orig(objectives, ply, ...)
		end
		S.MarkWrapped(jcms, "ModHazard")
	end
	-- }}}

	-- // Kills: Adrenaline, Scavenger, Volatile {{{
	hook.Add("MapSweepersDeathNPC", "sweeper_mods", function(npc, attacker, inflictor, isPlayer)
		if not S.mods.inMission or isPlayer or not IsValid(npc) then return end
		local pos = npc:WorldSpaceCenter()

		if S.ModActive("adrenaline") and IsValid(attacker) and attacker:IsPlayer() then
			attacker:SetNWFloat("sweeper_modAdren", CurTime() + S.modConfig.adrenalineTime)
		end

		if S.ModActive("scavenger") and math.random() < S.modConfig.scavengerChance then
			local item = ents.Create(math.random() < 0.5 and "item_healthvial" or "item_battery")
			if IsValid(item) then
				item:SetPos(pos)
				item:Spawn()
				timer.Simple(30, function() if IsValid(item) then item:Remove() end end)
			end
		end

		if S.ModActive("volatile") then
			local ed = EffectData()
			ed:SetOrigin(pos)
			util.Effect("ManhackSparks", ed, true, true)
			sound.Play("weapons/grenade/tick1.wav", pos, 75, 130)
			timer.Simple(0.9, function()
				local e = EffectData()
				e:SetOrigin(pos)
				util.Effect("Explosion", e, true, true)
				util.BlastDamage(game.GetWorld(), game.GetWorld(), pos, S.modConfig.volatileRadius, S.modConfig.volatileDamage)
			end)
		end
	end)
	-- }}}

	-- // Ammo: Stockpile / Low Supply (pickups, crates, refills - not shop purchases) {{{
	hook.Add("PlayerAmmoChanged", "sweeper_mods", function(ply, ammoID, old, new)
		if not S.mods.inMission or S.modInPurchase or new <= old then return end
		local mul = S.ModKnob("ammoMul")
		if mul == 1 then return end
		ply.jcms_modAmmoGuard = ply.jcms_modAmmoGuard or {}
		if ply.jcms_modAmmoGuard[ammoID] == new then
			ply.jcms_modAmmoGuard[ammoID] = nil
			return
		end
		local target = math.max(old, old + math.floor((new - old) * mul))
		if target ~= new then
			ply.jcms_modAmmoGuard[ammoID] = target
			ply:SetAmmo(target, ammoID)
		end
	end)
	-- }}}

	-- // Victory: bonus V Tokens for the modifiers that were on {{{
	function S.InstallModMissionEnd()
		if not (jcms and jcms.mission_End) or S.Wrapped(jcms, "ModEnd") then return end
		local orig = jcms.mission_End
		S._wrappedModEnd = function(victory, ...)
			local list = table.Copy(running)
			local resetsBefore = S.resetCount
			local survivors = 0
			for i, p in ipairs(team.GetPlayers(1)) do
				local evacuated = jcms.director and jcms.director.evacuated and jcms.director.evacuated[p]
				if evacuated or (p:Alive() and p:GetObserverMode() == OBS_MODE_NONE) then survivors = survivors + 1 end
			end
			local r = { orig(victory, ...) }

			-- The mission is over, so any gravity a modifier set goes back now rather than waiting
			-- for the next ModStart (which used to lose the original value entirely)
			local okGrav, errGrav = pcall(S.ModRestoreGravity)
			if not okGrav then ErrorNoHalt("[sweeper] gravity restore: " .. tostring(errGrav) .. "\n") end

			local ok, err = pcall(function()
				if not victory or S.resetCount ~= resetsBefore or #list == 0 or not S.AddPoolTokens then return end
				local bonus = 0
				for i, id in ipairs(list) do
					local m = S.modById[id]
					if m then
						bonus = bonus + (m.reward or 0)
						if m.doubleVictory and tokenVictoryCvar then bonus = bonus + tokenVictoryCvar:GetInt() end
						if id == "extraction" then bonus = bonus + survivors * S.modConfig.extractionPerSweeper end
					end
				end
				if bonus > 0 then
					S.AddPoolTokens(bonus, "Mission modifier bonus")
					tellAll(string.format("[Mission Modifiers] Bonus for the modifiers: +%d %s.", bonus, S.tokenNamePlural or "V Tokens"))
				end
			end)
			if not ok then ErrorNoHalt("[sweeper] modifier reward error: " .. tostring(err) .. "\n") end
			return unpack(r)
		end
		jcms.mission_End = S._wrappedModEnd
		S.MarkWrapped(jcms, "ModEnd")
	end
	-- }}}

	-- Lucky Hacks (read by the terminal V Token roll in sh_group.lua)
	function S.TerminalTokenChance()
		if S.ModActive("luckyhacks") then return 1 end
		return S.cvar_tokensTerminalChance and S.cvar_tokensTerminalChance:GetFloat() or 0.35
	end

	-- // Install + admin commands {{{
	local function install()
		S.InstallModRandomize()
		S.InstallModDirector()
		S.InstallModMissionEnd()
		S.InstallModWeaponLoan()
		S.InstallModSecondWind()
		S.InstallModScramble()
		S.InstallModIntel()
		S.InstallModHazardPay()
	end
	hook.Add("Initialize", "sweeper_mods", install)
	hook.Add("InitPostEntity", "sweeper_mods", function()
		install()
		timer.Simple(3, function()
			if jcms and not jcms.director and #(S.mods.list or {}) == 0 and not S._modsRolledOnce then
				S._modsRolledOnce = true
				S.RollModifiers()
			end
		end)
	end)
	install()

	local function isAdmin(ply) return not IsValid(ply) or ply:IsAdmin() end

	concommand.Add("jcms_mods_reroll", function(ply)
		if not isAdmin(ply) then return end
		if jcms and jcms.director then print("[Mission Modifiers] Only in the lobby.") return end
		S.RollModifiers()
	end)

	concommand.Add("jcms_mods_set", function(ply, cmd, args)
		if not isAdmin(ply) then return end
		if jcms and jcms.director then print("[Mission Modifiers] Only in the lobby.") return end
		local list = {}
		for i, id in ipairs(args) do
			if S.modById[id] then list[#list + 1] = id else print("[Mission Modifiers] unknown id: " .. id) end
		end
		S.mods.list = list
		pickLoan()
		if S.RefreshWeaponShop then S.RefreshWeaponShop() end
		S.ModSync()
	end, function(cmd, args)
		local out = {}
		for i, m in ipairs(S.modifiers) do out[#out + 1] = cmd .. " " .. m.id end
		return out
	end)

	concommand.Add("jcms_mods_list", function(ply)
		local lines = {}
		for i, m in ipairs(S.modifiers) do
			lines[#lines + 1] = string.format("%-16s %s  %s - %s", m.id, S.modKindLabel[m.kind], m.name, m.desc)
		end
		local msg = table.concat(lines, "\n")
		S.PrintConsole(ply, msg)
	end)
	-- }}}
end

-- ============================================================================================
if CLIENT then
	local cvar_modhud = CreateClientConVar("jcms_modhud", "1", true, false, "Show mission modifiers + weather on the HUD.")

	net.Receive("sweeper_mods", function()
		local t = net.ReadTable()
		S.mods = { list = t.list or {}, inMission = t.inMission and true or false, weather = t.weather or "",
			weatherName = t.weatherName or "", loan = t.loan or "", subfaction = t.subfaction or "",
			plannedWeather = t.plannedWeather or "" }
		S.clVersion = (S.clVersion or 0) + 1 -- refresh cached stat totals (call-in prices etc.)
	end)

	net.Receive("sweeper_modspot", function()
		local untilTime = net.ReadFloat()
		S.spotted = S.spotted or {}
		for i = 1, net.ReadUInt(8) do
			local e = net.ReadEntity()
			if IsValid(e) then S.spotted[e] = math.max(S.spotted[e] or 0, untilTime) end
		end
	end)

	net.Receive("sweeper_modlight", function()
		timer.Simple(0.2, function() render.RedownloadAllLightmaps(true) end)
	end)

	-- Dense Fog
	local fogData = { fogCol = Color(150, 155, 160), fogStart = 80, fogEnd = 1100, fogMaxDensity = 0.97 }
	hook.Add("RenderScene", "sweeper_modFog", function()
		if jcms and jcms.fogStack_push and S.ModKnob("fog") then
			jcms.fogStack_push(fogData)
		end
	end)

	-- Broken HUD: no locators, compass flickers
	function S.InstallModHud()
		if not jcms then return end
		if jcms.draw_Locators and not S.Wrapped(jcms, "ModLocators") then
			local orig = jcms.draw_Locators
			S._wrappedModLocators = function(...)
				if S.ModKnob("brokenHud") then return end
				return orig(...)
			end
			jcms.draw_Locators = S._wrappedModLocators
			S.MarkWrapped(jcms, "ModLocators")
		end
		if jcms.draw_Compass and not S.Wrapped(jcms, "ModCompass") then
			local orig = jcms.draw_Compass
			S._wrappedModCompass = function(...)
				if S.ModKnob("brokenHud") and (CurTime() * 1.7) % 3 < 1.2 then return end
				return orig(...)
			end
			jcms.draw_Compass = S._wrappedModCompass
			S.MarkWrapped(jcms, "ModCompass")
		end
	end
	hook.Add("Initialize", "sweeper_modHud", S.InstallModHud)
	hook.Add("InitPostEntity", "sweeper_modHud", S.InstallModHud)
	S.InstallModHud()

	-- HUD: a compact line above the compass (the gamemode's top HUD panel)
	if S.AddHud then
		S.AddHud("modifiers", "top", function(ply, alpha)
			if not cvar_modhud:GetBool() then return end
			local items = {}
			local sf, sfFaction = S.GetSubfaction and S.GetSubfaction(S.mods.subfaction)
			if sf then
				local fc = jcms.factions_GetColor and jcms.factions_GetColor(sfFaction) or jcms.color_bright
				items[#items + 1] = { text = string.upper(sf.name), col = fc }
			end
			for i, id in ipairs(S.mods.list or {}) do
				local m = S.modById[id]
				if m then items[#items + 1] = { text = string.upper(m.name), col = S.modKindColors[m.kind]() } end
			end
			if (S.mods.weatherName or "") ~= "" and S.mods.weather ~= "" then
				items[#items + 1] = { text = "WEATHER: " .. string.upper(S.mods.weatherName), col = jcms.color_bright_alt }
			end
			if #items == 0 then return end

			surface.SetFont("jcms_hud_small")
			local gap = 48
			local total = 0
			for i, it in ipairs(items) do
				it.w = surface.GetTextSize(it.text)
				total = total + it.w + (i > 1 and gap or 0)
			end
			local x = -total / 2
			surface.SetAlphaMultiplier(alpha * 0.85)
			for i, it in ipairs(items) do
				S.HudGlowText(it.text, "jcms_hud_small", x, -34, it.col, jcms.color_dark, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 5)
				x = x + it.w + gap
			end
			surface.SetAlphaMultiplier(alpha)
		end)
	end

	-- // Mission tag row: modifier chips + tooltips at the bottom {{{
	-- The gamemode draws its tag tooltips to the LEFT of the tags, on top of the mission description,
	-- which is hard to read. While its lobby paint runs we hide the cursor from it so it draws no
	-- tooltip at all, then we draw the hover outline and one tooltip UNDER the tag row instead -
	-- for the gamemode's own tags and for our modifier chips.
	local function tagRow(p, w, h)
		if jcms.director then return end -- lobby only
		local missionType = jcms.util_GetMissionType and jcms.util_GetMissionType() or ""
		local missionData = jcms.missions and jcms.missions[missionType]
		if not missionData or missionType == "" then return end

		-- same geometry the gamemode uses for the mission name, description and tag row
		local lowres = jcms.util_IsLowRes()
		local smallscreen = ScrW() <= 1500
		local font = smallscreen and "jcms_hud_small" or "jcms_hud_medium"
		local base = missionData.basename or missionType
		local name = (jcms.util_IsPVP() and "PVP " or "") .. language.GetPhrase("#jcms." .. base)
		local desc = language.GetPhrase("#jcms." .. base .. "_desc")
		surface.SetFont(font)
		local tw, th = surface.GetTextSize(name)
		tw = math.max(tw, 210)
		local colTag = ("<color=%d,%d,%d>"):format(jcms.color_bright:Unpack())
		local mup = markup.Parse(colTag .. "<font=jcms_small>\"" .. desc .. "\"</font></color>",
			math.max(lowres and 300 or 520, tw + 48))
		local tagSize = lowres and 16 or 32
		local tagy = 100 + th + mup:GetHeight() + 56

		local mx, my = input.GetCursorPos()
		local hoverTitle, hoverDesc, hoverCol

		local function hitTest(x)
			return mx >= x and my >= tagy and mx < x + tagSize and my < tagy + tagSize
		end

		-- the gamemode's own tags: it already drew the icons, we add the hover outline
		local used = 0
		if istable(missionData.tags) then
			for i, tag in ipairs(missionData.tags) do
				used = used + 1
				local tagx = w - 48 - (tagSize + 4) * i
				if hitTest(tagx) then
					hoverCol = jcms.mission_GetTagColor(tag)
					hoverTitle = language.GetPhrase("jcms.missiontag_" .. tag)
					hoverDesc = language.GetPhrase("jcms.missiontag_" .. tag .. "_desc")
					surface.SetDrawColor(hoverCol)
					jcms.hud_DrawHollowPolyButton(tagx - 3, tagy - 3, tagSize + 6, tagSize + 6, 6)
				end
			end
		end
		if jcms.missions_official and not jcms.missions_official[missionType] then
			used = used + 1
			local tagx = w - 48 - (tagSize + 4) * used
			if hitTest(tagx) then
				hoverCol = jcms.color_bright_alt
				hoverTitle = language.GetPhrase("jcms.missiontag_unofficial")
				hoverDesc = language.GetPhrase("jcms.missiontag_unofficial_desc")
				surface.SetDrawColor(hoverCol)
				surface.DrawCircle(tagx + tagSize / 2, tagy + tagSize / 2, tagSize / 2)
			end
		end

		-- our modifier chips, continuing the same row
		local mods = (S.mods and S.mods.list) or {}
		for i, id in ipairs(mods) do
			local m = S.modById and S.modById[id]
			if m then
				local x = w - 48 - (tagSize + 4) * (used + i)
				local col = S.modKindColors[m.kind]()
				surface.SetDrawColor(col)
				if hitTest(x) then
					hoverCol = col
					hoverTitle = string.upper(m.name)
					hoverDesc = m.desc
					if m.reward and m.reward > 0 then
						hoverDesc = hoverDesc .. "  (+" .. m.reward .. " " .. S.tokenNamePlural .. " on victory)"
					end
					if m.doubleVictory then hoverDesc = hoverDesc .. "  (double victory " .. S.tokenNamePlural .. ")" end
					jcms.hud_DrawHollowPolyButton(x - 3, tagy - 3, tagSize + 6, tagSize + 6, 6)
				end
				jcms.hud_DrawFilledPolyButton(x, tagy, tagSize, tagSize, 4)
				draw.SimpleText(S.modKindLabel[m.kind], lowres and "jcms_small_bolder" or "jcms_big",
					x + tagSize / 2, tagy + tagSize / 2 - 1, jcms.color_dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end

		-- one tooltip, under the row, where there is nothing to read over
		if hoverTitle then
			local tfont = lowres and "jcms_small_bolder" or "jcms_medium"
			surface.SetFont(tfont)
			local tw2, th2 = surface.GetTextSize(hoverTitle)
			tw2 = tw2 + 32
			local ty = tagy + tagSize + (lowres and 6 or 10)
			surface.SetDrawColor(hoverCol)
			jcms.hud_DrawNoiseRect(w - 48 - tw2, ty, tw2, th2)
			surface.DrawRect(w - 48, ty, 2, th2)
			surface.DrawRect(w - 48 - tw2 - 2, ty, 2, th2)
			draw.SimpleText(hoverTitle, tfont, w - 48 - tw2 / 2, ty + th2 / 2, hoverCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			-- description, wrapped so long ones stay inside the panel
			local dfont = lowres and "DefaultSmall" or "jcms_small"
			local dcol = ColorAlpha(hoverCol, 160)
			local dmup = markup.Parse(("<color=%d,%d,%d,%d>"):format(dcol.r, dcol.g, dcol.b, dcol.a) ..
				"<font=" .. dfont .. ">" .. tostring(hoverDesc or "") .. "</font></color>", lowres and 320 or 520)
			dmup:Draw(w - 48, ty + th2 + 4, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 255, TEXT_ALIGN_RIGHT)
		end
	end

	function S.InstallModLobbyIcons()
		if not (jcms and jcms.offgame_paint_LobbyFrame) or S.Wrapped(jcms, "LobbyPaint") then return end
		local orig = jcms.offgame_paint_LobbyFrame
		S._wrappedLobbyPaint = function(p, w, h, ...)
			-- hide the cursor from the gamemode's own tag hover so its left-side tooltip never draws
			local realGetCursorPos = input.GetCursorPos
			input.GetCursorPos = function() return -10000, -10000 end
			local ok, r = pcall(orig, p, w, h, ...)
			input.GetCursorPos = realGetCursorPos
			if not ok then error(r, 0) end

			local ok2, err = pcall(tagRow, p, w, h)
			if not ok2 and (S._chipErrAt or 0) < CurTime() then
				S._chipErrAt = CurTime() + 10
				ErrorNoHalt("[sweeper] mission tags: " .. tostring(err) .. "\n")
			end
			return r
		end
		jcms.offgame_paint_LobbyFrame = S._wrappedLobbyPaint
		S.MarkWrapped(jcms, "LobbyPaint")
	end
	hook.Add("Initialize", "sweeper_modLobbyIcons", S.InstallModLobbyIcons)
	hook.Add("InitPostEntity", "sweeper_modLobbyIcons", S.InstallModLobbyIcons)
	S.InstallModLobbyIcons()
	-- }}}
end
