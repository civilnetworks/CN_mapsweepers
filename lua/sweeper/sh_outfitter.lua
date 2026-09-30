--[[
	Map Sweepers - Implants & Class Levels (addon)
	OUTFITTER SUPPORT

	Lets players wear their Outfitter outfit during a mission, while keeping the team reading clear:
	the player COLOUR is still forced to the class / PvP team colour, so you can tell who is who.

	- Each player decides for themselves whether they see outfits (Map Sweepers settings -> OUTFITS).
	- Admins can switch outfits off for the whole server, or block one player who is abusing it.
	  A blocked player's outfit is hidden for everyone, and they are told once.
	- Nothing in the gamemode or in Outfitter is edited. Outfits are applied by Outfitter itself,
	  clientside; this file only decides who gets un-outfitted, and paints the team colour on top.

	Player convars:  jcms_outfits 1/0            see other players' outfits
	                 jcms_outfits_self 1/0       see your own outfit
	                 jcms_outfits_color 1/0      force the class / team colour onto outfits
	                 jcms_outfits_tint 0-1       how strongly outfits are tinted to that colour
	Server convar:   jcms_outfits_allowed 1/0    outfits allowed on this server at all
	Admin commands:  jcms_outfit_block <name|steamid64>, jcms_outfit_unblock <...>, jcms_outfit_blocklist
--]]

local S = sweeper

S.outfitBlocked = S.outfitBlocked or {}   -- [steamid64] = true, synced to clients

local function outfitterLoaded()
	return outfitter ~= nil and type(outfitter) == "table"
end

-- ============================================================================================
if SERVER then
	util.AddNetworkString("sweeper_outfits")

	S.cvar_outfitsAllowed = CreateConVar("jcms_outfits_allowed", "1",
		{ FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, "Allow Outfitter outfits on this server (1/0).", 0, 1)

	local SAVE = "sweeper_outfitblocks.json"

	local function save()
		local t = {}
		for id in pairs(S.outfitBlocked) do t[#t + 1] = id end
		file.Write(SAVE, util.TableToJSON(t))
	end

	local function load()
		local raw = file.Read(SAVE, "DATA")
		if not raw then return end
		for i, id in ipairs(util.JSONToTable(raw) or {}) do S.outfitBlocked[tostring(id)] = true end
	end
	load()

	function S.OutfitSync(ply)
		net.Start("sweeper_outfits")
			net.WriteTable(S.outfitBlocked)
		if IsValid(ply) then net.Send(ply) else net.Broadcast() end
	end
	hook.Add("jcms_PlayerNetReady", "sweeper_outfits", function(ply)
		timer.Simple(2, function() if IsValid(ply) then S.OutfitSync(ply) end end)
	end)
	hook.Add("PlayerInitialSpawn", "sweeper_outfits", function(ply)
		timer.Simple(6, function() if IsValid(ply) then S.OutfitSync(ply) end end)
	end)

	-- find a player by name or steamid
	local function findPlayer(str)
		if not str or str == "" then return nil end
		local lower = string.lower(str)
		for i, p in ipairs(player.GetHumans()) do
			if p:SteamID64() == str or p:SteamID() == str or string.find(string.lower(p:Nick()), lower, 1, true) then
				return p
			end
		end
	end

	local function adminOnly(ply)
		if IsValid(ply) and not ply:IsAdmin() then
			ply:ChatPrint("[Outfits] Admins only.")
			return false
		end
		return true
	end

	concommand.Add("jcms_outfit_block", function(ply, cmd, args)
		if not adminOnly(ply) then return end
		local target = findPlayer(args[1])
		local id = target and target:SteamID64() or (args[1] and args[1]:match("^%d+$") and args[1])
		if not id then
			local msg = "[Outfits] No player found for: " .. tostring(args[1])
			if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
			return
		end
		S.outfitBlocked[id] = true
		save()
		S.OutfitSync()
		local who = IsValid(target) and target:Nick() or id
		for i, p in ipairs(player.GetHumans()) do
			p:ChatPrint(string.format("[Outfits] %s's outfit was switched off by an admin.", who))
		end
	end, nil, "Admin: hide one player's Outfitter outfit for everyone.")

	concommand.Add("jcms_outfit_unblock", function(ply, cmd, args)
		if not adminOnly(ply) then return end
		local target = findPlayer(args[1])
		local id = target and target:SteamID64() or args[1]
		if not id or not S.outfitBlocked[id] then
			local msg = "[Outfits] That player isn't blocked."
			if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
			return
		end
		S.outfitBlocked[id] = nil
		save()
		S.OutfitSync()
		local msg = "[Outfits] Outfit allowed again for " .. (IsValid(target) and target:Nick() or id) .. "."
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
	end, nil, "Admin: allow a blocked player's outfit again.")

	concommand.Add("jcms_outfit_blocklist", function(ply)
		local lines = {}
		for id in pairs(S.outfitBlocked) do
			local name = id
			for i, p in ipairs(player.GetHumans()) do
				if p:SteamID64() == id then name = p:Nick() .. "  (" .. id .. ")" end
			end
			lines[#lines + 1] = name
		end
		local msg = #lines > 0 and ("[Outfits] Blocked:\n" .. table.concat(lines, "\n")) or "[Outfits] Nobody is blocked."
		S.PrintConsole(ply, msg)
	end, nil, "List players whose outfits are switched off.")
end

-- ============================================================================================
if CLIENT then
	local cvar_outfits      = CreateClientConVar("jcms_outfits", "1", true, false, "Show other players' Outfitter outfits.")
	local cvar_outfitsSelf  = CreateClientConVar("jcms_outfits_self", "1", true, false, "Show your own Outfitter outfit.")
	local cvar_outfitsColor = CreateClientConVar("jcms_outfits_color", "1", true, false, "Force the class / team colour onto outfits.")
	local cvar_outfitsTint  = CreateClientConVar("jcms_outfits_tint", "0.35", true, false, "How strongly outfits are tinted to the team colour (0-1).")
	S.cvar_outfits = cvar_outfits

	net.Receive("sweeper_outfits", function()
		S.outfitBlocked = net.ReadTable() or {}
	end)

	local function serverAllows()
		local cv = GetConVar("jcms_outfits_allowed")
		return not cv or cv:GetBool()
	end

	-- Should this player's outfit be shown to me?
	function S.OutfitAllowed(ply)
		if not IsValid(ply) or not ply:IsPlayer() then return false end
		if not serverAllows() then return false end
		if S.outfitBlocked[ply:SteamID64() or ""] then return false end
		if ply == LocalPlayer() then return cvar_outfitsSelf:GetBool() end
		return cvar_outfits:GetBool()
	end

	-- The colour this player should read as: PvP team colour in PvP, otherwise their class colour
	function S.OutfitTeamColor(ply)
		local pvpTeam = ply:GetNWInt("jcms_pvpTeam", -1)
		if pvpTeam > 0 and jcms and jcms.util_GetPVPColor then
			return jcms.util_GetPVPColor(ply)
		end
		local class = ply:GetNWString("jcms_class", "")
		local data = jcms and jcms.classes and jcms.classes[class]
		local v = data and data.playerColorVector
		if v then return Color(v.x * 255, v.y * 255, v.z * 255) end
		return nil
	end

	-- Paint the team colour onto a player, and take the outfit off anyone who isn't allowed one
	local function updatePlayer(ply)
		if not IsValid(ply) or not ply:IsPlayer() then return end

		local allowed = S.OutfitAllowed(ply)

		-- The gamemode sets everyone's model again on spawn and on class change, which drops the
		-- outfit. Put it back when the player is allowed one.
		if allowed and ply.enforce_model and ply:GetModel() ~= ply.enforce_model then
			ply:SetModel(ply.enforce_model)
		end

		if not allowed then
			-- put their real (class) model back, if Outfitter had swapped it
			if ply.enforce_model and ply.EnforceModel then
				ply:EnforceModel(nil)
			end
			if ply.sweeperTinted then
				ply:SetColor(color_white)
				ply.sweeperTinted = nil
			end
			return
		end

		if not cvar_outfitsColor:GetBool() then
			if ply.sweeperTinted then
				ply:SetColor(color_white)
				ply.sweeperTinted = nil
			end
			return
		end

		local col = S.OutfitTeamColor(ply)
		if not col then return end

		-- playermodel colour (only works on models that support it; harmless when it doesn't)
		pcall(ply.SetPlayerColor, ply, Vector(col.r / 255, col.g / 255, col.b / 255))

		-- and a tint on top, so outfits that ignore player colour still read as their team
		local wearing = ply.enforce_model ~= nil
		local strength = math.Clamp(cvar_outfitsTint:GetFloat(), 0, 1)
		if wearing and strength > 0 then
			ply:SetColor(Color(
				Lerp(strength, 255, col.r),
				Lerp(strength, 255, col.g),
				Lerp(strength, 255, col.b)
			))
			ply.sweeperTinted = true
		elseif ply.sweeperTinted then
			ply:SetColor(color_white)
			ply.sweeperTinted = nil
		end
	end

	timer.Create("sweeper_outfits", 0.25, 0, function()
		if not outfitterLoaded() then return end
		for i, ply in ipairs(player.GetAll()) do
			local ok, err = pcall(updatePlayer, ply)
			if not ok and (S._outfitErrAt or 0) < CurTime() then
				S._outfitErrAt = CurTime() + 10
				ErrorNoHalt("[sweeper] outfits: " .. tostring(err) .. "\n")
			end
		end
	end)

	-- // Settings: "OUTFITS" category in the Map Sweepers options {{{
	function S.AddOutfitterCategory(tab)
		-- same lookup cl_skills.lua uses: the first category list on the options tab is the client settings
		local catList
		for i, child in ipairs(tab and tab:GetChildren() or {}) do
			if child:GetName() == "DCategoryList" then catList = child break end
			for j, sub in ipairs(child:GetChildren()) do
				if sub:GetName() == "DCategoryList" then catList = sub break end
			end
			if catList then break end
		end
		if not S.ClaimOptionsCategory(catList, "Outfits") then return end
		local contentSize = catList:GetWide()
		local installed = outfitterLoaded()

		local bar = catList:Add("Outfits")
		S.PlaceOptionsCategory(catList, bar, S.optionsCatZ.outfits)
		bar.Paint = jcms.paint_Category
		bar.dontSubtractHeight = true
		local content = vgui.Create("DPanel", bar)
		content:SetPaintBackground(false)
		content:DockPadding(0, 0, 0, 16)
		bar:SetContents(content)

		local y = 16
		local function checkbox(label, cvar)
			local cb = content:Add("DCheckBoxLabel")
			cb:SetPos(24, y)
			cb:SetText(label)
			cb:SetWide(440)
			cb:SetConVar(cvar)
			cb.Paint = jcms.paint_CheckBoxLabel
			cb:SetEnabled(installed)
			y = y + 24
		end

		local function slider(label, cvar, min, max, dec)
			local sl = content:Add("DNumSlider")
			sl:SetText(label)
			sl:SetSize(contentSize - 48, 24)
			sl:SetPos(24, y)
			sl:SetMinMax(min, max)
			sl:SetDecimals(dec or 2)
			sl:SetConVar(cvar)
			sl.Paint = jcms.paint_NumSlider
			sl:SetEnabled(installed)
			y = y + 28
		end

		checkbox("Show other players' outfits", "jcms_outfits")
		checkbox("Show my own outfit", "jcms_outfits_self")
		checkbox("Force class / team colour onto outfits", "jcms_outfits_color")
		y = y + 4
		slider("Team colour strength", "jcms_outfits_tint", 0, 1, 2)

		local l = content:Add("DLabel")
		l:SetPos(24, y)
		l:SetSize(contentSize - 48, 52)
		l:SetWrap(true)
		l:SetFont("jcms_small")
		l:SetText(installed
			and "Outfits come from the Outfitter addon. Your class and team colour is still painted on top so players stay readable. Admins can switch outfits off for the server or for one player."
			or "Outfitter isn't installed, so there's nothing to show here.")
		l.Think = function(self) self:SetTextColor(installed and jcms.color_bright_alt or jcms.color_alert) end
		y = y + 56

		if installed then
			local b = content:Add("DButton")
			b:SetPos(24, y)
			b:SetSize(200, 26)
			b:SetText("OPEN OUTFITTER")
			b.jFont = "jcms_small_bolder"
			b.Paint = jcms.paint_ButtonFilled
			b.DoClick = function()
				surface.PlaySound("buttons/button15.wav")
				RunConsoleCommand("outfitter_open")
			end
		end
	end

	-- add our category to the options tab, after the ones cl_skills.lua adds
	function S.InstallOutfitOptions()
		if not (jcms and jcms.offgame_BuildOptionsTab) or S.Wrapped(jcms, "OutfitOptions") then return end
		local orig = jcms.offgame_BuildOptionsTab
		S._wrappedOutfitOptions = function(tab, ...)
			local r = orig(tab, ...)
			local ok, err = pcall(S.AddOutfitterCategory, tab)
			if not ok then ErrorNoHalt("[sweeper] couldn't add the outfit options: " .. tostring(err) .. "\n") end
			return r
		end
		jcms.offgame_BuildOptionsTab = S._wrappedOutfitOptions
		S.MarkWrapped(jcms, "OutfitOptions")
	end
	hook.Add("Initialize", "sweeper_outfitOptions", S.InstallOutfitOptions)
	hook.Add("InitPostEntity", "sweeper_outfitOptions", S.InstallOutfitOptions)
	S.InstallOutfitOptions()
	-- }}}
end
