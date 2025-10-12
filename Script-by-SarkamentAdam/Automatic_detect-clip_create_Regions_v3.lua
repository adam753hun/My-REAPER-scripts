--[[
A script a következő lépéseket hajtja végre:
1. Megszámolja a kiválasztott média elemeket.
2. Végigmegy minden egyes kiválasztott média elemen.
3. Lekéri az elem pozícióját és hosszát.
4. Létrehoz egy régiót az elem pozíciójának és hosszának megfelelően.
5. Frissíti a rendezési nézetet, hogy megjelenítse az új régiókat.
------ Frissítés | Automatic_detect-clip_create_Regions_v3 | 2025.10.12.

• automatikusan régiókra osztja a kiválasztott médiaelemeket.
+ • Frissítés v2 : Lehetőség lett az időráhagyásra előtte és utána.
+ • Frissítés v3 : Lekéri az eredeti az eredeti média elemhez tartozó nevet
és az alapján nevezi el a régiót. (eltérő színezéssel)

Régiók létrehozása a kiválasztott itemekből, ráhagyással, automatikus elnevezéssel,
színezéssel, és a legutóbb használt beállítások megjegyzésével.
--]]

-- Konfig fájl elérési útja (a REAPER resource path-ban)
local config_path = reaper.GetResourcePath() .. "/RegionCreationSettings.txt"

-- Betöltjük a korábbi beállításokat (ha vannak)
local default_before = "0"
local default_after = "0"

local file = io.open(config_path, "r")
if file then
  local content = file:read("*all")
  local b, a = content:match("([%d%.%-]+),([%d%.%-]+)")
  if b and a then
    default_before = b
    default_after = a
  end
  file:close()
end

-- Kérjük be az értékeket a felhasználótól
local retval, user_input = reaper.GetUserInputs(
  "Régiók létrehozása ráhagyással",
  2,
  "Előtte hagyandó idő (ms):,Utána hagyandó idő (ms):",
  default_before .. "," .. default_after
)

if not retval then return end

-- Mentjük a beállításokat fájlba
local before_ms, after_ms = user_input:match("([^,]+),([^,]+)")
local file = io.open(config_path, "w")
if file then
  file:write(before_ms .. "," .. after_ms)
  file:close()
end

-- Átalakítás számokká és másodpercekké
before_ms = tonumber(before_ms) or 0
after_ms = tonumber(after_ms) or 0
local before_s = before_ms / 1000
local after_s = after_ms / 1000

-- Undo blokk
reaper.Undo_BeginBlock()

local num_items = reaper.CountSelectedMediaItems(0)
for i = 0, num_items - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local take = reaper.GetActiveTake(item)
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_pos + item_len

  -- Régió határok ráhagyással
  local region_start = math.max(0, item_pos - before_s)
  local region_end = item_end + after_s

  -- Régiónév: take neve vagy üres
  local region_name = ""
  if take then
    local take_name = reaper.GetTakeName(take)
    if take_name and take_name ~= "" then
      region_name = take_name
    end
  end

  -- Régió színe: véletlenszerű (vagy fix, ha szeretnéd)
  local color = reaper.ColorToNative(
    math.random(60,255), math.random(60,255), math.random(60,255)
  ) | 0x1000000

  -- Régió létrehozása
  reaper.AddProjectMarker2(0, true, region_start, region_end, region_name, -1, color)
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Régiók létrehozása ráhagyással, névvel és színnel", -1)
