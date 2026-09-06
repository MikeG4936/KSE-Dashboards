-- Bound native image allocations before giving a candidate to LVGL. Header
-- checks establish dimensions, not complete PNG/BMP decoder validity.
local function modelImageAllowed(path)
  local stat = _G.fstat
  if type(stat) ~= "function" then return false end
  local ok, info = pcall(stat, path)
  local size = ok and type(info) == "table" and tonumber(info.size) or nil
  if not size or size < 26 or size > 100 * 1024 then return false end
  local opened, file = pcall(io.open, path, "r")
  if not opened or not file then return false end
  local readOk, header = pcall(io.read, file, math.min(54, size))
  pcall(io.close, file)
  if not readOk or type(header) ~= "string"
     or #header ~= math.min(54, size) then return false end
  local function word(offset, bytes, little)
    local value = 0
    for i = 0, bytes - 1 do
      local position = little and offset + bytes - 1 - i or offset + i
      value = (value << 8) | string.byte(header, position)
    end
    return value
  end
  local width, height
  if #header >= 33 and string.sub(header, 1, 8) == "\137PNG\r\n\26\n"
     and word(9, 4) == 13 and string.sub(header, 13, 16) == "IHDR" then
    width, height = word(17, 4), word(21, 4)
  elseif string.sub(header, 1, 2) == "BM" then
    local dib = word(15, 4, true)
    if dib == 12 then
      width, height = word(19, 2, true), word(21, 2, true)
    elseif dib >= 40 and #header >= 54 and dib <= size - 14 then
      width, height = word(19, 4, true), word(23, 4, true)
      -- A negative BMP height denotes rows stored from top to bottom.
      if height < 0 then height = -height end
    end
  end
  return width ~= nil and height ~= nil
         and width > 0 and width <= 480 and height > 0 and height <= 272
end

local function resolveModelImagePath()
  local name = getModelName()
  if modelImageName == name then return modelImagePath end
  local sanitized = sanitizeFsName(name)
  if not sanitized or sanitized == "" then sanitized = "MODEL" end
  -- Never concatenate raw model text into an SD-card path. The sanitized name
  -- preserves normal names while preventing separators from escaping /IMAGES.
  local candidates = {
    "/IMAGES/" .. sanitized .. ".png",
    "/IMAGES/" .. sanitized .. ".bmp",
    G.assetRoot .. "/default.png",
  }
  candidates[#candidates+1] = "/IMAGES/default.png"
  candidates[#candidates+1] = "/IMAGES/defaultmodel.png"
  candidates[#candidates+1] = G.assetRoot .. "/Rotorflight.png"
  modelImagePath = nil
  for _, path in ipairs(candidates) do
    if modelImageAllowed(path) then modelImagePath = path; break end
  end
  modelImageName = name
  return modelImagePath
end
