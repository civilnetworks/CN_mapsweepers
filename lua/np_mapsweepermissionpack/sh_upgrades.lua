jcms.np_upgradeinfo = {
	[1] = {
		Name = "#jcms.np_upgrade_1",
		DescriptionLines = {
			"#jcms.np_upgrade_1_desc1",
			"#jcms.np_upgrade_1_desc2"
		},
		Cost = 1200,
		Callback="HP",
	},
	[2] = {
		Name = "#jcms.np_upgrade_2",
		DescriptionLines = {
			"#jcms.np_upgrade_2_desc1",
			"#jcms.np_upgrade_2_desc2",
			"#jcms.np_upgrade_2_desc3"
		},
		Cost = 1500,
	},
	[3] = {
		Name = "#jcms.np_upgrade_3",
		DescriptionLines = {
			"#jcms.np_upgrade_3_desc1",
			"#jcms.np_upgrade_3_desc2"
		},
		Cost = 1500,
	},
	[4] = {
		Name = "#jcms.np_upgrade_4",
		DescriptionLines = {
			"#jcms.np_upgrade_4_desc1",
			"#jcms.np_upgrade_4_desc2"
		},
		Cost = 1000,
		Callback="SPEED",
	},
	[5] = {
		Name = "#jcms.np_upgrade_5",
		DescriptionLines = {
			"#jcms.np_upgrade_5_desc1",
		},
		Cost = 1000,
	},
	[6] = {
		Name = "#jcms.np_upgrade_6",
		DescriptionLines = {
			"#jcms.np_upgrade_6_desc1",
			"#jcms.np_upgrade_6_desc2"
		},
		Cost = 750,
	},
	[7] = {
		Name = "#jcms.np_upgrade_7",
		DescriptionLines = {
			"#jcms.np_upgrade_7_desc1",
			"#jcms.np_upgrade_7_desc2",
			"#jcms.np_upgrade_7_desc3"
		},
		Cost = 1200,
		Callback="SHIELDRECHARGE",
	},
	[8] = {
		Name = "#jcms.np_upgrade_8",
		DescriptionLines = {
			"#jcms.np_upgrade_8_desc1",
		},
		Cost = 1000,
	},
}

-- Used to sync and inform client and server about upgrades without relying on GetNW too much.
function jcms.np_tag_upgrade(ply,upgradeID)
	
	if not ply.jcms_np_upgrades then
		ply.jcms_np_upgrades = {}
	end
	
	ply.jcms_np_upgrades[upgradeID] = true
	
end

function jcms.np_has_upgradetag(ply,upgradeID)
	if not ply.jcms_np_upgrades then
		ply.jcms_np_upgrades = {}
	end
	
	return ply.jcms_np_upgrades[upgradeID]
end

function jcms.np_update_classcds(ply,data)
	if not data._originalCooldown then
			data._originalCooldown = data.getCoolDownMult or function() return 1 end

			data.getCoolDownMult = function(orderData)
				local base = data._originalCooldown(orderData)
				local mult = 1

				if IsValid(ply) and jcms.np_has_upgradetag(ply,8) then
					mult = 0.66
				end

				return base * mult
		end
	end
end

hook.Add("MapSweepersClassApplied", "jcms_np_classapplied", function(ply, class, data)
	-- update da bladdy cooldowns u bloddy baztard
	timer.Simple(1,function()
	
		jcms.np_update_classcds(ply,data)
		
	end)
	
	if CLIENT then -- HANDLE BLACKOUT
		
	end
end)


