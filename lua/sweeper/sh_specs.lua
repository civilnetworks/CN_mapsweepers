--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Shared: Specializations (T1-T3 subclasses).

	A player picks ONE of two specializations per tier. Picks stack (T1 + T2 + T3 all active).
	`stats` uses the same keys as skills (see sh_tree.lua), but are NOT per-rank - they apply once.

	Extra stat keys used by specializations:
		meleeDmg       melee damage dealt            (0.5 = +50%)
		meleeKillHeal  health restored per melee kill
		pistolDmg      pistol/revolver damage dealt  (0.25 = +25%)
		headshot       headshot damage vs NPCs       (0.3 = +30%)
		crouchDmg      damage dealt while crouched   (0.2 = +20%)
		rangeDmg       damage vs targets far away    (0.2 = +20%, beyond S.rangeDmgDistance units)
		blastDmg       explosive damage dealt        (0.25 = +25%)
		orderCost      order (spawn menu) cost       (0.15 = 15% cheaper)
		orderCooldown  order cooldowns               (0.25 = 25% shorter)
		barrierLength  Sentinel barrier duration     (seconds, added)
		barrierCooldown Sentinel barrier cooldown    (seconds, added - use negative to shorten)

	`perk`    describes a unique mechanic that IS coded (shown in the menu as "Perk:").
	`ability` describes a planned mechanic that is NOT coded yet (shown as "coming soon").
--]]

local S = sweeper

S.specLevels = { 5, 12, 20 } -- level required for T1, T2, T3
S.rangeDmgDistance = 1000     -- ~19 metres

S.specs = {
	recon = {
		{ -- T1
			{ id = "scout",        name = "Scout",        stats = { speed = 0.15, jump = 40, delay = 0.20 },
			  perk = "Enemies you aim at are outlined for your whole team for 6s. Ability (Recon Pulse): outline every enemy within 2500 units for your whole team for 8s, through walls. 40s cooldown." },
			{ id = "infiltrator",  name = "Infiltrator",  stats = { hp = -10, dmg = 0.15 },
			  perk = "Ambush: +40% damage to enemies that aren't targeting you - anything that hasn't noticed you, or that your Decoy has pulled away. Ability (Decoy): drop a hologram of yourself. Nearby enemies lose track of you and go after it for 8s, or until they shoot it down. 25s cooldown." },
		},
		{ -- T2
			{ id = "gunslinger",   name = "Gunslinger",   stats = { speed = 0.10, pistolDmg = 0.25 },
			  perk = "Quickdraw: each kill makes you reload 10% faster for 30s (stacks 5 times). Ability (Deadeye): lock on to every enemy on your screen and one-shot them. 45s cooldown." },
			{ id = "stalker",      name = "Stalker",      stats = { headshot = 0.30, crouchDmg = 0.20, killShield = 10 },
			  perk = "Weak Point: enemies you shoot are marked for 5s, and your whole team deals +15% damage to them. Ability (One Shot, One Kill): for 6s, any enemy below 35% HP dies to your next hit. Every execute resets the timer. 45s cooldown." },
		},
		{ -- T3
			{ id = "bountyhunter",       name = "Bounty Hunter", stats = { hp = 10, headshot = 0.20 },
			  perk = "Hits: new enemies sometimes become bounty targets for 60s, seen through walls by your whole team. Whoever kills one gets 2x its bounty and 60 XP. Ability (Execution): 6s of 5x damage and 2.5x fire rate. 45s cooldown." },
			{ id = "phantom",      name = "Phantom",      stats = { speed = 0.10, armor = 20 },
			  perk = "Triple jump. Nearby allies move 10% faster. Ability (Phantom Cloak): 6s invisible. Shooting doesn't break it, and each kill adds +2s (up to 15s left). 35s cooldown." },
		},
	},

	infantry = {
		{
			{ id = "commando",     name = "Commando",     stats = { armor = 15, dmg = 0.10 },
			  perk = "Combat Cocktail: every stim running on you gives +3% damage. Ability (Combat Stim): roll a random stim for 15s. 30s cooldown." },
			{ id = "ranger",       name = "Ranger",       stats = { hp = 20, rangeDmg = 0.20 },
			  perk = "Long-range kills refill half a magazine into your reserve ammo. Ability (Marksman's Focus): 8s of zoom, no bullet spread and +50% damage at long range. 40s cooldown." },
		},
		{
			{ id = "grenadier",    name = "Grenadier",    stats = { blastDmg = 0.25, blast = 0.40 },
			  perk = "Cluster Charge: your explosions scatter 3 bomblets. Blast Walker: your own explosions heal you instead of hurting you. Ability (Airburst Barrage): 5 mortar shells rain down where you aim (never hurts your team). 40s cooldown." },
			{ id = "quartermaster",name = "Quartermaster",stats = { orderCost = 0.15, killCash = 3 },
			  perk = "Tops your reserve ammo back up every 60 seconds during a mission, no crate to pick up. Ability (Resupply Drop): you and nearby allies get 3 magazines for every gun and a full shield. 60s cooldown." },
		},
		{
			{ id = "fieldcommander", name = "Field Commander", stats = { hp = 20 },
			  perk = "Rally aura: nearby allies deal +10% damage and regain 2 shield per second. Ability (Battle Cry): allies within ~11m get +25% damage and +25% fire rate for 8s. 50s cooldown." },
			{ id = "shocktrooper", name = "Shock Trooper", stats = { speed = 0.10, armor = 10 },
			  perk = "Kills stack +3% damage (max 10, fades 8s after your last kill). Below 30% HP: Adrenaline gives +25% speed and -25% damage taken for 5s (60s cooldown). Ability (Overdrive): trigger Adrenaline on demand; kills add +1s (up to 12s). 40s cooldown." },
		},
	},

	engineer = {
		{
			{ id = "technician",   name = "Technician",   stats = { deploy = 0.20 },
			  perk = "Deployables +50% HP. Turrets get 2x ammo, a regenerating shield, and take 30% less damage. Ability (Overclock): your turrets and deployables fire 2x faster and can't be damaged for 8s. 45s cooldown." },
			{ id = "medic",        name = "Medic",        stats = { hp = 10 },
			  perk = "Spawns with the Medkit (Medic only). Heal aura: 5 HP/s to nearby allies. Ability (Triage Pulse): instantly heal everyone nearby for 50 HP and put out fires. 30s cooldown." },
		},
		{
			{ id = "mechanic",     name = "Mechanic",     stats = { orderCooldown = 0.25, orderCost = 0.15 },
			  perk = "Hold E on your turrets and deployables to repair them and refill turret ammo. Ability (Quick Deploy): drop a free mini SMG turret in front of you for 30s. 45s cooldown." },
			{ id = "fieldsurgeon", name = "Field Surgeon",stats = { armor = 15 },
			  perk = "Shield aura: 2.5 shield/s to nearby allies, and puts out burning allies. Ability (Barrier Burst): overcharge nearby allies' shields to 150% for 10s. 40s cooldown." },
		},
		{
			{ id = "dronemaster",    name = "Drone Master", stats = { deploy = 0.25 },
			  perk = "Your turrets fire 25% faster and see 25% further. Run 2 Combat Drones at once. Ability (Drone Swarm): call in 3 extra Combat Drones for 20s. 60s cooldown." },
			{ id = "guardian",     name = "Guardian",     stats = { hp = 20 },
			  perk = "Your auras are tripled. Ability (Lifeline), once per mission: revive a fallen teammate next to you." },
		},
	},

	sentinel = {
		{
			{ id = "juggernaut",   name = "Juggernaut",   stats = { hp = 25, armor = 50, resist = 0.15, speed = -0.05 },
			  perk = "Immovable: no single hit can take more than 20% of your max health, so nothing one-shots you. Ability (Iron Skin): take 70% less damage for 6s, but move 30% slower. 35s cooldown." },
			{ id = "brawler",      name = "Brawler",      stats = { hp = 50, meleeDmg = 0.50, meleeKillHeal = 10 },
			  perk = "Frenzy: every melee kill gives +10% melee damage and +4% speed for 6s, stacking 5 times. Ability (Ground Pound): leap up and slam down - 80 damage around you, enemies are knocked back and staggered. No fall damage. 20s cooldown." },
		},
		{
			{ id = "bastion",      name = "Bastion",      stats = { resist = 0.10, armor = 30 },
			  perk = "Taunt: enemies within ~13m prefer to target you. Your walk key (Alt) toggles Taunt on/off instead of raising the barrier (starts off, and turns off if you swap out of Bastion). Taunt runs on a 600 damage pool in place of that barrier - damage you take while it's up drains the pool, and when it empties the Taunt drops and takes 12s to come back full. Switching it off yourself instead refills it at 40/s. Ability (Challenge): every enemy within ~20m is forced to target you for 6s while you take 50% less damage. 40s cooldown." },
			{ id = "enforcer",     name = "Enforcer",     stats = { meleeDmg = 0.30, speed = 0.05 },
			  perk = "Riot Control: your melee hits knock enemies off their feet, and every enemy your Charge hits takes 1.5s off its cooldown (up to 6s per charge). Ability (Charge): dash forward; enemies in your path take 40 damage and get knocked back. Works in mid-air, holding its height, so it chains off a jump. 12s cooldown." },
		},
		{
			{ id = "aegis",        name = "Aegis",        stats = { barrierLength = 4, barrierCooldown = -1 },
			  perk = "Kinetic Reclaim: 25% of the damage your Bullet Barrier or Aegis Dome absorbs comes back to you as shield. Ability (Aegis Dome): a shield bubble moves with you for 10s. Enemy fire from outside is absorbed (800 HP) before it reaches anyone inside, but your team can still shoot out. 40s cooldown." },
			{ id = "ravager",      name = "Ravager",      stats = { hp = 25 },
			  perk = "Melee hits heal you for 30% of the damage. Dropping below 35% HP triggers Rage: +30% damage and +20% speed for 8s (45s cooldown). Ability (Bloodlust): trigger Rage on demand; melee kills add +5s (up to 30s). 40s cooldown." },
		},
	},
}

-- Lookup: S.specById[class][id] = { tier = n, spec = tbl }
S.specById = {}
for class, tiers in pairs(S.specs) do
	S.specById[class] = {}
	for tier, options in ipairs(tiers) do
		for i, spec in ipairs(options) do
			spec.tier = tier
			S.specById[class][spec.id] = spec
		end
	end
end

function S.GetSpec(class, id)
	return S.specById[class] and S.specById[class][id]
end

-- Returns ok, reason. `inMission` = a mission is currently running.
function S.CanPickSpec(class, classData, tier, id, inMission)
	local spec = S.GetSpec(class, id)
	if not spec or spec.tier ~= tier then return false, "Unknown specialization." end

	local specs = classData.specs or {}
	if specs[tier] == id then return false, "Already selected." end
	if (classData.level or 1) < S.specLevels[tier] then
		return false, "Unlocks at level " .. S.specLevels[tier] .. "."
	end
	if tier > 1 and not specs[tier - 1] then
		return false, "Pick a Tier " .. (tier - 1) .. " specialization first."
	end
	if specs[tier] and inMission then
		return false, "Specializations can only be changed between missions."
	end
	return true
end

-- Name of the player's highest picked specialization (or nil)
function S.GetTopSpecName(class, classData)
	local specs = classData and classData.specs
	if not specs then return nil end
	for tier = 3, 1, -1 do
		local spec = specs[tier] and S.GetSpec(class, specs[tier])
		if spec then return spec.name end
	end
end
