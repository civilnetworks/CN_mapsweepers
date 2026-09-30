--[[
	Map Sweepers - Implants & Class Levels (addon)
	Orbital loadout: each sweeper picks which orbitals they bring, 4 of them.

	Every orbital used to be available to everyone all the time, which made the whole category a
	menu of 13 and no decision. Now each player picks 4 and commits to them for the mission.

	  - PER PLAYER, not per squad. A squad can deliberately spread coverage between them.
	  - Picked in the lobby, LOCKED the moment you deploy. Changing your picks mid-mission does
	    nothing until the next one - the snapshot taken at deploy is what's enforced.
	  - 4 slots, plus 1 for each rank of the g_orbitalslots Team Upgrade (sh_group.lua). Team
	    Upgrades are off in PVP, so PVP is always the base 4.
	  - The pool is derived from jcms.orders at runtime - anything in the ORBITALS category, ours
	    and the gamemode's alike - so a new orbital needs no list updating here.

	HOW IT'S ENFORCED (no gamemode edit): S.PlayerCanUseOrder in sh_classorders.lua is already the
	single gate both realms go through - the server's jcms.orders_CanUse wrap refuses an order with
	it, and the client's jcms.orders_RebuildLists wrap uses it to drop entries from the order wheel.
	Wrapping that one function therefore both blocks an unpicked orbital and hides it from the wheel,
	with the server staying the authority.

	Data: sql table sweeper_orbitals (sid64, picks) - one row per player, not per class, because
	orbitals aren't class-locked. Shared between coop and PVP: picks cost nothing and aren't
	progression, so there's no exploit in carrying them across.

	Admin: sweeper_orbitals_status [player]
--]]

local S = sweeper

S.orbitalPicks = {
	enabled = true,

	slots = 4,                      -- orbitals each sweeper may bring
	upgradeId = "g_orbitalslots",   -- Team Upgrade granting more (nil to disable)
	slotsPerRank = 1,

	-- Orbitals that every sweeper always has, and which therefore don't appear in the picker or cost a
	-- slot. Anti-Air Missile is the squad's only answer to a gunship, so making it a pick would mean a
	-- team could walk into an air mission with no way to deal with it.
	exclude = {
		antiairmissile = true,
	},
}

-- Shared UI helpers. Declared at FILE scope on purpose: they're used from more than one `if CLIENT`
-- block below, and a local declared inside one of those blocks is invisible to the others - which is
-- exactly how S.BuildOrbitalPicker ended up calling a nil global `fnt` and erroring on every frame.
local function colBright() return jcms and jcms.color_bright or Color(255, 255, 255) end
local function colDark() return jcms and jcms.color_dark or Color(0, 0, 0) end
local function colAlt() return jcms and jcms.color_bright_alt or colBright() end

-- Same pattern the rest of the menus use: the gamemode's font when it's there, ours as the fallback.
local function fnt(name, fallback) return (jcms and jcms.color_bright) and name or fallback end

function S.OrbitalRules()
	local cfg = S.orbitalPicks
	if not (cfg and cfg.enabled) then return nil end
	return cfg
end

-- // The pool {{{
-- Every ORBITALS-category order the game has, ours and the gamemode's, in the order the wheel shows
-- them. Rebuilt on demand rather than cached: jcms.orders is filled in over several load steps.
function S.OrbitalPool()
	local out = {}
	local cfg = S.OrbitalRules()
	if not (cfg and jcms and istable(jcms.orders) and jcms.SPAWNCAT_ORBITALS) then return out end

	for id, o in pairs(jcms.orders) do
		if istable(o) and o.category == jcms.SPAWNCAT_ORBITALS and not cfg.exclude[id] then
			out[#out + 1] = id
		end
	end

	table.sort(out, function(a, b)
		local A, B = jcms.orders[a], jcms.orders[b]
		local sa, sb = A.slotPos or 99, B.slotPos or 99
		if sa ~= sb then return sa < sb end
		return a < b
	end)
	return out
end

function S.IsOrbitalOrder(id)
	local cfg = S.OrbitalRules()
	if not (cfg and jcms and jcms.SPAWNCAT_ORBITALS) then return false end
	if cfg.exclude[id] then return false end
	local o = jcms.orders and jcms.orders[id]
	return istable(o) and o.category == jcms.SPAWNCAT_ORBITALS
end

-- Slots available right now. S.GroupRank reports 0 in PVP (Team Upgrades are off there), so PVP
-- always gets the base count - no special case needed here.
function S.OrbitalSlots()
	local cfg = S.OrbitalRules()
	if not cfg then return math.huge end

	local n = cfg.slots
	if cfg.upgradeId and S.GroupRank then
		n = n + S.GroupRank(cfg.upgradeId) * (cfg.slotsPerRank or 1)
	end
	return math.max(1, math.floor(n))
end

-- A readable name for an orbital, for menus and chat
function S.OrbitalName(id)
	local c = S.callins and S.callins[id]
	if c and c.name then return c.name end
	local phrase = language and language.GetPhrase and language.GetPhrase("jcms." .. id)
	if phrase and phrase ~= "" and phrase ~= "jcms." .. id then return phrase end
	return id
end
-- }}}

if SERVER then

	util.AddNetworkString("sweeper_orbitals")
	util.AddNetworkString("sweeper_orbital_pick")

-- // Storage {{{
	sql.Query([[CREATE TABLE IF NOT EXISTS sweeper_orbitals (
		sid64 TEXT NOT NULL PRIMARY KEY,
		picks TEXT NOT NULL DEFAULT '[]'
	)]])

	S.orbData = S.orbData or {} -- [sid64] = { id, id, ... } in pick order

	-- A player who has never picked gets the first few of the pool rather than nothing at all
	local function defaultPicks()
		local pool, out = S.OrbitalPool(), {}
		for i = 1, math.min(S.OrbitalSlots(), #pool) do out[i] = pool[i] end
		return out
	end

	local function loadPicks(sid64)
		local rows = sql.Query("SELECT picks FROM sweeper_orbitals WHERE sid64 = " .. sql.SQLStr(sid64))
		local saved = istable(rows) and rows[1] and util.JSONToTable(rows[1].picks or "[]") or nil

		local out = {}
		if istable(saved) then
			for i = 1, #saved do
				local id = tostring(saved[i])
				-- Drop anything that is no longer an orbital, so a retired order can't occupy a slot
				if S.IsOrbitalOrder(id) then out[#out + 1] = id end
			end
		end
		if #out == 0 then out = defaultPicks() end
		return out
	end

	function S.OrbitalPicks(ply)
		if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return {} end
		local sid64 = ply:SteamID64()
		if not sid64 then return {} end
		if not S.orbData[sid64] then S.orbData[sid64] = loadPicks(sid64) end
		return S.orbData[sid64]
	end

	function S.OrbitalSave(ply)
		if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return end
		local sid64 = ply:SteamID64()
		if not sid64 then return end
		sql.Query(string.format("REPLACE INTO sweeper_orbitals (sid64, picks) VALUES (%s, %s)",
			sql.SQLStr(sid64), sql.SQLStr(util.TableToJSON(S.OrbitalPicks(ply)))))
	end

	hook.Add("PlayerDisconnected", "sweeper_orbitalPicks", function(ply)
		if ply:IsBot() then return end
		local sid64 = ply:SteamID64()
		if sid64 then S.orbData[sid64] = nil end
	end)
-- }}}

-- // Locked at deploy {{{
	-- The snapshot is per player and taken as they deploy, so a late joiner is locked to what they
	-- had when THEY dropped in, not to whatever the first player picked.
	local function inMission()
		return jcms and jcms.director ~= nil
	end
	S.OrbitalInMission = inMission

	function S.OrbitalLock(ply)
		if not IsValid(ply) then return end
		local snap = {}
		for i, id in ipairs(S.OrbitalPicks(ply)) do snap[i] = id end
		ply.sweeperOrbLocked = snap
	end

	function S.OrbitalUnlock(ply)
		if IsValid(ply) then ply.sweeperOrbLocked = nil end
	end

	-- The set that COUNTS: the deploy snapshot while one exists, the live picks otherwise
	function S.OrbitalActive(ply)
		if not IsValid(ply) then return {} end
		return ply.sweeperOrbLocked or S.OrbitalPicks(ply)
	end

	hook.Add("MapSweepersClassApplied", "sweeper_orbitalLock", function(ply)
		if not inMission() then return end
		-- Locked once per mission, not on every respawn, or a mid-mission class change would
		-- re-snapshot and quietly let someone swap orbitals by dying.
		if not ply.sweeperOrbLocked then
			S.OrbitalLock(ply)
			S.OrbitalSend(ply)
		end
	end)

	-- Back in the lobby: picks are editable again
	function S.OrbitalReleaseAll()
		for i, ply in ipairs(player.GetHumans()) do
			if ply.sweeperOrbLocked then
				S.OrbitalUnlock(ply)
				S.OrbitalSend(ply)
			end
		end
	end

	timer.Create("sweeper_orbitalRelease", 2, 0, function()
		if not inMission() then S.OrbitalReleaseAll() end
	end)
-- }}}

-- // Networking {{{
	function S.OrbitalSend(ply)
		if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return end
		local picks = S.OrbitalPicks(ply)
		local locked = ply.sweeperOrbLocked

		net.Start("sweeper_orbitals")
			net.WriteBool(locked ~= nil)
			net.WriteUInt(#picks, 5)
			for i = 1, #picks do net.WriteString(picks[i]) end
			-- The locked snapshot too, so the client can show what it's actually flying with
			net.WriteUInt(locked and #locked or 0, 5)
			for i = 1, (locked and #locked or 0) do net.WriteString(locked[i]) end
		net.Send(ply)
	end

	net.Receive("sweeper_orbital_pick", function(len, ply)
		if not IsValid(ply) then return end
		if (ply.sweeperOrbNext or 0) > CurTime() then return end
		ply.sweeperOrbNext = CurTime() + 0.1

		local id = net.ReadString()
		local want = net.ReadBool()

		local cfg = S.OrbitalRules()
		if not cfg then return end
		if inMission() then return end          -- locked in for the mission
		if not S.IsOrbitalOrder(id) then return end

		local picks = S.OrbitalPicks(ply)
		local at
		for i = 1, #picks do if picks[i] == id then at = i break end end

		if want and not at then
			if #picks >= S.OrbitalSlots() then
				S.OrbitalSend(ply) -- full: put the client's view back the way it was
				return
			end
			picks[#picks + 1] = id
		elseif not want and at then
			table.remove(picks, at)
		else
			return -- already in the state they asked for
		end

		S.OrbitalSave(ply)
		S.OrbitalSend(ply)
	end)

	hook.Add("jcms_PlayerNetReady", "sweeper_orbitalPicks", function(ply)
		timer.Simple(1, function() if IsValid(ply) then S.OrbitalSend(ply) end end)
	end)
-- }}}

-- // Enforcement {{{
	-- S.PlayerCanUseOrder is the one gate both realms already funnel through, so wrapping it covers
	-- the server's refusal AND the client dropping the entry from the order wheel.
	function S.InstallOrbitalGate()
		if S.Wrapped(S, "OrbitalGate") or not S.PlayerCanUseOrder then return end
		local orig = S.PlayerCanUseOrder

		S._wrappedOrbitalOrder = function(ply, orderId, ...)
			if not orig(ply, orderId, ...) then return false end
			if not S.OrbitalRules() or not S.IsOrbitalOrder(orderId) then return true end

			for i, id in ipairs(S.OrbitalActive(ply)) do
				if id == orderId then return true end
			end
			return false
		end

		S.PlayerCanUseOrder = S._wrappedOrbitalOrder
		S.MarkWrapped(S, "OrbitalGate")
	end

	local function installAll()
		S.InstallOrbitalGate()
	end
	hook.Add("Initialize", "sweeper_orbitalPicks", installAll)
	hook.Add("InitPostEntity", "sweeper_orbitalPicks", installAll)
-- }}}

	concommand.Add("sweeper_orbitals_status", function(ply, cmd, args)
		if IsValid(ply) and not ply:IsAdmin() then return end
		local say = function(t) if S.PrintConsole and IsValid(ply) then S.PrintConsole(ply, t) else print(t) end end

		local target = ply
		if args[1] then
			for i, p in ipairs(player.GetHumans()) do
				if string.find(string.lower(p:Nick()), string.lower(args[1]), 1, true) then target = p break end
			end
		end

		local pool = S.OrbitalPool()
		local lines = {
			"--- Orbital loadout ---",
			string.format("  pool: %d orbitals    slots: %d (base %d + %s)", #pool, S.OrbitalSlots(),
				S.orbitalPicks.slots,
				S.orbitalPicks.upgradeId and (S.orbitalPicks.upgradeId .. " rank " ..
					tostring(S.GroupRank and S.GroupRank(S.orbitalPicks.upgradeId) or 0)) or "no upgrade"),
			string.format("  in a mission: %s (picks are %s)", tostring(S.OrbitalInMission()),
				S.OrbitalInMission() and "LOCKED" or "editable"),
		}
		if IsValid(target) then
			local names = {}
			for i, id in ipairs(S.OrbitalActive(target)) do names[i] = S.OrbitalName(id) .. " (" .. id .. ")" end
			lines[#lines + 1] = string.format("  %s flying with: %s", target:Nick(),
				#names > 0 and table.concat(names, ", ") or "nothing")
			if target.sweeperOrbLocked then
				local live = {}
				for i, id in ipairs(S.OrbitalPicks(target)) do live[i] = S.OrbitalName(id) end
				lines[#lines + 1] = "  ...and has picked for next mission: " .. table.concat(live, ", ")
			end
		end
		lines[#lines + 1] = "  pool contents: " .. table.concat(pool, ", ")
		say(table.concat(lines, "\n"))
	end, nil, "Admin: show a player's orbital loadout.")

end

if CLIENT then

-- // What the server says we're carrying {{{
	S.orbCl = S.orbCl or { picks = {}, locked = nil }

	function S.OrbitalPicks(ply)
		-- Only ever asked about ourselves on this realm; the wheel filter passes LocalPlayer()
		return S.orbCl.picks or {}
	end

	function S.OrbitalActive(ply)
		return S.orbCl.locked or S.orbCl.picks or {}
	end

	function S.OrbitalLockedCl()
		return S.orbCl.locked ~= nil
	end

	net.Receive("sweeper_orbitals", function()
		local locked = net.ReadBool()

		local picks = {}
		for i = 1, net.ReadUInt(5) do picks[i] = net.ReadString() end
		local snap = {}
		for i = 1, net.ReadUInt(5) do snap[i] = net.ReadString() end

		S.orbCl.picks = picks
		S.orbCl.locked = locked and snap or nil

		-- The order wheel is built from a cached list, so it has to be told to drop or re-add entries
		if jcms and jcms.orders_RebuildLists then pcall(jcms.orders_RebuildLists) end
	end)

	function S.OrbitalTogglePick(id, want)
		net.Start("sweeper_orbital_pick")
			net.WriteString(id)
			net.WriteBool(want and true or false)
		net.SendToServer()
	end

	function S.InstallOrbitalGate()
		if S.Wrapped(S, "OrbitalGate") or not S.PlayerCanUseOrder then return end
		local orig = S.PlayerCanUseOrder

		S._wrappedOrbitalOrder = function(ply, orderId, ...)
			if not orig(ply, orderId, ...) then return false end
			if not S.OrbitalRules() or not S.IsOrbitalOrder(orderId) then return true end

			for i, id in ipairs(S.OrbitalActive(ply)) do
				if id == orderId then return true end
			end
			return false
		end

		S.PlayerCanUseOrder = S._wrappedOrbitalOrder
		S.MarkWrapped(S, "OrbitalGate")
	end

	local function installAll() S.InstallOrbitalGate() end
	hook.Add("Initialize", "sweeper_orbitalPicks", installAll)
	hook.Add("InitPostEntity", "sweeper_orbitalPicks", installAll)
-- }}}

	concommand.Add("sweeper_orbitals_mine", function()
		local names = {}
		for i, id in ipairs(S.OrbitalActive()) do names[i] = S.OrbitalName(id) .. " (" .. id .. ")" end
		print(string.format("--- My orbitals (%s) ---", S.OrbitalLockedCl() and "LOCKED for this mission" or "editable"))
		print("  " .. (#names > 0 and table.concat(names, ", ") or "none picked"))
		print(string.format("  slots: %d   pool: %d", S.OrbitalSlots(), #S.OrbitalPool()))
	end, nil, "Show the orbitals you're carrying.")

end

if CLIENT then

-- // The picker, as a third view in the implants menu {{{
-- Drawn into the ORBITALS tab inside the lobby loadout panel (addLoadoutTabs below).
-- One card per orbital in the pool, in wheel order;
-- clicking toggles it, and the header counts your slots.
--
-- `frame` only needs statusText / statusUntil fields for the refusal messages, so this works in the
-- popup below or in any other panel that has them.
function S.BuildOrbitalPicker(frame, panel)
	panel:Clear()
	panel.Paint = function() end

	local pool = S.OrbitalPool()
	local slots = S.OrbitalSlots()
	local locked = S.OrbitalLockedCl()

	local function picked(id)
		for i, p in ipairs(S.orbCl.picks or {}) do if p == id then return i end end
	end

	-- A DScrollPanel's vertical bar sits inside its width, so the grid has to leave room for it or
	-- the right-hand column is drawn underneath it (which is exactly what it did).
	local pw = panel:GetWide() - (panel.VBar and 18 or 0)
	local gap = 8
	local cols = math.max(1, math.floor((pw + gap) / (190 + gap)))
	local cardW = math.floor((pw - gap * (cols - 1)) / cols)
	local cardH = 84

	-- This IS the section heading: the page is drawn over the gamemode's "WEAPON SHOP" title and its
	-- buy tip, both of which are wrong on this tab, so they're replaced rather than left showing.
	local header = panel:Add("DPanel")
	header:SetPos(0, 0)
	header:SetSize(pw, 56)
	header.Paint = function(self, w, h)
		local c = colBright()
		local alt = colAlt()
		local n = #(S.orbCl.picks or {})

		-- Same place and font the gamemode puts "WEAPON SHOP", so switching tabs just changes the word
		draw.SimpleText("ORBITAL LOADOUT", fnt("jcms_hud_small", "sweeper_title"), 8, 2, c)

		surface.SetFont(fnt("jcms_hud_small", "sweeper_title"))
		local tw = surface.GetTextSize("ORBITAL LOADOUT")
		draw.SimpleText(string.format("%d / %d", n, slots), fnt("jcms_medium", "sweeper_med"),
			8 + tw + 14, 8, n >= slots and alt or c)

		local msg
		if locked then
			msg = "Locked for this mission - change them in the lobby before you deploy."
		elseif n >= slots then
			msg = "Full. Click one to drop it, then pick another."
		else
			msg = string.format("Pick %d more. Only what you carry can be called in.", slots - n)
		end
		draw.SimpleText(msg, fnt("jcms_small", "sweeper_small"), 8, 36, ColorAlpha(c, 170))
		return true
	end

	for i, id in ipairs(pool) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local o = jcms.orders[id]
		local name = string.upper(S.OrbitalName(id))
		local cost = o and o.cost or 0
		local cd = o and o.cooldown or 0

		local card = panel:Add("DButton")
		card:SetText("")
		card:SetPos(col * (cardW + gap), 64 + row * (cardH + gap))
		card:SetSize(cardW, cardH)
		S.SetSweeperTooltip(card, function()
			local carried = picked(id)
			return {
				{ text = string.upper(S.OrbitalName(id)), font = fnt("jcms_medium", "sweeper_title") },
				{ text = string.format("%d J    %ds cooldown", cost, cd), color = ColorAlpha(colBright(), 170) },
				{ text = S.OrbitalLockedCl() and "LOCKED FOR THIS MISSION"
					or (carried and "CLICK TO DROP" or "CLICK TO CARRY"), color = colAlt() },
			}
		end)

		card.Paint = function(self, w, h)
			local at = picked(id)
			local on = at ~= nil
			local c = jcms.color_bright
			local alt = jcms.color_bright_alt
			local dark = jcms.color_dark
			local hov = self:IsHovered() and not locked

			surface.SetDrawColor(dark.r, dark.g, dark.b, 200)
			surface.DrawRect(0, 0, w, h)
			if hov then
				surface.SetDrawColor(c.r, c.g, c.b, 25)
				surface.DrawRect(0, 0, w, h)
			end

			-- Carried: solid edge and a slot number. Not carried: faint outline.
			surface.SetDrawColor(on and alt or ColorAlpha(c, locked and 40 or 70))
			surface.DrawOutlinedRect(0, 0, w, h, on and 2 or 1)

			if on then
				surface.SetDrawColor(alt)
				surface.DrawRect(0, 0, 4, h)
				draw.SimpleText(tostring(at), fnt("jcms_medium", "sweeper_title"), w - 8, 6, alt, TEXT_ALIGN_RIGHT)
			end

			local textC = on and c or ColorAlpha(c, locked and 90 or 140)
			draw.SimpleText(name, fnt("jcms_title", "sweeper_med"), 12, 10, textC)
			draw.SimpleText(string.format("%d J", cost), fnt("jcms_small", "sweeper_small"), 12, h - 32, ColorAlpha(textC, 200))
			draw.SimpleText(string.format("%ds cooldown", cd), fnt("jcms_small", "sweeper_small"), 12, h - 18, ColorAlpha(textC, 150))
			return true
		end

		card.DoClick = function()
			if locked then
				surface.PlaySound("buttons/button10.wav")
				frame.statusText = "Orbitals are locked once you deploy."
				frame.statusUntil = CurTime() + 2.5
				return
			end

			local at = picked(id)
			if not at and #(S.orbCl.picks or {}) >= slots then
				surface.PlaySound("buttons/button10.wav")
				frame.statusText = string.format("All %d orbital slots are full - drop one first.", slots)
				frame.statusUntil = CurTime() + 2.5
				return
			end

			S.OrbitalTogglePick(id, not at)
			surface.PlaySound(at and "buttons/button19.wav" or "buttons/button14.wav")
		end
	end

	-- The server answers a pick with the authoritative set, so redraw when it lands
	panel.sweeperOrbPicks = #(S.orbCl.picks or {})
	panel.Think = function(self)
		local n = #(S.orbCl.picks or {})
		if n ~= self.sweeperOrbPicks or locked ~= S.OrbitalLockedCl() then
			self.sweeperOrbPicks = n
			if IsValid(frame) and frame.Refresh then frame:Refresh() end
		end
	end
end
-- }}}

end

if CLIENT then

-- // Map Sweepers styled tooltip {{{
-- Derma's default tooltip is the grey GMod box, which looks wrong against this UI. Panel:SetTooltipPanel
-- hands Derma our own panel to show instead - the same trick the gamemode uses for its online-player
-- list - so positioning, hover delay and lifetime stay Derma's problem and only the drawing is ours.
--
-- getLines() is called each frame while the tooltip is up and returns { {text=, font=, color=}, ... }.
-- Returning nothing collapses it to nothing drawn, which is how a tooltip turns itself off when the
-- thing it describes no longer needs one.
local function blankPaint() end

-- Every plain Panel:SetTooltip in the game - ours and the gamemode's - is drawn by Derma through the
-- default skin's PaintTooltip. Overriding that one function restyles the lot in place, with no need
-- to touch a single call site. This is deliberately global: it is the only way to catch the tooltips
-- the gamemode sets on its own buttons.
function S.InstallTooltipSkin()
	if S.Wrapped(S, "TooltipSkin") then return end

	local skin = derma and derma.GetDefaultSkin and derma.GetDefaultSkin()
	if not istable(skin) then return end

	skin.PaintTooltip = function(self, panel, w, h)
		local dark, bright = colDark(), colBright()
		surface.SetDrawColor(dark.r, dark.g, dark.b, 248)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(bright)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		surface.SetDrawColor(bright.r, bright.g, bright.b, 60)
		if jcms.hud_DrawStripedRect then
			jcms.hud_DrawStripedRect(1, 1, w - 2, 3, 32)
		else
			surface.DrawRect(1, 1, w - 2, 3)
		end
		return true
	end

	-- DTooltip colours its label from the skin, so the text follows the box.
	if istable(skin.Colours) then
		skin.Colours.TooltipText = colBright()
	end

	S.MarkWrapped(S, "TooltipSkin")
end

hook.Add("Initialize", "sweeper_tooltipSkin", function() pcall(S.InstallTooltipSkin) end)
hook.Add("InitPostEntity", "sweeper_tooltipSkin", function() pcall(S.InstallTooltipSkin) end)
pcall(S.InstallTooltipSkin)

function S.SetSweeperTooltip(target, getLines)
	if not IsValid(target) then return end

	local tip = vgui.Create("DPanel")
	tip:SetVisible(false)
	tip:SetPaintBackground(false)
	tip:SetSize(180, 40)
	tip.lines = {}

	tip.Think = function(self)
		-- Derma re-parents this into a DTooltip when it shows it; blank that wrapper's own background
		-- or the grey frame draws behind ours.
		local parent = self:GetParent()
		if IsValid(parent) and parent.Paint ~= blankPaint then parent.Paint = blankPaint end

		local ok, lines = pcall(getLines)
		if not ok or not istable(lines) then lines = {} end
		self.lines = lines

		if #lines == 0 then
			self:SetSize(1, 1)
			return
		end

		local widest = 0
		for i, ln in ipairs(lines) do
			surface.SetFont(ln.font or fnt("jcms_small_bolder", "sweeper_small"))
			widest = math.max(widest, (surface.GetTextSize(tostring(ln.text or ""))))
		end
		self:SetSize(widest + 24, 10 + #lines * 16 + 8)
	end

	tip.Paint = function(self, w, h)
		local lines = self.lines
		if not lines or #lines == 0 then return end

		local dark, bright = colDark(), colBright()
		surface.SetDrawColor(dark.r, dark.g, dark.b, 248)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(bright)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		-- the striped accent the rest of the panels use
		surface.SetDrawColor(bright.r, bright.g, bright.b, 60)
		if jcms.hud_DrawStripedRect then
			jcms.hud_DrawStripedRect(1, 1, w - 2, 3, 32)
		else
			surface.DrawRect(1, 1, w - 2, 3)
		end

		for i, ln in ipairs(lines) do
			draw.SimpleText(tostring(ln.text or ""), ln.font or fnt("jcms_small_bolder", "sweeper_small"),
				12, 8 + (i - 1) * 16, ln.color or bright)
		end
		return true
	end

	target:SetTooltipPanel(tip)
	target:SetTooltipDelay(0.18)
	return tip
end
-- }}}

-- // WEAPONS / ORBITALS tabs inside the loadout {{{
-- The shop half of the loadout panel becomes two tabs. WEAPONS is the gamemode's own gun shop,
-- untouched - picking ORBITALS just hides its widgets and shows our grid over the same area.
--
-- Nothing in the gamemode is edited: its shop widgets are all hung off tab.loadoutPnl by name, so
-- they can be shown and hidden from here.
local SHOP_WIDGETS = { "shopScroller", "sortComboBox", "categoryComboBox", "reverseSort" }

-- DScrollPanel sizes its canvas from its children, but the cards are positioned absolutely, so the
-- bottom-most one is measured directly rather than trusting the layout pass.
local function fitCanvas(p)
	local canvas = p.GetCanvas and p:GetCanvas()
	if not IsValid(canvas) then return end
	local bottom = 0
	for i, c in ipairs(canvas:GetChildren()) do
		bottom = math.max(bottom, c:GetY() + c:GetTall())
	end
	canvas:SetTall(bottom + 8)
end

local function addLoadoutTabs(tab)
	local pnl = tab and tab.loadoutPnl
	if not IsValid(pnl) or pnl.sweeperOrbTabs then return end
	if not S.OrbitalRules() then return end
	pnl.sweeperOrbTabs = true

	-- Top of the SHOP box, the same figure offgame_paint_LoadoutPanel uses to draw its outline
	local lowres = pnl.lowres
	local y1 = lowres and 128 or (164 + 32 + 8)
	local btnW, btnH = lowres and 96 or 120, 24
	local btnY = y1 + 6
	-- Right-aligned to the panel edge. "ORBITAL LOADOUT" is a good bit wider than the "WEAPON SHOP"
	-- it replaces, so a fixed x here put the tabs straight through the end of the title.
	local btnX = math.max(256, pnl:GetWide() - 8 - (btnW * 2 + 4))

	-- Our page covers the shop box from just under the tab row down, including the left column where
	-- the gun-stats readout paints, so it's drawn opaque.
	-- Covers the SHOP box from its top edge down, heading included: on this tab "WEAPON SHOP" and
	-- "click a weapon to buy it" are both wrong, so the page draws its own title over them. The tab
	-- buttons are added after the page, so they stay on top of it.
	local top = y1 + 2
	local page = pnl:Add("DScrollPanel")
	page:SetPos(16, top)
	page:SetSize(pnl:GetWide() - 32, math.max(120, pnl:GetTall() - top - 16))
	page:SetVisible(false)

	-- The gamemode hides the bar's buttons and paints only the grip; match it, or this one scrollbar
	-- is the only stock-Derma thing on screen.
	if IsValid(page.VBar) then
		page.VBar.Paint = function() end
		page.VBar:SetHideButtons(true)
		if IsValid(page.VBar.btnGrip) and jcms.paint_ScrollGrip then
			page.VBar.btnGrip.Paint = jcms.paint_ScrollGrip
		end
	end
	page.Paint = function(self, w, h)
		local dark = colDark()
		surface.SetDrawColor(dark.r, dark.g, dark.b, 250)
		surface.DrawRect(0, 0, w, h)
		if self.statusUntil and CurTime() < self.statusUntil then
			draw.SimpleText(string.upper(self.statusText or ""), fnt("jcms_medium", "sweeper_med"),
				w / 2, h - 18, jcms.color_alert or colBright(), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
	end
	-- The picker uses the panel it draws into as its host (statusText, Refresh), so page is both.
	page.Refresh = function(self)
		S.BuildOrbitalPicker(self, self)
		fitCanvas(self)
	end

	local tabs = {}
	local function setView(which)
		pnl.sweeperOrbView = which
		for i, name in ipairs(SHOP_WIDGETS) do
			local wdg = pnl[name]
			if IsValid(wdg) then wdg:SetVisible(which == "weapons") end
		end
		page:SetVisible(which == "orbitals")
		if which == "orbitals" then
			-- Re-fit on every show: loadoutPnl's height is set with a formula that reads its own
			-- GetTall(), so the value at build time isn't necessarily the one it settles on.
			page:SetSize(pnl:GetWide() - 32, math.max(120, pnl:GetTall() - top - 16))
			page:Refresh()
		end
	end

	for i, def in ipairs({ { "weapons", "WEAPONS" }, { "orbitals", "ORBITALS" } }) do
		local b = pnl:Add("DButton")
		b:SetSize(btnW, btnH)
		b:SetPos(btnX + (i - 1) * (btnW + 4), btnY)
		b:SetText("")
		b.Paint = function(self, w, h)
			local on = pnl.sweeperOrbView == def[1]
			local bright, alt = colBright(), colAlt()
			local hov = self:IsHovered()

			if on then
				surface.SetDrawColor(bright)
				surface.DrawRect(0, 0, w, h)
			else
				surface.SetDrawColor(hov and alt or ColorAlpha(bright, 90))
				surface.DrawOutlinedRect(0, 0, w, h, 1)
			end

			local label = def[2]
			if def[1] == "orbitals" then
				label = string.format("%s %d/%d", def[2], #(S.orbCl.picks or {}), S.OrbitalSlots())
			end
			draw.SimpleText(label, fnt("jcms_small_bolder", "sweeper_small"), w / 2, h / 2,
				on and colDark() or (hov and alt or bright), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return true
		end
		b.DoClick = function()
			if pnl.sweeperOrbView == def[1] then return end
			surface.PlaySound("buttons/button15.wav")
			setView(def[1])
		end
		tabs[i] = b
	end

	setView("weapons")
end

function S.InstallOrbitalLoadoutTabs()
	if not (jcms and jcms.offgame_BuildMissionPrepTab) or S.Wrapped(jcms, "OrbitalLoadoutTabs") then return end
	local orig = jcms.offgame_BuildMissionPrepTab

	S._wrappedOrbLoadoutTab = function(tab, ...)
		local rtn = { orig(tab, ...) }
		local ok, err = pcall(addLoadoutTabs, tab)
		if not ok then ErrorNoHalt("[sweeper] orbital loadout tabs: " .. tostring(err) .. "\n") end
		return unpack(rtn)
	end

	jcms.offgame_BuildMissionPrepTab = S._wrappedOrbLoadoutTab
	S.MarkWrapped(jcms, "OrbitalLoadoutTabs")
end

hook.Add("Initialize", "sweeper_orbitalTab", S.InstallOrbitalLoadoutTabs)
hook.Add("InitPostEntity", "sweeper_orbitalTab", S.InstallOrbitalLoadoutTabs)
-- }}}

end
