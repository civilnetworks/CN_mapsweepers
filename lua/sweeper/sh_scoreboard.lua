--[[
	Map Sweepers - Implants & Class Levels (addon)
	Adds our info to the gamemode's own Tab scoreboard (nothing in the gamemode is edited):

	  Player rows   top subclass icon + class level ("LV12"), a dot when their ability is ready, and
	                a hover tooltip with all their subclasses (teammates only, like the gamemode's own info).
	  Controls box  IMPLANTS and TEAM UPGRADES buttons, plus the squad's V Tokens and Armory rank.

	Uses the gamemode's paint functions/fonts so it looks the same as the rest of the scoreboard.
--]]

local S = sweeper

-- // Server: share everyone's level + subclasses (the full data only goes to its owner) {{{
if SERVER then
	-- ...except on request. The level and specs above are broadcast constantly because they're small
	-- and everyone needs them; a whole skill tree is neither, so it's sent only to someone who asked
	-- for one specific player, one time, when they right click that player's lobby row.
	util.AddNetworkString("sweeper_inspect")

	net.Receive("sweeper_inspect", function(len, ply)
		if not IsValid(ply) then return end

		-- one request per player per half second, so a held mouse button can't flood anyone
		if (ply.sweeperNextInspect or 0) > CurTime() then return end
		ply.sweeperNextInspect = CurTime() + 0.5

		local target = net.ReadEntity()
		if not (IsValid(target) and target:IsPlayer() and not target:IsBot()) then return end

		-- Same rule the lobby row uses for showing a loadout at all: teammates only
		local mine, theirs = ply:GetNWInt("jcms_pvpTeam", -1), target:GetNWInt("jcms_pvpTeam", -1)
		if not (theirs == -1 or mine == theirs) then return end

		-- In the lobby nobody has spawned yet, so fall back to the class they've picked to play
		local class = S.GetActiveClass(target)
		if not class then
			local desired = target:GetNWString("jcms_desiredclass", "")
			if S.IsSkillClass(desired) then class = desired end
		end
		if not class then return end

		local cd = S.GetClassData(target, class)
		if not cd then return end

		local skills = {}
		for id, rank in pairs(cd.skills or {}) do
			if (tonumber(rank) or 0) > 0 then skills[#skills + 1] = { id, rank } end
		end

		net.Start("sweeper_inspect")
			net.WriteEntity(target)
			net.WriteString(class)
			net.WriteUInt(math.Clamp(cd.level or 1, 0, 255), 8)
			net.WriteUInt(math.max(0, math.floor(cd.xp or 0)), 32)

			net.WriteUInt(math.min(#skills, 255), 8)
			for i = 1, math.min(#skills, 255) do
				net.WriteString(skills[i][1])
				net.WriteUInt(math.Clamp(skills[i][2], 0, 63), 6)
			end

			for tier = 1, 3 do
				local id = cd.specs and (cd.specs[tier] or cd.specs[tostring(tier)])
				net.WriteString(id or "")
			end
		net.Send(ply)
	end)

	local function publish(ply)
		if not IsValid(ply) or ply:IsBot() then return end
		local class = S.GetActiveClass(ply)
		if not class then
			local desired = ply:GetNWString("jcms_desiredclass", "")
			if S.IsSkillClass(desired) then class = desired end
		end
		local cd = class and S.GetClassData(ply, class)
		local level = cd and cd.level or 0
		local specs = {}
		if cd and cd.specs then
			for tier = 1, 3 do
				local id = cd.specs[tier] or cd.specs[tostring(tier)]
				if id then specs[#specs + 1] = id end
			end
		end
		local specStr = table.concat(specs, ",")
		if ply:GetNWInt("sweeper_level", -1) ~= level then ply:SetNWInt("sweeper_level", level) end
		if ply:GetNWString("sweeper_specs", "") ~= specStr then ply:SetNWString("sweeper_specs", specStr) end
	end
	S.PublishScoreboardInfo = publish

	timer.Create("sweeper_scoreboardInfo", 1, 0, function()
		for i, ply in ipairs(player.GetHumans()) do publish(ply) end
	end)
end
-- }}}

if CLIENT then
	local specIcons = {}
	local function specIcon(id)
		local m = specIcons[id]
		if m == nil then
			m = Material("sweeper/icons/spec_" .. id .. ".png", "smooth mips")
			if m:IsError() then m = false end
			specIcons[id] = m
		end
		return m or nil
	end

	local function splitSpecs(str)
		local out = {}
		for id in string.gmatch(str or "", "[^,]+") do out[#out + 1] = id end
		return out
	end

	-- Is this player's top ability ready? (NW vars are visible to everyone)
	local function abilityReady(ply, specs)
		for i = #specs, 1, -1 do
			local ab = S.abilities[specs[i]]
			if ab then
				if ab.oncePerMission then return not ply:GetNWBool("sweeper_used_" .. specs[i], false) end
				return ply:GetNWFloat("sweeper_readyAt_" .. specs[i], 0) <= CurTime()
			end
		end
	end

	-- // Player rows {{{
	function S.InstallScoreboardRow()
		if not (jcms and jcms.paint_scoreboard_Player) or S.Wrapped(jcms, "ScoreRow") then return end
		local orig = jcms.paint_scoreboard_Player
		S._wrappedScoreRow = function(p, w, h, ...)
			local r = orig(p, w, h, ...)
			local ply = p.ply
			if not IsValid(ply) or ply:IsBot() then return r end

			local myTeam = jcms.locPly and jcms.locPly:GetNWInt("jcms_pvpTeam", -1) or -1
			local theirTeam = ply:GetNWInt("jcms_pvpTeam", -1)
			if not (theirTeam == -1 or myTeam == theirTeam) then return r end

			local level = ply:GetNWInt("sweeper_level", 0)
			if level <= 0 then return r end
			local specs = splitSpecs(ply:GetNWString("sweeper_specs", ""))

			local dim = not ply:Alive() or ply:GetNWBool("jcms_evacuated", false)
			if dim then surface.SetAlphaMultiplier(0.5) end

			-- Right after the health/shield bars: [top subclass icon] LV 12
			local barsW = math.max(ply:GetMaxHealth(), ply:GetMaxArmor()) / 2
			local x = 140 + ((ply:Alive() and not ply:GetNWBool("jcms_evacuated", false)) and barsW + 8 or 0)
			local maxX = w - 4 - 58 - 44 -- keep clear of the cash column

			local top = specs[#specs]
			local m = top and specIcon(top)
			if m and x + 14 <= maxX then
				surface.SetMaterial(m)
				surface.SetDrawColor(jcms.color_bright)
				surface.DrawTexturedRect(x, h / 2 - 8, 14, 14)
				-- ability-ready dot in the icon's corner
				local ready = abilityReady(ply, specs)
				if ready ~= nil then
					surface.SetDrawColor(ready and jcms.color_bright_alt or Color(90, 90, 90))
					surface.DrawRect(x + 11, h / 2 + 3, 4, 4)
				end
				x = x + 18
			end
			if x + 24 <= maxX + 30 then
				draw.SimpleText("LV" .. level, "jcms_small", x, h / 2 - 1, jcms.color_bright_alt, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end

			-- Full info on hover
			local names = {}
			for i, id in ipairs(specs) do
				local spec = S.GetSpec and S.GetSpec(ply:GetNWString("jcms_class", ""), id)
				names[#names + 1] = spec and spec.name or id
			end
			local tip = string.format("%s  -  Class level %d%s", ply:Nick(), level, #names > 0 and ("\n" .. table.concat(names, "  /  ")) or "")
			if p.sweeperTip ~= tip then
				p.sweeperTip = tip
				p:SetTooltip(tip)
			end

			if dim then surface.SetAlphaMultiplier(1) end
			return r
		end
		jcms.paint_scoreboard_Player = S._wrappedScoreRow
		S.MarkWrapped(jcms, "ScoreRow")
	end
	hook.Add("Initialize", "sweeper_scoreboardRow", S.InstallScoreboardRow)
	hook.Add("InitPostEntity", "sweeper_scoreboardRow", S.InstallScoreboardRow)
	S.InstallScoreboardRow()
	-- }}}

	-- // Lobby player rows {{{
	-- On top of the gamemode's own row, without editing it:
	--   * its weapon icons dropped into the row's border instead of overhanging its top edge
	--   * the player's class level, and their top subclass badged onto the class icon
	--   * right click a row to open that player's implant menu, read-only
	local WEAPON_DROP = 8 -- the border's top inset; the icons start at y=0 and overhang it by exactly this

	-- Right click a row to open that player's implant menu. Their tree isn't on the wire (only level
	-- and specs are), so this asks the server for it and the menu opens when the answer comes back.
	local function askToInspect(ply)
		if not IsValid(ply) then return end
		surface.PlaySound("buttons/lightswitch2.wav")
		net.Start("sweeper_inspect")
			net.WriteEntity(ply)
		net.SendToServer()
	end

	net.Receive("sweeper_inspect", function()
		local target = net.ReadEntity()
		local class = net.ReadString()
		local level = net.ReadUInt(8)
		local xp = net.ReadUInt(32)

		local skills = {}
		for i = 1, net.ReadUInt(8) do
			local id = net.ReadString()
			skills[id] = net.ReadUInt(6)
		end

		local specs = {}
		for tier = 1, 3 do
			local id = net.ReadString()
			if id ~= "" then specs[tier] = id end
		end

		if S.OpenInspectMenu then
			S.OpenInspectMenu(target, class, { level = level, xp = xp, skills = skills, specs = specs })
		end
	end)

	function S.InstallLobbyRow()
		if not (jcms and jcms.paint_PlayerLobby) or S.Wrapped(jcms, "LobbyRow") then return end
		local orig = jcms.paint_PlayerLobby

		S._wrappedLobbyRow = function(p, w, h, ...)
			-- The gamemode centres each weapon icon at iconSize/2, so it starts at y=0, while the row's
			-- border is drawn at y=8 - exactly 8px of overhang, at both resolutions. The border's top
			-- inset is hardcoded and a taller row only grows it DOWNWARDS, so no amount of enlarging
			-- reaches an icon that starts at 0; the icons have to come down into the box instead.
			-- DrawTexturedRectRotated is used only for the weapon icons in this function (the class,
			-- team and leader icons all go through DrawTexturedRect), so swapping it for the length of
			-- the call catches exactly them and nothing else.
			local origRot = surface.DrawTexturedRectRotated
			surface.DrawTexturedRectRotated = function(x, y, iw, ih, rot)
				return origRot(x, y + WEAPON_DROP, iw, ih, rot)
			end
			local ok, err = pcall(orig, p, w, h, ...)
			surface.DrawTexturedRectRotated = origRot
			if not ok then error(err, 0) end

			local ply = p.player
			if not (IsValid(ply) and not ply:IsBot()) then return end

			-- Teammates only, the same rule the gamemode uses for hiding enemy loadouts in PVP
			local myTeam = jcms.locPly and jcms.locPly:GetNWInt("jcms_pvpTeam", -1) or -1
			local theirTeam = ply:GetNWInt("jcms_pvpTeam", -1)
			if not (theirTeam == -1 or myTeam == theirTeam) then return end

			-- Right click opens their implants. Attached here, lazily, because the row panels are
			-- created by the gamemode and this paint is the only place we ever see them.
			if not p.sweeperRightClick then
				p.sweeperRightClick = true
				p:SetMouseInputEnabled(true)
				p.OnMouseReleased = function(self, code)
					if code == MOUSE_RIGHT and IsValid(self.player) then askToInspect(self.player) end
				end
			end

			local level = ply:GetNWInt("sweeper_level", 0)
			if level <= 0 then return end

			local specs = splitSpecs(ply:GetNWString("sweeper_specs", ""))
			local lowres = p.lowres

			-- Where the gamemode put the class icon: baseX is derived from the avatar, and in PVP it
			-- shifts one icon right to make room for the team badge it draws first.
			local av = p:GetChild(0)
			local iconSize = lowres and 16 or 32
			local baseX = IsValid(av) and (av:GetX() + av:GetWide() + 4) or (lowres and 32 or 48)
			local cx = baseX + 4 + (theirTeam > 0 and iconSize or 0)
			local cy = 12

			-- Top subclass badged into the corner of the class icon the gamemode already drew, which
			-- costs no space of its own on a row that has none to spare.
			local top = specs[#specs]
			local m = top and specIcon(top)
			local badge = lowres and 9 or 14
			if m then
				local bx, by = cx + iconSize - badge, cy + iconSize - badge
				surface.SetDrawColor(0, 0, 0, 190)
				surface.DrawRect(bx - 1, by - 1, badge + 2, badge + 2)
				surface.SetDrawColor(jcms.color_bright)
				surface.SetMaterial(m)
				surface.DrawTexturedRect(bx, by, badge, badge)
			end

			-- Level, in the gap the gamemode leaves between the name block and its weapon list, which
			-- starts at baseX + w*0.4. Sit as far right in that gap as possible, but never before the
			-- nickname ends - on a narrow row with a long nick the gap closes up, and following the
			-- name beats printing on top of it.
			local lvlFont = lowres and "jcms_small" or "jcms_small_bolder"
			local lvlText = "LV " .. level
			surface.SetFont(lvlFont)
			local lvlW = surface.GetTextSize(lvlText)

			surface.SetFont("jcms_small_bolder") -- the font the gamemode draws the nick in
			local nickEnd = baseX + iconSize + (theirTeam > 0 and iconSize or 0) + 10
				+ surface.GetTextSize(ply:Nick())

			draw.SimpleText(lvlText, lvlFont,
				math.max(nickEnd + 12, baseX + w * 0.4 - 12 - lvlW), h / 2 + 1,
				jcms.color_bright_alt, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			-- Hover for the full list. jcms_class is empty in the lobby, so resolve the spec names
			-- against the class they've actually picked to play.
			local class = ply:GetNWString("jcms_class", "")
			if class == "" then class = ply:GetNWString("jcms_desiredclass", "") end
			local names = {}
			for i, id in ipairs(specs) do
				local spec = S.GetSpec and S.GetSpec(class, id)
				names[#names + 1] = spec and spec.name or id
			end
			local tip = string.format("%s  -  Class level %d%s\nRight click to see their implants.",
				ply:Nick(), level, #names > 0 and ("\n" .. table.concat(names, "  /  ")) or "")
			if p.sweeperTip ~= tip then
				p.sweeperTip = tip
				p:SetTooltip(tip)
			end
		end

		jcms.paint_PlayerLobby = S._wrappedLobbyRow
		S.MarkWrapped(jcms, "LobbyRow")
	end
	hook.Add("Initialize", "sweeper_lobbyRow", S.InstallLobbyRow)
	hook.Add("InitPostEntity", "sweeper_lobbyRow", S.InstallLobbyRow)
	S.InstallLobbyRow()
	-- }}}

	-- // Team Upgrades pop-up (same page as the lobby tab) {{{
	function S.OpenGroupMenu()
		if not S.BuildGroupMenu then return end
		if IsValid(S.groupFrame) then S.groupFrame:Remove() end
		local frame = vgui.Create("DFrame")
		S.groupFrame = frame
		frame:SetSize(math.min(900, ScrW() - 40), math.min(680, ScrH() - 40))
		frame:Center()
		frame:SetTitle("")
		frame:MakePopup()
		frame.Paint = function() end
		local root = frame:Add("DPanel")
		root:SetPos(0, 24)
		root:SetSize(frame:GetWide(), frame:GetTall() - 24)
		S.BuildGroupMenu(root)
	end
	concommand.Add("jcms_teamupgrades", S.OpenGroupMenu, nil, "Open the Team Upgrades menu.")
	-- }}}

	-- // Controls box: buttons + squad info {{{
	hook.Add("MapSweepersScoreboardControls", "sweeper_scoreboard", function(controls)
		local info = controls:Add("DPanel")
		info:Dock(TOP)
		info:SetTall(40)
		info:DockMargin(2, 2, 2, 2)
		info.Paint = function(self, w, h)
			local me = LocalPlayer()
			local class = me:GetNWString("jcms_class", "")
			local cd = S.cl and S.cl[class]
			if cd then
				local name = S.GetTopSpecName and S.GetTopSpecName(class, cd)
				draw.SimpleText(string.format("%s  LV %d%s", string.upper(S.classNames[class] or class), cd.level,
					name and ("  /  " .. string.upper(name)) or ""), "jcms_small_bolder", 4, 2, jcms.color_bright)
				local chips = S.ChipsetsAvailable and S.ChipsetsAvailable(cd) or 0
				if chips > 0 then
					draw.SimpleText(string.format("%d %s to spend", chips, chips == 1 and S.pointName or S.pointNamePlural),
						"jcms_small", w - 4, 2, jcms.color_bright_alt, TEXT_ALIGN_RIGHT)
				end
			end
			if S.GroupPool then
				local rank = S.GroupRank and S.GroupRank("g_weapons") or 0
				local armory = (S.WeaponLocksEnabled and S.WeaponLocksEnabled()) and string.format("   -   Armory rank %d/5", rank) or ""
				draw.SimpleText(string.format("Squad %s: %d%s", S.tokenNamePlural or "V Tokens", S.GroupPool(), armory),
					"jcms_small", 4, 22, jcms.color_bright_alt)
			end
		end

		local function button(text, onClick)
			local b = controls:Add("DButton")
			b:Dock(TOP)
			b:SetTall(30)
			b:DockMargin(2, 2, 2, 2)
			b:SetText(text)
			b.jFont = "jcms_small_bolder"
			b.Paint = jcms.paint_Button
			b.DoClick = function()
				surface.PlaySound("buttons/button15.wav")
				onClick()
			end
			return b
		end

		button("IMPLANTS", function() if S.OpenMenu then S.OpenMenu() end end)
		local gb = button("TEAM UPGRADES", S.OpenGroupMenu)
		-- Glow while an upgrade vote is running (same glow as the lobby tab)
		gb.PaintOver = function(self, w, h)
			if S.PaintGroupTabGlow then
				local x, y = 0, 0
				S.PaintGroupTabGlow(x + 3, y + 3, w - 6, h - 6)
			end
		end
	end)
	-- }}}
end
