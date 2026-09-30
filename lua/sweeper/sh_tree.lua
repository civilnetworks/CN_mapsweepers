--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Shared: configuration, skill trees, and helper functions.

	HOW TO EDIT SKILLS
	Each class has 15-16 class skills (tiers 1-5) plus 3 upgrades for each of its 6 specializations.
	A skill looks like:
		{ id = "r_hp", name = "Lightweight Plating", tier = 1, max = 3,
		  col = 2,                       -- column in the menu (1-4, halves like 2.5 allowed); put a skill
		                                 --   under the skill it requires so the tree reads top-down
		  req = { "other_id" },          -- optional: every listed skill needs at least 1 rank
		  stats = { hp = 8 },            -- bonus PER RANK
		  desc = "+8 max health per rank." }

	Stat keys you can use in `stats`:
		hp          flat max health
		armor       flat max shield
		dmg         damage dealt           (0.05 = +5%)
		speed       walk/run speed         (0.04 = +4%)
		jump        flat jump power
		resist      all damage taken       (0.04 = -4%)
		blast       explosive damage taken (0.15 = -15%)
		fire        fire damage taken      (0.20 = -20%)
		regen       shield regen speed     (0.12 = +12%)
		delay       shield regen delay     (0.10 = -10%)
		killHeal    health restored per kill
		killShield  shield restored per kill
		killCash    extra J Corp cash per kill
		xp          XP gained              (0.10 = +10%)
		deploy      damage dealt by your turrets / deployables (0.08 = +8%)
		deployHp    health of your turrets / deployables (0.15 = +15%)
		airDmg      damage dealt while in the air        (0.06 = +6%)
		lowHpDmg    damage dealt while below half health (0.10 = +10%)
		sprintResist damage taken while running fast     (0.08 = -8%)
		closeResist damage taken from enemies within 400 units (0.08 = -8%)
		killCdr     seconds taken off your ability cooldowns per kill
		ammoDrop    chance per kill to drop an ammo box any sweeper can grab (0.12 = 12%)

	SPECIALIZATION UPGRADES (skills with `spec = "<spec id>"`)
	- Only buyable while that specialization is picked, and only count while it's picked. Changing a spec
	  refunds the Chipsets spent on the old one's upgrades.
	- `slot` 1-3 = their position in the spec's row (left to right). They show under the class tree.
	- Extra keys only upgrades use:
		cdr_<spec id>   that spec's ability cooldown (0.10 = 10% shorter, capped at 60%)
		t_<config key>  added to a tuning value in S.recon / S.infantry / S.engineer / S.sentinel for
		                this player only (the code reads it through S.Tune(ply, key, base))
--]]

sweeper = sweeper or {}
local S = sweeper

-- Wrapper guard. Several of our files wrap the same gamemode function (the options tab, mission_End,
-- the shop buy functions...). Checking "is the current function my wrapper?" isn't enough: once another
-- file wraps on top, the check fails and we wrap again, so everything runs twice. Instead each install
-- leaves a marker on the table that owns the function and only ever wraps once.
function S.Wrapped(owner, id)
	return istable(owner) and owner["sweeper_wrapped_" .. id] == true
end
function S.MarkWrapped(owner, id)
	if istable(owner) then owner["sweeper_wrapped_" .. id] = true end
end

-- Stops the same options category being added to one options list twice.
-- Where our options categories sit in the client settings list. The gamemode adds Preferences,
-- Customize HUD and Crosshair (in that order) before any of ours, and DCategoryList items are
-- docked, so ZPos decides the order. Two addons wrap the options tab, so which of ours is added
-- first isn't fixed - explicit ZPos is the only way to get a stable layout.
S.optionsCatZ = {
	thirdperson = 150,   -- right under the gamemode's Preferences
	implants    = 400,
	outfits     = 500,
	music       = 600,   -- last
}

function S.PlaceOptionsCategory(catList, bar, zpos)
	if not (IsValid(catList) and IsValid(bar)) then return end

	local canvas = catList.GetCanvas and catList:GetCanvas() or catList
	if not IsValid(canvas) then return end

	-- Pin the gamemode's own categories once, in the order it added them, so ours can be slotted
	-- between them. Only untagged panels: anything of ours already placed keeps its own ZPos.
	if not catList.sweeperOrdered then
		catList.sweeperOrdered = true
		local n = 0
		for i, child in ipairs(canvas:GetChildren()) do
			if child ~= bar and not child.sweeperCat then
				n = n + 1
				child:SetZPos(n * 100)
			end
		end
	end

	bar.sweeperCat = true
	bar:SetZPos(zpos or 900)
end

function S.ClaimOptionsCategory(catList, name)
	if not IsValid(catList) then return false end
	catList.sweeperCats = catList.sweeperCats or {}
	if catList.sweeperCats[name] then return false end
	catList.sweeperCats[name] = true
	return true
end

S.pointName = "Chipset"
S.pointNamePlural = "Chipsets"

S.maxLevel = 30          -- 1 Chipset per level-up => 29 Chipsets at max level
S.classes = { "recon", "infantry", "sentinel", "engineer" }
S.classNames = { recon = "Recon", infantry = "Infantry", sentinel = "Sentinel", engineer = "Engineer" }

-- XP needed to go from `level` to `level + 1`.
-- T1 at level 5 = 1,400 XP, T2 at 12 = 7,700 XP, T3 at 20 = 20,900 XP, max level 30 = 46,400 XP.
-- For quicker/slower leveling without editing this, use the server convar jcms_implant_xpmul.
function S.XPToNext(level)
	return 200 + 100 * (level - 1)
end

function S.ChipsetsEarned(level)
	return math.max(0, (level or 1) - 1)
end

-- // Skill trees {{{
S.tree = {
	recon = {
		{ id = "r_hp",          name = "Lightweight Plating", tier = 1, col = 1, max = 3, stats = { hp = 8 },            desc = "+8 max health per rank." },
		{ id = "r_speed",       name = "Adrenal Boost",       tier = 1, col = 2, max = 3, stats = { speed = 0.04 },      desc = "+4% movement speed per rank." },
		{ id = "r_dmg",         name = "Marksman Training",   tier = 1, col = 3.5, max = 3, stats = { dmg = 0.05 },        desc = "+5% damage per rank." },
		{ id = "r_jump",        name = "Afterburners",        tier = 2, col = 2, max = 2, stats = { jump = 30 },         desc = "+30 jump power per rank.",                      req = { "r_speed" } },
		{ id = "r_delay",       name = "Quick Recharge",      tier = 2, col = 1, max = 3, stats = { delay = 0.10 },      desc = "Shield starts recharging 10% sooner per rank.",  req = { "r_hp" } },
		{ id = "r_killheal",    name = "Combat Stims",        tier = 2, col = 3, max = 2, stats = { killHeal = 3 },      desc = "Kills restore 3 health per rank.",               req = { "r_dmg" } },
		{ id = "r_cash",        name = "Bounty Hunter",       tier = 2, col = 4, max = 2, stats = { killCash = 3 },      desc = "+3 J Corp cash per kill per rank.",              req = { "r_dmg" } },
		{ id = "r_killshield",  name = "Reactive Shielding",  tier = 3, col = 1, max = 2, stats = { killShield = 5 },    desc = "Kills restore 5 shield per rank.",               req = { "r_delay" } },
		{ id = "r_xp",          name = "Field Analyst",       tier = 3, col = 4, max = 2, stats = { xp = 0.10 },         desc = "+10% XP per rank.",                              req = { "r_cash" } },
		{ id = "r_apex",        name = "Apex Predator",       tier = 4, col = 1.5, max = 1, stats = { dmg = 0.15, speed = 0.10 }, desc = "+15% damage and +10% movement speed.",   req = { "r_killshield", "r_jump" } },
		{ id = "r_air",         name = "Aerial Ace",          tier = 3, col = 2, max = 3, stats = { airDmg = 0.06 },     desc = "+6% damage while in the air per rank.",          req = { "r_jump" } },
		{ id = "r_evasive",     name = "Evasive Maneuvers",   tier = 3, col = 3, max = 2, stats = { sprintResist = 0.08 }, desc = "-8% damage taken while running per rank.",     req = { "r_killheal" } },
		{ id = "r_headhunter",  name = "Headhunter",          tier = 4, col = 3.5, max = 2, stats = { headshot = 0.10 },  desc = "+10% headshot damage per rank.",                 req = { "r_xp" } },
		{ id = "r_reflex",      name = "Combat Reflexes",     tier = 5, col = 1.5, max = 2, stats = { killCdr = 1 },       desc = "Kills take 1s off your ability cooldowns per rank.", req = { "r_apex" } },
		{ id = "r_ghost",       name = "Ghost Protocol",      tier = 5, col = 3.5, max = 1, stats = { speed = 0.08, airDmg = 0.10, sprintResist = 0.10 }, desc = "+8% speed, +10% air damage, -10% damage taken while running.", req = { "r_headhunter" } },
	},

	infantry = {
		{ id = "i_hp",          name = "Combat Conditioning", tier = 1, col = 1, max = 3, stats = { hp = 10 },           desc = "+10 max health per rank." },
		{ id = "i_armor",       name = "Reinforced Plates",   tier = 1, col = 2.5, max = 3, stats = { armor = 10 },        desc = "+10 max shield per rank." },
		{ id = "i_dmg",         name = "Weapon Drills",       tier = 1, col = 4, max = 3, stats = { dmg = 0.04 },        desc = "+4% damage per rank." },
		{ id = "i_resist",      name = "Hardened",            tier = 2, col = 1, max = 3, stats = { resist = 0.04 },     desc = "-4% damage taken per rank.",                     req = { "i_hp" } },
		{ id = "i_regen",       name = "Capacitor Tuning",    tier = 2, col = 2, max = 2, stats = { regen = 0.12 },      desc = "+12% shield regen speed per rank.",              req = { "i_armor" } },
		{ id = "i_blast",       name = "Blast Padding",       tier = 2, col = 3, max = 2, stats = { blast = 0.15 },      desc = "-15% explosive damage taken per rank.",          req = { "i_armor" } },
		{ id = "i_killheal",    name = "Battle Rhythm",       tier = 2, col = 4, max = 2, stats = { killHeal = 4 },      desc = "Kills restore 4 health per rank.",               req = { "i_dmg" } },
		{ id = "i_cash",        name = "War Profiteer",       tier = 3, col = 4, max = 2, stats = { killCash = 3 },      desc = "+3 J Corp cash per kill per rank.",              req = { "i_killheal" } },
		{ id = "i_killshield",  name = "Second Wind",         tier = 3, col = 2, max = 2, stats = { killShield = 6 },    desc = "Kills restore 6 shield per rank.",               req = { "i_regen" } },
		{ id = "i_veteran",     name = "Frontline Veteran",   tier = 4, col = 1.5, max = 1, stats = { dmg = 0.10, resist = 0.10 }, desc = "+10% damage and -10% damage taken.",  req = { "i_resist", "i_killshield" } },
		{ id = "i_laststand",   name = "Last Stand",          tier = 3, col = 1, max = 2, stats = { lowHpDmg = 0.10 },   desc = "+10% damage while below half health per rank.",  req = { "i_resist" } },
		{ id = "i_demo",        name = "Demolitions",         tier = 3, col = 3, max = 2, stats = { blastDmg = 0.10 },   desc = "+10% explosive damage dealt per rank.",          req = { "i_blast" } },
		{ id = "i_marksman",    name = "Designated Marksman", tier = 4, col = 3.5, max = 2, stats = { rangeDmg = 0.08, headshot = 0.05 }, desc = "+8% long-range and +5% headshot damage per rank.", req = { "i_cash" } },
		{ id = "i_scavenger",   name = "Scavenger",           tier = 4, col = 2.5, max = 3, stats = { ammoDrop = 0.12 },  desc = "Kills have a 12% chance per rank to drop an ammo box.", req = { "i_killshield" } },
		{ id = "i_tactician",   name = "Tactician",           tier = 5, col = 1.5, max = 2, stats = { killCdr = 1 },       desc = "Kills take 1s off your ability cooldowns per rank.", req = { "i_veteran" } },
		{ id = "i_warmachine",  name = "War Machine",         tier = 5, col = 3.5, max = 1, stats = { dmg = 0.08, lowHpDmg = 0.10, armor = 20 }, desc = "+8% damage, +10% more below half health, +20 max shield.", req = { "i_marksman" } },
	},

	sentinel = {
		{ id = "s_armor",       name = "Heavy Plating",       tier = 1, col = 1.5, max = 3, stats = { armor = 15 },        desc = "+15 max shield per rank." },
		{ id = "s_hp",          name = "Iron Constitution",   tier = 1, col = 3, max = 3, stats = { hp = 10 },           desc = "+10 max health per rank." },
		{ id = "s_speed",       name = "Servo Boost",         tier = 1, col = 4, max = 2, stats = { speed = 0.04 },      desc = "+4% movement speed per rank." },
		{ id = "s_resist",      name = "Bulwark",             tier = 2, col = 3, max = 3, stats = { resist = 0.04 },     desc = "-4% damage taken per rank.",                     req = { "s_hp" } },
		{ id = "s_delay",       name = "Rapid Reboot",        tier = 2, col = 1, max = 3, stats = { delay = 0.10 },      desc = "Shield starts recharging 10% sooner per rank.",  req = { "s_armor" } },
		{ id = "s_blast",       name = "Blast Shield",        tier = 2, col = 2, max = 2, stats = { blast = 0.15 },      desc = "-15% explosive damage taken per rank.",          req = { "s_armor" } },
		{ id = "s_fire",        name = "Heat Sink",           tier = 2, col = 4, max = 2, stats = { fire = 0.20 },       desc = "-20% fire damage taken per rank.",               req = { "s_speed" } },
		{ id = "s_killshield",  name = "Absorption",          tier = 3, col = 1, max = 2, stats = { killShield = 8 },    desc = "Kills restore 8 shield per rank.",               req = { "s_delay" } },
		{ id = "s_dmg",         name = "Suppressor",          tier = 3, col = 3, max = 2, stats = { dmg = 0.05 },        desc = "+5% damage per rank.",                           req = { "s_resist" } },
		{ id = "s_unbreakable", name = "Unbreakable",         tier = 4, col = 2, max = 1, stats = { armor = 50, resist = 0.10 }, desc = "+50 max shield and -10% damage taken.", req = { "s_killshield", "s_dmg" } },
		{ id = "s_frontline",   name = "Frontliner",          tier = 3, col = 4, max = 2, stats = { closeResist = 0.08 }, desc = "-8% damage taken from enemies up close per rank.", req = { "s_fire" } },
		{ id = "s_capacitor",   name = "Barrier Capacitors",  tier = 3, col = 2, max = 2, stats = { barrierLength = 1 },  desc = "+1s barrier duration per rank.",                 req = { "s_blast" } },
		{ id = "s_bruiser",     name = "Bruiser",             tier = 4, col = 3.5, max = 2, stats = { meleeDmg = 0.12, meleeKillHeal = 3 }, desc = "+12% melee damage and +3 HP per melee kill per rank.", req = { "s_frontline" } },
		{ id = "s_rebuke",      name = "Rebuke",              tier = 5, col = 1.5, max = 2, stats = { killCdr = 1 },       desc = "Kills take 1s off your ability cooldowns per rank.", req = { "s_unbreakable" } },
		{ id = "s_colossus",    name = "Colossus",            tier = 5, col = 3.5, max = 1, stats = { hp = 40, closeResist = 0.10, barrierCooldown = -1 }, desc = "+40 max health, -10% damage up close, -1s barrier cooldown.", req = { "s_bruiser" } },
	},

	engineer = {
		{ id = "e_hp",          name = "Field Kit",           tier = 1, col = 1, max = 3, stats = { hp = 8 },            desc = "+8 max health per rank." },
		{ id = "e_armor",       name = "Shield Emitter",      tier = 1, col = 2, max = 3, stats = { armor = 8 },         desc = "+8 max shield per rank." },
		{ id = "e_deploy",      name = "Turret Calibration",  tier = 1, col = 3.5, max = 3, stats = { deploy = 0.08 },     desc = "Your turrets and deployables deal +8% damage per rank." },
		{ id = "e_regen",       name = "Efficient Cells",     tier = 2, col = 2, max = 2, stats = { regen = 0.15 },      desc = "+15% shield regen speed per rank.",              req = { "e_armor" } },
		{ id = "e_cash",        name = "Salvage Rights",      tier = 2, col = 3, max = 2, stats = { killCash = 3 },      desc = "+3 J Corp cash per kill per rank.",              req = { "e_deploy" } },
		{ id = "e_deploy2",     name = "Overclocked Servos",  tier = 2, col = 4, max = 2, stats = { deploy = 0.10 },     desc = "Your turrets and deployables deal +10% damage per rank.", req = { "e_deploy" } },
		{ id = "e_killheal",    name = "Nanite Repair",       tier = 2, col = 1, max = 2, stats = { killHeal = 4 },      desc = "Kills restore 4 health per rank.",               req = { "e_hp" } },
		{ id = "e_xp",          name = "Research Grant",      tier = 3, col = 3, max = 2, stats = { xp = 0.10 },         desc = "+10% XP per rank.",                              req = { "e_cash" } },
		{ id = "e_hazard",      name = "Hazard Suit",         tier = 3, col = 1, max = 2, stats = { fire = 0.15, blast = 0.15 }, desc = "-15% fire and explosive damage taken per rank.", req = { "e_killheal" } },
		{ id = "e_chief",       name = "Chief Engineer",      tier = 4, col = 3.5, max = 1, stats = { deploy = 0.20, killCash = 5 }, desc = "Turrets/deployables +20% damage and +5 cash per kill.", req = { "e_deploy2", "e_xp" } },
		{ id = "e_reinforced",  name = "Reinforced Chassis",  tier = 3, col = 4, max = 3, stats = { deployHp = 0.15 },   desc = "Your turrets and deployables get +15% health per rank.", req = { "e_deploy2" } },
		{ id = "e_logistics",   name = "Logistics",           tier = 3, col = 2, max = 2, stats = { orderCooldown = 0.06 }, desc = "Call-in cooldowns are 6% shorter per rank.",  req = { "e_regen" } },
		{ id = "e_tinkerer",    name = "Tinkerer",            tier = 4, col = 1.5, max = 2, stats = { orderCost = 0.05, killShield = 3 }, desc = "Call-ins cost 5% less and kills restore 3 shield per rank.", req = { "e_hazard" } },
		{ id = "e_protocols",   name = "Field Protocols",     tier = 5, col = 1.5, max = 2, stats = { killCdr = 1 },       desc = "Kills take 1s off your ability cooldowns per rank.", req = { "e_tinkerer" } },
		{ id = "e_mastermind",  name = "Mastermind",          tier = 5, col = 3.5, max = 1, stats = { deploy = 0.15, deployHp = 0.25, orderCooldown = 0.10 }, desc = "Deployables +15% damage and +25% health, call-ins recharge 10% faster.", req = { "e_chief" } },
	},
}
-- // }}}


-- // Specialization upgrades {{{
-- 3 per specialization: a stat upgrade, an ability cooldown upgrade, and a signature upgrade that changes how
-- the spec's ability/perk works (t_ keys, read with S.Tune). Merged into S.tree[class] below.
local function specRow(class, spec, a, b, c)
	a.spec, b.spec, c.spec = spec, spec, spec
	a.slot, b.slot, c.slot = 1, 2, 3
	a.id, b.id, c.id = "sp_" .. spec .. "_1", "sp_" .. spec .. "_2", "sp_" .. spec .. "_3"
	b.req = { a.id }
	c.req = { b.id }
	a.tier, b.tier, c.tier = 0, 0, 0
	for i, sk in ipairs({ a, b, c }) do table.insert(S.tree[class], sk) end
end
local function cdr(spec, abilityName)
	return { name = "Rapid " .. abilityName, max = 2, stats = { ["cdr_" .. spec] = 0.10 }, desc = abilityName .. " cooldown 10% shorter per rank." }
end

-- RECON
specRow("recon", "scout",
	{ name = "Fleet Foot",       max = 2, stats = { speed = 0.04, jump = 20 }, desc = "+4% speed and +20 jump power per rank." },
	cdr("scout", "Recon Pulse"),
	{ name = "Wide-Band Sonar",  max = 1, stats = { t_pulseRange = 1500, t_pulseDuration = 4 }, desc = "Recon Pulse reaches 1500 units further and lasts 4s longer." })
specRow("recon", "infiltrator",
	{ name = "Ambusher",         max = 2, stats = { crouchDmg = 0.08, dmg = 0.03 }, desc = "+8% damage while crouched and +3% damage per rank." },
	cdr("infiltrator", "Decoy"),
	{ name = "Volatile Hologram", max = 1, stats = { t_decoyPopDamage = 120, t_decoyDuration = 3 }, desc = "Decoy lasts 3s longer and explodes for 120 damage when it pops." })
specRow("recon", "gunslinger",
	{ name = "Fast Hands",       max = 2, stats = { pistolDmg = 0.10 }, desc = "+10% pistol damage per rank." },
	cdr("gunslinger", "Deadeye"),
	{ name = "Fan the Hammer",   max = 1, stats = { t_autoAimMaxTargets = 6, t_autoAimBossDamage = 300 }, desc = "Deadeye locks on to 6 more enemies and hits bosses for +300 damage." })
specRow("recon", "stalker",
	{ name = "Patient Hunter",   max = 2, stats = { headshot = 0.12 }, desc = "+12% headshot damage per rank." },
	cdr("stalker", "One Shot, One Kill"),
	{ name = "Executioner",      max = 1, stats = { t_oneShotThreshold = 0.15 }, desc = "One Shot, One Kill executes enemies below 50% health instead of 35%." })
specRow("recon", "bountyhunter",
	{ name = "Blood Money",      max = 2, stats = { killCash = 3 }, desc = "+3 cash per kill per rank." },
	cdr("bountyhunter", "Execution"),
	{ name = "Dead or Alive",    max = 1, stats = { t_hitCashMul = 1, t_executionDuration = 2 }, desc = "Hits pay 3x the bounty instead of 2x. Execution lasts 2s longer." })
specRow("recon", "phantom",
	{ name = "Shadow Step",      max = 2, stats = { speed = 0.04, killShield = 3 }, desc = "+4% speed and +3 shield per kill per rank." },
	cdr("phantom", "Phantom Cloak"),
	{ name = "Wraith",           max = 1, stats = { t_phantomCloakPerKill = 1, t_phantomCloakMaxLeft = 5 }, desc = "Kills while cloaked add +3s (not +2s), and the cloak can build up to 20s." })

-- INFANTRY
specRow("infantry", "commando",
	{ name = "Shock and Awe",    max = 2, stats = { blastDmg = 0.10 }, desc = "+10% explosive damage dealt per rank." },
	cdr("commando", "Combat Stim"),
	{ name = "Overdose",         max = 3, stats = { t_commandoStimCount = 1, t_commandoStimDurationMul = 0.15 }, desc = "Combat Stim rolls 1 more stim and lasts 15% longer per rank." })
specRow("infantry", "ranger",
	{ name = "Steady Aim",       max = 2, stats = { rangeDmg = 0.10 }, desc = "+10% long-range damage per rank." },
	cdr("ranger", "Marksman's Focus"),
	{ name = "Hollow Points",    max = 1, stats = { t_focusRangeDamageMul = 0.25, t_focusDuration = 4 }, desc = "Marksman's Focus lasts 4s longer and gives +75% long-range damage (not +50%)." })
specRow("infantry", "grenadier",
	{ name = "Blast Veteran",    max = 2, stats = { blastDmg = 0.08, blast = 0.10 }, desc = "+8% explosive damage dealt and -10% taken per rank." },
	cdr("grenadier", "Airburst Barrage"),
	{ name = "Carpet Shelling",  max = 1, stats = { t_barrageShells = 3, t_clusterBomblets = 2 }, desc = "Airburst Barrage fires 8 shells, and Cluster Charge scatters 5 bomblets." })
specRow("infantry", "quartermaster",
	{ name = "Bulk Buyer",       max = 2, stats = { orderCost = 0.05 }, desc = "Call-ins cost 5% less per rank." },
	cdr("quartermaster", "Resupply Drop"),
	{ name = "Logistics Chief",  max = 1, stats = { t_resupplyMags = 2, t_resupplyRadius = 250 }, desc = "Resupply Drop gives 5 magazines and reaches 250 units further." })
specRow("infantry", "fieldcommander",
	{ name = "Lead from the Front", max = 2, stats = { hp = 10, armor = 10 }, desc = "+10 max health and +10 max shield per rank." },
	cdr("fieldcommander", "Battle Cry"),
	{ name = "Warlord",          max = 1, stats = { t_battleCryDuration = 4, t_battleCryRadius = 300 }, desc = "Battle Cry lasts 4s longer and reaches 300 units further." })
specRow("infantry", "shocktrooper",
	{ name = "Momentum",         max = 2, stats = { killHeal = 3 }, desc = "Kills restore 3 health per rank." },
	cdr("shocktrooper", "Overdrive"),
	{ name = "Live Wire",        max = 1, stats = { t_shockMaxStacks = 5, t_overdriveMax = 6 }, desc = "Kill stacks go up to 15 (+45% damage), and Overdrive can build up to 18s." })

-- ENGINEER
specRow("engineer", "technician",
	{ name = "Hardened Turrets", max = 2, stats = { deploy = 0.08, deployHp = 0.10 }, desc = "Deployables +8% damage and +10% health per rank." },
	cdr("technician", "Overclock"),
	{ name = "Overvolt",         max = 1, stats = { t_overclockDuration = 4 }, desc = "Overclock lasts 4s longer." })
specRow("engineer", "medic",
	{ name = "Bedside Manner",   max = 2, stats = { hp = 8, killHeal = 2 }, desc = "+8 max health and +2 HP per kill per rank." },
	cdr("medic", "Triage Pulse"),
	{ name = "Mass Triage",      max = 1, stats = { t_triageHeal = 30, t_triageRadius = 200 }, desc = "Triage Pulse heals 80 HP (not 50) and reaches 200 units further." })
specRow("engineer", "mechanic",
	{ name = "Quick Fix",        max = 2, stats = { orderCooldown = 0.06 }, desc = "Call-in cooldowns are 6% shorter per rank." },
	cdr("mechanic", "Quick Deploy"),
	{ name = "Heavy Deploy",     max = 1, stats = { t_quickDeployLifetime = 30, t_mechanicRepair = 3 }, desc = "Quick Deploy turrets last 60s (not 30s), and your repairs are 60% faster." })
specRow("engineer", "fieldsurgeon",
	{ name = "Capacitor Bank",   max = 2, stats = { armor = 10, regen = 0.10 }, desc = "+10 max shield and +10% shield regen per rank." },
	cdr("fieldsurgeon", "Barrier Burst"),
	{ name = "Hardlight Overcharge", max = 1, stats = { t_barrierBurstDuration = 5, t_barrierBurstMul = 0.25 }, desc = "Barrier Burst overcharges shields to 175% and lasts 5s longer." })
specRow("engineer", "dronemaster",
	{ name = "Swarm Logic",      max = 2, stats = { deploy = 0.10 }, desc = "Deployables +10% damage per rank." },
	cdr("dronemaster", "Drone Swarm"),
	{ name = "Hive Mind",        max = 1, stats = { t_swarmDrones = 2, t_swarmLifetime = 10 }, desc = "Drone Swarm calls 5 drones (not 3) that last 10s longer." })
specRow("engineer", "guardian",
	{ name = "Stalwart",         max = 2, stats = { resist = 0.04 }, desc = "-4% damage taken per rank." },
	{ name = "Wide Aura",        max = 2, stats = { t_auraRadius = 100 }, desc = "Your auras reach 100 units further per rank." },
	{ name = "Guardian Angel",   max = 1, stats = { t_guardianAuraMul = 1 }, desc = "Your auras are 4x as strong (not 3x)." })

-- SENTINEL
specRow("sentinel", "juggernaut",
	{ name = "Plate Stacking",   max = 2, stats = { armor = 15 }, desc = "+15 max shield per rank." },
	cdr("juggernaut", "Iron Skin"),
	{ name = "Titan Skin",       max = 1, stats = { t_ironSkinDuration = 3, t_ironSkinSpeedMul = 0.30 }, desc = "Iron Skin lasts 3s longer and no longer slows you down." })
specRow("sentinel", "brawler",
	{ name = "Heavy Hands",      max = 2, stats = { meleeDmg = 0.15 }, desc = "+15% melee damage per rank." },
	cdr("brawler", "Ground Pound"),
	{ name = "Earthshaker",      max = 1, stats = { t_poundDamage = 60, t_poundRadius = 100 }, desc = "Ground Pound deals 140 damage (not 80) and hits 100 units wider." })
specRow("sentinel", "bastion",
	{ name = "Stonewall",        max = 2, stats = { resist = 0.04, armor = 10 }, desc = "-4% damage taken and +10 max shield per rank." },
	cdr("bastion", "Challenge"),
	{ name = "Unyielding",       max = 1, stats = { t_challengeDamageTaken = -0.20, t_challengeDuration = 3 }, desc = "During Challenge you take 70% less damage (not 50%), and it lasts 3s longer." })
specRow("sentinel", "enforcer",
	{ name = "Riot Gear",        max = 2, stats = { meleeDmg = 0.10, speed = 0.03 }, desc = "+10% melee damage and +3% speed per rank." },
	cdr("enforcer", "Charge"),
	{ name = "Freight Train",    max = 1, stats = { t_chargeDamage = 60, t_chargeDuration = 0.25 }, desc = "Charge goes 50% further and hits for 100 damage (not 40)." })
specRow("sentinel", "aegis",
	{ name = "Projector Tuning", max = 2, stats = { barrierLength = 1 }, desc = "+1s barrier duration per rank." },
	cdr("aegis", "Aegis Dome"),
	{ name = "Fortress",         max = 1, stats = { t_domeHealth = 700, t_domeDuration = 5 }, desc = "Aegis Dome absorbs 1500 damage (not 800) and lasts 5s longer." })
specRow("sentinel", "ravager",
	{ name = "Carnage",          max = 2, stats = { meleeKillHeal = 5 }, desc = "+5 HP per melee kill per rank." },
	cdr("ravager", "Bloodlust"),
	{ name = "Endless Rage",     max = 1, stats = { t_bloodlustPerKill = 3, t_bloodlustMax = 15 }, desc = "Bloodlust melee kills add +8s (not +5s), up to 45s." })
-- }}}

-- // Lookup + helpers {{{
S.byId = {}
for class, skills in pairs(S.tree) do
	S.byId[class] = {}
	for i, sk in ipairs(skills) do
		sk.index = i
		S.byId[class][sk.id] = sk
	end
end

function S.IsSkillClass(class)
	return S.tree[class] ~= nil
end

function S.ChipsetsSpent(skills)
	local n = 0
	for id, rank in pairs(skills or {}) do
		n = n + (tonumber(rank) or 0)
	end
	return n
end

function S.ChipsetsAvailable(classData)
	if not classData then return 0 end
	return S.ChipsetsEarned(classData.level) - S.ChipsetsSpent(classData.skills)
end

-- // PVP scaling {{{
-- Coop is meant to feel tanky - late-winstreak enemies delete you without it - so the implant and
-- specialization numbers are tuned for PVE and left exactly as they are there. PVP is the problem
-- case: those same numbers are what let a level-30 Sentinel walk through a fresh player, so they get
-- scaled down here and only here. Nothing in this block runs outside a live PVP mission.
--
-- Why these groups: measured against the real 29-Chipset budget, defence was the runaway - a maxed
-- Sentinel reached ~1,800 effective HP against a fresh player's 250 (7.1x). Offence barely needs
-- touching, because half of it already does nothing to players (headshots and every on-kill effect
-- hang off NPC-only hooks). So defence is halved, offence is nudged, and resistance gets a hard PVP
-- ceiling. That lands the spread at ~2.7x for Sentinel and 1.4-1.6x for the rest: still clearly a
-- tank, no longer unkillable.
S.pvpScale = {
	enabled = true,

	defense = 0.50,   -- hp, armor and every damage-reduction stat
	offense = 0.85,   -- damage dealt, in all its conditional flavours
	utility = 0.75,   -- speed, jump, shield regen and delay
	deploy  = 0.60,   -- turret / deployable damage and health

	-- Hard ceilings in PVP, applied at the end so Team Upgrades can't push back over them
	resistCap = 0.40,
	closeCap  = 0.25, -- caps closeResist and sprintResist each
}

-- Only the keys listed here are touched. Anything absent - the t_ ability tuning keys, cdr_ keys,
-- barrier timings, per-kill effects, cash and XP - passes through untouched, because scaling those
-- either does nothing in PVP anyway or would quietly break an ability that counts in whole numbers
-- (0.85 of a mortar shell is not a thing).
S.pvpScaleGroups = {
	hp = "defense", armor = "defense", resist = "defense", blast = "defense", fire = "defense",
	sprintResist = "defense", closeResist = "defense",

	dmg = "offense", blastDmg = "offense", meleeDmg = "offense", pistolDmg = "offense",
	rangeDmg = "offense", crouchDmg = "offense", airDmg = "offense", lowHpDmg = "offense",
	headshot = "offense",

	speed = "utility", jump = "utility", regen = "utility", delay = "utility",

	deploy = "deploy", deployHp = "deploy",
}

-- True only inside a live PVP mission. jcms.util_IsPVP reads a networked bool off the world entity,
-- so this answers the same on the server and on the client.
function S.PvpScaling()
	local cfg = S.pvpScale
	if not (cfg and cfg.enabled) then return nil end
	if not (jcms and jcms.util_IsPVP and jcms.util_IsPVP()) then return nil end
	return cfg
end

-- Scales a totals table in place. Negative values (Infiltrator's -10 hp) scale too, which is what
-- you want: a halved penalty next to a halved bonus.
function S.ScaleForPvp(totals)
	local cfg = S.PvpScaling()
	if not cfg then return totals end

	for k, v in pairs(totals) do
		local group = S.pvpScaleGroups[k]
		local f = group and cfg[group]
		if f and f ~= 1 then totals[k] = v * f end
	end
	return totals
end
-- }}}

-- Total bonuses from skill ranks + picked specializations (+ that player's stims, when `ply` is given).
function S.ComputeStats(class, skills, specs, ply)
	local totals = {}
	local tree = S.byId[class]
	if not tree then return totals end

	local picked = {}
	for tier, id in pairs(specs or {}) do picked[id] = true end

	for id, rank in pairs(skills or {}) do
		local sk = tree[id]
		rank = tonumber(rank) or 0
		if sk and rank > 0 and (not sk.spec or picked[sk.spec]) then
			for k, v in pairs(sk.stats) do
				totals[k] = (totals[k] or 0) + v * rank
			end
		end
	end

	-- Specializations (S.specs is defined in sh_specs.lua)
	for tier, id in pairs(specs or {}) do
		local spec = S.GetSpec and S.GetSpec(class, id)
		if spec and spec.tier == tonumber(tier) then
			for k, v in pairs(spec.stats) do
				totals[k] = (totals[k] or 0) + v
			end
		end
	end

	-- In PVP, scale what PROGRESSION gave you - the tree and the specializations, i.e. everything above
	-- this line. Deliberately before Team Upgrades, stims and modifiers: those are equal for everyone in
	-- the match (Team Upgrades are server-wide, stims are pickups), so they aren't what makes a veteran
	-- unkillable and nerfing them would just make PVP mushy.
	S.ScaleForPvp(totals)

	-- Team Upgrades (sh_group.lua) apply to every sweeper
	if S.GetGroupStats then
		for k, v in pairs(S.GetGroupStats()) do
			totals[k] = (totals[k] or 0) + v
		end
	end

	-- Stims: temporary boosts from Stim Crates (sh_stims.lua)
	if ply and S.GetStimStats then
		for k, v in pairs(S.GetStimStats(ply)) do
			totals[k] = (totals[k] or 0) + v
		end
	end

	-- Mission modifiers + weather effects (sh_modifiers.lua)
	if S.GetModifierStats then
		for k, v in pairs(S.GetModifierStats(class)) do
			totals[k] = (totals[k] or 0) + v
		end
	end

	-- Sanity caps
	totals.resist = math.min(totals.resist or 0, 0.75)
	totals.blast = math.min(totals.blast or 0, 0.9)
	totals.fire = math.min(totals.fire or 0, 0.9)
	totals.delay = math.min(totals.delay or 0, 0.9)
	totals.orderCost = math.min(totals.orderCost or 0, 0.9)
	totals.orderCooldown = math.min(totals.orderCooldown or 0, 0.9)
	totals.speed = math.max(totals.speed or 0, -0.5)
	totals.regen = math.max(totals.regen or 0, -0.9)          -- negative values come from mission modifiers / weather
	totals.orderCost = math.max(totals.orderCost, -1.5)
	totals.orderCooldown = math.max(totals.orderCooldown, -1.5)
	totals.resist = math.max(totals.resist, -1)
	totals.sprintResist = math.min(totals.sprintResist or 0, 0.5)
	totals.closeResist = math.min(totals.closeResist or 0, 0.5)
	totals.ammoDrop = math.min(totals.ammoDrop or 0, 0.75)

	-- PVP ceilings last, so nothing added after the scaling above can climb back over them. These are
	-- what stop the multiplicative stack: resist, closeResist and sprintResist multiply together in the
	-- damage hook, so 40% + 25% + 25% is already a 66% cut at a dead run in someone's face.
	local pvp = S.PvpScaling()
	if pvp then
		totals.resist = math.min(totals.resist or 0, pvp.resistCap)
		totals.closeResist = math.min(totals.closeResist or 0, pvp.closeCap)
		totals.sprintResist = math.min(totals.sprintResist or 0, pvp.closeCap)
	end

	return totals
end

function S.ReqsMet(class, skills, sk)
	if not sk.req then return true end
	for i, reqId in ipairs(sk.req) do
		if (tonumber(skills[reqId]) or 0) < 1 then
			return false
		end
	end
	return true
end

-- Returns ok, reasonString
function S.CanBuy(class, classData, id)
	local sk = S.byId[class] and S.byId[class][id]
	if not sk then return false, "Unknown skill." end

	local rank = tonumber(classData.skills[id]) or 0
	if rank >= sk.max then return false, "Already at max rank." end
	if sk.spec then
		local has = false
		for tier, sid in pairs(classData.specs or {}) do if sid == sk.spec then has = true end end
		if not has then
			local spec = S.GetSpec and S.GetSpec(class, sk.spec)
			return false, "Pick " .. (spec and spec.name or sk.spec) .. " first."
		end
	end
	if not S.ReqsMet(class, classData.skills, sk) then return false, "Requirements not met." end
	if S.ChipsetsAvailable(classData) < 1 then return false, "No " .. S.pointNamePlural .. " available." end
	return true
end

local statLabels = {
	{ "hp",         "+%d max health",          1 },
	{ "armor",      "+%d max shield",          1 },
	{ "dmg",        "+%d%% damage",            100 },
	{ "speed",      "+%d%% move speed",        100 },
	{ "jump",       "+%d jump power",          1 },
	{ "resist",     "-%d%% damage taken",      100 },
	{ "blast",      "-%d%% explosive damage",  100 },
	{ "fire",       "-%d%% fire damage",       100 },
	{ "regen",      "+%d%% shield regen",      100 },
	{ "delay",      "-%d%% shield delay",      100 },
	{ "killHeal",   "+%d HP per kill",         1 },
	{ "killShield", "+%d shield per kill",     1 },
	{ "killCash",   "+%d cash per kill",       1 },
	{ "xp",         "+%d%% XP",                100 },
	{ "deploy",     "+%d%% turret damage",     100 },
	{ "deployHp",   "+%d%% deployable health", 100 },
	{ "airDmg",     "+%d%% damage in the air", 100 },
	{ "lowHpDmg",   "+%d%% damage below half health", 100 },
	{ "sprintResist", "-%d%% damage taken while running", 100 },
	{ "closeResist", "-%d%% damage taken up close", 100 },
	{ "killCdr",    "-%ds ability cooldown per kill", 1 },
	{ "ammoDrop",   "+%d%% ammo drop chance per kill", 100 },
	{ "meleeDmg",   "+%d%% melee damage",      100 },
	{ "meleeKillHeal", "+%d HP per melee kill", 1 },
	{ "pistolDmg",  "+%d%% pistol damage",     100 },
	{ "headshot",   "+%d%% headshot damage",   100 },
	{ "crouchDmg",  "+%d%% damage while crouched", 100 },
	{ "rangeDmg",   "+%d%% damage at long range", 100 },
	{ "blastDmg",   "+%d%% explosive damage dealt", 100 },
	{ "orderCost",  "-%d%% order cost",        100 },
	{ "orderCooldown", "-%d%% order cooldown", 100 },
	{ "barrierLength", "+%ds barrier duration", 1 },
	{ "barrierCooldown", "%+ds barrier cooldown", 1 },
}

-- Every non-zero bonus as its own string, in statLabels order. The UI needs the pieces separately so
-- it can lay them out as a list or fit as many as it has room for, instead of one run-on line.
function S.StatList(totals)
	local parts = {}
	for i, row in ipairs(statLabels) do
		local v = totals[ row[1] ]
		if v and v ~= 0 then
			local fmt = row[2]
			if v < 0 and row[1] ~= "barrierCooldown" then
				-- flip the sign for negative values, e.g. "+%d max health" -> "-10 max health"
				fmt = string.gsub(fmt, "^([%+%-])", function(c) return c == "+" and "-" or "+" end)
				v = -v
			end
			parts[#parts + 1] = string.format(fmt, math.Round(v * row[3]))
		end
	end
	return parts
end

function S.FormatStats(totals)
	return table.concat(S.StatList(totals), ",  ")
end
-- // }}}


-- // Per-player tuning (specialization upgrades) {{{
-- Server: the stat totals of the player's active class. Client: only the local player's (others get nil,
-- so their values fall back to the base config - only used for visuals there).
function S.PlayerTotals(ply)
	if not IsValid(ply) then return nil end
	if SERVER then return S.GetPlayerTotals and S.GetPlayerTotals(ply) or nil end
	if ply ~= LocalPlayer() then return nil end
	local class = ply:GetNWString("jcms_class", "")
	local cd = S.cl and S.cl[class]
	if not cd or not S.IsSkillClass(class) then return nil end
	local frame = FrameNumber()
	if S._clTotalsFrame ~= frame or S._clTotalsClass ~= class then
		S._clTotalsFrame, S._clTotalsClass = frame, class
		S._clTotals = S.ComputeStats(class, cd.skills, cd.specs, ply)
	end
	return S._clTotals
end

-- base + this player's t_<key> bonus
function S.Tune(ply, key, base)
	local t = S.PlayerTotals(ply)
	local add = t and t["t_" .. key]
	if add then return base + add end
	return base
end
-- }}}

-- // Overheal caps {{{
-- Health and shield gained from kills and lifesteal stop at your maximum. Sentinels are the
-- exception: they're meant to be standing in it, so their kill gains push past the bar.
-- Fractions above 1.0 = how far over maximum that source is allowed to reach.
S.overheal = {
	sentinelHp     = 0.20,  -- Sentinel kill gains reach 120% of max health
	sentinelShield = 0.25,  -- ...and 125% of max shield

	-- Anything above the NORMAL max (kill gains, medkit overheal, overshields) drains back down
	-- once it has gone this long without being topped up again.
	decayDelay     = 60,
	decayRate      = 2,     -- health / shield per second once it starts draining
}

function S.KillHealthCap(ply)
	local base = ply:GetMaxHealth()
	if S.GetActiveClass and S.GetActiveClass(ply) == "sentinel" then
		return math.floor(base * (1 + (S.overheal.sentinelHp or 0)))
	end
	return base
end

function S.KillShieldCap(ply)
	local base = ply:GetMaxArmor()
	if S.GetActiveClass and S.GetActiveClass(ply) == "sentinel" then
		return math.floor(base * (1 + (S.overheal.sentinelShield or 0)))
	end
	return base
end

-- Every kill heal / lifesteal in the addon goes through these two.
-- They only ever ADD: someone already above the cap from another source (a Barrier Burst
-- overshield, say) is left alone rather than trimmed back down.
function S.GrantKillHealth(ply, amount)
	if not SERVER then return end
	if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return end

	local hp, cap = ply:Health(), S.KillHealthCap(ply)
	if hp >= cap then return end
	ply:SetHealth(math.min(hp + amount, cap))
	if ply:Health() > ply:GetMaxHealth() then S.MarkOverheal(ply) end
end

function S.GrantKillShield(ply, amount)
	if not SERVER then return end
	if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return end

	local sh, cap = ply:Armor(), S.KillShieldCap(ply)
	if sh >= cap then return end
	ply:SetArmor(math.min(sh + amount, cap))
	if ply:Armor() > ply:GetMaxArmor() then S.MarkOverheal(ply) end
end

-- // Overheal decay {{{
-- Overheal used to sit there forever: a Medic pair could hold 150% health indefinitely before a
-- push. Anything above the normal max now drains back down after decayDelay seconds without a
-- top-up. Every source that pushes someone over calls S.MarkOverheal to restart that clock, and
-- the tick below starts one itself for anything that doesn't, so nothing can sit over the cap.
function S.MarkOverheal(ply)
	if IsValid(ply) and ply:IsPlayer() then ply.sweeperOverhealAt = CurTime() end
end

if SERVER then
	local DECAY_TICK = 1

	timer.Create("sweeper_overhealDecay", DECAY_TICK, 0, function()
		local ct = CurTime()
		local delay = S.overheal.decayDelay or 60
		local step = math.max(1, math.ceil((S.overheal.decayRate or 2) * DECAY_TICK))

		for i, ply in ipairs(player.GetAll()) do
			if not ply:Alive() then
				ply.sweeperOverhealAt = nil
			else
				local maxHp, maxSh = ply:GetMaxHealth(), ply:GetMaxArmor()
				local hp, sh = ply:Health(), ply:Armor()

				if hp > maxHp or sh > maxSh then
					local at = ply.sweeperOverhealAt
					if not at then
						ply.sweeperOverhealAt = ct -- untracked source: start its clock now
					elseif ct - at >= delay then
						if hp > maxHp then ply:SetHealth(math.max(maxHp, hp - step)) end
						if sh > maxSh then ply:SetArmor(math.max(maxSh, sh - step)) end
					end
				else
					ply.sweeperOverhealAt = nil
				end
			end
		end
	end)
end
-- }}}


-- // Printing long text {{{
-- The engine refuses any TextMsg over 255 bytes ("Refusing to send user message TextMsg of N bytes"),
-- which silently eats long console listings and chat lines. These split the text into safe pieces first.
local PRINT_CHUNK = 180

local function chunks(text, out)
	for line in string.gmatch(tostring(text) .. "\n", "([^\n]*)\n") do
		if #line <= PRINT_CHUNK then
			out[#out + 1] = line
		else
			-- break on spaces where we can, hard-cut when a single word is too long
			while #line > PRINT_CHUNK do
				local cut = PRINT_CHUNK
				for i = PRINT_CHUNK, math.floor(PRINT_CHUNK * 0.6), -1 do
					if string.sub(line, i, i) == " " then cut = i break end
				end
				out[#out + 1] = string.sub(line, 1, cut)
				line = string.sub(line, cut + 1)
			end
			if line ~= "" then out[#out + 1] = line end
		end
	end
	return out
end
S.TextChunks = function(text) return chunks(text, {}) end

-- Console print: to that player's console, or the server console when ply is nil (rcon / listen server host)
function S.PrintConsole(ply, text)
	local lines = chunks(text, {})
	if IsValid(ply) and ply:IsPlayer() then
		for i, line in ipairs(lines) do ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	else
		for i, line in ipairs(lines) do print(line) end
	end
end

-- Chat print, same size guard
function S.ChatPrint(ply, text)
	if not (IsValid(ply) and ply:IsPlayer()) then return end
	for i, line in ipairs(chunks(text, {})) do ply:ChatPrint(line) end
end

function S.ChatPrintAll(text)
	local lines = chunks(text, {})
	for i, p in ipairs(player.GetHumans()) do
		for j, line in ipairs(lines) do p:ChatPrint(line) end
	end
end
-- }}}
