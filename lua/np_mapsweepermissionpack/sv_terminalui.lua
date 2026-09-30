jcms.terminal_modeTypes["rgg_flatscreen"] = 
{
	command = function(ent, cmd, data, ply)
		if cmd == 0 then
			jcms.terminal_ToUnlock(ent)
			return true
		elseif cmd == 1 and not ent:GetNWBool("osinstall") and not ent:GetNWBool("jcms_terminal_locked") then
			local worked, newdata = ent.jcms_terminal_Callback(ent, cmd, data, ply)
			return worked, newdata
		end
	end,
	
	generate = function(ent)
	end
}

jcms.terminal_modeTypes["jcorp_lightgen"] = 
{
	command = function(ent, cmd, data, ply)
		if cmd == 0 then
			jcms.terminal_ToUnlock(ent)
			return true
		elseif cmd == 1 and not ent:GetNWBool("genrepair") and not ent:GetNWBool("jcms_terminal_locked") then
			local worked, newdata = ent.jcms_terminal_Callback(ent, cmd, data, ply)
			ent:SetNWBool("genrepair",true)
			return worked, newdata
		end
	end,
	
	generate = function(ent)
	end
}