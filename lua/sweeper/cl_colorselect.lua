--[[
	Map Sweepers - Implants & Class Levels (addon)
	Client: makes the HUD colour picker show which slot you're editing.

	The gamemode already wants to label the picked one - jcms.paint_ButtonColor draws "#jcms.selected"
	when `p:GetParent().selectedColor == p.colorName`. But in the options menu the buttons are parented
	to the colour area while `selectedColor` is stored on the panel ABOVE it, so that test is never
	true and nothing is ever marked. Rather than touch the gamemode, the paint function is wrapped:
	the original runs first, then we look for the flag on the button's parent AND its grandparent and
	draw a white outline plus the SELECTED label ourselves.

	It also seeds the flag to "bright" when nothing has been clicked yet, which is the colour the mixer
	starts on - without that, dragging the mixer before clicking a slot silently edits nothing.
--]]

local S = sweeper

if not CLIENT then return end

local SLOT_DEFAULT = "bright"

-- The flag lives on one of the ancestors; the gamemode only ever checks the first one.
local function selectionHolder(btn)
	local parent = btn.GetParent and btn:GetParent()
	if not IsValid(parent) then return end
	if parent.selectedColor ~= nil then return parent end

	local grandparent = parent:GetParent()
	if IsValid(grandparent) and grandparent.selectedColor ~= nil then return grandparent end

	-- Nothing picked yet anywhere: the grandparent is where the options menu keeps it
	return IsValid(grandparent) and grandparent or parent
end

function S.InstallColorSelectHighlight()
	if not (jcms and jcms.paint_ButtonColor) or S.Wrapped(jcms, "ButtonColorSelect") then return end
	local orig = jcms.paint_ButtonColor

	S._wrappedButtonColor = function(p, w, h, ...)
		local ret = orig(p, w, h, ...)

		local name = p.colorName
		if not name then return ret end

		local holder = selectionHolder(p)
		if not IsValid(holder) then return ret end

		-- The mixer opens on the bright colour, so treat that as the starting selection
		if holder.selectedColor == nil then holder.selectedColor = SLOT_DEFAULT end
		if holder.selectedColor ~= name then return ret end

		local y = p:IsHovered() and 0 or 4
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawOutlinedRect(0, y, w, h - 4, 2)
		draw.SimpleTextOutlined(language.GetPhrase("jcms.selected"), "jcms_small", w / 2, h / 2 + y,
			color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

		return ret
	end

	jcms.paint_ButtonColor = S._wrappedButtonColor
	S.MarkWrapped(jcms, "ButtonColorSelect")
end

hook.Add("Initialize", "sweeper_colorSelect", S.InstallColorSelectHighlight)
hook.Add("InitPostEntity", "sweeper_colorSelect", S.InstallColorSelectHighlight)
S.InstallColorSelectHighlight()
