-- Shared KSE count storage; assembled into each standalone dashboard.
-- EdgeTX v2.12.1: io.read hides errors as ""; fstat size is required.
-- Global rename/del return FatFS FRESULT; only numeric zero means success.
local Storage = { maxBytes=32768, maxEntries=200, retryTicks=500, maxAttempts=3 }

function Storage.stat(path)
  if type(_G.fstat) ~= "function" then return nil, "FSTAT UNAVAILABLE" end
  local ok, info = pcall(_G.fstat, path)
  if not ok then return nil, "STAT ERROR" end
  if info == nil then return nil, "MISSING" end
  if type(info) ~= "table" or type(info.size) ~= "number"
     or info.size < 0 or info.size > math.floor(info.size) then
    return nil, "STAT ERROR"
  end
  return info
end

function Storage.read(path)
  local before, reason = Storage.stat(path)
  if not before then return nil, reason end
  if before.size > Storage.maxBytes then return nil, "HISTORY TOO LARGE" end
  local ok, file = pcall(io.open, path, "r")
  if not ok or not file then return nil, "READ ERROR" end
  local parts, total, valid = {}, 0, true
  while total < before.size do
    -- Larger bounded reads reduce Lua/API overhead for the maximum history.
    local want = math.min(8192, before.size - total)
    local readOk, chunk = pcall(io.read, file, want)
    if not readOk or type(chunk) ~= "string" or #chunk ~= want then
      valid = false
      break
    end
    total = total + #chunk
    parts[#parts+1] = chunk
  end
  -- Check for extra data even when the initial size is an exact block multiple.
  local endOk, extra = pcall(io.read, file, 1)
  local closed = pcall(io.close, file)
  local after = Storage.stat(path)
  if not valid or not endOk or extra ~= "" or not closed
     or not after or after.size ~= before.size then return nil, "READ ERROR" end
  return table.concat(parts)
end

function Storage.parse(text)
  if type(text) ~= "string" or text == "" then return nil, "EMPTY HISTORY" end
  if #text > Storage.maxBytes then return nil, "HISTORY TOO LARGE" end
  local values, entries, header = {}, 0, false
  for line in string.gmatch(text, "[^\r\n]+") do
    local n = string.match(line, "^%s*(.-)%s*$")
    if n == "model_name,flight_count" then
      if header or entries > 0 then return nil, "MALFORMED HISTORY" end
      header = true
    elseif string.sub(n, 1, 1) == "#" then
      -- A model row beginning with # is indistinguishable from a comment in
      -- the existing format. Quarantine it rather than silently dropping it.
      if string.match(n, "^#[^,]*,%s*%d+%s*$") then
        return nil, "AMBIGUOUS MODEL NAME"
      end
    elseif n ~= "" then
      local key, digits = string.match(n, "^([^,]+),(%d+)$")
      key = key and string.match(key, "^%s*(.-)%s*$")
      local count = math.tointeger(tonumber(digits))
      if not key or key == "" or string.find(key, "%c")
         or not count or count < 0 or count > 2147483647
         or count ~= math.floor(count) or values[key] ~= nil then
        return nil, "MALFORMED HISTORY"
      end
      entries = entries + 1
      if entries > Storage.maxEntries then return nil, "TOO MANY MODELS" end
      values[key] = count
    end
  end
  if not header and entries == 0 then return nil, "EMPTY HISTORY" end
  return values
end

function Storage.readHistory(path)
  local text, reason = Storage.read(path)
  if not text then return nil, reason end
  local values, parseReason = Storage.parse(text)
  if not values then return nil, parseReason end
  return { values=values, text=text, path=path }
end

function Storage.new(path)
  return {path=path, cache=nil, writable=false, dirty=false,
          error=nil, attempts=0, nextAttempt=0, source=nil}
end

function Storage.load(state)
  -- Never reload an in-memory dirty generation and lose a counted event.
  if state.dirty then return state.cache end
  state.writable=false
  local main, mainReason = Storage.readHistory(state.path)
  if main then
    state.cache, state.source, state.baseText = main.values, "main", main.text
    state.writable, state.error = true, nil
    return state.cache
  end
  local backup, backupReason = Storage.readHistory(state.path .. ".bak")
  if backup then
    state.cache, state.source, state.baseText = backup.values, "backup", backup.text
    -- An unreadable/malformed main must not be replaced with a partial fallback.
    state.writable = mainReason == "MISSING"
    state.error = state.writable and "RECOVERED BACKUP" or mainReason
    return state.cache
  end
  local temp, tempReason = Storage.readHistory(state.path .. ".tmp")
  if temp then
    state.cache, state.source, state.baseText = temp.values, "temporary", temp.text
    state.error = "TEMP UNCONFIRMED"
    return state.cache -- A syntactically valid prefix cannot prove full history.
  end
  if mainReason == "MISSING" and backupReason == "MISSING"
     and tempReason == "MISSING" then
    local directory = string.match(state.path, "^(.*)/[^/]+$")
    local root = Storage.stat(directory == "" and "/" or directory or ".")
    if root then
      state.cache, state.source, state.baseText = {}, "new", nil
      state.writable, state.error = true, nil
      return state.cache
    end
    state.error = "STORAGE UNAVAILABLE"
  else
    state.error = mainReason ~= "MISSING" and mainReason
                  or backupReason ~= "MISSING" and backupReason or tempReason
  end
  state.cache, state.source, state.baseText = nil, nil, nil
  return nil
end

function Storage.serialize(values)
  local keys = {}
  for key, value in pairs(values) do
    if type(key) ~= "string" or key == "" or string.sub(key, 1, 1) == "#"
       or string.find(key, "[,%c]")
       or string.match(key,"^%s*(.-)%s*$") ~= key
       or type(value) ~= "number" or math.tointeger(value) == nil
       or value < 0 or value > 2147483647
       or value > math.floor(value) then return nil, "INVALID COUNT" end
    keys[#keys+1] = key
  end
  if #keys > Storage.maxEntries then return nil, "TOO MANY MODELS" end
  table.sort(keys)
  local parts = {"model_name,flight_count\n# api_ver=1\n"}
  for _, key in ipairs(keys) do
    parts[#parts+1] = string.format("%s,%d\n", key, values[key])
  end
  local text = table.concat(parts)
  if #text > Storage.maxBytes then return nil, "HISTORY TOO LARGE" end
  return text
end

function Storage.rename(from, to)
  if type(_G.rename) ~= "function" then return false end
  local ok, result = pcall(_G.rename, from, to)
  return ok and type(result) == "number" and result == 0
end

function Storage.remove(path)
  if type(_G.del) ~= "function" then return false end
  local ok, result = pcall(_G.del, path)
  return ok and type(result) == "number" and result == 0
end

function Storage.writeValidated(path, text)
  local opened, file = pcall(io.open, path, "w")
  if not opened or not file then return false end
  local written, result = pcall(io.write, file, text)
  local closed = pcall(io.close, file)
  if not written or result == nil or result == false or not closed then return false end
  local readback = Storage.read(path)
  return readback == text
end

function Storage.save(state)
  if not state.writable or not state.cache then return false, state.error or "READ ONLY" end
  if type(_G.rename) ~= "function" or type(_G.del) ~= "function" then
    return false, "FILESYSTEM API UNAVAILABLE"
  end
  local text, reason = Storage.serialize(state.cache)
  if not text then return false, reason end
  -- The base text was fully parsed on load. Exact comparison avoids parsing
  -- the same history again during a save, retaining the same write guard.
  local current, mainReason = Storage.read(state.path)
  if current then
    if current == text then
      -- A prior promotion may have succeeded before its confirmation failed.
      state.baseText, state.source = text, "main"
      return true
    end
    if state.source == "new" or current ~= state.baseText then
      return false, "HISTORY CHANGED"
    end
  elseif mainReason ~= "MISSING" then return false, mainReason end
  -- If the only confirmed source is backup, revalidate it before replacing temp.
  if not current and state.source ~= "new" then
    local backup = Storage.read(state.path .. ".bak")
    if not backup or backup ~= state.baseText then return false, "BACKUP UNAVAILABLE" end
  end
  local tmp, backupPath = state.path .. ".tmp", state.path .. ".bak"
  if not Storage.writeValidated(tmp, text) then return false, "TEMP WRITE ERROR" end
  if current then
    local backupInfo, backupReason = Storage.stat(backupPath)
    if backupInfo then
      if not Storage.remove(backupPath) then return false, "BACKUP DELETE ERROR" end
    elseif backupReason ~= "MISSING" then return false, backupReason end
    if not Storage.rename(state.path, backupPath) then return false, "BACKUP RENAME ERROR" end
  end
  if not Storage.rename(tmp, state.path) then
    -- Keep both files for recovery. Never delete the sole confirmed backup.
    return false, "PROMOTE ERROR"
  end
  local confirmed = Storage.read(state.path)
  if confirmed ~= text then return false, "PROMOTE READ ERROR" end
  state.baseText, state.source = text, "main"
  return true
end

function Storage.markDirty(state, now)
  if not state.writable then return false end
  if not state.dirty then state.attempts, state.nextAttempt = 0, now or 0 end
  state.dirty = true
  return true
end

function Storage.service(state, now)
  if not state.dirty or state.attempts >= Storage.maxAttempts
     or now < state.nextAttempt then return false end
  state.attempts = state.attempts + 1
  local ok, reason = Storage.save(state)
  if ok then
    state.dirty, state.error, state.attempts = false, nil, 0
    return true
  end
  state.error = reason or "SAVE ERROR"
  state.nextAttempt = now + Storage.retryTicks
  return false
end

function Storage.retry(state, now)
  -- Explicit retry after media recovery; it never increments a model count.
  if not state.dirty then return false end
  state.attempts, state.nextAttempt = 0, now or 0
  return true
end

return Storage
