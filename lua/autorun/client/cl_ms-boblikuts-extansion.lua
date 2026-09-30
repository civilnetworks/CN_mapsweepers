hook.Add("MapSweepersReady", "boblikut's missions", function()
	jcms.missions.generator = {
		tags = { },
		faction = "any"
	}
	jcms.missions.guntest = {
		tags = { "hacking", "killsrequired" },
		faction = "any"
	}
	
	local function getGlitchMatrix(div, baseAddition)
		baseAddition = baseAddition or 0
		local matrix = Matrix()
		matrix:Translate(Vector(0,0, baseAddition + (2 + (math.random() < 0.023 and math.random() or 0))/(div or 8)))
		return matrix
	end
	
	jcms.terminal_modeTypes.guntest_terminal  = function(ent, mx, my, w, h, modedata)  
		local color_bg, color_fg, color_accent = jcms.terminal_GetColors(ent)  
		
		surface.SetDrawColor(color_bg)
		cam.PushModelMatrix(getGlitchMatrix(), true)
		render.OverrideBlend( true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
			surface.DrawRect(0, 0, w, h)
		render.OverrideBlend( false )
		cam.PopModelMatrix()
		  
		cam.PushModelMatrix(getGlitchMatrix(), true)  
			render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)  
			draw.SimpleText("#jcms.terminal_guntestcontrols", "jcms_hud_medium", w/2, 32, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)  
			render.OverrideBlend(false)  
		cam.PopModelMatrix()  
		  
		local buttonId  
		  
		if ent:GetNWBool("jcms_terminal_locked") then  
			cam.PushModelMatrix(getGlitchMatrix(), true)  
				render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)  
				draw.SimpleText("#jcms.terminal_unlocked", "jcms_hud_medium", w/2, h*0.75, color_accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)  
				render.OverrideBlend(false)  
			cam.PopModelMatrix()  
		else  
			if modedata == "gotten" then    
				cam.PushModelMatrix(getGlitchMatrix(), true)  
					render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)  
					draw.SimpleText("#jcms.terminal_guntestgotten", "jcms_hud_medium", w/2, h*0.75, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)  
					render.OverrideBlend(false)  
				cam.PopModelMatrix()  
			else   
				local bx, by, bw, bh = w/2 - 75, h*0.75 - 24, 150, 48  
				  
				if mx >= bx and my >= by and mx <= bx + bw and my <= by + bh then  
					surface.SetDrawColor(color_fg)  
					buttonId = 1  
				else  
					surface.SetDrawColor(color_bg)  
				end  
				  
				surface.DrawRect(bx, by, bw, bh)  
				  
				cam.PushModelMatrix(getGlitchMatrix(), true)  
					render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)  
					draw.SimpleText("#jcms.terminal_guntestget", "jcms_hud_medium", bx + bw/2, by + bh/2, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)  
					render.OverrideBlend(false)  
				cam.PopModelMatrix()  
			end  
		end  
		  
		return buttonId  
	end
	
	
	local function RotateVectorAroundPoint(vec, center, angleDeg)
		local angleRad = math.rad(angleDeg)
		local translated = vec - center

		local cosA = math.cos(angleRad)
		local sinA = math.sin(angleRad)

		local rotated = Vector(
			translated.x * cosA - translated.y * sinA,
			translated.x * sinA + translated.y * cosA,
			translated.z
		)

		return rotated + center
	end

	hook.Add("PostDrawOpaqueRenderables", "DrawElectricEffect", function()
		local ent = ents.FindByClass("jcms_generator")[1]
		if !ent or !ent:IsValid() or !ent:GetNWBool("working") then return end
		
		render.SetMaterial(Material("sprites/bluelaser1"))
		render.StartBeam(10)
		
		local ent_pos = ent:GetPos()
		local ent_ang = ent:GetAngles()
		local start_pos = ent_pos + Vector(0,80,150)
		local end_pos = ent_pos + Vector(0,-80,150)
		start_pos = RotateVectorAroundPoint(start_pos, ent:GetPos() + Vector(0,0,150), ent_ang.y)
		end_pos = RotateVectorAroundPoint(end_pos, ent:GetPos() + Vector(0,0,150), ent_ang.y)
		
		for i = 0, 4 do
			local t = i / 4
			local pos = LerpVector(t, start_pos, end_pos)
			local offset = VectorRand() * 15
			render.AddBeam(pos + offset, 10, 0.5, Color(240,75,75))
		end

		render.EndBeam()
	end)
	
end)