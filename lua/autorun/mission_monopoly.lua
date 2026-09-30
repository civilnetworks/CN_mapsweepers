hook.Add("MapSweepersReady", "np_msexp_monopolytakeover", function()
		
	if SERVER then
	
		local function PickUniqueReward()
			if #jcms.np_monopoly_rewardIds == 0 then return 1 end -- should not happen but just to be safe.
			
			local RandomIndex = math.random(1,#jcms.np_monopoly_rewardIds)
			local PickedValue = jcms.np_monopoly_rewardIds[RandomIndex]
			table.remove(jcms.np_monopoly_rewardIds,RandomIndex)
			
			return PickedValue
		end
	
		jcms.prefabs.casinoterminal = {
		
			check = function(area)
				local wallspots, normals = jcms.prefab_GetWallSpotsFromArea(area, 20, 20)
				
				if #wallspots > 0 then
					local rng = math.random(#wallspots)
					return true, { pos = wallspots[rng], normal = normals[rng] }
				else
					return false
				end
			end,
			
			stamp = function(area, data)
			
			
				local terminal = ents.Create("jcms_rggcasinoterminal")
				if not IsValid(terminal) then return end
				
				
				terminal:SetPos(data.pos)
				terminal:SetAngles(data.normal:Angle())
				terminal:Spawn()
				
				terminal:SetID(1)
				--terminal:SetID(jcms.np_next_screen_id)
				
				local terminal2 = ents.Create("jcms_terminal")
				terminal2:SetPos(terminal:GetPos() + terminal:GetAngles():Right()*72+ terminal:GetAngles():Forward()*15)
				jcms.mapgen_DropEntToNav(terminal2)
				terminal2:SetAngles(terminal:GetAngles())
				terminal2:Spawn()
				
				terminal2:InitAsTerminal("models/jcms/rgg_node.mdl", "rgg_flatscreen", function(ent, cmd, data, ply)
					terminal:SetID(jcms.np_next_screen_id)
					terminal:ConvertToJCorp()
					terminal:SetUniqueReward(PickUniqueReward())
					terminal2:SetNWBool("osinstall",true)
					jcms.np_next_screen_id = jcms.np_next_screen_id + 1
					return true, "1"
				end)
				
				terminal2:SetNWEntity("jcms_link", terminal)

				
				return terminal
			end
		}
	
		jcms.missions.monopolytakeover = {
			faction = "rebel",

			generate = function(data, missionData)
				local difficulty = jcms.runprogress_GetDifficulty()
				jcms.np_monopoly_rewardIds = {1,2,3,4,5,6,7,8}
				jcms.np_next_screen_id = 1

				jcms.mapgen_PlaceNaturals( jcms.mapgen_AdjustCountForMapSize(14) )
				jcms.mapgen_PlaceEncounters()
				
				for _, ply in pairs(player.GetAll()) do 
					if ply.jcms_np_upgrades then
						ply.jcms_np_upgrades = {}
					end
				end
				
				net.Start("jcms_np_resetupg")
				net.Broadcast()

				-- Lua logic for generating your mission here.
				local count = math.Clamp(math.ceil( jcms.runprogress_GetDifficulty() * 2),2,5)
				missionData.casinoTerminals = jcms.mapgen_SpreadPrefabs("casinoterminal", count, 100, true)
			end,
			
			tagEntities = function(director, missionData, tags)
				for i, terminal in ipairs(missionData.casinoTerminals) do
					if not terminal:GetConverted() then
						tags[terminal] = { name = "#jcms.casinoterminal", moving = false, active = IsValid(terminal) and not terminal:GetConverted() }
					else
						tags[terminal] = { name = "#jcms.casinoterminalhacked", moving = false, active = IsValid(terminal) and not terminal:GetReportBought() }
					end
				end
			end,

			getObjectives = function(missionData)
				local casinoTerminals = missionData.casinoTerminals
				local reportsBought = 0
				
				local objectivesTable = {}
				
				for i=#casinoTerminals, 1, -1 do 
					local terminal = casinoTerminals[i]
					if IsValid(terminal) then 
						if not terminal:GetConverted() then
							table.insert(objectivesTable,{type="hackcasinoterminal",progress=terminal:GetConverted() and 1 or 0,total=1,completed=terminal:GetConverted(),percent=false})
						else
							table.insert(objectivesTable,{type="businessreports",progress=terminal:GetReportBought() and 1 or 0,total=1,completed=terminal:GetReportBought(),percent=false})
						end
						if terminal:GetReportBought() then 
							reportsBought = reportsBought + 1
						end
						
					else
						table.remove(casinoTerminals, i)
					end
				end
				
				local completed = (reportsBought == #casinoTerminals) -- Set to true if all objectives are ocmplete.
				
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
		jcms.missions.monopolytakeover = {
			faction = "rebel",
			tags = {hacking}
			-- Valid mission tags: 'hacking', 'infighting', 'timer', 'extraorders', 'rarebosses', 'killsrequired', 'naturalhazard'
		}
	end

end)