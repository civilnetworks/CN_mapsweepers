-- models/props_phx/construct/windows/window_dome360.mdl

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_phx/construct/windows/window_dome360.mdl")
    self:SetModelScale(14, 0)
    self:SetMaterial("models/props_combine/portalball001_sheet")
    
    self:PhysicsInitBox(Vector(-128, -128, 0), Vector(128, 128, 128))
    self:SetCollisionBounds(Vector(-128, -128, 0), Vector(128, 128, 128))
	self:SetSolid(SOLID_NONE)
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	self:SetMoveType(MOVETYPE_NONE)
	self:DrawShadow(false)
	
	self.FactionColor = jcms.factions_neutralColor
	if jcms.director then
		self.FactionColor = jcms.factions_GetColor(jcms.director.faction) or jcms.factions_neutralColor
	end
	
	self:SetColor(self.FactionColor)
	
    self.CaptureProgress = 0
	self.CurrentPlayerCount = #player.GetAll()
	
	self.NetworkPercentTime = 0
	
	self.Radius = 700
end

function ENT:Complete()
	self.ZoneCaptured = true
	self:EmitSound("weapons/physcannon/physcannon_claws_open.wav", 100, 120)
	self:SetIsCaptured(true)
	self:SetCaptureProgress(1)
end

function ENT:InZone(ent)
	return self:GetPos():Distance(ent:GetPos()) <= self.Radius and ent:GetPos().z + 50 >= self:GetPos().z
end

function ENT:Think()
    local count = 0
	local AllPlayers = player.GetAll()
	local CurrentPlayers = #player.GetAll()
	
    for _, ply in pairs(AllPlayers) do
        if IsValid(ply) and ply:Alive() and self:InZone(ply) then
            count = count + 1
        end
    end
	
	local hasHostiles = false
	
	for _, ent in ipairs(ents.FindInSphere(self:GetPos(), self.Radius)) do
		if ent:IsNPC() and ent:Alive() and ent:IsValid() and self:InZone(ent) and not jcms.team_JCorp_ent(ent) then
			hasHostiles = true
			break
		end
	end
	

	if CurrentPlayers ~= self.CurrentPlayerCount then
		self.CurrentPlayerCount = CurrentPlayers
	end
	
	local MaxTime = 20 * self.CurrentPlayerCount

	if not self.ZoneCaptured then
		if count > 0 then
			if not hasHostiles then
				self.CaptureProgress = math.Clamp(self.CaptureProgress + FrameTime() * (math.Clamp(count * 0.5,1,5)),0,MaxTime)
			end
		else
			self.CaptureProgress = math.Clamp(self.CaptureProgress - FrameTime() * 0.3, 0, self.CaptureProgress)
		end
		
		if self.CaptureProgress == MaxTime then
			
			self:Complete()
			
		end
	end
	
	local ChargeDecimalValue = self.CaptureProgress/MaxTime
	
	if not self.ZoneCaptured then
		self.NetworkPercentTime = self.NetworkPercentTime + FrameTime()
		if self.NetworkPercentTime >= 1 then
			self:SetCaptureProgress(ChargeDecimalValue)
			self.NetworkPercentTime = 0
		end
		
		if hasHostiles and not self:GetEnemiesBlocking() then
			self:SetEnemiesBlocking(true)
		elseif not hasHostiles and self:GetEnemiesBlocking() then
			self:SetEnemiesBlocking(false)
		end
	end

	if self.CaptureProgress > 0 and not self.ZoneCaptured then
		if not self.ChargeSound or not self.ChargeSound:IsPlaying() then
			if self.ChargeSound then self.ChargeSound:Stop() end
			self.ChargeSound = CreateSound(self, "weapons/physcannon/superphys_hold_loop.wav")
			self.ChargeSound:PlayEx(1, 130+(ChargeDecimalValue*100))
			self.ChargeSound:SetSoundLevel(160)
		elseif self.ChargeSound:IsPlaying() and self:GetEnemiesBlocking() then
			self.ChargeSound:ChangePitch(80)
		elseif self.ChargeSound:IsPlaying() then
			self.ChargeSound:ChangePitch(130+(ChargeDecimalValue*100))
		end
	else
		if self.ChargeSound then self.ChargeSound:Stop() end
	end
	
	local FieldColor = self.FactionColor:Lerp(Color(255,0,0),ChargeDecimalValue)
	self:SetColor(FieldColor)

    self:NextThink(CurTime())
    return true
end



