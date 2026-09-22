-- In-memory EdgeTX/FatFS API mock. Tests cannot touch host settings files.
fs={}
fs.reset=function(files)
  fs.files=files or {}; fs.directories={["/"]=true}; fs.faults={}; fs.calls={}; fs.online=true
end
fs.reset()
getVersion=function() return "2.12.4", "mock", 2, 12, 4 end
getFieldInfo=function(name) if name=="SG" then return {id=99,name="SG"} end end
fs.call=function(kind,path,extra)
  fs.calls[#fs.calls+1]=kind..":"..path..(extra and ":"..extra or "")
  local fault=fs.faults[kind..":"..path]
  if type(fault)=="function" then return fault(path,extra) end
  return fault
end
fstat=function(path)
  local fault=fs.call("stat",path)
  if fault=="throw" then error("stat failure") end
  if not fs.online or fault then return nil end
  -- Native FatFS f_stat rejects '/' even while the volume is available.
  if path=="/" then return nil end
  if fs.directories[path] then return {size=0,attrib=16} end
  local data=fs.files[path]
  if data~=nil then return {size=#data,attrib=0} end
end
dir=function(path)
  local fault=fs.call("dir",path)
  if fault=="throw" then error("directory failure") end
  if not fs.online or fault=="nil" then return nil end
  if fault then return fault end
  if not fs.directories[path] then return nil end
  local names={}
  local prefix=path=="/" and "/" or path.."/"
  for name in pairs(fs.files) do
    if string.sub(name,1,#prefix)==prefix then
      local child=string.sub(name,#prefix+1)
      if not string.find(child,"/",1,true) then names[#names+1]=child end
    end
  end
  table.sort(names)
  local index=0
  return function()
    fs.call("iterate",path); index=index+1; return names[index]
  end
end
mkdir=function(path)
  local fault=fs.call("mkdir",path)
  if fault=="throw" then error("mkdir failure") end
  if fault~=nil then return fault end
  if not fs.online then return 3 end
  if fs.files[path]~=nil or fs.directories[path] then return 8 end
  local parent=string.match(path,"^(.*)/[^/]+$")
  if parent=="" then parent="/" end
  if not fs.directories[parent] then return 5 end
  fs.directories[path]=true; return 0
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
  fs.files[path]=nil; return 0
end
io={open=function(path,mode)
  local fault=fs.call("open"..mode,path)
  if fault=="throw" then error("open failure") end
  if not fs.online or fault then return nil end
  if mode=="r" and fs.files[path]==nil then return nil end
  if mode=="w" then
    local parent=string.match(path,"^(.*)/[^/]+$")
    if parent=="" then parent="/" end
    if not fs.directories[parent] then return nil end
    fs.files[path]=""
  end
  return {path=path,pos=1,mode=mode}
end,
read=function(file,want)
  local fault=fs.call("read",file.path)
  if fault=="throw" then error("read failure") end
  if not fs.online or fault=="empty" then return "" end
  local data=fs.files[file.path] or ""
  if fault=="short" then want=math.max(0,want-1) end
  local chunk=string.sub(data,file.pos,file.pos+want-1)
  file.pos=file.pos+#chunk; return chunk
end,
write=function(file,data)
  local fault=fs.call("write",file.path)
  if fault=="throw" then error("write failure") end
  if not fs.online or fault=="nil" then return nil end
  if fault=="short" or fault=="silent-short" then
    fs.files[file.path]=string.sub(data,1,#data-1)
    if fault=="silent-short" then return file end
    return nil
  end
  fs.files[file.path]=data; return file
end,
close=function(file)
  local fault=fs.call("close",file.path)
  if fault=="throw" then error("close failure") end
  if fault=="lost" then fs.files[file.path]="" end
  -- EdgeTX intentionally does not expose the FatFS close/flush result.
end}
