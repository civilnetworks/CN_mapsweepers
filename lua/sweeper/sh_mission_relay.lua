--[[
	Map Sweepers - Implants & Class Levels (addon)
	Mission type: Relay Network.

	Comms relays are scattered around the map. Each one has to be started by hand and then
	held for a full transmission - while a relay transmits it screams on every hostile band,
	so the locals come for it. If they smash it, that relay's progress is lost and it reboots.
	Get every relay online, then evac.

	Nothing in the mapsweepers gamemode folder is edited: the mission and its prefab are
	registered into the gamemode's own tables at Initialize time.
--]]

local S = sweeper

-- // Tuning {{{
	S.relayMission = S.relayMission or {
		transmitTime = 60,    -- seconds of uptime one relay needs
		health       = 900,   -- relay hitpoints while transmitting
		aggroRange   = 1500,  -- how far a transmitting relay pulls enemies
		rebootTime   = 10,    -- seconds before a smashed relay can be started again
		relaysMin    = 3,
		relaysMax    = 6
	}
-- }}}

if SERVER then

-- // Prefab {{{
	function S.InstallRelayPrefab()
		if not (jcms and jcms.prefabs) then return end
		if jcms.prefabs.skills_relay then return end

		jcms.prefabs.skills_relay = {
			check = function(area)
				if area:GetSizeX() < 130 or area:GetSizeY() < 130 then return false end

				local center = jcms.mapgen_AreaPointAwayFromEdges(area, 160)
				if not center then return false end

				local tr = util.TraceHull {
					start = center,
					endpos = center + Vector(0, 0, 90),
					mins = Vector(-30, -30, 0),
					maxs = Vector(30, 30, 76)
				}

				if tr.Hit then return false end
				return true, center
			end,

			stamp = function(area, center)
				local relay = ents.Create("sweeper_relay")
				if not IsValid(relay) then return end

				relay:SetPos(center)
				relay:SetAngles( Angle(0, math.random(0, 3) * 90, 0) )
				jcms.mapgen_DropEntToNav(relay)
				relay:Spawn()

				return relay
			end
		}
	end
-- }}}

-- // Mission {{{
	local function relayCounts(missionData)
		local done, total, sending = 0, 0, false

		for i = #missionData.relays, 1, -1 do
			local relay = missionData.relays[i]
			if IsValid(relay) then
				total = total + 1
				local state = relay:GetRelayState()
				if state == 2 then
					done = done + 1
				elseif state == 1 then
					sending = true
				end
			else
				table.remove(missionData.relays, i)
			end
		end

		return done, total, sending
	end

	function S.InstallRelayMission()
		if not (jcms and jcms.missions) then return end
		S.InstallRelayPrefab()
		if jcms.missions.skills_relaynetwork then return end

		jcms.missions.skills_relaynetwork = {
			faction = "any",
			pvpAllowed = false,

			generate = function(data, missionData)
				local cfg = S.relayMission
				local difficulty = jcms.runprogress_GetDifficulty()
				local count = math.Clamp(math.ceil(difficulty * 3), cfg.relaysMin, cfg.relaysMax)

				local relays = jcms.mapgen_SpreadPrefabs("skills_relay", count, 130, true)

				if not relays or #relays == 0 then
					error("Couldn't place any comms relays. This map is too cramped, pick a bigger one.")
				end

				missionData.relays = relays
				jcms.mapgen_Wait( 0.9 )

				jcms.mapgen_PlaceNaturals( jcms.mapgen_AdjustCountForMapSize(10) )
				jcms.mapgen_PlaceEncounters()
			end,

			think = function(director)
				local missionData = director.missionData
				if not missionData.relayActive then return end

				local target
				for i, relay in ipairs(missionData.relays or {}) do
					if IsValid(relay) and relay:GetRelayState() == 1 then
						target = relay
						break
					end
				end
				if not IsValid(target) then return end

				-- Enemies that can't see anyone head for the noisy relay instead of wandering.
				local ply = director.strongestPlayer
				if not IsValid(ply) then return end

				for i, npc in ipairs(director.npcs or {}) do
					if IsValid(npc) and math.random() < 0.35 and not npc:Visible(ply) then
						npc:UpdateEnemyMemory(ply, target:WorldSpaceCenter())
					end
				end
			end,

			tagEntities = function(director, missionData, tags)
				for i, relay in ipairs(missionData.relays or {}) do
					if IsValid(relay) then
						tags[relay] = {
							name = "#jcms.skills_relay_ent",
							moving = false,
							active = relay:GetRelayState() ~= 2
						}
					end
				end
			end,

			getObjectives = function(missionData)
				local done, total, sending = relayCounts(missionData)
				missionData.relaysDone = done
				missionData.relaysTotal = total
				missionData.relayActive = sending

				local missionTime = CurTime() - jcms.director.missionStartTime

				if total > 0 and done >= total and missionTime > 10 then
					missionData.evacuating = true

					if not IsValid(missionData.evacEnt) then
						missionData.evacEnt = jcms.mission_DropEvac(jcms.mission_PickEvacLocation())
					end

					return jcms.mission_GenerateEvacObjective()
				end

				if (not missionData.lastRelayCount) or missionData.lastRelayCount < done then
					missionData.lastRelayCount = done
					jcms.net_SendTip("all", true, "#jcms.skills_relaynetwork_completion", done / math.max(1, total))
				end

				return {
					{
						type = "skills_relay",
						progress = done,
						total = math.max(1, total),
						completed = (total > 0) and (done >= total)
					}
				}
			end,

			swarmCalcCost = function(director, swarmCost)
				return swarmCost + 2 -- same head start hacking missions get
			end,

			swarmCalcCooldown = function(director, baseCooldown, swarmCost)
				local missionData = director.missionData

				if missionData.relayActive then
					return baseCooldown * 0.55 -- a live relay is what brings the pressure
				end

				if missionData.relaysTotal and missionData.relaysTotal > 0 then
					return Lerp(missionData.relaysDone / missionData.relaysTotal, baseCooldown, baseCooldown * 0.8)
				end

				return baseCooldown
			end
		}
	end
-- }}}

-- // Debug {{{
	-- "Why isn't the counter moving?" - dumps what the mission and every relay actually think is happening.
	concommand.Add("sweeper_relaydebug", function(ply)
		local out = {}
		local function line(fmt, ...) out[#out + 1] = string.format(fmt, ...) end

		local d = jcms and jcms.director
		line("--- Relay Network debug ---")
		line("mission type: %s   registered: %s",
			tostring(d and d.missionType),
			tostring(jcms and jcms.missions and jcms.missions.skills_relaynetwork ~= nil))

		local worldRelays = ents.FindByClass("sweeper_relay")
		line("relays existing in the world: %d", #worldRelays)

		local md = d and d.missionData
		if not md then
			line("no missionData (no mission running?)")
		else
			local relays = md.relays
			line("missionData.relays: %s tracked", relays and tostring(#relays) or "nil")
			for i, r in ipairs(relays or {}) do
				if IsValid(r) then
					line("  [%d] %s  state=%d progress=%.3f hp=%d/%d  uses=%d thinks=%d",
						i, tostring(r), r:GetRelayState(), r:GetProgress(),
						r:Health(), r:GetMaxHealth(), r.jcms_useCount or 0, r.jcms_thinkCount or 0)
				else
					line("  [%d] INVALID (removed)", i)
				end
			end
			line("last counted: done=%s total=%s active=%s",
				tostring(md.relaysDone), tostring(md.relaysTotal), tostring(md.relayActive))
		end

		-- Anything in the world the mission isn't tracking is the real problem.
		if md and md.relays then
			local tracked = {}
			for i, r in ipairs(md.relays) do tracked[r] = true end
			local untracked = 0
			for i, r in ipairs(worldRelays) do
				if not tracked[r] then untracked = untracked + 1 end
			end
			if untracked > 0 then
				line("WARNING: %d relay(s) in the world are NOT in missionData.relays", untracked)
			end
		end

		line("state key: 0=idle 1=sending 2=done 3=reboot")

		local msg = table.concat(out, "\n")
		if S.PrintConsole then S.PrintConsole(IsValid(ply) and ply or nil, msg) else print(msg) end
	end, nil, "Dumps Relay Network mission state (Implants addon).")
-- }}}

else

-- // Client mission entry + names {{{
	function S.InstallRelayMission()
		if not (jcms and jcms.missions) then return end
		if jcms.missions.skills_relaynetwork then return end

		jcms.missions.skills_relaynetwork = {
			faction = "any",
			tags = { "hacking", "killsrequired" }
		}
	end

	language.Add("jcms.skills_relaynetwork", "Relay Network")
	language.Add("jcms.skills_relaynetwork_desc", "A string of comms relays went dark out here. Start each one by hand and hold it until the transmission clears - everything nearby will come to shut it up.")
	language.Add("jcms.skills_relaynetwork_completion", "%d%% of the relay network is online")

	language.Add("jcms.obj_skills_relay", "Bring the comms relays online")
	language.Add("jcms.skills_relay_ent", "Comms Relay")

	language.Add("jcms.skills_relay_started", "Relay transmitting - keep it standing")
	language.Add("jcms.skills_relay_lost", "Relay destroyed - transmission lost")
	language.Add("jcms.skills_relay_done", "Relay online")
-- }}}

end

hook.Add("Initialize", "sweeper_relaymission", function() S.InstallRelayMission() end)
hook.Add("InitPostEntity", "sweeper_relaymission", function() S.InstallRelayMission() end)
