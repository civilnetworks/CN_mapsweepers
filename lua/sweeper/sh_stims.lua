--[[
	Map Sweepers - Implants & Class Levels (addon)
	STIMS: temporary stat boosts picked up from a Stim Crate (Infantry call-in).

	HOW TO EDIT
	Add or change a line in S.stims below:
		{ id = "speed", name = "Adrenal Stim", duration = 30, weight = 1,
		  color = Color(255, 120, 255),
		  desc = "+20% move speed.",
		  stats = { speed = 0.20 } },

		id        unique, used for the networked timer and the HUD
		duration  seconds the boost lasts
		weight    how often it shows up in a crate (higher = more common)
		stats     the same stat keys as implants (see sh_tree.lua):
		            hp, armor, dmg, speed, jump, resist, blast, fire, regen, delay, killHeal,
		            killShield, killCash, xp, deploy, deployHp, airDmg, lowHpDmg, headshot,
		            meleeDmg, pistolDmg, rangeDmg, crouchDmg, blastDmg, orderCost, orderCooldown...
		          They stack with everything else and are removed when the stim runs out.

	Taking the same stim again just refreshes its timer. Different stims stack.
	Stims are cleared on death, on respawn and when you change class.
--]]

local S = sweeper

S.stimConfig = {
	boxLifetime = 240,   -- a dropped stim box disappears after this long
	pickupRange = 72,    -- how close you have to be to press E on one
}

S.stims = {
	{ id = "shield", name = "Hardlight Stim", duration = 30, weight = 1, color = Color(90, 180, 255),
	  desc = "+50 max shield.", stats = { armor = 50 } },
	{ id = "health", name = "Trauma Stim",    duration = 30, weight = 1, color = Color(120, 255, 140),
	  desc = "+50 max health.", stats = { hp = 50 } },
	{ id = "speed",  name = "Adrenal Stim",   duration = 30, weight = 1, color = Color(255, 210, 90),
	  desc = "+20% move speed.", stats = { speed = 0.20 } },
	{ id = "damage", name = "Combat Stim",    duration = 30, weight = 1, color = Color(255, 90, 90),
	  desc = "+20% damage.", stats = { dmg = 0.20 } },
	{ id = "jump",   name = "Kinetic Stim",   duration = 30, weight = 1, color = Color(180, 140, 255),
	  desc = "+60 jump power.", stats = { jump = 60 } },
	{ id = "armor",  name = "Plating Stim",   duration = 30, weight = 1, color = Color(200, 200, 210),
	  desc = "-15% damage taken.", stats = { resist = 0.15 } },
}

S.stimById = {}
for i, st in ipairs(S.stims) do S.stimById[st.id] = st end

function S.StimKey(id) return "sweeper_stim_" .. id end

-- Seconds left on a stim (0 = not running). Works on both realms - the timer is networked.
function S.StimLeft(ply, id)
	if not IsValid(ply) then return 0 end
	return math.max(0, ply:GetNWFloat(S.StimKey(id), 0) - CurTime())
end

-- How many stims are running on this player right now (Commando's Combat Cocktail scales off it)
function S.CountStims(ply)
	if not (IsValid(ply) and ply:IsPlayer()) then return 0 end
	local n = 0
	for i, st in ipairs(S.stims) do
		if S.StimLeft(ply, st.id) > 0 then n = n + 1 end
	end
	return n
end

-- Stats from every stim running on this player right now (added into S.ComputeStats)
function S.GetStimStats(ply)
	local out = {}
	if not IsValid(ply) or not ply:IsPlayer() then return out end
	for i, st in ipairs(S.stims) do
		if S.StimLeft(ply, st.id) > 0 then
			for k, v in pairs(st.stats or {}) do out[k] = (out[k] or 0) + v end
		end
	end
	return out
end

-- A random stim id, by weight. `exclude` is an optional set of ids to skip, so you can draw
-- several distinct stims in a row (Commando's Combat Stim does this).
function S.RandomStim(exclude)
	local total = 0
	for i, st in ipairs(S.stims) do
		if not (exclude and exclude[st.id]) then total = total + (st.weight or 1) end
	end
	if total <= 0 then return nil end

	local r = math.random() * total
	for i, st in ipairs(S.stims) do
		if not (exclude and exclude[st.id]) then
			r = r - (st.weight or 1)
			if r <= 0 then return st.id end
		end
	end

	-- Float rounding: hand back the first id that wasn't excluded.
	for i, st in ipairs(S.stims) do
		if not (exclude and exclude[st.id]) then return st.id end
	end
end

-- Draw up to `n` distinct stim ids by weight.
function S.RandomStims(n)
	local picked, taken = {}, {}
	for i = 1, math.max(0, math.floor(n or 1)) do
		local id = S.RandomStim(taken)
		if not id then break end
		taken[id] = true
		picked[#picked + 1] = id
	end
	return picked
end

if SERVER then
	-- Start (or refresh) a stim on a player.
	-- durationOverride: use this many seconds instead of the stim's own duration (the Commando's
	-- Combat Stim ability hands out every stim on a shorter clock than a crate pickup would).
	function S.GiveStim(ply, id, durationOverride)
		local st = S.stimById[id]
		if not (st and IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return false end

		-- "Stim Crate: Potent Mix" Team Upgrade makes them last longer
		local dur = tonumber(durationOverride) or st.duration or 30
		local rank = S.GroupRank and S.GroupRank("g_stims") or 0
		if rank > 0 then dur = dur * (1 + ((S.callinUpgrades and S.callinUpgrades.stimDurationPerRank) or 0) * rank) end
		dur = math.Round(dur)
		local untilT = CurTime() + dur
		ply:SetNWFloat(S.StimKey(id), untilT)
		if S.RefreshStats then S.RefreshStats(ply) end

		timer.Create("sweeper_stim_" .. id .. "_" .. ply:EntIndex(), dur, 1, function()
			if IsValid(ply) then
				ply:SetNWFloat(S.StimKey(id), 0)
				if S.RefreshStats then S.RefreshStats(ply) end
				ply:EmitSound("items/suitchargeno1.wav", 55, 120, 0.5)
			end
		end)

		-- Combat Stim hands out every stim at once and prints its own single line instead.
		if not ply.sweeperQuietStims then
			ply:EmitSound("items/smallmedkit1.wav", 70, 130)
			ply:ChatPrint(string.format("[Stim] %s: %s (%ds)", st.name, st.desc or "", dur))
		end
		return true
	end

	function S.ClearStims(ply)
		if not IsValid(ply) then return end
		for i, st in ipairs(S.stims) do
			if ply:GetNWFloat(S.StimKey(st.id), 0) ~= 0 then ply:SetNWFloat(S.StimKey(st.id), 0) end
			timer.Remove("sweeper_stim_" .. st.id .. "_" .. ply:EntIndex())
		end
		if S.RefreshStats then S.RefreshStats(ply) end
	end

	hook.Add("PlayerSpawn", "sweeper_stims", function(ply) S.ClearStims(ply) end)
	hook.Add("PlayerDeath", "sweeper_stims", function(ply) S.ClearStims(ply) end)
	hook.Add("MapSweepersClassApplied", "sweeper_stims", function(ply) S.ClearStims(ply) end)
end
