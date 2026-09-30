--[[
	Map Sweepers - Implants & Class Levels (addon)
	Client: icon HUD for specialization abilities and perk buffs.

	Drawn inside the gamemode's own HUD pass (the "MapSweepersDrawHUD" hook), so it:
	  - uses the Map Sweepers HUD colours (jcms_hud_color_* / themes) and HUD fonts,
	  - scales with jcms_hud_scale, sways with the HUD (or not, with jcms_motionsickness),
	  - hides whenever the gamemode hides its HUD (spectating, lobby, dead, intro sequence),
	  - uses the same "dark shadow + bright glow" look as the health bar and Sentinel barrier.

	ABILITIES  bottom-right HUD panel, left of the ammo counter (slot 1 nearest the ammo, up to 3 slots). Key shows
	           underneath when ready ("[G]"). On cooldown the panel dims, stripes fill up and a 00.0s
	           countdown shows underneath. While running it glows with the time left underneath.
	PERKS      bottom-left HUD panel, a row above the health / shield bars; timers underneath.
	BUFFS      a second row above the perks (only while active); stacks in the corner, timer underneath.

	Icons live in materials/sweeper/icons/*.png (white on transparent, tinted in code).
	Client convars: jcms_iconhud (0/1), jcms_iconhud_offset (move up/down),
	                jcms_iconhud_scale (size, on top of jcms_hud_scale),
	                jcms_iconhud_abilityscale (ability row only, on top of jcms_iconhud_scale).
--]]

local S = sweeper

local cvar_on     = CreateClientConVar("jcms_iconhud", "1", true, false, "Show ability / perk icons on the HUD.")
local cvar_offset = CreateClientConVar("jcms_iconhud_offset", "0", true, false, "Move the ability icons up (+) or down (-).", -100, 300)
local cvar_scale  = CreateClientConVar("jcms_iconhud_scale", "1", true, false, "Size of the ability / perk icons (on top of jcms_hud_scale).", 0.5, 2)
-- The class ability panels are big next to the ammo counter, so they get their own multiplier on
-- top of the shared size. It scales the whole row - panel, countdown and keybind together.
local cvar_abscale = CreateClientConVar("jcms_iconhud_abilityscale", "0.7", true, false, "Size of the class ability icons, on top of jcms_iconhud_scale.", 0.4, 1.5)

-- // Materials {{{
local mats = {}
local function icon(name)
	local m = mats[name]
	if m == nil then
		m = Material("sweeper/icons/" .. name .. ".png", "smooth mips")
		if m:IsError() then m = false end
		mats[name] = m
	end
	return m or nil
end
-- }}}

local function timerText(t)
	return string.format("%04.1fs", math.max(0, t))
end

-- // Ability definitions: icon + "is it running right now?" {{{
-- active(ply) returns secondsLeft, totalSeconds (or nil when not running)
S.hudAbilities = {
	scout = { icon = "pulse", color = Color(255, 160, 60), active = function(ply)
		local left = ply:GetNWFloat("sweeper_pulseUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "pulseDuration", S.recon.pulseDuration) end
	end },
	infiltrator = { icon = "decoy", color = Color(120, 190, 255), active = function(ply)
		local left = ply:GetNWFloat("sweeper_decoyUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "decoyDuration", S.recon.decoyDuration) end
	end },
	phantom = { icon = "phantom", color = Color(150, 200, 255), active = function(ply)
		if ply:GetNWBool("sweeper_cloaked", false) and ply:GetNWBool("sweeper_phantomCloak", false) then
			return ply:GetNWFloat("sweeper_cloakEnd", 0) - CurTime(), S.Tune(ply, "phantomCloakMaxLeft", S.recon.phantomCloakMaxLeft)
		end
	end },
	bountyhunter = { icon = "execute", color = Color(255, 50, 50), active = function(ply)
		local left = ply:GetNWFloat("sweeper_execUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "executionDuration", S.recon.executionDuration) end
	end },
	gunslinger = { icon = "autoaim", color = Color(255, 90, 60) },
	stalker = { icon = "oneshot", color = Color(255, 140, 40), active = function(ply)
		local left = ply:GetNWFloat("sweeper_oneShotUntil", 0) - CurTime()
		if left > 0 then return left, S.recon.oneShotDuration end
	end },
	enforcer = { icon = "charge", color = Color(255, 170, 60), active = function(ply)
		local left = ply:GetNWFloat("sweeper_chargeUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "chargeDuration", S.sentinel.chargeDuration) end
	end },
	aegis = { icon = "dome", color = Color(120, 200, 255), active = function(ply)
		local left = ply:GetNWFloat("sweeper_domeUntil", 0) - CurTime()
		if left > 0 and ply:GetNWInt("sweeper_domeHP", 0) > 0 then return left, S.Tune(ply, "domeDuration", S.sentinel.domeDuration) end
	end },
	guardian = { icon = "lifeline", color = Color(120, 255, 160) },

	-- Engineer
	technician = { icon = "overclock", color = Color(120, 200, 255), active = function(ply)
		local left = ply:GetNWFloat("sweeper_overclockUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "overclockDuration", S.engineer.overclockDuration) end
	end },
	medic = { icon = "triage", color = Color(120, 255, 160) },
	mechanic = { icon = "quickdeploy", color = Color(255, 200, 90) },
	fieldsurgeon = { icon = "barrierburst", color = Color(120, 200, 255) },
	dronemaster = { icon = "swarm", color = Color(120, 200, 255), active = function(ply)
		local left = ply:GetNWFloat("sweeper_swarmUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "swarmLifetime", S.engineer.swarmLifetime) end
	end },

	-- Sentinel
	juggernaut = { icon = "ironskin", color = Color(170, 190, 220), active = function(ply)
		local left = ply:GetNWFloat("sweeper_ironSkinUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "ironSkinDuration", S.sentinel.ironSkinDuration) end
	end },
	brawler = { icon = "groundpound", color = Color(255, 110, 70) },
	bastion = { icon = "challenge", color = Color(255, 170, 60), active = function(ply)
		local left = ply:GetNWFloat("sweeper_challengeUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "challengeDuration", S.sentinel.challengeDuration) end
	end },
	ravager = { icon = "bloodlust", color = Color(255, 60, 40), active = function(ply)
		local left = ply:GetNWFloat("sweeper_bloodlustUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "bloodlustMax", S.sentinel.bloodlustMax) end
	end },

	-- Infantry
	commando = { icon = "adrenaline", color = Color(160, 220, 110), active = function(ply)
		local left = ply:GetNWFloat("sweeper_commandoStimUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "commandoStimDuration", S.infantry.commandoStimDuration) end
	end },
	ranger = { icon = "focus", color = Color(160, 220, 110), active = function(ply)
		local left = ply:GetNWFloat("sweeper_focusUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "focusDuration", S.infantry.focusDuration) end
	end },
	grenadier = { icon = "barrage", color = Color(255, 140, 60) },
	quartermaster = { icon = "resupply", color = Color(255, 200, 90) },
	fieldcommander = { icon = "battlecry", color = Color(255, 210, 80), active = function(ply)
		local left = ply:GetNWFloat("sweeper_battleCryUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "battleCryDuration", S.infantry.battleCryDuration) end
	end },
	shocktrooper = { icon = "overdrive", color = Color(255, 225, 60), active = function(ply)
		local left = ply:GetNWFloat("sweeper_overdriveUntil", 0) - CurTime()
		if left > 0 then return left, S.Tune(ply, "overdriveMax", S.infantry.overdriveMax) end
	end },
}
-- }}}

-- // Passive perk definitions (one per specialization) {{{
-- timer(ply) may return: secondsLeft, totalSeconds, label   (label shown instead of a timer, e.g. "MAX")
-- cooldown = true means the timer is a cooldown (icon greys out while it runs)
local function specCooldown(nw)
	return function(ply)
		local left = ply:GetNWFloat(nw, 0) - CurTime()
		if left > 0 then return left end
	end
end

S.hudPassives = {
	scout         = { icon = "spot",      color = Color(255, 160, 60) },
	gunslinger    = { icon = "quickdraw", color = Color(255, 200, 90) },
	phantom       = { icon = "jump",      color = Color(150, 200, 255) },
	bountyhunter        = { icon = "contract",  color = Color(255, 70, 70), timer = function(ply)
		if IsValid(ply:GetNWEntity("sweeper_hit")) then
			local left = ply:GetNWFloat("sweeper_hitEnd", 0) - CurTime()
			if left > 0 then return left, S.recon.hitDuration end
		end
		return nil, nil, "NONE"
	end },
	commando      = { icon = "bloodlust", color = Color(160, 220, 110), timer = function(ply)
		-- Combat Cocktail: show how much damage the stims on you are currently worth.
		local n = S.CountStims and S.CountStims(ply) or 0
		if n <= 0 then return nil, nil, "NONE" end
		return nil, nil, string.format("+%d%%", math.Round(n * S.infantry.cocktailDamagePerStim * 100))
	end },
	ranger        = { icon = "scope",     color = Color(160, 220, 110) },
	quartermaster = { icon = "ammo",      color = Color(255, 200, 90), timer = function(ply)
		local left = GetGlobalFloat("sweeper_qmNext", 0) - CurTime()
		if left > 0 then return left, S.infantry.qmInterval end
	end },
	fieldcommander= { icon = "rally",     color = Color(120, 255, 160) },
	shocktrooper  = { icon = "adrenaline",color = Color(255, 225, 60), cooldown = true, timer = specCooldown("sweeper_adrenalineReady") },
	technician    = { icon = "turret",    color = Color(120, 200, 255) },
	medic         = { icon = "medic",     color = Color(120, 255, 160) },
	mechanic      = { icon = "wrench",    color = Color(255, 200, 90) },
	fieldsurgeon  = { icon = "surgeon",   color = Color(120, 200, 255) },
	dronemaster     = { icon = "drone",     color = Color(120, 200, 255) },
	bastion       = { icon = "taunt",     color = Color(255, 170, 60), timer = function(ply)
		-- Taunt runs off a damage pool: count down the lockout, otherwise show how much pool is left
		-- A label rather than (left, total): the bar under a passive reads as "filling up", which is
		-- the wrong way round for a pool that is recharging, and the status row draws it the same way.
		local ready = ply:GetNWFloat("sweeper_tauntReady", 0) - CurTime()
		if ready > 0 then return nil, nil, string.format("%ds", math.ceil(ready)) end

		local max = ply:GetNWFloat("sweeper_tauntChargeMax", 0)
		local cur = ply:GetNWFloat("sweeper_tauntCharge", 0)
		if max > 0 and cur < max then
			return nil, nil, string.format("%d%%", math.floor(cur / max * 100))
		end
		return nil, nil, ply:GetNWBool("sweeper_tauntOn", false) and "ON" or "OFF"
	end },
	ravager       = { icon = "rage",      color = Color(255, 80, 40), cooldown = true, timer = specCooldown("sweeper_rageReady") },
	stalker  = { icon = "weakpoint", color = Color(255, 170, 40) },
	grenadier     = { icon = "cluster",   color = Color(255, 140, 60) },
	infiltrator   = { icon = "spec_infiltrator",  color = Color(150, 200, 255) },
	juggernaut    = { icon = "spec_juggernaut",   color = Color(120, 200, 255) },
	brawler       = { icon = "spec_brawler",      color = Color(255, 110, 70), timer = function(ply)
		-- Frenzy: how many melee-kill stacks are running
		local stacks = S.FrenzyStacks and S.FrenzyStacks(ply) or 0
		if stacks <= 0 then return nil, nil, "NONE" end
		return nil, nil, "x" .. stacks
	end },
	enforcer      = { icon = "spec_enforcer",     color = Color(255, 150, 90) },
	aegis         = { icon = "spec_aegis",        color = Color(120, 200, 255) },
	guardian      = { icon = "spec_guardian",     color = Color(120, 255, 160) },
}

function S.GetLocalSpecs(ply)
	local class = ply:GetNWString("jcms_class", "")
	local cd = S.cl and S.cl[class]
	local out = {}
	if not (cd and cd.specs) then return out end
	for tier = 1, 3 do
		local id = cd.specs[tier] or cd.specs[tostring(tier)]
		if id then out[#out + 1] = id end
	end
	return out
end
-- }}}

-- // Buff definitions {{{
-- get(ply) returns nil when inactive, or { left = secs|nil, total = secs|nil, stacks = n|nil, text = string|nil }
S.hudBuffs = {
	{ id = "quickdraw", icon = "quickdraw", color = Color(255, 200, 90), get = function(ply)
		local stacks = S.QuickdrawStacks and S.QuickdrawStacks(ply) or 0
		if stacks > 0 then
			return { stacks = stacks, left = ply:GetNWFloat("sweeper_qdExpire", 0) - CurTime(), total = S.recon.quickdrawDuration }
		end
	end },
	{ id = "shock", icon = "shock", color = Color(255, 210, 60), get = function(ply)
		local stacks = ply:GetNWInt("sweeper_shockStacks", 0)
		if stacks > 0 then
			return { stacks = stacks, left = ply:GetNWFloat("sweeper_shockExpire", 0) - CurTime(), total = S.infantry.shockStackDuration }
		end
	end },
	{ id = "adrenaline", icon = "adrenaline", color = Color(255, 225, 60), get = function(ply)
		local left = ply:GetNWFloat("sweeper_adrenalineUntil", 0) - CurTime()
		if left > 0 then return { left = left, total = S.infantry.adrenalineDuration } end
	end },
	{ id = "frenzy", icon = "spec_brawler", color = Color(255, 110, 70), get = function(ply)
		local stacks = S.FrenzyStacks and S.FrenzyStacks(ply) or 0
		if stacks > 0 then
			return { stacks = stacks, left = ply:GetNWFloat("sweeper_frenzyExpire", 0) - CurTime(), total = S.sentinel.frenzyDuration }
		end
	end },
	{ id = "rage", icon = "rage", color = Color(255, 80, 40), get = function(ply)
		local left = ply:GetNWFloat("sweeper_rageUntil", 0) - CurTime()
		if left > 0 then return { left = left, total = S.sentinel.rageDuration } end
	end },
	{ id = "dome", icon = "shield", color = Color(120, 200, 255), get = function(ply)
		if not S.GetActiveDomes then return end
		for i, owner in ipairs(S.GetActiveDomes()) do
			if owner == ply or ply:WorldSpaceCenter():DistToSqr(owner:WorldSpaceCenter()) <= S.sentinel.domeRadius ^ 2 then
				return {
					left = owner:GetNWFloat("sweeper_domeUntil", 0) - CurTime(), total = S.Tune(owner, "domeDuration", S.sentinel.domeDuration),
					text = tostring(owner:GetNWInt("sweeper_domeHP", 0)),
					bar = math.Clamp(owner:GetNWInt("sweeper_domeHP", 0) / S.Tune(owner, "domeHealth", S.sentinel.domeHealth), 0, 1),
				}
			end
		end
	end },
	{ id = "overshield", icon = "barrierburst", color = Color(120, 200, 255), get = function(ply)
		local left = ply:GetNWFloat("sweeper_overshieldUntil", 0) - CurTime()
		if left > 0 and ply:Armor() > ply:GetMaxArmor() then return { left = left, total = S.Tune(ply, "barrierBurstDuration", S.engineer.barrierBurstDuration) } end
	end },
	{ id = "battlecry", icon = "battlecry", color = Color(255, 210, 80), get = function(ply)
		local left = ply:GetNWFloat("sweeper_battleCryUntil", 0) - CurTime()
		if left > 0 then return { left = left, total = S.infantry.battleCryDuration } end
	end },
	{ id = "rally", icon = "rally", color = Color(120, 255, 160), get = function(ply)
		if ply:GetNWBool("sweeper_rallied", false) then return { text = "RALLY" } end
	end },
	{ id = "haste", icon = "haste", color = Color(120, 230, 255), get = function(ply)
		if ply:GetNWBool("sweeper_hasted", false) then return { text = "HASTE" } end
	end },
	{ id = "taunt", icon = "taunt", color = Color(255, 170, 60), get = function(ply)
		-- No pool bar here: the Bullet Barrier bar at the bottom of the screen is the pool readout now
		if ply:GetNWBool("sweeper_taunting", false) then return { text = "TAUNT" } end
	end },
}
-- }}}

-- // Drawing helpers (3D2D units: the gamemode's HUD panels are ~4 units per pixel at 1080p) {{{
local OFF = 8 -- how far the bright layer floats above its dark shadow, like the gamemode HUD
local vec_scale = Vector(1, 1, 1)
local vec_move = Vector(0, 0, 0)

local function additive(on)
	if on then
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
	else
		render.OverrideBlend(false)
	end
end

local function drawIcon(name, x, y, s, col)
	local m = icon(name)
	if m then
		surface.SetMaterial(m)
		surface.SetDrawColor(col)
		surface.DrawTexturedRect(x, y, s, s)
	else
		draw.SimpleText(string.upper(string.sub(name, 1, 2)), "jcms_hud_medium", x + s / 2, y + s / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

-- Text with the gamemode's dark shadow + bright additive copy
local function glowText(text, font, x, y, bright, dark, ax, ay)
	draw.SimpleText(text, font, x, y, dark, ax, ay)
	additive(true)
		draw.SimpleText(text, font, x, y - OFF, bright, ax, ay)
	additive(false)
end

--[[ One icon panel.
	st.bright / st.dark   colours (from the HUD theme)
	st.fill               "ready" | "running" | "cooldown" | nil
	st.bar                0-1 bar along the bottom edge (time left / progress)
	st.stripes            0-1 striped fill from the bottom (cooldown progress)
	st.alpha              extra alpha (dimmed when unavailable)
--]]
local function panel(name, x, y, s, st, baseAlpha)
	local a = baseAlpha * (st.alpha or 1)
	local cut = s * 0.2
	local barH = math.max(10, s * 0.07)

	surface.SetAlphaMultiplier(a)
	surface.SetDrawColor(st.dark.r, st.dark.g, st.dark.b, 230)
	jcms.hud_DrawFilledPolyButton(x, y, s, s, cut)

	additive(true)
		local b = st.bright
		local by = y - OFF
		-- soft body
		if st.fill == "running" then
			surface.SetDrawColor(b.r, b.g, b.b, 22 + 18 * ((math.sin(CurTime() * 6) + 1) / 2))
			jcms.hud_DrawFilledPolyButton(x, by, s, s, cut)
			surface.SetDrawColor(b.r, b.g, b.b, 30)
			jcms.hud_DrawNoiseRect(x + cut, by, s - cut, s - cut, 128)
		elseif st.fill == "ready" then
			surface.SetDrawColor(b.r, b.g, b.b, 26)
			jcms.hud_DrawFilledPolyButton(x, by, s, s, cut)
		end
		if st.stripes and st.stripes > 0 then
			local h = (s - barH) * st.stripes
			surface.SetDrawColor(b.r, b.g, b.b, 40)
			jcms.hud_DrawStripedRect(x, by + s - barH - h, s - cut * 0.5, h, 96, CurTime() * 40)
		end
		-- icon
		local pad = s * 0.16
		drawIcon(name, x + pad, by + pad - barH * 0.4, s - pad * 2, b)
		-- bottom bar
		if st.bar then
			surface.SetDrawColor(b)
			surface.DrawRect(x, by + s - barH, (s - cut) * math.Clamp(st.bar, 0, 1), barH)
		end
	additive(false)
	surface.SetAlphaMultiplier(baseAlpha)
end

local function keyName(slot)
	local cv = GetConVar(slot == 1 and "jcms_ability_key" or ("jcms_ability" .. slot .. "_key"))
	return cv and string.upper(cv:GetString()) or tostring(slot)
end

-- Fade while the call-in menu is open (the gamemode shrinks its HUD then too)
local function spaceAlpha()
	return 1 - 0.75 * math.Clamp(jcms.hud_spawnmenuAnim or 0, 0, 1)
end

-- Hide our corner icons in vehicles that hide the matching gamemode panel
local function panelShown(ply, field)
	local veh = ply:GetNWEntity("jcms_vehicle")
	if not IsValid(veh) then return true end
	return veh:GetTable()[field] and true or false
end

-- Our own size / height on top of the gamemode's HUD scale. Returns false when hidden.
local vec_scale2 = Vector(1, 1, 1)
local vec_move2 = Vector(0, 0, 0)
local function pushLayout(x, y, extraScale)
	local k = math.Clamp(cvar_scale:GetFloat(), 0.5, 2) * (extraScale or 1)
	local m = Matrix()
	vec_move2:SetUnpacked(x, y - cvar_offset:GetFloat() * 4, 0)
	m:Translate(vec_move2)
	vec_scale2:SetUnpacked(k, k, 1)
	m:Scale(vec_scale2)
	cam.PushModelMatrix(m, true)
end

local function withLayout(x, y, extraScale, fn, ...)
	pushLayout(x, y, extraScale)
	local ok, err = pcall(fn, ...)
	surface.SetAlphaMultiplier(1)
	render.OverrideBlend(false)
	cam.PopModelMatrix()
	if not ok then error(err, 0) end
end
-- }}}

-- // ABILITIES: bottom-right HUD panel, to the left of the ammo counter {{{
-- Origin = bottom-right corner of the ability row; panels grow to the left and up.
local function drawAbilities(ply, alpha)
	local bright, dark = jcms.color_bright, jcms.color_dark
	local brightAlt, darkAlt = jcms.color_bright_alt, jcms.color_dark_alt
	local ct = CurTime()
	surface.SetAlphaMultiplier(alpha)

	local abilities = S.GetPlayerAbilities and S.GetPlayerAbilities(ply) or {}
	local size, gap = 200, 48
	local count = math.min(#abilities, 3)
	if count == 0 then return end
	local y = -size

	for slot = 1, count do
		-- slot 1 sits closest to the ammo counter (right), slots 2 and 3 further left
		local id = abilities[slot]
		local ab = S.abilities[id]
		local def = S.hudAbilities[id] or { icon = id }
		local px = -slot * size - (slot - 1) * gap
		local ready = S.AbilityStatus(ply, id)
		local left, total
		if def.active then left, total = def.active(ply) end
		local running = left and left > 0

		local cdLeft, cdTotal, used = 0, ply:GetNWFloat("sweeper_cdTotal_" .. id, ab.cooldown or 1), false
		if ab.oncePerMission then
			used = ply:GetNWBool("sweeper_used_" .. id, false)
		elseif ab.cooldown then
			cdLeft = math.max(0, ply:GetNWFloat("sweeper_readyAt_" .. id, 0) - ct)
		end

		local st
		if running then
			st = { bright = bright, dark = dark, fill = "running", bar = total and total > 0 and left / total or 1 }
		elseif used then
			st = { bright = bright, dark = dark, alpha = 0.3 }
		elseif cdLeft > 0 then
			st = { bright = bright, dark = dark, alpha = 0.45, stripes = 1 - math.Clamp(cdLeft / cdTotal, 0, 1) }
		else
			st = { bright = brightAlt, dark = darkAlt, fill = ready and "ready" or nil, bar = 1, alpha = ready and 1 or 0.45 }
		end
		panel(def.icon, px, y, size, st, alpha)

		local extra = def.extra and def.extra(ply)
		if extra then
			glowText(extra, "jcms_hud_small", px + size / 2, y - 18, st.bright, st.dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end

		-- Underneath: 00.0s countdown / time left, or the key when ready
		local tx, ty = px + size / 2, 20
		if running then
			glowText(timerText(left), "jcms_hud_medium", tx, ty, bright, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		elseif used then
			surface.SetAlphaMultiplier(alpha * 0.4)
			glowText("USED", "jcms_hud_medium", tx, ty, bright, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			surface.SetAlphaMultiplier(alpha)
		elseif cdLeft > 0 then
			glowText(timerText(cdLeft), "jcms_hud_medium", tx, ty, bright, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		else
			glowText("[" .. keyName(slot) .. "]", "jcms_hud_medium", tx, ty, brightAlt, darkAlt, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	end
end
-- }}}

-- // PERKS + BUFFS: bottom-left HUD panel, above the health / shield bars {{{
-- Origin = bottom-left of the perk row. Buffs sit in a second row above the perks.
local function drawPerksAndBuffs(ply, alpha)
	local bright, dark = jcms.color_bright, jcms.color_dark
	local brightAlt, darkAlt = jcms.color_bright_alt, jcms.color_dark_alt
	surface.SetAlphaMultiplier(alpha)

	-- Perks (one per subclass you've picked)
	local passives = {}
	for i, specId in ipairs(S.GetLocalSpecs and S.GetLocalSpecs(ply) or {}) do
		if S.hudPassives[specId] then passives[#passives + 1] = S.hudPassives[specId] end
	end

	local ps, pgap = 120, 30
	local px = 0
	for i, def in ipairs(passives) do
		local left, total, label
		if def.timer then left, total, label = def.timer(ply) end
		local onCooldown = def.cooldown and left and left > 0

		local st
		if onCooldown then
			st = { bright = bright, dark = dark, alpha = 0.45, stripes = total and (1 - math.Clamp(left / total, 0, 1)) or nil }
		else
			st = { bright = bright, dark = dark, bar = (left and total and total > 0) and (1 - math.Clamp(left / total, 0, 1)) or nil }
		end
		panel(def.icon, px, -ps, ps, st, alpha)

		local tx, ty = px + ps / 2, 14
		if label then
			glowText(label, "jcms_hud_small", tx, ty, bright, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		elseif left and left > 0 then
			glowText(timerText(left), "jcms_hud_small", tx, ty, bright, dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
		px = px + ps + pgap
	end

	-- Buffs (only while active)
	local active = {}
	for i, b in ipairs(S.hudBuffs) do
		local ok, state = pcall(b.get, ply)
		if ok and state and (not state.left or state.left > 0) then
			active[#active + 1] = { def = b, st = state }
		end
	end
	if #active == 0 then return end

	local bs, bgap = 110, 30
	local by = (#passives > 0) and (-ps - 90 - bs) or -bs
	local bx = 0
	for i, entry in ipairs(active) do
		local def, st = entry.def, entry.st
		local frac = st.bar or (st.left and st.total and st.total > 0 and math.Clamp(st.left / st.total, 0, 1)) or nil
		panel(def.icon, bx, by, bs, { bright = brightAlt, dark = darkAlt, fill = "ready", bar = frac }, alpha)

		if st.stacks then
			glowText("x" .. st.stacks, "jcms_hud_small", bx + bs, by - 6, brightAlt, darkAlt, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		elseif st.text and st.left then
			glowText(st.text, "jcms_hud_small", bx + bs / 2, by - 6, brightAlt, darkAlt, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end

		local tx, ty = bx + bs / 2, by + bs + 14
		if st.left then
			glowText(timerText(st.left), "jcms_hud_small", tx, ty, brightAlt, darkAlt, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		elseif st.text then
			glowText(st.text, "jcms_hud_small", tx, ty, brightAlt, darkAlt, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
		bx = bx + bs + bgap
	end
end
-- }}}

-- // Register with the HUD framework (cl_skills.lua) {{{
if S.AddHud then
	-- Right of the screen, left of the ammo counter. This x is the RIGHT edge of the icon block
	-- (slots lay out leftward from it), in HUD units - about 4 per pixel.
	-- -520 is where the old left/right slider sat at 50: the original -720 plus 50 * 4.
	local ABILITY_X = -520

	S.AddHud("iconAbilities", "bottomright", function(ply, hudAlpha)
		if not cvar_on:GetBool() or not panelShown(ply, "DoDrawAmmo") then return end
		local alpha = hudAlpha * spaceAlpha()
		if alpha <= 0.01 then return end
		withLayout(ABILITY_X, 0, math.Clamp(cvar_abscale:GetFloat(), 0.4, 1.5), drawAbilities, ply, alpha)
	end)

	-- Passives and buffs used to live here, above the health bar. They now share the gamemode's
	-- damage-icon row (radiation / oxygen / fracture) instead - see cl_statusrow.lua.
	-- drawPerksAndBuffs is kept above so the old layout is one AddHud call away if we want it back:
	--   S.AddHud("iconPerksBuffs", "bottomleft", function(ply, hudAlpha)
	--       if not cvar_on:GetBool() or not panelShown(ply, "DoDrawHealthbar") then return end
	--       local alpha = hudAlpha * spaceAlpha()
	--       if alpha <= 0.01 then return end
	--       withLayout(40, -190, 1, drawPerksAndBuffs, ply, alpha)
	--   end)
end
-- }}}
