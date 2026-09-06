-- Separate function scope keeps test locals out of the production main chunk.
__runContracts=function()
  local t,m=__test,__mock
  local function check(label,actual,expected)
    if type(expected)=="number" then
      assert(type(actual)=="number" and math.abs(actual-expected)<0.001,
             label..": expected "..tostring(expected)..", got "..tostring(actual))
    else
      assert(actual==expected,label..": expected "..tostring(expected)..", got "..tostring(actual))
    end
    local value=type(actual)=="number" and string.format("%.4f",actual) or tostring(actual)
    print("TRACE|"..label.."|"..value)
  end
  local function frame(now)
    m.now=now or (m.now+10)
    t.clearFrameCache()
  end
  local function reset()
    m.values={}; m.events={}; m.fieldCalls={}
    t.resetSessionEvidence(); t.resetSessionStats(); frame(0)
    t.applyOptions({HeliType=1,BattRsv=20,CountSrc=1,MinFlight=30,
                    RxPackMin="6.60",RxPackMax="8.40",MotorSw=99})
  end
  local function source(name,value,current,fresh)
    m.values[name]={value=value,current=current,fresh=fresh}
    -- Discovery changes become visible after the bounded metadata-cache TTL.
    frame(m.now+100)
  end
  local function alert(now,pct,voice,data)
    frame(now); t.updateBatteryAlertState(pct,data~=false,voice,"fc")
  end
  reset()
  check("missing current",t.getCurr(),0)
  check("missing current validity",t.D.currentValid,false)
  source("Curr",0)
  check("live zero current",t.getCurr(),0)
  check("live zero current validity",t.D.currentValid,true)
  source("Curr",{value=41.7})
  check("source value wrapper",t.getCurr(),41.7)
  source("Curr",2001)
  check("out of range current",t.getCurr(),0)
  check("out of range current validity",t.D.currentValid,false)
  source("Curr",32,false)
  check("noncurrent rejected",t.getCurr(),0)
  check("noncurrent validity",t.D.currentValid,false)
  source("Curr",32)
  m.values.Curr.throw=true
  check("source exception rejected",t.getCurr(),0)
  source("Curr",32)
  check("source recovery",t.getCurr(),32)
  m.values.Curr.value=44
  check("one sample per frame",t.getCurr(),32)
  frame()
  check("next frame refresh",t.getCurr(),44)
  -- A noncurrent cached ID is rejected immediately and re-resolves at TTL.
  reset()
  m.values.Curr={id=301}; m.values[301]={value=12}
  check("numeric sensor ID lookup",t.getCurr(),12)
  m.values[301].current=false; frame()
  check("expired ID invalid",t.getCurr(),0)
  m.values.Curr={id=302}; m.values[302]={value=13}; frame(100)
  check("changed sensor ID recovery",t.getCurr(),13)
  source("Vcel",3.97)
  check("Rotorflight average cell scalar",t.getCellVoltage(),3.97)
  source("Bat%",0)
  check("zero battery sensor valid",t.getBatPct(),0)
  check("zero battery validity",t.D.batteryPercentValid,true)
  source("Bat%",101)
  check("invalid battery sensor",t.getBatPct(),false)
  source("Gov",4)
  check("governor active",t.getGovState(),"ACTIVE")
  source("Gov",99)
  check("unknown governor display",t.getGovState(),"--")
  check("unknown governor invalid",t.D.govCurrentInvalid,true)
  source("Hspd",0)
  check("stopped rotor zero",t.getHeadspeed(),0)
  check("stopped rotor valid",t.D.rpmValid,true)
  source("BAT#",6)
  check("one based battery profile",t.getBattProfile(),6)
  source("BAT#",0)
  check("zero profile rejected",t.getBattProfile(),nil)
  source("tx-voltage",8000)
  check("transmitter millivolts",t.getTxVolt(),8)
  check("LiPo empty",t.txPctFromVolts(7,false),0)
  check("LiIon empty",t.txPctFromVolts(6.2,true),0)
  check("transmitter full",t.txPctFromVolts(8.4,true),100)
  check("RSSI conversion",t.signalPercent(-80),50)

  -- Assert selector authority independently of UI smoothing and source cache.
  local p,valid,kind=t.selectFlightBatteryPercent(1,72,true,95,true,true)
  check("Smart Fuel priority",p,72); check("Smart Fuel source",kind,"fc")
  p,valid,kind=t.selectFlightBatteryPercent(1,72,true,nil,false,false)
  check("positive percent independent",valid,true)
  p,valid,kind=t.selectFlightBatteryPercent(1,0,true,nil,false,false)
  check("USB only is no data",valid,false)
  p,valid,kind=t.selectFlightBatteryPercent(1,0,true,nil,false,true)
  check("powered empty pack",p,0); check("powered empty pack valid",valid,true)
  p,valid,kind=t.selectFlightBatteryPercent(1,false,false,35,true,true)
  check("voltage fallback",p,35); check("voltage fallback source",kind,"voltage")
  p,valid,kind=t.selectFlightBatteryPercent(2,72,true,95,true,true)
  check("Nitro no flight percentage",valid,false)
  p,valid,kind=t.selectFlightBatteryPercent(3,72,true,nil,false,false)
  check("OMP requires pack contract",valid,false)
  check("reserve maps usable range",t.calculateAdjustedPercent(60,20),50)
  check("reserve floor",t.calculateAdjustedPercent(10,20),0)
  check("reserve full",t.calculateAdjustedPercent(100,20),100)
  reset(); source("Bat%",72); t.tick(m.now)
  check("Smart Fuel display",t.A.displayPercent,65)
  source("Bat%",60); t.tick(m.now)
  check("Smart Fuel display no second filter",t.A.displayPercent,50)
  reset(); t.OPT.heliType=3; m.modelName="My m1 heli"
  source("RxBt",8.6)
  check("OMP M1 cells",t.getCellCount(),2)
  check("OMP M1 chemistry",t.D.isLiHV,true)
  check("OMP M1 cell voltage",t.getCellVoltage(),4.3)
  m.modelName="My M2 heli"; frame()
  check("OMP M2 cells",t.getCellCount(),3)
  m.modelName="Unidentified OMP"; frame()
  check("unidentified OMP cells",t.getCellCount(),0)
  m.modelName="Fixture"

  reset(); t.A.linkAvailable=true
  alert(0,60,true); alert(10,50,true)
  check("50 percent voice",m.events[1],"voice:50")
  alert(20,40,true)
  check("voice cooldown",#m.events,1)
  alert(230,40,true)
  check("40 percent voice",m.events[2],"voice:40")
  alert(450,15,true)
  check("skipped threshold chooses lowest",m.events[3],"voice:20")
  alert(670,10,true); t.updateBatteryHapticTick()
  check("10 percent voice",m.events[4],"voice:10")
  check("low haptic first burst",m.events[5],"haptic:15")
  check("haptic immediate priority",m.hapticFlags,16)
  frame(769); t.updateBatteryHapticTick()
  check("haptic spacing",#m.events,5)
  frame(770); t.updateBatteryHapticTick()
  check("low haptic second burst",m.events[6],"haptic:15")
  frame(1000); t.updateBatteryHapticTick()
  check("only two low bursts",#m.events,6)
  alert(1010,0,true); t.updateBatteryHapticTick()
  check("zero percent voice",m.events[7],"voice:0")
  check("zero haptic starts",m.events[8],"haptic:15")
  check("zero warning latched",t.A.battZeroReached,true)
  t.voice.available[t.voice.deadPath]=true
  t.A.motorSwitchPosition=-1
  frame(1260); t.voice.updateDead(true)
  check("dead voice after initial delay",m.events[9],"file:dead.wav")
  t.A.motorSwitchPosition=1; frame(1480); t.voice.updateDead(true)
  check("switch acknowledges repeat",t.A.flightDeadVoiceAcknowledged,true)
  check("acknowledged voice stopped",#m.events,9)
  alert(1600,80,true); alert(1700,80,true)
  check("new FC battery rearms",t.A.battZeroReached,false)
  alert(1920,50,true)
  check("new battery voice",m.events[10],"voice:50")
  reset(); t.A.linkAvailable=true
  alert(0,60,false); alert(10,40,false); alert(250,40,true)
  check("enabling voice no backlog",#m.events,0)
  alert(500,30,true,false)
  check("missing sample no voice",#m.events,0)
  alert(510,30,true)
  check("voice after valid recovery",m.events[1],"voice:30")
  reset(); t.A.linkAvailable=true; t.A.battConnectionZeroPending=true
  alert(0,0,false); alert(299,0,false)
  check("startup zero waits for confirmation",t.A.battAlert0HapticPlayed,false)
  alert(300,0,false,false)
  check("startup zero gap clears evidence",t.A.battConnectionZeroSince,nil)
  alert(310,0,false); alert(609,0,false)
  check("startup zero new confirmation window",t.A.battAlert0HapticPlayed,false)
  alert(610,0,false)
  check("startup zero confirmed haptic",t.A.battAlert0HapticPlayed,true)

  reset(); t.A.linkAvailable=true
  frame(0); t.updateEscBecAlerts(111,true,4.7,true)
  frame(49); t.updateEscBecAlerts(111,true,4.7,true)
  check("ESC BEC confirmation delay",#m.events,0)
  frame(50); t.updateEscBecAlerts(111,true,4.7,true)
  check("ESC BEC confirmed",#m.events,2)
  frame(150); t.updateEscBecAlerts(105,true,4.9,true)
  check("ESC BEC hysteresis",#m.events,2)
  frame(200); t.updateEscBecAlerts(99,true,5.1,true)
  check("ESC rearmed",t.A.escTempAlertPlayed,false)
  check("BEC rearmed",t.A.becAlertPlayed,false)
  frame(250); t.updateEscBecAlerts(111,true,4.7,true)
  frame(280); t.updateEscBecAlerts(111,false,4.7,false)
  frame(300); t.updateEscBecAlerts(111,true,4.7,true)
  frame(349); t.updateEscBecAlerts(111,true,4.7,true)
  check("invalid sample resets persistence",#m.events,2)
  frame(350); t.updateEscBecAlerts(111,true,4.7,true)
  check("alerts recur after rearm",#m.events,4)

  reset(); t.A.linkAvailable=true; t.A.motorSwitchPosition=-1
  frame(0); t.updateRxPackAlert(6.6)
  frame(199); t.updateRxPackAlert(6.6)
  check("Nitro qualification",#m.events,0)
  frame(200); t.updateRxPackAlert(6.6)
  check("Nitro sustained low",t.A.rxDeadVoiceLatched,true)
  check("Nitro low haptic",#m.events,1)
  t.A.motorSwitchPosition=1; frame(220); t.updateRxPackAlert(6.6)
  check("Nitro acknowledgement",t.A.rxDeadVoiceAcknowledged,true)
  check("Nitro acknowledgement stops haptic",#m.events,1)
  frame(230); t.updateRxPackAlert(7.0)
  check("Nitro recovered rearm",t.A.rxDeadVoiceLatched,false)

  reset()
  local opts={Theme=1,TxBatt=1,HeliType=1,BattRsv=20,CountSrc=1,MinFlight=30,
              RxPackMin="6.60",RxPackMax="8.40",MotorSw=99}
  local w=t.create({x=0,y=0,w=800,h=480},opts)
  local function count(start,value)
    m.timer={start=start,value=value}; frame(); t.tickFlightCount()
    return t.getFlightCount()
  end
  check("count initial",count(0,0),0)
  check("count before ascending threshold",count(0,29),0)
  check("count at ascending threshold",count(0,30),1)
  check("count only once per cycle",count(0,80),1)
  check("count reset rearms",count(0,0),1)
  check("count second ascending cycle",count(0,30),2)
  check("count countdown starts",count(120,120),2)
  check("count before countdown threshold",count(120,91),2)
  check("count at countdown threshold",count(120,90),3)
  check("count countdown overrun",count(120,-10),3)
  -- Simulate removing the old widget and opening its replacement after the
  -- ownership lease expires. Exercise the real foreground takeover path.
  frame(m.now+500)
  w=t.create({x=0,y=0,w=800,h=480},opts)
  t.refresh(w,nil,nil)
  check("attach over threshold no extra flight",count(120,80),3)
  check("attach then reset",count(120,120),3)
  check("attach next flight",count(120,90),4)
  check("malformed timer",t.timerElapsedSeconds({value="bad"}),nil)
  check("timer elapsed clamped",t.timerElapsedSeconds({start=120,value=130}),0)

  local names={"Theme","TxBatt","MinFlight","HeliType","BattRsv","BattVoice",
               "RxPackMin","RxPackMax","MotorSw","CountSrc"}
  check("persisted option count",#t.options,10)
  for i,name in ipairs(names) do check("option slot "..i,t.options[i][1],name) end
  check("default counter",t.options[10][3],2)
  t.applyOptions({MinFlight=-30,BattRsv=99,CountSrc=99,RxPackMin="66",RxPackMax="840"})
  check("legacy negative duration",t.config(),30)
  check("reserve clamped",t.OPT.reservePct,50)
  check("invalid counter defaults FC",t.OPT.flightCounter,2)
  check("legacy Rx tenths",t.OPT.rxPackMin,6.6)
  check("legacy Rx hundredths",t.OPT.rxPackMax,8.4)
  check("Rx settings validity",t.OPT.rxPackValid,true)
  t.applyOptions(opts)
  t.A.battZeroReached=true; t.A.rxDeadVoiceLatched=true; t.S.rpmMax=2300
  opts.Theme=2; t.update(w,opts)
  check("theme preserves flight warning",t.A.battZeroReached,true)
  check("theme preserves Nitro warning",t.A.rxDeadVoiceLatched,true)
  check("theme preserves session maximum",t.S.rpmMax,2300)
  opts.BattRsv=25; t.update(w,opts)
  check("reserve resets flight warning",t.A.battZeroReached,false)
  check("reserve preserves Nitro warning",t.A.rxDeadVoiceLatched,true)
  opts.RxPackMin="6.7"; t.update(w,opts)
  check("Rx option resets Nitro warning",t.A.rxDeadVoiceLatched,false)
  t.D.currentValid=true; t.A.linkAvailable=true
  opts.HeliType=2; t.update(w,opts)
  check("type resets sensor evidence",t.D.currentValid,false)
  check("type resets link evidence",t.A.linkAvailable,false)
  check("type resets session maximum",t.S.rpmMax,0)
  for i=1,#t.options[1][4] do
    opts.Theme=i; t.applyOptions(opts)
    local bg,accent,transparent=t.theme()
    assert(transparent==(__variant=="KSE4" and (i==3 or i==19)))
    -- Palette and theme slot traces compare to the same variant's baseline.
    print("THEME|"..i.."|"..t.options[1][4][i].."|"..tostring(bg).."|"..
          tostring(accent).."|"..tostring(transparent))
  end
  -- Generic metadata is cached for 100 ticks, including unsuccessful lookup.
  reset()
  m.values.Curr={id=601}; m.values[601]={value=12}
  check("metadata initial ID",t.get("Curr"),12)
  check("metadata first lookup",m.fieldCalls.Curr,1)
  m.values.Curr={id=602}; m.values[602]={value=24}
  frame(99)
  check("metadata positive TTL retains ID",t.get("Curr"),12)
  check("metadata positive TTL avoids lookup",m.fieldCalls.Curr,1)
  frame(100)
  check("metadata positive TTL rebinds ID",t.get("Curr"),24)
  check("metadata positive TTL lookup count",m.fieldCalls.Curr,2)
  frame(101)
  check("metadata missing source",t.get("AbsentTelemetry"),nil)
  m.values.AbsentTelemetry={id=603}; m.values[603]={value=8}
  frame(200)
  check("metadata negative TTL holds absence",t.get("AbsentTelemetry"),nil)
  check("metadata negative TTL avoids lookup",m.fieldCalls.AbsentTelemetry,1)
  frame(201)
  check("metadata negative TTL discovers source",t.get("AbsentTelemetry"),8)
  check("metadata negative TTL lookup count",m.fieldCalls.AbsentTelemetry,2)

  -- Safety/acknowledgement source names re-resolve even within one frame.
  for i,name in ipairs({"ARM","Gov","Hspd","RPM"}) do
    m.values[name]={id=610+i}; m.values[610+i]={value=4}
    check(name.." uncached initial ID",t.get(name),4)
    m.values[name]={id=620+i}; m.values[620+i]={value=5}
    check(name.." uncached changed ID",t.get(name),5)
    check(name.." metadata every call",m.fieldCalls[name],2)
  end

  reset()
  m.values.Curr={value=31,rawFlags=true,current=nil,fresh=true}
  local value,current,fresh=t.get("Curr")
  check("unspecified current value rejected",value,nil)
  check("unspecified current metadata rejected",current,false)
  m.values.Curr.current=1; frame()
  value,current,fresh=t.get("Curr")
  check("truthy nonboolean current rejected",value,nil)
  m.values.Curr.current=true; m.values.Curr.fresh=1; frame()
  value,current,fresh=t.get("Curr")
  check("truthy nonboolean freshness rejected",fresh,false)
  m.values.Curr.current=true; m.values.Curr.fresh=nil; frame()
  value,current,fresh=t.get("Curr")
  check("current sample survives absent freshness",value,31)
  check("absent freshness stays false",fresh,false)
  m.values.Curr.fresh=false; frame()
  value,current,fresh=t.get("Curr")
  check("stale current sample remains displayable",value,31)
  check("false freshness preserved",fresh,false)
  m.values.Curr.fresh=true; frame()
  value,current,fresh=t.get("Curr")
  check("explicit freshness preserved",fresh,true)
  local sourceValueApi=getSourceValue
  getSourceValue=nil; frame()
  value,current,fresh=t.get("Curr")
  check("legacy display value",value,31)
  check("legacy display current",current,true)
  check("legacy API cannot prove freshness",fresh,false)
  getSourceValue=sourceValueApi

  -- Reset must discard both cached IDs and cached absence, without waiting.
  reset()
  m.values.Curr={id=701}; m.values[701]={value=11}
  t.get("Curr"); t.get("NewAfterReset")
  m.values.Curr={id=702}; m.values[702]={value=22}
  m.values.NewAfterReset={value=33}
  t.resetSessionEvidence(); frame(1)
  check("session reset clears positive metadata",t.get("Curr"),22)
  check("session reset clears negative metadata",t.get("NewAfterReset"),33)
  t.get("NewAfterModel")
  m.values.Curr={id=703}; m.values[703]={value=44}
  m.values.NewAfterModel={value=55}
  m.modelName="Changed cache model"; frame(2); t.tickFlightCount()
  check("model reset clears positive metadata",t.get("Curr"),44)
  check("model reset clears negative metadata",t.get("NewAfterModel"),55)
  m.modelName="Fixture"

  -- Freshness limits stop acknowledgement only; stale values remain usable
  -- for display. Each scenario builds real movement/running/stop evidence.
  local function motorSample(now,position,rpm,rpmFresh,gov,govFresh)
    frame(now)
    m.values[t.OPT.heliType==3 and "RPM" or "Hspd"]={value=rpm,fresh=rpmFresh}
    m.values.Gov=gov~=nil and {value=gov,fresh=govFresh} or nil
    t.A.linkAvailable=true
    t.A.motorSourcePhysical=true; t.A.motorSourceReadable=true
    t.A.motorSwitchPosition=position
    local head=t.getHeadspeed()
    local mode=t.getGovernorMode()
    t.updateMotorAlertGate(now,mode,head)
    return head
  end
  for _,heli in ipairs({1,3}) do
    local label=heli==1 and "Electric RPM" or "OMP RPM"
    reset(); t.OPT.heliType=heli; t.OPT.battBarMode=0
    check(label.." stale display",motorSample(0,-1,2200,false,nil,false),2200)
    check(label.." stale display validity",t.D.rpmValid,true)
    check(label.." stale freshness",t.D.rpmFresh,false)
    motorSample(10,-1,2200,true,nil,false)
    motorSample(20,1,0,false,nil,false)
    motorSample(60,1,0,false,nil,false)
    check(label.." stale stop cannot pause",t.A.flightBatteryAlertsPaused,false)
    -- Start an independent fresh-evidence cycle after resetting stale state.
    t.resetSessionEvidence()
    motorSample(70,-1,2200,true,nil,false)
    motorSample(80,-1,2200,true,nil,false)
    motorSample(90,1,0,true,nil,false)
    motorSample(120,1,0,true,nil,false)
    check(label.." fresh stop pauses",t.A.flightBatteryAlertsPaused,true)
    motorSample(130,1,0,false,nil,false)
    check(label.." stale hold releases pause",t.A.flightBatteryAlertsPaused,false)
  end
  reset()
  motorSample(0,-1,nil,false,4,true)
  motorSample(10,1,nil,false,0,false)
  motorSample(40,1,nil,false,0,false)
  check("Gov stale stopped display",t.getGovernorMode(),0)
  check("Gov stale display validity",t.D.govValid,true)
  check("Gov stale freshness",t.D.govFresh,false)
  check("Gov stale stop cannot pause",t.A.flightBatteryAlertsPaused,false)
  t.resetSessionEvidence()
  motorSample(50,-1,nil,false,4,true)
  motorSample(60,-1,nil,false,4,true)
  motorSample(70,1,nil,false,0,true)
  motorSample(90,1,nil,false,0,true)
  check("Gov fresh stop pauses",t.A.flightBatteryAlertsPaused,true)
  motorSample(100,1,nil,false,0,false)
  check("Gov stale hold releases pause",t.A.flightBatteryAlertsPaused,false)

  -- Effective OMP counter choice must not rewrite the persisted preference.
  reset()
  local savedOptions={HeliType=3,CountSrc=2,BattRsv=20,MinFlight=20,
                      RxPackMin="6.60",RxPackMax="8.40",MotorSw=99}
  t.applyOptions(savedOptions)
  check("OMP effective local counter",t.OPT.flightCounter,t.FC.RADIO)
  check("OMP preserves saved FC preference",savedOptions.CountSrc,2)
  savedOptions.HeliType=1; t.applyOptions(savedOptions)
  check("Electric restores saved FC preference",t.OPT.flightCounter,t.FC.ROTORFLIGHT)
  savedOptions.HeliType=3; savedOptions.CountSrc=1; t.applyOptions(savedOptions)
  check("OMP selected local counter stays local",t.OPT.flightCounter,t.FC.RADIO)
  savedOptions.HeliType=1; t.applyOptions(savedOptions)
  check("Electric preserves saved local preference",t.OPT.flightCounter,t.FC.RADIO)

  t.applyOptions({HeliType=2,CountSrc=1,BattRsv=49,BattVoice=true,MinFlight=80,
                  RxPackMin="7.20",RxPackMax="8.80",MotorSw=123})
  t.applyOptions(nil)
  check("nil options resets helicopter",t.OPT.heliType,1)
  check("nil options resets battery mode",t.OPT.battBarMode,0)
  check("nil options resets counter",t.OPT.flightCounter,t.FC.ROTORFLIGHT)
  check("nil options resets reserve",t.OPT.reservePct,20)
  check("nil options resets battery voice",t.OPT.battVoice,false)
  check("nil options resets Rx minimum",t.OPT.rxPackMin,6.6)
  check("nil options resets Rx maximum",t.OPT.rxPackMax,8.4)
  check("nil options defaults Rx valid",t.OPT.rxPackValid,true)
  local defaultDuration,defaultMotor=t.config()
  check("nil options resets minimum duration",defaultDuration,20)
  check("nil options resets motor source",defaultMotor,99)
  check("profile whole lower valid",t.profileIndexValid(1),true)
  check("profile whole upper valid",t.profileIndexValid(6),true)
  check("fractional profile rejected on EdgeTX",t.profileIndexValid(1.5),false)
  check("profile zero rejected",t.profileIndexValid(0),false)
  check("profile overflow rejected",t.profileIndexValid(7),false)
  check("profile string rejected",t.profileIndexValid("1"),false)
  t.FC.status="INITIALIZING"
  check("initializing status is pending",t.flightStatusPending(),true)
  t.FC.status="NO REPLY"
  check("failure status is not pending",t.flightStatusPending(),false)
  check("complete",true,true)
end
__runContracts()
