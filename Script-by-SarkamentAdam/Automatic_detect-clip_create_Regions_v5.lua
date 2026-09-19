--[[
Automatic_detect-clip_create_Regions_v5
ReaImGui kezelőfelület a kiválasztott médiaitemek régióinak létrehozásához és frissítéséhez.

V5 | 2026.09.19.
• Intuitív ReaImGui felület feliratozott választókkal és színmezővel.
• A v4 által tárolt item–régió kapcsolatokkal kompatibilis.
• Külön gomb a létrehozás/frissítéshez és a csak pozíció-frissítéshez.

Függőség / Dependency: ReaImGui (telepíthető ReaPackből).
--]]

-- Stop with a helpful message when ReaImGui is unavailable.
-- Hasznos hibaüzenettel leáll, ha a ReaImGui nincs telepítve.
if not reaper.ImGui_CreateContext then
  reaper.MB("A ReaImGui bővítmény szükséges ehhez a v5 felülethez.\nTelepítsd ReaPackből: ReaTeam Extensions > ReaImGui.", "Hiányzó ReaImGui", 0)
  return
end

-- Keep the v4 mapping section so existing tracked regions remain refreshable.
-- A v4 kapcsolati szakaszát használjuk, így a régi követett régiók is frissíthetők maradnak.
local MAP_SECTION = "SarkamentAdam.RegionCreator.v4"
local SETTINGS_SECTION = "SarkamentAdam.RegionCreator.v5"
local SETTINGS_KEY = "gui_settings"
local MIN_REGION_LENGTH = 0.001

local NAME_SOURCES = "Take-név\0Fájlnév\0Track-név\0Saját név\0\0"
local COLOR_MODES = "Véletlen szín\0Saját szín\0Track színe\0\0"

local function split(value)
  local fields = {}
  for field in (value .. "|"):gmatch("(.-)|") do fields[#fields + 1] = field end
  return fields
end

local function get_item_guid(item)
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return ok and guid or nil
end

-- Find a region by its displayed REAPER region ID / Régió keresése a REAPER régióazonosítója alapján.
local function get_region_by_id(region_id)
  local i = 0
  while true do
    local retval, is_region, start_pos, end_pos, name, id, color = reaper.EnumProjectMarkers3(0, i)
    if retval == 0 then return nil end
    if is_region and id == region_id then
      return { id = id, start_pos = start_pos, end_pos = end_pos, name = name, color = color }
    end
    i = i + 1
  end
end

-- Locate an exact region match to prevent duplicates and adopt older v3/v4 regions.
-- Pontosan egyező régió keresése a duplikáció elkerüléséhez és régi v3/v4 régiók átvételéhez.
local function find_matching_region(start_pos, end_pos)
  local i, epsilon = 0, 0.000001
  while true do
    local retval, is_region, existing_start, existing_end, name, id, color = reaper.EnumProjectMarkers3(0, i)
    if retval == 0 then return nil end
    if is_region and math.abs(existing_start - start_pos) < epsilon and math.abs(existing_end - end_pos) < epsilon then
      return { id = id, name = name, color = color }
    end
    i = i + 1
  end
end

local function get_mapped_region_id(item)
  local guid = get_item_guid(item)
  if not guid then return nil end
  local ok, value = reaper.GetProjExtState(0, MAP_SECTION, guid)
  return ok == 1 and tonumber(value) or nil
end

local function save_region_mapping(item, region_id)
  local guid = get_item_guid(item)
  if guid then reaper.SetProjExtState(0, MAP_SECTION, guid, tostring(region_id)) end
end

-- Resolve the selected name source / A kiválasztott névforrás feloldása.
local function get_item_name(item, name_source, custom_name)
  if name_source == 3 then return custom_name ~= "" and custom_name or "Régió" end
  local take = reaper.GetActiveTake(item)
  if name_source == 0 then
    local name = take and reaper.GetTakeName(take) or ""
    return name ~= "" and name or "Névtelen"
  end
  if name_source == 1 and take then
    local source = reaper.GetMediaItemTake_Source(take)
    local ok, filename = reaper.GetMediaSourceFileName(source, "")
    if ok and filename ~= "" then
      local basename = filename:match("([^\\/]+)$") or filename
      return (basename:gsub("%.[^%.]+$", ""))
    end
  end
  if name_source == 2 then
    local ok, track_name = reaper.GetTrackName(reaper.GetMediaItem_Track(item), "")
    if ok and track_name ~= "" then return track_name end
  end
  return "Névtelen"
end

local function make_region_name(index, item, settings)
  local base_name = get_item_name(item, settings.name_source, settings.prefix)
  local prefix = settings.name_source == 3 and "" or settings.prefix
  return string.format("%02d_%s%s%s", index, prefix, base_name, settings.suffix)
end

local function native_color(settings, item)
  if settings.color_mode == 0 then
    return reaper.ColorToNative(math.random(60, 255), math.random(60, 255), math.random(60, 255)) | 0x1000000
  end
  if settings.color_mode == 2 then
    local color = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(item), "I_CUSTOMCOLOR")
    if color ~= 0 then return color end
  end
  return reaper.ColorToNative(math.floor(settings.red * 255), math.floor(settings.green * 255), math.floor(settings.blue * 255)) | 0x1000000
end

-- Enforce the minimum gap. It shortens the previous region first, then moves the next one if needed.
-- A minimális távolság betartása: először az előző régió rövidül, utána szükség esetén a következő eltolódik.
local function apply_spacing(regions, gap)
  table.sort(regions, function(a, b) return a.start_pos < b.start_pos end)
  local collisions = 0
  for i = 2, #regions do
    local previous, current = regions[i - 1], regions[i]
    if previous.end_pos + gap > current.start_pos then
      collisions = collisions + 1
      local allowed_end = current.start_pos - gap
      if allowed_end > previous.start_pos then
        previous.end_pos = allowed_end
      else
        current.start_pos = previous.end_pos + gap
        if current.end_pos <= current.start_pos then current.end_pos = current.start_pos + MIN_REGION_LENGTH end
      end
    end
  end
  return collisions
end

local function save_settings(s)
  reaper.SetExtState(SETTINGS_SECTION, SETTINGS_KEY, table.concat({
    s.before_ms, s.after_ms, s.gap_ms, s.name_source, s.prefix, s.suffix,
    s.color_mode, s.red, s.green, s.blue
  }, "|"), true)
end

local function load_settings()
  local v = split(reaper.GetExtState(SETTINGS_SECTION, SETTINGS_KEY))
  return {
    before_ms = tonumber(v[1]) or 0, after_ms = tonumber(v[2]) or 0, gap_ms = tonumber(v[3]) or 1,
    name_source = tonumber(v[4]) or 0, prefix = v[5] or "", suffix = v[6] or "",
    color_mode = tonumber(v[7]) or 0, red = tonumber(v[8]) or 0.27,
    green = tonumber(v[9]) or 0.51, blue = tonumber(v[10]) or 0.71
  }
end

-- Create or refresh all selected items. Refresh-only preserves existing names and colors.
-- Kijelölt itemek létrehozása vagy frissítése. Csak frissítés módban a név és szín megmarad.
local function process_regions(settings, refresh_only)
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return "Nincs kijelölt médiaitem." end

  math.randomseed(os.time())
  local before, after, gap = math.max(0, settings.before_ms) / 1000, math.max(0, settings.after_ms) / 1000, math.max(0, settings.gap_ms) / 1000
  local work, untracked = {}, 0

  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local desired_start = math.max(0, item_start - before)
    local desired_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH") + after
    local id = get_mapped_region_id(item)
    local mapped = id and get_region_by_id(id) or nil

    if refresh_only then
      if mapped then
        work[#work + 1] = { item = item, action = "update", id = id, start_pos = desired_start, end_pos = desired_end, name = mapped.name, color = mapped.color }
      else
        untracked = untracked + 1
      end
    elseif mapped then
      work[#work + 1] = { item = item, action = "update", id = id, start_pos = desired_start, end_pos = desired_end, name = make_region_name(i + 1, item, settings), color = native_color(settings, item) }
    else
      local matching = find_matching_region(desired_start, desired_end)
      if matching then
        work[#work + 1] = { item = item, action = "update", id = matching.id, start_pos = desired_start, end_pos = desired_end, name = make_region_name(i + 1, item, settings), color = native_color(settings, item) }
      else
        work[#work + 1] = { item = item, action = "create", start_pos = desired_start, end_pos = desired_end, name = make_region_name(i + 1, item, settings), color = native_color(settings, item) }
      end
    end
  end

  if #work == 0 then return "Nincs létrehozható vagy frissíthető régió." end
  local collisions = apply_spacing(work, gap)
  reaper.Undo_BeginBlock()
  local created, updated = 0, 0
  for _, region in ipairs(work) do
    if region.action == "create" then
      local id = reaper.AddProjectMarker2(0, true, region.start_pos, region.end_pos, region.name, -1, region.color)
      save_region_mapping(region.item, id)
      created = created + 1
    else
      reaper.SetProjectMarker3(0, region.id, true, region.start_pos, region.end_pos, region.name, region.color)
      save_region_mapping(region.item, region.id)
      updated = updated + 1
    end
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Régiók létrehozása/frissítése v5", -1)

  local result = string.format("Kész — létrehozva: %d | frissítve: %d", created, updated)
  if collisions > 0 then result = result .. string.format(" | Ütközés korrigálva: %d", collisions) end
  if untracked > 0 then result = result .. string.format(" | Nem követett item: %d", untracked) end
  return result
end

local ctx = reaper.ImGui_CreateContext("Régiókészítő v5")
local settings = load_settings()
local status = "Állítsd be a régiókat, majd válassz műveletet."

local function input_int(label, value)
  local changed, new_value = reaper.ImGui_InputInt(ctx, label, value)
  return changed and math.max(0, new_value) or value
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 520, 560, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, "Régiókészítő v5", true)
  if visible then
    reaper.ImGui_TextWrapped(ctx, "Kijelölt médiaitemekből régiókat hoz létre, illetve követett régiókat frissít.")
    reaper.ImGui_Separator(ctx)

    reaper.ImGui_Text(ctx, "Régióhatárok")
    settings.before_ms = input_int("Ráhagyás előtte (ms)", settings.before_ms)
    settings.after_ms = input_int("Ráhagyás utána (ms)", settings.after_ms)
    settings.gap_ms = input_int("Minimális távolság (ms)", settings.gap_ms)
    reaper.ImGui_TextDisabled(ctx, "Ütközéskor a rendszer megtartja ezt a távolságot.")

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Elnevezés")
    local changed, name_source = reaper.ImGui_Combo(ctx, "Név forrása", settings.name_source, NAME_SOURCES)
    if changed then settings.name_source = name_source end
    if settings.name_source == 3 then
      local text_changed, text = reaper.ImGui_InputText(ctx, "Saját név", settings.prefix)
      if text_changed then settings.prefix = text end
    else
      local prefix_changed, prefix = reaper.ImGui_InputText(ctx, "Előtag", settings.prefix)
      if prefix_changed then settings.prefix = prefix end
    end
    local suffix_changed, suffix = reaper.ImGui_InputText(ctx, "Utótag", settings.suffix)
    if suffix_changed then settings.suffix = suffix end
    local preview_source = settings.name_source == 3 and (settings.prefix ~= "" and settings.prefix or "Régió") or "[választott név]"
    local preview_prefix = settings.name_source == 3 and "" or settings.prefix
    reaper.ImGui_TextDisabled(ctx, "Előnézet: 01_" .. preview_prefix .. preview_source .. settings.suffix)

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Színezés")
    local color_changed, color_mode = reaper.ImGui_Combo(ctx, "Régió színe", settings.color_mode, COLOR_MODES)
    if color_changed then settings.color_mode = color_mode end
    if settings.color_mode == 1 then
      -- ReaImGui ColorEdit3 takes one packed ImGui color, not separate RGB values.
      -- A ReaImGui ColorEdit3 egyetlen csomagolt színt vár, nem külön RGB értékeket.
      local native = reaper.ColorToNative(
        math.floor(settings.red * 255), math.floor(settings.green * 255), math.floor(settings.blue * 255)
      )
      local imgui_color = reaper.ImGui_ColorConvertNative(native)
      local edited, selected_color = reaper.ImGui_ColorEdit3(ctx, "Saját szín", imgui_color)
      if edited then
        local selected_native = reaper.ImGui_ColorConvertNative(selected_color)
        settings.red, settings.green, settings.blue = reaper.ColorFromNative(selected_native)
        settings.red, settings.green, settings.blue = settings.red / 255, settings.green / 255, settings.blue / 255
      end
    elseif settings.color_mode == 2 then
      reaper.ImGui_TextDisabled(ctx, "A régió az item sávjának színét veszi át.")
    else
      reaper.ImGui_TextDisabled(ctx, "Minden új vagy teljesen frissített régió véletlen színt kap.")
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Régiók létrehozása / frissítése") then
      save_settings(settings)
      status = process_regions(settings, false)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Csak pozíciók frissítése") then
      save_settings(settings)
      status = process_regions(settings, true)
    end
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, status)
    reaper.ImGui_Separator(ctx)
    -- Subtle footer / Visszafogott lábléc.
    reaper.ImGui_TextDisabled(ctx, "Régiókészítő v0.5a | By Sarkament Ádám © 2026")
    reaper.ImGui_End(ctx)
  end
  if open then
    reaper.defer(loop)
  elseif reaper.ImGui_DestroyContext then
    -- Older ReaImGui versions may not expose this optional cleanup function.
    -- Régebbi ReaImGui-verziókban ez az opcionális felszabadító függvény hiányozhat.
    reaper.ImGui_DestroyContext(ctx)
  end
end

loop()