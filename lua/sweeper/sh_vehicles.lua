--[[
	Map Sweepers - Implants & Class Levels (addon)
	Team Upgrades for the gamemode's own VEHICLES (DS-2 VTOL, LHT-6 Tank, APC).
	The upgrade rows live in S.group (sh_group.lua); this is what they do.

		g_vtol   Extended Belts    VTOL machinegun carries +200 rounds per rank (base 400).
		                           At the last rank the rocket pods come online - right click
		                           fires a homing salvo of micro-missiles.
		g_tank   Autoloader        Tank main gun cycles 12% faster per rank (base 2.5s) and the
		                           micro-missile launcher reloads 15% faster per rank (base 0.4s).
		g_apc    Reactive Plating  APC shield holds +3s and recharges 2.5s sooner per rank
		                           (base 8s / 15s), and it drives 6% faster per rank.

	HOW, WITHOUT EDITING THE GAMEMODE
	  All three vehicles are caught on OnEntityCreated and their stats set a tick later, once
	  Spawn/SetupDataTables has run - the same seam sh_orbitals.lua uses for jcms_deathraycontroller.
	    * VTOL ammo is a NetworkVar, so SetMachinegunAmmo is all it takes. The client HUD hardcodes
	      "/ 400" as the maximum, so the real maximum rides along on a NWInt and the client wrap
	      below rewrites that one string as it is drawn.
	    * The tank already networks Firerate1 (main gun) and Firerate2 (missiles) and reads them
	      through GetFirerate1/2 every shot, and its reload bars read the same values - so setting
	      them is enough and the HUD follows on its own.
	    * The APC reads ShieldDuration, ShieldRechargeTime, Speed and SpeedTurbo off self:GetTable()
	      every tick, so writing them on the instance shadows the class defaults.

	  Rocket pods hang off StartCommand. The gamemode's own jcms_NoVehicleShooting hook strips
	  IN_ATTACK2 out of the usercmd and records it as vehicle.attacking2 instead, and we cannot
	  count on running before or after it, so the check below accepts either signal.

	  Nothing here touches a class table shared with another addon: every write lands on one
	  entity instance, except the client HUD wrap, which is marked so it can only happen once.
--]]

local S = sweeper

S.vehicles = {
	-- DS-2 VTOL (base: 400 rounds)
	vtolBaseAmmo = 400,
	vtolAmmoPerRank = 200,       -- + machinegun rounds per rank

	vtolRocketRank = 3,          -- the rank that brings the rocket pods online
	vtolRocketCount = 4,         -- missiles per salvo
	vtolRocketSpacing = 0.12,    -- seconds between the missiles of one salvo
	vtolRocketCooldown = 6,      -- seconds between salvos
	vtolRocketDamage = 90,
	vtolRocketRadius = 220,
	vtolRocketProximity = 45,

	-- LHT-6 Tank (base: 2.5s main gun, 0.4s missiles)
	tankBaseFirerate1 = 2.5,
	tankBaseFirerate2 = 0.4,
	tankFirerate1PerRank = 0.12, -- fraction off the main gun's cycle
	tankFirerate1Floor = 0.5,    -- ...never quicker than this fraction of the base
	tankFirerate2PerRank = 0.15, -- fraction off the missile reload
	tankFirerate2Floor = 0.45,

	-- APC (base: 8s shield, 15s recharge, 485/690 speed)
	apcBaseShieldDuration = 8,
	apcBaseShieldRecharge = 15,
	apcShieldDurationPerRank = 3,    -- + seconds the dome holds
	apcShieldRechargePerRank = 2.5,  -- - seconds off the recharge
	apcShieldRechargeFloor = 6,      -- ...never quicker than this
	apcSpeedPerRank = 0.06,          -- + fraction of top speed
}

local V = S.vehicles

--[[ ------------------------------------------------------------------ CLIENT ]]
if CLIENT then
	-- The VTOL HUD builds its ammo readout as "<ammo> / 400" with the maximum written in by hand.
	-- Rather than copy the whole of DrawHUDBottom out of the gamemode to change one string, swap
	-- draw.SimpleText for the length of that one call and rewrite the readout on the way through.
	local function installVtolHud()
		local stored = scripted_ents.GetStored("jcms_vtol")
		local t = stored and stored.t
		if not (t and isfunction(t.DrawHUDBottom)) then return end
		if S.Wrapped(t, "VtolAmmoHud") then return end

		local orig = t.DrawHUDBottom
		t.DrawHUDBottom = function(ent, ...)
			local maxAmmo = ent:GetNWInt("sweeper_vtolMaxAmmo", 0)
			local rockets = ent:GetNWBool("sweeper_vtolRockets", false)

			if maxAmmo > V.vtolBaseAmmo then
				local pattern = "^(%d+) / " .. V.vtolBaseAmmo .. "$"
				local replace = "%1 / " .. maxAmmo
				local origText = draw.SimpleText

				draw.SimpleText = function(text, ...)
					if isstring(text) then
						text = string.gsub(text, pattern, replace)
					end
					return origText(text, ...)
				end

				local ok, err = pcall(orig, ent, ...)
				draw.SimpleText = origText
				if not ok then ErrorNoHalt("[Vehicles] VTOL HUD: " .. tostring(err) .. "\n") end
			else
				orig(ent, ...)
			end

			if rockets then
				local left = ent:GetNWFloat("sweeper_vtolRocketNext", 0) - CurTime()
				local ready = left <= 0
				local label = ready and "ROCKETS READY" or string.format("ROCKETS %.1f", left)
				draw.SimpleText(label, "jcms_hud_small", 0, -176,
					ready and jcms.color_bright_alt or jcms.color_dark_alt,
					TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			end
		end

		S.MarkWrapped(t, "VtolAmmoHud")
	end

	hook.Add("InitPostEntity", "sweeper_vehicleHud", installVtolHud)
	hook.Add("OnReloaded", "sweeper_vehicleHud", installVtolHud)
	installVtolHud() -- Lua refresh

	return
end

--[[ ------------------------------------------------------------------ SERVER ]]

local function rank(id)
	return (S.GroupRank and S.GroupRank(id)) or 0
end

-- // Stats, stamped on each vehicle as it spawns {{{
-- refresh = the vehicle already exists and a rank was just bought, so only the difference is handed
-- over. Stamping the full belt again would be a free reload every time someone buys an upgrade.
local function applyVtol(ent, refresh)
	local r = rank("g_vtol")

	local maxAmmo = V.vtolBaseAmmo + V.vtolAmmoPerRank * r
	local oldMax = tonumber(ent.sweeperMaxAmmo) or V.vtolBaseAmmo
	ent.sweeperMaxAmmo = maxAmmo
	ent:SetNWInt("sweeper_vtolMaxAmmo", maxAmmo)

	if ent.SetMachinegunAmmo then
		if refresh then
			local extra = maxAmmo - oldMax
			if extra > 0 then
				ent:SetMachinegunAmmo(math.min(maxAmmo, ent:GetMachinegunAmmo() + extra))
			end
		else
			-- SetupDataTables filled the belt to the stock 400; top it up to the new maximum
			ent:SetMachinegunAmmo(maxAmmo)
		end
	end

	local rockets = r >= V.vtolRocketRank
	ent.sweeperRockets = rockets
	ent:SetNWBool("sweeper_vtolRockets", rockets)
	if not refresh then
		ent:SetNWFloat("sweeper_vtolRocketNext", 0)
	end
end

local function applyTank(ent)
	local r = rank("g_tank")
	if r <= 0 then return end

	local f1 = V.tankBaseFirerate1 * math.max(V.tankFirerate1Floor, 1 - V.tankFirerate1PerRank * r)
	local f2 = V.tankBaseFirerate2 * math.max(V.tankFirerate2Floor, 1 - V.tankFirerate2PerRank * r)

	-- A tank is two entities: the hull and the tower. The hull is what shoots, but both carry the
	-- NetworkVars and the tower is what the reload bars are read off, so set them on whichever we got.
	if ent.SetFirerate1 then ent:SetFirerate1(f1) end
	if ent.SetFirerate2 then ent:SetFirerate2(f2) end
end

local function applyApc(ent)
	local r = rank("g_apc")
	if r <= 0 then return end

	ent.ShieldDuration = V.apcBaseShieldDuration + V.apcShieldDurationPerRank * r
	ent.ShieldRechargeTime = math.max(V.apcShieldRechargeFloor,
		V.apcBaseShieldRecharge - V.apcShieldRechargePerRank * r)

	local mul = 1 + V.apcSpeedPerRank * r
	local base = scripted_ents.GetStored("jcms_apc")
	base = base and base.t

	ent.Speed = (tonumber(base and base.Speed) or 485) * mul
	ent.SpeedTurbo = (tonumber(base and base.SpeedTurbo) or 690) * mul
end

local appliers = {
	jcms_vtol = applyVtol,
	jcms_tank = applyTank,
	jcms_apc = applyApc,
}

hook.Add("OnEntityCreated", "sweeper_vehicleUpgrades", function(ent)
	if not IsValid(ent) then return end
	local fn = appliers[ent:GetClass()]
	if not fn then return end

	-- Spawn and SetupDataTables have not run yet inside OnEntityCreated, so wait a tick
	timer.Simple(0, function()
		if not IsValid(ent) then return end
		local ok, err = pcall(fn, ent, false)
		if not ok then ErrorNoHalt("[Vehicles] " .. ent:GetClass() .. ": " .. tostring(err) .. "\n") end
	end)
end)

-- A rank bought while a vehicle is already parked on the map should reach that vehicle too
function S.VehicleRefreshAll()
	for i, ent in ipairs(ents.GetAll()) do
		local fn = IsValid(ent) and appliers[ent:GetClass()]
		if fn then
			local ok, err = pcall(fn, ent, true)
			if not ok then ErrorNoHalt("[Vehicles] refresh " .. ent:GetClass() .. ": " .. tostring(err) .. "\n") end
		end
	end
end

function S.InstallVehicleReapply()
	if not S.GroupReapply or S.Wrapped(S, "VehicleReapply") then return end
	local orig = S.GroupReapply
	S._wrappedVehicleReapply = function(...)
		local r = { orig(...) }
		local ok, err = pcall(S.VehicleRefreshAll)
		if not ok then ErrorNoHalt("[Vehicles] reapply: " .. tostring(err) .. "\n") end
		return unpack(r)
	end
	S.GroupReapply = S._wrappedVehicleReapply
	S.MarkWrapped(S, "VehicleReapply")
end
hook.Add("Initialize", "sweeper_vehicleReapply", S.InstallVehicleReapply)
hook.Add("InitPostEntity", "sweeper_vehicleReapply", S.InstallVehicleReapply)
S.InstallVehicleReapply()
-- }}}

-- // VTOL rocket pods {{{
local function vtolRocketOrigin(veh, index)
	local ang = veh:GetAngles()
	local side = (index % 2 == 1) and 1 or -1
	return veh:GetPos()
		+ ang:Forward() * 20
		+ ang:Right() * side * 96
		+ ang:Up() * 4, ang
end

local function vtolFireOne(veh, driver, index, aimAng)
	if not (IsValid(veh) and IsValid(driver)) then return end
	if veh.jcms_destroyed then return end

	local pos = vtolRocketOrigin(veh, index)

	local missile = ents.Create("jcms_micromissile")
	if not IsValid(missile) then return end

	missile:SetPos(pos)
	missile:SetAngles(aimAng)
	missile:SetOwner(veh)
	missile.Damage = V.vtolRocketDamage
	missile.Radius = V.vtolRocketRadius
	missile.Proximity = V.vtolRocketProximity
	missile.ActivationTime = CurTime() + 0.35
	missile.jcms_owner = driver
	if missile.SetBlinkColor and jcms.util_GetPVPVectorColor then
		missile:SetBlinkColor(jcms.util_GetPVPVectorColor(driver))
	end
	missile:Spawn()

	local phys = missile:GetPhysicsObject()
	if IsValid(phys) then
		-- pushed out and down so the salvo clears the airframe before it steers in
		phys:SetVelocity(aimAng:Forward() * 400 + veh:GetAngles():Up() * -120 + veh:GetVelocity())
	end

	-- Pick something to home on: whatever is straight ahead, or the nearest NPC around that point
	local trace = util.TraceLine {
		start = pos, endpos = pos + aimAng:Forward() * 20000,
		filter = { veh, driver, missile }, mask = MASK_SHOT
	}

	local target = trace.Entity
	if not IsValid(target) then
		local variants = ents.FindInSphere(trace.HitPos, V.vtolRocketRadius * 2)
		table.Shuffle(variants)
		for i, var in ipairs(variants) do
			if var:Health() > 0 and jcms.team_NPC(var) then
				target = var
				break
			end
		end
	end

	missile.Target = IsValid(target) and target or trace.HitPos
	missile.Damping = math.Rand(0.8, 1.0)
	missile.NeverLoseTarget = true

	veh:EmitSound("weapons/rpg/rocketfire1.wav", 90, math.random(105, 118), 0.75)

	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetNormal(aimAng:Forward())
	ed:SetScale(3)
	ed:SetFlags(1)
	util.Effect("jcms_muzzleflash", ed)
end

local function vtolFireSalvo(veh, driver)
	local aimAng = veh:GetTurretAngleFromDriver(driver, true)

	for i = 1, V.vtolRocketCount do
		if i == 1 then
			vtolFireOne(veh, driver, i, aimAng)
		else
			timer.Simple(V.vtolRocketSpacing * (i - 1), function()
				if not (IsValid(veh) and IsValid(driver)) then return end
				-- re-aim each missile so the salvo follows the pilot's crosshair
				local ok, ang = pcall(veh.GetTurretAngleFromDriver, veh, driver, true)
				vtolFireOne(veh, driver, i, ok and ang or aimAng)
			end)
		end
	end
end

hook.Add("StartCommand", "sweeper_vtolRockets", function(ply, cmd)
	local veh = ply:GetNWEntity("jcms_vehicle")
	if not (IsValid(veh) and veh:GetClass() == "jcms_vtol") then return end
	if veh:GetDriver() ~= ply then return end
	if veh.jcms_destroyed or not veh:GetIsWorking() then return end
	if not veh.sweeperRockets then return end

	-- The gamemode's own hook strips IN_ATTACK2 and leaves it on the vehicle as attacking2; which of
	-- us runs first is not ours to decide, so either signal counts.
	local down = veh.attacking2 or (bit.band(cmd:GetButtons(), IN_ATTACK2) > 0)
	if not down then return end

	local t = CurTime()
	if (veh.sweeperRocketNext or 0) > t then return end
	veh.sweeperRocketNext = t + V.vtolRocketCooldown
	veh:SetNWFloat("sweeper_vtolRocketNext", veh.sweeperRocketNext)

	local ok, err = pcall(vtolFireSalvo, veh, ply)
	if not ok then ErrorNoHalt("[Vehicles] VTOL rockets: " .. tostring(err) .. "\n") end
end)
-- }}}

concommand.Add("sweeper_vehicles_status", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local lines = { "--- Vehicle upgrades ---" }
	for i, id in ipairs({ "g_vtol", "g_tank", "g_apc" }) do
		local up = S.groupById and S.groupById[id]
		lines[#lines + 1] = string.format("  %-8s rank %d/%d  %s", id, rank(id),
			up and #up.costs or 0, up and up.name or "?")
	end

	local rv, rt, ra = rank("g_vtol"), rank("g_tank"), rank("g_apc")
	lines[#lines + 1] = string.format("  VTOL : %d rounds, rockets %s",
		V.vtolBaseAmmo + V.vtolAmmoPerRank * rv,
		rv >= V.vtolRocketRank and "ONLINE" or "offline")
	lines[#lines + 1] = string.format("  Tank : %.2fs cannon, %.2fs missiles",
		V.tankBaseFirerate1 * math.max(V.tankFirerate1Floor, 1 - V.tankFirerate1PerRank * rt),
		V.tankBaseFirerate2 * math.max(V.tankFirerate2Floor, 1 - V.tankFirerate2PerRank * rt))
	lines[#lines + 1] = string.format("  APC  : %.0fs shield, %.1fs recharge, %.0f/%.0f speed",
		V.apcBaseShieldDuration + V.apcShieldDurationPerRank * ra,
		math.max(V.apcShieldRechargeFloor, V.apcBaseShieldRecharge - V.apcShieldRechargePerRank * ra),
		485 * (1 + V.apcSpeedPerRank * ra), 690 * (1 + V.apcSpeedPerRank * ra))

	local live = 0
	for i, ent in ipairs(ents.GetAll()) do
		if appliers[ent:GetClass()] then live = live + 1 end
	end
	lines[#lines + 1] = string.format("  %d vehicle entities on the map right now", live)

	local text = table.concat(lines, "\n")
	if S.PrintConsole and IsValid(ply) then S.PrintConsole(ply, text) else print(text) end
end, nil, "Admin: show the vehicle upgrade ranks and the stats they produce.")
