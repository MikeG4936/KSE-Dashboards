-- Emulate the firmware ROM-backed global constant lookup.
do
  local inherited = getmetatable(_G).__index
  getmetatable(_G).__index = setmetatable({PLAY_NOW=16}, {__index=inherited})
end
-- Minimal public EdgeTX API surface; no desktop Lua I/O or package loader.
__mock = {now=0, values={}, files={}, events={}, timer={value=0,start=0}, modelName="Fixture"}
LCD_W=800; LCD_H=480
lcd={RGB=function(r,g,b) return r*65536+g*256+b end}
getTime=function() return __mock.now end
getFieldInfo=function(name)
  if name == "SG" or name == 99 then return {id=99,name="SG",desc="Switch G"} end
  local item = __mock.values[name]
  if item then return {id=item.id or name,name=tostring(name)} end
end
getSourceName=function(id) return id==99 and "SG" or "Telemetry" end
getValue=function(id)
  if id==99 then return -1024 end
  local item=__mock.values[id]
  return item and item.value or 0
end
getSourceValue=function(id)
  local item=__mock.values[id]
  if not item then return nil,false,false end
  if item.throw then error("source temporarily unavailable") end
  return item.value,item.current~=false,item.fresh~=false
end
getRSSI=function() return 0 end
model={getInfo=function() return {name=__mock.modelName} end,
       getTimer=function() return __mock.timer end}
fstat=function(path)
  if path=="/" then return {size=0} end
  local data=__mock.files[path]
  if data~=nil then return {size=#data} end
end
rename=function(from,to)
  if __mock.files[from]==nil then return 4 end
  if __mock.files[to]~=nil then return 8 end
  __mock.files[to],__mock.files[from]=__mock.files[from],nil
  return 0
end
del=function(path)
  if __mock.files[path]==nil then return 4 end
  __mock.files[path]=nil
  return 0
end
io={open=function(path,mode)
  if mode=="r" and __mock.files[path]==nil then return nil end
  return {path=path,pos=1}
end,
read=function(file,count)
  local data=__mock.files[file.path] or ""
  local chunk=string.sub(data,file.pos,file.pos+count-1)
  file.pos=file.pos+#chunk
  return chunk
end,
write=function(file,data) __mock.files[file.path]=data; return true end,
close=function() end}
playNumber=function(value) __mock.events[#__mock.events+1]="voice:"..tostring(value) end
playFile=function(path) __mock.events[#__mock.events+1]="file:"..string.match(path,"[^/]+$") end
playHaptic=function(length,pause,flags)
  __mock.hapticFlags=flags
  __mock.events[#__mock.events+1]="haptic:"..tostring(length)
end
