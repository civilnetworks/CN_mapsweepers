ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Light Generator"
ENT.Author = "NewPuncher"
ENT.Category = "Map Sweepers"
ENT.Spawnable = false

ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "IsPowered")
end

function ENT:Initialize()
	self:SetupDataTables()
	
	-- apparently we cant add more through mapsweepersready, so this somewhat ugly implement will have to do for now.
	if not jcms.terminal_modelInfos["models/props_combine/combine_interface001a.mdl"] then
		local LightGeneratorType = {
			theme = "jcorp",
			width = 500,
			height = 500,
			up = 50,
			right = 8.5,
			fwd = 0,
			rotateRight = -30,
			rotateUp = 90,
		}

		jcms.terminal_modelInfos["models/props_combine/combine_interface001a.mdl"] = LightGeneratorType
	end
end