-- A REAPER fade shape azonosítói:
-- 0 = Linear, 2 = Slow start/end, 3 = Fast start, 5 = Bezier
local fade_shapes = {
  ["1"] = { id = 0, name = "Linear" },
  ["2"] = { id = 3, name = "Fast start" },
  ["3"] = { id = 2, name = "Slow start/end" },
  ["4"] = { id = 5, name = "Bezier" }
}

-- Kérjük a felhasználótól a fade in/out időtartamot és a görbét.
local ret, user_input = reaper.GetUserInputs(
  "Fade In / Fade Out beállítása",
  4,
  "Fade In (ms),Fade Out (ms),Görbe (1-4),Súgó",
  "100,100,1,1=Lineáris | 2=Gyors/meredek | 3=Lassú/lágy | 4=S-görbe"
)
if not ret then return end

-- Szétválasztjuk a felhasználói bemenetet
local fade_in, fade_out, shape_choice = user_input:match("([^,]+),([^,]+),([^,]+),.*")
fade_in = tonumber(fade_in)
fade_out = tonumber(fade_out)
shape_choice = shape_choice and shape_choice:match("^%s*(.-)%s*$")
local fade_shape = fade_shapes[shape_choice]

-- Ellenőrizzük, hogy a bemenetek érvényesek-e
if not fade_in or not fade_out or fade_in < 0 or fade_out < 0 or not fade_shape then
  reaper.ShowMessageBox(
    "Adj meg két nem negatív számot és egy görbét 1 és 4 között.\n\n" ..
    "1 = Lineáris\n2 = Gyors/meredek\n3 = Lassú/lágy\n4 = S-görbe",
    "Érvénytelen beállítás",
    0
  )
  return
end

-- Átalakítjuk a milliszekundumokat másodpercekké
fade_in = fade_in / 1000
fade_out = fade_out / 1000

-- Kezdjük a tranzakciót
reaper.Undo_BeginBlock()

-- Beállítjuk a fade in/out időket és görbéket minden kiválasztott itemre
local num_items = reaper.CountSelectedMediaItems(0)
for i = 0, num_items - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_in)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_out)
  reaper.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", fade_shape.id)
  reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", fade_shape.id)
end

-- Befejezzük a tranzakciót
reaper.Undo_EndBlock("Fade in/out beállítása (" .. fade_shape.name .. ")", -1)

-- Frissítjük a felületet
reaper.UpdateArrange()