-- Public telemetry boundary shared by render/Auto-mode fixtures. Identification
-- still runs through real OMP lifecycle confirmation; no engine state is seeded.
UNIT_VOLTS=1; UNIT_RPMS=3
local baseFieldInfo=getFieldInfo
getFieldInfo=function(name)
  if name=="telem1" and __mock.ompSensors then return {id=300,name="telem1"} end
  return baseFieldInfo(name)
end
model.getSensor=function(index)
  if index<0 or index>=64 then return nil end
  return (__mock.ompSensors or {})[index] or {type=0,name="",unit=0,id=0,instance=0}
end
function __setOmpSources(cells,voltage)
  __mock.ompSensors={}
  local function sensor(index,name,value,id,unit)
    local source=300+3*index
    local item={id=source,value=value,current=true,fresh=true}
    __mock.ompSensors[index]={type=0,name=name,unit=unit,id=id,instance=0}
    __mock.values[name]=item
    __mock.values[source]=item
  end
  voltage=voltage or 3.8
  sensor(1,"RxBt",cells*voltage,0x08,UNIT_VOLTS)
  sensor(7,"Volt",voltage,0x80FE,UNIT_VOLTS)
  sensor(12,"RPM",0,0x0C,UNIT_RPMS)
end
