-- Kérjük a felhasználótól a fade in és fade out időtartamot milliszekundumban
local ret, user_input = reaper.GetUserInputs("Set Fade In and Out", 2, "Fade In (ms),Fade Out (ms)", "100,100")
if not ret then return end

-- Szétválasztjuk a felhasználói bemenetet
local fade_in, fade_out = user_input:match("([^,]+),([^,]+)")
fade_in = tonumber(fade_in)
fade_out = tonumber(fade_out)

-- Ellenőrizzük, hogy a bemenetek érvényes számok-e
if not fade_in or not fade_out then
  reaper.ShowMessageBox("Please enter valid numbers for fade in and fade out times.", "Error", 0)
  return
end

-- Átalakítjuk a milliszekundumokat másodpercekké
fade_in = fade_in / 1000
fade_out = fade_out / 1000

-- Kezdjük a tranzakciót
reaper.Undo_BeginBlock()

-- Beállítjuk a fade in és fade out időket minden kiválasztott itemre
local num_items = reaper.CountSelectedMediaItems(0)
for i = 0, num_items - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_in)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_out)
end

-- Befejezzük a tranzakciót
reaper.Undo_EndBlock("Set fade in and out for selected items", -1)

-- Frissítjük a felületet
reaper.UpdateArrange()

