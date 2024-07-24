
--[[
**********************************************************************
ButtonBin - A displayer for LibDataBroker compatible addons
**********************************************************************
Some code from Fortress was used in this addon with permission from the
author Borlox.
**********************************************************************
]]
ButtonBin = LibStub("AceAddon-3.0"):NewAddon("ButtonBin", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0",  "LibMagicUtil-1.0")

local LibStub = LibStub
local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local R = LibStub("AceConfigRegistry-3.0")

local BB_DEBUG = false

local LJ = LibStub("LibJostle-3.0")

-- Silently fail embedding if it doesn't exist
local Logger = LibStub("LibLogger-1.0", true)
local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")
local media = LibStub("LibSharedMedia-3.0")
local mod = ButtonBin

local CreateFrame = CreateFrame
local GetAddOnInfo = GetAddOnInfo
local GetCursorPosition = GetCursorPosition
local GetScreenHeight = GetScreenHeight
local GetScreenWidth = GetScreenWidth
local IsAltKeyDown = IsAltKeyDown
local UIParent = UIParent
local fmt = string.format
local ipairs = ipairs
local lower = string.lower
local pairs = pairs
local select = select
local setmetatable = setmetatable
local tconcat = table.concat
local tinsert = table.insert
local tostring = tostring
local tremove = table.remove
local tsort   = table.sort
local type = type
local unpack = unpack

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

if Logger then
   Logger:Embed(mod)
else
   -- Enable info messages
   mod.info = function(self, ...) mod:Print(fmt(...)) end
   mod.error = mod.info
   mod.warn = mod.info
   -- But disable debugging
   if BB_DEBUG then
      mod.debug = mod.info
   else
      mod.debug = function(self, ...) end
   end
   mod.trace = mod.debug
   mod.spam = mod.debug
end

local defaults = {
   profile = {
      enabledDataObjects = {
         ['*'] = {
            enabled = true,
            tooltipScale = 1.0,
         },
      },
      size = 24,
      scale = 1.0,
      tooltipScale = 1.0,
      width  = 20,
      hpadding = 0.5,
      vpadding = 0.5,
      bins = {
	 ['*'] =  {
	    colors = {
	       backgroundColor = { 0, 0, 0, 0.5},
	       borderColor = { 0.88, 0.88, 0.88, 0.8 },
	       labelColor  = { 1, 1, 1 },
	       textColor   = { 1, 1, 1 },
	       unitColor   = { 1, 1, 1 },
	       valueColor   = { 0.9, 0.9, 0 },
	    },
	    background = "Solid",
	    binLabel = true,
	    border = "None",
	    clampToScreen = true,
	    collapsed = false,
	    edgeSize = 10,
	    flipx = false,
	    flipy = false,
	    font = "Friz Quadrata TT",
	    moveFrames = false,
	    fontsize = 12,
	    hidden = true,
	    hideAllText = false,
	    hideEmpty = true,
	    hideLabel = true,
	    hideTimeout = 2,
	    hpadding = 0.5,
	    labelOnMouse = false,
	    pixelwidth = 0,
	    scale = 1.0,
	    size = 24,
	    sortedButtons = {},
	    tooltipScale = 1.0,
	    useGlobal = true,
	    visibility = "always",
	    vpadding = 0.5,
	    width = 10,
	    binTexture = "Interface\\AddOns\\ButtonBin\\bin.tga",
	    center = false, 
	 }
      }
   }
}

local function ColorToHex(c)
   return ("%02x%02x%02x"):format(c[1]*255, c[2]*255, c[3]*255)
end

local GameTooltip = GameTooltip
local function GT_OnLeave(self)
   self:SetScript("OnLeave", self.oldOnLeave)
   self.oldOnLeave = nil
   if self.oldScale then
      self:SetScale(self.oldScale)
      self.oldScale = nil
   end
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

local function SetTooltipScale(tooltip, frame)
   local bdb,sdb = mod:GetBinSettings(frame:GetParent())

   local tooltipScale =
      mod:DataBlockConfig(frame.name, "tooltipScale",
                          sdb.tooltipScale)
   tooltip.oldScale = tooltip:GetScale()
   tooltip:SetScale(tooltipScale or tooltip.oldScale)
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
   SetTooltipScale(frame, anchorFrame)
end

local tablet
local function LDB_OnEnter(self)
   local obj = self.obj
   local bin = self:GetParent()
   local bdb = mod:GetBinSettings(bin)
   local hideTooltip = mod:DataBlockConfig(self.name, "hideTooltip", bdb.hideTooltips)
   if not hideTooltip then
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
   end
   self._isMouseOver = true
   self:resizeWindow()
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
   if mod:MouseIsOver(GameTooltip) and (obj.tooltiptext or obj.OnTooltipShow)
   then
      return
   end

   if self.hideTooltipOnLeave or obj.tooltiptext or obj.OnTooltipShow then
      GT_OnLeave(GameTooltip)
      self.hideTooltipOnLeave = nil
   end
   if obj.OnLeave then
      obj.OnLeave(self)
   end
end

local function LDB_OnReceiveDrag(self, button)
   if self._ondrag then
      self._ondrag(self, button)
   end
end

local function LDB_OnClick(self, button)
   if self._onclick then
      LDB_OnLeave(self)
      self._onclick(self, button)
   end
end

local function BB_OnClick(self, button)
   LDB_OnLeave(self)
   if button == "LeftButton" then
      if IsAltKeyDown() then
         mod:ToggleButtonLock()
      else
         mod:ToggleCollapsed(self)
      end
   elseif button == "MiddleButton" then
      mod:ToggleLocked()
   elseif button == "RightButton" then
      mod:ToggleConfigDialog(self)
   end
end

function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("ButtonBinDB", defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
   db = self.db.profile

   if self.SetLogLevel and BB_DEBUG then
      mod:SetLogLevel(self.logLevels.TRACE)
   end

   if BB_DEBUG then
      -- Just for easy access while debugging
      bbdb = db
      bns = bins
      bf = buttonFrames
   end
end

function mod:AddNewBin()
   db.bins[#db.bins+1].hidden = false
   mod:LoadPosition(mod:CreateBinFrame(#db.bins, db.bins[#db.bins]))
   self:SetupBinOptions(true)
end

do
   local tooltip = "Button Bin %d\n"..
      "|cffffff00Left click|r to collapse/uncollapse all other icons.\n"..
      "|cffffff00Alt-Left click|r to toggle the button lock.\n"..
      "|cffffff00Middle click|r to toggle the Button Bin window lock.\n"..
      "|cffffff00Right click|r to open the Button Bin configuration.\n"
   function mod:CreateBinFrame(id, bdb)
      local f = mod:GetBinFrame()
      local sdb
      if bdb.useGlobal then sdb = db else sdb = bdb end
      bins[id] = f
      f.binId = id
      f:SetClampedToScreen(bdb.clampToScreen)
      f.mover:SetClampedToScreen(bdb.clampToScreen)
      f:SetScale(sdb.scale)
      f:FixBackdrop()
      f.button.db = { tooltiptext = tooltip:format(id) }
      f.button.obj = f.button.db
      f.button.name = "ButtonBin"
      mod:SetBinIconAndLabel(f, bdb)
      --      f._isMouseOver = true
      mod:SortFrames(f)
      return f
   end
end

function mod:SetBinIconAndLabel(frame, bdb)
   if bdb.binLabel then
      frame.button.buttonBinText = bdb.binName or "Bin #"..frame.binId
   else
      frame.button.buttonBinText = nil
   end
   frame.button.icon:SetTexture(bdb.binTexture)
end

function mod:LibDataBroker_DataObjectCreated(event, name, obj)
   ldbObjects[name] = obj
   if db.enabledDataObjects[name].enabled then
      mod:EnableDataObject(name, obj)
      local binid = buttonFrames[name].db.bin
      local bdb = db.bins[binid]
      for _,bname in ipairs(bdb.sortedButtons) do
         if name == bname then
            return
         end
      end
      bdb.sortedButtons[#bdb.sortedButtons+1] = name
      mod:SortFrames(bins[binid])
   end
end

local function TextUpdater(frame, value, name, obj, delay)
   local bdb,sdb = mod:GetBinSettings(frame:GetParent())

   if mod:DataBlockConfig(name, "hideLabel", bdb.hideAllText) and
      mod:DataBlockConfig(name, "hideText",  bdb.hideAllText) and
      mod:DataBlockConfig(name, "hideValue", bdb.hideAllText) then
      frame.buttonBinText = nil
   else
      local showLabel = not mod:DataBlockConfig(name, "hideLabel", bdb)
      local showText  = not mod:DataBlockConfig(name, "hideText",  bdb)
      local showValue = not mod:DataBlockConfig(name, "hideValue", bdb)

      local labelColor = ColorToHex(bdb.colors.labelColor)
      local textColor = ColorToHex(bdb.colors.textColor)
      local unitColor = ColorToHex(bdb.colors.unitColor)
      local valueColor = ColorToHex(bdb.colors.valueColor)

      local text

      if showLabel and obj.label then  -- try to show the label
         if showValue and obj.value then
            text = fmt("|cff%s%s:|r |cff%s%s|r|cff%s%s|r", labelColor, obj.label,
                       valueColor, obj.value, unitColor, obj.suffix or "")
	    
         elseif showText and obj.text and obj.text ~= obj.label then
	    text = fmt("|cff%s%s:|r |cff%s%s|r",
		       labelColor, obj.label, textColor, obj.text)

         else
            text = fmt("|cff%s%s|r", labelColor, obj.label)
         end
      elseif showLabel and type == "launcher" then
         -- show the addonname for launchers if no label is set
         local addonName, addonTitle = GetAddOnInfo(obj.tocname or name)
         text = fmt("|cff%s%s|r", labelColor, addonTitle or addonName or name)
      elseif showText and obj.text then
         if showValue and obj.value then
            text = fmt("|cff%s%s|cff%s%s|r", valueColor,
                       obj.value, unitColor, obj.suffix or "")
         else
            text = fmt("|cff%s%s|r", textColor, obj.text)
         end
      end
      frame.buttonBinText = text
   end
   if not delay then
      local w = frame:GetWidth()
      frame:resizeWindow(true)
      w = w - frame:GetWidth()
      if w > 0 or w < -10 then
         mod:SortFrames(frame:GetParent())
      end
   end
end
local function SetTexCoord(frame, value, name, object)
   object.texcoord = value
   if object.texcoord then
      frame.icon:SetTexCoord(unpack(object.texcoord))
   end
end

local function SetIconColor(frame, object)
   frame.icon:SetVertexColor(object.iconR or 1,
                             object.iconG or 1,
                             object.iconB or 1)
end



local updaters = {
   text   = TextUpdater,   value  = TextUpdater,
   suffix = TextUpdater,   label  = TextUpdater,
   textcoord = SetTexCoord,
   iconCoords = SetTexCoord,
   iconR = function(frame, value, name, object)
              object.iconR = value
              SetIconColor(frame, object)
           end,
   iconG = function(frame, value, name, object)
              object.iconG = value
              SetIconColor(frame, object)
           end,
   iconB = function(frame, value, name, object)
              object.iconB = value
              SetIconColor(frame, object)
           end,
   icon = function(frame, value, name, object, delay)
             frame.icon:SetTexture(value)
             local has_texture = not not value
             if has_texture ~= frame._has_texture then
                frame._has_texture = has_texture
                if not delay then
                   if has_texture then
                      mod:SortFrames(frame:GetParent()) -- we grew
                   else
                      frame:resizeWindow(true)
                   end
                end
             end
          end,
   OnClick = function(frame, value)
                frame._onclick = value
                if value then
                   frame:SetScript("OnClick", LDB_OnClick)
                else
                   frame:SetScript("OnClick", nil)
                end
             end,
   OnReceiveDrag = function(frame, value)
                frame._ondrag = value
                if value then
                   frame:SetScript("OnReceiveDrag", LDB_OnReceiveDrag)
                else
                   frame:SetScript("OnReceiveDrag", nil)
                end
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
   if f and obj then
      if updaters[key] then
         updaters[key](f, value, name, obj)
      end
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

   mod:UpdateBlock(name, frame, true)

   LDB.RegisterCallback(self, "LibDataBroker_AttributeChanged_"..name, "AttributeChanged")
   mod:SortFrames(frame:GetParent())
   mod:SetupDataBlockOptions(true)
end

function mod:DisableDataObject(name, obj)
   db.enabledDataObjects[name].enabled = false
   LDB.UnregisterCallback(self, "LibDataBroker_AttributeChanged_"..name)
   if buttonFrames[name] then
      self:ReleaseFrame(buttonFrames[name])
   end
   mod:SetupDataBlockOptions(true)
end

function mod:OnEnable()
   -- Make sure we have the default set of bins
   if not db.bins or #db.bins == 0 then
      mod:LoadDefaultBins()
   else
      for id,bdb in pairs(db.bins) do
	 mod:CreateBinFrame(id, bdb)
      end
   end
   mod:SetupOptions()

   self:ApplyProfile()
   if self.SetLogLevel then
      self:SetLogLevel(self.logLevels.TRACE)
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
   local function Low_RecalculateSizes()
      for _,bin in ipairs(bins) do
         mod:SortFrames(bin)
      end
   end
   function mod:RecalculateSizes()
      if timer then mod:CancelTimer(timer, true) timer = nil end
      timer = mod:ScheduleTimer(Low_RecalculateSizes, 1)
   end
end

-- Migrate settings

do
   local migrated = {
      shortLabels = "hideLabel"
   }
   local migratedobj = {
   }
   function mod:ConvertBinOptions(bin)
      if bin.showLabels ~= nil then
         bin.hideAllText = not bin.showLabels
         bin.showLabels = nil
      end
      for from,to in pairs(migrated) do
         if bin[from] ~= nil then
            bin[to] = bin[from]
            bin[from] = nil
         end
      end
   end
   function mod:ConvertBlockOptions(obj)
      for from,to in pairs(migratedobj) do
         if obj[from] ~= nil then
            obj[to] = obj[from]
            obj[from] = nil
         end
      end
   end
end

function mod:ApplyProfile()
   -- clean stuff up
   for id,bin in ipairs(db.bins) do
      local seen = {}
      local newButtons = {}
      for bid, name in pairs(bin.sortedButtons) do
         if not seen[name] then
            seen[name] = true
            if db.enabledDataObjects[name].bin == id then
               newButtons[#newButtons+1] = name
            end
         end
      end
      mod:ConvertBinOptions(bin)
      bin.sortedButtons = newButtons
   end

   for id, obj in pairs(db.enabledDataObjects) do
      mod:ConvertBlockOptions(obj)
   end
   for _,frame in pairs(buttonFrames) do
      mod:ReleaseFrame(frame)
   end
   for name, obj in LDB:DataObjectIterator() do
      self:LibDataBroker_DataObjectCreated(nil, name, obj)
   end
   for id,bin in ipairs(bins) do
      bin:ClearAllPoints()
      mod:LoadPosition(bin)
      if bin.mover:IsVisible() then
         mod:ToggleLocked()
      else
         self:SortFrames(bin) -- will handle any size changes etc
      end
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
      if bdb.moveFrames and bin:IsVisible() and bin:GetAlpha() > 0 then
         local height = UIParent:GetHeight()
         local diff = height + posy/s
         if diff < height/15 then
            LJ:RegisterBottom(bin)
         elseif (height - diff) < height/15 then
            LJ:RegisterTop(bin)
         else
            LJ:Unregister(bin)
         end
      else
         LJ:Unregister(bin)
      end
      LJ:Refresh()
   else
      bin:SetPoint(anchor, UIParent, "CENTER")
   end
end

function mod:OnProfileChanged(event, newdb, src)
   db = self.db.profile
   for id,frame in ipairs(bins) do
      mod:ReleaseBinFrame(frame)
   end
   if event == "OnProfileReset" or #db.bins == 0 then
      for id,frame in ipairs(bins) do
         db.bins[id] = nil
      end
      db.bins[1].hidden = false
   end
   for id,bdb in pairs(db.bins) do
      mod:CreateBinFrame(id, bdb)
   end
   self:ApplyProfile()
   self:SetupBinOptions(true)
end


function mod:LoadDefaultBins()
   local defaults = {
      posy = 0.5,
      posx = 0,
      hidden = false,
      binLabel = false,
      hideBinIcon = true,
      edgeSize = 0,
      moveFrames = true,
      anchor = "TOPLEFT",
      pixelwidth = UIParent:GetWidth(),
      width = 100,
      clampToScreen = false
   }

   for id in ipairs(db.bins) do
      if bins[id] then
	 mod:ReleaseBinFrame(bins[id])
      end
      db.bins[id] = nil
   end
   for id = 1, 3 do
      local bdb = db.bins[id]
      for key, val in pairs(defaults) do
         bdb[key] = val
      end
   end

   -- left
   db.bins[1].binName = "Left"
   db.bins[1].hideBinIcon = false
   -- right
   db.bins[2].binName = "Right"
   db.bins[2].flipx = true
   db.bins[2].anchor = "TOPRIGHT"
   -- center
   db.bins[3].binName = "Center"
   db.bins[3].center = true

   for id, data in pairs(db.enabledDataObjects) do
      data.bin = 1
   end

   for id,bdb in pairs(db.bins) do
      mod:CreateBinFrame(id, bdb)
   end      
   self:ApplyProfile()
   self:SetupBinOptions(true)
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
      end
      bin:ShowOrHide()
      mod:SortFrames(bin)
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
         if name ~= "ButtonBin" or not db.hideBinTooltip then
            frame:SetScript("OnEnter", frame._onenter or LDB_OnEnter)
            frame:SetScript("OnLeave", frame._onleave or LDB_OnLeave)
         end
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
   if not db.hideBinTooltip then
      bin.button:SetScript("OnEnter", LDB_OnEnter)
      bin.button:SetScript("OnLeave", LDB_OnLeave)
   else
      bin.button:SetScript("OnEnter", nil)
      bin.button:SetScript("OnLeave", nil)
   end
   mod:UpdateAllBlocks(bin)
   mod:SavePosition(bin)
   mod:LoadPosition(bin)
   mod:SortFrames(bin)
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
         tooltipScale = {
            type = "range",
            name = "Tooltip Scale",
            desc = "The scale of the tooltip for this datablock",
            width="full",
            min = 0.1, max = 5, step = 0.05,
         },
         toggleButton = {
            type = "toggle",
            name = "Lock data broker button positions",
            desc = "When unlocked, you can move buttons into a new position on the bar.",
            width = "full",
            get = function() return not unlockButtons end,
            set = function() mod:ToggleButtonLock() end
         },
         hideBinTooltip = {
            type = "toggle",
            width = "full",
            name = "Hide Button Bin tooltips",
            desc = "Decide whether or not to show the helper tooltip when mousing over the Button Bin icons.",
         },
         globalScale = {
            type = "group",
            name = "Scale and size",
            args = {
               hpadding = {
                  type = "range",
                  name = "Horizontal button padding",
                  width = "full",
                  min = 0, max = 50, step = 0.1,
                  order = 130,
               },
               vpadding = {
                  type = "range",
                  name = "Vertical button padding",
                  width = "full",
                  min = 0, max = 50, step = 0.1,
                  order = 140,
               },
               size = {
                  type = "range",
                  name = "Button size",
                  width = "full",
                  min = 5, max = 50, step = 1,
                  order = 160,
               },
               scale = {
                  type = "range",
                  name = "Bin scale",
                  width = "full",
                  min = 0.01, max = 5, step = 0.01,
                  order = 170,
               },
            }

         }
      }
   },

   dataBlock = {
      type = "group",
      handler = mod,
      set = "SetDataBlockOption",
      get = "GetDataBlockOption",
      args = {
         help = {
            type = "description",
            name = "You can override the bar level configuration in this section. Note that when enabled, these settings will always override the settings of the individual bins.",
            order = 0,
            hidden = function() return bins[1] == nil end,
         },
         enabled = {
            type="toggle",
            name = "Enabled",
            desc = "Toggle to enable display of this datablock.",
            order = 1,
            disabled = function() return bins[1] == nil end,
         },
         blockOverride = {
            type = "toggle",
            name = "Override bin config",
            desc = "If override is enabled, the settings here are used over the bin level configuration. Otherwise the block will be displayed as per the bin settings.",
            order = 2,
            hidden = "HideOverrideConfig",
         },
	 hideTooltip = {
	    type = "toggle",
	    name = "Hide tooltip",
	    desc = "Don't show the mouseover tooltip for this block.",
	    order = 10,
	 },	 
         hideIcon = {
            type = "toggle",
            name = "Hide icon",
            desc = "Hide the icon for this datablock.",
            hidden = "HideDataBlockOptions"
         },
         hideLabel = {
            type = "toggle",
            name = "Hide label",
            desc = "Hide the label for this datablock",
            hidden = "HideDataBlockOptions"
         },
         hideText = {
            type = "toggle",
            name = "Hide text",
            desc = "Hide the text for this data block.",
            hidden = "HideDataBlockOptions",
         },
         hideValue = {
            type = "toggle",
            name = "Hide values",
            desc = "Hide the value for this data block.",
            hidden = "HideDataBlockOptions",
         },
         tooltipScale = {
            type = "range",
            name = "Tooltip Scale",
            desc = "The scale of the tooltip for this datablock",
            width="full",
            min = 0.1, max = 5, step = 0.05,
            hidden = "HideDataBlockOptions"
         },
         bin = {
            type = "select",
            name = "Bin",
            desc = "The bin this datablock resides in.",
            width = "full",
            values = function() local val = {}
                        for id,bdb in pairs(db.bins) do
                           val[id]= bdb.binName
                        end
                        return val
                     end,
         }
      }
   },

   bins = {
      type = "group",
      name = "Bins",
      handler = mod,
      args = {
         newbin = {
            type = "execute",
            name = "Add a new bin",
            desc = "Create a new display bin.",
            func = "AddNewBin",
         },
	 loaddefaults = {
	    type = "execute",
	    name = "Reset Bin Layout",
	    desc = "This will remove your existing set of bins and load the default three bin left/center/right setup. All datablocks will be reset to be shown in the first bin as well.",
	    func = "LoadDefaultBins",
	 }
      }
   },
   binConfig = {
      type = "group",
      name = "Bin #",
      order = 4,
--      childGroups = "tab",
      get = "GetOption",
      set = "SetOption",
      args = {
         help = {
            type = "description",
            name = "Select the sub-sections to configure this bin. You can also delete the bin permanently by clicking the button below.",
            order = 1,
         },
         separator = {
            type = "header",
            name = "",
            order = 2,
         },
         delete = {
            type = "execute",
            name = "Delete bin",
            desc = "Delete this bin. All objects displayed in this bin will be hidden and all settings purged.",
            func = "DeleteBin",
            confirm = true,
            confirmText = "Are you sure that you want to delete this bin? This action can't be reverted.",
            order = 10,
         },
         binIcon = {
            type = "group",
            name = "Bin Icon and Name",
            args = {
               binName = {
                  type = "input",
                  name = "Bin Name",
                  desc = "The name of the bin, used in the configuration UI and the bin icon if shown.",
                  order = 3,
                  disabled = "DisableBinIconOptions",
               },
               binTexture =  {
                  type = "input",
                  name = "Bin Icon Texture",
                  desc = "The path to the texture used as the bin icon.",
                  order = 4,
                  disabled = "DisableBinIconOptions",
               },
               hideBinIcon = {
                  width = "full",
                  type = "toggle",
                  name = "Hide button bin icon",
                  desc = "Hide or show the button bin icon for this bin.",
                  order = 1
               },
               binLabel = {
                  type = "toggle",
                  width = "full",
                  name = "Show label for the ButtonBin icon ",
                  order = 50,
                  disabled = "DisableBinLabelOption",
               },
            },
         },
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
               hideTooltips = {
                  type = "toggle",
                  name = "Hide tooltips",
                  desc = "Don't show the mouseover tooltips for any blocks in this bin, unless overriden by the block level configuration.",
                  width = "full",
                  order = 10,
               },
               moveFrames = {
                  type = "toggle",
                  name = "Move Blizzard frames",
                  desc = "When enabled, default Blizzard frames such as the minimap, buff frame etc will be moved to make room for this bin. This is useful if you want your bin to sit at the top or bottom of the frame without overlapping Blizzard frames..",
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
               hideIcons = {
                  width = "full",
                  type = "toggle",
                  name = "Hide all icons",
                  desc = "Hide the icons of all datablocks in this bin. Note that datablocks without a label will be invisible if this is enabled.",
                  order = 31,
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
                     noCombat = "Hide during combat",
                     mouseNoCombat = "Mouseover, not combat",
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
         colors = {
            type = "group",
            name = "Text Colors",
            set = "SetColorOpt",
            get = "GetColorOpt",
            args = {
               labelColor = {
                  type = "color",
                  name = "Label color",
                  hasAlpha = false,
               },
               textColor = {
                  type = "color",
                  name = "Text color",
                  hasAlpha = false,
               },
               unitColor = {
                  type = "color",
                  name = "Unit color",
                  hasAlpha = false,
               },
               valueColor = {
                  type = "color",
                  name = "Value color",
                  hasAlpha = false,
               },
            }
         },
         labels = {
            type = "group",
            name = "Text Labels",
            args = {
               hideAllText = {
                  width = "full",
                  type = "toggle",
                  name = "Hide all text",
                  desc = "Hide all text, showing only the icons.",
                  order = 40,
               },
               labelOnMouse = {
                  width = "full",
                  type = "toggle",
                  name = "Show text only on mouse over",
                  desc = "Don't show any datablock text unless the cursor is hovering over it.",
                  order = 80,
                  disabled = "DisableLabelOption",
               },
               hideLabel = {
                  width = "full",
                  type = "toggle",
                  name = "Hide labels",
                  desc = "Hide the data block labels.",
                  order = 70,
                  disabled = "DisableLabelOption",
               },
               hideText = {
                  width = "full",
                  type = "toggle",
                  name = "Hide text",
                  desc = "Hide the data block text.",
                  order = 70,
                  disabled = "DisableLabelOption",
               },
               hideValue = {
                  width = "full",
                  type = "toggle",
                  name = "Hide values",
                  desc = "Hide the data block values.",
                  order = 70,
                  disabled = "DisableLabelOption",
               },
            },
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
               center = {
                  type = "toggle",
                  name = "Center alignment",
                  desc = "All rows will be center aligned in the bin.",
                  order = 120,
               }
            }
         },
         spacing = {
            type = "group",
            name = "Sizing",
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
                  desc = "Horizontal space between each datablock.",
                  width = "full",
                  hidden = "UsingGlobalScale",
                  min = 0, max = 50, step = 0.1,
                  order = 130,
               },
               vpadding = {
                  type = "range",
                  hidden = "UsingGlobalScale",
                  name = "Vertical padding",
                  desc = "Space between datablock rows.",
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
                  min = 0.01, max = 5, step = 0.01,
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
               tooltipScale = {
                  type = "range",
                  name = "Tooltip Scale",
                  desc = "The scale of the tooltips for the datablocks in this bin.",
                  width="full",
                  min = 0.1, max = 5, step = 0.05,
                  disabled = "UsingGlobalScale",
                  order = 190,
               },
            }
         }
      }
   },
   objconfig = {
      name = "Data Object Configuration",
      type = "group",
      args = {
         help = {
            type = "description",
            name = "There are currently no bins configured. Please add a bin before configuring the data blocks.\n\n",
            order = 0,
            hidden = function() return bins[1] end,
         },
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

function mod:SetDataBlockOption(info, val)
   local var  = info[#info]
   local name = options.objconfig.args[info[#info - 1]].desc

   if var == "bin" and val ~= db.enabledDataObjects[name][var] then
      -- Moving this to another bin
      local oldBin = db.enabledDataObjects[name][var]
      buttonFrames[name]:SetParent(bins[val])
      local oldBinButtons = {}
      for _,bname in ipairs(db.bins[oldBin].sortedButtons) do
         if bname ~= name then
            oldBinButtons[#oldBinButtons+1] = bname
         end
      end
      db.bins[oldBin].sortedButtons = oldBinButtons
      db.bins[val].sortedButtons[#db.bins[val].sortedButtons+1] = name
      mod:SortFrames(bins[oldBin])
      mod:SortFrames(bins[val])
   end

   db.enabledDataObjects[name][var] = val

   if buttonFrames[name] then
      mod:UpdateBlock(name)
      buttonFrames[name]:resizeWindow(true)
   end
   if var == "enabled" then
      if val then
         mod:LibDataBroker_DataObjectCreated("config", name,
                                             LDB:GetDataObjectByName(name))
      else
         mod:DisableDataObject(name)
      end
   end
   mod:SetupDataBlockOptions(true)
end

function mod:GetDataBlockOption(info)
   local var  = info[#info]
   local name = options.objconfig.args[info[#info - 1]].desc
   return db.enabledDataObjects[name][var]
end

function mod:HideOverrideConfig(info)
   local name = options.objconfig.args[info[#info - 1]].desc
   return not db.enabledDataObjects[name].enabled
end

function mod:HideDataBlockOptions(info)
   local name = options.objconfig.args[info[#info - 1]].desc
   return not db.enabledDataObjects[name].blockOverride or
      mod:HideOverrideConfig(info)
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
mod.binMetaTable = binMetaTable
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

local function ShowOrHideOnMouseover(self, bdb, force)
   self:Show()
   if not self._isMouseOver and not force then
      self:SetAlpha(0.0)
      for _,name in ipairs(bdb.sortedButtons) do
         if buttonFrames[name] then
            buttonFrames[name]:Hide()
         end
      end
   else
      if not bdb.hideBinIcon then self.button:resizeWindow() end
      if not bdb.collapsed or force then
         for _,name in ipairs(bdb.sortedButtons) do
            if buttonFrames[name] then
               buttonFrames[name]:resizeWindow()
            end
         end
      end
   end
end

function binMetaTable:ShowOrHide(timer, onenter)
   local bdb = db.bins[self.binId]
   local forceShow = false
   if timer and bdb.hideTimeout > 0 and bdb.visibility ~= "always" then
      if binTimers[self.binId] then
         mod:CancelTimer(binTimers[self.binId], true)
      end
      binTimers[self.binId] = mod:ScheduleTimer(binMetaTable.ShowOrHide, bdb.hideTimeout, self)
   else
      self:SetAlpha(1.0)
      if unlockButtons or unlockFrames then
         self:Show()
         forceShow = true
      elseif bdb.hidden then
         self:Hide()
      elseif bdb.visibility == "noCombat" then
         if playerInCombat then
            self:Hide()
         else
            self:Show()
            forceShow = true
         end
      elseif bdb.visibility == "inCombat" then
         if playerInCombat then
            forceShow = true
            self:Show()
         else
            self:Hide()
         end
      elseif bdb.visibility == "mouse" then
         ShowOrHideOnMouseover(self, bdb)
      elseif bdb.visibility == "mouseNoCombat" then
         if playerInCombat then
            self:Hide()
         else
            ShowOrHideOnMouseover(self, bdb)
         end
      else
         self:Show()
         forceShow = true
      end
   end
   if forceShow and not bdb.collapsed then
      ShowOrHideOnMouseover(self, bdb, true)
   end
   if onenter and self:IsVisible() and self:GetAlpha() > 0 then
      mod:SortFrames(self)
   end
--   mod:LoadPosition(self) -- this will make sure hiding / showing works as expected
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
   mod:UpdateAllBlocks(self)
end

function binMetaTable:GetColorOpt(arg)
   local bdb = db.bins[self.binId]
   local color = arg[#arg]
   return unpack(bdb.colors[color])
end

function binMetaTable:DisableBinIconOptions(info)
   return db.bins[self.binId].hideBinIcon
end

function binMetaTable:DisableLabelOption(info)
   local bdb = db.bins[self.binId]
   return bdb.hideAllText
end

function binMetaTable:DisableHideIconOption(info)
   local bdb = db.bins[self.binId]
   return bdb.hideAllText or bdb.labelOnMouse
end

function binMetaTable:DisableBinLabelOption(info)
   local bdb = db.bins[self.binId]
   return bdb.hideAllText or bdb.hideBinIcon
end

function binMetaTable:DisableHideOption(info)
   local bdb = db.bins[self.binId]
   return bdb.visibility == "always"
end

function binMetaTable:UsingGlobalScale(info)
   local bdb = db.bins[self.binId]
   return bdb.useGlobal
end

function binMetaTable:DeleteBin(info)
   local bdb = db.bins[self.binId]
   self.disabled = true
   -- Disabled all datablocks in this bin
   for id, button in pairs(bdb.sortedButtons) do
      mod:DisableDataObject(button)
      db.enabledDataObjects[button].bin = 1 -- default to be added to bin 1
   end

   -- This makes sure to "move" objects to a lower bin
   for id, data in pairs(db.enabledDataObjects) do
      if data.bin and data.bin > self.binId then
         data.bin = data.bin - 1
      end
   end
   -- We're shifting bins down one
   for id = self.binId+1,#db.bins do
      local bdb = db.bins[id]
      local sdb
      if bdb.useGlobal then sdb = db else sdb = bdb end
      local destBinID = id - 1
      db.bins[destBinID] = db.bins[id]
      local f = bins[id]
      bins[destBinID] = f
      if f then
         f.binId = destBinID
         if bdb.binLabel then
            f.button.buttonBinText = "Bin #"..destBinID
         end
      end
   end
   mod:ReleaseBinFrame(self, true)
   -- remove the last one
   db.bins[#db.bins] = nil
   bins[#bins]= nil
   mod:SetupBinOptions(true)
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
   elseif var == "binLabel"  or var == "binName" or var == "binTexture" then
      mod:SetBinIconAndLabel(self, bdb)
      if not bdb.hideBinIcon then
         self.button:resizeWindow()
      end
      if var == "binName" then
         mod:SetupBinOptions(true) -- reload list of bins
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

function mod:SetupBinOptions(reload)
   for id, data in pairs(options.bins.args) do
      if data.type == "group" then
         options.bins.args[id] = nil
      end
   end
   for id, bdb in ipairs(db.bins) do
      local bin = {}
      for key,val in pairs(options.binConfig) do
         bin[key] = val
      end
      if bdb.binName then
         bin.name = bdb.binName
      else
         bin.name = bin.name .. id
      end
      bin.handler = bins[id]
      options.bins.args[tostring(id)] = bin
   end
   if reload then
      R:NotifyChange("Button Bin: Bins")
   else
      mod.binopts = mod:OptReg(": Bins", options.bins, "Bins")
   end
end

do
   local updateOnce  = { value=true, suffix=true, label=true, text=true }
   function mod:UpdateBlock(name, frame, delay)
      frame = frame or buttonFrames[name]
      local updated, uonce
      if frame then
         local obj = ldbObjects[name]
         for key, func in pairs(updaters) do
            uonce = updateOnce[key]
            if not uonce or not updated then
               func(frame, obj[key], name, obj, delay)
            end
            updated = uonce or updated
         end
      end
   end
end

function mod:UpdateAllBlocks(name, parent)
   for name,frame in pairs(buttonFrames) do
      if not parent or  frame:GetParent() == parent then
         mod:UpdateBlock(name, frame)
      end
   end
end

local disabled = "|cff999999%s|r"
local override = "|cffffff00%s|r"
--local enabled = "|cff00cf00%s|r"

function mod:SetupDataBlockOptions(reload)

   local conf = options.objconfig.args
   local counter = 1

   local used = {}
   if reload then
      for id,data in pairs(conf) do
         if data.desc then
            used[data.desc] = data
            conf[id] = nil
         end
      end
   end

   -- sort by name
   local sorted = {}
   for name in pairs(db.enabledDataObjects) do
      sorted[#sorted+1] = name
   end
   tsort(sorted)

   --
   for _,name in ipairs(sorted) do
      local data = db.enabledDataObjects[name]
      if LDB:GetDataObjectByName(name) then
         local obj = used[name]
         if not obj then
            obj = {}
            for key, val in pairs(options.dataBlock) do
               obj[key] = val
            end
         end
         if data.enabled then
            if db.enabledDataObjects[name].blockOverride then
               obj.name = override:format(name)
            else
               obj.name = name
            end
         else
            obj.name = disabled:format(name)
         end
         obj.desc = name
         obj.order = counter
         conf[tostring(counter)] = obj
         counter = counter + 1
      end
   end

   if reload then
      R:NotifyChange("Button Bin: Datablock Configuration")
   else
      mod:OptReg(": Datablock Config", options.objconfig, "Datablock Configuration")
   end
end

function mod:SetupOptions()
   options.profile = DBOpt:GetOptionsTable(self.db)
   mod.main = mod:OptReg("Button Bin", options.global)
   mod:SetupBinOptions()
   mod:SetupDataBlockOptions()
   mod.profile = mod:OptReg(": Profiles", options.profile, "Profiles")
   mod:OptReg("Button Bin CmdLine", options.cmdline, nil,  { "buttonbin", "bin" })
end

function mod:ToggleConfigDialog(frame)
   mod:InterfaceOptionsFrame_OpenToCategory(mod.profile)
   mod:InterfaceOptionsFrame_OpenToCategory(mod.main)
end

function mod:ToggleCollapsed(frame)
   local bdb
   local bin = frame:GetParent()
   bdb = db.bins[bin.binId]
   bdb.collapsed = not bdb.collapsed
   bin._isMouseOver = true
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
   if not bin or bin.disabled then return end
   local bdb,sdb = mod:GetBinSettings(bin)
   local sizeOptions
   local xoffset = 0
   local width = 0
   local height = 0
   local sorted = bdb.sortedButtons
   local frame
   local addBin = false
   if not bdb.hideBinIcon and bdb.collapsed
      and not (unlockButtons or unlockFrames) then
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
   local frameAlign = {}
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
         frameAlign[1] = { frame = previousFrame, width = xoffset, ypos = ymulti*inset }
      else
         previousFrame = nil
      end
   else
      bin.button:ClearAllPoints()
      bin.button:Hide()
      width = inset
      height = inset
   end
   local lineWidth = 0
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
            else
               lineWidth = xoffset
            end
            count = count + 1
            if xoffset > width then width =  xoffset end
            if previousFrame then
               frame:SetPoint(anchor, previousFrame, otheranchor, xmulti*hpadding, 0)
            else
               height = height + vpadding
               local ypos = ymulti*(height-vpadding)
               if bdb.center then
                  local frameCount = #frameAlign
                  if frameCount > 0 then
                     frameAlign[frameCount].width = lineWidth
                  end
                  frameAlign[frameCount+1] = { frame = frame, width = xoffset, ypos = ypos }
               end
               frame:SetPoint(anchor, bin, anchor, xmulti*inset, ypos)
            end
            previousFrame = frame
         else
            frame:Hide()
         end
      end
   end

   if #frameAlign > 0 then
      frameAlign[#frameAlign].width = xoffset
   end

   if bdb.pixelwidth > width then
      width = bdb.pixelwidth
   end
   if bdb.center then
      for id,framedata in ipairs(frameAlign) do
         if framedata.width ~= width then
            framedata.frame:ClearAllPoints()
            framedata.frame:SetPoint(anchor, bin, anchor, xmulti*(inset+(width-framedata.width)/2), framedata.ypos)
         end
      end
   end
   bin:SetWidth(width + inset)
   bin:SetHeight(height + inset)
   bin.mover:SetWidth(bin:GetWidth())
   bin.mover:SetHeight(bin:GetHeight())
   bin:ShowOrHide()
end


do
   local unusedFrames = {}
   local numBlocks = 1
   local oldSorted

   local function Button_OnDragStart(self)
      local toRemove
      local bin = self:GetParent()
      local bdb = db.bins[bin.binId]
      local newSorted = {}
      for id, name in pairs(bdb.sortedButtons) do
         if name ~= self.name then
            newSorted[#newSorted+1] = name
         end
      end
      oldSorted = bdb.sortedButtons
      bdb.sortedButtons = newSorted
      mod:SortFrames(bin)
      self:ClearAllPoints()
      self:StartMoving()
      self:SetAlpha(0.75)
      self:SetFrameLevel(100)
   end

   local function Button_OnDragStop(self)
      local bin = self:GetParent()
      local bdb = db.bins[bin.binId]
      local destFrame, destParent
      self:StopMovingOrSizing()
      self:SetFrameLevel(98)
      self:SetAlpha(1.0)
      for id,frame in ipairs(bins) do
         if mod:MouseIsOver(frame.button) then
            destFrame = frame.button
            destParent = frame
         end
      end

      if not destFrame then
         for name,frame in pairs(buttonFrames) do
            if mod:MouseIsOver(frame) and frame ~= self then
               destFrame = frame
               destParent = frame:GetParent()
               break
            end
         end
      end
      if destFrame and destParent then
         if destParent ~= bin then
            --         mod:Print("Changing parent from "..bin.binId.." to "..destParent.binId)
            self.db.bin = destParent.binId
            self:SetParent(destParent)
            bdb = db.bins[destParent.binId]
         end
         local inserted
         if destParent.button == destFrame then
            tinsert(bdb.sortedButtons, 1, self.name)
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
               x = select(2, GetCursorPosition())
               midpoint = (destFrame:GetBottom() + destFrame:GetHeight()/2)*destParent:GetEffectiveScale()
               if bdb.flipy then
                  if x > midpoint then add = 1 end
               else
                  if x < midpoint then add = 1 end
               end
            end

            --         mod:Print("x = "..x..", mid = "..midpoint.."...")
            for id,n in pairs(bdb.sortedButtons) do
               if destFrame.name == n then
                  id = id + add
                  if id < 1 then id = 1 end
                  if id > (#bdb.sortedButtons+1) then id = id - 1 end
                  tinsert(bdb.sortedButtons, id, self.name)
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
      self:SetParent(bin)
      mod:SortFrames(bin)
   end

   function mod:DataBlockConfig(name, var, global)
      local bcfg = db.enabledDataObjects[name]
      if not bcfg or not bcfg.blockOverride then
         if type(global) == "table" then
            return global[var]
         else
            return global
         end
      end
      return bcfg[var]
   end

   local function Frame_ResizeWindow(self, dontShow)
      local parent = self:GetParent()
      local bdb,sdb,dbs = mod:GetBinSettings(parent)
      local iconWidth, width
      local hideIcon = mod:DataBlockConfig(self.name, "hideIcon", bdb.hideIcons)
      local showLabel = not not self.buttonBinText
      if parent:GetAlpha() < 1.0 then
         self.label:Hide()
         return
      end
      self.icon:ClearAllPoints()
      self.label:ClearAllPoints()

      if self.name ~= "ButtonBin" and hideIcon and showLabel
         and not bdb.labelOnMouse then
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

      if showLabel and (not bdb.labelOnMouse or self._isMouseOver) then
         if bdb.font and bdb.fontsize then
            self.label:SetFont(media:Fetch("font", bdb.font), bdb.fontsize)
         end
         self.label:SetText(self.buttonBinText)
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
         self.label:SetText("")
         self.label:Hide()
         width = iconWidth
      end
      if bdb.labelOnMouse and showLabel then
         local oldWidth = self:GetWidth(self)
         if oldWidth > 0 and  oldWidth ~= width then
            local bin = parent
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
         frame = CreateFrame("Button", "ButtonBinBlock"..numBlocks)
         frame:EnableMouse(true)
         frame:RegisterForClicks("AnyUp")
         frame.icon = frame:CreateTexture()
         frame.label = frame:CreateFontString(nil, nil, "GameFontNormal")
         frame.resizeWindow = Frame_ResizeWindow
         frame:SetScript("OnDragStart", Button_OnDragStart)
         frame:SetScript("OnDragStop", Button_OnDragStop)
         numBlocks = numBlocks + 1
      end
      return frame
   end

   function mod:ReleaseFrame(frame)
      local bin = frame:GetParent()
--      mod:Print("Releasing button frame ", frame.name)
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
      frame:SetScript("OnReceiveDrag", nil)
      if bin and not bin.disabled then self:SortFrames(bin) end
   end
end

do
   local unusedBinFrames = {}
   local numBinFrames = 1
   local bgFrame = {
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 6,
      insets = {left = 1, right = 1, top = 1, bottom = 1}
   }
   function mod:ReleaseBinFrame(frame, noClear)
      frame.disabled = true
      LJ:Unregister(frame) -- easier to always do this
      for _,obj in pairs(buttonFrames) do
         if obj:GetParent() == frame then
            mod:ReleaseFrame(obj)
         end
      end
      unusedBinFrames[#unusedBinFrames+1] = frame
--      mod:Print("Released bin frame id ", frame.binId,  " at position #", #unusedBinFrames)
      if not noClear then
         bins[frame.binId] = nil
      end
      frame.button.db = nil
      frame.button.binId = nil
      frame.button.obj = nil
      frame.mover.text:Hide()
      frame.mover:Hide()
      frame:Hide()
   end

   function mod:GetBinFrame()
      local f
      if #unusedBinFrames > 0 then
         f = unusedBinFrames[#unusedBinFrames]
         f.disabled = nil
--         mod:Print("Using unused bin frame #", #unusedBinFrames)
         unusedBinFrames[#unusedBinFrames] = nil
      else
--         mod:Print("Creating new bin frame");
         f = setmetatable(CreateFrame("Frame", "ButtonBinParent:"..numBinFrames, UIParent, BackdropTemplateMixin and "BackdropTemplate"), mod.binMetaTable_mt)
         f:EnableMouse(true)
         f:SetScript("OnEnter", function(self) self._isMouseOver = true self:ShowOrHide(nil, true) end)
         f:SetScript("OnLeave", function(self) self._isMouseOver = nil  self:ShowOrHide(true) end)
         f.mover = CreateFrame("Button", "ButtonBinMover", UIParent, BackdropTemplateMixin and "BackdropTemplate")
         f.mover:EnableMouse(true)
         f.mover:SetMovable(true)
         f.mover:SetBackdrop(bgFrame)
         f.mover:SetBackdropColor(0, 1, 0);
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
         if not db.hideBinTooltip then
            f.button:SetScript("OnEnter", LDB_OnEnter)
            f.button:SetScript("OnLeave", LDB_OnLeave)
         end
         f.mover:Hide()
         f.mover.text:Hide()
      end
      return f
   end
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

