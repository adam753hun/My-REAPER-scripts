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

-- Persistent project keys / Projektben tárolt állapotkulcsok.
-- They link each media item to its generated region without changing the visible name.
-- Ezek az itemet a létrehozott régióhoz kapcsolják a látható régiónév módosítása nélkül.
local SECTION = "SarkamentAdam.RegionCreator.v4"
local SETTINGS_KEY = "settings"
local MIN_REGION_LENGTH = 0.001 -- 1 ms

-- Split the settings saved between runs / A futtatások között mentett beállítások felbontása.
local function split_settings(value)
  local values = {}
  for part in (value .. "|"):gmatch("(.-)|") do
    values[#values + 1] = part
  end
  return values
end

-- Read REAPER's stable item identifier / A REAPER állandó item-azonosítójának lekérése.
local function get_item_guid(item)
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return ok and guid or nil
end

-- Find a region by its REAPER region ID / Régió megkeresése a REAPER régióazonosítója alapján.
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

-- Find an exact region match to avoid duplicates and adopt compatible older regions.
-- Pontosan egyező régió keresése duplikáció elkerüléséhez és régebbi régiók átvételéhez.
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

-- Build the name source selected by the user: take, file, track, or custom text.
-- A felhasználó által választott névforrás elkészítése: take, fájl, track vagy saját szöveg.
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

-- Resolve the color mode for one item / Egy itemhez tartozó színmód feloldása.
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

-- Keep regions separated. First shorten the previous region; if that is impossible, move the next one.
-- Régiótávolság tartása. Először az előző régió rövidül, szükség esetén a következő eltolódik.
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
        -- Identical or fully overlapping regions cannot be shortened safely, so move the next one.
        -- Azonos vagy teljesen átfedő régiókat nem lehet biztonságosan rövidíteni, ezért a következő eltolódik.
        current.start_pos = previous.end_pos + minimum_gap
        if current.end_pos <= current.start_pos then
          current.end_pos = current.start_pos + MIN_REGION_LENGTH
        end
      end
    end
  end

  return collisions
end

-- Add a two-digit sequence number plus optional prefix and suffix.
-- Kétjegyű sorszám, valamint opcionális elő- és utótag hozzáadása.
local function make_region_name(index, item, source_choice, prefix, suffix)
  local base_name = get_item_name(item, source_choice, prefix)
  local name_prefix = source_choice == "4" and "" or prefix
  return string.format("%02d_%s%s%s", index, name_prefix, base_name, suffix)
end

-- Read a previously saved item-to-region link / Korábban mentett item–régió kapcsolat beolvasása.
local function get_mapped_region_id(item)
  local guid = get_item_guid(item)
  if not guid then return nil end
  local ok, value = reaper.GetProjExtState(0, SECTION, guid)
  return ok == 1 and tonumber(value) or nil
end

-- Save the item-to-region link inside the current project / Item–régió kapcsolat mentése az aktuális projektbe.
local function save_region_mapping(item, region_id)
  local guid = get_item_guid(item)
  if guid then
    reaper.SetProjExtState(0, SECTION, guid, tostring(region_id))
  end
end

-- Restore the last dialog values / Legutóbbi párbeszédablak-értékek visszatöltése.
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

-- Show a compact legend before the settings dialog / Rövid súgó megjelenítése a beállítóablak előtt.
reaper.ShowMessageBox(
  "Művelet: 1 = Létrehozás / frissítés, 2 = Csak frissítés\n\n" ..
  "Névforrás: 1 = Take-név, 2 = Fájlnév, 3 = Track-név, 4 = Saját név\n" ..
  "Szín: 1 = Véletlen, 2 = Saját szín, 3 = Track színe\n\n" ..
  "Átfedéskor a script legalább a megadott távolságot tartja, majd figyelmeztet.",
  "Régiókészítő v4 – súgó",
  0
)

-- Collect creation, naming, spacing, and color preferences / Létrehozási, névadási, távolság- és színbeállítások bekérése.
local retval, user_input = reaper.GetUserInputs(
  "Régiókészítő v4",
  8,
  "Művelet (1-2),Előtte (ms),Utána (ms),Min. távolság (ms),Névforrás (1-4),Előtag / saját név,Utótag,Szín (1-3),separator=|,extrawidth=460",
  table.concat(defaults, "|")
)
if not retval then return end

-- Parse and validate the dialog data / Párbeszédablak adatainak feldolgozása és ellenőrzése.
local mode, before_text, after_text, gap_text, source_choice, prefix, suffix, color_mode =
  user_input:match("^(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)$")

local before_ms = tonumber(before_text)
local after_ms = tonumber(after_text)
local gap_ms = tonumber(gap_text)
if (mode ~= "1" and mode ~= "2") or not before_ms or not after_ms or not gap_ms or
   before_ms < 0 or after_ms < 0 or gap_ms < 0 or
   (source_choice ~= "1" and source_choice ~= "2" and source_choice ~= "3" and source_choice ~= "4") or
   (color_mode ~= "1" and color_mode ~= "2" and color_mode ~= "3") then
  -- Report invalid settings / Érvénytelen beállítások jelzése.
reaper.ShowMessageBox("Ellenőrizd a számértékeket és a választási kódokat.", "Érvénytelen beállítás", 0)
  return
end

-- Remember settings for the next run / Beállítások megjegyzése a következő futtatáshoz.
reaper.SetExtState(SECTION, SETTINGS_KEY, user_input, true)

-- Open REAPER's native color picker only for the fixed-color mode.
-- A REAPER saját színválasztója csak az egyedi színmódnál nyílik meg.
local fixed_color = reaper.ColorToNative(70, 130, 180) | 0x1000000
if mode == "1" and color_mode == "2" then
  local color_ok, chosen_color = reaper.GR_SelectColor(0, fixed_color)
  if color_ok == 0 then return end
  fixed_color = chosen_color | 0x1000000
end

-- Work only on selected media items / Csak a kijelölt médiaitemek feldolgozása.
local item_count = reaper.CountSelectedMediaItems(0)
if item_count == 0 then
  -- Stop when no media items are selected / Leállás, ha nincs kijelölt médiaitem.
reaper.ShowMessageBox("Jelölj ki legalább egy médiaitemet.", "Nincs kijelölt item", 0)
  return
end

-- Prepare the requested region changes before modifying the project.
-- A kért régiómódosítások előkészítése a projekt tényleges módosítása előtt.
math.randomseed(os.time())
local before_seconds = before_ms / 1000
local after_seconds = after_ms / 1000
local gap_seconds = gap_ms / 1000
local work = {}
local skipped_duplicates = 0
local missing_mappings = 0

-- Create a work list. In refresh-only mode, untracked regions are deliberately left untouched.
-- Munkalista készítése. Csak frissítés módban a nem követett régiók szándékosan érintetlenek maradnak.
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
      -- Adopt an exact older region so later refresh-only runs can find it.
      -- Pontosan egyező régebbi régió átvétele, hogy a későbbi csak-frissítés mód megtalálja.
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
  -- Stop when there is no region work to perform / Leállás, ha nincs feldolgozható régió.
reaper.ShowMessageBox("Nincs létrehozható vagy frissíthető régió.", "Régiókészítő v4", 0)
  return
end

-- Resolve collisions before a single undoable project update.
-- Ütközések feloldása egyetlen visszavonható projektmódosítás előtt.
local collisions = apply_spacing(work, gap_seconds)
reaper.Undo_BeginBlock()

-- Apply creates and updates, then store a link for every handled item.
-- Létrehozások és frissítések végrehajtása, majd kapcsolat mentése minden kezelt itemhez.
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

-- Summarize the result, including collisions and skipped items.
-- Eredmény összegzése, az ütközésekkel és kihagyott itemekkel együtt.
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
-- Present the completion summary / Befejezési összegzés megjelenítése.
reaper.ShowMessageBox(table.concat(messages, "\n"), "Régiókészítő v4", 0)