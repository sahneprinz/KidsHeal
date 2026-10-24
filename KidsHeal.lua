--[[
  KidsHeal v1.3.22
  ==============
  Big health bars with clickable spell icons for each group member.

  HOW TO USE
  ----------
  1. Open your spellbook (or bags) and DRAG a spell onto one of the big
     icon slots below (or next to, see options) a health bar. Every group
     member's bar gets it. You can also drag usable ITEMS (e.g. a healing
     trinket) onto a slot.
  2. LEFT-CLICK an icon -> casts that spell on THAT player.
  3. The cooldown sweep shows on every bar at the same time.
  4. MOVE the panel: left-click and hold the handle strip on top.
  5. `/kidsheal clear <n>` removes the spell in slot n.
  6. Size of bars/icons and icon position: Interface Options -> AddOns -> KidsHeal.

  TECH NOTE (v1.3.2): drop detection works on three independent paths:
  (1) OnReceiveDrag directly on the slot button,
  (2) cursor polling via GetCursorInfo() - the moment the cursor empties
      while the mouse is over a slot (found via GetMouseFocus and a
      MouseIsOver fallback), the cached entry is assigned,
  (3) dragging from an ACTION BAR is now supported too (kind "action"
      is resolved via GetActionInfo).
  The old TOOLTIP-strata catcher frame was removed - it swallowed drops.
]]

local DEFAULTS = {
  barWidth = 120,
  barHeight = 36,
  iconSize = 24,
  spacing = 10,
  iconSpacing = 8,
  slotCount = 4,
  iconsRight = false,
  showHealthText = true,
  nameFontSize = 14,
  hpFontSize = 14,
  buffSize = 18,
  barPadding = 4,
  buffPadding = -9,
  blockSpacing = 10,
  showAllBuffs = false,
  onlyMyBuffs = false,
  showFocus = true,
  maxBuffs = 10,
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
  if type(p.spells) == "table" and type(p.specSpells) ~= "table" then
    -- migrate old flat layout to the current specialization
    p.specSpells = { [GetSpecialization() or 1] = p.spells }
    p.spells = nil
  end
  if type(p.specSpells) ~= "table" then p.specSpells = {} end
  if type(p.x) ~= "number" then p.x, p.y = DEFAULT_POS.x, DEFAULT_POS.y end
  if type(p.settings) ~= "table" then p.settings = {} end
  for key, val in pairs(DEFAULTS) do
    if p.settings[key] == nil then p.settings[key] = val end
  end
  return p
end

local function Settings()
  return Profile().settings
end

local function SpellSlots()
  local p = Profile()
  local spec = GetSpecialization() or 1
  if type(p.specSpells[spec]) ~= "table" then p.specSpells[spec] = {} end
  return p.specSpells[spec]
end

local function SlotCount()
  local p = Profile()
  local spec = GetSpecialization() or 1
  if type(p.specSlotCount) ~= "table" then
    -- first read after update: take over the previous global setting
    p.specSlotCount = { }
    for i = 1, 4 do p.specSlotCount[i] = p.settings.slotCount end
  end
  local n = p.specSlotCount[spec]
  if type(n) ~= "number" or n < 1 then n = 1 end
  if n > 10 then n = 10 end
  return math.floor(n)
end

local function SetSlotCount(n)
  local p = Profile()
  local spec = GetSpecialization() or 1
  if type(p.specSlotCount) ~= "table" then p.specSlotCount = {} end
  p.specSlotCount[spec] = math.floor(n)
end

-- ------------------------------------------------------------------ layout
local function BlockSize()
  local s = Settings()
  local blockW, blockH
  local pad = s.barPadding
  local n = SlotCount()
  local iconRowW = n * s.iconSize + (n - 1) * s.iconSpacing
  if s.iconsRight then
    blockW = s.barWidth + pad + iconRowW + pad
    blockH = math.max(s.barHeight, s.iconSize) + pad * 2
  else
    blockW = math.max(s.barWidth, iconRowW + pad * 2)
    blockH = s.barHeight + s.iconSize + pad * 2
  end
  return blockW, blockH
end

local function PanelHeight(n)
  local _, blockH = BlockSize()
  return 12 + n * blockH + (n - 1) * Settings().blockSpacing
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
  local entry = ResolveEntry(SpellSlots()[slotIndex])
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
  if InCombatLockdown() then
    print("|cff00ccffKidsHeal|r: Nicht im Kampf möglich.")
    return
  end
  SpellSlots()[slotIndex] = rawEntry
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
  if Settings().showHealthText then
    member.healthText:SetText(("%d / %d"):format(hp, hpMax))
  else
    member.healthText:SetText("")
  end
end

local function UpdateButton(member, i)
  local btn = member.buttons[i]
  if not btn then return end
  local e = btn.entry

  local start, duration
  if e then
    local ref = e.id or e.name
    if e.kind == "spell" then
      start, duration = GetSpellCooldown(ref)
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
  local ref = e.id or e.name
  if e.kind == "spell" then
    usable, noMana = IsUsableSpell(ref)
    inRange = IsSpellInRange(ref, member.unit)
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

local UpdateBuffs  -- defined below (buff row)

local function UpdateMember(member)
  UpdateHealth(member)
  for i = 1, SlotCount() do UpdateButton(member, i) end
  UpdateBuffs(member)
end

-- ------------------------------------------------------------------ buffs
-- show the player's own Heal-over-Time / shield effects (and optionally
-- all buffs) with remaining time under each health bar.
local IMPORTANT_BUFFS = {
  -- Priest
  ["Renew"] = true, ["Erneuerung"] = true,
  ["Power Word: Shield"] = true, ["Machtwort: Schild"] = true,
  ["Prayer of Mending"] = true, ["Gebet der Besserung"] = true,
  ["Pain Suppression"] = true, ["Schmerzunterdrückung"] = true,
  -- Paladin
  ["Divine Shield"] = true, ["Göttlicher Schild"] = true,
  ["Beacon of Light"] = true, ["Siegel des Lichts"] = true,
  ["Blessing of Sacrifice"] = true, ["Segen des Opfers"] = true,
  ["Blessing of Protection"] = true, ["Segen des Schutzes"] = true,
  ["Blessing of Spellwarding"] = true, ["Segen der Zauberschutzwehr"] = true,
  -- Monk
  ["Renewing Mist"] = true, ["Erneuernder Nebel"] = true,
  ["Enveloping Mist"] = true, ["Einhüllender Nebel"] = true,
  ["Life Cocoon"] = true, ["Lebenskokon"] = true,
  ["Soothing Mist"] = true, ["Beruhigender Nebel"] = true,
  ["Thunder Focus Tea"] = true, ["Donnerfokus-Tee"] = true,
  -- Druid
  ["Rejuvenation"] = true, ["Verjüngung"] = true,
  ["Regrowth"] = true, ["Nachwachsen"] = true,
  ["Wild Growth"] = true, ["Wildwuchs"] = true,
  ["Ironbark"] = true, ["Eisenrinde"] = true,
  -- Shaman
  ["Riptide"] = true, ["Springflut"] = true,
  ["Earth Shield"] = true, ["Erdschild"] = true,
  ["Spirit Link"] = true, ["Geistführer-Verbindung"] = true,
  -- Discipline Priest
  ["Atonement"] = true, ["Sühne"] = true,
  ["Grace"] = true, ["Gnade"] = true,
}

UpdateBuffs = function(member)
  if not member.buffFrames then return end
  local unit = member.unit
  if not UnitExists(unit) then return end
  local s = Settings()
  local idx = 1
  local filterMine = s.onlyMyBuffs and not s.showAllBuffs
  -- with "Nur meine Zauber": ask the client directly whose buff it is
  -- (UnitBuff's third argument "PLAYER" returns only buffs cast by me)
  for i = 1, 40 do
    local name, _, icon, _, _, duration, expires, _, _, _, spellId
    if filterMine then
      name, _, icon, _, _, duration, expires, _, _, _, spellId = UnitBuff(unit, i, "PLAYER")
    else
      name, _, icon, _, _, duration, expires, _, _, _, spellId = UnitBuff(unit, i)
    end
    if not name then break end
    if filterMine then
      dbg("buff:", name, "id:", spellId, "inList:", IMPORTANT_BUFFS[name] and true or false)
    end
    if s.showAllBuffs
        or (not filterMine and IMPORTANT_BUFFS[name])
        or (filterMine and IMPORTANT_BUFFS[name]) then
      local f = member.buffFrames[idx]
      if f then
        f.buffName = name
        f.buffIndex = i
        f.icon:SetTexture(icon)
        local remain = expires and (expires - GetTime()) or nil
        if remain and remain > 0 then
          if remain < 10 then
            f.time:SetText(("%.1f"):format(remain))
          else
            f.time:SetText(("%d"):format(remain))
          end
        else
          f.time:SetText("")
        end
        f:Show()
        idx = idx + 1
        if idx > s.maxBuffs then break end
      end
    end
  end
  for i = idx, s.maxBuffs do
    if member.buffFrames[i] then member.buffFrames[i]:Hide() end
  end
end

-- ------------------------------------------------------------------ drop detection
-- Three independent paths (see header note). The catcher frame from older
-- versions is gone; it sat in the TOOLTIP strata above the slot and
-- swallowed the drop before the button ever saw it.
local pendingEntry = nil   -- cached {kind,id,name} of what was held
local pendingCursor = false

local function SlotUnderMouse()
  local focus = GetMouseFocus()
  while focus do
    if focus.isKidSlot then return focus end
    focus = focus:GetParent()
  end
  -- fallback: geometric check
  for _, m in pairs(memberFrames) do
    for i = 1, SlotCount() do
      local btn = m.buttons[i]
      if btn and btn:IsShown() and MouseIsOver(btn) then
        return btn
      end
    end
  end
  return nil
end

-- read what the cursor holds; returns an entry table or nil
local function CacheCursor()
  local kind, a, b = GetCursorInfo()
  if not kind then return nil end
  dbg("cursor raw:", kind, a, b)
  if kind == "spell" then
    -- GetCursorInfo returns (slot, bookType) or (bookType, slot) depending
    -- on client version and pickup source; try both orders.
    local name, _, _, _, _, _, spellId = GetSpellBookItemInfo(a, b)
    if not name then
      name, _, _, _, _, _, spellId = GetSpellBookItemInfo(b, a)
    end
    if not name and type(a) == "number" then
      -- some pickups hand us the spell id directly
      local n2 = GetSpellInfo(a)
      if n2 then
        return { kind = "spell", id = a, name = n2 }
      end
    end
    if name then
      dbg("cursor: spell", name, spellId)
      return { kind = "spell", id = spellId, name = name }
    end
  elseif kind == "petaction" then
    -- pet actions have no spellbook entry; resolve via GetPetActionInfo
    local _, petName = GetPetActionInfo(a)
    if not petName and type(b) == "number" then
      _, petName = GetPetActionInfo(b)
    end
    if not petName then petName = GetSpellBookItemInfo(a, b) end
    if not petName then petName = GetSpellBookItemInfo(b, a) end
    if petName then
      dbg("cursor: petaction", petName)
      return { kind = "spell", id = nil, name = petName }
    end
  elseif kind == "item" then
    dbg("cursor: item", a)
    return { kind = "item", id = a }
  elseif kind == "action" then
    -- dragged off an action bar slot
    local aType, aId = GetActionInfo(a)
    if aType == "spell" and aId then
      local name, _, icon = GetSpellInfo(aId)
      if name then
        dbg("cursor: action->spell", name, aId)
        return { kind = "spell", id = aId, name = name }
      end
    elseif aType == "item" and aId then
      dbg("cursor: action->item", aId)
      return { kind = "item", id = aId }
    end
  end
  -- cursor holds something we can't use; keep previous state
  return pendingEntry
end

local function PollCursor()
  if InCombatLockdown() then
    pendingEntry, pendingCursor = nil, false
    return
  end
  local entry = CacheCursor()
  if entry then
    pendingEntry = entry
    pendingCursor = true
  elseif pendingCursor then
    -- cursor just emptied: that was a drop; if it happened over one of
    -- our slots, assign the cached entry to that slot
    pendingCursor = false
    if pendingEntry then
      local btn = SlotUnderMouse()
      if btn then
        AssignEntry(btn.slotIndex, pendingEntry)
      end
      pendingEntry = nil
    end
  end
end

-- ------------------------------------------------------------------ spell pick
-- "The next spell you cast lands in slot N": after clicking an empty slot,
-- the next successful cast of the player is assigned to that slot.
local pickSlot = nil

local function StartSpellPick(slotIndex)
  if InCombatLockdown() then
    print("|cff00ccffKidsHeal|r: Nicht im Kampf möglich.")
    return
  end
  pickSlot = slotIndex
  print("|cff00ccffKidsHeal|r: Wirke jetzt einen Zauber - er landet in Slot " ..
    slotIndex .. ". (Escape oder /kidsheal pick zum Abbrechen)")
end

local function HandleSpellPick(unit, spellName, _, spellId)
  if not pickSlot then return end
  if unit ~= "player" then return end
  local slot = pickSlot
  pickSlot = nil
  local name = spellName or (spellId and select(1, GetSpellInfo(spellId)))
  local id = spellId
  if not id and name then id = select(7, GetSpellInfo(name)) end
  if not name or not id then
    print("|cff00ccffKidsHeal|r: Zauber nicht erkannt. Nutze /kidsheal set.")
    return
  end
  AssignEntry(slot, { kind = "spell", id = id, name = name })
end

-- ------------------------------------------------------------------ build
local function CreateMember(unitId, index)
  local s = Settings()
  local blockW, blockH = BlockSize()
  local f = CreateFrame("Frame", "KidsHealBox" .. index, container)
  f:SetSize(blockW, blockH)
  f:SetPoint("TOPLEFT", container, "TOPLEFT", 0,
             -(12 + (index - 1) * (blockH + s.blockSpacing)))

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0.55)

  local hb = CreateFrame("StatusBar", nil, f)
  hb:SetSize(s.barWidth - 8, s.barHeight - 8)
  if s.iconsRight then
    hb:SetPoint("LEFT", f, "LEFT", s.barPadding, 0)
  else
    hb:SetPoint("TOP", f, "TOP", 0, -s.barPadding)
  end
  hb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  hb:SetMinMaxValues(0, 1)
  hb:SetValue(1)
  hb.bg = hb:CreateTexture(nil, "BACKGROUND")
  hb.bg:SetAllPoints()
  hb.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  hb.bg:SetVertexColor(0.08, 0.08, 0.08)

  hb.nameText = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  hb.nameText:SetPoint("TOPLEFT", hb, "TOPLEFT", 6, -4)
  hb.nameText:SetFont(STANDARD_TEXT_FONT, s.nameFontSize, "OUTLINE")
  hb.healthText = hb:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  hb.healthText:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", -6, 4)
  hb.healthText:SetFont(STANDARD_TEXT_FONT, s.hpFontSize, "OUTLINE")

  local member = {
    unit = unitId, main = f,
    healthBar = hb, nameText = hb.nameText, healthText = hb.healthText,
    buttons = {}, buffFrames = {},
  }

  -- buff row under the health bar -----------------------------------
  local maxB = s.maxBuffs
  for bi = 1, maxB do
    local bf = CreateFrame("Frame", nil, f)
    bf:SetFrameStrata("MEDIUM")
    bf:SetFrameLevel(hb:GetFrameLevel() + 10)
    bf:SetSize(s.buffSize, s.buffSize)
    bf:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT",
      2 + (bi - 1) * (s.buffSize + 2), s.buffPadding)
    bf.bg = bf:CreateTexture(nil, "BACKGROUND")
    bf.bg:SetAllPoints()
    bf.bg:SetColorTexture(0, 0, 0, 0.5)
    bf.icon = bf:CreateTexture(nil, "ARTWORK")
    bf.icon:SetAllPoints()
    bf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bf.time = bf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bf.time:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", 0, 0)
    bf.time:SetFont(STANDARD_TEXT_FONT, math.max(s.buffSize * 0.45, 7), "OUTLINE")
    bf:Hide()
    bf:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      if self.buffName then GameTooltip:SetUnitBuff(unitId, self.buffIndex) end
      GameTooltip:Show()
    end)
    bf:SetScript("OnLeave", function() GameTooltip:Hide() end)
    member.buffFrames[bi] = bf
  end

  local n = SlotCount()
  for i = 1, n do
    local btn = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
    btn:SetSize(s.iconSize, s.iconSize)
    if s.iconsRight then
      local xOff = s.barWidth + 6 + (i - 1) * (s.iconSize + s.iconSpacing)
      local yOff = -((blockH - s.iconSize) / 2)
      btn:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, yOff)
    else
      local xOff = -((n - 1) * (s.iconSize + s.iconSpacing)) / 2
        + (i - 1) * (s.iconSize + s.iconSpacing)
      btn:SetPoint("TOP", f, "TOP", xOff, -(s.barHeight + s.barPadding))
    end

    btn.isKidSlot = true
    btn.slotIndex = i

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints()

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:RegisterForClicks("LeftButtonDown")

    -- empty slot: left-click starts pick mode. IMPORTANT: never SetScript
    -- ("OnClick") here - that would replace the secure cast handler.
    -- PreClick runs before it and leaves filled slots untouched.
    btn:SetScript("PreClick", function(self, mouseButton)
      if self.entry then return end  -- filled slots cast as usual (secure)
      if InCombatLockdown() then return end
      if mouseButton == "LeftButton" then
        StartSpellPick(self.slotIndex)
      end
    end)

    -- drop path 1: the button itself receives the drag release
    btn:SetScript("OnReceiveDrag", function(self)
      if InCombatLockdown() then return end
      if pendingEntry then
        AssignEntry(self.slotIndex, pendingEntry)
        pendingEntry, pendingCursor = nil, false
      end
    end)

    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      local e = self.entry
      if e then
        if e.kind == "spell" then
          if e.id then
            GameTooltip:SetSpellByID(e.id)
          else
            GameTooltip:SetText(e.name)
          end
        else
          GameTooltip:SetItemByID(e.id)
        end
        GameTooltip:AddLine("Klick: wirken auf " ..
          (UnitName(unitId) or unitId), 1, 1, 1)
      else
        GameTooltip:AddLine("Leerer Slot", 1, 1, 1)
        GameTooltip:AddLine("Klick: nächsten Zauber wirken, der dann hier landet", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("(oder /kidsheal set <slot> <Name>)", 0.8, 0.8, 0.8)
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
  if Settings().showFocus then units[#units + 1] = "focus" end
  for i, unit in ipairs(units) do
    memberFrames[unit] = CreateMember(unit, i)
  end

  local blockW = BlockSize()
  container:SetSize(blockW, PanelHeight(#units))
  for i = 1, SlotCount() do ApplySlotToAll(i) end
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
-- invisible drag strip on top of the panel (bars remain draggable too)
local handle = CreateFrame("Frame", "KidsHealHandle", container)
handle:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
handle:SetSize(260, 12)
EnableDrag(handle)

container:SetMovable(true)

-- keep the handle as wide as the panel
local function SyncHandleWidth()
  local blockW = BlockSize()
  handle:ClearAllPoints()
  handle:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  handle:SetSize(blockW, 26)
end

-- ------------------------------------------------------------------ spell picker (typed names)
local function SpellIdByName(name)
  if not name or name == "" then return nil end
  local lower = name:lower()
  for book = 1, 2 do
    local i = 1
    while true do
      local n, _, _, _, _, _, spellId = GetSpellBookItemInfo(i, book)
      if not n then break end
      if n:lower() == lower then return spellId, n end
      i = i + 1
    end
  end
  local n2, _, _, _, _, _, id2 = GetSpellInfo(name)
  if n2 then return id2, n2 end
  return nil
end

local function SetSlotByName(slotIndex, name)
  if InCombatLockdown() then
    print("|cff00ccffKidsHeal|r: Nicht im Kampf möglich.")
    return
  end
  local id, resolved = SpellIdByName(name)
  if resolved then
    AssignEntry(slotIndex, { kind = "spell", id = id, name = resolved })
  else
    print("|cff00ccffKidsHeal|r: Zauber \"" .. name .. "\" nicht gefunden (exakt so schreiben wie im Zauberbuch).")
  end
end

-- ------------------------------------------------------------------ options panel
-- wrapped in pcall: if anything here fails on an older client, the addon
-- must keep working (bars, clicks, slash command) instead of dying at load
local slotCountSlider = nil
local panel, optionsError = pcall(function()
  local panel = CreateFrame("Frame", "KidsHealOptionsPanel", UIParent)
  panel.name = "KidsHeal"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText("KidsHeal Einstellungen")

  -- scrollable area for all controls
  local scroll = CreateFrame("ScrollFrame", "KidsHealOptionsScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)
  local child = CreateFrame("Frame", "KidsHealOptionsChild", scroll)
  child:SetSize(1, 900)
  scroll:SetScrollChild(child)

  local note = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -6)
  note:SetText("Änderungen greifen sofort außerhalb des Kampfes.")

  local function MakeSlider(label, key, minV, maxV, step, y)
    local sl = CreateFrame("Slider", "KidsHealSlider" .. key, child, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", child, "TOPLEFT", 40, y)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    sl:SetValue(Settings()[key])
    local textLbl = _G[sl:GetName() .. "Text"]
    textLbl:SetText(label .. ": " .. Settings()[key])
    _G[sl:GetName() .. "Low"]:SetText(tostring(minV))
    _G[sl:GetName() .. "High"]:SetText(tostring(maxV))
    if key == "slotCount" then
      -- per-spec: slider shows/edits the current specialization's count
      sl:SetValue(SlotCount())
      textLbl:SetText(label .. ": " .. SlotCount())
      sl:SetScript("OnValueChanged", function(_, v)
        SetSlotCount(v)
        textLbl:SetText(label .. ": " .. math.floor(v))
      end)
    else
      sl:SetScript("OnValueChanged", function(_, v)
        Settings()[key] = v
        textLbl:SetText(label .. ": " .. v)
      end)
    end
    sl:SetScript("OnMouseUp", function()
      RequestRebuild()
    end)
    return sl
  end

  local function MakeCheckbox(label, key, y)
    local cb = CreateFrame("CheckButton", "KidsHealCheck" .. key, child, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", child, "TOPLEFT", 40, y)
    local txt = _G[cb:GetName() .. "Text"]
    txt:SetText(label)
    txt:SetFontObject("GameFontNormalLarge")
    cb:SetChecked(Settings()[key])
    cb:SetScript("OnClick", function(self)
      Settings()[key] = self:GetChecked() or false
      RequestRebuild()
    end)
    return cb
  end

  MakeSlider("Balkenbreite", "barWidth", 50, 400, 10, -80)
  MakeSlider("Balkenhöhe", "barHeight", 24, 80, 2, -130)
  MakeSlider("Icongröße", "iconSize", 20, 80, 2, -180)
  MakeCheckbox("Icons rechts neben den Balken", "iconsRight", -240)
  MakeCheckbox("Lebenspunkte als Text anzeigen", "showHealthText", -280)
  MakeSlider("Namensgröße", "nameFontSize", 8, 24, 1, -330)
  MakeSlider("Zahlengröße (HP)", "hpFontSize", 8, 24, 1, -380)
  MakeSlider("Buffgröße", "buffSize", 12, 32, 2, -430)
  slotCountSlider = MakeSlider("Anzahl Icons (nur diese Spezialisierung)", "slotCount", 1, 10, 1, -480)
  MakeSlider("Abstand zwischen Charakteren", "blockSpacing", 0, 30, 1, -530)
  MakeSlider("Buff-Überlappposition", "buffPadding", -10, 20, 1, -580)
  MakeSlider("Rahmenabstand (Padding)", "barPadding", 0, 16, 1, -630)
  MakeCheckbox("Alle Buffs zeigen (statt nur HoTs/Schilde)", "showAllBuffs", -700)
  MakeCheckbox("Nur meine Zauber zeigen (nur HoTs/Schilde, die ich selbst gecastet habe)", "onlyMyBuffs", -740)
  MakeCheckbox("Fokus-Ziel als eigene Leiste zeigen", "showFocus", -780)

  -- slot + spell dropdown --------------------------------------------
  local ddLabel = child:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  ddLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -800)
  ddLabel:SetText("Zauber per Liste wählen (Slot auswählen, dann Zauber):")

  local slotLabel = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  slotLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 40, -830)
  slotLabel:SetText("Slot:")

  local slotDD = CreateFrame("Frame", "KidsHealSlotDD", child, "UIDropDownMenuTemplate")
  slotDD:SetPoint("TOPLEFT", child, "TOPLEFT", 80, -825)
  UIDropDownMenu_SetWidth(slotDD, 80)
  local curSlot = 1
  local function SlotDDText()
    UIDropDownMenu_SetText(slotDD, "Slot " .. curSlot ..
      (SpellSlots()[curSlot] and " (belegt)" or ""))
  end
  UIDropDownMenu_Initialize(slotDD, function(self, level)
    for i = 1, Settings().slotCount do
      local info = UIDropDownMenu_CreateInfo()
      info.text = "Slot " .. i
      info.checked = (i == curSlot)
      info.func = function()
        curSlot = i
        SlotDDText()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  SlotDDText()

  local spellLabel = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  spellLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 220, -830)
  spellLabel:SetText("Zauber:")

  local spellDD = CreateFrame("Frame", "KidsHealSpellDD", child, "UIDropDownMenuTemplate")
  spellDD:SetPoint("TOPLEFT", child, "TOPLEFT", 280, -825)
  UIDropDownMenu_SetWidth(spellDD, 180)
  UIDropDownMenu_Initialize(spellDD, function(self, level)
    if level == 1 then
      local info = UIDropDownMenu_CreateInfo()
      info.text = "— (Slot leeren) —"
      info.notCheckable = true
      info.func = function()
        if not InCombatLockdown() then
          SpellSlots()[curSlot] = nil
          ApplySlotToAll(curSlot)
          print("|cff00ccffKidsHeal|r: Slot " .. curSlot .. " geleert.")
        end
        SlotDDText()
      end
      UIDropDownMenu_AddButton(info, level)
      info = UIDropDownMenu_CreateInfo()
      info.text = "Zauberbuch"
      info.notCheckable = true
      info.hasArrow = true
      info.value = "BOOK"
      UIDropDownMenu_AddButton(info, level)
    elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "BOOK" then
      for book = 1, 2 do
        local i = 1
        while true do
          local name, _, _, _, _, _, spellId = GetSpellBookItemInfo(i, book)
          if not name then break end
          if spellId and IsSpellKnown(spellId) then
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.notCheckable = true
            info.func = function()
              SetSlotByName(curSlot, name)
              SlotDDText()
            end
            UIDropDownMenu_AddButton(info, level)
          end
          i = i + 1
        end
      end
    end
  end)

  InterfaceOptions_AddCategory(panel)
  return panel
end)

if not panel then
  print("|cff00ccffKidsHeal|r: Optionspanel konnte nicht erstellt werden (" ..
    tostring(optionsError) .. "). /kidsheal funktioniert trotzdem.")
end

-- ------------------------------------------------------------------ events
container:SetScript("OnEvent", function(_, event, unit, a1, a2, a3, a4)
  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- spell slots AND icon count are saved per spec: rebuild + re-sync slider
    RequestRebuild()
    if type(slotCountSlider) == "table" then
      slotCountSlider:SetValue(SlotCount())
      local textLbl = _G[slotCountSlider:GetName() .. "Text"]
      textLbl:SetText("Anzahl Icons (nur diese Spezialisierung): " .. SlotCount())
    end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE"
      or event == "PLAYER_FOCUS_CHANGED" then
    if event == "PLAYER_ENTERING_WORLD" then
      ApplyPosition()
    end
    if event == "PLAYER_FOCUS_CHANGED" then
      -- just refresh visibility/values; the frames exist already
      local m = memberFrames["focus"]
      if m then UpdateMember(m) end
    else
      RequestRebuild()
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if rosterDirty then
      rosterDirty = false
      Rebuild()
      SyncHandleWidth()
    end
  elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
      or event == "UNIT_NAME_UPDATE" then
    local m = memberFrames[unit]
    if m then UpdateHealth(m) end
  elseif event == "UNIT_AURA" then
    local m = memberFrames[unit]
    if m then UpdateBuffs(m) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- args: unit, spellName, rank, lineID, spellId
    HandleSpellPick(unit, a1, nil, a4)
  end
end)
container:RegisterEvent("PLAYER_ENTERING_WORLD")
container:RegisterEvent("GROUP_ROSTER_UPDATE")
container:RegisterEvent("PLAYER_REGEN_ENABLED")
container:RegisterEvent("UNIT_HEALTH")
container:RegisterEvent("UNIT_MAXHEALTH")
container:RegisterEvent("UNIT_NAME_UPDATE")
container:RegisterEvent("UNIT_AURA")
container:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
container:RegisterEvent("PLAYER_FOCUS_CHANGED")
container:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

-- timers: 0.02s cursor polling, 0.25s cooldown/range refresh
local fast = 0
local slow = 0
container:SetScript("OnUpdate", function(_, e)
  fast = fast + e
  if fast >= 0.02 then
    fast = 0
    PollCursor()
  end
  slow = slow + e
  if slow >= 0.25 then
    slow = 0
    for _, m in pairs(memberFrames) do UpdateMember(m) end
  end
end)

-- initial layout
SyncHandleWidth()
print("|cff00ccffKidsHeal|r v1.3.1 geladen. /kidsheal für Hilfe.")

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
    if n and n >= 1 and n <= SlotCount() then
      if not InCombatLockdown() then
        SpellSlots()[n] = nil
        ApplySlotToAll(n)
        print("|cff00ccffKidsHeal|r: Slot " .. n .. " geleert.")
      else
        print("|cff00ccffKidsHeal|r: Nicht im Kampf möglich.")
      end
    else
      print("|cff00ccffKidsHeal|r: /kidsheal clear 1.." .. SlotCount())
    end
  elseif cmd == "set" then
    local n = tonumber(arg)
    local name = msg:match("^set%s+%S+%s+(.+)")
    if name then name = name:gsub("[%[%]]", "") end
    if n and name and n >= 1 and n <= SlotCount() then
      SetSlotByName(n, name)
    else
      print("|cff00ccffKidsHeal|r: /kidsheal set <slot> <Zaubername>, z.B. /kidsheal set 2 [Blitz des Lichts]")
    end
  elseif cmd == "pick" then
    local n = tonumber(arg)
    if n and n >= 1 and n <= SlotCount() then
      StartSpellPick(n)
    else
      pickSlot = nil
      print("|cff00ccffKidsHeal|r: Zauber-Auswahl abgebrochen.")
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
    SyncHandleWidth()
    print("|cff00ccffKidsHeal|r neu aufgebaut.")
  elseif cmd == "options" or cmd == "config" then
    if type(panel) == "table" and panel.name then
      InterfaceOptionsFrame_OpenToCategory(panel)
      InterfaceOptionsFrame_OpenToCategory(panel)
    else
      print("|cff00ccffKidsHeal|r: Optionspanel nicht verfügbar.")
    end
  else
    print("|cff00ccffKidsHeal|r: reset | clear <slot> | set <slot> <Zauber> | test | refresh | debug | options")
  end
end
