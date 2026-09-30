--[[
	Map Sweepers - Implants & Class Levels (addon)
	SWEEPER UPGRADE STATION: more upgrade types

	The gamemode's Upgrade Station (the "augment station" terminal) always offered the same 3 upgrades:
	Incendiary Rounds, Shield Boost, Explosive Rounds. This replaces its terminal mode (from this addon, the
	gamemode files are not edited) so each station offers 3 upgrades picked at random from a bigger pool.

	- Same price rules as before: 1000 J, +500 J for every upgrade already bought from that station.
	- Upgrades are for the buyer only and last until they die / respawn (like the originals).
	- Stacking the same upgrade from different stations works for most of them.

	Add your own upgrade: S.stationUpgrades[id] = { name = "...", short = "...", weight = 1, apply = function(ply, stacks) end }
	(ids can't contain spaces). Tuning: S.stationConfig.
--]]

local S = sweeper

S.stationConfig = {
	offers = 3,          -- upgrades per station (the screen is laid out for 3)
	baseCost = 1000,
	costPerBought = 500,
}

-- // The upgrade pool {{{
-- name: shown on the station. apply(ply, stacks) runs on the server when bought; stacks = how many of this the
-- player now has (1 on first buy).
S.stationUpgrades = {
	-- The 3 originals
	incendiary = { name = "INCENDIARY ROUNDS", short = "Hits set enemies on fire", weight = 1 },
	shield     = { name = "SHIELD BOOST", short = "+50% max shield", weight = 1 },
	explosive  = { name = "EXPLOSIVE ROUNDS", short = "Shots explode on impact", weight = 1 },

	-- New
	reinforced = { name = "REINFORCED FRAME", short = "+25 max health", weight = 1 },
	hollow     = { name = "HOLLOW POINTS", short = "+15% damage", weight = 1 },
	plating    = { name = "KINETIC PLATING", short = "-15% damage taken", weight = 1 },
	vampiric   = { name = "VAMPIRIC ROUNDS", short = "Heal 5% of damage dealt", weight = 0.8 },
	servo      = { name = "SERVO LEGS", short = "+12% move speed", weight = 1 },
	jumpjets   = { name = "JUMP JETS", short = "Jump much higher", weight = 0.7 },
	regen      = { name = "NANO REGEN", short = "Regenerate 1 HP per second", weight = 0.8 },
	salvager   = { name = "SALVAGER", short = "+15 J per kill", weight = 0.9 },
	recycler   = { name = "AMMO RECYCLER", short = "Kills refill a quarter clip", weight = 0.9 },
	fieldmedic = { name = "COMBAT STIMS", short = "Kills heal 4 HP", weight = 0.9 },
	shock      = { name = "SHOCK ROUNDS", short = "Hits can arc to a nearby enemy", weight = 0.8 },
	frost      = { name = "CRYO ROUNDS", short = "Hits slow enemies", weight = 0.8 },
}
-- }}}

-- ============================================================================================
if SERVER then
	local U = S.stationUpgrades

	local function stacks(ply, id) return (ply.jcms_stationUps and ply.jcms_stationUps[id]) or 0 end
	S.StationStacks = stacks

	local function isEnemy(ent)
		return IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0 and jcms.team_NPC and jcms.team_NPC(ent)
	end

	-- // Original three (same code as the gamemode's station) {{{
	U.incendiary.apply = function(ply)
		ply.jcms_incendiaryUpgrade = (ply.jcms_incendiaryUpgrade and ply.jcms_incendiaryUpgrade + 1) or 1
		ply.jcms_damageEffect = function(ply, target, dmgInfo)
			if not jcms.team_JCorp(target) and not (target:GetClass() == "jcms_fire" or target:GetClass() == "gmod_hands" or target:GetClass() == "predicted_viewmodel") and not target:IsWeapon() then
				target:Ignite(ply.jcms_incendiaryUpgrade * 2)
			end
		end
	end

	U.shield.apply = function(ply)
		ply:SetMaxArmor(math.floor(ply:GetMaxArmor() * 1.5))
	end

	U.explosive.apply = function(ply)
		ply.jcms_explosiveUpgrade = (ply.jcms_explosiveUpgrade and ply.jcms_explosiveUpgrade + 1) or 1
		local expl = ply.jcms_explosiveUpgrade
		ply.jcms_EntityFireBullets = function(ent, bulletData)
			bulletData.TracerName = nil
			bulletData.Tracer = math.huge
			local ogCallback = bulletData.Callback
			bulletData.Callback = function(attacker, tr, dmgInfo)
				if type(ogCallback) == "function" then ogCallback(attacker, tr, dmgInfo) end
				local dmg = dmgInfo:GetDamage()
				local blastRadius, blastDmg = math.max(dmg ^ (2 / 3) * 5 * expl, 66), math.max(expl * dmg / 4, 2)
				local effectdata = EffectData()
				local angles = attacker:EyeAngles()
				local origin = attacker:EyePos() + angles:Right() * 1 + angles:Up() * -2 + angles:Forward() * 16
				effectdata:SetStart(origin)
				effectdata:SetScale(math.random(6500, 9000))
				effectdata:SetMagnitude(blastRadius)
				effectdata:SetAngles(tr.Normal:Angle())
				effectdata:SetOrigin(tr.HitPos)
				effectdata:SetFlags(5)
				util.Effect("jcms_bolt", effectdata, true, true)
				util.BlastDamage(ent, ent, tr.HitPos, blastRadius, blastDmg)
			end
		end
	end
	-- }}}

	-- // New ones {{{
	U.reinforced.apply = function(ply)
		ply:SetMaxHealth(ply:GetMaxHealth() + 25)
		ply:SetHealth(math.min(ply:Health() + 25, ply:GetMaxHealth()))
	end

	U.hollow.apply = function(ply)
		ply.jcms_dmgMult = (ply.jcms_dmgMult or 1) * 1.15
	end

	U.servo.apply = function(ply)
		ply:SetWalkSpeed(ply:GetWalkSpeed() * 1.12)
		ply:SetRunSpeed(ply:GetRunSpeed() * 1.12)
	end

	U.jumpjets.apply = function(ply)
		ply:SetJumpPower(ply:GetJumpPower() + 90)
	end

	-- plating / vampiric / shock / frost / regen / salvager / recycler / fieldmedic work through the hooks below
	for id, up in pairs(U) do
		if not up.apply then up.apply = function() end end
	end

	hook.Add("EntityTakeDamage", "sweeper_station", function(ent, dmg)
		-- Kinetic Plating
		if ent:IsPlayer() then
			local n = stacks(ent, "plating")
			if n > 0 then dmg:ScaleDamage(0.85 ^ n) end
			return
		end

		local attacker = dmg:GetAttacker()
		if not (IsValid(attacker) and attacker:IsPlayer() and attacker.jcms_stationUps) or not isEnemy(ent) then return end
		if dmg:GetInflictor() ~= attacker and not (IsValid(dmg:GetInflictor()) and dmg:GetInflictor():IsWeapon()) then return end

		-- Cryo Rounds: slow the target for a moment
		if stacks(attacker, "frost") > 0 and ent:IsNPC() then
			ent.jcms_stationSlowUntil = CurTime() + 1.5 * stacks(attacker, "frost")
			ent:SetPlaybackRate(0.6)
		end

		-- Shock Rounds: 15% (per stack) chance to arc to another enemy nearby
		local shock = stacks(attacker, "shock")
		if shock > 0 and not attacker.jcms_stationArcing and math.random() < 0.15 * shock then
			for i, other in ipairs(ents.FindInSphere(ent:WorldSpaceCenter(), 250)) do
				if other ~= ent and isEnemy(other) then
					attacker.jcms_stationArcing = true
					local arc = DamageInfo()
					arc:SetAttacker(attacker)
					arc:SetInflictor(attacker)
					arc:SetDamage(20)
					arc:SetDamageType(DMG_SHOCK)
					arc:SetDamagePosition(other:WorldSpaceCenter())
					other:TakeDamageInfo(arc)
					attacker.jcms_stationArcing = nil
					local ed = EffectData()
					ed:SetEntity(other)
					ed:SetMagnitude(3)
					ed:SetScale(1)
					util.Effect("TeslaHitBoxes", ed, true, true)
					other:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 70, 120, 0.6)
					break
				end
			end
		end
	end)

	-- Vampiric Rounds: heal from damage actually dealt
	hook.Add("PostEntityTakeDamage", "sweeper_station", function(ent, dmg, took)
		if not took or not (IsValid(ent) and not ent.sweeperDecoy and (ent:IsNPC() or ent:IsNextBot()) and jcms.team_NPC and jcms.team_NPC(ent)) then return end
		local attacker = dmg:GetAttacker()
		if not (IsValid(attacker) and attacker:IsPlayer() and attacker:Alive()) then return end
		local n = stacks(attacker, "vampiric")
		if n > 0 then
			local heal = dmg:GetDamage() * 0.05 * n
			attacker.jcms_stationVampCarry = (attacker.jcms_stationVampCarry or 0) + heal
			local whole = math.floor(attacker.jcms_stationVampCarry)
			if whole > 0 then
				attacker.jcms_stationVampCarry = attacker.jcms_stationVampCarry - whole
				S.GrantKillHealth(attacker, whole)
			end
		end
	end)

	-- Kills: Salvager, Ammo Recycler, Combat Stims
	hook.Add("MapSweepersDeathNPC", "sweeper_station", function(npc, attacker, inflictor, isPlayer)
		if isPlayer or not (IsValid(attacker) and attacker:IsPlayer() and attacker:Alive() and attacker.jcms_stationUps) then return end
		local n = stacks(attacker, "salvager")
		if n > 0 then attacker:SetNWInt("jcms_cash", attacker:GetNWInt("jcms_cash", 0) + 15 * n) end

		n = stacks(attacker, "fieldmedic")
		if n > 0 then S.GrantKillHealth(attacker, 4 * n) end

		n = stacks(attacker, "recycler")
		if n > 0 then
			local wep = attacker:GetActiveWeapon()
			if IsValid(wep) and wep:GetPrimaryAmmoType() >= 0 then
				local clip = wep:GetMaxClip1()
				if clip and clip > 0 then
					attacker:GiveAmmo(math.max(1, math.floor(clip * 0.25 * n)), wep:GetPrimaryAmmoType(), true)
				end
			end
		end
	end)

	-- Nano Regen + keep Cryo-slowed enemies slow
	timer.Create("sweeper_station", 1, 0, function()
		for i, ply in ipairs(player.GetAll()) do
			local n = stacks(ply, "regen")
			if n > 0 and ply:Alive() and ply:Health() < ply:GetMaxHealth() then
				ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + n))
			end
		end
	end)
	timer.Create("sweeper_stationSlow", 0.25, 0, function()
		if not (jcms and jcms.director and jcms.director.npcs) then return end
		local ct = CurTime()
		for i, npc in ipairs(jcms.director.npcs) do
			if IsValid(npc) and npc.jcms_stationSlowUntil then
				if npc.jcms_stationSlowUntil > ct then
					npc:SetPlaybackRate(0.6)
				else
					npc.jcms_stationSlowUntil = nil
					npc:SetPlaybackRate(1)
				end
			end
		end
	end)

	-- Upgrades last one life (the gamemode resets the original three the same way)
	hook.Add("MapSweepersClassApplied", "sweeper_station", function(ply)
		ply.jcms_stationUps = nil
		ply.jcms_stationVampCarry = nil
	end)
	-- }}}

	-- // The terminal mode {{{
	local function pickOffers()
		local pool = {}
		for id, up in pairs(U) do pool[id] = up.weight or 1 end
		local out = {}
		for n = 1, S.stationConfig.offers do
			local id = jcms.util_ChooseByWeight(pool)
			if not id then break end
			out[#out + 1] = id
			pool[id] = nil
		end
		return out
	end

	local function stationCost(tokens)
		local cost = S.stationConfig.baseCost
		for i, t in ipairs(tokens) do
			if t == "x" then cost = cost + S.stationConfig.costPerBought end
		end
		return cost
	end

	function S.InstallUpgradeStation()
		local terms = jcms and jcms.terminal_modeTypes
		if not terms or not terms.upgrade_station or terms.upgrade_station == S._stationMode then return end
		S._origStationMode = terms.upgrade_station

		S._stationMode = {
			generate = function(ent)
				return table.concat(pickOffers(), " ")
			end,

			command = function(ent, cmd, data, ply)
				local tokens = string.Split(data or "", " ")
				local id = tokens[cmd]
				local up = id and U[id]
				if not up then return false end

				local cost = stationCost(tokens)
				if ply:GetNWInt("jcms_cash", 0) < cost then return false end

				ply.jcms_stationUps = ply.jcms_stationUps or {}
				ply.jcms_stationUps[id] = (ply.jcms_stationUps[id] or 0) + 1
				local ok, err = pcall(up.apply, ply, ply.jcms_stationUps[id])
				if not ok then ErrorNoHalt("[sweeper] upgrade station '" .. id .. "': " .. tostring(err) .. "\n") end

				tokens[cmd] = "x"
				ent:EmitSound("items/medshot4.wav", 100, 80, 1)
				ply:SetNWInt("jcms_cash", ply:GetNWInt("jcms_cash", 0) - cost)
				ply:ChatPrint(string.format("[Upgrade Station] %s installed (%s).", up.name, up.short))
				return true, table.concat(tokens, " ")
			end,
		}
		-- keep any other fields the gamemode may add later (e.g. weight)
		for k, v in pairs(S._origStationMode) do
			if S._stationMode[k] == nil then S._stationMode[k] = v end
		end
		terms.upgrade_station = S._stationMode
	end
	hook.Add("Initialize", "sweeper_station", S.InstallUpgradeStation)
	hook.Add("InitPostEntity", "sweeper_station", S.InstallUpgradeStation)
	S.InstallUpgradeStation()
	-- }}}
end

-- ============================================================================================
if CLIENT then
	-- Same look as the gamemode's station screen, but with our upgrade names
	local function drawStation(ent, mx, my, w, h, modedata)
		local color_bg, color_fg, color_accent = jcms.terminal_GetColors(ent)
		local tokens = string.Split(modedata or "", " ")
		local n = math.max(#tokens, 1)
		local rowH, rowGap = 64, 72
		if n > 3 then rowGap = math.floor(216 / n) rowH = rowGap - 8 end

		local hoveredBtn = -1
		local cost = S.stationConfig.baseCost
		for i = 1, n do
			local y = 72 + (i - 1) * rowGap
			if hoveredBtn == -1 and tokens[i] ~= "x" and mx > 16 and mx < w - 32 and my > y and my < y + rowH then
				hoveredBtn = i
			end
			if tokens[i] == "x" then cost = cost + S.stationConfig.costPerBought end
			surface.SetDrawColor(color_bg)
			jcms.hud_DrawNoiseRect(16, y, w - 32, rowH, 128)
		end
		local costY = 72 + n * rowGap
		local costText = language.GetPhrase("jcms.terminal_cost"):format(cost)

		draw.SimpleText("#jcms.terminal_augmentstation", "jcms_hud_medium", w / 2, 0, color_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		draw.SimpleText(costText, "jcms_hud_big", w / 2, costY, color_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		cam.PushModelMatrix(jcms.terminal_getGlitchMatrix(), true)
			render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
			draw.SimpleText("#jcms.terminal_augmentstation", "jcms_hud_medium", w / 2, 0, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

			for i = 1, n do
				local y = 72 + (i - 1) * rowGap
				local id = tokens[i]
				if id == "x" then
					draw.SimpleText("#jcms.terminal_soldout", "jcms_hud_small", w / 2, y + rowH / 2, color_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				else
					local up = S.stationUpgrades[id]
					local text = up and (up.name .. ": " .. string.upper(up.short)) or string.upper(tostring(id))
					local col = hoveredBtn == i and color_accent or color_fg
					surface.SetDrawColor(col)
					surface.DrawOutlinedRect(16, y, w - 32, rowH, 4)
					surface.SetFont("jcms_hud_small")
					local font = (surface.GetTextSize(text) > w - 64) and "jcms_medium" or "jcms_hud_small"
					if font == "jcms_medium" then
						-- too long for one big line: name on top, effect below
						draw.SimpleText(up and up.name or text, "jcms_hud_small", w / 2, y + rowH * 0.36, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						if up then draw.SimpleText(string.upper(up.short), "jcms_medium", w / 2, y + rowH * 0.78, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
					else
						draw.SimpleText(text, font, w / 2, y + rowH / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
				end
			end

			draw.SimpleText(costText, "jcms_hud_big", w / 2, costY, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			render.OverrideBlend(false)
		cam.PopModelMatrix()

		return hoveredBtn
	end

	function S.InstallUpgradeStationClient()
		local terms = jcms and jcms.terminal_modeTypes
		if not terms or terms.upgrade_station == drawStation then return end
		S._origStationDraw = S._origStationDraw or terms.upgrade_station
		terms.upgrade_station = drawStation
	end
	hook.Add("Initialize", "sweeper_station", S.InstallUpgradeStationClient)
	hook.Add("InitPostEntity", "sweeper_station", S.InstallUpgradeStationClient)
	S.InstallUpgradeStationClient()
end
