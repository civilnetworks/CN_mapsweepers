--[[
	Map Sweepers - Implants & Class Levels (addon)
	Client: one shop category per weapon PACK (the Workshop addon), e.g. "ARC9 - Polyarm".

	The shop groups guns by jcms.gunstats_Get(class).category, which the gamemode builds as the
	SWEP's Category with its SubCategory appended:

		SWEP.Category = "ARC9 - Polyarm"   SWEP.SubCategory = "Rifles"   ->  "ARC9 - Polyarm - Rifles"

	so one pack spreads across as many shop rows as it has sub-categories. The pack's real name is
	the Category on its own, which is read back here from weapons.Get(class) rather than guessed out
	of the joined string - splitting on " - " would cut "ARC9 - Polyarm" down to "ARC9".

	Order of preference for a weapon's category:
	  1. a rule in S.shopPacks below (match on class name, the gamemode's pack id, or the category),
	  2. with jcms_shop_packbase 1: the weapons base the gamemode identified (ARC9, TFA, M9K,
	     CW2.0, FA:S, ARC9, Tactical RP, MW Base, Draconic, Darken217) - every ARC9 pack in ONE row,
	  3. the SWEP's own Category, without the SubCategory - one row per pack, the default,
	  4. whatever it shipped with.

	Convars (client, per player):
		jcms_shop_packcats 1   group by pack (default)
		jcms_shop_packbase 0   1 collapses every pack sharing a base into a single category

	`sweeper_shopcats` prints the categories with their weapons, each showing the pack Category
	and base it was sorted by - that's how to find the name for a rule below.

	Nothing in the mapsweepers folder is edited: jcms.gunstats_Get is wrapped, clientside only, and
	the category the weapon shipped with is kept on the stats table so the convars can be flipped
	live. It tidies the in-field shop terminal too, which has no "Categories by" dropdown.
--]]

if SERVER then return end

local S = sweeper

-- Rules, checked first. `classes` and `categories` are Lua patterns (matched lowercase), `bases`
-- are the gamemode's pack ids from stats.base. Use one when a pack spreads over several top-level
-- Categories of its own ("M9K Assault Rifles", "M9K Pistols", ...) rather than one plus sub-ones.
S.shopPacks = S.shopPacks or {
	{ name = "M9K", categories = { "^m9k" } },
}

local cvar_packs = CreateClientConVar("jcms_shop_packcats", "1", true, false,
	"Group each weapon pack into one shop category instead of one per sub-category.")
local cvar_base = CreateClientConVar("jcms_shop_packbase", "0", true, false,
	"Go further and put every pack that shares a weapons base (all ARC9 packs, say) in one category.")

-- The SWEP's own Category, before the gamemode appended its SubCategory
local function rawCategory(class)
	local data = weapons.Get(class) or (jcms.default_weapons_datas and jcms.default_weapons_datas[class])
	local cat = data and data.Category
	if isstring(cat) and cat ~= "" and cat ~= "Other" then return cat end
end

-- Last resort for a weapon whose SWEP table can't be read back: drop the trailing " - Something"
local function stripSub(cat)
	cat = tostring(cat)
	local head = string.match(cat, "^(.*)%s%-%s[^%-]*$")
	return head or cat
end

local function packCategory(class, stats)
	local original = stats.sweeperCat0 or stats.category or "_"
	if not cvar_packs:GetBool() then return original end

	local lowerClass, lowerCat = string.lower(tostring(class)), string.lower(tostring(original))
	for i, rule in ipairs(S.shopPacks) do
		for j, pattern in ipairs(rule.classes or {}) do
			if string.find(lowerClass, pattern) then return rule.name end
		end
		for j, pattern in ipairs(rule.categories or {}) do
			if string.find(lowerCat, pattern) then return rule.name end
		end
		for j, base in ipairs(rule.bases or {}) do
			if stats.base == base then return rule.name end
		end
	end

	-- Opt-in: one row per weapons base instead of per pack ("ARC9", not "ARC9 - Polyarm")
	if cvar_base:GetBool() and stats.base and stats.base ~= "" and stats.base ~= "Default" then
		return stats.base
	end

	return rawCategory(class) or stripSub(original)
end
S.ShopPackCategory = packCategory

function S.InstallShopPackCategories()
	if not (jcms and jcms.gunstats_Get) or S.Wrapped(jcms, "GunstatsPacks") then return end

	local orig = jcms.gunstats_Get
	S._wrappedGunstats = function(class, ...)
		local stats = orig(class, ...)
		if istable(stats) then
			-- Remember what it shipped with, once, so flipping a convar can put it back
			if stats.sweeperCat0 == nil then stats.sweeperCat0 = stats.category or "_" end
			local ok, cat = pcall(packCategory, class, stats)
			if ok and cat then stats.category = cat end
		end
		return stats
	end

	jcms.gunstats_Get = S._wrappedGunstats
	S.MarkWrapped(jcms, "GunstatsPacks")
end

hook.Add("Initialize", "sweeper_shopPackCats", S.InstallShopPackCategories)
hook.Add("InitPostEntity", "sweeper_shopPackCats", S.InstallShopPackCategories)
S.InstallShopPackCategories()

-- What each weapon ended up under, and what it was sorted by, for writing S.shopPacks rules
concommand.Add("sweeper_shopcats", function()
	if not (jcms and jcms.weapon_prices) then return end

	local byCat = {}
	for class in pairs(jcms.weapon_prices) do
		local stats = jcms.gunstats_Get(class)
		if istable(stats) then
			local cat = stats.category or "_"
			byCat[cat] = byCat[cat] or {}
			table.insert(byCat[cat], string.format("%s   [pack: %s | base: %s | shipped: %s]",
				class, tostring(rawCategory(class)), tostring(stats.base), tostring(stats.sweeperCat0)))
		end
	end

	local cats = {}
	for cat in pairs(byCat) do cats[#cats + 1] = cat end
	table.sort(cats)

	print(("--- Shop categories: %d (grouping %s, by base %s) ---"):format(#cats,
		cvar_packs:GetBool() and "ON" or "OFF", cvar_base:GetBool() and "ON" or "OFF"))
	for i, cat in ipairs(cats) do
		table.sort(byCat[cat])
		print(("  %s  (%d)"):format(cat, #byCat[cat]))
		for j, line in ipairs(byCat[cat]) do print("      " .. line) end
	end
end, nil, "List the shop categories and which weapons are in each.")
