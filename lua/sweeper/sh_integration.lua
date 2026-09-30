--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Shared: small wrappers around gamemode functions so specialization stats that the
	gamemode itself controls (order cost/cooldown, Sentinel barrier, Sentinel sprint) work.
	Nothing in the mapsweepers folder is edited.
--]]

local S = sweeper

-- // Per-player stat totals on the client (only the local player is known) {{{
if CLIENT then
	S.clVersion = S.clVersion or 0
	local cacheKey, cacheTotals

	function S.GetPlayerTotals(ply)
		if not IsValid(ply) or ply ~= LocalPlayer() then return nil end
		local class = ply:GetNWString("jcms_class", "")
		local cd = S.cl and S.cl[class]
		if not cd then return nil end
		if jcms and jcms.team_JCorp_player and not jcms.team_JCorp_player(ply) then return nil end

		local key = class .. "#" .. S.clVersion
		if key ~= cacheKey then
			cacheKey = key
			cacheTotals = S.ComputeStats(class, cd.skills, cd.specs)
		end
		return cacheTotals
	end
end
-- }}}

function S.InstallIntegration()
	if not jcms then return end

	-- // Order cost / cooldown {{{
	if jcms.class_GetCostMultipliers and not S.Wrapped(jcms, "Cost") then
		local orig = jcms.class_GetCostMultipliers
		S._wrappedCost = function(data, orderData, ...)
			local costMult, coolDownMult = orig(data, orderData, ...)
			local ply = SERVER and S.costCtxPly or (CLIENT and LocalPlayer())
			local t = IsValid(ply) and S.GetPlayerTotals and S.GetPlayerTotals(ply)
			if t then
				costMult = costMult * (1 - (t.orderCost or 0))
				coolDownMult = coolDownMult * (1 - (t.orderCooldown or 0))
			end
			return costMult, coolDownMult
		end
		jcms.class_GetCostMultipliers = S._wrappedCost
		S.MarkWrapped(jcms, "Cost")
	end

	if SERVER then
		-- The gamemode doesn't pass the player into class_GetCostMultipliers, so remember who is ordering.
		S._wrappedOrders = S._wrappedOrders or {}
		for i, fname in ipairs({ "orders_CanUse", "orders_ForceUse" }) do
			local current = jcms[fname]
			if current and not S.Wrapped(jcms, "Orders_" .. fname) then
				local wrapped = function(ply, ...)
					S.costCtxPly = ply
					local r = table.Pack(pcall(current, ply, ...))
					S.costCtxPly = nil
					if not r[1] then error(r[2], 0) end
					return unpack(r, 2, r.n)
				end
				S._wrappedOrders[fname] = wrapped
				S.MarkWrapped(jcms, "Orders_" .. fname)
				jcms[fname] = wrapped
			end
		end
	end
	-- }}}

	local sen = jcms.classes and jcms.classes.sentinel
	if sen then
		-- // Sentinel barrier duration / cooldown {{{
		if sen.PerformBarrierLogic and not S.Wrapped(sen, "Barrier") then
			local orig = sen.PerformBarrierLogic
			S._wrappedBarrier = function(ply, active, ...)
				local t = S.GetPlayerTotals and S.GetPlayerTotals(ply)
				if not t or ((t.barrierLength or 0) == 0 and (t.barrierCooldown or 0) == 0) then
					return orig(ply, active, ...)
				end

				-- The gamemode reads these off the class table, so swap them in for this call only.
				local length, cooldown = sen.barrierLength, sen.barrierCooldown
				sen.barrierLength = length + (t.barrierLength or 0)
				sen.barrierCooldown = math.max(0.5, cooldown + (t.barrierCooldown or 0))
				local ok, result = pcall(orig, ply, active, ...)
				sen.barrierLength, sen.barrierCooldown = length, cooldown
				if not ok then error(result, 0) end
				return result
			end
			sen.PerformBarrierLogic = S._wrappedBarrier
			S.MarkWrapped(sen, "Barrier")
		end
		-- }}}

		-- // Sentinel sprint speed (the gamemode resets run speed every tick) {{{
		if sen.SetupMove and not S.Wrapped(sen, "SentinelMove") then
			local orig = sen.SetupMove
			S._wrappedSentinelMove = function(ply, mv, cmd, ...)
				local r = orig(ply, mv, cmd, ...)
				local t = S.GetPlayerTotals and S.GetPlayerTotals(ply)
				if t and (t.speed or 0) ~= 0 then
					ply:SetRunSpeed(ply:GetRunSpeed() * (1 + t.speed))
				end
				return r
			end
			sen.SetupMove = S._wrappedSentinelMove
			S.MarkWrapped(sen, "SentinelMove")
		end
		-- }}}
	end
end

hook.Add("Initialize", "sweeper_integration", S.InstallIntegration)
S.InstallIntegration() -- in case of a Lua refresh after the gamemode is already loaded
