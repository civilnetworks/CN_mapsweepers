--[[
	Map Sweepers - Implants & Class Levels (addon)
	Over-the-shoulder third person.

	Each player toggles it for themselves; the server decides whether it's allowed at all
	(sweeper_thirdperson, replicated). Allowed in PvP too - the advantage is symmetric.

	AIMING IS UNTOUCHED. Shots are traced from the player's shoot position on the server, which has
	nothing to do with where the client puts its camera, so pulling the view back changes what you
	SEE and nothing else. That is the whole reason this can stay client-side.

	The gamemode owns GM:CalcView (cl_init.lua) and does real work in it: per-class view sway for
	Recon, the Sentinel's sprint bob, vehicle driver cams, the ragdoll death cam and the evac
	fly-out. We must not replace it. hook.Add("CalcView") runs BEFORE the GM function and skips it
	when it returns a table, so instead we call the gamemode's own CalcView ourselves, then pull the
	camera back from whatever it produced. Everything it does is preserved.

	Client convars: jcms_thirdperson (0/1), jcms_thirdperson_dist,
	                jcms_thirdperson_right (0-60, how far out to the side),
	                jcms_thirdperson_side (1 / -1, set by the swap button, not shown in settings),
	                jcms_thirdperson_up, jcms_thirdperson_ads (first person while aiming).

	Third person also steps aside on its own while a weapon's customization / attachment menu is
	open - those menus pose the gun at the camera and can't be used from behind the player.
	Console commands: jcms_thirdperson_toggle, jcms_thirdperson_swap
	Keys: jcms_thirdperson_key (default F1), jcms_thirdperson_swapkey (default F2) - both
	      rebindable in Options > Third Person.
--]]

local S = sweeper

-- Replicated: created on both realms so the client can read the server's answer.
if SERVER then
	CreateConVar("sweeper_thirdperson", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
		"Allow players to use over-the-shoulder third person.")
	return
end

local cvar_on    = CreateClientConVar("jcms_thirdperson", "0", true, false, "Use over-the-shoulder third person.")
local cvar_dist  = CreateClientConVar("jcms_thirdperson_dist", "80", true, false, "How far the third-person camera sits behind you.", 30, 200)
local cvar_right = CreateClientConVar("jcms_thirdperson_right", "22", true, false, "How far the third-person camera sits out to the side.", 0, 60)
-- Which shoulder, as 1 or -1. Hidden from the settings panel on purpose: the slider is a distance,
-- and the side is the swap button's business. Saved so it survives a restart.
local cvar_side = CreateClientConVar("jcms_thirdperson_side", "1", true, false, "Which shoulder the third-person camera sits over: 1 right, -1 left.", -1, 1)

-- Older builds stored the side as the sign of jcms_thirdperson_right. Migrate those once so the
-- slider isn't stuck at a negative it can no longer display.
local function normaliseShoulder()
	local v = cvar_right:GetFloat()
	if v < 0 then
		RunConsoleCommand("jcms_thirdperson_right", tostring(-v))
		RunConsoleCommand("jcms_thirdperson_side", "-1")
	end
end
normaliseShoulder()
hook.Add("InitPostEntity", "sweeper_thirdperson_migrate", normaliseShoulder)
local cvar_up    = CreateClientConVar("jcms_thirdperson_up", "4", true, false, "How far the third-person camera sits above your eyes.", -30, 30)
local cvar_ads   = CreateClientConVar("jcms_thirdperson_ads", "1", true, false, "Drop back to first person while aiming down sights. 0 stays in third person.", 0, 1)
local cvar_key     = CreateClientConVar("jcms_thirdperson_key", "f1", true, false, "Key that toggles third person (e.g. f1, v, mouse4).")
local cvar_swapkey = CreateClientConVar("jcms_thirdperson_swapkey", "f2", true, false, "Key that swaps the camera to your other shoulder.")

-- // When it's allowed to be on {{{
function S.ThirdPersonAllowed()
	local sv = GetConVar("sweeper_thirdperson")
	return not sv or sv:GetBool()
end

-- // Weapon-base detection {{{
-- The gamemode supports several weapon bases (its own, ArcCW, TFA, CW2.0, FA:S) and we can't
-- depend on any of them being installed, so every check is guarded. Add more to either table and
-- they get picked up automatically.

-- Is the attachment / customization menu open? Third person has to get out of the way for it:
-- those menus pose the gun in front of the camera and are unusable from behind the player.
S.ThirdPersonCustomizeChecks = {
	function(ply, wep)  -- ArcCW
		local A = _G.ArcCW
		if not A then return false end
		if A.InAttMenu then return true end
		if A.STATE_CUSTOMIZE and isfunction(wep.GetState) and wep:GetState() == A.STATE_CUSTOMIZE then return true end
		return false
	end,
	function(ply, wep)  -- CW 2.0
		if not _G.CustomizableWeaponry then return false end
		if _G.CW_CUSTOMIZE and wep.dt and wep.dt.State == _G.CW_CUSTOMIZE then return true end
		return false
	end,
	function(ply, wep)  -- generic: a base that exposes it plainly
		if wep.Customizing or wep.CustomizeMenuOpen then return true end
		if isfunction(wep.GetCustomize) and wep:GetCustomize() then return true end
		return false
	end,
}

-- Aiming down sights / scoped in.
S.ThirdPersonSightChecks = {
	function(ply, wep) return isfunction(wep.GetInSights) and wep:GetInSights() end,    -- ArcCW
	function(ply, wep) return isfunction(wep.GetIronSights) and wep:GetIronSights() end, -- TFA
	function(ply, wep) return isfunction(wep.GetIronsights) and wep:GetIronsights() end, -- FA:S and friends
	function(ply, wep)                                                                   -- CW 2.0
		return _G.CW_AIMING ~= nil and wep.dt and wep.dt.State == _G.CW_AIMING
	end,
	function(ply, wep)                                                                   -- M9K and similar
		-- Only for weapons that clearly HAVE ironsights: plenty of SWEPs use secondary fire for
		-- a grenade or a melee swing, and flipping the view on those would be wrong.
		return wep.IronSightsPos ~= nil and ply:KeyDown(IN_ATTACK2)
	end,
}

local function anyCheck(list, ply, wep)
	for i, fn in ipairs(list) do
		local ok, res = pcall(fn, ply, wep)
		if ok and res then return true end
	end
	return false
end

function S.ThirdPersonCustomizing(ply)
	local wep = IsValid(ply) and ply:GetActiveWeapon()
	if not IsValid(wep) then return false end
	return anyCheck(S.ThirdPersonCustomizeChecks, ply, wep)
end

function S.ThirdPersonAiming(ply)
	local wep = IsValid(ply) and ply:GetActiveWeapon()
	if not IsValid(wep) then return false end
	return anyCheck(S.ThirdPersonSightChecks, ply, wep)
end
-- }}}

-- The gamemode's own view handles all of these far better than we could, so we stay out of them:
-- spectating, the lobby, driving, the drop pod, the death ragdoll cam and the evac fly-out.
function S.ThirdPersonActive(ply)
	if not cvar_on:GetBool() or not S.ThirdPersonAllowed() then return false end
	if not (IsValid(ply) and ply:Alive()) then return false end
	if ply:GetObserverMode() ~= OBS_MODE_NONE then return false end
	if IsValid(ply:GetNWEntity("jcms_vehicle")) then return false end
	if IsValid(ply:GetRagdollEntity()) then return false end

	-- Second return value: "snap", for reasons that should switch quickly rather than glide.

	-- Any seat. The drop pod sits you in a prop_vehicle_prisoner_pod of its own (jcms_droppod.lua
	-- spawns one and calls EnterVehicle) and never sets the gamemode's jcms_vehicle, so the check
	-- above missed it and the camera hung outside the pod on the way down. Snapping rather than
	-- easing keeps the view from sliding through the pod's hull as you board or land.
	if ply:InVehicle() then return false, true end

	if S.ThirdPersonCustomizing(ply) then return false, true end
	if cvar_ads:GetBool() and S.ThirdPersonAiming(ply) then return false, true end

	return true
end
-- }}}

-- // Camera {{{
local curDist = 0        -- eased, so toggling doesn't snap
local curRight = 0       -- eased separately, so swapping shoulders slides across
local traceHull = { mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8) }

hook.Add("CalcView", "sweeper_thirdperson", function(ply, origin, angles, fov, znear, zfar)
	local active, snap = S.ThirdPersonActive(ply)

	-- Ease all the way home before handing the view back, so switching off doesn't cut. Aiming and
	-- the customize menu use a faster rate: a lazy glide there feels like input lag.
	local want = active and math.Clamp(cvar_dist:GetFloat(), 30, 200) or 0
	curDist = curDist + (want - curDist) * math.Clamp(FrameTime() * (snap and 30 or 10), 0, 1)
	if curDist < 0.5 then
		curDist = 0
		if not active then return end
	end

	-- Let the gamemode build its view first: class sway, weapon CalcView, the lot.
	local view
	if GAMEMODE and GAMEMODE.CalcView then
		view = GAMEMODE:CalcView(ply, origin, angles, fov, znear, zfar)
	end
	if not istable(view) then
		view = { origin = origin, angles = angles, fov = fov, znear = znear, zfar = zfar }
	end

	local ang = view.angles or angles
	local eye = view.origin or origin
	local frac = curDist / math.max(1, want > 0 and want or curDist)

	-- Ease the shoulder too: swapping sides should sweep the camera across, not teleport it.
	local side = cvar_side:GetFloat() < 0 and -1 or 1
	local wantRight = math.abs(cvar_right:GetFloat()) * side * frac
	curRight = curRight + (wantRight - curRight) * math.Clamp(FrameTime() * 8, 0, 1)

	local target = eye
		- ang:Forward() * curDist
		+ ang:Right() * curRight
		+ ang:Up() * (cvar_up:GetFloat() * frac)

	-- Keep the camera out of walls. Brushes only: tracing against props and NPCs would make it
	-- lurch every time something walked behind you.
	traceHull.start = eye
	traceHull.endpos = target
	traceHull.filter = ply
	traceHull.mask = MASK_SOLID_BRUSHONLY

	local tr = util.TraceHull(traceHull)
	view.origin = tr.Hit and tr.HitPos or target
	view.drawviewer = true

	return view
end)

-- No viewmodel while the camera is behind us - the world model is what's visible.
hook.Add("PreDrawViewModel", "sweeper_thirdperson", function(vm, ply, wep)
	if curDist > 1 then return true end
end)
-- }}}

-- // Keys {{{
-- Polled rather than hooked: PlayerButtonDown isn't called clientside in singleplayer or on the
-- listen-server host, so it can't be relied on. Same approach the ability keys use.
local keyBindings = {
	{ cvar = cvar_key,     cmd = "jcms_thirdperson_toggle" },
	{ cvar = cvar_swapkey, cmd = "jcms_thirdperson_swap" },
}

local wasDown = {}
hook.Add("Think", "sweeper_thirdpersonKeys", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local blocked = ply:IsTyping() or gui.IsGameUIVisible()
		or IsValid(vgui.GetKeyboardFocus()) or vgui.CursorVisible()

	for i, bind in ipairs(keyBindings) do
		local key = input.GetKeyCode(bind.cvar:GetString())
		local down = false

		if key and key > 0 then
			if key >= MOUSE_FIRST and key <= MOUSE_LAST then
				down = input.IsMouseDown(key)
			else
				down = input.IsKeyDown(key)
			end
		end

		if down and not wasDown[i] and not blocked then
			RunConsoleCommand(bind.cmd)
		end
		wasDown[i] = down
	end
end)
-- }}}

-- // Toggle {{{
concommand.Add("jcms_thirdperson_swap", function()
	RunConsoleCommand("jcms_thirdperson_side", cvar_side:GetFloat() < 0 and "1" or "-1")

	-- Dead centre has no visible side to flip to, so give it one rather than looking broken.
	if math.abs(cvar_right:GetFloat()) < 1 then
		RunConsoleCommand("jcms_thirdperson_right", "22")
	end

	surface.PlaySound("common/talk.wav")
end, nil, "Swap the third-person camera to your other shoulder.")

concommand.Add("jcms_thirdperson_toggle", function()
	if not S.ThirdPersonAllowed() then
		chat.AddText(Color(255, 120, 120), "[Implants] Third person is disabled on this server.")
		return
	end

	local on = not cvar_on:GetBool()
	RunConsoleCommand("jcms_thirdperson", on and "1" or "0")
	surface.PlaySound("buttons/lightswitch2.wav")
end, nil, "Toggle over-the-shoulder third person.")
-- }}}
