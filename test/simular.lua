-- lua test/simular.lua [es] [sintemplate]   (from ~/dev/Olfato)
local opts = {}
for _, a in ipairs(arg) do opts[a] = true end
sim = { locale = opts.es and "esES" or "enUS" }
if opts.sintemplate then
  sim.templates = { UICheckButtonTemplate = true, UIPanelButtonTemplate = true, BackdropTemplate = true, UIPanelCloseButton = true,
    InputBoxTemplate = true }
end
dofile("test/wow.lua")

local fails = 0
local function Check(cond, msg)
  if cond then print("ok    " .. msg) else print("FALLA " .. msg) fails = fails + 1 end
end

OlfatoDB = sim.olfatoDB
assert(loadfile("Olfato/Olfato.lua"))("Olfato")
sim.Fire("ADDON_LOADED", "Olfato")
sim.Fire("PLAYER_LOGIN")
local db = OlfatoDB

print("== por defecto ==")
Check(db.enabled and db.tooltip and db.targetDistance and not db.sound, "puntos, tooltip y distancia prendidos; sonido apagado")
Check(sim.cvars.nameplateMaxDistance == "41", "barras a 41")
Check(db.alertRange == 0, "sin rango propio")
Check(sim.settingsCategory and sim.settingsCategory.name == "Olfato", "registrado en Settings > AddOns")

print("== distancia al objetivo ==")
sim.Tick()
local dist = OlfatoDistance
Check(not dist:IsShown(), "sin objetivo no se ve")
sim.units.wolf = { name = "Timber Wolf", level = 34, hostile = true, reaction = 2, min = 20, max = 25 }
sim.target = "wolf"
TargetFrame:Show()
sim.Fire("PLAYER_TARGET_CHANGED")
print("      texto: " .. dist.text.text)
Check(dist:IsShown() and dist.text.text == "20-25", "al seleccionar: 20-25 al toque")
Check(dist.point[2] == TargetFrame.portrait and dist.point[1] == "BOTTOM" and dist.point[3] == "TOP", "arriba del retrato del objetivo")
Check(not dist.text.text:find("[%a]"), "sin rótulos")
sim.units.wolf.min, sim.units.wolf.max = 8, 10
sim.Tick()
Check(dist.text.text == "8-10", "se actualiza al moverte (8-10)")
sim.units.wolf.min, sim.units.wolf.max = 40, nil
sim.Tick()
Check(dist.text.text == "40+", "más lejos que lo medible: 40+")
sim.secretRange = true
local ok, err = pcall(sim.Tick)
Check(ok and not dist:IsShown(), "rango secreto: se esconde sin error " .. tostring(err or ""))
sim.secretRange = nil
sim.target = "player"
sim.Fire("PLAYER_TARGET_CHANGED")
Check(not dist:IsShown(), "a uno mismo no")
sim.units.ally = { name = "Thrall", level = 63, hostile = false, reaction = 5, min = 0, max = 5 }
sim.target = "ally"
sim.Fire("PLAYER_TARGET_CHANGED")
Check(dist:IsShown() and dist.text.text == "0-5", "amigos también (0-5)")
TargetFrame:Hide()
sim.Tick()
Check(dist:IsShown() and dist.point[2] == OlfatoHUD and dist.point[1] == "TOP", "marco del objetivo escondido por otro addon: bajo el personaje")
TargetFrame:Show()
sim.target = nil
sim.Fire("PLAYER_TARGET_CHANGED")
Check(not dist:IsShown(), "al soltar el objetivo desaparece")

print("== ventana /olf ==")
SlashCmdList.OLFATO("")
local win = OlfatoOptions
Check(win and win:IsShown(), "/olf la abre")
Check(win.TitleText == nil or win.TitleText.text == "Olfato", "título Olfato")
local checks, button, box, texts = {}, nil, nil, {}
for _, w in ipairs(sim.frames) do
  if w.parent == win and w.kind == "CheckButton" then checks[#checks + 1] = w end
  if w.parent == win and w.kind == "Button" and w.template == "UIPanelButtonTemplate" then button = w end
  if w.parent == win and w.kind == "EditBox" then box = w end
  if w.parent == win and w.kind == "FontString" and w ~= win.TitleText then texts[#texts + 1] = w.text end
end
local labels = {}
for i, cb in ipairs(checks) do labels[i] = cb.Text.text .. (cb.checked and " [x]" or " [ ]") end
print("      " .. table.concat(labels, " · ") .. " · " .. texts[#texts - 1] .. " [" .. box.text .. "] " .. texts[#texts]
  .. " · (" .. button.text .. ")")
Check(#checks == 4, "cuatro checks")
Check(box and box.text == "", "campo de rango vacío")
local function CheckFor(label) for _, cb in ipairs(checks) do if cb.Text.text:find(label) then return cb end end end
local L = sim.locale == "esES" and { "Puntos", "tooltip", "Sonido", "Distancia" }
  or { "dots", "tooltip", "sound", "Distance" }
local dots, tip, sound, distance = CheckFor(L[1]), CheckFor(L[2]), CheckFor(L[3]), CheckFor(L[4])
Check(dots.checked and tip.checked and not sound.checked and distance.checked, "reflejan lo guardado")
Check(tinsert and UISpecialFrames[1] == "OlfatoOptions", "Esc la cierra")

sim.target = "wolf"
sim.units.wolf.min, sim.units.wolf.max = 20, 25
sim.Fire("PLAYER_TARGET_CHANGED")
distance:Click()
Check(db.targetDistance == false and not dist:IsShown(), "destildar distancia la esconde")
sim.Tick()
Check(not dist:IsShown(), "y no vuelve con el tick")
distance:Click()
Check(dist:IsShown(), "tildar la vuelve a mostrar")

print("== rango propio ==")
local function Color() return dist.text.color[2] == 1 and "verde" or "gris" end
Check(Color() == "gris", "sin rango: gris")
box:Type("30")
Check(db.alertRange == 30 and box.text == "30", "escribir 30 + Enter lo guarda")
local cases = { { 20, 25, "verde" }, { 25, 30, "verde" }, { 30, 35, "gris" }, { 40, nil, "gris" }, { 0, 5, "verde" } }
for _, c in ipairs(cases) do
  sim.units.wolf.min, sim.units.wolf.max = c[1], c[2]
  sim.Tick()
  Check(Color() == c[3], dist.text.text .. " con 30: " .. c[3])
end
box:Type("33")
sim.units.wolf.min, sim.units.wolf.max = 30, 35
sim.Tick()
Check(Color() == "gris", "30-35 con 33: gris (puede estar afuera)")
box:Type("99", "Esc")
Check(db.alertRange == 33 and box.text == "33", "Esc descarta lo escrito")
box:Type("")
sim.units.wolf.min, sim.units.wolf.max = 20, 25
sim.Tick()
Check(db.alertRange == 0 and box.text == "" and Color() == "gris", "borrarlo lo apaga")
box:Type("30")

-- Aggro: a mob in a forbidden plate getting close, summed up under the character.
sim.Fire("FORBIDDEN_NAME_PLATE_UNIT_ADDED", "nameplate1")
sim.units.nameplate1 = { name = "Ashenvale Bear", level = 36, hostile = true, reaction = 2, min = 15, max = 20 }
sim.Tick()
local hud = OlfatoHUD
Check(hud.inner:IsShown() and hud.inner.pulse.playing and hud.name.text == "Ashenvale Bear", "puntos rojos titilando bajo el personaje")
Check(#sim.sounds == 0, "sin sonido por defecto")
sim.units.nameplate1.min, sim.units.nameplate1.max = 40, nil
sim.Tick()
sound:Click()
Check(db.sound == true, "tildar sonido")
sim.units.nameplate1.min, sim.units.nameplate1.max = 15, 20
sim.Tick()
Check(#sim.sounds == 1, "suena al pasar a rojo")
dots:Click()
Check(db.enabled == false and not hud.inner:IsShown(), "destildar puntos los esconde")
sim.Tick()
Check(not hud.inner:IsShown(), "y no vuelven con el tick")
Check(dist:IsShown(), "la distancia sigue andando sin los puntos")
local lines = sim.Hover("nameplate1")
Check(#lines == 1 and lines[1]:find("Aggro 20 " .. (sim.locale == "esES" and "m" or "yd")), "tooltip sigue con los puntos apagados: " .. tostring(lines[1]))
tip:Click()
Check(#sim.Hover("nameplate1") == 0, "destildar tooltip saca la línea")
tip:Click()
dots:Click()

button:Click()
sim.Advance(0)
Check(hud.inner:IsShown(), "Probar muestra el aviso")
sim.Advance(5)
Check(not hud.inner:IsShown(), "y se va solo")


SlashCmdList.OLFATO("opciones")
Check(not win:IsShown(), "/olf opciones la cierra")

print("== Settings > AddOns ==")
sound:Click() -- off from the window while Settings is closed
local panel = sim.OpenSettings()
local pchecks, pbox = {}, nil
for _, w in ipairs(sim.frames) do
  if w.parent == panel and w.kind == "CheckButton" then pchecks[w.Text.text] = w end
  if w.parent == panel and w.kind == "EditBox" then pbox = w end
end
local n = 0 for _ in pairs(pchecks) do n = n + 1 end
Check(n == 4, "cuatro checks en el panel")
Check(pbox.text == "30", "el panel ve el rango de la ventana")
for label, cb in pairs(pchecks) do
  if label:find(L[3]) then Check(cb.checked == false, "el panel ve el cambio de la ventana") end
  if label:find(L[4]) then cb:Click() end
end
Check(db.targetDistance == false, "y escribe en OlfatoDB")
SlashCmdList.OLFATO("")
Check(distance.checked == false, "la ventana ve el cambio del panel")

print("== comandos ==")
SlashCmdList.OLFATO("distancia")
Check(db.targetDistance == true, "/olf distancia")
SlashCmdList.OLFATO("off")
Check(db.enabled == false and db.tooltip == true, "/olf off apaga los puntos")
SlashCmdList.OLFATO("on")
SlashCmdList.OLFATO("sonido")
Check(db.sound == true, "/olf sonido")
SlashCmdList.OLFATO("cualquiera")
print("      " .. sim.printed[#sim.printed])

if fails > 0 then print(fails .. " fallas") os.exit(1) end
print("todo bien")
