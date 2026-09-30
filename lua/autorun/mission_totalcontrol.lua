hook.Add("MapSweepersReady", "np_msexp_totalcontrol", function()
		
	if SERVER then
	
		jcms.prefabs.controlzone = {
		
			check = function(area)
				return area:IsFlat() and ( area:GetSizeX()*area:GetSizeY() ) > 60000
			end,
			
			stamp = function(area, data)
				local v = area:GetCenter() + area:GetRandomPoint()
				v:Mul(0.5)
				
				local zone = ents.Create("jcms_zonecontrol")
				zone:SetPos(v)
				zone:Spawn()
				
				return zone
			end
		}
	
		jcms.missions.totalcontrol = {
			faction = "any",

			generate = function(data, missionData)
				local difficulty = jcms.runprogress_GetDifficulty()

				jcms.mapgen_PlaceNaturals( jcms.mapgen_AdjustCountForMapSize(16) )
				jcms.mapgen_PlaceEncounters()

				-- Lua logic for generating your mission here.
				local count = math.Clamp(math.ceil( jcms.runprogress_GetDifficulty() * 3),3,12)
				missionData.controlZones = jcms.mapgen_SpreadPrefabs("controlzone", count, 300, true)
			end,
			
			tagEntities = function(director, missionData, tags)
				for i, zone in ipairs(missionData.controlZones) do
					tags[zone] = { name = "#jcms.zonecontrol", moving = false, active = IsValid(zone) and not zone:GetIsCaptured() }
				end
			end,

			getObjectives = function(missionData)
				local controlZones = missionData.controlZones
				local capturedZones = 0
				
				local objectivesTable = {}
				
				for i=#controlZones, 1, -1 do 
					local zone = controlZones[i]
					if IsValid(zone) then 
						if zone:GetIsCaptured() then 
							capturedZones = capturedZones + 1
						end
						table.insert(objectivesTable,{type="controlzone",progress=zone:GetCaptureProgress()*100,total=100,completed=zone:GetIsCaptured(),percent=true})
					else
						table.remove(controlZones, i)
					end
				end
				
				local completed = (capturedZones == #controlZones) -- Set to true if all objectives are ocmplete.
				
				if completed then
					-- If the mission is completed, we place down the evac.
					missionData.evacuating = true 

					if not IsValid(missionData.evacEnt) then
						missionData.evacEnt = jcms.mission_DropEvac(jcms.mission_PickEvacLocation(), 45)
					end
					
					return jcms.mission_GenerateEvacObjective() -- Automatically generates "Charge evac" then "Evacuate" objectives..
				else
					-- List of your objectives.
					-- 'type' is the name of the objective. It is localized as #jcms.obj_<type here>. For example type = "j" gets localized as "#jcms.obj_j" AKA "Kill everyone"
					-- If 'progress' is 0 and 'total' is 0, this objective will have no progress bar.
					-- If 'percent' is false, then objective will be displayed as "progress/total", for example: "5/25".
					-- If 'percent' is true, then objective will be displayed as a percentage ("20%" instead of "5/25")
					-- If 'completed' is true, the objective will be highlighted in blue. This is purely visual.

					return objectivesTable
				end
			end
		}
	end

	if CLIENT then
		jcms.missions.totalcontrol = {
			faction = "any",
			tags = { }
			-- Valid mission tags: 'hacking', 'infighting', 'timer', 'extraorders', 'rarebosses', 'killsrequired', 'naturalhazard'
		}
	end

end)