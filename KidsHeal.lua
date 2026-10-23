--[[
  KidsHeal v1.2.0
  ==============
  Big health bars with clickable spell icons for each group member.

  HOW TO USE
  ----------
  1. Open your spellbook (or bags) and DRAG a spell onto one of the big
     icon slots below a health bar. Every group member's bar gets it.
     You can also drag usable ITEMS (e.g. a healing trinket) onto a slot.
  2. LEFT-CLICK an icon -> casts that spell on THAT player.
  3. The cooldown sweep shows on every bar at the same time.
  4. MOVE the panel: left-click and hold the handle strip on top.
  5. `/kidsheal clear <n>` removes the spell in slot n.

  TECH NOTE (v1.2.0): spell drops are detected by polling GetCursorInfo()
  (never CursorHasSpell, which is unreliable) while a pickup is held, and
  assigned the moment the cursor empties while still hovering a slot.
  A drop-catcher frame is also kept as a fast path. This works even if
  OnReceiveDrag never fires.
]]

local CONFIG = {
  barWidth = 260,
  barHeight = 46,
  buttonSize = 52,
  spacing = 10,
  iconSpacing = 8,
  slotCount = 4,
  showHealthText = true,
}

local DEFAULT_POS = { x = 40, y = -120 }

---------------------------------------------------------------------------

local container = CreateFrame("Frame", "KidsHealPanel", UIParent)
local memberFrames = {}
local rosterDirty = false
local DEBUG = false

local function dbg(...)
  if DEBUG then print("|cff00ccffKidsHeal|r DEBUG:", ...) end
end

-- ------------------------------------------------------------------ profile
local function CharKey()
  local n, r = UnitName("player"), GetRealmName()
  return (n or "?") .. " - " .. (r or "?")
end

local function Profile()
  if type(KidsHealDB) ~= "table" then KidsHealDB = {} end
  local k = CharKey()
  if type(KidsHealDB[k]) ~= "table" then KidsHealDB[k] = { spells = {} } end
  local p = KidsHealDB[k]
  if type(p.spells) ~= "table" then p.spells = {} end
  if type(p.x) ~= "number" then p.x, p.y = DEFAULT_POS.x, DEFAULT_POS.y end
  return p
end

-- ------------------------------------------------------------------ layout
local function BlockHeight()
  return CONFIG.barHeight + CONFIG.buttonSize + 6
end

local function PanelHeight(n)
  return 30 + 8 + n * BlockHeight() + (n - 1) * CONFIG.spacing
end

local function ApplyPosition()
  local p = Profile()
  container:ClearAllPoints()
  container:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.x, p.y)
end

local function SavePosition()
  local p = Profile()
  p.x = container:GetLeft() or DEFAULT_POS.x
  p.y = (container:GetTop() or 0) - (UIParent:GetTop() or 0)
end

local function EnableDrag(frame)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    if InCombatLockdown() then return end
    container:StartMoving()
  end)
  frame:SetScript("OnDragStop", function()
    container:StopMovingOrSizing()
    SavePosition()
  end)
end

-- ------------------------------------------------------------------ assignments
local function ResolveEntry(entry)
  if not entry then return nil end
  if entry.kind == "spell" then
    if entry.id then
      local name, _, icon = GetSpellInfo(entry.id)
      if name then return { kind = "spell", id = entry.id, name = name, icon = icon } end
    elseif entry.name then
      -- pet spells have no spell id; resolve by name
      local name, _, icon = GetSpellInfo(entry.name)
      if name then return { kind = "spell", id = nil, name = name, icon = icon } end
    end
  elseif entry.kind == "item" then
    local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(entry.id)
    if name then return { kind = "item", id = entry.id, name = name, icon = icon } end
  end
  return nil
end

local function ApplyAssignment(btn, entry, unitId)
  if InCombatLockdown() then return end
  btn:SetAttribute("type", nil)
  btn:SetAttribute("spell", nil)
  btn:SetAttribute("macrotext", nil)
  btn:SetAttribute("unit", nil)
  if not entry then return end
  if entry.kind == "spell" then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", entry.name)
    btn:SetAttribute("unit", unitId)
  elseif entry.kind == "item" then
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "/use [@" .. unitId .. "] " .. entry.name)
  end
end

local function ApplySlotToAll(slotIndex)
  local p = Profile()
  local entry = ResolveEntry(p.spells[slotIndex])
  for unitId, m in pairs(memberFrames) do
    local btn = m.buttons[slotIndex]
    if btn then
      ApplyAssignment(btn, entry, unitId)
      btn.entry = entry
      btn.icon:SetTexture(entry and entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      btn.icon:SetDesaturated(not entry)
      if entry then
        btn.icon:SetVertexColor(1, 1, 1)
      else
        btn.icon:SetVertexColor(0.5, 0.5, 0.5)
      end
    end
  end
end

local function AssignEntry(slotIndex, rawEntry)
  if not rawEntry or not slotIndex then return end
  Profile().spells[slotIndex] = rawEntry
  ApplySlotToAll(slotIndex)
  local r = ResolveEntry(rawEntry)
  print("|cff00ccffKidsHeal|r: Slot " .. slotIndex .. " = " .. (r and r.name or "?"))
end

-- ------------------------------------------------------------------ updates
local function UpdateHealth(member)
  local f = member.main
  local unit = member.unit
  if not UnitExists(unit) then
    f:Hide()
    return
  end
  f:Show()
  local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
  member.healthBar:SetMinMaxValues(0, math.max(hpMax, 1))
  member.healthBar:SetValue(hp)
  local _, class = UnitClass(unit)
  local c = RAID_CLASS_COLORS[class] or { r = 0.3, g = 0.3, b = 0.3 }
  member.healthBar:SetStatusBarColor(c.r, c.g, c.b)
  member.nameText:SetText(UnitName(unit))
  if CONFIG.showHealthText then
    member.healthText:SetText(("%d / %d"):format(hp, hpMax))
  end
end

local function UpdateButton(member, i)
  local btn = member.buttons[i]
  if not btn then return end
  local e = btn.entry

  local start, duration
  if e then
    if e.kind == "spell" then
      start, duration = GetSpellCooldown(e.id)
    else
      start, duration = GetItemCooldown(e.id)
    end
  end
  if start and start > 0 and duration and duration > 1.5 then
    if btn.cdStart ~= start or btn.cdDuration ~= duration then
      btn.cd:SetCooldown(start, duration)
      btn.cdStart, btn.cdDuration = start, duration
    end
    btn.cd:Show()
  else
    if btn.cdStart then
      btn.cd:Hide()
      btn.cdStart, btn.cdDuration = nil, nil
    end
  end

  if not e then return end
  local usable, noMana
  local inRange
  if e.kind == "spell" then
    usable, noMana = IsUsableSpell(e.id)
    inRange = IsSpellInRange(e.id, member.unit)
  else
    usable, noMana = IsUsableItem(e.id)
    inRange = IsItemInRange(e.id, member.unit)
  end
  if not usable or noMana then
    btn.icon:SetDesaturated(true)
    btn.icon:SetVertexColor(0.4, 0.4, 0.4)
  elseif inRange == 0 then
    btn.icon:SetDesaturated(false)
    btn.icon:SetVertexColor(0.6, 0.6, 0.6)
  else
    btn.icon:SetDesaturated(false)
    btn.icon:SetVertexColor(1, 1, 1)
  end
end

local function UpdateMember(member)
  UpdateHealth(member)
  for i = 1, CONFIG.slotCount do UpdateButton(member, i) end
end

-- ------------------------------------------------------------------ build
local function CreateMember(unitId, index)
  local f = CreateFrame("Frame", "KidsHealBox" .. index, container)
  f:SetSize(CONFIG.barWidth, BlockHeight())
  f:SetPoint("TOPLEFT", container, "TOPLEFT", 0,
             -(38 + (index - 1) * (BlockHeight() + CONFIG.spacing)))

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0.55)

  local hb = CreateFrame("StatusBar", nil, f)
  hb:SetSize(CONFIG.barWidth - 8, CONFIG.barHeight - 8)
  hb:SetPoint("TOP", f, "TOP", 0, -4)
  hb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  hb:SetMinMaxValues(0, 1)
  hb:SetValue(1)
  hb.bg = hb:CreateTexture(nil, "BACKGROUND")
  hb.bg:SetAllPoints()
  hb.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  hb.bg:SetVertexColor(0.08, 0.08, 0.08)

  hb.nameText = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  hb.nameText:SetPoint("TOPLEFT", hb, "TOPLEFT", 6, -4)
  hb.healthText = hb:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  hb.healthText:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", -6, 4)

  local member = {
    unit = unitId, main = f,
    healthBar = hb, nameText = hb.nameText, healthText = hb.healthText,
    buttons = {},
  }

  local n = CONFIG.slotCount
  for i = 1, n do
    local btn = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
    local size = CONFIG.buttonSize
    local xOff = -((n - 1) * (size + CONFIG.iconSpacing)) / 2
      + (i - 1) * (size + CONFIG.iconSpacing)
    btn:SetSize(size, size)
    btn:SetPoint("TOP", f, "TOP", xOff, -(CONFIG.barHeight - 2))

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints()

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:RegisterForClicks("LeftButtonDown")

    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      local e = self.entry
      if e then
        if e.kind == "spell" then
          GameTooltip:SetSpellByID(e.id)
        else
          GameTooltip:SetItemByID(e.id)
        end
        GameTooltip:AddLine("Klick: wirken auf " ..
          (UnitName(unitId) or unitId), 1, 1, 1)
      else
        GameTooltip:AddLine("Leerer Slot", 1, 1, 1)
        GameTooltip:AddLine("Zieh einen Zauber hierher", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("(oder ein benutzbares Item, z.B. Trank/Trinket)", 0.8, 0.8, 0.8)
      end
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    member.buttons[i] = btn
  end

  f:SetScript("OnEnter", function(self)
    if UnitExists(unitId) then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetUnit(unitId)
      GameTooltip:Show()
    end
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  EnableDrag(f)

  return member
end

local function Rebuild()
  for _, m in pairs(memberFrames) do m.main:Hide() end
  memberFrames = {}

  local units = { "player" }
  for i = 1, 4 do units[#units + 1] = "party" .. i end
  for i, unit in ipairs(units) do
    memberFrames[unit] = CreateMember(unit, i)
  end

  container:SetSize(CONFIG.barWidth, PanelHeight(#units))
  for i = 1, CONFIG.slotCount do ApplySlotToAll(i) end
  for _, m in pairs(memberFrames) do UpdateMember(m) end
end

local function RequestRebuild()
  if InCombatLockdown() then
    rosterDirty = true
  else
    Rebuild()
  end
end

-- ------------------------------------------------------------------ drag handle
local handle = CreateFrame("Frame", "KidsHealHandle", container)
handle:SetSize(CONFIG.barWidth, 26)
handle:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
handle.tex = handle:CreateTexture(nil, "BACKGROUND")
handle.tex:SetAllPoints()
handle.tex:SetColorTexture(0, 0, 0, 0.7)
handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
handle.text:SetText("≡ KidsHeal  (hier festhalten und ziehen)")
handle.text:SetPoint("CENTER", handle, "CENTER", 0, 0)
handle.text:SetTextColor(0, 0.8, 1)
EnableDrag(handle)
handle:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Linke Maustaste gedrückt halten und ziehen", 1, 1, 1)
  GameTooltip:Show()
end)
handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

container:SetMovable(true)

-- ------------------------------------------------------------------ drop detection
-- Two mechanisms:
-- (A) while a pickup is held, we cache what the cursor holds and which slot
--     is hovered. The moment the cursor EMPTIES (drop happened anywhere),
--     we assign if the mouse is still over that slot. This works even if
--     no drop event ever reaches us.
-- (B) a catcher frame above the hovered slot handles OnReceiveDrag/OnMouseUp
--     as a fast path.
local pendingEntry = nil   -- cached {kind,id,name} of what was held
local pendingSlot = nil

-- find the slot button under the mouse; returns member, slotIndex, btn
local function FindHoveredSlot()
  for _, m in pairs(memberFrames) do
    for i = 1, CONFIG.slotCount do
      local btn = m.buttons[i]
      if btn and btn:IsShown() and MouseIsOver(btn) then
        return m, i, btn
      end
    end
  end
  return nil, nil, nil
end

-- read and cache what the cursor holds; returns true if usable for us
local function CacheCursor()
  local kind, a, b = GetCursorInfo()
  if kind == "spell" then
    local name, _, _, _, _, _, spellId = GetSpellBookItemInfo(a, b)
    if name and spellId then
      pendingEntry = { kind = "spell", id = spellId, name = name }
      dbg("cursor: spell", name, spellId)
      return true
    end
  elseif kind == "petaction" then
    local name = GetSpellBookItemInfo(a, b)
    if name then
      pendingEntry = { kind = "spell", id = nil, name = name }
      dbg("cursor: petaction", name)
      return true
    end
  elseif kind == "item" then
    pendingEntry = { kind = "item", id = a }
    dbg("cursor: item", a)
    return true
  end
  return false
end

local catcher = CreateFrame("Frame", "KidsHealDropCatcher", UIParent)
catcher:EnableMouse(true)
catcher:SetFrameStrata("TOOLTIP")
catcher:Hide()

catcher:SetScript("OnReceiveDrag", function()
  if pendingSlot and pendingEntry then
    AssignEntry(pendingSlot, pendingEntry)
  end
  pendingEntry, pendingSlot = nil, nil
  catcher:Hide()
end)
catcher:SetScript("OnMouseUp", function()
  if pendingSlot and pendingEntry then
    AssignEntry(pendingSlot, pendingEntry)
  end
  pendingEntry, pendingSlot = nil, nil
  catcher:Hide()
end)

local function PollCursor()
  if InCombatLockdown() then
    pendingEntry, pendingSlot = nil, nil
    catcher:Hide()
    return
  end
  if GetCursorInfo() then
    if CacheCursor() then
      local m, i, btn = FindHoveredSlot()
      if btn then
        pendingSlot = i
        catcher:ClearAllPoints()
        catcher:SetAllPoints(btn)
        catcher:Show()
      else
        pendingSlot = nil
        catcher:Hide()
      end
    end
  else
    -- cursor just emptied: if it emptied over our slot, that was a drop
    if pendingSlot and pendingEntry then
      local _, i, btn = FindHoveredSlot()
      if btn and i == pendingSlot then
        AssignEntry(pendingSlot, pendingEntry)
      end
    end
    pendingEntry, pendingSlot = nil, nil
    catcher:Hide()
  end
end

-- ------------------------------------------------------------------ events
container:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
    if event == "PLAYER_ENTERING_WORLD" then ApplyPosition() end
    RequestRebuild()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if rosterDirty then rosterDirty = false; Rebuild() end
  elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
      or event == "UNIT_NAME_UPDATE" then
    local m = memberFrames[unit]
    if m then UpdateHealth(m) end
  end
end)
container:RegisterEvent("PLAYER_ENTERING_WORLD")
container:RegisterEvent("GROUP_ROSTER_UPDATE")
container:RegisterEvent("PLAYER_REGEN_ENABLED")
container:RegisterEvent("UNIT_HEALTH")
container:RegisterEvent("UNIT_MAXHEALTH")
container:RegisterEvent("UNIT_NAME_UPDATE")

-- timers: 0.05s cursor polling, 0.25s cooldown/range refresh
local fast = 0
local slow = 0
container:SetScript("OnUpdate", function(_, e)
  fast = fast + e
  if fast >= 0.05 then
    fast = 0
    PollCursor()
  end
  slow = slow + e
  if slow >= 0.25 then
    slow = 0
    for _, m in pairs(memberFrames) do UpdateMember(m) end
  end
end)

-- ------------------------------------------------------------------ slash
SLASH_KIDSHEAL1 = "/kidsheal"
SlashCmdList["KIDSHEAL"] = function(msg)
  local cmd, arg = msg:match("(%S+)%s*(%S*)")
  cmd = cmd and cmd:lower() or ""
  if cmd == "reset" then
    local p = Profile()
    p.x, p.y = DEFAULT_POS.x, DEFAULT_POS.y
    ApplyPosition()
    print("|cff00ccffKidsHeal|r: Position zurückgesetzt (oben links).")
  elseif cmd == "clear" then
    local n = tonumber(arg)
    if n and n >= 1 and n <= CONFIG.slotCount then
      if not InCombatLockdown() then
        Profile().spells[n] = nil
        ApplySlotToAll(n)
        print("|cff00ccffKidsHeal|r: Slot " .. n .. " geleert.")
      else
        print("|cff00ccffKidsHeal|r: Nicht im Kampf möglich.")
      end
    else
      print("|cff00ccffKidsHeal|r: /kidsheal clear 1.." .. CONFIG.slotCount)
    end
  elseif cmd == "debug" then
    DEBUG = not DEBUG
    print("|cff00ccffKidsHeal|r: Debug " .. (DEBUG and "AN" or "AUS") ..
      ". Halte einen Zauber im Cursor und schaue in den Chat.")
  elseif cmd == "test" then
    for _, m in pairs(memberFrames) do
      m.healthBar:SetValue(math.random(30, 100) / 100 * math.max(UnitHealthMax(m.unit), 1))
    end
  elseif cmd == "refresh" then
    RequestRebuild()
    print("|cff00ccffKidsHeal|r neu aufgebaut.")
  else
    print("|cff00ccffKidsHeal|r: reset | clear <slot> | test | refresh | debug")
  end
end
