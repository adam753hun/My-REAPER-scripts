--[[
A script a következő lépéseket hajtja végre:

1. Megszámolja a kiválasztott médiaelemeket.
2. Lekéri az itemek pozícióját és hosszát.
3. A beállított ráhagyásokkal létrehozza vagy frissíti a hozzájuk tartozó régiókat.
4. Átfedés esetén megtartja a megadott minimális távolságot a régiók között.
5. Frissíti a rendezési nézetet, hogy az új vagy módosított régiók megjelenjenek.

------ Frissítés | Automatic_detect-clip_create_Regions | Első verzió
• Automatikusan régiókra osztja a kiválasztott médiaelemeket.

• Frissítés v2:
  Lehetőség lett az időráhagyásra előtte és utána.

• Frissítés v3 | 2025.10.12.:
  Lekéri az eredeti médiaelemhez tartozó nevet, és az alapján nevezi el a régiót.
  A régiók eltérő színezést kapnak, és a script megjegyzi a legutóbb használt
  időráhagyás-beállításokat.

------ Frissítés | Automatic_detect-clip_create_Regions_v4 | 2026.09.19.
Változások:

• Átfedéskor tartja a megadott minimális távolságot (alapból 1 ms), majd jelzi,
  hány ütközést korrigált.
• Sorszámozott neveket készít: 01_..., 02_... .
• Névforrás lehet take-név, fájlnév, track-név vagy saját név, elő- és utótaggal.
• Színmód: véletlen, saját színválasztóval megadott vagy track-szín.
• Nem dupláz: az azonos helyű, korábbi régiókat átveszi és a v4-hez kapcsolja.
• 1. művelet: létrehozás / frissítés.
• 2. művelet: csak a korábban v4 által követésbe vett régiók pozícióját frissíti,
  név- és színmódosítás nélkül.
--]]

local SECTION = "SarkamentAdam.RegionCreator.v4"
local SETTINGS_KEY = "settings"
local MIN_REGION_LENGTH = 0.001 -- 1 ms

local function split_settings(value)
  local values = {}
  for part in (value .. "|"):gmatch("(.-)|") do
    values[#values + 1] = part
  end
  return values
end

local function get_item_guid(item)
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return ok and guid or nil
end

local function get_region_by_id(region_id)
  local marker_index = 0
  while true do
    local retval, is_region, start_pos, end_pos, name, id, color =
      reaper.EnumProjectMarkers3(0, marker_index)
    if retval == 0 then return nil end
    if is_region and id == region_id then
      return { id = id, start_pos = start_pos, end_pos = end_pos, name = name, color = color }
    end
    marker_index = marker_index + 1
  end
end

local function find_matching_region(start_pos, end_pos)
  local epsilon = 0.000001
  local marker_index = 0
  while true do
    local retval, is_region, existing_start, existing_end, name, id, color =
      reaper.EnumProjectMarkers3(0, marker_index)
    if retval == 0 then return nil end
    if is_region and math.abs(existing_start - start_pos) < epsilon and math.abs(existing_end - end_pos) < epsilon then
      return { id = id, name = name, color = color }
    end
    marker_index = marker_index + 1
  end
end

local function get_item_name(item, source_choice, custom_name)
  if source_choice == "4" then
    return custom_name ~= "" and custom_name or "Régió"
  end

  local take = reaper.GetActiveTake(item)
  if source_choice == "1" then
    local take_name = take and reaper.GetTakeName(take) or ""
    return take_name ~= "" and take_name or "Névtelen"
  end

  if source_choice == "2" and take then
    local source = reaper.GetMediaItemTake_Source(take)
    local ok, filename = reaper.GetMediaSourceFileName(source, "")
    if ok and filename ~= "" then
      local basename = filename:match("([^\\/]+)$") or filename
      return (basename:gsub("%.[^%.]+$", ""))
    end
  end

  if source_choice == "3" then
    local track = reaper.GetMediaItem_Track(item)
    local ok, track_name = reaper.GetTrackName(track, "")
    if ok and track_name ~= "" then return track_name end
  end

  return "Névtelen"
end

local function get_region_color(item, color_mode, fixed_color)
  if color_mode == "1" then
    return reaper.ColorToNative(math.random(60, 255), math.random(60, 255), math.random(60, 255)) | 0x1000000
  end

  if color_mode == "3" then
    local track = reaper.GetMediaItem_Track(item)
    local track_color = reaper.GetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR")
    if track_color ~= 0 then return track_color end
  end

  return fixed_color
end

local function apply_spacing(regions, minimum_gap)
  local collisions = 0
  table.sort(regions, function(a, b) return a.start_pos < b.start_pos end)

  for i = 2, #regions do
    local previous = regions[i - 1]
    local current = regions[i]
    if previous.end_pos + minimum_gap > current.start_pos then
      collisions = collisions + 1
      local allowed_end = current.start_pos - minimum_gap

      if allowed_end > previous.start_pos then
        previous.end_pos = allowed_end
      else
        -- Két azonos vagy egymást teljesen fedő régiónál a következő régiót eltoljuk.
        current.start_pos = previous.end_pos + minimum_gap
        if current.end_pos <= current.start_pos then
          current.end_pos = current.start_pos + MIN_REGION_LENGTH
        end
      end
    end
  end

  return collisions
end

local function make_region_name(index, item, source_choice, prefix, suffix)
  local base_name = get_item_name(item, source_choice, prefix)
  local name_prefix = source_choice == "4" and "" or prefix
  return string.format("%02d_%s%s%s", index, name_prefix, base_name, suffix)
end

local function get_mapped_region_id(item)
  local guid = get_item_guid(item)
  if not guid then return nil end
  local ok, value = reaper.GetProjExtState(0, SECTION, guid)
  return ok == 1 and tonumber(value) or nil
end

local function save_region_mapping(item, region_id)
  local guid = get_item_guid(item)
  if guid then
    reaper.SetProjExtState(0, SECTION, guid, tostring(region_id))
  end
end

local saved = split_settings(reaper.GetExtState(SECTION, SETTINGS_KEY))
local defaults = {
  saved[1] ~= "" and saved[1] or "1", -- 1=create/update, 2=refresh only
  saved[2] ~= "" and saved[2] or "0",
  saved[3] ~= "" and saved[3] or "0",
  saved[4] ~= "" and saved[4] or "1",
  saved[5] ~= "" and saved[5] or "1", -- 1=take, 2=file, 3=track, 4=custom
  saved[6] or "",
  saved[7] or "",
  saved[8] ~= "" and saved[8] or "1" -- 1=random, 2=fixed, 3=track
}

reaper.ShowMessageBox(
  "Művelet: 1 = Létrehozás / frissítés, 2 = Csak frissítés\n\n" ..
  "Névforrás: 1 = Take-név, 2 = Fájlnév, 3 = Track-név, 4 = Saját név\n" ..
  "Szín: 1 = Véletlen, 2 = Saját szín, 3 = Track színe\n\n" ..
  "Átfedéskor a script legalább a megadott távolságot tartja, majd figyelmeztet.",
  "Régiókészítő v4 – súgó",
  0
)

local retval, user_input = reaper.GetUserInputs(
  "Régiókészítő v4",
  8,
  "Művelet (1-2),Előtte (ms),Utána (ms),Min. távolság (ms),Névforrás (1-4),Előtag / saját név,Utótag,Szín (1-3),separator=|,extrawidth=460",
  table.concat(defaults, "|")
)
if not retval then return end

local mode, before_text, after_text, gap_text, source_choice, prefix, suffix, color_mode =
  user_input:match("^(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)$")

local before_ms = tonumber(before_text)
local after_ms = tonumber(after_text)
local gap_ms = tonumber(gap_text)
if (mode ~= "1" and mode ~= "2") or not before_ms or not after_ms or not gap_ms or
   before_ms < 0 or after_ms < 0 or gap_ms < 0 or
   (source_choice ~= "1" and source_choice ~= "2" and source_choice ~= "3" and source_choice ~= "4") or
   (color_mode ~= "1" and color_mode ~= "2" and color_mode ~= "3") then
  reaper.ShowMessageBox("Ellenőrizd a számértékeket és a választási kódokat.", "Érvénytelen beállítás", 0)
  return
end

reaper.SetExtState(SECTION, SETTINGS_KEY, user_input, true)

local fixed_color = reaper.ColorToNative(70, 130, 180) | 0x1000000
if mode == "1" and color_mode == "2" then
  local color_ok, chosen_color = reaper.GR_SelectColor(0, fixed_color)
  if color_ok == 0 then return end
  fixed_color = chosen_color | 0x1000000
end

local item_count = reaper.CountSelectedMediaItems(0)
if item_count == 0 then
  reaper.ShowMessageBox("Jelölj ki legalább egy médiaitemet.", "Nincs kijelölt item", 0)
  return
end

math.randomseed(os.time())
local before_seconds = before_ms / 1000
local after_seconds = after_ms / 1000
local gap_seconds = gap_ms / 1000
local work = {}
local skipped_duplicates = 0
local missing_mappings = 0

for i = 0, item_count - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local desired_start = math.max(0, item_start - before_seconds)
  local desired_end = item_end + after_seconds
  local mapped_id = get_mapped_region_id(item)
  local mapped_region = mapped_id and get_region_by_id(mapped_id) or nil

  if mode == "2" then
    if mapped_region then
      work[#work + 1] = {
        item = item, action = "update", id = mapped_id,
        start_pos = desired_start, end_pos = desired_end,
        name = mapped_region.name, color = mapped_region.color
      }
    else
      missing_mappings = missing_mappings + 1
    end
  elseif mapped_region then
    work[#work + 1] = {
      item = item, action = "update", id = mapped_id,
      start_pos = desired_start, end_pos = desired_end,
      name = make_region_name(i + 1, item, source_choice, prefix, suffix),
      color = get_region_color(item, color_mode, fixed_color)
    }
  else
    local matching_region = find_matching_region(desired_start, desired_end)
    if matching_region then
      -- A korábbi v3-as, azonos helyű régiót átvesszük v4-követéshez.
      work[#work + 1] = {
        item = item, action = "update", id = matching_region.id,
        start_pos = desired_start, end_pos = desired_end,
        name = make_region_name(i + 1, item, source_choice, prefix, suffix),
        color = get_region_color(item, color_mode, fixed_color)
      }
    else
    work[#work + 1] = {
      item = item, action = "create",
      start_pos = desired_start, end_pos = desired_end,
      name = make_region_name(i + 1, item, source_choice, prefix, suffix),
      color = get_region_color(item, color_mode, fixed_color)
      }
    end
  end
end

if #work == 0 then
  reaper.ShowMessageBox("Nincs létrehozható vagy frissíthető régió.", "Régiókészítő v4", 0)
  return
end

local collisions = apply_spacing(work, gap_seconds)
reaper.Undo_BeginBlock()

local created = 0
local updated = 0
for _, region in ipairs(work) do
  if region.action == "create" then
    local region_id = reaper.AddProjectMarker2(0, true, region.start_pos, region.end_pos, region.name, -1, region.color)
    save_region_mapping(region.item, region_id)
    created = created + 1
  else
    reaper.SetProjectMarker3(0, region.id, true, region.start_pos, region.end_pos, region.name, region.color)
    save_region_mapping(region.item, region.id)
    updated = updated + 1
  end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Régiók létrehozása/frissítése v4", -1)

local messages = { string.format("Létrehozva: %d | Frissítve: %d", created, updated) }
if skipped_duplicates > 0 then
  messages[#messages + 1] = string.format("Kihagyott duplikátum: %d", skipped_duplicates)
end
if missing_mappings > 0 then
  messages[#messages + 1] = string.format("Nem követett régió (csak frissítés módban): %d", missing_mappings)
end
if collisions > 0 then
  messages[#messages + 1] = string.format("FIGYELEM: %d régióütközés korrigálva; a megadott távolság megmaradt.", collisions)
end
reaper.ShowMessageBox(table.concat(messages, "\n"), "Régiókészítő v4", 0)