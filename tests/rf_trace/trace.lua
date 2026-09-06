-- Structural characterization only: these traces include known unsafe baseline sends.
local tick=1000
getTime=function()return tick end
lcd={RGB=function(r,g,b)return r*65536+g*256+b end}
LCD_W=800;LCD_H=480
model={getInfo=function()return{name="MSP Probe"}end,getTimer=function()return{value=0,start=0}end}
getFieldInfo=function(name)if name=="ARM"then return{id=77,name=name}end end
getValue=function()return 0 end
getSourceValue=function(id)if id==77 then return 1,true,true end end
getRSSI=function()return 100 end
io={open=function()return nil end,close=function()end}
bit32={bor=function(a,b)return a|b end,band=function(a,b)return a&b end,lshift=function(a,b)return a<<b end,rshift=function(a,b)return a>>b end}
local function setup(n,mode,counter)
 tick=1000
 local sent={};local reply
 rf2={apiVersion=12.09,rfToolApiVersion=1.0,clock=function()return tick/100 end,registerWidget=function()end,widget={state="armed",background=function()end},call=function(fn,...)return fn(...)end}
 rf2.executeScript=function(name)
  assert(name=='MSP/common')
  return function(cmd,payload)
   sent[#sent+1]={command=cmd,tick=tick,state=rf2.widget.state};reply=cmd
  end,function()end,function()
   local cmd=reply;reply=nil
   if not cmd then return nil end
   local buf={};for i=1,32 do buf[i]=0 end
   if cmd==175 then buf[1]=1 end
   return cmd,buf,nil
  end,function()reply=nil end
 end
 rf2.mspQueue=dofile(upstreamDir .. '/mspQueue.lua')
 rf2.mspHelper=dofile(upstreamDir .. '/mspHelper.lua')
 local status=dofile(upstreamDir .. '/mspStatus.lua')
 local stats=dofile(upstreamDir .. '/mspFlightStats.lua')
 rf2.useApi=function(name)if name=='mspStatus'then return status elseif name=='mspFlightStats'then return stats end end
 local api=dofile(dashboardDir .. '/KSE'..n..'.lua');local a=api.audit
 a.OPT.heliType=mode;a.OPT.flightCounter=counter
 local w={profileRfState='armed',profileRfProviderRef=rf2,profileRfToolRegistered=true}
 return a,w,sent
end
local function trace(case, sent)
 for _, message in ipairs(sent) do
  print("TRACE|" .. case .. "|" .. message.command .. "|" .. message.tick .. "|" .. message.state)
 end
 print("TRACE|" .. case .. "|count|" .. #sent)
end
for n=4,5 do
 for mode=1,2 do
  for counter=1,2 do
   local a,w,sent=setup(n,mode,counter)
   for t=1000,1500,10 do tick=t;a.profiles.service(w,false,nil,nil)end
   trace('KSE'..n..'/armed/'..mode..'/'..counter, sent)
  end
 end
 -- Receive-only OMP + local counter does not initiate RF traffic.
 local a,w,sent=setup(n,3,1)
 for t=1000,1500,10 do tick=t;a.profiles.service(w,false,nil,nil)end
 assert(#sent==0,'OMP local counter should not send MSP')
 trace('KSE'..n..'/omp-local', sent)
 -- Queue profile transaction while disarmed; then arm before its first send.
 a,w,sent=setup(n,1,1)
 w.profileRfState='disarmed';rf2.widget.state='disarmed'
 assert(a.profiles.begin(w,'select',2))
 w.profileRfState='armed';rf2.widget.state='armed'
 for t=1010,1030,10 do tick=t;a.profiles.service(w,false,nil,nil)end
 trace('KSE'..n..'/queued-select-then-arm', sent)
 -- A queued stats read is sent before the arm cancellation phase runs.
 a,w,sent=setup(n,2,2)
 local msg={command=14,processReply=function()end}
 rf2.mspQueue:add(msg)
 w.profileBusy=true;w.profileOperation={kind='flightStats',token=1,startedAt=tick,queue=rf2.mspQueue,messages={msg},model='__default__'}
 a.FC.pending=true;a.FC.state='disarmed';a.FC.armState=false;a.FC.model='__default__'
 a.profiles.service(w,false,nil,nil)
 trace('KSE'..n..'/queued-stats-then-arm', sent)
end
