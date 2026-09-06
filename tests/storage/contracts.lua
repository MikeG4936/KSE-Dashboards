local function eq(name,actual,expected)
  assert(actual==expected,name..": expected "..tostring(expected)..", got "..tostring(actual))
  print("PASS|"..name)
end
local path="/flights-count.csv"
local header="model_name,flight_count\n# api_ver=1\n"
local old=header.."Model A,7\nModel B,20\n"
local updated=header.."Model A,8\nModel B,20\n"
local function setup(files)
  fs.files=files or {}; fs.faults={}; fs.calls={}; fs.online=true
  local s=Storage.new(path); Storage.load(s); return s
end
local function dirty(s)
  s.cache["Model A"]=8; Storage.markDirty(s,0)
end
local function writesMain()
  for _,call in ipairs(fs.calls) do if call=="openw:"..path then return true end end
  return false
end
local s=setup({[path]=old})
eq("load all models",s.cache["Model B"],20)
dirty(s); eq("normal save",Storage.service(s,0),true)
eq("normal main contents",fs.files[path],updated)
eq("retain backup",fs.files[path..".bak"],old)
eq("never direct overwrite",writesMain(),false)
eq("save clears dirty",s.dirty,false)

s=setup(); eq("new readable filesystem",s.writable,true)
s.cache["Model A"]=1; Storage.markDirty(s,0)
eq("new history save",Storage.service(s,0),true)
eq("new history serialized",fs.files[path],header.."Model A,1\n")
fs.online=false; s=Storage.new(path); Storage.load(s)
eq("missing SD read only",s.writable,false)
eq("missing SD visible",s.error,"STORAGE UNAVAILABLE")

for _,fault in ipairs({"nil","short","silent-short","throw"}) do
  s=setup({[path]=old}); dirty(s); fs.faults["write:"..path..".tmp"]=fault
  eq("failed write "..fault,Storage.service(s,0),false)
  eq("failed write preserves main "..fault,fs.files[path],old)
  eq("failed write stays dirty "..fault,s.dirty,true)
end
for _,fault in ipairs({"empty","short","throw"}) do
  s=setup({[path]=old}); dirty(s); fs.faults["read:"..path..".tmp"]=fault
  eq("readback failure "..fault,Storage.service(s,0),false)
  eq("readback preserves main "..fault,fs.files[path],old)
end
s=setup({[path]=old}); dirty(s); fs.faults["close:"..path..".tmp"]="lost"
eq("silent close loss detected",Storage.service(s,0),false)
eq("silent close preserves main",fs.files[path],old)

for _,result in ipairs({1,true,false}) do
  s=setup({[path]=old}); dirty(s); fs.faults["rename:"..path]=result
  eq("FRESULT strict "..tostring(result),Storage.service(s,0),false)
  eq("rename error preserves main "..tostring(result),fs.files[path],old)
end
s=setup({[path]=old,[path..".bak"]=header.."Model A,6\n"}); dirty(s)
fs.faults["del:"..path..".bak"]=1
eq("backup deletion failure",Storage.service(s,0),false)
eq("backup deletion preserves main",fs.files[path],old)
eq("backup deletion preserves backup",fs.files[path..".bak"],header.."Model A,6\n")
s=setup({[path]=old}); dirty(s); fs.faults["rename:"..path..".tmp"]=1
eq("promotion failure",Storage.service(s,0),false)
eq("promotion retains confirmed backup",fs.files[path..".bak"],old)
eq("promotion retains candidate",fs.files[path..".tmp"],updated)
fs.faults={}
eq("promotion retry delayed",Storage.service(s,499),false)
eq("promotion retry succeeds",Storage.service(s,500),true)
eq("promotion retry no double increment",fs.files[path],updated)

s=setup({[path..".bak"]=old})
eq("backup startup source",s.source,"backup")
eq("backup startup all models",s.cache["Model B"],20)
dirty(s); eq("backup recovery saves",Storage.service(s,0),true)
eq("backup recovery preserves old copy",fs.files[path..".bak"],old)
s=setup({[path..".bak"]=old,[path..".tmp"]=updated})
eq("both artifacts prefer confirmed backup",s.cache["Model A"],7)
s=setup({[path..".tmp"]=updated})
eq("temp salvage available",s.cache["Model A"],8)
eq("temp alone read only",s.writable,false)
eq("temp alone warning",s.error,"TEMP UNCONFIRMED")
eq("temp alone cannot dirty",Storage.markDirty(s,0),false)

local invalids={
  {"empty",""}, {"bad count",header.."Model A,nope\n"},
  {"negative",header.."Model A,-1\n"}, {"fraction",header.."Model A,1.5\n"},
  {"extra column",header.."Model A,7,extra\n"},
  {"duplicate",header.."Model A,7\nModel A,8\n"},
  {"large",header..string.rep("# padding\n",4000)},
}
local exact=header.."#"..string.rep("x",Storage.maxBytes-#header-2).."\n"
s=setup({[path]=exact})
eq("exact byte limit accepted",s.writable,true)
local boundary={header}
for i=1,200 do boundary[#boundary+1]="Model "..i..",1\n" end
s=setup({[path]=table.concat(boundary)})
eq("200 models accepted",s.writable,true)
s.cache["new model"]=1; Storage.markDirty(s,0)
eq("201st model cannot rewrite history",Storage.service(s,0),false)
eq("201st model preserves source",fs.files[path],table.concat(boundary))
local many={header}
for i=1,201 do many[#many+1]="Model "..i..",1\n" end
invalids[#invalids+1]={"201 entries",table.concat(many)}
for _,case in ipairs(invalids) do
  s=setup({[path]=case[2],[path..".bak"]=old})
  eq("invalid source read only "..case[1],s.writable,false)
  eq("invalid source cannot save "..case[1],Storage.save(s),false)
  eq("invalid source preserved "..case[1],fs.files[path],case[2])
end
for _,fault in ipairs({"empty","short","throw"}) do
  fs.files={[path]=old}; fs.faults={["read:"..path]=fault}
  s=Storage.new(path); Storage.load(s)
  eq("main read failure blocks writes "..fault,s.writable,false)
  eq("main read failure no partial cache "..fault,s.cache,nil)
end
s=setup({[path]=old}); dirty(s); fs.files[path]=header.."Model A,99\n"
eq("foreign modification blocks save",Storage.service(s,0),false)
eq("foreign modification preserved",fs.files[path],header.."Model A,99\n")
for _,replacement in ipairs({"",header.."Model A,broken\n",header.."Model A,7\n"}) do
  s=setup({[path]=old}); dirty(s); fs.files[path]=replacement
  eq("changed main blocked "..#replacement,Storage.service(s,0),false)
  eq("changed main intact "..#replacement,fs.files[path],replacement)
  eq("changed main no temporary write "..#replacement,fs.files[path..".tmp"],nil)
end
for _,replacement in ipairs({header.."Model A,broken\n",header.."Model A,99\n"}) do
  s=setup({[path..".bak"]=old}); dirty(s); fs.files[path..".bak"]=replacement
  eq("changed recovery backup blocked "..#replacement,Storage.service(s,0),false)
  eq("changed recovery backup intact "..#replacement,fs.files[path..".bak"],replacement)
  eq("changed recovery backup no main write "..#replacement,fs.files[path],nil)
end

-- Lua integers and floats are both 32-bit in the pinned EdgeTX core. A float
-- equal to 2147483648 can compare equal to converted MAX_INT; %d then throws.
local maxCountText=header.."Model A,2147483647\n"
s=setup({[path]=maxCountText})
eq("MAX_INT history writable",s.writable,true)
eq("MAX_INT parsed exactly",s.cache["Model A"],2147483647)
eq("MAX_INT serialized exactly",Storage.serialize(s.cache),maxCountText)
s.cache["Model B"]=1; Storage.markDirty(s,0)
eq("MAX_INT survives unrelated save",Storage.service(s,0),true)
eq("MAX_INT saved exact decimal",fs.files[path],maxCountText.."Model B,1\n")
s=setup({[path]=header.."Model A,2147483648\n"})
eq("MAX_INT plus one is read only",s.writable,false)
eq("MAX_INT plus one no invalid cache",s.cache,nil)
local serializedOk,serialized=pcall(Storage.serialize,{["Model A"]=tonumber("2147483648")})
eq("overflow serialization does not throw",serializedOk,true)
eq("overflow serialization rejected",serialized,nil)
serializedOk,serialized=pcall(Storage.serialize,{["Model A"]=1.5})
eq("fraction serialization does not throw",serializedOk,true)
eq("fraction serialization rejected",serialized,nil)
local normalComments=header.."# ordinary history note\nFixture,7\n"
s=setup({[path]=normalComments})
eq("api version and ordinary comments remain valid",s.writable,true)
eq("comments preserve model counts",s.cache.Fixture,7)
local ambiguous=header.."#My helicopter,17\nFixture,7\n"
s=setup({[path]=ambiguous})
eq("comment-shaped model quarantined",s.writable,false)
eq("comment-shaped model error explicit",s.error,"AMBIGUOUS MODEL NAME")
eq("comment-shaped model no partial cache",s.cache,nil)
eq("comment-shaped model cannot save",Storage.save(s),false)
eq("comment-shaped model source preserved",fs.files[path],ambiguous)
serializedOk,serialized=pcall(Storage.serialize,{["#My helicopter"]=17})
eq("comment-shaped key serialize does not throw",serializedOk,true)
eq("comment-shaped key serialize rejected",serialized,nil)
s=setup({[path]=old}); s.cache["#My helicopter"]=17; Storage.markDirty(s,0)
eq("new comment-shaped key cannot rewrite history",Storage.service(s,0),false)
eq("new comment-shaped key preserves source",fs.files[path],old)
eq("new comment-shaped key remains dirty",s.dirty,true)
s=setup({[path]=old}); dirty(s); fs.online=false
for i=0,8 do Storage.service(s,i*500) end
eq("retry bound",s.attempts,3)
eq("retry exhaustion visible",s.error~=nil,true)
eq("retry exhaustion retains count",s.cache["Model A"],8)
fs.online=true
eq("retry exhaustion does not restart automatically",Storage.service(s,5000),false)
Storage.retry(s,5000)
eq("explicit retry succeeds",Storage.service(s,5000),true)
eq("explicit retry no recount",fs.files[path],updated)

-- Read confirmation can fail after the rename already installed correct bytes.
s=setup({[path]=old}); dirty(s)
fs.faults["read:"..path]=function()
  if fs.files[path]==updated then return "empty" end
end
eq("post-promotion read error",Storage.service(s,0),false)
eq("post-promotion keeps backup",fs.files[path..".bak"],old)
fs.faults={}
eq("post-promotion retry recognizes committed data",Storage.service(s,500),true)
eq("post-promotion retry no recount",fs.files[path],updated)

-- Public filesystem names can live behind EdgeTX's ROM-style __index lookup.
local originalMeta=getmetatable(_G)
local originalIndex=originalMeta.__index
local api={fstat=fstat,rename=rename,del=del}
rawset(_G,"fstat",nil); rawset(_G,"rename",nil); rawset(_G,"del",nil)
setmetatable(_G,{__index=function(_,key) return api[key] or originalIndex[key] end})
s=setup({[path]=old}); dirty(s)
eq("ROM filesystem lookup",Storage.service(s,0),true)
eq("ROM filesystem saved contents",fs.files[path],updated)
setmetatable(_G,originalMeta)
fstat=api.fstat; rename=api.rename; del=api.del
print("PASS|complete")
