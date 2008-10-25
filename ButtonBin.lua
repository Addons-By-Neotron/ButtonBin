--[[
**********************************************************************
ButtonBin - A displayer for LibDataBroker compatible addons
**********************************************************************
Code inspired by and copied from Fortress by Borlox
**********************************************************************
]]
ButtonBin = LibStub("AceAddon-3.0"):NewAddon("ButtonBin", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0" )

-- Silently fail embedding if it doesn't exist
local LibStub = LibStub
LDB = LibStub:GetLibrary("LibDataBroker-1.1")

local BB_DEBUG = false

local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")
local media = LibStub("LibSharedMedia-3.0")
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

local bins = {}
local binTimers = {}

local ldbObjects = {}
local buttonFrames = {}
local options
local db

local unlockButtons = false
local unlockFrames = false
local playerInCombat = false

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
      width  = 10,
      hpadding = 0.5,
      vpadding = 0.5,
      bins = {
	 ['*'] = {
	    colors = {
	       backgroundColor = { 0, 0, 0, 0},
	       borderColor = { 0, 0, 0, 0 },
	    },
	    edgeSize = 10,
	    size = 24,
	    scale = 1.0,
	    width  = 10,
	    hpadding = 0.5,
	    vpadding = 0.5,
	    collapsed = false,
	    useGlobal = true,
	    flipx = false,
	    flipy = false,
	    hideEmpty = true,
	    sortedButtons = {},
	    newlyAdded = true,
	    hidden = true,
	    labelOnMouse = false,
	    binLabel = true,
	    visibility = "always",
	    hideTimeout = 2,
	    border = "None",
	    background = "Solid",
	    fontsize = 12,
	    pixelwidth = 0,
	    clampToScreen = true,
	    font = "Friz Quadrata TT",
	 }
      },
   }
}


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

local function BB_OnClick(clickedFrame, button)
   if button == "LeftButton" then
      if IsAltKeyDown() then
	 mod:ToggleButtonLock()
      else
	 mod:ToggleCollapsed(clickedFrame)
      end
   elseif button == "MiddleButton" then
      mod:ToggleLocked()
   elseif button == "RightButton" then
      mod:ToggleConfigDialog(clickedFrame)
   end
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
   self._isMouseOver = true
   self:resizeWindow()
   local bin = self:GetParent()
   bin._isMouseOver = true
   bin:ShowOrHide()
end

local function LDB_OnLeave(self)
   local obj = self.obj
   local bin = self:GetParent()
   self._isMouseOver = nil
   bin._isMouseOver = nil
   bin:ShowOrHide(true)
   self:resizeWindow()
   if not obj then return end
   if mod:MouseIsOver(GameTooltip) and (obj.tooltiptext or obj.OnTooltipShow) then return end	

   if self.hideTooltipOnLeave or obj.tooltiptext or obj.OnTooltipShow then
      GT_OnLeave(GameTooltip)
      self.hideTooltipOnLeave = nil
   end
   if obj.OnLeave then
      obj.OnLeave(self)
   end
end

function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("ButtonBinDB", defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileDeleted","OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
   db = self.db.profile

   options.profile = DBOpt:GetOptionsTable(self.db)

   -- Initialize 5 bins, hiding all but the first
   for id=1,5 do
      local bin = db.bins[id]
      if bin.newlyAdded then
	 if id == 1 then bin.hidden = false end
      end
      bin.newlyAdded = nil
   end

   local bgFrame = {
      bgFile = "Interface/Tooltips/UI-Tooltip-Background", 
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 6,
      insets = {left = 1, right = 1, top = 1, bottom = 1}
   }
   local tooltip = "Button Bin %d\n"..
      "|cffffff00Left click|r to collapse/uncollapse all other icons.\n"..
      "|cffffff00Alt-Left click|r to toggle the button lock.\n"..
      "|cffffff00Middle click|r to toggle the Button Bin window lock.\n"..
      "|cffffff00Right click|r to open the Button Bin configuration.\n"

   for id,bdb in pairs(db.bins) do
      local f = setmetatable(CreateFrame("Frame", "ButtonBinParent:"..id, UIParent), mod.binMetaTable_mt)
      local sdb
      if bdb.useGlobal then sdb = db else sdb = bdb end
      bins[id] = f
      f.binId = id
      f:EnableMouse(true)
      f:SetClampedToScreen(bdb.clampToScreen)
      f:SetScale(sdb.scale)
      f:FixBackdrop()
      f:SetScript("OnEnter", function(self) self._isMouseOver = true self:ShowOrHide() end)
      f:SetScript("OnLeave", function(self) self._isMouseOver = nil  self:ShowOrHide(true) end)
      f.mover = CreateFrame("Button", "ButtonBinMover", UIParent)
      f.mover:EnableMouse(true)
      f.mover:SetMovable(true)
      f.mover:SetBackdrop(bgFrame)
      f.mover:SetBackdropColor(0, 1, 0);
      f.mover:SetClampedToScreen(bdb.clampToScreen)
      f.mover:RegisterForClicks("AnyUp")
      f.mover:SetFrameStrata("HIGH")
      f.mover:SetFrameLevel(5)
      f.mover:SetAlpha(0.5)
      f.mover:SetScript("OnDragStart",
			       function(self) self:StartMoving() end)
      f.mover:SetScript("OnDragStop",
			       function(self)
				  mod:SavePosition(f)
				  self:StopMovingOrSizing() end)
      f.mover:SetScript("OnClick",
			       function(frame,button)
				  mod:ToggleLocked()
			       end)
      f.mover.text = CreateFrame("Frame")
      f.mover.text:SetPoint("BOTTOMLEFT", f.mover, "TOPLEFT")   
      f.mover.text:SetPoint("BOTTOMRIGHT", f.mover, "TOPRIGHT")
      f.mover.text:SetHeight(30)
      f.mover.text:SetFrameStrata("DIALOG")
      f.mover.text:SetFrameLevel(10)
      
      f.mover.text.label = f.mover.text:CreateFontString(nil, nil, "GameFontNormal")
      f.mover.text.label:SetJustifyH("CENTER")
      f.mover.text.label:SetPoint("BOTTOM")
      f.mover.text.label:SetText("Click to stop moving")
      f.mover.text.label:SetNonSpaceWrap(true)
      f.mover.text:SetAlpha(1)

      f.button = self:GetFrame()
      f.button:SetParent(f)
      f.button:SetScript("OnClick", BB_OnClick)
      f.button:SetScript("OnEnter", LDB_OnEnter)
      f.button:SetScript("OnLeave", LDB_OnLeave)
      f.button.icon:SetTexture("Interface\\AddOns\\ButtonBin\\bin.tga")
      f.button.db = { bin = id, tooltiptext = tooltip:format(id) }
      f.button.obj = f.button.db
      f.button.name = "ButtonBin"
      if bdb.binLabel then
	 f.button.buttonBinText = "Bin #"..id
      end
      f:ShowOrHide()
      f.mover:Hide()
      f.mover.text:Hide()
   end
   
   mod:SetupOptions()
   
   
   if BB_DEBUG then
      -- Just for easy access while debugging
      bbdb = db
      bns = bins
      bf = buttonFrames
   end
end

function mod:LibDataBroker_DataObjectCreated(event, name, obj)
   ldbObjects[name] = obj
   if db.enabledDataObjects[name].enabled then
      mod:EnableDataObject(name, obj)
      local bdb = db.bins[buttonFrames[name].db.bin]
      for _,bname in ipairs(bdb.sortedButtons) do
	 if name == bname then
	    return
	 end
      end
      bdb.sortedButtons[#bdb.sortedButtons+1] = name
   end
end

local updaters = {
   text = function(frame, value, name, object, delay)
	     local bdb = db.bins[frame.db.bin]
	     local text, shortText
	     if type(object.label) == "string" then
		if object.value and (type(object.value) == "string" or type(object.value) == "number") then
		   text = fmt("|cffffffff%s:|r %s|cffffffff%s|r", object.label, object.value, ((type(object.suffix) == "string" or type(object.suffix) == "number") and object.suffix) or "")
		elseif object.text and object.text ~= object.label and string.find(object.text, "%S") then
		   text = fmt("|cffffffff%s:|r %s", object.label, object.text)
		else
		   text = fmt("|cffffffff%s|r", object.label)
		end
	     end
	     if object.value and (type(object.value) == "string" or type(object.value) == "number") then
		shortText = fmt("%s|cffffffff%s|r", object.value, ((type(object.suffix) == "string" or type(object.suffix) == "number") and object.suffix) or "")
	     elseif object.text then
		shortText = object.text
	     elseif object.type and object.type == "launcher" then
		local addonName, title = GetAddOnInfo(object.tocname or name)
		shortText = fmt("|cffffffff%s|r", title or addonName or name)
	     end
	     frame.buttonBinText = text
	     frame.shortButtonText = shortText
	     
	     if not delay then
		frame:resizeWindow(true)
	     end
	  end,	
   icon = function(frame, value, name, delay)
	     frame.icon:SetTexture(value)
	     local has_texture = not not value
	     if has_texture ~= frame._has_texture then
		frame._has_texture = has_texture
		if not delay then
		   frame:resizeWindow(true)
		end
	     end
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
   obj[key] = value
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
   if not frame.db.bin then
      frame.db.bin = 1
   end
   frame:SetParent(bins[frame.db.bin])
   frame:SetScript("OnEnter", LDB_OnEnter)
   frame:SetScript("OnLeave", LDB_OnLeave)
   
   for key, func in pairs(updaters) do
      func(frame, obj[key], name, obj, true) 
   end	

   LDB.RegisterCallback(self, "LibDataBroker_AttributeChanged_"..name, "AttributeChanged")

   mod:SortFrames(frame:GetParent())
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
   for _,bin in ipairs(bins) do
      self:SortFrames(bin)
   end
   -- Seems to fire when resizing the window or switching from fullscreen to
   -- windowed mode but not at other times
   self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS","RecalculateSizes")
   self:RegisterEvent("PLAYER_REGEN_ENABLED")
   self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function mod:OnDisable()
   self:UnregisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
   self:UnregisterEvent("PLAYER_REGEN_ENABLED")
   self:UnregisterEvent("PLAYER_REGEN_DISABLED")
   LDB.UnregisterAllCallbacks(self)

   for id,bin in ipairs(bins) do
      bin:Hide()
      if binTimers[id] then
	 self:CancelTimer(binTimers[id], true)
	 binTimers[id] = nil
      end

   end
end

function mod:PLAYER_REGEN_ENABLED()
   playerInCombat = false
   for id,bin in ipairs(bins) do
      bin:ShowOrHide(db.bins[id].visibility == "inCombat")
   end
end

function mod:PLAYER_REGEN_DISABLED()
   playerInCombat = true
   for id,bin in ipairs(bins) do
      bin:ShowOrHide(db.bins[id].visibility == "noCombat")
   end
end

do
   local timer 
   function Low_RecalculateSizes()
      for _,bin in ipairs(bins) do
	 mod:SortFrames(bin)
      end
   end
   function mod:RecalculateSizes()
      if timer then mod:CancelTimer(timer, true) timer = nil end
      timer = mod:ScheduleTimer(Low_RecalculateSizes, 1)
   end
end

function mod:ApplyProfile()
   for _,frame in pairs(buttonFrames) do
      mod:ReleaseFrame(frame)
   end
   for name, obj in LDB:DataObjectIterator() do
      self:LibDataBroker_DataObjectCreated(nil, name, obj)
   end   
   for _,bin in ipairs(bins) do
      if bin.mover:IsVisible() then
	 mod:ToggleLocked()
      end
      bin:ClearAllPoints()
      self:SortFrames(bin) -- will handle any size changes etc
      mod:LoadPosition(bin)
   end
end

function mod:SavePosition(bin)
   local s = bin:GetEffectiveScale()
   local bdb = db.bins[bin.binId]
   local top = bin:GetTop()
   if not top then return end -- the bin is empty, and bin icon hidden
   if bdb.flipy then
      bdb.posy = bin:GetBottom() * s
      bdb.anchor = "BOTTOM"
   else
      bdb.posy =  top * s - UIParent:GetHeight()*UIParent:GetEffectiveScale() 
      bdb.anchor = "TOP"
   end
   if bdb.flipx then
      bdb.anchor = bdb.anchor .. "RIGHT"
      bdb.posx = bin:GetRight() * s - UIParent:GetWidth()*UIParent:GetEffectiveScale() 
   else
      bdb.anchor = bdb.anchor .. "LEFT"
      bdb.posx = bin:GetLeft() * s
   end
end

function mod:LoadPosition(bin)
   local bdb = db.bins[bin.binId]
   local posx = bdb.posx 
   local posy = bdb.posy

   local anchor = bdb.anchor
   bin:ClearAllPoints()
   if not anchor then  anchor = "TOPLEFT" end
   local s = bin:GetEffectiveScale()
   if posx and posy then
      bin:SetPoint(anchor, posx/s, posy/s)
   else
      bin:SetPoint(anchor, UIParent, "CENTER")
   end
end

function mod:OnProfileChanged(event, newdb, src)
   if event ~= "OnProfileDeleted" then
      db = self.db.profile
      if event == "OnProfileCopied" then
	 -- This hack seems to be necessary for some reason
	 -- no sure why but otherwise I get extra crap
	 local srcBins = ButtonBinDB.profiles[src].bins
	 for id,data in ipairs(srcBins) do
	    local buttons = db.bins[id] and db.bins[id].sortedButtons
	    if data.sortedButtons and buttons then
	       for pos = #data.sortedButtons+1, #buttons do
		  buttons[pos] = nil
	       end
	    end
	 end
      end
      self:ApplyProfile()
   end
end

function mod:ToggleLocked()
   unlockFrames = not unlockFrames
   for id,bin in ipairs(bins) do 
      if not unlockFrames then
	 local s = bin:GetEffectiveScale()
	 bin.mover:RegisterForDrag()
	 bin.mover:Hide()
	 bin.mover.text:Hide()
	 mod:LoadPosition(bin)
	 bin:ShowOrHide()
      else
	 bin.mover:ClearAllPoints()
	 bin.mover:SetWidth(bin:GetWidth())
	 bin.mover:SetHeight(bin:GetHeight())
	 bin.mover:SetScale(bin:GetScale())
	 bin.mover:SetPoint(bin:GetPoint())
	 bin.mover:RegisterForDrag("LeftButton")
	 bin:ClearAllPoints()
	 bin:SetPoint("TOPLEFT", bin.mover)
	 bin.mover:Show()
	 bin.mover.text:Show()
	 bin:ShowOrHide()
      end
   end
end

function mod:ToggleButtonLock()
   unlockButtons = not unlockButtons
   
   local dragButton
   if unlockButtons then dragButton = "LeftButton" end
      if unlockButtons then
	 mod:Print("Button positions are now unlocked.")
      else
	 mod:Print("Locking button positions.")
      end
   for name,frame in pairs(buttonFrames) do
      frame:RegisterForDrag(dragButton)
      frame:SetMovable(unlockButtons)
      if unlockButtons then
	 frame._onenter = frame:GetScript("OnEnter")
	 frame._onleave = frame:GetScript("OnLeave")
	 frame:SetScript("OnEnter", nil)
	 frame:SetScript("OnLeave", nil)
      else
	 frame:SetScript("OnEnter", frame._onenter or LDB_OnEnter)
	 frame:SetScript("OnLeave", frame._onleave or LDB_OnLeave)
	 frame._onenter = nil frame._onleave = nil
      end
   end
   for _,bin in ipairs(bins) do
      bin:ShowOrHide()
   end
end
   
function mod:ReloadFrame(bin)
   local wasUnlocked = unlockFrames
   if wasUnlocked then mod:ToggleLocked() end
   mod:SortFrames(bin)
   mod:SavePosition(bin)
   mod:LoadPosition(bin)
   if wasUnlocked then mod:ToggleLocked() end
end

options = { 
   global = {
      type = "group",
      name = "Global Settings",
      order = 4,
      childGroups = "tab",
      handler = mod,
      get = "GetOption", 
      set = "SetOption", 
      args = {
	 toggle ={ 
	    type = "toggle",
	    name = "Lock the button bin frame",
	    width = "full",
	    get = function() return not unlockFrames end,
	    set = function() mod:ToggleLocked() end,
	 },
	 toggleButton = {
	    type = "toggle",
	    name = "Lock data broker button positions",
	    desc = "When unlocked, you can move buttons into a new position on the bar.",
	    width = "full",
	    get = function() return not unlockButtons end,
	    set = function() mod:ToggleButtonLock() end
	 },
	 globalScale = {
	    type = "group",
	    name = "Scale and Size",
	    args = {
	       hpadding = {
		  type = "range",
		  name = "Horizontal Button Padding",
		  width = "full",
		  min = 0, max = 50, step = 0.1,
		  order = 130,
	       }, 
	       vpadding = {
		  type = "range",
		  name = "Vertical Button Padding",
		  width = "full",
		  min = 0, max = 50, step = 0.1,
		  order = 140,
	       },
	       size = {
		  type = "range",
		  name = "Button Size",
		  width = "full",
		  min = 5, max = 50, step = 1,
		  order = 160,
	       },
	       scale = {
		  type = "range",
		  name = "Bin Scale",
		  width = "full",
		  min = 0.01, max = 5, step = 0.05,
		  order = 170,
	       },
	    }

	 }
      }
   },
   binConfig = {
      type = "group",
      name = "Bin #",
      order = 4,
      childGroups = "tab",
      get = "GetOption", 
      set = "SetOption", 
      args = {
	 general = {
	    type = "group",
	    name = "General",
	    args = {
	       hideEmpty = {
		  type = "toggle",
		  name = "Hide blocks without icons",
		  desc = "This will hide all addons that lack icons instead of showing an empty space.",
		  width = "full",
		  order = 10,
	       },
	       clampToScreen = {
		  type = "toggle",
		  name = "Clamp to screen",
		  desc = "Prevent the bin to be moved outside the boundaries of the screen.",
		  width = "full",
		  order = 10,
	       },
	       hidden = {
		  type = "toggle",
		  name = "Hide button bin",
		  width = "full",
		  desc = "Hide or show this bin.",
		  order = 20,
	       },
	       hideBinIcon = {
		  width = "full",
		  type = "toggle",
		  name = "Hide button bin icon",
		  desc = "Hide or show the button bin icon for this bin.",
		  order = 30
	       },
	       hideIcons = {
		  width = "full",
		  type = "toggle",
		  name = "Hide all icons",
		  desc = "Hide the icons of all datablocks in this bin. Note that datablocks without a label will be invisible if this is enabled.",
		  order = 31,
		  disabled = "DisableLabelOption",
	       },
	       headerLabels = {
		  type = "header",
		  name = "Labels",
		  order = 35,
	       },
	       showLabels = {
		  width = "full",
		  type = "toggle",
		  name = "Show labels",
		  order = 40,
	       },
	       binLabel = {
		  type = "toggle",
		  width = "full",
		  name = "Show button bin label",
		  order = 50,
		  disabled = "DisableBinLabelOption",
	       },
	       labelOnMouse = {
		  width = "full",
		  type = "toggle",
		  name = "Show label only on mouse over",
		  desc = "Don't show any labels unless the cursor is hovering over the button.",
		  order = 55,
		  disabled = "DisableLabelOption",
	       },
	       shortLabels = {
		  width = "full",
		  type = "toggle",
		  name = "Show short text",
		  desc = "Only show the value text, not the labels.",
		  order = 70,
		  disabled = "DisableLabelOption",
	       },
	       headerVisibility = {
		  type = "header",
		  name = "Visibility",
		  order = 100,
	       },
	       visibility = {
		  type = "select",
		  name = "Bin visibility",
		  values = {
		     always = "Always visible",
		     mouse = "Show on mouseover",
		     inCombat = "Show only in combat",
		     noCombat = "Hide during combat"
		  },
		  order = 110,
	       },
	       hideTimeout = {
		  type = "range",
		  name = "Seconds until hidden",
		  desc = "Wait this many seconds until hiding the bin after the condition is met (in combat etc).",
		  disabled = "DisableHideOption",
		  min = 0, max = 15, step = 0.1,
		  order = 120,
	       },

	    }
	 },
	 lookandfeel = {
	    type = "group",
	    name = "Look & Feel",
	    args = {
	       background = {
		  type = 'select',
		  dialogControl = 'LSM30_Background',
		  name = 'Background texture',
		  desc = 'The background texture used for the bin.',
		  order = 20,
		  values = AceGUIWidgetLSMlists.background, 
	       },
	       border = {
		  type = 'select',
		  dialogControl = 'LSM30_Border',
		  name = 'Border texture',
		  desc = 'The border texture used for the bin.',
		  order = 40,
		  values = AceGUIWidgetLSMlists.border, 
	       },
	       backgroundColor = {
		  type = "color",
		  name = "Background color",
		  hasAlpha = true,
		  set = "SetColorOpt",
		  get = "GetColorOpt",
		  order = 30,
	       },
	       borderColor = {
		  type = "color",
		  name = "Border color",
		  hasAlpha = true,
		  set = "SetColorOpt",
		  get = "GetColorOpt",
		  order = 50,
	       },
	       edgeSize = {
		  type = "range",
		  name = "Edge size",
		  desc = "Width of the border.",
		  min = 1, max = 50, step = 0.1,
	       },
	       font = {
		  type = 'select',
		  dialogControl = 'LSM30_Font',
		  name = 'Font',
		  desc = 'Font used on the bars',
		  values = AceGUIWidgetLSMlists.font, 
		  order = 1,
	       },
	       fontsize = {
		  order = 1, 
		  type = "range",
		  name = "Font size",
		  min = 1, max = 30, step = 1,
		  order = 2
	       },
	    },
	 },
	 orientation = {
	    type = "group",
	    name = "Orientation",
	    args = {
	       flipx = {
		  type = "toggle",
		  name = "Flip x-axis",
		  desc = "If toggled, the buttons will expand to the left instead of to the right.",
		  order = 90,
	       },
	       flipy = {
		  type = "toggle",
		  name = "Flip y-axis",
		  desc = "If toggled, the buttons will expand upwards instead of downwards.",
		  order = 100,
	       },
	       flipicons = {
		  type = "toggle",
		  name = "Icons on the right",
		  desc = "If checked, icons will be placed to the right of the label.",
		  order = 110,
	       },
	    }
	 },
	 spacing = {
	    type = "group",
	    name = "Padding and Sizing",
	    args = {
	       useGlobal = {
		  type = "toggle",
		  name = "Use global settings",
		  desc = "Use global settings for scale, button size and padding.",
		  order = 1,
	       },
	       resetFromGlobal = {
		  type = "execute",
		  name = "Copy global settings",
		  desc = "Copy parameters from the global Button Bin settings. This will override the bin specific settings.",
		  func = "CopyGlobalSettings",
		  disabled = "UsingGlobalScale",
		  order = 2,
	       },
	       hpadding = {
		  type = "range",
		  name = "Horizontal padding",
		  desc = "Horizontal space between each data block.",
		  width = "full",
		  hidden = "UsingGlobalScale",
		  min = 0, max = 50, step = 0.1,
		  order = 130,
	       }, 
	       vpadding = {
		  type = "range",
		  hidden = "UsingGlobalScale",
		  name = "Vertical padding",
		  desc = "Space between data block rows.",
		  width = "full",
		  min = 0, max = 50, step = 0.1,
		  order = 140,
	       },
	       size = {
		  type = "range",		  
		  name = "Icon size",
		  hidden = "UsingGlobalScale",
		  desc = "Icon size in pixels.",
		  width = "full",
		  min = 5, max = 50, step = 1,
		  order = 160,
	       },
	       scale = {
		  type = "range",
		  hidden = "UsingGlobalScale",
		  name = "Bin scale",
		  desc = "Relative scale of the bin and all contents.",
		  width = "full",
		  min = 0.01, max = 5, step = 0.05,
		  order = 170,
	       },
	       width = {
		  type = "range",
		  name = "Max blocks per row",
		  desc = "Maximum number of blocks to place per row. Note that regardless of this setting, you will never get a bin wider than the absolute width specified.",
		  width = "full",
		  min = 1, max = 200, step = 1, 
		  order = 180,
	       },
	       pixelwidth = {
		  type = "range",
		  name = "Bin width",
		  desc = "Width of the bin. If zero, the width is dynamically determined by the max blocks setting. If non-zero the row will wrap to avoid going beyond this width. Note that at minimum of one block always be placed on each row so for very small values, the bin might be wider than this setting.",
		  width = "full",
		  min = 0, max = 4000, step = 1, 
		  order = 180,
	       },
	    }
	 }
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
			   if LDB:GetDataObjectByName(name) then
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
function mod:GetOption(info)
   return db[info[#info]]
end

function mod:SetOption(info, val)
   local var = info[#info]
   db[var] = val
   for _,bin in pairs(bins) do
      mod:ReloadFrame(bin)
   end
end

local barFrameMT = {__index = CreateFrame("Frame") }
local binMetaTable =  setmetatable({}, barFrameMT)
mod.binMetaTable_mt = {__index = binMetaTable }


function binMetaTable:FixBackdrop()   
   local bdb = db.bins[self.binId]
   local bgFrame = self:GetBackdrop()
   if not bgFrame then
      bgFrame = {
	 insets = {left = 1, right = 1, top = 1, bottom = 1}
      }
   end

   local edge = 0
   if bdb.border ~= "None" then
      edge = bdb.edgeSize
   end
   bgFrame.edgeSize = edge
   edge = edge / 4
   bgFrame.insets.left   = edge
   bgFrame.insets.right  = edge
   bgFrame.insets.top    = edge
   bgFrame.insets.bottom = edge


   bgFrame.edgeFile = media:Fetch("border", bdb.border)
   bgFrame.bgFile = media:Fetch("background", bdb.background)
   self:SetBackdrop(bgFrame)
   self:SetBackdropColor(unpack(bdb.colors.backgroundColor))
   self:SetBackdropBorderColor(unpack(bdb.colors.borderColor))
end

function binMetaTable:ShowOrHide(timer)
   local bdb = db.bins[self.binId]
   if timer and bdb.hideTimeout > 0 then
      if binTimers[self.binId] then
	 mod:CancelTimer(binTimers[self.binId], true)
      end
      binTimers[self.binId] = mod:ScheduleTimer(binMetaTable.ShowOrHide, bdb.hideTimeout, self)
   else
      self:SetAlpha(1.0)
      if unlockButtons or unlockFrames then
	 self:Show()
      elseif bdb.hidden then
	 self:Hide()
      elseif bdb.visibility == "noCombat" then
	 if playerInCombat then self:Hide() else self:Show() end
      elseif bdb.visibility == "inCombat" then
	 if playerInCombat then self:Show() else self:Hide() end
      elseif bdb.visibility == "mouse" then
	 self:Show()
	 if not self._isMouseOver then
	    self:SetAlpha(0.0)
	 end
      else
	 self:Show()
      end
   end
   binTimers[self.binId] = nil
end

function binMetaTable:SetColorOpt(arg, r, g, b, a)
   local bdb = db.bins[self.binId]
   local color = arg[#arg]
   bdb.colors[color][1] = r
   bdb.colors[color][2] = g
   bdb.colors[color][3] = b
   bdb.colors[color][4] = a
   self:FixBackdrop()
end

function binMetaTable:GetColorOpt(arg)
   local bdb = db.bins[self.binId]
   local color = arg[#arg]
   return unpack(bdb.colors[color])
end

function binMetaTable:DisableLabelOption(info)
   local bdb = db.bins[self.binId]
   return not bdb.showLabels
end

function binMetaTable:DisableHideIconOption(info)
   local bdb = db.bins[self.binId]
   return not (bdb.showLabels or not bdb.labelOnMouse)
end

function binMetaTable:DisableBinLabelOption(info)
   local bdb = db.bins[self.binId]
   return not bdb.showLabels or bdb.hideBinIcon
end

function binMetaTable:DisableHideOption(info)
   local bdb = db.bins[self.binId]
   return bdb.visibility == "always"
end

function binMetaTable:UsingGlobalScale(info)
   local bdb = db.bins[self.binId]
   return bdb.useGlobal
end

function binMetaTable:GetOption(info)
   local bdb = db.bins[self.binId]
   local var = info[#info]
   return bdb[var]
end

function binMetaTable:SetOption(info, val)
   local bdb = db.bins[self.binId]
   local var = info[#info]

   bdb[var] = val
   if var == "scale" then
      self:SetScale(val)
      self.mover:SetScale(self:GetScale())
   elseif var == "hidden" or var == "visibility" then
      self:ShowOrHide()
   elseif var == "binLabel" then
      if val then
	 self.button.buttonBinText = "Bin #"..self.binId
      else
	 self.button.buttonBinText = nil
      end
      if not bdb.hideBinIcon then
	 self.button:resizeWindow()
      end
      return
   elseif var == "background" or var == "border" or var == "edgeSize"then
      self:FixBackdrop()
   elseif var == "clampToScreen" then
      self:SetClampedToScreen(val)
      self.mover:SetClampedToScreen(val)
   end   
   mod:ReloadFrame(self) 
end

do
   local params = { 'size', 'scale', 'hpadding', 'vpadding' }
   
   function binMetaTable:CopyGlobalSettings()
      local bdb = db.bins[self.binId]
      for _,param in ipairs(params) do
	 bdb[param] = db[param]
      end
      mod:ReloadFrame(self) 
   end
end



function mod:AddBinOptions(id)
   local bin = {}
   for key,val in pairs(options.binConfig) do
      bin[key] = val
   end
   bin.name = bin.name .. id
   bin.handler = bins[id]
   mod.binopts[id] = mod:OptReg(": "..bin.name, bin, bin.name)
   
end

function mod:SetupOptions()
   mod.main = mod:OptReg("Button Bin", options.global)
   mod:OptReg(": Data Blocks", options.objects, "Data Blocks")
   mod.profile = mod:OptReg(": Profiles", options.profile, "Profiles")
   mod.binopts = {}
   for id, bin in ipairs(db.bins) do
      mod:AddBinOptions(id)
   end
   mod:OptReg("Button Bin CmdLine", options.cmdline, nil,  { "buttonbin", "bin" })
end

function mod:ToggleConfigDialog(frame)
   if frame then 
      bin = frame:GetParent()
      InterfaceOptionsFrame_OpenToCategory(mod.binopts[bin.binId])
   else
      InterfaceOptionsFrame_OpenToCategory(mod.profile)
      InterfaceOptionsFrame_OpenToCategory(mod.main)
   end
end

function mod:ToggleCollapsed(frame)
   local bdb
   bin = frame:GetParent()
   bdb = db.bins[bin.binId]
   bdb.collapsed = not bdb.collapsed
   mod:SortFrames(bin)
end

function mod:GetBinSettings(bin)
   local bdb = db.bins[bin.binId]
   if bdb.useGlobal then
      return bdb, db
   else
      return bdb, bdb
   end
end

function mod:SortFrames(bin)
   --   mod:Print("Sorting frames for bin "..bin.binId)
   local bdb,sdb = mod:GetBinSettings(bin)
   local sizeOptions
   local xoffset = 0
   local width = 0
   local height = 0
   local sorted = bdb.sortedButtons
   local frame
   local addBin = false
   if not bdb.hideBinIcon and bdb.collapsed then
      for id,name in pairs(sorted) do
	 if buttonFrames[name] then
	    buttonFrames[name]:Hide()
	 end
      end 
      sorted = {}
   end   

   if sdb.scale ~= bin:GetScale() then
      bin:SetScale(sdb.scale)
   end
   
   local count = 1
   local previousFrame

   local anchor, xmulti, ymulti, otheranchor
   
   if bdb.flipy then ymulti = 1 anchor = "BOTTOM" otheranchor = "BOTTOM"
   else ymulti = -1 anchor = "TOP" otheranchor = "TOP" end

   if bdb.flipx then
      anchor = anchor .. "RIGHT"
      otheranchor = otheranchor.. "LEFT"
      xmulti = -1 
   else
      otheranchor = otheranchor .. "RIGHT"
      anchor = anchor .. "LEFT"
      xmulti = 1
   end
   local inset = 0
   if bdb.border ~= "None" then
      inset = bdb.edgeSize / 2
   end
   
   local hpadding = (sdb.hpadding or 0)
   local vpadding = (sdb.size + (sdb.vpadding or 0))
   if not bdb.hideBinIcon then 
      previousFrame = bin.button
      previousFrame:resizeWindow()
      previousFrame:ClearAllPoints()
      previousFrame:SetPoint(anchor, bin, anchor, xmulti*inset, ymulti*inset)
      width = previousFrame:GetWidth() + inset
      height = vpadding + inset
      if bdb.width > 1 then
	 xoffset = hpadding + width
	 count = 2
      else
	 previousFrame = nil
      end
   else
      bin.button:ClearAllPoints()
      bin.button:Hide()
      width = inset
      height = inset
   end
   
   for _,name in ipairs(sorted) do
      frame = buttonFrames[name]
      if frame then
	 frame:ClearAllPoints()
	 if (not bdb.hideEmpty or frame._has_texture) then
	    frame:resizeWindow()
	    local fwidth = frame:GetWidth()
	    xoffset = xoffset + hpadding + fwidth
	    if (bdb.width > 1 and bdb.pixelwidth > 0
		and xoffset > bdb.pixelwidth )
	       or count > bdb.width then
	       previousFrame = nil
	       xoffset = hpadding + fwidth
	       count = 1
	    end
	    count = count + 1
	    if xoffset > width then width =  xoffset end		    
	    if previousFrame then
--	       mod:Print(tostring(previousFrame).. ":"..previousFrame.name.." =>"..
--			 tostring(frame) .. ":"..frame.name)
	       frame:SetPoint(anchor, previousFrame, otheranchor, xmulti*hpadding, 0)
	    else
	       height = height + vpadding
	       frame:SetPoint(anchor, bin, anchor, xmulti*inset, ymulti*(height-vpadding))
	    end
	    previousFrame = frame
	 else
	    frame:Hide()
	 end
      end
   end
   if bdb.pixelwidth > width then
      width = bdb.pixelwidth
   end
   bin:SetWidth(width + inset)
   bin:SetHeight(height + inset)
   bin.mover:SetWidth(bin:GetWidth())
   bin.mover:SetHeight(bin:GetHeight())
   bin:ShowOrHide()
end


local unusedFrames = {}
local oldSorted

local function Button_OnDragStart()
   local toRemove
   local bin = this:GetParent()
   local bdb = db.bins[bin.binId]
   local newSorted = {}
   for id, name in pairs(bdb.sortedButtons) do
      if name ~= this.name then
	 newSorted[#newSorted+1] = name
      end
   end
   oldSorted = bdb.sortedButtons
   bdb.sortedButtons = newSorted
   mod:SortFrames(bin)
   this:ClearAllPoints()
   this:StartMoving()
   this:SetAlpha(0.75)
   this:SetFrameLevel(100)
end

local function Button_OnDragStop()
   local bin = this:GetParent()
   local bdb = db.bins[bin.binId]
   local destFrame, destParent
   this:StopMovingOrSizing()
   this:SetFrameLevel(98)
   this:SetAlpha(1.0)
   for id,frame in ipairs(bins) do
      if mod:MouseIsOver(frame.button) then
	 destFrame = frame.button
	 destParent = frame
      end
   end

   if not destFrame then
      for name,frame in pairs(buttonFrames) do
	 if mod:MouseIsOver(frame) and frame ~= this then
	    destFrame = frame
	    destParent = frame:GetParent()
	    break
	 end
      end
   end
   if destFrame and destParent then
      if destParent ~= bin then
--	 mod:Print("Changing parent from "..bin.binId.." to "..destParent.binId)
	 this.db.bin = destParent.binId
	 this:SetParent(destParent)
	 bdb = db.bins[destParent.binId]
      end
      local inserted 
      if destParent.button == destFrame then
	 tinsert(bdb.sortedButtons, 1, this.name)
	 inserted = true
      else
	 local x, midpoint
	 local add = 0
	 if bdb.width > 1 then
	    x = GetCursorPosition()
	    midpoint = (destFrame:GetLeft() + destFrame:GetWidth()/2)*destParent:GetEffectiveScale()
	    if bdb.flipx then
	       if x < midpoint then add = 1 end
	    else
	       if x > midpoint then add = 1 end
	    end
	 else
	    _,x = GetCursorPosition()
	    midpoint = (destFrame:GetBottom() + destFrame:GetHeight()/2)*destParent:GetEffectiveScale()
	    if bdb.flipy then
	       if x > midpoint then add = 1 end
	    else
	       if x < midpoint then add = 1 end
	    end
	 end

--	 mod:Print("x = "..x..", mid = "..midpoint.."...")
	 for id,n in pairs(bdb.sortedButtons) do
	    if destFrame.name == n then
	       id = id + add 
	       if id < 1 then id = 1 end
	       if id > (#bdb.sortedButtons+1) then id = id - 1 end
	       tinsert(bdb.sortedButtons, id, this.name)
	       inserted = true
	       break
	    end
	 end
      end
      if inserted then
	 oldSorted = nil
	 mod:SortFrames(destParent)
	 return
      end
   end
   -- no valid destination, roll state back
   bdb.sortedButtons = oldSorted
   this:SetParent(bin)
   mod:SortFrames(bin)
end

local function Frame_ResizeWindow(self, dontShow)
   local bdb,sdb = mod:GetBinSettings(self:GetParent())
   local iconWidth
   self.icon:ClearAllPoints()
   self.label:ClearAllPoints()
   
   if self.name ~= "ButtonBin" and bdb.hideIcons
      and bdb.showLabels and not bdb.labelOnMouse then
      self.icon:Hide();
      iconWidth = 0
      self.icon:SetWidth(0)
      self.icon:SetHeight(0)
      self.label:SetPoint("RIGHT", self)
   else
      iconWidth = sdb.size
      self.icon:Show();
      if bdb.flipicons then
	 self.icon:SetPoint("RIGHT", self)
	 self.label:SetPoint("RIGHT", self.icon, "LEFT", -2, 0)
      else
	 self.icon:SetPoint("LEFT", self)
	 self.label:SetPoint("LEFT", self.icon, "RIGHT", 2, 0)
      end
      self.icon:SetWidth(sdb.size)
      self.icon:SetHeight(sdb.size)
   end

   if not dontShow then self:Show() end

   local width
   
   if bdb.showLabels and (not bdb.labelOnMouse or self._isMouseOver) then
      if bdb.font and bdb.fontsize then
	 self.label:SetFont(media:Fetch("font", bdb.font), bdb.fontsize)
      end
      if bdb.shortLabels then
	 self.label:SetText(self.shortButtonText or self.buttonBinText)
      else
	 self.label:SetText(self.buttonBinText or self.shortButtonText)
      end
      width = self.label:GetStringWidth()
      if width > 0 then
	 self.label:SetWidth(width)
	 self.label:Show()
	 if iconWidth > 0 then
	    width = width + iconWidth + 6
	 else
	    width = width + 3
	 end
      else
	 width = iconWidth
      end
   else
      self.label:Hide()
      width = iconWidth
   end
   if bdb.labelOnMouse then
      local oldWidth = self:GetWidth(self)
      if oldWidth ~= width then
	 local bin = self:GetParent()
	 bin:SetWidth(bin:GetWidth() - oldWidth + width)
      end
   end
   self:SetWidth(width)
   self:SetHeight(sdb.size)
end

function mod:GetFrame()
   local frame
   if #unusedFrames > 0 then
      frame = unusedFrames[#unusedFrames]
      unusedFrames[#unusedFrames] = nil
   else
      frame = CreateFrame("Button", nil)
      frame:EnableMouse(true)
      frame:RegisterForClicks("AnyUp")
      frame.icon = frame:CreateTexture()
      frame.label = frame:CreateFontString(nil, nil, "GameFontNormal")
      frame.resizeWindow = Frame_ResizeWindow
      frame:SetScript("OnDragStart", Button_OnDragStart)
      frame:SetScript("OnDragStop", Button_OnDragStop)
      
   end
   return frame
end

function mod:ReleaseFrame(frame)
   local bin = frame:GetParent()
   buttonFrames[frame.name] = nil
   unusedFrames[#unusedFrames+1] = frame
   frame:Hide()
   frame:SetParent(nil)
   frame.buttonBinText = nil
   frame.db = nil
   frame.name = nil
   frame.obj = nil
   frame._has_texture = nil
   frame:SetScript("OnEnter", nil)
   frame:SetScript("OnLeave", nil)
   frame:SetScript("OnClick", nil)
   if bin then self:SortFrames(bin) end
end
   
function mod:MouseIsOver(frame)
   local x, y = GetCursorPosition();
   x = x / frame:GetEffectiveScale();
   y = y / frame:GetEffectiveScale();
   
   local left = frame:GetLeft();
   local right = frame:GetRight();
   local top = frame:GetTop();
   local bottom = frame:GetBottom();
   if not left then return nil end
   if ( (x > left and x < right) and (y > bottom and y < top) ) then
      return true
   end
end
 
