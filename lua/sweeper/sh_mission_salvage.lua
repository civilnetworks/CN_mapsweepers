--[[
	Map Sweepers - Implants & Class Levels (addon)
	Mission type: Salvage Run.

	Salvage crates are scattered all over the map and there are several processors dotted
	around, all feeding one shared quota - so you haul to whichever is closest.

	Crates are ordinary physics props and carrying works exactly like it does in any Source
	game: E to pick one up and E to let go, or a gravity gun with its normal drop and punt.
	Nothing here changes how you move or shoot while holding one. A crate that ends up inside a
	processor counts however it got there, and whoever last held it gets paid. Holding one does
	make every hostile in the area come for YOU, so it's still a squad job.

	Nothing in the mapsweepers gamemode folder is edited.
--]]

local S = sweeper

-- // Tuning {{{
	S.salvageMission = S.salvageMission or {
		quotaMin        = 8,     -- crates that have to reach a processor
		quotaMax        = 16,
		spareCrates     = 5,     -- extra crates placed beyond the quota, so a lost one isn't fatal
		padsMin         = 2,     -- salvage processors placed around the map
		padsMax         = 4,
		carryAggroRange = 1400,  -- how far a carrier pulls enemies onto themselves
		deliverRange    = 180,   -- how close to a processor counts as delivered
		crateReward     = 150,   -- J paid to whoever brings one in
		crateMass       = 35,    -- kept near the engine's carry weight so it handles like a prop
		hitForceMul     = 1,     -- how much getting shot / hit shoves a loose crate
		hitForceMax     = 60000  -- impulse cap, so a rocket doesn't send one into orbit
	}
-- }}}

-- // Carrying: slower, and no shooting (shared so prediction agrees) {{{
	function S.CarriedSalvage(ply)
		if not IsValid(ply) then return nil end
		local crate = ply:GetNWEntity("sweeper_carrying")
		return IsValid(crate) and crate or nil
	end

	-- Carrying is plain Source behaviour: the engine's +USE carry and the gravity gun, with
	-- their own movement, drop and punt. Nothing here modifies how the player moves or shoots.
-- }}}

if SERVER then

-- // Carry tracking: the engine's +USE carry tells us when it starts and stops {{{
	local function isCrate(ent)
		return IsValid(ent) and ent:GetClass() == "sweeper_salvage"
	end

	local function grab(ply, crate)
		crate:SetCarrier(ply)
		crate.jcms_lastCarrier = ply
		ply:SetNWEntity("sweeper_carrying", crate)
	end

	local function letGo(ply, crate)
		crate:SetCarrier(NULL)
		if IsValid(ply) then
			ply:SetNWEntity("sweeper_carrying", NULL)
		end
	end

	-- Carried by hand (+USE)
	hook.Add("OnPlayerPhysicsPickup", "sweeper_salvagecarry", function(ply, ent)
		if not isCrate(ent) then return end
		grab(ply, ent)
	end)

	hook.Add("OnPlayerPhysicsDrop", "sweeper_salvagecarry", function(ply, ent, thrown)
		if not isCrate(ent) then return end
		letGo(ply, ent)
	end)

	-- Held on the gravity gun. Dropping and punting are the gun's normal behaviour.
	hook.Add("GravGunOnPickedUp", "sweeper_salvagecarry", function(ply, ent)
		if not isCrate(ent) then return end
		grab(ply, ent)
	end)

	hook.Add("GravGunOnDropped", "sweeper_salvagecarry", function(ply, ent)
		if not isCrate(ent) then return end
		letGo(ply, ent)
	end)

	hook.Add("GravGunPunt", "sweeper_salvagecarry", function(ply, ent)
		if not isCrate(ent) then return end
		ent.jcms_lastCarrier = ply
	end)
-- }}}

-- // Delivery: every processor feeds the same quota {{{
	function S.SalvageDeliver(ply, crate, pad)
		local d = jcms and jcms.director
		local missionData = d and d.missionData
		if not missionData then return end

		missionData.delivered = (missionData.delivered or 0) + 1
		local quota = math.max(1, missionData.quota or 1)

		if IsValid(pad) and pad.Effects then pad:Effects() end

		-- ply can be nil: a crate that was punted in still counts, it just pays nobody.
		if IsValid(ply) then
			if jcms.giveCash then jcms.giveCash(ply, S.salvageMission.crateReward) end
			if jcms.director_PvpObjectiveCompleted and IsValid(pad) then
				jcms.director_PvpObjectiveCompleted(ply, pad:GetPos(), true)
			end
		end

		if IsValid(crate) then crate:Remove() end

		S.SalvageSyncPads(missionData)

		if jcms.net_SendTip then
			jcms.net_SendTip("all", true, "#jcms.skills_salvage_delivered", missionData.delivered / quota)
		end
	end

	-- Push the shared total onto every processor so they all read the same numbers.
	function S.SalvageSyncPads(missionData)
		if not missionData then return end
		local delivered = missionData.delivered or 0
		local quota = missionData.quota or 0

		for i, pad in ipairs(missionData.pads or {}) do
			if IsValid(pad) then
				pad:SetDelivered(delivered)
				pad:SetQuota(quota)
			end
		end
	end
-- }}}

-- // Prefabs {{{
	function S.InstallSalvagePrefabs()
		if not (jcms and jcms.prefabs) then return end

		if not jcms.prefabs.skills_salvage then
			jcms.prefabs.skills_salvage = {
				check = function(area)
					if area:GetSizeX() < 100 or area:GetSizeY() < 100 then return false end

					local center = jcms.mapgen_AreaPointAwayFromEdges(area, 100)
					if not center then return false end

					local tr = util.TraceHull {
						start = center + Vector(0, 0, 8),
						endpos = center + Vector(0, 0, 60),
						mins = Vector(-24, -24, 0),
						maxs = Vector(24, 24, 40)
					}

					if tr.Hit then return false end
					return true, center
				end,

				stamp = function(area, center)
					local crate = ents.Create("sweeper_salvage")
					if not IsValid(crate) then return end

					crate:SetPos(center + Vector(0, 0, 8))
					crate:SetAngles( Angle(0, math.random(0, 359), 0) )
					crate:Spawn()

					return crate
				end
			}
		end

		if not jcms.prefabs.skills_salvagedrop then
			jcms.prefabs.skills_salvagedrop = {
				check = function(area)
					if area:GetSizeX() < 180 or area:GetSizeY() < 180 then return false end

					local center = jcms.mapgen_AreaPointAwayFromEdges(area, 170)
					if not center then return false end

					local tr = util.TraceHull {
						start = center,
						endpos = center + Vector(0, 0, 110),
						mins = Vector(-50, -50, 0),
						maxs = Vector(50, 50, 100)
					}

					if tr.Hit then return false end
					return true, center
				end,

				stamp = function(area, center)
					local pad = ents.Create("sweeper_dropoff")
					if not IsValid(pad) then return end

					pad:SetPos(center)
					pad:SetAngles( Angle(0, math.random(0, 3) * 90, 0) )
					pad:Spawn()

					return pad
				end
			}
		end
	end
-- }}}

-- // Mission {{{
	local function countValid(list)
		local n = 0
		for i = #(list or {}), 1, -1 do
			if IsValid(list[i]) then n = n + 1 else table.remove(list, i) end
		end
		return n
	end

	function S.InstallSalvageMission()
		if not (jcms and jcms.missions) then return end
		S.InstallSalvagePrefabs()
		if jcms.missions.skills_salvagerun then return end

		jcms.missions.skills_salvagerun = {
			faction = "any",
			pvpAllowed = false,

			generate = function(data, missionData)
				local c = S.salvageMission
				local difficulty = jcms.runprogress_GetDifficulty()

				local quota = math.Clamp(math.ceil(difficulty * 8), c.quotaMin, c.quotaMax)
				local padCount = math.Clamp(math.ceil(difficulty * 2), c.padsMin, c.padsMax)

				-- Processors first, so crates can be spread away from all of them.
				local pads, padAreas = jcms.mapgen_SpreadPrefabs("skills_salvagedrop", padCount, 180, true)
				local placedPads = {}
				for i, pad in ipairs(pads or {}) do
					if IsValid(pad) then table.insert(placedPads, pad) end
				end

				if #placedPads == 0 then
					error("Couldn't place a salvage processor. This map has no open ground, pick a bigger one.")
				end

				jcms.mapgen_Wait( 0.4 )

				local crates = jcms.mapgen_SpreadPrefabs("skills_salvage", quota + c.spareCrates, 100, true, padAreas)
				local placedCrates = {}
				for i, crate in ipairs(crates or {}) do
					if IsValid(crate) then table.insert(placedCrates, crate) end
				end

				if #placedCrates == 0 then
					error("Couldn't place any salvage crates. This map is too cramped.")
				end

				-- Don't fail the mission over a tight map: ask for what actually fit.
				quota = math.min(quota, #placedCrates)

				missionData.pads = placedPads
				missionData.crates = placedCrates
				missionData.quota = quota
				missionData.delivered = 0
				S.SalvageSyncPads(missionData)

				jcms.mapgen_Wait( 0.9 )

				jcms.mapgen_PlaceNaturals( jcms.mapgen_AdjustCountForMapSize(10) )
				jcms.mapgen_PlaceEncounters()
			end,

			think = function(director)
				-- Whoever is hauling is the loudest thing on the map: pull in NPCs that
				-- can't see anyone, not just the ones already close.
				local carrier
				for i, ply in ipairs(player.GetAll()) do
					if ply:Alive() and S.CarriedSalvage(ply) then
						carrier = ply
						break
					end
				end
				if not IsValid(carrier) then return end

				for i, npc in ipairs(director.npcs or {}) do
					if IsValid(npc) and math.random() < 0.3 and not npc:Visible(carrier) then
						npc:UpdateEnemyMemory(carrier, carrier:WorldSpaceCenter())
					end
				end
			end,

			tagEntities = function(director, missionData, tags)
				for i, pad in ipairs(missionData.pads or {}) do
					if IsValid(pad) then
						tags[pad] = { name = "#jcms.skills_salvage_pad", moving = false, active = true }
					end
				end

				for i, crate in ipairs(missionData.crates or {}) do
					if IsValid(crate) then
						tags[crate] = {
							name = "#jcms.skills_salvage_ent",
							moving = IsValid(crate:GetCarrier()),
							active = true
						}
					end
				end
			end,

			getObjectives = function(missionData)
				local quota = math.max(1, missionData.quota or 1)
				local delivered = missionData.delivered or 0
				local missionTime = CurTime() - jcms.director.missionStartTime

				if delivered >= quota and missionTime > 10 then
					missionData.evacuating = true

					if not IsValid(missionData.evacEnt) then
						missionData.evacEnt = jcms.mission_DropEvac(jcms.mission_PickEvacLocation())
					end

					return jcms.mission_GenerateEvacObjective()
				end

				-- If the map somehow ate every remaining crate, don't leave the squad stuck.
				local cratesLeft = countValid(missionData.crates)
				if cratesLeft == 0 and delivered < quota then
					missionData.quota = math.max(1, delivered)
					S.SalvageSyncPads(missionData)
					quota = missionData.quota
				end

				-- A processor can be gone (map cleanup, a stray explosion) - keep at least one.
				if countValid(missionData.pads) == 0 then
					missionData.quota = math.max(1, delivered)
					quota = missionData.quota
				end

				return {
					{
						type = "skills_salvage",
						progress = delivered,
						total = quota,
						completed = delivered >= quota
					}
				}
			end,

			swarmCalcCost = function(director, swarmCost)
				return swarmCost + 1
			end,

			swarmCalcCooldown = function(director, baseCooldown, swarmCost)
				-- Pressure rises as the run goes on rather than while any one crate moves.
				local missionData = director.missionData
				local quota = missionData.quota or 0
				if quota > 0 then
					return Lerp((missionData.delivered or 0) / quota, baseCooldown, baseCooldown * 0.7)
				end
				return baseCooldown
			end
		}
	end
-- }}}

-- // Debug {{{
	concommand.Add("sweeper_salvagedebug", function(ply)
		local out = {}
		local function line(fmt, ...) out[#out + 1] = string.format(fmt, ...) end

		local d = jcms and jcms.director
		line("--- Salvage Run debug ---")
		line("mission type: %s", tostring(d and d.missionType))

		local md = d and d.missionData
		if not md then
			line("no missionData (no mission running?)")
		else
			line("delivered=%s  quota=%s", tostring(md.delivered), tostring(md.quota))
			line("processors tracked: %s   in world: %d",
				md.pads and tostring(#md.pads) or "nil",
				#ents.FindByClass("sweeper_dropoff"))

			for i, pad in ipairs(md.pads or {}) do
				if IsValid(pad) then
					line("  pad[%d] %s  shows %d/%d", i, tostring(pad), pad:GetDelivered(), pad:GetQuota())
				else
					line("  pad[%d] INVALID", i)
				end
			end

			line("crates tracked: %s   in world: %d",
				md.crates and tostring(#md.crates) or "nil",
				#ents.FindByClass("sweeper_salvage"))

			local carried, loose = 0, 0
			for i, crate in ipairs(md.crates or {}) do
				if IsValid(crate) then
					if IsValid(crate:GetCarrier()) then carried = carried + 1 else loose = loose + 1 end
				end
			end
			line("  %d loose, %d being carried", loose, carried)
		end

		for i, p in ipairs(player.GetAll()) do
			local crate = S.CarriedSalvage(p)
			if crate then line("%s is carrying %s", p:Nick(), tostring(crate)) end
		end

		local msg = table.concat(out, "\n")
		if S.PrintConsole then S.PrintConsole(IsValid(ply) and ply or nil, msg) else print(msg) end
	end, nil, "Dumps Salvage Run mission state (Implants addon).")
-- }}}

else

-- // Client mission entry + names {{{
	function S.InstallSalvageMission()
		if not (jcms and jcms.missions) then return end
		if jcms.missions.skills_salvagerun then return end

		jcms.missions.skills_salvagerun = {
			faction = "any",
			tags = { "altincome", "killsrequired" }
		}
	end

	language.Add("jcms.skills_salvagerun", "Salvage Run")
	language.Add("jcms.skills_salvagerun_desc", "There's a field of abandoned cargo out here and a handful of processors to feed it into. Pick a crate up with E or a gravity gun and get it to the nearest one - whoever's holding it is the loudest thing on the map.")
	language.Add("jcms.skills_salvage_delivered", "%d%% of the salvage quota delivered")

	language.Add("jcms.obj_skills_salvage", "Deliver salvage to the processors")
	language.Add("jcms.skills_salvage_ent", "Salvage Crate")
	language.Add("jcms.skills_salvage_pad", "Salvage Processor")
-- }}}

end

hook.Add("Initialize", "sweeper_salvagemission", function() S.InstallSalvageMission() end)
hook.Add("InitPostEntity", "sweeper_salvagemission", function() S.InstallSalvageMission() end)
