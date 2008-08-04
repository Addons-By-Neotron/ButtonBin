--[[
**********************************************************************
ButtonBin - A displayer for LibDataBroker compatible addons
**********************************************************************
Code inspired by and copied from Fortress by Borlox
**********************************************************************
]]
ButtonBin = LibStub("AceAddon-3.0"):NewAddon("ButtonBin") -- , "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")

-- Silently fail embedding if it doesn't exist
local LibStub = LibStub
LDB = LibStub:GetLibrary("LibDataBroker-1.1")

local Logger = LibStub("LibLogger-1.0", true)
if Logger then
   Logger:Embed(ButtonBin)
end

local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")
local mod = ButtonBin

local fmt = string.format
local tinsert = table.insert
local tsort   = table.sort
local tconcat = table.concat
local tremove = table.remove
local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring 
local unpack = unpack
local lower = string.lower

buttonBin = nil
local ldbObjects = {}
local buttonFrames = {}
local options


function mod.clear(tbl)
   if type(tbl) == "table" then
      for id,data in pairs(tbl) do
	 if type(data) == "table" then mod.del(data) end
	 tbl[id] = nil
      end
   end
end   
   

function mod.get()
   return tremove(tableStore) or {}
end

function mod.del(tbl, index)
   local todel = tbl
   if index then todel = tbl[index] end
   if type(todel) ~= "table" then return end
   mod.clear(todel)
   tinsert(tableStore, todel)
   if index then tbl[index] = nil end
end

local defaults = {
   profile = {
      -- TBD
      enabledDataObjects = {
	 ['*'] = {
	    enabled = true
	 },
      },
      size = 24,
      scale = 1.0,
      width  = 10
   }
}

function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("ButtonBinDB", defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileDeleted","OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
   db = self.db.profile

   
   options.profile = DBOpt:GetOptionsTable(self.db)

   buttonBin = CreateFrame("Frame", "ButtonBinParent", UIParent)
   buttonBin:EnableMouse(true)
   buttonBin:SetClampedToScreen(true)
   buttonBin:SetWidth(300)
   buttonBin:SetHeight(db.size)
   buttonBin:SetScale(db.scale)
   buttonBin:Show()

   local bgFrame = {
      bgFile = "Interface/Tooltips/UI-Tooltip-Background", 
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 6,
      insets = {left = 1, right = 1, top = 1, bottom = 1}
   }
   buttonBin.mover = CreateFrame("Button", "ButtonBinMover", UIParent)
   buttonBin.mover:EnableMouse(true)
   buttonBin.mover:SetMovable(true)
   buttonBin.mover:SetBackdrop(bgFrame)
   buttonBin.mover:SetBackdropColor(0, 1, 0);
   buttonBin.mover:SetClampedToScreen(true)
   buttonBin.mover:RegisterForClicks("AnyUp")
   buttonBin.mover:SetFrameStrata("HIGH")
   buttonBin.mover:SetFrameLevel(5)
   buttonBin.mover:SetAlpha(0.5)
   buttonBin.mover:SetScript("OnDragStart",
			     function() buttonBin.mover:StartMoving() end)
   buttonBin.mover:SetScript("OnDragStop",
			     function()
				local s = buttonBin:GetEffectiveScale()
				db.posx = buttonBin:GetLeft() * s
				db.posy = buttonBin:GetTop() * s
				--				mod:trace("Moved to: %f x %f", db.posx, db.posy)
				buttonBin.mover:StopMovingOrSizing() end)
   buttonBin.mover:SetScript("OnClick",
			     function(frame,button)
				if button == "RightButton" then
				   mod:ToggleLocked()
				end
			     end)
   buttonBin.mover.text = CreateFrame("Frame")
   buttonBin.mover.text:SetPoint("BOTTOMLEFT", buttonBin.mover, "TOPLEFT")   
   buttonBin.mover.text:SetPoint("BOTTOMRIGHT", buttonBin.mover, "TOPRIGHT")
   buttonBin.mover.text:SetHeight(30)
   buttonBin.mover.text:SetFrameStrata("DIALOG")
   buttonBin.mover.text:SetFrameLevel(10)

   buttonBin.mover.text.label = buttonBin.mover.text:CreateFontString(nil, nil, "GameFontNormal")
   buttonBin.mover.text.label:SetJustifyH("CENTER")
   buttonBin.mover.text.label:SetPoint("BOTTOM")
   buttonBin.mover.text.label:SetText("Right click to stop moving")
   buttonBin.mover.text.label:SetNonSpaceWrap(true)
   buttonBin.mover.text:SetAlpha(1)

   buttonBin.mover:Hide()
   buttonBin.mover.text:Hide()
   mod:SetupOptions()

   self.ldb =
      LDB:NewDataObject("ButtonBin",
			{
			   type =  "launcher", 
			   label = "Button Bin",
			   icon = "Interface\\AddOns\\ButtonBin\\bin.tga",
			   tooltiptext = ("|cffffff00Left click|r to collapse/uncollapse all other icons.\n"..
					  "|cffffff00Middle click|r to open the Button Bin configuration.\n"..
					  "|cffffff00Right click|r to toggle the Button Bin window lock."), 

			   OnClick = function(clickedframe, button)
					if button == "LeftButton" then
					   mod:ToggleCollapsed()
					elseif button == "MiddleButton" then
					   mod:ToggleConfigDialog()
					elseif button == "RightButton" then
					   mod:ToggleLocked()
					end
				     end,
			})
   
end

local GameTooltip = GameTooltip
local function GT_OnLeave(self)
	self:SetScript("OnLeave", self.oldOnLeave)
	self.oldOnLeave = nil
	self:Hide()
	GameTooltip:EnableMouse(false)
end

local function getAnchors(frame)
   local x, y = frame:GetCenter()
   local leftRight
   if x < GetScreenWidth() / 2 then
      leftRight = "LEFT"
   else
      leftRight = "RIGHT"
   end
   if y < GetScreenHeight() / 2 then
      return "BOTTOM", "TOP"
   else
      return "TOP", "BOTTOM"
   end
end

local function PrepareTooltip(frame, anchorFrame, isGameTooltip)
   if frame == GameTooltip then
      frame.oldOnLeave = frame:GetScript("OnLeave")
      frame:EnableMouse(true)
      frame:SetScript("OnLeave", GT_OnLeave)
   end
   frame:SetOwner(anchorFrame, "ANCHOR_NONE")
   frame:ClearAllPoints()
   local a1, a2 = getAnchors(anchorFrame)
   frame:SetPoint(a1, anchorFrame, a2)	
end

local function LDB_OnEnter(self, now)
   local obj = self.obj

   if obj.tooltip then
      PrepareTooltip(obj.tooltip, self)
      obj.tooltip:Show()
      if obj.tooltiptext then
	 obj.tooltip:SetText(obj.tooltiptext)
      end
   elseif obj.OnTooltipShow then
      PrepareTooltip(GameTooltip, self, true)
      obj.OnTooltipShow(GameTooltip)
      GameTooltip:Show()
   elseif obj.tooltiptext then
      PrepareTooltip(GameTooltip, self, true)
      GameTooltip:SetText(obj.tooltiptext)
      GameTooltip:Show()
   elseif self.buttonBinText and not obj.OnEnter then
      PrepareTooltip(GameTooltip, self, true)
      GameTooltip:SetText(self.buttonBinText)
      GameTooltip:Show()
      self.hideTooltipOnLeave = true
   end
   if obj.OnEnter then
      obj.OnEnter(self)
   end
--   resizeBin(buttonBin)
end

local function LDB_OnLeave(self)
   local obj = self.obj
--   resizeWindow(buttonBin)
   if not obj then return end
   if MouseIsOver(GameTooltip) and (obj.tooltiptext or obj.OnTooltipShow) then return end	

   if self.hideTooltipOnLeave or obj.tooltiptext or obj.OnTooltipShow then
      GT_OnLeave(GameTooltip)
      self.hideTooltipOnLeave = nil
   end
   if obj.OnLeave then
      obj.OnLeave(self)
   end
end


function mod:LibDataBroker_DataObjectCreated(event, name, obj)
   ldbObjects[name] = obj
   if db.enabledDataObjects[name].enabled then
      mod:EnableDataObject(name, obj)
   end
end

local updaters = {
   text = function(frame, value, name, object)
	     local text
	     if type(object.label) == "string" then
		if object.value and (type(object.value) == "string" or type(object.value) == "number") then
		   text = fmt("|cffffffff%s:|r %s|cffffffff%s|r", object.label, object.value, ((type(object.suffix) == "string" or type(object.suffix) == "number") and object.suffix) or "")
		elseif object.text and object.text ~= object.label and string.find(object.text, "%S") then
		   text = fmt("|cffffffff%s:|r %s", object.label, object.text)
		else
		   text = fmt("|cffffffff%s|r", object.label)
		end
	     elseif object.value and (type(object.value) == "string" or type(object.value) == "number") then
		text = fmt("%s|cffffffff%s|r", object.value, ((type(object.suffix) == "string" or type(object.suffix) == "number") and object.suffix) or "")
	     elseif object.text then
		text = object.text
	     elseif object.type and object.type == "launcher" then
		local addonName, title = GetAddOnInfo(object.tocname or name)
		text = fmt("|cffffffff%s|r", title or addonName or name)
	     end
	     frame.buttonBinText = text
	  end,	
   icon = function(frame, value, name)
	     frame.icon:SetTexture(value)
	  end,
   OnClick = function(frame, value)
		frame:SetScript("OnClick", value)
	     end,
   tooltiptext = function(frame, value, name, object)
		    local tt = object.tooltip or GameTooltip
		    if tt:GetOwner() == frame then
		       tt:SetText(object.tooltiptext)
		    end
		 end,
}

function mod:AttributeChanged(event, name, key, value)
   if not db.enabledDataObjects[name].enabled then return end
   local f = buttonFrames[name]
   local obj = ldbObjects[name]

   if f and obj and updaters[key] then
      updaters[key](f, value, name, obj)     
   end   
end

function mod:EnableDataObject(name, obj)
   db.enabledDataObjects[name].enabled = true
   -- create frame for object
   local frame = buttonFrames[name] or mod:GetFrame()
   buttonFrames[name] = frame
   frame.db = db.enabledDataObjects[name]
   frame.name = name
   frame.obj = obj

   frame:SetScript("OnEnter", LDB_OnEnter)
   frame:SetScript("OnLeave", LDB_OnLeave)
   
   for key, func in pairs(updaters) do
      func(frame, obj[key], name, obj) 
   end	

   LDB.RegisterCallback(self, "LibDataBroker_AttributeChanged_"..name, "AttributeChanged")

   mod:SortFrames()
end

function mod:DisableDataObject(name, obj)
   db.enabledDataObjects[name].enabled = false
   LDB.UnregisterCallback(self, "LibDataBroker_AttributeChanged_"..name)
   if buttonFrames[name] then
      self:ReleaseFrame(buttonFrames[name])
   end
end

function mod:OnEnable()
   self:ApplyProfile()
   if self.SetLogLevel then
      self:SetLogLevel(self.logLevels.TRACE)
   end
   for name, obj in LDB:DataObjectIterator() do
      self:LibDataBroker_DataObjectCreated(nil, name, obj)
   end
   LDB.RegisterCallback(self, "LibDataBroker_DataObjectCreated")
   self:SortFrames()
end

function mod:OnDisable()
   LDB.UnregisterAllCallbacks(self)
   buttonBin:Hide()
end
function mod:PLAYER_REGEN_ENABLED()
end

function mod:PLAYER_REGEN_DISABLED()
end

function mod:ApplyProfile()
   if buttonBin.mover:IsVisible() then
      mod:ToggleLocked()
   end
   buttonBin:ClearAllPoints()
   self:SortFrames() -- will handle any size changes etc
   local posx = db.posx 
   local posy = db.posy
   if posx and posy then
      local s = buttonBin:GetEffectiveScale()
      buttonBin:SetPoint("TOPLEFT", posx/s, (posy - UIParent:GetHeight()*UIParent:GetEffectiveScale())/s)
   else
      buttonBin:SetPoint("TOPLEFT", UIParent, "CENTER")
   end
end

function mod:OnProfileChanged(event, newdb)
   if event ~= "OnProfileDeleted" then
      db = self.db.profile
      if not db.colors then db.colors = colors end -- set default if needed
      self:ApplyProfile()
   end
end

function mod:ToggleLocked()
   if buttonBin.mover:IsVisible () then
      local s = buttonBin:GetEffectiveScale()
      buttonBin:ClearAllPoints()
      buttonBin:SetPoint("TOPLEFT", db.posx / s, (db.posy - UIParent:GetHeight()*UIParent:GetEffectiveScale())/s)
      buttonBin.mover:RegisterForDrag()
      buttonBin.mover:Hide()
      buttonBin.mover.text:Hide()
   else
      buttonBin.mover:ClearAllPoints()
      buttonBin.mover:SetWidth(buttonBin:GetWidth())
      buttonBin.mover:SetHeight(buttonBin:GetHeight())
      buttonBin.mover:SetScale(buttonBin:GetScale())
      buttonBin.mover:SetPoint(buttonBin:GetPoint())
      buttonBin.mover:RegisterForDrag("LeftButton")
      buttonBin:ClearAllPoints()
      buttonBin:SetPoint("TOPLEFT", buttonBin.mover)
      buttonBin.mover:Show()
      buttonBin.mover.text:Show()
   end
end

options = { 
   sizing = {
      type = "group",
      name = "Bin Size",
      order = 4,
      args = { 
	 toggle = {
	    type = "toggle",
	    name = "Lock the button bin frame",
	    get = function() return not buttonBin.mover:IsVisible() end,
	    set = function() mod:ToggleLocked() end,
	 },
	 height = {
	    type = "range",
	    name = "Button Size",
	    width = "full",
	    min = 5, max = 50, step = 1,
	    set = function(_,val) db.size = val mod:SortFrames() end,
	    get = function() return db.size end
	 }, 
	 scale = {
	    type = "range",
	    name = "Bin Scale",
	    width = "full",
	    min = 0.01, max = 5, step = 0.05,
	    set = function(_,val) db.scale = val
		     buttonBin:SetScale(val)
		     buttonBin.mover:SetScale(buttonBin:GetScale())
		  end,
	    get = function() return db.scale end
	 },
	 width = {
	    type = "range",
	    name = "Bin Width",
	    width = "full",
	    min = 1, max = 100, step = 1, 
	    set = function(_,val) db.width = val mod:SortFrames() end,
	    get = function() return db.width end
	 },

      }
   },
   objects = {
      name = "Enabled Data Objects",
      type = "group",
      args = {
	 objs = {
	    name = "",
	    type = "multiselect",
	    values = function()
			local tbl = {}
			for name in pairs(db.enabledDataObjects) do
			   if name ~= "ButtonBin" and LDB:GetDataObjectByName(name) then
			      tbl[name] = name
			   end
			end
			return tbl
		     end,
	    get = function(_,key)  return db.enabledDataObjects[key].enabled end,
	    set = function(_,key,state)
		     db.enabledDataObjects[key].enabled = state
		     if state then
			mod:LibDataBroker_DataObjectCreated("config", key,
							    LDB:GetDataObjectByName(key))
		     else
			mod:DisableDataObject(key)
		     end
		  end
	       }
      }
   },
   cmdline = {
      name = "Command Line",
      type = "group",
      args = {
	 config = {
	    type = "execute",
	    name = "Show configuration dialog",
	    func = function() mod:ToggleConfigDialog() end,
	    dialogHidden = true
	 },
	 toggle = {
	    type = "execute",
	    name = "Toggle the frame lock",
	    func = function() mod:ToggleLocked() end,
	    dialogHidden = true
	 },
      }
   }
}


function mod:OptReg(optname, tbl, dispname, cmd)
   if dispname then
      optname = "ButtonBin"..optname
      LibStub("AceConfig-3.0"):RegisterOptionsTable(optname, tbl, cmd)
      if not cmd then
	 return LibStub("AceConfigDialog-3.0"):AddToBlizOptions(optname, dispname, "Button Bin")
      end
   else
      LibStub("AceConfig-3.0"):RegisterOptionsTable(optname, tbl, cmd)
      if not cmd then
	 return LibStub("AceConfigDialog-3.0"):AddToBlizOptions(optname, "Button Bin")
      end
   end
end

function mod:SetupOptions()
   mod.main = mod:OptReg("Button Bin", options.sizing)
   mod:OptReg(": Data Blocks", options.objects, "Data Blocks")
   mod.profile = mod:OptReg(": Profiles", options.profile, "Profiles")
   mod:OptReg("Button Bin CmdLine", options.cmdline, nil,  { "buttonbin", "bin" })
end

function mod:ToggleConfigDialog()
   InterfaceOptionsFrame_OpenToFrame(mod.profile)
   InterfaceOptionsFrame_OpenToFrame(mod.main)
end

function mod:ToggleCollapsed()
   buttonBin.collapsed = not buttonBin.collapsed
   mod:SortFrames()
end


function mod:SortFrames()
   local xoffset = 0
   local width = 0
   local height = 0
   local sorted = {}
   local frame
   local addBin = false
   if not buttonBin.collapsed then
      for name in pairs(buttonFrames) do
	 if name ~= "ButtonBin" then tinsert(sorted, name) else addBin = true end
      end
      tsort(sorted)
   else
      for name in pairs(buttonFrames) do
	 if name ~= "ButtonBin" then buttonFrames[name]:Hide() else addBin = true end
      end
   end
   if addBin then tinsert(sorted, 1, "ButtonBin") end
   local count = 1
   local previousFrame
   for _,name in ipairs(sorted) do
      if count == 1 then height = height + db.size end
      frame = buttonFrames[name]
      frame:SetWidth(db.size)
      frame:SetHeight(db.size)
      frame:ClearAllPoints()
      if previousFrame then
	 frame:SetPoint("TOPLEFT", previousFrame, "TOPRIGHT")
      else
	 frame:SetPoint("TOPLEFT", buttonBin, "TOPLEFT", 0, -(height-db.size))
      end
      frame:Show()
      count = count + 1
      xoffset = xoffset + frame:GetWidth()
      if xoffset > width then
	 width =  xoffset
      end
      if count > db.width then
	 previousFrame = nil
	 xoffset = 0
	 count = 1
      else
	 previousFrame = frame
      end
   end
   buttonBin:SetWidth(width)
   buttonBin:SetHeight(height)
   buttonBin:Show()
   buttonBin.mover:SetWidth(buttonBin:GetWidth())
   buttonBin.mover:SetHeight(buttonBin:GetHeight())
end


local unusedFrames = {}

function mod:GetFrame()
   local frame
   if #unusedFrames > 0 then
      frame = unusedFrames[#unusedFrames]
      unusedFrames[#unusedFrames] = nil
   else
      frame = CreateFrame("Button", nil, buttonBin)
      frame:SetWidth(db.size)
      frame:SetHeight(db.size)
      frame:EnableMouse(true)
      frame:RegisterForClicks("AnyUp")
      frame.icon = frame:CreateTexture()
      frame.icon:SetPoint("TOPLEFT", frame)
      frame.icon:SetPoint("BOTTOMRIGHT", frame)
      frame.resizeWindow = function(self)
			      self:SetWidth(db.size)
			      self:SetHeight(db.size)
			   end
   end
   return frame
end

function mod:ReleaseFrame(frame)
   buttonFrames[frame.name] = nil
   unusedFrames[#unusedFrames+1] = frame
   frame:Hide()
   frame.buttonBinText = nil
   frame.db = nil
   frame.name = nil
   frame.obj = nil
   frame:SetScript("OnEnter", nil)
   frame:SetScript("OnLeave", nil)
   frame:SetScript("OnClick", nil)
   self:SortFrames()
end
   
