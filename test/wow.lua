-- Simulated WoW Forever client (12.x engine) for Olfato: frames, units, nameplates, CVars and Settings.
-- lua test/simular.lua  (from ~/dev/Olfato)
-- Set sim.locale, sim.templates or sim.olfatoDB before loading this to change the client.
sim = sim or {}
sim.frames, sim.printed, sim.sounds, sim.units, sim.combat = {}, {}, {}, {}, false
sim.cvars = sim.cvars or { nameplateMaxDistance = "20" }
sim.locale = sim.locale or "enUS"
sim.templates = sim.templates or { UICheckButtonTemplate = true, UIPanelButtonTemplate = true, BasicFrameTemplateWithInset = true,
  BackdropTemplate = true, UIPanelCloseButton = true, InputBoxTemplate = true }

-- Secret values: sim.Secret(v) hands out a value addons can't read, like the 12.x client.
local secrets = setmetatable({}, { __mode = "k" })
function sim.Secret(v) local t = { v = v } secrets[t] = true return t end
function issecretvalue(v) return type(v) == "table" and secrets[v] == true end

local function noop() end
local Widget = {}
-- Unknown methods (Capitalized) do nothing; child keys the templates may or may not create stay nil.
local FIELDS = { Text = true, TitleText = true, TargetFrameContainer = true, Portrait = true }
Widget.__index = function(t, k)
  if Widget[k] then return Widget[k] end
  if type(k) == "string" and k:match("^%u") and not FIELDS[k] then return noop end
end
local function NewWidget(kind, name, parent)
  local w = setmetatable({ kind = kind, scripts = {}, shown = true, text = "", parent = parent, events = {} }, Widget)
  if name then _G[name] = w end
  sim.frames[#sim.frames + 1] = w
  return w
end
sim.NewWidget = NewWidget
function Widget:SetScript(k, f) self.scripts[k] = f end
function Widget:HookScript(k, f)
  local old = self.scripts[k]
  self.scripts[k] = function(...) if old then old(...) end f(...) end
end
function Widget:Show() local was = self:IsVisible() self.shown = true if not was and self:IsVisible() then self:Shown() end end
function Widget:Hide() self.shown = false end
function Widget:Shown() if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() local w = self while w do if not w.shown then return false end w = w.parent end return true end
function Widget:SetText(t) self.text = t == nil and "" or tostring(t) end
function Widget:GetText() return self.text end
function Widget:CreateFontString(_, _, font) local fs = NewWidget("FontString", nil, self) fs.font = font return fs end
function Widget:CreateTexture() return NewWidget("Texture", nil, self) end
function Widget:CreateMaskTexture() return NewWidget("MaskTexture", nil, self) end
function Widget:CreateAnimationGroup() local g = NewWidget("AnimationGroup", nil, self) return g end
function Widget:CreateAnimation(kind) return NewWidget(kind or "Animation", nil, self) end
function Widget:Play() self.playing = true end
function Widget:Stop() self.playing = false end
function Widget:IsPlaying() return self.playing == true end
function Widget:GetFrameLevel() return 1 end
function Widget:RegisterEvent(e) self.events[e] = true end
function Widget:SetPoint(...) self.point = { ... } end
function Widget:ClearAllPoints() self.point = nil end
function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
function Widget:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Widget:SetFontObject(f) self.font = f end
function Widget:SetChecked(v) self.checked = v and true or false end
function Widget:GetChecked() return self.checked == true end
function Widget:SetParent(p) self.parent = p end
-- Typing in an edit box: focus, text, then Enter (which drops the focus) or Esc.
function Widget:ClearFocus() if self.focused then self.focused = false
  if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end end
function Widget:Type(text, key)
  self.focused = true
  self.text = text
  self.scripts[key == "Esc" and "OnEscapePressed" or "OnEnterPressed"](self)
end
function Widget:Click()
  if self.kind == "CheckButton" then self.checked = not self.checked end
  if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
end

function CreateFrame(kind, name, parent, template)
  if template and not sim.templates[template] then error("CreateFrame: Couldn't find inherited node \"" .. template .. "\"") end
  local w = NewWidget(kind, name, parent or nil)
  w.template = template
  if template == "UICheckButtonTemplate" then w.Text = w:CreateFontString() end
  if template == "BasicFrameTemplateWithInset" then w.TitleText = w:CreateFontString() end
  return w
end
function sim.Fire(event, ...)
  for _, w in ipairs(sim.frames) do
    if w.events[event] and w.scripts.OnEvent then w.scripts.OnEvent(w, event, ...) end
  end
end

UIParent = NewWidget("Frame", "UIParent")
TargetFrame = NewWidget("Frame", "TargetFrame", UIParent)
TargetFrame.portrait = TargetFrame:CreateTexture()
TargetFrame:Hide()
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
unpack = unpack or table.unpack
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) sim.printed[#sim.printed + 1] = m end }
GetLocale = function() return sim.locale end
sim.now = 0
GetTime = function() return sim.now end
SOUNDKIT = { TELL_MESSAGE = 3081 }
PlaySound = function(id) sim.sounds[#sim.sounds + 1] = id end
InCombatLockdown = function() return sim.combat end
GetCVar = function(k) return sim.cvars[k] end
GetCVarDefault = function(k) if k == "nameplateMaxDistance" then return "20" end end
SetCVar = function(k, v)
  if sim.combat then error("SetCVar blocked in combat") end
  sim.cvars[k] = tostring(v)
end
C_Item = { IsItemInRange = function() return nil end }
CheckInteractDistance = function() return nil end

-- Units: sim.units[token] = { level =, hostile =, reaction =, combat =, dead =, player =, min =, max = }
-- "player" is the Warlock; "target" is whatever sim.target points to.
sim.player = { level = 36, player = true, name = "Dalsev" }
local function U(unit)
  if unit == "player" then return sim.player end
  if unit == "target" then return sim.target and sim.units[sim.target] end
  return sim.units[unit]
end
UnitExists = function(u) return U(u) ~= nil end
UnitIsUnit = function(a, b)
  if a == "target" and b == "player" then return sim.target == "player" end
  if a == "target" then return sim.target == b end
  if b == "target" then return sim.target == a end
  return a == b
end
UnitLevel = function(u) local x = U(u) return x and x.level end
UnitName = function(u) local x = U(u) return x and x.name end
UnitIsDeadOrGhost = function(u) local x = U(u) return x and x.dead or false end
UnitIsPlayer = function(u) local x = U(u) return x and x.player or false end
UnitCanAttack = function(_, u) local x = U(u) return x and x.hostile or false end
UnitAffectingCombat = function(u) local x = U(u) return x and x.combat or false end
UnitReaction = function(u) local x = U(u) return x and x.reaction end
sim.units.player = sim.player
C_NamePlate = { GetNamePlateForUnit = function() return nil end } -- NPC plates are forbidden on Forever

-- LibRangeCheck stand-in: the band each unit is in, or a secret when sim.secretRange is set.
local RC = { harmRC = { 1, 2, 3 } }
function RC:GetRange(u)
  local x = U(u)
  if not x then return nil end
  if sim.secretRange then return sim.Secret(x.min), sim.Secret(x.max) end
  return x.min, x.max
end
LibStub = function(name) assert(name == "LibRangeCheck-3.0") return RC end

sim.tickers = {}
C_Timer = {
  After = function(d, f) sim.timers[#sim.timers + 1] = { at = sim.now + d, f = f } end,
  NewTicker = function(d, f) sim.tickers[#sim.tickers + 1] = f end,
}
sim.timers = {}
function sim.Tick() for _, f in ipairs(sim.tickers) do f() end end
function sim.Advance(sec)
  sim.now = sim.now + sec
  local keep = {}
  for _, t in ipairs(sim.timers) do if t.at <= sim.now then t.f() else keep[#keep + 1] = t end end
  sim.timers = keep
end

GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:GetUnit() return self.unitName, self.unit end
Enum = { TooltipDataType = { Unit = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, f) sim.tooltipHook = f end }
function sim.Hover(unit)
  GameTooltip.lines, GameTooltip.unit = {}, unit
  sim.tooltipHook(GameTooltip)
  return GameTooltip.lines
end

Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    local c = { frame = frame, name = name, ID = name }
    function c:GetID() return self.ID end
    return c
  end,
  RegisterAddOnCategory = function(c) sim.settingsCategory = c end,
}
-- What the game does when you click the addon in Settings > AddOns.
function sim.OpenSettings()
  local panel = sim.settingsCategory.frame
  panel.parent = UIParent
  panel.shown = false
  panel:Show()
  return panel
end

date = os.date

-- Spellbook: sim.spellbook = { { id =, name =, min =, max =, harm =, passive = }, ... }; sim.units[x].real is the
-- true distance spells see (LibRangeCheck's band is min/max). sim.oldSpellAPI = true gives the pre-11.x globals.
sim.spellbook = sim.spellbook or {}
local function SpellByID(id) for i, s in ipairs(sim.spellbook) do if s.id == id then return s, i end end end
local function SpellInRange(s, unit)
  local x = U(unit)
  if not x or not x.real or s.passive then return nil end
  if s.harm ~= (x.hostile == true) then return nil end -- can't be cast on that unit
  if sim.secretSpells then return sim.Secret(true) end
  return x.real >= (s.min or 0) and x.real <= s.max
end
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
Enum.SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }
if sim.oldSpellAPI then
  GetNumSpellTabs = function() return 1 end
  GetSpellTabInfo = function() return "General", 0, 0, #sim.spellbook end
  GetSpellBookItemInfo = function(i) local s = sim.spellbook[i] if s then return s.passive and "PASSIVE" or "SPELL", s.id end end
  GetSpellInfo = function(id) local s = SpellByID(id) if s then return s.name, nil, 100 + id, 0, s.min or 0, s.max, id end end
  GetSpellTexture = function(id) return SpellByID(id) and 100 + id end
  IsSpellInRange = function(i, _, unit)
    local r = SpellInRange(sim.spellbook[i], unit)
    if r == nil or issecretvalue(r) then return r and sim.Secret(1) end
    return r and 1 or 0
  end
else
  C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 2 end,
    GetSpellBookSkillLineInfo = function(n)
      local half = math.floor(#sim.spellbook / 2)
      if n == 1 then return { itemIndexOffset = 0, numSpellBookItems = half } end
      return { itemIndexOffset = half, numSpellBookItems = #sim.spellbook - half }
    end,
    GetSpellBookItemInfo = function(i)
      local s = sim.spellbook[i]
      if s then return { spellID = s.id, itemType = Enum.SpellBookItemType.Spell, isPassive = s.passive or false, isOffSpec = false } end
    end,
  }
  C_Spell = {
    GetSpellInfo = function(id) local s = SpellByID(id) if s then return { name = s.name, minRange = s.min or 0, maxRange = s.max, iconID = 100 + id } end end,
    GetSpellTexture = function(id) return SpellByID(id) and 100 + id end,
    IsSpellInRange = function(id, unit) local s = SpellByID(id) return s and SpellInRange(s, unit) end,
  }
end
function GameTooltip:SetSpellByID(id) self.lines = { "spell:" .. id } end
