include("shared.lua")

function ENT:DrawTranslucent()

	--self:DrawModel()
	if not self:GetIsPowered() then
		local ply = LocalPlayer()
		if not IsValid(ply) then return end

		local dist = ply:GetPos():Distance(self:GetPos())
		local maxDist, minDist = 3750, 1000
		local fade = 1 - math.Clamp((dist - minDist) / (maxDist - minDist), 0, 1)

		if fade <= 0 then return end 

		local pos = self:GetPos()
		local top = pos + Vector(0, 0, 5000)

		render.SetMaterial(Material("blackoutbeacon/jbeam"))
		render.DrawBeam(pos, top, 20 * fade, 0, 10, Color(255, 50, 50, 200 * fade))
	end
end