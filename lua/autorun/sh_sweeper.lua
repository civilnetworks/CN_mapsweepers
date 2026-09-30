--[[
	Map Sweepers - Class Levels & Chipset Skill Trees (addon)
	Loader. Only runs when the active gamemode is Map Sweepers.
--]]
if engine.ActiveGamemode() ~= "mapsweepers" then return end

AddCSLuaFile("sweeper/sh_tree.lua")
AddCSLuaFile("sweeper/sh_specs.lua")
AddCSLuaFile("sweeper/sh_pvp.lua")
AddCSLuaFile("sweeper/sh_orbitalpicks.lua")
AddCSLuaFile("sweeper/sh_stims.lua")
AddCSLuaFile("sweeper/cl_skills.lua")
AddCSLuaFile("sweeper/sh_integration.lua")
AddCSLuaFile("sweeper/sh_classorders.lua")
AddCSLuaFile("sweeper/sh_callins.lua")
AddCSLuaFile("sweeper/sh_orbitals.lua")
AddCSLuaFile("sweeper/sh_vehicles.lua")
AddCSLuaFile("sweeper/sh_offensive.lua")
AddCSLuaFile("sweeper/sh_abilities.lua")
AddCSLuaFile("sweeper/sh_engineer.lua")
AddCSLuaFile("sweeper/sh_recon.lua")
AddCSLuaFile("sweeper/sh_sentinel.lua")
AddCSLuaFile("sweeper/sh_infantry.lua")
AddCSLuaFile("sweeper/sh_group.lua")
AddCSLuaFile("sweeper/sh_modifiers.lua")
AddCSLuaFile("sweeper/sh_subfactions.lua")
AddCSLuaFile("sweeper/sh_mission_relay.lua")
AddCSLuaFile("sweeper/sh_mission_salvage.lua")
AddCSLuaFile("sweeper/sh_thirdperson.lua")
AddCSLuaFile("sweeper/sh_missionfilter.lua")
AddCSLuaFile("sweeper/sh_gunprogress.lua")
AddCSLuaFile("sweeper/sh_fieldtest.lua")
AddCSLuaFile("sweeper/sh_outfitter.lua")
AddCSLuaFile("sweeper/sh_leaderboard.lua")
-- AddCSLuaFile("sweeper/sh_weather.lua") -- weather: on hold, uncomment both lines to turn it back on
AddCSLuaFile("sweeper/sh_upgradestation.lua")
AddCSLuaFile("sweeper/cl_shophotkeys.lua")
AddCSLuaFile("sweeper/cl_hudicons.lua")
AddCSLuaFile("sweeper/cl_statusrow.lua")
AddCSLuaFile("sweeper/cl_colorselect.lua")
AddCSLuaFile("sweeper/cl_shopcategories.lua")
AddCSLuaFile("sweeper/sh_scoreboard.lua")

include("sweeper/sh_tree.lua")
include("sweeper/sh_specs.lua")
include("sweeper/sh_stims.lua")

if SERVER then
	include("sweeper/sv_skills.lua")
else
	include("sweeper/cl_skills.lua")
end

-- After sv_skills.lua, because it wraps S.GetClassData / S.Sync / S.SaveClass / S.AddXP.
-- Shared include; the file itself returns early on the client after its config block.
include("sweeper/sh_pvp.lua")

include("sweeper/sh_integration.lua")
include("sweeper/sh_classorders.lua")
-- After sh_classorders.lua: it wraps that file's S.PlayerCanUseOrder.
include("sweeper/sh_orbitalpicks.lua")
include("sweeper/sh_callins.lua")
include("sweeper/sh_orbitals.lua")
include("sweeper/sh_vehicles.lua")
include("sweeper/sh_offensive.lua")
include("sweeper/sh_abilities.lua")
include("sweeper/sh_engineer.lua")
include("sweeper/sh_recon.lua")
include("sweeper/sh_sentinel.lua")
include("sweeper/sh_infantry.lua")
include("sweeper/sh_group.lua")
include("sweeper/sh_modifiers.lua")
include("sweeper/sh_subfactions.lua")
include("sweeper/sh_mission_relay.lua")
include("sweeper/sh_mission_salvage.lua")
include("sweeper/sh_thirdperson.lua")
include("sweeper/sh_missionfilter.lua")
include("sweeper/sh_gunprogress.lua")
include("sweeper/sh_fieldtest.lua")
include("sweeper/sh_outfitter.lua")
include("sweeper/sh_leaderboard.lua")
-- include("sweeper/sh_weather.lua")
include("sweeper/sh_upgradestation.lua")
include("sweeper/sh_scoreboard.lua")

-- Custom factions: every lua/sweeper/factions/*.lua whose name doesn't start with "_" (so _template.lua is skipped)
for i, f in ipairs(file.Find("sweeper/factions/*.lua", "LUA")) do
	if f:sub(1, 1) ~= "_" then
		if SERVER then AddCSLuaFile("sweeper/factions/" .. f) end
		include("sweeper/factions/" .. f)
	end
end

if CLIENT then
	include("sweeper/cl_shophotkeys.lua")
	include("sweeper/cl_hudicons.lua")
	include("sweeper/cl_statusrow.lua")
	include("sweeper/cl_colorselect.lua")
	include("sweeper/cl_shopcategories.lua")
else
	-- HUD icons: make multiplayer clients download them
	for i, f in ipairs(file.Find("materials/sweeper/icons/*.png", "GAME")) do
		resource.AddFile("materials/sweeper/icons/" .. f)
	end
end
