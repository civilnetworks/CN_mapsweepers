--[[
	Map Sweepers - Implants & Class Levels (addon)
	Client: bulk-buy modifiers for the lobby weapon shop. TURNED OFF - see below.

	The idea was Shift+click = buy a batch of 5, Ctrl+Shift+click = buy as many as you can afford,
	on top of the stock click = 1 / Shift+click = max. It never worked reliably and is now disabled:
	S.shopBulkEnabled = false means nothing here installs, the shop behaves exactly as the gamemode
	wrote it, and the shop tip is left alone.

	Kept rather than deleted because the findings are worth not rediscovering:
	  - The shop's gun buttons are built inside a local closure, so they can only be reached by
	    wrapping jcms.paint_Gun (the paint function every gun button uses) and swapping DoClick the
	    first time each button draws.
	  - p:GetParent():GetClassName() does NOT identify a Lua-registered panel like DIconLayout -
	    GetClassName returns the ENGINE class, so that test never matched and no button was patched.
	  - input.IsKeyDown stops reporting keys while a Derma panel holds keyboard focus, which the lobby
	    does. input.IsShiftDown / input.IsControlDown are the VGUI-side checks that keep working -
	    though even with those, the modifier clicks still didn't take, so something further up
	    (probably the button's own DoClick being replaced again after we patch it) is still in play.
	  - The count argument does reach the server intact: spawnmenu_PurchaseLoadoutGun buys
	    min(affordable, count) extra clips for a gun you own, count-1 alongside one you don't.

	Set S.shopBulkEnabled = true to put it back for another look. `sweeper_shopdebug` still reports
	what attached and which modifier checks see what.
--]]

if SERVER then return end

local S = sweeper

-- Off. This whole file is a no-op until it's true; the shop is left exactly as the gamemode built it.
S.shopBulkEnabled = false

-- How many the Shift batch buys, if it's ever switched back on. Ctrl+Shift buys the maximum.
S.shopBulkCount = S.shopBulkCount or 5

local BUY_ALL = 9999999

-- input.IsKeyDown reads the engine's key state, which stops updating while a Derma panel holds
-- keyboard focus - and the lobby is exactly that. input.IsShiftDown / IsControlDown are the
-- VGUI-side checks Derma itself uses for modifier clicks, so they keep working in a menu. Both are
-- consulted (feature-detected, in case a build lacks them) so this works either way.
local function shiftHeld()
	if input.IsShiftDown and input.IsShiftDown() then return true end
	return input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
end

-- Ctrl is the reliable second modifier for the same reason. Alt is still accepted for anyone used to
-- it, but it has no VGUI-side check, so it only works when the engine is still reporting keys.
local function maxHeld()
	if input.IsControlDown and input.IsControlDown() then return true end
	return input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
		or input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
end

-- Which of the gun buttons is a SHOP BUY button.
--
-- This used to test `p:GetParent():GetClassName() == "DIconLayout"`, and that is why bulk buy did
-- nothing: GetClassName returns the ENGINE class of a panel, so a Lua-registered panel like
-- DIconLayout doesn't report its own name and the test was never true. No button was ever patched,
-- so every click fell through to stock behaviour (Shift = buy max).
--
-- All four button sets share `gunClass` and `jcms.paint_Gun`, so they're told apart by what else
-- they carry (lobby shop = cl_offgame.lua, sell row = cl_paint.lua, presets = cl_offgame.lua):
--   shop buy   gunClass + DoRightClick (right click favourites it) + gunSale + cost >= 0
--   sell row   gunClass + gunSale, NO DoRightClick
--   presets    gunClass, cost = -1, NO DoRightClick
-- The favourite right-click only exists in the shop, so that alone is the discriminator; the cost
-- check keeps the preset grid out even if a later version gives it a right-click too.
-- The shop's own DListLayout is tagged when the Mission tab is built (below), so a button can be
-- identified by walking up to it rather than by guessing from the fields it carries. That is exact:
-- the sell row and the preset grid live in different panels and can never match.
local function inTaggedShop(p)
	local at, guard = p, 0
	while IsValid(at) and guard < 8 do
		if at.sweeperIsShop then return true end
		at = at:GetParent()
		guard = guard + 1
	end
	return false
end

local function isShopBuyButton(p)
	if not (IsValid(p) and p.gunClass and isfunction(p.DoClick)) then return false end
	if inTaggedShop(p) then return true end

	-- Fallback for anything built before the tag was in place: the favourite right-click only exists
	-- on shop buttons, and cost < 0 marks the preset grid.
	if not isfunction(p.DoRightClick) then return false end
	return (tonumber(p.cost) or -1) >= 0
end

-- Tag the shop list. jcms.offgame_BuildMissionPrepTab builds it, so wrap that and mark it after.
function S.InstallShopTag()
	if not (jcms and jcms.offgame_BuildMissionPrepTab) or S.Wrapped(jcms, "ShopTag") then return end
	local orig = jcms.offgame_BuildMissionPrepTab

	S._wrappedShopTagTab = function(tab, ...)
		local rtn = { orig(tab, ...) }
		local shop = tab and tab.loadoutPnl and tab.loadoutPnl.shop
		if IsValid(shop) then shop.sweeperIsShop = true end
		return unpack(rtn)
	end

	jcms.offgame_BuildMissionPrepTab = S._wrappedShopTagTab
	S.MarkWrapped(jcms, "ShopTag")
end

-- Counters for sweeper_shopdebug, so "bulk buy isn't working" is one command to diagnose
S.shopSeen, S.shopPatched, S.shopLastBuy = 0, 0, "none yet"

local function patchButton(p)
	p.sweeperBulkBuy = true
	S.shopPatched = S.shopPatched + 1

	local origClick = p.DoClick
	p.DoClick = function(self)
		if self.cantAfford or not shiftHeld() then
			return origClick(self)
		end

		local count = maxHeld() and BUY_ALL or S.shopBulkCount
		S.shopLastBuy = string.format("%s x%s", tostring(self.gunClass), count == BUY_ALL and "MAX" or count)
		RunConsoleCommand("jcms_buyweapon", self.gunClass, count)
		surface.PlaySound("physics/metal/weapon_footstep" .. math.random(1, 2) .. ".wav")
	end
end

function S.InstallShopHotkeys()
	if not S.shopBulkEnabled then return end
	if not (jcms and jcms.paint_Gun) or S.Wrapped(jcms, "PaintGunBulkBuy") then return end

	local orig = jcms.paint_Gun
	jcms.paint_Gun = function(p, w, h, ...)
		if istable(p) and not p.sweeperBulkBuy then
			S.shopSeen = S.shopSeen + 1
			if isShopBuyButton(p) then patchButton(p) end
		end
		return orig(p, w, h, ...)
	end

	S.MarkWrapped(jcms, "PaintGunBulkBuy")
	S.InstallShopTag()
	S.InstallShopHotkeyText()
end

function S.InstallShopHotkeyText()
	-- Overwrites the gamemode's own shop blurb so players can see the modifiers.
	language.Add("jcms.shop_tip", string.format(
		"Click to buy, click again for extra ammo. Shift+Click buys x%d, Ctrl+Shift+Click buys as many as you can afford. Right click to favourite.",
		S.shopBulkCount))
end

if S.shopBulkEnabled then S.InstallShopHotkeyText() end

hook.Add("Initialize", "sweeper_shophotkeys", function() S.InstallShopHotkeys() end)
hook.Add("InitPostEntity", "sweeper_shophotkeys", function() S.InstallShopHotkeys() end)

concommand.Add("sweeper_shopdebug", function()
	local wrapped = S.Wrapped and S.Wrapped(jcms, "PaintGunBulkBuy") or false
	print("--- Implants: shop bulk buy ---")
	print(("paint_Gun wrapped: %s   (jcms.paint_Gun exists: %s)"):format(tostring(wrapped), tostring(jcms and jcms.paint_Gun ~= nil)))
	print(("gun buttons seen: %d   patched: %d"):format(S.shopSeen or 0, S.shopPatched or 0))
	print(("batch size: x%d      last bulk buy: %s"):format(S.shopBulkCount, tostring(S.shopLastBuy)))
	print(("shift held now: %s    ctrl/alt held now: %s"):format(tostring(shiftHeld()), tostring(maxHeld())))
	print(("  IsShiftDown: %s  IsKeyDown(LSHIFT): %s   <- if the first is true and the second false,")
		:format(tostring(input.IsShiftDown and input.IsShiftDown()), tostring(input.IsKeyDown(KEY_LSHIFT))))
	print("  that is the menu-focus problem this file works around.")
	print("Open the lobby shop first - buttons are only seen once they've drawn. 0 patched with a")
	print("non-zero seen count means the shop-button test needs another look.")
end, nil, "Show whether the shop bulk-buy patch attached to the weapon shop buttons.")
