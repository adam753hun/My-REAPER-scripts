--[[ 
Ez a script automatikusan létrehoz régiókat a kiválasztott média elemek helyén és hosszán alapulva.
Minden kiválasztott média elemhez létrehoz egy régiót, amely megfelel az elem kezdőpozíciójának és hosszának.
A script a következő lépéseket hajtja végre:
1. Megszámolja a kiválasztott média elemeket.
2. Végigmegy minden egyes kiválasztott média elemen.
3. Lekéri az elem pozícióját és hosszát.
4. Létrehoz egy régiót az elem pozíciójának és hosszának megfelelően.
5. Frissíti a rendezési nézetet, hogy megjelenítse az új régiókat.
--]]

-- Get the number of selected media items | A kiválasztott médiaelemek számának lekérdezése
local num_items = reaper.CountSelectedMediaItems(0)

-- Loop through each selected media item | Átfutás az egyes kiválasztott médiaelemeken
for i = 0, num_items - 1 do
  -- Get the media item |A médiaelem lekérése
  local item = reaper.GetSelectedMediaItem(0, i)
  
  -- Get the position and length of the media item | A médiaelem pozíciójának és hosszának lekérdezése
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_pos + item_len 
  
  -- Create a region for the media item | Hozzon létre egy régiót a médiaelemhez
  reaper.AddProjectMarker2(0, true, item_pos, item_end, "", -1, 0)
end

-- Update the arrange view to reflect the new regions |Frissítse a rendezési nézetet, hogy tükrözze az új régiókat
reaper.UpdateArrange()

