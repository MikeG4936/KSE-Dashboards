#!/usr/bin/env python3
"""Measure isolated storage paths in the pinned host, including mock overhead."""
import argparse
from pathlib import Path
import subprocess
import tempfile

from integration import instrument

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    args = parser.parse_args()
    source = (HERE / 'mock.lua').read_text() + '\nStorage=(function()\n'
    source += (ROOT / 'src/shared/count_storage.lua').read_text() + '\nend)()\n'
    source += '''
local values={}
for i=1,200 do values["Model "..i]=i end
for _,full in ipairs({false,true}) do
 if full then
  local text=Storage.serialize(values)
  values[string.rep("x",32768-#text-3)]=values["Model 1"]
  values["Model 1"]=nil
  -- Fill exactly to the source byte limit without increasing entry count.
  text=Storage.serialize(values)
  local key="Model 2"
  local count=values[key];values[key]=nil
  values[key..string.rep("y",32768-#text)]=count
 end
 local data=assert(Storage.serialize(values))
 fs.files={["/flights-count.csv"]=data};fs.calls={};fs.faults={}
 local state=Storage.new("/flights-count.csv")
 local loadCost=measure(function()assert(Storage.load(state))end)
 Storage.markDirty(state,0)
 -- Force ordinary replacement, not the idempotent no-op path, without growth.
 state.cache["Model 200"]=199
 local saveCost=measure(function()Storage.service(state,0)end)
 assert(not state.dirty,state.error)
 print("PROFILE|"..#data.." bytes|load="..loadCost.."|save="..saveCost)
 assert(loadCost<15000 and saveCost<15000,"isolated storage path exceeds project instruction margin")
end
'''
    with tempfile.TemporaryDirectory(prefix='kse-storage-profile-') as tmp:
        path = Path(tmp) / 'profile.lua'
        path.write_text(source)
        subprocess.run([str(args.runner.resolve()), str(path)], check=True, timeout=60)

    # Full local-counter callback paths, with RF and renderer entry points
    # stubbed exactly as documented by the integration fixtures.
    body = """
local t,m=__integration,__mock
local values={Fixture=7};for i=1,199 do values["M"..i]=i end
local text=Storage.serialize(values)
values[string.rep("x",32768-#text)]=values.M1;values.M1=nil
text=Storage.serialize(values)
local count=values.M2;values.M2=nil;values["M2"..string.rep("y",32768-#text)]=count
text=assert(Storage.serialize(values));assert(#text==32768)
fs.files={["/flights-count.csv"]=text}
local opts={CountSrc=1,HeliType=3,MinFlight=30,MotorSw=99}
local init,w=measure(t.create,{x=0,y=0,w=800,h=480},opts)
m.now=0;m.timer={start=0,value=0};t.background(w)
m.now=10;m.timer={start=0,value=30};t.background(w)
m.now=20
local save=measure(t.background,w)
assert(not t.state.dirty,t.state.error)
print("PROFILE|callbacks|create="..init.."|background-save="..save)
assert(init<15000 and save<15000,"mocked local-counter callback exceeds instruction margin")
"""
    for variant in ('KSE4', 'KSE5'):
        script = instrument((ROOT / variant / 'main.lua').read_text(), 'qualified')
        script = script.rsplit('__runIntegration()', 1)[0] + body
        with tempfile.TemporaryDirectory(prefix='kse-counter-profile-') as tmp:
            path = Path(tmp) / (variant + '.lua')
            path.write_text(script)
            subprocess.run([str(args.runner.resolve()), str(path)], check=True, timeout=60)


if __name__ == '__main__':
    main()
