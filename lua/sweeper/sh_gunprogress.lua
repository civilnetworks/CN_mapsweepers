--[[
	Map Sweepers - Implants & Class Levels (addon)
	Gun unlocks earned by the team winning missions. Shared by the whole squad, and per RUN.

	This is a SECOND unlock axis, next to the Armory Access Team Upgrade in sh_group.lua:
		Armory Access   bought with V Tokens, resets every run.
		This file       earned by winning missions, resets every run.

	Every win opens the next batch of weapons in the shop - a random 5 to 15 of them
	(S.gunProgress.batchMin / batchMax; set both the same for a fixed batch).

	WHEN THE RUN ENDS EVERYTHING LOCKS AGAIN, back to the starting list. The gamemode's own
	jcms.runprogress_Reset is the signal - a failed mission (winstreak to 0), or a dedicated server
	sitting empty for 1.5 hours - the same signal that wipes implants and team upgrades. It does not
	go through the implant `reset_on_gameover` convar: guns always reset with the run.

	OFF BY DEFAULT. `sweeper_gununlocks 0` (the default) means every weapon is buyable exactly
	as before - that's the "keep all guns unlocked for now" state until the starting list below is
	written. Wins and unlocks are still recorded while it's off, so flipping it on later doesn't
	throw away what the server has already earned.

	TO TURN IT ON
	  1. Fill in S.gunProgress.starting  - the guns the server starts with.
	  2. Fill in S.gunProgress.order     - the order the rest unlock in (leave empty for
	                                       cheapest-first out of jcms.weapon_prices).
	  3. Tune batchMin / batchMax        - weapons per win.
	  4. sweeper_gununlocks 1

	Data: data/sweeper_guns/server.json  ->  { wins = n, unlocked = { class = true } }
	One file for the whole squad, not one per player, so a player joining mid-run walks into whatever
	the squad has already opened. It's on disk only so a server restart mid-run doesn't cost the
	squad their progress; the run ending clears it.

	LOCKED GUNS ARE SHOWN, NOT HIDDEN. A locked weapon sits in the lobby shop in its usual place with a
	padlock over it, so you can see what the squad is playing for. They used to be deleted from the price
	table instead, which had two problems: the client couldn't tell "not unlocked yet" from "doesn't
	exist" (so it couldn't draw a lock), and lock state was expressed as ABSENCE. Absence is a bad way to
	network state - the gamemode's WLD_WEAPON_PRICES handler MERGES what it receives and never removes,
	so once a client's view was wrong nothing could put it right, which is exactly what "the weapons I
	unlocked are still missing next map" looks like. The server now states the lock set outright.

	HOW IT'S ENFORCED (no gamemode edit) - with its own markers so it stacks with Armory Access:
	  - jcms.spawnmenu_PurchaseLoadoutGun / _PurchaseAndGiveGun are wrapped and refuse a locked gun.
	    That's the authority: the server decides, whatever the client sends.
	  - sweeper_gunlocks carries the locked class list to clients: on net ready (so a fresh map or a
	    mid-run joiner gets it), and again whenever a batch opens or the run resets.
	  - Client: jcms.paint_Gun is wrapped to dim a locked gun, stamp a padlock on it and mark it
	    unaffordable, which is also what stops the shop's own DoClick from trying to buy it.
	  - Client: the in-mission shop terminal is one monolithic draw function with no per-weapon hook,
	    so locked guns stay hidden there (jcms.weapon_prices is swapped for a filtered copy for the
	    length of the call) rather than showing up as buyable.

	Admin: sweeper_guns_status                 sweeper_guns_grant <count>
	       sweeper_guns_unlock <class|all>     sweeper_guns_lock <class|all>
	       sweeper_guns_reset  (lock everything, as if the run had ended)
--]]

local S = sweeper

S.gunProgress = {
	-- ==========================================================================================
	-- HAND-WRITTEN LIST - the guns the squad starts every run with. Empty = nothing is open up
	-- front, which with the system ON means every weapon on the server is locked until the first
	-- win. Either spelling is read, so write it whichever way reads better:
	--     starting = { "weapon_pistol", "weapon_smg1" }      -- a plain list
	--     starting = { weapon_pistol = true }                -- or a set
	-- Check it took with `sweeper_guns_starting` in console.
	-- ==========================================================================================
	starting = {"weapon_pistol","weapon_357","weapon_crossbow","weapon_shotgun","weapon_frag","weapon_ar2","weapon_slam","weapon_rpg","weapon_smg1", "arc9_doi_m1919", "arc9_doi_m1911", "arc9_doi_springfield", "arc9_doi_m3", "arc9_doi_panzerfaust", "arc9_doi_mg34", "arc9_doi_luger", "arc9_doi_k98", "arc9_doi_mp40", "arc9_doi_bren", "arc9_doi_enfield", "arc9_doi_sten", "arc9_cod2019_ar_fal", "arc9_cod2019_ar_kilo141", "arc9_cod2019_ar_m4", "arc9_cod2019_pi_m19", "arc9_cod2019_pi_x16", "arc9_cod2019_la_pila", "arc9_cod2019_nade_c4", "arc9_cod2019_nade_frag", "arc9_cod2019_nade_knife", "arc9_cod2019_lm_pkm", "arc9_cod2019_mm_m14", "arc9_cod2019_me_shield", "arc9_cod2019_sh_r90", "arc9_cod2019_sn_svd", "arc9_cod2019_sm_p90", "arc9_cod2019_nade_flash", "arc9_cod2019_nade_smoke", "arc9_uplp_ak", "arc9_uplp_ar15", "arc9_uplp_sr25", "arc9_uplp_m249", "arc9_uplp_2011", "arc9_uplp_m9", "arc9_uplp_panzerfaust", "arc9_uplp_dbs", "arc9_uplp_spas", "arc9_uplp_awp", "arc9_uplp_ak_smg", "arc9_uplp_mp9" },

	-- Unlock order. Empty = cheapest first, from jcms.weapon_prices (deterministic: price, then name).
	order = {},

	batchMin = 5,       -- weapons opened per win, low end
	batchMax = 15,      -- ...and high end. Equal values = a fixed batch size.
	announce = true,    -- print the batch to chat when it opens
}

local CVAR = "sweeper_gununlocks"

if SERVER then
	util.AddNetworkString("sweeper_gunlocks")
	CreateConVar(CVAR, "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"1 = shop weapons unlock as the team wins missions. 0 = every weapon is buyable (default).")
end

function S.GunProgressEnabled()
	local cv = GetConVar(CVAR)
	return cv ~= nil and cv:GetBool()
end

-- // Lists {{{
local function startingSet()
	local out, list = {}, S.gunProgress.starting or {}

	-- Read both spellings. It used to be ipairs only, so writing the list as a set - the obvious way
	-- to write a list of flags - parsed to nothing at all and locked the whole armory without a word
	-- about why. pairs() skips the array part here because those keys are numbers, so a list written
	-- either way, or half each, comes out the same.
	for i = 1, #list do
		if isstring(list[i]) then out[string.lower(list[i])] = true end
	end
	for class, on in pairs(list) do
		if isstring(class) and on then out[string.lower(class)] = true end
	end
	return out
end
S.GunStartingSet = startingSet

-- Every gun that can be earned, in the order they're earned in.
function S.GunUnlockOrder()
	if #(S.gunProgress.order or {}) > 0 then return S.gunProgress.order end

	local list = {}
	for class, price in pairs(jcms and jcms.weapon_prices or {}) do
		list[#list + 1] = { class = class, price = tonumber(price) or 0 }
	end
	table.sort(list, function(a, b)
		if a.price == b.price then return a.class < b.class end
		return a.price < b.price
	end)

	local out = {}
	for i, e in ipairs(list) do out[i] = e.class end
	return out
end
-- }}}

if SERVER then

-- // Saved progress (one file for the server) {{{
	local DIR = "sweeper_guns"
	local PATH = DIR .. "/server.json"
	file.CreateDir(DIR)

	local data -- { wins = n, unlocked = { class = true } }

	function S.GunData()
		if data then return data end

		data = { wins = 0, unlocked = {} }
		local raw = file.Read(PATH, "DATA")
		if raw then
			local t = util.JSONToTable(raw)
			if istable(t) then
				data.wins = tonumber(t.wins) or 0
				if istable(t.unlocked) then
					for class, v in pairs(t.unlocked) do
						if v then data.unlocked[string.lower(tostring(class))] = true end
					end
				end
			end
		end
		return data
	end

	function S.GunSave()
		if data then file.Write(PATH, util.TableToJSON(data)) end
	end
-- }}}

-- // Unlock state {{{
	function S.GunUnlocked(class)
		if not S.GunProgressEnabled() then return true end

		class = string.lower(tostring(class or ""))
		if class == "" then return true end
		if startingSet()[class] then return true end

		return S.GunData().unlocked[class] == true
	end

	-- Opens the next n guns in order. Returns the classes it opened.
	function S.GrantGunUnlocks(n)
		n = math.floor(tonumber(n) or 0)
		if n <= 0 then return {} end

		local d, start, granted = S.GunData(), startingSet(), {}
		for i, class in ipairs(S.GunUnlockOrder()) do
			if n <= 0 then break end
			local id = string.lower(class)
			if not d.unlocked[id] and not start[id] then
				d.unlocked[id] = true
				granted[#granted + 1] = class
				n = n - 1
			end
		end

		if #granted > 0 then S.GunSave() end
		return granted
	end

	function S.GunLockedCount()
		local d, start, locked = S.GunData(), startingSet(), 0
		for i, class in ipairs(S.GunUnlockOrder()) do
			local id = string.lower(class)
			if not d.unlocked[id] and not start[id] then locked = locked + 1 end
		end
		return locked
	end

	local function weaponName(class)
		if S.WeaponName then
			local ok, name = pcall(S.WeaponName, class)
			if ok and name and name ~= "" then return name end
		end
		return class
	end

	-- Tells clients exactly which weapons are locked. `to` may be a player, a table of them, or nil/"all"
	-- for everyone. Compressed the same way the gamemode sends its price table, because the list is every
	-- gun on the server at the start of a run.
	function S.GunSendLocks(to)
		local on, list = S.GunProgressEnabled(), {}
		if on then
			for class in pairs(jcms and jcms.weapon_prices or {}) do
				if not S.GunUnlocked(class) then list[#list + 1] = class end
			end
		end

		local compressed = util.Compress(util.TableToJSON(list)) or ""
		if #compressed > 60000 then
			-- Past the net message limit. Shouldn't be reachable, but send "nothing locked" rather than
			-- a message that errors out and leaves clients with no lock data at all.
			ErrorNoHalt(string.format("[sweeper] gun lock list too big to send (%d bytes, %d guns)\n", #compressed, #list))
			compressed, on = "", false
		end

		net.Start("sweeper_gunlocks")
			net.WriteBool(on)
			net.WriteUInt(#compressed, 16)
			if #compressed > 0 then net.WriteData(compressed, #compressed) end
		if to == nil or to == "all" then net.Broadcast() else net.Send(to) end
	end

	-- Re-send prices and locks so a batch shows up in the shop without anyone reconnecting
	local function refreshShop()
		if jcms and jcms.net_SendWeaponPrices and jcms.weapon_prices then
			jcms.net_SendWeaponPrices(jcms.weapon_prices, player.GetAll())
		end
		S.GunSendLocks()
	end
	S.GunRefreshPrices = refreshShop
-- }}}

-- // Earning them: a batch per win {{{
-- Recorded even while the system is switched off, so turning it on later doesn't start the server
-- from zero. Wraps jcms.mission_End the same way the V Token payout does.
	local function missionComplete(victory)
		if not victory then return end

		local d = S.GunData()
		d.wins = (d.wins or 0) + 1

		local lo = math.max(0, math.floor(tonumber(S.gunProgress.batchMin) or 0))
		local hi = math.max(lo, math.floor(tonumber(S.gunProgress.batchMax) or lo))
		local granted = S.GrantGunUnlocks(math.random(lo, hi))
		S.GunSave()

		if not S.GunProgressEnabled() then return end

		if #granted > 0 then
			refreshShop()
			if S.gunProgress.announce then
				local names = {}
				for i, class in ipairs(granted) do names[i] = weaponName(class) end
				local msg = string.format("[Armory] Mission won - %d new weapon%s in the shop: %s",
					#granted, #granted == 1 and "" or "s", table.concat(names, ", "))
				if S.ChatPrintAll then S.ChatPrintAll(msg) else
					for i, ply in ipairs(player.GetAll()) do ply:ChatPrint(msg) end
				end
			end
		elseif S.gunProgress.announce and S.ChatPrintAll then
			S.ChatPrintAll("[Armory] Mission won - every weapon is already unlocked.")
		end
	end

	-- Run over: back to the starting list. Called from the jcms.runprogress_Reset wrap below, which is
	-- the gamemode's own "the run is over" signal (failed mission, or an empty dedicated server).
	function S.GunRunReset()
		local d = S.GunData()
		local had = table.Count(d.unlocked)

		d.wins = 0
		d.unlocked = {}
		S.GunSave()
		refreshShop()

		if had > 0 and S.GunProgressEnabled() and S.gunProgress.announce then
			local msg = string.format("[Armory] The run is over - %d unlocked weapon%s locked again.",
				had, had == 1 and " is" or "s are")
			if S.ChatPrintAll then S.ChatPrintAll(msg) else
				for i, ply in ipairs(player.GetAll()) do ply:ChatPrint(msg) end
			end
		end
	end

	function S.InstallGunRunReset()
		if not (jcms and jcms.runprogress_Reset) or S.Wrapped(jcms, "GunRunReset") then return end
		local orig = jcms.runprogress_Reset
		S._wrappedGunRunReset = function(...)
			local rtn = { orig(...) }
			local ok, err = pcall(S.GunRunReset)
			if not ok then ErrorNoHalt("[sweeper] gun unlock reset: " .. tostring(err) .. "\n") end
			return unpack(rtn)
		end
		jcms.runprogress_Reset = S._wrappedGunRunReset
		S.MarkWrapped(jcms, "GunRunReset")
	end

	function S.InstallGunMissionEnd()
		if not (jcms and jcms.mission_End) or S.Wrapped(jcms, "GunMissionEnd") then return end
		local orig = jcms.mission_End
		S._wrappedGunMissionEnd = function(victory, ...)
			local rtn = { orig(victory, ...) }
			local ok, err = pcall(missionComplete, victory)
			if not ok then ErrorNoHalt("[sweeper] gun unlocks: " .. tostring(err) .. "\n") end
			return unpack(rtn)
		end
		jcms.mission_End = S._wrappedGunMissionEnd
		S.MarkWrapped(jcms, "GunMissionEnd")
	end
-- }}}

-- // Enforcement {{{
	function S.InstallGunLocks()
		if not jcms then return end

		-- The server decides what may be bought
		local function blockLocked(fname)
			local current = jcms[fname]
			if not current or S.Wrapped(jcms, "GunLock_" .. fname) then return end

			S._wrappedGunBuy = S._wrappedGunBuy or {}
			local wrapped = function(ply, class, ...)
				if S.GunProgressEnabled() and not S.GunUnlocked(class) then
					if IsValid(ply) then
						ply:ChatPrint(string.format("[Armory] %s isn't unlocked yet - the squad opens more weapons by winning missions.",
							weaponName(class)))
					end
					return false
				end
				return current(ply, class, ...)
			end

			S._wrappedGunBuy[fname] = wrapped
			jcms[fname] = wrapped
			S.MarkWrapped(jcms, "GunLock_" .. fname)
		end
		blockLocked("spawnmenu_PurchaseLoadoutGun")
		blockLocked("spawnmenu_PurchaseAndGiveGun")

		-- Prices are NOT filtered any more: a locked gun keeps its real price so the client can show it
		-- with a padlock on it. The lock set goes over sweeper_gunlocks instead, and the purchase wraps
		-- above are what actually stop a locked gun being bought.
	end

	-- Every fresh map and every mid-run joiner gets the lock set here. Slightly delayed so it lands
	-- after the gamemode's own price send, which is what the client's shop is built from.
	hook.Add("jcms_PlayerNetReady", "sweeper_gunProgress", function(ply)
		timer.Simple(0.5, function()
			if IsValid(ply) then S.GunSendLocks(ply) end
		end)
	end)

	-- Flipping the system live has to reach clients too, or their shops keep the old locks
	cvars.AddChangeCallback(CVAR, function()
		timer.Simple(0, function() S.GunSendLocks() end)
	end, "sweeper_gunProgress")

	-- "Every weapon is locked" should never again be something you find out by squinting at the shop.
	-- Delayed so jcms.weapon_prices is built and the convar's archived value has settled.
	hook.Add("InitPostEntity", "sweeper_gunProgressWarn", function()
		timer.Simple(5, function()
			if not S.GunProgressEnabled() or table.Count(startingSet()) > 0 then return end
			ErrorNoHalt("[sweeper] gun unlocks are ON but the starting weapon list is EMPTY, so every " ..
				"weapon on this server is locked until the squad wins a mission. Fill S.gunProgress.starting " ..
				"in lua/sweeper/sh_gunprogress.lua, or run sweeper_gununlocks 0. (sweeper_guns_status)\n")
		end)
	end)

	local function installAll()
		S.InstallGunLocks()
		S.InstallGunMissionEnd()
		S.InstallGunRunReset()
	end
	hook.Add("Initialize", "sweeper_gunProgress", installAll)
	hook.Add("InitPostEntity", "sweeper_gunProgress", installAll)
-- }}}

-- // Admin commands {{{
	local function adminOnly(ply)
		if not IsValid(ply) then return true end
		if ply:IsAdmin() then return true end
		if S.PrintConsole then S.PrintConsole(ply, "[Armory] Admins only.") end
		return false
	end

	local function say(ply, text)
		if S.PrintConsole then S.PrintConsole(ply, text) else print(text) end
	end

	concommand.Add("sweeper_guns_status", function(ply)
		if not adminOnly(ply) then return end

		local d, order, start = S.GunData(), S.GunUnlockOrder(), startingSet()
		local lines = {
			"--- Armory: gun unlocks (server-wide) ---",
			string.format("  system: %s", S.GunProgressEnabled() and "ON" or "OFF (everything buyable)"),
			string.format("  wins this run: %d    batch per win: %d-%d    (all of it resets when the run ends)",
				d.wins or 0, S.gunProgress.batchMin or 0, S.gunProgress.batchMax or 0),
			string.format("  unlocked: %d    still locked: %d    of %d in the order",
				table.Count(d.unlocked), S.GunLockedCount(), #order),
		}

		local nextUp = {}
		for i, class in ipairs(order) do
			local id = string.lower(class)
			if not d.unlocked[id] and not start[id] then
				nextUp[#nextUp + 1] = class
				if #nextUp >= 8 then break end
			end
		end
		lines[#lines + 1] = "  next up: " .. (#nextUp > 0 and table.concat(nextUp, ", ") or "nothing left")
		lines[#lines + 1] = string.format("  starting list: %d weapon(s) open from the start of every run", table.Count(start))
		if table.Count(start) == 0 then
			lines[#lines + 1] = "  WARNING: the starting list is empty, so EVERY weapon is locked until the squad wins."
			lines[#lines + 1] = "           Fill S.gunProgress.starting in lua/sweeper/sh_gunprogress.lua, or sweeper_gununlocks 0."
		end
		say(ply, table.concat(lines, "\n"))
	end, nil, "Admin: show the server's gun unlock progress.")

	-- Prints what the game actually parsed out of S.gunProgress.starting, so a list that didn't take
	-- shows up as an empty list here instead of as a shop full of padlocks.
	concommand.Add("sweeper_guns_starting", function(ply)
		if not adminOnly(ply) then return end

		local start, names = startingSet(), {}
		for class in pairs(start) do names[#names + 1] = class end
		table.sort(names)

		local missing = {}
		for i, class in ipairs(names) do
			if not (jcms and jcms.weapon_prices and jcms.weapon_prices[class]) then missing[#missing + 1] = class end
		end

		local lines = {
			string.format("--- Armory: starting list (%d weapon%s) ---", #names, #names == 1 and "" or "s"),
			"  " .. (#names > 0 and table.concat(names, ", ") or "EMPTY - every weapon is locked until the squad wins."),
		}
		if #missing > 0 then
			lines[#lines + 1] = string.format("  %d of these aren't weapons this server has (typo or missing addon): %s",
				#missing, table.concat(missing, ", "))
		end
		say(ply, table.concat(lines, "\n"))
	end, nil, "Admin: show the parsed starting weapon list.")

	concommand.Add("sweeper_guns_grant", function(ply, cmd, args)
		if not adminOnly(ply) then return end
		local granted = S.GrantGunUnlocks(tonumber(args[1]) or 1)
		refreshShop()
		say(ply, string.format("[Armory] Unlocked %s.", #granted > 0 and table.concat(granted, ", ") or "nothing (all done)"))
	end, nil, "Admin: open the next N weapons.")

	concommand.Add("sweeper_guns_unlock", function(ply, cmd, args)
		if not adminOnly(ply) then return end
		local class = string.lower(string.Trim(tostring(args[1] or "")))
		if class == "" then say(ply, "[Armory] Usage: sweeper_guns_unlock <weapon class|all>") return end

		local d = S.GunData()
		if class == "all" then
			for i, c in ipairs(S.GunUnlockOrder()) do d.unlocked[string.lower(c)] = true end
			say(ply, "[Armory] Everything unlocked.")
		else
			d.unlocked[class] = true
			say(ply, "[Armory] Unlocked " .. class .. ".")
		end
		S.GunSave()
		refreshShop()
	end, nil, "Admin: unlock one weapon (or all) for the server.")

	concommand.Add("sweeper_guns_lock", function(ply, cmd, args)
		if not adminOnly(ply) then return end
		local class = string.lower(string.Trim(tostring(args[1] or "")))
		if class == "" then say(ply, "[Armory] Usage: sweeper_guns_lock <weapon class|all>") return end

		local d = S.GunData()
		if class == "all" then
			d.unlocked = {}
			say(ply, "[Armory] Unlocks wiped (win count kept).")
		else
			d.unlocked[class] = nil
			say(ply, "[Armory] Locked " .. class .. ".")
		end
		S.GunSave()
		refreshShop()
	end, nil, "Admin: lock one weapon (or all) again.")

	concommand.Add("sweeper_guns_reset", function(ply)
		if not adminOnly(ply) then return end
		S.GunRunReset()
		say(ply, "[Armory] Unlocks reset to the starting list, as if the run had ended.")
	end, nil, "Admin: lock every weapon again (what happens when a run ends).")
-- }}}

end

if CLIENT then

-- // What the server says is locked {{{
	-- One table, replaced outright every time the server speaks, so the client's view can't drift the
	-- way it did when locks were expressed by deleting guns from the price table.
	S.gunLocks = S.gunLocks or { enabled = false, locked = {}, version = 0 }

	function S.GunLockedCl(class)
		local g = S.gunLocks
		if not g.enabled then return false end
		return g.locked[string.lower(tostring(class or ""))] == true
	end

	net.Receive("sweeper_gunlocks", function()
		local g = S.gunLocks
		local on = net.ReadBool()
		local size = net.ReadUInt(16)
		local raw = size > 0 and net.ReadData(size) or nil

		local list
		if raw then
			local json = util.Decompress(raw)
			list = json and util.JSONToTable(json) or nil
		end

		g.enabled = on
		g.locked = {}
		if istable(list) then
			for i = 1, #list do g.locked[string.lower(tostring(list[i]))] = true end
		end
		g.version = (g.version or 0) + 1

		-- Belt and braces: the shop copies jcms.paint_Gun by value into every button it builds, so the
		-- wrap has to be in place before any shop panel exists. Both installs are marker-guarded, so
		-- this is a no-op once it has run.
		if S.InstallGunLockPaint then S.InstallGunLockPaint() end
		if S.InstallGunLockTerminal then S.InstallGunLockTerminal() end
		if S.InstallShopUnlockSort then S.InstallShopUnlockSort() end
	end)
-- }}}

-- // Padlock over the icon {{{
	local matLock = Material("jcms/lock.png", "smooth")

	function S.InstallGunLockPaint()
		if not (jcms and jcms.paint_Gun) or S.Wrapped(jcms, "GunLockPaint") then return end
		local orig = jcms.paint_Gun

		S._wrappedGunLockPaint = function(p, w, h, ...)
			-- cost below zero is the admin price editor, which isn't a shop and shouldn't grow padlocks
			local locked = (tonumber(p.cost) or 0) >= 0 and S.GunLockedCl(p.gunClass)

			if locked then
				-- Set BEFORE the original paints, so it already draws its unaffordable styling and, more
				-- to the point, so the shop's own DoClick (which refuses when cantAfford) won't buy it.
				-- The shop's Think resets this every frame, so it has to be re-set every frame too.
				p.cantAfford = true
				if not p.sweeperLockTip then
					p:SetTooltip("Locked - the squad opens more weapons by winning missions.")
					p.sweeperLockTip = true
				end
			elseif p.sweeperLockTip then
				p:SetTooltip(nil)
				p.sweeperLockTip = nil
			end

			local rtn = orig(p, w, h, ...)
			if not locked then return rtn end

			-- Dimmed rather than blanked out, so you can still tell which gun you're looking at
			local dark = jcms.color_dark
			surface.SetDrawColor(dark.r, dark.g, dark.b, 170)
			surface.DrawRect(0, 0, w, h)

			local s = math.floor(math.min(w, h) * 0.44)
			surface.SetMaterial(matLock)
			surface.SetDrawColor(jcms.color_bright)
			surface.DrawTexturedRect((w - s) / 2, (h - s) / 2 - h * 0.08, s, s)

			-- The price sits in the right half of the bottom strip, so this goes in the left half. On the
			-- lowres 48px buttons the word is wider than that half, so there the padlock speaks for itself.
			if w >= 64 then
				draw.SimpleText("LOCKED", "Default", w / 4, h - 8, jcms.color_bright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			return rtn
		end

		jcms.paint_Gun = S._wrappedGunLockPaint
		S.MarkWrapped(jcms, "GunLockPaint")
	end
-- }}}

-- // jcms.weapon_prices with the locked guns taken out {{{
	-- Some gamemode code walks the whole price table and treats everything in it as buyable. Rather
	-- than reimplement those (and have the copy drift from the original), the table is swapped for a
	-- filtered one for the length of the call. Cached, and rebuilt only when the prices or the lock
	-- set actually change, because a couple of the callers run every frame.
	--
	-- Returns jcms.weapon_prices itself when there's nothing to filter, so callers can compare by
	-- identity to skip the swap entirely.
	local unlockedPrices, upHash, upVersion = {}, nil, -1

	function S.GunUnlockedPrices()
		if not (S.gunLocks.enabled and istable(jcms.weapon_prices)) then return jcms.weapon_prices end

		local hash = jcms.util_Hash and jcms.util_Hash(jcms.weapon_prices) or nil
		if hash ~= upHash or upVersion ~= S.gunLocks.version then
			upHash, upVersion = hash, S.gunLocks.version
			unlockedPrices = {}
			for class, price in pairs(jcms.weapon_prices) do
				if not S.GunLockedCl(class) then unlockedPrices[class] = price end
			end
		end
		return unlockedPrices
	end

	-- Runs fn with the locked guns missing from jcms.weapon_prices, restoring the real table in every
	-- path including the error one, and passing fn's return values back through.
	--
	-- An empty filtered table is passed through as-is rather than treated as a failure: the shop
	-- terminal still has to draw its frame when the squad has nothing unlocked. Callers that need to
	-- do something else in that case check for it themselves.
	function S.WithUnlockedPrices(label, fn, ...)
		local prices = S.GunUnlockedPrices()
		if prices == jcms.weapon_prices then return fn(...) end

		local real = jcms.weapon_prices
		jcms.weapon_prices = prices
		local rtn = { pcall(fn, ...) }
		jcms.weapon_prices = real

		if not rtn[1] then
			ErrorNoHalt("[sweeper] " .. tostring(label) .. ": " .. tostring(rtn[2]) .. "\n")
			return
		end
		return unpack(rtn, 2)
	end

	-- Nothing at all buyable right now (the system is on and every gun is still locked)
	function S.GunNothingUnlocked()
		if not S.gunLocks.enabled then return false end
		return next(S.GunUnlockedPrices()) == nil
	end
-- }}}

-- // In-mission shop terminal {{{
	-- That terminal draws its whole weapon grid inline, with no per-weapon hook to stamp a padlock onto,
	-- so locked guns stay hidden there instead of sitting around looking buyable.
	function S.InstallGunLockTerminal()
		local terms = jcms and jcms.terminal_modeTypes
		if not (terms and isfunction(terms.shop)) or S.Wrapped(jcms, "GunLockShop") then return end
		local orig = terms.shop

		S._wrappedGunLockShop = function(...)
			return S.WithUnlockedPrices("shop terminal", orig, ...)
		end

		terms.shop = S._wrappedGunLockShop
		S.MarkWrapped(jcms, "GunLockShop")
	end
-- }}}

-- // "Unlocked first" in the lobby shop's Sort by dropdown {{{
	-- The gamemode's sort modes are 1-7 and its GetSortFunc switches on shop.sortMode, so ours takes a
	-- number well clear of theirs - if they ever add an 8th, this still won't collide.
	local SORT_UNLOCKED = 101

	local function unlockSortFunc(first, last)
		local lf, ll = S.GunLockedCl(first), S.GunLockedCl(last)
		-- Locked guns sink to the bottom; within each group, by name. Comparing the booleans this way
		-- round means unlocked (false) comes first.
		if lf ~= ll then return ll end

		local sf, sl = jcms.gunstats_Get(first), jcms.gunstats_Get(last)
		return (sf and sf.name or first) < (sl and sl.name or last)
	end

	-- The dice button rolls a random affordable gun straight out of jcms.weapon_prices, which now has
	-- the locked ones in it, so it could hand you something you can't buy - the server would refuse it
	-- and you'd get a chat line instead of a weapon. Its own DoClick is wrapped with the price table
	-- filtered rather than rewritten, so the gamemode keeps owning the cash test and the weighting.
	local function addUnlockedRandomLoadout(tab)
		local dice = tab and tab.loadoutPnl and tab.loadoutPnl.randomLoadout
		if not (IsValid(dice) and isfunction(dice.DoClick)) or dice.sweeperUnlockedOnly then return end
		dice.sweeperUnlockedOnly = true

		local orig = dice.DoClick
		dice.DoClick = function(self, ...)
			if S.GunNothingUnlocked() then
				-- Say so rather than rolling a gun the server will only refuse
				surface.PlaySound("buttons/button10.wav")
				chat.AddText(jcms.color_bright_alt or color_white, "[Armory] ", color_white,
					"Nothing unlocked yet - the squad opens weapons by winning missions.")
				return
			end
			return S.WithUnlockedPrices("random loadout", orig, self, ...)
		end
	end

	local function addUnlockSort(tab)
		local pnl = tab and tab.loadoutPnl
		local shop, box = pnl and pnl.shop, pnl and pnl.sortComboBox
		if not (IsValid(shop) and IsValid(box)) then return end
		if shop.sweeperUnlockSort then return end
		shop.sweeperUnlockSort = true

		box:AddChoice("Unlocked", SORT_UNLOCKED)

		-- Categories still group the guns, so this puts the locked ones at the end of each category.
		-- For one flat list of everything, set "Categories by" to none.
		local origGet = shop.GetSortFunc
		shop.GetSortFunc = function(self, ...)
			if self.sortMode ~= SORT_UNLOCKED then return origGet(self, ...) end
			return unlockSortFunc
		end

		-- The shop only rebuilds when the price table changes, which no longer happens when a batch
		-- opens (prices aren't filtered any more - only the lock set moves), so nudge it ourselves.
		local origThink = shop.Think
		shop.Think = function(self, ...)
			local v = S.gunLocks.version or 0
			if self.sweeperLockVer == nil then self.sweeperLockVer = v end
			if self.sweeperLockVer ~= v then
				self.sweeperLockVer = v
				if self.sortMode == SORT_UNLOCKED then self:RebuildLayout() end
			end
			if origThink then return origThink(self, ...) end
		end
	end

	function S.InstallShopUnlockSort()
		if not (jcms and jcms.offgame_BuildMissionPrepTab) or S.Wrapped(jcms, "ShopUnlockSort") then return end
		local orig = jcms.offgame_BuildMissionPrepTab

		S._wrappedPrepTab = function(tab, ...)
			local rtn = { orig(tab, ...) }
			local ok, err = pcall(addUnlockSort, tab)
			if not ok then ErrorNoHalt("[sweeper] unlocked-first sort: " .. tostring(err) .. "\n") end

			ok, err = pcall(addUnlockedRandomLoadout, tab)
			if not ok then ErrorNoHalt("[sweeper] random loadout: " .. tostring(err) .. "\n") end
			return unpack(rtn)
		end

		jcms.offgame_BuildMissionPrepTab = S._wrappedPrepTab
		S.MarkWrapped(jcms, "ShopUnlockSort")
	end
-- }}}

	local function installAll()
		S.InstallGunLockPaint()
		S.InstallGunLockTerminal()
		S.InstallShopUnlockSort()
	end
	hook.Add("Initialize", "sweeper_gunProgress", installAll)
	hook.Add("InitPostEntity", "sweeper_gunProgress", installAll)

	concommand.Add("sweeper_guns_locked", function()
		local g = S.gunLocks
		local n, names = 0, {}
		for class in pairs(g.locked) do
			n = n + 1
			if n <= 20 then names[#names + 1] = class end
		end
		print(string.format("--- Armory (client): system %s, %d weapon%s locked ---",
			g.enabled and "ON" or "OFF", n, n == 1 and "" or "s"))
		print("  " .. (n > 0 and (table.concat(names, ", ") .. (n > 20 and ", ..." or "")) or "nothing"))
	end, nil, "Show what this client thinks is locked.")

end
