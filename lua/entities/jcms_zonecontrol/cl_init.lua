include("shared.lua")

function ENT:DrawTranslucent()
	self:DrawModel()
 
	local progress = self:GetCaptureProgress() or 0
	local obstructed = self:GetEnemiesBlocking() or false
	local captured = self:GetIsCaptured() or false
    local percentage = math.floor(progress * 100)

    cam.Start3D2D(self:GetPos() + Vector(0, 0, 100), Angle(0, LocalPlayer():EyeAngles().y - 90, 90), 0.25)
		if not captured then
        draw.SimpleText( language.GetPhrase("jcms.np_zone_capture_progress") .." ".. percentage .. "%", "jcms_hud_big", math.Rand(-4, 4), math.Rand(-1, 1), Color(255, 255, 255,125):Lerp(Color(255,0,0,125),progress), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		
		if progress > 0 and not obstructed and not captured then
		draw.SimpleText(language.GetPhrase("jcms.np_zone_defend"), "jcms_hud_big", math.Rand(-4, 4), 60 + math.Rand(-1,1), Color(255, 255, 255,125), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif obstructed and not captured then
		draw.SimpleText(language.GetPhrase("jcms.np_zone_contested"), "jcms_hud_big", math.Rand(-4, 4), 60 + math.Rand(-1,1), Color(255, 0, 0,125), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif captured then
		draw.SimpleText(language.GetPhrase("jcms.np_zone_secured"), "jcms_hud_big", math.Rand(-4, 4), 60 + math.Rand(-1,1), Color(255, 0, 0,125), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
    cam.End3D2D()
end
