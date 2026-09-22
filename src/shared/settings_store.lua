-- Local dashboard configuration. No executable Lua data and no FC requests.
-- File operations follow EdgeTX FatFS results/readback, not desktop Lua I/O.
local Store = {root="/KSE/Settings", exports="/KSE/Settings/Exports", maxBytes=512}
local fields = {
  {"MinFlight", 1, 120, 20}, {"HeliType", 1, 5, 1},
  {"BattRsv", 0, 50, 20}, {"BattVoice", 0, 1, 0},
  {"RxPackMin", "text", nil, "6.60"}, {"RxPackMax", "text", nil, "8.40"},
  {"MotorSw", 0, 32767, 0}, {"CountSrc", 1, 2, 2}, {"FuelCheck", 1, 121, 25},
}
Store.heliTypes={"Electric", "Nitro", "Auto Elec/Nitro", "OMPHOBBY"}
-- Display order is independent of saved IDs. Retired manual OMP ID 3 now
-- means automatic OMP; existing Rotorflight Auto ID 4 keeps its meaning.
Store.heliTypeIds={1,2,4,5}
local function integer(n, lo, hi)
  return type(n)=="number" and n>=lo and n<=hi and n<=math.floor(n)
end
local function hex(text)
  return (string.gsub(text, ".", function(c) return string.format("%02X",string.byte(c)) end))
end
local function unhex(text)
  if #text%2~=0 or string.find(text,"[^%x]") then return nil end
  return (string.gsub(text,"%x%x",function(c) return string.char(tonumber(c,16)) end))
end
local function identity(value)
  return type(value)=="string" and #value>0 and #value<=64
     and not string.find(value,"[%c/\\]") and value~="." and value~=".."
end
local function basename(modelFile)
  if not identity(modelFile) then return nil end
  return (string.find(modelFile,"[^%w_.%-]") and "v2-hex-"..hex(modelFile)
          or "v2-model-"..modelFile)..".kse"
end
local function checksum(text)
  local a,b=1,0
  for i=1,#text do a=(a+string.byte(text,i))%65521; b=(b+a)%65521 end
  return string.format("%04X%04X",b,a)
end
function Store.supported()
  if type(getVersion)~="function" then return false end
  local _,_,major,minor,patch=getVersion()
  -- Configuration requires the reviewed native editor API family.
  return major==2 and minor==12 and type(patch)=="number" and patch>=4
end
function Store.defaults()
  local result={Theme=1}
  for _,field in ipairs(fields) do result[field[1]]=field[4] end
  local info=type(getFieldInfo)=="function" and getFieldInfo("SG") or nil
  if type(info)=="table" and type(info.id)=="number" then result.MotorSw=info.id end
  return result
end
function Store.capture(values)
  local result=Store.defaults()
  for key in pairs(result) do
    if values and values[key]~=nil then result[key]=values[key] end
  end
  if type(result.BattVoice)=="boolean" then result.BattVoice=result.BattVoice and 1 or 0 end
  if integer(result.HeliType,3,3) then result.HeliType=5 end
  return result
end
function Store.make(modelFile, variant, values, base)
  local source=Store.capture(values)
  local record={model=modelFile,values={},themes={}}
  for _,field in ipairs(fields) do record.values[field[1]]=source[field[1]] end
  for key,value in pairs(base and base.themes or {}) do record.themes[key]=value end
  record.themes[variant]=source.Theme
  return record
end
function Store.effective(record, variant)
  local result=Store.defaults()
  if record then
    for _,field in ipairs(fields) do result[field[1]]=record.values[field[1]] end
    result.Theme=record.themes[variant] or 1
  end
  if integer(result.HeliType,3,3) then result.HeliType=5 end
  return result
end
function Store.equal(a,b)
  if not a or not b then return false end
  if a.Theme~=b.Theme then return false end
  for _,field in ipairs(fields) do
    local key=field[1]
    if a[key]~=b[key] then return false end
  end
  return true
end
local function valid(record)
  if type(record)~="table" or not identity(record.model)
     or type(record.values)~="table" or type(record.themes)~="table" then
    return false,"Invalid model identity"
  end
  for _,field in ipairs(fields) do
    local key,value=field[1],record.values[field[1]]
    if field[2]=="text" then
      if type(value)~="string" or not string.match(value,"^[4-9]%.%d%d$")
         or tonumber(value)>9 then
        return false,"Invalid "..key
      end
    elseif not integer(value,field[2],field[3]) then return false,"Invalid "..key end
  end
  for key,value in pairs(record.themes) do
    if (key~="KSE4" and key~="KSE5") or not integer(value,1,22) then
      return false,"Invalid theme"
    end
  end
  return true
end
function Store.serialize(record)
  local ok,reason=valid(record)
  if not ok then return nil,reason end
  local lines={"KSE_SETTINGS=2\n","model="..hex(record.model).."\n"}
  for _,field in ipairs(fields) do
    local key,value=field[1],record.values[field[1]]
    if value~=nil then
      lines[#lines+1]=key.."="..(field[2]=="text" and hex(value)
                                  or string.format("%d",value)).."\n"
    end
  end
  for _,variant in ipairs({"KSE4","KSE5"}) do
    if record.themes[variant]~=nil then
      lines[#lines+1]="theme."..variant.."="..string.format("%d",record.themes[variant]).."\n"
    end
  end
  local payload=table.concat(lines)
  return payload.."END="..checksum(payload).."\n"
end
function Store.parse(text)
  if type(text)~="string" or #text>Store.maxBytes then return nil,"Settings file too large" end
  local payload,sum=string.match(text,"^(.*\n)END=(%x%x%x%x%x%x%x%x)\n$")
  if not payload then return nil,"Incomplete or damaged settings" end
  local raw={}
  for line in string.gmatch(payload,"([^\n]*)\n") do
    local key,value=string.match(line,"^([%w_.]+)=(.*)$")
    if not key or raw[key]~=nil then return nil,"Invalid settings record" end
    raw[key]=value
  end
  if raw.KSE_SETTINGS~="2" then return nil,"Unsupported settings version" end
  local record={model=raw.model and unhex(raw.model),values={},themes={}}
  raw.KSE_SETTINGS,raw.model=nil,nil
  for _,field in ipairs(fields) do
    local key,value=field[1],raw[field[1]]
    if value~=nil then
      if field[2]=="text" then record.values[key]=unhex(value)
      elseif string.match(value,"^%-?%d+$") then record.values[key]=tonumber(value) end
      if record.values[key]==nil then return nil,"Invalid "..key end
    end
    raw[key]=nil
  end
  for _,variant in ipairs({"KSE4","KSE5"}) do
    local key="theme."..variant
    if raw[key]~=nil then
      if not string.match(raw[key],"^%d+$") then return nil,"Invalid theme" end
      record.themes[variant]=tonumber(raw[key])
      if record.themes[variant]==nil then return nil,"Invalid theme" end
    end
    raw[key]=nil
  end
  if next(raw) then return nil,"Unknown settings field" end
  local ok,reason=valid(record)
  if not ok then return nil,reason end
  if checksum(payload)~=sum then return nil,"Incomplete or damaged settings" end
  return record
end
local function stat(path)
  if type(fstat)~="function" then return nil,"Storage unavailable" end
  local ok,info=pcall(fstat,path)
  if not ok then return nil,"Storage read error" end
  if info==nil then return nil,"missing" end
  if type(info)~="table" or not integer(info.size,0,Store.maxBytes) then
    return nil,"Settings file too large"
  end
  return info
end
local function read(path)
  local info,reason=stat(path)
  if not info then return nil,reason end
  if not io or type(io.open)~="function" then return nil,"Storage unavailable" end
  local ok,file=pcall(io.open,path,"r")
  if not ok or not file then return nil,"Storage read error" end
  local good,text=pcall(io.read,file,info.size)
  local endOk,extra=pcall(io.read,file,1)
  local closed=pcall(io.close,file)
  local after=stat(path)
  if not good or type(text)~="string" or #text~=info.size or not endOk
     or extra~="" or not closed or not after or after.size~=info.size then
    return nil,"Storage read error"
  end
  return text
end
local function readRecord(path,modelFile)
  local text,reason=read(path)
  if not text then return nil,reason end
  local record,parseReason=Store.parse(text)
  if not record then return nil,parseReason end
  if modelFile and record.model~=modelFile then return nil,"Settings belong to another model" end
  return record,nil,text
end
local function openPath(path,modelFile)
  local state={path=path,model=modelFile,writable=false}
  local record,reason,text=readRecord(path,modelFile)
  if record then
    state.record,state.baseText,state.source,state.writable=record,text,"main",true
    return state
  end
  local backup,backupReason,backupText=readRecord(path..".bak",modelFile)
  if backup then
    state.record,state.baseText,state.source=backup,backupText,"backup"
    state.writable=reason=="missing"
    state.error=state.writable and "Recovered saved backup" or reason
    return state
  end
  local temp,tempReason=stat(path..".tmp")
  if reason=="missing" and backupReason=="missing" and not temp and tempReason=="missing" then
    state.source,state.writable="new",true
  else
    state.error=reason~="missing" and reason or backupReason~="missing" and backupReason
                or "Unconfirmed save; preserve .tmp file"
  end
  return state
end
function Store.open(modelFile)
  local name=basename(modelFile)
  if not name then return {model=modelFile,writable=false,error="Save the EdgeTX model first"} end
  local state=openPath(Store.root.."/"..name,modelFile)
  state.filename=name
  return state
end
local function directory(path)
  if type(dir)~="function" then return false end
  local ok,iterator=pcall(dir,path)
  return ok and type(iterator)=="function"
end
local function makeDirectory(path)
  if directory(path) then return true end
  if type(mkdir)~="function" then return false end
  local ok,result=pcall(mkdir,path)
  return ok and result==0 and directory(path)
end
local function mutation(fn,...)
  if type(fn)~="function" then return false end
  local ok,result=pcall(fn,...)
  return ok and type(result)=="number" and result==0
end
local function write(path,text)
  local ok,file=pcall(io.open,path,"w")
  if not ok or not file then return false end
  local written,result=pcall(io.write,file,text)
  local closed=pcall(io.close,file)
  return written and result~=nil and result~=false and closed and read(path)==text
end
function Store.startSave(state,record)
  if not state or not state.writable or not state.path then
    return nil,state and state.error or "Settings are read-only"
  end
  if record.model~=state.model then return nil,"Model changed" end
  local text,reason=Store.serialize(record)
  if not text then return nil,reason end
  -- A private snapshot prevents later field edits from changing this save.
  local snapshot={model=record.model,values={},themes={}}
  for key,value in pairs(record.values) do snapshot.values[key]=value end
  for key,value in pairs(record.themes) do snapshot.themes[key]=value end
  return {state=state,record=snapshot,text=text,phase=1}
end
function Store.step(job)
  if job.done then return job.done,job.error end
  local state,path=job.state,job.state.path
  local function fail(reason) job.done,job.error="error",reason; return "error",reason end
  if job.phase==1 then
    if not makeDirectory("/KSE") or not makeDirectory(Store.root)
       or (state.export and not makeDirectory(Store.exports)) then return fail("Cannot create settings folder") end
    local current,reason=read(path)
    if current==job.text then job.phase=7; return "pending" end
    if current then
      if state.source=="new" or current~=state.baseText then return fail("Saved settings changed; reopen menu") end
    elseif reason~="missing" then return fail(reason)
    elseif state.source~="new" and read(path..".bak")~=state.baseText then
      return fail("Saved backup unavailable")
    end
    job.hadMain=current~=nil
  elseif job.phase==2 then
    if not write(path..".tmp",job.text) then return fail("Settings write failed") end
  elseif job.phase==3 then
    if job.hadMain then
      local info,reason=stat(path..".bak")
      if info and not mutation(del,path..".bak") then return fail("Cannot replace settings backup") end
      if not info and reason~="missing" then return fail(reason) end
    end
  elseif job.phase==4 then
    local current,reason=read(path)
    if (job.hadMain and current~=state.baseText)
       or (not job.hadMain and (current~=nil or reason~="missing")) then
      return fail("Saved settings changed; reopen menu")
    end
    if job.hadMain and not mutation(rename,path,path..".bak") then return fail("Cannot back up saved settings") end
  elseif job.phase==5 then
    if not mutation(rename,path..".tmp",path) then return fail("Cannot finish settings save") end
    if read(path)~=job.text then return fail("Settings readback failed") end
    -- Promotion, verification and live snapshot commit share one callback:
    -- fullscreen/model cancellation cannot fall between these stages.
    job.phase=7
  end
  if job.phase==7 then
    state.record,state.baseText,state.source,state.error=job.record,job.text,"main",nil
    job.done="done"
    return "done"
  end
  job.phase=job.phase+1
  return "pending"
end
function Store.readExport(filename)
  if type(filename)~="string" or #filename>150
     or not string.match(filename,"^[%w_.%-]+%.kse$") then return nil,"Select a .kse settings file" end
  return readRecord(Store.exports.."/"..filename)
end
function Store.startExport(state)
  if not state or not state.record or not state.filename then return nil,"Save KSE settings before exporting" end
  local exported=openPath(Store.exports.."/"..state.filename,state.model)
  exported.export=true
  return Store.startSave(exported,state.record)
end
return Store
