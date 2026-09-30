--[[
	Map Sweepers - Implants & Class Levels (addon)
	SERVER RECORDS (leaderboard)

	Keeps permanent per-player records on the SERVER, so nobody can edit their own numbers, and shows
	them in a RECORDS tab in the lobby. The gamemode's own leaderboard (wins / losses / win streak) is
	left alone; this sits beside it with the things it doesn't track.

	Boards:      Kills, Boss kills, Missions won, Best win streak, Missions played, Survival rate,
	             Deaths per mission, Call-ins used, Implant Rank, Longest life
	Records:     Fastest clear of each mission type, most kills in one mission, longest life, best streak
	Seasons:     Every month starts a new season. The old season's top three are kept in the Hall of Fame.

	Files (in the server's data folder):
	  sweeper_lb/<steamid64>.json   one file per player
	  sweeper_lb/_records.json      map / mission records
	  sweeper_lb/_halloffame.json   past seasons

	Convars:  jcms_records 1/0           keep records at all
	          jcms_records_minplayers 2  missions with fewer players than this don't count
	Admin:    jcms_records_reset <name|steamid64>, jcms_records_season_end, jcms_records_wipe
--]]

local S = sweeper

S.lbSeason = function() return os.date("%Y-%m") end

-- Boards: id, label, the stat it reads, and whether more is better.
-- `calc` builds the number from a player's record entry.
-- source = "pve" / "pvp" reads the gamemode's own leaderboard files (all-time, with its full history).
S.lbBoards = {
	{ id = "wins",      label = "Missions won",    source = "pve", calc = function(e) return e.wins or 0 end },
	{ id = "wlr",       label = "Win / loss ratio", source = "pve", decimals = 2, minGames = 5,
	  calc = function(e) local l = e.losses or 0 return l == 0 and (e.wins or 0) or ((e.wins or 0) / l) end },
	{ id = "streak",    label = "Best win streak", source = "pve", calc = function(e) return e.highestWinstreak or 0 end },
	{ id = "kills",     label = "Kills",           calc = function(e) return e.kills or 0 end },
	{ id = "boss",      label = "Boss kills",      calc = function(e) return e.bossKills or 0 end },
	{ id = "missions",  label = "Missions played", calc = function(e) return e.missions or 0 end },
	{ id = "survival",  label = "Survival rate",   suffix = "%", minMissions = 5,
	  calc = function(e) return (e.missions or 0) > 0 and math.Round((e.evacs or 0) / e.missions * 100) or 0 end },
	{ id = "deaths",    label = "Deaths per mission", lowerIsBetter = true, decimals = 2, minMissions = 5,
	  calc = function(e) return (e.missions or 0) > 0 and ((e.deaths or 0) / e.missions) or 0 end },
	{ id = "orders",    label = "Call-ins used",   calc = function(e) return e.orders or 0 end },
	{ id = "implants",  label = "Implant Rank",    calc = function(e) return e.implantRank or 0 end },
	{ id = "life",      label = "Longest life",    time = true, calc = function(e) return e.longestLife or 0 end },
	{ id = "elo",       label = "PvP rating",      source = "pvp", calc = function(e) return e.elo or 500 end },
	{ id = "pvpwins",   label = "PvP wins",        source = "pvp", calc = function(e) return e.wins or 0 end },
}

function S.LbFormat(board, value)
	if board.time then
		local t = math.floor(value)
		return string.format("%d:%02d", math.floor(t / 60), t % 60)
	end
	if board.decimals then return string.format("%." .. board.decimals .. "f", value) end
	return string.format("%d", math.floor(value)) .. (board.suffix or "")
end

-- ============================================================================================
if SERVER then
	util.AddNetworkString("sweeper_records")

	S.cvar_records = CreateConVar("jcms_records", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, "Keep permanent player records (1/0).", 0, 1)
	S.cvar_recordsMin = CreateConVar("jcms_records_minplayers", "2", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Missions with fewer players than this don't count towards records.", 1, 16)

	local DIR = "sweeper_lb"
	file.CreateDir(DIR)

	-- // Storage {{{
	local function pathFor(sid64) return DIR .. "/" .. sid64 .. ".json" end

	local blank = {
		name = "", missions = 0, wins = 0, losses = 0, bestStreak = 0,
		kills = 0, killsDirect = 0, killsTurret = 0, killsExplosive = 0, bossKills = 0,
		deaths = 0, evacs = 0, orders = 0, longestLife = 0, implantRank = 0,
		lastSeen = 0, season = "", s = {},   -- s = this season's copy of the same numbers
	}

	function S.LbGet(sid64)
		local e = table.Copy(blank)
		local raw = file.Read(pathFor(sid64), "DATA")
		if raw then
			local t = util.JSONToTable(raw)
			if istable(t) then table.Merge(e, t) end
		end
		-- new month = new season, the old numbers stay in the all-time totals
		if e.season ~= S.lbSeason() then
			e.season = S.lbSeason()
			e.s = {}
		end
		return e
	end

	function S.LbSave(sid64, e)
		file.Write(pathFor(sid64), util.TableToJSON(e))
	end

	function S.LbAll()
		local out = {}
		for i, f in ipairs(file.Find(DIR .. "/*.json", "DATA")) do
			local sid = f:gsub("%.json$", "")
			if sid:sub(1, 1) ~= "_" then
				local raw = file.Read(DIR .. "/" .. f, "DATA")
				local t = raw and util.JSONToTable(raw)
				if istable(t) then
					t.sid64 = sid
					out[#out + 1] = t
				end
			end
		end
		return out
	end

	local function readJSON(name, fallback)
		local raw = file.Read(DIR .. "/" .. name, "DATA")
		local t = raw and util.JSONToTable(raw)
		return istable(t) and t or fallback
	end
	local function writeJSON(name, t) file.Write(DIR .. "/" .. name, util.TableToJSON(t)) end

	function S.LbRecords() return readJSON("_records.json", { fastest = {} }) end
	function S.LbHallOfFame() return readJSON("_halloffame.json", {}) end
	-- }}}

	-- // Live tracking during a mission {{{
	S.lbRun = S.lbRun or { boss = {}, life = {} }

	local function runReset()
		S.lbRun = { boss = {}, life = {} }
	end

	local function sidOf(ply)
		return IsValid(ply) and ply:IsPlayer() and not ply:IsBot() and ply:SteamID64() or nil
	end

	-- remember which enemy type an NPC is, so we know on death whether it was a boss
	hook.Add("MapSweepersNPCSpawned", "sweeper_records", function(npc, npcType)
		if IsValid(npc) then npc.sweeperType = npcType end
	end)

	hook.Add("OnNPCKilled", "sweeper_records", function(npc, attacker, inflictor)
		if not (jcms and jcms.director) then return end
		local sid = sidOf(attacker)
		if not sid and IsValid(attacker) and attacker.jcms_owner then sid = sidOf(attacker.jcms_owner) end
		if not sid then return end
		local data = npc.sweeperType and jcms.npc_types and jcms.npc_types[npc.sweeperType]
		if data and (data.danger == jcms.NPC_DANGER_BOSS or data.danger == jcms.NPC_DANGER_RAREBOSS) then
			S.lbRun.boss[sid] = (S.lbRun.boss[sid] or 0) + 1
		end
	end)

	-- how long each player stayed alive, best run of the mission
	local function lifeStart(ply)
		local sid = sidOf(ply)
		if sid then ply.jcms_lbAliveSince = CurTime() end
	end
	local function lifeStop(ply)
		local sid = sidOf(ply)
		if not sid or not ply.jcms_lbAliveSince then return end
		local lived = CurTime() - ply.jcms_lbAliveSince
		S.lbRun.life[sid] = math.max(S.lbRun.life[sid] or 0, lived)
		ply.jcms_lbAliveSince = nil
	end

	hook.Add("PlayerSpawn", "sweeper_records", function(ply)
		timer.Simple(0.2, function()
			if IsValid(ply) and jcms and jcms.director and ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE then
				lifeStart(ply)
			end
		end)
	end)
	hook.Add("PlayerDeath", "sweeper_records", function(ply) lifeStop(ply) end)
	hook.Add("PlayerDisconnected", "sweeper_records", function(ply) lifeStop(ply) end)
	-- }}}

	-- // Writing it all down when the mission ends {{{
	local function implantRankOf(sid64)
		local total = 0
		local d = S.data and S.data[sid64]
		if istable(d) then
			for class, cd in pairs(d) do
				if istable(cd) and tonumber(cd.level) then total = total + cd.level end
			end
		end
		return total
	end

	-- add to both the all-time number and this season's
	local function bump(e, key, amount)
		if amount == 0 then return end
		e[key] = (e[key] or 0) + amount
		e.s[key] = (e.s[key] or 0) + amount
	end
	local function best(e, key, value)
		if (e[key] or 0) < value then e[key] = value end
		if (e.s[key] or 0) < value then e.s[key] = value end
	end

	function S.LbRecordMission(victory)
		if not S.cvar_records:GetBool() then return end
		if jcms.util_IsPVP and jcms.util_IsPVP() then return end
		if jcms.inSpecialMap then return end

		local stats = jcms.director_GetPostMissionStats and jcms.director_GetPostMissionStats()
		if not stats or not stats.players then return end

		-- count the humans who actually played
		local played = 0
		for i, pd in ipairs(stats.players) do
			if pd.wasSweeper and not tostring(pd.sid64):StartWith("BOT_") then played = played + 1 end
		end
		if played < S.cvar_recordsMin:GetInt() then return end

		local missionType = jcms.util_GetMissionType and jcms.util_GetMissionType() or ""
		local streak = (jcms.runprogress and jcms.runprogress.winstreak) or 0
		local records = S.LbRecords()
		local topKills, topKillsWho = 0, nil
		local topLife, topLifeWho = 0, nil

		for i, pd in ipairs(stats.players) do
			local sid = tostring(pd.sid64)
			if pd.wasSweeper and not sid:StartWith("BOT_") then
				-- players still here get their life time closed off first
				local ply = player.GetBySteamID64(sid)
				if IsValid(ply) then lifeStop(ply) end

				local e = S.LbGet(sid)
				e.name = pd.nickname or e.name
				e.lastSeen = os.time()

				local kd = pd.kills_direct or 0
				local kt = pd.kills_defenses or 0
				local ke = pd.kills_explosions or 0
				local kills = kd + kt + ke

				bump(e, "missions", 1)
				bump(e, "kills", kills)
				bump(e, "killsDirect", kd)
				bump(e, "killsTurret", kt)
				bump(e, "killsExplosive", ke)
				bump(e, "bossKills", S.lbRun.boss[sid] or 0)
				bump(e, "deaths", pd.deaths_sweeper or 0)
				bump(e, "orders", pd.ordersUsedCounts or 0)
				if victory then bump(e, "wins", 1) else bump(e, "losses", 1) end
				if pd.evacuated then bump(e, "evacs", 1) end
				if victory then best(e, "bestStreak", streak) end
				best(e, "longestLife", math.floor(S.lbRun.life[sid] or 0))
				e.implantRank = implantRankOf(sid)
				S.LbSave(sid, e)

				if kills > topKills then topKills, topKillsWho = kills, e.name end
				local life = math.floor(S.lbRun.life[sid] or 0)
				if life > topLife then topLife, topLifeWho = life, e.name end
			end
		end

		-- server records
		local now = os.date("%Y-%m-%d")
		if victory and missionType ~= "" and stats.missionTime then
			local t = math.floor(stats.missionTime)
			local prev = records.fastest[missionType]
			if t > 5 and (not prev or t < prev.time) then
				local names = {}
				for i, pd in ipairs(stats.players) do
					if pd.wasSweeper and #names < 6 then names[#names + 1] = pd.nickname end
				end
				records.fastest[missionType] = { time = t, map = game.GetMap(), squad = played,
					names = names, date = now }
				for i, p in ipairs(player.GetHumans()) do
					p:ChatPrint(string.format("[Records] New fastest %s: %d:%02d!",
						language and missionType or missionType, math.floor(t / 60), t % 60))
				end
			end
		end
		if topKillsWho and topKills > (records.mostKills and records.mostKills.value or 0) then
			records.mostKills = { value = topKills, name = topKillsWho, map = game.GetMap(), date = now }
		end
		if topLifeWho and topLife > (records.longestLife and records.longestLife.value or 0) then
			records.longestLife = { value = topLife, name = topLifeWho, map = game.GetMap(), date = now }
		end
		if victory and streak > (records.bestStreak and records.bestStreak.value or 0) then
			records.bestStreak = { value = streak, name = "the squad", map = game.GetMap(), date = now }
		end
		writeJSON("_records.json", records)

		runReset()
	end

	-- the gamemode tells us the mission is over here
	function S.InstallRecordHook()
		if not (jcms and jcms.leaderboard_RoundEnd) or S.Wrapped(jcms, "RoundEnd") then return end
		local orig = jcms.leaderboard_RoundEnd
		S._wrappedRoundEnd = function(isPVP, victory, aliveTeams, ...)
			local r = orig(isPVP, victory, aliveTeams, ...)
			local ok, err = pcall(S.LbRecordMission, victory)
			if not ok then ErrorNoHalt("[sweeper] records: " .. tostring(err) .. "\n") end
			return r
		end
		jcms.leaderboard_RoundEnd = S._wrappedRoundEnd
		S.MarkWrapped(jcms, "RoundEnd")
	end
	hook.Add("Initialize", "sweeper_records", S.InstallRecordHook)
	hook.Add("InitPostEntity", "sweeper_records", S.InstallRecordHook)
	S.InstallRecordHook()
	-- }}}

	-- // Seasons {{{
	-- Called by an admin (or automatically on the first mission of a new month): keep the top three
	-- of each board in the Hall of Fame, then everyone's season numbers start again.
	function S.LbEndSeason(seasonId)
		local hof = S.LbHallOfFame()
		local entry = { season = seasonId or S.lbSeason(), boards = {} }
		local all = S.LbAll()

		for i, board in ipairs(S.lbBoards) do
			-- boards read from the gamemode's files have no seasons, so they aren't archived
			if not board.source then
				local rows = {}
				for j, e in ipairs(all) do
					local season = istable(e.s) and e.s or {}
					if (season.missions or 0) >= (board.minMissions or 1) then
						rows[#rows + 1] = { name = e.name or e.sid64, value = board.calc(season) }
					end
				end
				table.sort(rows, function(x, y)
					if board.lowerIsBetter then return x.value < y.value end
					return x.value > y.value
				end)
				local top = {}
				for j = 1, math.min(3, #rows) do top[j] = rows[j] end
				entry.boards[board.id] = top
			end
		end

		table.insert(hof, 1, entry)
		while #hof > 12 do table.remove(hof) end
		writeJSON("_halloffame.json", hof)

		-- clear everyone's season numbers
		for i, e in ipairs(all) do
			e.s = {}
			e.season = S.lbSeason()
			S.LbSave(e.sid64, e)
		end
	end
	-- }}}

	-- // Sending the boards to a player {{{
	-- The gamemode's own leaderboard: one file per player, wins / losses / streak (PvE) and ELO (PvP)
	local function readOfficial(kind)
		local dir = "mapsweepers/server/leaderboard/" .. kind
		local out = {}
		for i, f in ipairs(file.Find(dir .. "/*.json", "DATA")) do
			local sid = f:gsub("%.json$", "")
			if sid:match("^%d+$") then
				local raw = file.Read(dir .. "/" .. f, "DATA")
				local t = raw and util.JSONToTable(raw)
				if istable(t) then
					t.sid64 = sid
					t.name = t.lastUsedName ~= "" and t.lastUsedName or nil
					out[#out + 1] = t
				end
			end
		end
		return out
	end

	local function buildBoards(forSid, seasonOnly)
		local all = S.LbAll()
		local names = {}
		for i, e in ipairs(all) do if e.name and e.name ~= "" then names[e.sid64] = e.name end end
		local official = { pve = readOfficial("pve"), pvp = readOfficial("pvp") }
		local out = {}
		for i, board in ipairs(S.lbBoards) do
			local rows = {}
			if board.source then
				for j, e in ipairs(official[board.source]) do
					local games = (e.wins or 0) + (e.losses or 0)
					if games >= (board.minGames or 1) then
						rows[#rows + 1] = { name = e.name or names[e.sid64] or e.sid64, sid = e.sid64, value = board.calc(e) }
					end
				end
			else
				for j, e in ipairs(all) do
					local src = seasonOnly and (istable(e.s) and e.s or {}) or e
					local missions = src.missions or 0
					if missions >= (board.minMissions or 1) then
						rows[#rows + 1] = { name = e.name or e.sid64, sid = e.sid64, value = board.calc(src) }
					end
				end
			end
			table.sort(rows, function(a, b)
				if board.lowerIsBetter then return a.value < b.value end
				return a.value > b.value
			end)

			local top, mine = {}, nil
			for j = 1, math.min(10, #rows) do top[j] = { rows[j].name, rows[j].value } end
			for j, row in ipairs(rows) do
				if row.sid == forSid then mine = { j, row.name, row.value } break end
			end
			out[board.id] = { top = top, mine = mine, count = #rows, allTime = board.source ~= nil }
		end
		return out
	end

	net.Receive("sweeper_records", function(len, ply)
		if not IsValid(ply) then return end
		if (ply.jcms_lbNext or 0) > CurTime() then return end
		ply.jcms_lbNext = CurTime() + 1
		local seasonOnly = net.ReadBool()

		local payload = {
			boards = buildBoards(ply:SteamID64(), seasonOnly),
			records = S.LbRecords(),
			hof = S.LbHallOfFame(),
			season = S.lbSeason(),
		}
		net.Start("sweeper_records")
			net.WriteBool(seasonOnly)
			net.WriteTable(payload)
		net.Send(ply)
	end)
	-- }}}

	-- // Admin {{{
	local function adminOnly(ply)
		if IsValid(ply) and not ply:IsAdmin() then ply:ChatPrint("[Records] Admins only.") return false end
		return true
	end

	concommand.Add("jcms_records_reset", function(ply, cmd, args)
		if not adminOnly(ply) then return end
		local target = args[1]
		if not target then return end
		local sid = target:match("^%d+$") and target
		if not sid then
			for i, p in ipairs(player.GetHumans()) do
				if string.find(string.lower(p:Nick()), string.lower(target), 1, true) then sid = p:SteamID64() end
			end
		end
		local msg = "[Records] No player found: " .. tostring(target)
		if sid then
			file.Delete(pathFor(sid))
			msg = "[Records] Wiped records for " .. sid .. "."
		end
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
	end, nil, "Admin: wipe one player's records.")

	concommand.Add("jcms_records_season_end", function(ply)
		if not adminOnly(ply) then return end
		S.LbEndSeason()
		local msg = "[Records] Season closed. Top three of each board kept in the Hall of Fame."
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
	end, nil, "Admin: end the season now and start a new one.")

	concommand.Add("jcms_records_wipe", function(ply, cmd, args)
		if not adminOnly(ply) then return end
		if args[1] ~= "confirm" then
			local msg = "[Records] This wipes EVERY record. Run: jcms_records_wipe confirm"
			if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
			return
		end
		for i, f in ipairs(file.Find(DIR .. "/*.json", "DATA")) do file.Delete(DIR .. "/" .. f) end
		local msg = "[Records] All records wiped."
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
	end, nil, "Admin: wipe every record (needs 'confirm').")
	-- }}}
end

-- ============================================================================================
if CLIENT then
	S.lbData = S.lbData or nil
	S.lbSeasonOnly = false
	local nextAsk = 0

	net.Receive("sweeper_records", function()
		local seasonOnly = net.ReadBool()
		S.lbData = net.ReadTable()
		S.lbData.seasonOnly = seasonOnly
		if IsValid(S.lbPanel) and S.lbPanel.Refresh then S.lbPanel:Refresh() end
	end)

	function S.LbAsk(force)
		if not force and nextAsk > RealTime() then return end
		nextAsk = RealTime() + 2
		net.Start("sweeper_records")
			net.WriteBool(S.lbSeasonOnly)
		net.SendToServer()
	end

	-- // Look: same building blocks as the rest of our menus {{{
	local function colB() return jcms.color_bright end
	local function colA() return jcms.color_bright_alt end
	local function colD() return jcms.color_dark end
	local function polyF(x, y, w, h, pad) jcms.hud_DrawFilledPolyButton(x, y, w, h, pad or 8) end
	local function polyH(x, y, w, h, pad) jcms.hud_DrawHollowPolyButton(x, y, w, h, pad or 8) end

	local function chip(parent, text, isActive, onClick, wide)
		local b = parent:Add("DButton")
		b:SetText("")
		b:SetTall(26)
		b:SetWide(wide or 150)
		b.Paint = function(self, w, h)
			local active = isActive()
			local clr = self:IsHovered() and colA() or colB()
			surface.SetDrawColor(clr)
			if active then
				polyF(0, 0, w, h, 6)
				draw.SimpleText(text, "jcms_small_bolder", w / 2, h / 2, colD(), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			else
				polyH(0, 0, w, h, 6)
				draw.SimpleText(text, "jcms_small_bolder", w / 2, h / 2, clr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			return true
		end
		b.DoClick = function()
			onClick()
			surface.PlaySound("buttons/lightswitch2.wav")
		end
		return b
	end
	-- }}}

	-- // The RECORDS page {{{
	function S.BuildRecordsMenu(root)
		root:Clear()
		S.lbPanel = root
		S.lbBoard = S.lbBoard or "kills"
		S.lbView = S.lbView or "boards"   -- boards / records / hof

		root.Paint = function(self, w, h)
			local bright = colB()
			surface.SetDrawColor(jcms.color_pulsing)
			polyH(0, 0, w, h, 16)

			surface.SetFont("jcms_big")
			local tw, th = surface.GetTextSize("SERVER RECORDS")
			surface.SetDrawColor(bright.r, bright.g, bright.b, 30)
			jcms.hud_DrawNoiseRect(12, 6, tw + 16, th)
			draw.SimpleText("SERVER RECORDS", "jcms_big", 20, 6, bright)

			local sub = S.lbData and (S.lbData.seasonOnly and ("SEASON " .. (S.lbData.season or "")) or "ALL TIME") or "LOADING..."
			draw.SimpleText(sub, "jcms_small_bolder", w - 20, 24, ColorAlpha(bright, 160), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			surface.SetDrawColor(bright.r, bright.g, bright.b, 50)
			jcms.hud_DrawStripedRect(16, 46, w - 32, 3, 32)
			return true
		end

		-- top row: view switch + season switch
		local top = root:Add("DPanel")
		top:SetPos(16, 54)
		top:SetSize(root:GetWide() - 32, 26)
		top.Paint = function() end

		local x = 0
		local function addChip(text, view, wide)
			local c = chip(top, text, function() return S.lbView == view end, function()
				S.lbView = view
				root:Refresh()
			end, wide)
			c:SetPos(x, 0)
			x = x + (wide or 150) + 6
		end
		addChip("BOARDS", "boards", 130)
		addChip("MAP RECORDS", "records", 160)
		addChip("HALL OF FAME", "hof", 160)

		local season = chip(top, "SEASON ONLY", function() return S.lbSeasonOnly end, function()
			S.lbSeasonOnly = not S.lbSeasonOnly
			S.LbAsk(true)
		end, 160)
		season:SetPos(top:GetWide() - 160, 0)

		-- left: board picker (only on the boards view)
		local list = root:Add("DScrollPanel")
		list:SetPos(16, 90)
		list:SetSize(220, root:GetTall() - 106)
		if jcms.paint_ScrollGrip and IsValid(list:GetVBar()) then
			list:GetVBar():SetHideButtons(true)
			list:GetVBar().Paint = function() end
			list:GetVBar().btnGrip.Paint = jcms.paint_ScrollGrip
		end
		for i, board in ipairs(S.lbBoards) do
			local b = chip(list, string.upper(board.label), function() return S.lbBoard == board.id end, function()
				S.lbBoard = board.id
				root:Refresh()
			end, 204)
			b:Dock(TOP)
			b:DockMargin(0, 0, 0, 4)
			b:SetTall(28)
		end

		-- right: the content
		local body = root:Add("DPanel")
		body:SetPos(248, 90)
		body:SetSize(root:GetWide() - 264, root:GetTall() - 106)
		body.Paint = function(self, w, h)
			local bright = colB()
			surface.SetDrawColor(bright.r, bright.g, bright.b, 60)
			polyH(0, 0, w, h, 10)

			if not S.lbData then
				draw.SimpleText("Loading records...", "jcms_medium", w / 2, h / 2, ColorAlpha(bright, 140),
					TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				return true
			end

			if S.lbView == "boards" then
				local board
				for i, b in ipairs(S.lbBoards) do if b.id == S.lbBoard then board = b end end
				local data = board and S.lbData.boards and S.lbData.boards[board.id]
				if not board or not data then return true end

				draw.SimpleText(string.upper(board.label), "jcms_medium", 16, 10, bright)
				local note = data.count .. " ranked"
				if data.allTime then note = note .. "  -  all time (no seasons)" end
				draw.SimpleText(note, "jcms_small", w - 16, 16, ColorAlpha(bright, 120), TEXT_ALIGN_RIGHT)
				surface.SetDrawColor(bright.r, bright.g, bright.b, 40)
				jcms.hud_DrawStripedRect(16, 40, w - 32, 2, 32)

				local y = 52
				if #data.top == 0 then
					draw.SimpleText(board.source and "Nobody has played enough games for this board yet."
						or ("Nothing recorded yet. Play " .. (board.minMissions or 1) .. "+ missions to appear here."),
						"jcms_small", 16, y, ColorAlpha(bright, 120))
				end
				for i, row in ipairs(data.top) do
					local medal = (i == 1 and Color(255, 215, 0)) or (i == 2 and Color(200, 200, 210))
						or (i == 3 and Color(205, 127, 50)) or nil
					local mine = S.lbData.boards[board.id].mine and S.lbData.boards[board.id].mine[1] == i
					if mine then
						surface.SetDrawColor(colA().r, colA().g, colA().b, 30)
						polyF(12, y - 3, w - 24, 24, 5)
					end
					if medal then
						surface.SetDrawColor(medal)
						polyF(16, y + 2, 16, 16, 4)
						draw.SimpleText(i, "jcms_small_bolder", 24, y + 10, colD(), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					else
						draw.SimpleText(i, "jcms_small_bolder", 24, y + 10, ColorAlpha(bright, 140),
							TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
					draw.SimpleText(row[1] or "?", "jcms_small_bolder", 44, y + 10, bright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText(S.LbFormat(board, row[2] or 0), "jcms_medium", w - 16, y + 10, colA(),
						TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
					y = y + 26
				end

				-- your own row, pinned at the bottom
				local mine = data.mine
				surface.SetDrawColor(bright.r, bright.g, bright.b, 40)
				jcms.hud_DrawStripedRect(16, h - 44, w - 32, 2, 32)
				if mine then
					draw.SimpleText("YOU  #" .. mine[1], "jcms_small_bolder", 16, h - 24, colA(), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText(S.LbFormat(board, mine[3] or 0), "jcms_medium", w - 16, h - 24, colA(),
						TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				else
					draw.SimpleText("You aren't ranked on this board yet.", "jcms_small", 16, h - 24,
						ColorAlpha(bright, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end

			elseif S.lbView == "records" then
				draw.SimpleText("MAP RECORDS", "jcms_medium", 16, 10, bright)
				surface.SetDrawColor(bright.r, bright.g, bright.b, 40)
				jcms.hud_DrawStripedRect(16, 40, w - 32, 2, 32)

				local r = S.lbData.records or {}
				local y = 52
				local function line(label, value, sub)
					draw.SimpleText(label, "jcms_small_bolder", 16, y, bright)
					draw.SimpleText(value, "jcms_medium", w - 16, y - 2, colA(), TEXT_ALIGN_RIGHT)
					if sub then
						draw.SimpleText(sub, "jcms_small", 16, y + 16, ColorAlpha(bright, 120))
						y = y + 36
					else
						y = y + 24
					end
				end

				if r.mostKills then
					line("Most kills in one mission", r.mostKills.value or 0,
						(r.mostKills.name or "?") .. "  -  " .. (r.mostKills.map or "") .. "  " .. (r.mostKills.date or ""))
				end
				if r.longestLife then
					local t = r.longestLife.value or 0
					line("Longest life", string.format("%d:%02d", math.floor(t / 60), t % 60),
						(r.longestLife.name or "?") .. "  -  " .. (r.longestLife.map or "") .. "  " .. (r.longestLife.date or ""))
				end
				if r.bestStreak then
					line("Best win streak", r.bestStreak.value or 0, (r.bestStreak.date or ""))
				end

				draw.SimpleText("FASTEST CLEARS", "jcms_small_bolder", 16, y + 6, ColorAlpha(bright, 160))
				y = y + 28
				local any = false
				for missionType, rec in SortedPairs(r.fastest or {}) do
					any = true
					local name = language.GetPhrase("#jcms." .. missionType)
					local t = rec.time or 0
					draw.SimpleText(name, "jcms_small_bolder", 16, y, bright)
					draw.SimpleText(string.format("%d:%02d", math.floor(t / 60), t % 60), "jcms_small_bolder",
						w - 16, y, colA(), TEXT_ALIGN_RIGHT)
					draw.SimpleText((rec.map or "") .. "  -  " .. (rec.squad or "?") .. " players  -  " ..
						table.concat(rec.names or {}, ", "), "jcms_small", 16, y + 15, ColorAlpha(bright, 110))
					y = y + 34
					if y > h - 30 then break end
				end
				if not any then
					draw.SimpleText("No mission has been cleared yet.", "jcms_small", 16, y, ColorAlpha(bright, 120))
				end

			else -- hall of fame
				draw.SimpleText("HALL OF FAME", "jcms_medium", 16, 10, bright)
				surface.SetDrawColor(bright.r, bright.g, bright.b, 40)
				jcms.hud_DrawStripedRect(16, 40, w - 32, 2, 32)
				local y = 52
				local hof = S.lbData.hof or {}
				if #hof == 0 then
					draw.SimpleText("The first season is still running.", "jcms_small", 16, y, ColorAlpha(bright, 120))
				end
				for i, season in ipairs(hof) do
					draw.SimpleText("SEASON " .. (season.season or "?"), "jcms_small_bolder", 16, y, colA())
					y = y + 20
					for j, board in ipairs(S.lbBoards) do
						local top = season.boards and season.boards[board.id]
						if top and top[1] then
							draw.SimpleText(board.label, "jcms_small", 28, y, ColorAlpha(bright, 140))
							draw.SimpleText((top[1].name or "?") .. "  -  " .. S.LbFormat(board, top[1].value or 0),
								"jcms_small_bolder", w - 16, y, bright, TEXT_ALIGN_RIGHT)
							y = y + 18
						end
						if y > h - 24 then break end
					end
					y = y + 10
					if y > h - 24 then break end
				end
			end
			return true
		end

		-- Everything is sized here, every time the page gets its real size. Measuring once while the
		-- lobby was still building gave zero-height panels, which is why the boards didn't show.
		root.PerformLayout = function(self, w, h)
			top:SetPos(16, 54)
			top:SetSize(math.max(0, w - 32), 26)
			season:SetPos(math.max(0, top:GetWide() - 160), 0)
			local listW = 220
			list:SetPos(16, 90)
			list:SetSize(listW, math.max(60, h - 106))
			local boards = S.lbView == "boards"
			body:SetPos(boards and (16 + listW + 12) or 16, 90)
			body:SetSize(math.max(60, w - (boards and (16 + listW + 12 + 16) or 32)), math.max(60, h - 106))
		end

		function root:Refresh()
			list:SetVisible(S.lbView == "boards")
			self:InvalidateLayout(true)
		end
		root:Refresh()
		S.LbAsk()
	end

	function S.OpenRecordsMenu()
		if IsValid(S.recordsFrame) then S.recordsFrame:Remove() end
		local frame = vgui.Create("DFrame")
		S.recordsFrame = frame
		frame:SetSize(math.min(900, ScrW() - 40), math.min(620, ScrH() - 40))
		frame:Center()
		frame:SetTitle("")
		frame:MakePopup()
		frame:ShowCloseButton(false)
		local close = frame:Add("DButton")
		close:SetText("")
		close:SetSize(28, 26)
		close:SetPos(frame:GetWide() - 38, 10)
		close.Paint = function(self, w, h)
			local clr = self:IsHovered() and colA() or colB()
			surface.SetDrawColor(clr)
			polyH(0, 0, w, h, 6)
			draw.SimpleText("X", "jcms_small_bolder", w / 2, h / 2, clr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return true
		end
		close.DoClick = function() frame:Remove() end
		local inner = frame:Add("DPanel")
		inner:Dock(FILL)
		S.BuildRecordsMenu(inner)
	end
	concommand.Add("jcms_records", function() S.OpenRecordsMenu() end, nil, "Open the server records.")
	-- }}}

	-- // The LEADERBOARD tab is our records page {{{
	-- The gamemode builds its wins / losses tables into the tab; we remove them and put the records
	-- page there instead. Its numbers aren't lost: they're the "Missions won", "Win / loss ratio",
	-- "Best win streak" and PvP boards, read straight from the gamemode's own files.
	function S.InstallRecordsTab()
		if not (jcms and jcms.offgame_BuildLeaderboardTab) or S.Wrapped(jcms, "LbTab") then return end
		local orig = jcms.offgame_BuildLeaderboardTab
		S._wrappedLbTab = function(tab, ...)
			local ok0, r = pcall(orig, tab, ...)
			local ok, err = pcall(function()
				for i, child in ipairs(tab:GetChildren()) do
					if IsValid(child) then child:Remove() end
				end
				local root = tab:Add("DPanel")
				root:Dock(FILL)
				root:DockMargin(0, 8, 0, 8)
				S.BuildRecordsMenu(root)
			end)
			if not ok then ErrorNoHalt("[sweeper] records tab: " .. tostring(err) .. "\n") end
			return r
		end
		jcms.offgame_BuildLeaderboardTab = S._wrappedLbTab
		S.MarkWrapped(jcms, "LbTab")
	end
	hook.Add("Initialize", "sweeper_recordsTab", S.InstallRecordsTab)
	hook.Add("InitPostEntity", "sweeper_recordsTab", S.InstallRecordsTab)
	S.InstallRecordsTab()
	-- }}}
end
