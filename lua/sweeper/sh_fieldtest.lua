--[[
	Map Sweepers - Implants & Class Levels (addon)
	Helpers for the Field Trials mission (the "guntest" mission in the Workshop addon
	"MAP SWEAPERS boblikut's EXTENSION #1").

	HOW THAT MISSION PICKS ITS WEAPONS
		The dispenser terminal rolls  table.Random(jcms.weapon_prices)  and re-rolls while the class
		is in jcms.ft_bl or is already being tested. So the trial pool IS the shop's price table:
		  - every Spawnable SWEP is priced automatically by the gamemode, so a mounted weapon pack
		    is in the pool already - there's nothing to register,
		  - a weapon is OUT only if it has no price (or 0), is in jcms.weapon_blacklist, is in the
		    Field Trials blacklist, or is being tested right now.

	SO "ADDING A WEAPON" MEANS GIVING IT A PRICE. S.fieldTest.prices below does that: the classes
	listed there are written into jcms.weapon_prices after the gamemode has built it, which puts
	them in the trial pool (and in the shop, same table).

	The extension ships jcms_ft_add_to_bl and jcms_ft_update_bl, both superadmin, and no way to take
	a weapon back OUT of the blacklist short of editing data/mapsweepers/server/ft_blacklist.json by
	hand. The commands here fill that in and write the same file it reads.

	WATCH OUT: its re-roll is `while jcms.ft_bl[class] or isWeaponTesting(class) do ... end` with no
	attempt limit, so a blacklist covering every priced weapon freezes the server the moment someone
	uses the terminal. sweeper_ft_pool reports how many weapons can still roll, and the check on
	mission start shouts if that number reaches zero.

	Commands (admin):
		sweeper_ft_pool [n]        how many weapons can roll, and a sample
		sweeper_ft_list            the Field Trials blacklist
		sweeper_ft_add <class>     blacklist a weapon
		sweeper_ft_remove <class>  take one back off the blacklist  (the missing one)
		sweeper_ft_clear           empty the blacklist
--]]

local S = sweeper

S.fieldTest = S.fieldTest or {"arccw_apex_havoc", "arccw_apex_hemlok", "arccw_apex_r301", "arccw_apex_flatline", "arccw_apex_bocek", "arccw_apex_3030", "arccw_apex_g7", "arccw_apex_tripletake", "arccw_apex_nade_arcstar", "arccw_apex_nade_frag", "arccw_apex_nade_nox", "arccw_apex_nade_thermite", "arccw_apex_lstar", "arccw_apex_spitfire", "arccw_apex_rampage", "arccw_apex_devotion", "arccw_apex_melee_wrench", "arccw_apex_melee_baton", "arccw_apex_mozambique", "arccw_apex_p2020", "arccw_apex_re45", "arccw_apex_wingman", "arccw_apex_eva", "arccw_apex_mastiff", "arccw_apex_peacekeeper", "arccw_apex_chargerifle", "arccw_apex_kraber", "arccw_apex_longbow", "arccw_apex_sentinel", "arccw_apex_alternator", "arccw_apex_car", "arccw_apex_prowler", "arccw_apex_r99", "arccw_apex_volt", "sfw_eblade", "sfw_hornet", "sfw_stinger", "sfw_dartgun", "sfw_vprnade", "sfw_pulsar", "sfw_azure", "sfw_lapis", "sfw_zircon", "sfw_vapor", "sfw_fallingstar", "sfw_asa6", "sfw_storm", "sfw_akraga", "sfw_phasma", "sfw_zeala", "sfw_astra", "sfw_prisma", "sfw_supra", "sfw_vectra", "sfw_alchemy", "sfw_frag", "sfw_lapis_dual", "sfw_phoenix", "sfw_ember", "sfw_seraphim", "sfw_pyre", "sfw_hwave", "sfw_saphyre", "sfw_pandemic", "sfw_draco", "sfw_aquamarine", "sfw_helios", "sfw_umbra", "sfw_kamahmg", "sfw_neutrino", "sfw_frag_mirv", "sfw_hellfire", "sfw_grinder", "sfw_corruptor", "sfw_behemoth", "sfw_trace", "sfw_meridian", "sfw_solaris", "sfw_blizzard", "sfw_cryon", "sfw_jotunn", "sfw_ymir", "sfw_thunderbolt", "sfw_acidrain", "sfw_fathom", "sfw_meteor", "sfw_vk21", "sfw_talon2", "sfw_talon"}

-- Weapons to put in the pool, class = price. Anything already priced by the gamemode (which is
-- every spawnable SWEP) needs no entry - use this for weapons that came out at 0, or to set your
-- own price. Example:
--     S.fieldTest.prices = { ["arc9_polyarm_ak"] = 1400 }
S.fieldTest.prices = S.fieldTest.prices or {}

-- Finishing a trial unlocks that weapon for the squad (the mission's own blurb promises "you may
-- keep the trial samples"). The addon needs `trialKills` enemy kills with the prototype to count it
-- done; that number is a file-local in its code, so it's mirrored here - change it if they change it.
S.fieldTest.unlockOnTrial = true
S.fieldTest.trialKills = 20

-- Getting a loose prototype back to the terminal that handed it out. A dropped one can end up in a
-- pit, in lava, or out in a firefight nobody wants to cross, and a one-shot weapon leaves no drop
-- at all - see the section further down for why that last one can make the mission unwinnable.
S.fieldTest.returnDelay = 30        -- seconds a dropped prototype lies untouched before it goes home
S.fieldTest.returnDistance = 200    -- ...and how far from its pedestal it has to be for that to mean anything
S.fieldTest.lostCheckInterval = 5   -- how often to check that each tester still holds their prototype
S.fieldTest.lostStrikes = 2         -- consecutive failed checks before calling it spent, so a weapon
                                    -- that blips out of the inventory for a tick isn't declared lost

if not SERVER then return end

local BL_PATH = "mapsweepers/server/ft_blacklist.json"

-- // The blacklist, as the extension stores it {{{
local function readBL()
	if not file.Exists(BL_PATH, "DATA") then return {} end
	local raw = file.Read(BL_PATH, "DATA")
	local tbl = raw and util.JSONToTable(raw)
	return istable(tbl) and tbl or {}
end

local function writeBL(tbl)
	file.CreateDir("mapsweepers")
	file.CreateDir("mapsweepers/server")
	file.Write(BL_PATH, util.TableToJSON(tbl))
	if jcms then jcms.ft_bl = tbl end -- the extension keeps its own copy in memory
end

function S.FieldTestBlacklist()
	return (jcms and istable(jcms.ft_bl)) and jcms.ft_bl or readBL()
end
-- }}}

-- // Pool {{{
-- Every weapon the terminal could hand out right now
function S.FieldTestPool()
	local bl, out = S.FieldTestBlacklist(), {}
	for class, price in pairs(jcms and jcms.weapon_prices or {}) do
		if (tonumber(price) or 0) > 0 and not bl[class] then out[#out + 1] = class end
	end
	table.sort(out)
	return out
end

-- Our own additions, applied once the gamemode has finished pricing everything
function S.FieldTestApplyPrices()
	if not (jcms and jcms.weapon_prices) then return 0 end

	local n = 0
	for class, price in pairs(S.fieldTest.prices) do
		price = math.floor(tonumber(price) or 0)
		if price > 0 and jcms.weapon_prices[class] ~= price then
			jcms.weapon_prices[class] = price
			n = n + 1
		end
	end

	if n > 0 and S.RefreshWeaponShop then S.RefreshWeaponShop() end
	return n
end

-- The gamemode prices weapons in a hook of its own, so this lands after it rather than racing it
hook.Add("InitPostEntity", "sweeper_fieldTest", function()
	timer.Simple(5, function()
		local n = S.FieldTestApplyPrices()
		if n > 0 then print(("[Field Trials] Priced %d extra weapon(s) into the pool."):format(n)) end

		-- The terminal's re-roll has no attempt limit: an empty pool locks the server up
		if #S.FieldTestPool() == 0 and next(S.FieldTestBlacklist()) then
			ErrorNoHalt("[Field Trials] Every priced weapon is blacklisted. The trial terminal would " ..
				"hang the server - clear some with sweeper_ft_remove <class> or sweeper_ft_clear.\n")
		end
	end)
end)
-- }}}

-- // Finished trials unlock the weapon {{{
-- The trial mission is jcms.missions.guntest from the Workshop extension. It tracks progress in
-- jcms.director.missionData.testing_data = { { npc_killed, testing_weapon, testing_weapon_name, ply } }
-- and has no hook of its own, so this watches that table instead of touching their addon.
local granted = {}

local function watchTrials()
	if not (S.fieldTest.unlockOnTrial and S.GunProgressEnabled and S.GunProgressEnabled()) then return end
	if not (jcms and jcms.director and jcms.director.missionData) then granted = {} return end

	local td = jcms.director.missionData.testing_data
	if not istable(td) then granted = {} return end

	local need = math.max(1, math.floor(tonumber(S.fieldTest.trialKills) or 20))
	for i, entry in ipairs(td) do
		local class = entry.testing_weapon
		if class and not granted[class] and (tonumber(entry.npc_killed) or 0) >= need then
			granted[class] = true

			local data = S.GunData and S.GunData()
			if data and not S.GunUnlocked(class) then
				data.unlocked[string.lower(class)] = true
				if S.GunSave then S.GunSave() end
				if S.GunRefreshPrices then S.GunRefreshPrices() end

				local name = entry.testing_weapon_name or class
				local msg = string.format("[Armory] Field trial passed - %s is unlocked for the squad.", name)
				if S.ChatPrintAll then S.ChatPrintAll(msg) else
					for j, ply in ipairs(player.GetAll()) do ply:ChatPrint(msg) end
				end
			end
		end
	end
end

timer.Create("sweeper_fieldTestWatch", 2, 0, function()
	local ok, err = pcall(watchTrials)
	if not ok then ErrorNoHalt("[Field Trials] trial watch: " .. tostring(err) .. "\n") end
end)
-- }}}

-- // Loose prototypes go back to their terminal {{{
-- Two holes in the extension, both fixed from out here - their addon is not touched.
--
--   1. A tester who dies or disconnects has a fresh jcms_testing_weapon dropped where they fell and
--      the entry's .ply cleared. Nothing ever retrieves that pickup, so a prototype that lands in a
--      pit, in lava, or in the middle of a firefight is gone for the rest of the mission.
--
--   2. A ONE-SHOT prototype (a grenade, a single-use launcher, anything that removes itself when
--      spent) leaves no drop at all. The entry still points at a living player who no longer holds
--      the weapon, so npc_killed can never reach the target; the mission needs every trial finished,
--      and isWeaponTesting() keeps that class from ever re-rolling. The mission becomes unwinnable.
--
-- Both end the same way: put the prototype back on the pedestal it came from, carrying the kills it
-- already earned, so whoever picks it up next carries on the same trial instead of starting over.

local homes = {}    -- weapon class -> the pedestal prop that dispensed it
local strikes = {}  -- weapon class -> consecutive checks where its tester didn't have it

-- The prefab returns the red prop as the terminal's entity; missionData keeps the list of them, and
-- the jcms_terminal beside each one points back at it with jcms_link.
local function pedestals()
	local md = jcms and jcms.director and jcms.director.missionData
	local list = md and md.guntest_terminals
	return istable(list) and list or {}
end

local function nearestPedestal(pos)
	local best, bestD
	for i, prop in ipairs(pedestals()) do
		if IsValid(prop) then
			local d = prop:GetPos():DistToSqr(pos)
			if not bestD or d < bestD then best, bestD = prop, d end
		end
	end
	return best, bestD and math.sqrt(bestD) or nil
end

-- Where the terminal itself puts a freshly dispensed prototype
local function homeSpot(prop)
	return prop:GetPos() + Vector(0, 0, 100)
end

local function spawnEffect(pos, ent)
	local ed = EffectData()
	ed:SetColor(jcms.util_colorIntegerJCorp)
	ed:SetFlags(1)
	ed:SetMagnitude(1)
	ed:SetOrigin(pos + Vector(0, 0, 156))
	ed:SetStart(pos + Vector(0, 0, -60))
	ed:SetEntity(ent)
	ed:SetScale(1)
	util.Effect("jcms_spawneffect", ed)
end

-- The world model, without the extension's habit of spawning the weapon just to read it back
local function worldModel(class)
	local tab = weapons.Get(class)
	local mdl = tab and (tab.WorldModel or tab.WM)
	if isstring(mdl) and mdl ~= "" then return mdl end

	local tmp = ents.Create(class)
	if not IsValid(tmp) then return "models/weapons/w_pistol.mdl" end
	tmp:Spawn()
	mdl = tmp:GetModel()
	tmp:Remove()
	return (isstring(mdl) and mdl ~= "") and mdl or "models/weapons/w_pistol.mdl"
end

-- HasWeapon alone would call it lost if a SWEP's real class differs in case from the priced key,
-- which would hand out a second copy while the tester still had theirs. Check both ways.
local function playerHolds(ply, class)
	if ply:HasWeapon(class) then return true end
	local want = string.lower(class)
	for i, w in ipairs(ply:GetWeapons()) do
		if IsValid(w) and string.lower(w:GetClass()) == want then return true end
	end
	return false
end

local function prototypeInWorld(class)
	for i, ent in ipairs(ents.FindByClass("jcms_testing_weapon")) do
		if IsValid(ent) and ent.wep_class == class then return true end
	end
	return false
end

-- Built the same shape the extension builds its own, because jcms_testing_weapon:Use only re-attaches
-- a pickup to a trial already in progress when its .kills equals that entry's npc_killed.
local function placeOnPedestal(class, name, kills, prop)
	if not (IsValid(prop) and isstring(class)) then return false end

	local wep = ents.Create("jcms_testing_weapon")
	if not IsValid(wep) then return false end

	local pos = homeSpot(prop)
	wep.wep_class = class
	wep.PrintName = name or class
	wep.kills = kills
	wep:SetModel(worldModel(class))
	wep:SetPos(pos)
	wep:Spawn()

	wep.sweeperHome = prop
	wep.sweeperDroppedAt = CurTime()
	homes[class] = prop
	prop.wep_given = true -- there's a weapon on it again, so the "collected" objective still counts it

	spawnEffect(pos, wep)
	return true
end
S.FieldTestReturn = placeOnPedestal
S.FieldTestHolds = playerHolds
S.FieldTestInWorld = prototypeInWorld

-- How many pedestals have handed a prototype out (what the mission's "collected" objective counts)
function S.FieldTestDispensed()
	local n = 0
	for i, prop in ipairs(pedestals()) do
		if IsValid(prop) and prop.wep_given then n = n + 1 end
	end
	return n
end

-- Remember where each prototype belongs the moment it appears. The terminal spawns one directly above
-- its own pedestal, so for that one the nearest pedestal is the right answer; a corpse drop is
-- anywhere at all, and inherits whichever pedestal its class was dispensed from.
hook.Add("OnEntityCreated", "sweeper_fieldTestHome", function(ent)
	if not IsValid(ent) or ent:GetClass() ~= "jcms_testing_weapon" then return end

	timer.Simple(0, function() -- wep_class and the position are set after Initialize
		if not IsValid(ent) then return end
		ent.sweeperDroppedAt = CurTime()

		local class = ent.wep_class
		if not isstring(class) then return end

		local prop, dist = nearestPedestal(ent:GetPos())
		if prop and dist and dist <= (tonumber(S.fieldTest.returnDistance) or 200) then
			homes[class] = prop -- dispensed right here
			ent.sweeperHome = prop
		else
			ent.sweeperHome = IsValid(homes[class]) and homes[class] or prop
		end
	end)
end)

-- A prototype nobody has picked up goes home. Moving the entity rather than replacing it keeps the
-- kills it is carrying and its entry in the director's tag list.
local function returnIdle()
	local delay = tonumber(S.fieldTest.returnDelay) or 30
	if delay <= 0 then return end
	local far = tonumber(S.fieldTest.returnDistance) or 200

	for i, ent in ipairs(ents.FindByClass("jcms_testing_weapon")) do
		local prop = IsValid(ent) and ent.sweeperHome
		if IsValid(prop) and (CurTime() - (ent.sweeperDroppedAt or CurTime())) >= delay then
			local pos = homeSpot(prop)
			-- One already sitting on its own pedestal has nowhere to go
			if ent:GetPos():DistToSqr(pos) > far * far then
				ent:SetPos(pos)
				local phys = ent:GetPhysicsObject()
				if IsValid(phys) then
					phys:SetVelocity(Vector(0, 0, 0))
					phys:SetAngleVelocity(Vector(0, 0, 0))
					phys:Wake()
				end
				ent.sweeperDroppedAt = CurTime() -- so one that rolls off isn't teleported every tick
				spawnEffect(pos, ent)
			end
		end
	end
end

-- A tester who is alive and no longer holding their prototype spent it. Put it back so the trial,
-- and the mission, can carry on.
local function returnLost()
	if not (jcms and jcms.director and jcms.director.missionData) then
		homes, strikes = {}, {}
		return
	end

	local td = jcms.director.missionData.testing_data
	if not istable(td) then homes, strikes = {}, {} return end

	local need = math.max(1, math.floor(tonumber(S.fieldTest.trialKills) or 20))
	local limit = math.max(1, math.floor(tonumber(S.fieldTest.lostStrikes) or 2))

	for i, entry in ipairs(td) do
		local class, ply = entry.testing_weapon, entry.ply
		local done = (tonumber(entry.npc_killed) or 0) >= need

		-- ply == nil means the extension has already dealt with it (death, disconnect) and dropped
		-- the pickup itself, so there's nothing here to recover.
		if isstring(class) and not done and ply ~= nil then
			local isPly = IsValid(ply) and ply:IsPlayer()
			local lost
			if not isPly then
				lost = true                     -- the entry points at something that is no longer a player
			elseif not ply:Alive() then
				lost = false                    -- dead: their PlayerDeath hook drops it and clears .ply
			else
				lost = not playerHolds(ply, class) -- alive and empty-handed: they used it up
			end

			if not lost then
				strikes[class] = 0
			else
				strikes[class] = (strikes[class] or 0) + 1
				if strikes[class] >= limit then
					if prototypeInWorld(class) then
						-- One is already lying around, so don't make a second. Releasing the entry is
						-- still the repair: with .ply cleared, that pickup can re-attach to this trial
						-- instead of the entry sitting here pointing at someone who hasn't got it.
						entry.ply = nil
						strikes[class] = 0
					else
						local prop = IsValid(homes[class]) and homes[class]
							or nearestPedestal(isPly and ply:GetPos() or Vector(0, 0, 0))

						if placeOnPedestal(class, entry.testing_weapon_name, entry.npc_killed, prop) then
							entry.ply = nil
							strikes[class] = 0

							local msg = string.format("[Field Trials] %s was used up - a replacement is back on its terminal (%d/%d kills kept).",
								entry.testing_weapon_name or class, tonumber(entry.npc_killed) or 0, need)
							if S.ChatPrintAll then S.ChatPrintAll(msg) else
								for j, p in ipairs(player.GetAll()) do p:ChatPrint(msg) end
							end
						end
					end
				end
			end
		end
	end
end

timer.Create("sweeper_fieldTestReturn", 1, 0, function()
	local ok, err = pcall(returnIdle)
	if not ok then ErrorNoHalt("[Field Trials] idle return: " .. tostring(err) .. "\n") end
end)

timer.Create("sweeper_fieldTestLost", math.max(1, tonumber(S.fieldTest.lostCheckInterval) or 5), 0, function()
	local ok, err = pcall(returnLost)
	if not ok then ErrorNoHalt("[Field Trials] lost check: " .. tostring(err) .. "\n") end
end)
-- }}}

-- // Commands {{{
local function adminOnly(ply)
	if not IsValid(ply) then return true end
	if ply:IsAdmin() then return true end
	if S.PrintConsole then S.PrintConsole(ply, "[Field Trials] Admins only.") end
	return false
end

local function say(ply, text)
	if S.PrintConsole then S.PrintConsole(ply, text) else print(text) end
end

concommand.Add("sweeper_ft_pool", function(ply, cmd, args)
	if not adminOnly(ply) then return end

	local pool = S.FieldTestPool()
	local show = math.Clamp(tonumber(args[1]) or 25, 1, 200)
	local lines = {
		string.format("--- Field Trials pool: %d weapon(s) can roll ---", #pool),
		string.format("  blacklisted: %d    (the pool is jcms.weapon_prices minus the blacklist)", table.Count(S.FieldTestBlacklist())),
	}
	if #pool == 0 then
		lines[#lines + 1] = "  WARNING: nothing can roll. The terminal's re-roll loop has no limit and would hang the server."
	end
	for i = 1, math.min(show, #pool) do
		lines[#lines + 1] = string.format("  %-34s %d", pool[i], jcms.weapon_prices[pool[i]] or 0)
	end
	if #pool > show then lines[#lines + 1] = string.format("  ... and %d more", #pool - show) end
	say(ply, table.concat(lines, "\n"))
end, nil, "Admin: how many weapons the Field Trials terminal can hand out.")

concommand.Add("sweeper_ft_list", function(ply)
	if not adminOnly(ply) then return end

	local bl, ids = S.FieldTestBlacklist(), {}
	for class in pairs(bl) do ids[#ids + 1] = class end
	table.sort(ids)

	local lines = { string.format("--- Field Trials blacklist (%d) ---", #ids) }
	for i, class in ipairs(ids) do lines[#lines + 1] = "  " .. class end
	if #ids == 0 then lines[#lines + 1] = "  (empty - every priced weapon can roll)" end
	say(ply, table.concat(lines, "\n"))
end, nil, "Admin: show the Field Trials blacklist.")

concommand.Add("sweeper_ft_add", function(ply, cmd, args)
	if not adminOnly(ply) then return end
	local class = string.lower(string.Trim(tostring(args[1] or "")))
	if class == "" then say(ply, "[Field Trials] Usage: sweeper_ft_add <weapon class>") return end

	local bl = S.FieldTestBlacklist()
	bl[class] = true
	writeBL(bl)

	local left = #S.FieldTestPool()
	say(ply, string.format("[Field Trials] %s blacklisted. %d weapon(s) can still roll.%s", class, left,
		left == 0 and "  WARNING: an empty pool hangs the terminal." or ""))
end, nil, "Admin: keep a weapon out of Field Trials.")

concommand.Add("sweeper_ft_remove", function(ply, cmd, args)
	if not adminOnly(ply) then return end
	local class = string.lower(string.Trim(tostring(args[1] or "")))
	if class == "" then say(ply, "[Field Trials] Usage: sweeper_ft_remove <weapon class>") return end

	local bl = S.FieldTestBlacklist()
	if not bl[class] then say(ply, "[Field Trials] " .. class .. " isn't blacklisted.") return end

	bl[class] = nil
	writeBL(bl)
	say(ply, string.format("[Field Trials] %s can roll again. Pool: %d.", class, #S.FieldTestPool()))
end, nil, "Admin: put a weapon back into Field Trials.")

concommand.Add("sweeper_ft_clear", function(ply)
	if not adminOnly(ply) then return end
	writeBL({})
	say(ply, string.format("[Field Trials] Blacklist cleared. Pool: %d.", #S.FieldTestPool()))
end, nil, "Admin: empty the Field Trials blacklist.")
-- }}}

concommand.Add("sweeper_ft_trials", function(ply)
	if not adminOnly(ply) then return end

	local md = jcms and jcms.director and jcms.director.missionData
	local td = md and md.testing_data
	if not istable(td) then say(ply, "[Field Trials] No trial mission running.") return end

	local need = math.max(1, math.floor(tonumber(S.fieldTest.trialKills) or 20))
	local lines = { string.format("--- Field Trials (%d/%d terminals dispensed) ---",
		S.FieldTestDispensed(), md.guntest_terminals_count or 0) }

	for i, entry in ipairs(td) do
		local class = entry.testing_weapon or "?"
		local who = IsValid(entry.ply) and entry.ply:Nick() or (entry.ply == nil and "-- loose --" or "?? stale ??")
		local held = IsValid(entry.ply) and entry.ply:IsPlayer() and S.FieldTestHolds(entry.ply, class)
		lines[#lines + 1] = string.format("  %-28s %2d/%d kills  tester: %-20s %s%s",
			class, tonumber(entry.npc_killed) or 0, need, who,
			IsValid(entry.ply) and (held and "holding" or "NOT HOLDING") or "",
			S.FieldTestInWorld(class) and "  [a pickup is on the map]" or "")
	end

	if #td == 0 then lines[#lines + 1] = "  (nothing dispensed yet)" end
	lines[#lines + 1] = string.format("  return after %ds idle / %ds further than %d units from its pedestal",
		S.fieldTest.returnDelay or 30, S.fieldTest.returnDelay or 30, S.fieldTest.returnDistance or 200)

	local text = table.concat(lines, "\n")
	if S.PrintConsole and IsValid(ply) then S.PrintConsole(ply, text) else print(text) end
end, nil, "Admin: show every Field Trial in progress and whether its tester still holds the prototype.")
