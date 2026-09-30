hook.Add("MapSweepersReady", "np_msexp_upgradeinit", function()
	include("np_mapsweepermissionpack/sh_upgrades.lua")
	AddCSLuaFile("np_mapsweepermissionpack/sh_upgrades.lua")
	AddCSLuaFile("np_mapsweepermissionpack/cl_terminalnet.lua")
	AddCSLuaFile("np_mapsweepermissionpack/cl_terminalui.lua")
	
	if SERVER then
		include("np_mapsweepermissionpack/sv_terminalnet.lua")
		include("np_mapsweepermissionpack/sv_upgradehooks.lua")
		include("np_mapsweepermissionpack/sv_terminalui.lua")
	end
	
	if CLIENT then
		include("np_mapsweepermissionpack/cl_terminalnet.lua")
		include("np_mapsweepermissionpack/cl_terminalui.lua")
	end
	
end)