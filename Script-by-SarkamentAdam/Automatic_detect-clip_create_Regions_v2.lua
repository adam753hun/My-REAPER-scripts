--[[
A script a következő lépéseket hajtja végre:
1. Megszámolja a kiválasztott média elemeket.
2. Végigmegy minden egyes kiválasztott média elemen.
3. Lekéri az elem pozícióját és hosszát.
4. Létrehoz egy régiót az elem pozíciójának és hosszának megfelelően.
5. Frissíti a rendezési nézetet, hogy megjelenítse az új régiókat.
------ Frissítés | Automatic_detect-clip_create_Regions_v2 | 2025.10.12.
Ez a script automatikusan létrehoz régiókat a kiválasztott médiaelemek helyén és hosszán alapulva,
de lehetőséget ad arra is, hogy milliszekundumban megadjuk,
mennyi időt hagyjon rájuk előtte és utána.

Korábbi szkript lépései: (ez is hasonló metodikát hajt végre, de lehetőség van immár időráhagyásra)
Ez a script automatikusan létrehoz régiókat a kiválasztott média elemek helyén és hosszán alapulva.
Minden kiválasztott média elemhez létrehoz egy régiót, amely megfelel az elem kezdőpozíciójának és hosszának.
--]]

-- Kérjük be a felhasználótól a ráhagyásokat (ms-ben)
local retval, user_input = reaper.GetUserInputs("Régiók létrehozása ráhagyással", 2, 
"Előtte hagyandó idő (ms):,Utána hagyandó idő (ms):", "0,0")

-- Ha a felhasználó megszakította, lépjünk ki
if not retval then return end

-- Szétválasztjuk a két értéket
local before_ms, after_ms = user_input:match("([^,]+),([^,]+)")

-- Átalakítás számokká és ms → s
before_ms = tonumber(before_ms) or 0
after_ms = tonumber(after_ms) or 0
local before_s = before_ms / 1000
local after_s = after_ms / 1000

-- Kiválasztott médiaelemek száma
local num_items = reaper.CountSelectedMediaItems(0)

-- Undo blokk kezdete
reaper.Undo_BeginBlock()

for i = 0, num_items - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_pos + item_len

  -- Alkalmazzuk a ráhagyásokat
  local region_start = item_pos - before_s
  local region_end = item_end + after_s

  -- Ne legyen negatív kezdés
  if region_start < 0 then region_start = 0 end

  -- Hozzuk létre a régiót
  reaper.AddProjectMarker2(0, true, region_start, region_end, "", -1, 0)
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Régiók létrehozása ráhagyással", -1)
