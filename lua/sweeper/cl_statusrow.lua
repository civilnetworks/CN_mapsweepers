--[[
	Map Sweepers - Implants & Class Levels (addon)
	Client: status row.

	The gamemode has a row of damage-type icons at the top of the health-bar panel - radiation,
	biohazard, oxygen, fracture (jcms.hud_damageIndicators / jcms.draw_DamageIndicators in
	cl_hud.lua). That is not a status system: each icon lights when a damage packet of that type
	arrives and fades a few seconds after the last one. There is no duration, no stack count and
	no server-side state behind it.

	This file puts our own statuses in that same row and in the same style: the passives you get
	from your specializations, every buff, and every debuff. Abilities stay bottom-right on their
	own panel; the bottom-left row is now only this.

	It draws inside the SAME 3D2D matrix the gamemode uses (setup3d2dDiagonal(false, true) - the
	health-bar panel), so the coordinates here are the gamemode's: 64-unit icons, a 3-unit offset
	between the dark shadow and the bright layer, 16 units of gap.

	Nothing in the mapsweepers folder is edited: jcms.draw_DamageIndicators is wrapped and our row
	is drawn after the stock icons.

	ADDING A DEBUFF
		S.hudDebuffs[#S.hudDebuffs + 1] = { id = "myDebuff", icon = "shock", get = function(ply)
			local left = ply:GetNWFloat("sweeper_myDebuff", 0) - CurTime()
			if left > 0 then return { left = left, total = 8 } end
		end }
	`get` returns nil when inactive, or { left, total, stacks, text, bar } - the same contract
	S.hudBuffs uses. Debuffs are tinted with the alert colour so they read apart from buffs.
--]]

if SERVER then return end

local S = sweeper

local cvar_on = CreateClientConVar("jcms_statusrow", "1", true, false, "Show implant passives, buffs and debuffs in the gamemode's damage-icon row.")

-- Size comes from the SAME setting as the ability / perk icons (jcms_iconhud_scale, declared in
-- cl_hudicons.lua) so the two never drift apart. Our icons are square, so it drives both their
-- width and their height. 1.0 = 64 wide, matching the gamemode's own damage icons exactly.
local BASE_WIDTH = 64
local function widthCvar()
	return GetConVar("jcms_iconhud_scale")
end

-- // Debuffs {{{
-- Same contract as S.hudBuffs. Empty by default: the addon has no networked player debuffs yet,
-- so this is the hook to hang them on as they get built.
S.hudDebuffs = S.hudDebuffs or {}
-- }}}

-- // Materials {{{
local mats = {}
local function icon(name)
	if not name then return nil end
	local m = mats[name]
	if m == nil then
		m = Material("sweeper/icons/" .. name .. ".png", "smooth mips")
		if m:IsError() then m = false end
		mats[name] = m
	end
	return m or nil
end
-- }}}

-- The gamemode's own indicators are a fixed 64 wide with 16 of gap (cl_hud.lua
-- draw_DamageIndicators). These two are used ONLY to work out where its row ends - our icons are
-- sized by the convar below, so they must not be derived from it.
local STOCK_ICON, STOCK_GAP = 64, 16

local ROW_X, ROW_Y = 30, -256 + 32
local ROW_WIDTH = 640  -- usable width before our row wraps upward
local FONT = "jcms_small"

-- Everything about our icons scales off the width, so the offset, bar and spacing stay in
-- proportion at any size. 64 reproduces the gamemode's own look exactly.
local function metrics()
	local cv = widthCvar()
	local w = math.Clamp(math.Round(BASE_WIDTH * (cv and cv:GetFloat() or 1)), 24, 160)
	local gap = math.max(4, math.floor(w / 4))
	local perRow = math.Clamp(math.floor(ROW_WIDTH / (w + gap)), 3, 14)
	return w, gap, perRow, math.max(1, math.Round(w / 21)), math.max(2, math.floor(w / 13))
end

local function timerText(t)
	return string.format("%04.1fs", math.max(0, t))
end

-- // Collecting what's active {{{
function S.StatusRowEntries(ply)
	local out = {}

	-- Passives: one per specialization you've picked.
	for i, specId in ipairs(S.GetLocalSpecs and S.GetLocalSpecs(ply) or {}) do
		local def = S.hudPassives and S.hudPassives[specId]
		if def then
			local left, total, label
			if def.timer then
				local ok, a, b, c = pcall(def.timer, ply)
				if ok then left, total, label = a, b, c end
			end

			out[#out + 1] = {
				icon = def.icon,
				kind = "passive",
				left = (left and left > 0) and left or nil,
				-- A passive on cooldown fills up; one that's simply running drains.
				bar = (left and total and total > 0) and math.Clamp(def.cooldown and (1 - left / total) or (left / total), 0, 1) or nil,
				text = label,
				dim = def.cooldown and left and left > 0,
			}
		end
	end

	local function collect(list, kind)
		for i, b in ipairs(list or {}) do
			local ok, st = pcall(b.get, ply)
			if ok and st and (not st.left or st.left > 0) then
				out[#out + 1] = {
					icon = b.icon or b.id,
					kind = kind,
					left = st.left,
					stacks = st.stacks,
					text = st.text,
					bar = st.bar or (st.left and st.total and st.total > 0 and math.Clamp(st.left / st.total, 0, 1)) or nil,
				}
			end
		end
	end

	collect(S.hudBuffs, "buff")
	collect(S.hudDebuffs, "debuff")

	return out
end
-- }}}

-- // Drawing {{{
-- Always the live HUD theme colours, never the per-effect colours in S.hudBuffs / S.hudPassives:
-- those are fixed values and would ignore the player's HUD theme. The tables keep them because
-- the screen-tint code in cl_skills.lua still uses them.
-- Theme-swapped names are color_bright/_dark, their _alt pair, and color_alert1/2 (cl_hud.lua
-- hudShift). Plain `jcms.color_alert` is NOT swapped, so don't reach for it here.
local function entryColors(kind)
	if kind == "passive" then
		return jcms.color_bright, jcms.color_dark
	elseif kind == "debuff" then
		return jcms.color_alert1 or jcms.color_bright, jcms.color_dark
	end
	return jcms.color_bright_alt, jcms.color_dark_alt   -- buffs, as the old bottom-left row had them
end

local function drawEntry(e, x, y, ICON, OFF, BAR_H)
	local mat = icon(e.icon)
	if not mat then return end

	local bright, dark = entryColors(e.kind)
	bright = bright or color_white
	dark = dark or color_black

	if e.dim then surface.SetAlphaMultiplier(0.45) end

	-- Same two-layer look the gamemode's indicators use: dark shadow, bright additive on top.
	surface.SetMaterial(mat)
	surface.SetDrawColor(dark)
	surface.DrawTexturedRect(x, y, ICON, ICON)

	render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		surface.SetDrawColor(bright)
		surface.DrawTexturedRect(x + OFF, y - OFF, ICON, ICON)
	render.OverrideBlend(false)

	if e.dim then surface.SetAlphaMultiplier(1) end

	-- Progress bar directly under the icon.
	if e.bar then
		surface.SetDrawColor(dark)
		surface.DrawRect(x, y + ICON + OFF, ICON, BAR_H)
		surface.SetDrawColor(bright)
		surface.DrawRect(x, y + ICON + OFF, ICON * math.Clamp(e.bar, 0, 1), BAR_H)
	end

	-- Stack count in the top-right corner, the way the old buff row did it.
	if e.stacks and e.stacks > 0 then
		draw.SimpleText("x" .. e.stacks, FONT, x + ICON + OFF, y - OFF - 2, bright, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end

	-- Buffs and debuffs read off the bar alone - no countdown, no label. Passives keep their text
	-- because several of them (NONE / MAX) have no bar to read instead.
	if e.kind == "passive" then
		local label = e.left and timerText(e.left) or e.text
		if label then
			local ly = y + ICON + (e.bar and (OFF + BAR_H + 3) or (OFF + 2))
			draw.SimpleText(label, FONT, x + ICON / 2 + 1, ly + 1, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			draw.SimpleText(label, FONT, x + ICON / 2, ly, bright, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	end
end

function S.DrawStatusRow()
	if not cvar_on:GetBool() then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	if jcms.team_JCorp_player and not jcms.team_JCorp_player(ply) then return end

	local entries = S.StatusRowEntries(ply)
	if #entries == 0 then return end

	local ICON, GAP, PER_ROW, OFF, BAR_H = metrics()

	-- Carry on from where the gamemode's own icons stopped. Their spacing shrinks as they fade, so
	-- read it off their live alpha - and use THEIR fixed size, not ours.
	local x = ROW_X
	for i, ind in ipairs(jcms.hud_damageIndicators or {}) do
		x = x + (STOCK_ICON + STOCK_GAP) * ((ind.alpha or 0) ^ 0.5)
	end

	local rowStep = ICON + math.max(12, math.floor(ICON * 0.53))
	local col, row = 0, 0
	for i, e in ipairs(entries) do
		-- Rows stack upward so a long list never runs off the side of the panel.
		drawEntry(e, x + col * (ICON + GAP), ROW_Y - row * rowStep, ICON, OFF, BAR_H)
		col = col + 1
		if col >= PER_ROW then
			col, row = 0, row + 1
			x = ROW_X
		end
	end

	surface.SetAlphaMultiplier(1)
end
-- }}}

-- // Install {{{
function S.InstallStatusRow()
	if not (jcms and jcms.draw_DamageIndicators) then return end
	if S.Wrapped(jcms, "DamageIndicators") then return end

	local orig = jcms.draw_DamageIndicators
	jcms.draw_DamageIndicators = function(...)
		orig(...)

		-- Never let a bad status entry take the whole HUD down with it.
		local ok, err = pcall(S.DrawStatusRow)
		if not ok then
			surface.SetAlphaMultiplier(1)
			render.OverrideBlend(false)
			if not S.statusRowErrored then
				S.statusRowErrored = true
				ErrorNoHalt("[mapsweepers_skills] status row draw failed: " .. tostring(err) .. "\n")
			end
		end
	end

	S.MarkWrapped(jcms, "DamageIndicators")
end

hook.Add("Initialize", "sweeper_statusrow", function() S.InstallStatusRow() end)
hook.Add("InitPostEntity", "sweeper_statusrow", function() S.InstallStatusRow() end)
-- }}}
