local function profilePointInBatteryTarget(wgt, touchState)
  if type(touchState) ~= "table" then return false end
  local x, y = tonumber(touchState.x), tonumber(touchState.y)
  local card = wgt.layout and wgt.layout.rings and wgt.layout.rings[1]
  return x and y and card
         and x >= card.x and x < card.x + card.w
         and y >= card.y and y < card.y + card.h
end
