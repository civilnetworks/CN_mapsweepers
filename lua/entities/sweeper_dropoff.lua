--[[
	Map Sweepers - Implants & Class Levels (addon)
	Salvage Processor: a drop-off point for the Salvage Run mission (sh_mission_salvage.lua).

	There are several of these around the map and they all feed the same quota, so you haul to
	whichever one is closest. Walk into it holding a crate and it takes it off your hands.

	The running total lives on the mission, not on any one processor - sh_mission_salvage.lua
	pushes it to every processor so they all read the same numbers.
--]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Salvage Processor"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Delivered")
	self:NetworkVar("Int", 1, "Quota")
end

local function cfg()
	local c = sweeper and sweeper.salvageMission
	return c or { deliverRange = 180 }
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/jcms/jcorp_orerefinery.mdl")
		self:PhysicsInitStatic(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)

		self:SetDelivered(0)
		self:SetQuota(0)
		self:NextThink(CurTime() + 0.25)
	end

	function ENT:Effects()
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter() + Vector(0, 0, 40))
		ed:SetMagnitude(2)
		ed:SetScale(1)
		util.Effect("cball_explode", ed, true, true)

		self:EmitSound("ambient/machines/thumper_startup1.wav", 80, 120)
		self:EmitSound("buttons/button17.wav", 75, 100)
	end

	function ENT:Think()
		local ct = CurTime()
		self:NextThink(ct + 0.25)

		local range = cfg().deliverRange
		local center = self:WorldSpaceCenter()
		local deliver = sweeper and sweeper.SalvageDeliver
		if not deliver then return true end

		-- Carried in by hand or on the gravity gun.
		for i, ply in ipairs(player.GetAll()) do
			if ply:Alive() and center:DistToSqr(ply:WorldSpaceCenter()) < range * range then
				local crate = ply:GetNWEntity("sweeper_carrying")
				if IsValid(crate) and crate:GetClass() == "sweeper_salvage" then
					deliver(ply, crate, self)
				end
			end
		end

		-- Thrown or punted in. Whoever last held it gets the credit.
		for i, crate in ipairs(ents.FindInSphere(center, range)) do
			if crate:GetClass() == "sweeper_salvage" and not IsValid(crate:GetCarrier()) then
				local last = crate.jcms_lastCarrier
				deliver(IsValid(last) and last or nil, crate, self)
			end
		end

		return true
	end
else
	local matGlow = Material("sprites/light_glow02_add")

	function ENT:Draw()
		self:DrawModel()
	end

	-- Glow only. The objective HUD already carries the delivered/quota count.
	function ENT:DrawTranslucent()
		local delivered, quota = self:GetDelivered(), self:GetQuota()
		local done = quota > 0 and delivered >= quota
		local col = done and Color(90, 255, 140) or Color(255, 200, 80)

		render.SetMaterial(matGlow)
		local pulse = 48 + math.sin(CurTime() * 2) * 10
		render.DrawSprite(self:WorldSpaceCenter() + Vector(0, 0, 70), pulse, pulse, Color(col.r, col.g, col.b, 190))
	end
end
