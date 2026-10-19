-- Shared KSE count storage; assembled into each standalone dashboard.
-- EdgeTX v2.12.1: io.read hides errors as ""; fstat size is required.
-- Global rename/del return FatFS FRESULT; only numeric zero means success.
local Storage = { maxBytes=32768, maxEntries=200, batchLines=24, saveBatch=12,
                  retryTicks=500, maxAttempts=3 }

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

function Storage.parse(job)
  if not job.lines then
    if job.text == "" then return nil, "EMPTY HISTORY" end
    job.lines = string.gmatch(job.text, "[^\r\n]+")
    job.values, job.entries, job.header = {}, 0, false
  end
  -- Count every line, including comments, against the same callback budget.
  -- Values remain private until EOF; a valid prefix is never a usable cache.
  for _ = 1, Storage.batchLines do
    local line = job.lines()
    if not line then
      if not job.header and job.entries == 0 then return nil, "EMPTY HISTORY" end
      return job.values
    end
    local n = string.match(line, "^%s*(.-)%s*$")
    if n == "model_name,flight_count" then
      if job.header or job.entries > 0 then return nil, "MALFORMED HISTORY" end
      job.header = true
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
         or count ~= math.floor(count) or job.values[key] ~= nil then
        return nil, "MALFORMED HISTORY"
      end
      job.entries = job.entries + 1
      if job.entries > Storage.maxEntries then return nil, "TOO MANY MODELS" end
      job.values[key] = count
    end
  end
  return nil, nil -- Pending: continue this immutable snapshot next callback.
end

function Storage.new(path)
  return {path=path, cache=nil, writable=false, dirty=false,
          error=nil, attempts=0, nextAttempt=0, source=nil}
end

function Storage.beginLoad(state)
  -- A handoff/reselection must retain both dirty counts and unfinished reads.
  if state.dirty or state.loading then return end
  state.cache, state.source, state.baseText = nil, nil, nil
  state.writable, state.error = false, nil
  state.loading = {stage=1, reasons={}}
end

function Storage.finishLoad(state, values, source, text, writable, reason, now)
  state.cache, state.source, state.baseText = values, source, text
  state.writable, state.error, state.loading = writable, reason, nil
  -- Timer crossings observed during loading belong to the shared store, not
  -- the current widget/model. Quarantine cannot authorize their persistence.
  if writable and state.pending then
    for key, count in pairs(state.pending) do
      local previous = values[key] or 0
      local accepted = math.min(count, 2147483647 - previous)
      if accepted > 0 then
        values[key] = previous + accepted
        Storage.markDirty(state, now)
      end
      if accepted < count then
        state.pending[key] = count - accepted
        state.error = "COUNT UNAVAILABLE"
      else
        state.pending[key] = nil
      end
    end
    if next(state.pending) == nil then state.pending = nil end
  end
  return true
end

function Storage.stepLoad(state, now)
  local job = state.loading
  if not job then return false end
  local reason, values
  if job.text == nil then
    local suffix = job.stage == 1 and "" or job.stage == 2 and ".bak" or ".tmp"
    job.text, reason = Storage.read(state.path .. suffix)
  end
  if job.text then
    values, reason = Storage.parse(job)
    if not values and not reason then return false end
    if values then
      local source = job.stage == 1 and "main" or job.stage == 2 and "backup" or "temporary"
      local writable = job.stage == 1 or (job.stage == 2 and job.reasons[1] == "MISSING")
      if job.stage == 2 then reason = writable and "RECOVERED BACKUP" or job.reasons[1]
      elseif job.stage == 3 then reason = "TEMP UNCONFIRMED" end
      return Storage.finishLoad(state, values, source, job.text, writable, reason, now)
    end
  end
  job.reasons[job.stage] = reason
  if job.stage < 3 then
    -- Even a last-line failure yields before starting the next candidate.
    job.stage = job.stage + 1
    job.text, job.lines, job.values = nil, nil, nil
    return false
  end
  if job.reasons[1] == "MISSING" and job.reasons[2] == "MISSING"
     and job.reasons[3] == "MISSING" then
    local directory = string.match(state.path, "^(.*)/[^/]+$")
    -- FatFS rejects f_stat("/") even on a healthy card. Opening a directory
    -- works for the root too; the discarded iterator closes through native GC.
    -- Do not enumerate the card or create a probe file during history loading.
    local opened, iterator = false, nil
    if type(_G.dir) == "function" then
      opened, iterator = pcall(_G.dir, directory == "" and "/" or directory or ".")
    end
    if opened and type(iterator) == "function" then
      return Storage.finishLoad(state, {}, "new", nil, true, nil, now)
    end
    reason = "STORAGE UNAVAILABLE"
  else
    reason = job.reasons[1] ~= "MISSING" and job.reasons[1]
             or job.reasons[2] ~= "MISSING" and job.reasons[2] or job.reasons[3]
  end
  return Storage.finishLoad(state, nil, nil, nil, false, reason, now)
end

function Storage.increment(state, key, now)
  if state.loading then
    state.pending = state.pending or {}
    local count = state.pending[key] or 0
    if count < 2147483647 then state.pending[key] = count + 1; return true end
  elseif state.writable and state.cache then
    local previous = state.cache[key] or 0
    if previous < 2147483647 then
      state.cache[key] = previous + 1
      return Storage.markDirty(state, now)
    end
  end
  state.error = state.error or "COUNT UNAVAILABLE"
  return false
end

-- Callbacks supply a job to yield after each batch. The no-job form is a
-- bounded synchronous utility for fixture/CSV construction, never servicing.
function Storage.serialize(values, job)
  local batch = job and Storage.saveBatch or Storage.maxEntries + 1
  local work = job or {}
  if not work.keys then work.keys, work.parts = {}, {"model_name,flight_count\n# api_ver=1\n"} end
  if not work.index then
    for _ = 1, batch do
      local key, value = next(values, work.key)
      work.key = key
      if key == nil then
        table.sort(work.keys) -- Native sort, bounded to at most 200 names.
        work.index = 1
        break
      end
      if type(key) ~= "string" or key == "" or string.sub(key, 1, 1) == "#"
         or string.find(key, "[,%c]")
         or string.match(key,"^%s*(.-)%s*$") ~= key
         or type(value) ~= "number" or math.tointeger(value) == nil
         or value < 0 or value > 2147483647
         or value > math.floor(value) then return nil, "INVALID COUNT" end
      work.keys[#work.keys+1] = key
      if #work.keys > Storage.maxEntries then return nil, "TOO MANY MODELS" end
    end
    if job then return nil end -- Never collect and format in one callback.
  end
  for _ = 1, batch do
    local key = work.keys[work.index]
    if key == nil then
      local text = table.concat(work.parts)
      if #text > Storage.maxBytes then return nil, "HISTORY TOO LARGE" end
      return text
    end
    local row = string.format("%s,%d\n", key, values[key])
    work.bytes = (work.bytes or #work.parts[1]) + #row
    if work.bytes > Storage.maxBytes then return nil, "HISTORY TOO LARGE" end
    work.parts[#work.parts+1] = row
    work.index = work.index + 1
  end
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

-- Exact comparison with the fully validated base guards every write attempt
-- and is repeated immediately before promotion after yielding between phases.
function Storage.checkBase(state, text)
  local current, reason = Storage.read(state.path)
  if current then
    if current == text then return true, current, true end
    if state.source == "new" or current ~= state.baseText then
      return false, "HISTORY CHANGED"
    end
  elseif reason ~= "MISSING" then return false, reason end
  if not current and state.source ~= "new" then
    local backup = Storage.read(state.path .. ".bak")
    if not backup or backup ~= state.baseText then return false, "BACKUP UNAVAILABLE" end
  end
  return true, current, false
end

function Storage.save(state)
  if not state.writable or not state.cache then return false, state.error or "READ ONLY" end
  if type(_G.rename) ~= "function" or type(_G.del) ~= "function" then
    return false, "FILESYSTEM API UNAVAILABLE"
  end
  local job = state.saving
  if not job then return false, "SAVE NOT STARTED" end
  if job.phase == "serialize" then
    if job.revision ~= state.revision then
      -- A count changed while collecting/formatting: restart before using next
      -- with a changed table, retaining this attempt's retry accounting.
      job = {revision=state.revision, phase="serialize", active=true}
      state.saving = job
    end
    local text, reason = Storage.serialize(state.cache, job)
    if reason then return false, reason end
    if text then
      job.text, job.phase = text, "guard"
      job.keys, job.parts, job.key = nil, nil, nil
    end
    return nil
  end
  local tmp, backupPath = state.path .. ".tmp", state.path .. ".bak"
  if job.phase == "write" then
    if not Storage.writeValidated(tmp, job.text) then return false, "TEMP WRITE ERROR" end
    job.phase = "commit"
    return nil
  end
  local ok, current, committed = Storage.checkBase(state, job.text)
  if not ok then return false, current end
  if not committed then
    if job.phase == "guard" then job.phase = "write"; return nil end
    -- Temp could have changed since the preceding callback. No rename or
    -- backup deletion is permitted until both source and candidate agree.
    if Storage.read(tmp) ~= job.text then return false, "TEMP CHANGED" end
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
    if Storage.read(state.path) ~= job.text then return false, "PROMOTE READ ERROR" end
  end
  state.baseText, state.source = job.text, "main"
  return true
end

function Storage.markDirty(state, now)
  if not state.writable then return false end
  if not state.dirty then state.attempts, state.nextAttempt = 0, now or 0 end
  state.dirty = true
  state.revision = (state.revision or 0) + 1
  return true
end

function Storage.service(state, now)
  if not state.dirty or now < state.nextAttempt then return false end
  local job = state.saving
  if not job or not job.active then
    if state.attempts >= Storage.maxAttempts then return false end
    state.attempts = state.attempts + 1
    job = job or {revision=state.revision, phase="serialize"}
    job.active, state.saving = true, job
  end
  local ok, reason = Storage.save(state)
  job = state.saving -- Serialization may restart after a new count.
  if ok == nil then return false end -- One bounded phase; still in progress.
  if ok then
    state.dirty = state.revision ~= job.revision
    state.error = state.pending and "COUNT UNAVAILABLE" or nil
    state.attempts, state.nextAttempt, state.saving = 0, now, nil
    return true
  end
  -- Keep an immutable completed snapshot across retries, including a failed
  -- readback after promotion. Newer counts wait for its confirmation, then
  -- save against the confirmed base; they cannot be mistaken for foreign edits.
  if job.text then job.phase, job.active = "guard", false
  else state.saving = nil end
  state.error = reason or "SAVE ERROR"
  state.nextAttempt = now + Storage.retryTicks
  return false
end

function Storage.retry(state, now)
  -- Explicit retry after media recovery; it never increments a model count.
  if not state.dirty then return false end
  if state.saving and state.saving.active then return true end
  state.attempts, state.nextAttempt = 0, now or 0
  return true
end

return Storage
