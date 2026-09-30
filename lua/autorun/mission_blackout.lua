hook.Add("MapSweepersReady", "np_msexp_blackout", function()
		
	if SERVER then
	
		jcms.prefabs.lightgenerator = {
		
			check = function(area)
				local center = jcms.mapgen_AreaPointAwayFromEdges(area, 120)
				local tr = util.TraceHull { start = center, endpos = center + Vector(0, 0, 100), mins = Vector(-36, -36, 0), maxs = Vector(36, 36, 64) }
				
				if not tr.Hit then
					return true, center
				else
					return false
				end
			end,
			
			stamp = function(area, center)
				
				local generator = ents.Create("jcms_lightgenerator")
				generator:SetPos(center)
				generator:Spawn()
				
				if not IsValid(generator) then return end
				
				local terminal = ents.Create("jcms_terminal")
				terminal:SetPos(generator:GetPos() + generator:GetAngles():Forward()*-5 + generator:GetAngles():Right()*-30)
				terminal:SetAngles(generator:GetAngles() + Angle(0,90,0))
				
				terminal:Spawn()
				
				if not IsValid(terminal) then return end
				
				terminal:InitAsTerminal("models/props_combine/combine_interface001a.mdl", "jcorp_lightgen", function(ent, cmd, data, ply)
					if IsValid(generator) then
						generator:SetIsPowered(true)
					end
					jcms.director.darknessEntity:SetGeneratorsActive(jcms.director.darknessEntity:GetGeneratorsActive() + 1)
					jcms.director.darknessEntity:AdjustLighting()
					jcms.director.darknessDMGScale = jcms.director.darknessDMGScale - ((1/jcms.director.darknessEntity:GetMaxGenerators()) * 0.4)
					return true, "1"
				end)
				terminal:SetSkin(1)
				terminal:SetNWEntity("jcms_link", generator)
				
				return generator
			end
		}
		
		local function cleanUpGenerators(lightGenerators)
			for _, generator in pairs(lightGenerators) do
				generator:Remove()
			end
		end
		
		jcms.missions.blackout = {
			faction = "any",
			
			

			generate = function(data, missionData)
				local difficulty = jcms.runprogress_GetDifficulty()

				jcms.mapgen_PlaceNaturals( jcms.mapgen_AdjustCountForMapSize(16) )
				jcms.mapgen_PlaceEncounters()
				
				-- Lua logic for generating your mission here.
				local count = math.Clamp(math.ceil( jcms.runprogress_GetDifficulty() * 4),4,15)
				
				for i = 1,4 do
					missionData.lightGenerators = jcms.mapgen_SpreadPrefabs("lightgenerator", count, 70, true)
				
	
					if #missionData.lightGenerators < 4 then
						if i == 4 then
							error("Failed to place 4 light generators down. Try a different map maybe?")
						else
							cleanUpGenerators(missionData.lightGenerators)
						end
					else
						break
					end
				end
				
				local darknessEnt = ents.Create("jcms_blackouteffect")
				darknessEnt:Spawn()
				darknessEnt:SetMaxGenerators(count)
				jcms.director.darknessDMGScale = 1.4
				jcms.director.darknessEntity = darknessEnt
			end,
			
			tagEntities = function(director, missionData, tags)
				for i, generator in ipairs(missionData.lightGenerators) do
					tags[generator] = { name = "#jcms.lightgenerator", moving = false, active = IsValid(generator) and not generator:GetIsPowered() }
				end
			end,

			getObjectives = function(missionData)
				local lightGenerators = missionData.lightGenerators
				local poweredGens = 0
				
				local objectivesTable = {}
				
				for i=#lightGenerators, 1, -1 do 
					local generator = lightGenerators[i]
					if IsValid(generator) then 
						if generator:GetIsPowered() then 
							poweredGens = poweredGens + 1
						end
						table.insert(objectivesTable,{type="lightgenerator",progress=generator:GetIsPowered() and 1 or 0,total=1,completed=generator:GetIsPowered(),percent=false})
					else
						table.remove(lightGenerators, i)
					end
				end
				
				local completed = (poweredGens == #lightGenerators) -- Set to true if all objectives are ocmplete.
				
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

					return {
						{
							type="lightgenerator",
							progress=poweredGens,
							total=#lightGenerators,
							completed = (poweredGens == #lightGenerators)
						}
					}
				end
			end
		}
	end

	if CLIENT then
		jcms.missions.blackout = {
			faction = "any",
			tags = { 'hacking', 'naturalhazard' }
			-- Valid mission tags: 'hacking', 'infighting', 'timer', 'extraorders', 'rarebosses', 'killsrequired', 'naturalhazard'
		}
	end

end)