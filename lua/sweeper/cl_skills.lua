--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Client: HUD XP bar and the skill tree menu (F4 or "jcms_implants" in console).
--]]

local S = sweeper
S.cl = S.cl or {}             -- [class] = { xp, level, skills }
S.cl_levelUpUntil = 0

local ACTION_BUY, ACTION_RESPEC, ACTION_SPEC = 1, 2, 3
local cvar_hud = CreateClientConVar("jcms_implant_hud", "1", true, false, "Show the class level bar on the HUD.")

surface.CreateFont("sweeper_title", { font = "Roboto", size = 26, weight = 800, extended = true })
surface.CreateFont("sweeper_med",   { font = "Roboto", size = 17, weight = 700, extended = true })
surface.CreateFont("sweeper_small", { font = "Roboto", size = 14, weight = 500, extended = true })

-- Colours follow the gamemode's HUD theme when it's available
local function colBright() return (jcms and jcms.color_bright) or Color(255, 0, 0) end
local function colDark()   return (jcms and jcms.color_dark) or Color(30, 12, 12) end
local function colAlt()    return (jcms and jcms.color_bright_alt) or Color(64, 180, 255) end
local colText   = Color(235, 235, 235)
local colDim    = Color(120, 120, 120)
local colLocked = Color(20, 20, 20, 230)

-- // Map Sweepers menu look {{{
-- Same building blocks as the gamemode's lobby: angled (cut-corner) panels and buttons, the jcms_* fonts,
-- the theme colours (bright / bright_alt / dark / pulsing) and the striped + noise fills.
local function colDarkAlt() return (jcms and jcms.color_dark_alt) or Color(10, 20, 30) end
local function colPulse()   return (jcms and jcms.color_pulsing) or colBright() end
local function colAlert()   return (jcms and jcms.color_alert) or Color(255, 120, 0) end
local function fnt(name, fallback) return (jcms and jcms.color_bright) and name or fallback end

local function polyFilled(x, y, w, h, pad)
	if jcms and jcms.hud_DrawFilledPolyButton then return jcms.hud_DrawFilledPolyButton(x, y, w, h, pad) end
	surface.DrawRect(x, y, w, h)
end
local function polyHollow(x, y, w, h, pad)
	if jcms and jcms.hud_DrawHollowPolyButton then return jcms.hud_DrawHollowPolyButton(x, y, w, h, pad) end
	surface.DrawOutlinedRect(x, y, w, h)
end
local function striped(x, y, w, h, sc, off)
	if jcms and jcms.hud_DrawStripedRect and w > 0 then jcms.hud_DrawStripedRect(x, y, w, h, sc or 32, off or 0) end
end
local function noise(x, y, w, h)
	if jcms and jcms.hud_DrawNoiseRect and w > 0 then jcms.hud_DrawNoiseRect(x, y, w, h) else surface.DrawRect(x, y, w, h) end
end

-- A lobby-style tab/toggle button: filled when active, outlined otherwise, bright_alt on hover
local function paintToggle(self, w, h, text, active, font)
	local hov = self:IsHovered()
	local clr = hov and colAlt() or colBright()
	local dark = hov and colDarkAlt() or colDark()
	font = font or fnt("jcms_small_bolder", "sweeper_med")
	surface.SetDrawColor(clr)
	if active then
		polyFilled(0, 0, w, h, math.min(w / 4, 8))
		draw.SimpleText(text, font, w / 2 - 1, h / 2 - 1, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	else
		polyHollow(0, 0, w, h, math.min(w / 4, 8))
		draw.SimpleText(text, font, w / 2 - 1, h / 2 - 1, clr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	return true
end

-- Rank pips drawn like the gamemode's stat bars (little angled pieces, filled = owned)
local function drawPips(x, y, count, filled, clr, pw, ph)
	pw, ph = pw or 12, ph or 8
	surface.SetDrawColor(clr)
	for p = 1, count do
		local px = x + (p - 1) * (pw + 2)
		if p <= filled then polyFilled(px, y, pw, ph, 3) else polyHollow(px, y, pw, ph, 3) end
	end
end
-- // }}}

-- Subclass emblems: materials/sweeper/icons/spec_<id>.png
local specMats = {}
function S.SpecIconMat(id)
	local m = specMats[id]
	if m == nil then
		m = Material("sweeper/icons/spec_" .. tostring(id) .. ".png", "smooth mips")
		if m:IsError() then m = false end
		specMats[id] = m
	end
	return m or nil
end

function S.DrawSpecIcon(id, x, y, size, col)
	local m = S.SpecIconMat(id)
	if not m then return false end
	surface.SetMaterial(m)
	surface.SetDrawColor(col)
	surface.DrawTexturedRect(x, y, size, size)
	return true
end

-- The menu normally shows your own data out of S.cl. When it's inspecting someone else (right click
-- on their lobby row) it's handed a one-off snapshot the server sent instead, so every read of a
-- class's progress inside the menu goes through here rather than touching S.cl directly.
local EMPTY_CD = { xp = 0, level = 1, skills = {}, specs = {} }
local function menuData(frame, class)
	local ins = frame and frame.inspect
	if ins then
		return (ins.class == class) and ins.data or EMPTY_CD
	end
	return S.cl[class]
end

local function currentClass()
	local ply = LocalPlayer()
	if not IsValid(ply) then return nil end
	local class = ply:GetNWString("jcms_class", "")
	if S.IsSkillClass(class) then return class end
	class = ply:GetNWString("jcms_desiredclass", "")
	if S.IsSkillClass(class) then return class end
	return nil
end

-- // Networking {{{
net.Receive("sweeper_sync", function()
	local tbl = net.ReadTable()

	for class, cd in pairs(tbl) do
		local old = S.cl[class]
		if old and cd.level > old.level then
			S.cl_levelUpUntil = CurTime() + 4
			S.cl_levelUpText = string.format("%s  LEVEL %d", string.upper(S.classNames[class] or class), cd.level)
			S.cl_specUnlocked = nil
			for tier, lvl in ipairs(S.specLevels) do
				if old.level < lvl and cd.level >= lvl then
					S.cl_specUnlocked = string.format("Tier %d Specialization unlocked!  Press F4", tier)
				end
			end
			surface.PlaySound("buttons/button9.wav")
		end
	end

	S.cl = tbl
	S.clVersion = (S.clVersion or 0) + 1
	if IsValid(S.menu) then S.menu:Refresh() end
	if IsValid(S.lobbyMenu) then S.lobbyMenu:Refresh() end
end)

net.Receive("sweeper_open", function()
	S.OpenMenu()
end)

concommand.Add("jcms_implants", function() S.OpenMenu() end, nil, "Open the Implants menu.")

local function sendAction(action, class, id, tier)
	net.Start("sweeper_action")
		net.WriteUInt(action, 2)
		net.WriteString(class)
		if tier then net.WriteUInt(tier, 2) end
		if id then net.WriteString(id) end
	net.SendToServer()
end

-- Word-wrap `text` to `width` pixels in `font`; returns a string with \n, at most maxLines lines.
local function wrapText(text, font, width, maxLines)
	local lines, line = {}, ""
	surface.SetFont(font)
	for word in string.gmatch(text, "%S+") do
		local test = (line == "") and word or (line .. " " .. word)
		if surface.GetTextSize(test) > width and line ~= "" then
			table.insert(lines, line)
			line = word
		else
			line = test
		end
	end
	if line ~= "" then table.insert(lines, line) end
	if maxLines and #lines > maxLines then
		lines[maxLines] = lines[maxLines] .. "..."
	end
	return table.concat(lines, "\n", 1, math.min(#lines, maxLines or #lines))
end
-- // }}}

-- // HUD framework {{{
--[[
	Everything this addon draws on the HUD goes through the gamemode's own HUD pass ("MapSweepersDrawHUD"),
	so it only shows when the Map Sweepers HUD shows (not in the lobby, spectating, dead or during cutscenes),
	fades in with the mission intro, and follows the HUD settings:
	  jcms_hud_scale, jcms_hud_color_* / themes, jcms_motionsickness (sway), jcms_hud_nocolourfilter (tints).

	S.AddHud(name, where, fn)   fn(ply, alpha)
	  where = "tint"    full-screen colour tints (skipped with jcms_hud_nocolourfilter 1 or jcms_tints 0)
	          "2d"      world markers in screen space (hidden while the call-in menu is open, like the locators)
	          "top" / "center" / "bottom"   the gamemode's floating 3D2D HUD panels
	          "bottomleft"  the health bar panel     "bottomright"  the ammo panel
--]]
local cvar_tints = CreateClientConVar("jcms_tints", "1", true, false, "Screen tints while abilities / buffs are active.")
S.hudLayers = S.hudLayers or {}
local hudOrder = { tint = 1, ["2d"] = 2, top = 3, center = 4, bottom = 5, bottomleft = 6, bottomright = 7 }
local hudSorted

function S.AddHud(name, where, fn)
	S.hudLayers[name] = { name = name, where = where, fn = fn }
	hudSorted = nil
end

function S.HudTint(col, a)
	surface.SetDrawColor(col.r, col.g, col.b, a)
	surface.DrawRect(-2, -2, ScrW() + 4, ScrH() + 4)
end

-- The gamemode's look: dark shadow copy, then a bright additive copy floating slightly above it
function S.HudGlowText(text, font, x, y, bright, dark, ax, ay, off)
	off = off or 8
	draw.SimpleText(text, font, x, y, dark, ax, ay)
	render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		draw.SimpleText(text, font, x, y - off, bright, ax, ay)
	render.OverrideBlend(false)
end

-- Screen-space marker text in the same style as the gamemode's locators
function S.HudMarkerText(text, font, x, y, col, ax, ay)
	draw.SimpleTextOutlined(text, font, x, y, col, ax, ay, 1, jcms.color_dark)
end

function S.HudDistance(dist)
	if jcms.util_ToDistance then return jcms.util_ToDistance(dist, true) end
	return string.format("%dm", math.floor(dist * 0.0254))
end

local hudErrors = {}
local function runLayer(layer, ply, alpha)
	local ok, err = pcall(layer.fn, ply, alpha)
	if not ok and (hudErrors[layer.name] or 0) < CurTime() then
		hudErrors[layer.name] = CurTime() + 10
		ErrorNoHalt("[sweeper] HUD '" .. layer.name .. "': " .. tostring(err) .. "\n")
	end
	surface.SetAlphaMultiplier(alpha)
	render.OverrideBlend(false)
end

function S.HudIntroAlpha()
	local t, len = jcms.hud_beginsequencet, jcms.hud_beginsequenceLen
	if t and len and t <= len then
		return math.Clamp((t - 2.4) / 1, 0, 1)
	end
	return 1
end

hook.Add("MapSweepersDrawHUD", "jcms_implant_hud", function()
	local ply = jcms.locPly or LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return end
	local alpha = S.HudIntroAlpha()
	if alpha <= 0 then return end

	if not hudSorted then
		hudSorted = {}
		for name, layer in pairs(S.hudLayers) do hudSorted[#hudSorted + 1] = layer end
		table.sort(hudSorted, function(a, b)
			local oa, ob = hudOrder[a.where] or 9, hudOrder[b.where] or 9
			if oa ~= ob then return oa < ob end
			return a.name < b.name
		end)
	end

	local tints = cvar_tints:GetBool() and not (jcms.cvar_hud_nocolourfilter and jcms.cvar_hud_nocolourfilter:GetBool())
	local markers = (jcms.hud_spawnmenuAnim or 0) <= 0.05
	local open -- which 3D2D panel / 2D pass is currently open

	local function close()
		if open == "2d" then cam.End2D() elseif open then cam.End3D2D() end
		open = nil
	end

	for i, layer in ipairs(hudSorted) do
		local where = layer.where
		if not ((where == "tint" and not tints) or (where == "2d" and not markers)) then
			local want = (where == "tint") and "2d" or where
			if open ~= want then
				close()
				if want == "2d" then
					cam.Start2D()
				elseif want == "bottomleft" then
					jcms.setup3d2dDiagonal(false, true)   -- health bar panel
				elseif want == "bottomright" then
					jcms.setup3d2dDiagonal(false, false)  -- ammo panel
				else
					jcms.setup3d2dCentral(want)
				end
				open = want
			end
			surface.SetAlphaMultiplier(alpha)
			runLayer(layer, ply, alpha)
		end
	end
	close()
	surface.SetAlphaMultiplier(1)
	draw.NoTexture()
end)
-- // }}}

-- // Class level / XP bar (under the compass) + level-up banner {{{
local shownFrac = 0
S.AddHud("xpBar", "top", function(ply, alpha)
	if not cvar_hud:GetBool() then return end

	local class = ply:GetNWString("jcms_class", "")
	local cd = S.cl[class]
	if not cd or not S.IsSkillClass(class) then return end

	local bright, dark = jcms.color_bright, jcms.color_dark
	local brightAlt, darkAlt = jcms.color_bright_alt, jcms.color_dark_alt
	local off = 6

	local w, h = 760, 14
	local x, y = -w / 2, 176
	local maxed = cd.level >= S.maxLevel
	local frac = maxed and 1 or math.Clamp(cd.xp / S.XPToNext(cd.level), 0, 1)
	shownFrac = Lerp(FrameTime() * 6, shownFrac, frac)

	-- Bar: dark track, bright fill floating above it
	surface.SetDrawColor(dark)
	surface.DrawRect(x, y, w, h)
	render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		surface.SetDrawColor(bright)
		surface.DrawRect(x, y - off, w * shownFrac, h)
		surface.SetDrawColor(bright.r, bright.g, bright.b, 40)
		jcms.hud_DrawStripedRect(x + w * shownFrac, y - off, w * (1 - shownFrac), h, 64, CurTime() * 30)
	render.OverrideBlend(false)

	-- Labels under the bar
	local specName = S.GetTopSpecName(class, cd)
	local label = string.upper(S.classNames[class] or class) .. (specName and ("  /  " .. string.upper(specName)) or "")
	S.HudGlowText(string.format("%s  LV %d", label, cd.level), "jcms_hud_small", x, y + h + 12, bright, dark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, off)
	S.HudGlowText(maxed and "MAX" or string.format("%d / %d XP", cd.xp, S.XPToNext(cd.level)), "jcms_hud_small", x + w, y + h + 12, bright, dark, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, off)

	-- Subclass emblems (T1, T2, T3) to the left of the bar
	local es, ex = 64, x - 20
	for tier = 3, 1, -1 do
		local id = cd.specs and (cd.specs[tier] or cd.specs[tostring(tier)])
		if id then
			ex = ex - es - 10
			local ey = y + h / 2 - es / 2
			surface.SetDrawColor(dark)
			jcms.hud_DrawFilledPolyButton(ex, ey, es, es, 14)
			render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
				S.DrawSpecIcon(id, ex + 8, ey + 8 - off, es - 16, tier == 3 and bright or ColorAlpha(bright, 150))
			render.OverrideBlend(false)
		end
	end

	-- Unspent chipsets
	local chips = S.ChipsetsAvailable(cd)
	if chips > 0 then
		surface.SetAlphaMultiplier(alpha * (0.55 + 0.45 * math.abs(math.sin(CurTime() * 3))))
		S.HudGlowText(string.format("%d %s AVAILABLE  [F4]", chips, string.upper(chips == 1 and S.pointName or S.pointNamePlural)),
			"jcms_hud_small", 0, y + h + 60, brightAlt, darkAlt, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, off)
		surface.SetAlphaMultiplier(alpha)
	end
end)

S.AddHud("levelUp", "top", function(ply, alpha)
	if CurTime() >= S.cl_levelUpUntil or not S.cl_levelUpText then return end
	local left = S.cl_levelUpUntil - CurTime()
	surface.SetAlphaMultiplier(alpha * math.Clamp(left, 0, 1))
	local bright, dark = jcms.color_bright, jcms.color_dark
	local y = 420
	S.HudGlowText("LEVEL UP", "jcms_hud_big", 0, y, bright, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 10)
	S.HudGlowText(string.upper(S.cl_levelUpText .. "  -  +1 " .. S.pointName), "jcms_hud_medium", 0, y + 8, bright, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 8)
	if S.cl_specUnlocked then
		S.HudGlowText(string.upper(S.cl_specUnlocked), "jcms_hud_medium", 0, y + 80, jcms.color_bright_alt, jcms.color_dark_alt, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 8)
	end
	surface.SetAlphaMultiplier(alpha)
end)
-- // }}}

-- // Skill tree menu {{{
local NODE_W, NODE_H = 180, 74
local TREE_COLUMNS = 4

local function buildTree(frame, treePanel, class)
	-- keep the scroll position when the tree is rebuilt (after buying a rank)
	local oldScroll = (IsValid(treePanel.scroll) and treePanel.scrollClass == class) and treePanel.scroll:GetVBar():GetScroll() or 0
	treePanel:Clear()
	treePanel.Paint = function() end

	local cd = menuData(frame, class) or EMPTY_CD
	local skills = cd.skills or {}
	local specs = cd.specs or {}
	local tree = S.tree[class]

	-- Class skills grouped into tier rows; specialization upgrades grouped by spec
	local tiers, maxTier, specRows = {}, 1, {}
	for i, sk in ipairs(tree) do
		if sk.spec then
			specRows[sk.spec] = specRows[sk.spec] or {}
			specRows[sk.spec][sk.slot or (#specRows[sk.spec] + 1)] = sk
		else
			tiers[sk.tier] = tiers[sk.tier] or {}
			table.insert(tiers[sk.tier], sk)
			maxTier = math.max(maxTier, sk.tier)
		end
	end

	-- Everything sits on a canvas inside a scroll panel (the tree is taller than the window)
	local scroll = vgui.Create("DScrollPanel", treePanel)
	scroll:Dock(FILL)
	treePanel.scroll, treePanel.scrollClass = scroll, class
	timer.Simple(0, function()
		if IsValid(scroll) and oldScroll > 0 then scroll:GetVBar():SetScroll(oldScroll) end
	end)
	local vbar = scroll:GetVBar()
	vbar:SetWide(8)
	vbar:SetHideButtons(true)
	vbar.Paint = function(self, w, h)
		local c = colBright()
		surface.SetDrawColor(c.r, c.g, c.b, 25)
		surface.DrawRect(2, 0, w - 4, h)
	end
	vbar.btnGrip.Paint = function(self, w, h)
		surface.SetDrawColor(colBright())
		surface.DrawRect(2, 0, w - 4, h)
	end

	local tw = treePanel:GetWide() - 14
	local rowGap = 104
	local specTop = 16 + maxTier * rowGap + 8
	local specRowGap = 96
	local canvasH = specTop + 44 + #S.specLevels * specRowGap + 8

	local canvas = vgui.Create("DPanel", scroll)
	canvas:SetSize(tw, canvasH)
	scroll:AddItem(canvas)
	canvas.nodes = {}
	treePanel.nodes = canvas.nodes

	local function makeNode(sk, nx, ny)
		local rank = tonumber(skills[sk.id]) or 0
		local reqsMet = S.ReqsMet(class, skills, sk)
		local canBuy = S.CanBuy(class, cd, sk.id)

		local btn = vgui.Create("DButton", canvas)
		btn:SetPos(nx, ny)
		btn:SetSize(NODE_W, NODE_H)
		btn:SetText("")

		local tip = sk.name .. "\n" .. sk.desc .. string.format("\nRank %d / %d", rank, sk.max)
		if sk.spec then
			local spec = S.GetSpec(class, sk.spec)
			tip = tip .. "\nSpecialization upgrade: " .. (spec and spec.name or sk.spec)
		end
		if sk.req then
			local names = {}
			for j, reqId in ipairs(sk.req) do
				table.insert(names, S.byId[class][reqId].name)
			end
			tip = tip .. "\nRequires: " .. table.concat(names, ", ")
		end
		btn:SetTooltip(tip)
		btn.OnCursorEntered = function() canvas.hoverId = sk.id end
		btn.OnCursorExited = function() if canvas.hoverId == sk.id then canvas.hoverId = nil end end

		-- Word-wrap the description to fit inside the node (max 2 lines)
		local descLines, line = {}, ""
		surface.SetFont(fnt("jcms_small", "sweeper_small"))
		for word in string.gmatch(sk.desc, "%S+") do
			local test = (line == "") and word or (line .. " " .. word)
			if surface.GetTextSize(test) > NODE_W - 16 and line ~= "" then
				table.insert(descLines, line)
				line = word
			else
				line = test
			end
		end
		if line ~= "" then table.insert(descLines, line) end
		local wrappedDesc = table.concat(descLines, "\n", 1, math.min(#descLines, 2))

		btn.Paint = function(self, w, h)
			-- Lobby style: maxed = solid, owned = outlined + tinted, buyable = outlined (bright_alt on hover),
			-- locked = faint outline. Same cut-corner shapes as the gamemode's buttons.
			local hov = self:IsHovered() and canBuy
			local clr = hov and colAlt() or colBright()
			local dark = hov and colDarkAlt() or colDark()
			local maxed = rank >= sk.max
			local nameFont, descFont = fnt("jcms_title", "sweeper_med"), fnt("jcms_small", "sweeper_small")
			local nameCol, descCol

			if maxed then
				surface.SetDrawColor(clr)
				polyFilled(0, 0, w, h, 8)
				nameCol, descCol = dark, ColorAlpha(dark, 220)
			else
				surface.SetDrawColor(dark.r, dark.g, dark.b, 200)
				polyFilled(0, 0, w, h, 8)
				if rank > 0 or hov then
					surface.SetDrawColor(clr.r, clr.g, clr.b, hov and 40 or 22)
					polyFilled(0, 0, w, h, 8)
				end
				local a = (rank > 0 or canBuy) and 255 or (reqsMet and 150 or 45)
				surface.SetDrawColor(clr.r, clr.g, clr.b, a)
				polyHollow(0, 0, w, h, 8)
				nameCol = ColorAlpha(clr, reqsMet and 255 or 90)
				descCol = ColorAlpha(clr, reqsMet and 170 or 60)
			end

			draw.SimpleText(sk.name, nameFont, 10, 5, nameCol)
			draw.DrawText(wrappedDesc, descFont, 10, 27, descCol, TEXT_ALIGN_LEFT)

			-- Rank pips (bottom right)
			local pw = 12
			drawPips(w - 10 - sk.max * (pw + 2), h - 14, sk.max, rank, maxed and dark or ColorAlpha(clr, reqsMet and 255 or 70), pw, 7)
			return true
		end

		btn.DoClick = function()
			if frame.inspect then surface.PlaySound("buttons/button10.wav") return end
			local ok, reason = S.CanBuy(class, cd, sk.id)
			if ok then
				sendAction(ACTION_BUY, class, sk.id)
				surface.PlaySound("buttons/button14.wav")
			else
				surface.PlaySound("buttons/button10.wav")
				frame.statusText = reason
				frame.statusUntil = CurTime() + 2.5
			end
		end

		canvas.nodes[sk.id] = { x = nx, y = ny, sk = sk }
	end

	-- Class tree
	local colW = tw / TREE_COLUMNS
	for tier, row in pairs(tiers) do
		local count = #row
		local spacing = tw / count
		for i, sk in ipairs(row) do
			-- Skills sit in a fixed column (sk.col) so children line up under their parents
			local cx = sk.col and (colW * (sk.col - 0.5)) or (spacing * (i - 0.5))
			local nx = math.floor(math.Clamp(cx - NODE_W / 2, 0, tw - NODE_W))
			makeNode(sk, nx, 16 + (tier - 1) * rowGap)
		end
	end

	-- Specialization upgrades: one row per tier, for the spec picked in that tier
	local header = vgui.Create("DPanel", canvas)
	header:SetPos(0, specTop)
	header:SetSize(tw, 36)
	header.Paint = function(self, w, h)
		local c = colBright()
		surface.SetDrawColor(c.r, c.g, c.b, 50)
		striped(0, 2, w, 3, 32)
		draw.SimpleText("SPECIALIZATION UPGRADES", fnt("jcms_medium", "sweeper_title"), 4, 10, c)
		draw.SimpleText("Only for the specialization you picked. Changing it refunds its upgrades.",
			fnt("jcms_small", "sweeper_small"), w - 4, 18, ColorAlpha(c, 120), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		return true
	end

	for tier = 1, #S.specLevels do
		local ry = specTop + 44 + (tier - 1) * specRowGap
		local specId = specs[tier] or specs[tostring(tier)]
		local spec = specId and S.GetSpec(class, specId)
		local row = spec and specRows[specId]

		local label = vgui.Create("DPanel", canvas)
		label:SetPos(0, ry)
		label:SetSize(math.floor(colW) - 12, NODE_H)
		label.Paint = function(self, w, h)
			local c = colBright()
			surface.SetDrawColor(c.r, c.g, c.b, spec and 120 or 35)
			striped(0, 6, 4, h - 12, 32, CurTime() * 16)
			if spec then
				S.DrawSpecIcon(spec.id, 12, h / 2 - 20, 40, c)
				draw.SimpleText(string.upper(spec.name), fnt("jcms_title", "sweeper_med"), 60, h / 2 - 2, c, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				draw.SimpleText("TIER " .. tier, fnt("jcms_small_bolder", "sweeper_small"), 61, h / 2 + 2, ColorAlpha(c, 160), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			else
				draw.SimpleText("TIER " .. tier, fnt("jcms_title", "sweeper_med"), 14, h / 2 - 2, ColorAlpha(c, 90), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				local why = (cd.level or 1) < S.specLevels[tier] and ("Unlocks at level " .. S.specLevels[tier]) or "Pick a specialization"
				draw.SimpleText(string.upper(why), fnt("jcms_small_bolder", "sweeper_small"), 15, h / 2 + 2, ColorAlpha(c, 70), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
			return true
		end

		if row then
			for slot = 1, 3 do
				local sk = row[slot]
				if sk then
					local cx = colW * (slot + 0.5)
					local nx = math.floor(math.Clamp(cx - NODE_W / 2, 0, tw - NODE_W))
					makeNode(sk, nx, ry)
				end
			end
		end
	end

	-- Connection lines, drawn under the nodes.
	-- Each line drops straight down from the parent, turns just above the child, then enters it,
	-- so it's always clear which skill leads to which. Hovering a skill highlights its links.
	local function thickLine(x1, y1, x2, y2, t)
		if x1 == x2 then
			surface.DrawRect(x1 - t / 2, math.min(y1, y2), t, math.abs(y2 - y1))
		else
			surface.DrawRect(math.min(x1, x2) - t / 2, y1 - t / 2, math.abs(x2 - x1) + t, t)
		end
	end

	canvas.Paint = function(self, w, h)
		local hover = self.hoverId
		local passes = { false, true } -- draw normal lines first, highlighted ones on top
		for p, highlightPass in ipairs(passes) do
			for id, node in pairs(self.nodes) do
				if node.sk.req then
					for j, reqId in ipairs(node.sk.req) do
						local parent = self.nodes[reqId]
						if parent then
							local isHover = hover ~= nil and (hover == id or hover == reqId)
							if isHover == highlightPass then
								local owned = (tonumber(skills[reqId]) or 0) > 0
								local col
								if isHover then
									col = colAlt()
								elseif owned then
									col = colBright()
								else
									col = ColorAlpha(colBright(), 50)
								end
								surface.SetDrawColor(col)

								local t = isHover and 3 or 2
								draw.NoTexture()
								if parent.y == node.y then
									-- same row (specialization upgrades): straight across, arrow into the left edge
									local x1, x2, y = parent.x + NODE_W, node.x, math.floor(node.y + NODE_H / 2)
									thickLine(x1, y, x2, y, t)
									surface.DrawPoly({ { x = x2 - 6, y = y - 5 }, { x = x2, y = y }, { x = x2 - 6, y = y + 5 } })
								else
									local x1, y1 = math.floor(parent.x + NODE_W / 2), parent.y + NODE_H
									local x2, y2 = math.floor(node.x + NODE_W / 2), node.y
									local elbowY = y2 - 12
									thickLine(x1, y1, x1, elbowY, t)
									thickLine(x1, elbowY, x2, elbowY, t)
									thickLine(x2, elbowY, x2, y2, t)

									-- small arrow tip into the child
									surface.DrawPoly({ { x = x2 - 5, y = y2 - 6 }, { x = x2 + 5, y = y2 - 6 }, { x = x2, y = y2 } })
								end
							end
						end
					end
				end
			end
		end
	end
end

local function buildSpecs(frame, panel, class)
	panel:Clear()
	panel.Paint = function() end

	local cd = menuData(frame, class) or EMPTY_CD
	local specs = cd.specs or {}
	local pw = panel:GetWide()
	local labelW, gap = 110, 12
	local cardW = math.floor((pw - labelW - gap * 2) / 2)
	local cardH, rowGap = 118, 132

	for tier, options in ipairs(S.specs[class] or {}) do
		local ry = 6 + (tier - 1) * rowGap
		local unlocked = cd.level >= S.specLevels[tier]

		local label = vgui.Create("DPanel", panel)
		label:SetPos(0, ry)
		label:SetSize(labelW - 8, cardH)
		label.Paint = function(self, w, h)
			local clr = colBright()
			-- striped marker bar on the left, like the gamemode's separators
			surface.SetDrawColor(clr.r, clr.g, clr.b, unlocked and 120 or 35)
			striped(0, 8, 4, h - 16, 32, CurTime() * 16)
			draw.SimpleText("TIER " .. tier, fnt("jcms_big", "sweeper_title"), 12, h / 2 + 2, ColorAlpha(clr, unlocked and 255 or 70), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText("LEVEL " .. S.specLevels[tier], fnt("jcms_small_bolder", "sweeper_small"), 13, h / 2 + 4, ColorAlpha(clr, unlocked and 180 or 60), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			return true
		end

		for i, spec in ipairs(options) do
			local cx = labelW + (i - 1) * (cardW + gap)
			local selected = specs[tier] == spec.id
			local canPick, reason = S.CanPickSpec(class, cd, tier, spec.id, false)

			local statText = S.FormatStats(spec.stats)
			local statWrapped = statText ~= "" and wrapText(statText, fnt("jcms_small", "sweeper_small"), cardW - 84, 2) or ""
			local abilityText = (spec.perk and ("Perk: " .. spec.perk)) or (spec.ability and ("Ability (coming soon): " .. spec.ability))
			local abilityWrapped = abilityText and wrapText(abilityText, fnt("jcms_small", "sweeper_small"), cardW - 84, 3) or ""

			local card = vgui.Create("DButton", panel)
			card:SetPos(cx, ry)
			card:SetSize(cardW, cardH)
			card:SetText("")
			card:SetTooltip(spec.name .. "\n" .. (statText ~= "" and statText or "No stat changes") .. (abilityText and ("\n" .. abilityText) or ""))

			card.Paint = function(self, w, h)
				local hov = self:IsHovered() and canPick and not selected
				local clr = hov and colAlt() or colBright()
				local dark = hov and colDarkAlt() or colDark()
				local alt = colAlt()
				local on = selected or canPick
				local small = fnt("jcms_small", "sweeper_small")

				-- Card body: dark cut-corner panel; selected gets a solid header strip, hover a tint
				surface.SetDrawColor(dark.r, dark.g, dark.b, 200)
				polyFilled(0, 0, w, h, 10)
				if hov then
					surface.SetDrawColor(clr.r, clr.g, clr.b, 30)
					polyFilled(0, 0, w, h, 10)
				end
				surface.SetDrawColor(clr.r, clr.g, clr.b, on and 255 or 45)
				polyHollow(0, 0, w, h, 10)
				if selected then
					surface.SetDrawColor(clr)
					polyFilled(64, 4, w - 68, 26, 6)
				end

				-- Emblem in a cut-corner frame
				surface.SetDrawColor(clr.r, clr.g, clr.b, on and 255 or 45)
				if selected then polyFilled(8, 8, 50, 50, 8) else polyHollow(8, 8, 50, 50, 8) end
				S.DrawSpecIcon(spec.id, 12, 12, 42, selected and dark or ColorAlpha(clr, on and 255 or 60))

				draw.SimpleText(string.upper(spec.name), fnt("jcms_medium", "sweeper_title"), 72, 5, selected and dark or ColorAlpha(clr, on and 255 or 70))

				-- The TIER label at the left of the row already says which level opens it, so the cards
				-- don't repeat it - a level lock just leaves this corner blank.
				local status = selected and "SELECTED" or (canPick and "CLICK TO SELECT") or (unlocked and string.upper(reason or "")) or ""
				draw.SimpleText(status, fnt("jcms_small_bolder", "sweeper_small"), w - 12, 17, selected and dark or ColorAlpha(canPick and alt or clr, canPick and 255 or 70), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

				draw.DrawText(statWrapped, small, 72, 38, ColorAlpha(clr, on and 200 or 60), TEXT_ALIGN_LEFT)
				if abilityWrapped ~= "" then
					draw.DrawText(abilityWrapped, small, 72, statWrapped ~= "" and 72 or 38, ColorAlpha(alt, on and 220 or 70), TEXT_ALIGN_LEFT)
				end
				return true
			end

			card.DoClick = function()
				if selected or frame.inspect then return end
				local ok, why = S.CanPickSpec(class, cd, tier, spec.id, false)
				if ok then
					sendAction(ACTION_SPEC, class, spec.id, tier)
					surface.PlaySound("buttons/button14.wav")
				else
					surface.PlaySound("buttons/button10.wav")
					frame.statusText = why
					frame.statusUntil = CurTime() + 2.5
				end
			end
		end
	end
end

-- // Options view {{{
-- Opens the gamemode's own Options tab (same one as in the lobby) in a pop-up
function S.OpenGameOptions()
	if not (jcms and jcms.offgame_BuildOptionsTab) then return end
	if S.InstallGameOptions then S.InstallGameOptions() end
	if IsValid(S.gameOptionsFrame) then S.gameOptionsFrame:Remove() end
	-- Sized to what the gamemode actually builds instead of a round number: its two tab buttons run
	-- to x=636 (32 + 300 + 4 + 300) and the category lists are 512 wide at x=48, so anything past
	-- ~660 is dead space - which is what the old 940 was mostly showing.
	local TAB_W = 660

	local frame = vgui.Create("DFrame")
	S.gameOptionsFrame = frame
	frame:SetSize(math.min(TAB_W + 40, ScrW() - 40), math.min(720, ScrH() - 40))
	frame:Center()
	frame:SetTitle("")
	frame:MakePopup()

	-- Derma's own window buttons don't belong on a Map Sweepers panel
	frame:ShowCloseButton(false)
	for i, name in ipairs({ "btnClose", "btnMaxim", "btnMinim" }) do
		local b = frame[name]
		if IsValid(b) then b:SetVisible(false) b:SetMouseInputEnabled(false) end
	end

	frame.Paint = function(self, w, h)
		local dark, bright = colDark(), colBright()
		surface.SetDrawColor(dark.r, dark.g, dark.b, 245)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(bright)
		surface.DrawOutlinedRect(0, 0, w, h, 2)
		draw.SimpleText("MAP SWEEPERS OPTIONS", "sweeper_title", 16, 6, bright)
	end

	local close = frame:Add("DButton")
	close:SetSize(30, 24)
	close:SetPos(frame:GetWide() - 42, 8)
	close:SetText("X")
	close.jFont = "jcms_small_bolder"
	close.Paint = jcms.paint_ButtonFilled
	close.DoClick = function()
		surface.PlaySound("buttons/button15.wav")
		frame:Remove()
	end

	local tab = frame:Add("DPanel")
	tab:SetPos(20, 44)
	tab:SetSize(math.min(TAB_W, frame:GetWide() - 40), frame:GetTall() - 60)
	tab:SetPaintBackground(false)
	local ok, err = pcall(jcms.offgame_BuildOptionsTab, tab)
	if not ok then
		ErrorNoHalt("[Implants] couldn't build the Map Sweepers options: " .. tostring(err) .. "\n")
	end
end

-- // Our settings inside the Map Sweepers options tab (lobby Options + the pop-up above) {{{
-- The gamemode has no hook for its options tab, so we wrap jcms.offgame_BuildOptionsTab, let it build
-- everything as normal, then add an "IMPLANTS & CLASS LEVELS" category to its client settings list,
-- built the same way (same paint functions / fonts) as the gamemode's own categories.
local function findClientCatList(tab)
	for i, child in ipairs(tab:GetChildren()) do
		if child:GetName() == "DCategoryList" then return child end
		for j, sub in ipairs(child:GetChildren()) do
			if sub:GetName() == "DCategoryList" then return sub end -- first one = client settings
		end
	end
end

-- // Shared row layout for every category we add {{{
-- There used to be four copies of these helpers, one per category, and their steps had drifted
-- (sliders 28 or 30, notes a fixed 36 or 48, gaps 6 or 8), so rows didn't line up between our
-- categories or with the gamemode's. This is the one copy, using the gamemode's own metrics:
-- 24px left padding, 24px-tall controls starting at y=16, sliders the full content width
-- (contentSize - 48), from cl_offgame.lua's Preferences / Customize HUD categories.
--
-- finish() sizes the content panel to its last row. Without it a category reserves whatever height
-- Derma felt like giving an unsized DPanel, which is where the empty space under our rows came from;
-- the gamemode does the same thing by hand for its own variable-length panels.
S.optionsMetrics = {
	pad    = 24,   -- left / right padding
	top    = 16,   -- first row
	row    = 24,   -- control height
	step   = 24,   -- checkbox row step
	tall   = 28,   -- slider / binder / button row step
	gap    = 8,    -- between groups
	button = 22,   -- button height
	tail   = 8,    -- breathing room under the last row
}

function S.OptionsRows(content, contentSize)
	local M = S.optionsMetrics
	local width = contentSize - M.pad * 2
	local R = { y = M.top, binders = {}, width = width }

	function R.checkbox(label, cvar)
		local cb = content:Add("DCheckBoxLabel")
		cb:SetPos(M.pad, R.y)
		cb:SetText(label)
		cb:SetWide(width)
		cb:SetConVar(cvar)
		cb.Paint = jcms.paint_CheckBoxLabel
		R.y = R.y + M.step
		return cb
	end

	function R.slider(label, cvar, min, max, decimals)
		local sl = content:Add("DNumSlider")
		sl:SetText(label)
		sl:SetSize(width, M.row)
		sl:SetPos(M.pad, R.y)
		sl:SetMinMax(min, max)
		sl:SetDecimals(decimals or 0)
		sl:SetConVar(cvar)
		sl.Paint = jcms.paint_NumSlider
		R.y = R.y + M.tall
		return sl
	end

	-- Key binders read their convar once at build time, so a reset has to push the value back in -
	-- R.binders is what the reset button walks.
	function R.keybind(label, cvar)
		local l = content:Add("DLabel")
		l:SetPos(M.pad, R.y)
		l:SetSize(width - 170, M.row)
		l:SetFont("jcms_small_bolder")
		l:SetText(label)
		l.Think = function(self) self:SetTextColor(jcms.color_bright) end

		local b = content:Add("DBinder")
		b:SetPos(M.pad + width - 160, R.y)
		b:SetSize(160, M.row)
		local cv = GetConVar(cvar)
		local code = cv and input.GetKeyCode(cv:GetString()) or KEY_NONE
		if code and code > 0 then b:SetValue(code) end
		b.OnChange = function(self, newCode)
			if not newCode or newCode <= 0 then return end
			local name = input.GetKeyName(newCode)
			if name then RunConsoleCommand(cvar, string.lower(name)) end
		end
		b.jFont = "jcms_small_bolder"
		b.Paint = jcms.paint_Button

		R.binders[#R.binders + 1] = { binder = b, cvar = cvar }
		R.y = R.y + M.tall
		return b
	end

	function R.button(label, fn, w)
		local b = content:Add("DButton")
		b:SetPos(M.pad, R.y)
		b:SetSize(w or 220, M.button)
		b:SetText(label)
		b.jFont = "jcms_small_bolder"
		b.Paint = jcms.paint_ButtonFilled
		b.DoClick = function()
			surface.PlaySound("buttons/button15.wav")
			fn()
		end
		R.y = R.y + M.button + 6
		return b
	end

	-- Several buttons sharing one row, splitting the content width between them
	function R.buttonRow(list)
		local n = #list
		if n == 0 then return end
		local w = math.floor((width - (n - 1) * 8) / n)
		local made = {}

		for i, entry in ipairs(list) do
			local b = content:Add("DButton")
			b:SetPos(M.pad + (i - 1) * (w + 8), R.y)
			b:SetSize(w, M.button)
			b:SetText(entry.text)
			b.jFont = "jcms_small_bolder"
			b.Paint = jcms.paint_ButtonFilled
			b.DoClick = function()
				surface.PlaySound("buttons/button15.wav")
				entry.fn()
			end
			made[i] = b
		end

		R.y = R.y + M.button + 6
		return unpack(made)
	end

	-- Wrapped text. DLabel's own wrap needs a height before it will lay out and SetAutoStretchVertical
	-- only applies on the next layout pass - which is after the category has already measured itself,
	-- so notes used to come out clipped mid-sentence. The lines are measured here instead and drawn
	-- by hand, so the panel is exactly as tall as the text and nothing is cut off.
	function R.note(text, colorFn)
		local lines, line = {}, ""
		surface.SetFont("jcms_small")
		for word in string.gmatch(tostring(text), "%S+") do
			local test = (line == "") and word or (line .. " " .. word)
			if surface.GetTextSize(test) > width and line ~= "" then
				lines[#lines + 1] = line
				line = word
			else
				line = test
			end
		end
		if line ~= "" then lines[#lines + 1] = line end

		local _, lineH = surface.GetTextSize("Wy")
		lineH = lineH + 2

		local p = content:Add("DPanel")
		p:SetPos(M.pad, R.y)
		p:SetSize(width, #lines * lineH)
		p:SetPaintBackground(false)
		p.Paint = function(self, w, h)
			local col = (colorFn and colorFn()) or jcms.color_bright_alt
			for i, str in ipairs(lines) do
				draw.SimpleText(str, "jcms_small", 0, (i - 1) * lineH, col)
			end
			return true
		end

		R.y = R.y + #lines * lineH + 6
		return p
	end

	-- A label / button pair on one row, for lists whose state isn't a convar (the blocklists)
	function R.toggleRow(text, labelColor, buttonText, onClick)
		local l = content:Add("DLabel")
		l:SetPos(M.pad, R.y + 3)
		l:SetSize(width - 100, M.row - 6)
		l:SetFont("jcms_small_bolder")
		l:SetText(text)
		l.Think = function(self) self:SetTextColor(labelColor()) end

		local b = content:Add("DButton")
		b:SetPos(M.pad + width - 90, R.y)
		b:SetSize(90, M.row)
		b.jFont = "jcms_small_bolder"
		b.Paint = jcms.paint_ButtonFilled
		b.Think = function(self) self:SetText(buttonText()) end
		b.DoClick = function()
			surface.PlaySound("buttons/button15.wav")
			onClick()
		end

		R.y = R.y + M.step + 2
		return l, b
	end

	function R.text(str)
		local l = content:Add("DLabel")
		l:SetPos(M.pad, R.y)
		l:SetSize(width, M.row)
		l:SetFont("jcms_small")
		l:SetText(str)
		l.Think = function(self) self:SetTextColor(jcms.color_bright_alt) end
		R.y = R.y + M.step
		return l
	end

	function R.gap(n) R.y = R.y + (n or M.gap) end

	function R.finish()
		content:SetTall(R.y + M.tail)
		return R.y
	end

	return R
end
-- }}}

function S.AddGameOptionsCategory(tab)
	local catList = findClientCatList(tab)
	if not S.ClaimOptionsCategory(catList, "Implants & Class Levels") then return end
	local contentSize = catList:GetWide()

	local bar = catList:Add("Implants & Class Levels")
	S.PlaceOptionsCategory(catList, bar, S.optionsCatZ.implants)
	bar.Paint = jcms.paint_Category
	bar.dontSubtractHeight = true
	local content = vgui.Create("DPanel", bar)
	content:SetPaintBackground(false)
	content:DockPadding(0, 0, 0, 16)
	bar:SetContents(content)

	local rows = S.OptionsRows(content, contentSize)
	local checkbox, slider, keybind, note = rows.checkbox, rows.slider, rows.keybind, rows.note
	local binders = rows.binders

	checkbox("Show the class level / XP bar", "jcms_implant_hud")
	checkbox("Show ability, perk and buff icons", "jcms_iconhud")
	checkbox("Show passives / buffs in the damage-icon row", "jcms_statusrow")
	checkbox("Screen tints while abilities are active", "jcms_tints")
	rows.gap()
	slider("Ability icons: up / down", "jcms_iconhud_offset", -100, 300, 0)
	slider("Icon size (abilities and status row)", "jcms_iconhud_scale", 0.5, 2, 2)
	slider("Ability icon size", "jcms_iconhud_abilityscale", 0.4, 1.5, 2)
	rows.gap()
	keybind("Ability 1 (highest tier)", "jcms_ability_key")
	keybind("Ability 2", "jcms_ability2_key")
	keybind("Ability 3", "jcms_ability3_key")

	-- Everything this category shows. Add a convar here when you add a control above, or the
	-- reset button will quietly leave it alone.
	local ourCvars = {
		"jcms_implant_hud", "jcms_iconhud", "jcms_statusrow", "jcms_tints",
		"jcms_iconhud_offset", "jcms_iconhud_scale", "jcms_iconhud_abilityscale",
		"jcms_ability_key", "jcms_ability2_key", "jcms_ability3_key",
	}

	local function resetDefaults()
		for i, name in ipairs(ourCvars) do
			local cv = GetConVar(name)
			-- Read the default off the convar rather than repeating it here, so the two can't drift.
			if cv then RunConsoleCommand(name, cv:GetDefault()) end
		end

		-- Console commands only land next frame, so seed the binders from the defaults directly.
		for i, entry in ipairs(binders) do
			local cv = GetConVar(entry.cvar)
			local code = cv and input.GetKeyCode(cv:GetDefault())
			if code and code > 0 then entry.binder:SetValue(code) end
		end
	end

	rows.gap()
	rows.button("Reset these to defaults", resetDefaults)

	note("Icon size covers both the ability icons and the status row, so they stay the same width and height. Icons also follow the HUD scale, HUD colours, motion sickness and colour filter settings above.")
	rows.finish()
end

-- // "MUSIC - BATTLEBEATS" category: buttons that open the BattleBeats addon's own menus {{{
-- BattleBeats (Workshop 3473911205, by N3xsX) registers "battlebeats_menu" (music packs / main menu) and
-- "battlebeats_playlist_editor". If it isn't installed the buttons are greyed out.
local function hasCommand(name)
	local cmds = concommand.GetTable()
	return cmds and cmds[name] ~= nil
end

-- // SERVER tab: our server convars, for admins {{{
-- The options window has two DCategoryLists: the first is the client tab, the second the server
-- tab. findClientCatList takes the first, so this takes the second.
--
-- Controls bind straight to the convars, exactly as the gamemode's own server settings do. That
-- only works because every convar listed here is FCVAR_REPLICATED - a server convar the client
-- can't read shows up as 0 and silently does nothing.
local function findServerCatList(tab)
	local found = {}
	local function scan(panel, depth)
		if depth > 3 then return end
		for i, child in ipairs(panel:GetChildren()) do
			if child:GetName() == "DCategoryList" then
				found[#found + 1] = child
			else
				scan(child, depth + 1)
			end
		end
	end
	scan(tab, 1)
	return found[2]
end

function S.AddServerOptionsCategories(tab)
	local catList = findServerCatList(tab)
	if not IsValid(catList) then return end
	if not S.ClaimOptionsCategory(catList, "Implants - Server") then return end

	local contentSize = catList:GetWide()

	local function category(title, build)
		local bar = catList:Add(title)
		bar.Paint = jcms.paint_Category
		bar.dontSubtractHeight = true
		bar:SetExpanded(false)
		local content = vgui.Create("DPanel", bar)
		content:SetPaintBackground(false)
		content:DockPadding(0, 0, 0, 16)
		bar:SetContents(content)

		local rows = S.OptionsRows(content, contentSize)
		build(rows.checkbox, rows.slider, rows.gap)
		rows.finish()
		return bar
	end

	category("Progression", function(checkbox, slider, gap)
		slider("XP multiplier", "jcms_implant_xpmul", 0, 5, 2)
		checkbox("Wipe levels and implants when a run fails", "jcms_implant_reset_on_gameover")
		gap()
		checkbox("Keep permanent player records", "jcms_records")
		slider("Records need at least this many players", "jcms_records_minplayers", 1, 16)
	end)

	category("Team Upgrades", function(checkbox, slider, gap)
		slider("Upgrade cost multiplier", "jcms_team_costmul", 0, 3, 2)
		checkbox("Guns unlock by completing missions", "sweeper_gununlocks")
		gap()
		slider("V Tokens for finishing a map", "jcms_vtokens_victory", 0, 50)
		slider("V Tokens per extra sweeper", "jcms_vtokens_perplayer", 0, 20)
		slider("V Tokens per sweeper evacuated", "jcms_vtokens_evac", 0, 20)
		slider("Chance a terminal turns up tokens", "jcms_vtokens_terminal_chance", 0, 1, 2)
		gap()
		slider("Upgrade vote time (seconds)", "jcms_team_votetime", 10, 300)
	end)

	-- Blocklist rows. Toggle buttons rather than checkboxes: the state lives in a comma-separated
	-- convar, not one convar per entry, and a DCheckBoxLabel driven from Think would fight its own
	-- OnChange. The button reads the list every frame, so another admin's change shows up here too.
	local function toggleList(title, ids, blockedFn, cmd, emptyText)
		local bar = catList:Add(title)
		bar.Paint = jcms.paint_Category
		bar.dontSubtractHeight = true
		bar:SetExpanded(false)
		local content = vgui.Create("DPanel", bar)
		content:SetPaintBackground(false)
		content:DockPadding(0, 0, 0, 16)
		bar:SetContents(content)

		local rows = S.OptionsRows(content, contentSize)

		if #ids == 0 then
			rows.text(emptyText)
			rows.finish()
			return bar
		end

		for i, id in ipairs(ids) do
			rows.toggleRow(id,
				function() return blockedFn()[id] and jcms.color_dark_alt or jcms.color_bright end,
				function() return blockedFn()[id] and "OFF" or "ON" end,
				function() RunConsoleCommand(cmd, id) end)
		end

		rows.finish()
		return bar
	end

	local function sortedKeys(tbl)
		local out = {}
		for k in pairs(tbl or {}) do out[#out + 1] = string.lower(k) end
		table.sort(out)
		return out
	end

	toggleList("Mission Types", sortedKeys(jcms.missions), S.BlockedMissions,
		"sweeper_mission_toggle", "No mission types found.")
	toggleList("Factions", sortedKeys(jcms.factions), S.BlockedFactions,
		"sweeper_faction_toggle", "No factions found.")

	category("Missions & Players", function(checkbox, slider, gap)
		checkbox("Roll mission modifiers", "jcms_modifiers")
		slider("Most modifiers per mission", "jcms_modifiers_max", 0, 5)
		gap()
		slider("Sub-faction chance", "jcms_subfaction_chance", 0, 1, 2)
		checkbox("Weather has gameplay effects", "jcms_weather_effects")
		gap()
		checkbox("Allow third person", "sweeper_thirdperson")
		checkbox("Allow Outfitter outfits", "jcms_outfits_allowed")
	end)
end
-- // }}}

-- // "THIRD PERSON" category: sits directly under the gamemode's own Preferences {{{
function S.AddThirdPersonCategory(tab)
	local catList = findClientCatList(tab)
	if not S.ClaimOptionsCategory(catList, "Third Person") then return end
	local contentSize = catList:GetWide()

	local bar = catList:Add("Third Person")
	S.PlaceOptionsCategory(catList, bar, S.optionsCatZ.thirdperson)
	bar.Paint = jcms.paint_Category
	bar.dontSubtractHeight = true
	local content = vgui.Create("DPanel", bar)
	content:SetPaintBackground(false)
	content:DockPadding(0, 0, 0, 16)
	bar:SetContents(content)

	local rows = S.OptionsRows(content, contentSize)
	local checkbox, slider, keybind, note = rows.checkbox, rows.slider, rows.keybind, rows.note
	local binders = rows.binders

	local allowed = S.ThirdPersonAllowed and S.ThirdPersonAllowed()

	checkbox("Use third person (over the shoulder)", "jcms_thirdperson")
	checkbox("Drop to first person while aiming", "jcms_thirdperson_ads")
	rows.gap()
	slider("Camera distance", "jcms_thirdperson_dist", 30, 200, 0)
	slider("Shoulder offset", "jcms_thirdperson_right", 0, 60, 0)
	slider("Camera height", "jcms_thirdperson_up", -30, 30, 0)
	rows.gap()
	keybind("Toggle third person", "jcms_thirdperson_key")
	keybind("Swap shoulder", "jcms_thirdperson_swapkey")
	rows.gap(4)

	-- Every convar this category owns. jcms_thirdperson_side has no control of its own - the swap
	-- button sets it - but it still belongs to the reset.
	local ourCvars = {
		"jcms_thirdperson", "jcms_thirdperson_ads", "jcms_thirdperson_dist",
		"jcms_thirdperson_right", "jcms_thirdperson_up", "jcms_thirdperson_side",
		"jcms_thirdperson_key", "jcms_thirdperson_swapkey",
	}

	rows.buttonRow({
		{ text = "Swap shoulder now", fn = function()
			RunConsoleCommand("jcms_thirdperson_swap")
		end },
		{ text = "Reset these to defaults", fn = function()
			for i, name in ipairs(ourCvars) do
				local cv = GetConVar(name)
				if cv then RunConsoleCommand(name, cv:GetDefault()) end
			end

			-- Console commands land next frame, so seed the binders from the defaults directly.
			for i, entry in ipairs(binders) do
				local cv = GetConVar(entry.cvar)
				local code = cv and input.GetKeyCode(cv:GetDefault())
				if code and code > 0 then entry.binder:SetValue(code) end
			end
		end },
	})

	if allowed then
		note("F1 toggles third person and F2 swaps shoulder by default - rebind them above. Your aim is never affected: shots always come from your character, not the camera. The view steps aside on its own while you customize a weapon.")
	else
		note("Third person is switched off on this server (sweeper_thirdperson 0), so these settings do nothing right now.")
	end
	rows.finish()
end
-- // }}}

function S.AddBattleBeatsCategory(tab)
	local catList = findClientCatList(tab)
	if not S.ClaimOptionsCategory(catList, "Music - BattleBeats") then return end
	local contentSize = catList:GetWide()
	local installed = hasCommand("battlebeats_menu")

	local bar = catList:Add("Music - BattleBeats")
	S.PlaceOptionsCategory(catList, bar, S.optionsCatZ.music)
	bar.Paint = jcms.paint_Category
	bar.dontSubtractHeight = true
	local content = vgui.Create("DPanel", bar)
	content:SetPaintBackground(false)
	content:DockPadding(0, 0, 0, 16)
	bar:SetContents(content)

	local rows = S.OptionsRows(content, contentSize)

	local open, editor = rows.buttonRow({
		{ text = "OPEN BATTLEBEATS", fn = function() RunConsoleCommand("battlebeats_menu") end },
		{ text = "PLAYLIST EDITOR",  fn = function() RunConsoleCommand("battlebeats_playlist_editor") end },
	})
	open:SetEnabled(hasCommand("battlebeats_menu"))
	editor:SetEnabled(hasCommand("battlebeats_playlist_editor"))

	rows.note(installed and "Dynamic combat / ambient music. Pick music packs, playlists and volume in the BattleBeats menu."
		or "BattleBeats isn't installed. Subscribe to \"BattleBeats | Dynamic Music System\" on the Workshop to use this.",
		not installed and function() return jcms.color_alert1 or jcms.color_bright end or nil)
	rows.finish()
end
-- }}}

function S.InstallGameOptions()
	if not (jcms and jcms.offgame_BuildOptionsTab) or S.Wrapped(jcms, "OptionsTab") then return end
	local orig = jcms.offgame_BuildOptionsTab
	S._wrappedOptionsTab = function(tab, ...)
		local r = orig(tab, ...)
		local ok, err = pcall(S.AddGameOptionsCategory, tab)
		if not ok then ErrorNoHalt("[Implants] couldn't add our options: " .. tostring(err) .. "\n") end
		local ok4, err4 = pcall(S.AddServerOptionsCategories, tab)
		if not ok4 then ErrorNoHalt("[Implants] couldn't add the server options: " .. tostring(err4) .. "\n") end
		local ok3, err3 = pcall(S.AddThirdPersonCategory, tab)
		if not ok3 then ErrorNoHalt("[Implants] couldn't add the third person options: " .. tostring(err3) .. "\n") end
		local ok2, err2 = pcall(S.AddBattleBeatsCategory, tab)
		if not ok2 then ErrorNoHalt("[Implants] couldn't add the BattleBeats options: " .. tostring(err2) .. "\n") end
		return r
	end
	jcms.offgame_BuildOptionsTab = S._wrappedOptionsTab
	S.MarkWrapped(jcms, "OptionsTab")
end
hook.Add("Initialize", "sweeper_gameOptions", S.InstallGameOptions)
hook.Add("InitPostEntity", "sweeper_gameOptions", S.InstallGameOptions)
S.InstallGameOptions()
-- }}}

-- }}}

-- Builds the whole skills menu inside `frame` (a DFrame for the F4 pop-up, or a plain panel in the lobby).
function S.BuildMenuContents(frame, class, closeable)
	frame.class = class
	frame.view = (S.menuView == "specs") and "specs" or "tree"

	frame.Paint = function(self, w, h)
		local bright, dark, alt = colBright(), colDark(), colAlt()

		-- Panel: the pop-up gets a dark backing (it floats over the game); in the lobby it's see-through
		-- like the gamemode's own tabs. Both get the pulsing cut-corner outline.
		if closeable then
			surface.SetDrawColor(dark.r, dark.g, dark.b, 235)
			polyFilled(0, 0, w, h, 16)
		end
		surface.SetDrawColor(colPulse())
		polyHollow(0, 0, w, h, 16)

		local cd = menuData(self, self.class) or EMPTY_CD
		local maxed = cd.level >= S.maxLevel

		-- Title with the noise strip behind it
		local specName = S.GetTopSpecName(self.class, cd)
		local title = string.upper(S.classNames[self.class]) .. (specName and ("  /  " .. string.upper(specName)) or "")
		if self.inspect and IsValid(self.inspect.ply) then
			title = string.upper(self.inspect.ply:Nick()) .. "  /  " .. title
		end
		surface.SetFont(fnt("jcms_big", "sweeper_title"))
		local tw, th = surface.GetTextSize(title)
		surface.SetDrawColor(bright.r, bright.g, bright.b, 30)
		noise(12, 8, tw + 16, th)
		draw.SimpleText(title, fnt("jcms_big", "sweeper_title"), 20, 8, bright)

		-- Level + XP bar
		draw.SimpleText(string.format("LEVEL %d / %d", cd.level, S.maxLevel), fnt("jcms_medium", "sweeper_med"), 20, 84, bright)
		local bx, by, bw, bh = 170, 90, 320, 14
		local frac = maxed and 1 or math.Clamp(cd.xp / S.XPToNext(cd.level), 0, 1)
		surface.SetDrawColor(bright)
		polyHollow(bx, by, bw, bh, 4)
		if frac > 0 then polyFilled(bx + 2, by + 2, math.max(6, (bw - 4) * frac), bh - 4, 3) end
		surface.SetDrawColor(bright.r, bright.g, bright.b, 40)
		striped(bx + 2 + (bw - 4) * frac, by + 2, (bw - 4) * (1 - frac), bh - 4, 32, CurTime() * 16)
		draw.SimpleText(maxed and "MAX LEVEL" or string.format("%d / %d XP", cd.xp, S.XPToNext(cd.level)), fnt("jcms_small_bolder", "sweeper_small"), bx + bw + 10, by + bh / 2, bright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		-- Chipsets badge: solid when you have some to spend
		local chips = S.ChipsetsAvailable(cd)
		local ctext = string.format("%s: %d", string.upper(S.pointNamePlural), chips)
		surface.SetFont(fnt("jcms_medium", "sweeper_title"))
		local cw = surface.GetTextSize(ctext) + 28
		local cx, cy, ch = w - 16 - cw, 82, 30
		if chips > 0 then
			surface.SetDrawColor(alt)
			polyFilled(cx, cy, cw, ch, 8)
			draw.SimpleText(ctext, fnt("jcms_medium", "sweeper_title"), cx + cw / 2, cy + ch / 2 - 1, colDarkAlt(), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			surface.SetDrawColor(bright.r, bright.g, bright.b, 90)
			polyHollow(cx, cy, cw, ch, 8)
			draw.SimpleText(ctext, fnt("jcms_medium", "sweeper_title"), cx + cw / 2, cy + ch / 2 - 1, ColorAlpha(bright, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- This line used to be every bonus joined into one unwrapped string, which ran clean off the
		-- right edge once a class had a few implants in it. The bonuses live in the strip along the
		-- bottom of the content area now, so all this has to say is when there aren't any yet.
		-- bonusCount is cached by rebuildStrip, so this doesn't re-measure 40 stats every frame
		if (self.bonusCount or 0) == 0 then
			draw.SimpleText("No implants installed yet. Earn XP to gain " .. S.pointNamePlural .. ".",
				fnt("jcms_small", "sweeper_small"), 20, 118, ColorAlpha(bright, 200))
		end
		surface.SetDrawColor(bright.r, bright.g, bright.b, 50)
		striped(16, 134, w - 32, 3, 32)

		-- Bottom line: error/status in the alert colour, otherwise a hint
		if self.statusUntil and CurTime() < self.statusUntil then
			draw.SimpleText(string.upper(self.statusText or ""), fnt("jcms_medium", "sweeper_med"), w / 2, h - 24, colAlert(), TEXT_ALIGN_CENTER)
		else
			local hint
			if self.inspect then
				hint = IsValid(self.inspect.ply)
					and (self.inspect.ply:Nick() .. "'s implants, as they stand right now. You can look, but not change anything.")
					or "Viewing another sweeper's implants. Read-only."
			elseif self.view == "specs" then
				hint = "Pick one specialization per tier. Bonuses stack. Picks can be changed between missions."
			else
				hint = "Hover an implant for details. Click to spend a " .. S.pointName .. ". Bonuses apply instantly while playing that class."
			end
			draw.SimpleText(hint, fnt("jcms_small", "sweeper_small"), w / 2, h - 22, ColorAlpha(bright, 110), TEXT_ALIGN_CENTER)
		end
		return true
	end

	-- Close button (pop-up only)
	if IsValid(frame.btnClose) then
		frame.btnClose:SetVisible(false)
		frame.btnMaxim:SetVisible(false)
		frame.btnMinim:SetVisible(false)
	end
	if closeable then
		local close = vgui.Create("DButton", frame)
		close:SetText("")
		close:SetSize(28, 28)
		close:SetPos(frame:GetWide() - 38, 10)
		close.Paint = function(self, w, h)
			return paintToggle(self, w, h, "X", false, fnt("jcms_medium", "sweeper_title"))
		end
		close.DoClick = function() frame:Remove() end
	end

	-- Class tabs: only in the lobby (in a match you only see your current class)
	local classTabs = {}
	for i, c in ipairs(S.classes) do
		local tab = vgui.Create("DButton", frame)
		classTabs[#classTabs + 1] = tab
		tab:SetText("")
		tab:SetSize(136, 30)
		tab:SetPos(16 + (i - 1) * 142, 46)
		tab.Paint = function(self, w, h)
			local cd = S.cl[c]
			return paintToggle(self, w, h, string.format("%s  LV %d", string.upper(S.classNames[c]), cd and cd.level or 1), frame.class == c)
		end
		tab.DoClick = function()
			frame.class = c
			frame:Refresh()
			surface.PlaySound("buttons/lightswitch2.wav")
		end
	end

	-- Respec
	local respec = vgui.Create("DButton", frame)
	respec:SetText("")
	respec:SetSize(110, 30)
	respec:SetPos(frame:GetWide() - 126, 46)
	respec.Paint = function(self, w, h)
		return paintToggle(self, w, h, "RESET TREE", false)
	end
	respec.DoClick = function()
		local c = frame.class
		Derma_Query("Reset the " .. S.classNames[c] .. " implant tree and refund all " .. S.pointNamePlural .. "?", "Reset Tree",
			"Reset", function() sendAction(ACTION_RESPEC, c) end,
			"Cancel")
	end

	-- View toggle: Skill Tree / Specializations
	-- In the lobby the Options tab is right there, so the Options button is only on the F4 pop-up -
	-- and never when inspecting someone else, where your own settings have no business being.
	local views = { { "tree", "Implant Tree" }, { "specs", "Specializations" } }
	if closeable and not frame.inspect then views[#views + 1] = { "options", "Options" } end
	local rightEdge = frame:GetWide() - (closeable and 48 or 12)

	-- Each button sized to its own label rather than a flat 156, so a third view fits the row instead
	-- of pushing the whole lot left into the title.
	surface.SetFont(fnt("jcms_medium", "sweeper_title"))
	local totalW = 0
	for i, v in ipairs(views) do
		v.w = math.max(84, surface.GetTextSize(string.upper(v[2])) + 26)
		totalW = totalW + v.w + 6
	end
	local bx = rightEdge - totalW
	for i, v in ipairs(views) do
		local bw = v.w
		local b = vgui.Create("DButton", frame)
		b:SetText("")
		b:SetSize(bw, 28)
		b:SetPos(bx, 10)
		bx = bx + bw + 6
		b.Paint = function(self, w, h)
			return paintToggle(self, w, h, string.upper(v[2]), frame.view == v[1])
		end
		b.DoClick = function()
			if v[1] == "options" then
				-- Options = the Map Sweepers options (our settings are in its IMPLANTS & CLASS LEVELS category)
				surface.PlaySound("buttons/button15.wav")
				if S.OpenGameOptions then S.OpenGameOptions() end
				return
			end
			frame.view = v[1]
			S.menuView = v[1]
			frame:Refresh()
			surface.PlaySound("buttons/lightswitch2.wav")
		end
	end

	-- // Content area, with the bonus strip along its bottom {{{
	-- The strip runs along the BOTTOM rather than down the side on purpose. The implant tree lays its
	-- nodes out in 4 fixed 180px columns across the panel width, so taking even 150px off the side
	-- makes those columns overlap at every window size. Height is nearly free by comparison - the tree
	-- sits in a scroll panel whose canvas is already far taller than the viewport, so giving up a band
	-- of height costs a bit of scrolling and nothing else. It shows on both Tree and Specs, so the
	-- totals tick up in front of you as you spend chipsets.
	local contentX, contentY = 16, 140
	local contentW = frame:GetWide() - 32
	local contentH = frame:GetTall() - 180

	local treePanel = vgui.Create("DPanel", frame)
	local statStrip = vgui.Create("DPanel", frame)

	local STRIP_ROW = 19
	local STRIP_HEAD = 22 -- room for the strip's own header line
	local STRIP_MAX = 130

	-- Rebuilt when the tree changes rather than per frame: there's no reason to re-measure 40 stats
	-- sixty times a second.
	local function rebuildStrip(class)
		local cd = menuData(frame, class) or EMPTY_CD
		local parts = S.StatList(S.ComputeStats(class, cd.skills, cd.specs,
			(not frame.inspect) and class == currentClass() and LocalPlayer() or nil))

		statStrip.parts = parts
		frame.bonusCount = #parts
		statStrip.cols = math.max(2, math.floor(contentW / 215))
		statStrip.rows = math.ceil(#parts / statStrip.cols)
		statStrip.offset = 0

		local needed = #parts > 0 and (statStrip.rows * STRIP_ROW + STRIP_HEAD) or 0
		statStrip.fullH = needed
		local shown = math.min(needed, STRIP_MAX)

		statStrip:SetVisible(#parts > 0)
		statStrip:SetPos(contentX, contentY + contentH - shown)
		statStrip:SetSize(contentW, math.max(1, shown))

		-- ...and the tree/specs panel takes whatever height is left
		treePanel:SetPos(contentX, contentY)
		treePanel:SetSize(contentW, contentH - (shown > 0 and (shown + 8) or 0))
	end

	statStrip.OnMouseWheeled = function(self, delta)
		if (self.fullH or 0) <= self:GetTall() then return false end
		self.offset = math.Clamp((self.offset or 0) - delta * STRIP_ROW, 0, self.fullH - self:GetTall())
		return true
	end

	statStrip.Paint = function(self, w, h)
		local parts = self.parts
		if not parts or #parts == 0 then return true end

		local bright, alt = colBright(), colAlt()
		local small = fnt("jcms_small", "sweeper_small")

		surface.SetDrawColor(bright.r, bright.g, bright.b, 40)
		striped(0, 0, w, 2, 32)
		draw.SimpleText(string.format("BONUSES  (%d)", #parts),
			fnt("jcms_small_bolder", "sweeper_med"), 2, 4, ColorAlpha(bright, 220))

		local cols = self.cols or 2
		local colW = math.floor(w / cols)
		local top = STRIP_HEAD - (self.offset or 0)

		-- clipped to the strip, so a scrolled list never bleeds up over the tree
		local sx, sy = self:LocalToScreen(0, STRIP_HEAD - 2)
		local ex, ey = self:LocalToScreen(w, h)
		render.SetScissorRect(sx, sy, ex, ey, true)
		for i, part in ipairs(parts) do
			local c = (i - 1) % cols
			local r = math.floor((i - 1) / cols)
			local x, y = c * colW, top + r * STRIP_ROW
			if y + STRIP_ROW > 0 and y < h then
				surface.SetDrawColor(alt)
				polyFilled(x + 2, y + STRIP_ROW / 2 - 4, 5, 7, 2)
				draw.SimpleText(part, small, x + 12, y + STRIP_ROW / 2, bright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
		render.SetScissorRect(0, 0, 0, 0, false)

		-- only hint at scrolling when the list is actually taller than the cap
		if (self.fullH or 0) > h then
			draw.SimpleText("SCROLL", small, w - 2, 5, ColorAlpha(bright, 110), TEXT_ALIGN_RIGHT)
		end
		return true
	end
	-- }}}

	function frame:Refresh()
		-- Inspecting someone else is read-only: nothing to reset, and no other class to switch to
		-- since the server only sent us the one they're playing.
		respec:SetVisible(self.view == "tree" and not self.inspect)
		local ply = LocalPlayer()
		local inLobby = not closeable or (IsValid(ply) and ply:GetObserverMode() == OBS_MODE_FIXED)
		if not inLobby and not self.inspect then
			self.class = currentClass() or self.class
		end
		for i, t in ipairs(classTabs) do
			if IsValid(t) then t:SetVisible(inLobby and self.view ~= "options" and not self.inspect) end
		end
		-- Size the strip first: the tree/specs builders read treePanel:GetWide()/GetTall()
		rebuildStrip(self.class)
		if self.view == "specs" then
			buildSpecs(self, treePanel, self.class)
		else
			buildTree(self, treePanel, self.class)
		end
	end
	frame:Refresh()
end

function S.OpenMenu(class)
	if IsValid(S.menu) then S.menu:Remove() end

	class = class or currentClass() or "infantry"

	local frame = vgui.Create("DFrame")
	S.menu = frame
	frame:SetSize(math.min(900, ScrW() - 40), math.min(640, ScrH() - 40))
	frame:Center()
	frame:SetTitle("")
	frame:MakePopup()
	frame:SetDraggable(true)
	S.BuildMenuContents(frame, class, true)
end

-- Someone else's implants, from the snapshot the server sent when we right clicked their lobby row.
-- Same menu, read-only: menuData() feeds every read from `data` instead of S.cl, and Refresh hides
-- the reset button and the other class tabs, since we only asked for the class they're playing.
function S.OpenInspectMenu(target, class, data)
	if not (S.IsSkillClass and S.IsSkillClass(class)) then return end
	if IsValid(S.menu) then S.menu:Remove() end

	local frame = vgui.Create("DFrame")
	S.menu = frame
	frame:SetSize(math.min(900, ScrW() - 40), math.min(640, ScrH() - 40))
	frame:Center()
	frame:SetTitle("")
	frame:MakePopup()
	frame:SetDraggable(true)

	-- Set before building: BuildMenuContents and everything it creates read frame.inspect
	frame.inspect = { ply = target, class = class, data = data }
	S.BuildMenuContents(frame, class, true)
end

-- // Lobby ("main menu") tab {{{
-- Adds an "IMPLANTS" tab right after MISSION in the Map Sweepers lobby.
function S.InstallLobbyTab()
	if not (jcms and jcms.offgame_ShowPreMission) or S.Wrapped(jcms, "PreMission") then return end

	local orig = jcms.offgame_ShowPreMission
	S._wrappedPreMission = function(...)
		local r = { orig(...) }

		local pnl = jcms.offgame
		if IsValid(pnl) and pnl.buttonsPrimary and pnl.buttonsPrimary[1] and not IsValid(pnl.sweeperTabButton) then
			local btn = pnl:Add("DButton")
			btn:SetText("IMPLANTS")
			btn.BuildFunc = function(tab)
				local root = tab:Add("DPanel")
				root:SetPos(0, 8)
				root:SetSize(math.min(tab:GetWide(), 900), math.Clamp(tab:GetTall() - 16, 480, 720))
				S.lobbyMenu = root
				S.BuildMenuContents(root, currentClass() or "infantry", false)
			end
			-- Put it second, right after Mission, and renumber the tabs
			table.insert(pnl.buttonsPrimary, 2, btn)
			for i, b in ipairs(pnl.buttonsPrimary) do
				b.listIndex = i
			end
			btn.DoClick = pnl.buttonsPrimary[1].DoClick -- same tab-switching behaviour as the other tabs
			btn.Paint = jcms.paint_Button
			btn:SetPos(-128, -128)
			pnl.sweeperTabButton = btn

			-- TEAM UPGRADES tab, right after IMPLANTS (sh_group.lua)
			if S.BuildGroupMenu then
				local gbtn = pnl:Add("DButton")
				gbtn:SetText("TEAM UPGRADES")
				gbtn.BuildFunc = function(tab)
					local root = tab:Add("DPanel")
					root:SetPos(0, 8)
					root:SetSize(math.min(tab:GetWide(), 900), math.Clamp(tab:GetTall() - 16, 480, 720))
					S.BuildGroupMenu(root)
				end
				-- Shorten the label if it doesn't fit the tab (low resolutions)
				gbtn.Think = function(self)
					if self.sweeperShort or not self.jFont then return end
					surface.SetFont(self.jFont)
					local tw = surface.GetTextSize(self:GetText())
					if tw > self:GetWide() - 12 then
						self:SetText("UPGRADES")
						self.sweeperShort = true
					end
				end
				table.insert(pnl.buttonsPrimary, 3, gbtn)
				for i, b in ipairs(pnl.buttonsPrimary) do
					b.listIndex = i
				end
				gbtn.DoClick = pnl.buttonsPrimary[1].DoClick
				gbtn.Paint = jcms.paint_Button
				gbtn:SetPos(-128, -128)
				pnl.sweeperGroupButton = gbtn

				-- Glow around the tab while an upgrade vote is running
				local origPaintOver = pnl.PaintOver
				pnl.PaintOver = function(self, w, h, ...)
					if origPaintOver then origPaintOver(self, w, h, ...) end
					if S.PaintGroupTabGlow and IsValid(gbtn) then
						local x, y = gbtn:GetPos()
						S.PaintGroupTabGlow(x, y, gbtn:GetWide(), gbtn:GetTall())
					end
				end
			end
		end

		return unpack(r)
	end
	jcms.offgame_ShowPreMission = S._wrappedPreMission
	S.MarkWrapped(jcms, "PreMission")
end
hook.Add("Initialize", "sweeper_lobbyTab", S.InstallLobbyTab)
hook.Add("InitPostEntity", "sweeper_lobbyTab", S.InstallLobbyTab)
S.InstallLobbyTab()
-- }}}
-- // }}}
