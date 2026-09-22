local function eq(name,actual,expected)
  assert(actual==expected,name..": expected "..tostring(expected)..", got "..tostring(actual))
  print("PASS|"..name)
end
local function rejected(name,text)
  local record,err=Store.parse(text)
  eq(name.." rejected",record,nil)
  eq(name.." explained",type(err),"string")
end
local function mutations()
  local count=0
  for _,call in ipairs(fs.calls) do
    if string.find(call,"^openw:") or string.find(call,"^mkdir:")
       or string.find(call,"^rename:") or string.find(call,"^del:") then
      count=count+1
    end
  end
  return count
end
local function complete(job)
  assert(job,"missing save job")
  local status,err
  for _=1,30 do
    status,err=Store.step(job)
    if status~="pending" then return status,err end
  end
  error("settings job did not terminate in 30 stages")
end

-- Sign deliberately malformed payloads so schema tests reach past the
-- corruption guard. This fixture encoder is not used to generate saved data.
local function signed(payload)
  local a,b=1,0
  for i=1,#payload do a=(a+string.byte(payload,i))%65521; b=(b+a)%65521 end
  return payload.."END="..string.format("%04X%04X",b,a).."\n"
end
local function modify(text,from,to)
  local payload=assert(string.match(text,"^(.*\n)END="))
  local changed,count=string.gsub(payload,from,to)
  assert(count==1,"fixture replacement did not match exactly once")
  return signed(changed)
end
local function setup(text,backup,temp,model)
  fs.reset()
  local state=Store.open(model or "model01.yml")
  fs.directories["/KSE"]=true; fs.directories[Store.root]=true
  if text~=nil then fs.files[state.path]=text end
  if backup~=nil then fs.files[state.path..".bak"]=backup end
  if temp~=nil then fs.files[state.path..".tmp"]=temp end
  fs.calls={}
  return Store.open(model or "model01.yml")
end
local function save(state,record)
  local job,err=Store.startSave(state,record)
  assert(job,err)
  return complete(job)
end

local defaults=Store.defaults()
local defaultCount=0
for _ in pairs(defaults) do defaultCount=defaultCount+1 end
eq("ten canonical settings",defaultCount,10)
eq("transmitter battery fallback removed",defaults.TxBatt,nil)
eq("default fuel reminder is six minutes",defaults.FuelCheck,25)
eq("default flight counter is Rotorflight",defaults.CountSrc,2)
eq("default theme is first variant theme",defaults.Theme,1)
eq("four helicopter types",#Store.heliTypes,4)
eq("reviewed firmware supported",Store.supported(),true)
local version=getVersion
for _,v in ipairs({{2,11,5},{2,12,1},{2,12,3},{2,13,0},{3,0,0}}) do
  getVersion=function() return "fixture","mock",v[1],v[2],v[3] end
  eq("unreviewed firmware excludes menu "..v[1].."."..v[2].."."..v[3],Store.supported(),false)
end
getVersion=nil; eq("missing firmware API excludes menu",Store.supported(),false)
getVersion=version

local values={Theme=4,TxBatt=2,MinFlight=20,HeliType=5,BattRsv=27,
  BattVoice=1,RxPackMin="6.60",RxPackMax="8.40",MotorSw=99,CountSrc=2,FuelCheck=1}
local capture=Store.capture(values)
eq("capture copies known settings",capture.BattVoice,1)
eq("capture does not retain removed key",capture.TxBatt,nil)
eq("canonical flight duration retained",capture.MinFlight,20)
eq("canonical voltage retained",capture.RxPackMin,"6.60")
eq("off fuel index retained",capture.FuelCheck,1)
eq("input not mutated",values.TxBatt,2)
eq("internal source default",Store.capture({}).MotorSw,99)
eq("partial capture fills fuel default",Store.capture({}).FuelCheck,25)
local independent=Store.defaults(); independent.BattRsv=44
eq("defaults are a fresh copy",Store.defaults().BattRsv,20)
eq("retired OMP choice becomes automatic",Store.capture({HeliType=3}).HeliType,5)
eq("fractional OMP choice is not normalized",tostring(Store.capture({HeliType=3.5}).HeliType),"3.5")
eq("saved Rotorflight Auto identity retained",Store.capture({HeliType=4}).HeliType,4)

local first=Store.make("model01.yml","KSE4",capture)
local old=assert(Store.serialize(first))
local parsed=assert(Store.parse(old))
eq("canonical record roundtrip",Store.serialize(parsed),old)
eq("schema roundtrip model filename",parsed.model,"model01.yml")
eq("schema roundtrip canonical voltage",parsed.values.RxPackMin,"6.60")
local retired=Store.make("omp.yml","KSE4",capture)
retired.values.HeliType=3
local retiredText=assert(Store.serialize(retired))
local loadedRetired=assert(Store.parse(retiredText))
eq("saved manual OMP opens as automatic",Store.effective(loadedRetired,"KSE4").HeliType,5)
eq("opening old menu record leaves it unchanged",Store.serialize(loadedRetired),retiredText)
local replaced=Store.make("omp.yml","KSE4",Store.effective(loadedRetired,"KSE4"),loadedRetired)
eq("explicit save writes automatic OMP ID",replaced.values.HeliType,5)
eq("uninitialized variant theme remains absent",parsed.themes.KSE5,nil)
local other=Store.effective(parsed,"KSE5")
eq("functional settings shared",other.BattRsv,27)
eq("counter preference survives OMP mode",other.CountSrc,2)
eq("second variant initially uses canonical first theme",other.Theme,1)
other.Theme=18; other.BattRsv=28
local both=Store.make("model01.yml","KSE5",other,parsed)
eq("save other variant preserves first theme",both.themes.KSE4,4)
eq("save other variant records separate theme",both.themes.KSE5,18)
eq("source record remains immutable",parsed.values.BattRsv,27)
eq("shared setting read by first variant",Store.effective(both,"KSE4").BattRsv,28)
eq("first variant keeps own theme",Store.effective(both,"KSE4").Theme,4)
local nextRecord=Store.make("model01.yml","KSE4",capture,both)
nextRecord.values.BattRsv=31
local updated=assert(Store.serialize(nextRecord))

for _,bad in ipairs({"","return {arbitrary=true}",string.sub(old,1,#old-1),old.."x",
                     string.gsub(old,"END=.","END=Z",1),string.rep("x",Store.maxBytes+1)}) do
  rejected("damaged input "..#bad,bad)
end
rejected("non-string input",{})
local schemaCases={
  {"old schema version","KSE_SETTINGS=2","KSE_SETTINGS=1"},
  {"future schema version","KSE_SETTINGS=2","KSE_SETTINGS=3"},
  {"duplicate key","BattRsv=27","BattRsv=27\nBattRsv=28"},
  {"unknown key","BattRsv=27","BattRsv=27\nUnknown=1"},
  {"missing required field","BattRsv=27\n",""},
  {"fraction","BattRsv=27","BattRsv=27.5"},
  {"overflow","BattRsv=27","BattRsv=2147483648"},
  {"negative reserve","BattRsv=27","BattRsv=-1"},
  {"out of range source","MotorSw=99","MotorSw=32768"},
  {"bad hex text","RxPackMin=362E3630","RxPackMin=XX"},
  {"odd hex text","RxPackMin=362E3630","RxPackMin=3"},
  {"control text","RxPackMin=362E3630","RxPackMin=00"},
  {"legacy tenths rejected","RxPackMin=362E3630","RxPackMin=3636"},
  {"legacy hundredths rejected","RxPackMin=362E3630","RxPackMin=363630"},
  {"locale voltage rejected","RxPackMin=362E3630","RxPackMin=362C3630"},
  {"long text","RxPackMin=362E3630","RxPackMin="..string.rep("31",21)},
  {"legacy signed duration rejected","MinFlight=20","MinFlight=-20"},
  {"legacy zero counter rejected","CountSrc=2","CountSrc=0"},
  {"legacy zero fuel rejected","FuelCheck=1","FuelCheck=0"},
  {"missing fuel rejected","FuelCheck=1\n",""},
  {"removed fallback key rejected","BattRsv=27","BattRsv=27\nTxBatt=1"},
  {"legacy zero theme rejected","theme.KSE4=4","theme.KSE4=0"},
  {"theme fraction","theme.KSE4=4","theme.KSE4=4.5"},
  {"theme range","theme.KSE4=4","theme.KSE4=23"},
  {"unknown theme variant","theme.KSE4=4","theme.KSE6=4"},
  {"unsafe model path","model=6D6F64656C30312E796D6C","model=2E2E2F78"},
}
for _,case in ipairs(schemaCases) do rejected(case[1],modify(old,case[2],case[3])) end
for _,value in ipairs({-1,51,27.5,0/0,math.huge}) do
  local bad=Store.make("model01.yml","KSE4",capture)
  bad.values.BattRsv=value
  eq("serializer rejects bad number "..tostring(value),Store.serialize(bad),nil)
end

fs.reset()
local state=Store.open("model01.yml")
local path=state.path
local prototypePath=Store.root.."/model-model01.yml.kse"
local prototype=modify(modify(old,"KSE_SETTINGS=2","KSE_SETTINGS=1"),
                       "BattRsv=27","BattRsv=27\nTxBatt=1")
fs.files[prototypePath]=prototype
fs.files[prototypePath..".bak"]=prototype
fs.files[prototypePath..".tmp"]=prototype
state=Store.open("model01.yml")
eq("first use has no adopted settings",state.record,nil)
eq("versioned filename namespace",string.find(path,"/v2%-model%-")~=nil,true)
eq("old prototype main remains untouched",fs.files[prototypePath],prototype)
eq("first use ready for explicit save",state.writable,true)
eq("first use does not create folders or files",mutations(),0)
local job=assert(Store.startSave(state,first))
eq("starting save does not write",mutations(),0)
eq("starting save does not adopt settings",state.record,nil)
local phase=1
while true do
  local status,err=Store.step(job)
  assert(status~="error",err)
  if status=="done" then break end
  eq("pending stage does not apply "..phase,state.record,nil)
  phase=phase+1; assert(phase<12,"first save did not complete")
end
eq("save creates settings root",fs.directories[Store.root],true)
eq("first explicit save adopts settings",state.record.values.BattRsv,27)
eq("first save main contents",fs.files[path],old)
eq("new save never overwrites prototype main",fs.files[prototypePath],prototype)
eq("new save never overwrites prototype backup",fs.files[prototypePath..".bak"],prototype)
eq("new save never overwrites prototype temporary",fs.files[prototypePath..".tmp"],prototype)
eq("reboot reloads saved record",Store.open("model01.yml").record.values.BattRsv,27)
eq("completed job idempotent",Store.step(job),"done")
eq("save updated settings",save(state,nextRecord),"done")
eq("save preserves previous complete backup",fs.files[path..".bak"],old)
eq("save publishes updated record",state.record.values.BattRsv,31)
eq("save writes canonical main",fs.files[path],updated)
for _,call in ipairs(fs.calls) do eq("no direct main write "..call,call=="openw:"..path,false) end

state=setup(old)
local candidate=Store.make("model01.yml","KSE4",capture)
candidate.values.BattRsv=30
job=assert(Store.startSave(state,candidate)); candidate.values.BattRsv=40
eq("save owns immutable snapshot",complete(job),"done")
eq("later draft mutations cannot change saved values",state.record.values.BattRsv,30)
local unchanged=state.record
job=assert(Store.startSave(state,state.record)); fs.calls={}
eq("unchanged save succeeds",complete(job),"done")
eq("unchanged save avoids media writes",mutations(),0)

state=setup(nil,old,updated)
eq("backup preferred over unconfirmed temp",state.source,"backup")
eq("backup recovery is writable",state.writable,true)
eq("backup load performs no mutation",mutations(),0)
eq("backup recovery explicit save",save(state,nextRecord),"done")
eq("backup recovery retains confirmed backup",fs.files[path..".bak"],old)
eq("backup recovery publishes new main",fs.files[path],updated)
state=setup(nil,nil,updated)
eq("temporary only remains unadopted",state.record,nil)
eq("temporary only cannot overwrite",state.writable,false)
eq("temporary only visible error",type(state.error),"string")
eq("temporary only save rejected",Store.startSave(state,nextRecord),nil)
eq("temporary candidate preserved",fs.files[path..".tmp"],updated)
for _,bad in ipairs({"", "not settings", string.rep("x",Store.maxBytes+1)}) do
  state=setup(bad,old)
  eq("invalid main fallback displays backup "..#bad,state.record.values.BattRsv,27)
  eq("invalid main read-only "..#bad,state.writable,false)
  eq("invalid main cannot save "..#bad,Store.startSave(state,nextRecord),nil)
  eq("invalid main preserved "..#bad,fs.files[path],bad)
end
local wrong=Store.make("different.yml","KSE4",capture)
state=setup(Store.serialize(wrong),old)
eq("model mismatch does not adopt foreign settings",state.record.model,"model01.yml")
eq("model mismatch read-only",state.writable,false)
eq("model mismatch cannot save",Store.startSave(state,nextRecord),nil)
state=setup(old)
eq("foreign destination save refused",Store.startSave(state,wrong),nil)
for _,name in ipairs({"", ".", "..", "../model.yml", "a/b.yml", "a\\b.yml", "a\n", string.rep("a",65)}) do
  eq("unsafe model identity rejected "..#name,Store.open(name).writable,false)
end
eq("display punctuation safely encodes path",string.find(Store.open("Model A.yml").path," ",1,true),nil)
eq("different filenames have different settings paths",Store.open("a.yml").path==Store.open("b.yml").path,false)

for _,fault in ipairs({"empty","short","throw"}) do
  state=setup(old); fs.faults["read:"..path]=fault
  local failed=Store.open("model01.yml")
  eq("read failure read-only "..fault,failed.writable,false)
  eq("read failure no partial record "..fault,failed.record,nil)
end
for _,fault in ipairs({"nil","short","silent-short","throw"}) do
  state=setup(old); fs.faults["write:"..path..".tmp"]=fault
  eq("write failure "..fault,save(state,nextRecord),"error")
  eq("write failure preserves main "..fault,fs.files[path],old)
  eq("write failure retains live record "..fault,state.record.values.BattRsv,27)
end
for _,fault in ipairs({"empty","short","throw"}) do
  state=setup(old); fs.faults["read:"..path..".tmp"]=fault
  eq("temp readback failure "..fault,save(state,nextRecord),"error")
  eq("temp readback preserves main "..fault,fs.files[path],old)
end
for _,fault in ipairs({"lost","throw"}) do
  state=setup(old); fs.faults["close:"..path..".tmp"]=fault
  eq("close failure detected "..fault,save(state,nextRecord),"error")
  eq("close failure preserves main "..fault,fs.files[path],old)
end
for _,operation in ipairs({"del:"..path..".bak","rename:"..path,"rename:"..path..".tmp"}) do
  for _,fault in ipairs({1,true,false,"throw"}) do
    state=setup(old,old); fs.faults[operation]=fault
    eq("strict filesystem result "..operation.." "..tostring(fault),save(state,nextRecord),"error")
    eq("failed save keeps active settings "..operation,state.record.values.BattRsv,27)
    eq("failed save retains confirmed copy "..operation,
       fs.files[path]==old or fs.files[path..".bak"]==old,true)
  end
end
fs.reset(); state=Store.open("model01.yml"); fs.online=false
eq("missing media save fails",save(state,nextRecord),"error")
eq("missing media no settings adoption",state.record,nil)
for _,fault in ipairs({1,true,false,"throw"}) do
  fs.reset(); state=Store.open("model01.yml"); fs.faults["mkdir:/KSE"]=fault
  eq("directory creation failure "..tostring(fault),save(state,nextRecord),"error")
  eq("directory failure no file created "..tostring(fault),fs.files[path],nil)
end

-- Cut power after each completed pending stage, then reconstruct state from
-- disk only. No in-memory draft may become implicitly adopted by an old state.
for stop=1,4 do
  state=setup(old); job=assert(Store.startSave(state,nextRecord))
  for _=1,stop do eq("interruption pending stage "..stop,Store.step(job),"pending") end
  eq("interrupted job keeps previous live settings "..stop,state.record.values.BattRsv,27)
  local recovered=Store.open("model01.yml")
  eq("interruption retains a complete saved record "..stop,recovered.record~=nil,true)
  eq("interruption data is whole old or new snapshot "..stop,
     recovered.baseText==old or recovered.baseText==updated,true)
  eq("interruption restart can explicitly save "..stop,save(recovered,nextRecord),"done")
  eq("interruption resumed main is complete "..stop,fs.files[path],updated)
end
state=setup(old); fs.files[path]=updated
eq("external change before save refused",save(state,first),"error")
eq("external change before save preserved",fs.files[path],updated)
state=setup(nil,old); fs.files[path..".bak"]=updated
eq("external backup change refused",save(state,first),"error")
eq("external backup change preserved",fs.files[path..".bak"],updated)
for stop=1,3 do
  state=setup(old); job=assert(Store.startSave(state,nextRecord))
  for _=1,stop do eq("stale save first stages "..stop,Store.step(job),"pending") end
  local foreign=Store.make("model01.yml","KSE4",capture)
  foreign.values.BattRsv=48
  local foreignText=assert(Store.serialize(foreign))
  fs.files[path]=foreignText
  eq("external main change during save refused "..stop,complete(job),"error")
  eq("external main change during save preserved "..stop,fs.files[path],foreignText)
  eq("stale staged save keeps active settings "..stop,state.record.values.BattRsv,27)
end
state=setup(old); job=assert(Store.startSave(state,nextRecord))
for _=1,4 do eq("promoted readback setup",Store.step(job),"pending") end
fs.faults["read:"..path]="empty"
eq("promoted readback failure is reported",complete(job),"error")
eq("promoted readback failure keeps prior live settings",state.record.values.BattRsv,27)
eq("promoted readback failure retains confirmed backup",fs.files[path..".bak"],old)
fs.faults={}; state=Store.open("model01.yml")
eq("readback recovery uses complete promoted file",state.record.values.BattRsv,31)

-- Separate transfer record: export only the saved snapshot, then rebind its
-- validated fields to the destination through make() and explicit Save.
state=setup(old)
local exportJob=assert(Store.startExport(state))
eq("export job does not immediately write",mutations(),0)
eq("export saved snapshot",complete(exportJob),"done")
local exportPath=Store.exports.."/"..state.filename
eq("export equals saved snapshot",fs.files[exportPath],old)
local imported=assert(Store.readExport(state.filename))
eq("export preserves source identity for review",imported.model,"model01.yml")
local destination=Store.open("model02.yml")
local newValues=Store.effective(imported,"KSE5")
local rebound=Store.make("model02.yml","KSE5",newValues,imported)
eq("import draft rebound to destination",rebound.model,"model02.yml")
eq("import retains other dashboard theme",rebound.themes.KSE4,4)
eq("import does not write source",fs.files[path],old)
eq("import does not write destination before save",fs.files[destination.path],nil)
eq("import explicit destination save",save(destination,rebound),"done")
eq("import destination receives shared values",destination.record.values.BattRsv,27)
eq("import leaves original saved record untouched",fs.files[path],old)
for _,filename in ipairs({"../model01.yml.kse","/model01.yml.kse","model.lua","a\\b.kse",string.rep("a",151)..".kse"}) do
  eq("unsafe import filename rejected "..#filename,Store.readExport(filename),nil)
end
fs.files[exportPath]="return os.execute('bad')"
eq("import never executes malformed content",Store.readExport(state.filename),nil)
fs.files[exportPath]=prototype
eq("prototype companion requires reconfiguration",Store.readExport(state.filename),nil)
fs.reset(); state=Store.open("model01.yml")
eq("export unavailable before first save",Store.startExport(state),nil)

-- Measure allocation/work bursts per cooperative stage, including mock calls.
-- This excludes native SD latency and the rest of the widget callback.
state=setup(old)
local parseCost=measure(Store.parse,old)
local serializeCost=measure(Store.serialize,nextRecord)
local openCost=measure(Store.open,"model01.yml")
local startCost,measured=measure(Store.startSave,state,nextRecord)
local maxStep=0
while true do
  local cost,status,err=measure(Store.step,measured)
  if cost>maxStep then maxStep=cost end
  assert(status~="error",err)
  if status=="done" then break end
end
print("PROFILE|settings bytes="..#old.."|serialize="..serializeCost.."|parse="..parseCost.."|open="..openCost.."|start="..startCost.."|max-step="..maxStep)
assert(serializeCost<15000 and parseCost<15000 and openCost<15000 and startCost<15000 and maxStep<15000,
       "isolated settings stage exceeds project instruction margin")
local largest=Store.make(string.rep("m",64),"KSE4",capture,both)
largest.values.RxPackMin="4.00"; largest.values.RxPackMax="9.00"
largest.values.MotorSw=32767; largest.values.MinFlight=120; largest.values.FuelCheck=121
largest.themes.KSE4=22; largest.themes.KSE5=22
local largeText=assert(Store.serialize(largest))
state=setup(largeText,nil,nil,largest.model)
largest.values.BattRsv=50
serializeCost=measure(Store.serialize,largest)
parseCost=measure(Store.parse,largeText)
openCost=measure(Store.open,largest.model)
startCost,measured=measure(Store.startSave,state,largest)
maxStep=0
while true do
  local cost,status,err=measure(Store.step,measured)
  if cost>maxStep then maxStep=cost end
  assert(status~="error",err)
  if status=="done" then break end
end
print("PROFILE|largest-valid bytes="..#largeText.."|serialize="..serializeCost.."|parse="..parseCost.."|open="..openCost.."|start="..startCost.."|max-step="..maxStep)
assert(serializeCost<15000 and parseCost<15000 and openCost<15000 and startCost<15000 and maxStep<15000,
       "largest valid settings stage exceeds project instruction margin")
local boundary=signed(string.rep("x",Store.maxBytes-14).."\n")
eq("malformed parser boundary fixture",#boundary,Store.maxBytes)
local boundaryCost,boundaryRecord=measure(Store.parse,boundary)
eq("limit-sized malformed record rejected",boundaryRecord,nil)
print("PROFILE|invalid-boundary bytes="..#boundary.."|parse="..boundaryCost)
print("PASS|complete")
