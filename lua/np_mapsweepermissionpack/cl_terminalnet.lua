net.Receive("jcms_np_cacheclient",function()
	local ply = LocalPlayer()
	local upgradeID = net.ReadUInt(4)
	jcms.np_tag_upgrade(ply,upgradeID)
	
	if upgradeID == 8 then
		local data = jcms.class_GetLocPlyData()
		jcms.np_update_classcds(ply,data)
	end
end)

net.Receive("jcms_np_resetupg",function()
	local ply = LocalPlayer()
	ply.jcms_np_upgrades = {}
end)

net.Receive("jcms_np_blackoutupdate",function()
	render.RedownloadAllLightmaps(true, true)
end)