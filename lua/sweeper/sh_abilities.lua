--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Shared: Specialization helpers + the active-ability key (default G).

	Active abilities are registered in S.abilities[specId] = {
		name = "Shown on HUD",
		oncePerMission = true,         -- or cooldown = seconds
		activate = function(ply) return ok, messageIfFailed end,   (server)
	}
	Players press G for their highest-tier ability, H for the next one and J for the third (when all three
	picked subclasses have an ability). Client convars jcms_ability_key / ability2_key / ability3_key,
	or run "jcms_ability 1" / "jcms_ability 2" / "jcms_ability 3".
--]]

local S = sweeper
S.abilities = S.abilities or {}

-- // Which specializations does a player have active right now? {{{
local function specsFor(ply)
	if not IsValid(ply) then return nil end
	local class = ply:GetNWString("jcms_class", "")
	if not S.IsSkillClass(class) then return nil end
	if jcms and jcms.team_JCorp_player and not jcms.team_JCorp_player(ply) then return nil end

	local cd
	if SERVER then
		cd = S.GetClassData(ply, class)
	else
		if ply ~= LocalPlayer() then return nil end
		cd = S.cl and S.cl[class]
	end
	return cd and cd.specs, class
end

function S.PlayerHasSpec(ply, specId)
	local specs, class = specsFor(ply)
	if not specs then return false end
	for tier, id in pairs(specs) do
		if id == specId then return true end
	end
	return false
end

-- All active abilities this player has, highest tier first (slot 1 = G, slot 2 = H, slot 3 = J)
function S.GetPlayerAbilities(ply)
	local list = {}
	local specs = specsFor(ply)
	if not specs then return list end
	for tier = 3, 1, -1 do
		local id = specs[tier] or specs[tostring(tier)]
		if id and S.abilities[id] then list[#list + 1] = id end
	end
	return list
end

function S.GetPlayerAbility(ply, slot)
	return S.GetPlayerAbilities(ply)[slot or 1]
end

-- Readiness, stored per ability so two abilities keep separate cooldowns
function S.AbilityStatus(ply, id)
	local ab = S.abilities[id]
	if not ab then return false, "" end
	if ab.oncePerMission then
		local used = ply:GetNWBool("sweeper_used_" .. id, false)
		return not used, used and "USED" or "READY"
	elseif ab.cooldown then
		local left = ply:GetNWFloat("sweeper_readyAt_" .. id, 0) - CurTime()
		if left > 0 then return false, string.format("%ds", math.ceil(left)) end
	end
	return true, "READY"
end
-- }}}

if SERVER then
	function S.AbilityReady(ply, id)
		local ab = S.abilities[id]
		if not ab then return false end
		if ab.oncePerMission then
			return not (ply.sweeperUsedIn and ply.sweeperUsedIn[id] == jcms.director)
		end
		return (S.AbilityStatus(ply, id))
	end

	function S.MarkAbilityUsed(ply, id)
		local ab = S.abilities[id]
		if ab.oncePerMission then
			ply.sweeperUsedIn = ply.sweeperUsedIn or {}
			ply.sweeperUsedIn[id] = jcms.director
			ply:SetNWBool("sweeper_used_" .. id, true)
		elseif ab.cooldown then
			-- Specialization upgrades can shorten it (cdr_<spec id>, capped at 60%)
			local cd = ab.cooldown
			local t = S.GetPlayerTotals and S.GetPlayerTotals(ply)
			local cdr = t and t["cdr_" .. id]
			if cdr and cdr > 0 then cd = cd * (1 - math.min(cdr, 0.6)) end
			ply:SetNWFloat("sweeper_cdTotal_" .. id, cd)
			ply:SetNWFloat("sweeper_readyAt_" .. id, CurTime() + cd)
		end
	end

	-- Takes seconds off one running cooldown (Enforcer's Riot Control refunds Charge this way).
	-- Never pushes it into the future and never rewinds past ready.
	function S.CutCooldown(ply, id, seconds)
		if not (IsValid(ply) and ply:IsPlayer()) or not S.abilities[id] then return 0 end
		seconds = tonumber(seconds) or 0
		if seconds <= 0 then return 0 end

		local key = "sweeper_readyAt_" .. id
		local ct, readyAt = CurTime(), ply:GetNWFloat(key, 0)
		if readyAt <= ct then return 0 end

		local cut = math.min(seconds, readyAt - ct)
		ply:SetNWFloat(key, readyAt - cut)
		return cut
	end

	-- killCdr (class skills): every kill takes seconds off your running ability cooldowns
	hook.Add("MapSweepersDeathNPC", "sweeper_killCdr", function(npc, attacker)
		if IsValid(attacker) and not attacker:IsPlayer() and IsValid(attacker.jcms_owner) then attacker = attacker.jcms_owner end
		if not (IsValid(attacker) and attacker:IsPlayer()) then return end
		local t = S.GetPlayerTotals and S.GetPlayerTotals(attacker)
		local cut = t and t.killCdr
		if not cut or cut <= 0 then return end
		local ct = CurTime()
		for i, id in ipairs(S.GetPlayerAbilities(attacker)) do
			local key = "sweeper_readyAt_" .. id
			local readyAt = attacker:GetNWFloat(key, 0)
			if readyAt > ct then attacker:SetNWFloat(key, math.max(ct, readyAt - cut)) end
		end
	end)

	concommand.Add("jcms_ability", function(ply, cmd, args)
		if not IsValid(ply) or not ply:Alive() or ply:GetObserverMode() ~= OBS_MODE_NONE then return end
		if (ply.sweeperNextAbilityPress or 0) > CurTime() then return end
		ply.sweeperNextAbilityPress = CurTime() + 0.3

		local slot = math.Clamp(math.floor(tonumber(args[1]) or 1), 1, 3)
		local id = S.GetPlayerAbility(ply, slot)
		if not id then
			ply:ChatPrint("[Implants] You don't have an active ability in slot " .. slot .. ". Pick a specialization with one in IMPLANTS > Specializations.")
			return
		end

		if not S.AbilityReady(ply, id) then
			ply:ChatPrint("[Implants] " .. S.abilities[id].name .. " isn't ready yet.")
			ply:EmitSound("buttons/button10.wav", 60)
			return
		end

		local ok, msg = S.abilities[id].activate(ply)
		if ok then
			S.MarkAbilityUsed(ply, id)
		else
			if msg then ply:ChatPrint("[Implants] " .. msg) end
			ply:EmitSound("buttons/button10.wav", 60)
		end
	end, nil, "Use your specialization's active ability.")

	-- New mission: once-per-mission abilities become available again
	hook.Add("MapSweepersClassApplied", "sweeper_abilityReset", function(ply)
		for id, ab in pairs(S.abilities) do
			if ab.oncePerMission and not (ply.sweeperUsedIn and ply.sweeperUsedIn[id] == jcms.director) then
				ply:SetNWBool("sweeper_used_" .. id, false)
			end
		end
	end)
end

if CLIENT then
	local cvar_keys = {
		CreateClientConVar("jcms_ability_key", "g", true, false, "Key for your highest-tier specialization ability (e.g. g, h, mouse4)."),
		CreateClientConVar("jcms_ability2_key", "h", true, false, "Key for your second specialization ability."),
		CreateClientConVar("jcms_ability3_key", "j", true, false, "Key for your third specialization ability (only if all three picked subclasses have one)."),
	}

	-- Poll the keys every frame. (PlayerButtonDown isn't called clientside in singleplayer / on the
	-- listen-server host, so it can't be relied on.)
	local wasDown = {}
	hook.Add("Think", "sweeper_abilityKey", function()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local blocked = ply:IsTyping() or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus()) or vgui.CursorVisible()

		for slot, cvar in ipairs(cvar_keys) do
			local key = input.GetKeyCode(cvar:GetString())
			local down = false
			if key and key > 0 then
				if key >= MOUSE_FIRST and key <= MOUSE_LAST then
					down = input.IsMouseDown(key)
				else
					down = input.IsKeyDown(key)
				end
			end
			if down and not wasDown[slot] and not blocked then
				RunConsoleCommand("jcms_ability", tostring(slot))
			end
			wasDown[slot] = down
		end
	end)

	-- The ability HUD (icons + cooldowns) is drawn in cl_hudicons.lua
end
