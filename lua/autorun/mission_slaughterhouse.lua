hook.Add("MapSweepersReady", "faction_slaughterhouse_mission", function()
		
	if SERVER then
		jcms.missions.slaughterhouse = {
			faction = "any",

			generate = function(data, missionData)
				local difficulty = jcms.runprogress_GetDifficulty()

				jcms.mapgen_PlaceNaturals(jcms.mapgen_AdjustCountForMapSize(16))
				jcms.mapgen_PlaceEncounters()

				missionData.kills = 0
				local scaledDifficulty = difficulty^(2/3)
				missionData.kills_req = math.ceil(150 * scaledDifficulty)

				missionData.escalationStage = 0

				hook.Add("OnNPCKilled", "slaughterhouse_KillTracker", function(npc, attacker, inflictor)
					if not (jcms.director and jcms.director.missionType == "slaughterhouse" and jcms.director.missionData and jcms.director.missionData.kills) then
						hook.Remove("OnNPCKilled", "slaughterhouse_KillTracker")
					else
						if IsValid(npc) and IsValid(attacker) and jcms.team_JCorp(attacker) then
							local md = jcms.director.missionData
							md.kills = math.min(md.kills_req, md.kills + 1)

							local progress = md.kills / md.kills_req
							if progress >= 0.75 and md.escalationStage < 3 then
								jcms.net_SendTip("all", true, "#jcms.75complete", 1)
								md.escalationStage = 3
							elseif progress >= 0.5 and md.escalationStage < 2 then
								jcms.net_SendTip("all", true, "#jcms.50complete", 1)
								md.escalationStage = 2
							elseif progress >= 0.25 and md.escalationStage < 1 then
								jcms.net_SendTip("all", true, "#jcms.25complete", 1)
								md.escalationStage = 1
							end
						end
					end
				end)
			end,

			swarmCalcCooldown = function(director, baseCooldown, swarmCost)
				local md = director.missionData
				if not (md and md.kills_req and md.kills_req > 0) then
					return baseCooldown / 2
				end

				local progress = md.kills / md.kills_req
				local multiplier = 2 

				if progress >= 0.75 then
					multiplier = 5
				elseif progress >= 0.5 then
					multiplier = 4
				elseif progress >= 0.25 then
					multiplier = 3
				end

				return baseCooldown / multiplier
			end,

			getObjectives = function(missionData)
				local completed = missionData.kills >= missionData.kills_req
				
				if completed then
					missionData.evacuating = true 

					if not IsValid(missionData.evacEnt) then
						missionData.evacEnt = jcms.mission_DropEvac(jcms.mission_PickEvacLocation(), 45)
					end
					
					return jcms.mission_GenerateEvacObjective()
				else
					return { 
						{ type = "slaughterhousekilltotal", progress = missionData.kills, total = missionData.kills_req, completed = missionData.kills >= missionData.kills_req },
					}
				end
			end
		}
	end

	if CLIENT then
		jcms.missions.slaughterhouse = {
			faction = "any",
			tags = { "killsrequired" }
		}
	end

end)
