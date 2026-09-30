--[[
	Map Sweepers - Implants & Class Levels (addon)
	MISSION WEATHER (gWeather)

	The weather is rolled together with the mission modifiers: new map, New Contract reroll, admin reroll.
	It shows in the TEAM UPGRADES tab before the mission, and gets spawned when the mission starts.
	The gameplay effect of each weather is in sh_modifiers.lua (S.weatherEffects).

	- Needs gWeather installed. Without it nothing here runs.
	- While this is on, JWeather's random spawner is switched off (its hook is put back if you turn this off),
	  so there's only ever one weather, and it stays the same for the whole mission.
	- Higher win streaks roll harsher weather. Boss missions lean harsher too.

	Convars:  jcms_weather_roll 1/0        roll weather with the mission (0 = leave it to JWeather)
	          jcms_weather_clearchance 0.3 chance of no weather at all
	          jcms_weather_maxtier 7       harshest gWeather tier that can roll (1-7)
	Admin:    jcms_weather_set <class|clear|random>, jcms_weather_list
--]]

local S = sweeper

-- // Tuning {{{
S.weatherConfig = {
	-- Tier weights by win streak (last row whose minStreak <= streak is used). Tier = the "tN" in gw_tN_name.
	tiersByStreak = {
		{ minStreak = 0,  weights = { 6, 4, 1.5, 0.4, 0.1, 0, 0} },
		{ minStreak = 5, weights = { 4, 4, 3,1.5, 0.5, 0.15, 0} },
		{ minStreak = 10, weights = { 2, 3, 3.5, 3,1.5, 0.6, 0.15} },
		{ minStreak = 30, weights = { 1, 2, 3, 3.5, 2.5, 1.2, 0.4} },
	},
	bossTierShift = 1,  -- boss missions: roll as if the tier weights were shifted this many tiers harsher
	-- Per-weather weight multipliers (0 = never rolls). Classes not listed use 1.
	classWeights = {
		gw_t1_sunny = 0.5, gw_t1_partlycloudy = 0.5, -- plain skies are covered by the clear chance already
		gw_t7_space = 0.5,
	},
}
-- }}}

S.mods = S.mods or { list = {}, inMission = false, weather = "", weatherName = "", loan = "" }
S.mods.plannedWeather = S.mods.plannedWeather or ""

S.cvar_weatherRoll = CreateConVar("jcms_weather_roll", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"Roll the mission's weather with the mission modifiers (1), or leave it to JWeather (0).", 0, 1)

-- Nice name for a gWeather class (shared: works on the client for the menu)
function S.WeatherName(class)
	if not class or class == "" then return "Clear" end
	local st = scripted_ents.GetStored(class)
	local n = st and st.t and st.t.PrintName
	if n and n ~= "" then return n end
	local short = class:gsub("^gw_t%d_", ""):gsub("_", " ")
	return (short:gsub("^%l", string.upper))
end

function S.WeatherTier(class)
	return tonumber(string.match(class or "", "^gw_t(%d)_")) or 1
end

-- ============================================================================================
if SERVER then
	S.cvar_weatherClear = CreateConVar("jcms_weather_clearchance", "0.3", { FCVAR_ARCHIVE }, "Chance (0-1) a mission has no weather.", 0, 1)
	S.cvar_weatherMaxTier = CreateConVar("jcms_weather_maxtier", "7", { FCVAR_ARCHIVE }, "Harshest gWeather tier that can roll (1-7).", 1, 7)

	local function gWeatherInstalled()
		return scripted_ents.GetStored("gw_t1_sunny") ~= nil
	end

	-- Every gWeather weather class that's installed (hail is an add-on effect, not a weather)
	local function allWeathers()
		local list = {}
		for class, _ in pairs(scripted_ents.GetList()) do
			if string.match(class, "^gw_t%d_") and not string.match(class, "hail$") then
				list[#list + 1] = class
			end
		end
		table.sort(list)
		return list
	end
	S.AllWeathers = allWeathers

	-- // JWeather: switch its random spawner off while we roll the weather {{{
	local jweatherFn
	function S.WeatherTakeover()
		local tbl = hook.GetTable().Think
		local on = S.cvar_weatherRoll:GetBool() and gWeatherInstalled()
		if on then
			if tbl and tbl.jcms_Weather then
				jweatherFn = tbl.jcms_Weather
				hook.Remove("Think", "jcms_Weather")
			end
		elseif jweatherFn and not (tbl and tbl.jcms_Weather) then
			hook.Add("Think", "jcms_Weather", jweatherFn)
		end
	end
	hook.Add("InitPostEntity", "sweeper_weatherTakeover", function() timer.Simple(0, S.WeatherTakeover) end)
	cvars.AddChangeCallback("jcms_weather_roll", function() S.WeatherTakeover() end, "sweeper_weather")
	S.WeatherTakeover()
	-- }}}

	local function streak()
		return (jcms and jcms.runprogress and jcms.runprogress.winstreak) or 0
	end

	function S.RollWeather(silent)
		S.mods.plannedWeather = ""
		if not (S.cvar_weatherRoll:GetBool() and gWeatherInstalled()) then return end
		if S.ModsAllowed and not S.ModsAllowed() then return end
		if math.random() < S.cvar_weatherClear:GetFloat() then return end

		local cfg = S.weatherConfig
		local st = streak()
		local row = cfg.tiersByStreak[1]
		for i, r in ipairs(cfg.tiersByStreak) do if st >= r.minStreak then row = r end end
		local shift = (jcms and jcms.mission_IsBossMission and jcms.mission_IsBossMission()) and (cfg.bossTierShift or 0) or 0
		local maxTier = S.cvar_weatherMaxTier:GetInt()

		local weights, total = {}, 0
		for i, class in ipairs(allWeathers()) do
			local tier = S.WeatherTier(class)
			if tier <= maxTier then
				local w = (row.weights[math.max(1, tier - shift)] or 0) * (cfg.classWeights[class] or 1)
				-- when shifted, the mildest tiers lose weight instead of borrowing it
				if shift > 0 and tier <= shift then w = w * 0.25 end
				if w > 0 then weights[class] = w total = total + w end
			end
		end
		if total <= 0 then return end
		local r = math.random() * total
		for class, w in pairs(weights) do
			r = r - w
			if r <= 0 then S.mods.plannedWeather = class break end
		end

		if not silent and S.mods.plannedWeather ~= "" then
			local def = S.weatherEffects and S.weatherEffects[S.mods.plannedWeather]
			local msg = string.format("[Weather] Forecast: %s. %s", S.WeatherName(S.mods.plannedWeather), def and def.desc or "")
			for i, p in ipairs(player.GetHumans()) do p:ChatPrint(msg) end
		end
	end

	-- // Spawning {{{
	local current -- the weather entity we spawned for this mission

	local function removeWeathers()
		for i, e in ipairs(ents.FindByClass("gw_t*")) do
			if IsValid(e) then e:Remove() end
		end
	end

	local function spawnPlanned()
		local class = S.mods.plannedWeather
		if class == "" or not scripted_ents.GetStored(class) then return end
		local e = ents.Create(class)
		if not IsValid(e) then return end
		e:SetPos(vector_origin)
		e:Spawn()
		e:Activate()
		current = e
		if jcms and jcms.director then jcms.director.weatherControl = e end
	end

	function S.WeatherStart()
		if not (S.cvar_weatherRoll:GetBool() and gWeatherInstalled()) then return end
		S.WeatherTakeover()
		removeWeathers()
		current = nil
		-- a moment later, so the map/mission is fully set up
		timer.Simple(1, function()
			if S.mods.inMission then spawnPlanned() end
		end)
	end

	-- Called every second during the mission: gWeather removes weather after gw_weather_lifetime,
	-- so put the same weather back for the rest of the mission.
	function S.WeatherKeep()
		if not (S.cvar_weatherRoll:GetBool() and S.mods.inMission) then return end
		if S.mods.plannedWeather == "" or IsValid(current) then return end
		if (S._weatherNextTry or 0) > CurTime() then return end
		S._weatherNextTry = CurTime() + 5
		spawnPlanned()
	end

	function S.WeatherStop()
		if not S.cvar_weatherRoll:GetBool() then return end
		if IsValid(current) then current:Remove() end
		current = nil
	end
	-- }}}

	-- // Admin {{{
	concommand.Add("jcms_weather_set", function(ply, cmd, args)
		if IsValid(ply) and not ply:IsAdmin() then return end
		local a = args[1] or ""
		if a == "random" then
			S.RollWeather(true)
		elseif a == "clear" or a == "" then
			S.mods.plannedWeather = ""
		elseif scripted_ents.GetStored(a) and string.match(a, "^gw_t%d_") then
			S.mods.plannedWeather = a
		else
			local msg = "[Weather] unknown weather: " .. a .. "  (see jcms_weather_list)"
			S.PrintConsole(ply, msg)
			return
		end
		-- mid-mission: swap it right away
		if S.mods.inMission then
			removeWeathers()
			current = nil
			spawnPlanned()
		end
		if S.ModSync then S.ModSync() end
		local msg = "[Weather] Set to " .. S.WeatherName(S.mods.plannedWeather)
		S.PrintConsole(ply, msg)
	end, nil, "Admin: set this mission's weather: <gw_ class>, clear, or random.")

	concommand.Add("jcms_weather_list", function(ply)
		local lines = {}
		for i, class in ipairs(allWeathers()) do
			local def = S.weatherEffects and S.weatherEffects[class]
			lines[#lines + 1] = string.format("T%d  %-26s %s", S.WeatherTier(class), class, def and def.desc or "")
		end
		local msg = table.concat(lines, "\n")
		S.PrintConsole(ply, msg)
	end, nil, "List gWeather weathers, their tier and gameplay effect.")
	-- }}}
end
