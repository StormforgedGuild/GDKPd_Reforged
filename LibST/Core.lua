local MAJOR, MINOR = "ScrollingTable2", tonumber("bed1ec579596101579452182d240b1ca3267c599") or 40000;

if MINOR < 40000 then
	MINOR = MINOR + 10000;
end
local ScrollingTable, oldminor = LibStub:NewLibrary(MAJOR, MINOR);
if not ScrollingTable then
	return; -- No Upgrade needed.
end

do
	local defaultcolor = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 };
	local defaulthighlight = { ["r"] = 1.0, ["g"] = 0.9, ["b"] = 0.0, ["a"] = 0.5 };
	local defaulthighlightblank = { ["r"] = 0.0, ["g"] = 0.0, ["b"] = 0.0, ["a"] = 0.0 };
	local lrpadding = 2.5;

	local ScrollPaneBackdrop  = {
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 3, right = 3, top = 5, bottom = 3 }
	};

	local SetHeight = function(self)
		self.frame:SetHeight( (self.displayRows * self.rowHeight) + 10);
		self:Refresh();
	end

	local SetWidth = function(self)
		local width = 13;
		for num, col in pairs(self.cols) do
			width = width + col.width;
		end
		self.frame:SetWidth(width+20);
		self:Refresh();
	end

	--- API for a ScrollingTable table
	-- @name SetHighLightColor
	-- @description Set the row highlight color of a frame ( cell or row )
	-- @usage st:SetHighLightColor(rowFrame, color)
	-- @see http://www.wowace.com/addons/lib-st/pages/colors/
	local function SetHighLightColor (self, frame, color)
		if not frame.highlight then
			--old code: frame.highlight = frame:CreateTexture(nil, "OVERLAY");
			frame.highlight = frame:CreateTexture(nil, "BORDER");
			frame.highlight:SetAllPoints(frame);
		end
		frame.highlight:SetColorTexture(color.r, color.g, color.b, color.a);
	end

	local FireUserEvent = function (self, frame, event, handler, ...)
		if not handler( ...) then
			if self.DefaultEvents[event] then
				self.DefaultEvents[event]( ...);
			end
		end
	end

	--- API for a ScrollingTable table
	-- @name RegisterEvents
	-- @description Set the event handlers for various ui events for each cell.
	-- @usage st:RegisterEvents(events, true)
	-- @see http://www.wowace.com/addons/lib-st/pages/ui-events/
	local function RegisterEvents (self, events, fRemoveOldEvents)
		local table = self; -- save for closure later

		for i, row in ipairs(self.rows) do
			for j, col in ipairs(row.cols) do
				-- unregister old events.
				if fRemoveOldEvents and self.events then
					for event, handler in pairs(self.events) do
						col:SetScript(event, nil);
					end
				end

				-- register new ones.
				for event, handler in pairs(events) do
					col:SetScript(event, function(cellFrame, ...)
						local realindex = table.filtered[i+table.offset];
						table:FireUserEvent(col, event, handler, row, cellFrame, table.data, table.cols, i, realindex, j, table, ... );
					end);
				end
			end
		end

		for j, col in ipairs(self.head.cols) do
			-- unregister old events.
			if fRemoveOldEvents and self.events then
				for event, handler in pairs(self.events) do
					col:SetScript(event, nil);
				end
			end

			-- register new ones.
			for event, handler in pairs(events) do
				col:SetScript(event, function(cellFrame, ...)
					table:FireUserEvent(col, event, handler, self.head, cellFrame, table.data, table.cols, nil, nil, j, table, ...);
				end);
			end
		end
		self.events = events;
	end

	--- API for a ScrollingTable table
	-- @name SetDisplayRows
	-- @description Set the number and height of displayed rows
	-- @usage st:SetDisplayRows(10, 15)
	local function SetDisplayRows (self, num, rowHeight)
		local table = self; -- reference saved for closure
		-- should always set columns first
		self.displayRows = num;
		self.rowHeight = rowHeight;
		if not self.rows then
			self.rows = {};
		end
		for i = 1, num do
			local row = self.rows[i];
			if not row then
				row = CreateFrame("Button", self.frame:GetName().."Row"..i, self.frame);
				row:SetFrameStrata("MEDIUM");
				row:SetFrameLevel(2);
				self.rows[i] = row;
				if i > 1 then
					row:SetPoint("TOPLEFT", self.rows[i-1], "BOTTOMLEFT", 0, 0);
					row:SetPoint("TOPRIGHT", self.rows[i-1], "BOTTOMRIGHT", 0, 0);
				else
					row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -5);
					row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -4, -5);
				end
				row:SetHeight(rowHeight);
			end

			if not row.cols then
				row.cols = {};
			end
			for j = 1, #self.cols do
				local col = row.cols[j];
				if not col then
					col = CreateFrame("Button", row:GetName().."col"..j, row);
					-- old code col.text = row:CreateFontString(col:GetName().."text", "OVERLAY", "GameFontHighlightSmall");
					col.text = row:CreateFontString(col:GetName().."text", "BORDER", "GameFontHighlightSmall");
					--col:SetFrameStrata("MEDIUM");
					row.cols[j] = col;
					local align = self.cols[j].align or "LEFT";
					col.text:SetJustifyH(align);
					col:EnableMouse(true);
					col:RegisterForClicks("AnyUp");

					if self.events then
						for event, handler in pairs(self.events) do
							col:SetScript(event, function(cellFrame, ...)
								if table.offset then
									local realindex = table.filtered[i+table.offset];
									table:FireUserEvent(col, event, handler, row, cellFrame, table.data, table.cols, i, realindex, j, table, ... );
								end
							end);
						end
					end
				end

				if j > 1 then
					col:SetPoint("LEFT", row.cols[j-1], "RIGHT", 0, 0);
				else
					col:SetPoint("LEFT", row, "LEFT", 2, 0);
				end
				col:SetHeight(rowHeight);
				col:SetWidth(self.cols[j].width);
				col.text:SetPoint("TOP", col, "TOP", 0, 0);
				col.text:SetPoint("BOTTOM", col, "BOTTOM", 0, 0);
				col.text:SetWidth(self.cols[j].width - 2*lrpadding);
			end
			j = #self.cols + 1;
			col = row.cols[j];
			while col do
				col:Hide();
				j = j + 1;
				col = row.cols[j];
			end
		end

		for i = num + 1, #self.rows do
			self.rows[i]:Hide();
		end

		self:SetHeight();
	end

	--- API for a ScrollingTable table
	-- @name SetDisplayCols
	-- @description Set the column info for the scrolling table
	-- @usage st:SetDisplayCols(cols)
	-- @see http://www.wowace.com/addons/lib-st/pages/create-st/#w-cols
	local function SetDisplayCols (self, cols)
		local table = self; -- reference saved for closure
		self.cols = cols;

		local row = self.head
		if not row then
			row = CreateFrame("Frame", self.frame:GetName().."Head", self.frame);
			row:SetFrameStrata("MEDIUM");
			row:SetFrameLevel(1);
			row:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 4, 0);
			row:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", -4, 0);
			row:SetHeight(self.rowHeight);
			row.cols = {};
			self.head = row;
		end
		for i = 1, #cols do
			local colFrameName =  row:GetName().."Col"..i;
			local col = getglobal(colFrameName);
			if not col then
				col = CreateFrame("Button", colFrameName, row);
				--col:SetFrameStrata("MEDIUM");
				col:RegisterForClicks("AnyUp");	 -- LS: right clicking on header

				if self.events then
					for event, handler in pairs(self.events) do
						col:SetScript(event, function(cellFrame, ...)
							table:FireUserEvent(col, event, handler, row, cellFrame, table.data, table.cols, nil, nil, i, table, ...);
						end);
					end
				end
			end
			--col:SetFrameStrata("MEDIUM");
			row.cols[i] = col;

			--old code local fs = col:GetFontString() or col:CreateFontString(col:GetName().."fs", "OVERLAY", "GameFontHighlightSmall");
			local fs = col:GetFontString() or col:CreateFontString(col:GetName().."fs", "BORDER", "GameFontHighlightSmall");
			fs:SetAllPoints(col);
			fs:SetPoint("LEFT", col, "LEFT", lrpadding, 0);
			fs:SetPoint("RIGHT", col, "RIGHT", -lrpadding, 0);
			local align = cols[i].align or "LEFT";
			fs:SetJustifyH(align);

			col:SetFontString(fs);
			fs:SetText(cols[i].name);
			fs:SetTextColor(1.0, 1.0, 1.0, 1.0);
			col:SetPushedTextOffset(0,0);

			if i > 1 then
				col:SetPoint("LEFT", row.cols[i-1], "RIGHT", 0, 0);
			else
				col:SetPoint("LEFT", row, "LEFT", 2, 0);
			end
			col:SetHeight(self.rowHeight);
			col:SetWidth(cols[i].width);

			local color = cols[i].bgcolor;
			if (color) then
				local colibg = "col"..i.."bg";
				local bg = self.frame[colibg];
				if not bg then
					--old code: bg = self.frame:CreateTexture(nil, "OVERLAY");
					bg = self.frame:CreateTexture(nil, "BORDER");
					self.frame[colibg] = bg;
				end
				bg:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 4);
				bg:SetPoint("TOPLEFT", col, "BOTTOMLEFT", 0, -4);
				bg:SetPoint("TOPRIGHT", col, "BOTTOMRIGHT", 0, -4);
				bg:SetColorTexture(color.r, color.g, color.b, color.a);
			end
		end

		self:SetDisplayRows(self.displayRows, self.rowHeight);
		self:SetWidth();
	end

	--- API for a ScrollingTable table
	-- @name Show
	-- @description Used to show the scrolling table when hidden.
	-- @usage st:Show()
	local function Show (self)
		self.frame:Show();
		self.scrollframe:Show();
		self.showing = true;
	end

	--- API for a ScrollingTable table
	-- @name Hide
	-- @description Used to hide the scrolling table when shown.
	-- @usage st:Hide()
	local function Hide (self)
		self.frame:Hide();
		self.showing = false;
	end

	--- API for a ScrollingTable table
	-- @name SortData
	-- @description Resorts the table using the rules specified in the table column info.
	-- @usage st:SortData()
	-- @see http://www.wowace.com/addons/lib-st/pages/create-st/#w-defaultsort
	local function SortData (self, groupby)
		-- sanity check
		if not(self.sorttable) or (#self.sorttable ~= #self.data)then
			self.sorttable = {};
		end
		if #self.sorttable ~= #self.data then
			for i = 1, #self.data do
				self.sorttable[i] = i;
			end
		end
		
		-- go on sorting
		local i, sortby = 1, nil;
		while i <= #self.cols and not sortby do
			if self.cols[i].sort then
				sortby = i;
			end
			i = i + 1;
		end
		if sortby then
			--GDKPd_Debug("ST:SortData: sortby true");
			--GDKPd_Debug("ST:SortData:sortby = " ..sortby);
			table.sort(self.sorttable, function(rowa, rowb)
				local column = self.cols[sortby];
				if column.CompareSort then
					--GDKPd_Debug("ST:SortData:sortby:CompareSort = true");
					return column.CompareSort(self, rowa, rowb, sortby);
				else
					--GDKPd_Debug("ST:SortData:sortby:CompareSort = false");
					if (groupby == nil) or not groupby then
						return self:CompareSort(rowa, rowb, sortby);
					else
						--GDKPd_Debug("ST:SortData:groupby");
						return self:CompareSort(rowa, rowb, sortby, groupby);
					end
				end
			end);
		end
		self.filtered = self:DoFilter();
		self:Refresh();
	end
	
	local StringToNumber = function(str)
		if str == "" then
			return 0;
		else
			return tonumber(str)
		end
	end

	--- API for a ScrollingTable table
	-- @name CompareSort
	-- @description CompareSort function used to determine how to sort column values.  Can be overridden in column data or table data.
	-- @usage used internally.
	-- @see Core.lua
	local function CompareSort (self, rowa, rowb, sortbycol, groupby)
		GDKPd_Debug("ST:CompareSort Called!");
		local cella, cellb = self:GetCell(rowa, sortbycol), self:GetCell(rowb, sortbycol);
		local a1, b1 = cella, cellb;
		local a2, b2
		if groupby == nil or not groupby then
			--do nothing
		else
			--GDKPd_Debug("ST:CompareSort: groupby is true");
			local cella2, cellb2 = self:GetCell(rowa, 5), self:GetCell(rowb, 5);
			if not cella2 then cella2="Unknown" end;
			if not cellb2 then callb2="Unknown" end;
			a2, b2 = cella2, cellb2
			--GDKPd_Debug("ST:CompareSort: groupby a2 == " ..a2);
			--GDKPd_Debug("ST:CompareSort: groupby b2 == " ..b2);
		end
		if type(a1) == 'table' then
			a1 = a1.value;
		end
		if type(b1) == 'table' then
			b1 = b1.value;
		end
		--GDKPd_Debug("ST:CompareSort: type of a1 is " ..type(a1));
		--GDKPd_Debug("ST:CompareSort: type of b2 is " ..type(b1));
		local column = self.cols[sortbycol];

		if type(a1) == "function" then
			if (cella.args) then
				a1 = a1(unpack(cella.args))
			else
				a1 = a1(self.data, self.cols, rowa, sortbycol, self);
			end
		end
		if type(b1) == "function" then
			if (cellb.args) then
				b1 = b1(unpack(cellb.args))
			else
				b1 = b1(self.data, self.cols, rowb, sortbycol, self);
			end
		end
		if type(a1) ~= type(b1) then
			local typea, typeb = type(a1), type(b1);
			if typea == "number" and typeb == "string" then
				if tonumber(b1) then -- is it a number in a string?
					b1 = StringToNumber(b1); -- "" = 0
				else
					a1 = tostring(a1);
				end
			elseif typea == "string" and typeb == "number" then
				if tonumber(a1) then -- is it a number in a string?
					a1 = StringToNumber(a1); -- "" = 0
				else
					b1 = tostring(b1);
				end
			end
		end
		if (type(a1) == "boolean") or (not a1) then
			if a1 then
				a1 = 1;
			else 
				a1 = 0
			end
			if b1 then
				b1 = 1;
			else 
				b1 = 0;
			end
		end
		--if there is format in the string, clean it for sort.
		if type(a1) == "string" and type(b1) == "string" then
			--clean name
			a1, b1 = cleanString(a1), cleanString(b1);
			--check for time sort
			--call it some function
			GDKPd_Debug("ST:CompareSort: a1: " ..a1.." b1: " ..b1);
			a1, b1 = ST2_stringTimetonumberTime(a1), ST2_stringTimetonumberTime(b1);
			GDKPd_Debug("ST:CompareSort: after stringTime: a1: " ..a1.." b1: " ..b1);
		end
		if (groupby == nil) or not groupby then
			if a1 == b1 then
				if column.sortnext then
					local nextcol = self.cols[column.sortnext];
					if not(nextcol.sort) then
						if nextcol.CompareSort then
							return nextcol.CompareSort(self, rowa, rowb, column.sortnext);
						else
							return self:CompareSort(rowa, rowb, column.sortnext);
						end
					else
						return false;
					end
				else
					return false;
				end
			else

				local direction = column.sort or column.defaultsort or "asc";
				if direction:lower() == "asc" then
					return a1 > b1;
				else
					return a1 < b1;
				end
			end
		else
			--do group by
			--GDKPd_Debug("ST:CompareSort: calling ststorbyclass");
			local direction = column.sort or column.defaultsort or "asc";
			return stsortbyclass(a1, b1, a2, b2, direction)
		end
	end
	function ST2_stringTimetonumberTime(sText1)
		local retVal1
		local cIndex = strfind(sText1, ":")
		GDKPd_Debug("ST:ST2_stringTimetonumberTime: Called!");
		GDKPd_Debug("ST:ST2_stringTimetonumberTime: sText: " ..sText1);
		if strlen(sText1) > 7 then cIndex = nil end
		if (cIndex) then GDKPd_Debug("ST:ST2_stringTimetonumberTime: cIndex: " ..cIndex);end
		if not cIndex then
			--[[ local isNum = string.find(sText1, "%d")
			if not isNum then 
				GDKPd_Debug("ST:ST2_stringTimetonumberTime: sText1: " ..sText1);
				return sText1;
			else
				local subText = string.sub(sText1,1,isNum-1)
				GDKPd_Debug("ST:ST2_stringTimetonumberTime: subText: " ..subText)
				retVal1 = tonumber(subText)-- + tonumber(string.sub(sText1,isNum))
				GDKPd_Debug("ST:ST2_stringTimetonumberTime: retVal1: " ..tostring(retVal1));
				return retVal1
			end ]]
			return sText1
		end
		retVal1 = ST2_cStrTimetoInt(sText1,cIndex)
		GDKPd_Debug("ST:ST2_stringTimetonumberTime: retVal1: " ..retVal1);
		return retVal1;
	end
	function ST2_cStrTimetoInt(sText, cIndex)
		GDKPd_Debug("ST2_cStrTimetoInt: called! ");
		local sH, sM;
		sH = string.sub(sText,1,cIndex-1)
		if not sH or sH == "" then
			sH = 0;
		end
		GDKPd_Debug("ST:ST2_stringTimetonumberTime: sH: " ..sH);
		sM = string.sub(sText,cIndex+1)
		if not sM or sM == "" then
			sM = 0
		end
		--GDKPd_Debug("ST:ST2_stringTimetonumberTime: sM: " ..sM);
		return (tonumber(sH)*60) + tonumber(sM);
	end

	function cleanString(strText, keepCase)
		--|cff9d9d9d
		local sText;
		if not keepCase then 
			sText = string.lower(strText);
		else
			--GDKPd_Debug("ST:CleanString keepCase");
			sText = strText;
		end 
		local strFound = strfind(sText, "|c")
		if not strFound then
			return sText;
		else
			--GDKPd_Debug("ST:CleanString:format found, stripping")
			--GDKPd_Debug("ST:CleanString:string.sub(sText,11)" ..string.sub(sText,11));
			return string.sub(sText, 11);
		end
	end
	function stsortbyclass (a1, b1, a2, b2, direction)
		--GDKPd_Debug("ST:stsortbyclass: a1, b1, a2, b2, " ..a1.." "..b1.." "..a2.." "..b2);
		if a2 == b2 then
			--GDKPd_Debug("ST:stsortbyclass: a2 == b2");
			--GDKPd_Debug("ST:stsortbyclass: direction == " ..direction);
			if direction:lower() == "asc" then
				return a1 > b1;
			else
				return a1 < b1;
			end
		else
			if direction:lower() == "asc" then
				return a2 > b2;
			else
				return a2 < b2;
			end
		end
	end

	local Filter = function(self, rowdata)
		return true;
	end

	--- API for a ScrollingTable table
	-- @name SetFilter
	-- @description Set a display filter for the table.
	-- @usage st:SetFilter( function (self, ...) return true end )
	-- @see http://www.wowace.com/addons/lib-st/pages/filtering-the-scrolling-table/
	local function SetFilter (self, Filter)
		self.Filter = Filter;
		self:SortData();
	end

	local DoFilter = function(self)
		local result = {};
		for row = 1, #self.data do
			local realrow = self.sorttable[row];
			local rowData = self:GetRow(realrow);
			if self:Filter(rowData) then
				table.insert(result, realrow);
			end
		end
		return result;
	end

	function GetDefaultHighlightBlank(self)
		return self.defaulthighlightblank;
	end

	function SetDefaultHighlightBlank(self, red, green, blue, alpha)
		if not self.defaulthighlightblank then
			self.defaulthighlightblank = defaulthighlightblank;
		end

		if red then self.defaulthighlightblank["r"] = red; end
		if green then self.defaulthighlightblank["g"] = green; end
		if blue then self.defaulthighlightblank["b"] = blue; end
		if alpha then self.defaulthighlightblank["a"] = alpha; end
	end

	function GetDefaultHighlight(self)
		return self.defaulthighlight;
	end

	function SetDefaultHighlight(self, red, green, blue, alpha)
		if not self.defaulthighlight then
			self.defaulthighlight = defaulthighlight;
		end

		if red then self.defaulthighlight["r"] = red; end
		if green then self.defaulthighlight["g"] = green; end
		if blue then self.defaulthighlight["b"] = blue; end
		if alpha then self.defaulthighlight["a"] = alpha; end
	end

	--- API for a ScrollingTable table
	-- @name EnableSelection
	-- @description Turn on or off selection on a table according to flag.  Will not refresh the table display.
	-- @usage st:EnableSelection(true)
	local function EnableSelection(self, flag)
		self.fSelect = flag;
	end

	--- API for a ScrollingTable table
	-- @name ClearSelection
	-- @description Clear the currently selected row.  You should not need to refresh the table.
	-- @usage st:ClearSelection()
	local function ClearSelection(self)
		self:SetSelection(nil);
	end

	--- API for a ScrollingTable table
	-- @name SetSelection
	-- @description Sets the currently selected row to 'realrow'.  Realrow is the unaltered index of the data row in your table. You should not need to refresh the table.
	-- @usage st:SetSelection(12)
	local function SetSelection(self, realrow)
		self.selected = realrow;
		self:Refresh();
	end

	--- API for a ScrollingTable table
	-- @name GetSelection
	-- @description Gets the currently selected to row.  Return will be the unaltered index of the data row that is selected.
	-- @usage st:GetSelection()
	local function GetSelection(self)
		return self.selected;
	end

	--- API for a ScrollingTable table
	-- @name DoCellUpdate
	-- @description Cell update function used to paint each cell.  Can be overridden in column data or table data.
	-- @usage used internally.
	-- @see http://www.wowace.com/addons/lib-st/pages/docell-update/
	local function DoCellUpdate (rowFrame, cellFrame, data, cols, row, realrow, column, fShow, table, ...)
		if fShow then
			local rowdata = table:GetRow(realrow);
			local celldata = table:GetCell(rowdata, column);

			local cellvalue = celldata;
			if type(celldata) == "table" then
				cellvalue = celldata.value;
			end
			if type(cellvalue) == "function" then
				if celldata.args then
					cellFrame.text:SetText(cellvalue(unpack(celldata.args)));
				else
					cellFrame.text:SetText(cellvalue(data, cols, realrow, column, table));
				end
			else
				cellFrame.text:SetText(cellvalue);
			end

			local color = nil;
			if type(celldata) == "table" then
				color = celldata.color;
			end

			local colorargs = nil;
			if not color then
			 	color = cols[column].color;
			 	if not color then
			 		color = rowdata.color;
			 		if not color then
			 			color = defaultcolor;
			 		else
			 			colorargs = rowdata.colorargs;
			 		end
			 	else
			 		colorargs = cols[column].colorargs;
			 	end
			else
				colorargs = celldata.colorargs;
			end
			if type(color) == "function" then
				if colorargs then
					color = color(unpack(colorargs));
				else
					color = color(data, cols, realrow, column, table);
				end
			end
			cellFrame.text:SetTextColor(color.r, color.g, color.b, color.a);

			local highlight = nil;
			if type(celldata) == "table" then
				highlight = celldata.highlight;
			end

			if table.fSelect then
				if table.selected == realrow then
					table:SetHighLightColor(rowFrame, highlight or cols[column].highlight or rowdata.highlight or table:GetDefaultHighlight());
				else
					table:SetHighLightColor(rowFrame, table:GetDefaultHighlightBlank());
				end
			end
		else
			cellFrame.text:SetText("");
		end
	end

	--- API for a ScrollingTable table
	-- @name SetData
	-- @description Sets the data for the scrolling table
	-- @usage st:SetData(datatable)
	-- @see http://www.wowace.com/addons/lib-st/pages/set-data/
	local function SetData (self, data, isMinimalDataformat, skipsort)
		self.isMinimalDataformat = isMinimalDataformat;
		self.data = data;
		--SF: skipsort so that we don't do goofy sort
		if (skipsort == nil) or (not skipsort) then
			--GDKPd_Debug("STSetData: skipsort == false ");
			self:SortData();
		else 
			--GDKPd_Debug("STSetData: skipsort ==True ");
			self:Refresh();
		end
	end

	--- API for a ScrollingTable table
	-- @name GetRow
	-- @description Returns the data row of the table from the given data row index
	-- @usage used internally.
	local function GetRow(self, realrow)
		return self.data[realrow];
	end

	--- API for a ScrollingTable table
	-- @name GetCell
	-- @description Returns the cell data of the given row from the given row and column index
	-- @usage used internally.
	local function GetCell(self, row, col)
		local rowdata = row;
		if type(row) == "number" then
			rowdata = self:GetRow(row);
		end

		if self.isMinimalDataformat then
			return rowdata[col];
		else
			return rowdata.cols[col];
		end
	end

	--- API for a ScrollingTable table
	-- @name IsRowVisible
	-- @description Checks if a row is currently being shown
	-- @usage st:IsRowVisible(realrow)
	-- @thanks sapu94
	local function IsRowVisible(self, realrow)
		return (realrow > self.offset and realrow <= (self.displayRows + self.offset))
	end

	
	function ST2_doOnClick(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, disabledeselect, groupby, ...)
		--GDKPd_Debug("ST_doOnClick fired!");
		st = table;
		if button == "LeftButton" then	-- LS: only handle on LeftButton click (right passes thru)
			--GDKPd_Debug("ST_doOnClick button == Leftbutton");
			if not (row or realrow) then
				--GDKPd_Debug("ST_doOnClick not (row or realrow) sorting!");
				for i, col in ipairs(st.cols) do
					if i ~= column then -- clear out all other sort marks
						cols[i].sort = nil;
					end
				end
				local sortorder = "asc";
				if not cols[column].sort and cols[column].defaultsort then
					sortorder = cols[column].defaultsort; -- sort by columns default sort first;
				elseif cols[column].sort and cols[column].sort:lower() == "asc" then
					sortorder = "dsc";
				end
				cols[column].sort = sortorder;
				--check groupby default is off
				if groupby == nil then
					--do nothing, just call sortdata
					--GDKPd_Debug("ST_doOnClick:groupby not passed!");					
					table:SortData();
				else
					if groupby then
						--do new groupby
						--GDKPd_Debug("ST_doOnClick:group by class checked!");
						table:SortData(groupby);
					else
						----do nothing, just call sortdata
						--GDKPd_Debug("ST_doOnClick group by class not checked!");
						table:SortData();
					end	
				end
				

			else
				--GDKPd_Debug("ST_doOnClick row or realrow");
				if table:GetSelection() == realrow then
					if not disabledeselect then				--disable deselect in loot table
						GDKPd_Debug("ST_doOnClick not disabledeselect");
						table:ClearSelection();
					else 
						GDKPd_Debug("ST_doOnClick disabledeselect"); -- do nothing in the loot table
					end
				else
					--GDKPd_Debug("ST_doOnClick setselction");
					table:SetSelection(realrow);
				end
			end
			return true;
		end
	end 

	function ScrollingTable:CreateST(cols, numRows, rowHeight, highlight, parent)
		local st = {};
		self.framecount = self.framecount or 1;
		local f = CreateFrame("Frame", "ScrollTable2" .. self.framecount, parent or UIParent);
		--f:SetFrameStrata("MEDIUM");
		self.framecount = self.framecount + 1;
		st.showing = true;
		st.frame = f;
		
		st.Show = Show;
		st.Hide = Hide;
		st.SetDisplayRows = SetDisplayRows;
		st.SetRowHeight = SetRowHeight;
		st.SetHeight = SetHeight;
		st.SetWidth = SetWidth;
		st.SetDisplayCols = SetDisplayCols;
		st.SetData = SetData;
		st.SortData = SortData;
		st.CompareSort = CompareSort;
		st.RegisterEvents = RegisterEvents;
		st.FireUserEvent = FireUserEvent;
		st.SetDefaultHighlightBlank = SetDefaultHighlightBlank;
		st.SetDefaultHighlight = SetDefaultHighlight;
		st.GetDefaultHighlightBlank = GetDefaultHighlightBlank;
		st.GetDefaultHighlight = GetDefaultHighlight;
		st.EnableSelection = EnableSelection;
		st.SetHighLightColor = SetHighLightColor;
		st.ClearSelection = ClearSelection;
		st.SetSelection = SetSelection;
		st.GetSelection = GetSelection;
		st.GetCell = GetCell;
		st.GetRow = GetRow;
		st.DoCellUpdate = DoCellUpdate;
		st.RowIsVisible = IsRowVisible;

		st.SetFilter = SetFilter;
		st.DoFilter = DoFilter;
		
		highlight = highlight or {};
		st:SetDefaultHighlight(highlight["r"], highlight["g"], highlight["b"], highlight["a"]); -- highlight color
		st:SetDefaultHighlightBlank(); -- non highlight color

		st.displayRows = numRows or 12;
		st.rowHeight = rowHeight or 15;
		st.cols = cols;
		st.DefaultEvents = {
			["OnEnter"] = function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
				if row and realrow then
					local rowdata = table:GetRow(realrow);
					local celldata = table:GetCell(rowdata, column);
					local highlight = nil;
					if type(celldata) == "table" then
						highlight = celldata.highlight;
					end
					table:SetHighLightColor(rowFrame, highlight or cols[column].highlight or rowdata.highlight or table:GetDefaultHighlight());
				end
				return true;
			end,
			["OnLeave"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
				if row and realrow then
					local rowdata = table:GetRow(realrow);
					local celldata = table:GetCell(rowdata, column);
					if realrow ~= table.selected or not table.fSelect then
						table:SetHighLightColor(rowFrame, table:GetDefaultHighlightBlank());
					end
				end
				return true;
			end,
			["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)		-- LS: added "button" argument
				--GDKPd_Debug("ST_Onclick fired!");
				ST2_doOnClick(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...);
				return true;
				--[[ if button == "LeftButton" then	-- LS: only handle on LeftButton click (right passes thru)
					if not (row or realrow) then
						for i, col in ipairs(st.cols) do
							if i ~= column then -- clear out all other sort marks
								cols[i].sort = nil;
							end
						end
						local sortorder = "asc";
						if not cols[column].sort and cols[column].defaultsort then
							sortorder = cols[column].defaultsort; -- sort by columns default sort first;
						elseif cols[column].sort and cols[column].sort:lower() == "asc" then
							sortorder = "dsc";
						end
						cols[column].sort = sortorder;
						table:SortData();

					else
						if table:GetSelection() == realrow then
							--table:ClearSelection();
						else
							table:SetSelection(realrow);
						end
					end
					return true;
				end ]]
			end,
		};
		st.data = {};

		f:SetBackdrop(ScrollPaneBackdrop);
		f:SetBackdropColor(0.1,0.1,0.1);
		f:SetPoint("CENTER",UIParent,"CENTER",0,0);

		-- build scroll frame
		local scrollframe = CreateFrame("ScrollFrame", f:GetName().."ScrollFrame", f, "FauxScrollFrameTemplate");
		--scrollframe:SetFrameStrata("MEDIUM");
		st.scrollframe = scrollframe;
		scrollframe:Show();
		scrollframe:SetScript("OnHide", function(self, ...)
			self:Show();
		end);

		scrollframe:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4);
		scrollframe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 3);

		local scrolltrough = CreateFrame("Frame", f:GetName().."ScrollTrough", scrollframe);
		--scrolltrough:SetFrameStrata("MEDIUM");
		scrolltrough:SetWidth(17);
		scrolltrough:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -3);
		scrolltrough:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4);
		scrolltrough.background = scrolltrough:CreateTexture(nil, "BACKGROUND");
		scrolltrough.background:SetAllPoints(scrolltrough);
		scrolltrough.background:SetColorTexture(0.05, 0.05, 0.05, 1.0);
		local scrolltroughborder = CreateFrame("Frame", f:GetName().."ScrollTroughBorder", scrollframe);
		--scrolltroughborder:SetFrameStrata("MEDIUM")
		scrolltroughborder:SetWidth(1);
		scrolltroughborder:SetPoint("TOPRIGHT", scrolltrough, "TOPLEFT");
		scrolltroughborder:SetPoint("BOTTOMRIGHT", scrolltrough, "BOTTOMLEFT");
		scrolltroughborder.background = scrolltrough:CreateTexture(nil, "BACKGROUND");
		scrolltroughborder.background:SetAllPoints(scrolltroughborder);
		scrolltroughborder.background:SetColorTexture(0.5, 0.5, 0.5, 1.0);
		
		st.Refresh = function(self)
			FauxScrollFrame_Update(scrollframe, #st.filtered, st.displayRows, st.rowHeight);
			local o = FauxScrollFrame_GetOffset(scrollframe);
			st.offset = o;

			for i = 1, st.displayRows do
				local row = i + o;
				if st.rows then
					local rowFrame = st.rows[i];
					local realrow = st.filtered[row];
					local rowData = st:GetRow(realrow);
					local fShow = true;
					for col = 1, #st.cols do
						local cellFrame = rowFrame.cols[col];
						local fnDoCellUpdate = st.DoCellUpdate;
						if rowData then
							st.rows[i]:Show();
							local cellData = st:GetCell(rowData, col);
							if type(cellData) == "table" and cellData.DoCellUpdate then
								fnDoCellUpdate = cellData.DoCellUpdate;
							elseif st.cols[col].DoCellUpdate then
								fnDoCellUpdate = st.cols[col].DoCellUpdate;
							elseif rowData.DoCellUpdate then
								fnDoCellUpdate = rowData.DoCellUpdate;
							end
						else
							st.rows[i]:Hide();
							fShow = false;
						end
						fnDoCellUpdate(rowFrame, cellFrame, st.data, st.cols, row, st.filtered[row], col, fShow, st);
					end
				end
			end
		end

		scrollframe:SetScript("OnVerticalScroll", function(self, offset)
			FauxScrollFrame_OnVerticalScroll(self, offset, st.rowHeight, function() st:Refresh() end);					-- LS: putting st:Refresh() in a function call passes the st as the 1st arg which lets you reference the st if you decide to hook the refresh
		end);

		st:SetFilter(Filter);
		st:SetDisplayCols(st.cols);
		st:RegisterEvents(st.DefaultEvents);

		return st;
	end
end
