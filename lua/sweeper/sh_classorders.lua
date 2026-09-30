--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Shared: Class-only call-ins (orders).

	HOW TO EDIT
	Add a line to S.orderClasses:   orderId = { "who", "who", ... }
	"who" can be a class      (recon, infantry, sentinel, engineer)
	          or a specialization id (scout, medic, juggernaut, ... see sh_specs.lua)
	A call-in with no line here is available to everyone, like normal.

	Order IDs:
	  Turrets     turret_smg (SMG Turret), turret_bolter (Bolter Turret), turret_shotgun (Scattergun Turret),
	              turret_gatling (Gatling Turret), turret_smrls (Missile Platform)
	  Orbitals    carpetbombing (Carpet Bombing), shelling (Shelling), antiairmissile (Anti-Air Missile),
	              orbitalbeam (Orbital Beam), smoke (Smoke)
	  Mobility    jumppad (Jump Pad), vtol (Dropship), apc (APC), hovertank (Tank)
	  Supplies    firstaid (First Aid Drop), restock (Ammo Restock), antirad (Antirad Drop)
	  Mines       mine_multiblast (MultiBlast Mine), mine_c4 (Timed Explosives), mine_breach (Breaching Charge)
	  Defensive   shieldcharger (Shield Charger), tesla (Tesla Coil)
	  Utility     respawnbeacon (Respawn Beacon), autohacker (Auto-Hack Device), locator (Locator)

	Tip: don't lock EVERY call-in in a category, or that slice of the spawn wheel will be empty
	for the other classes.
--]]

local S = sweeper

S.orderClasses = {
	-- The gamemode's own call-ins are available to everyone (no locks).
	-- New class-only call-ins added by this addon (see sh_callins.lua):
	skills_drone_combat = { "engineer" },   -- Combat Drone
	skills_drone_repair = { "engineer" },   -- Repair Drone
	skills_stimcrate    = { "infantry" },   -- Stim Crate
	skills_ammocache    = { "infantry" },   -- Ammo Cache
	skills_uav          = { "recon" },      -- UAV Scan
	skills_cover        = { "sentinel" },   -- Deployable Cover
	skills_decoy        = { "recon" },      -- Decoy Beacon
	skills_healstation  = { "engineer" },   -- Healing Station
	skills_bulwark      = { "sentinel" },   -- Bulwark
	skills_totem        = { "sentinel" },   -- Taunt Totem
	-- Precision Strike and Strafing Run are for everyone (no line here)
}

-- Can a player with this class + specialization picks use the order?
function S.CanClassUseOrder(class, specs, orderId)
	local allowed = S.orderClasses[orderId]
	if not allowed then return true end

	for i, who in ipairs(allowed) do
		if who == class then return true end
		if specs then
			for tier, specId in pairs(specs) do
				if specId == who and S.GetSpec(class, specId) then return true end
			end
		end
	end
	return false
end

-- Readable list of who can use an order, e.g. "Engineer" or "Medic, Lifeline"
function S.OrderAllowedText(orderId)
	local allowed = S.orderClasses[orderId]
	if not allowed then return nil end
	local names = {}
	for i, who in ipairs(allowed) do
		local name = S.classNames[who]
		if not name then
			for class in pairs(S.specById) do
				local spec = S.GetSpec(class, who)
				if spec then name = spec.name break end
			end
		end
		table.insert(names, name or who)
	end
	return table.concat(names, ", ")
end

local function playerClassAndSpecs(ply)
	local class = ply:GetNWString("jcms_class", "")
	if not S.IsSkillClass(class) then
		class = ply:GetNWString("jcms_desiredclass", "")
	end

	local cd
	if SERVER then
		cd = S.IsSkillClass(class) and S.GetClassData(ply, class)
	else
		cd = S.cl and S.cl[class]
	end
	return class, cd and cd.specs
end

function S.PlayerCanUseOrder(ply, orderId)
	if not IsValid(ply) then return true end
	local class, specs = playerClassAndSpecs(ply)
	return S.CanClassUseOrder(class, specs, orderId)
end

function S.InstallClassOrders()
	if not jcms or not jcms.orders_CanUse then return end

	-- // Server + client: block locked orders {{{
	if not S.Wrapped(jcms, "OrderCanUse") then
		local orig = jcms.orders_CanUse
		if SERVER then
			S._wrappedOrderCanUse = function(ply, orderId, ...)
				if not S.PlayerCanUseOrder(ply, orderId) then
					return false, 0
				end
				return orig(ply, orderId, ...)
			end
		else
			S._wrappedOrderCanUse = function(orderId, ...)
				if not S.PlayerCanUseOrder(LocalPlayer(), orderId) then
					return false
				end
				return orig(orderId, ...)
			end
		end
		jcms.orders_CanUse = S._wrappedOrderCanUse
		S.MarkWrapped(jcms, "OrderCanUse")
	end
	-- }}}

	-- // Client: hide locked orders from the spawn wheel {{{
	if CLIENT and jcms.orders_RebuildLists and not S.Wrapped(jcms, "Rebuild") then
		local orig = jcms.orders_RebuildLists
		S._wrappedRebuild = function(...)
			orig(...)
			local ply = LocalPlayer()
			if not IsValid(ply) or not jcms.orders_lists then return end

			for sector, list in pairs(jcms.orders_lists) do
				for i = #list, 1, -1 do
					if not S.PlayerCanUseOrder(ply, list[i]) then
						table.remove(list, i)
					end
				end
			end

			-- Keep the wheel's selected entry inside the (possibly shorter) list
			if jcms.spawnmenu_selectedOrders then
				for sector, sel in pairs(jcms.spawnmenu_selectedOrders) do
					local count = jcms.orders_lists[sector] and #jcms.orders_lists[sector] or 0
					jcms.spawnmenu_selectedOrders[sector] = math.Clamp(sel, 1, math.max(count, 1))
				end
			end
		end
		jcms.orders_RebuildLists = S._wrappedRebuild
		S.MarkWrapped(jcms, "Rebuild")
		jcms.orders_RebuildLists()
	end
	-- }}}
end

hook.Add("Initialize", "sweeper_classorders", S.InstallClassOrders)
hook.Add("InitPostEntity", "sweeper_classorders", S.InstallClassOrders)
S.InstallClassOrders()

if CLIENT then
	-- Rebuild the spawn wheel whenever your class or specializations change
	local lastKey
	timer.Create("sweeper_classorders_watch", 0.5, 0, function()
		local ply = LocalPlayer()
		if not IsValid(ply) or not (jcms and jcms.orders_RebuildLists) then return end

		local class = ply:GetNWString("jcms_class", "") .. "/" .. ply:GetNWString("jcms_desiredclass", "")
		local key = class .. "#" .. tostring(S.clVersion or 0)
		if key ~= lastKey then
			lastKey = key
			jcms.orders_RebuildLists()
		end

		-- Guard against the wheel's selection becoming invalid (e.g. empty slice)
		if jcms.spawnmenu_selectedOrders then
			for sector, sel in pairs(jcms.spawnmenu_selectedOrders) do
				if sel ~= sel then jcms.spawnmenu_selectedOrders[sector] = 1 end -- NaN check
			end
		end
	end)
end
