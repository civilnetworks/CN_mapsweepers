--[[
	Map Sweepers - Implants & Class Levels (addon)
	Admin blocklist for mission types and factions.

	Two replicated convars hold comma-separated ids, so the client UI can show the current state
	without any networking of our own:
		sweeper_missions_off   e.g. "hell,eschaton"
		sweeper_factions_off   e.g. "zombie"

	Admin commands (also driven by the buttons in Options > Server):
		sweeper_mission_toggle <type>     sweeper_missions_list
		sweeper_faction_toggle <name>     sweeper_factions_list

	HOW IT'S ENFORCED (no gamemode edit):
	  1. jcms.mission_GetWeightedTypes is wrapped and blocked mission types are dropped from the
	     weight pool, so they're simply never drawn.
	  2. jcms.mission_Randomize is wrapped and re-rolls when the result lands on a blocked faction.
	     The faction for an "any" mission is chosen inline inside mission_Randomize, and every
	     faction-locked mission carries its faction with it, so there's no weight table to filter -
	     re-rolling is the only place that catches both.

	Both have a hard stop: if everything is blocked, the last roll stands and a warning is printed
	rather than the server locking up or refusing to start a mission.
--]]

local S = sweeper

local MISSIONS_CVAR = "sweeper_missions_off"
local FACTIONS_CVAR = "sweeper_factions_off"

if SERVER then
	CreateConVar(MISSIONS_CVAR, "", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Mission types admins have switched off, comma separated.")
	CreateConVar(FACTIONS_CVAR, "", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Factions admins have switched off, comma separated.")
end

-- // Reading the lists {{{
local function listSet(cvarName)
	local cv = GetConVar(cvarName)
	local out = {}
	if not cv then return out end

	for i, part in ipairs(string.Explode(",", cv:GetString())) do
		part = string.Trim(part):lower()
		if part ~= "" then out[part] = true end
	end
	return out
end

-- The factions the gamemode ships with (gamemode/npcs/types/*.lua). Anything else on the list comes
-- from an addon, which is what sweeper_factions_defaultonly switches off.
S.defaultFactions = { "antlion", "combine", "rebel", "zombie" }

function S.BlockedMissions() return listSet(MISSIONS_CVAR) end
function S.BlockedFactions() return listSet(FACTIONS_CVAR) end

function S.MissionAllowed(id)
	if not id or id == "" then return true end
	return not S.BlockedMissions()[string.lower(id)]
end

function S.FactionAllowed(name)
	if not name or name == "" then return true end
	return not S.BlockedFactions()[string.lower(name)]
end
-- }}}

if SERVER then

-- // Writing the lists {{{
	local function setList(cvarName, set)
		local keys = {}
		for id in pairs(set) do keys[#keys + 1] = id end
		table.sort(keys)
		RunConsoleCommand(cvarName, table.concat(keys, ","))
	end

	-- Returns the new state: true = now blocked.
	function S.ToggleBlocked(kind, id)
		if not id or id == "" then return end
		id = string.lower(string.Trim(id))

		local cvarName = (kind == "faction") and FACTIONS_CVAR or MISSIONS_CVAR
		local set = listSet(cvarName)

		if set[id] then set[id] = nil else set[id] = true end
		setList(cvarName, set)

		return set[id] == true
	end
-- }}}

-- // Enforcement {{{
	local warned = false

	local function anyCombinationLeft()
		for id, data in pairs(jcms.missions or {}) do
			if S.MissionAllowed(id) then
				if data.faction ~= "any" then
					if S.FactionAllowed(data.faction) then return true end
				else
					for i, faction in ipairs(jcms.factions_GetOrder and jcms.factions_GetOrder() or {}) do
						if S.FactionAllowed(faction) then return true end
					end
				end
			end
		end
		return false
	end

	function S.InstallMissionFilter()
		if not jcms then return end

		-- Drop blocked mission types out of the weight pool.
		if jcms.mission_GetWeightedTypes and not S.Wrapped(jcms, "MissionWeights") then
			local orig = jcms.mission_GetWeightedTypes
			jcms.mission_GetWeightedTypes = function(...)
				local weights = orig(...)
				if not istable(weights) then return weights end

				local kept, n = {}, 0
				for id, w in pairs(weights) do
					if S.MissionAllowed(id) then kept[id] = w n = n + 1 end
				end

				-- Never hand back an empty pool: the gamemode asserts on the pick.
				if n == 0 then return weights end
				return kept
			end
			S.MarkWrapped(jcms, "MissionWeights")
		end

		-- Re-roll when the faction that came out is blocked.
		if jcms.mission_Randomize and not S.Wrapped(jcms, "MissionRandomize") then
			local orig = jcms.mission_Randomize
			jcms.mission_Randomize = function(...)
				local wld = game.GetWorld()

				if not anyCombinationLeft() then
					orig(...)
					if not warned then
						warned = true
						ErrorNoHalt("[sweeper] Every mission/faction combination is switched off - " ..
							"the blocklist is being ignored. Check sweeper_missions_list / sweeper_factions_list.\n")
					end
					return
				end

				for attempt = 1, 50 do
					orig(...)
					local mission = wld:GetNWString("jcms_missiontype", "")
					local faction = wld:GetNWString("jcms_missionfaction", "")
					if S.MissionAllowed(mission) and S.FactionAllowed(faction) then return end
				end

				-- Unlucky rather than impossible: keep the last roll instead of spinning.
				ErrorNoHalt("[sweeper] Couldn't roll an allowed mission in 50 tries, keeping the last one.\n")
			end
			S.MarkWrapped(jcms, "MissionRandomize")
		end
	end

	hook.Add("Initialize", "sweeper_missionfilter", function() S.InstallMissionFilter() end)
	hook.Add("InitPostEntity", "sweeper_missionfilter", function() S.InstallMissionFilter() end)
-- }}}

-- // Commands {{{
	local function adminOnly(ply)
		if not IsValid(ply) then return true end -- server console
		if ply:IsAdmin() then return true end
		if S.PrintConsole then S.PrintConsole(ply, "[Implants] Admins only.") end
		return false
	end

	local function say(ply, text)
		if S.PrintConsole then S.PrintConsole(ply, text) else print(text) end
	end

	local function toggleCmd(kind, valid, label)
		return function(ply, cmd, args)
			if not adminOnly(ply) then return end

			local id = string.lower(string.Trim(tostring(args[1] or "")))
			if id == "" then
				say(ply, string.format("[Implants] Usage: %s <%s>", cmd, label))
				return
			end

			if not valid()[id] then
				say(ply, string.format("[Implants] Unknown %s '%s'.", label, id))
				return
			end

			local off = S.ToggleBlocked(kind, id)
			local msg = string.format("[Implants] %s '%s' is now %s.", label, id, off and "OFF" or "ON")
			say(ply, msg)
			if S.ChatPrintAll then S.ChatPrintAll(msg) end
		end
	end

	local function missionSet()
		local t = {}
		for id in pairs(jcms and jcms.missions or {}) do t[string.lower(id)] = true end
		return t
	end

	local function factionSet()
		local t = {}
		for id in pairs(jcms and jcms.factions or {}) do t[string.lower(id)] = true end
		return t
	end

	concommand.Add("sweeper_mission_toggle", toggleCmd("mission", missionSet, "mission"),
		nil, "Switch a mission type on or off (admin).")
	concommand.Add("sweeper_faction_toggle", toggleCmd("faction", factionSet, "faction"),
		nil, "Switch a faction on or off (admin).")

	local function listCmd(getSet, blockedFn, label)
		return function(ply)
			local blocked = blockedFn()
			local ids = {}
			for id in pairs(getSet()) do ids[#ids + 1] = id end
			table.sort(ids)

			local lines = { string.format("--- %s (%d) ---", label, #ids) }
			for i, id in ipairs(ids) do
				lines[#lines + 1] = string.format("  %-28s %s", id, blocked[id] and "OFF" or "on")
			end
			say(ply, table.concat(lines, "\n"))
		end
	end

	concommand.Add("sweeper_missions_list", listCmd(missionSet, S.BlockedMissions, "Mission types"),
		nil, "List mission types and whether they're switched on.")
	concommand.Add("sweeper_factions_list", listCmd(factionSet, S.BlockedFactions, "Factions"),
		nil, "List factions and whether they're switched on.")

	-- Testing with the stock roster: block every faction an addon registered
	concommand.Add("sweeper_factions_defaultonly", function(ply)
		if not adminOnly(ply) then return end

		local keep = {}
		for i, id in ipairs(S.defaultFactions) do keep[id] = true end

		local blocked, kept = {}, {}
		local set = {}
		for id in pairs(factionSet()) do
			if keep[id] then
				kept[#kept + 1] = id
			else
				set[id] = true
				blocked[#blocked + 1] = id
			end
		end
		table.sort(blocked) table.sort(kept)
		setList(FACTIONS_CVAR, set)

		say(ply, string.format("[Implants] Stock factions only.\n  on:  %s\n  off: %s",
			table.concat(kept, ", "), #blocked > 0 and table.concat(blocked, ", ") or "(none found)"))
	end, nil, "Admin: block every faction that came from an addon, leaving the gamemode's own.")

	concommand.Add("sweeper_factions_all", function(ply)
		if not adminOnly(ply) then return end
		setList(FACTIONS_CVAR, {})
		say(ply, "[Implants] Every faction is back on.")
	end, nil, "Admin: clear the faction blocklist.")
-- }}}

end
