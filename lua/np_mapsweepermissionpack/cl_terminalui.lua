-- plis make dis globel fonction !!!!
local function getGlitchMatrix(div, baseAddition)
	baseAddition = baseAddition or 0
	local matrix = Matrix()
	matrix:Translate(Vector(0,0, baseAddition + (2 + (math.random() < 0.023 and math.random() or 0))/(div or 8)))
	return matrix
end

rgg_flatscreen = function(ent, mx, my, w, h, modedata)
	local color_bg, color_fg, color_accent = jcms.terminal_GetColors(ent)
	local jcolor_bg, jcolor_fg, jcolor_accent = unpack(jcms.terminal_themes["jcorp"])
	
	local vh = math.min(w, h) 
	local vw = vh
	local vx, vy = (w-vw)/2, (h-vh)/4*3
	
	local btn
	if not ent:GetNWBool("jcms_terminal_locked") then
	
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		surface.SetDrawColor(jcolor_bg)
		surface.DrawRect(vx, vy, vw, vh)
		
		local installed = ent:GetNWBool("osinstall",false)
		
		if mx >= w/8 and mx <= w/1.1 and my >= 300-64 and my <= 300 and not installed then
			render.OverrideBlend( true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
			surface.SetDrawColor(jcolor_fg)
			surface.DrawOutlinedRect(w/20,300-64,w/1.1,64,3)
			btn = 1
		end
		
		draw.SimpleText("#jcms.terminal_rggscreen_hackedtitle", "jcms_hud_medium", w/2, 64, jcolor_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		draw.SimpleText("#jcms.terminal_rggscreen_hackedos", "jcms_hud_medium", w/2, 128, jcolor_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		
		if not installed then
			draw.SimpleText("#jcms.terminal_rggscreen_hackedinstall", "jcms_hud_medium", w/2, 304, jcolor_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		else
			draw.SimpleText("#jcms.terminal_rggscreen_hackedinstalled", "jcms_hud_medium", w/2, 304, jcolor_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
		local matrix = getGlitchMatrix(8)
		cam.PushModelMatrix(matrix, true)
			draw.SimpleText("#jcms.terminal_rggscreen_hackedtitle", "jcms_hud_medium", w/2, 60, jcolor_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			draw.SimpleText("#jcms.terminal_rggscreen_hackedos", "jcms_hud_medium", w/2, 124,jcolor_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			
			if not installed then
				draw.SimpleText("#jcms.terminal_rggscreen_hackedinstall", "jcms_hud_medium", w/2, 300, jcolor_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			else
				draw.SimpleText("#jcms.terminal_rggscreen_hackedinstalled", "jcms_hud_medium", w/2, 300, jcolor_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			end
		cam.PopModelMatrix()
		
		render.OverrideBlend(false)
		return btn
	else
		
		surface.SetDrawColor(color_bg)
		surface.DrawRect(vx, vy, vw, vh)
		
		if mx >= w/8 and mx <= w/1.1 and my >= 300-64 and my <= 300 then
			render.OverrideBlend( true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
			surface.SetDrawColor(color_fg)
			surface.DrawOutlinedRect(w/20,300-64,w/1.1,64,3)
			btn = 0
		end
		
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		
		local randNumb = math.floor(util.SharedRandom(ent:EntIndex(),1,777))
		local rggOS = language.GetPhrase("jcms.terminal_rggscreen_os")
		local OsString = rggOS..randNumb
		
		draw.SimpleText("#jcms.terminal_rggscreen_title", "jcms_hud_medium", w/2, 64, color_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		draw.SimpleText(OsString, "jcms_hud_medium", w/2, 128, color_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		
		draw.SimpleText("#jcms.terminal_rggscreen_access", "jcms_hud_medium", w/2, 304, color_bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		
		local matrix = getGlitchMatrix(8)
		cam.PushModelMatrix(matrix, true)
		
			draw.SimpleText("#jcms.terminal_rggscreen_title", "jcms_hud_medium", w/2, 60, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(OsString, "jcms_hud_medium", w/2, 124, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			
			draw.SimpleText("#jcms.terminal_rggscreen_access", "jcms_hud_medium", w/2, 300, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			
		cam.PopModelMatrix()
		render.OverrideBlend(false)
		return btn
	end
end

jcorp_lightgen = function(ent, mx, my, w, h, modedata)
	local color_bg, color_fg, color_accent = jcms.terminal_GetColors(ent)
	
	local btn
	local vh = math.min(w, h) 
	local vw = vh * 1.8
	local vx, vy = (w-vw)/2.5, (h-vh)/4*3
	
	local matrix = getGlitchMatrix(8)
	cam.PushModelMatrix(matrix, true)
	render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
	surface.SetDrawColor(color_bg)
	surface.DrawRect(vx, vy, vw, vh)
	
	
	if not ent:GetNWBool("jcms_terminal_locked") then
		draw.SimpleText("#jcms.terminal_rggscreen_hackedtitle", "jcms_hud_big", w/1.75, 100, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		draw.SimpleText("#jcms.terminal_lightgen", "jcms_hud_medium", w/1.75, 150, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		
		if not ent:GetNWBool("genrepair") then
			draw.SimpleText("#jcms.terminal_lightgenfix", "jcms_hud_medium", w/1.75, 250, Color(255,0,0):Lerp(Color(255,255,255), math.cos(CurTime() * 5)), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			
			for i = 1,10 do
				local csize = 5+(i*10)
				jcms.draw_Circle(5, 350, csize, csize, 7, 7)
			end
			
			surface.DrawRect(120, 300, 250, 60)
			draw.SimpleText("#jcms.terminal_lightgenactivate", "jcms_hud_medium", 130, 295, Color(255,0,0):Lerp(Color(255,255,255), math.cos(CurTime() * 5)), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			if mx >= 120 and mx <= 370 and my >= 300 and my <= 360 then
				render.OverrideBlend( true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
				surface.SetDrawColor(color_fg)
				surface.DrawOutlinedRect(120, 300, 250, 60)
				btn = 1
			end
		else
		
			draw.SimpleText("#jcms.terminal_lightgenworking", "jcms_hud_medium", 130, 295, Color(255,0,0), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			for i = 1,10 do
				local csize = 5+(i*10)
				surface.SetDrawColor(Color(255,0,0):Lerp(Color(255,255,255), math.abs(math.sin(CurTime()) * 2/i )) )
				jcms.draw_Circle(5, 350, csize, csize, 7, 7)
			end
		end
	else
		draw.SimpleText("#jcms.terminal_rggscreen_hackedtitle", "jcms_hud_big", w/1.75, 100, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		draw.SimpleText("#jcms.terminal_lightgen", "jcms_hud_medium", w/1.75, 150, color_fg, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		
		draw.SimpleText("#jcms.terminal_lightgenerror", "jcms_hud_big", w/1.75, 250, Color(255,0,0):Lerp(Color(255,255,255), math.cos(CurTime() * 5)), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		
		for i = 1,10 do
			local csize = 5+(i*10)
			if i % 2 == 0 then
				jcms.draw_Circle(5, 350, csize*math.cos(CurTime()-(i-1)), csize*math.cos(CurTime()-(i-1)), 7 + math.floor(math.sin(CurTime()) * 1.5), 7+ math.floor(math.sin(CurTime()) * 1.5))
			else
				jcms.draw_Circle(5, 350, csize*math.sin(CurTime()+(i-1)), csize*math.sin(CurTime()+(i-1)), 7 + math.floor(math.cos(CurTime()) * 1.5), 7+ math.floor(math.cos(CurTime()) * 1.5))
				
			end
		
		end
		
		--jcms.terminal_lightgenrepair
		
		surface.DrawRect(120, 300, 200, 60)
		draw.SimpleText("#jcms.terminal_lightgenrepair", "jcms_hud_medium", 130, 295, Color(255,0,0):Lerp(Color(255,255,255), math.cos(CurTime() * 5)), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		if mx >= 120 and mx <= 320 and my >= 300 and my <= 360 then
			render.OverrideBlend( true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
			surface.SetDrawColor(color_fg)
			surface.DrawOutlinedRect(120, 300, 200, 60)
			btn = 0
		end
	end
		cam.PopModelMatrix()
	
	render.OverrideBlend(false)
	return btn
end


jcms.terminal_modeTypes["rgg_flatscreen"] = rgg_flatscreen
jcms.terminal_modeTypes["jcorp_lightgen"] = jcorp_lightgen