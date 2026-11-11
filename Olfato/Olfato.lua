local addonName = ...

local RC = LibStub("LibRangeCheck-3.0")

local DEFAULTS = { enabled = true, sound = false, plateDistance = 41 }
local TICK = 0.2
-- How much earlier than the aggro radius each step lights up (yards).
local WARN_FAR, WARN_NEAR = 10, 5

local COLORS = {
  { 1.00, 0.82, 0.00 }, -- peligroso
  { 1.00, 0.50, 0.00 }, -- muy cerca
  { 1.00, 0.15, 0.10 }, -- inevitable
}

local YD = GetLocale():sub(1, 2) == "es" and " m" or " yd"

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

-- Temporary trace (saved on /reload): what each check returned, "S" = secret value.
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

local function NewIndicator(plate)
  local f = CreateFrame("Frame", nil, plate)
  f:SetSize(30, 8)
  f:SetPoint("BOTTOM", plate, "TOP", 0, -2)
  f:SetFrameLevel(plate:GetFrameLevel() + 10)
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
  f = f or NewIndicator(plate)
  indicators[plate] = f
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

local function Update()
  db.stats.ticks = db.stats.ticks + 1
  if not db.enabled or testing then return end
  local alarm = false
  for unit in pairs(units) do
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    db.stats.plate = plate and "yes" or "nil"
    if plate then
      local level = DangerLevel(unit)
      if level == 3 and (lastLevel[unit] or 0) < 3 then alarm = true end
      lastLevel[unit] = level
      Show(plate, level)
    end
  end
  if alarm and db.sound then PlaySound(SOUNDKIT.TELL_MESSAGE or 3081, "SFX") end
end

local function HideAll()
  for _, f in pairs(indicators) do f:Hide(); f.pulse:Stop() end
  wipe(lastLevel)
end

local function ExtendPlates()
  -- Nameplates only exist up to this distance; the default can be closer than the aggro radius.
  local current = tonumber(GetCVar("nameplateMaxDistance") or "")
  if current and db.plateDistance and current < db.plateDistance and not InCombatLockdown() then
    pcall(SetCVar, "nameplateMaxDistance", db.plateDistance)
  end
end

local function AddTooltipLine(tooltip)
  if tooltip ~= GameTooltip or not db.enabled then return end
  local _, unit = tooltip:GetUnit()
  unit = Public(unit)
  if not unit or not Public(UnitCanAttack("player", unit)) or Public(UnitIsPlayer(unit)) then return end
  local reaction = Public(UnitReaction(unit, "player"))
  if not reaction or reaction > 3 or Public(UnitIsDeadOrGhost(unit)) then return end
  tooltip:AddLine("|cff999999Aggro " .. AggroRadius(unit) .. YD .. "|r")
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == addonName then
    OlfatoDB = OlfatoDB or {}
    for k, v in pairs(DEFAULTS) do
      if OlfatoDB[k] == nil then OlfatoDB[k] = v end
    end
    db = OlfatoDB
    db.trace = {}
    db.stats = { added = 0, ticks = 0 }
  elseif event == "PLAYER_LOGIN" then
    ExtendPlates()
    C_Timer.NewTicker(TICK, Update)
    if TooltipDataProcessor then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipLine)
    end
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    units[arg] = true
    db.stats.added = db.stats.added + 1
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    units[arg] = nil
    lastLevel[arg] = nil
    local plate = C_NamePlate.GetNamePlateForUnit(arg)
    if plate then Show(plate, 0) end
  end
end)

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff9933Olfato|r " .. msg)
end

SLASH_OLFATO1 = "/olf"
SLASH_OLFATO2 = "/olfato"
SlashCmdList.OLFATO = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "on" or msg == "off" then
    db.enabled = msg == "on"
    if not db.enabled then HideAll() end
    Print(db.enabled and "activado" or "desactivado")
  elseif msg == "prueba" or msg == "test" then
    -- Shows the three steps on your target's nameplate, then the alarm sound.
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then
      Print("poné de target algo con barra de nombre")
      return
    end
    testing = true
    for level = 1, 3 do
      C_Timer.After(level - 1, function()
        Show(plate, level)
        if level == 3 then PlaySound(SOUNDKIT.TELL_MESSAGE or 3081, "SFX") end
      end)
    end
    C_Timer.After(5, function() testing = false; Show(plate, 0) end)
  elseif msg == "sonido" or msg == "sound" then
    db.sound = not db.sound
    Print("sonido " .. (db.sound and "sí" or "no"))
  else
    local target = UnitExists("target") and Public(UnitCanAttack("player", "target"))
    local minR, maxR = RC:GetRange("target")
    Print(("%s · sonido %s · placas hasta %s yd%s"):format(
      db.enabled and "on" or "off", db.sound and "sí" or "no", GetCVar("nameplateMaxDistance") or "?",
      target and (" · target: aggro %d yd, estás a %s-%s"):format(AggroRadius("target"), Public(minR) or "?", Public(maxR) or "?") or ""))
  end
end
