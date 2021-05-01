-- GLOBALS: GDKPd, GDKPd_PotData, GDKPd_Anchor, GDKPd_BalanceData, SlashCmdList, SLASH_GDKPD1, SLASH_GDKPD2
-- fetch all used functions into locals to improve performance
local table, tinsert, tremove, pairs, ipairs, unpack, math, tostring, tonumber, select, _G, strlen, setmetatable, string, print, next, type, rawget, date = 
	  table, tinsert, tremove, pairs, ipairs, unpack, math, tostring, tonumber, select, _G, strlen, setmetatable, string, print, next, type, rawget, date
local SendAddonMessage, SendChatMessage, UnitIsRaidOfficer, UnitIsUnit, UnitIsGroupLeader, GetMasterLootCandidate, GetNumLootItems, GetLootSlotLink, GiveMasterLoot, UnitName, GetUnitName, CreateFrame, GetCVar, GetCVarBool, GetTime, StaticPopup_Show, GetItemInfo, GameTooltip, LibStub, ITEM_QUALITY_COLORS, InCombatLockdown, ERR_TRADE_COMPLETE, GetPlayerTradeMoney, GetTargetTradeMoney, GetItemIcon, ClearCursor, GetNumGroupMembers, GetRaidRosterInfo, GetLootThreshold, GetLootSlotType, GetLootSlotInfo, EditBox_HandleTabbing, GetCursorInfo, PickupItem, IsInRaid, IsInGroup, SendMail, SetSendMailMoney, ClearSendMail =
	  C_ChatInfo.SendAddonMessage, SendChatMessage, UnitIsRaidOfficer, UnitIsUnit, UnitIsGroupLeader, GetMasterLootCandidate, GetNumLootItems, GetLootSlotLink, GiveMasterLoot, UnitName, GetUnitName, CreateFrame, GetCVar, GetCVarBool, GetTime, StaticPopup_Show, GetItemInfo, GameTooltip, LibStub, ITEM_QUALITY_COLORS, InCombatLockdown, ERR_TRADE_COMPLETE, GetPlayerTradeMoney, GetTargetTradeMoney, GetItemIcon, ClearCursor, GetNumGroupMembers, GetRaidRosterInfo, GetLootThreshold, GetLootSlotType, GetLootSlotInfo, EditBox_HandleTabbing, GetCursorInfo, PickupItem, IsInRaid, IsInGroup, SendMail, SetSendMailMoney, ClearSendMail
local _
local UIParent, MailFrame =
	  UIParent, MailFrame
	  
-- Fetch all the different realm separators into a table
local REALM_SEPARATOR_LIST = {}
for s in REALM_SEPARATORS:gmatch(".") do tinsert(REALM_SEPARATOR_LIST,s) end

--Auto loot declarations
local deformat = LibStub("LibDeformat-3.0");

--MRT IMPORTS
local ScrollingTable = LibStub("ScrollingTable2");

-- table handling to prevent any memory leakage from accumulating.
local emptytable = select(2,...).emptytable

local DEBUGFORCEVERSION

--[===[@debug@
DEBUGFORCEVERSION="2.0.0"
--@end-debug@]===]
-- fetch locale data
local L = LibStub("AceLocale-3.0"):GetLocale("GDKPd")
-- versioning info
local VERSIONING_STRINGS = {
	VERSION_NONFUNCTIONAL = L["This version of GDKPd was never functional due to internal errors."],
	INCOMPATIBLE_AUCTIONSTART = L["This version will be unable to recognize auctions started by you."],
	INCOMPATIBLE_DISTRIBUTE = L["This version's player balance window will be unable to recognize distributions by you."],
	INCOMPATIBLE_AUCTIONCANCEL = L["This version will be unable to recognize auctions cancelled by you."],
	INCOMPATIBLE_VERSIONCHECK = L["This version will be unable to recognize version check requests by you. Version check requests sent by this version of GDKPd will not be answered."],
}
local COMPATIBLE_VERSIONS = {
	["2.0.0"]=true,
}
local INCOMPATIBLE_VERSIONS = {
	["beta-1"]={"INCOMPATIBLE_AUCTIONSTART","INCOMPATIBLE_AUCTIONCANCEL","INCOMPATIBLE_DISTRIBUTE"},
}

-- define a few old API functions that I can't be bothered to replace everywhere
local function IsRaidOfficer()
	return IsInRaid() and UnitIsRaidOfficer("player")
end

local function IsRaidLeader()
	return IsInRaid() and UnitIsGroupLeader("player")
end

local function LootSlotIsItem(i)
	return (GetLootSlotType(i) == 1)
end

-- static popup dialog definition
StaticPopupDialogs["GDKPD_RESETPOT"] = {
	text=L["Do you want to save your pot or reset without saving? You can also add a note to the pot."],
	button1=SAVE.." & "..RESET,
	button2=RESET,
	button3=CANCEL,
	hasEditBox=true,
	EditBoxOnEnterPressed=function(self) self:GetParent().button1:Click() end,
	OnAccept=function(self)
		tinsert(GDKPd_PotData.history, {size=GDKPd_PotData.potAmount, date=date(), items=GDKPd_PotData.curPotHistory, note=(strlen(self.editBox:GetText()) > 0 and self.editBox:GetText())})
		GDKPd_PotData.potAmount = 0
		GDKPd_PotData.prevDist = 0
		GDKPd_PotData.curPotHistory = {}
		GDKPd_PotData.playerBalance = setmetatable({},{__index=function() return 0 end})
		GDKPd.status:Update()
		GDKPd.balance:Update()
		if GDKPd.history:IsShown() then
			GDKPd.history:Update()
		end
		GDKPd:PotLogTableUpdate()
	end,
	OnCancel=function(self)
		GDKPd_PotData.potAmount = 0
		GDKPd_PotData.prevDist = 0
		GDKPd_PotData.curPotHistory = {}
		GDKPd_PotData.playerBalance = setmetatable({},{__index=function() return 0 end})
		GDKPd.status:Update()
		GDKPd.balance:Update()
	end,
	timeout=0,
}
StaticPopupDialogs["GDKPD_SLIMMLWARN"] = {
	text=L["WARNING!\n\nIf you use the slim bidding frame, you will be unable to cancel auctions and revert bids!\nAre you certain you want to do this?"],
	button1=YES,
	button2=NO,
	OnShow=function(self)
		--elevate it above aceconfig
		self:SetFrameStrata("FULLSCREEN_DIALOG")
		self.button1:SetFrameLevel(10000)
		self.button2:SetFrameLevel(10000)
	end,
	OnAccept=function()
		GDKPd.opt.slimML = true
		GDKPd.opt.slimMLConfirmed=true
	end,
	OnHide=function(self)
		self:SetFrameStrata("DIALOG")
	end,
	timeout=0,
	hideOnEscape=true,
	whileDead=true,
	showAlert=true,
	cancels="GDKPD_SLIMMLWARN",
}
StaticPopupDialogs["GDKPD_ADDTOPOT"] = {
	text=L["Enter the amount you want to add to the pot:"],
	button1=ADD,
	button2=CANCEL,
	hasEditBox=true,
	OnShow=function(self)
		self.button1:Disable()
	end,
	EditBoxOnEnterPressed=function(self) self:GetParent().button1:Click() end,
	EditBoxOnTextChanged = function(self)
		if strlen(self:GetText()) > 0 then
			self:GetParent().button1:Enable()
		else
			self:GetParent().button1:Disable()
		end
	end,
	OnAccept=function(self)
		GDKPd_PotData.potAmount = (tonumber(self.editBox:GetText()) or 0)+GDKPd_PotData.potAmount
		tinsert(GDKPd_PotData.curPotHistory, tonumber(self.editBox:GetText()) or 0)
		GDKPd.status:Update()
	end,
	timeout=0,
	whileDead=true,
}
StaticPopupDialogs["GDKPD_REMFROMPOT"] = {
	text=L["Enter the amount you want to subtract from the pot:"],
	button1=REMOVE,
	button2=CANCEL,
	hasEditBox=true,
	OnShow=function(self)
		self.button1:Disable()
	end,
	EditBoxOnEnterPressed=function(self) self:GetParent().button1:Click() end,
	EditBoxOnTextChanged=function(self)
		if strlen(self:GetText()) > 0 then
			self:GetParent().button1:Enable()
		else
			self:GetParent().button1:Disable()
		end
	end,
	OnAccept = function(self)
		GDKPd_PotData.potAmount = math.max(0, GDKPd_PotData.potAmount-(tonumber(self.editBox:GetText()) or 0))
		tinsert(GDKPd_PotData.curPotHistory, (tonumber(self.editBox:GetText()) or 0)*(-1))
		GDKPd.status:Update()
	end,
	timeout=0,
	whileDead=true,
}
StaticPopupDialogs["GDKPD_ADDTOPLAYER"] = {
	text=L["Enter the amount you want to add to player %s:"],
	button1=ADD,
	button2=CANCEL,
	hasEditBox=true,
	OnShow=function(self)
		self.button1:Disable()
	end,
	EditBoxOnEnterPressed=function(self) self:GetParent().button1:Click() end,
	EditBoxOnTextChanged=function(self)
		if strlen(self:GetText()) > 0 then
			self:GetParent().button1:Enable()
		else
			self:GetParent().button1:Disable()
		end
	end,
	OnAccept = function(self, data)
		GDKPd_PotData.playerBalance[data] = (GDKPd_PotData.playerBalance[data]+(tonumber(self.editBox:GetText()) or 0))
		SendAddonMessage("GDKPD MANADJ",tostring((tonumber(self.editBox:GetText()) or 0)*(-1)),"WHISPER",data)
		GDKPd.balance:Update()
		if GDKPd.opt.linkBalancePot then
			GDKPd_PotData.potAmount = math.max(0, GDKPd_PotData.potAmount-(tonumber(self.editBox:GetText()) or 0))
			tinsert(GDKPd_PotData.curPotHistory, (tonumber(self.editBox:GetText()) or 0)*(-1))
			GDKPd.status:Update()
		end
	end,
	timeout=0,
	whileDead=true,
}
StaticPopupDialogs["GDKPD_REMFROMPLAYER"] = {
	text=L["Enter the amount you want to subtract from player %s:"],
	button1=REMOVE,
	button2=CANCEL,
	hasEditBox=true,
	OnShow=function(self)
		self.button1:Disable()
	end,
	EditBoxOnEnterPressed=function(self) self:GetParent().button1:Click() end,
	EditBoxOnTextChanged=function(self)
		if strlen(self:GetText()) > 0 then
			self:GetParent().button1:Enable()
		else
			self:GetParent().button1:Disable()
		end
	end,
	OnAccept = function(self, data)
		GDKPd_PotData.playerBalance[data] = (GDKPd_PotData.playerBalance[data]-(tonumber(self.editBox:GetText()) or 0))
		SendAddonMessage("GDKPD MANADJ",tostring(tonumber(self.editBox:GetText()) or 0),"WHISPER",data)
		GDKPd.balance:Update()
		if GDKPd.opt.linkBalancePot then
			GDKPd_PotData.potAmount = GDKPd_PotData.potAmount+(tonumber(self.editBox:GetText()) or 0)
			tinsert(GDKPd_PotData.curPotHistory, tonumber(self.editBox:GetText()) or 0)
			GDKPd.status:Update()
		end
	end,
	timeout=0,
	whileDead=true,
}
StaticPopupDialogs["GDKPD_MAILGOLD"]={
	text=L["Are you sure you want to mail %s gold to player %s?"],
	button1=L["Mail money"],
	button2=CANCEL,
	OnAccept=function(self,data)
		GDKPd:MailBalanceGold(data)
	end,
	timeout=0,
	whileDead=true,
	showAlert=true,
	hideOnEscape=true,
}
StaticPopupDialogs["GDKPD_WIPEHISTORY"]={
	text=L["This will completely wipe your auction history and is IRREVERSIBLE.\nAre you completely SURE you want to do this?"],
	button1=L["Wipe history"],
	button2=CANCEL,
	OnAccept=function()
		table.wipe(GDKPd_PotData.history)
		if GDKPd.history:IsShown() then
			GDKPd.history:Update()
		end
	end,
	timeout=0,
	hideOnEscape=true,
	whileDead=true,
	showAlert=true,
	cancels="GDKPD_WIPEHISTORY",
}
StaticPopupDialogs["GDKPD_AUTOBID"] = {
	text=L["Enter the maximum amount of money you want to bid on %s:"],
	button1=BID,
	button2=CANCEL,
	hasEditBox=true,
	OnShow=function(self)
		self.button1:Disable()
	end,
	EditBoxOnEnterPressed=function(self) self:GetParent().button1:Click() end,
	EditBoxOnTextChanged = function(self)
		if strlen(self:GetText()) > 0 then
			self:GetParent().button1:Enable()
		else
			self:GetParent().button1:Disable()
		end
	end,
	OnAccept=function(self, data)
		data.maxAutoBid = tonumber(self.editBox:GetText())
		if (data.curbidismine == false) and data.maxAutoBid then
			local newBid = data.curbidamount + data.bidIncrement
			if newBid <= data.maxAutoBid then
				if data.isMultiBid then
					SendChatMessage(data.itemlink.." "..newBid,"RAID")
				else
					SendChatMessage(tostring(newBid),"RAID")
				end
			end
		end
		data.autobid:Hide()
		data.stopautobid:Show()
	end,
	timeout=0,
}
StaticPopupDialogs["GDKPD_CURPOTCLICK"]={
	text=L["You have selected the current pot, size %d gold.\nWhat do you want to do with this pot?"],
	button1=L["Export"],
	button2=DELETE,
	button3=CANCEL,
	OnShow=function(self) self.button3:Disable() end,
	OnAccept=function(self)
		GDKPd.exportframe:Show()
		GDKPd.exportframe:Set("", GDKPd_PotData.curPotHistory)
	end,
	timeout=0,
	whileDead=true,
}
StaticPopupDialogs["GDKPD_HISTORYCLICK"] = {
	text="%s",
	button1=L["Export"],
	button2=DELETE,
	button3=CANCEL,
	OnAccept=function(self, data)
		print("onaccept")
		local output = "GDKPd pot data for "..data.date.."\nPot size: "..data.size.." gold"
		if data.note then
			output = output.."\nNote: "..data.note
		end
		--[[if data.items then
			for _, aucdata in ipairs(data.items) do
				if type(aucdata) == "table" then
					output = output.."\n"..(aucdata.item:match("(|h.+|h)"))..": "..aucdata.name.." ("..aucdata.bid.." gold)"
				else
					output = output.."\n"..L["Manual adjustment"]..": "..(aucdata > 0 and "+" or "")..aucdata.." gold"
				end
			end
		end--]]
		GDKPd.exportframe:Show()
		GDKPd.exportframe:Set(output,data.items)
	end,
	OnCancel=function(self, data,clickType)
		if clickType == "override" then return end
		for num, t in ipairs(GDKPd_PotData.history) do
			if t == data then
				tremove(GDKPd_PotData.history, num)
				break
			end
		end
		GDKPd.history:Update()
	end,
	timeout=0,
	whileDead=0,
}
StaticPopupDialogs["GDKPD_CUSTOMSETTINGSID"]={
	text=L["Please enter the itemID of an item you want to drop here:"],
	button1=OKAY,
	button2=CANCEL,
	hasEditBox=true,
	OnShow=function(self)
		self.button1:Disable()
	end,
	EditBoxOnEnterPressed=function(self) self:GetParent().button1:Click() end,
	hideOnEscape=true,
	EditBoxOnTextChanged = function(self)
		if (tonumber(self:GetText())) and (tonumber(self:GetText()) >= 0) and (not GDKPd.opt.customItemSettings[tonumber(self:GetText())]) then
			self:GetParent().button1:Enable()
		else
			self:GetParent().button1:Disable()
		end
	end,
	OnAccept=function(self)
		GDKPd.opt.customItemSettings[tonumber(self.editBox:GetText())] = {}
		GDKPd.itemsettings:Update()
	end,
	timeout=0,
}
StaticPopupDialogs["GDKPD_42_ADDONMSG"]={
	text=L["Due to the changes to the addon message system implemented in patch 4.2, GDKPd is no longer able to communicate using its old version checking standard.\nThus, this version of GDKPd will only be able to send and receive version checks from and to versions 1.2.0 and above of GDKPd.\nWhile all other functionalities of GDKPd should still be compatible with previous versions, we |cffff0000strongly recommend updating GDKPd to version 1.2.0 or above|r."],
	button1=OKAY,
	showAlert=true,
	hideOnEscape=false,
	timeout=0,
}
local function round(num, places)
	return tonumber(string.format("%."..(places or 0).."f",num))
end
-- if GetUnitName cannot parse the name as a unitID, that means they're from our realm - parse manually
local function localNameOnly(name)
	for _,s in ipairs(REALM_SEPARATOR_LIST) do
		local i = name:find(s,1,true)
		if i then name=name:sub(1,i-1) end
	end
	return name
end
local function pruneCrossRealm(name) -- only use for people in the raid group!
	return GetUnitName(name,true) or localNameOnly(name)
end
GDKPd = CreateFrame("Frame")
local GDKPd = GDKPd
GDKPd.frames = {}
GDKPd.curAuction = {}
GDKPd.curAuctions = {}
GDKPd.auctionList = {}
GDKPd.ignoredLinks = {}
GDKPd.versions = {}
GDKPd.itemCount = 0 -- # of loot drop, also index of loot that dropped.
GDKPd.itemNew = true --flag for auction if new, add to curPotHistory, if false, search to modify.
GDKPd:Hide()
GDKPd:SetScript("OnUpdate", function(self, elapsed)
	if (not self.curAuction.item) and (not next(self.curAuctions)) then self:Hide() return end
	if not self.opt.allowMultipleAuctions then
		-- old code for single auctions
		local curPot = math.floor(self.curAuction.timeRemains/self.opt.countdownTimerJump)
		self.curAuction.timeRemains = self.curAuction.timeRemains-elapsed
		if (curPot ~= math.floor(self.curAuction.timeRemains/self.opt.countdownTimerJump)) and (curPot*self.opt.countdownTimerJump < self.opt.auctionTimer) and (not (next(self.curAuction.bidders,nil) and (curPot*self.opt.countdownTimerJump == self.opt.auctionTimerRefresh))) and (curPot > 0) then
			SendChatMessage("[Caution] "..(curPot*self.opt.countdownTimerJump).." seconds remaining!","RAID")
		end
		if self.curAuction.timeRemains <= 0 then
			self:Hide()
			self:FinishAuction()
		end
	else
		-- new code for multiple auctions
		local auctionsToFinish = emptytable()
		for item,aucdata in pairs(self.curAuctions) do
			local curPot = math.floor(aucdata.timeRemains/self.opt.countdownTimerJump)
			aucdata.timeRemains = aucdata.timeRemains-elapsed
			if (curPot ~= math.floor(aucdata.timeRemains/self.opt.countdownTimerJump)) and (curPot*self.opt.countdownTimerJump < self.opt.auctionTimer) and (not (next(aucdata.bidders,nil) and (curPot*self.opt.countdownTimerJump == self.opt.auctionTimerRefresh))) and (curPot > 0) then
				SendChatMessage("[Caution] "..(curPot*self.opt.countdownTimerJump).." seconds remaining for item "..item.."!","RAID")
			end
			if aucdata.timeRemains <= 0 then
				tinsert(auctionsToFinish, item)
			end
		end
		if #auctionsToFinish > 0 then
			for _, link in ipairs(auctionsToFinish) do
				self:FinishAuction(link)
			end
		end
		auctionsToFinish:Release()
		-- there are no keys
		if not next(self.curAuctions) then
			self:Hide()
		end
	end
end)
local anchor = CreateFrame("Frame", "GDKPd_Anchor", UIParent)
anchor:SetClampedToScreen(true)
anchor:EnableMouse(true)
anchor:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
anchor:SetMovable(true)
anchor:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
	GDKPd.opt.point.point, _, GDKPd.opt.point.relative, GDKPd.opt.point.x, GDKPd.opt.point.y = self:GetPoint()
end)
anchor:SetSize(300,60)
anchor:SetFrameStrata("DIALOG")
anchor:Hide()
anchor.movetx = anchor:CreateTexture()
anchor.movetx:SetAllPoints()
anchor.movetx:SetTexture(0.3,0.3,0.9)
anchor.movetx:SetAlpha(0.5)
anchor.movetx.text = anchor:CreateFontString()
anchor.movetx.text:SetFontObject(GameFontHighlightLarge)
anchor.movetx.text:SetText(L["GDKPd: Drag to move\n/gdkpd and check \"Lock\" to hide"])
anchor.movetx.text:SetAllPoints()

-------------------------------------------------------------------------------------------
-- STATUS FRAME
-------------------------------------------------------------------------------------------
GDKPd.status = CreateFrame("Frame", "GDKPd_Status", UIParent)
local status = GDKPd.status
status:SetSize(605, 550)
status:Hide()
status:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
function status:UpdateVisibility(forceCombat)
--	if GDKPd.opt.hide then
--		self:Hide()
--		return
--	end
--	if ((not GDKPd.opt.hideCombat.status) or (not (forceCombat ~= nil and forceCombat or InCombatLockdown()))) and GDKPd:PlayerIsML((UnitName("player")),true) then
--		self:Show()
--	else
--		self:Hide()
--	end
end

--HEADER
status.header = CreateFrame("Button", nil, status)
status.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
status.header:SetSize(180,50)
status.header.text = status.header:CreateFontString()
status.header.text:SetPoint("TOP",0,-9)
status.header.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
status.header.text:SetTextColor(1,1,1)
status.header.text:SetText("GDKPd")
status.header:SetMovable(true)
status.header:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
status.header:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
	GDKPd.opt.statuspoint.point, _, GDKPd.opt.statuspoint.relative, GDKPd.opt.statuspoint.x, GDKPd.opt.statuspoint.y = self:GetPoint()
end)
status:SetPoint("TOP", status.header, "TOP", 0, -6)
status:SetScript("OnShow", function(self)
	self:UpdateSize()
end)

--CLOSE BUTTON
local close = CreateFrame("Button", nil, status, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 1)

--BOSS LOOT TABLE
local BossLootTableColDef = {
    {["name"] = "", ["width"] = 1},                            -- invisible column for storing the loot number index from the raidlog-table
    {                                                          -- coloumn for Item Icon - need to store ID
        ["name"] = "Icon",
        ["width"] = 30,
        ["DoCellUpdate"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, fShow, self, ...)
            -- icon handling
            if fShow then
                --GDKPd_Debug("self:GetCell(realrow, column) = "..self:GetCell(realrow, column));
                local itemId = self:GetCell(realrow, column);
                local itemTexture = GetItemIcon(itemId);
                cellFrame:SetBackdrop( { bgFile = itemTexture } );            -- put this back in, if and when SetBackdrop can handle texture IDs
               if not (cellFrame.cellItemTexture) then
                    cellFrame.cellItemTexture = cellFrame:CreateTexture();
                end
                cellFrame.cellItemTexture:SetTexture(itemTexture);
                cellFrame.cellItemTexture:SetTexCoord(0, 1, 0, 1);
                cellFrame.cellItemTexture:Show();
                cellFrame.cellItemTexture:SetPoint("CENTER", cellFrame.cellItemTexture:GetParent(), "CENTER");
                cellFrame.cellItemTexture:SetWidth(30);
                cellFrame.cellItemTexture:SetHeight(30);
            end
            -- tooltip handling
            local itemLink = self:GetCell(realrow, 6);
            cellFrame:SetScript("OnEnter", function()
                                             status.itemtt:SetOwner(cellFrame, "ANCHOR_RIGHT");
                                             status.itemtt:SetHyperlink(itemLink);
                                             status.itemtt:Show();
                                           end);
            cellFrame:SetScript("OnLeave", function()
												status.itemtt:Hide();
												status.itemtt:SetOwner(UIParent, "ANCHOR_NONE");
                                           end);
        end,
    },
    {["name"] = "Name", ["width"] = 120},
    {["name"] = "Looter", ["width"] = 85},
    {["name"] = "Price", ["width"] = 45},
    {["name"] = "", ["width"] = 1},                            -- invisible column for itemString (needed for tooltip)
    {["name"] = "Time", ["width"] = 45},
    {                                                          -- col for OffSpec
    ["name"] = "Done", 
    ["width"] = 30,
 --   ["DoCellUpdate"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, fShow, self, ...)
--    end,
    },                  
};
--Tooltip declaration
status.itemtt = CreateFrame("GameTooltip", "GDKP_ItemTT", UIParent, "GameTooltipTemplate")
--Tooltips are being wonky.. maybe this will stop the wonkiness
status.itemtt:UnregisterAllEvents()

--Boss Loot Table
status.BossLootTable = ScrollingTable:CreateST(BossLootTableColDef, 12, 32, nil, status);           -- ItemId should be squared - so use 30x30 -> 30 pixels high
status.BossLootTable.head:SetHeight(15);                                                                     -- Manually correct the height of the header (standard is rowHight - 30 pix would be different from others tables around and looks ugly)
status.BossLootTable.frame:SetPoint("TOPLEFT", status, "TOPLEFT", 200, -75);
status.BossLootTable:EnableSelection(true);

--BOSS LOOT FILTER
status.lootFilter = CreateFrame("EditBox", nil, status, "InputBoxTemplate")
status.lootFilter:SetSize(100, 30)
status.lootFilter:SetAutoFocus(false) -- dont automatically focus
status.lootFilter:SetFontObject("ChatFontNormal")
status.lootFilter:SetPoint("TOPLEFT", status, "TOPLEFT", 210, -25);

--ADD LOOT BUTTON
status.addLoot = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.addLoot:SetSize(22, 22)
status.addLoot:SetPoint("LEFT", status.distribute, "RIGHT")
status.addLootFont = status.addLoot:CreateFontString()
status.addLootFont:SetFont("Fonts/FRIZQT__.TTF",14)
status.addLootFont:SetText("+")
status.addLoot:SetFontString(status.addLootFont)
status.addLoot:SetPoint("TOPLEFT", status, "TOPLEFT", 315, -28);

--REMOVE LOOT BUTTON
status.removeLoot = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.removeLoot:SetSize(22, 22)
status.removeLoot:SetPoint("LEFT", status.distribute, "RIGHT")
status.removeLootFont = status.removeLoot:CreateFontString()
status.removeLootFont:SetFont("Fonts/FRIZQT__.TTF",14)
status.removeLootFont:SetText("-")
status.removeLoot:SetFontString(status.removeLootFont)
status.removeLoot:SetPoint("TOPLEFT", status, "TOPLEFT", 337, -28);

--EDIT LOOT BUTTON
status.editLoot = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.editLoot:SetSize(50, 22)
status.editLoot:SetPoint("LEFT", status.distribute, "RIGHT")
status.editLootFont = status.editLoot:CreateFontString()
status.editLootFont:SetFont("Fonts/FRIZQT__.TTF",12)
status.editLootFont:SetText("Edit")
status.editLoot:SetFontString(status.editLootFont)
status.editLoot:SetPoint("TOPLEFT", status, "TOPLEFT", 360, -28);

--LINK LOOT BUTTON
status.linkLoot = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.linkLoot:SetSize(50, 22)
status.linkLoot:SetPoint("LEFT", status.distribute, "RIGHT")
status.linkLootFont = status.linkLoot:CreateFontString()
status.linkLootFont:SetFont("Fonts/FRIZQT__.TTF",12)
status.linkLootFont:SetText("Link")
status.linkLoot:SetFontString(status.linkLootFont)
status.linkLoot:SetPoint("TOPLEFT", status, "TOPLEFT", 411, -28);

--BID LOOT BUTTON
status.bidLoot = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.bidLoot:SetSize(50, 22)
status.bidLoot:SetPoint("LEFT", status.distribute, "RIGHT")
status.bidLootFont = status.bidLoot:CreateFontString()
status.bidLootFont:SetFont("Fonts/FRIZQT__.TTF",12)
status.bidLootFont:SetText("Bid")
status.bidLoot:SetFontString(status.bidLootFont)
status.bidLoot:SetPoint("TOPLEFT", status, "TOPLEFT", 462, -28);
status.bidLoot:SetScript("OnClick", function() GDKPd:bidLoot_click(); end);

function GDKPd:bidLoot_click()
	
    local loot_select = status.BossLootTable:GetSelection();
    if (loot_select == nil) then
        GDKPd_Debug("No loot selected");
        return;
    end
    local lootnum = status.BossLootTable:GetCell(loot_select, 1);
	local link = GDKPd_PotData.curPotHistory[lootnum]["item"]
	GDKPd:DoAuction(link, lootnum)
    --LootAnnounce("RAID_WARNING", MRT_RaidLog[raidnum]["Loot"][lootnum]["ItemLink"], MRT_GUI_BossLootTable:GetCell(loot_select, 5))
end

--TRADE LOOT BUTTON
status.tradeLoot = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.tradeLoot:SetSize(50, 22)
status.tradeLoot:SetPoint("LEFT", status.distribute, "RIGHT")
status.tradeLootFont = status.tradeLoot:CreateFontString()
status.tradeLootFont:SetFont("Fonts/FRIZQT__.TTF",12)
status.tradeLootFont:SetText("Trade")
status.tradeLoot:SetFontString(status.tradeLootFont)
status.tradeLoot:SetPoint("TOPLEFT", status, "TOPLEFT", 512, -28);

--LOOT LINE
status.lootLine = status:CreateLine()
print(l)
status.lootLine :SetThickness(1)
status.lootLine :SetColorTexture(235,231,223,.5)
status.lootLine :SetStartPoint("TOPLEFT",205,-55)
status.lootLine :SetEndPoint("TOPLEFT",585,-55)

--NEW POT
status.reset = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.reset:SetSize(75, 22)
status.reset:SetPoint("LEFT", status, "TOPLEFT", 15, -30)
status.reset:SetText("New Pot")
status.reset:SetScript("OnClick", function(self)
	StaticPopup_Show("GDKPD_RESETPOT")
end)

--REMOVE POT
status.removePot = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.removePot:SetSize(22, 22)
status.removePot:SetPoint("LEFT", status.reset, "RIGHT")
status.removePot:SetText("-")
status.removePot:SetScript("OnClick", function(self)
--	StaticPopup_Show("GDKPD_RESETPOT")
end)

--OPTIONS
status.text = status:CreateFontString()
status.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
status.text:SetTextColor(1,1,1)
status.text:SetPoint("TOPLEFT", 15, -15)
status.text:SetJustifyH("LEFT")
status.options = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.options:SetSize(75, 22)
status.options:SetPoint("LEFT", status.removePot, "RIGHT")
status.options:SetText("Options")
status.options:SetScript("OnClick", function(self)
	LibStub("AceConfigDialog-3.0"):Open("GDKPd")
end)

--RAID LOG TABLE
local PotLogTableColDef = {
	{["name"] = "", ["width"] = 1}, --invisible item for pot index
    {["name"] = "Date", ["width"] = 75},
    {["name"] = "Name", ["width"] = 65},
};

status.PotLogTable = ScrollingTable:CreateST(PotLogTableColDef, 4, nil, nil, status);           
status.PotLogTable.head:SetHeight(15);                                                                    
status.PotLogTable.frame:SetPoint("TOPLEFT", status.reset, "TOPLEFT", 0, -45);
status.PotLogTable:EnableSelection(true);
status.PotLogTable:RegisterEvents({
	["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, coloumn, scrollingTable, button, ...)
	    doOnClick(rowFrame, cellFrame, data, cols, row, realrow, coloumn, scrollingTable, button, ...)  
    	GDKPd:PotChanged();
		return true
	end,
})

-- LINE BELOW POT LIST
local l = status:CreateLine()
print(l)
l:SetThickness(1)
l:SetColorTexture(235,231,223,.5)
l:SetStartPoint("TOPLEFT",20,-140)
l:SetEndPoint("TOPLEFT",185,-140)

-- POT FROM ITEMS
status.potItemsLabel = status:CreateFontString()
status.potItemsLabel:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
status.potItemsLabel:SetTextColor(1,1,1)
status.potItemsLabel:SetPoint("TOPLEFT", status.PotLogTable.frame, "TOPLEFT", 05, -88)
status.potItemsLabel:SetJustifyH("LEFT")
status.potItemsLabel:SetText("Item Spend:")

status.potItemsAmount = status:CreateFontString()
status.potItemsAmount:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
status.potItemsAmount:SetTextColor(1,1,1)
status.potItemsAmount:SetPoint("LEFT", status.potItemsLabel, "RIGHT", 15, 0)
status.potItemsAmount:SetJustifyH("LEFT")
status.potItemsAmount:SetText("10000g")

-- POT ADJUST
status.potAdjustLabel = status:CreateFontString()
status.potAdjustLabel:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
status.potAdjustLabel:SetTextColor(1,1,1)
status.potAdjustLabel:SetPoint("TOPLEFT", status.potItemsLabel, "BOTTOMLEFT", 0, -10)
status.potAdjustLabel:SetJustifyH("LEFT")
status.potAdjustLabel:SetText("Pot Adjust:")

status.potAdjustBox = CreateFrame("EditBox", nil, status, "InputBoxTemplate")
status.potAdjustBox:SetSize(75, 30)
status.potAdjustBox:SetAutoFocus(false) -- dont automatically focus
status.potAdjustBox:SetFontObject("ChatFontNormal")
status.potAdjustBox:SetPoint("LEFT", status.potAdjustLabel, "RIGHT", 10, 0);

-- POT TOTAL
status.potText = status:CreateFontString()
status.potText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
status.potText:SetTextColor(1,1,1)
status.potText:SetPoint("TOPLEFT", status.potAdjustLabel, "BOTTOMLEFT", 0, -10)
status.potText:SetJustifyH("LEFT")

status.potDistributeText = status:CreateFontString()
status.potDistributeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
status.potDistributeText:SetTextColor(1,1,1)
status.potDistributeText:SetPoint("TOPLEFT", status.potText, "BOTTOMLEFT", 0, -10)
status.potDistributeText:SetJustifyH("LEFT")

-- LINE ABOVE ATTENDEE LIST
local l = status:CreateLine()
print(l)
l:SetThickness(1)
l:SetColorTexture(235,231,223,.5)
l:SetStartPoint("TOPLEFT",20,-240)
l:SetEndPoint("TOPLEFT",185,-240)

-- ADD/ REMOVE GOLD
--[[status.add = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.add:SetSize(15,15)
status.add:SetPoint("LEFT", status, "TOPLEFT",10,-200)
status.add:SetText("+")
status.add:SetScript("OnClick", function(self)
	StaticPopup_Show("GDKPD_ADDTOPOT")
end)
status.rem = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.rem:SetSize(15,15)
status.rem:SetPoint("LEFT", status.add, "RIGHT")
status.rem:SetText("-")
status.rem:SetScript("OnClick", function(self)
	StaticPopup_Show("GDKPD_REMFROMPOT")
end)
--]]

--POST RULES
status.rules = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.rules:SetSize(90, 22)
status.rules:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 15, 245)
status.rules:SetText("Post rules")
status.rules:SetScript("OnClick",function()
	local announceStrings = emptytable("")
	for line in string.gmatch(GDKPd.opt.rulesString,"[^\n]+") do
		for word in string.gmatch(line, "%S+") do
			if strlen(announceStrings[#announceStrings])+1+strlen(word) > 255 then
				tinsert(announceStrings, word)
			else
				if strlen(announceStrings[#announceStrings]) > 0 then
					announceStrings[#announceStrings] = announceStrings[#announceStrings].." "..word
				else
					announceStrings[#announceStrings] = word
				end
			end
		end
		tinsert(announceStrings, "")
	end
	for _, msg in ipairs(announceStrings) do
		SendChatMessage(msg, "RAID")
	end
	announceStrings:Release()
end)
status.rules:Disable()

--DISTRIBUTE 
status.text = status:CreateFontString()
status.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
status.text:SetTextColor(1,1,1)
--status.text:SetPoint("TOPLEFT", 15, -15)
status.text:SetJustifyH("LEFT")
status.distribute = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.distribute:SetSize(80, 22)
status.distribute:SetPoint("LEFT", status.rules, "RIGHT")
status.distribute:SetText("Distribute")
status.distribute:SetScript("OnClick", function(self)
	GDKPd:DistributePot()
end)

--ATTENDEES TABLE
local GDKPd_RaidAttendeesTableColDef = {
    {["name"] = "", ["width"] = 1},                            -- invisible column for storing the player number index from the raidlog-table
    {["name"] = "Name", ["width"] = 100},
    {["name"] = "$$$", ["width"] = 40},
};

MRT_GUI_AttendeesTable = ScrollingTable:CreateST(GDKPd_RaidAttendeesTableColDef,18, 10, nil, status);           
MRT_GUI_AttendeesTable.head:SetHeight(15);                                                                    
MRT_GUI_AttendeesTable.frame:SetPoint("TOPLEFT", status.rules, "BOTTOMLEFT", 0 , -20);
MRT_GUI_AttendeesTable:EnableSelection(true);

--SHOW AUCTION HISTORY
--[[status.itemhistory = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.itemhistory:SetSize(170, 15)
status.itemhistory:SetPoint("TOPLEFT", status.rules, "BOTTOMLEFT")
status.itemhistory:SetText(L["Auction history"])
status.itemhistory:SetScript("OnEnter", function(self)
	GameTooltip:ClearAllPoints()
	GameTooltip:ClearLines()
	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:AddLine(L["GDKPd auction history"],1,1,1)
	for _, aucdata in ipairs(GDKPd_PotData.curPotHistory) do
		if type(aucdata) == "table" then
			GameTooltip:AddDoubleLine("|T"..GetItemIcon(aucdata.item)..":12|t "..aucdata.item, aucdata.name.." ("..aucdata.bid.."|cffffd100g|r)",1,1,1,1,1,1)
		else
			GameTooltip:AddDoubleLine("|T:12|t "..L["Manual adjustment"], (aucdata > 0 and "+" or "")..aucdata.."|cffffd100g|r",1,1,1,1,1,1)
		end
	end
	GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 5)
	GameTooltip:Show()
end)
status.itemhistory:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)
status.itemhistory:SetScript("OnClick", function()
	GDKPd.history:Show()
end)
--]]

--ANNOUCE - LEGACY
status.announcetext = status:CreateFontString()
status.announcetext:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
status.announcetext:SetTextColor(1,1,1)
status.announcetext:SetPoint("TOPLEFT", status.itemhistory, "BOTTOMLEFT", 0, -5)
status.announcetext:SetJustifyH("LEFT")
status.announcetext:SetText(L["You have looted a monster!\nDo you want GDKPd to announce loot?"])
status.announcetext:Hide()
status.announce1 = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.announce1:SetSize(170,15)
status.announce1:SetPoint("TOPLEFT", status.announcetext, "BOTTOMLEFT", 0, -5)
status.announce1:SetText(L["Announce & auto-auction"])
status.announce1:SetScript("OnClick", function(self)
	GDKPd:AnnounceLoot(true)
	status.announcetext:Hide()
	self:Hide()
	status.announce2:Hide()
	status.noannounce:Hide()
	status:UpdateSize()
end)
status.announce1:Hide()
status.announce2 = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.announce2:SetSize(170,15)
status.announce2:SetPoint("TOPLEFT", status.announce1, "BOTTOMLEFT", 0, -5)
status.announce2:SetText(L["Announce loot"])
status.announce2:SetScript("OnClick", function(self)
	GDKPd:AnnounceLoot(false)
	status.announcetext:Hide()
	status.announce1:Hide()
	self:Hide()
	status.noannounce:Hide()
	status:UpdateSize()
end)
status.announce2:Hide()
status.noannounce = CreateFrame("Button", nil, status, "UIPanelButtonTemplate")
status.noannounce:SetSize(170,15)
status.noannounce:SetPoint("TOPLEFT", status.announce2, "BOTTOMLEFT", 0, -5)
status.noannounce:SetText(L["Do not announce"])
status.noannounce:SetScript("OnClick", function(self)
	status.announcetext:Hide()
	status.announce1:Hide()
	status.announce2:Hide()
	self:Hide()
	status:UpdateSize()
end)
status.noannounce:Hide()
function status:UpdateSize()
	local height = 480
	height = height+status.text:GetHeight()
	if status.announcetext:IsShown() then
		height=height+status.announcetext:GetHeight()+5
	end
	if status.announce1:IsShown() then
		height=height+20
	end
	if status.announce2:IsShown() then
		height=height+20
	end
	if status.noannounce:IsShown() then
		height=height+20
	end
	self:SetHeight(height)
end


--------------------------------------------------------------------
--- HISTORY FRAME
--------------------------------------------------------------------
GDKPd.history = CreateFrame("Frame", "GDKPd_History", UIParent)
local history = GDKPd.history
history:SetSize(200,95)
history:Hide()
history:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
history.header = CreateFrame("Button", nil, history)
history.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
history.header:SetSize(133,34)
history.header:SetHitRectInsets(31.5,31.5,4.5,14.5)
history.header.text = history.header:CreateFontString()
history.header.text:SetPoint("TOP",0,-7)
history.header.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
history.header.text:SetTextColor(1,1,1)
history.header.text:SetText(L["History"])
history.header:SetMovable(true)
history.header:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
history.header:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
end)
history.header:SetPoint("CENTER",UIParent,"CENTER")
history:SetPoint("TOP", history.header, "TOP", 0, -6)
history:SetScript("OnShow", function(self)
	self:Update()
end)
history.entries = setmetatable({},{__index=function(t,v)
	local f = CreateFrame("Button", nil, history)
	if v > 1 then
		f:SetPoint("TOPLEFT", t[v-1], "BOTTOMLEFT", 0, -5)
		f:SetPoint("TOPRIGHT", t[v-1], "BOTTOMRIGHT", 0, -5)
	else
		f:SetPoint("TOPLEFT", 15, -15)
		f:SetPoint("TOPRIGHT", -15, -15)
	end
	function f:UpdateHeight()
		self:SetHeight(f.date:GetHeight())
	end
	f.date = f:CreateFontString()
	f.date:SetFont("Fonts\\FRIZQT__.TTF", 8,"")
	f.date:SetTextColor(1,1,1)
	f.date:SetPoint("TOPLEFT")
	f.date:SetWidth(55)
	f.amount = f:CreateFontString()
	f.amount:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
	f.amount:SetTextColor(1,1,1)
	f.amount:SetPoint("TOPLEFT", f.date, "TOPRIGHT", 5, 0)
	f.amount:SetPoint("BOTTOMLEFT", f.date, "BOTTOMRIGHT", 5, 0)
	f.amount:SetWidth(40)
	f.amount:SetJustifyH("RIGHT")
	f.note = f:CreateFontString()
	f.note:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
	f.note:SetTextColor(1,1,1)
	f.note:SetPoint("BOTTOMLEFT", f.amount, "BOTTOMRIGHT", 5, 0)
	f.note:SetPoint("TOPRIGHT")
	f.note:SetJustifyH("LEFT")
	function f:SetDataTable(data)
		self.date:SetText(data.date:match("%S+"))
		self.rawdate = data.date
		self.amount:SetText(data.size.."|cffffd100g|r")
		self.rawamount = data.size
		self.note:SetText(data.note)
		self.itemtable = data.items
		self.data = data
		self:UpdateHeight()
	end
	function f:SetRawData(date,amount,note,items)
		self.date:SetText(date)
		self.rawdate = date
		self.amount:SetText(amount.."|cffffd100g|r")
		self.rawamount = amount
		self.note:SetText(note)
		self.itemtable = items
		self:UpdateHeight()
	end
	f:SetScript("OnEnter", function(self)
		GameTooltip:ClearAllPoints()
		GameTooltip:ClearLines()
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		if self.itemtable then
			GameTooltip:AddLine(L["GDKPd auction history for %s"]:format(self.rawdate),1,1,1)
			if self.note:GetText() then
				GameTooltip:AddLine(L["Auction note: %s"]:format(self.note:GetText()),1,1,1)
			end
			for _, aucdata in ipairs(self.itemtable) do
				if type(aucdata) == "table" then
					GameTooltip:AddDoubleLine("|T"..GetItemIcon(aucdata.item)..":12|t "..aucdata.item, aucdata.name.." ("..aucdata.bid.."|cffffd100g|r)",1,1,1,1,1,1)
				else
					GameTooltip:AddDoubleLine("|T:12|t "..L["Manual adjustment"], (aucdata > 0 and "+" or "")..aucdata.."|cffffd100g|r",1,1,1,1,1,1)
				end
			end
		else
			GameTooltip:AddLine(L["GDKPd: No detailed data available"],1,1,1)
		end
		GameTooltip:SetPoint("TOPRIGHT", self, "LEFT", -5, 0)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)
	f:SetScript("OnClick", function(self)
		ClearCursor()
		if self.data then
			StaticPopup_Show("GDKPD_HISTORYCLICK", L["You have selected the following pot:\n%s, dated %s, size %d gold.\nWhat do you want to do with this pot?"]:format(self.note:GetText(), self.date:GetText(), self.rawamount)).data = self.data
		else
			StaticPopup_Show("GDKPD_CURPOTCLICK", GDKPd_PotData.potAmount)
		end
	end)
	t[v]=f
	return f
end})
history.hide = CreateFrame("Button", nil, history, "UIPanelButtonTemplate")
history.hide:SetSize(170,15)
history.hide:SetPoint("BOTTOM", 0, 15)
history.hide:SetText(L["Hide"])
history.hide:SetScript("OnClick", function() history:Hide() end)
function history:Update()
	for _, f in ipairs(self.entries) do
		f:Hide()
	end
	local c = 1
	local size = 45
	for _, potdata in ipairs(GDKPd_PotData.history) do
		local f = self.entries[c]
		f:Show()
		f:SetDataTable(potdata)
		size=size+f:GetHeight()+5
		c=c+1
	end
	if GDKPd_PotData.potAmount > 0 then
		local f = self.entries[c]
		f:Show()
		f:SetRawData("Current pot", GDKPd_PotData.potAmount, nil, GDKPd_PotData.curPotHistory)
		size=size+f:GetHeight()+5
		c=c+1
	end
	self:SetHeight(size)
end
GDKPd.itemsettings = CreateFrame("Frame", "GDKPd_ItemSettings", UIParent)
local itemsettings = GDKPd.itemsettings
itemsettings:SetWidth(250)
itemsettings:Hide()
itemsettings:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
itemsettings.header = CreateFrame("Button", nil, itemsettings)
itemsettings.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
itemsettings.header:SetSize(133,34)
itemsettings.header:SetHitRectInsets(31.5,31.5,4.5,14.5)
itemsettings.header.text = itemsettings.header:CreateFontString()
itemsettings.header.text:SetPoint("TOP", 0, -7)
itemsettings.header.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
itemsettings.header.text:SetTextColor(1,1,1)
itemsettings.header.text:SetText(L["Item settings"])
itemsettings.header:SetMovable(true)
itemsettings.header:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
itemsettings.header:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
end)
itemsettings.header:SetPoint("CENTER", UIParent, "CENTER")
itemsettings:SetPoint("TOP", itemsettings.header, "TOP", 0, -6)
itemsettings:SetScript("OnShow", function(self)
	self:Update()
end)
itemsettings.thead = CreateFrame("Frame", nil, itemsettings)
itemsettings.thead:SetPoint("TOPLEFT", 15, -15)
itemsettings.thead:SetPoint("TOPRIGHT", -15, -15)
itemsettings.thead:SetHeight(15)
itemsettings.thead.item = itemsettings.thead:CreateFontString()
itemsettings.thead.item:SetFont("Fonts\\FRIZQT__.TTF", 10)
itemsettings.thead.item:SetTextColor(1,0.82,0)
--itemsettings.thead.item:SetText(L["Itm"])
itemsettings.thead.item:SetPoint("LEFT")
itemsettings.thead.item:SetWidth(15)
itemsettings.thead.startbid = itemsettings.thead:CreateFontString()
itemsettings.thead.startbid:SetFont("Fonts\\FRIZQT__.TTF", 10)
itemsettings.thead.startbid:SetTextColor(1,0.82,0)
itemsettings.thead.startbid:SetText(L["Starting bid"])
itemsettings.thead.startbid:SetPoint("LEFT", itemsettings.thead.item, "RIGHT")
itemsettings.thead.startbid:SetWidth(102.5)
itemsettings.thead.minincre = itemsettings.thead:CreateFontString()
itemsettings.thead.minincre:SetFont("Fonts\\FRIZQT__.TTF", 10)
itemsettings.thead.minincre:SetTextColor(1,0.82,0)
itemsettings.thead.minincre:SetText(L["Minimum increment"])
itemsettings.thead.minincre:SetPoint("LEFT", itemsettings.thead.startbid, "RIGHT")
itemsettings.thead.minincre:SetPoint("RIGHT")
itemsettings.scroll = CreateFrame("ScrollFrame", nil, itemsettings)
itemsettings.scroll:SetPoint("TOPLEFT", itemsettings.thead, "BOTTOMLEFT", 0, -5)
itemsettings.scroll.child = CreateFrame("Frame", nil, itemsettings.scroll)
itemsettings.scroll.child:EnableMouseWheel(true)
itemsettings.scroll.child:SetScript("OnMouseWheel", function(self, delta)
	if delta == 1 then
		itemsettings.scroll:SetVerticalScroll(math.max(itemsettings.scroll:GetVerticalScroll()-10,0))
	else
		itemsettings.scroll:SetVerticalScroll(math.min(itemsettings.scroll:GetVerticalScroll()+10,itemsettings.scroll:GetVerticalScrollRange()))
	end
end)
itemsettings.scroll.child:SetWidth(itemsettings.scroll:GetWidth())
itemsettings.scroll:SetScrollChild(itemsettings.scroll.child)
itemsettings.scroll:SetScript("OnSizeChanged", function(self, width)
	self.child:SetWidth(width)
	self:UpdateScrollChildRect()
end)
itemsettings.entries = setmetatable({}, {__index=function(t,v)
	local f = CreateFrame("Frame", nil, itemsettings.scroll.child)
	if v > 1 then
		f:SetPoint("TOPLEFT", t[v-1], "BOTTOMLEFT", 0, -5)
		f:SetPoint("TOPRIGHT", t[v-1], "BOTTOMRIGHT", 0, -5)
	else
		f:SetPoint("TOPLEFT"--[[, itemsettings.thead, "BOTTOMLEFT", 0, -5--]])
		f:SetPoint("TOPRIGHT"--[[, itemsettings.thead, "BOTTOMRIGHT", 0, -5--]])
	end
	f:SetHeight(15)
	f.itemicon = CreateFrame("Button", nil, f)
	f.itemicon:SetScript("OnEnter", function()
		if not f.itemID then return end
		GameTooltip:ClearAllPoints()
		GameTooltip:ClearLines()
		GameTooltip:SetOwner(f, "ANCHOR_NONE")
		GameTooltip:SetHyperlink("item:"..f.itemID)
		GameTooltip:SetPoint("RIGHT", itemsettings, "LEFT", -5, 0)
		GameTooltip:Show()
	end)
	f.itemicon:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	f.itemicon:SetSize(15,15)
	f.itemicon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	f.itemicon:SetPoint("LEFT")
	f.itemicon:SetScript("OnMouseUp", function(self)
		if (select(1,GetCursorInfo())) == "item" then
			local id = (select(2, GetCursorInfo()))
			if GDKPd.opt.customItemSettings[id] then ClearCursor() return end
			if f.itemID then
				GDKPd.opt.customItemSettings[id] = GDKPd.opt.customItemSettings[f.itemID]
				GDKPd.opt.customItemSettings[f.itemID] = nil
			else
				GDKPd.opt.customItemSettings[id] = {}
			end
			ClearCursor()
			itemsettings:Update()
		else
			if f.itemID then
				local cis = GDKPd.opt.customItemSettings[f.itemID]
				if cis.minBid or cis.minIncrement then
					PickupItem(f.itemID)
				else
					GDKPd.opt.customItemSettings[f.itemID] = nil
					itemsettings:Update()
				end
			else
				StaticPopup_Show("GDKPD_CUSTOMSETTINGSID")
			end
		end
	end)
	f.itemicon:EnableMouse(true)
	f.minBid = CreateFrame("EditBox", nil, f)
	f.minBid:SetMultiLine(nil)
	f.minBid:SetScript("OnEditFocusGained", function(self) if not f.itemID then self:ClearFocus() end end)
	f.minBid:SetScript("OnEnterPressed", function(self) GDKPd.opt.customItemSettings[f.itemID].minBid = self:GetNumber() > 0 and self:GetNumber() or nil self:ClearFocus() itemsettings:Update() end)
	f.minBid:SetScript("OnEscapePressed", function(self) self:SetNumber(GDKPd.opt.customItemSettings[f.itemID].minBid) self:ClearFocus() end)
	f.minBid:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.minBid:SetTextColor(1,1,1)
	f.minBid:SetPoint("TOPLEFT", f.itemicon, "TOPRIGHT")
	f.minBid:SetPoint("BOTTOMLEFT", f.itemicon, "BOTTOMRIGHT")
	f.minBid:SetJustifyH("RIGHT")
	f.minBid:SetAutoFocus(false)
	f.minBid:SetWidth(102.5)
	f.minBid:SetTextInsets(5,5,2,2)
	f.minBid:SetNumeric(true)
	f.minBid:SetScript("OnTextChanged", function(self, userInput)
		if strlen(self:GetText()) > 0 then
			self.g:Show()
		else
			self.g:Hide()
		end
	end)
	f.minBid.g = f:CreateFontString()
	f.minBid.g:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.minBid.g:SetTextColor(1,0.82,0)
	f.minBid.g:SetText("g")
	f.minBid.g:SetPoint("TOPRIGHT", f.itemicon, "TOPRIGHT", 102.5, 0)
	f.minBid.g:SetPoint("BOTTOMRIGHT", f.itemicon, "BOTTOMRIGHT", 102.5, 0)
	f.minBid:SetPoint("RIGHT", f.minBid.g, "LEFT")
	f.minBid.tex = f:CreateTexture(nil,"BACKGROUND")
	f.minBid.tex:SetPoint("TOPLEFT",f.minBid,20,0)
	f.minBid.tex:SetPoint("BOTTOMRIGHT",f.minBid.g)
	f.minBid.tex:SetAlpha(0.2)
	f.minBid.tex:SetTexture(0.5,0.5,0.5)
	f.minIncrement = CreateFrame("EditBox", nil, f)
	f.minIncrement:SetMultiLine(nil)
	f.minIncrement:SetScript("OnEditFocusGained", function(self) if not f.itemID then self:ClearFocus() end end)
	f.minIncrement:SetScript("OnEnterPressed", function(self) GDKPd.opt.customItemSettings[f.itemID].minIncrement = self:GetNumber() > 0 and self:GetNumber() or nil self:ClearFocus() itemsettings:Update() end)
	f.minIncrement:SetScript("OnEscapePressed", function(self) if GDKPd.opt.customItemSettings[f.itemID].minIncrement then self:SetNumber(GDKPd.opt.customItemSettings[f.itemID].minIncrement) else self:SetText("") end self:ClearFocus() end)
	f.minIncrement:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.minIncrement:SetTextColor(1,1,1)
	f.minIncrement:SetPoint("TOPLEFT", f.minBid.g, "TOPRIGHT")
	f.minIncrement:SetPoint("BOTTOMLEFT", f.minBid.g, "BOTTOMRIGHT")
	f.minIncrement:SetJustifyH("RIGHT")
	f.minIncrement:SetAutoFocus(false)
	--f.minIncrement:Setp(102.5)
	f.minIncrement:SetTextInsets(5,5,2,2)
	f.minIncrement:SetScript("OnTextChanged", function(self, userInput)
		if strlen(self:GetText()) > 0 then
			self.g:Show()
		else
			self.g:Hide()
		end
	end)
	f.minIncrement.g = f:CreateFontString()
	f.minIncrement.g:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.minIncrement.g:SetTextColor(1,0.82,0)
	f.minIncrement.g:SetText("g")
	f.minIncrement.g:SetPoint("TOPRIGHT", f.minBid.g, "TOPRIGHT", 102.5, 0)
	f.minIncrement.g:SetPoint("BOTTOMRIGHT", f.minBid.g, "BOTTOMRIGHT", 102.5, 0)
	f.minIncrement:SetPoint("TOPRIGHT", f.minIncrement.g, "TOPLEFT")
	f.minIncrement:SetPoint("BOTTOMRIGHT", f.minIncrement.g, "BOTTOMLEFT")
	f.minIncrement.tex = f:CreateTexture(nil,"BACKGROUND")
	f.minIncrement.tex:SetPoint("TOPLEFT",f.minIncrement,20,0)
	f.minIncrement.tex:SetPoint("BOTTOMRIGHT",f.minIncrement.g,"BOTTOMRIGHT")
	f.minIncrement.tex:SetAlpha(0.2)
	f.minIncrement.tex:SetTexture(0.5,0.5,0.5)
	function f:SetItemID(itemID)
		if (not itemID) or (not GDKPd.opt.customItemSettings[itemID]) then
			self.itemicon:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
			self.minBid:SetText("")
			self.minIncrement:SetText("")
			self.itemID = nil
		else
			self.itemicon:SetNormalTexture((select(10, GetItemInfo(itemID))))
			if GDKPd.opt.customItemSettings[itemID].minBid then
				self.minBid:SetText(GDKPd.opt.customItemSettings[itemID].minBid)
			else
				self.minBid:SetText("")
			end
			if GDKPd.opt.customItemSettings[itemID].minIncrement then
				self.minIncrement:SetText(GDKPd.opt.customItemSettings[itemID].minIncrement)
			else
				self.minIncrement:SetText("")
			end
			self.itemID = itemID
		end
	end
	t[v] = f
	return f
end})
function itemsettings:Update()
	for _, btn in ipairs(self.entries) do btn:Hide() end
	local f = self.entries[1]
	f:Show()
	f:SetItemID()
	local c = 2
	for iID in pairs(GDKPd.opt.customItemSettings) do
		f = self.entries[c]
		f:Show()
		f:SetItemID(iID)
		c=c+1
	end
	self.scroll.child:SetHeight(20*(c-1)-5)
	self:SetHeight(70+20*math.min(c-1,10))
end
itemsettings.hide = CreateFrame("Button", nil, itemsettings, "UIPanelButtonTemplate")
itemsettings.hide:SetSize(220, 15)
itemsettings.hide:SetPoint("BOTTOM", 0, 15)
itemsettings.hide:SetText(L["Hide"])
itemsettings.hide:SetScript("OnClick", function() itemsettings:Hide() end)
itemsettings.scroll:SetPoint("BOTTOMRIGHT", itemsettings.hide, "TOPRIGHT", 0, 10)
GDKPd.itemLevels = CreateFrame("Frame", "GDKPd_ItemLevels", UIParent)
local itemlevels = GDKPd.itemLevels
itemlevels:SetWidth(250)
itemlevels:Hide()
itemlevels:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
itemlevels.header = CreateFrame("Button", nil, itemlevels)
itemlevels.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
itemlevels.header:SetSize(133,34)
itemlevels.header:SetHitRectInsets(31.5,31.5,4.5,14.5)
itemlevels.header.text = itemlevels.header:CreateFontString()
itemlevels.header.text:SetPoint("TOP", 0, -7)
itemlevels.header.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
itemlevels.header.text:SetTextColor(1,1,1)
itemlevels.header.text:SetText(L["iLvL ranges"])
itemlevels.header:SetMovable(true)
itemlevels.header:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
itemlevels.header:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
end)
itemlevels.header:SetPoint("CENTER", UIParent, "CENTER")
itemlevels:SetPoint("TOP", itemlevels.header, "TOP", 0 ,-6)
itemlevels:SetScript("OnShow", function(self)
	self:Update()
end)
itemlevels.thead = CreateFrame("Frame", nil, itemlevels)
itemlevels.thead:SetPoint("TOPLEFT", 15, -15)
itemlevels.thead:SetPoint("TOPRIGHT", -15, -15)
itemlevels.thead:SetHeight(15)
itemlevels.thead.min = itemlevels.thead:CreateFontString()
itemlevels.thead.min:SetFont("Fonts\\FRIZQT__.TTF", 10)
itemlevels.thead.min:SetTextColor(1,0.82,0)
itemlevels.thead.min:SetPoint("LEFT")
itemlevels.thead.min:SetWidth(25)
itemlevels.thead.min:SetText("Min")
itemlevels.thead.max = itemlevels.thead:CreateFontString()
itemlevels.thead.max:SetFont("Fonts\\FRIZQT__.TTF", 10)
itemlevels.thead.max:SetTextColor(1,0.82,0)
itemlevels.thead.max:SetPoint("LEFT", itemlevels.thead.min, "RIGHT", 5, 0)
itemlevels.thead.max:SetWidth(25)
itemlevels.thead.max:SetText("Max")
itemlevels.thead.minbid = itemlevels.thead:CreateFontString()
itemlevels.thead.minbid:SetFont("Fonts\\FRIZQT__.TTF", 10)
itemlevels.thead.minbid:SetTextColor(1,0.82,0)
itemlevels.thead.minbid:SetPoint("LEFT", itemlevels.thead.max, "RIGHT", 5, 0)
itemlevels.thead.minbid:SetWidth(60)
itemlevels.thead.minbid:SetText(L["Starting bid"])
itemlevels.thead.mininc = itemlevels.thead:CreateFontString()
itemlevels.thead.mininc:SetFont("Fonts\\FRIZQT__.TTF", 10)
itemlevels.thead.mininc:SetTextColor(1,0.82,0)
itemlevels.thead.mininc:SetPoint("LEFT", itemlevels.thead.minbid, "RIGHT", 5, 0)
itemlevels.thead.mininc:SetWidth(80)
itemlevels.thead.mininc:SetText(L["Min increment"])
itemlevels.hide = CreateFrame("Button", nil, itemlevels, "UIPanelButtonTemplate")
itemlevels.hide:SetSize(220,15)
itemlevels.hide:SetPoint("BOTTOM", 0, 15)
itemlevels.hide:SetText(L["Hide"])
itemlevels.hide:SetScript("OnClick", function() itemlevels:Hide() end)
itemlevels.add = CreateFrame("Frame", nil, itemlevels)
itemlevels.add:SetPoint("BOTTOMLEFT", 15, 35)
itemlevels.add:SetPoint("BOTTOMRIGHT", -15, 35)
itemlevels.add:SetHeight(20)
local tablist = {"GDKPdItemLevelFrameAddEditBoxMinItemLevel","GDKPdItemLevelFrameAddEditBoxMaxItemLevel","GDKPdItemLevelFrameAddEditBoxMinBid","GDKPdItemLevelFrameAddEditBoxMinIncrement"}
local tabfunc = function(self) EditBox_HandleTabbing(self, tablist) end
itemlevels.add.min = CreateFrame("EditBox", "GDKPdItemLevelFrameAddEditBoxMinItemLevel", itemlevels.add, "InputBoxTemplate")
itemlevels.add.min:SetAutoFocus(false)
itemlevels.add.min:SetPoint("TOPLEFT",2.5,0)
itemlevels.add.min:SetPoint("BOTTOMLEFT",2.5,0)
itemlevels.add.min:SetWidth(25)
itemlevels.add.min:SetNumeric(true)
itemlevels.add.min:SetScript("OnEnterPressed", itemlevels.add.min:GetScript("OnEscapePressed"))
itemlevels.add.min:SetMaxLetters(3)
itemlevels.add.min:SetScript("OnTabPressed", tabfunc)
--itemlevels.add.min:SetJustifyH("RIGHT")
itemlevels.add.max = CreateFrame("EditBox", "GDKPdItemLevelFrameAddEditBoxMaxItemLevel", itemlevels.add, "InputBoxTemplate")
itemlevels.add.max:SetAutoFocus(false)
itemlevels.add.max:SetPoint("TOPLEFT", itemlevels.add.min, "TOPRIGHT", 5, 0)
itemlevels.add.max:SetPoint("BOTTOMLEFT", itemlevels.add.min, "BOTTOMRIGHT", 5, 0)
--itemlevels.add.max:SetPoint("TOPLEFT", 30, 0)
--itemlevels.add.max:SetPoint("BOTTOMLEFT", 30, 0)
itemlevels.add.max:SetWidth(25)
itemlevels.add.max:SetScript("OnEnterPressed", itemlevels.add.max:GetScript("OnEscapePressed"))
itemlevels.add.max:SetNumeric(true)
itemlevels.add.max:SetMaxLetters(3)
itemlevels.add.max:SetScript("OnTabPressed", tabfunc)
--itemlevels.add.max:SetJustifyH("RIGHT")
itemlevels.add.minbid = CreateFrame("EditBox", "GDKPdItemLevelFrameAddEditBoxMinBid", itemlevels.add, "InputBoxTemplate")
itemlevels.add.minbid:SetAutoFocus(false)
itemlevels.add.minbid:SetPoint("TOPLEFT", itemlevels.add.max, "TOPRIGHT", 5, 0)
itemlevels.add.minbid:SetPoint("BOTTOMLEFT", itemlevels.add.max, "BOTTOMRIGHT", 5, 0)
itemlevels.add.minbid:SetWidth(60)
itemlevels.add.minbid:SetScript("OnEnterPressed", itemlevels.add.minbid:GetScript("OnEscapePressed"))
itemlevels.add.minbid:SetNumeric(true)
itemlevels.add.minbid:SetMaxLetters(6)
itemlevels.add.minbid:SetScript("OnTabPressed", tabfunc)
--itemlevels.add.minbid:SetJustifyH("RIGHT")
itemlevels.add.mininc = CreateFrame("EditBox", "GDKPdItemLevelFrameAddEditBoxMinIncrement", itemlevels.add, "InputBoxTemplate")
itemlevels.add.mininc:SetAutoFocus(false)
itemlevels.add.mininc:SetPoint("TOPLEFT", itemlevels.add.minbid, "TOPRIGHT", 5, 0)
itemlevels.add.mininc:SetPoint("BOTTOMLEFT", itemlevels.add.minbid, "BOTTOMRIGHT", 5, 0)
itemlevels.add.mininc:SetWidth(80)
itemlevels.add.mininc:SetScript("OnEnterPressed", itemlevels.add.mininc:GetScript("OnEscapePressed"))
itemlevels.add.mininc:SetNumeric(true)
itemlevels.add.mininc:SetMaxLetters(5)
itemlevels.add.mininc:SetScript("OnTabPressed", tabfunc)
--itemlevels.add.mininc:SetJustifyH("RIGHT")
itemlevels.add.add = CreateFrame("Button", nil, itemlevels.add)
itemlevels.add.add:SetSize(20,20)
itemlevels.add.add:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
itemlevels.add.add:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
itemlevels.add.add:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
itemlevels.add.add:SetPoint("RIGHT", 5, 0)
itemlevels.add.add:SetScript("OnClick", function()
	local minl = itemlevels.add.min:GetNumber()
	local maxl = itemlevels.add.max:GetNumber()
	local minbid = itemlevels.add.minbid:GetNumber()
	local mininc = itemlevels.add.mininc:GetNumber()
	if minbid ~= 0 and mininc ~= 0 then
		tinsert(GDKPd.opt.itemLevelPricing, {min=minl, max=maxl, minbid=minbid, mininc=mininc})
		itemlevels:Update()
		itemlevels.add.min:SetText("")
		itemlevels.add.max:SetText("")
		itemlevels.add.minbid:SetText("")
		itemlevels.add.mininc:SetText("")
	end
end)
itemlevels.entries = setmetatable({}, {__index=function(t,v)
	local f = CreateFrame("Frame", nil, itemlevels)
	if v > 1 then
		f:SetPoint("TOPLEFT", t[v-1], "BOTTOMLEFT", 0, -5)
		f:SetPoint("TOPRIGHT", t[v-1], "BOTTOMRIGHT", 0, -5)
	else
		f:SetPoint("TOPLEFT", itemlevels.thead, "BOTTOMLEFT", 0, -5)
		f:SetPoint("TOPRIGHT", itemlevels.thead, "BOTTOMRIGHT", 0, -5)
	end
	f:SetHeight(15)
	f.min = f:CreateFontString()
	f.min:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.min:SetTextColor(1,1,1)
	f.min:SetPoint("LEFT")
	f.min:SetWidth(25)
	f.min:SetJustifyH("RIGHT")
	f.max = f:CreateFontString()
	f.max:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.max:SetTextColor(1,1,1)
	f.max:SetPoint("LEFT", f.min, "RIGHT", 5, 0)
	f.max:SetWidth(25)
	f.max:SetJustifyH("RIGHT")
	f.minbid = f:CreateFontString()
	f.minbid:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.minbid:SetTextColor(1,1,1)
	f.minbid:SetPoint("LEFT", f.max, "RIGHT", 5, 0)
	f.minbid:SetWidth(60)
	f.minbid:SetJustifyH("RIGHT")
	f.mininc = f:CreateFontString()
	f.mininc:SetFont("Fonts\\FRIZQT__.TTF", 10)
	f.mininc:SetTextColor(1,1,1)
	f.mininc:SetPoint("LEFT", f.minbid, "RIGHT", 5, 0)
	f.mininc:SetWidth(80)
	f.mininc:SetJustifyH("RIGHT")
	function f:SetValues(min, max, minbid, mininc)
		self.min:SetText(min)
		self.max:SetText(max)
		self.minbid:SetText(minbid.."|cffffd100g|r")
		self.mininc:SetText(mininc.."|cffffd100g|r")
	end
	f.del = CreateFrame("Button", nil, f)
	f.del:SetSize(15,15)
	f.del:SetPoint("RIGHT", 5, 0)
	f.del:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
	--minus uses pluses' highlight
	f.del:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
	f.del:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-DOWN")
	f.del:SetScript("OnClick", function()
		tremove(GDKPd.opt.itemLevelPricing, v)
		itemlevels:Update()
	end)
	t[v] = f
	return f
end})
function itemlevels:Update()
	--self:SetHeight(100)
	-- 30 borders
	-- 5 list
	-- 15 thead
	for _, f in ipairs(self.entries) do f:Hide() end
	local height = 95
	for num, data in ipairs(GDKPd.opt.itemLevelPricing) do
		local f = self.entries[num]
		f:Show()
		f:SetValues(data.min, data.max, data.minbid, data.mininc)
		height=height+20
	end
	self:SetHeight(height)
end
GDKPd.version = CreateFrame("Frame", "GDKPd_Versions", UIParent)
local version = GDKPd.version
version:SetSize(200,85)
version:Hide()
version:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
version.header = CreateFrame("Button", nil, version)
version.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
version.header:SetSize(133,34)
version.header:SetHitRectInsets(31.5,31.5,4.5,14.5)
version.header.text = version.header:CreateFontString()
version.header.text:SetPoint("TOP", 0, -7)
version.header.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
version.header.text:SetTextColor(1,1,1)
version.header.text:SetText(L["Versions"])
version.header:SetMovable(true)
version.header:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
version.header:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
end)
version.header:SetPoint("CENTER", UIParent, "CENTER")
version:SetPoint("TOP", version.header, "TOP", 0, -6)
version:SetScript("OnShow", function(self)
	self:Update()
end)
version.entries = setmetatable({},{__index=function(t,v)
	local f = CreateFrame("Button", nil, version)
	if v > 1 then
		f:SetPoint("TOPLEFT", t[v-1], "BOTTOMLEFT", 0, -5)
		f:SetPoint("TOPRIGHT", t[v-1], "BOTTOMRIGHT", 0, -5)
	else
		f:SetPoint("TOPLEFT", 15, -15)
		f:SetPoint("TOPRIGHT", -15, -15)
	end
	function f:UpdateHeight()
		self:SetHeight(f.name:GetHeight())
	end
	f.name = f:CreateFontString()
	f.name:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	f.name:SetTextColor(1,1,1)
	f.name:SetPoint("TOPLEFT")
	f.name:SetWidth(110)
	f.name:SetJustifyH("LEFT")
	f.version = f:CreateFontString()
	f.version:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	f.version:SetPoint("BOTTOMLEFT", f.name, "BOTTOMRIGHT", 5, 0)
	f.version:SetPoint("TOPRIGHT")
	f.version:SetJustifyH("LEFT")
	function f:SetVersion(name, versionstring)
		if not versionstring then
			f.version:SetTextColor(0.8,0,0)
			f.name:SetText(name)
			f.version:SetText("n/A")
			f.status = "not_installed"
			GDKPd.version.notify:Enable()
			self:UpdateHeight()
			return
		end
		if versionstring == (DEBUGFORCEVERSION or "2.0.0") then
			f.version:SetTextColor(0,0.8,0)
			f.name:SetText(name)
			f.version:SetText(versionstring)
			f.status = "updated"
		elseif COMPATIBLE_VERSIONS[versionstring] then
			f.version:SetTextColor(0.8,0.8,0)
			f.name:SetText(name)
			f.version:SetText(versionstring)
			f.status = "outdated_compatible"
			GDKPd.version.notify:Enable()
		elseif INCOMPATIBLE_VERSIONS[versionstring] then
			f.version:SetTextColor(0.8,0,0)
			f.name:SetText(name)
			f.version:SetText(versionstring)
			f.status = "outdated_incompatible"
			GDKPd.version.notify:Enable()
		else
			f.version:SetTextColor(0.3,0.3,1)
			f.name:SetText(name)
			f.version:SetText(versionstring)
			f.status = "self_outdated"
		end
		self:UpdateHeight()
	end
	f:SetScript("OnEnter", function(self)
		GameTooltip:ClearAllPoints()
		GameTooltip:ClearLines()
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:AddLine(L["Version status for player %s"]:format(self.name:GetText()))
		if self.status == "updated" then
			GameTooltip:AddLine(L["This player has the same version of GDKPd as you do. Full compability is ensured."])
		elseif self.status == "outdated_compatible" then
			GameTooltip:AddLine(L["This player's version of GDKPd is outdated. However, their version should be fully compatible with yours."])
		elseif self.status == "outdated_incompatible" then
			GameTooltip:AddLine(L["This player's version of GDKPd is outdated and one or more functionalities are not compatible:"])
			for _, incompatible_string in ipairs(INCOMPATIBLE_VERSIONS[f.version:GetText()]) do
				GameTooltip:AddLine(" - "..VERSIONING_STRINGS[incompatible_string])
			end
		elseif self.status == "self_outdated" then
			GameTooltip:AddLine(L["This player's version of GDKPd is more advanced than yours. Please consult your Curse Client for updates or manually check the curse.com page."])
		elseif self.status == "not_installed" then
			GameTooltip:AddLine(L["This player does not have GDKPd running or his version of GDKPd does not yet support version checks."])
		end
		GameTooltip:SetPoint("TOPRIGHT", self, "LEFT", -5, 0)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)
	t[v] = f
	return f
end})
version.hide = CreateFrame("Button", nil, version, "UIPanelButtonTemplate")
version.hide:SetSize(170,15)
version.hide:SetPoint("BOTTOM", 0, 15)
version.hide:SetText(L["Hide"])
version.hide:SetScript("OnClick", function() version:Hide() end)
version.notify = CreateFrame("Button", nil, version, "UIPanelButtonTemplate")
version.notify:SetSize(170,15)
version.notify:SetPoint("BOTTOM", version.hide, "TOP", 0, 5)
version.notify:SetText(L["Notify outdated versions"])
version.notify:SetScript("OnClick", function()
	local c = 1
	local f = rawget(version.entries,c)
	while (f and f:IsShown()) do
		if f.status == "outdated_compatible" and GDKPd.opt.notifyVersions.notifyCompatibleOutdated then
			SendChatMessage(L["Your version of GDKPd is slightly outdated compared to the raid leader's. Full compability should be possible, however, you might want to take some time and update GDKPd."], "WHISPER", nil, f.name:GetText())
		elseif f.status == "outdated_incompatible"  and GDKPd.opt.notifyVersions.notifyIncompatibleOutdated then
			SendChatMessage(L["Your version of GDKPd is outdated and no longer compatible with the raid leader's in one or more functionalities. In order to ensure smooth performance, please update GDKPd."], "WHISPER", nil, f.name:GetText())
		elseif f.status == "not_installed" and GDKPd.opt.notifyVersions.notifyNotInstalled then
			SendChatMessage(L["This raid uses GDKPd to faciliate its GDKP bidding process. While you can bid on items without having GDKPd installed, installing it provides you with a GUI bidding panel, auto bidding functions, auction timers, chat filtering and more!"], "WHISPER", nil, f.name:GetText())
		end
		c=c+1
		f=rawget(version.entries,c)
	end
end)
version.notify:Disable()
version.request = CreateFrame("Button", nil, version, "UIPanelButtonTemplate")
version.request:SetSize(170,15)
version.request:SetPoint("BOTTOM", version.notify, "TOP", 0, 5)
version.request:SetText(L["Request version data"])
version.request:SetScript("OnClick", function() GDKPd.hasRequestedData = true SendAddonMessage("GDKPD VREQ","poptix","RAID") end)
function version:Update()
	if not GDKPd.hasRequestedData then return end
	for _, f in ipairs(self.entries) do
		f:Hide()
	end
	self.notify:Disable()
	local size = 85
	for numRaid=1, GetNumGroupMembers() do
		local pName = UnitName("raid"..numRaid)
		local f = self.entries[numRaid]
		f:Show()
		f:SetVersion(pName, GDKPd.versions[pName])
		size=size+f:GetHeight()+5
	end
	self:SetHeight(size)
end
function GDKPd:MailBalanceGold(targetName)
	local moneyToMail = GDKPd_PotData.playerBalance[targetName]
	if moneyToMail <= 0 then return end
	ClearSendMail()
	SetSendMailMoney(moneyToMail*10000)
	SendMail(targetName, "<GDKPd> "..moneyToMail.." gold")
	GDKPd_PotData.playerBalance[targetName] = 0
	self.balance:Update()
end
GDKPd.balance = CreateFrame("Frame", "GDKPd_PlayerBalance", status)
local balance = GDKPd.balance
balance:SetSize(200, 95)
balance:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
balance.header = CreateFrame("Button", nil, balance)
balance.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
balance.header:SetSize(133,34)
balance.header:SetHitRectInsets(31.5,31.5,4.5,14.5)
balance.header.text = balance.header:CreateFontString()
balance.header.text:SetPoint("TOP", 0, -7)
balance.header.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
balance.header.text:SetTextColor(1,1,1)
balance.header.text:SetText(L["Balance"])
balance.header:SetMovable(true)
balance.header:SetScript("OnMouseDown", function(self)
	if self:IsMovable() then
		self:StartMoving()
	end
end)
balance.header:SetScript("OnMouseUp", function(self)
	if self:IsMovable() then
		self:StopMovingOrSizing()
		GDKPd.opt.balancepoint.point, _, GDKPd.opt.balancepoint.relative, GDKPd.opt.balancepoint.x, GDKPd.opt.balancepoint.y = self:GetPoint()
	end
end)
balance:SetPoint("TOP", balance.header, "TOP", 0, -6)
balance:SetScript("OnShow", function(self)
	self:Update()
end)
balance.entries = setmetatable({}, {__index=function(t,v)
	local f = CreateFrame("Button", nil, balance)
	if v > 1 then
		f:SetPoint("TOPLEFT", t[v-1], "BOTTOMLEFT", 0, -5)
		f:SetPoint("TOPRIGHT", t[v-1], "BOTTOMRIGHT", 0, -5)
	else
		f:SetPoint("TOPLEFT", 15, -35)
		f:SetWidth(170)
	end
	function f:UpdateHeight()
		self:SetHeight(math.max(self.name:GetHeight(), self.amount:GetHeight()))
	end
	f.name = f:CreateFontString()
	f.name:SetPoint("TOPLEFT")
	f.name:SetPoint("BOTTOMLEFT")
	f.name:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
	f.name:SetTextColor(1,1,1)
	f.name:SetJustifyH("LEFT")
	f.amount = f:CreateFontString()
	f.amount:SetPoint("TOPLEFT", f.name, "TOPRIGHT", 5, 0)
	f.amount:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
	f.amount:SetTextColor(1,1,1)
	f.amount:SetJustifyH("RIGHT")
	f.add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.add:SetSize(15,15)
	f.add:SetText("+")
	f.add:SetScript("OnClick", function(self)
		StaticPopup_Show("GDKPD_ADDTOPLAYER", f.name:GetText()).data=f.name:GetText()
	end)
	f.rem = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.rem:SetSize(15,15)
	f.rem:SetText("-")
	f.rem:SetScript("OnClick", function(self)
		StaticPopup_Show("GDKPD_REMFROMPLAYER", f.name:GetText()).data=f.name:GetText()
	end)
	--f.rem:SetPoint("TOPRIGHT")
	f.rem:SetPoint("RIGHT")
	f.add:SetPoint("RIGHT", f.rem, "LEFT")
	--f.add:SetPoint("BOTTOMRIGHT", f.rem, "BOTTOMLEFT")
	f.amount:SetPoint("BOTTOMRIGHT", f.add, "BOTTOMLEFT")
	function f.amount:SetAmount(gAmount)
		if gAmount > 0 then
			self:SetText("|cff00ff00"..gAmount.."|r|cffffd100g|r")
		elseif gAmount < 0 then
			self:SetText("|cffff0000"..gAmount.."|r|cffffd100g|r")
		else
			self:SetText("0|cffffd100g|r")
		end
	end
	f.mail = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.mail:SetSize(40, 15)
	f.mail:SetText(L["Mail"])
	f.mail:SetScript("OnClick", function(self)
		local targetName = f.name:GetText()
		if GDKPd.opt.confirmMail then
			StaticPopup_Show("GDKPD_MAILGOLD", GDKPd_PotData.playerBalance[targetName],targetName).data=targetName
		else
			GDKPd:MailBalanceGold(targetName)
		end
	end)
	function f.mail:UpdateState()
		local shouldDisable = (not MailFrame) or (not MailFrame:IsShown())
		shouldDisable = shouldDisable or (GDKPd_PotData.playerBalance[f.name:GetText()] <= 0)
		if shouldDisable then
			self:Disable()
			return false
		else
			self:Enable()
			return true
		end
	end
	f.mail:SetPoint("LEFT", f.rem, "RIGHT", 5, 0)
	t[v] = f
	return f
end})
function balance:UpdatePosition()
	local f = self.header
	f:ClearAllPoints()
	if not GDKPd.opt.anchorBalance then
		f:SetPoint(GDKPd.opt.balancepoint.point, UIParent, GDKPd.opt.balancepoint.relative, GDKPd.opt.balancepoint.x, GDKPd.opt.balancepoint.y)
		f:SetMovable(true)
	else
		f:SetPoint("TOP", status, "BOTTOM", 0, -15)
		f:StopMovingOrSizing()
		f:SetMovable(false)
	end
end
function balance:Update()
	for _, f in ipairs(self.entries) do
		f:Hide()
	end
	local c = 1
	local size = 50
	local isWidthIncreased = false
	if (GDKPd.isTrading) then
		local f = self.entries[c]
		f:Show()
		f.amount:SetAmount(GDKPd_PotData.playerBalance[(UnitName("NPC"))])
		MoneyInputFrame_SetCopper(TradePlayerInputMoneyFrame, (GDKPd_PotData.playerBalance[(UnitName("NPC"))]*10000));
		f.name:SetText((UnitName("NPC")))
		f:UpdateHeight()
		isWidthIncreased = f.mail:UpdateState() or isWidthIncreased
		c = c+1
		size=size+f:GetHeight()+5
	end
	for name, amount in pairs(GDKPd_PotData.playerBalance) do
		if ((not GDKPd.isTrading) or (name ~= (UnitName("NPC")))) and (amount ~= 0) and (name ~= (UnitName("player"))) then
			local f = self.entries[c]
			f:Show()
			f.name:SetText(name)
			f.amount:SetAmount(amount)
			f:UpdateHeight()
			isWidthIncreased = f.mail:UpdateState() or isWidthIncreased
			c = c+1
			size=size+f:GetHeight()+5
		end
	end
	self:SetHeight(size)
	if size == 50 then
		self:Hide()
	else
		self:Show()
	end
	if isWidthIncreased then
		for _, f in ipairs(self.entries) do
			f.mail:Show()
		end
		self:SetWidth(245)
	else
		for _, f in ipairs(self.entries) do
			f.mail:Hide()
		end
		self:SetWidth(200)
	end
end
GDKPd.playerBalance = CreateFrame("Frame", "GDKPd_PlayerBalance", UIParent)
local playerBalance = GDKPd.playerBalance
playerBalance:SetSize(200, 95)
playerBalance:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
playerBalance.header = CreateFrame("Button", nil, playerBalance)
playerBalance.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
playerBalance.header:SetSize(133,34)
playerBalance.header:SetHitRectInsets(31.5,31.5,4.5,14.5)
playerBalance.header.text = playerBalance.header:CreateFontString()
playerBalance.header.text:SetPoint("TOP", 0, -7)
playerBalance.header.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
playerBalance.header.text:SetTextColor(1,1,1)
playerBalance.header.text:SetText(L["Player balance"])
playerBalance.header:SetMovable(true)
playerBalance.header:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
playerBalance.header:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
	GDKPd.opt.playerbalancepoint.point, _, GDKPd.opt.playerbalancepoint.relative, GDKPd.opt.playerbalancepoint.x, GDKPd.opt.playerbalancepoint.y = self:GetPoint()
end)
playerBalance:SetPoint("TOP", playerBalance.header, "TOP", 0, -6)
playerBalance:SetScript("OnShow", function(self)
	self:Update()
end)
playerBalance.reset = CreateFrame("Button", nil, playerBalance, "UIPanelButtonTemplate")
playerBalance.reset:SetSize(170,15)
playerBalance.reset:SetPoint("BOTTOM", 0, 15)
playerBalance.reset:SetText(RESET)
playerBalance.reset:SetScript("OnClick", function() GDKPd_BalanceData = setmetatable({},{__index=function() return 0 end}) GDKPd.playerBalance:Update() end)
playerBalance.entries = setmetatable({}, {__index=function(t,v)
	local f = CreateFrame("Button", nil, playerBalance)
	if v > 1 then
		f:SetPoint("TOPLEFT", t[v-1], "BOTTOMLEFT", 0, -5)
		f:SetPoint("TOPRIGHT", t[v-1], "BOTTOMRIGHT", 0, -5)
	else
		f:SetPoint("TOPLEFT", 15, -15)
		f:SetPoint("TOPRIGHT", -15, -15)
	end
	function f:UpdateHeight()
		self:SetHeight(math.max(self.name:GetHeight(), self.amount:GetHeight()))
	end
	f.name = f:CreateFontString()
	f.name:SetPoint("TOPLEFT")
	f.name:SetPoint("BOTTOMLEFT")
	f.name:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
	f.name:SetTextColor(1,1,1)
	f.name:SetJustifyH("LEFT")
	f.amount = f:CreateFontString()
	f.amount:SetPoint("TOPLEFT", f.name, "TOPRIGHT", 5, 0)
	f.amount:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
	f.amount:SetTextColor(1,1,1)
	f.amount:SetJustifyH("RIGHT")
	f.amount:SetPoint("BOTTOMRIGHT")
	function f.amount:SetAmount(gAmount)
		if gAmount > 0 then
			self:SetText("|cff00ff00"..gAmount.."|r|cffffd100g|r")
		elseif gAmount < 0 then
			self:SetText("|cffff0000"..gAmount.."|r|cffffd100g|r")
		else
			self:SetText("0|cffffd100g|r")
		end
	end
	t[v] = f
	return f
end})
function playerBalance:UpdateVisibility(forceCombat)
	if GDKPd.opt.hide then
		self:Hide()
		return
	end
	if (self:GetHeight() > 50) and ((not GDKPd.opt.hideCombat.status) or (not (forceCombat~=nil and forceCombat or InCombatLockdown()))) then
		self:Show()
	else
		self:Hide()
	end
end
function playerBalance:Update()
	for _, f in ipairs(self.entries) do
		f:Hide()
	end
	local c = 1
	local size = 45
	if (GDKPd.isTrading) then
		local f = self.entries[c]
		f:Show()
		f.amount:SetAmount(GDKPd_BalanceData[(UnitName("NPC"))])
		f.name:SetText((UnitName("NPC")))
		f:UpdateHeight()
		c = c+1
		size=size+f:GetHeight()+5
	end
	for name, amount in pairs(GDKPd_BalanceData) do
		if ((not GDKPd.isTrading) or (name ~= (UnitName("NPC")))) and (amount ~= 0) and (name ~= (UnitName("player"))) then
			local f = self.entries[c]
			f:Show()
			f.name:SetText(name)
			f.amount:SetAmount(amount)
			f:UpdateHeight()
			c = c+1
			size=size+f:GetHeight()+5
		end
	end
	self:SetHeight(size)
	self:UpdateVisibility()
end
GDKPd.exportframe = CreateFrame("Frame", "GDKPd_Export", UIParent)
local export = GDKPd.exportframe
export:Hide()
export:SetBackdrop({
	bgFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
	edgeFile="Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tileSize=32,
	edgeSize=24,
	tile=true,
	insets={
		top=6,
		bottom=6,
		right=6,
		left=6,
	},
})
export.header = CreateFrame("Button", nil, export)
export.header:SetNormalTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
export.header:SetSize(133,34)
export.header:SetHitRectInsets(31.5,31.5,4.5,14.5)
export.header.text = export.header:CreateFontString()
export.header.text:SetPoint("TOP", 0, -7)
export.header.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
export.header.text:SetTextColor(1,1,1)
export.header.text:SetText(L["Pot export"])
export.header:SetMovable(true)
export.header:SetScript("OnMouseDown", function(self)
	self:StartMoving()
end)
export.header:SetScript("OnMouseUp", function(self)
	self:StopMovingOrSizing()
end)
export.header:SetPoint("TOP", history, "BOTTOM", 0, -10)
export.box = CreateFrame("EditBox", nil, export)
export.box:SetMultiLine(true)
export.box:SetAutoFocus(false)
export.box:SetFont("Fonts\\FRIZQT__.TTF", 12)
export.box:SetPoint("TOP", export.header, "TOP", 0, -21)
export.box:SetJustifyH("LEFT")
export.box:SetWidth(50)
do
	local st = export.box.SetText
	local dummy_text = UIParent:CreateFontString()
	dummy_text:SetFont("Fonts\\FRIZQT__.TTF", 12)
	function export.box:SetText(text)
		dummy_text:SetText(text)
		self:SetWidth(dummy_text:GetStringWidth())
		self.text = text
		st(self, text)
	end
end
export.box:SetScript("OnTextChanged", function(self, userInput)
	if userInput then
		self:SetText(self.text or "")
	end
	self:HighlightText()
	self:SetFocus()
end)
export.box:SetScript("OnEscapePressed", function(self)
	self:ClearFocus()
	export:Hide()
end)
export.box:SetScript("OnEnterPressed", function(self)
	self:ClearFocus()
end)
export:SetPoint("TOPLEFT", export.box, "TOPLEFT", -15, 15)
export:SetPoint("BOTTOMRIGHT", export.box, "BOTTOMRIGHT", 15, -15)

export.toggleBB = CreateFrame("Button", nil, export, "UIPanelButtonTemplate")
export.toggleBB:SetSize(150,20)
export.toggleBB:SetPoint("TOP", export, "BOTTOM", 0, 10)
export.toggleBB:SetText("BBCode")
export.toggleBB:SetScript("OnClick", function() export:SetType('BB') end)

export.toggleDefault = CreateFrame("Button", nil, export, "UIPanelButtonTemplate")
export.toggleDefault:SetSize(150,20)
export.toggleDefault:SetPoint("RIGHT",export.toggleBB,"LEFT")
export.toggleDefault:SetText("Tab Delimited")
export.toggleDefault:SetScript("OnClick", function() export:SetType('Default') end)

export.toggleBN = CreateFrame("Button", nil, export, "UIPanelButtonTemplate")
export.toggleBN:SetSize(150,20)
export.toggleBN:SetPoint("LEFT",export.toggleBB,"RIGHT")
export.toggleBN:SetText("Battle.net forums")
export.toggleBN:SetScript("OnClick",function() export:SetType('BN') end)

function export:Update()
	local text = self.header
	for _, aucdata in ipairs(self.data) do
		if type(aucdata) == "table" then
			if self.exportType == "BB" then
				text = text.."\n[color=#"..aucdata.item:match("|c[fF][fF]([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])").."][url=http://www.wowhead.com/item="..aucdata.item:match("|Hitem:(%d+):").."]"..(aucdata.item:match("(|h.+|h)")).."[/url][/color]: "..aucdata.name.." ("..aucdata.bid.." gold)"
			elseif self.exportType == "BN" then
				text = text.."\n[item=\""..aucdata.item:match("|Hitem:(%d+):").."\" /]: "..aucdata.name.." ("..aucdata.bid.." gold)"
			else
				text = text.."\n=HYPERLINK(\"http://classic.wowhead.com/item="..(aucdata.item:match("|Hitem:(%d+):")).."\",\""..aucdata.item:match("(|h.+|h)").."\")\t"..aucdata.name.."\t"..aucdata.bid
			end
		else
			text = text.."\n"..L["Manual adjustment"]..": "..(aucdata > 0 and "+" or "")..aucdata.." gold"
		end
	end
	self.box:SetText(text)
end

function export:Set(header,data)
	self.header = header
	self.data = data
	self:Update()
end

function export:SetType(t)
	self["toggle"..self.exportType]:UnlockHighlight()
	self.exportType = t
	self["toggle"..t]:LockHighlight()
	self:Update()
end
export.exportType = "Default"
export.toggleDefault:LockHighlight()

function GDKPd:SetMovable(movable)
	if movable then
		anchor:EnableMouse(true)
		anchor:Show()
	else
		anchor:EnableMouse(false)
		anchor:Hide()
	end
end
function GDKPd:GetStartBid(id)
	local ilvl = (select(4, GetItemInfo(id)))
	if self.opt.customItemSettings[id] then
		return self.opt.customItemSettings[id].minBid
	end
	if ilvl then
		for _, d in ipairs(self.opt.itemLevelPricing) do
			if (d.min <= ilvl) and (d.max >= ilvl) then
				return d.minbid
			end
		end
	end
	return self.opt.startBid
end
function GDKPd:GetMinIncrement(id)
	local ilvl = (select(4, GetItemInfo(id)))
	if self.opt.customItemSettings[id] then
		return self.opt.customItemSettings[id].minIncrement
	end
	if ilvl then
		for _, d in ipairs(self.opt.itemLevelPricing) do
			if (d.min <= ilvl) and (d.max >= ilvl) then
				return d.mininc
			end
		end
	end
	return self.opt.increment
end
function GDKPd:FetchFrameFromLink(itemLink)
	for num, frame in ipairs(GDKPd.frames) do
		if (frame.itemlink == itemLink) and frame.isActive then
			return frame,num
		end
	end
end
function GDKPd:PlayerIsML(playerName, invert)
	for raidID = (invert and GetNumGroupMembers() or 1), (invert and 1 or GetNumGroupMembers()), (invert and -1 or 1) do
		local name, _, _, _, _,_,_,_,_,_,isML = GetRaidRosterInfo(raidID)
		if playerName == name then
			return isML
		end
	end
end
function GDKPd:AnnounceLoot(shouldQueueAuctions)
	if GetNumLootItems() <= 0 then return end
	local lootList = emptytable()
	local minQuality = (self.opt.minQuality == -1 and GetLootThreshold() or self.opt.minQuality)
	local playerName = (UnitName("player"))
	for numLoot=1, GetNumLootItems() do
		if LootSlotIsItem(numLoot) then
			local tex, item, quantity, currency, quality, isLocked = GetLootSlotInfo(numLoot)
			if quality >= minQuality then
				tinsert(lootList, GetLootSlotLink(numLoot))
				if self.opt.awardToML then
					local candidateIndex = 1
					local candidateName = GetMasterLootCandidate(numLoot,candidateIndex)
					while candidateName do
						if candidateName == playerName then
							GiveMasterLoot(numLoot,candidateIndex)
							break
						end
						candidateIndex = candidateIndex + 1
						candidateName = GetMasterLootCandidate(numLoot,candidateIndex)
					end
				end
			end
		end
	end
	local lootString = L["Loot dropped: "]..lootList[1]
	for lootNum, link in ipairs(lootList) do
		if lootNum > 1 then
			if strlen(lootString)+strlen(link)+2 > 255 then
				SendChatMessage(lootString,"RAID")
				lootString=link
			else
				lootString=lootString..", "..link
			end
		end
	end
	SendChatMessage(lootString, "RAID")
	for _, item in ipairs(lootList) do
		if shouldQueueAuctions then
			local itemID = tonumber(item:match("|Hitem:(%d+):"))
			--local iLvL = (select(4, GetItemInfo(itemID)))
			--local startBid = (GDKPd.opt.customItemSettings[itemID] and GDKPd.opt.customItemSettings[itemID].minBid) or  or self.opt.startBid
			--local increment = (GDKPd.opt.customItemSettings[itemID] and GDKPd.opt.customItemSettings[itemID].minIncrement) or self.opt.increment
			--GDKPd:QueueAuction(item, startBid, increment)
			GDKPd:QueueAuction(item, GDKPd:GetStartBid(itemID), GDKPd:GetMinIncrement(itemID))
		else
			SendAddonMessage("GDKPD START", item, "RAID")
		end
	end
	lootList:Release()
end
function GDKPd:QueueAuction(item, minbid, increment, index)
	if (not GDKPd.curAuction.item) or GDKPd.opt.allowMultipleAuctions then
		if (index) then 
			GDKPd:AuctionOffItem(item, minbid, increment, index)
		else
			--if index is not passed in, we should find the item in the curpot and pass in the index.  Skip for now.
			GDKPd:AuctionOffItem(item, minbid, increment, GDKPd.itemCount)
		end 
	else
		SendAddonMessage("GDKPD START", item, "RAID")
		tinsert(GDKPd.auctionList,emptytable(item,minbid,increment))
	end
end
function GDKPd:AuctionOffItem(item, minbid, increment, index)
	if (GDKPd.curAuction.item) and (not self.opt.allowMultipleAuctions) then return end
	if (self.opt.allowMultipleAuctions) and (self.curAuctions[item]) then return end
	if (not self.opt.allowMultipleAuctions) then
		-- old code
		SendChatMessage(("Bidding starts on %s. Please bid in raid chat, starting bid %d gold, minimum increment %d gold."):format(item,minbid,increment,self.opt.auctionTimer, self.opt.auctionTimerRefresh), (self.opt.announceRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
		GDKPd.curAuction.item = item
		GDKPd.curAuction.curBid = (minbid-increment)
		GDKPd.curAuction.increment = increment
		GDKPd.curAuction.bidders = emptytable()
		GDKPd.curAuction.timeRemains = self.opt.auctionTimer
		GDKPd.curAuction.index = index
	else
		-- new code
		SendChatMessage(("Bidding starts on %s. Bid using format '[item] 1000', starting bid %d gold, minimum increment %d gold. TTL: %d/%d"):format(item,minbid,increment,self.opt.auctionTimer, self.opt.auctionTimerRefresh), (self.opt.announceRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
		local aucTable = emptytable()
		aucTable.item = item
		aucTable.curBid = (minbid-increment)
		aucTable.increment = increment
		aucTable.bidders = emptytable()
		aucTable.timeRemains = self.opt.auctionTimer
		aucTable.index = index
		GDKPd.curAuctions[item] = aucTable
	end
	GDKPd:Show()
end
function GDKPd:RevertHighestBid(link)
	if self.opt.allowMultipleAuctions then
		if not link then return end
		local aucdata = self.curAuctions[link]
		if not aucdata then return end
		if #aucdata.bidders < 2 then return end
		table.sort(aucdata.bidders, function(a,b) return a.bidAmount > b.bidAmount end)
		aucdata.bidders[aucdata.bidders[1].bidderName] = nil
		tremove(aucdata.bidders,1)
		SendChatMessage(("New highest bidder on %s: %s (%d gold)"):format(link, aucdata.bidders[1].bidderName, aucdata.bidders[1].bidAmount), (self.opt.announceBidRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
		-- fix name-to-index assigns
		for num, t in ipairs(aucdata.bidders) do
			aucdata.bidders[t.bidderName] = num
		end
		aucdata.timeRemains = math.max(aucdata.timeRemains, self.opt.auctionTimerRefresh)
		aucdata.curBid = aucdata.bidders[1].bidAmount
	else
		if #self.curAuction.bidders < 2 then return end
		table.sort(self.curAuction.bidders, function(a,b) return a.bidAmount > b.bidAmount end)
		self.curAuction.bidders[self.curAuction.bidders[1].bidderName] = nil
		tremove(self.curAuction.bidders, 1)
		SendChatMessage(("New highest bidder: %s (%d gold)"):format(self.curAuction.bidders[1].bidderName, self.curAuction.bidders[1].bidAmount), (self.opt.announceBidRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
		for num, t in ipairs(self.curAuction.bidders) do
			self.curAuction.bidders[t.bidderName] = num
		end
		self.curAuction.timeRemains = math.max(self.curAuction.timeRemains, self.opt.auctionTimerRefresh)
		self.curAuction.curBid = self.curAuction.bidders[1].bidAmount
	end
end
function GDKPd:CancelAuction(link)
	if self.opt.allowMultipleAuctions then
		if not link then return end
		local aucdata = self.curAuctions[link]
		if not aucdata then return end
		SendChatMessage(("Auction cancelled for %s."):format(link), (self.opt.announceRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
		self.curAuctions[link] = nil
	else
		SendChatMessage("Auction cancelled.", (self.opt.announceRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
		table.wipe(self.curAuction)
		if self.auctionList[1] then
			self:AuctionOffItem(unpack(self.auctionList[1]))
			self.auctionList[1]:Release()
			tremove(self.auctionList,1)
		end
	end
end

function GDKPd:AddItemToPot(link, bid, bname, select)
	--add item into GDKPd_PotData.curPotHistory here.
	local itemlink = link
	local bid1 = bid
	local name = bname
	GDKPd_Debug("AddItemToPot: link: " ..itemlink)
	GDKPd_Debug("AddItemToPot: bid: " ..tostring(bid1))
	GDKPd_Debug("AddItemToPot: lootername: " ..name)
	local itemName, _, itemId, itemString, itemRarity, itemColor, itemLevel, _, itemType, itemSubType, _, _, _, _, itemClassID, itemSubClassID = GDKPd:GetDetailedItemInformation(link);
	GDKPd.itemCount = GDKPd.itemCount + 1
	tinsert(GDKPd_PotData.curPotHistory, {itemName=itemName, itemId=itemId, itemColor=itemColor, item=itemlink, bid=bid1, name=name, index=GDKPd.itemCount, ltime=time()})
	local loottable = GDKPd:BossLootTableUpdate()
	if select then 
		if loottable then 
			for i = 1, #loottable do
				pName = cleanString(loottable[i][4]);
				pItem = loottable[i][6]
				GDKPd_Debug("selecPlayer: Comparing pName: " ..pName.." and name: " ..name)
				if (pName == name) and (pItem == itemlink) then
					GDKPd_Debug("selecPlayer: Player, "..name.. " found! i: " ..i)
					status.BossLootTable:SetSelection(i)
					return;
				end
			end
		end
		
	end 
end

function GDKPd:UpdateItemInPot(link, bid, bname, index)
	--add item into GDKPd_PotData.curPotHistory here.
	--tinsert(GDKPd_PotData.curPotHistory, {itemName=itemName, itemId=itemId, itemColor=itemColor, item=itemlink, bid=bid1, name=name, index=GDKPd.itemCount, ltime=time()})
	GDKPd_Debug("UpdateItemInPot: link: " ..link)
	GDKPd_Debug("UpdateItemInPot: bid: " ..tostring(bid))
	GDKPd_Debug("UpdateItemInPot: lootername: " ..bname)
	GDKPd_Debug("UpdateItemInPot: index: " ..index)
	GDKPd_PotData.curPotHistory[index]["bid"]=bid
	GDKPd_PotData.curPotHistory[index]["name"]=bname
	GDKPd:BossLootTableUpdate()
end

function GDKPd:DoAuction(link, index)
	if self:PlayerIsML((UnitName("player")),true) then
		for itemLink in string.gmatch(link, "|c........|Hitem:.-|r") do
			local itemID = tonumber(itemLink:match("|Hitem:(%d+):"))
			self:QueueAuction(itemLink, GDKPd:GetStartBid(itemID), GDKPd:GetMinIncrement(itemID), index)
		end
	else
		print(L["Cannot start auction without Master Looter privileges."])
	end
end

function GDKPd:FinishAuction(link)
	if self.opt.allowMultipleAuctions then
		-- new code
		if not link then return end
		local aucdata = self.curAuctions[link]
		if aucdata then
			table.sort(aucdata.bidders, function(a,b) return a.bidAmount > b.bidAmount end)
			if aucdata.bidders[1] then
				local totalAmount = aucdata.bidders[1].bidAmount
				local remAmount = totalAmount
				local paymentString = "%d to pot"
				if self.opt.shareSecondEnable and aucdata.bidders[2] then
					local secondShare = round(totalAmount*self.opt.shareSecondAmount)
					remAmount = remAmount-secondShare
					paymentString = paymentString..", "..secondShare.." to "..aucdata.bidders[2].bidderName
				end
				if self.opt.shareThirdEnable and aucdata.bidders[3] then
					local thirdShare = round(totalAmount*self.opt.shareThirdAmount)
					remAmount = remAmount-thirdShare
					paymentString = paymentString..", "..thirdShare.." to "..aucdata.bidders[3].bidderName
				end
				paymentString = paymentString:format(remAmount)
				SendChatMessage(("Auction finished for %s. Winner: %s. %s."):format(link, aucdata.bidders[1].bidderName, paymentString),"RAID")
				GDKPd_PotData.potAmount = (GDKPd_PotData.potAmount or 0)+remAmount
				GDKPd_PotData.playerBalance[aucdata.bidders[1].bidderName] = GDKPd_PotData.playerBalance[aucdata.bidders[1].bidderName] -remAmount
				GDKPd.balance:Update()
				if self.opt.announcePotAfterAuction then
					SendChatMessage("Current pot: "..GDKPd_PotData.potAmount.." gold","RAID")
				end
				--This is where we'll want to find and update instead of adding new item.
				GDKPd_Debug("FinishAuction: link: "..link.." bid: " ..totalAmount.. " aucdata.bidders[1].bidderName: " ..aucdata.bidders[1].bidderName)
				--self:AddItemToPot(link, totalAmount, aucdata.bidders[1].bidderName)
				self:UpdateItemInPot(link, totalAmount, aucdata.bidders[1].bidderName, self.curAuction.index)
				--tinsert(GDKPd_PotData.curPotHistory, {item=link, bid=totalAmount, name=aucdata.bidders[1].bidderName})
				self.status:Update()
				if self.opt.autoAwardLoot then
					local bestBidderName = aucdata.bidders[1].bidderName
					for lootSlot = 1, GetNumLootItems() do
						if GetLootSlotLink(lootSlot) == link then
							local candidateIndex = 1
							local candidateName = GetMasterLootCandidate(lootSlot,candidateIndex)
							while candidateName do
								if candidateName == bestBidderName then
									GiveMasterLoot(lootSlot,candidateIndex)
									break
								end
								candidateIndex = candidateIndex + 1
								candidateName = GetMasterLootCandidate(candidateIndex)
							end
							break
						end
					end
				end
			else
				SendChatMessage(("Auction finished for %s. No bids recieved."):format(link),"RAID")
			end
			aucdata:Release()
		end
		self.curAuctions[link] = nil
	else
		-- old code
		table.sort(self.curAuction.bidders, function(a,b) return a.bidAmount > b.bidAmount end)
		if self.curAuction.bidders[1] then
			local totalAmount = self.curAuction.bidders[1].bidAmount
			local remAmount = totalAmount
			local paymentString = "%d to pot"
			if self.opt.shareSecondEnable and self.curAuction.bidders[2] then
				local secondShare = round(totalAmount*self.opt.shareSecondAmount)
				remAmount = remAmount-secondShare
				paymentString = paymentString..", "..secondShare.." to "..self.curAuction.bidders[2].bidderName
			end
			if self.opt.shareThirdEnable and self.curAuction.bidders[3] then
				local thirdShare = round(totalAmount*self.opt.shareThirdAmount)
				remAmount = remAmount-thirdShare
				paymentString = paymentString..", "..thirdShare.." to "..self.curAuction.bidders[3].bidderName
			end
			paymentString = paymentString:format(remAmount)
			SendChatMessage(("Auction finished. Winner: %s. %s."):format(self.curAuction.bidders[1].bidderName, paymentString),"RAID")
			GDKPd_PotData.potAmount = (GDKPd_PotData.potAmount or 0)+remAmount
			GDKPd_PotData.playerBalance[self.curAuction.bidders[1].bidderName] = GDKPd_PotData.playerBalance[self.curAuction.bidders[1].bidderName] -remAmount
			GDKPd.balance:Update()
			if self.opt.announcePotAfterAuction then
				SendChatMessage("Current pot: "..GDKPd_PotData.potAmount.." gold","RAID")
			end
			--using new add method
			--GDKPd_Debug("self.curAuction.bidders: self.curAuction.item: " ..self.curAuction.item.. " totalAmount: " ..totalAmount.. " self.curAuction.bidders[1].bidderName: " ..self.curAuction.bidders[1].bidderName)
			local aucitem = self.curAuction.item
			local bidamt = tonumber(totalAmount)
			local winname = self.curAuction.bidders[1].bidderName
			GDKPd_Debug("self.curAuction.bidders: aucitem: " ..aucitem.. " bidamt: " ..bidamt.. " winname: " ..winname, "self.curAuction.index: " ..self.curAuction.index)
			--self:AddItemToPot(aucitem, bidamt, winname)
			self:UpdateItemInPot(aucitem, bidamt, winname, self.curAuction.index)
			--tinsert(GDKPd_PotData.curPotHistory, {item=self.curAuction.item, bid=totalAmount, name=self.curAuction.bidders[1].bidderName})
			self.status:Update()
			if self.opt.autoAwardLoot then
				local bestBidderName = self.curAuction.bidders[1].bidderName
				local candidateIndex = 1
				local candidateName = GetMasterLootCandidate(candidateIndex)
				while candidateName do
					if candidateName == bestBidderName then
						for lootSlot = 1, GetNumLootItems() do
							if GetLootSlotLink(lootSlot) == self.curAuction.item then
								GiveMasterLoot(lootSlot,candidateIndex)
								break
							end
						end
						break
					end
					candidateIndex = candidateIndex + 1
					candidateName = GetMasterLootCandidate(candidateIndex)
				end
			end
		else
			SendChatMessage("Auction finished. No bids recieved.","RAID")
		end
		self.curAuction.bidders:Release()
		table.wipe(self.curAuction)
		if self.auctionList[1] then
			self:AuctionOffItem(unpack(self.auctionList[1]))
			self.auctionList[1]:Release()
			tremove(self.auctionList,1)
		end
	end
end
function GDKPd:DistributePot()
	local numraid = GetNumGroupMembers()
	if not (numraid > 0) then return end
	local distAmount = (GDKPd_PotData.potAmount or 0)-(GDKPd_PotData.prevDist or 0)
	if distAmount <= 0 then return end
	local numadditionalmemb = self.opt.AdditonalRaidMembersAmount
	if self.opt.AdditionalRaidMembersEnable then
		SendChatMessage(("Distributing pot. Pot size: %d gold. Amount to distribute: %d gold. Players in raid: %d(%d). Share per player: %d gold."):format((GDKPd_PotData.potAmount or 0), distAmount, numraid,numadditionalmemb, (distAmount or 0)/(numraid+numadditionalmemb)),"RAID")
	else
		SendChatMessage(("Distributing pot. Pot size: %d gold. Amount to distribute: %d gold. Players in raid: %d. Share per player: %d gold."):format((GDKPd_PotData.potAmount or 0), distAmount, numraid, (distAmount or 0)/numraid),"RAID")
	end
	for numRaid=1, numraid do
		if self.opt.AdditionalRaidMembersEnable then
			GDKPd_PotData.playerBalance[(UnitName("raid"..numRaid))] = GDKPd_PotData.playerBalance[(UnitName("raid"..numRaid))]+math.floor((distAmount or 0)/(numraid+numadditionalmemb))
		else
			GDKPd_PotData.playerBalance[(UnitName("raid"..numRaid))] = GDKPd_PotData.playerBalance[(UnitName("raid"..numRaid))]+math.floor((distAmount or 0)/numraid)
		end
	end
	GDKPd_PotData.prevDist = GDKPd_PotData.potAmount
	GDKPd.balance:Update()
end
function GDKPd:GetUnoccupiedFrame()
	local c = 1
	while GDKPd.frames[c] do
		if not GDKPd.frames[c]:IsShown() then
			GDKPd.frames[c].hide:Disable()
			GDKPd.frames[c].bidbox:SetNumber(0)
			GDKPd.frames[c].autobid:Disable()
			GDKPd.frames[c].bidbox:Hide()
			GDKPd.frames[c].bid:Disable()
			GDKPd.frames[c].itemlink = nil
			GDKPd.frames[c].maxAutoBid = nil
			GDKPd.frames[c].curbidamount = nil
			GDKPd.frames[c].curbidismine = nil
			GDKPd.frames[c].bidIncrement = nil
			GDKPd.frames[c].initialBid = nil
			GDKPd.frames[c].autobid:Show()
			GDKPd.frames[c].stopautobid:Hide()
			GDKPd.frames[c].curbid:Hide()
			GDKPd.frames[c].isActive = false
			GDKPd.frames[c].restartAuction:Hide()
			GDKPd.frames[c].bigHide:Hide()
			if (GDKPd:PlayerIsML((UnitName("player")),true) and (not GDKPd.opt.slimML)) then
				GDKPd.frames[c].cancelAuction:Show()
				GDKPd.frames[c].reverseBid:Show()
			else
				GDKPd.frames[c].cancelAuction:Hide()
				GDKPd.frames[c].reverseBid:Hide()
			end
			GDKPd.frames[c].reverseBid:Disable()
			GDKPd.frames[c]:UpdateSize()
			return GDKPd.frames[c]
		end
		c=c+1
	end
	local f = CreateFrame("Frame", "GDKPdBidFrame"..c, UIParent)
	f:SetSize(300,60)
	f:SetBackdrop({
		bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
		tileSize=16,
		edgeSize=24,
		edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
		tile=true,
		edgeSize=16,
		insets={top=5,bottom=5,left=5,right=5},
	})
	if c > 1 then
		f:SetPoint("TOPLEFT", GDKPd.frames[c-1], "BOTTOMLEFT")
	else
		f:SetPoint("TOPLEFT", anchor, "TOPLEFT")
	end
	--f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, (-60)*(c-1))
	f:Hide()
	f:SetFrameStrata("DIALOG")
	f.icon = f:CreateTexture()
	f.icon:SetSize(40,40)
	f.icon:SetTexture(1,1,1)
	f.icon:SetPoint("TOPLEFT", 10, -10)
	f.itemstring = f:CreateFontString()
	f.itemstring:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	f.itemstring:SetTextColor(1,1,1)
	f.itemstring:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 5, 0)
	f.itemstring:SetWidth(160)
	f.itemstring:SetWordWrap(false)
	f.itemstring:SetJustifyH("LEFT")
	f.curbid = f:CreateFontString()
	f.curbid:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
	f.curbid:SetTextColor(1,1,1)
	f.curbid:SetPoint("TOPLEFT", f.itemstring, "BOTTOMLEFT", 0, -5)
	f.curbid:Hide()
	f.highestbid = f:CreateFontString()
	f.highestbid:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	f.highestbid:SetTextColor(0,0.8,0)
	f.highestbid:SetPoint("TOPLEFT", f.curbid, "BOTTOMLEFT", 0, -5)
	f.highestbid:SetText("You are the top bidder!")
	f.highestbidder = f:CreateFontString()
	f.highestbidder:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
	f.highestbidder:SetTextColor(1,1,1)
	f.highestbidder:SetPoint("TOPLEFT", f.curbid, "BOTTOMLEFT", 0, -5)
	f.timer = CreateFrame("Cooldown",nil,f)
	-- omnicc stuff
	f.timer.noCooldownCount = true
	f.timer:SetReverse(true)
	f.timer:SetAllPoints(f.icon)
	f.timer.update = CreateFrame("Frame")
	f.timer.update:Hide()
	f.timer.update:SetScript("OnUpdate", function(self)
		local timeRemain = self.endTime-GetTime()
		if timeRemain <= 0 then
			self:Hide()
			f.timer.text:Hide()
		end
		if timeRemain%1 > 0.5 then
			f.timer.text:SetTextColor(1,0,0)
		else
			f.timer.text:SetTextColor(1,1,0)
		end
		f.timer.text:SetText(math.ceil(timeRemain))
	end)
	f.timer.text = f.timer:CreateFontString()
	f.timer.text:SetFont("Fonts\\FRIZQT__.TTF", GetCVarBool("useUiScale") and (32*(GetCVar("uiScale") or 1)) or 28, "OUTLINE")
	f.timer.text:SetAllPoints()
	f.timer.text:Hide()
	f.autobid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.autobid:SetText(L["Auto bid"])
	f.autobid:SetSize(70, 16)
	f.autobid:SetScript("OnClick", function(self)
		StaticPopup_Show("GDKPD_AUTOBID", f.itemlink).data=f
		f.hide:Disable()
	end)
	f.autobid:SetPoint("TOPRIGHT", -10, -10)
	f.stopautobid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.stopautobid:SetText(L["Stop bid"])
	f.stopautobid:SetAllPoints(f.autobid)
	f.stopautobid:Hide()
	f.stopautobid:SetScript("OnClick", function(self)
		self:Hide()
		f.maxAutoBid = nil
		f.autobid:Show()
		f.hide:Enable()
	end)
	f.bidbox = CreateFrame("EditBox", nil, f)
	f.bidbox:SetMultiLine(nil)
	f.bidbox:SetScript("OnEditFocusGained", function(self)
		if self.disabled then
			self:ClearFocus()
		end
	end)
	function f.bidbox:Enable()
		self.disabled = false
	end
	function f.bidbox:Disable()
		self.disabled = true
	end
	f.bidbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.bidbox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local wantBid = self:GetNumber()
		if wantBid >= (f.bidIncrement+f.curbidamount) then
			SendChatMessage((f.isMultiBid and f.itemlink.." " or "")..wantBid, "RAID")
		end
		self:SetNumber(0)
	end)
	f.bidbox:SetBackdrop({bgFile="Interface\\ChatFrame\\UI-ChatInputBorder",tile=false})
	f.bidbox:SetTextInsets(5,5,2,2)
	f.bidbox:SetSize(40,16)
	f.bidbox:SetFont("Fonts\\FRIZQT__.TTF", 9)
	f.bidbox:SetAutoFocus(false)
	f.bidbox:SetPoint("LEFT", f.curbid, "RIGHT", 5, 0)
	f.bidbox:SetJustifyH("RIGHT")
	f.bidbox:SetNumeric(true)
	f.bidbox:SetNumber(0)
	f.bidbox:Hide()
	f.bid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.bid:SetText(L["Bid"])
	f.bid:SetSize(70,16)
	f.bid:SetPoint("TOP", f.autobid, "BOTTOM", 0, -8)
	f.bid:SetScript("OnClick", function(self)
		local newBid = f.curbidamount + f.bidIncrement
		if f.isMultiBid then
			SendChatMessage(f.itemlink.." "..newBid,"RAID")
		else
			SendChatMessage(tostring(newBid),"RAID")
		end
	end)
	f.bid:Disable()
	f.bid.enabledelay = CreateFrame("Frame", nil, f.bid)
	f.bid.enabledelay:Hide()
	f.bid.enabledelay:SetScript("OnUpdate", function(self)
		if not self.reenabletime then self:Hide() return end
		if GetTime() >= self.reenabletime then f.bid:Enable() self.reenabletime = nil self:Hide() end
	end)
	--f.hide = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.hide = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	--f.hide:SetText(L["Hide"])
	f.hide:SetSize(16,16)
	f.hide:SetPoint("TOPRIGHT")
	f.hide:SetScript("OnClick", function(self)
		GDKPd.ignoredLinks[f.itemlink] = true
		f:Hide()
	end)
	f.hide:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
	end)
	f.hide:SetScript("OnLeave", function(self)
		if (not GDKPd.opt.forceHideShow) then
			self:SetAlpha(0)
		end
	end)
	f.hide:SetAlpha(GDKPd.opt.forceHideShow and 1 or 0)
	f.hide:SetDisabledTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Disabled")
	f.autobid:Disable()
	f.hide:Disable()
	f.bigHide = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.bigHide:SetText(L["Hide"])
	f.bigHide:SetHeight(15)
	f.bigHide:SetPoint("BOTTOMLEFT", 10, 10)
	f.bigHide:SetPoint("BOTTOMRIGHT", -10, 10)
	f.bigHide:SetScript("OnClick", function(self)
		f:Hide()
	end)
	f.bigHide:Hide()
	f.restartAuction = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.restartAuction:SetText(L["Restart auction"])
	f.restartAuction:SetHeight(15)
	f.restartAuction:SetPoint("BOTTOMLEFT", f.bigHide, "TOPLEFT", 0, 5)
	f.restartAuction:SetPoint("BOTTOMRIGHT", f.bigHide, "TOPRIGHT", 0, 5)
	f.restartAuction:SetScript("OnClick", function(self)
		f:Hide()
		local itemLink = f.itemlink
		local itemID = tonumber(itemLink:match("|Hitem:(%d+):"))
		GDKPd:QueueAuction(itemLink, GDKPd:GetStartBid(itemID), GDKPd:GetMinIncrement(itemID), GDKPd.curAuction.index)
	end)
	f.restartAuction:Hide()
	f.cancelAuction = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.cancelAuction:SetText(L["Cancel auction"])
	f.cancelAuction:SetAllPoints(f.restartAuction)
	f.cancelAuction:SetScript("OnClick", function(self)
		GDKPd:CancelAuction(f.itemlink)
		self:Hide()
		f.reverseBid:Hide()
		f.bigHide:Show()
		f.restartAuction:Show()
	end)
	f.reverseBid = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.reverseBid:SetText(L["Revert highest bid"])
	f.reverseBid:SetAllPoints(f.bigHide)
	f.reverseBid:SetScript("OnClick", function(self)
		GDKPd:RevertHighestBid(f.itemlink)
	end)
	if (not self:PlayerIsML((UnitName("player")), true)) or self.opt.slimML then
		f.cancelAuction:Hide()
		f.reverseBid:Hide()
	end
	f.reverseBid:Disable()
	function f:SetItem(itemlink)
		self.icon:SetTexture((select(10,GetItemInfo(itemlink))))
		self.itemstring:SetText(itemlink)
		self:EnableMouse(true)
		self.autobid:Enable()
		self.bidbox:Enable()
		self.hide:Enable()
		self.highestbid:Hide()
		self.itemlink = itemlink
	end
	function f:SetCurBid(goldAmount, bidderName, isMine, isInitial)
		self.curbid:SetText((isInitial and L["Minimum bid: "] or L["Current bid: "])..goldAmount.."|cffffd100g|r")
		if bidderName and (not isMine) then
			self.highestbidder:Show()
			self.highestbidder:SetText(L["Highest bidder: %s"]:format(bidderName))
			self.highestbid:Hide()
		elseif isMine then
			self.highestbid:Show()
			self.highestbidder:Hide()
		else
			self.highestbid:Hide()
			self.highestbidder:Hide()
		end
		self.curbidamount = goldAmount-(isInitial and self.bidIncrement or 0)
		self.curbidismine = not not isMine
		self.curbid:Show()
		self.bidbox:Show()
		self.bid:Enable()
		if not isInitial then
			self.bid:Disable()
			if not isMine then
				self.bid.enabledelay.reenabletime = GetTime()+GDKPd.opt.bidButtonReenableDelay
				self.bid.enabledelay:Show()
			end
			if goldAmount > (self.initialBid or math.huge) then
				self.reverseBid:Enable()
			end
		else
			self.initialBid = goldAmount
		end
	end
	function f:SetAuctionTimer(timerDuration, timerResetDuration)
		if (not timerDuration) then return end
		local ctime = GetTime()
		self.timer:SetCooldown(ctime, timerDuration)
		self.timer.update.endTime = ctime+timerDuration
		self.timer[GDKPd.opt.showAuctionDurationTimer and "Show" or "Hide"](self.timer)
		self.timer.text[GDKPd.opt.showAuctionDurationTimerText and "Show" or "Hide"](self.timer.text)
		self.timer.update[GDKPd.opt.showAuctionDurationTimerText and "Show" or "Hide"](self.timer.update)
		self.timerDuration = timerDuration
		self.timerResetDuration = timerResetDuration or timerDuration
	end
	function f:ResetAuctionTimer()
		if not self.timerResetDuration then return end
		if (self.timerResetDuration+GetTime()) < self.timer.update.endTime then return end
		self.timer:SetCooldown(GetTime()-(self.timerDuration-self.timerResetDuration), self.timerDuration)
		self.timer.update.endTime = GetTime()+self.timerResetDuration
	end
	f:SetScript("OnEnter", function(self)
		GameTooltip:ClearAllPoints()
		GameTooltip:ClearLines()
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetHyperlink(self.itemlink)
		GameTooltip:SetPoint("RIGHT", self, "LEFT")
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:SetScale(self.opt.appearScale)
	f:SetAlpha(self.opt.appearAlpha)
	f.isActive = false
	function f:UpdateSize()
		if (self.bigHide:IsShown() or self.cancelAuction:IsShown()) then
			self:SetHeight(100)
		else
			self:SetHeight(60)
		end
	end
	f:UpdateSize()
	GDKPd.frames[c] = f
	return f
end

function GDKPd:UpdateAllVisibilities()
	status:UpdateVisibility()
	playerBalance:UpdateVisibility()
end

local defaults={profile={
	point={
		point="CENTER",
		relative="CENTER",
		x=0,
		y=0,
	},
	statuspoint={
		point="CENTER",
		relative="CENTER",
		x=0,
		y=0,
	},
	balancepoint={
		point="CENTER",
		relative="CENTER",
		x=0,
		y=-50,
	},
	playerbalancepoint={	
		point="CENTER",
		relative="CENTER",
		x=0,
		y=50,
	},
	customItemSettings={
	},
	itemLevelPricing={	
	},
	forceHideShow=true,
	countdownTimerJump=5,
	shareSecondEnable=false,
	shareSecondAmount=0.33,
	shareThirdEnable=false,
	shareThirdAmount=0.11,
	AdditionalRaidMembers=false,
	AdditonalRaidMembersAmount=0,
	auctionTimer=20,
	auctionTimerRefresh=20,
	movable=true,
	startBid=20,
	increment=5,
	minQuality=-1,
	autoAwardLoot=false,
	awardToML=false,
	showAuctionDurationTimer=true,
	showAuctionDurationTimerText=false,
	announceRaidWarning=true,
	announceBidRaidWarning=false,
	allowMultipleAuctions=false,
	announcePotAfterAuction=true,
	hideChatMessages={
		auctionAnnounce=false,
		auctionAnnounceRW=false,
		newBid=false,
		bidFinished=false,
		secondsRemaining=false,
		bidChats=false,
		potValues=false,
		auctionCancel=false,
		auctionCancelRW=false,
	},
	notifyVersions={
		notifyCompatibleOutdated=true,
		notifyIncompatibleOutdated=true,
		notifyNotInstalled=false,
	},
	hideCombat={
	},
	appearAlpha=1,
	appearScale=1,
	controlScale=1,
	bidButtonReenableDelay=0.2,
	slimML=false,
	slimMLConfirmed=false,
	confirmMailAll=true,
	confirmMail=false,
	linkBalancePot=false,
	debugLog=false,
	autoLootTracking = true,
	minQualityTracking=3,
}}

GDKPd.options={
	type="group",
	args={
		lock={
			type="toggle",
			name=L["Lock"],
			desc=L["Prevent dragging and hide anchor"],
			get=function() return not GDKPd.opt.movable end,
			set=function(info, value) GDKPd.opt.movable = not value GDKPd:SetMovable(not value) end,
			order=1,
			width="half",
		},
		show={
			type="toggle",
			name=L["Show"],
			desc=L["Show addon frames"],
			get=function() return not GDKPd.opt.hide end,
			set=function(info, value) GDKPd.opt.hide = not value GDKPd:UpdateAllVisibilities() end,
			order=2,
			width="half",
		},
		behaviour={
			type="group",
			name=L["Behaviour options"],
			args={
				startBid={
					type="range",
					name=L["Starting bid"],
					min=0,
					max=100000,
					softMax=10000,
					softMin=0,
					step=1,
					get=function() return GDKPd.opt.startBid end,
					set=function(info, value) GDKPd.opt.startBid = value end,
					order=1,
				},
				minIncrement={
					type="range",
					name=L["Minimum increment"],
					min=1,
					max=100000,
					softMax=2000,
					softMin=10,
					step=1,
					get=function() return GDKPd.opt.increment end,
					set=function(info, value) GDKPd.opt.increment = value end,
					order=2,
				},
				customSettings={
					type="execute",
					name=L["Per-item settings"],
					func=function() GDKPd.itemsettings:Show() LibStub("AceConfigDialog-3.0"):Close("GDKPd") end,
					order=2.5,
--					width="double",
				},
				customILvLSettings={
					type="execute",
					name=L["Item level settings"],
					func=function() GDKPd.itemLevels:Show() LibStub("AceConfigDialog-3.0"):Close("GDKPd") end,
					order=2.7,
--					width="double",
				},
				secondShare={
					dialogInline=true,
					name=L["Second bidder share"],
					order=3,
					type="group",
					args={
						isEnabled={
							order=1,
							type="toggle",
							name=L["Enable"],
							set=function(info,value) GDKPd.opt.shareSecondEnable = value end,
							get=function() return GDKPd.opt.shareSecondEnable end,
						},
						shareAmount={
							order=2,
							type="range",
							name=L["Amount"],
							min=0.01,
							max=0.99,
							isPercent=true,
							set=function(info, value) GDKPd.opt.shareSecondAmount = value end,
							get=function() return GDKPd.opt.shareSecondAmount end,
						},
					},
				},
				thirdShare={
					dialogInline=true,
					name=L["Third bidder share"],
					order=4,
					type="group",
					args={
						isEnabled={
							order=1,
							type="toggle",
							name=L["Enable"],
							set=function(info,value) GDKPd.opt.shareThirdEnable = value end,
							get=function() return GDKPd.opt.shareThirdEnable end,
						},
						shareAmount={
							order=2,
							type="range",
							name=L["Amount"],
							min=0.01,
							max=0.99,
							isPercent=true,
							set=function(info, value) GDKPd.opt.shareThirdAmount = value end,
							get=function() return GDKPd.opt.shareThirdAmount end,
						},
					},
				},
				AdditionalRaidMembers={
					dialogInline=true,
					name=L["Additional Raid Members"],
					order=5,
					type="group",
					args={
						isEnabled={
							order=1,
							type="toggle",
							name=L["Enable"],
							set=function(info,value) GDKPd.opt.AdditionalRaidMembersEnable = value end,
							get=function() return GDKPd.opt.AdditionalRaidMembersEnable end,
						},
						shareAmount={
							order=2,
							type="range",
							name=L["Amount"],
							min=0,
							max=40,
							step=1,
							isPercent=false,
							set=function(info, value) GDKPd.opt.AdditonalRaidMembersAmount = value end,
							get=function() return GDKPd.opt.AdditonalRaidMembersAmount end,
						},
					},
				},
				minQuality={
					type="select",
					values=function()
						local vtab={}
						for key, tab in pairs(ITEM_QUALITY_COLORS) do
							if _G["ITEM_QUALITY"..key.."_DESC"] then
								vtab[key] = tab.hex.._G["ITEM_QUALITY"..key.."_DESC"].."|r"
							end
						end
						vtab[-1] = "|cffaa2222"..L["Use looting system loot threshold setting"].."|r"
						return vtab
					end,
					name=L["Minimum quality"],
					set=function(info, value) GDKPd.opt.minQuality = value end,
					get=function() return GDKPd.opt.minQuality end,
					order=6,
					width="full",
				},
				auctionTimer={
					type="range",
					softMin=5,
					softMax=30,
					order=7,
					name=L["Auction timeout"],
					desc=L["The amount of seconds that have to pass before the auction is closed without bids recieved"],
					set=function(info, value) GDKPd.opt.auctionTimer = value end,
					get=function() return GDKPd.opt.auctionTimer end,
				},
				auctionTimerRefresh={
					type="range",
					softMin=5,
					softMax=30,
					order=8,
					name=L["Auction bid timeout refresh"],
					desc=L["The amount of seconds that have to pass after a bid before the auction is closed"],
					set=function(info, value) GDKPd.opt.auctionTimerRefresh = value end,
					get=function() return GDKPd.opt.auctionTimerRefresh end,
				},
				countdownTimerJump={
					type="range",
					softMin=1,
					softMax=10,
					order=8.5,
					name=L["Countdown timer announce interval"],
					desc=L["The amount of seconds between each announcement of the remaining time"],
					set=function(info, value) GDKPd.opt.countdownTimerJump = value end,
					get=function() return GDKPd.opt.countdownTimerJump end,
				},
				autoAward={
					type="toggle",
					name=L["Auto-award loot to winner"],
					set=function(info, value) GDKPd.opt.autoAwardLoot = value end,
					get=function() return GDKPd.opt.autoAwardLoot end,
					width="full",
					order=9,
					disabled=function() return not not GDKPd.opt.awardToML end,
				},
				awardToML={
					type="toggle",
					name=L["Award loot to Master Looter when auto-auctioning"],
					set=function(info, value) GDKPd.opt.awardToML = value end,
					get=function() return GDKPd.opt.awardToML end,
					width="full",
					order=10,
					disabled=function() return not not GDKPd.opt.autoAwardLoot end,
				},
				announceRW={
					type="toggle",
					name=L["Announce auction start to raid warning"],
					set=function(info, value) GDKPd.opt.announceRaidWarning = value end,
					get=function() return GDKPd.opt.announceRaidWarning end,
					width="full",
					order=11,
				},
				announceRWBid={
					type="toggle",
					name=L["Announce bids to raid warning"],
					width="full",
					set=function(info, value) GDKPd.opt.announceBidRaidWarning = value end,
					get=function() return GDKPd.opt.announceBidRaidWarning end,
					order=12,
				},
				allowMultiple={
					type="toggle",
					name=L["Allow multiple simultanous auctions"],
					width="full",
					set=function(info, value) GDKPd.opt.allowMultipleAuctions = value end,
					get=function() return GDKPd.opt.allowMultipleAuctions end,
					disabled=function() return ((GDKPd.curAuctions and (#GDKPd.curAuctions > 0)) or (GDKPd.curAuction.item)) end,
					order=13,
				},
				announcePotAfterAuction={
					type="toggle",
					name=L["Announce the current pot amount after each auction"],
					width="full",
					set=function(info, value) GDKPd.opt.announcePotAfterAuction = value end,
					get=function() return GDKPd.opt.announcePotAfterAuction end,
					order=14,
				},
				confirmMail={
					type="toggle",
					name=L["Require confirmation when mailing pot shares"],
					width="full",
					set=function(info, value) GDKPd.opt.confirmMail = value end,
					get=function() return GDKPd.opt.confirmMail end,
					order=15,
				},
				linkBalancePot={
					type="toggle",
					name=L["Link raid member balance to pot"],
					desc=L["Any money subtracted from raid members is added to the pot and vice versa"],
					width="full",
					set=function(info, value) GDKPd.opt.linkBalancePot = value end,
					get=function() return GDKPd.opt.linkBalancePot end,
					order=16,
				},
				debugLog={
					type="toggle",
					name="Debug logging",
					desc="Turn on debug logging of the addon",
					width="full",
					set=function(info, value) GDKPd.opt.debugLog = value end,
					get=function() return GDKPd.opt.debugLog end,
					order=17,
				},
				autoLootTracking={
					type="toggle",
					name="Auto Loot Tracking",
					desc="Turn on to auto track loot",
					width="full",
					set=function(info, value) GDKPd.opt.autoLootTracking = value end,
					get=function() return GDKPd.opt.autoLootTracking end,
					order=18,
				},
				minQualityTracking={
					type="select",
					values=function()
						local vtab={}
						for key, tab in pairs(ITEM_QUALITY_COLORS) do
							if _G["ITEM_QUALITY"..key.."_DESC"] then
								vtab[key] = tab.hex.._G["ITEM_QUALITY"..key.."_DESC"].."|r"
							end
						end
						return vtab
					end,
					name="Item Drop Quality to track",
					set=function(info, value) GDKPd.opt.minQualityTracking = value end,
					get=function() return GDKPd.opt.minQualityTracking end,
					order=19,
				},
			},
			order=1,
		},
		appearance={
			type="group",
			name=L["Appearance options"],
			args={
				showtimer={
					set=function(info, value) GDKPd.opt.showAuctionDurationTimer = value end,
					get=function() return GDKPd.opt.showAuctionDurationTimer end,
					type="toggle",
					name=L["Show auction duration spiral"],
					width="full",
					order=1,
				},
				showtimertext={
					disabled=function() return not GDKPd.opt.showAuctionDurationTimer end,
					set=function(info, value) GDKPd.opt.showAuctionDurationTimerText = value end,
					get=function() return GDKPd.opt.showAuctionDurationTimerText end,
					type="toggle",
					name=L["Show countdown text on auction duration spiral"],
					width="full",
					order=2,
				},
				hideChats={
					type="multiselect",
					name=L["Hide chat messages"],
					values={
						auctionAnnounce=L["Hide 'Bidding starts' announcements"],
						auctionAnnounceRW=L["Hide 'Bidding starts' announcements from raid warning"],
						newBid=L["Hide 'New highest bidder' announcements"],
						secondsRemaining=L["Hide 'Time remaining' announcements"],
						bidFinished=L["Hide 'Auction finished' announcements"],
						bidChats=L["Hide players' bid messages"],
						potValues=L["Hide 'Current pot:' announcements"],
						auctionCancel=L["Hide 'Auction cancelled' announcements"],
						auctionCancelRW=L["Hide 'Auction cancelled' announcements from raid warning"],
					},
					set=function(info, key, value) GDKPd.opt.hideChatMessages[key]=value end,
					get=function(info, key) return GDKPd.opt.hideChatMessages[key] end,
					order=3,
					width="full",
				},
				frameAlpha={
					type="range",
					min=0,
					max=1,
					bigStep=0.1,
					name=L["Frame alpha"],
					order=4,
					set=function(info, value) GDKPd.opt.appearAlpha = value for _, f in ipairs(GDKPd.frames) do f:SetAlpha(value) end end,
					get=function() return GDKPd.opt.appearAlpha end,
				},
				frameScale={
					type="range",
					min=0.01,
					softMin=0.5,
					softMax=2,
					name=L["Frame scale"],
					order=5,
					set=function(info, value) GDKPd.opt.appearScale = value for _, f in ipairs(GDKPd.frames) do f:SetScale(value) end GDKPd_Anchor:SetScale(value) end,
					get=function() return GDKPd.opt.appearScale end,
				},
				bidButtonReenableDelay={	
					type="range",
					min=0,
					max=10,
					softMax=1,
					softMin=0,
					name=L["Bid button re-enable delay"],
					order=6,
					set=function(info, value) GDKPd.opt.bidButtonReenableDelay = value end,
					get=function() return GDKPd.opt.bidButtonReenableDelay end,
				},
				controlScale={
					type="range",
					min=0.01,
					softMin=0.5,
					softMax=2,
					name=L["Control panel scale"],
					order=7,
					set=function(info, value)
						GDKPd.opt.controlScale = value
						GDKPd.status:SetScale(value)
						GDKPd.history:SetScale(value)
						GDKPd.version:SetScale(value)
					end,
					get=function() return GDKPd.opt.controlScale end,
				},
				useSlimML={
					type="toggle",
					set=function(info, value) if value and (not GDKPd.opt.slimMLConfirmed) then StaticPopup_Show("GDKPD_SLIMMLWARN") else GDKPd.opt.slimML = value end end,
					get=function() return GDKPd.opt.slimML end,
					name=L["Use slim bidding window even while Master Looter"],
					width="full",
					order=8,
				},
				forceHideShow={
					type="toggle",
					set=function(info, value) GDKPd.opt.forceHideShow = value for _,f in ipairs(GDKPd.frames) do f.hide:SetAlpha(value and 1 or 0) end end,
					get=function() return GDKPd.opt.forceHideShow end,
					order=8.5,
					width="full",
					name=L["Always show the \"Hide\" button on bid frames"],
				},
				anchorBalance={
					type="toggle",
					set=function(info, value) GDKPd.opt.anchorBalance = value GDKPd.balance:UpdatePosition() end,
					get=function() return GDKPd.opt.anchorBalance end,
					name=L["Anchor balance window to status window"],
					width="full",
					order=9,
				},
			},
			order=2,
		},
		notification={
			type="group",
			name=L["Notification options"],
			args={
				rules={
					type="input",
					name=L["Rules"],
					order=1,
					multiline=true,
					get=function() return GDKPd.opt.rulesString or "" end,
					set=function(info, value)
						GDKPd.opt.rulesString = strlen(value) > 0 and value
						if GDKPd.opt.rulesString then
							GDKPd.status.rules:Enable()
						else
							GDKPd.status.rules:Disable()
						end
					end,
					width="full",
				},
				notifyVersions={
					type="multiselect",
					name=L["Version notifications"],
					values={
						notifyCompatibleOutdated=L["Notify outdated versions that are compatible with your version"],
						notifyIncompatibleOutdated=L["Notify outdated versions that aren't compatible with your version"],
						notifyNotInstalled=L["Notify raid members that do not have GDKPd installed"],
					},
					set=function(info, key, value) GDKPd.opt.notifyVersions[key]=value end,
					get=function(info, key) return GDKPd.opt.notifyVersions[key] end,
					order=2,
					width="full",
				},
			},
			order=3,
		},
		visibility={
			type="group",
			name=L["Visibility settings"],
			args={
				hideCombatFrames={
					type="multiselect",
					name=L["Hide frames in combat"],
					values={
						status=L["Hide status and balance windows"],
						history=L["Hide history window"],
						vercheck=L["Hide version check window"],
					},
					set=function(info, key, value)
						GDKPd.opt.hideCombat[key]=value
						GDKPd.status:UpdateVisibility()
						GDKPd.playerBalance:UpdateVisibility()
						if InCombatLockdown() then
							if key == "history" and value then
								GDKPd.history:Hide()
							end
							if key == "vercheck" and value then
								GDKPd.version:Hide()
							end
						end
					end,
					get=function(info, key) return GDKPd.opt.hideCombat[key] end,
					order=1,
					width="full",
				},
			},
			order=4,
		},
	},
}

function GDKPd:OnProfileEnable()
	self.opt = self.db.profile
	for _, f in ipairs(self.frames) do
		f:SetAlpha(self.opt.appearAlpha)
		f:SetScale(self.opt.appearScale)
	end
	GDKPd_Anchor:SetScale(self.opt.appearScale)
end

GDKPd:SetScript("OnEvent", function(self, event, ...)
	local arg = emptytable(...)
	if event == "ADDON_LOADED" and arg[1] == "GDKPd_Reforged" then
		self:UnregisterEvent("ADDON_LOADED")
		local isFirstLogin = not (GDKPd_PotData or GDKPd_BalanceData)
		GDKPd_PotData = GDKPd_PotData or {history={},potAmount=0}
		--seperate line for savedvar upgrading purposes
		GDKPd_PotData.curPotHistory = GDKPd_PotData.curPotHistory or {}
		GDKPd_PotData.playerBalance = GDKPd_PotData.playerBalance or {}
		setmetatable(GDKPd_PotData.playerBalance, {__index=function() return 0 end})
		GDKPd_BalanceData = GDKPd_BalanceData or {}
		setmetatable(GDKPd_BalanceData, {__index=function() return 0 end})
--		self.status:Update()
		self.db = LibStub("AceDB-3.0"):New("GDKPd_DB", defaults or {})
		self.db.RegisterCallback(self,"OnProfileChanged","OnProfileEnable")
		self.db.RegisterCallback(self,"OnProfileCopied","OnProfileEnable")
		self.db.RegisterCallback(self,"OnProfileReset","OnProfileEnable")
		self.opt = self.db.profile
		if not self.db.global.shownPopupAddonMsg4_2 then
			self.db.global.shownPopupAddonMsg4_2 = true
			if not isFirstLogin then
				-- the user has moved the window, so he's already logged in
				-- at least i hope nobody will have their GDKPd windows in the center of their screen
				StaticPopup_Show("GDKPD_42_ADDONMSG")
			end
		end
		GDKPd_Anchor:SetScale(self.opt.appearScale)
		self.status:SetScale(self.opt.controlScale)
		if self.opt.rulesString then
			self.status.rules:Enable()
		else
			self.status.rules:Disable()
		end
		self.history:SetScale(self.opt.controlScale)
		self.version:SetScale(self.opt.controlScale)
		self.options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
		self.options.args.profiles.order = -1
		LibStub("AceConfig-3.0"):RegisterOptionsTable("GDKPd", self.options)
		SlashCmdList["GDKPD"] = function(input)
			local cmd, link = input:match("(%S+)%s+(|c........|Hitem:.+|r)")
			if (cmd and cmd == "auction") and link then
				--call DoAuction
				self:AddItemToPot(link, 0, "unassigned", true)
				GDKPd:bidLoot_click()
				--[[ if self:PlayerIsML((UnitName("player")),true) then
					for itemLink in string.gmatch(link, "|c........|Hitem:.-|r") do
						local itemID = tonumber(itemLink:match("|Hitem:(%d+):"))
						self:QueueAuction(itemLink, GDKPd:GetStartBid(itemID), GDKPd:GetMinIncrement(itemID))
					end
				else
					print(L["Cannot start auction without Master Looter privileges."])
				end ]]
			elseif input:lower() == "ver" then
				print(L["GDKPd version %s. Packaged %s."]:format(DEBUGFORCEVERSION or "2.0.0","2020-01-01T00:00:00Z"))
			elseif input:lower() == "history" then
				GDKPd.history:Show()
			elseif input:lower() == "wipe" then
				StaticPopup_Show("GDKPD_WIPEHISTORY")
			elseif input:lower() == "vercheck" then
				GDKPd.version:Show()
			else
				--LibStub("AceConfigDialog-3.0"):Open("GDKPd")
				self:PotLogTableUpdate();
				self.status:Show();
				
			end
		end
		SLASH_GDKPD1 = "/gdkpd"
		SLASH_GDKPD2 = "/gdkp"
		anchor:SetPoint(self.opt.point.point, UIParent, self.opt.point.relative, self.opt.point.x, self.opt.point.y)
		self:SetMovable(self.opt.movable)
		self.status.header:SetPoint(self.opt.statuspoint.point, UIParent, self.opt.statuspoint.relative, self.opt.statuspoint.x, self.opt.statuspoint.y)
		--self.balance.header:SetPoint(self.opt.balancepoint.point, UIParent, self.opt.balancepoint.relative, self.opt.balancepoint.x, self.opt.balancepoint.y)
		self.balance:UpdatePosition()
		self.playerBalance.header:SetPoint(self.opt.playerbalancepoint.point, UIParent, self.opt.playerbalancepoint.relative, self.opt.playerbalancepoint.x, self.opt.playerbalancepoint.y)
		self.playerBalance:Update()
		self.status:UpdateVisibility()
	end
	if (event == "CHAT_MSG_RAID") or (event == "CHAT_MSG_RAID_LEADER") or (event == "CHAT_MSG_RAID_WARNING") then
		local msg,sender = arg[1],pruneCrossRealm(arg[2])
		--this is code for single-auction mode. put into a do branch to avoid local clashes.
		do
			local itemLink, minBid, bidIncrement, auctionTimer, auctionTimerRefresh = string.match(msg, "Bidding starts on (|c........|Hitem:.+|r). Please bid in raid chat, starting bid (%d+) gold, minimum increment (%d+) gold. TTL: (%d+)/(%d+)")
			if not itemLink then
				-- backwards comp number three
				itemLink, minBid, bidIncrement, auctionTimer, auctionTimerRefresh = string.match(msg, "Bidding starts on (|c........|Hitem:.+|r). Please bid in raid chat, starting bid (%d+) gold, minimum increment (%d+) gold. TTL until expire: (%d+) seconds, TTL after bid: (%d+) seconds.")
			end
			if not itemLink then
				-- backwords compability strikes again
				itemLink, minBid, bidIncrement, auctionTimer = string.match(msg, "Bidding starts on (|c........|Hitem:.+|r). Please bid in raid chat, starting bid (%d+) gold, minimum increment (%d+) gold. TTL after a bid is placed: (%d+) seconds.")
				auctionTimerRefresh=auctionTimer
			end
			if not itemLink then
				-- backwards version compability
				itemLink, minBid, bidIncrement = string.match(msg, "Bidding starts on (|c........|Hitem:.+|r). Please bid in raid chat, starting bid (%d+) gold, minimum increment (%d+) gold.")
				auctionTimer = 0
				auctionTimerRefresh=0
			end
			auctionTimer = tonumber(auctionTimer) or 0
			auctionTimerRefresh = tonumber(auctionTimerRefresh) or 0
			if itemLink and self:PlayerIsML(sender, false) then
				if not self.ignoredLinks[itemLink] then
					local f = GDKPd:FetchFrameFromLink(itemLink)
					if not f then
						f = self:GetUnoccupiedFrame()
						f:SetItem(itemLink)
						f.isActive = true
						f:Show()
					end
					f.isMultiBid = false
					self.InProgressBidFrame = f
					f.bidIncrement = bidIncrement
					f:SetCurBid(minBid, false, false, true)
					f:SetAuctionTimer(auctionTimer, auctionTimerRefresh)
					if f.maxAutoBid then
						local newBid = tonumber(minBid)
						if newBid < f.maxAutoBid then
							SendChatMessage(tostring(newBid),"RAID")
						end
					end
				else
					self.ignoredLinks[itemLink] = nil
				end
			end
			if self.curAuction.item and msg:find("%d+") == 1 then
				local newBid = tonumber(msg:match("([0-9]+%.?[0-9]*)[kK]"))
				if not newBid then
					newBid = tonumber(msg:match("%d+"))
				else
					newBid = math.floor(newBid*1000)
				end

				-- Ignore obnoxiously large numbers, they break %d formats and are over gold cap anyway
				if newBid < 999999999 and (self.curAuction.curBid + self.curAuction.increment) <= newBid then
					GDKPd.curAuction.curBid = newBid
					if GDKPd.curAuction.bidders[sender] then
						GDKPd.curAuction.bidders[GDKPd.curAuction.bidders[sender]].bidAmount = newBid
					else
						tinsert(GDKPd.curAuction.bidders, {bidAmount=newBid, bidderName=sender})
						GDKPd.curAuction.bidders[sender] = #GDKPd.curAuction.bidders
					end
					SendChatMessage(("New highest bidder: %s (%d gold)"):format(sender, newBid),(self.opt.announceBidRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
					self.curAuction.timeRemains = math.max(self.opt.auctionTimerRefresh, self.curAuction.timeRemains)
				end
			end
			local bidderName, newBid = string.match(msg, "New highest bidder: (%S+) %((%d+) gold%)")
			if bidderName and self.InProgressBidFrame then
				local isSelf = pruneCrossRealm(bidderName) == (UnitName("player"))
				self.InProgressBidFrame:SetCurBid(newBid, bidderName, isSelf)
				self.InProgressBidFrame:ResetAuctionTimer()
				if not isSelf then
					if self.InProgressBidFrame.maxAutoBid then
						local myNewBid = newBid+self.InProgressBidFrame.bidIncrement
						if myNewBid <= self.InProgressBidFrame.maxAutoBid then
							SendChatMessage(tostring(myNewBid),"RAID")
						end
					end
				end
			end
			if msg:find("Auction finished.") and GDKPd:PlayerIsML(sender,false) and self.InProgressBidFrame then
				self.InProgressBidFrame:Hide()
				self.InProgressBidFrame.isActive = false
				self.InProgressBidFrame = nil
				local winnerName, paymentString = msg:match("Auction finished. Winner: (%S+). (.+).")
				if winnerName then
					if pruneCrossRealm(winnerName) == (UnitName("player")) then
						for targetAmount, targetName in paymentString:gmatch("(%d+) to (%S+)[%.,]") do
							local tarName = pruneCrossRealm(targetName)
							if GDKPd:PlayerIsML((UnitName("player")),true) then
								GDKPd_PotData.playerBalance[tarName == "pot" and sender or tarName] = GDKPd_PotData.playerBalance[tarName == "pot" and sender or tarName] + targetAmount
								GDKPd.balance:Update()
							else
								GDKPd_BalanceData[tarName == "pot" and sender or tarName] = GDKPd_BalanceData[tarName == "pot" and sender or tarName] + targetAmount
								GDKPd.playerBalance:Update()
							end
						end
					else
						for targetAmount, targetName in paymentString:gmatch("(%d+) to (%S+)[%.,]") do
							if pruneCrossRealm(targetName) == (UnitName("player")) then
								if GDKPd:PlayerIsML((UnitName("player")),true) then
									GDKPd_PotData.playerBalance[winnerName] = GDKPd_PotData.playerBalance[winnerName]-targetAmount
									GDKPd.balance:Update()
								else
									GDKPd_BalanceData[winnerName] = GDKPd_BalanceData[winnerName]-targetAmount
									GDKPd.playerBalance:Update()
								end
							end
						end
					end
				end
			end
			if msg:find("Auction cancelled.") and GDKPd:PlayerIsML(sender, false) and self.InProgressBidFrame then
				self.InProgressBidFrame.isActive = false
				if GDKPd:PlayerIsML((UnitName("player")),true) then
					local f = self.InProgressBidFrame
					self.InProgressBidFrame = nil
					f.timer:Hide()
					f.timer.update:Hide()
					f.curbid:Hide()
					f.highestbidder:Hide()
					f.highestbid:Hide()
					f.bidbox:Hide()
					f.bid:Disable()
					f.autobid:Disable()
				else
					self.InProgressBidFrame:Hide()
				end
			end
		end
		-- this is new code for multi-auction. slight variations are used rl-side to indicate this.
		do
			local itemLink, minBid, bidIncrement, auctionTimer, auctionTimerRefresh = string.match(msg, "Bidding starts on (|c........|Hitem:.+|r). Bid using format '%[item%] 1000', starting bid (%d+) gold, minimum increment (%d+) gold. TTL: (%d+)/(%d+)")
			if not itemLink then
				-- backwards to non-shortened
				itemLink, minBid, bidIncrement, auctionTimer, auctionTimerRefresh = string.match(msg, "Bidding starts on (|c........|Hitem:.+|r). Bid using format '%[item%] 1000', starting bid (%d+) gold, minimum increment (%d+) gold. TTL until expire: (%d+) seconds, TTL after bid: (%d+) seconds.")
			end
			if not itemLink then
				itemLink, minBid, bidIncrement, auctionTimer = string.match(msg, "Bidding starts on (|c........|Hitem:.+|r). Please bid in raid chat, using format 'itemlink bid'. Starting bid (%d+) gold, minimum increment (%d+) gold. TTL after a bid is placed: (%d+) seconds.")
				auctionTimerRefresh = auctionTimer
			end
			auctionTimer = tonumber(auctionTimer) or 0
			auctionTimerRefresh = tonumber(auctionTimerRefresh) or 0
			if itemLink and self:PlayerIsML(sender,false) then
				if not self.ignoredLinks[itemLink] then
					local f = GDKPd:FetchFrameFromLink(itemLink)
					if not f then
						f = self:GetUnoccupiedFrame()
						f:SetItem(itemLink)
						f.isActive = true
						f:Show()
					end
					f.isMultiBid = true
					f.bidIncrement = bidIncrement
					f:SetCurBid(minBid, false, false, true)
					f:SetAuctionTimer(auctionTimer, auctionTimerRefresh)
					if f.maxAutoBid then
						local newBid = tonumber(minBid)
						if newBid < f.maxAutoBid then
							SendChatMessage(itemLink.." "..newBid)
						end
					end
				else
					self.ignoredLinks[itemLink] = nil
				end
			end
			local bidItemLink, bidAmount = msg:match("(|c........|Hitem:.+|r)%s*([0-9]+%.?[0-9]*)[kK]")
			if not bidItemLink then
				bidItemLink, bidAmount = msg:match("(|c........|Hitem:.+|r)%s*(%d+)")
			else
				bidAmount = math.floor(bidAmount*1000)
			end
			if bidItemLink then
				if self.curAuctions[bidItemLink] then
					local aucdata = self.curAuctions[bidItemLink]
					bidAmount = tonumber(bidAmount)
					if (aucdata.curBid+aucdata.increment) <= bidAmount then
						aucdata.curBid = bidAmount
						if aucdata.bidders[sender] then
							aucdata.bidders[aucdata.bidders[sender]].bidAmount = bidAmount
						else
							tinsert(aucdata.bidders, {bidAmount=bidAmount, bidderName=sender})
							aucdata.bidders[sender] = #aucdata.bidders
						end
						SendChatMessage(("New highest bidder on %s: %s (%d gold)"):format(bidItemLink,sender,bidAmount),(self.opt.announceBidRaidWarning and (IsRaidOfficer() or IsRaidLeader())) and "RAID_WARNING" or "RAID")
						aucdata.timeRemains = math.max(aucdata.timeRemains, self.opt.auctionTimerRefresh)
					end
				end
			end
			local bidItem, bidderName, newBid = string.match(msg, "New highest bidder on (|c........|Hitem:.+|r): (%S+) %((%d+) gold%)")
			if bidderName and self:FetchFrameFromLink(bidItem) then
				local isSelf = pruneCrossRealm(bidderName) == (UnitName("player"))
				local bidFrame = self:FetchFrameFromLink(bidItem)
				bidFrame:SetCurBid(newBid, bidderName, isSelf)
				bidFrame:ResetAuctionTimer()
				if not isSelf then
					if bidFrame.maxAutoBid then
						local myNewBid = newBid+bidFrame.bidIncrement
						if myNewBid <= bidFrame.maxAutoBid then
							SendChatMessage(bidItem.." "..myNewBid, "RAID")
						end
					end
				end
			end
			local auctionEndItem = msg:match("Auction finished for (|c........|Hitem:.+|r).")
			if auctionEndItem and GDKPd:PlayerIsML(sender,false) and self:FetchFrameFromLink(auctionEndItem) then
				local f = self:FetchFrameFromLink(auctionEndItem)
				f.isActive = false
				f:Hide()
				local winnerName, paymentString = msg:match("Auction finished for |c........|Hitem:.+|r%. Winner: (%S+)%. (.+)")
				if winnerName then
					if pruneCrossRealm(winnerName) == (UnitName("player")) then
						for targetAmount, targetName in paymentString:gmatch("(%d+) to (%S+)[%.,]") do
							local tarName = pruneCrossRealm(targetName)
							if GDKPd:PlayerIsML((UnitName("player")),true) then
								GDKPd_PotData.playerBalance[tarName == "pot" and sender or tarName] = GDKPd_PotData.playerBalance[tarName == "pot" and sender or tarName] + targetAmount
								GDKPd.balance:Update()
							else
								GDKPd_BalanceData[tarName == "pot" and sender or tarName] = GDKPd_BalanceData[tarName == "pot" and sender or tarName] + targetAmount
								GDKPd.playerBalance:Update()
							end
						end
					else
						for targetAmount, targetName in paymentString:gmatch("(%d+) to (%S+)[%.,]") do
							if pruneCrossRealm(targetName) == (UnitName("player")) then
								if GDKPd:PlayerIsML((UnitName("player")),true) then
									GDKPd_PotData.playerBalance[winnerName] = GDKPd_PotData.playerBalance[winnerName]-targetAmount
									GDKPd.balance:Update()
								else
									GDKPd_BalanceData[winnerName] = GDKPd_BalanceData[winnerName]-targetAmount
									GDKPd.playerBalance:Update()
								end
							end
						end
					end
				end
			end
			local auctionCancelItem = msg:match("Auction cancelled for (|c........|Hitem:.+|r)%.")
			if auctionCancelItem and GDKPd:PlayerIsML(sender, false) and self:FetchFrameFromLink(auctionCancelItem) then
				local f = self:FetchFrameFromLink(auctionCancelItem)
				f.isActive = false
				if GDKPd:PlayerIsML((UnitName("player")), true) then
					f.timer:Hide()
					f.timer.update:Hide()
					f.curbid:Hide()
					f.highestbidder:Hide()
					f.highestbid:Hide()
					f.bidbox:Hide()
					f.bid:Disable()
					f.autobid:Disable()
				else
					f:Hide()
				end
			end
		end
		-- generic code for both auction modes
		do
			local potAmount = msg:match("Distributing pot. Pot size: %d+ gold. Amount to distribute: %d+ gold. Players in raid: %d+. Share per player: (%d+) gold.")
			if not potAmount then
				potAmount = msg:match("Distributing pot. Pot size: %d+ gold. Players in raid: %d+. Pot share per player: (%d+) gold.")
			end
			if potAmount and self:PlayerIsML(sender,false) then
				GDKPd_BalanceData[sender] = GDKPd_BalanceData[sender]-potAmount
				GDKPd.playerBalance:Update()
			end
		end
	end
	if (event == "CHAT_MSG_ADDON") then
		local sender = pruneCrossRealm(arg[4])
		if sender then
			if arg[1] == "GDKPD START" and self:PlayerIsML(sender,false) then
				if not self:FetchFrameFromLink(arg[2]) then
					local f = self:GetUnoccupiedFrame()
					f.isActive = true
					f:SetItem(arg[2])
					f:Show()
				end
			end
			if arg[1] == "GDKPD VREQ" then
				SendAddonMessage("GDKPD VDATA", DEBUGFORCEVERSION or "2.0.0", "WHISPER", arg[4])
			end
			if arg[1] == "GDKPD VDATA" then
				self.versions[sender] = arg[2]
				self.version:Update()
			end
			if arg[1] == "GDKPD MANADJ" and self:PlayerIsML(sender,false) then
				GDKPd_BalanceData[sender] = GDKPd_BalanceData[sender]+arg[2]
				GDKPd.playerBalance:Update()
			end
		end
	end
	if (event == "LOOT_CLOSED") then
		self.status.announcetext:Hide()
		self.status.announce1:Hide()
		self.status.announce2:Hide()
		self.status.noannounce:Hide()
		self.status:UpdateSize()
	end
	if (event == "LOOT_OPENED") and self:PlayerIsML((UnitName("player")), true) then
		self.status.announcetext:Show()
		self.status.announce1:Show()
		self.status.announce2:Show()
		self.status.noannounce:Show()
		self.status:UpdateSize()
	end
	if (event == "GROUP_ROSTER_UPDATE") or (event == "PARTY_LOOT_METHOD_CHANGED") then
		self.status:UpdateVisibility()
		--[[if self:PlayerIsML((UnitName("player")),true) then
			self.status:Show()
		else
			self.status:Hide()
		end--]]
	end
	if (event == "UNIT_NAME_UPDATE") then
		if UnitIsUnit("player",arg[1]) then
			self:UnregisterEvent("UNIT_NAME_UPDATE")
			self.status:UpdateVisibility()
		end
	end
	if (event == "TRADE_CLOSED") then
		self.isTrading = false
	end
	if (event == "TRADE_SHOW") then
		self.isTrading = true
		self.tradePartner = (GetUnitName("npc",true))
		self.tradeMoneySelf = 0
		self.tradeMoneyOther = 0
		self.balance:Update()
	end
	if (event == "TRADE_ACCEPT_UPDATE") and (arg[1] == 1) then
		self.tradeMoneySelf = GetPlayerTradeMoney()/10000
	end
	if (event == "TRADE_MONEY_CHANGED") then
		self.tradeMoneyOther = GetTargetTradeMoney()/10000
	end
	if (event == "UI_INFO_MESSAGE") then
		if arg[2] == ERR_TRADE_COMPLETE then
			--if self:PlayerIsML((UnitName("player")),true) and GDKPd_PotData.playerBalance[self.tradePartner] ~= 0 then
			if self:PlayerIsML((UnitName("player")),true) then
				if GDKPd_PotData.playerBalance[self.tradePartner] ~= 0 then
					local moneyChange = (self.tradeMoneyOther)-(self.tradeMoneySelf)
					local curBalancePot, curBalancePlayer = GDKPd_PotData.playerBalance[self.tradePartner], GDKPd_BalanceData[self.tradePartner]
					if moneyChange > 0 then
						--[[if curBalancePot+moneyChange > 0 then
							moneyChange = moneyChange-(curBalancePot*(-1))
							GDKPd_PotData.playerBalance[self.tradePartner] = 0
							if (curBalancePlayer ~= 0 or GetRealNumRaidMembers() > 0) then
								GDKPd_BalanceData[self.tradePartner] = curBalancePlayer+moneyChange
							end
						else--]]
							GDKPd_PotData.playerBalance[self.tradePartner] = curBalancePot+moneyChange
						--end
					elseif moneyChange < 0 then
						--[[if curBalancePot+moneyChange < 0 then
							moneyChange = moneyChange+(curBalancePot*(-1))
							GDKPd_PotData.playerBalance[self.tradePartner] = 0
							if (curBalancePlayer ~= 0 or GetRealNumRaidMembers() > 0) then
								GDKPd_BalanceData[self.tradePartner] = curBalancePlayer+moneyChange
							end
						else--]]
							GDKPd_PotData.playerBalance[self.tradePartner] = curBalancePot+moneyChange
						--end
					end
				end
			elseif GDKPd_BalanceData[self.tradePartner] ~= 0 then
				GDKPd_BalanceData[self.tradePartner] = GDKPd_BalanceData[self.tradePartner]-(self.tradeMoneySelf)+(self.tradeMoneyOther)
			end
			GDKPd.balance:Update()
			GDKPd.playerBalance:Update()
		end
	end
	if (event == "PLAYER_REGEN_ENABLED") then
		self.status:UpdateVisibility(false)
		self.playerBalance:UpdateVisibility(false)
	end
	if (event == "PLAYER_REGEN_DISABLED") then
		self.status:UpdateVisibility(true)
		self.playerBalance:UpdateVisibility(true)
	end
	if (event == "MAIL_CLOSED") or (event == "MAIL_INBOX_UPDATE") then
		self.balance:Update()
	end
	if (event == "CHAT_MSG_LOOT") then
        if GDKPd.opt.autoLootTracking then 
			chatmsg = arg[1]
			GDKPd_Debug("Loot event received. Processing...");
			-- patterns LOOT_ITEM / LOOT_ITEM_SELF are also valid for LOOT_ITEM_MULTIPLE / LOOT_ITEM_SELF_MULTIPLE - but not the other way around - try these first
			-- first try: somebody else received multiple loot (most parameters)
			local playerName, itemLink, itemCount = deformat(chatmsg, LOOT_ITEM_MULTIPLE);
			-- next try: somebody else received single loot
			if (playerName == nil) then
				itemCount = 1;
				playerName, itemLink = deformat(chatmsg, LOOT_ITEM);
			end
			-- if player == nil, then next try: player received multiple loot
			if (playerName == nil) then
				playerName = UnitName("player");
				itemLink, itemCount = deformat(chatmsg, LOOT_ITEM_SELF_MULTIPLE);
			end
			-- if itemLink == nil, then last try: player received single loot
			if (itemLink == nil) then
				itemCount = 1;
				itemLink = deformat(chatmsg, LOOT_ITEM_SELF);
			end
			-- if itemLink == nil, then there was neither a LOOT_ITEM, nor a LOOT_ITEM_SELF message
			if (itemLink == nil) then
				-- GDKPd_Debug("No valid loot event received.");
				return;
			end
			-- if code reaches this point, we should have a valid looter and a valid itemLink
			-- SF: hack to assign to disenchanted playerName = "disenchanted";
			GDKPd_Debug("Item looted - Looter is "..playerName.." and loot is "..itemLink);
			--cache the item
			local itemName, _, itemId, itemString, itemRarity, itemColor, itemLevel, _, itemType, itemSubType, _, _, _, _, itemClassID, itemSubClassID = GDKPd:GetDetailedItemInformation(itemLink);
			--if itemRarity is green (2) or better add
			--if 1 < itemRarity then 
			GDKPd_Debug("itemlink: "..itemLink.. "playerName: " ..playerName.. " itemRarity: " ..itemRarity.. " GDKPd.opt.minQualityTracking: " ..GDKPd.opt.minQualityTracking)
			if GDKPd.opt.minQualityTracking <= itemRarity then 
				self:AddItemToPot(itemLink, 0, playerName)
			else
				GDKPd_Debug("Item Rarity is too low to track")
			end
		end
	end
	-- release table back into the pool of usable tables
	arg:Release()
end)

function GDKPd:GetDetailedItemInformation(itemIdentifier)
	local MRT_ItemColors = {
		[1] = "ff9d9d9d",  -- poor
		[2] = "ffffffff",  -- common
		[3] = "ff1eff00",  -- uncommon
		[4] = "ff0070dd",  -- rare
		[5] = "ffa335ee",  -- epic
		[6] = "ffff8000",  -- legendary
		[7] = "ffe6cc80",  -- artifact / heirloom
		[8] = "ffe6cc80",
	}
	
	GDKPd_Debug("GetDetailedItemInformation: itemIdentifier: " ..itemIdentifier)
    local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice, itemClassID, itemSubClassID = GetItemInfo(itemIdentifier);
    if (not itemLink) then return nil; end
    local _, itemString, _ = deformat(itemLink, "|c%s|H%s|h%s|h|r");
    local itemId, _ = deformat(itemString, "item:%d:%s");
    local itemColor = MRT_ItemColors[itemRarity + 1];
    return itemName, itemLink, itemId, itemString, itemRarity, itemColor, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice, itemClassID, itemSubClassID;
end

GDKPd:RegisterEvent("ADDON_LOADED")
GDKPd:RegisterEvent("CHAT_MSG_RAID")
GDKPd:RegisterEvent("CHAT_MSG_RAID_LEADER")
GDKPd:RegisterEvent("CHAT_MSG_RAID_WARNING")
GDKPd:RegisterEvent("LOOT_OPENED")
GDKPd:RegisterEvent("LOOT_CLOSED")
GDKPd:RegisterEvent("GROUP_ROSTER_UPDATE")
GDKPd:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
GDKPd:RegisterEvent("UNIT_NAME_UPDATE")
GDKPd:RegisterEvent("CHAT_MSG_ADDON")
GDKPd:RegisterEvent("TRADE_MONEY_CHANGED")
GDKPd:RegisterEvent("UI_INFO_MESSAGE")
GDKPd:RegisterEvent("TRADE_CLOSED")
GDKPd:RegisterEvent("TRADE_SHOW")
GDKPd:RegisterEvent("TRADE_ACCEPT_UPDATE")
GDKPd:RegisterEvent("PLAYER_TRADE_MONEY")
GDKPd:RegisterEvent("PLAYER_REGEN_ENABLED")
GDKPd:RegisterEvent("PLAYER_REGEN_DISABLED")
GDKPd:RegisterEvent("MAIL_INBOX_UPDATE")
GDKPd:RegisterEvent("MAIL_CLOSED")
--Loot events
GDKPd:RegisterEvent("CHAT_MSG_LOOT")

--chat filters
local function filterChat_CHAT_MSG_RAID(chatframe,event,msg)
	--auctionAnnounce newBid bidFinished
	if GDKPd.opt.hideChatMessages.auctionAnnounce and msg:match("Bidding starts on (|c........|Hitem:.+|r).")  then
		return true
	end
	if GDKPd.opt.hideChatMessages.newBid and msg:match("New highest bidder(.*): (%S+) %((%d+) gold%)") then
		return true
	end
	if GDKPd.opt.hideChatMessages.bidFinished and msg:match("Auction finished") then
		return true
	end
	if GDKPd.opt.hideChatMessages.secondsRemaining and msg:match("[Caution] (%d+) seconds remaining(.*)!") then
		return true
	end
	if GDKPd.opt.hideChatMessages.bidChats and (((msg:match("%d+") and (not msg:match("seconds remaining"))) and (GDKPd.InProgressBidFrame or GDKPd.curAuction.item)) or (msg:match("(|c........|Hitem:.+|r)%s*(%d+)") and (GDKPd:FetchFrameFromLink(msg:match("(|c........|Hitem:.+|r)")) or GDKPd.curAuctions[msg:match("(|c........|Hitem:.+|r)")]))) then
		return true
	end
	if GDKPd.opt.hideChatMessages.potValues and msg:match("Current pot: (%d+) gold") then
		return true
	end
	if GDKPd.opt.hideChatMessages.auctionCancel and msg:match("Auction cancelled") then
		return true
	end
	return false
end
--register chat filters
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID",filterChat_CHAT_MSG_RAID)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_WARNING",filterChat_CHAT_MSG_RAID)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER",filterChat_CHAT_MSG_RAID)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM",function(chatframe,event,msg)
	if msg:find(L["Your version of GDKPd is slightly outdated compared to the raid leader's. Full compability should be possible, however, you might want to take some time and update GDKPd."]:gsub("%[","%%["):gsub("%]","%%]")) then
		return true
	end
	if msg:find(L["Your version of GDKPd is outdated and no longer compatible with the raid leader's in one or more functionalities. In order to ensure smooth performance, please update GDKPd."]:gsub("%[","%%["):gsub("%]","%%]")) then
		return true
	end
	if msg:find(L["This raid uses GDKPd to faciliate its GDKP bidding process. While you can bid on items without having GDKPd installed, installing it provides you with a GUI bidding panel, auto bidding functions, auction timers, chat filtering and more!"]:gsub("%[","%%["):gsub("%]","%%]")) then
		return true
	end
end)
--chat filters done
--filter raid warning frame
do
	-- GLOBALS: RaidNotice_AddMessage
	local oldmessage = RaidNotice_AddMessage
	function RaidNotice_AddMessage(frame,text,...)
		if GDKPd.opt.hideChatMessages.auctionAnnounceRW and text:match("Bidding starts on (|c........|Hitem:.+|r).") then
			return
		end
		if GDKPd.opt.hideChatMessages.auctionCancelRW and text:match("Auction cancelled") then
			return
		end
		if GDKPd.opt.hideChatMessages.newBid and text:match("New highest bidder(.*): (%S+) %((%d+) gold%)") then
			return
		end
		oldmessage(frame,text,...)
	end
end
--end raid warning frame filter
--register addon msg prefixes
C_ChatInfo.RegisterAddonMessagePrefix("GDKPD START")
C_ChatInfo.RegisterAddonMessagePrefix("GDKPD VREQ")
C_ChatInfo.RegisterAddonMessagePrefix("GDKPD VDATA")
C_ChatInfo.RegisterAddonMessagePrefix("GDKPD MANADJ")
--prefixes done


------------------
--Pot Log Table --
------------------
function GDKPd:PotLogTableUpdate()
	local PotLogTableData = {};
	-- insert reverse order
	local intCount = 0
	for i, v in ipairs(GDKPd_PotData["history"]) do
		--MRT_GUI_RaidLogTableData[i] = {i, date("%m/%d %H:%M", v["StartTime"]), v["RaidZone"], v["RaidSize"]};
		local realdate = GDKPd:stringtodate(v["date"])
		intCount = intCount + 1
		PotLogTableData[intCount] = {i, date("%m/%d %H:%M", realdate), v["note"]};
	end
	intCount = intCount + 1
	PotLogTableData[intCount] = {9999, date("%m/%d %H:%M", time()), "Active Pot"};
	table.sort(PotLogTableData, function(a, b) return (a[1] > b[1]); end);
	status.PotLogTable:SetData(PotLogTableData, true);
end 

function GDKPd:stringtodate(timeString)
	local monthShortTable={Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}
	-- timeString = 'Sun Jan  7 09:42:54 2018'
	-- This has no definition of time zone, Let's assume that it is in UTC.
	-- Note that the os.time() function requires a table that is all numbers, so we
	-- need to use the monthShortTable table defined in Initialize() to turn the
	-- "Jan" into 1.
	local formatPattern = '^%a+%s+(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)%s+(%d+)$'
	local monthText, day, hour, min, sec, year = timeString:match(formatPattern)
	local month=monthShortTable[monthText]
	
	local timeStamp = time({month=month, day=day, year=year, hour=hour, min=min, sec=sec, isdst=false})
	
	--formatedString = date('%A, %B %d, %Y at %I:%M:%S %p', timeStamp)
	-- Just for cosmetics, strip off any leading zeros on the day, and on the hour.
	-- Regrettably, Lua's os.date() doesn't  support Rainmeter's "#" character to suppress leading zeros.
	--formatedString = formatedString:gsub(' 0',' ')
	
	--return formatedString..'\nUnix timestamp is '..timeStamp
	return timeStamp
end


---------------------
-- UPDATE THE DISPLAYED GOLD --
---------------------
function status:Update()
	local potAmount;
	local lastDist;
	if GDKPd:IsActivePotSelected() then
		GDKPd_Debug("Active pot selected")

		potAmount = (GDKPd_PotData.potAmount or 0)
		lastDist = (GDKPd_PotData.prevDist or 0)
	else
		GDKPd_Debug("Non-active pot selected")
		potAmount = 55
		lastDist = 44
	end
	if lastDist > 0 then
		status.potText:SetText(L["Pot size: %d|cffffd100g|r"]:format(potAmount))
		status.potDistributeText:SetText(L[" |cffaa0000(Distribute: %dg)|r"]:format(potAmount-lastDist))
	else
		status.potText:SetText(L["Pot size: %d|cffffd100g|r"]:format(potAmount))
		status.potDistributeText:SetText("")

	end
end

---------------------
-- POT CHANGED --
---------------------
function GDKPd:PotChanged()
	GDKPd:BossLootTableUpdate();
    status:Update();

end

---------------------
-- IsActivePotSelected--
---------------------
function GDKPd:IsActivePotSelected()

	potnum = status.PotLogTable:GetSelection()
	local potID = status.PotLogTable:GetCell(potnum, 1);

	if potID == 9999 then 
		return true
	else
		return false
	end

end

---------------------
-- Boss Loot Table --
---------------------
function GDKPd:BossLootTableUpdate(skipsort, filter)
    GDKPd_Debug("BossLootTableUpdate Fired!")
    local BossLootTableData = {};
    local potnum = status.PotLogTable:GetSelection()
	local potID
	local curPot
    local indexofsub1;
    local indexofsub2;
	
	if not (potnum) then 
		status.PotLogTable:SetSelection(1);
		potnum = status.PotLogTable:GetSelection()
	end 
	GDKPd_Debug("BosslootTableUpdate: potnum: " ..potnum)
	potID = status.PotLogTable:GetCell(potnum, 1);
	if potID == 9999 then 
		curPot = GDKPd_PotData.curPotHistory
	elseif #GDKPd_PotData["history"] == 0 then 
		--no history
		GDKPd_Debug("BossLootTableData: no history")
		return
	else
		GDKPd_Debug("BossLootTableUpdate: potID: " ..potID)
		curPot = GDKPd_PotData["history"][potID]["items"]
	end 

	local index = 1;
	local checkFilter
	local hasFilter = filter
        --checkFilter = MRT_GUIFrame_BossLoot_Filter:GetText();
        --GDKPd_Debug("BossLootTableUpdate: checkFilter: " ..checkFilter);
	if checkFilter == "" or checkFilter == nil then 
		hasFilter = false
	else 
		hasFilter = true
	end
    local classColor = "ff9d9d9d"     
	if #curPot > 0 then 
		for i, v in ipairs(curPot) do
			--BossLootTableData[index] = {i, v["ItemId"], "|c"..v["itemColor"]..v["itemName"].."|r", v["Looter"], v["DKPValue"], v["ItemLink"], v["Note"]};
			-- SF: if unassigned, make it red.
			
			--Set Class Color
			GDKPd_Debug("BossLootTableUpdate: v['name']: "..v["name"])
			local playerClass, classFilename, classId = UnitClass(v["name"])
			if (playerClass) then 
				GDKPd_Debug("BossLootTableUpdate: playerClass: "..playerClass)
			else
				GDKPd_Debug("BossLootTableUpdate: playerClass: isNull")
			end
			classColor = GDKPd:getClassColor(playerClass);  
			GDKPd_Debug("BossLootTableUpdate: classColor: "..classColor)
			--GDKPd_Debug("Row: "..v["itemName"])
			--GDKPd_Debug("BossLootTableUpdate: elseif raidnum condition: looter: " ..v["Looter"] .."playerClass: "..playerClass..", classColor: " ..classColor);
			
			--GetDate 
			local lootTime = GDKPd:calculateLootTimeLeft(v["ltime"])

			--SetDoneState
			--local doneState = SetDoneState(v["Looter"], v["Traded"], v["itemName"])

			if not hasFilter then
				--GDKPd_Debug("BossLootTableUpdate: hasFilter: " ..tostring(hasFilter) .." false, so do regular stuff");
				if v["Looter"] == "unassigned" then
					BossLootTableData[index] = {i, v["itemId"], "|c"..v["itemColor"]..v["itemName"].."|r", "|cffff0000"..v["name"], v["bid"], v["item"], lootTime, doneState};
				else 
					BossLootTableData[index] = {i, v["itemId"], "|c"..v["itemColor"]..v["itemName"].."|r", "|c"..classColor..v["name"], v["bid"], v["item"], lootTime, doneState};
				end 
				index = index + 1;
			else
				--GDKPd_Debug("BossLootTableUpdate: hasFilter: " ..tostring(hasFilter) .." true, so filter list");
				--[[ local checkFilter = filter;
				if not checkFilter then
					checkFilter = MRT_GUIFrame_BossLoot_Filter:GetText();
				end  ]]
				-- need function here to return true if there are classes to filter
				--local strFilter, isSpecialFilter = parseFilter4Special(checkFilter); 
				local strFilter, isSpecialFilter = GDKPd:parseFilter4Classes(checkFilter);
				if isSpecialFilter then
					-- if there are classes or special to filter check for which classes
					-- checking if class is in the classfilter list
					-- new function to return true if class is in classfilter table.
					-- old code: indexofsub = substr(v["Class"], strFilter);
					-- old code: if not indexofsub then
					local tblSpecialFilter = GDKPd:check4GroupFilters(strFilter);
					--tblSpecialFilter = filter out list.

					if not (GDKPd:isLooterInSpecialFilter(v["Looter"], tblSpecialFilter)) then
						--skip no special matches so don't do anything.
					else 
						--special match found so include in table
						if v["Looter"] == "unassigned" then
							BossLootTableData[index] = {i, v["itemId"], "|c"..v["itemColor"]..v["itemName"].."|r", "|cffff0000"..v["name"], v["bid"], v["item"], lootTime, doneState};
						else 
							BossLootTableData[index] = {i, v["itemId"], "|c"..v["itemColor"]..v["itemName"].."|r", "|c"..classColor..v["name"], v["bid"], v["item"], lootTime, doneState};
						end 
						index = index + 1;
					end
				else -- if not special filter, do the normal thing 
					indexofsub1 = substr(v["itemName"], checkFilter);
					indexofsub2 = substr(v["Looter"], checkFilter);
					if not indexofsub1 and not indexofsub2 then
						--skip
					else
						---
						if v["name"] == "unassigned" then
							BossLootTableData[index] = {i, v["itemId"], "|c"..v["itemColor"]..v["itemName"].."|r", "|cffff0000"..v["name"], v["bid"], v["item"], lootTime, doneState};
						else 
							BossLootTableData[index] = {i, v["itemId"], "|c"..v["itemColor"]..v["itemName"].."|r", "|c"..classColor..v["name"], v["bid"], v["item"], lootTime, doneState};
						end 
						index = index + 1;
					end
				end
			end
		end
	end
    
    table.sort(BossLootTableData, function(a, b) return (a[3] < b[3]); end);
    --BossLootTable:ClearSelection();
    --[[ if skipsort then 
        GDKPd_Debug("BossLootTableUpdate: skipsort==True about to call SetData");
    else
        GDKPd_Debug("BossLootTableUpdate: skipsort:Nil about to call SetData");
    end ]]
    status.BossLootTable:SetData(BossLootTableData, true, skipsort);
	return BossLootTableData
end

function GDKPd:isLooterInSpecialFilter(looter, specialFilter)
    --return if looter is not in special filter
    --GDKPd_Debug("isLooterInSpecialFilter:Called!");
    GDKPd_Debug("isLooterInSpecialFilter: # of items: "..table.maxn(specialFilter));
    for i, v in pairs(specialFilter) do
        --GDKPd_Debug("isLooterInSpecialFilter:looter == " ..looter);
        --GDKPd_Debug("isLooterInSpecialFilter:i == " ..i.." :v == " ..v);
        if string.lower(v) == string.lower(looter) then
            return false;
        else 
            --GDKPd_Debug("isLooterInSpecialFilter: looter not in table");
        end
    end
    return true;
end

function GDKPd:getClassColor(class)
    local classColor = "ff9d9d9d";
    if class == "Hunter"
    then classColor = "ffA9D271";
    elseif class == "Druid"
    then classColor = "ffFF7D0A";   
    elseif class == "Mage"
    then classColor = "ff40C7EB";   
    elseif class == "Paladin"
    then classColor = "ffF58CBA";   
    elseif class == "Rogue"
    then classColor = "ffFFF569";   
    elseif class == "Warlock"
    then classColor = "ff8787ED";   
    elseif class == "Warrior"
    then classColor = "ffC79C6E";   
    elseif class == "Shaman"
    then classColor = "ff0070DE";   
    elseif class == "Priest"
    then classColor = "ffffffff";
    elseif class == "bank"
    then classColor = "ff9d8e8d";
    elseif class == "disenchanted"
    then classColor = "ff9d8e8d";
    end 
    return classColor;
end
function GDKPd:parseFilter4Classes(strText)
    --GDKPd_Debug("parseFilter4Classes called!");
    classFilters = {}
    local retVal = string.gsub(strText, " ", "")
    --GDKPd_Debug("parseFilter4Classes retVal == "..retVal);
    if string.len(retVal) > 3 and substr(strText,":") then
        for i in string.gmatch(retVal, "%a+") do
            --GDKPd_Debug("parseFilter4Classes i == "..i);
            table.insert(classFilters, i);
        end
        if table.maxn(classFilters) > 0 then
            --GDKPd_Debug("parseFilter4Classes:classFilters true");
            return classFilters, true;
        else
            --GDKPd_Debug("parseFilter4Classes:classFilters false");
            return strText, false;
        end 
    else
        return strText;
    end
end

function GDKPd:check4GroupFilters(classFilter)
    GDKPd_Debug("check4GroupFilters: called!");

    local sgroupFilters = {
        ["healer"] = {"druid", "paladin", "priest"},
        ["healers"] = {"druid", "paladin", "priest"},
        ["caster"] = {"mage", "warlock"},
        ["casters"] = {"mage", "warlock"},
        ["ranged"] = {"mage", "warlock", "hunter"},
        ["melee"] = {"warrior", "rogue"},
        ["players"] = {"bank", "disenchanted"},
        ["player"] = {"bank", "disenchanted"},
        ["command"] = {"warrior", "hunter", "rogue", "priest"},
        ["dominance"] = {"druid", "mage", "paladin", "warlock", "shaman"},
        ["diadem"] = {"druid", "hunter", "paladin", "rogue", "shaman"},
        ["circlet"] = {"mage", "priest", "warlock", "warrior"},
    }
    local oclassFilter = classFilter;
    
    for i, v in pairs(oclassFilter) do
        --look for special filter
        local tblGroupFilter = sgroupFilters[string.lower(v)];

        if (tblGroupFilter) then
            --add the list into the classFilter
            for i1, v1 in pairs(tblGroupFilter) do
                GDKPd_Debug("check4GroupFilters: i1: " ..i1.. " v1: " ..v1);
                table.insert(oclassFilter,v1)
            end
        end
    end
    return oclassFilter
end
function GDKPd:calculateLootTimeLeft (timeLooted)
	local lootTime
    local lootTimeStamp = timeLooted;
    local nowTimeStamp = time();
    -- GDKPd_Debug(date("%m/%d/%y %H:%M:%S", nowTimeStamp));
    -- GDKPd_Debug(date("%m/%d/%y %H:%M:%S", lootTimeStamp));
    local deltaTime = 7200 - difftime(nowTimeStamp, lootTimeStamp);
    --GDKPd_Debug(deltaTime)

    if deltaTime > 0 then
        local hours = math.floor(deltaTime /3600);
        local minutes = math.floor( (deltaTime - (hours*3600) )/60);
        local strM --string for minutes to get 01 instead of 1
        if minutes < 10 then
            strM = "0"..minutes
        else
            strM = minutes
        end
        -- GDKPd_Debug(hours);
        -- GDKPd_Debug(minutes);
        if hours > 0 then
            lootTime = hours ..":" ..strM;
        else
            lootTime = ":" ..strM;
        end
    else
        lootTime = date("%I:%M", timeLooted); --default to time stamp if the loot has expired
    end
	return lootTime
end
------------------------
--  helper functions  --
------------------------
function GDKPd_Debug(text)

	if GDKPd.opt.debugLog then
	    DEFAULT_CHAT_FRAME:AddMessage("GDKPd: Debug: "..text, 1, 0.5, 0);
    end
end