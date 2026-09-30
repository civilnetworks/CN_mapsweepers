util.AddNetworkString("jcms_np_upg")
util.AddNetworkString("jcms_np_buyreport")
util.AddNetworkString("jcms_np_cacheclient")
util.AddNetworkString("jcms_np_resetupg")
util.AddNetworkString("jcms_np_blackoutupdate")

net.Receive("jcms_np_upg",function(len,ply)
	if not ply:Alive() or not IsValid(ply) then return end
	
	local UpgradePick = net.ReadUInt(4)
	local UsersCash = ply:GetNWInt("jcms_cash",0)
	
	-- its sanity checking time!!!!
	local UpgradeInfo = jcms.np_upgradeinfo[UpgradePick]
	if not UpgradeInfo then return end
	
	local UpgradeCost = UpgradeInfo.Cost
	if UsersCash < UpgradeCost then return end 
	
	if jcms.np_has_upgradetag(ply,UpgradePick) then return end 
	
	ply:SetNWInt("jcms_cash",UsersCash-UpgradeCost)
	
	jcms.np_tag_upgrade(ply,UpgradePick)
	
	net.Start("jcms_np_cacheclient") -- tell the client the purchase was successful so we can cache it lol.
	net.WriteUInt(UpgradePick,4)
	net.Broadcast(ply)
	
	local CallbackString = UpgradeInfo.Callback
	if CallbackString then
		jcms.np_upgradecallbacks[CallbackString](ply)
	end
end)

net.Receive("jcms_np_buyreport",function(len,ply)
	if not ply:Alive() or not IsValid(ply) then return end
	
	local Terminal = net.ReadEntity()
	if not IsValid(Terminal) then return end
	
	if Terminal:GetClass() ~= "jcms_rggcasinoterminal" then return end
	
	if Terminal:GetReportBought() then return end
	
	local BuyPrice = Terminal:GetReportPrice()
	local UsersCash = ply:GetNWInt("jcms_cash",0)
	
	if UsersCash < BuyPrice then return end
	ply:SetNWInt("jcms_cash",UsersCash-BuyPrice)
	Terminal:SetReportBought(true)
end)


