--[[
    import_Afilm_metadata.lua - plugin for darktable
    Version 1.0
	
    Copyright (C) 2026 George Xystouris
	https://github.com/gxystouris/A

	SPDX-License-Identifier: GPL-2.0-or-later

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
]]
--[[
	Darktable Lua script that applies metadata from the Afilm app
    .json log file to the imported photos.

    MAPPING RULE (v1):
    The .json frames metadata are mapped 1:1 to the imported photos, 
	in the order they were imported, (usually this is sorted by name).
    E.g. if the photos are named r001, r002, r003 etc., this script will apply 
    the .json metadata for frame 1 to r001, for frame 2 to r002 etc. If the
    number of imported images does not match the number of frames in the
    .json file, nothing will be written and you will get a message with 
    both counts so you can fix the selection.
    
    (A manual per-frame mapping table for partial rolls / mismatches is planned
    for a follow-up version.)

    Requires: exiftool on PATH -- https://exiftool.org
    Test with: exiftool -ver   (from a terminal)

    INSTALL:
      1. Copy this file into your darktable lua scripts folder:
		 Windows: %LOCALAPPDATA%\darktable\lua\contrib\
		 Linux (untested):  ~/.config/darktable/lua/contrib/
		 macOS (untested):  ~/Library/Application Support/darktable/lua/contrib/
      2. Restart darktable, then go to preferences -> lua options and
         enable "import_Afilm_metadata".
      3. Restart darktable again. A new "import Afilm metadata" section should
         appear in the lighttable left panel.

    BEFORE YOU START:
      - Put the Afilm .json export in the same folder as the scans,
        and make sure it is the only .json file there.
      - Name your scans so they sort in shooting order
        (e.g. r001, r002, r003 ...). Frame 1 goes to the first file,
        frame 2 to the second, and so on.
      - This script WRITES INTO YOUR IMAGE FILES (via ExifTool).
        Keep a backup of your scans.

    USAGE:
      1. Import the roll into darktable, then double-click its folder
         in the collections module so only that roll is shown.
      2. In the lighttable's left panel, open "import Afilm metadata"
         and click "Detect JSON from current folder".
         (You can also pick the file yourself with the file button.)
      3. Click "Apply metadata to collection".
      4. Wait for the "Done" message. The images are removed from and
         re-imported into darktable so it picks up the new metadata;
         the files on disk stay where they are.

    TIPS:
      - Run this right after importing, BEFORE you start editing.
        Edits stored only in darktable's library can be lost when the
        images are re-imported (they are restored from .xmp sidecars
        if sidecar writing is on, which is the default).
      - If the number of images doesn't match the number of frames in
        the .json, nothing is written and the message shows both counts.
        Remove or add images until they match, then try again.
      - Something went wrong? Check Help -> Show Log for the details.
    
]]

local dt = require "darktable"
local MODULE = "import_Afilm_metadata"

-- set a single path separator for avoiding mismatches
local PATH_SEP = "/"

local function normalise_path(p)
  return p:gsub("\\", "/")
end

-- lists .json files in a folder, using the right shell command for the OS
local function find_json_files(folder)
  local found = {}
  local cmd
  if dt.configuration.running_os == "windows" then
    cmd = 'dir /b "' .. folder:gsub("/", "\\") .. '"'
  else -- linux and macOS
    cmd = 'ls -1 "' .. folder .. '"'
  end
  local handle = io.popen(cmd)
  if handle then
    for line in handle:lines() do
      if line:lower():match("%.json$") then
        table.insert(found, line)
      end
    end
    handle:close()
  end
  return found
end


-- ---------------------------------------------------------------------
-- minimal JSON decoder (hand-written recursive descent; no dependencies)
-- ---------------------------------------------------------------------
local function json_decode(str)
  local pos = 1
  local len = #str

  local function skip_ws()
    while pos <= len and str:sub(pos, pos):match("%s") do pos = pos + 1 end
  end

  local parse_value

  local function parse_string()
    pos = pos + 1 -- opening quote
    local buf = {}
    while true do
      local c = str:sub(pos, pos)
      if c == "" then error("Unterminated string in JSON") end
      if c == '"' then pos = pos + 1 break end
      if c == "\\" then
        local nc = str:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f",
                      ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if map[nc] then
          table.insert(buf, map[nc])
          pos = pos + 2
        elseif nc == "u" then
          local hex = str:sub(pos + 2, pos + 5)
          local code = tonumber(hex, 16) or 63
          table.insert(buf, code < 128 and string.char(code) or "?")
          pos = pos + 6
        else
          table.insert(buf, nc)
          pos = pos + 2
        end
      else
        table.insert(buf, c)
        pos = pos + 1
      end
    end
    return table.concat(buf)
  end

  local function parse_number()
    local start = pos
    while pos <= len and str:sub(pos, pos):match("[%d%.%-%+eE]") do pos = pos + 1 end
    return tonumber(str:sub(start, pos - 1))
  end

  local function parse_object()
    pos = pos + 1
    local obj = {}
    skip_ws()
    if str:sub(pos, pos) == "}" then pos = pos + 1 return obj end
    while true do
      skip_ws()
      local key = parse_string()
      skip_ws()
      pos = pos + 1 -- ':'
      skip_ws()
      obj[key] = parse_value()
      skip_ws()
      local c = str:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "}" then pos = pos + 1 break
      else error("Expected , or } at position " .. pos) end
    end
    return obj
  end

  local function parse_array()
    pos = pos + 1
    local arr = {}
    skip_ws()
    if str:sub(pos, pos) == "]" then pos = pos + 1 return arr end
    while true do
      skip_ws()
      table.insert(arr, parse_value())
      skip_ws()
      local c = str:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "]" then pos = pos + 1 break
      else error("Expected , or ] at position " .. pos) end
    end
    return arr
  end

  parse_value = function()
    skip_ws()
    local c = str:sub(pos, pos)
    if c == '"' then return parse_string()
    elseif c == "{" then return parse_object()
    elseif c == "[" then return parse_array()
    elseif c == "t" then pos = pos + 4; return true
    elseif c == "f" then pos = pos + 5; return false
    elseif c == "n" then pos = pos + 4; return nil
    else return parse_number()
    end
  end

  skip_ws()
  return parse_value()
end

-- ---------------------------------------------------------------------
-- metadata / exiftool helpers
-- ---------------------------------------------------------------------

-- turns "f/4.8" -> "4.8"
local function strip_f(aperture)
  if not aperture then return nil end
  aperture = aperture:gsub("^~", "")  -- drop leading ~
  return aperture:match("f/([%d%.]+)")
end

-- normalises shutter speed strings from the logging app:
--   "1/250"  -> "1/250"   (pass through)
--   "~2"     -> "2"       (drop tilde)
--   "2-3"    -> "2.5"     (average)
--   "~10-15" -> "12.5"    (drop tilde, then average)
local function strip_shutter(s)
  if not s or s == "" then return nil end
  s = s:gsub("^~", "")
  local lo, hi = s:match("^([%d%.]+)-([%d%.]+)$")
  if lo and hi then
    return tostring((tonumber(lo) + tonumber(hi)) / 2)
  end
  return s
end

-- extracts focal length from lens name if unambiguous:
--   "Porst 35mm"        -> "35"
--   "Zoom 35mm-150mm"   -> nil  (more than one match, do nothing)
--   "Carl Zeiss Jena"   -> nil  (no match)
local function extract_focal_length(lens_name)
  if not lens_name or lens_name == "" then return nil end
  local matches = {}
  for n in lens_name:gmatch("(%d+)%s*mm") do
    table.insert(matches, n)
  end
  if #matches == 1 then
    return matches[1]
  end
  return nil
end

-- turns "2025-08-24T17:07:19.734" -> "2025:08:24 17:07:19"
local function iso_to_exif_date(iso_date)
  if not iso_date then return nil end
  local y, mo, d, h, mi, s = iso_date:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  return string.format("%s:%s:%s %s:%s:%s", y, mo, d, h, mi, s)
end

local function build_exif_args(roll, frame)
  local args = {}
  local function add(tag, value)
    if value ~= nil and value ~= "" then
      table.insert(args, string.format("-%s=%s", tag, tostring(value)))
    end
  end

  add("Model", roll.cameraName)
  add("ISO", roll.iso)

  if frame.lensName and frame.lensName ~= "" then
    add("LensModel", frame.lensName)
    add("FocalLength", extract_focal_length(frame.lensName))
  end

  add("FNumber", strip_f(frame.aperture))
  add("ExposureTime", strip_shutter(frame.shutterSpeed))
  add("DateTimeOriginal", iso_to_exif_date(frame.date))

  if frame.note and frame.note ~= "" then
    add("XMP-dc:Description", frame.note)
    add("IPTC:Caption-Abstract", frame.note)
  end

  if frame.location then
    local lat, lon = frame.location.latitude, frame.location.longitude
    if lat then
      add("GPSLatitude", math.abs(lat))
      add("GPSLatitudeRef", lat >= 0 and "N" or "S")
    end
    if lon then
      add("GPSLongitude", math.abs(lon))
      add("GPSLongitudeRef", lon >= 0 and "E" or "W")
    end
  end

  return args
end

-- writes an exiftool "-@ argfile" so we never have to shell-escape notes,
-- quotes, or unicode in the JSON ourselves
local function apply_metadata_to_file(filepath, args)
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  for _, a in ipairs(args) do
    f:write(a .. "\n")
  end
  f:write("-overwrite_original\n")
  f:close()

  local cmd = string.format('exiftool -@ "%s" "%s"', tmp, filepath)
  local handle = io.popen(cmd .. " 2>&1")
  local result = handle and handle:read("*a") or ""
  if handle then handle:close() end
  os.remove(tmp)
  return result
end


-- ---------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------
local function get_collection_folder()
  for _, img in ipairs(dt.collection) do
    return normalise_path(img.path)
  end
  return nil
end

local file_chooser = dt.new_widget("file_chooser_button") {
  title = "Choose roll .json file",
  value = "",
  is_directory = false,
  tooltip = "Select the per-roll metadata JSON file exported from your logging app",
}

local status_label = dt.new_widget("label") { label = "" }

local function set_status(msg)
  status_label.label = msg
  dt.print(msg)
end

local function run_apply()
  -- find the JSON: manual choice takes priority, then auto-detect in collection folder
  local json_path = file_chooser.value
  if not json_path or json_path == "" then
    local folder = get_collection_folder()
    if not folder then
      set_status("No collection open — double-click a folder first")
      return
    end
    local found = find_json_files(folder)
    if #found == 0 then
      set_status("No .json file found in " .. folder)
      return
    elseif #found > 1 then
      set_status("More than one .json found in " .. folder .. " — remove the extra ones")
      return
    else
      json_path = folder .. PATH_SEP .. found[1]
    end
  end

  local f = io.open(json_path, "r")
  if not f then
    set_status("Could not open file: " .. json_path)
    return
  end
  local content = f:read("*a")
  f:close()

  local ok, roll = pcall(json_decode, content)
  if not ok or type(roll) ~= "table" or type(roll.frames) ~= "table" then
    set_status("Could not parse JSON, or no 'frames' object found")
    return
  end

  local frame_keys = {}
  for k, _ in pairs(roll.frames) do
    table.insert(frame_keys, tonumber(k))
  end
  table.sort(frame_keys)

  local images = {}
  for _, img in ipairs(dt.collection) do
    table.insert(images, img)
  end
  table.sort(images, function(a, b) return a.filename < b.filename end)

  if #images == 0 then
    set_status("No images in current collection — double-click a folder first")
    return
  end

  -- safety 1: ensure all images are from the same folder
  local first_folder = normalise_path(images[1].path)
  for _, img in ipairs(images) do
    if normalise_path(img.path) ~= first_folder then
      set_status("Images span multiple folders — open a single roll folder and try again")
      return
    end
  end

  -- safety 2: ensure there is exactly one .json file in the folder
  local json_count = #find_json_files(first_folder)
  if json_count == 0 then
    set_status("No .json file found in " .. first_folder)
    return
  end
  if json_count > 1 then
    set_status("More than one .json found in " .. first_folder .. " — remove the extra ones")
    return
  end

  if #images ~= #frame_keys then
    set_status(string.format(
      "Mismatch: %d image(s) in collection vs %d frame(s) in JSON. Nothing written.",
      #images, #frame_keys))
    return
  end

  local errors = 0
  for i, frame_num in ipairs(frame_keys) do
    local frame = roll.frames[tostring(frame_num)]
    local image = images[i]
    local filepath = normalise_path(image.path) .. PATH_SEP .. image.filename
    local args = build_exif_args(roll, frame)
    local result = apply_metadata_to_file(filepath, args)
    if result and result:lower():match("error") then
      errors = errors + 1
      dt.print_error(image.filename .. ": " .. result)
    end
  end

  -- remove and re-import each image to force EXIF refresh
  local paths = {}
  for _, image in ipairs(images) do
    table.insert(paths, {path = image.path, filename = image.filename})
  end
  for _, image in ipairs(images) do
    dt.database.delete(image)
  end
  for _, p in ipairs(paths) do
    dt.database.import(p.path .. PATH_SEP .. p.filename)
  end

  set_status(string.format(
    "Done: %d image(s) processed, %d error(s). Images reloaded.",
    #images, errors))
end

local detect_button = dt.new_widget("button") {
  label = "Detect JSON from current folder",
  tooltip = "Looks for a .json file in the folder of the current collection",
  clicked_callback = function()
    local folder = get_collection_folder()
    if not folder then
      set_status("No collection open — double-click a folder first")
      return
    end
    set_status("Scanning: " .. folder)
    local found = find_json_files(folder)
    if #found == 0 then
      set_status("No .json file found in " .. folder)
    elseif #found > 1 then
      set_status("More than one .json found in " .. folder .. " — remove the extra ones")
    else
      local full_path = folder .. PATH_SEP .. found[1]
      file_chooser.value = full_path
      set_status("Found: " .. full_path)
    end
  end,
}

local apply_button = dt.new_widget("button") {
  label = "Apply metadata to collection",
  tooltip = "Applies JSON metadata to all images in the current collection, sorted by filename",
  clicked_callback = run_apply,
}

local widget = dt.new_widget("box") {
  orientation = "vertical",
  dt.new_widget("label") { label = "Film roll metadata" },
  file_chooser,
  detect_button,
  apply_button,
  status_label,
}

dt.register_lib(
  MODULE,
  "import Afilm metadata",
  true,
  true,
  { [dt.gui.views.lighttable] = { "DT_UI_CONTAINER_PANEL_LEFT_CENTER", 100 } },
  widget
)