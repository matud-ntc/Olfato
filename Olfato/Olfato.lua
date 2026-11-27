local addonName = ...

local RC = LibStub("LibRangeCheck-3.0")

local DEFAULTS = { enabled = true, tooltip = true, sound = false, targetDistance = true, alertRange = 0, plateDistance = 41 }
local TICK = 0.2
-- How much earlier than the aggro radius each step lights up (yards).
local WARN_FAR, WARN_NEAR = 10, 5

local COLORS = {
  { 1.00, 0.82, 0.00 }, -- peligroso
  { 1.00, 0.50, 0.00 }, -- muy cerca
  { 1.00, 0.15, 0.10 }, -- inevitable
}

local SPANISH = GetLocale():sub(1, 2) == "es"
local YD = SPANISH and " m" or " yd"

local L = SPANISH and {
  enabled = "Puntos de aggro", tooltip = "Radio de aggro en el tooltip", sound = "Sonido de alarma",
  targetDistance = "Distancia al objetivo", alertRange = "Avisar a",
  test = "Probar",
} or {
  enabled = "Aggro dots", tooltip = "Aggro radius in tooltips", sound = "Alarm sound",
  targetDistance = "Distance to target", alertRange = "Alert within",
  test = "Test",
}

local BACKUP_UNITS = { "target", "mouseover", "softenemy" }

local db
local testing = false
local units = {}      -- nameplate unit token -> true
local indicators = {} -- nameplate frame -> indicator
local lastLevel = {}  -- unit token -> level shown

-- 12.x clients can hand addons "secret" values; treat them as unknown instead of erroring.
local function Public(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- Vanilla rule: 20 yd at the same level, -1 yd per level you're above the mob
-- (+1 per level below, counting at most 25), never under 5 yd.
local function AggroRadius(unit)
  local player = Public(UnitLevel("player")) or 1
  local level = Public(UnitLevel(unit))
  if not level or level <= 0 then level = player + 10 end -- "??" bosses
  local diff = math.max(player - level, -25)
  return math.max(20 - diff, 5)
end

local function Threatens(unit)
  if not Public(UnitExists(unit)) or Public(UnitIsDeadOrGhost(unit)) then return false end
  if Public(UnitIsPlayer(unit)) or not Public(UnitCanAttack("player", unit)) then return false end
  if Public(UnitAffectingCombat(unit)) then return false end -- already busy (maybe with you)
  local reaction = Public(UnitReaction(unit, "player"))
  return reaction ~= nil and reaction <= 3 -- yellow (neutral) mobs never start a fight
end

-- /olf debug: records what each check returned (saved on /reload), "S" = secret value.
local traced = {}
local function V(v)
  if issecretvalue and issecretvalue(v) then return "S" end
  return tostring(v)
end
local function Trace(unit)
  if (traced[unit] or 0) > GetTime() - 1 or UnitIsPlayer(unit) == true then return end
  traced[unit] = GetTime()
  local minR, maxR = RC:GetRange(unit)
  local line = table.concat({
    date("%H:%M:%S"), unit,
    "ex=" .. V(UnitExists(unit)), "dead=" .. V(UnitIsDeadOrGhost(unit)), "pl=" .. V(UnitIsPlayer(unit)),
    "atk=" .. V(UnitCanAttack("player", unit)), "cmb=" .. V(UnitAffectingCombat(unit)),
    "rea=" .. V(UnitReaction(unit, "player")), "lvl=" .. V(UnitLevel(unit)) .. "/" .. V(UnitLevel("player")),
    "rng=" .. V(minR) .. "-" .. V(maxR), "harmRC=" .. #(RC.harmRC or {}),
    "item5=" .. V(C_Item.IsItemInRange(8149, unit)), "int3=" .. V(CheckInteractDistance(unit, 3)),
    "plate=" .. (C_NamePlate.GetNamePlateForUnit(unit) and "y" or "n"),
  }, " ")
  local t = db.trace
  table.insert(t, line)
  if #t > 120 then table.remove(t, 1) end
end

local function DangerLevel(unit)
  if db.trace then pcall(Trace, unit) end
  if not Threatens(unit) then return 0 end
  local minRange, maxRange = RC:GetRange(unit)
  minRange, maxRange = Public(minRange), Public(maxRange)
  if not minRange then return 0 end
  local estimate = maxRange and (minRange + maxRange) / 2 or minRange + 2.5
  local margin = estimate - AggroRadius(unit)
  if margin <= 0 then return 3 end
  if margin <= WARN_NEAR then return 2 end
  if margin <= WARN_FAR then return 1 end
  return 0
end

local function NewIndicator(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(30, 8)
  f.dots = {}
  for i = 1, 3 do
    local dot = f:CreateTexture(nil, "OVERLAY")
    dot:SetSize(7, 7)
    dot:SetPoint("LEFT", f, "LEFT", (i - 1) * 10 + 1, 0)
    dot:SetColorTexture(1, 1, 1)
    local mask = f:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(dot)
    dot:AddMaskTexture(mask)
    f.dots[i] = dot
  end
  local pulse = f:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.35)
  fade:SetDuration(0.45)
  f.pulse = pulse
  f:Hide()
  return f
end

local function Show(plate, level)
  local f = indicators[plate]
  if level == 0 then
    if f then f:Hide(); f.pulse:Stop() end
    return
  end
  if not f then
    f = NewIndicator(plate)
    f:SetPoint("BOTTOM", plate, "TOP", 0, -2)
    f:SetFrameLevel(plate:GetFrameLevel() + 10)
    indicators[plate] = f
  end
  local r, g, b = unpack(COLORS[level])
  for i, dot in ipairs(f.dots) do
    if i <= level then
      dot:SetVertexColor(r, g, b, 0.95)
    else
      dot:SetVertexColor(0, 0, 0, 0.35)
    end
  end
  if level == 3 then
    if not f.pulse:IsPlaying() then f.pulse:Play() end
  else
    f.pulse:Stop()
  end
  f:Show()
end

-- Forever doesn't let addons touch enemy NPC nameplates (they arrive as "forbidden"),
-- so mobs without a usable plate are summed up in a small indicator under your character.
local hud
local function Hud()
  if hud then return hud end
  hud = CreateFrame("Frame", "OlfatoHUD", UIParent)
  hud:SetSize(30, 8)
  hud:SetPoint("CENTER", UIParent, "CENTER", 0, -110)
  hud.inner = NewIndicator(hud)
  hud.inner:SetAllPoints(hud)
  hud.name = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hud.name:SetPoint("TOP", hud, "BOTTOM", 0, -2)
  hud.name:SetTextColor(0.8, 0.8, 0.8)
  return hud
end

local function ShowHud(level, unit)
  local h = Hud()
  indicators[h] = h.inner
  Show(h, level)
  local name = unit and Public(UnitName(unit))
  h.name:SetText(level > 0 and name or "")
end

-- Distance to your target, as the band LibRangeCheck can tell apart ("20-25"): the client
-- doesn't give addons the exact distance to NPCs. Sits over the target portrait.
local distance
local function TargetAnchor()
  if TargetFrame and TargetFrame:IsVisible() then
    local container = TargetFrame.TargetFrameContainer
    return TargetFrame.portrait or TargetFramePortrait or (container and container.Portrait) or TargetFrame, "BOTTOM", "TOP", 0, 10
  end
  return Hud(), "TOP", "BOTTOM", 0, -16 -- unit frames replaced by another addon: under the aggro dots
end

local GREY, GREEN = { 0.85, 0.85, 0.85 }, { 0.3, 1, 0.3 }

-- Your own spells whose range is exactly the "Alert within" number. LibRangeCheck only asks
-- a fixed list per class, so a hunter's 41 yd Auto Shot (35 + Hawk Eye) may not be a cut there;
-- asking the spell itself makes that number exact and splits the band around it.
local rangeSpells = {}

local function SpellRange(id)
  local minRange, maxRange
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if info then minRange, maxRange = info.minRange, info.maxRange end
  elseif GetSpellInfo then
    minRange, maxRange = select(5, GetSpellInfo(id))
  end
  minRange, maxRange = Public(minRange), Public(maxRange)
  if not maxRange then return end
  return math.floor((minRange or 0) + 0.5), math.floor(maxRange + 0.5)
end

local function FindRangeSpells()
  wipe(rangeSpells)
  local range = db.alertRange
  if range <= 0 then return end
  local book = C_SpellBook and C_SpellBook.GetSpellBookItemInfo
  local lines = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines()
    or GetNumSpellTabs and GetNumSpellTabs() or 0
  local last = 0
  for line = 1, lines do
    local offset, count
    if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo then
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      if info then offset, count = info.itemIndexOffset, info.numSpellBookItems end
    else
      offset, count = select(3, GetSpellTabInfo(line))
    end
    if offset and count then last = math.max(last, offset + count) end
  end
  for index = 1, last do
    local id
    if book then
      local info = book(index, Enum.SpellBookSpellBank.Player)
      if info and info.itemType == Enum.SpellBookItemType.Spell and not info.isPassive and not info.isOffSpec then
        id = info.spellID
      end
    else
      local kind, spellID = GetSpellBookItemInfo(index, BOOKTYPE_SPELL or "spell")
      if kind == "SPELL" then id = spellID end
    end
    local minRange, maxRange
    if id then minRange, maxRange = SpellRange(id) end
    if maxRange == range then
      rangeSpells[#rangeSpells + 1] = { id = id, index = index, minRange = minRange }
    end
  end
end

-- true/false from the first of those spells that can be used on the target, nil if none can.
local function SpellSays(unit, bandMin)
  for _, spell in ipairs(rangeSpells) do
    local answer
    if C_Spell and C_Spell.IsSpellInRange then
      answer = Public(C_Spell.IsSpellInRange(spell.id, unit))
    elseif IsSpellInRange then
      local r = Public(IsSpellInRange(spell.index, BOOKTYPE_SPELL or "spell", unit))
      if r == 1 then answer = true elseif r == 0 then answer = false end
    end
    if answer == true then return true end
    -- "No" from a spell with a dead zone (Auto Shot under 8 yd) may just mean too close.
    if answer == false and bandMin >= spell.minRange then return false end
  end
end

local function UpdateDistance()
  if not distance then
    distance = CreateFrame("Frame", "OlfatoDistance", UIParent)
    distance:SetSize(60, 12)
    distance:SetFrameStrata("HIGH")
    distance.text = distance:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distance.text:SetPoint("CENTER")
  end
  local minR, maxR
  if db.targetDistance and Public(UnitExists("target")) and not Public(UnitIsUnit("target", "player")) then
    minR, maxR = RC:GetRange("target")
    minR, maxR = Public(minR), Public(maxR)
  end
  if not minR then
    distance:Hide()
    return
  end
  local anchor, point, relative, x, y = TargetAnchor()
  if anchor ~= distance.anchor then
    distance.anchor = anchor
    distance:ClearAllPoints()
    distance:SetPoint(point, anchor, relative, x, y)
  end
  local alert = db.alertRange
  local inRange = alert > 0 and maxR and maxR <= alert or false
  if alert > 0 and not inRange and (not maxR or maxR > alert) then
    local says = SpellSays("target", minR)
    if says == true then
      inRange, maxR = true, alert
      if minR > alert then minR = alert end
    elseif says == false and minR < alert then
      minR = alert
    end
  end
  -- Without a spell to ask, green only when the whole band is inside: "30-35" with 33 might not be.
  distance.text:SetText(maxR and (minR == maxR and minR or minR .. "-" .. maxR) or (minR .. "+"))
  distance.text:SetTextColor(unpack(inRange and GREEN or GREY))
  distance:Show()
end

local function Update()
  if not db.enabled or testing then return end
  local alarm = false
  local worst, worstUnit = 0, nil
  local seenTarget = false
  for unit in pairs(units) do
    local level = DangerLevel(unit)
    if level == 3 and (lastLevel[unit] or 0) < 3 then alarm = true end
    lastLevel[unit] = level
    if UnitIsUnit(unit, "target") == true then seenTarget = true end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then
      Show(plate, level)
    elseif level > worst then
      worst, worstUnit = level, unit
    end
  end
  -- Backups for mobs the game never reported through a nameplate: whatever you have
  -- targeted, under the mouse, or soft-targeted. Normally the nameplates cover everything.
  if not seenTarget then
    for _, unit in ipairs(BACKUP_UNITS) do
      if UnitExists(unit) == true then
        local level = DangerLevel(unit)
        if level == 3 and (lastLevel[unit] or 0) < 3 then alarm = true end
        lastLevel[unit] = level
        if level > worst then worst, worstUnit = level, unit end
      end
    end
  end
  ShowHud(worst, worstUnit)
  if alarm and db.sound then PlaySound(SOUNDKIT.TELL_MESSAGE or 3081, "SFX") end
end

local function HideAll()
  for _, f in pairs(indicators) do f:Hide(); f.pulse:Stop() end
  wipe(lastLevel)
end

local function Tick()
  db.stats.ticks = db.stats.ticks + 1
  Update()
  UpdateDistance()
end

-- Nameplates only exist up to this distance; the default can be closer than the aggro radius.
-- A /reload in combat can't change it, so it waits for the fight to end.
local platesPending = false
local function ApplyPlates()
  if InCombatLockdown() then platesPending = true return end
  platesPending = false
  local current = tonumber(GetCVar("nameplateMaxDistance") or "")
  if current and db.plateDistance and current < db.plateDistance then
    pcall(SetCVar, "nameplateMaxDistance", db.plateDistance)
  end
end

local function AddTooltipLine(tooltip)
  if tooltip ~= GameTooltip or not db.tooltip then return end
  local _, unit = tooltip:GetUnit()
  unit = Public(unit)
  if not unit or not Public(UnitCanAttack("player", unit)) or Public(UnitIsPlayer(unit)) then return end
  local reaction = Public(UnitReaction(unit, "player"))
  if not reaction or reaction > 3 or Public(UnitIsDeadOrGhost(unit)) then return end
  tooltip:AddLine("|cff999999Aggro " .. AggroRadius(unit) .. YD .. "|r")
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff9933Olfato:|r " .. msg)
end

-- Plays the three steps and the alarm so you know what to look for.
local function RunTest()
  testing = true
  for level = 1, 3 do
    C_Timer.After(level - 1, function()
      ShowHud(level, UnitExists("target") and "target" or "player")
      if level == 3 then PlaySound(SOUNDKIT.TELL_MESSAGE or 3081, "SFX") end
    end)
  end
  C_Timer.After(5, function() testing = false; ShowHud(0) end)
end

local OPTIONS = { "enabled", "tooltip", "sound", "targetDistance" }

local function SetOption(key, on)
  db[key] = on
  if key == "enabled" and not on then HideAll() end
  if key == "targetDistance" then UpdateDistance() end
end

-- The same checks go in the /olf window and in Settings > AddOns; each one reads the
-- saved values again when it's shown.
local function AddChecks(parent, x, y)
  local checks = {}
  for i, key in ipairs(OPTIONS) do
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - (i - 1) * 26)
    local label = cb.Text or cb.text
    if not label then
      label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    label:SetFontObject("GameFontHighlight")
    label:SetText(L[key])
    cb:SetScript("OnClick", function(self) SetOption(key, self:GetChecked() and true or false) end)
    checks[key] = cb
  end

  -- Your own range (a spell's, say): the distance turns green once the target is surely inside it.
  -- Empty is off.
  local rowY = y - #OPTIONS * 26 - 4
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, rowY)
  label:SetText(L.alertRange)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(34, 20)
  box:SetPoint("LEFT", label, "RIGHT", 10, 0)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(3)
  box:SetJustifyH("CENTER")
  local unit = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  unit:SetPoint("LEFT", box, "RIGHT", 4, 0)
  unit:SetText(strtrim(YD))
  -- The spell that makes that number exact, if you have one.
  local icon = CreateFrame("Frame", nil, parent)
  icon:SetSize(18, 18)
  icon:SetPoint("LEFT", unit, "RIGHT", 8, 0)
  icon.texture = icon:CreateTexture(nil, "ARTWORK")
  icon.texture:SetAllPoints(icon)
  icon:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.spell)
    GameTooltip:Show()
  end)
  icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local function Refresh()
    box:SetText(db.alertRange > 0 and db.alertRange or "")
    local spell = rangeSpells[1]
    local texture = spell and (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.id)
      or GetSpellTexture and GetSpellTexture(spell.id))
    icon.spell = spell and spell.id
    icon.texture:SetTexture(texture)
    icon:SetShown(texture ~= nil)
  end
  local function Save()
    db.alertRange = tonumber(box:GetText()) or 0
    FindRangeSpells()
    Refresh()
    UpdateDistance()
  end
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(self) Refresh(); self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", Save)

  local test = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  test:SetSize(90, 22)
  test:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, rowY - 30)
  test:SetText(L.test)
  test:SetScript("OnClick", RunTest)
  parent:HookScript("OnShow", function()
    for key, cb in pairs(checks) do cb:SetChecked(db[key] and true or false) end
    Refresh()
  end)
  return checks, box
end

local window
local function ToggleWindow()
  if not window then
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    if not ok then
      f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
      f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(0, 0, 0, 0.9)
      local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
      close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    end
    window = f
    _G.OlfatoOptions = f
    tinsert(UISpecialFrames, "OlfatoOptions") -- Esc closes it
    f:SetSize(260, 206)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f.TitleText
    if not title then
      title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      title:SetPoint("TOP", f, "TOP", 0, -6)
    end
    title:SetText("Olfato")
    f:Hide()
    AddChecks(f, 14, -32)
  end
  window:SetShown(not window:IsShown())
end

local function RegisterSettings()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local panel = CreateFrame("Frame")
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText("Olfato")
  AddChecks(panel, 14, -48)
  local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Olfato")
  if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == addonName then
    OlfatoDB = OlfatoDB or {}
    -- Before 0.2.0 "/olf off" also hid the tooltip line.
    if OlfatoDB.tooltip == nil and OlfatoDB.enabled == false then OlfatoDB.tooltip = false end
    for k, v in pairs(DEFAULTS) do
      if OlfatoDB[k] == nil then OlfatoDB[k] = v end
    end
    db = OlfatoDB
    db.trace = db.debug and {} or nil
    db.stats = { added = 0, forbidden = 0, ticks = 0 }
    RegisterSettings()
  elseif event == "PLAYER_LOGIN" then
    ApplyPlates()
    FindRangeSpells()
    C_Timer.NewTicker(TICK, Tick)
    if TooltipDataProcessor then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipLine)
    end
  elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
    if db then FindRangeSpells() end -- new ranks and talents like Hawk Eye change ranges
  elseif event == "PLAYER_TARGET_CHANGED" then
    if db then UpdateDistance() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if platesPending then ApplyPlates() end
  elseif event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
    units[arg] = true
    if event == "NAME_PLATE_UNIT_ADDED" then
      db.stats.added = db.stats.added + 1
    else
      db.stats.forbidden = db.stats.forbidden + 1
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" or event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED" then
    units[arg] = nil
    lastLevel[arg] = nil
    local plate = C_NamePlate.GetNamePlateForUnit(arg)
    if plate then Show(plate, 0) end
  end
end)

local function Diagnostics()
  local n = 0
  for _ in pairs(units) do n = n + 1 end
  local line = ("placas a %s yd, %d a la vista (%d normales, %d bloqueadas)"):format(
    GetCVar("nameplateMaxDistance") or "?", n, db.stats.added, db.stats.forbidden)
  if UnitExists("target") and Public(UnitCanAttack("player", "target")) then
    local minR, maxR = RC:GetRange("target")
    line = line .. ("; target: aggro %d yd, distancia %s-%s yd"):format(
      AggroRadius("target"), Public(minR) or "?", Public(maxR) or "?")
  end
  return line
end

SLASH_OLFATO1 = "/olf"
SLASH_OLFATO2 = "/olfato"
SlashCmdList.OLFATO = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "" or msg == "opciones" or msg == "options" then
    ToggleWindow()
  elseif msg == "on" or msg == "off" then
    SetOption("enabled", msg == "on")
    Print(db.enabled and "activado." or "desactivado.")
  elseif msg == "prueba" or msg == "test" then
    RunTest()
  elseif msg == "sonido" or msg == "sound" then
    SetOption("sound", not db.sound)
    Print(db.sound and "va a sonar un aviso cuando un enemigo esté por atacarte." or "sin sonido.")
  elseif msg == "distancia" or msg == "distance" then
    SetOption("targetDistance", not db.targetDistance)
    Print(db.targetDistance and "con distancia al objetivo." or "sin distancia al objetivo.")
  elseif msg == "debug" then
    db.debug = not db.debug
    db.trace = db.debug and {} or nil
    Print(db.debug and ("diagnóstico activado (se guarda con /reload). " .. Diagnostics()) or "diagnóstico desactivado.")
  else
    Print("/olf · /olf prueba · /olf sonido · /olf distancia · /olf " .. (db.enabled and "off" or "on"))
  end
end
