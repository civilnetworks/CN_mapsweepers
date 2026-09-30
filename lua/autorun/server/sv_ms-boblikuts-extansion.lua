hook.Add("MapSweepersReady", "boblikut's missions", function()

	---------------------------
	--		  GENERATOR		  -
	---------------------------
	
	jcms.prefabs.generator = {
		check = function(area)
				local center = area:GetCenter()
				local tr = util.TraceHull { start = center, endpos = center + Vector(0, 0, 100), mins = Vector(-24, -24, 0), maxs = Vector(24, 24, 64) }
				
				if not tr.Hit then
					return true, center
				else
					return false
				end
			end,

			stamp = function(area, center)
				local generator = ents.Create("jcms_generator")
				if not IsValid(generator) then return end
				generator:SetPos(center + Vector(0,0,150))
				generator:SetAngles( Angle(0, math.random(1, 4)*90, 0) )

				generator:Spawn()

				return generator
			end
	}
	jcms.prefabs.energy_block = {
		check = function(area)
				local center = area:GetCenter()
				local tr = util.TraceHull { start = center, endpos = center + Vector(0, 0, 20), mins = Vector(-6, -6, 0), maxs = Vector(6, 6, 16) }
				
				if not tr.Hit then
					return true, center
				else
					return false
				end
			end,

			stamp = function(area, center)
				local energy_block = ents.Create("jcms_energy_block")
				if not IsValid(energy_block) then return end
				energy_block:SetPos(center)
				energy_block:SetAngles( Angle(0, math.random(1, 4)*90, 0) )

				energy_block:Spawn()

				return energy_block
			end
	}
	jcms.missions.generator = {
		faction = "any",

		generate = function(data, missionData)
			local generator = jcms.mapgen_SpreadPrefabs("generator", 1, 125, true)

			if #generator == 0 then
				error("Couldn't place generator. This map sucks, find a bigger one.")
			end
			
			local energy_blocks = jcms.mapgen_SpreadPrefabs("energy_block", 10, 20)
			
			if #energy_blocks == 0 then
				error("Couldn't place enough energy_blocks. This map sucks, find a bigger one.")
			end
			
			generator[1].hp = #energy_blocks - 2
			missionData.generator = generator[1]
			missionData.energy_blocks = energy_blocks
			missionData.energy_blocksCount = #energy_blocks

			jcms.mapgen_PlaceNaturals(jcms.mapgen_AdjustCountForMapSize(24))
			jcms.mapgen_PlaceEncounters()
		end,

		tagEntities = function(director, missionData, tags)
			local generator = missionData.generator
			local energy_blocks = missionData.energy_blocks
			tags[generator] = { id = "Generator", name = "#jcms.generator", moving = false, active = !generator:GetNWBool("working") }
			for k, v in ipairs(energy_blocks) do
				tags[v] = { id = "block"..k, name = "#jcms.energy_block", moving = true, active = v:IsValid() }
			end
		end,

		getObjectives = function(missionData)
			local progress = (missionData.energy_blocksCount - 2) - missionData.generator.hp
			if progress < (missionData.energy_blocksCount - 2) then
				return {
					{ 
						type = "generator", 
						progress = math.min(missionData.energy_blocksCount - 2, progress),
						total = missionData.energy_blocksCount - 2,
						completed = progress >= missionData.energy_blocksCount - 2
					}
				}
			else
				missionData.evacuating = true
			
				if not IsValid(missionData.evacEnt) then
					missionData.evacEnt = jcms.mission_DropEvac(jcms.mission_PickEvacLocation(), 5)
				end
				
				return jcms.mission_GenerateEvacObjective()
			end
		end,
	}
	
	---------------------------
	--		  GUNTEST		  -
	---------------------------
	
	if !file.Exists("mapsweepers/server/ft_blacklist.json", "DATA") then
		file.Write("mapsweepers/server/ft_blacklist.json", "{}")
		jcms.ft_bl = {}
	else
		local str = file.Read("mapsweepers/server/ft_blacklist.json", "DATA")
		local tbl = util.JSONToTable(str)
		jcms.ft_bl = tbl
	end
	
	
	local requied_kills = 20
	
	jcms.terminal_modeTypes.guntest_terminal = {
		command = function(ent, cmd, data, ply)  
			if ent:GetNWBool("jcms_terminal_locked") then  
				if cmd == 0 then  
					jcms.terminal_ToUnlock(ent)  
					return true  
				end  
			else  
				if cmd == 1 then
					ent.jcms_terminal_Callback(ent, cmd, data, ply)
					return true, "gotten"  
				end  
			end  
		end,
		generate = function(ent) return "" end
	}
	
	jcms.prefabs.guntest_terminal = {
			check = function(area)
				local center = area:GetCenter()
				local tr = util.TraceHull { start = center, endpos = center + Vector(0, 0, 64), mins = Vector(-24, -24, 0), maxs = Vector(24, 24, 64) }
				
				if not tr.Hit then
					return true, center
				else
					return false
				end
			end,

			stamp = function(area, center)
				local prop = ents.Create("prop_physics")
				if not IsValid(prop) then return end
				prop:SetModel("models/props_phx/construct/metal_angle360.mdl")
				prop:SetColor(Color(255,0,0))
				local terminal = ents.Create("jcms_terminal")
				prop:SetPos(center)
				prop:SetAngles( Angle(0, math.random(1, 4)*90, 0) )
				local propPos, propAngles = prop:GetPos(), prop:GetAngles()
				terminal:SetPos(propPos + propAngles:Right()*72)

				prop:Spawn()
				local phys = prop:GetPhysicsObject()
				if phys:IsValid() then
					phys:EnableMotion(false)
				end
				
				local function isWeaponTesting(class)
					local td = jcms.director.missionData.testing_data
					for k, v in ipairs(td) do
						if v.testing_weapon == class then return true end
					end
					return false
				end
				
				terminal:InitAsTerminal("models/props_combine/breenconsole.mdl", "guntest_terminal", function(ent, cmd, data, ply)
					local _, class = table.Random(jcms.weapon_prices)
					while jcms.ft_bl[class] or isWeaponTesting(class) do
						_, class = table.Random(jcms.weapon_prices)
					end

					local wm_ent = ents.Create(class)
					wm_ent:Spawn()
					local wm = wm_ent:GetModel()
					wm_ent:Remove()
					
					local wep = ents.Create("jcms_testing_weapon")
					local wep_tab = weapons.Get(class)
					wep.PrintName = (wep_tab and wep_tab.PrintName) or class
					print(wep.PrintName.." ("..class..")")
					wep:SetModel(wm)
					wep.wep_class = class
					if not IsValid(wep) then return end
					local prop = ent:GetNWEntity("jcms_link")
					local pos = prop:GetPos() + Vector(0,0,100)
					wep:SetPos(pos)
					wep:Spawn()
					local ed = EffectData()  
					ed:SetColor(jcms.util_colorIntegerJCorp)  
					ed:SetFlags(1)
					ed:SetMagnitude(1)					
					ed:SetOrigin(pos + Vector(0, 0, 156))
					ed:SetStart(pos + Vector(0,0,-60))
					ed:SetEntity(wep)
					ed:SetScale(1)				
					util.Effect("jcms_spawneffect", ed)
					prop.wep_given = true
				end)
				
				terminal:SetAngles( propAngles )
				terminal:Spawn()
				terminal:SetNWEntity("jcms_link", prop)

				return prop
			end
		}
	
	local lang_convar = CreateConVar("jcms_bob_lang", "en", {FCVAR_ARCHIVE})
	local obj_guntestkills = {
		en = "Eliminate enemies to test %s",
		ru = "Убивайте врагов, чтобы испытать %s",
	}
	
	jcms.missions.guntest = {
		faction = "any",

		generate = function(data, missionData)
			missionData.testing_data = {}
			local guntest_terminals = jcms.mapgen_SpreadPrefabs("guntest_terminal", 4, 125, true)

			if #guntest_terminals == 0 then
				error("Couldn't place guntest terminals. This map sucks, find a bigger one.")
			end
			
			missionData.guntest_terminals = guntest_terminals
			missionData.guntest_terminals_count = #guntest_terminals

			jcms.mapgen_PlaceNaturals(jcms.mapgen_AdjustCountForMapSize(24))
			jcms.mapgen_PlaceEncounters()
		end,

		tagEntities = function(director, missionData, tags)
			local guntest_terminals = missionData.guntest_terminals
			for k, v in ipairs(guntest_terminals) do
				tags[v] = { id = "guntest_terminal"..k, name = "#jcms.terminal", moving = false, active = !v.wep_given }
			end
		end,

		getObjectives = function(missionData)
			local total = missionData.guntest_terminals_count
			local objs = {}
			local testing_data = missionData.testing_data
			local tested = 0
			for k, v in ipairs(testing_data) do 
				if v.npc_killed >= requied_kills then
					tested = tested + 1
				end
			end
			objs[#objs + 1] = { 
						type = "guntest", 
						progress = math.min(total, tested),
						total = total,
						completed = tested >= total
					}
			local getting_progress = 0
			for k, v in ipairs(missionData.guntest_terminals) do
				if v.wep_given then
					getting_progress = getting_progress + 1
				end
			end
			objs[#objs + 1] = { 
						type = "gunget", 
						progress = math.min(total, getting_progress),
						total = total,
						completed = getting_progress >= total
					}
			for k, v in ipairs(testing_data) do
				objs[#objs + 1] = {
					type = "guntestkills",
					format = {v.testing_weapon_name},
					progress = v.npc_killed,
					total = requied_kills,
					completed = v.npc_killed >= requied_kills
				}
			end
			if tested < total then
				return objs
			else
				missionData.evacuating = true
			
				if not IsValid(missionData.evacEnt) then
					missionData.evacEnt = jcms.mission_DropEvac(jcms.mission_PickEvacLocation(), 5)
				end
				
				return jcms.mission_GenerateEvacObjective()
			end
		end,
	}
	
	
	---------------------------
	--		  HOOKS		  	 --
	---------------------------
	
	hook.Add("OnNPCKilled", "guntest_OnNPCKilled_hook", function(npc, attacker, inflictor) 
		if !attacker or !attacker:IsValid() or !attacker:IsPlayer() then return end
		if !jcms.director then return end
		local missionData = jcms.director.missionData
		if !missionData or !missionData.testing_data then return end
		local testing_data = missionData.testing_data
		if string.sub(inflictor:GetClass(), 1, 4) == "jcms" or inflictor:GetClass() == "prop_physics" then return end
		
		for k, v in ipairs(testing_data) do
			if !v.ply then continue end
			if v.ply == attacker then
				local wep = attacker:GetActiveWeapon()
				if !wep:IsValid() then continue end
				if wep:GetClass() != v.testing_weapon then continue end
				v.npc_killed = v.npc_killed + 1
			end
		end
	end)
		
	hook.Add( "PlayerDeath", "guntest death", function( victim, inflictor, attacker )
		if !jcms.director then return end
		local missionData = jcms.director.missionData
		if !missionData or !missionData.testing_data then return end
		local testing_data = missionData.testing_data
		
		for k, v in ipairs(testing_data) do
			if !v.ply then continue end
			if v.ply == victim then
				--victim:StripWeapon(v.testing_weapon)
				victim.jcms_lastLoadout[v.testing_weapon] = nil
				local wep = ents.Create("jcms_testing_weapon")
				wep.kills = v.npc_killed
				wep.PrintName = v.testing_weapon_name
				local wm_ent = ents.Create(v.testing_weapon)
				wm_ent:Spawn()
				local wm = wm_ent:GetModel()
				wm_ent:Remove()
				wep:SetModel(wm)
				wep.wep_class = v.testing_weapon
				local pos = victim:GetPos() + Vector(0,0,50)
				wep:SetPos(pos)
				wep:Spawn()
				v.ply = nil
			end
		end
	end)
		
	hook.Add( "PlayerDisconnected", "guntest dissconect", function(ply)
		if !jcms.director then return end
		local missionData = jcms.director.missionData
		if !missionData or !missionData.testing_data then return end
		local testing_data = missionData.testing_data
		
		for k, v in ipairs(testing_data) do
			if !v.ply then continue end
			if v.ply == ply then
				local wep = ents.Create("jcms_testing_weapon")
				wep.kills = v.npc_killed
				wep.PrintName = v.testing_weapon_name
				local wm_ent = ents.Create(v.testing_weapon)
				wm_ent:Spawn()
				local wm = wm_ent:GetModel()
				wm_ent:Remove()
				wep:SetModel(wm)
				wep.wep_class = v.testing_weapon
				local pos = ply:GetPos() + Vector(0,0,50)
				wep:SetPos(pos)
				wep:Spawn()
				v.ply = nil
			end
		end
	end)
end)

-----------------------------------
--		  	CONCOMMANDS		  	 --
-----------------------------------

concommand.Add( "jcms_ft_add_to_bl", function(ply, cmd, args)  
	if !ply:IsSuperAdmin() then return end
	local wep_class = args[1]
	jcms.ft_bl[wep_class] = true
	file.Write("mapsweepers/server/ft_blacklist.json", util.TableToJSON(jcms.ft_bl))
end )

concommand.Add("jcms_ft_update_bl", function(ply)
	if !ply:IsSuperAdmin() then return end
	local str = file.Read("mapsweepers/server/ft_blacklist.json", "DATA")
	local tbl = util.JSONToTable(str)
	jcms.ft_bl = tbl
end)