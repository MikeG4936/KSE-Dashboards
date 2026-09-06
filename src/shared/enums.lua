local BATTERY_PROFILE_COUNT = 6
local GOV_STATES = {
  [0]="OFF",      [1]="IDLE",     [2]="SPOOLUP",  [3]="RECOVERY",
  [4]="ACTIVE",   [5]="THR-OFF",  [6]="LOST-HS",
  [7]="AUTOROT",  [8]="BAILOUT",  [9]="BYPASS",
}
-- Only explicit, recognized states participate in the motor-alert gate. An
-- unknown future enum must never be interpreted as motor-off.
local GOV_RUNNING_STATE = {
  [2]=true, -- SPOOLUP
  [3]=true, -- RECOVERY
  [4]=true, -- ACTIVE
  [8]=true, -- BAILOUT
  [9]=true, -- BYPASS
}
local GOV_STOP_STATE = {
  [0]=true, -- OFF
  [5]=true, -- THR-OFF / lost throttle
  [7]=true, -- AUTOROT
}
local GOV_PAUSE_HOLD_STATE = {
  [0]=true, -- OFF
  [1]=true, -- IDLE after a previously validated stop
  [5]=true, -- THR-OFF / lost throttle
  [7]=true, -- AUTOROT
}
