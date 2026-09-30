local SpeedBoostedPlayers = {}

local function UpdateShieldCharger(ply, data)
	local timerIdentifier = "jcms_ShieldRegen" .. ply:EntIndex()
		timer.Remove(timerIdentifier) -- Remove old timer. This might suck to maintain lol, but whatever.
		
		local regenTime = 1/data.shieldRegen
		local actualRegenTime = jcms.np_has_upgradetag(ply,7) and regenTime * 0.66 or regenTime
	
		timer.Create(timerIdentifier, actualRegenTime, 0, function()
			if IsValid(ply) and ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE then
			
			
				if (ply:Armor() < ply:GetMaxArmor()) and (not ply.jcms_lastDamaged or CurTime()-ply.jcms_lastDamaged > data.shieldDelay) then
					local newValue = ply:Armor() + 1
					ply:SetArmor(newValue)

					if newValue == ply:GetMaxArmor() then
						local ed = EffectData()
						ed:SetEntity(ply)
						ed:SetFlags(2)
						ed:SetColor(jcms.util_colorIntegerSweeperShield)
						util.Effect("jcms_shieldeffect", ed)
						ply:EmitSound("items/suitchargeok1.wav", 50, 130, 0.5)
					end
				end

			else
				timer.Remove(timerIdentifier)
			end
		end)
end

jcms.np_upgradecallbacks = {
	["HP"] = function(ply) -- jcorp medical care
		timer.Create("jcms_healthregen_" .. ply:SteamID64(), 2, 0, function()
            if not IsValid(ply) then return end
            if not ply:Alive() then return end

            local hp = ply:Health()
            local maxHp = ply:GetMaxHealth()

            if hp < maxHp then
               ply:SetHealth(math.min(hp + 2, maxHp))
            end
        end)
	end,
	
	["SPEED"] = function(ply) -- ralab
		SpeedBoostedPlayers[ply] = true
		ply:SetWalkSpeed(ply:GetWalkSpeed() * 1.25)
		ply:SetRunSpeed(ply:GetRunSpeed() * 1.25)
	end,
	
	["SHIELDRECHARGE"] = function(ply)
		local data = jcms.class_GetData(ply)
		UpdateShieldCharger(ply,data)
	end,
	
}


local KillCounters = {}

-- HEALTH UPGRADE AND SPEED UPGRADE (1) + (4)
hook.Add("PlayerSpawn", "jcms_np_healthupgrade_add", function(ply)
	SpeedBoostedPlayers[ply] = nil
    timer.Simple(1, function()
        if not IsValid(ply) then return end

        if jcms.np_has_upgradetag(ply,1) then
		   timer.Remove("jcms_healthregen_" .. ply:SteamID64())
           jcms.np_upgradecallbacks["HP"](ply)
        end
		
		if jcms.np_has_upgradetag(ply,4) and not SpeedBoostedPlayers[ply] then
			jcms.np_upgradecallbacks["SPEED"](ply)
		end
    end)
end)

hook.Add("PlayerDisconnected", "jcms_np_healthupgrade_remove", function(ply)
    timer.Remove("jcms_healthregen_" .. ply:SteamID64())
	
	if KillCounters[ply] then KillCounters[ply] = nil end
end)

local FearTimers = {}


-- ARMOR UPGRADE + AMMO UPGRADE + FEAR HANDLE (2) + (3) + (6)
hook.Add("EntityTakeDamage", "jcms_np_damageevent", function(target, dmginfo)
	if IsValid(target) and target:IsPlayer() and target:Alive() and jcms.np_has_upgradetag(target,2) and jcms.team_JCorp_player(target) and not dmginfo:IsDamageType(DMG_FALL) then
		dmginfo:ScaleDamage(0.8)
	end
	
	local Attacker = dmginfo:GetAttacker()
	
	if IsValid(Attacker) and Attacker.jcms_fear_inflict and Attacker:Alive() and IsValid(target) and target:Alive() and target:IsPlayer() and jcms.np_has_upgradetag(target,6) and jcms.team_JCorp_player(target) then
		dmginfo:ScaleDamage(0.8)
	end
	
	if IsValid(jcms.director) and IsValid(Attacker) and Attacker:Alive() and IsValid(target) and target:Alive() and target:IsPlayer() and jcms.team_JCorp_player(target) and jcms.director.darknessDMGScale then
		dmginfo:ScaleDamage(jcms.director.darknessDMGScale)
	end

	if Attacker:IsPlayer() and IsValid(Attacker) and jcms.np_has_upgradetag(Attacker,3) and jcms.team_JCorp_player(Attacker) then
		dmginfo:ScaleDamage(1.25)
		
		if not target:IsPlayer() and jcms.np_has_upgradetag(Attacker,6) and not FearTimers[target] and IsValid(target) then
			target.jcms_fear_inflict = true
			
			FearTimers[target] = timer.Simple(5,function()
			
				if IsValid(target) then
					target.jcms_fear_inflict = false
				end
				
				FearTimers[target] = nil
			end)
			
		end
	end
end)

-- BOUNTY (5)
hook.Add("OnNPCKilled", "jcms_np_bountyreward", function(npc, attacker, inflictor)
	if IsValid(attacker) and attacker:IsPlayer() and jcms.team_JCorp_player(attacker) and jcms.np_has_upgradetag(attacker,5) and not jcms.team_JCorp_ent(npc) then
		if not KillCounters[attacker] then KillCounters[attacker] = 0 end
		KillCounters[attacker] = KillCounters[attacker] + 1
		
		if KillCounters[attacker] >= 6 then
			KillCounters[attacker] = 0
			
			local Cash = attacker:GetNWInt("jcms_cash",0)
			attacker:SetNWInt("jcms_cash",Cash+45)
			jcms.net_SendCashEarn(attacker,45)
		end
	end
end)



-- SHIELD RECHARGE (7) + ORDER UPGRADE (8)
hook.Add("MapSweepersClassApplied", "jcms_np_fastrecharge", function(ply, class, data)
	
	if not jcms.director then return end -- likely a map loading issue or something.
	
	if jcms.director.missionType ~= "monopolytakeover" and (ply.jcms_np_upgrades and #ply.jcms_np_upgrades ~= 0) then
		ply.jcms_np_upgrades = {}
		net.Start("jcms_np_resetupg")
		net.Send(ply)
		return
	end

	-- Shield
	timer.Simple(1,function()
	
		UpdateShieldCharger(ply, data)
		
	end)
end)


