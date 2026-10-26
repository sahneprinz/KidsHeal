--[[
  KidsHeal v1.4.0
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

local ADDON_VERSION = "1.4.2"

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

-- ------------------------------------------------------------------ locales
local LOCALES = {
  enUS = {
    notInCombat = "Not possible while in combat.",
    slotSet = function(n, what) return "Slot " .. n .. " = " .. what end,
    slotCleared = function(n) return "Slot " .. n .. " cleared." end,
    clearUsage = function(n) return "/kidsheal clear 1.." .. n end,
    spellPickPrompt = function(n)
      return "Now cast a spell - it will land in slot " .. n ..
        ". (Press Escape or use /kidsheal pick to cancel)"
    end,
    spellPickCancelled = "Spell selection cancelled.",
    spellNotRecognized = "Spell not recognized. Use /kidsheal set.",
    spellNotFound = function(name)
      return "Spell \"" .. name .. "\" not found (write it exactly as in the spellbook)."
    end,
    setUsage = '/kidsheal set <slot> <spell name>, e.g. /kidsheal set 2 [Flash of Light]',
    positionReset = "Position reset (top left).",
    debugState = function(on) return "Debug " .. (on and "ON" or "OFF") ..
      ". Hold a spell on the cursor and watch the chat." end,
    rebuilt = "KidsHeal rebuilt.",
    loaded = function(v) return "KidsHeal v" .. v .. " loaded. /kidsheal for help." end,
    optionsBroken = function(err)
      return "Options panel could not be created (" .. tostring(err) ..
        "). /kidsheal still works." end,
    optionsUnavailable = "Options panel not available.",
    help = "reset | clear <slot> | set <slot> <spell> | test | refresh | debug | options",

    optionsTitle = "KidsHeal Settings",
    optionsNote = "Changes apply immediately outside of combat.",
    barWidth = "Bar width",
    barHeight = "Bar height",
    iconSize = "Icon size",
    iconsRight = "Icons to the right of the bars",
    showHealthText = "Show health points as text",
    nameFontSize = "Name size",
    hpFontSize = "Number size (HP)",
    buffSize = "Buff size",
    slotCountLabel = "Number of icons (current specialization only)",
    blockSpacing = "Spacing between characters",
    buffPadding = "Buff overlap position",
    barPadding = "Frame padding",
    showAllBuffs = "Show all buffs (instead of only HoTs/shields)",
    onlyMyBuffs = "Only show my spells (only HoTs/shields I cast myself)",
    showFocus = "Show focus target as its own bar",
    ddLabel = "Pick a spell from a list (select a slot, then a spell):",
    slotLabel = "Slot:",
    slotTaken = "(taken)",
    spellLabel = "Spell:",
    clearSlot = "— (clear slot) —",
    spellbook = "Spellbook",
    languageLabel = "Language:",
    languageAuto = "Client language (auto)",
    mmTooltipLine1 = "Click: show/hide bars",
    mmTooltipLine2 = "Right-click: settings",
  },
  deDE = {
    notInCombat = "Nicht im Kampf möglich.",
    slotSet = function(n, what) return "Slot " .. n .. " = " .. what end,
    slotCleared = function(n) return "Slot " .. n .. " geleert." end,
    clearUsage = function(n) return "/kidsheal clear 1.." .. n end,
    spellPickPrompt = function(n)
      return "Wirke jetzt einen Zauber - er landet in Slot " .. n ..
        ". (Escape oder /kidsheal pick zum Abbrechen)"
    end,
    spellPickCancelled = "Zauber-Auswahl abgebrochen.",
    spellNotRecognized = "Zauber nicht erkannt. Nutze /kidsheal set.",
    spellNotFound = function(name)
      return "Zauber \"" .. name .. "\" nicht gefunden (exakt so schreiben wie im Zauberbuch)."
    end,
    setUsage = '/kidsheal set <slot> <Zaubername>, z.B. /kidsheal set 2 [Blitz des Lichts]',
    positionReset = "Position zurückgesetzt (oben links).",
    debugState = function(on) return "Debug " .. (on and "AN" or "AUS") ..
      ". Halte einen Zauber im Cursor und schaue in den Chat." end,
    rebuilt = "KidsHeal neu aufgebaut.",
    loaded = function(v) return "KidsHeal v" .. v .. " geladen. /kidsheal für Hilfe." end,
    optionsBroken = function(err)
      return "Optionspanel konnte nicht erstellt werden (" .. tostring(err) ..
        "). /kidsheal funktioniert trotzdem." end,
    optionsUnavailable = "Optionspanel nicht verfügbar.",
    help = "reset | clear <slot> | set <slot> <Zauber> | test | refresh | debug | options",

    optionsTitle = "KidsHeal Einstellungen",
    optionsNote = "Änderungen greifen sofort außerhalb des Kampfes.",
    barWidth = "Balkenbreite",
    barHeight = "Balkenhöhe",
    iconSize = "Icongröße",
    iconsRight = "Icons rechts neben den Balken",
    showHealthText = "Lebenspunkte als Text anzeigen",
    nameFontSize = "Namensgröße",
    hpFontSize = "Zahlengröße (HP)",
    buffSize = "Buffgröße",
    slotCountLabel = "Anzahl Icons (nur diese Spezialisierung)",
    blockSpacing = "Abstand zwischen Charakteren",
    buffPadding = "Buff-Überlappposition",
    barPadding = "Rahmenabstand (Padding)",
    showAllBuffs = "Alle Buffs zeigen (statt nur HoTs/Schilde)",
    onlyMyBuffs = "Nur meine Zauber zeigen (nur HoTs/Schilde, die ich selbst gecastet habe)",
    showFocus = "Fokus-Ziel als eigene Leiste zeigen",
    ddLabel = "Zauber per Liste wählen (Slot auswählen, dann Zauber):",
    slotLabel = "Slot:",
    slotTaken = "(belegt)",
    spellLabel = "Zauber:",
    clearSlot = "— (Slot leeren) —",
    spellbook = "Zauberbuch",
    languageLabel = "Sprache:",
    languageAuto = "Client-Sprache (automatisch)",
    mmTooltipLine1 = "Klick: Leisten zeigen/verstecken",
    mmTooltipLine2 = "Rechtsklick: Einstellungen",
  },
  esMX = {
    notInCombat = "No es posible en combate.",
    slotSet = function(n, what) return "Espacio " .. n .. " = " .. what end,
    slotCleared = function(n) return "Espacio " .. n .. " vaciado." end,
    clearUsage = function(n) return "/kidsheal clear 1.." .. n end,
    spellPickPrompt = function(n)
      return "Lanza ahora un hechizo - irá al espacio " .. n ..
        ". (Escape o /kidsheal pick para cancelar)"
    end,
    spellPickCancelled = "Selección de hechizo cancelada.",
    spellNotRecognized = "Hechizo no reconocido. Usa /kidsheal set.",
    spellNotFound = function(name)
      return "Hechizo \"" .. name .. "\" no encontrado (escríbelo exactamente como en el grimorio)."
    end,
    setUsage = '/kidsheal set <espacio> <nombre del hechizo>, p.ej. /kidsheal set 2 [Luz Sagrada]',
    positionReset = "Posición restablecida (arriba a la izquierda).",
    debugState = function(on) return "Depuración " .. (on and "ACTIVADA" or "DESACTIVADA") ..
      ". Mantén un hechizo en el cursor y observa el chat." end,
    rebuilt = "KidsHeal reconstruido.",
    loaded = function(v) return "KidsHeal v" .. v .. " cargado. /kidsheal para ayuda." end,
    optionsBroken = function(err)
      return "No se pudo crear el panel de opciones (" .. tostring(err) ..
        "). /kidsheal sigue funcionando." end,
    optionsUnavailable = "Panel de opciones no disponible.",
    help = "reset | clear <espacio> | set <espacio> <hechizo> | test | refresh | debug | options",

    optionsTitle = "Ajustes de KidsHeal",
    optionsNote = "Los cambios se aplican inmediatamente fuera de combate.",
    barWidth = "Ancho de la barra",
    barHeight = "Alto de la barra",
    iconSize = "Tamaño de los iconos",
    iconsRight = "Iconos a la derecha de las barras",
    showHealthText = "Mostrar vida como texto",
    nameFontSize = "Tamaño del nombre",
    hpFontSize = "Tamaño de números (vida)",
    buffSize = "Tamaño de los buffs",
    slotCountLabel = "Número de iconos (solo esta especialización)",
    blockSpacing = "Espacio entre personajes",
    buffPadding = "Posición de superposición de buffs",
    barPadding = "Margen interior del marco",
    showAllBuffs = "Mostrar todos los buffs (en vez de solo HoTs/escudos)",
    onlyMyBuffs = "Solo mis hechizos (solo HoTs/escudos lanzados por mí)",
    showFocus = "Mostrar el objetivo de foco como barra propia",
    ddLabel = "Elegir hechizo de una lista (elige espacio, luego hechizo):",
    slotLabel = "Espacio:",
    slotTaken = "(ocupado)",
    spellLabel = "Hechizo:",
    clearSlot = "— (vaciar espacio) —",
    spellbook = "Grimorio",
    languageLabel = "Idioma:",
    languageAuto = "Idioma del cliente (automático)",
    mmTooltipLine1 = "Clic: mostrar/ocultar barras",
    mmTooltipLine2 = "Clic derecho: ajustes",
  },
}

local LOCALE_NAMES = {
  auto = "Client language (auto)",
  enUS = "English",
  deDE = "Deutsch",
  esMX = "Español (Latinoamérica)",
}

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

-- account-level language preference: one choice for every character on
-- this WoW account (each WoW account has its own SavedVariables file).
-- SavedVariables load AFTER .lua files, so KidsHealDB may still be nil
-- at addon load time - every access must go through these safe helpers.
local function GetAccountLocale()
  return (type(KidsHealDB) == "table") and KidsHealDB.locale or nil
end

local function SetAccountLocale(code)
  Profile().locale = nil
  if type(KidsHealDB) ~= "table" then KidsHealDB = {} end
  KidsHealDB.locale = code
end

local function ActiveLocale()
  local want = GetAccountLocale()
  if want and LOCALES[want] then return want end
  local cl = GetLocale()
  if LOCALES[cl] then return cl end
  if cl == "deDE" then return "deDE" end
  if cl == "esES" or cl == "esMX" then return "esMX" end
  return "enUS"
end

local function L(key)
  local loc = LOCALES[ActiveLocale()]
  local v = loc[key] or LOCALES.enUS[key]
  if type(v) == "function" then return v end
  return v
end

local function LF(key, ...)
  local v = L(key)
  if type(v) == "function" then return v(...) end
  return v
end

local function LMsg(key, ...)
  print("|cff00ccffKidsHeal|r: " .. LF(key, ...))
end

local function SpellSlots()
  local p = Profile()
  local spec = GetSpecialization() or 1
  if type(p.specSpells[spec]) ~= "table" then p.specSpells[spec] = {} end
  return p.specSpells[spec]
end

-- per-spec enabled state (minimap button toggle). Defaults to ON for
-- new characters/specs; remembered per character + spec across logins.
local function SpecEnabled()
  local p = Profile()
  local spec = GetSpecialization() or 1
  if type(p.specEnabled) ~= "table" then p.specEnabled = {} end
  local v = p.specEnabled[spec]
  if v == nil then v = true end
  return v
end

local function SetSpecEnabled(v)
  local p = Profile()
  local spec = GetSpecialization() or 1
  if type(p.specEnabled) ~= "table" then p.specEnabled = {} end
  p.specEnabled[spec] = v and true or false
end

local function ApplySpecEnabled()
  if SpecEnabled() then
    container:Show()
  else
    container:Hide()
  end
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
    LMsg("notInCombat")
    return
  end
  SpellSlots()[slotIndex] = rawEntry
  ApplySlotToAll(slotIndex)
  local r = ResolveEntry(rawEntry)
  LMsg("slotSet", slotIndex, r and r.name or "?")
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

-- re-stack all visible member bars top-down; the panel height follows.
-- order: tanks first, then healers, then everyone else; focus always last.
-- called after every visibility change so the focus bar sits directly
-- after the last present member instead of at a fixed position.
local allUnits = { "player", "party1", "party2", "party3", "party4", "focus" }
local function Relayout()
  local s = Settings()
  local _, blockH = BlockSize()

  local roleRank = { TANK = 1, HEALER = 2 }
  local function rank(unit)
    if unit == "focus" then return 9 end
    return roleRank[UnitGroupRolesAssigned(unit)] or 3
  end

  local position = {}
  for i, unit in ipairs(allUnits) do position[unit] = i end
  local visibleUnits = {}
  for _, unit in ipairs(allUnits) do
    local m = memberFrames[unit]
    if m and m.main:IsShown() then visibleUnits[#visibleUnits + 1] = unit end
  end
  table.sort(visibleUnits, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    return position[a] < position[b]
  end)

  local y = 12
  for _, unit in ipairs(visibleUnits) do
    local m = memberFrames[unit]
    m.main:ClearAllPoints()
    m.main:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
    y = y + blockH + s.blockSpacing
  end
  local n = #visibleUnits
  container:SetHeight(12 + n * blockH + math.max(n - 1, 0) * s.blockSpacing)
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
    LMsg("notInCombat")
    return
  end
  pickSlot = slotIndex
  LMsg("spellPickPrompt", slotIndex)
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
    LMsg("spellNotRecognized")
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

    member.buttons[i] = btn
  end

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
  container:SetWidth(blockW)
  for i = 1, SlotCount() do ApplySlotToAll(i) end
  for _, m in pairs(memberFrames) do UpdateMember(m) end
  Relayout()
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

local panel  -- options panel frame (created further below in a pcall)

-- ------------------------------------------------------------------ minimap button
-- standard LDB + LibDBIcon approach (same as HealBot): the library draws
-- the classic round button, handles circular dragging and saves the
-- position per character. Left-click toggles the panel.
local ldb = LibStub("LibDataBroker-1.1")
local iconLib = LibStub("LibDBIcon-1.0", true)

if ldb and iconLib then
  local kidsHealLDB = ldb:NewDataObject("KidsHeal", {
    type = "data source",
    text = "KidsHeal",
    icon = "Interface\\Icons\\Spell_Holy_Renew",
    OnClick = function(self, button)
      if button == "LeftButton" then
        SetSpecEnabled(not SpecEnabled())
        ApplySpecEnabled()
      elseif button == "RightButton" then
        if type(panel) == "table" and panel.name then
          InterfaceOptionsFrame_OpenToCategory(panel)
          InterfaceOptionsFrame_OpenToCategory(panel)
        end
      end
    end,
    OnTooltipShow = function(tooltip)
      if not tooltip or not tooltip.AddLine then return end
      tooltip:AddLine("KidsHeal")
      tooltip:AddLine(L("mmTooltipLine1"), 1, 1, 1)
      tooltip:AddLine(L("mmTooltipLine2"), 1, 1, 1)
    end,
  })

  local mmFrame = CreateFrame("Frame")
  mmFrame:RegisterEvent("PLAYER_LOGIN")
  mmFrame:SetScript("OnEvent", function(self)
    local p = Profile()
    if type(p.minimap) ~= "table" then p.minimap = { hide = false } end
    iconLib:Register("KidsHeal", kidsHealLDB, p.minimap)
    self:UnregisterEvent("PLAYER_LOGIN")
  end)
end

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
    LMsg("notInCombat")
    return
  end
  local id, resolved = SpellIdByName(name)
  if resolved then
    AssignEntry(slotIndex, { kind = "spell", id = id, name = resolved })
  else
    LMsg("spellNotFound", name)
  end
end

-- ------------------------------------------------------------------ options panel
-- wrapped in pcall: if anything here fails on an older client, the addon
-- must keep working (bars, clicks, slash command) instead of dying at load
local slotCountSlider = nil
local refreshLangDD = nil
local optionsError
panel = select(2, pcall(function()
  local panel = CreateFrame("Frame", "KidsHealOptionsPanel", UIParent)
  panel.name = "KidsHeal"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText(L("optionsTitle"))

  -- scrollable area for all controls
  local scroll = CreateFrame("ScrollFrame", "KidsHealOptionsScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)
  local child = CreateFrame("Frame", "KidsHealOptionsChild", scroll)
  child:SetSize(1, 1010)
  scroll:SetScrollChild(child)

  local note = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -6)
  note:SetText(L("optionsNote"))

  -- language dropdown ----------------------------------------------
  local langLabel = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  langLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -70)
  langLabel:SetText(L("languageLabel"))
  local langDD = CreateFrame("Frame", "KidsHealLanguageDD", child, "UIDropDownMenuTemplate")
  langDD:SetPoint("TOPLEFT", child, "TOPLEFT", 120, -65)
  UIDropDownMenu_SetWidth(langDD, 200)
  local langOrder = { "auto", "enUS", "deDE", "esMX" }
  local RefreshOptionsText  -- forward declaration, defined further below
  local function LangDDText()
    local cur = GetAccountLocale() or "auto"
    if cur == "auto" then
      UIDropDownMenu_SetText(langDD, L("languageAuto") .. " — " .. LOCALE_NAMES[ActiveLocale()])
    else
      UIDropDownMenu_SetText(langDD, LOCALE_NAMES[cur] or cur)
    end
  end
  refreshLangDD = LangDDText
  UIDropDownMenu_Initialize(langDD, function(self, level)
    for _, code in ipairs(langOrder) do
      local info = UIDropDownMenu_CreateInfo()
      if code == "auto" then
        info.text = L("languageAuto")
      else
        info.text = LOCALE_NAMES[code]
      end
      info.checked = ((GetAccountLocale() or "auto") == code)
      info.func = function()
        SetAccountLocale((code ~= "auto") and code or nil)
        RefreshOptionsText()
        LangDDText()
        RequestRebuild()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  -- controls: localized labels; the language dropdown rewrites all texts
  local sliderLabels = {}
  local checkboxLabels = {}

  local function MakeSlider(labelKey, key, minV, maxV, step, y)
    local sl = CreateFrame("Slider", "KidsHealSlider" .. key, child, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", child, "TOPLEFT", 40, y)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    sl:SetValue(Settings()[key])
    local textLbl = _G[sl:GetName() .. "Text"]
    local lowLbl = _G[sl:GetName() .. "Low"]
    local highLbl = _G[sl:GetName() .. "High"]
    sliderLabels[key] = { slider = sl, text = textLbl, labelKey = labelKey }
    local function LabelText(v)
      return L(labelKey) .. ": " .. (key == "slotCount" and math.floor(v) or v)
    end
    textLbl:SetText(LabelText(Settings()[key]))
    lowLbl:SetText(tostring(minV))
    highLbl:SetText(tostring(maxV))
    if key == "slotCount" then
      -- per-spec: slider shows/edits the current specialization's count.
      -- the default template centers the label over the slider, which would
      -- overflow the panel edge with this long text - left-anchor it instead.
      textLbl:ClearAllPoints()
      textLbl:SetPoint("BOTTOMLEFT", sl, "TOPLEFT", 0, 3)
      textLbl:SetJustifyH("LEFT")
      sl:SetValue(SlotCount())
      textLbl:SetText(LabelText(SlotCount()))
      sl:SetScript("OnValueChanged", function(_, v)
        SetSlotCount(v)
        textLbl:SetText(LabelText(v))
      end)
    else
      sl:SetScript("OnValueChanged", function(_, v)
        Settings()[key] = v
        textLbl:SetText(LabelText(v))
      end)
    end
    sl:SetScript("OnMouseUp", function()
      RequestRebuild()
    end)
    return sl
  end

  local function MakeCheckbox(labelKey, key, y)
    local cb = CreateFrame("CheckButton", "KidsHealCheck" .. key, child, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", child, "TOPLEFT", 40, y)
    local txt = _G[cb:GetName() .. "Text"]
    txt:SetText(L(labelKey))
    checkboxLabels[key] = { text = txt, labelKey = labelKey }
    txt:SetFontObject("GameFontNormalLarge")
    cb:SetChecked(Settings()[key])
    cb:SetScript("OnClick", function(self)
      Settings()[key] = self:GetChecked() or false
      RequestRebuild()
    end)
    return cb
  end

  MakeSlider("barWidth", "barWidth", 50, 400, 10, -130)
  MakeSlider("barHeight", "barHeight", 24, 80, 2, -180)
  MakeSlider("iconSize", "iconSize", 20, 80, 2, -230)
  MakeCheckbox("iconsRight", "iconsRight", -290)
  MakeCheckbox("showHealthText", "showHealthText", -330)
  MakeSlider("nameFontSize", "nameFontSize", 8, 24, 1, -380)
  MakeSlider("hpFontSize", "hpFontSize", 8, 24, 1, -430)
  MakeSlider("buffSize", "buffSize", 12, 32, 2, -480)
  slotCountSlider = MakeSlider("slotCountLabel", "slotCount", 1, 10, 1, -530)
  MakeSlider("blockSpacing", "blockSpacing", 0, 30, 1, -580)
  MakeSlider("buffPadding", "buffPadding", -10, 20, 1, -630)
  MakeSlider("barPadding", "barPadding", 0, 16, 1, -680)
  MakeCheckbox("showAllBuffs", "showAllBuffs", -750)
  MakeCheckbox("onlyMyBuffs", "onlyMyBuffs", -790)
  MakeCheckbox("showFocus", "showFocus", -830)

  -- slot + spell dropdown --------------------------------------------
  local ddLabel = child:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  ddLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -910)
  ddLabel:SetText(L("ddLabel"))

  local slotLabel = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  slotLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 40, -945)
  slotLabel:SetText(L("slotLabel"))

  local slotDD = CreateFrame("Frame", "KidsHealSlotDD", child, "UIDropDownMenuTemplate")
  slotDD:SetPoint("TOPLEFT", child, "TOPLEFT", 90, -940)
  UIDropDownMenu_SetWidth(slotDD, 80)
  local curSlot = 1
  local function SlotDDText()
    UIDropDownMenu_SetText(slotDD, L("slotLabel") .. " " .. curSlot ..
      (SpellSlots()[curSlot] and " " .. L("slotTaken") or ""))
  end
  UIDropDownMenu_Initialize(slotDD, function(self, level)
    for i = 1, Settings().slotCount do
      local info = UIDropDownMenu_CreateInfo()
      info.text = L("slotLabel") .. " " .. i
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
  spellLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 220, -945)
  spellLabel:SetText(L("spellLabel"))

  local spellDD = CreateFrame("Frame", "KidsHealSpellDD", child, "UIDropDownMenuTemplate")
  spellDD:SetPoint("TOPLEFT", child, "TOPLEFT", 290, -940)
  UIDropDownMenu_SetWidth(spellDD, 180)
  UIDropDownMenu_Initialize(spellDD, function(self, level)
    if level == 1 then
      local info = UIDropDownMenu_CreateInfo()
      info.text = L("clearSlot")
      info.notCheckable = true
      info.func = function()
        if not InCombatLockdown() then
          SpellSlots()[curSlot] = nil
          ApplySlotToAll(curSlot)
          LMsg("slotCleared", curSlot)
        end
        SlotDDText()
      end
      UIDropDownMenu_AddButton(info, level)
      info = UIDropDownMenu_CreateInfo()
      info.text = L("spellbook")
      info.notCheckable = true
      info.hasArrow = true
      info.value = "BOOK"
      UIDropDownMenu_AddButton(info, level)
    elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "BOOK" then
      -- Legion's GetSpellBookItemInfo takes a string book type, not a number
      for _, bookType in ipairs({ "spell", "pet" }) do
        local i = 1
        while true do
          local name, _, _, _, _, _, spellId, _, isPassive = GetSpellBookItemInfo(i, bookType)
          if not name then break end
          if spellId and not isPassive and IsSpellKnown(spellId)
            and IsSpellKnown(spellId) ~= false then
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

  -- rewrite all localized texts after a language switch
  function RefreshOptionsText()
    title:SetText(L("optionsTitle"))
    note:SetText(L("optionsNote"))
    langLabel:SetText(L("languageLabel"))
    for key, ref in pairs(sliderLabels) do
      local v = (key == "slotCount") and SlotCount() or Settings()[key]
      ref.text:SetText(L(ref.labelKey) .. ": " ..
        (key == "slotCount" and math.floor(v) or v))
    end
    for _, ref in pairs(checkboxLabels) do
      ref.text:SetText(L(ref.labelKey))
    end
    ddLabel:SetText(L("ddLabel"))
    slotLabel:SetText(L("slotLabel"))
    spellLabel:SetText(L("spellLabel"))
    SlotDDText()
  end

  InterfaceOptions_AddCategory(panel)
  return panel
end))

if not panel then
  print("|cff00ccffKidsHeal|r: " .. LF("optionsBroken", optionsError))
end

-- ------------------------------------------------------------------ events
container:SetScript("OnEvent", function(_, event, unit, a1, a2, a3, a4)
  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- spell slots, icon count AND enabled state are saved per spec
    RequestRebuild()
    ApplySpecEnabled()
    if type(slotCountSlider) == "table" then
      slotCountSlider:SetValue(SlotCount())
      local textLbl = _G[slotCountSlider:GetName() .. "Text"]
      textLbl:SetText(L("slotCountLabel") .. ": " .. SlotCount())
    end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE"
      or event == "PLAYER_FOCUS_CHANGED" then
    if event == "PLAYER_ENTERING_WORLD" then
      ApplyPosition()
      ApplySpecEnabled()
      -- SavedVariables are loaded by now: re-sync the language dropdown
      -- (it was built before KidsHealDB existed)
      if type(refreshLangDD) == "function" then refreshLangDD() end
    end
    if event == "PLAYER_FOCUS_CHANGED" then
      -- refresh visibility/values, then re-stack the bars
      for _, m in pairs(memberFrames) do UpdateMember(m) end
      Relayout()
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
print("|cff00ccffKidsHeal|r " .. LF("loaded", ADDON_VERSION))

-- ------------------------------------------------------------------ slash
SLASH_KIDSHEAL1 = "/kidsheal"
SlashCmdList["KIDSHEAL"] = function(msg)
  local cmd, arg = msg:match("(%S+)%s*(%S*)")
  cmd = cmd and cmd:lower() or ""
  if cmd == "reset" then
    local p = Profile()
    p.x, p.y = DEFAULT_POS.x, DEFAULT_POS.y
    ApplyPosition()
    LMsg("positionReset")
  elseif cmd == "clear" then
    local n = tonumber(arg)
    if n and n >= 1 and n <= SlotCount() then
      if not InCombatLockdown() then
        SpellSlots()[n] = nil
        ApplySlotToAll(n)
        LMsg("slotCleared", n)
      else
        LMsg("notInCombat")
      end
    else
      LMsg("clearUsage", SlotCount())
    end
  elseif cmd == "set" then
    local n = tonumber(arg)
    local name = msg:match("^set%s+%S+%s+(.+)")
    if name then name = name:gsub("[%[%]]", "") end
    if n and name and n >= 1 and n <= SlotCount() then
      SetSlotByName(n, name)
    else
      LMsg("setUsage")
    end
  elseif cmd == "pick" then
    local n = tonumber(arg)
    if n and n >= 1 and n <= SlotCount() then
      StartSpellPick(n)
    else
      pickSlot = nil
      LMsg("spellPickCancelled")
    end
  elseif cmd == "debug" then
    DEBUG = not DEBUG
    LMsg("debugState", DEBUG)
  elseif cmd == "test" then
    for _, m in pairs(memberFrames) do
      m.healthBar:SetValue(math.random(30, 100) / 100 * math.max(UnitHealthMax(m.unit), 1))
    end
  elseif cmd == "refresh" then
    RequestRebuild()
    SyncHandleWidth()
    LMsg("rebuilt")
  elseif cmd == "options" or cmd == "config" then
    if type(panel) == "table" and panel.name then
      InterfaceOptionsFrame_OpenToCategory(panel)
      InterfaceOptionsFrame_OpenToCategory(panel)
    else
      LMsg("optionsUnavailable")
    end
  else
    LMsg("help")
  end
end
