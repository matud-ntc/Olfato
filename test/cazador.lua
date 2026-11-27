-- lua test/cazador.lua [viejo]   (from ~/dev/Olfato): "Avisar a" with a hunter's own 41 yd shots.
local opts = {}
for _, a in ipairs(arg) do opts[a] = true end
local HAWK_EYE = 41 -- 35 + 6 with the talent
sim = { oldSpellAPI = opts.viejo, spellbook = {
  { id = 1494, name = "Track Beasts", max = 0 },
  { id = 2973, name = "Raptor Strike", max = 5, harm = true },
  { id = 75, name = "Auto Shot", min = 8, max = HAWK_EYE, harm = true },
  { id = 3044, name = "Arcane Shot", min = 8, max = HAWK_EYE, harm = true },
  { id = 19506, name = "Trueshot Aura", max = 0, passive = true },
  { id = 136, name = "Mend Pet", max = 45, harm = false },
} }
dofile("test/wow.lua")

local fails = 0
local function Check(cond, msg)
  if cond then print("ok    " .. msg) else print("FALLA " .. msg) fails = fails + 1 end
end

assert(loadfile("Olfato/Olfato.lua"))("Olfato")
sim.Fire("ADDON_LOADED", "Olfato")
sim.Fire("PLAYER_LOGIN")
sim.Fire("SPELLS_CHANGED")
local db = OlfatoDB

SlashCmdList.OLFATO("")
local box, icon
for _, w in ipairs(sim.frames) do
  if w.parent == OlfatoOptions and w.kind == "EditBox" then box = w end
  if w.parent == OlfatoOptions and w.kind == "Frame" and w.texture then icon = w end
end
Check(not icon:IsShown(), "sin número, sin ícono")
box:Type("41")
Check(db.alertRange == 41 and icon:IsShown() and icon.spell == 75, "41: encuentra Auto Shot y muestra su ícono")
icon.scripts.OnEnter(icon)
Check(GameTooltip.lines[1] == "spell:75", "el ícono muestra el hechizo al pasar el mouse")

sim.units.boar = { name = "Plainstrider", level = 34, hostile = true, reaction = 2 }
sim.target = "boar"
TargetFrame:Show()
local function At(real, min, max)
  local u = sim.units.boar
  u.real, u.min, u.max = real, min, max
  sim.Tick()
  local d = OlfatoDistance
  return d.text.text .. (d.text.color[2] == 1 and " verde" or " gris")
end
local cases = {
  { 40.5, 40, 45, "40-41 verde", "a 40,5: la franja 40-45 se parte en 40-41" },
  { 43, 40, 45, "41-45 gris", "a 43: 41-45, fuera de tiro" },
  { 41, 40, 45, "40-41 verde", "a 41 justo: a tiro" },
  { 38, 35, 40, "35-40 verde", "35-40 ya está adentro sin preguntar" },
  { 50, 45, nil, "45+ gris", "45+ queda igual" },
  { 6, 5, nil, "5+ gris", "zona muerta (a 6, Auto Shot dice que no): no inventa 41+" },
}
for _, c in ipairs(cases) do
  local got = At(c[1], c[2], c[3])
  Check(got == c[4], c[5] .. " -> " .. got)
end

sim.units.ally = { name = "Franco", level = 36, hostile = false, reaction = 5, real = 43, min = 40, max = 45 }
sim.target = "ally"
sim.Fire("PLAYER_TARGET_CHANGED")
Check(OlfatoDistance.text.text == "40-45", "aliado: los disparos no se le pueden tirar, queda la franja")
sim.target = "boar"

box:Type("33")
Check(icon:IsShown() == false and #sim.spellbook > 0, "33: no tiene nada a 33, sin ícono")
Check(At(34, 30, 35) == "30-35 gris", "y la franja queda como estaba")

box:Type("45")
Check(icon:IsShown() and icon.spell == 136, "45: Mend Pet (amistoso)")
Check(At(43, 40, 45) == "40-45 verde", "40-45 con 45: verde por la franja")
Check(At(47, 45, nil) == "45+ gris", "Mend Pet no sirve con un enemigo: 45+ sigue igual")

box:Type("41")
sim.secretSpells = true
local ok, got = pcall(At, 40.5, 40, 45)
Check(ok and got == "40-45 gris", "respuesta secreta: no rompe, queda la franja -> " .. tostring(got))
sim.secretSpells = nil

-- Respec without Hawk Eye: the shots go back to 35.
for _, s in ipairs(sim.spellbook) do if s.max == HAWK_EYE then s.max = 35 end end
sim.Fire("CHARACTER_POINTS_CHANGED")
Check(At(40.5, 40, 45) == "40-45 gris", "sin Hawk Eye ya no hay nada a 41")
box:Type("35")
Check(icon.spell == 75 and At(34, 30, 40) == "30-35 verde", "con 35: 30-40 se parte en 30-35")

if fails > 0 then print(fails .. " fallas") os.exit(1) end
print("todo bien")
