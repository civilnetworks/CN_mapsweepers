ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Control Zone"
ENT.Author = "NewPuncher"
ENT.Category = "Map Sweepers"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "CaptureProgress")
	self:NetworkVar("Bool", 0, "IsCaptured")
	self:NetworkVar("Bool", 1, "EnemiesBlocking")
end

function ENT:Initialize()
	self:SetupDataTables()
end