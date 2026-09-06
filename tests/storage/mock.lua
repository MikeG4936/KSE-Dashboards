-- EdgeTX-like filesystem calls. Failure injection reproduces nil/FRESULT/empty
-- string semantics rather than desktop Lua file methods.
fs={files={},calls={},faults={},online=true}
fs.call=function(kind,path,extra)
  fs.calls[#fs.calls+1]=kind..":"..path..(extra and ":"..extra or "")
  local key=kind..":"..path
  local fault=fs.faults[key]
  if type(fault)=="function" then return fault(path,extra) end
  return fault
end
fstat=function(path)
  local fault=fs.call("stat",path)
  if fault=="throw" then error("stat failure") end
  if not fs.online or fault then return nil end
  if path=="/" then return {size=0,attrib=16} end
  local data=fs.files[path]
  if data~=nil then return {size=#data,attrib=0} end
end
rename=function(from,to)
  local fault=fs.call("rename",from,to)
  if fault=="throw" then error("rename failure") end
  if fault~=nil then return fault end
  if not fs.online then return 3 end
  if fs.files[from]==nil then return 4 end
  if fs.files[to]~=nil then return 8 end
  fs.files[to],fs.files[from]=fs.files[from],nil
  return 0
end
del=function(path)
  local fault=fs.call("del",path)
  if fault=="throw" then error("delete failure") end
  if fault~=nil then return fault end
  if not fs.online then return 3 end
  if fs.files[path]==nil then return 4 end
  fs.files[path]=nil
  return 0
end
io={open=function(path,mode)
  local fault=fs.call("open"..mode,path)
  if fault=="throw" then error("open failure") end
  if not fs.online or fault then return nil end
  if mode=="r" and fs.files[path]==nil then return nil end
  if mode=="w" then fs.files[path]="" end
  return {path=path,pos=1,mode=mode}
end,
read=function(file,want)
  local fault=fs.call("read",file.path)
  if fault=="throw" then error("read failure") end
  if not fs.online or fault=="empty" then return "" end
  local data=fs.files[file.path] or ""
  if fault=="short" then want=math.max(0,want-1) end
  local chunk=string.sub(data,file.pos,file.pos+want-1)
  file.pos=file.pos+#chunk
  return chunk
end,
write=function(file,data)
  local fault=fs.call("write",file.path)
  if fault=="throw" then error("write failure") end
  if not fs.online or fault=="nil" then return nil end
  if fault=="short" then
    fs.files[file.path]=string.sub(data,1,#data-1)
    return nil
  end
  if fault=="silent-short" then
    fs.files[file.path]=string.sub(data,1,#data-1)
    return file
  end
  fs.files[file.path]=data
  return file
end,
close=function(file)
  local fault=fs.call("close",file.path)
  if fault=="throw" then error("close failure") end
  if fault=="lost" then fs.files[file.path]="" end
  -- Underlying FatFS status is intentionally not returned, matching EdgeTX.
end}
