--[[
	Map Sweepers - Implants & Class Levels (addon)
	Team Upgrades for the gamemode's own ORBITAL orders (Carpet Bombing, Shelling, Orbital Beam,
	AA Missile). The upgrade rows live in S.group (sh_group.lua); this is what they do.

		g_carpet       Saturation Run   Carpet Bombing: blast radius +100 and the run carries on +400 units
		                                past the mark, per rank. (The wider spread and the extra bombs of the
		                                same upgrade are in sh_callins.lua - one upgrade, two wraps, and only
		                                sh_callins touches the bomb count so they can never double up.)
		g_rapid        Rapid Battery    Shelling: first shell lands 25% sooner and +15 more shells fall,
		                                per rank - it starts faster and keeps going
		g_beam         Focusing Array   Beam radius +16 and sweep speed +75 per rank (base 32 / 350)
		g_dangerclose  Danger Close     your orbitals hurt sweepers 50% less per rank
		g_requisition  Requisition      every orbital order costs 10% less per rank
		g_salvo        Second Salvo     20% chance per rank of a free repeat a few seconds later

	HOW, WITHOUT EDITING THE GAMEMODE
	  Each orbital's jcms.orders.<id>.func is wrapped, the same shape sh_callins.lua already uses for
	  Carpet Bomb: Wide Pattern. Inside the wrap, jcms.spawnmenu_Airstrike is swapped for one that
	  edits the info table on the way through, then swapped straight back - so the change only ever
	  applies to that one call, never to another addon's airstrike.

	  Both Carpet Bombing and Shelling go through that one Airstrike call (shelling passes its own
	  shootFunc), which is why one seam covers them both. The Beam spawns jcms_deathraycontroller and
	  sets its stats right after Spawn, so it's caught on OnEntityCreated a tick later instead.

	  Costs are pushed with jcms.net_SendOrder, which is how the gamemode's own firing range changes
	  an order's price at runtime. Base costs are captured once so ranks can't compound.
--]]

local S = sweeper

S.orbitals = {
	carpetBlastPerRank = 100,    -- + blast radius (Carpet Bombing, base 400)
	carpetLengthPerRank = 400,   -- + units the run carries on PAST the mark (base run is 1000 long)
	-- The bomb count and the spread live in S.callinUpgrades (sh_callins.lua), which wraps the same
	-- order for the same upgrade. Adding bombs here too would stack them twice.

	rapidArrivalPerRank = 0.25,  -- Shelling: fraction off the wait before the first shell lands
	rapidArrivalFloor = 0.25,    -- ...never sooner than this much of the original wait
	rapidShellsPerRank = 15,     -- + shells, so the barrage keeps going (base 60, or 50 for Engineer)

	beamRadiusPerRank = 16,      -- Orbital Beam (base 32)
	beamSpeedPerRank = 75,       -- sweep speed (base 350)

	dangerClosePerRank = 0.5,    -- friendly damage removed per rank (2 ranks = none)
	requisitionPerRank = 0.10,   -- order cost off per rank
	requisitionFloor = 0.4,      -- ...never cheaper than this fraction of the base price

	salvoChancePerRank = 0.20,   -- chance of a free repeat
	salvoDelay = 4,              -- seconds before it lands
	orbitalWindow = 14,          -- how long after a call its damage still counts as "orbital"
}

-- The orders this file governs. AA Missile takes the squad-wide upgrades but has no payload tweak.
S.orbitalOrders = { "carpetbombing", "shelling", "orbitalbeam", "antiairmissile" }

if not SERVER then return end

local O = S.orbitals

local function rank(id)
	return (S.GroupRank and S.GroupRank(id)) or 0
end

-- // Payload tweaks, applied only while one orbital order is running {{{
-- Returns a replacement for jcms.spawnmenu_Airstrike, or nil when this order needs no changes.
local function airstrikeFor(orderId, orig)
	local carpet = (orderId == "carpetbombing") and rank("g_carpet") or 0
	local rapid = (orderId == "shelling") and rank("g_rapid") or 0
	local danger = rank("g_dangerclose")

	if carpet <= 0 and rapid <= 0 and danger <= 0 then return nil end

	return function(info)
		-- Saturation Run: bigger blasts, and the run carries on past the mark. Only the far end of
		-- the line moves, so the bombs still start where they were aimed. The bomb count and the
		-- wider spread are sh_callins.lua's half of this same upgrade.
		if carpet > 0 then
			if info.blast_radius then
				info.blast_radius = info.blast_radius + O.carpetBlastPerRank * carpet
			end

			if info.pos and info.pos2 then
				local dir = info.pos2 - info.pos
				if dir:LengthSqr() > 1 then
					dir:Normalize()
					info.pos2 = info.pos2 + dir * (O.carpetLengthPerRank * carpet)
				end
			end
		end

		-- Rapid Battery: the first shell lands sooner, and more of them fall, so the barrage opens
		-- faster and keeps going. The gaps between shells are left alone - shrinking those as well
		-- turned the barrage into one burst instead of a longer bombardment.
		if rapid > 0 then
			if info.arrival then
				info.arrival = info.arrival * math.max(O.rapidArrivalFloor, 1 - O.rapidArrivalPerRank * rapid)
			end
			info.count = (info.count or 1) + O.rapidShellsPerRank * rapid
		end

		-- Danger Close: tag each bomb so the damage hook below knows it came from an orbital
		if danger > 0 then
			local origCallback = info.callback
			info.callback = function(bomb, ...)
				if IsValid(bomb) then bomb.sweeperOrbital = true end
				if origCallback then return origCallback(bomb, ...) end
			end
		end

		return orig(info)
	end
end
-- }}}

-- // The order wrappers {{{
-- One per orbital: payload tweaks, the orbital-damage window for Danger Close, and Second Salvo.
local function wrapOrder(id)
	local order = jcms and jcms.orders and jcms.orders[id]
	if not order or not order.func or S.Wrapped(order, "Orbital") then return end

	local orig = order.func

	-- The body of one firing, without the salvo roll (so a repeat can reuse it)
	local function fire(ply, ...)
		if IsValid(ply) then ply.sweeperOrbitalUntil = CurTime() + O.orbitalWindow end

		local swapped = airstrikeFor(id, jcms.spawnmenu_Airstrike)
		if not swapped then return orig(ply, ...) end

		local before = jcms.spawnmenu_Airstrike
		jcms.spawnmenu_Airstrike = swapped
		local ok, err = pcall(orig, ply, ...)
		jcms.spawnmenu_Airstrike = before      -- always put it back, even if the order errored
		if not ok then error(err, 0) end
	end

	order.func = function(ply, ...)
		fire(ply, ...)

		local salvo = rank("g_salvo")
		if salvo > 0 and math.random() < O.salvoChancePerRank * salvo then
			local args = { ... }
			timer.Simple(O.salvoDelay, function()
				if not IsValid(ply) then return end
				local ok, err = pcall(fire, ply, unpack(args))
				if not ok then ErrorNoHalt("[Orbitals] second salvo: " .. tostring(err) .. "\n") end
			end)

			if S.ChatPrintAll then
				S.ChatPrintAll(string.format("[Orbitals] Second salvo incoming on %s's mark.", ply:Nick()))
			end
		end
	end

	S.MarkWrapped(order, "Orbital")
end
-- }}}

-- // Orbital Beam: Focusing Array {{{
-- The order creates the controller and sets its stats immediately after Spawn, so the buff is
-- applied a tick later rather than inside OnEntityCreated.
hook.Add("OnEntityCreated", "sweeper_orbitalBeam", function(ent)
	if not IsValid(ent) or ent:GetClass() ~= "jcms_deathraycontroller" then return end

	timer.Simple(0, function()
		if not IsValid(ent) then return end
		ent.sweeperOrbital = true

		local r = rank("g_beam")
		if r <= 0 then return end

		local radius = (tonumber(ent.beamRadius) or 32) + O.beamRadiusPerRank * r
		ent.beamRadius = radius
		ent.Speed = (tonumber(ent.Speed) or 350) + O.beamSpeedPerRank * r

		local ray = ent.deathRay
		if IsValid(ray) then
			ray.sweeperOrbital = true
			if ray.SetBeamRadius then ray:SetBeamRadius(radius) end
		end
	end)
end)
-- }}}

-- // Danger Close {{{
-- Two ways an orbital can hurt a sweeper: something we tagged (bombs, the beam), or Shelling, which
-- deals its damage straight from the order's closure with the caller as the attacker and no entity
-- to tag - that one is caught by the blast window opened when the order fired.
hook.Add("EntityTakeDamage", "sweeper_orbitalDangerClose", function(ent, dmg)
	local r = rank("g_dangerclose")
	if r <= 0 then return end
	if not (IsValid(ent) and ent:IsPlayer() and jcms.team_JCorp_player and jcms.team_JCorp_player(ent)) then return end

	local attacker, inflictor = dmg:GetAttacker(), dmg:GetInflictor()
	local tagged = (IsValid(inflictor) and inflictor.sweeperOrbital) or (IsValid(attacker) and attacker.sweeperOrbital)

	local windowed = IsValid(attacker) and attacker:IsPlayer()
		and (attacker.sweeperOrbitalUntil or 0) > CurTime()
		and bit.band(dmg:GetDamageType(), DMG_BLAST) ~= 0

	if not (tagged or windowed) then return end

	local left = math.max(0, 1 - O.dangerClosePerRank * r)
	if left <= 0 then
		dmg:SetDamage(0)
		return true
	end
	dmg:ScaleDamage(left)
end)
-- }}}

-- // Requisition {{{
-- Base costs are remembered the first time we see them, so repeated applies can't compound.
local baseCost = {}

function S.OrbitalRefreshCosts()
	if not (jcms and jcms.orders) then return end

	local r = rank("g_requisition")
	local mul = math.max(O.requisitionFloor, 1 - O.requisitionPerRank * r)

	for i, id in ipairs(S.orbitalOrders) do
		local order = jcms.orders[id]
		if order then
			baseCost[id] = baseCost[id] or order.cost
			local want = math.max(1, math.ceil((baseCost[id] or order.cost) * mul))
			if order.cost ~= want then
				order.cost = want
				if jcms.net_SendOrder then jcms.net_SendOrder(id, order) end
			end
		end
	end
end
-- }}}

function S.InstallOrbitalUpgrades()
	if not (jcms and jcms.orders) then return end
	for i, id in ipairs(S.orbitalOrders) do wrapOrder(id) end
	S.OrbitalRefreshCosts()
end

hook.Add("Initialize", "sweeper_orbitals", S.InstallOrbitalUpgrades)
hook.Add("InitPostEntity", "sweeper_orbitals", S.InstallOrbitalUpgrades)
S.InstallOrbitalUpgrades() -- Lua refresh

-- Buying a rank runs GroupReapply, which is where the new price has to reach the clients
function S.InstallOrbitalReapply()
	if not S.GroupReapply or S.Wrapped(S, "OrbitalReapply") then return end
	local orig = S.GroupReapply
	S._wrappedOrbitalReapply = function(...)
		local r = { orig(...) }
		local ok, err = pcall(S.OrbitalRefreshCosts)
		if not ok then ErrorNoHalt("[Orbitals] cost refresh: " .. tostring(err) .. "\n") end
		return unpack(r)
	end
	S.GroupReapply = S._wrappedOrbitalReapply
	S.MarkWrapped(S, "OrbitalReapply")
end
hook.Add("Initialize", "sweeper_orbitalsReapply", S.InstallOrbitalReapply)
hook.Add("InitPostEntity", "sweeper_orbitalsReapply", S.InstallOrbitalReapply)
S.InstallOrbitalReapply()

concommand.Add("sweeper_orbitals_status", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local lines = { "--- Orbital upgrades ---" }
	for i, id in ipairs({ "g_carpet", "g_rapid", "g_beam", "g_dangerclose", "g_requisition", "g_salvo" }) do
		local up = S.groupById and S.groupById[id]
		lines[#lines + 1] = string.format("  %-14s rank %d/%d  %s", id, rank(id),
			up and #up.costs or 0, up and up.name or "?")
	end
	lines[#lines + 1] = "  order costs now:"
	for i, id in ipairs(S.orbitalOrders) do
		local order = jcms.orders[id]
		if order then
			lines[#lines + 1] = string.format("    %-16s %d (base %s)", id, order.cost or 0, tostring(baseCost[id]))
		end
	end

	local text = table.concat(lines, "\n")
	if S.PrintConsole and IsValid(ply) then S.PrintConsole(ply, text) else print(text) end
end, nil, "Admin: show the orbital upgrade ranks and current order costs.")
