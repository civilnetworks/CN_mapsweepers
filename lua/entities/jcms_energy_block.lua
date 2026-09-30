AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Energy block"
ENT.Author = "boblikut"
ENT.Category = "Map Sweepers"

hook.Add( "AllowPlayerPickup", "Allow Energy Block Pickup", function( ply, ent )
	
end )

function ENT:Initialize()
	if SERVER then
		self:SetUseType( SIMPLE_USE )
		self:SetModel("models/Items/battery.mdl")
		self:SetModelScale(3)
		
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		
		local phys = self:GetPhysicsObject()
		
		if phys:IsValid() then
			phys:Wake()
		end

		self:SetColor(Color(255,0,0))
		self:SetShouldPlayPickupSound(true)
	end
end

function ENT:Use( activator )

	activator:PickupObject( self )

end